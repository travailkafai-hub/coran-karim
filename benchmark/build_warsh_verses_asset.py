#!/usr/bin/env python3
"""Construit `app/assets/data/quran_verses_warsh.json` -- le texte Warsh de
l'application, dans EXACTEMENT la meme forme que l'asset Hafs existant.

POURQUOI DES CLES (sourate, verset) DE MEME DECOUPE QUE L'ASSET HAFS
-------------------------------------------------------------------
Ce n'est pas une comparaison au Hafs, c'est une contrainte de l'AUDIO.
Le seul audio Warsh disponible verset par verset (everyayah.com, deux
recitateurs complets) nomme ses fichiers `SSSAAA.mp3` avec la numerotation du
mushaf du Caire -- verifie le 2026-08-12 : `002286.mp3` existe et dure 75,8 s
alors que le mushaf Warsh imprime s'arrete a 285 versets. Si l'asset texte
utilisait la numerotation du mushaf Warsh (6 214 versets), plus AUCUN fichier
audio ne tomberait en face de son texte : ni la lecture, ni la correction d'un
mot, ni les timings. Tout le reste de l'app (portions, statistiques, signets,
records) suit gratuitement puisque les cles ne bougent pas.

Le texte AFFICHE et JUGE reste integralement le texte Warsh du KFGQPC : seuls
les ENDROITS OU L'ON COUPE en versets viennent de l'autre decoupe. C'est une
decision de decoupage, pas une alteration du texte.

METHODE
-------
Pour chaque sourate : on met bout a bout les mots du texte Warsh, bout a bout
ceux du texte de reference, on aligne les deux suites (`difflib`, 99,16 % des
mots ont un squelette identique -- mesure du 2026-08-12), et on coupe la suite
Warsh la ou la reference change de verset. La Bismillah 1:1, jamais jugee par
l'app (decision 2026-07-20) et absente du decompte Warsh, est reprise telle
quelle.

SOURCE : https://github.com/thetruetruth/quran-data-kfgqpc (warsh/data,
KFGQPC = Complexe du Roi Fahd, version 0.10). A telecharger a cote de ce
script, ou passer son chemin en argument.

Usage :
    python3 build_warsh_verses_asset.py [chemin/warshData_v10.json]
"""
import difflib
import json
import re
import sys
import unicodedata
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
HAFS = RACINE / "app" / "assets" / "data" / "quran_verses.json"
SORTIE = RACINE / "app" / "assets" / "data" / "quran_verses_warsh.json"
SOURCE_URL = ("https://raw.githubusercontent.com/thetruetruth/"
              "quran-data-kfgqpc/main/warsh/data/warshData_v10.json")

# ── NORMALISATION POUR L'ALIGNEMENT SEULEMENT ───────────────────────────────
# Ne touche JAMAIS le texte ecrit dans l'asset : sert uniquement a decider si
# deux mots « sont le meme mot » pendant l'alignement. Sans le YEH BARREE
# (U+06D2, 2 996 occurrences cote Warsh) et l'ALEF WASLA (U+0671, 13 483 cote
# Hafs), on mesure son propre normaliseur et pas les deux textes : l'ecart
# apparent passe de 0,84 % a 6,25 % (mesure du 2026-08-12).
LETTRES = set("ابتثجحخدذرزسشصضطظعغفقكلمنهويءأإآؤئىة")
EQUIV = {
    "ٱ": "ا",  # ALEF WASLA (Hafs) -> alef
    "ے": "ى",  # YEH BARREE (Warsh) -> ya
    "ى": "ى", "ي": "ى",
    "آ": "ا", "أ": "ا", "إ": "ا",
    "ؤ": "و", "ئ": "ى", "ة": "ه",
}
# Chiffres arabo-indiens : le numero de verset est COLLE au texte dans le jeu
# KFGQPC (« ...العلمين ١ »), il ne fait pas partie du verset.
A_RETIRER = re.compile(r"[٠-٩۝۞ ‏]")


def squelette(mot: str) -> str:
    mot = "".join(EQUIV.get(c, c) for c in mot)
    return "".join(c for c in mot if c in LETTRES)


def mots(texte: str):
    """(squelette, mot original) pour chaque mot reellement prononce."""
    texte = A_RETIRER.sub(" ", texte)
    out = []
    for brut in texte.split():
        s = squelette(brut)
        if s:
            out.append((s, brut))
    return out


