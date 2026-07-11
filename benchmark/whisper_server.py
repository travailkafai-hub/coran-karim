"""
Serveur Whisper local pour test sur téléphone (WiFi).
Charge whisper-medium-ft (GPU) et expose POST /transcribe.

Usage:
  .venv/Scripts/python.exe whisper_server.py [--host 0.0.0.0] [--port 8765]

Depuis le téléphone (même réseau WiFi) :
  http://<IP_DU_PC>:8765/transcribe
"""
import os, io, argparse, warnings
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"
warnings.filterwarnings("ignore")
import truststore; truststore.inject_into_ssl()
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))

import torch
import numpy as np
import soundfile as sf
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
import uvicorn

ROOT      = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(ROOT, "models", "whisper-medium-ft")
DEVICE    = "cuda" if torch.cuda.is_available() else "cpu"

print(f"Chargement whisper-medium-ft sur {DEVICE}...", flush=True)
proc  = WhisperProcessor.from_pretrained(MODEL_DIR)
model = WhisperForConditionalGeneration.from_pretrained(
    MODEL_DIR, torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32
).to(DEVICE).eval()

try:
    model.generation_config.is_multilingual = True
    model.generation_config.forced_decoder_ids = proc.get_decoder_prompt_ids(
        language="arabic", task="transcribe")
    model.generation_config.suppress_tokens = []
except Exception:
    pass

print(f"Modèle prêt sur {DEVICE.upper()}", flush=True)

app = FastAPI(title="Whisper Coran Server")


@app.get("/health")
def health():
    return {"status": "ok", "model": "whisper-medium-ft", "device": DEVICE}


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    """Reçoit un fichier audio WAV 16kHz mono, retourne transcription + mots."""
    audio_bytes = await file.read()
    try:
        audio, sr = sf.read(io.BytesIO(audio_bytes), dtype="float32")
    except Exception as e:
        return JSONResponse({"error": f"Audio illisible : {e}"}, status_code=400)

    # Resample si nécessaire (le `record` package envoie 16kHz, mais on sécurise)
    if sr != 16000:
        try:
            import librosa
            audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
        except ImportError:
            # Fallback: sous-échantillonnage basique
            ratio = int(sr / 16000)
            audio = audio[::ratio] if ratio > 1 else audio

    # Mono si stéréo
    if audio.ndim > 1:
        audio = audio.mean(axis=1)

    feats = proc.feature_extractor(
        audio, sampling_rate=16000, return_tensors="pt"
    ).input_features.to(DEVICE)
    if DEVICE == "cuda":
        feats = feats.half()

    with torch.no_grad():
        ids = model.generate(feats, max_new_tokens=440)

    text = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()

    # Retourne les mots séparément pour le matching côté Flutter
    words = [
        {"text": w, "confidence": 0.9}
        for w in text.split()
        if w.strip()
    ]

    return {"text": text, "words": words}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()

    import socket
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    print(f"\n{'='*50}", flush=True)
    print(f"Serveur Whisper démarré :", flush=True)
    print(f"  Local   : http://localhost:{args.port}", flush=True)
    print(f"  Réseau  : http://{local_ip}:{args.port}", flush=True)
    print(f"Entrez cette IP dans l'app Flutter (Settings > Serveur ASR)", flush=True)
    print(f"{'='*50}\n", flush=True)

    uvicorn.run(app, host=args.host, port=args.port, log_level="warning")
