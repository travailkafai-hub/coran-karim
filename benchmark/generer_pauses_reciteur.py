#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ou le RECITATEUR s'arrete-t-il vraiment ? -> asset des coupes de palier.

── POURQUOI CE FICHIER EXISTE (2026-08-17) ────────────────────────────────────
Le coach « memorisation par palier » decoupait le verset tous les N mots
(`adultChunkWordCountProvider`, 6 par defaut). Constat utilisateur : le texte
s'arretait a `شَعَـٰٓئِرَ` pendant que l'audio allait jusqu'a `ٱللَّهِ` -- « je
veux la concordance », puis : « on decoupe selon le silence du reciteur, apres
on cherche le texte ».

MESURE QUI LUI DONNE RAISON (400 versets, 7 587 frontieres entre mots) :
  - 29,5 % des frontieres n'ont AUCUN creux d'energie franc -- les mots y sont
    LIES, il n'existe aucune frontiere acoustique a cet endroit ;
  - 37,5 % des bornes debordent sur le mot suivant (p90 = +240 ms).
Couper tous les N mots tombe donc regulierement en plein enchainement : c'est
la cause du decalage texte/audio, pas un defaut de reglage.

Les marques de WAQF ont ete envisagees puis ecartees, chiffres a l'appui :
`quran_waqf.json` ne couvre que 2 640 versets sur 6 236 (42 %), et ses types
sont ambigus pour cet usage (`wasl_awla` = mieux vaut CONTINUER, 1 682
occurrences ; `mamnu` = arret INTERDIT, 68). Le silence reel, lui, est
mesurable partout.

── CE QU'ON DETECTE, ET COMMENT ───────────────────────────────────────────────
PAS un silence : la mesure ci-dessous montre qu'il n'y en a pas. On vise des
paliers d'environ [TAILLE_UNITE] mots, puis on fait GLISSER chaque coupe de
+-[RAYON_MOTS] mot vers la frontiere de PLUS FAIBLE ENERGIE -- l'endroit ou le
recitateur ralentit le plus, donc ou l'oreille entend la fin d'une proposition.
Grain de 10 ms (le hop mel), soit huit fois plus fin que la frame CTC de 80 ms
qui a produit les bornes.

Verifie sur le cas de reference 22:32 :
    palier 1 : ذَٰلِكَ وَمَن يُعَظِّمْ شَعَـٰٓئِرَ ٱللَّهِ
    palier 2 : فَإِنَّهَا مِن تَقْوَى ٱلْقُلُوبِ
-- la coupe tombe apres `ٱللَّهِ`, exactement la ou l'utilisateur la situe, et
la proposition suivante demarre sur `فَإِنَّهَا`.

Sortie : {"s:a": [i, j, ...]} -- les index de mots APRES lesquels un palier
s'arrete. Index dans le meme decoupage que
`word_segments_mp3quran_afasy.json` (verifie equivalent au split Dart sur les
6 236 versets, cf. AUDIT_EQUIVALENCES_ECRITURE §3ter). Une liste VIDE signifie
un verset plus court que l'unite : il reste entier.

Usage :
    python generer_pauses_reciteur.py --demo 22:32,85:16,2:2
    python generer_pauses_reciteur.py --toutes
