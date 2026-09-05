"""Construit l'asset du DECOUPAGE EN LIGNES du mushaf de Medine (15 lignes/page).

POURQUOI CET ASSET EXISTE (2026-09-04). Constat utilisateur, apres une longue
serie de correctifs qui ne traitaient que des symptomes :

  « tu ne respectes pas le Coran papier. Ce n'est pas juste un nombre de pages :
    chaque page a un nombre precis de lignes, chaque ligne commence et finit
    avec les memes mots, quel que soit le type d'ecriture. »

C'est exact, et c'est un defaut d'ARCHITECTURE, pas de reglage. L'app ne
connaissait que le `page_number` de chaque verset : elle versait le texte d'une
page dans un paragraphe justifie et laissait Flutter choisir ou couper. Le
decoupage dependait donc de la police, de la largeur et de la taille calculee --
d'ou les demi-lignes rognees qu'on rattrapait sans fin, reserve apres reserve.

Un mushaf de Medine, c'est 604 pages de 15 lignes dont les mots de debut et de
fin sont FIXES. Aucun reglage d'interligne ne produit ca : il faut la donnee.

CE QU'ON PREND, ET CE QU'ON NE PREND PAS. On extrait UNIQUEMENT les frontieres
-- pour chaque ligne, son type et ses mots de debut/fin. Le TEXTE reste celui du
projet (`quran_verses.json`, deja verifie caractere par caractere le
2026-09-03 : « faut pas inventer et modifier le texte sacre »). On ne recopie
donc aucun texte coranique d'une source tierce, seulement une information de
MISE EN PAGE.

SOURCE : github.com/zonetecde/mushaf-layout, layout KFGQPC (1441H).
⚠️ Ce depot ne porte AUCUNE licence explicite. Les frontieres de lignes sont un
fait de mise en page du mushaf imprime, non une oeuvre -- mais le point est a
trancher avant publication, comme le reste des sources (PUBLICATION_PLAY.md §4).
"""

import json
import time
import urllib.request
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "app/assets/data/mushaf_lignes.json"
BASE = "https://raw.githubusercontent.com/zonetecde/mushaf-layout/main/mushaf"


def page(n):
    u = f"{BASE}/page-{n:03d}.json"
    r = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"})
    for essai in range(3):
        try:
            return json.load(urllib.request.urlopen(r, timeout=25))
        except Exception as e:
            if essai == 2:
                raise
            time.sleep(1.5 * (essai + 1))


def main():
    out = {}
    for n in range(1, 605):
        d = page(n)
        lignes = []
        for l in d.get("lines", []):
            t = l.get("type")
            if t == "surah-header":
                # `surah` arrive en chaine zero-completee ("002").
                lignes.append({"t": "s", "s": int(l["surah"])})
            elif t == "basmala":
                lignes.append({"t": "b"})
            else:
                mots = l.get("words") or []
                if not mots:
                    continue
                # Les mots d'une ligne sont contigus : deux bornes suffisent, et
                # l'asset reste petit (~150 Ko au lieu de ~2 Mo mot par mot).
                lignes.append({
                    "t": "x",
                    "d": mots[0]["location"],
                    "f": mots[-1]["location"],
                })
        out[str(n)] = lignes
        if n % 50 == 0:
            print(f"  {n}/604")
        time.sleep(0.05)

    SORTIE.parent.mkdir(parents=True, exist_ok=True)
    SORTIE.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")),
                      encoding="utf-8")
    ko = SORTIE.stat().st_size / 1024
    n_lignes = sum(len(v) for v in out.values())
    print(f"\necrit : {SORTIE}  ({ko:.0f} Ko, {n_lignes} lignes)")
    # Controle : 15 lignes par page, sans exception, sinon le rendu sera faux.
    faux = [p for p, v in out.items() if len(v) != 15]
    print(f"pages dont le nombre de lignes n'est pas 15 : {len(faux)}"
          + (f" -> {faux[:10]}" if faux else ""))


if __name__ == "__main__":
    main()
