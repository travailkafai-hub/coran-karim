#!/usr/bin/env python3
"""VALIDATION DE LA TETE TAJWID SUR AUDIO REEL — pas sur `val_tajwid`.

── POURQUOI CE BANC EXISTE ────────────────────────────────────────────────
`val_tajwid` est une metrique INTERNE, calculee sur le meme corpus que
l'entrainement. Le projet a deja ete trompe exactement la : un `val_wer_ctc` a
0,032 masquait un WER reel de 28 a 44 % hors studio (cf. l'avertissement dans
finetune_dual_head.py, ecrit apres coup). Un bon chiffre de validation ne dit
RIEN tant qu'on n'a pas confronte le modele a de la recitation reelle.

Demande utilisateur 2026-07-31 : « garde des checkpoints et avec des
validations d'audio qui sont disponibles ».

── CE QU'IL MESURE ────────────────────────────────────────────────────────
Sur les 380 s de recitation reelle du banc (Al-Baqara, meme flux que
BancFluxBrut), on compare :

    ce que la tete EMET   contre   ce que le texte recite CONTIENT

La verite terrain vient de `data/quran_tajweed_rules/uthmani_tajweed.jsonl`
(6 236 versets annotes en ligne, `<tajweed class=X>...</tajweed>`).

── CE QU'IL NE MESURE PAS, ET IL FAUT LE DIRE ─────────────────────────────
Il compare des COMPTES par regle sur tout le passage, pas des positions frame a
frame. Une regle emise au bon nombre mais au mauvais endroit passerait pour
correcte. C'est volontairement grossier :

  - un compte est deja BIEN plus informatif que `val_tajwid` : il dit quelles
    regles la tete ne voit JAMAIS (compte 0 alors que le texte en contient), ce
    qu'un agregat ne montre pas ;
  - l'attribution frame a frame demanderait l'alignement force, donc une
    seconde source d'erreur qu'on ne saurait pas separer de la premiere.

Un compte nul sur une regle presente dans le texte est un VERDICT : cette regle
est morte. Un compte proche est un INDICE, pas une preuve.
"""
import os

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import argparse
import json
import math
import re
from collections import Counter
from pathlib import Path

import numpy as np

BASE = Path(__file__).parent
ANNOT = BASE / "data" / "quran_tajweed_rules" / "uthmani_tajweed.jsonl"


