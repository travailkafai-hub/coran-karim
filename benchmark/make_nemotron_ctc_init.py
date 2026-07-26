"""Assemble un modele CTC entrainable : encodeur PRE-ENTRAINE cache-aware de
Nemotron 3.5 ASR streaming + tete CTC FRAICHE sur NOTRE vocabulaire (tajweed_bpe_v1,
1024 tokens, celui qui porte les harakat -- mixed-e14 et tous les runs depuis).

POURQUOI (2026-07-26, demande utilisateur explicite : "n'abandonne pas
Nemotron3.5, fait un entrainement pousse avec les deux tetes CTC") : le
fine-tune causal maison (causaliser notre propre encodeur offline) a echoue en
usage reel (cf. PROBLEMATIQUES_ASR.md §1.5, curseur gele apres ~35s, 4
politiques de cache rejetees par la mesure). Nemotron 3.5 ASR streaming est un
FastConformer CONCU cache-aware des l'entrainement (att_context_size multi-
lookahead [[56,3],[56,0],[56,6],[56,13]], causal_downsampling=True) -- on
recupere UNIQUEMENT son encodeur, pas son decodeur RNNT (deja ecarte le
2026-07-03 : WER 0,87 strict / 0,67 ortho sur 50 clips zero-shot, cf.
BENCHMARK_RESULTS.md -- mais c'etait sans fine-tuning, et le fine-tuning etait
bloque par une classe NeMo absente, debloquee aujourd'hui en installant NeMo
main (3.1.0) dans un venv Python 3.13 dedie, .venv_nemotron_ft).

CE QUI EST REPRIS TEL QUEL, CE QUI EST NEUF :
  - Encodeur (ConformerEncoder, 609M params, d_model=1024, 24 couches) :
    POIDS PRE-ENTRAINES de Nemotron, fine-tunes ensuite (pas geles -- notre
    propre lecon du 2026-07-24 : geler l'encodeur perd l'acquis de calibration
    fine, cf. ETAT_CTC_NEMO.md regression stagea-multilabel-v1).
  - Preprocesseur : celui de Nemotron (128 mels, pas nos 80 -- l'encodeur a
    ete entraine sur cette distribution, le changer casserait tout).
  - Tete CTC : FRAICHE (ConvASRDecoder), feat_in=1024 (d_model de l'encodeur),
    vocabulaire = tajweed_bpe_v1 (NOTRE tokenizer 1024 tokens incluant les
    harakat -- celui de mixed-e14, jamais change depuis, cf. commentaire
    finetune_dual_head.py). Le vocabulaire natif de Nemotron (13087 tokens,
    multilingue, ~2% arabe) est inadapte au coranique -- on ne le garde pas.
  - Tete tajwid : PAS incluse ici, greffee ensuite par finetune_dual_head.py
    comme pour stage A/B (deja parametre pour ca, aucun changement necessaire
    de ce cote).

⚠️ Tourne dans .venv_nemotron_ft (venv Python 3.13 + NeMo main dedie -- ne
touche JAMAIS .venv_nemo, qui reste la chaine de reference/rollback).

Usage :
    ./.venv_nemotron_ft/bin/python3.13 benchmark/make_nemotron_ctc_init.py
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

from pathlib import Path

import torch
from omegaconf import OmegaConf
import nemo.collections.asr as nemo_asr
from nemo.core import ModelPT

BASE = Path(__file__).parent
NEMOTRON_NEMO = (BASE / ".hf/models--nvidia--nemotron-3.5-asr-streaming-0.6b"
                 "/snapshots/f3d333391852ba876df169dcc9ba902d25b6ab0b"
                 "/nemotron-3.5-asr-streaming-0.6b.nemo")
TOKENIZER_DIR = BASE / "tokenizers/tajweed_bpe_v1"
OUT = BASE / "models/nemotron-ctc-init.nemo"


def main():
    print(f"chargement Nemotron : {NEMOTRON_NEMO}")
    src = ModelPT.restore_from(str(NEMOTRON_NEMO), map_location="cpu")
    print(f"  -> {type(src).__name__}, encodeur {type(src.encoder).__name__}, "
          f"d_model={src.cfg.encoder.d_model}")

    # ── Config du nouveau modele : preprocesseur + encodeur DE NEMOTRON,
    # tokenizer + decodeur CTC NEUFS sur NOTRE vocabulaire. ──────────────────
    cfg = OmegaConf.create({
        "sample_rate": 16000,
        "labels": None,
        "preprocessor": src.cfg.preprocessor,
        "encoder": src.cfg.encoder,
        "tokenizer": {
            "dir": str(TOKENIZER_DIR),
            "type": "bpe",
        },
        "decoder": {
            "_target_": "nemo.collections.asr.modules.ConvASRDecoder",
            "feat_in": int(src.cfg.encoder.d_model),
            "num_classes": -1,  # rempli par NeMo depuis la taille du tokenizer
            "vocabulary": [],   # idem
        },
        "spec_augment": src.cfg.get("spec_augment", None),
        "train_ds": None,
        "validation_ds": None,
        "test_ds": None,
        "optim": {"name": "adamw", "lr": 1e-4},
    })

    print("construction du modele CTC (encodeur Nemotron + tete fraiche)...")
    model = nemo_asr.models.EncDecCTCModelBPE(cfg=cfg)

    # Transplant des poids de l'encodeur pre-entraine -- strict=True : toute
    # divergence de forme/nommage doit remonter tout de suite, pas apres des
    # heures d'entrainement sur un encodeur mal charge.
    missing, unexpected = model.encoder.load_state_dict(
        src.encoder.state_dict(), strict=True)
    assert not missing and not unexpected, (missing, unexpected)
    print("encodeur Nemotron transplante avec succes (strict=True, 0 ecart)")

    n_enc = sum(p.numel() for p in model.encoder.parameters())
    n_dec = sum(p.numel() for p in model.decoder.parameters())
    print(f"parametres : encodeur={n_enc/1e6:.1f}M (pre-entraine) "
          f"decodeur={n_dec/1e6:.1f}M (fraicheur, vocab={model.tokenizer.vocab_size})")

    # ── Verification de continuite : un passage avant ne doit PAS planter,
    # et sa forme de sortie doit correspondre a notre vocabulaire. ──────────
    model.eval()
    dummy = torch.randn(1, cfg.preprocessor.features, 200)
    dummy_len = torch.tensor([200])
    with torch.no_grad():
        logits = model.decoder(encoder_output=model.encoder(
            audio_signal=dummy, length=dummy_len)[0])
    print(f"sortie CTC : {tuple(logits.shape)} "
          f"(attendu : (1, T, {model.tokenizer.vocab_size + 1}))")
    assert logits.shape[-1] == model.tokenizer.vocab_size + 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    model.save_to(str(OUT))
    print(f"\nOK -- ecrit : {OUT} ({OUT.stat().st_size/1e6:.1f} Mo)")
    print("Prochaine etape : fine-tune CTC sur ce checkpoint (nouveau script, "
          "encodeur NON gele -- lecon du 2026-07-24 sur le gel d'encodeur).")


if __name__ == "__main__":
    main()
