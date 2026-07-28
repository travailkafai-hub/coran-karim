#!/usr/bin/env python3
"""Mesure combien de coupes de segment tombent EN PLEIN MOT.

    python3 benchmark/mesurer_coupes.py benchmark/recettes/<dossier>...

POURQUOI. La mesure du 2026-07-28 a isole la cause des mots non verts : 19 sur
22 ont ZERO frame, avec une place disponible de 160 ms en mediane. Ces mots ne
sont pas mal alignes -- il n'y a pas d'audio pour eux, parce que la coupe de
segment tombe dessus. Ce script chiffre ce defaut la ou il NAIT, sans device.

METHODE. Les clips sont l'audio consomme, contigus et sans recouvrement (verifie
apres correctif : somme(clips) < flux brut). Les frontieres entre clips sont
donc exactement les coupes. Pour chacune, on decode une fenetre CENTREE dessus,
puis les deux moities separement : si le mot present a cheval sur la coupe
disparait des deux moities, la coupe l'a casse.
"""
import glob, json, os, re, sys, wave
os.environ["USE_TF"] = "0"
import numpy as np, onnxruntime as ort
sys.path.insert(0, os.path.dirname(__file__))
from mel_numpy_reference import compute_mel_features

SR = 16000; M = os.path.expanduser("~/.cache/coran-karim")
DIAC = re.compile(r"[ً-ْٰٖ-ٟۖ-ۭـ]")

def nz(x):
    x = DIAC.sub("", x)
    for a, b in (("أإآٱ","ا"),("ىي","ي"),("ؤو","و"),("ئء","ي"),("ة","ه")):
        for c in a: x = x.replace(c, b)
    return x

def lire(p):
    with wave.open(p, "rb") as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)/32768.

s = ort.InferenceSession(f"{M}/dev_model.onnx", providers=["CPUExecutionProvider"])
v = json.load(open(f"{M}/dev_vocab.json", encoding="utf-8"))
VOC = [k for k,_ in sorted(v.items(), key=lambda kv: kv[1])] if isinstance(v, dict) else v
BL = len(VOC)

def dec(a):
    if len(a) < SR//3: return ""
    mel = compute_mel_features(a).astype(np.float32)[None]
    lp = s.run(None, {"audio_signal": mel, "length": np.array([mel.shape[2]], dtype=np.int64)})[0][0]
    ids = lp.argmax(-1); o=[]; p=-1
    for i in ids:
        if i != p and i != BL: o.append(VOC[i])
        p = i
    return "".join(o).replace("▁"," ").strip()

tot = casse = 0
for d in sys.argv[1:] or sorted(glob.glob("benchmark/recettes/*/")):
    clips = sorted(glob.glob(os.path.join(d,"wav","clip_*.wav")),
                   key=lambda p: int(re.search(r"(\d+)", os.path.basename(p)).group(1)))
    if len(clips) < 3: continue
    audio = [lire(c) for c in clips]
    post = np.concatenate(audio)
    bornes, acc = [], 0
    for a in audio[:-1]:
        acc += len(a); bornes.append(acc)
    n_d = n_c = 0
    for b in bornes:
        if b < 2*SR or b + 2*SR > len(post): continue
        entier = nz(dec(post[b-2*SR:b+2*SR])).split()
        gauche = nz(dec(post[b-2*SR:b])).split()
        droite = nz(dec(post[b:b+2*SR])).split()
        # un mot vu ensemble mais absent des deux moities = coupe en plein mot
        perdus = [w for w in entier if len(w) >= 3 and w not in gauche and w not in droite]
        n_d += 1
        if perdus: n_c += 1
    tot += n_d; casse += n_c
    if n_d:
        print(f"{os.path.basename(d.rstrip('/')):<24} {n_c}/{n_d} coupes en plein mot "
              f"({n_c/n_d*100:.0f} %)")
if tot:
    print(f"\nTOTAL : {casse} coupes en plein mot sur {tot} = {casse/tot*100:.1f} %")
