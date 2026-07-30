#!/usr/bin/env python3
"""LE PLAFOND DU MODELE : que lit-il, sur l'audio que l'app a reellement consomme ?

POURQUOI CE SCRIPT (demande utilisateur 2026-07-30 : « controle les wav avec le
modele en local pour cibler le taux 2 % »).

Tant qu'on ne connait pas ce chiffre, aucun taux applicatif n'est
interpretable : on ne sait pas si 10 % est une chaine mediocre sur un bon
modele, ou une bonne chaine sur un modele a 10 %. C'est le denominateur qui
manquait a toutes les discussions de taux de ce projet.

DEUX PIEGES DE METHODE, TOUS DEUX DEJA PAYES ICI, ET EVITES EXPLICITEMENT :

1. « Le banc mesurait mon decoupage, pas l'app » (2026-07-29, repaye deux jours
   de suite). Un decoupage arbitraire en tranches de 5 s produisait de la
   bouillie la ou l'app, avec SON decoupage, transcrivait proprement le meme
   audio. ⇒ Ici on ne decoupe RIEN : on transcrit les clips ecrits par l'app
   elle-meme, c'est-a-dire exactement les segments qu'elle a donnes au modele.

2. Le modele utilise doit etre CELUI DU TELEPHONE, pas un checkpoint voisin.
   ⇒ `model.onnx` est tire du device par `adb pull` avant de lancer ce script.
   L'entree ONNX doit s'appeler `audio_signal` (mel) et jamais `raw_audio` --
   piege tombe deux fois, le modele se charge quand meme et chaque
   transcription echoue en silence.

Ce que le script NE dit pas : le taux de l'app. Il dit ce que le modele est
capable de lire quand on lui donne l'audio proprement. L'ecart entre les deux
est, par definition, ce que la chaine ajoute comme erreurs.
"""
import glob
import json
import re
import sys
import wave

import numpy as np
import onnxruntime as ort

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from mel_numpy_reference import compute_mel_features  # noqa: E402

HARAKAT = set("ًٌٍَُِّْٰٕٓٔۡـۖۗۘۙۚۛۜ۝۞ۣ۟۠ۢۥۦۧۨ۩۪ۭ۫۬")
EQUIV = {"آ": "ا", "أ": "ا", "إ": "ا", "ٱ": "ا", "ى": "ي", "ة": "ه"}


def sans_harakat(m: str) -> str:
    return "".join(EQUIV.get(c, c) for c in m if c not in HARAKAT)


def lire_wav(chemin: str) -> np.ndarray:
    with wave.open(chemin, "rb") as w:
        n = w.getnframes()
        brut = w.readframes(n)
    return np.frombuffer(brut, dtype=np.int16).astype(np.float32) / 32768.0


def greedy(logprobs: np.ndarray, pieces, blank: int) -> str:
    ids = []
    prec = -1
    for t in range(logprobs.shape[0]):
        m = int(np.argmax(logprobs[t]))
        if m != prec and m != blank:
            ids.append(m)
        prec = m
    return "".join(pieces[i] for i in ids if i < len(pieces)).replace("▁", " ").strip()


def distance_mots(ref, hyp):
    """Levenshtein sur les MOTS -> (substitutions+insertions+suppressions)."""
    n, m = len(ref), len(hyp)
    d = np.zeros((n + 1, m + 1), dtype=np.int32)
    d[:, 0] = np.arange(n + 1)
    d[0, :] = np.arange(m + 1)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            c = 0 if ref[i - 1] == hyp[j - 1] else 1
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1, d[i - 1, j - 1] + c)
    return int(d[n, m])


def main():
    modele, vocab_p, cible_p, dossier_clips = sys.argv[1:5]

    pieces = json.load(open(vocab_p, encoding="utf-8"))
    blank = len(pieces)
    attendus = json.load(open(cible_p, encoding="utf-8"))

    sess = ort.InferenceSession(modele, providers=["CPUExecutionProvider"])
    entrees = [i.name for i in sess.get_inputs()]
    print(f"entrees ONNX : {entrees}")
    assert "audio_signal" in entrees, \
        "export invalide : l'app calcule le mel, l'entree DOIT etre audio_signal"

    clips = sorted(glob.glob(f"{dossier_clips}/clip_*.wav"),
                   key=lambda p: int(re.search(r"clip_(\d+)", p).group(1)))
    print(f"{len(clips)} clips ecrits par l'app (= ses propres segments)\n")

    pcms = [lire_wav(c) for c in clips]

    def transcrire(bloc: np.ndarray) -> str:
        feats = compute_mel_features(bloc).astype(np.float32)  # (80, T)
        out = sess.run(None, {
            "audio_signal": feats[None, :, :],
            "length": np.array([feats.shape[1]], dtype=np.int64),
        })
        return greedy(out[0][0], pieces, blank)

    def grouper(secondes: float):
        """Regroupe des clips CONSECUTIFS jusqu'a `secondes`. On ne coupe donc
        JAMAIS ailleurs que la ou l'app a deja coupe : le banc ne mesure pas
        un decoupage de mon invention (piege paye deux jours de suite)."""
        blocs, cur = [], []
        n = 0
        for pcm in pcms:
            cur.append(pcm)
            n += len(pcm)
            if n >= secondes * 16000:
                blocs.append(np.concatenate(cur)); cur = []; n = 0
        if cur:
            blocs.append(np.concatenate(cur))
        return blocs

    # Le nombre de FRONTIERES est la variable qu'on fait bouger : si l'erreur
    # s'effondre quand elles diminuent, l'erreur est dans la coupe, pas dans le
    # modele. C'est la seule facon de separer les deux avec le meme audio.
    configs = [("clip par clip", pcms)]
    for d in (18.0, 60.0):
        configs.append((f"regroupes ~{int(d)}s", grouper(d)))
    configs.append(("fichier entier", [np.concatenate(pcms)]))

    print(f"{'decoupage':<20}{'blocs':>6}{'mots lus':>10}"
          f"{'strict':>10}{'lettres':>10}")
    for nom, blocs in configs:
        lu = " ".join(t for t in (transcrire(b) for b in blocs) if t).split()
        res = []
        for f in (lambda x: x, sans_harakat):
            ref = [f(m) for m in attendus]
            hyp = [f(m) for m in lu]
            res.append(100 * distance_mots(ref, hyp) / len(ref))
        print(f"{nom:<20}{len(blocs):>6}{len(lu):>10}"
              f"{res[0]:>9.2f}%{res[1]:>9.2f}%")
        if nom == "fichier entier":
            open("/tmp/claude-1000/plafond_texte.txt", "w",
                 encoding="utf-8").write(" ".join(lu))


if __name__ == "__main__":
    main()
