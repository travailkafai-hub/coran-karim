"""Split manifest_full_wav.jsonl into train_full / test_voice_full / test_text_full.
Same held-out reciters as Phase 2. Larger test sets (full Quran scope).
"""
import json, os, random
random.seed(42)
ROOT = os.path.dirname(os.path.abspath(__file__))

HOLDOUT_VOICE = {"Hani_Rifai_192kbps", "Abdul_Basit_Mujawwad_128kbps", "Yasser_Ad-Dussary_128kbps"}
N_HOLDOUT_TEXT = 40

rows = [json.loads(l) for l in open(os.path.join(ROOT, "data", "manifest_full_wav.jsonl"), encoding="utf-8")]
keys = sorted({r["key"] for r in rows})
holdout_text = set(random.sample(keys, min(N_HOLDOUT_TEXT, len(keys))))

train, test_voice, test_text = [], [], []
for r in rows:
    if r["reciter"] in HOLDOUT_VOICE:
        test_voice.append(r)
    elif r["key"] in holdout_text:
        test_text.append(r)
    else:
        train.append(r)

def dump(name, rows):
    with open(os.path.join(ROOT, "data", name), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{name}: {len(rows)}")

dump("train_full.jsonl", train)
dump("test_voice_full.jsonl", test_voice)
dump("test_text_full.jsonl", test_text)
print(f"Holdout reciters: {HOLDOUT_VOICE}")
print(f"Holdout verse keys: {len(holdout_text)}")
print("SPLIT FULL DONE")
