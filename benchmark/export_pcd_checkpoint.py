"""
Charge le checkpoint FastConformer CTC (pcd) EN COURS D'ENTRAINEMENT (snapshot,
training pas interrompu) et l'exporte en .nemo + ONNX pour valider tout de suite
le pipeline export -> inference, en parallele du training complet.

Objectif : ne pas attendre la fin du training pour decouvrir un probleme
d'integration (deja arrive avec whisper medium/small) -> on utilise une version
intermediaire (~20% val_wer_ctc) des maintenant.
"""
import os, sys, json, random
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
# Checkpoint a exporter : 1er argument CLI, sinon last.ckpt (attention : le
# periodic/last-v1.ckpt est souvent PLUS recent que last.ckpt, qui n'est
# rafraichi qu'aux points de validation).
CKPT = Path(sys.argv[1]) if len(sys.argv) > 1 else (
    BASE_DIR / "models" / "fastconformer-quran-pcd" / "last.ckpt")
LOCAL_NEMO = BASE_DIR / ".hf" / "nemo_models" / "stt_ar_fastconformer_hybrid_large_pcd_v1.0.nemo"
OUT_NEMO = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"
OUT_ONNX_DIR = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export"

class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0

def main():
    print(f"Restauration architecture (tokenizer OK) depuis : {LOCAL_NEMO}")
    # load_from_checkpoint() direct sur un .ckpt echoue: le tokenizer BPE est un
    # artifact resolu relativement au dossier du .nemo original (app_state.nemo_file_folder),
    # absent du seul .ckpt Lightning -> on restaure d'abord le .nemo (tokenizer OK),
    # puis on ecrase les poids avec le state_dict entraine du .ckpt.
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(LOCAL_NEMO), map_location="cpu")
    if hasattr(model, "joint") and hasattr(model.joint, "set_fuse_loss_wer"):
        model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.loss = _ZeroRNNTLoss()
    model.ctc_loss_weight = 1.0

    print(f"Chargement des poids entraines depuis : {CKPT}")
    ckpt = torch.load(str(CKPT), map_location="cpu", weights_only=False)
    state_dict = ckpt["state_dict"] if "state_dict" in ckpt else ckpt
    missing, unexpected = model.load_state_dict(state_dict, strict=False)
    print(f"  missing={len(missing)} unexpected={len(unexpected)}")
    if missing:
        print(f"  ex. missing: {missing[:5]}")
    if unexpected:
        print(f"  ex. unexpected: {unexpected[:5]}")
    model.eval()
    print("Checkpoint charge OK.")

    OUT_NEMO.parent.mkdir(parents=True, exist_ok=True)
    model.save_to(str(OUT_NEMO))
    print(f".nemo sauvegarde : {OUT_NEMO} ({OUT_NEMO.stat().st_size/1e6:.1f} Mo)")

    # ── Sanity check transcription (CTC greedy) sur qq clips val ────────────
    rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
    random.seed(0)
    sample = random.sample(rows, 3)
    wavs = [r["audio_filepath"] for r in sample]
    refs = [r["text"] for r in sample]

    model.cur_decoder = "ctc"
    with torch.no_grad():
        hyps = model.transcribe(wavs, batch_size=3)
    hyps_txt = [h.text if hasattr(h, "text") else h for h in hyps]

    print("\n=== Sanity check (checkpoint snapshot, CTC greedy) ===")
    for ref, hyp in zip(refs, hyps_txt):
        print(f"REF: {ref}")
        print(f"HYP: {hyp}")
        print()

    # ── Export ONNX ──────────────────────────────────────────────────────────
    OUT_ONNX_DIR.mkdir(parents=True, exist_ok=True)
    onnx_path = OUT_ONNX_DIR / "fastconformer_ctc_pcd.onnx"
    print(f"\nExport ONNX vers {onnx_path} ...")
    model.export(str(onnx_path))
    print(f"Export ONNX termine : {onnx_path.exists()}")
    for f in OUT_ONNX_DIR.iterdir():
        print(f"  {f.name} : {f.stat().st_size/1e6:.1f} Mo")

if __name__ == "__main__":
    main()