def charger_warsh(chemin: Path):
    if not chemin.exists():
        sys.exit(f"Source Warsh introuvable : {chemin}\n"
                 f"La telecharger depuis {SOURCE_URL}")
    # utf-8-sig : le fichier KFGQPC porte un BOM.
    lignes = json.loads(chemin.read_text(encoding="utf-8-sig"))
    par_sourate = {}
    for l in lignes:
        par_sourate.setdefault(int(l["sura_no"]), []).append(
            (int(l["aya_no"]), l["aya_text"]))
    return {s: [t for _, t in sorted(v)] for s, v in par_sourate.items()}


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "warshData_v10.json"
    warsh = charger_warsh(src)
    hafs = json.loads(HAFS.read_text(encoding="utf-8"))

    # L'asset de reference, groupe par sourate, dans l'ordre.
    ref = {}
    for v in hafs:
        s, a = v["verse_key"].split(":")
        ref.setdefault(int(s), []).append((int(a), v))
    for s in ref:
        ref[s].sort(key=lambda x: x[0])

    sortie = []
    total_mots_w = total_places = 0
    anomalies = []

    for s in range(1, 115):
        versets_ref = ref[s]
        flux_w = []
        for t in warsh[s]:
            flux_w += mots(t)
        # La Bismillah 1:1 n'existe pas dans le decompte Warsh : on la reprend
        # telle quelle depuis la reference (jamais jugee de toute facon).
        debut = 0
        if s == 1:
            premier = versets_ref[0][1]
            sortie.append(dict(premier))
            debut = 1

        flux_ref = []
        bornes = []  # index de fin (exclu) de chaque verset dans flux_ref
        for _, v in versets_ref[debut:]:
            flux_ref += [m[0] for m in mots(v["text_uthmani"])]
            bornes.append(len(flux_ref))

        # Alignement des deux suites de mots.
        sm = difflib.SequenceMatcher(None, flux_ref,
                                     [m[0] for m in flux_w], autojunk=False)
        # corresp[i] = position dans flux_w du mot de reference i (ou None)
        corresp = [None] * len(flux_ref)
        for i1, j1, taille in sm.get_matching_blocks():
            for k in range(taille):
                corresp[i1 + k] = j1 + k

        # Chaque borne de verset devient une coupe dans le flux Warsh. Si le
        # mot de borne n'a pas de correspondant direct (divergence reelle), on
        # remonte au dernier mot aligne connu : la coupe glisse d'un mot au
        # pire, jamais d'un verset.
        coupes = []
        dernier = 0
        for b in bornes:
            pos = None
            for i in range(b - 1, -1, -1):
                if corresp[i] is not None:
                    pos = corresp[i] + 1 + (b - 1 - i)
                    break
            if pos is None or pos < dernier:
                pos = dernier
            coupes.append(min(pos, len(flux_w)))
            dernier = coupes[-1]
        coupes[-1] = len(flux_w)  # le dernier verset prend tout le reste

        precedent = 0
        for (num, v), fin in zip(versets_ref[debut:], coupes):
            morceau = flux_w[precedent:fin]
            precedent = fin
            texte = " ".join(m[1] for m in morceau)
            if not texte.strip():
                anomalies.append(f"{s}:{num} vide")
            neuf = dict(v)
            neuf["text_uthmani"] = texte
            # Le tajweed colore est un balisage HTML derive du texte HAFS : le
            # garder ici afficherait des couleurs posees sur d'autres lettres.
            neuf["text_uthmani_tajweed"] = None
            sortie.append(neuf)
            total_places += len(morceau)
        total_mots_w += len(flux_w)

    SORTIE.write_text(json.dumps(sortie, ensure_ascii=False), encoding="utf-8")

    print(f"versets ecrits        : {len(sortie)} (reference : {len(hafs)})")
    print(f"mots Warsh places     : {total_places} / {total_mots_w}")
    print(f"anomalies             : {len(anomalies)}")
    for a in anomalies[:20]:
        print("   ", a)
    print(f"-> {SORTIE}  ({SORTIE.stat().st_size / 1e6:.1f} Mo)")
    if total_places != total_mots_w or anomalies:
        sys.exit("ECHEC : des mots ont ete perdus ou un verset est vide.")


if __name__ == "__main__":
    main()
