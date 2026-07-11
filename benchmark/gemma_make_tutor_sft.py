"""Build Gemma text-tutor SFT dataset from tafsir/translations.
Generates ~6 examples per verse (FR x3 + AR x2 + EN x1) = ~35k examples.
Output: data/gemma_tutor_sft.jsonl  format: {"user": str, "target": str}
"""
import json, os, random
random.seed(42)
ROOT = os.path.dirname(os.path.abspath(__file__))
TAFSIR_DIR = os.path.join(ROOT, "data", "tafsir")
OUT = os.path.join(ROOT, "data", "gemma_tutor_sft.jsonl")

MIN_LEN = 40  # discard tafsir texts shorter than this

def load(slug):
    path = os.path.join(TAFSIR_DIR, slug + ".jsonl")
    return {obj["verse_key"]: obj["text"]
            for l in open(path, encoding="utf-8")
            for obj in [json.loads(l)]
            if len(obj.get("text", "")) >= MIN_LEN}

print("Loading tafsir sources...", flush=True)
FR_H = load("fr-hamidullah")
FR_M = load("fr-montada")
FR_R = load("fr-rashid-maash")
AR_Y = load("ar-muyassar")
AR_S = load("ar-saadi")
EN_K = load("en-maarif")

# Load Arabic verse texts (canonical reference)
verses_raw = [json.loads(l) for l in open(
    os.path.join(ROOT, "data", "manifest_full.jsonl"), encoding="utf-8")]
arabic = {}
for v in verses_raw:
    arabic.setdefault(v["key"], v["text"])
all_keys = sorted(arabic.keys())
print(f"Verse keys: {len(all_keys)}", flush=True)

SYSTEM = ("Tu es un tuteur spécialisé en mémorisation et compréhension du Coran. "
          "Tu aides les apprenants francophones à comprendre le sens des versets, "
          "leur contexte et leur portée spirituelle. Tes réponses sont précises, "
          "bienveillantes et pédagogiques.")

# FR templates → FR translations as answers
FR_TEMPLATES = [
    (lambda k, ar: f"Traduis le verset {k} du Coran en français :\n{ar}", FR_H),
    (lambda k, ar: f"Quel est le sens du verset {k} du Coran :\n{ar}", FR_M),
    (lambda k, ar: f"Je mémorise le Coran. Explique-moi en français le verset {k} :\n{ar}", FR_R),
]

# AR templates → Arabic tafsir as answers
AR_TEMPLATES = [
    (lambda k, ar: f"فسِّر الآية الكريمة ({k}) من القرآن الكريم :\n{ar}", AR_Y),
    (lambda k, ar: f"ما معنى الآية {k} من القرآن الكريم :\n{ar}", AR_S),
]

# EN template → English tafsir
EN_TEMPLATES = [
    (lambda k, ar: f"Explain the meaning of Quran verse {k}:\n{ar}", EN_K),
]

examples = []
for key in all_keys:
    ar = arabic.get(key, "")
    if not ar:
        continue
    for (tmpl, source) in FR_TEMPLATES + AR_TEMPLATES + EN_TEMPLATES:
        txt = source.get(key, "")
        if len(txt) < MIN_LEN:
            continue
        examples.append({
            "system": SYSTEM,
            "user": tmpl(key, ar),
            "target": txt,
        })

random.shuffle(examples)
with open(OUT, "w", encoding="utf-8") as f:
    for ex in examples:
        f.write(json.dumps(ex, ensure_ascii=False) + "\n")

print(f"Tutor SFT examples: {len(examples)} -> gemma_tutor_sft.jsonl", flush=True)
# Lang breakdown
fr = sum(1 for e in examples if e["user"][0] in "TQJI")
ar = sum(1 for e in examples if e["user"][0] == "ف" or e["user"][0] == "م")
en = sum(1 for e in examples if e["user"].startswith("Explain"))
print(f"  FR: ~{fr}  AR: ~{ar}  EN: ~{en}", flush=True)
print("TUTOR SFT DONE", flush=True)
