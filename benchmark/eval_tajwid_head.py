"""Evalue la TETE 2 (tajwid) d'un modele 2 tetes (2026-07-22).

Une loss CTC basse ne prouve PAS que les regles sont detectees : elle peut
s'effondrer en emettant du blank partout (les symboles sont rares par rapport
aux frames). On decode donc reellement la tete et on compare, classe par
classe, les regles predites aux regles attendues.

Metriques par classe :
    rappel    = regles attendues effectivement emises
    precision = regles emises qui etaient bien attendues
Comparaison en MULTI-ENSEMBLE par clip (l'ordre importe peu ici : ce qui
compte cote app est "cette regle a-t-elle ete realisee dans ce mot", pas sa
position exacte dans la sequence).

Usage :
  PYTHONPATH=... python3.14 eval_tajwid_head.py \
      --nemo  models/fastconformer-dual-head-v1/stagea/stagea-final.nemo \
      --head  models/fastconformer-dual-head-v1/stagea/stagea-tajwid-head.pt \
      [--limit 400]
"""
import os, json, argparse
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

from collections import Counter
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import torch.nn as nn
import torch.nn.functional as F
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
VAL = BASE / "nemo_manifests_dual" / "val_manifest.jsonl"

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
N_RULES = len(RULE_CLASSES)
BLANK = N_RULES
PUA_LO = 0xE000


class _Zero(nn.Module):
    def forward(self, lp, t, il, tl):
        return lp.sum() * 0.0


@torch.no_grad()
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nemo", required=True)
    ap.add_argument("--head", required=True)
    ap.add_argument("--limit", type=int, default=400)
    args = ap.parse_args()

    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        args.nemo, map_location="cpu")
    if hasattr(m, "joint"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _Zero()
    m.eval()
    if torch.cuda.is_available():
        m = m.cuda()
    dev = next(m.parameters()).device

    head = nn.Linear(m.encoder._feat_out, N_RULES + 1).to(dev)
    head.load_state_dict(torch.load(args.head, map_location=dev))
    head.eval()

    rows = [json.loads(l) for l in open(VAL, encoding="utf-8")]
    rows = [r for r in rows if r.get("text_tajwid")][:args.limit]
    print(f"clips annotes evalues : {len(rows)}", flush=True)

    tp = Counter()      # vrai positif par classe
    attendu = Counter()
    predit = Counter()
    n_vides = 0

    for i, r in enumerate(rows):
        p = r["audio_filepath"]
        if not Path(p).exists():
            continue
        a, sr = sf.read(p, dtype="float32")
        if a.ndim > 1:
            a = a.mean(axis=1)
        if sr != 16000:
            import librosa
            a = librosa.resample(a, orig_sr=sr, target_sr=16000)
        at = torch.tensor(a, device=dev).unsqueeze(0)
        lt = torch.tensor([a.shape[0]], dtype=torch.int64, device=dev)
        feats, flen = m.preprocessor(input_signal=at, length=lt)
        enc, _ = m.encoder(audio_signal=feats, length=flen)
        logits = head(enc.transpose(1, 2))          # (1, T, 18)
        ids = logits[0].argmax(-1).tolist()

        # decodage CTC glouton : collapse des repetitions + retrait des blanks
        out, prev = [], -1
        for k in ids:
            if k != prev and k != BLANK:
                out.append(k)
            prev = k
        if not out:
            n_vides += 1

        exp = [ord(c) - PUA_LO for c in r["text_tajwid"]]
        ce, cp = Counter(exp), Counter(out)
        for cls in set(ce) | set(cp):
            tp[cls] += min(ce[cls], cp[cls])
            attendu[cls] += ce[cls]
            predit[cls] += cp[cls]
        if (i + 1) % 100 == 0:
            print(f"  {i+1}/{len(rows)}...", flush=True)

    print(f"\nclips ou la tete n'a RIEN emis : {n_vides}/{len(rows)} "
          f"({100*n_vides/max(len(rows),1):.1f} %)")
    print("\n" + "=" * 74)
    print(f"{'classe':<24s} {'attendu':>8s} {'predit':>8s} {'rappel':>8s} "
          f"{'prec':>8s}")
    print("=" * 74)
    tot_tp = tot_att = tot_pred = 0
    for c in range(N_RULES):
        att, pred, v = attendu[c], predit[c], tp[c]
        tot_tp += v
        tot_att += att
        tot_pred += pred
        if att == 0 and pred == 0:
            continue
        rec = v / att if att else float("nan")
        pre = v / pred if pred else float("nan")
        print(f"{RULE_CLASSES[c]:<24s} {att:8d} {pred:8d} "
              f"{rec:8.2f} {pre:8.2f}")
    print("=" * 74)
    rec = tot_tp / tot_att if tot_att else 0
    pre = tot_tp / tot_pred if tot_pred else 0
    f1 = 2 * rec * pre / (rec + pre) if (rec + pre) else 0
    print(f"{'GLOBAL':<24s} {tot_att:8d} {tot_pred:8d} {rec:8.2f} {pre:8.2f}"
          f"   F1={f1:.3f}")


if __name__ == "__main__":
    main()
