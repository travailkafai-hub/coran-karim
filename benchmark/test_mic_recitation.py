"""
Test direct : tu recites au micro -> Whisper Small fine-tune (CPU) transcrit.
Detection automatique : demarre a ta voix, s'arrete quand tu te tais (1.5s).
GPU non utilise (CUDA_VISIBLE_DEVICES vide) -> Medium intact.

Usage : python test_mic_recitation.py [verse_key]
  verse_key optionnel (ex: 112:1) -> compare a la reference et corrige.
"""
import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""   # force CPU
import truststore; truststore.inject_into_ssl()
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
import sys, json, re, time, queue
import numpy as np, sounddevice as sd, torch
from transformers import WhisperProcessor, WhisperForConditionalGeneration

ROOT = os.path.dirname(os.path.abspath(__file__))
FT   = os.path.join(ROOT, "models", "whisper-small-ft")
SR   = 16000
MAX_S = 30.0
SILENCE_END_S = 1.5
START_TIMEOUT_S = 60.0

verse_key = sys.argv[1] if len(sys.argv) > 1 else None

# ── Reference (si demandee) ────────────────────────────────────────────────
ref_text = None
if verse_key:
    for src in ("data/manifest_full.jsonl", "data/train_full.jsonl"):
        p = os.path.join(ROOT, src)
        if os.path.exists(p):
            for l in open(p, encoding="utf-8"):
                o = json.loads(l)
                if o.get("key") == verse_key:
                    ref_text = o["text"]; break
        if ref_text: break

# ── Charge le modele AVANT d'enregistrer ───────────────────────────────────
print("Chargement du modele (CPU)...", flush=True)
proc = WhisperProcessor.from_pretrained(FT, language="arabic", task="transcribe")
model = WhisperForConditionalGeneration.from_pretrained(FT).to("cpu").eval()
try:
    model.generation_config.is_multilingual = True
    model.generation_config.forced_decoder_ids = proc.get_decoder_prompt_ids(
        language="arabic", task="transcribe")
    model.generation_config.suppress_tokens = []
except Exception:
    pass
print("Modele pret.", flush=True)

# ── Enregistrement avec VAD ────────────────────────────────────────────────
q = queue.Queue()
def cb(indata, frames, t, status):
    q.put(indata.copy())

print(">>> PARLE MAINTENANT (recite le verset) <<<", flush=True)
frames = []
started = False
silence_run = 0.0
t_start = time.time()
block = 0.05  # 50ms

with sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                    blocksize=int(SR*block), callback=cb):
    while True:
        try:
            data = q.get(timeout=1.0)
        except queue.Empty:
            if not started and time.time()-t_start > START_TIMEOUT_S:
                print("Timeout : aucune voix detectee.", flush=True); sys.exit(0)
            continue
        rms = float(np.sqrt(np.mean(data**2)))
        if rms > 0.012:        # seuil de voix
            started = True
            silence_run = 0.0
            frames.append(data)
        elif started:
            silence_run += block
            frames.append(data)
            if silence_run >= SILENCE_END_S:
                break
        if started and (len(frames)*block) > MAX_S:
            break
        if not started and time.time()-t_start > START_TIMEOUT_S:
            print("Timeout : aucune voix detectee.", flush=True); sys.exit(0)

audio = np.concatenate(frames, axis=0).flatten()
dur = len(audio)/SR

# ── Diagnostic audio + sauvegarde ──────────────────────────────────────────
import soundfile as sf
peak = float(np.max(np.abs(audio)))
rms  = float(np.sqrt(np.mean(audio**2)))
os.makedirs(os.path.join(ROOT, "data", "mic_test"), exist_ok=True)
wav_path = os.path.join(ROOT, "data", "mic_test", "last_recording.wav")
# normalise legerement pour l'ecoute si tres faible
sf.write(wav_path, audio, SR)
print(f"AUDIO: duree={dur:.1f}s  peak={peak:.3f}  rms={rms:.4f}", flush=True)
print(f"  -> sauve: {wav_path}", flush=True)
if peak < 0.05:
    print("  ATTENTION: niveau TRES faible (micro trop loin / volume bas)", flush=True)
elif peak > 0.98:
    print("  ATTENTION: saturation (clipping)", flush=True)

# Transcrit aussi une version normalisee (boost si faible)
if 0 < peak < 0.3:
    audio_norm = (audio / peak * 0.7).astype(np.float32)
else:
    audio_norm = audio

print("Transcription...", flush=True)

# ── Transcription ──────────────────────────────────────────────────────────
def transcribe(a):
    feats = proc.feature_extractor(a, sampling_rate=SR, return_tensors="pt").input_features
    with torch.no_grad():
        ids = model.generate(feats, max_new_tokens=200)
    return proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()

hyp = transcribe(audio)
hyp_norm = transcribe(audio_norm) if audio_norm is not audio else hyp

print("\n========== RESULTAT ==========", flush=True)
print(f"ENTENDU      : {hyp}", flush=True)
if hyp_norm != hyp:
    print(f"ENTENDU(norm): {hyp_norm}", flush=True)
if ref_text:
    print(f"ATTENDU: {ref_text}", flush=True)
    # comparaison mot-a-mot normalisee
    har = re.compile(r'[ً-ٰٟۖ-ۜ۟-ۭـ]')
    norm = lambda t: har.sub('', t)
    hw = hyp.split(); rw = ref_text.split()
    print("CMP:", flush=True)
    for i, rwword in enumerate(rw):
        got = hw[i] if i < len(hw) else "(manquant)"
        ok = i < len(hw) and norm(got) == norm(rwword)
        print(f"  {'OK ' if ok else 'ERR'} attendu={rwword}  dit={got}", flush=True)
print("MIC TEST DONE", flush=True)