def _lire_wav(p):
    b = Path(p).read_bytes()
    d = np.frombuffer(b[44:44 + ((len(b) - 44) // 2) * 2], dtype="<i2")
    return (d.astype(np.float32) / 32768.0)


def normaliser(s):
    """Retire les diacritiques et les marques, pour apparier un mot du texte
    annote avec un mot de la cible du banc. Sans ca, la moindre difference de
    hamza ou de sukun ferait rater l'appariement."""
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"[ً-ْٓ-ٰٕۖ-ۭـ]", "", s)


def regles_attendues(mots_cible, sourate, depart):
    """Compte les regles des versets REELLEMENT recites.

    ── PIEGE CORRIGE (2026-07-31, avant toute conclusion) ──────────────────
    La premiere version appariait les versets par recouvrement de vocabulaire
    (« au moins la moitie des mots en commun »). Sur du texte coranique, ou les
    memes mots reviennent partout, elle a ramasse 398 VERSETS de 2:6 a 114:5
    pour un audio qui n'en contient qu'une vingtaine. Le denominateur etait
    gonfle d'un facteur ~15 et TOUS les ratios tombaient mecaniquement a
    0,1-0,2 : on aurait conclu « la tete n'emet presque rien » alors que le
    banc mesurait sa propre erreur.

    Ici : on part du verset de depart CONNU et on avance verset par verset
    jusqu'a couvrir le nombre de mots recites. Deterministe, aucun appariement.
    """
    versets = [json.loads(l) for l in open(ANNOT, encoding="utf-8")]
    par_cle = {v["verse_key"]: v["text"] for v in versets}

    compte, vus, n_mots = Counter(), [], 0
    v = depart
    while n_mots < len(mots_cible):
        cle = f"{sourate}:{v}"
        if cle not in par_cle:
            break
        t = par_cle[cle]
        n_mots += len(re.sub(r"<[^>]+>", "", t).split())
        vus.append(cle)
        for m in re.finditer(r"<tajweed class=([a-z_]+)>", t):
            compte[m.group(1)] += 1
        v += 1
    return compte, vus, n_mots


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--modele", required=True, help="model.onnx a 3 sorties")
    p.add_argument("--wav", default="/tmp/claude-1000/brut.wav")
    p.add_argument("--cible", default="/tmp/claude-1000/cible_v2.json")
    p.add_argument("--seuil", type=float, default=0.5,
                   help="probabilite au-dela de laquelle une regle est dite "
                        "presente sur une frame (sigmoide, donc INDEPENDANTE "
                        "par classe -- plusieurs regles peuvent depasser en "
                        "meme temps, c'est le but)")
    p.add_argument("--seuils", default=None,
                   help="seuils_tajwid.json a APPLIQUER (au lieu de --seuil). "
                        "Sert a mesurer une calibration sur un passage QU'ELLE "
                        "N'A PAS VU -- calibrer et evaluer sur le meme audio "
                        "garantit le resultat par construction.")
    p.add_argument("--part", default=None, choices=["1", "2"],
                   help="ne traiter que la 1re ou la 2e moitie de l'audio")
    p.add_argument("--calibrer", default=None,
                   help="ecrire ici un seuils_tajwid.json : un seuil PAR CLASSE "
                        "cale pour que le nombre d'emissions colle au texte "
                        "recite. Corrige la sur-emission due au pos_weight, "
                        "SANS reentrainer.")
    p.add_argument("--sourate", type=int, default=2)
    p.add_argument("--depart", type=int, default=6,
                   help="premier verset recite (DEPART du banc recette)")
    p.add_argument("--fenetre", type=float, default=20.0,
                   help="duree des tranches envoyees au modele (s). 20 s = la "
                        "borne haute du domaine d'entrainement (max_duration).")
    a = p.parse_args()

    import onnxruntime as ort
    import nemo.collections.asr as nemo_asr  # noqa: F401  (preprocessor)
    import torch
    from nemo.collections.asr.modules import AudioToMelSpectrogramPreprocessor

    pcm = _lire_wav(a.wav)
    if a.part == '1':
        pcm = pcm[:len(pcm)//2]
    elif a.part == '2':
        pcm = pcm[len(pcm)//2:]
    mots = json.loads(Path(a.cible).read_text(encoding="utf-8"))
    print(f"audio  : {len(pcm)/16000:.1f} s")
    print(f"cible  : {len(mots)} mots\n")

    mots_part = mots[:len(mots)//2] if a.part == '1' else (
        mots[len(mots)//2:] if a.part == '2' else mots)
    depart = a.depart
    if a.part == '2':
        _, v1, _ = regles_attendues(mots[:len(mots)//2], a.sourate, a.depart)
        depart = int(v1[-1].split(':')[1]) + 1
    attendu, versets, nm = regles_attendues(mots_part, a.sourate, depart)
    print(f"versets recites : {len(versets)}  ({versets[0]} … {versets[-1]})"
          f"  -> {nm} mots annotes pour {len(mots)} attendus")

    noms = json.loads((Path(a.modele).parent / "rules.json").read_text(
        encoding="utf-8"))

    prep = AudioToMelSpectrogramPreprocessor(
        sample_rate=16000, features=80, n_fft=512,
        window_size=0.025, window_stride=0.01, normalize="per_feature")
    prep.eval()

    sess = ort.InferenceSession(a.modele, providers=["CPUExecutionProvider"])
    sorties = [o.name for o in sess.get_outputs()]
    if "tajwid_logprobs" not in sorties:
        raise SystemExit(f"REFUS : ce modele n'a pas de tete tajwid ({sorties})")
    itaj = sorties.index("tajwid_logprobs")

    # On garde les logprobs bruts : ils servent DEUX fois -- au comptage au
    # seuil demande, et a la calibration par classe plus bas.
    tous = []
    frames_tot = 0
    pas = int(a.fenetre * 16000)
    for i in range(0, len(pcm), pas):
        bout = pcm[i:i + pas]
        if len(bout) < 16000:
            continue
        with torch.no_grad():
            mel, mel_len = prep(
                input_signal=torch.tensor(bout).unsqueeze(0),
                length=torch.tensor([len(bout)]))
        t = sess.run(None, {"audio_signal": mel.numpy(),
                            "length": mel_len.numpy().astype(np.int64)})[itaj][0]
        frames_tot += t.shape[0]
        tous.append(t)

    def compter(mat, seuils_log):
        """Une regle est COMPTEE UNE FOIS par plage contigue au-dessus du seuil,
        pas une fois par frame. Une ghunnah qui dure 5 frames est UNE ghunnah ;
        compter les frames gonflerait les regles longues (madd) et ecraserait
        les breves (qalqala)."""
        c = Counter()
        for t in mat:
            au = t > seuils_log
            for k in range(t.shape[1]):
                col = au[:, k]
                c[noms[k]] += int(np.sum(col[1:] & ~col[:-1]) + (1 if col[0] else 0))
        return c

    if a.seuils:
        cg = json.loads(Path(a.seuils).read_text(encoding='utf-8'))['seuils']
        seuils_log = np.array([math.log(cg.get(n, a.seuil)) for n in noms],
                              dtype=np.float32)
        print(f'seuils charges depuis {a.seuils}')
    else:
        seuils_log = np.full(len(noms), math.log(a.seuil), dtype=np.float32)
    obtenu = compter(tous, seuils_log)

    print(f"frames analysees : {frames_tot}\n")
    print(f"{'regle':24s} {'texte':>7s} {'emis':>7s} {'ratio':>8s}   verdict")
    print("-" * 68)
    morts, ok, bruit = [], [], []
    for n in noms:
        att, obt = attendu.get(n, 0), obtenu.get(n, 0)
        r = (obt / att) if att else float("inf") if obt else 1.0
        if att == 0 and obt == 0:
            v = "absente des deux"
        elif att > 0 and obt == 0:
            v = "MORTE -- jamais emise"; morts.append(n)
        elif att == 0 and obt > 0:
            v = "BRUIT -- emise sans raison"; bruit.append(n)
        elif 0.5 <= r <= 2.0:
            v = "coherent"; ok.append(n)
        else:
            v = "ecart fort"
        rs = "-" if r == float("inf") else f"{r:.2f}"
        print(f"{n:24s} {att:7d} {obt:7d} {rs:>8s}   {v}")

    print(f"\n{len(ok)}/{len(noms)} regles coherentes (ratio 0,5-2,0)")
    if morts:
        print(f"MORTES ({len(morts)}) : {', '.join(morts)}")
        print("  -> presentes dans le texte, JAMAIS emises. C'est un verdict, "
              "pas un indice.")
    if bruit:
        print(f"BRUIT ({len(bruit)}) : {', '.join(bruit)}")
    if a.calibrer:
        # CALIBRATION PAR CLASSE. Le pos_weight (jusqu'a 15) pousse le modele a
        # oser predire les classes rares -- c'est son role. Un seuil UNIQUE a
        # 0,5 ne le compense pas, d'ou la sur-emission mesuree ci-dessus,
        # d'autant plus forte que le pos_weight est eleve. On remonte donc le
        # seuil de chaque classe jusqu'a ce que son compte colle au texte.
        # Aucun reentrainement : c'est un defaut de CALIBRATION, pas d'appris.
        cal = {}
        for k, n in enumerate(noms):
            att = attendu.get(n, 0)
            if att == 0:
                cal[n] = 0.5
                continue
            bas, haut = math.log(0.5), math.log(0.999)
            for _ in range(40):
                mid = (bas + haut) / 2
                sl = seuils_log.copy(); sl[k] = mid
                if compter(tous, sl)[n] > att:
                    bas = mid          # trop d'emissions -> monter le seuil
                else:
                    haut = mid
            cal[n] = round(float(math.exp((bas + haut) / 2)), 4)
        Path(a.calibrer).write_text(json.dumps(
            {"description": "seuil par classe, cale sur audio reel pour que le "
                            "nombre d'emissions colle au texte recite",
             "source": f"{a.sourate}:{a.depart} .. {versets[-1]}, "
                       f"{frames_tot} frames",
             "seuils": cal}, ensure_ascii=False, indent=1), encoding="utf-8")
        sl = np.array([math.log(cal[n]) for n in noms], dtype=np.float32)
        apres = compter(tous, sl)
        coh = sum(1 for n in noms if attendu.get(n, 0) > 0
                  and 0.5 <= apres.get(n, 0) / attendu[n] <= 2.0)
        tot = sum(1 for n in noms if attendu.get(n, 0) > 0)
        print(f"\ncalibration ecrite -> {a.calibrer}")
        print(f"  coherentes APRES calibration : {coh}/{tot} "
              f"(avant : {len(ok)}/{tot})")
        print("  seuils : " + ", ".join(f"{n}={cal[n]:.2f}" for n in noms
                                        if attendu.get(n, 0) > 0))

    print("\n⚠️ Comptes sur tout le passage, PAS d'attribution frame a frame : "
          "une regle emise au bon nombre mais au mauvais endroit passerait pour "
          "correcte.")


if __name__ == "__main__":
    main()
