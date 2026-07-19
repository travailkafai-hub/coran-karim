"""Genere l'asset app des mots annotes de regles tajwid :
  app/assets/data/quran_rules_annotated.json   {"s:a": ["mot1", "mot2", ...]}

POURQUOI (2026-07-19, deploiement du modele stage1b-260h) : le modele a ete
entraine a transcrire le Coran canonique AVEC les symboles de regles
(U+E000..U+E010) inseres dans les mots. L'alignement force GOP doit donc
cibler ces memes mots annotes -- aligner sur le texte canonique nu penalise
le chemin force sur chaque frame ou le modele veut emettre un symbole
appris, ce qui fausse la calibration des seuils gop (ordre de grandeur
estime : jusqu'a ~1 point de gop sur un mot court a 1 symbole, comparable
aux seuils eux-memes).

Garanties verifiees ici (asserts, pas juste en commentaire) :
  - meme nombre de mots que le texte canonique pour CHAQUE verset
    (l'app mappe mot-a-mot affichage canonique <-> cible annotee) ;
  - retirer les symboles redonne EXACTEMENT le mot canonique.

Source : data/quran_tajweed_rules/{annotated,uthmani}.jsonl (Phase 0 du run
hybride). Mapping symbole->regle : U+E000+i dans l'ordre de rules_map.json,
qui est aussi l'ordre de l'enum Dart TajwidRule (judgement_options.dart) --
verifie a la main le 2026-07-19, ne pas reordonner l'un sans l'autre.
"""
import json
from pathlib import Path

BASE = Path(__file__).parent
RULES_DIR = BASE / "data" / "quran_tajweed_rules"
OUT = BASE.parent / "app" / "assets" / "data" / "quran_rules_annotated.json"


def words(t: str) -> list[str]:
    return [w for w in t.replace("۞", " ").split() if w]


def strip_pua(t: str) -> str:
    return "".join(c for c in t if not (0xE000 <= ord(c) <= 0xF8FF))


def main():
    ann, canon = {}, {}
    for l in open(RULES_DIR / "annotated.jsonl", encoding="utf-8"):
        r = json.loads(l)
        ann[r["verse_key"]] = r["text"]
    for l in open(RULES_DIR / "uthmani.jsonl", encoding="utf-8"):
        r = json.loads(l)
        canon[r["verse_key"]] = r["text"]

    out = {}
    n_sym_words = 0
    for key, ctext in canon.items():
        atext = ann.get(key)
        assert atext is not None, f"verset {key} absent de annotated.jsonl"
        wa, wc = words(atext), words(ctext)
        assert len(wa) == len(wc), f"{key}: {len(wa)} mots annotes vs {len(wc)} canoniques"
        for a, c in zip(wa, wc):
            assert strip_pua(a) == c, f"{key}: strip('{a}') != '{c}'"
        n_sym_words += sum(1 for a in wa if any(0xE000 <= ord(ch) <= 0xF8FF for ch in a))
        out[key] = wa

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    total_words = sum(len(v) for v in out.values())
    print(f"{OUT} : {len(out)} versets, {total_words} mots "
          f"({n_sym_words} portant au moins un symbole, "
          f"{OUT.stat().st_size/1e6:.1f} Mo)")


if __name__ == "__main__":
    main()
