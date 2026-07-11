"""
Serveur de test : le telephone (bon micro) enregistre dans le navigateur,
envoie l'audio au PC qui transcrit avec Whisper Small fine-tune sur CPU.
GPU non utilise (CUDA_VISIBLE_DEVICES vide) -> Medium intact.

Lancer : python server_test.py
Puis sur le tel (meme WiFi) : http://192.168.1.60:8000
"""
import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""
import truststore; truststore.inject_into_ssl()
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
import json, re, subprocess, tempfile, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import numpy as np, soundfile as sf, torch
from transformers import WhisperProcessor, WhisperForConditionalGeneration

ROOT = os.path.dirname(os.path.abspath(__file__))
FT   = os.path.join(ROOT, "models", "whisper-small-ft")
SR   = 16000
PORT = 8000

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

# Reference des versets (pour correction optionnelle)
REF = {}
for src in ("data/manifest_full.jsonl", "data/train_full.jsonl"):
    p = os.path.join(ROOT, src)
    if os.path.exists(p):
        for l in open(p, encoding="utf-8"):
            o = json.loads(l)
            REF.setdefault(o["key"], o["text"])
print(f"Modele pret. {len(REF)} versets de reference. Serveur sur :{PORT}", flush=True)

_HAR = re.compile(r'[ً-ٰٟۖ-ۜ۟-ۭـ]')
def norm(t): return _HAR.sub('', t)

SAVE_DIR = os.path.join(ROOT, "data", "mic_test")
os.makedirs(SAVE_DIR, exist_ok=True)

def decode_audio(raw_bytes):
    with tempfile.NamedTemporaryFile(suffix=".webm", delete=False) as f:
        f.write(raw_bytes); src = f.name
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", src,
           "-f", "f32le", "-ac", "1", "-ar", str(SR), "pipe:1"]
    r = subprocess.run(cmd, capture_output=True, timeout=120)
    os.unlink(src)
    if r.returncode != 0 or len(r.stdout) < 4:
        raise RuntimeError(r.stderr.decode()[:200])
    audio = np.frombuffer(r.stdout, dtype=np.float32).copy()
    # Sauvegarde pour analyse / re-test avec Medium
    ts = time.strftime("%H%M%S")
    sf.write(os.path.join(SAVE_DIR, f"phone_{ts}.wav"), audio, SR)
    return audio

def transcribe(audio):
    peak = float(np.max(np.abs(audio))) if len(audio) else 0
    if 0 < peak < 0.3:
        audio = (audio / peak * 0.7).astype(np.float32)
    feats = proc.feature_extractor(audio, sampling_rate=SR,
                                   return_tensors="pt").input_features
    with torch.no_grad():
        ids = model.generate(feats, max_new_tokens=200)
    return proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip(), peak

HTML = """<!doctype html><html lang=fr><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Test Coran ASR</title>
<style>
 body{font-family:system-ui;margin:0;background:#0c3b2c;color:#fff;text-align:center}
 .wrap{padding:24px;max-width:640px;margin:auto}
 h1{font-size:20px;color:#e6cf8f}
 .btn{display:inline-block;font-size:20px;padding:20px 30px;border:none;border-radius:16px;
   margin:10px;background:#1a7a5e;color:#fff;font-weight:600}
 input[type=text]{font-size:16px;padding:10px;border-radius:8px;border:none;width:130px;text-align:center}
 .card{background:#fbf7ee;color:#1a1209;border-radius:16px;padding:18px;margin-top:18px;
   text-align:right;font-size:26px;line-height:2;min-height:40px;direction:rtl;font-family:serif}
 .ref{background:#ebf7f3;font-size:22px}
 .ok{color:#1a7a5e;font-weight:700}.err{color:#b00020;font-weight:700}
 .status{font-size:14px;color:#e6cf8f;margin-top:10px}
 #file{display:none}
</style></head><body><div class=wrap>
<h1>🎙️ Test Whisper Small — Coran</h1>
<p>Verset attendu (optionnel) : <input type=text id=verse placeholder="ex 112:1"></p>
<label class=btn for=file>🎤 Enregistrer / Choisir audio</label>
<input type=file id=file accept="audio/*" capture="microphone">
<div class=status id=status>Tape le bouton → dictaphone du téléphone → enregistre → valide</div>
<div class=card id=out></div>
<div id=cmp></div>
<script>
const file=document.getElementById('file'),out=document.getElementById('out'),
 status=document.getElementById('status'),cmp=document.getElementById('cmp');
file.onchange=async()=>{
 if(!file.files.length)return;
 status.textContent='Transcription en cours...';out.textContent='';cmp.innerHTML='';
 const v=document.getElementById('verse').value.trim();
 try{
  const r=await fetch('/transcribe?verse='+encodeURIComponent(v),{method:'POST',body:file.files[0]});
  const j=await r.json();
  out.textContent=j.text||'(rien)';
  status.textContent='Niveau: '+((j.peak||0)*100).toFixed(0)+'% — '+(j.ms||0)+'ms';
  cmp.innerHTML=j.cmp||'';
 }catch(e){status.textContent='Erreur: '+e;}
 file.value='';
};
</script></div></body></html>"""

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(HTML.encode("utf-8"))
    def do_POST(self):
        try:
            ln = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(ln)
            from urllib.parse import urlparse, parse_qs
            vk = parse_qs(urlparse(self.path).query).get("verse", [""])[0]
            t0 = time.time()
            audio = decode_audio(raw)
            text, peak = transcribe(audio)
            ms = int((time.time()-t0)*1000)
            cmp_html = ""
            if vk and vk in REF:
                ref = REF[vk]; hw = text.split(); rw = ref.split()
                parts = []
                for i, w in enumerate(rw):
                    got = hw[i] if i < len(hw) else ""
                    ok = got and norm(got) == norm(w)
                    parts.append(f'<span class="{"ok" if ok else "err"}">{w}</span>')
                cmp_html = ('<div class="card ref">' + " ".join(parts) +
                            f'<br><small>Réf {vk}</small></div>')
            print(f"  POST: peak={peak:.3f} {ms}ms verse={vk} -> {text[:50]}", flush=True)
            body = json.dumps({"text": text, "peak": peak, "ms": ms, "cmp": cmp_html})
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(body.encode("utf-8"))
        except Exception as e:
            print(f"  ERREUR: {e}", flush=True)
            self.send_response(500); self.end_headers()
            self.wfile.write(json.dumps({"text": f"erreur: {e}"}).encode("utf-8"))

ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
