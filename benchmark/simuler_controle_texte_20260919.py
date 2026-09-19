"""La regle proposee par l'utilisateur, MESUREE avant d'etre ecrite.

── L'IDEE ─────────────────────────────────────────────────────────────────

Constat de l'utilisateur, le 19/09, apres avoir force des fautes que
l'application a laissees passer : « je ne suis pas satisfait que le modele
reponde bien et que c'est l'application qui genere mal les decisions ». Puis la
proposition : que le modele « revienne et fasse un grand bout d'un coup pour
controler apres ».

Verification sur sa session : la passe longue EXISTE DEJA. La fenetre f=25
(11,84 s) decode `... إِلَيْكَ فَ وَمَآمَآ أُنزِلَ مِن قَبْلِكَ` -- le `فَ`
insere y est visible. La chaine decoupe ensuite cette lecture mot par mot, et
c'est ce decoupage qui perd l'information, pas le modele.

La regle testee ici est donc : comparer le TEXTE ENTIER d'une fenetre longue au
texte attendu de sa bande, et signaler les mots decodes qui n'ont rien a y
faire (« intrus »).

── CE QUE CE SCRIPT REPOND, ET CE QU'IL NE REPOND PAS ─────────────────────

Il chiffre, sur le banc des erreurs REELLES (118 fautes / 1 254 mots) :
    - combien de fautes un intrus permettrait de rattraper ;
    - combien de mots CORRECTS seraient accuses a tort.

Le second chiffre est celui qui decide. Sur la session de l'utilisateur, une
application naive de la regle donnait 6 fautes reelles pour 6 artefacts --
fragments de bord (`م`, `للم`), mot deforme par le modele (`قالوامون`), fin de
session sans texte. D'ou les filtres testes ici, et le fait qu'on mesure AVANT
d'ecrire une ligne dans la chaine.
"""
from __future__ import annotations

import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / "benchmark" / "replay_chaine_jvm_20260915"
MAN = json.loads((ROOT / "benchmark" / "campagne_erreurs_reelles_20260916"
                  / "manifest.json").read_text(encoding="utf-8"))
CAS = {c["case_id"]: c for c in MAN["cases"]}
CFG = "vote_t3_bpe"

# Duree minimale d'une fenetre pour servir de controle. En dessous, elle ne
# porte pas assez de contexte pour qu'un « intrus » veuille dire quelque chose.
DUREE_MIN = 6.0


def squelette(mot: str) -> str:
    t = unicodedata.normalize("NFKD", mot)
    t = "".join(c for c in t
                if unicodedata.category(c)[0] != "M" and c not in "ـۖۗۚۛۜ۞۩")
    return t.replace("ٱ", "ا").strip()


def intrus_de_la_fenetre(entendu: str, attendus: list[str], filtre: bool):
    """Mots decodes absents du texte attendu de la bande.

    [filtre] applique les deux garde-fous tires de la session du 19/09 :
      - on IGNORE le premier et le dernier mot decodes : ce sont eux que la
        fenetre coupe, et un mot coupe n'est pas une faute (c'est le defaut
        `bord_fenetre` que la chaine connait deja) ;
      - on ignore les mots d'une seule lettre : un fragment, jamais une
        insertion reelle.
    """
    mots = [squelette(m) for m in entendu.split() if squelette(m)]
    if filtre and len(mots) > 2:
        mots = mots[1:-1]
    attendu = {squelette(a) for a in attendus}
    out = []
    for m in mots:
        if m in attendu:
            continue
        if filtre and len(m) <= 1:
            continue
        out.append(m)
    return out


def main() -> None:
    for filtre in (False, True):
        rattrapees = fausses = 0
        detail_faux = defaultdict(int)
        fenetres = 0
        for cid, cas in CAS.items():
            log = LOGS / f"{cid}_{CFG}.log"
            if not log.exists():
                continue
            mots = cas["expected_words"]
            fautes = set()
            for o in cas["operations"]:
                fautes.update(o["affected_word_indices"])

            for ligne in log.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.search(
                    r'\[v2\] f=(\d+) duree=([\d,]+)s bande=(\d+)\.\.(\d+).*?entendu="([^"]*)"',
                    ligne)
                if not m:
                    continue
                duree = float(m.group(2).replace(",", "."))
                if duree < DUREE_MIN:
                    continue
                i0, i1, entendu = int(m.group(3)), int(m.group(4)), m.group(5)
                bande = [mots[i] for i in range(i0, min(i1 + 1, len(mots)))]
                if not bande:
                    continue
                fenetres += 1
                if not intrus_de_la_fenetre(entendu, bande, filtre):
                    continue
                # Une fenetre qui porte un intrus accuse TOUTE sa bande : c'est
                # la limite de la regle -- elle dit « il y a une faute ici »,
                # pas « c'est ce mot-la ».
                cible = set(range(i0, min(i1 + 1, len(mots))))
                if cible & fautes:
                    rattrapees += 1
                else:
                    fausses += 1
                    detail_faux[cid] += 1

        nom = "AVEC filtres (bords + fragments)" if filtre else "SANS filtre"
        print(f"\n── {nom} ──")
        print(f"  fenetres de plus de {DUREE_MIN:.0f} s examinees : {fenetres}")
        print(f"  fenetres portant un intrus SUR une faute reelle : {rattrapees}")
        print(f"  fenetres portant un intrus sur du CORRECT       : {fausses}")
        if rattrapees + fausses:
            print(f"  precision : {100 * rattrapees / (rattrapees + fausses):.0f} % "
                  f"des alertes tombent sur une vraie faute")


if __name__ == "__main__":
    main()
