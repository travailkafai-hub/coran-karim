"""Genere l'asset des signes de WAQF (regles d'arret) par mot :
  app/assets/data/quran_waqf.json   {"s:a": {"<index_mot>": "<type>"}}

POURQUOI (demande utilisateur 2026-07-23) : l'arret EST une regle de tajwid,
et certains arrets sont INTERDITS. Aucune des 17 classes du modele ne la
couvre (verifie) -- mais cette regle n'a pas besoin du modele : il suffit de
comparer une PAUSE detectee (l'app mesure deja les silences, cf.
BufferedTranscriber.MIN_TRACKED_PAUSE_MS) a la POSITION dans le texte.

Les signes sont deja presents dans le texte uthmani (4366 occurrences). Ils
apparaissent comme des tokens SEPARES par des espaces, places APRES le mot
concerne :
    'رَيْبَ', 'ۛ', 'فِيهِ'      -> le ۛ porte sur رَيْبَ
Et ils sont FILTRES de la liste des mots recitables cote app
(splitExpectedWords : normalize() les vide, cf. le regex _harakat qui couvre
la plage ۖ-ۭ). L'index stocke ici est donc l'index du mot RECITABLE, celui
que l'app manipule -- pas l'index brut du split.

⚠️ Le rub-el-hizb ۞ (U+06DE) tombe dans la meme plage Unicode mais n'est PAS
un signe d'arret (simple reperage de decoupage du Coran) : exclu explicitement.
"""
import json
import re
from pathlib import Path

BASE = Path(__file__).parent
SRC = BASE / "data" / "quran_tajweed_rules" / "uthmani.jsonl"
OUT = BASE.parent / "app" / "assets" / "data" / "quran_waqf.json"

# Type de waqf par signe. Les libelles servent de cle stable cote Dart.
WAQF = {
    "ۘ": "lazim",      # ۘ  م    arret OBLIGATOIRE
    "ۙ": "mamnu",      # ۙ  لا   arret INTERDIT
    "ۚ": "jaiz",       # ۚ  ج    arret permis
    "ۖ": "wasl_awla",  # ۖ  صلى  mieux vaut CONTINUER
    "ۗ": "waqf_awla",  # ۗ  قلى  mieux vaut S'ARRETER
    "ۛ": "muanaqah",   # ۛ  ···  s'arreter a l'UN des deux, pas aux deux
    "ۜ": "sakta",      # ۜ  س    pause BREVE sans reprendre son souffle
}

# Meme filtre que ArabicNormalizer.normalize cote app : si le token ne
# contient aucune lettre arabe une fois les diacritiques/marques retires, ce
# n'est pas un mot recitable (marques de waqf, rub-el-hizb, numeros de verset).
HARAKAT_RE = re.compile(r"[ً-ٰؐ-ؚۖ-ۭـ]")


def is_recitable(tok: str) -> bool:
    return bool(HARAKAT_RE.sub("", tok).strip())


def main():
    out = {}
    stats = {k: 0 for k in WAQF.values()}
    orphans = 0
    for line in open(SRC, encoding="utf-8"):
        d = json.loads(line)
        marks = {}
        widx = -1  # index du dernier mot RECITABLE rencontre
        for tok in d["text"].split():
            if is_recitable(tok):
                widx += 1
                continue
            # token non recitable : est-ce un signe de waqf ?
            for ch in tok:
                t = WAQF.get(ch)
                if t is None:
                    continue
                if widx < 0:
                    # signe en tout debut de verset : rien avant a quoi le
                    # rattacher (ne devrait pas arriver, compte pour controle)
                    orphans += 1
                    continue
                # Un mot peut porter deux signes (rare) : le plus contraignant
                # gagne -- interdit/obligatoire priment sur un simple conseil.
                prio = {"mamnu": 5, "lazim": 5, "muanaqah": 4, "sakta": 4,
                        "waqf_awla": 3, "jaiz": 2, "wasl_awla": 1}
                prev = marks.get(widx)
                if prev is None or prio[t] > prio[prev]:
                    marks[widx] = t
                stats[t] += 1
        if marks:
            out[d["verse_key"]] = {str(k): v for k, v in sorted(marks.items())}

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    total = sum(len(v) for v in out.values())
    print(f"{OUT}")
    print(f"  {len(out)} versets, {total} mots portant un signe d'arret "
          f"({OUT.stat().st_size/1e3:.1f} Ko)")
    for k, n in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"    {k:<10} {n:>5}")
    if orphans:
        print(f"  ⚠️ {orphans} signes en debut de verset, ignores")


if __name__ == "__main__":
    main()
