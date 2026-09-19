"""Banc des ERREURS QUE FONT VRAIMENT LES RECITATEURS.

── POURQUOI CE BANC REMPLACE LE PRECEDENT ──────────────────────────────────

`campagne_paliers_20260915` etait fait a 72 % de coupures, insertions et
omissions. Critique de l'utilisateur, le 16/09, et elle est juste : un
recitateur ne coupe pas un mot en plein milieu. Il dit `ٱلضَّالُّونَ` au lieu de
`ٱلضَّالِّينَ`, ou `وَ` au lieu de `ثُمَّ`. Mesure qui lui donne raison : sur le
banc precedent, la detection tombe a 66 % toutes familles confondues mais monte
a **82 % sur les seules substitutions** -- le chiffre bas venait des fautes
artificielles, pas de la chaine.

Ce banc ne fabrique donc QUE des substitutions par une forme voisine
REELLEMENT PRONONCEE ailleurs dans le corpus :

  - FLEXION      `ٱلْجِبَالُ` -> `وَٱلْجِبَالَ`, meme racine, desinence differente ;
  - PARTICULE    `ٱرْجِعِ` -> `فَٱرْجِعِ`, ou une conjonction pour une autre.

L'audio du remplacant vient d'un endroit ou il est vraiment recite : aucun son
n'est synthetise, aucun mot n'est tronque.

── LA QUESTION QUE CE BANC POSE ────────────────────────────────────────────

Le modele est-il BIAISE PAR LE CONTEXTE ? Sur la Fatiha, entendant
`ٱلضَّالُّونَ` la ou le texte attend `ٱلضَّالِّينَ`, va-t-il « corriger » vers la
forme canonique parce qu'il connait le verset ? C'est le biais canonique que le
projet documente depuis juillet (« quand le modele est CONVAINCU du canonique,
forced == free, gop = 0, donc VERT A TORT ») -- jamais mesure sur des
substitutions de flexion.
"""
from __future__ import annotations

import argparse
import json
import random
import unicodedata
from collections import defaultdict

import campagne_100x20 as base
import campagne_100x20_dense30 as dense

q = base.q
ROOT = q.ROOT
OUT = ROOT / "benchmark" / "campagne_erreurs_reelles_20260916"


def squelette(mot: str) -> str:
    """Lettres de base : sans harakat, sans kashida, alif unifie."""
    return "".join(
        c for c in unicodedata.normalize("NFKD", mot)
        if unicodedata.category(c)[0] != "M" and c != "ـ"
    ).replace("ٱ", "ا")


def distance_un(a: str, b: str) -> bool:
    if a == b or abs(len(a) - len(b)) > 1:
        return False
    i = j = e = 0
    while i < len(a) and j < len(b):
        if a[i] != b[j]:
            e += 1
            if e > 1:
                return False
            if len(a) > len(b):
                i += 1
                continue
            if len(a) < len(b):
                j += 1
                continue
        i += 1
        j += 1
    return e + (len(a) - i) + (len(b) - j) <= 1


def meme_famille(a: str, b: str) -> str | None:
    """Rend le TYPE de confusion, ou None si les deux mots n'ont rien a voir.

    On exige une vraie parente : soit l'un est l'autre precede d'une particule
    (`فَ`, `وَ`, `لِ`, `بِ`, `كَ`), soit ils partagent une racine longue et ne
    different que par la fin (flexion). Sans ce filtre, `إِذْ` et `أَمْ` sortent
    a distance 1 alors que ce sont deux mots sans rapport -- remplacer l'un par
    l'autre ne serait pas une erreur de recitateur mais du bruit.
    """
    if len(a) >= 3 and len(b) == len(a) + 1 and b[1:] == a and b[0] in "فولبك":
        return "particule_ajoutee"
    if len(b) >= 3 and len(a) == len(b) + 1 and a[1:] == b and a[0] in "فولبك":
        return "particule_retiree"
    if len(a) >= 4 and len(b) >= 4 and a[:-1] == b[:-1] and a[-1] != b[-1]:
        return "flexion_finale"
    if len(a) >= 5 and len(b) >= 5 and a[:3] == b[:3] and distance_un(a, b):
        return "flexion_interne"
    return None


