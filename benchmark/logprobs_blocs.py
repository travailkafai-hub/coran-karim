#!/usr/bin/env python3
"""Calcule les logprobs des blocs DECIDES PAR L'APP, et rien d'autre.

C'est la couche C (mel + ONNX) du banc hors telephone, et SEULEMENT elle. Les
bornes des blocs viennent de `ConstructeurDeFenetres` -- le vrai code Kotlin,
execute en JVM juste avant (cf. BancFluxBrut.blocs). Ce script ne decide donc
aucune politique : il ne fait qu'executer le modele la ou l'app le lui demande.

C'est la reponse au piege paye deux jours de suite sur ce projet : « le banc
mesurait mon decoupage, pas l'app ».
"""
import json, os, struct, sys, wave
import numpy as np, onnxruntime as ort
sys.path.insert(0, "benchmark")
from mel_numpy_reference import compute_mel_features

RACINE = "/tmp/claude-1000"
modele = sys.argv[1] if len(sys.argv) > 1 else f"{RACINE}/modele/model.onnx"
vocab = sys.argv[2] if len(sys.argv) > 2 else f"{RACINE}/modele/vocab.json"

pieces = json.load(open(vocab, encoding="utf-8"))
open(f"{RACINE}/pieces.txt", "w", encoding="utf-8").write("\n".join(pieces))

w = wave.open(f"{RACINE}/brut.wav")
pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0

sess = ort.InferenceSession(modele, providers=["CPUExecutionProvider"])
assert "audio_signal" in [i.name for i in sess.get_inputs()]

os.makedirs(f"{RACINE}/logprobs", exist_ok=True)
for f in os.listdir(f"{RACINE}/logprobs"):
    os.remove(f"{RACINE}/logprobs/{f}")

n = 0
for ligne in open(f"{RACINE}/blocs.txt", encoding="utf-8"):
    if not ligne.strip():
        continue
    bid, debut, fin, _ = ligne.strip().split(";")
    x = pcm[int(debut):int(fin)]
    if len(x) < 3200:
        continue
    feats = compute_mel_features(x).astype(np.float32)
    out = sess.run(None, {"audio_signal": feats[None],
                          "length": np.array([feats.shape[1]], dtype=np.int64)})
    lp = np.asarray(out[0][0], dtype=np.float32)
    with open(f"{RACINE}/logprobs/{bid}.bin", "wb") as g:
        g.write(struct.pack("<ii", lp.shape[0], lp.shape[1]))
        g.write(lp.tobytes())
    n += 1
print(f"{n} blocs -> {RACINE}/logprobs/  (V={len(pieces)+1})")
