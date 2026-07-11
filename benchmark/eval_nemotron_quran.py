"""Zero-shot: WER de nvidia/nemotron-3.5-asr-streaming-0.6b sur clips Coran (val set).
Tourne sur CPU (CUDA_VISIBLE_DEVICES="") pour ne PAS perturber le training GPU.
Compare sous 2 normalisations:
  - strict  : normalisation pipeline (garde harakat de base)  -> comparable au val_wer_ctc de notre modele
  - ortho   : normalisation agressive (sans tashkeel, alef/hamza/ta-marbuta unifies) -> WER "brut" equitable
"""
import os, sys, json, re, random, argparse
os.environ["USE_TF"]="0"; os.environ["USE_JAX"]="0"; os.environ["CUDA_VISIBLE_DEVICES"]=""
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

MODEL = "nvidia/nemotron-3.5-asr-streaming-0.6b"
VAL = "nemo_manifests/val_manifest.jsonl"

def norm_strict(t):
    t = re.sub(r"[ؖ-ؚۖ-ۜ۟-۪ۤۧۨ-ۭ]", "", t)
    t = re.sub(r"[،؛؟\.,!?:;\-_()\[\]{}\"\'»«]", "", t)
    return re.sub(r"\s+", " ", t).strip()

def norm_ortho(t):
    t = norm_strict(t)
    t = re.sub(r"[ً-ْٰـ]", "", t)   # harakat + superscript alef + tatweel
    t = re.sub(r"[آأإٱ]", "ا", t)  # alef variants -> ا
    t = t.replace("ة", "ه")   # ة -> ه
    t = t.replace("ى", "ي")   # ى -> ي
    t = re.sub(r"[ؤئ]", "ء", t)  # ؤ ئ -> ء
    return re.sub(r"\s+", " ", t).strip()

def wer(ref, hyp):
    r, h = ref.split(), hyp.split()
    d = [[0]*(len(h)+1) for _ in range(len(r)+1)]
    for i in range(len(r)+1): d[i][0]=i
    for j in range(len(h)+1): d[0][j]=j
    for i in range(1,len(r)+1):
        for j in range(1,len(h)+1):
            d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+(r[i-1]!=h[j-1]))
    return d[len(r)][len(h)], len(r)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rows = [json.loads(l) for l in open(VAL, encoding="utf-8")]
    random.seed(args.seed); random.shuffle(rows)
    # clips courts d'abord (streaming, CPU) -> plus rapides
    rows = sorted(rows[:args.n*3], key=lambda r: r["duration"])[:args.n]
    paths = [r["audio_filepath"] for r in rows]
    refs  = [r["text"] for r in rows]
    print(f"{len(paths)} clips, duree {min(r['duration'] for r in rows):.1f}-{max(r['duration'] for r in rows):.1f}s", flush=True)

    import nemo.collections.asr as nemo_asr
    m = nemo_asr.models.ASRModel.from_pretrained(model_name=MODEL, map_location="cpu")
    m.eval()
    print("Modele charge:", type(m).__name__, "-> transcription...", flush=True)

    try:
        hyps = m.transcribe(paths, batch_size=1)
    except TypeError:
        hyps = m.transcribe(paths)
    # NeMo peut retourner list[str] ou list[Hypothesis]
    hyps = [h.text if hasattr(h, "text") else h for h in hyps]

    for tag, nf in (("strict", norm_strict), ("ortho", norm_ortho)):
        E=N=0
        for r,hp in zip(refs,hyps):
            e,n = wer(nf(r), nf(hp)); E+=e; N+=n
        print(f"[{tag}] WER = {E/max(N,1):.4f}  ({E}/{N} mots)", flush=True)

    print("\n--- 5 exemples (ortho) ---", flush=True)
    for r,hp in list(zip(refs,hyps))[:5]:
        print("REF:", norm_ortho(r)[:90], flush=True)
        print("HYP:", norm_ortho(hp)[:90], flush=True)
        print(flush=True)

if __name__ == "__main__":
    main()
