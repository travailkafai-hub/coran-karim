# -*- coding: utf-8 -*-
"""Reduit les explications DEJA GENEREES : moins de paliers, et seulement les
sources dont les droits sont eteints.

POURQUOI CE SCRIPT PLUTOT QU'UNE REGENERATION (2026-08-09)
-----------------------------------------------------------
`build_explanation_cascade.py` part du corpus de tafsirs (data/tafsir/, des
gigaoctets) et met longtemps. Or les deux sorties existent deja. Retirer des
sources et des paliers est une simple projection de ces fichiers : on lit, on
jette ce qu'on ne garde pas, on reecrit. Aucune donnee nouvelle n'est
necessaire, donc aucune raison de repayer la generation.

Le fichier d'origine n'est JAMAIS modifie : la sortie porte un autre nom. Si
une autorisation arrive plus tard, on relance avec une liste elargie et on
retrouve le contenu -- rien n'a ete detruit.

CE QUE FILTRE CE SCRIPT, ET POURQUOI
------------------------------------
Deux filtres independants, cumulables :

1. LES DROITS. Un tafsir dont l'auteur est mort il y a des siecles est libre ;
   un tafsir moderne ne l'est pas. Piege a ne pas manquer : **une TRADUCTION
   est une oeuvre a part entiere**, meme quand l'original est libre. Traduire
   Ibn Kathir (mort en 1373) en anglais aujourd'hui produit une oeuvre
   moderne, protegee. C'est pour cette raison que la liste permise ci-dessous
   ne contient QUE de l'arabe : toutes les entrees fr/en du corpus sont des
   traductions modernes, sans exception.

2. LES PALIERS. Le palier 3 n'etait deja pas embarque (fichiers separes,
   recuperes a la demande). Restent 1 et 2 ; `--paliers 1` ne garde que le
   premier, ce qui divise a peu pres par deux le poids embarque et simplifie
   l'affichage (une explication au lieu d'une cascade).

Usage :
    python filtrer_explications.py                    # paliers 1+2, sources libres
    python filtrer_explications.py --paliers 1        # palier 1 seulement
    python filtrer_explications.py --autorise "Al-Mukhtasar" "Montada"
                                                      # apres reception d'un accord
"""
import argparse
import io
import json
from pathlib import Path

RACINE = Path(__file__).parent
SCIENCES = RACINE / "data" / "quran_sciences"

# ── Sources dont les droits sont ETEINTS ─────────────────────────────────
# Compare a `TAFSIR_DISPLAY` de build_explanation_cascade.py. On apparie sur
# une SOUS-CHAINE du champ "source" ecrit dans le JSONL, pas sur le slug : le
# fichier genere ne contient que le libelle affiche.
#
# Auteurs et dates de deces -- c'est la date qui decide, pas la notoriete :
#   at-Tabari 923 | al-Baghawi 1122 | ar-Razi 1210 | al-Mahalli/as-Suyuti
#   1459/1505 (Jalalayn) | Ibn Kathir 1373 | Ibn Abbas (Tanwir al-Miqbas,
#   attribution ancienne) | ar-Raghib al-Isfahani ~1108 (Mufradat) |
#   Ibn al-Jawzi 1201 (Nuzhat al-A'yun).
LIBRES = [
    "Tabari",
    "Baghawi",
    "Razi",
    "Jalalayn",
    "Ibn Kathir",
    "Ibn Abbas",
    "Mufradat",       # explications de MOTS
    "Nuzhat",         # explications de MOTS
]

# ── Sources ECARTEES, et la raison ───────────────────────────────────────
# Gardees en clair plutot que supprimees : sans cette liste, un futur lecteur
# ne peut pas distinguer « jamais eu » de « retire volontairement », et le
# travail de verification serait a refaire.
#   al-Muyassar ......... Complexe du Roi Fahd, oeuvre moderne
#   as-Saadi ............ mort en 1957
#   Ibn Ashur ........... mort en 1973
#   Maarif ul-Quran ..... Mufti Muhammad Shafi, mort en 1976
#   Tazkirul Quran ...... Wahiduddin Khan, mort en 2021
#   al-Mukhtasar / al-Mokhtasar ... Markaz Tafsir, oeuvre moderne
#   Montada ............. Montada Islamic Foundation, oeuvre moderne
#   TOUTES les entrees fr/en ...... traductions modernes (cf. en-tete)


def permise(source: str, autorisees) -> bool:
    """Vrai si le libelle de source est libre de droits, ou explicitement
    autorise par l'utilisateur (accord recu, passe en ligne de commande)."""
    return any(m.lower() in source.lower() for m in list(LIBRES) + list(autorisees))


