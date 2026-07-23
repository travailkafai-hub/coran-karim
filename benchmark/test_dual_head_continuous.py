"""Test du modele 2 tetes sur un audio CONTINU (sourate entiere en un seul
fichier, pas coupee verset par verset) -- 2026-07-23, complement au test par
clips separes : plus proche des conditions reelles de recitation (pas de
silence artificiel entre les mots d'un meme verset, ni entre versets), et
permet de verifier si le decoupage en clips isoles du test precedent
influencait les resultats (question ouverte suite a la divergence observee
entre le test hors-ligne par clips et le test en direct sur telephone).

Reprend exactement le decodage et l'attribution de test_dual_head_full_surah
.py (frontieres de mots via le marqueur BPE '▁', regles attribuees par
recouvrement de frame), applique une seule fois sur le fichier entier.

Usage :
  PYTHONPATH=... python3.14 test_dual_head_continuous.py <surah> <wav_file> [<wav_file2> ...]
"""
import os, sys
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import torch
import torch.nn as nn
import nemo.collections.asr as nemo_asr
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from test_dual_head_full_surah import (
    load_expected_words, process_clip, _Zero, RULE_CLASSES, N_RULES,
    NEMO_PATH, HEAD_PATH, TAJWID_HEAD_HIDDEN,
)


def main():
    surah = int(sys.argv[1])
    wav_files = sys.argv[2:]
    expected = load_expected_words(surah)

    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO_PATH), map_location="cpu")
    if hasattr(m, "joint"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _Zero()
    m.eval()
    if torch.cuda.is_available():
        m = m.cuda()
    dev = next(m.parameters()).device

    if TAJWID_HEAD_HIDDEN > 0:
        from finetune_dual_head import ConvTajwidHead
        head = ConvTajwidHead(m.encoder._feat_out, TAJWID_HEAD_HIDDEN, N_RULES + 1).to(dev)
    else:
        head = nn.Linear(m.encoder._feat_out, N_RULES + 1).to(dev)
    head.load_state_dict(torch.load(HEAD_PATH, map_location=dev))
    head.eval()
    blank = m.tokenizer.vocab_size

    for wav_path in wav_files:
        words = process_clip(m, head, blank, wav_path)
        n = min(len(words), len(expected))
        if len(words) != len(expected):
            print(f"[{wav_path}] DESALIGNEMENT nb mots : detecte={len(words)} attendu={len(expected)}")

        print(f"\n{'='*70}\n{wav_path}\n{'='*70}")
        n_err = 0
        for k in range(n):
            av, exp_w, exp_cls = expected[k]
            det_txt = words[k]["text"]
            det_cls = words[k]["detected"]
            missing = exp_cls - det_cls
            extra = det_cls - exp_cls
            if missing or extra:
                n_err += 1
                flags = []
                if missing:
                    flags.append(f"MANQUANT={sorted(missing)}")
                if extra:
                    flags.append(f"EN_TROP={sorted(extra)}")
                print(f"  mot#{k+1:3d} verset={av:2d} \"{exp_w}\" (lettres: \"{det_txt}\") "
                      f"attendu={sorted(exp_cls) or '-'} detecte={sorted(det_cls) or '-'}  <<< {' '.join(flags)}")
        print(f"  --- total mots={n}, mots avec ecart={n_err} ({100*n_err/max(n,1):.1f}%) ---")


if __name__ == "__main__":
    main()
