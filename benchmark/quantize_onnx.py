"""
Quantification INT8 dynamique des fichiers ONNX Whisper.
Réduit la taille ~4x sans perte significative de WER.

Résultat attendu :
  small  float32 ~967 MB  →  INT8 ~245 MB
  medium float32 ~3000 MB →  INT8 ~770 MB

Usage:
  python quantize_onnx.py [--model small|medium|both]
"""
import os, sys, argparse
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

ROOT = os.path.dirname(os.path.abspath(__file__))

ap = argparse.ArgumentParser()
ap.add_argument("--model", choices=["small", "medium", "both"], default="both")
args = ap.parse_args()

from onnxruntime.quantization import quantize_dynamic, QuantType

PAIRS = {
    "small":  ("whisper-small-ft-onnx",  "whisper-small-ft-onnx-int8"),
    "medium": ("whisper-medium-ft-onnx", "whisper-medium-ft-onnx-int8"),
}

def quant(key: str):
    src_dir = os.path.join(ROOT, "models", PAIRS[key][0])
    dst_dir = os.path.join(ROOT, "models", PAIRS[key][1])
    os.makedirs(dst_dir, exist_ok=True)

    if not os.path.isdir(src_dir):
        print(f"Source absente : {src_dir} — lance d'abord export_onnx.py", flush=True)
        return

    print(f"\n{'='*55}", flush=True)
    print(f"Quantification INT8 : {PAIRS[key][0]}", flush=True)

    import shutil
    for f in os.listdir(src_dir):
        if not f.endswith(".onnx"):
            shutil.copy2(os.path.join(src_dir, f), os.path.join(dst_dir, f))

    for fname in ("encoder_model.onnx", "decoder_model.onnx"):
        src_f = os.path.join(src_dir, fname)
        dst_f = os.path.join(dst_dir, fname)
        if not os.path.exists(src_f):
            print(f"  {fname} absent — skip", flush=True)
            continue
        size_before = os.path.getsize(src_f) / 1e6
        print(f"  {fname}  ({size_before:.0f} MB) → quantification INT8...", flush=True)
        quantize_dynamic(
            model_input=src_f,
            model_output=dst_f,
            weight_type=QuantType.QUInt8,
            per_channel=False,
            reduce_range=False,
        )
        size_after = os.path.getsize(dst_f) / 1e6
        print(f"    → {size_after:.0f} MB  (réduction {size_before/size_after:.1f}×)", flush=True)

    total = sum(os.path.getsize(os.path.join(dst_dir, f)) / 1e6
                for f in os.listdir(dst_dir)
                if f.endswith(".onnx"))
    print(f"\nTotal ONNX INT8 ({key}) : {total:.0f} MB → {dst_dir}", flush=True)
    print(f"QUANTIZE {key.upper()} INT8 DONE", flush=True)


targets = ["small", "medium"] if args.model == "both" else [args.model]
for t in targets:
    quant(t)
