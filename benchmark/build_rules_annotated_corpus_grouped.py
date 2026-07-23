"""Variante GROUPEE de build_rules_annotated_corpus.py (2026-07-21, idee
utilisateur apres la nuit d'audit gop) : au lieu des 17 classes fines, fusionne
en 10 classes plus larges. Motivation mesuree, pas un choix arbitraire :
  - 3 des 17 classes sont quasi inapprenables seules (n=13, 58, 143
    occurrences sur 59844 dans le corpus complet) -- cf. rule_reliability.json
    deja mesure : IC95% enormes, aucune information exploitable.
  - Hypothese a tester : avoir 40 tokens-symboles dans le vocabulaire (17
    classes x jusqu'a plusieurs variantes) DILUE la calibration du modele
    (deja mesure la meme nuit : ~20% de masse de probabilite parasite sur les
    tokens-symboles meme sur des mots SANS aucune regle attendue). Reduire le
    nombre de classes distinctes pourrait limiter cette dilution.

Regroupement (17 -> 10), fusionne UNIQUEMENT ce qui est acoustiquement proche :
  - madd            = madda_necessary + madda_obligatory + madda_permissible
                       + madda_normal (meme phenomene de base : elongation
                       vocalique, differe seulement par la duree/contexte)
  - ikhfa           = ikhafa + ikhafa_shafawi (meme mecanisme de nasalisation
                       avant consonne, differe par la lettre declenchante)
  - idgham_ghunnah  = idgham_ghunnah + idgham_shafawi (fusion AVEC
                       nasalisation, audible)
  - idgham_sans_ghunnah = idgham_wo_ghunnah + idgham_mutajanisayn +
                       idgham_mutaqaribayn (fusion SANS nasalisation --
                       les 2 dernieres sont les classes n=58/n=13 ci-dessus)
  - ghunnah, iqlab, laam_shamsiyah, ham_wasl, slnt, qalaqah : INCHANGEES
                       (deja distinctes acoustiquement, pas fusionnees)

Sortie dans des fichiers SEPARES (jamais d'ecrasement des 17 classes
d'origine, cf. regle projet "aucune piste eliminee") :
  data/quran_tajweed_rules/annotated_grouped.jsonl
  data/quran_tajweed_rules/rules_map_grouped.json
  data/quran_tajweed_rules/corpus_rules_grouped.txt

Reste du principe IDENTIQUE a build_rules_annotated_corpus.py (voir ce
fichier pour le detail de la methode d'ancrage Levenshtein) -- seule la
table de regroupement GROUP_MAP est nouvelle, appliquee au nom de classe
brut AVANT le lookup RULES_MAP.
"""
import json
import re
from pathlib import Path

BASE = Path(__file__).parent
DIR = BASE / "data" / "quran_tajweed_rules"

# Regroupement 17 -> 10 (cf. docstring). Cle = nom de classe brut tel qu'il
# apparait dans uthmani_tajweed.jsonl (source externe, 17 classes), valeur =
# classe groupee utilisee pour CE corpus.
GROUP_MAP = {
    "madda_necessary": "madd",
    "madda_obligatory": "madd",
    "madda_permissible": "madd",
    "madda_normal": "madd",
    "ikhafa": "ikhfa",
    "ikhafa_shafawi": "ikhfa",
    "idgham_ghunnah": "idgham_ghunnah",
    "idgham_shafawi": "idgham_ghunnah",
    "idgham_wo_ghunnah": "idgham_sans_ghunnah",
    "idgham_mutajanisayn": "idgham_sans_ghunnah",
    "idgham_mutaqaribayn": "idgham_sans_ghunnah",
    "ghunnah": "ghunnah",
    "iqlab": "iqlab",
    "laam_shamsiyah": "laam_shamsiyah",
    "ham_wasl": "ham_wasl",
    "slnt": "slnt",
    "qalaqah": "qalaqah",
}

