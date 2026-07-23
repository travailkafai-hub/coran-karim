"""Test du modele 2 tetes sur des clips de RECITATEURS PROFESSIONNELS
(2026-07-22) -- controle demande par l'utilisateur : les regles manquees ce
soir sur son propre test (iqlab@"بِهَـٰذَا", ikhafa@"فِى"/"ذِى",
idgham_ghunnah@"وَشَفَتَيْنِ"...) sont-elles bien detectees quand la meme
sourate est recitee par un professionnel ? Si oui -> plutot une question de
prononciation chez l'utilisateur. Si non (meme sur un professionnel) ->
faiblesse du modele sur ce contexte acoustique precis, independante de qui
recite.

Usage :
  PYTHONPATH=... python3.14 test_dual_head_reference.py <clip1.wav> [clip2.wav ...]
"""
import os, sys
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import torch
import torch.nn as nn
import torch.nn.functional as F
import soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE = Path(__file__).parent
NEMO_PATH = BASE / "models/fastconformer-dual-head-v1/stagea-long/stagea-final.nemo"
HEAD_PATH = BASE / "models/fastconformer-dual-head-v1/stagea-long/stagea-tajwid-head.pt"

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
N_RULES = len(RULE_CLASSES)


class _Zero(nn.Module):
    def forward(self, lp, t, il, tl):
        return lp.sum() * 0.0


@torch.no_grad()
def main():
    clips = sys.argv[1:]
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO_PATH), map_location="cpu")
    if hasattr(m, "joint"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _Zero()
    m.eval()
    if torch.cuda.is_available():
        m = m.cuda()
    dev = next(m.parameters()).device

    head = nn.Linear(m.encoder._feat_out, N_RULES + 1).to(dev)
    head.load_state_dict(torch.load(HEAD_PATH, map_location=dev))
    head.eval()
    blank = m.tokenizer.vocab_size

    for path in clips:
        a, sr = sf.read(path, dtype="float32")
        if a.ndim > 1:
            a = a.mean(axis=1)
        if sr != 16000:
            import librosa
            a = librosa.resample(a, orig_sr=sr, target_sr=16000)
        at = torch.tensor(a, device=dev).unsqueeze(0)
        lt = torch.tensor([a.shape[0]], dtype=torch.int64, device=dev)
        feats, flen = m.preprocessor(input_signal=at, length=lt)
        enc, _ = m.encoder(audio_signal=feats, length=flen)

        letters_logits = m.ctc_decoder(encoder_output=enc)
        letters_ids = letters_logits[0].argmax(-1).tolist()
        out, prev = [], -1
        for i in letters_ids:
            if i != prev and i != blank:
                out.append(i)
            prev = i
        text = m.tokenizer.ids_to_text(out)

        tajwid_logits = head(enc.transpose(1, 2))
        tajwid_ids = tajwid_logits[0].argmax(-1).tolist()
        tout, tprev = [], -1
        for i in tajwid_ids:
            if i != tprev and i != N_RULES:
                tout.append(i)
            tprev = i
        rules = [RULE_CLASSES[i] for i in tout]

        reciter = Path(path).parts[-2]
        print(f"\n=== {reciter} / {Path(path).name} ===")
        print(f"  lettres : {text}")
        print(f"  regles detectees (ordre) : {rules}")


if __name__ == "__main__":
    main()