def filtrer_paliers(par_palier: dict, paliers_max: int, autorisees) -> dict:
    """Projette {"1": [entrees], "2": [...]} sur les paliers retenus, en ne
    gardant que les sources permises. Un palier vide disparait."""
    sortie = {}
    for palier, entrees in par_palier.items():
        if not palier.isdigit() or int(palier) > paliers_max:
            continue
        gardees = [e for e in entrees if permise(e.get("source", ""), autorisees)]
        if gardees:
            sortie[palier] = gardees
    return sortie


def traiter_versets(src: Path, dst: Path, paliers_max: int, autorisees):
    """ayah_explanations.jsonl : {"verse_key", "<langue>": {"<palier>": [...]}}"""
    gardes = vides = 0
    langues = {}
    with io.open(src, encoding="utf-8") as f, io.open(dst, "w", encoding="utf-8") as o:
        for ligne in f:
            ligne = ligne.strip()
            if not ligne:
                continue
            e = json.loads(ligne)
            out = {"verse_key": e["verse_key"]}
            for langue, par_palier in e.items():
                if langue == "verse_key" or not isinstance(par_palier, dict):
                    continue
                retenu = filtrer_paliers(par_palier, paliers_max, autorisees)
                if retenu:
                    out[langue] = retenu
                    langues[langue] = langues.get(langue, 0) + 1
            # Un verset sans aucune explication permise n'est PAS ecrit : une
            # entree vide ferait croire a l'app qu'elle a quelque chose a
            # afficher, et produirait une bulle vide au lieu du repli prevu.
            if len(out) > 1:
                o.write(json.dumps(out, ensure_ascii=False) + "\n")
                gardes += 1
            else:
                vides += 1
    return gardes, vides, langues


def traiter_mots(src: Path, dst: Path, paliers_max: int, autorisees):
    """word_explanations.jsonl : {"verse_key", "words": [{..., "<langue>": {...}}]}"""
    gardes = vides = 0
    with io.open(src, encoding="utf-8") as f, io.open(dst, "w", encoding="utf-8") as o:
        for ligne in f:
            ligne = ligne.strip()
            if not ligne:
                continue
            e = json.loads(ligne)
            mots = []
            for mot in e.get("words", []):
                copie = {k: v for k, v in mot.items() if not isinstance(v, dict)}
                garde_un = False
                for langue, par_palier in mot.items():
                    if not isinstance(par_palier, dict):
                        continue
                    retenu = filtrer_paliers(par_palier, paliers_max, autorisees)
                    if retenu:
                        copie[langue] = retenu
                        garde_un = True
                if garde_un:
                    mots.append(copie)
            if mots:
                o.write(json.dumps({"verse_key": e["verse_key"], "words": mots},
                                   ensure_ascii=False) + "\n")
                gardes += 1
            else:
                vides += 1
    return gardes, vides, {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--paliers", type=int, default=2,
                    help="palier maximum conserve (1 = le plus concis)")
    ap.add_argument("--autorise", nargs="*", default=[],
                    help="libelles de sources autorisees en plus des libres "
                         "(a utiliser QUAND un accord ecrit est recu)")
    ap.add_argument("--suffixe", default="_libre",
                    help="suffixe du fichier de sortie")
    args = ap.parse_args()

    if args.autorise:
        print("Sources autorisees en plus des libres : %s" % ", ".join(args.autorise))

    total_avant = total_apres = 0
    for nom, traite in (("ayah_explanations", traiter_versets),
                        ("word_explanations", traiter_mots)):
        src = SCIENCES / ("%s.jsonl" % nom)
        if not src.exists():
            print("ABSENT : %s -- ignore" % src)
            continue
        dst = SCIENCES / ("%s%s.jsonl" % (nom, args.suffixe))
        gardes, vides, langues = traite(src, dst, args.paliers, args.autorise)
        avant, apres = src.stat().st_size, dst.stat().st_size
        total_avant += avant
        total_apres += apres
        print("%s : %d lignes gardees, %d vidées -- %.1f Mo -> %.1f Mo (%.0f %% en moins)"
              % (nom, gardes, vides, avant / 1e6, apres / 1e6,
                 100 * (1 - apres / avant) if avant else 0))
        if langues:
            print("   par langue : %s" % ", ".join(
                "%s=%d" % (k, v) for k, v in sorted(langues.items())))
        print("   -> %s" % dst)

    if total_avant:
        print("\nTOTAL : %.1f Mo -> %.1f Mo" % (total_avant / 1e6, total_apres / 1e6))
    print("Les fichiers d'origine sont intacts.")


if __name__ == "__main__":
    main()