# 10 classes groupees (ordre fixe -> symboles U+E000..U+E009 stables)
CLASSES = [
    "madd", "ikhfa", "idgham_ghunnah", "idgham_sans_ghunnah", "ghunnah",
    "iqlab", "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
_OLD_CLASSES_UNUSED = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
RULES_MAP = {cls: chr(0xE000 + i) for i, cls in enumerate(CLASSES)}

TAG_RE = re.compile(r'<tajweed\s+class=["\']?([a-z_]+)["\']?>(.*?)</tajweed>', re.S)
ANY_TAG_RE = re.compile(r"<[^>]+>")


def strip_tags_with_spans(tagged: str):
    """Texte plat + [(start, end, classe)] en offsets du texte plat."""
    flat = []
    spans = []
    pos = 0
    idx = 0
    for m in TAG_RE.finditer(tagged):
        before = ANY_TAG_RE.sub("", tagged[idx:m.start()])
        flat.append(before)
        pos += len(before)
        content = ANY_TAG_RE.sub("", m.group(2))
        spans.append((pos, pos + len(content), m.group(1)))
        flat.append(content)
        pos += len(content)
        idx = m.end()
    tail = ANY_TAG_RE.sub("", tagged[idx:])
    flat.append(tail)
    return "".join(flat), spans


def align_offsets(src: str, dst: str):
    """Alignement Levenshtein caractere src->dst ; retourne map offset src -> offset dst.
    (petites chaines par verset, DP quadratique acceptable)"""
    n, m = len(src), len(dst)
    # DP cost + backtrack
    INF = 1 << 30
    prev = list(range(m + 1))
    ops = [[None] * (m + 1) for _ in range(n + 1)]
    for j in range(m + 1):
        ops[0][j] = "I"
    for i in range(1, n + 1):
        cur = [i] + [0] * m
        ops[i][0] = "D"
        for j in range(1, m + 1):
            sub = prev[j - 1] + (src[i - 1] != dst[j - 1])
            dele = prev[j] + 1
            ins = cur[j - 1] + 1
            best = min(sub, dele, ins)
            cur[j] = best
            ops[i][j] = "S" if best == sub else ("D" if best == dele else "I")
        prev = cur
    # backtrack -> pour chaque position src, l'offset dst correspondant
    mapping = [0] * (n + 1)
    i, j = n, m
    mapping[n] = m
    while i > 0 or j > 0:
        op = ops[i][j]
        if op == "S":
            i -= 1
            j -= 1
        elif op == "D":
            i -= 1
        else:
            j -= 1
        if i >= 0:
            mapping[i] = j
    return mapping, prev[m]


def main():
    canon = {}
    for l in open(DIR / "uthmani.jsonl", encoding="utf-8"):
        r = json.loads(l)
        canon[r["verse_key"]] = r["text"]

    out_rows = []
    stats = {c: 0 for c in CLASSES}
    unknown_classes = {}
    perfect, shifted = 0, 0
    total_dist = 0

    for l in open(DIR / "uthmani_tajweed.jsonl", encoding="utf-8"):
        r = json.loads(l)
        key = r["verse_key"]
        flat, spans = strip_tags_with_spans(r["text"])
        # l'API encode certains caracteres en entites html
        for ent, ch in [("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]:
            flat = flat.replace(ent, ch)
        dst = canon[key]
        mapping, dist = align_offsets(flat, dst)
        total_dist += dist
        if dist == 0:
            perfect += 1
        else:
            shifted += 1
        # insertion des symboles aux offsets canoniques (fin de span),
        # tries par offset decroissant pour ne pas invalider les suivants
        inserts = []
        for start, end, cls in spans:
            # GROUP_MAP AVANT le lookup RULES_MAP -- seule vraie difference
            # avec le script d'origine (17 classes).
            grouped_cls = GROUP_MAP.get(cls)
            if grouped_cls is None or grouped_cls not in RULES_MAP:
                unknown_classes[cls] = unknown_classes.get(cls, 0) + 1
                continue
            inserts.append((mapping[end], RULES_MAP[grouped_cls]))
            stats[grouped_cls] += 1
        text = dst
        for off, sym in sorted(inserts, key=lambda x: -x[0]):
            text = text[:off] + sym + text[off:]
        out_rows.append({"verse_key": key, "text": text})

    with open(DIR / "annotated_grouped.jsonl", "w", encoding="utf-8") as f:
        for r in out_rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    with open(DIR / "rules_map_grouped.json", "w", encoding="utf-8") as f:
        json.dump(RULES_MAP, f, ensure_ascii=False, indent=2)
    with open(DIR / "corpus_rules_grouped.txt", "w", encoding="utf-8") as f:
        for r in out_rows:
            f.write(r["text"] + "\n")

    print(f"versets annotes : {len(out_rows)} (align parfait {perfect}, "
          f"avec substitutions {shifted}, distance totale {total_dist})")
    print("symboles par classe :")
    for c in CLASSES:
        print(f"  {RULES_MAP[c]!r} {c:<24} {stats[c]}")
    if unknown_classes:
        print(f"⚠️ classes INCONNUES ignorees : {unknown_classes}")
    # controle : aucun symbole PUA preexistant dans le canonique
    pua = [ch for t in canon.values() for ch in t if 0xE000 <= ord(ch) <= 0xF8FF]
    assert not pua, f"PUA deja present dans le canonique ?! {pua[:5]}"
    print("controle PUA : aucun symbole en collision avec le texte canonique ✔")


if __name__ == "__main__":
    main()
