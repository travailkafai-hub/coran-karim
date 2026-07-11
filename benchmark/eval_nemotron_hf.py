"""Zero-shot Nemotron-3.5 (HF Transformers, venv isole) sur clips Coran, CPU.
Usage: python eval_nemotron_hf.py --n 30 --lang ar
"""
import os, sys, json, re, random, argparse, time
os.environ["USE_TF"]="0"; os.environ["USE_JAX"]="0"; os.environ["CUDA_VISIBLE_DEVICES"]=""
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass
import torch
torch.set_num_threads(max(1, os.cpu_count()-1))

MODEL = "nvidia/nemotron-3.5-asr-streaming-0.6b"
VAL = "nemo_manifests/val_manifest.jsonl"

def norm_strict(t):
    t = re.sub(r"[ؖ-ؚۖ-ۜ۟-۪ۤۧۨ-ۭ]", "", t)
    t = re.sub(r"[،؛؟\.,!?:;\-_()\[\]{}\"\'»«]", "", t)
    return re.sub(r"\s+", " ", t).strip()

def norm_ortho(t):
    t = norm_strict(t)
    t = re.sub(r"[ً-ْٰـ]", "", t)
    t = re.sub(r"[آأإٱ]", "ا", t)
    t = t.replace("ة", "ه").replace("ى", "ي")
    t = re.sub(r"[ؤئ]", "ء", t)
    return re.sub(r"\s+", " ", t).strip()

def wer_pair(ref, hyp):
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
    ap.add_argument("--n", type=int, default=30)
    ap.add_argument("--lang", type=str, default="ar")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--uniform", action="store_true", help="echantillon uniforme (pas trie par duree)")
    ap.add_argument("--maxdur", type=float, default=999.0)
    args = ap.parse_args()

    from transformers import AutoModelForRNNT, AutoProcessor
    from transformers.audio_utils import load_audio

    print("Chargement processor/model...", flush=True)
    processor = AutoProcessor.from_pretrained(MODEL)
    model = AutoModelForRNNT.from_pretrained(MODEL, dtype=torch.float32).to("cpu").eval()
    sr = processor.feature_extractor.sampling_rate
    print("OK. sample_rate=", sr, flush=True)

    rows = [json.loads(l) for l in open(VAL, encoding="utf-8")]
    rows = [r for r in rows if r["duration"] <= args.maxdur]
    random.seed(args.seed); random.shuffle(rows)
    if args.uniform:
        rows = rows[:args.n]
    else:
        rows = sorted(rows[:args.n*3], key=lambda r: r["duration"])[:args.n]
    print(f"{len(rows)} clips, {min(r['duration'] for r in rows):.1f}-{max(r['duration'] for r in rows):.1f}s", flush=True)

    hyps, refs = [], []
    t0 = time.time()
    for i, r in enumerate(rows):
        audio = load_audio(r["audio_filepath"], sampling_rate=sr)
        try:
            inputs = processor(audio, sampling_rate=sr, language=args.lang)
        except Exception as e:
            print("  processor lang fallback auto:", e, flush=True)
            inputs = processor(audio, sampling_rate=sr, language="auto")
        inputs = inputs.to(model.device, dtype=model.dtype)
        with torch.no_grad():
            out = model.generate(**inputs, return_dict_in_generate=True)
        txt = processor.decode(out.sequences, skip_special_tokens=True)
        if isinstance(txt, list): txt = txt[0]
        hyps.append(txt); refs.append(r["text"])
        if i < 3 or i % 10 == 0:
            print(f"[{i+1}/{len(rows)}] {time.time()-t0:.0f}s  hyp={norm_ortho(txt)[:60]}", flush=True)

    for tag, nf in (("strict", norm_strict), ("ortho", norm_ortho)):
        E=N=0
        for r,hp in zip(refs,hyps):
            e,n = wer_pair(nf(r), nf(hp)); E+=e; N+=n
        print(f"[{tag}] WER = {E/max(N,1):.4f}  ({E}/{N})", flush=True)

    print("\n--- exemples (ortho) ---", flush=True)
    for r,hp in list(zip(refs,hyps))[:6]:
        print("REF:", norm_ortho(r)[:90], flush=True)
        print("HYP:", norm_ortho(hp)[:90], flush=True)
        print(flush=True)

if __name__ == "__main__":
    main()
