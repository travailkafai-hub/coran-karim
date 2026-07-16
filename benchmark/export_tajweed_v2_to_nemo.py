#!/usr/bin/env python3
"""Convertit un checkpoint Lightning tajweed-v2 (.ckpt) en snapshot .nemo autonome.

POURQUOI CE SCRIPT EXISTE (2026-07-16) — deux pieges evites :

 1. `export_augmented_checkpoint.py` restaure l'architecture depuis le .nemo PCD
    puis fait `load_state_dict(..., strict=False)`. Sur un checkpoint TAJWEED
    c'est un piege silencieux : le tokenizer tajweed_bpe_v1 a un vocabulaire
    different du pcd -> la tete CTC n'a pas la meme forme -> strict=False fait
    IGNORER ces poids sans erreur. On exporterait un modele a tete CTC vierge
    en croyant avoir exporte le checkpoint entraine. Ici on applique donc
    change_vocabulary() AVANT le load, et on VERIFIE que missing/unexpected sont
    vides (sortie en erreur sinon).

 2. Reprendre un entrainement via `trainer.fit(ckpt_path=X.ckpt)` restaure aussi
    l'optimiseur, le scheduler et le compteur d'epochs. Quand on change de
    dataset (ici : passage au manifeste mixte Coran+ASC+TTS, 131882 lignes contre
    284823), c'est nefaste : le LR reprend en fin de courbe CosineAnnealing
    (quasi nul -> le modele n'apprend presque rien du nouveau signal) et le
    compteur d'epochs a deja consomme la moitie du budget. D'ou l'export en
    .nemo : `finetune_fastconformer.py --resume X.nemo` charge les POIDS SEULS
    (cf. _restore_ctc_only) et repart avec un optimiseur/scheduler neufs.

ATTENTION a l'usage : le .nemo produit contient DEJA le tokenizer tajweed.
    Relancer l'entrainement dessus AVEC --tokenizer_dir re-appellerait
    change_vocabulary() et REINITIALISERAIT la tete CTC -> tout l'acquis perdu.
    => avec ce .nemo, NE PAS passer --tokenizer_dir.

Usage :
    python3 export_tajweed_v2_to_nemo.py <checkpoint.ckpt> [sortie.nemo]
"""
import sys
from pathlib import Path

import torch
import nemo.collections.asr as nemo_asr

BASE_DIR = Path(__file__).parent
LOCAL_NEMO = BASE_DIR / ".hf" / "nemo_models" / "stt_ar_fastconformer_hybrid_large_pcd_v1.0.nemo"
TOKENIZER_DIR = BASE_DIR / "tokenizers" / "tajweed_bpe_v1"


class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    ckpt_path = Path(sys.argv[1])
    if not ckpt_path.exists():
        raise SystemExit(f"Checkpoint introuvable : {ckpt_path}")
    out_nemo = Path(sys.argv[2]) if len(sys.argv) > 2 else \
        ckpt_path.parent / (ckpt_path.stem + "-snapshot.nemo")

    print(f"Architecture depuis : {LOCAL_NEMO.name}")
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(LOCAL_NEMO), map_location="cpu")
    if hasattr(model, "joint") and hasattr(model.joint, "set_fuse_loss_wer"):
        model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.loss = _ZeroRNNTLoss()
    model.ctc_loss_weight = 1.0

    # OBLIGATOIRE avant le load : aligne la forme de la tete CTC sur le
    # vocabulaire tajweed du checkpoint (cf. piege 1 en en-tete).
    print(f"change_vocabulary -> {TOKENIZER_DIR}")
    model.change_vocabulary(new_tokenizer_dir=str(TOKENIZER_DIR), new_tokenizer_type="bpe")
    if hasattr(model, "joint") and hasattr(model.joint, "set_fuse_loss_wer"):
        model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.loss = _ZeroRNNTLoss()
    model.ctc_loss_weight = 1.0
    print(f"  vocab_size = {model.tokenizer.vocab_size}")

    print(f"Poids depuis : {ckpt_path.name}")
    ckpt = torch.load(str(ckpt_path), map_location="cpu", weights_only=False)
    state_dict = ckpt.get("state_dict", ckpt)
    missing, unexpected = model.load_state_dict(state_dict, strict=False)

    # Verification stricte : un poids manquant/inattendu signifie que le
    # checkpoint ne correspond pas a cette architecture -- on refuse plutot
    # que d'exporter un modele partiellement vierge (cf. piege 1).
    real_missing = [k for k in missing if not k.startswith("loss.")]
    real_unexpected = [k for k in unexpected if not k.startswith("loss.")]
    print(f"  missing={len(real_missing)} unexpected={len(real_unexpected)}")
    if real_missing or real_unexpected:
        print(f"  ex. missing   : {real_missing[:5]}")
        print(f"  ex. unexpected: {real_unexpected[:5]}")
        raise SystemExit(
            "ECHEC : le state_dict ne correspond pas a l'architecture. "
            "Exporter dans cet etat produirait un modele a poids partiels.")

    # Preuve que la tete CTC porte bien des poids entraines (et non une
    # reinitialisation) : une tete vierge a des stats tres differentes.
    w = model.ctc_decoder.decoder_layers[0].weight
    print(f"  tete CTC : shape={tuple(w.shape)} mean={w.mean():.5f} std={w.std():.5f}")

    model.eval()
    out_nemo.parent.mkdir(parents=True, exist_ok=True)
    model.save_to(str(out_nemo))
    print(f"\n.nemo ecrit : {out_nemo} ({out_nemo.stat().st_size/1e6:.1f} Mo)")
    print("\nRelance (SANS --tokenizer_dir, cf. en-tete) :")
    print(f"  --resume {out_nemo}")


if __name__ == "__main__":
    main()
