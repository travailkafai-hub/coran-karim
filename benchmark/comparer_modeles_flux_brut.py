#!/usr/bin/env python3
"""Tous les modeles deployables, sur le MEME flux brut, avec le MEME decoupage.

Demande utilisateur 2026-07-30 : « teste-moi tous les modeles qui existent ».

METHODE, et ce qu'elle evite. Le decoupage est le meme pour tous et il ne vient
pas de moi : les blocs sont delimites par les SILENCES REELS du recitateur
(pause >= 0,5 s, RMS < 0,02) sur le flux brut non filtre. C'est le seul
decoupage qui ne soit pas une politique applicative -- et la mesure du
2026-07-30 a montre qu'il est aussi le meilleur pour le modele du telephone
(14,86 % contre 29 a 54 % pour tout decoupage a longueur imposee).

Un modele qui aurait besoin d'un autre decoupage pour briller n'aiderait pas :
c'est CE decoupage que l'app peut produire en temps reel.
"""
import glob, json, os, sys, wave
import numpy as np, onnxruntime as ort
sys.path.insert(0, "benchmark")
from mel_numpy_reference import compute_mel_features
from plafond_modele import greedy, distance_mots, sans_harakat

def blocs_aux_silences(x, pause_min_s=0.5, rms_seuil=0.02):
    b = 1280
    n = len(x) // b
    rms = np.array([np.sqrt(np.mean(x[i*b:(i+1)*b]**2)) for i in range(n)])
    sil = rms < rms_seuil
    out, debut, run = [], 0, 0
    for i in range(n):
        if sil[i]:
            run += 1
        else:
            if run * 0.08 >= pause_min_s and i - run > debut:
                fin = i - run // 2
                out.append(x[debut*b:fin*b]); debut = fin
            run = 0
    out.append(x[debut*b:])
    return [z for z in out if len(z) > 3200]

def main():
    brut, cible = sys.argv[1], sys.argv[2]
    attendus = json.load(open(cible, encoding="utf-8"))
    w = wave.open(brut)
    pcm = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    blocs = blocs_aux_silences(pcm)
    print(f"flux brut {len(pcm)/16000:.1f} s -> {len(blocs)} blocs (silences reels)\n")

    modeles = []
    for d in sorted(glob.glob("benchmark/models_deployes/*/")):
        o, v = os.path.join(d, "model.onnx"), os.path.join(d, "vocab.json")
        if os.path.exists(o) and os.path.exists(v):
            modeles.append((os.path.basename(d.rstrip("/")), o, v))
    modeles.append(("DEPLOYE causal-v1 (telephone)",
                    "/tmp/claude-1000/modele/model.onnx",
                    "/tmp/claude-1000/modele/vocab.json"))

    print(f"{'modele':<48}{'mots':>7}{'strict':>10}{'lettres':>10}")
    for nom, o, v in modeles:
        try:
            pieces = json.load(open(v, encoding="utf-8"))
            sess = ort.InferenceSession(o, providers=["CPUExecutionProvider"])
            if "audio_signal" not in [i.name for i in sess.get_inputs()]:
                print(f"{nom:<48}{'ENTREE raw_audio -> inutilisable par l app':>27}")
                continue
            blank = len(pieces)
            txt = []
            for z in blocs:
                f = compute_mel_features(z).astype(np.float32)
                out = sess.run(None, {"audio_signal": f[None],
                                      "length": np.array([f.shape[1]], dtype=np.int64)})
                txt.append(greedy(out[0][0], pieces, blank))
            lu = " ".join(t for t in txt if t).split()
            r = [100*distance_mots([g(m) for m in attendus], [g(m) for m in lu])/len(attendus)
                 for g in (lambda s: s, sans_harakat)]
            print(f"{nom:<48}{len(lu):>7}{r[0]:>9.2f}%{r[1]:>9.2f}%")
            del sess
        except Exception as e:
            print(f"{nom:<48}  ECHEC : {str(e)[:60]}")

if __name__ == "__main__":
    main()
