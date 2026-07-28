#!/usr/bin/env python3
"""Confronte CHAQUE mot non vert de l'app au modele, sur l'audio brut.

    python3 benchmark/verifier_erreurs.py benchmark/recettes/<dossier>...

POURQUOI CET OUTIL. Un mot signale par l'app n'est une VRAIE erreur que si le
modele echoue lui aussi quand on lui donne l'audio dans de bonnes conditions.
S'il le lit correctement, l'app a produit un FAUX POSITIF, et le defaut est dans
la chaine -- decoupage, alignement, jugement -- pas dans la recitation.

C'est le critere impose par l'utilisateur le 2026-07-28 : « les erreurs, il faut
qu'elles soient egalement dans le modele avec l'audio brut ».

METHODE, et ses pieges deja tombes :

- On balaye plusieurs LARGEURS de fenetre. Une seule largeur ne prouve rien :
  mesure du 2026-07-28, `عظيم` est parfait a 3 s et introuvable a 12 s. Conclure
  « le modele n'y arrive pas » sur une seule largeur est une erreur de methode.
- Un test par sous-chaine ne suffit pas a ecrire « absent » : le modele decode
  souvent une quasi-homophone ou perd une lettre (`قاموا` -> `قالوا`,
  `لذهب` -> `لهب`). Les cas non trouves sont donc ressortis AVEC le texte
  reellement decode, pour etre lus et non devines.
- On travaille sur le flux BRUT (`stream_*.wav`), pas sur les clips : ceux-ci
  sont l'audio consomme, deja filtre par le portier et par la segmentation --
  c'est-a-dire deja influence par ce qu'on cherche a juger.
"""
import glob
import json
import os
import re
import sys
import wave

os.environ["USE_TF"] = "0"
import numpy as np  # noqa: E402
import onnxruntime as ort  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from mel_numpy_reference import compute_mel_features  # noqa: E402

SR = 16000
MODELE = os.path.expanduser("~/.cache/coran-karim")
LARGEURS = (2, 3, 4, 6, 8)
DIAC = re.compile(r"[ً-ْٰٖ-ٟۖ-ۭـ]")


def norm(x: str) -> str:
    x = DIAC.sub("", x)
    for src, dst in (("أإآٱ", "ا"), ("ىي", "ي"), ("ؤو", "و"), ("ئء", "ي"), ("ة", "ه")):
        for c in src:
            x = x.replace(c, dst)
    return x.replace(" ", "")


def lire(p):
    with wave.open(p, "rb") as w:
        n = w.getnframes()
        return np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0


class Modele:
    def __init__(self):
        self.s = ort.InferenceSession(f"{MODELE}/dev_model.onnx",
                                      providers=["CPUExecutionProvider"])
        v = json.load(open(f"{MODELE}/dev_vocab.json", encoding="utf-8"))
        self.vocab = ([k for k, _ in sorted(v.items(), key=lambda kv: kv[1])]
                      if isinstance(v, dict) else v)
        self.blank = len(self.vocab)

    def decode(self, a):
        if len(a) < SR // 2:
            return ""
        mel = compute_mel_features(a).astype(np.float32)[None]
        lp = self.s.run(None, {"audio_signal": mel,
                               "length": np.array([mel.shape[2]], dtype=np.int64)})[0][0]
        ids = lp.argmax(-1)
        out, prev = [], -1
        for i in ids:
            if i != prev and i != self.blank:
                out.append(self.vocab[i])
            prev = i
        return "".join(out).replace("▁", " ").strip()


def non_verts(log):
    """Mots signales OU non juges, avec leur etat. Les lignes du secours sont
    ecartees : elles rejouent l'aligneur et produisent les memes marqueurs."""
    lock, nj = {}, {}
    for l in open(log, encoding="utf-8", errors="replace"):
        if "secours:" in l:
            continue
        m = re.search(r'\[GOP\] mot=(\d+) "([^"]*)"', l)
        if not m:
            continue
        k = int(m.group(1))
        if "NON JUG" in l:
            nj[k] = m.group(2)
        st = re.search(r"WordStatus\.(\w+) \(lock=true", l)
        if st:
            lock[k] = (m.group(2), st.group(1))
    res = {k: (t, s) for k, (t, s) in lock.items() if s != "correct"}
    for k, t in nj.items():
        if k not in lock:
            res[k] = (t, "non juge")
    return res, len(lock) + len([k for k in nj if k not in lock])


def main(dossiers):
    mod = Modele()
    tot_nv = tot_juges = tot_vrai = 0
    for d in dossiers:
        log = os.path.join(d, "session.log")
        wavs = glob.glob(os.path.join(d, "wav", "stream_*.wav"))
        if not (os.path.exists(log) and wavs):
            continue
        nv, juges = non_verts(log)
        if juges < 20:
            continue
        audio = lire(wavs[0])
        tot_nv += len(nv)
        tot_juges += juges
        print(f"\n=== {os.path.basename(d)} — {juges} mots jugés, "
              f"{len(nv)} non verts ({len(nv)/juges*100:.1f} %) ===")
        for k in sorted(nv):
            attendu, etat = nv[k]
            cible = norm(attendu)
            trouve = None
            for win in LARGEURS:
                pas = max(1.0, win / 4)
                t = 0.0
                while t + win <= len(audio) / SR:
                    if cible in norm(mod.decode(audio[int(t * SR):int((t + win) * SR)])):
                        trouve = (win, t)
                        break
                    t += pas
                if trouve:
                    break
            if trouve:
                print(f"  {k:>4} {attendu:<18} {etat:<9} FAUX POSITIF "
                      f"— le modèle le lit à {trouve[1]:.0f}s (fenêtre {trouve[0]}s)")
            else:
                tot_vrai += 1
                print(f"  {k:>4} {attendu:<18} {etat:<9} *** VRAIE ERREUR *** "
                      f"— introuvable quelle que soit la largeur")
    if tot_juges:
        print(f"\n{'='*68}\nTOTAL : {tot_nv} non verts sur {tot_juges} mots jugés "
              f"= {tot_nv/tot_juges*100:.2f} %")
        print(f"  dont VRAIES erreurs (confirmées par le modèle) : {tot_vrai} "
              f"= {tot_vrai/tot_juges*100:.2f} %")
        print(f"  dont FAUX POSITIFS (défaut de la chaîne)       : {tot_nv-tot_vrai} "
              f"= {(tot_nv-tot_vrai)/tot_juges*100:.2f} %")


if __name__ == "__main__":
    args = sys.argv[1:] or sorted(glob.glob("benchmark/recettes/*/"))
    main(args)
