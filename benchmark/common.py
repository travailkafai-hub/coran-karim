"""Shared utilities: Arabic normalization, WER, algorithmic mistake detection."""
import re, unicodedata, difflib, json, os

ROOT = os.path.dirname(os.path.abspath(__file__))

# Arabic diacritics & marks to strip for orthography-insensitive comparison
_DIAC = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۜ۟-۪ۨ-ۭ࣓-ࣿـ]")
def normalize(text: str) -> str:
    if not text: return ""
    t = unicodedata.normalize("NFC", text)
    t = _DIAC.sub("", t)                      # remove harakat, tatweel, small signs
    t = t.replace("ٱ","ا").replace("أ","ا").replace("إ","ا").replace("آ","ا")  # alef variants
    t = t.replace("ى","ي").replace("ة","ه").replace("ؤ","و").replace("ئ","ي")
    t = re.sub(r"[^؀-ۿ\s]", " ", t) # keep arabic letters + space
    t = re.sub(r"\s+", " ", t).strip()
    return t

def words(text): return normalize(text).split()

def wer(ref: str, hyp: str) -> float:
    r, h = words(ref), words(hyp)
    if not r: return 0.0 if not h else 1.0
    # Levenshtein on word tokens
    d = list(range(len(h)+1))
    for i in range(1, len(r)+1):
        prev, d[0] = d[0], i
        for j in range(1, len(h)+1):
            cur = d[j]
            d[j] = prev if r[i-1]==h[j-1] else 1+min(prev, d[j], d[j-1])
            prev = cur
    return d[len(h)]/len(r)

def diff_has_error(reference: str, recited: str):
    """Algorithmic mistake detection: align recited words vs reference words.
    Returns (has_error: bool, details: list)."""
    r, h = words(reference), words(recited)
    sm = difflib.SequenceMatcher(None, r, h)
    ops = [op for op in sm.get_opcodes() if op[0] != "equal"]
    details = []
    for tag,i1,i2,j1,j2 in ops:
        if tag=="replace": details.append(f"sub: {' '.join(r[i1:i2])} -> {' '.join(h[j1:j2])}")
        elif tag=="delete": details.append(f"manque: {' '.join(r[i1:i2])}")
        elif tag=="insert": details.append(f"ajout: {' '.join(h[j1:j2])}")
    return (len(ops)>0, details)

def load_dataset():
    with open(os.path.join(ROOT,"data","dataset.json"),encoding="utf-8") as f:
        return json.load(f)

def vram_gb():
    try:
        import torch
        return round(torch.cuda.max_memory_allocated()/1e9,2)
    except Exception:
        return None
