"""
Convertit le checkpoint epoch14 (val_wer_ctc=0.1234, le plus entraine
disponible sur ce PC, cf. analyse val_wer_ctc du 2026-07-18) en snapshot
.nemo complet, en restaurant l'architecture depuis le snapshot epoch2 deja
present dans le meme dossier (meme tokenizer/architecture, juste des poids
plus entraines a superposer) -- meme pattern que export_augmented_checkpoint.py.
"""
import os, sys
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
CKPT = BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "fastconformer-quran-epoch=14-val_wer_ctc=0.123.ckpt"
REF_NEMO = BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "mixed-e02-144-snapshot.nemo"
OUT_NEMO = BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "mixed-e14-snapshot.nemo"


class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def main():
    print(f"Restauration architecture depuis : {REF_NEMO}")
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(REF_NEMO), map_location="cpu")
    if hasattr(model, "joint") and hasattr(model.joint, "set_fuse_loss_wer"):
        model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.loss = _ZeroRNNTLoss()
    model.ctc_loss_weight = 1.0

    print(f"Chargement des poids epoch14 depuis : {CKPT}")
    ckpt = torch.load(str(CKPT), map_location="cpu", weights_only=False)
    state_dict = ckpt["state_dict"] if "state_dict" in ckpt else ckpt
    missing, unexpected = model.load_state_dict(state_dict, strict=False)
    print(f"  missing={len(missing)} unexpected={len(unexpected)}")
    if missing:
        print(f"  ex. missing: {missing[:5]}")
    if unexpected:
        print(f"  ex. unexpected: {unexpected[:5]}")
    model.eval()

    model.save_to(str(OUT_NEMO))
    print(f".nemo sauvegarde : {OUT_NEMO} ({OUT_NEMO.stat().st_size/1e6:.1f} Mo)")

    # Sanity check rapide (CTC greedy) sur 3 clips du manifeste mixed.
    import json, random
    val_path = BASE_DIR / "nemo_manifests_mixed" / "val_mixed.jsonl"
    if val_path.exists():
        rows = [json.loads(l) for l in open(val_path, encoding="utf-8")]
        random.seed(0)
        sample = random.sample(rows, min(3, len(rows)))
        model.cur_decoder = "ctc"
        with torch.no_grad():
            hyps = model.transcribe([r["audio_filepath"] for r in sample], batch_size=3)
        hyps_txt = [h.text if hasattr(h, "text") else h for h in hyps]
        print("\n=== Sanity check (epoch14, CTC greedy) ===")
        for r, hyp in zip(sample, hyps_txt):
            print(f"REF: {r['text']}")
            print(f"HYP: {hyp}")
            print()


if __name__ == "__main__":
    main()
