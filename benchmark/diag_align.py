"""
Test youtube_align sur Un fichier An-Naba (40 versets, ~5 min).
"""
import truststore; truststore.inject_into_ssl()
import json, re, subprocess
import numpy as np
from difflib import SequenceMatcher
from pathlib import Path
import torch
from transformers import WhisperForConditionalGeneration, WhisperProcessor

ROOT = Path(__file__).parent
SR   = 16000
MODEL_DIR = str(ROOT / "models/whisper-phase4-noisy")
TRAIN_ORIG = ROOT / "data/train_full.jsonl"

def decode_m4a(path):
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", path,
           "-f", "f32le", "-ac", "1", "-ar", str(SR), "pipe:1"]
    r = subprocess.run(cmd, capture_output=True, timeout=300)
    return np.frombuffer(r.stdout, dtype=np.float32).copy()

def normalize(text):
    text = re.sub(r'[ً-ٰٟـ]', '', text)
    text = text.replace('أ','ا').replace('إ','ا').replace('آ','ا')
    text = text.replace('ى','ي').replace('ؤ','و').replace('ئ','ي')
    text = re.sub(r'[^؀-ۿ\s]', '', text)
    return ' '.join(text.split()).strip()

def sim(h, r):
    h, r = normalize(h), normalize(r)
    if not h or not r: return 0.0
    return SequenceMatcher(None, h, r).ratio()

def main():
    # Load verses for surah 78 (An-Naba)
    verses = {}
    for line in open(TRAIN_ORIG, encoding="utf-8"):
        r = json.loads(line)
        s, a = map(int, r["key"].split(":"))
        if s == 78:
            verses[a] = r["text"]
    verses = sorted(verses.items())
    print(f"Sourate 78: {len(verses)} versets")

    test_file = list((ROOT / "data/youtube_audio/s078_an_naba").glob("*.m4a"))[0]
    print(f"Fichier: {test_file.name}")
    audio = decode_m4a(str(test_file))
    print(f"Duree: {len(audio)/SR:.1f}s  max_amp={np.max(np.abs(audio)):.3f}")

    # Load model
    print("\nChargement modele...")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    proc  = WhisperProcessor.from_pretrained(MODEL_DIR)
    model = WhisperForConditionalGeneration.from_pretrained(MODEL_DIR).to(device)
    model.eval()
    forced_ids = proc.get_decoder_prompt_ids(language="arabic", task="transcribe")
    model.generation_config.is_multilingual    = True
    model.generation_config.forced_decoder_ids = forced_ids
    model.generation_config.suppress_tokens    = []
    model.generation_config.max_length         = 448

    CHUNK_S = 30
    chunk_len = SR * CHUNK_S

    # Test first 3 chunks
    print("\nTranscription 3 premiers blocs de 30s:")
    for ci in range(min(3, len(audio)//chunk_len + 1)):
        seg = audio[ci*chunk_len:(ci+1)*chunk_len]
        feats = proc.feature_extractor(seg, sampling_rate=SR, return_tensors="pt").input_features.to(device)
        with torch.no_grad():
            ids = model.generate(feats, max_new_tokens=440)
        hyp = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()

        # Find best window
        best_score, best_start, best_end = 0, 0, 1
        for start in range(ci*5, min(ci*5+15, len(verses))):
            win = ""
            for end in range(start+1, min(start+9, len(verses)+1)):
                win += (" " if win else "") + verses[end-1][1]
                s = sim(hyp, win)
                if s > best_score:
                    best_score, best_start, best_end = s, start, end

        matched_keys = [f"78:{verses[vi][0]}" for vi in range(best_start, best_end)]
        print(f"\nBloc {ci} [{ci*30}s-{(ci+1)*30}s]:")
        print(f"  hyp={hyp[:120]!r}")
        print(f"  best score={best_score:.3f} -> versets {matched_keys}")

if __name__ == "__main__":
    main()