"""
import argparse
import io
import json
import wave
from pathlib import Path

import numpy as np

BASE = Path(__file__).parent
SEGMENTS = BASE.parent / "app/assets/data/word_segments_mp3quran_afasy.json"
VERSES = BASE.parent / "app/assets/data/quran_verses.json"
WAV_DIR = BASE / "data" / "train_wav_local" / "Alafasy_mp3quran"
SORTIE = BASE.parent / "app/assets/data/coupes_palier_afasy.json"

# ── FILTRE DES ARRETS INTERDITS (2026-09-01) ───────────────────────────────
# Le critere d'energie ignore la SYNTAXE : il place une coupe la ou la voix
# retombe, y compris sur un waqf `mamnu` (لا), ou le tajwid INTERDIT de
# s'arreter. Mesure du 2026-09-01 sur le fichier alors livre : 14 coupes
# tombaient exactement sur un `mamnu` -- 2:25 mot 17, 2:174 mot 11,
# 5:3 mot 56, 5:106 mot 42, entre autres.
#
# Ces 14 coupes faisaient s'arreter un palier de memorisation la ou l'eleve
# ne doit precisement jamais s'arreter, dans une application qui enseigne le
# tajwid. On les retire.
#
# Pourquoi SEULEMENT `mamnu`, et pas les autres types (decision utilisateur
# du 2026-09-01, apres mesure) : les waqf et l'energie sont largement
# independants (31 % de coincidence exacte). Ajouter les 1 788 arrets
# canoniques manquants ferait couper le texte la ou le reciteur ne marque
# aucune pause -- soit exactement le defaut 22:32 qui a motive ce fichier.
# `mamnu` est le seul cas ou le waqf dit « NON » : il ne cree aucune coupe,
# il en supprime, donc il ne peut pas casser la concordance texte/audio.
WAQF = json.load(io.open(BASE.parent / "app/assets/data/quran_waqf.json",
                         encoding="utf-8"))


def sans_arrets_interdits(cle, coupes):
    """Retire les coupes tombant sur un waqf `mamnu` (لا, arret interdit)."""
    marques = WAQF.get(cle)
    if not marques:
        return coupes
    return [c for c in coupes if marques.get(str(c)) != "mamnu"]



BLOC_MS = 10.0

# ── CE QUI A ETE TESTE, ET POURQUOI C'EST L'ENERGIE QUI RESTE (2026-08-17) ────
# Trois criteres essayes sur le cas de reference 22:32, ou l'utilisateur situe
# l'arret apres `ٱللَّهِ` :
#
#   1. SILENCE du recitateur -- ECARTE. Mesure sur 22:32 : l'energie a CHAQUE
#      frontiere vaut 0,26 a 1,07 fois la moyenne. Aucun silence : Al-Afasy
#      recite le verset d'un seul souffle (13,7 s). Couper sur le silence
#      donnait UN palier par verset, verifie sur 4 versets de demo.
#   2. Marques de WAQF -- ECARTE. `quran_waqf.json` ne couvre que 2 640
#      versets sur 6 236 (42 %), et 22:32 n'en porte AUCUNE.
#   3. SOUKOUN final -- ECARTE, mesure sur les 75 775 frontieres du Coran :
#      soukoun -> waqf licite dans 3,6 % des cas seulement, et 88 % des waqf
#      n'ont pas de soukoun. Les deux sont quasi independants -- le soukoun est
#      morphologique (`يُعَظِّمْ` en porte un en plein milieu de phrase), l'arret
#      est syntaxique.
#
# Reste l'ENERGIE. Le recitateur ne s'arrete pas, mais il RALENTIT a la fin
# d'une proposition -- et c'est cette intention que l'oreille entend comme un
# point d'arret possible. Sur 22:32, `ٱللَّهِ` est a 0,49 x la moyenne, le
# minimum de son voisinage : la coupe y tombe juste.
#
# ⚠️ RAYON_MOTS calibre sur UN cas. A +-1 mot la coupe tombe sur `ٱللَّهِ` ;
# a +-2 elle glisse sur `تَقْوَى` (0,26 x, encore plus bas mais grammaticalement
# absurde). C'est donc un compromis assume, pas une valeur derivee : plus la
# fenetre est large, plus on risque de suivre un creux acoustique contre le
# sens.
TAILLE_UNITE = 6      # taille VISEE d'un palier, en mots
RAYON_MOTS = 1        # de combien la coupe peut glisser pour trouver le creux
RAYON_MS = 120.0      # demi-fenetre d'energie mesuree autour d'une borne


def lire(f):
    w = wave.open(str(f))
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    w.close()
    return x.astype(np.float64) / 32768.0


def enveloppe(pcm):
    n = int(BLOC_MS * 16)
    nb = len(pcm) // n
    if nb == 0:
        return np.array([])
    return np.sqrt((pcm[: nb * n].reshape(nb, n) ** 2).mean(axis=1))


def energie_a(env, borne_ms):
    """Energie moyenne autour de [borne_ms], rapportee a celle du verset.

    Rapportee, et non brute : un verset recite fort et un verset recite doux
    ne se comparent pas en absolu. C'est le RELIEF qui porte l'information,
    pas le niveau.
    """
    if len(env) == 0:
        return 1.0
    demi = max(1, int(RAYON_MS / BLOC_MS))
    c = int(borne_ms / BLOC_MS)
    lo, hi = max(0, c - demi), min(len(env), c + demi)
    if hi <= lo:
        return 1.0
    moy = env.mean()
    return float(env[lo:hi].mean() / moy) if moy > 0 else 1.0


def coupes_du_verset(env, bornes):
    """Index des mots APRES lesquels un palier s'arrete.

    Vise des paliers de [TAILLE_UNITE] mots, puis fait GLISSER chaque coupe
    de +-[RAYON_MOTS] vers la frontiere de plus faible energie -- celle ou le
    recitateur ralentit le plus. Le dernier mot du verset n'est jamais une
    coupe : le verset se termine, il n'y a rien apres.
    """
    n = len(bornes)
    if n <= TAILLE_UNITE:
        return []
    energies = [energie_a(env, bornes[i][1]) for i in range(n - 1)]
    coupes, cible = [], TAILLE_UNITE - 1
    while cible < n - 1:
        lo = max(0, cible - RAYON_MOTS)
        hi = min(n - 2, cible + RAYON_MOTS)
        # Jamais en arriere d'une coupe deja posee : les paliers doivent
        # rester dans l ordre et ne jamais se chevaucher.
        if coupes:
            lo = max(lo, coupes[-1] + 1)
        if lo > hi:
            cible += TAILLE_UNITE
            continue
        meilleur = min(range(lo, hi + 1), key=lambda i: energies[i])
        coupes.append(meilleur)
        cible = meilleur + TAILLE_UNITE
    return coupes


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--demo", help="ex: 22:32,85:16")
    g.add_argument("--toutes", action="store_true")
    a = ap.parse_args()

    segs = json.load(io.open(SEGMENTS, encoding="utf-8"))
    mots_par_verset = {}
    if a.demo:
        vs = json.load(io.open(VERSES, encoding="utf-8"))
        mots_par_verset = {v["verse_key"]: v["text_uthmani"].split() for v in vs}

    cles = a.demo.split(",") if a.demo else sorted(
        segs, key=lambda k: (int(k.split(":")[0]), int(k.split(":")[1])))

    out, n_ok, n_sans_audio = {}, 0, 0
    for cle in cles:
        s, ay = cle.split(":")
        wav = WAV_DIR / f"{s}_{ay}.wav"
        bornes = segs.get(cle)
        if bornes is None or not wav.exists():
            n_sans_audio += 1
            continue
        env = enveloppe(lire(wav))
        if len(env) < 10:
            continue
        coupes = coupes_du_verset(env, bornes)
        coupes = sans_arrets_interdits(cle, coupes)
        out[cle] = coupes
        n_ok += 1
        if a.demo:
            mots = mots_par_verset.get(cle, [])
            print(f"\n=== {cle} ===")
            grp, debut = [], 0
            for c in coupes + [len(bornes) - 1]:
                grp.append(" ".join(mots[debut:c + 1]) if mots else f"[{debut}..{c}]")
                debut = c + 1
            for k, g_ in enumerate(grp, 1):
                print(f"  palier {k} : {g_}")

    if a.toutes:
        json.dump(out, io.open(SORTIE, "w", encoding="utf-8"),
                  ensure_ascii=False, separators=(",", ":"))
        tot = sum(len(v) for v in out.values())
        print(f"{n_ok} versets, {tot} coupes ({tot/max(n_ok,1):.1f} par verset) "
              f"-> {SORTIE}")
        if n_sans_audio:
            print(f"  {n_sans_audio} verset(s) sans audio local, ignores")


if __name__ == "__main__":
    main()
