"""
Export Whisper fine-tuné vers ONNX pour déploiement on-device (sherpa-onnx / Android).

Usage:
  python export_onnx.py [--model small|medium] [--opset 17]

Sortie:
  models/whisper-small-ft-onnx/   (encoder.onnx + decoder.onnx + configs)
  models/whisper-medium-ft-onnx/
"""
import os, sys, argparse
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

ROOT = os.path.dirname(os.path.abspath(__file__))

ap = argparse.ArgumentParser()
ap.add_argument("--model", choices=["small", "medium", "both"], default="small")
ap.add_argument("--opset", type=int, default=17)
args = ap.parse_args()

MODELS = {
    "small":  ("whisper-small-ft",  "whisper-small-ft-onnx"),
    "medium": ("whisper-medium-ft", "whisper-medium-ft-onnx"),
}

def export_model(key: str):
    src_name, dst_name = MODELS[key]
    src = os.path.join(ROOT, "models", src_name)
    dst = os.path.join(ROOT, "models", dst_name)

    if not os.path.isdir(src):
        print(f"Modèle source absent : {src}", flush=True)
        return

    print(f"\n{'='*55}", flush=True)
    print(f"Export {src_name} → {dst_name}", flush=True)
    print(f"opset={args.opset}", flush=True)

    from optimum.exporters.onnx import main_export
    main_export(
        model_name_or_path=src,
        output=dst,
        task="automatic-speech-recognition",
        opset=args.opset,
        no_post_process=False,
    )

    # Vérification tailles
    print(f"\nFichiers générés dans {dst} :", flush=True)
    for f in sorted(os.listdir(dst)):
        p = os.path.join(dst, f)
        if os.path.isfile(p):
            size = os.path.getsize(p) / 1e6
            print(f"  {f:<45} {size:>7.1f} MB", flush=True)

    print(f"\nEXPORT {src_name.upper()} ONNX DONE → {dst}", flush=True)


targets = ["small", "medium"] if args.model == "both" else [args.model]
for t in targets:
    export_model(t)
