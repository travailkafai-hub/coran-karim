"""Construit le corpus coranique annote avec les 17 regles de tajwid
(Phase 0.2 du PLAN_ENTRAINEMENT_HYBRIDE.md).

Principe (piege documente FONCTIONNALITES_FUTURES.md §6) :
  - text_uthmani           = source de VERITE des caracteres (on entraine dessus)
  - text_uthmani_tajweed   = source des POSITIONS/CLASSES uniquement (ses
    caracteres different du canonique sur 4278/6236 versets)

Methode d'ancrage :
  1. Retirer les balises du texte tajweed -> texte "plat" + spans (debut, fin,
     classe) en offsets de ce texte plat.
  2. Aligner caractere par caractere le texte plat sur le canonique (les
     differences sont des substitutions 1:1 de diacritiques + qq insertions/
     suppressions -> alignement Levenshtein par verset, chemin optimal).
  3. Reporter la fin de chaque span sur l'offset canonique correspondant et
     inserer le SYMBOLE de la regle a cet endroit du texte canonique.
     (fin du span = fin de la realisation acoustique de la regle — c'est la
     que le CTC doit "declencher" le symbole.)

Symboles : zone privee Unicode U+E000+i (verifies absents du corpus).
Sortie :
  data/quran_tajweed_rules/annotated.jsonl   ({verse_key, text} annote)
  data/quran_tajweed_rules/rules_map.json    (classe -> symbole)
  data/quran_tajweed_rules/corpus_rules.txt  (texte seul, pour le tokenizer)
Stats de controle affichees (taux d'alignement parfait, nb symboles/classe).
"""
import json
import re
from pathlib import Path

BASE = Path(__file__).parent
DIR = BASE / "data" / "quran_tajweed_rules"

# Les 17 classes verifiees dans app/lib/widgets/tajweed_text.dart::_classColors
CLASSES = [
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


def word_index_at(text: str, offset: int) -> int:
    """Index (0-based) du mot canonique contenant le caractere en `offset`.
    Meme convention que words() dans build_app_rules_assets.py (۞ compte
    comme un espace, split() sur les espaces multiples)."""
    prefix = text[:offset + 1].replace("۞", " ")
    return len(prefix.split()) - 1


def main():
    canon = {}
    for l in open(DIR / "uthmani.jsonl", encoding="utf-8"):
        r = json.loads(l)
        canon[r["verse_key"]] = r["text"]

    out_rows = []
    # Mots "frontiere" (2026-07-22, demande utilisateur : afficher la paire
    # de mots pour les regles a cheval sur deux mots, ex. ikhafa/iqlab/idgham
    # -- le son declencheur est la fin du mot precedent + le debut du
    # suivant, pas un seul mot isole). Ancre = le mot qui porte le symbole
    # (cf. correctif ci-dessous) ; la paire a afficher cote app est donc
    # (word_index, word_index+1).
    boundary_rows = {}
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
            if cls not in RULES_MAP:
                unknown_classes[cls] = unknown_classes.get(cls, 0) + 1
                continue
            # Correctif 2026-07-22 : si le span traverse une frontiere de mot
            # (tag couvrant la fin d'un mot + le debut du suivant, ex. tanwin
            # + lettre suivante pour iqlab/idgham/ikhafa), l'ancien code
            # inserait TOUJOURS a `end`, donc apres l'espace -> le symbole
            # atterrissait dans le mot SUIVANT. Mesure sur le modele 2 tetes
            # (test_dual_head_full_surah.py, 3 recitateurs professionnels,
            # sourate 90) : l'evenement est detecte de facon reproductible
            # dans la fenetre de frames du mot PRECEDENT (le son du
            # tanwin/nun qui declenche la regle est physiquement a la fin de
            # ce mot). Consequence avant ce correctif : l'app comparait
            # "detecte sur le mot precedent" a "attendu sur le mot suivant"
            # et signalait a tort la regle comme non realisee (ex. iqlab sur
            # بِهَـٰذَا en 90:2, jamais realisee en pratique). On ancre donc le
            # symbole juste avant le premier espace du span quand il y en a
            # un (fin du mot precedent), sinon comportement inchange (fin du
            # span, cas intra-mot : madda, ghunnah, qalaqah...).
            content = flat[start:end]
            ws = content.find(" ")
            # Ancrage = DEBUT du span (mot qui porte le caractere taggue).
            #
            # Correctif 2026-07-22 (iqlab/idgham/ikhafa -- tags a cheval sur 2
            # mots) : l'ancien code inserait a `end`, donc APRES l'espace ->
            # le symbole atterrissait dans le mot SUIVANT alors que le trigger
            # (tanwin/noun) est sur le mot PRECEDENT. Insérer avant le premier
            # espace (`start + ws`) le remet sur le mot du trigger.
            #
            # Correctif 2026-07-23 (ham_wasl) ANNULE le meme jour apres MESURE
            # sur l'alignement force de PRODUCTION (test_forced_align_
            # attribution.py, 5 recitateurs, sourate 90) : contrairement a
            # l'intuition tiree du decodage greedy libre, l'alignement force
            # (ForcedAligner.kt, ce que l'app utilise REELLEMENT) attribue
            # CHAQUE regle au mot qui PORTE le caractere taggue dans le texte
            # -- mesure delta=0 dominant pour TOUTES les classes (ham_wasl 19x
            # delta=0 vs 4x delta=-1 ; iqlab 5/5 ; idgham 10/10 ; ikhafa
            # 11/11). Pour ham_wasl le ٱ appartient au mot SUIVANT, donc le
            # symbole doit y rester (pas sur le precedent). Le cas special
            # "ham_wasl -> mot precedent" faisait flasher a tort chaque mot
            # avant un ٱل- (ex. رَبِّ ٱلْعَـٰلَمِينَ : رَبِّ marque ham_wasl non
            # realisee) -> unclear -> correction -> pauseCapture -> cascade
            # d'erreurs (constate device 2026-07-23, session Al-Fatiha).
            # Regle universelle : ancrer au premier espace du span s'il y en a
            # un (fin du mot precedent = mot du trigger tanwin), sinon a la fin
            # du span (cas intra-mot : ham_wasl sur son ٱ, madda, ghunnah...).
            anchor = start + ws if ws != -1 else end
            canon_off = mapping[anchor]
            inserts.append((canon_off, RULES_MAP[cls]))
            stats[cls] += 1
            if ws != -1:
                wi = word_index_at(dst, canon_off)
                boundary_rows.setdefault(key, set()).add(wi)
        text = dst
        for off, sym in sorted(inserts, key=lambda x: -x[0]):
            text = text[:off] + sym + text[off:]
        out_rows.append({"verse_key": key, "text": text})

    with open(DIR / "annotated.jsonl", "w", encoding="utf-8") as f:
        for r in out_rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    with open(DIR / "boundary_words.jsonl", "w", encoding="utf-8") as f:
        for key, indices in boundary_rows.items():
            f.write(json.dumps(
                {"verse_key": key, "word_indices": sorted(indices)},
                ensure_ascii=False) + "\n")
    with open(DIR / "rules_map.json", "w", encoding="utf-8") as f:
        json.dump(RULES_MAP, f, ensure_ascii=False, indent=2)
    with open(DIR / "corpus_rules.txt", "w", encoding="utf-8") as f:
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