def prepare(taux: float, versets: int):
    scenarios = dense.load_scenarios()
    OUT.mkdir(parents=True, exist_ok=True)

    # Index de TOUT le corpus disponible : squelette -> occurrences reellement
    # prononcees. C'est ce qui permet de prendre un vrai audio pour le
    # remplacant, au lieu d'en fabriquer un.
    par_squelette: dict[str, list] = defaultdict(list)
    for reciter, _, _, records in scenarios:
        for rec in records:
            for k, mot in enumerate(rec["words"]):
                par_squelette[squelette(mot)].append(
                    dict(reciter=reciter, record=rec, index=k, mot=mot))

    cases = []
    numero = 0
    for reciter, surah, first, records in scenarios:
        numero += 1
        rng = random.Random(20260916 + numero)
        records = records[:versets]
        expected, audio, operations, timeline = [], [], [], []
        total = sum(len(r["words"]) for r in records)
        budget = max(1, round(taux * total))

        for rec in records:
            base_index = len(expected)
            expected.extend(rec["words"])
            n = len(rec["words"])
            timeline.append(dict(verse=rec["key"], start_ms=len(audio) / 16,
                                 word_start=base_index, word_count=n))
            changed = list(rec["samples"])
            delta = 0
            # Candidats : mots de CE verset qui ont un voisin reel ailleurs.
            candidats = []
            for i, mot in enumerate(rec["words"]):
                sq = squelette(mot)
                for autre, occ in par_squelette.items():
                    fam = meme_famille(sq, autre)
                    if not fam:
                        continue
                    # jamais le mot lui-meme, jamais le meme emplacement
                    bons = [o for o in occ if squelette(o["mot"]) != sq]
                    if bons:
                        candidats.append((i, fam, rng.choice(bons)))
                        break
            rng.shuffle(candidats)
            pris = []
            for i, fam, donneur in candidats:
                if len(pris) >= max(1, round(taux * n)) or budget <= 0:
                    break
                if any(abs(i - j) < 2 for j in pris):
                    continue
                seg = rec["segments"][i]
                deb, fin = int(seg[2] * 16), min(len(rec["samples"]), int(seg[3] * 16))
                remplacement = dense.clip(donneur["record"], donneur["index"])
                op = dict(verse=rec["key"], family=fam, word_index=i,
                          expected=rec["words"][i],
                          affected_word_indices=[base_index + i],
                          replacement_text=donneur["mot"],
                          donor_verse=donneur["record"]["key"],
                          donor_word=donneur["index"],
                          difference=fam,
                          source_start_sample=deb, source_end_sample=fin,
                          replacement_samples=len(remplacement),
                          output_edit_start_ms=(len(audio) + deb + delta) / 16)
                changed[deb + delta:fin + delta] = remplacement
                delta += len(remplacement) - (fin - deb)
                operations.append(op)
                pris.append(i)
                budget -= 1
            audio.extend(changed)
            audio.extend(q.silence(350))

        case_id = f"R{900 + numero:03d}"
        wav = OUT / "wav" / f"{case_id}.wav"
        q.write_wav(wav, audio)
        cases.append(dict(case_id=case_id, family="erreurs_reelles",
                          taux_reel=len(operations) / max(1, len(expected)),
                          reciter=reciter, surah=surah, depart=first,
                          verse_count=len(records), riwaya="hafs",
                          expected_words=expected,
                          duration_seconds=len(audio) / 16000, wav=str(wav),
                          sha256=q.sha256(wav), operations=operations,
                          timeline=timeline,
                          sources=[dict(key=r["key"], words=r["words"]) for r in records]))
        fam = defaultdict(int)
        for o in operations:
            fam[o["family"]] += 1
        print(f"{case_id} {surah}:{first} {len(operations)} erreurs / {len(expected)} mots "
              f"({len(operations)/max(1,len(expected)):.0%})  {dict(fam)}", flush=True)

    base.save(OUT / "manifest.json", dict(
        seed=20260916, cases=cases,
        limitations=[
            "Uniquement des SUBSTITUTIONS par une forme voisine reellement prononcee.",
            "Aucun mot tronque, aucun son synthetise, aucune insertion.",
            "Le remplacant vient d'un autre passage du meme corpus : sa prosodie "
            "differe, c'est la limite connue du montage.",
            "Hafs uniquement.",
        ]))
    tot = sum(len(c["operations"]) for c in cases)
    mots = sum(len(c["expected_words"]) for c in cases)
    print(f"PREPARED {len(cases)} cas, {tot} erreurs / {mots} mots ({tot/mots:.1%}), "
          f"{sum(c['duration_seconds'] for c in cases)/60:.1f} min")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=["prepare", "run"])
    p.add_argument("--serial", default="R3CY20XW7TD")
    p.add_argument("--taux", type=float, default=0.12)
    p.add_argument("--versets", type=int, default=20)
    a = p.parse_args()
    if a.action == "prepare":
        prepare(a.taux, a.versets)
    else:
        base.OUT = OUT
        base.run(a.serial)
