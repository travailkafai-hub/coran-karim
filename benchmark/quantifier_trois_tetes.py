#!/usr/bin/env python3
"""Quantifie INT8 le modele a trois tetes, et MESURE ce que ca coute.

Question de l'utilisateur (2026-08-04) : « on n'a pas teste quantize le
modele, voir comment il se comporte ». Jamais fait sur FastConformer -- les
seuls int8 du projet sont deux exports Whisper, piste abandonnee.

CE QUI EST EN JEU. Le modele deploye fait 459 Mo et l'utilisateur a signale une
lenteur. INT8 divise la taille par ~4 et accelere l'inference CPU. Mais une
quantification qui abime les logprobs abime le JUGEMENT -- et un gain de
vitesse paye en verdicts faux est un faux gain (regle du superviseur).

CE QU'ON MESURE, donc, sur du VRAI audio de recitation :
  1. taille du fichier ;
  2. ecart des logprobs FP32 vs INT8, et surtout le taux de frames ou
     l'argmax CHANGE -- c'est lui qui decide le texte decode ;
  3. ecart sur les trois sorties (lettres, tajwid, etat encodeur) ;
  4. temps d'inference, mediane sur plusieurs passes.

Le seuil de refus n'est pas un reglage : si l'argmax change sur des frames, le
texte change, donc les verdicts changent. On veut ~0 %.
"""
import argparse
import statistics
import sys
import time
from pathlib import Path

import numpy as np

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--modele", required=True)
    p.add_argument("--sortie", default=None)
    p.add_argument("--wav", required=True)
    p.add_argument("--secondes", type=float, default=20.0)
    p.add_argument("--passes", type=int, default=5)
    a = p.parse_args()

    import onnxruntime as ort
    from onnxruntime.quantization import quantize_dynamic, QuantType
    from assainir_corpus_fautes import lire_wav
    from mel_numpy_reference import compute_mel_features

    src = Path(a.modele)
    dst = Path(a.sortie) if a.sortie else src.with_name(src.stem + "_int8.onnx")
    if not dst.exists():
        print(f"quantification INT8 : {src.name} -> {dst.name} ...", flush=True)
        quantize_dynamic(str(src), str(dst), weight_type=QuantType.QInt8)
    print(f"  FP32 {src.stat().st_size/1e6:7.1f} Mo")
    print(f"  INT8 {dst.stat().st_size/1e6:7.1f} Mo "
          f"({100*dst.stat().st_size/src.stat().st_size:.0f} % de l'original)")

    pcm = lire_wav(Path(a.wav))[:int(16000 * a.secondes)]
    f = compute_mel_features(pcm).astype(np.float32)
    entree = {"audio_signal": f[None],
              "length": np.array([f.shape[1]], dtype=np.int64)}

    res = {}
    for nom, chemin in (("FP32", src), ("INT8", dst)):
        s = ort.InferenceSession(str(chemin), providers=["CPUExecutionProvider"])
        noms = [o.name for o in s.get_outputs()]
        s.run(None, entree)                      # chauffe
        t = []
        for _ in range(a.passes):
            t0 = time.perf_counter()
            out = s.run(None, entree)
            t.append(time.perf_counter() - t0)
        res[nom] = (dict(zip(noms, [np.asarray(o[0]) for o in out])),
                    statistics.median(t))
        print(f"  {nom} inference mediane : {1000*res[nom][1]:7.1f} ms "
              f"sur {a.secondes:.0f} s d'audio")

    g = res["FP32"][1] / res["INT8"][1]
    print(f"\n  acceleration : x{g:.2f}")

    print("\nECART SUR LES SORTIES (ce qui decide les verdicts) :")
    for nom in res["FP32"][0]:
        A, B = res["FP32"][0][nom], res["INT8"][0].get(nom)
        if B is None:
            continue
        n = min(A.shape[0], B.shape[0])
        A, B = A[:n], B[:n]
        d = np.abs(A - B)
        ligne = f"  {nom:16s} ecart max {d.max():.4f}  moyen {d.mean():.6f}"
        if nom in ("logprobs", "tajwid_logprobs"):
            chg = 100 * (A.argmax(1) != B.argmax(1)).mean()
            ligne += f"  | argmax CHANGE sur {chg:.2f} % des frames"
        print(ligne)
    print("\nLecture : un argmax qui change = un texte decode different, donc "
          "des verdicts differents. On veut 0 %.")


if __name__ == "__main__":
    main()
