"""Split manifest into train / held-out-voice / held-out-text for fair evaluation."""
import json, os, random
random.seed(42)
ROOT = os.path.dirname(os.path.abspath(__file__))

# 3 reciters entirely held out (diverse: modern voice, mujawwad style, classic)
HOLDOUT_VOICE = {"Hani_Rifai_192kbps","Abdul_Basit_Mujawwad_128kbps","Yasser_Ad-Dussary_128kbps"}
N_HOLDOUT_TEXT = 40                      # verse_keys removed from train (unseen content)

rows = [json.loads(l) for l in open(os.path.join(ROOT,"data","manifest_wav.jsonl"),encoding="utf-8")]
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
    with open(os.path.join(ROOT,"data",name),"w",encoding="utf-8") as f:
        for r in rows: f.write(json.dumps(r,ensure_ascii=False)+"\n")
    print(f"{name}: {len(rows)}")

dump("train.jsonl", train)
dump("test_voice.jsonl", test_voice)      # unseen reciter
dump("test_text.jsonl", test_text)        # unseen verses (seen reciters)
print("SPLIT DONE")
