"""WER SEPARE Coran / TTS-ASC sur le modele causal (2026-07-26).

Le manifest de validation (val_manifest.jsonl, 3976 clips) est compose a 50 %
de vraie recitation coranique et 50 % de TTS/Arabic Speech Corpus (arabe
general, non coranique). Le `val_wer_ctc` du training est une MOYENNE
melangee sur les deux -- inutilisable pour juger la performance reelle sur le
Coran, seul usage de l'app. Ce script les separe.
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import torch.multiprocessing as _mp
try: _mp.set_start_method("fork", force=True)
except RuntimeError: pass

import json
import re
from pathlib import Path

import torch
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent


def wer(ref, hyp):
    r, h = ref.split(), hyp.split()
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1): d[i][0] = i
    for j in range(len(h) + 1): d[0][j] = j
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1,
                          d[i-1][j-1] + (r[i-1] != h[j-1]))
    return d[-1][-1], len(r)


def is_tts_asc(path):
    return "tts_augmentation" in path or "arabic_speech_corpus" in path.lower()


import argparse

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ckpt", default=str(BASE / "models/fastconformer-streaming-causal-v1-lr3e4/causal-final.nemo"))
    ap.add_argument("--causal", action="store_true", help="fixe le contexte a [70,13] (modele causal uniquement)")
    a = ap.parse_args()
    ckpt = Path(a.ckpt)
    val_manifest = BASE / "nemo_manifests_dual/val_manifest.jsonl"

    print(f"Chargement : {ckpt}")
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(ckpt), map_location="cuda")
    m.eval()
    # FORCER le decodage CTC (2026-07-26, correctif methodologique) : par
    # defaut `cur_decoder == "rnnt"` sur CE checkpoint hybride (verifie), et le
    # RNNT n'a JAMAIS ete entraine (neutralise partout via _ZeroRNNTLoss) --
    # son decodage produit du charabia en boucle (WER > 90 mesure sur
    # mixed-e14 avant ce correctif). L'app n'utilise QUE le CTC
    # (GOP/ForcedAligner), et c'est ce que `val_wer_ctc` mesure pendant
    # l'entrainement -- seule comparaison qui a un sens.
    m.change_decoding_strategy(decoder_type="ctc")
    if a.causal:
        m.encoder.set_default_att_context_size([70, 13])

    lines = [json.loads(l) for l in open(val_manifest, encoding="utf-8")]
    lines = [d for d in lines if Path(d["audio_filepath"]).exists()]
    print(f"{len(lines)} clips valides\n")

    groups = {"coran": [], "tts_asc": []}
    for d in lines:
        (groups["tts_asc"] if is_tts_asc(d["audio_filepath"]) else groups["coran"]).append(d)

    for name, items in groups.items():
        files = [d["audio_filepath"] for d in items]
        refs = [d["text"] for d in items]
        with torch.no_grad():
            hyps = m.transcribe(files, batch_size=16, verbose=False)
        hyps = [str(getattr(h, "text", h)) for h in hyps]
        e_sum = n_sum = 0
        for r, h in zip(refs, hyps):
            e, n = wer(r, h)
            e_sum += e; n_sum += n
        print(f"{name:10s} : {len(items):>5d} clips  WER = {e_sum/max(n_sum,1):.3f}  "
              f"({e_sum} erreurs / {n_sum} mots de reference)")
        for r, h in list(zip(refs, hyps))[:3]:
            print(f"    attendu : {r[:60]}")
            print(f"    obtenu  : {h[:60]}")


if __name__ == "__main__":
    main()
