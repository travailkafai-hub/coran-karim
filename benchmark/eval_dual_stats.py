"""Stats des DEUX tetes ensemble, methode comparable a l'historique du projet
(2026-07-23, demande utilisateur : "pas de regression sur la tete lettres,
comparer au meilleur modele historique").

Tete lettres : val_wer_ctc au sens NeMo (nemo.collections.asr.metrics.wer.
word_error_rate), sur nemo_manifests_mixed/val_canonical.jsonl (14991 versets
Coran, MEME manifest que celui documente dans ETAT_CTC_NEMO.md pour les
mesures historiques -- val_wer_ctc=0,1234 modele deploye epoch14,
0,032-0,058 meilleur jamais mesure mais juge peu fiable/surajuste au studio).
Tourne volontairement sur CPU pour ne jamais ralentir un entrainement GPU en
cours en parallele.

Tete tajwid : reprend eval_tajwid_head.py (rappel/precision par classe).

Usage :
  python3 eval_dual_stats.py --nemo <model.nemo> --head <tajwid_head.pt> [--limit_wer 500] [--limit_tajwid 1970]
"""
import os, json, argparse, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

from collections import Counter
from pathlib import Path

import torch
import torch.nn as nn
import soundfile as sf
import nemo.collections.asr as nemo_asr
from nemo.collections.asr.metrics.wer import word_error_rate

BASE = Path(__file__).parent
VAL_CANONICAL = BASE / "nemo_manifests_mixed" / "val_canonical.jsonl"
VAL_TAJWID = BASE / "nemo_manifests_dual" / "val_manifest.jsonl"

RULE_CLASSES = [
    "madda_necessary", "madda_obligatory", "madda_permissible", "madda_normal",
    "ghunnah", "ikhafa", "ikhafa_shafawi", "idgham_ghunnah", "idgham_shafawi",
    "iqlab", "idgham_wo_ghunnah", "idgham_mutajanisayn", "idgham_mutaqaribayn",
    "laam_shamsiyah", "ham_wasl", "slnt", "qalaqah",
]
N_RULES = len(RULE_CLASSES)
BLANK_TAJWID = N_RULES


class _Zero(nn.Module):
    def forward(self, lp, t, il, tl):
        return lp.sum() * 0.0


def greedy_letters(logp, blank):
    ids = logp[0].argmax(-1).tolist()
    out, prev = [], -1
    for i in ids:
        if i != prev and i != blank:
            out.append(i)
        prev = i
    return out


@torch.no_grad()
def eval_letters(model, limit, seed=0):
    rows = [json.loads(l) for l in open(VAL_CANONICAL, encoding="utf-8")]
    rows = [r for r in rows if Path(r["audio_filepath"]).exists()]
    random.Random(seed).shuffle(rows)
    rows = rows[:limit]
    refs, hyps = [], []
    for i, r in enumerate(rows):
        a, sr = sf.read(r["audio_filepath"], dtype="float32")
        if a.ndim > 1:
            a = a.mean(axis=1)
        at = torch.tensor(a).unsqueeze(0)
        lt = torch.tensor([a.shape[0]], dtype=torch.int64)
        feats, flen = model.preprocessor(input_signal=at, length=lt)
        enc, enc_len = model.encoder(audio_signal=feats, length=flen)
        logits = model.ctc_decoder(encoder_output=enc)
        logp = torch.nn.functional.log_softmax(logits, dim=-1)
        ids = greedy_letters(logp, logp.shape[-1] - 1)
        hyp = model.tokenizer.ids_to_text(ids)
        refs.append(r["text"])
        hyps.append(hyp)
        if (i + 1) % 100 == 0:
            print(f"  lettres {i+1}/{len(rows)}...", flush=True)
    wer = word_error_rate(hyps, refs)
    return wer, len(rows)


@torch.no_grad()
def eval_tajwid(model, head, limit):
    rows = [json.loads(l) for l in open(VAL_TAJWID, encoding="utf-8")]
    rows = [r for r in rows if r.get("text_tajwid")][:limit]
    tp = Counter(); attendu = Counter(); predit = Counter()
    for i, r in enumerate(rows):
        p = r["audio_filepath"]
        if not Path(p).exists():
            continue
        a, sr = sf.read(p, dtype="float32")
        if a.ndim > 1:
            a = a.mean(axis=1)
        at = torch.tensor(a).unsqueeze(0)
        lt = torch.tensor([a.shape[0]], dtype=torch.int64)
        feats, flen = model.preprocessor(input_signal=at, length=lt)
        enc, _ = model.encoder(audio_signal=feats, length=flen)
        logits = head(enc.transpose(1, 2))
        ids = logits[0].argmax(-1).tolist()
        out, prev = [], -1
        for k in ids:
            if k != prev and k != BLANK_TAJWID:
                out.append(k)
            prev = k
        exp = [ord(c) - 0xE000 for c in r["text_tajwid"]]
        ce, cp = Counter(exp), Counter(out)
        for cls in set(ce) | set(cp):
            tp[cls] += min(ce[cls], cp[cls])
            attendu[cls] += ce[cls]
            predit[cls] += cp[cls]
        if (i + 1) % 200 == 0:
            print(f"  tajwid {i+1}/{len(rows)}...", flush=True)
    tot_tp = sum(tp.values()); tot_att = sum(attendu.values()); tot_pred = sum(predit.values())
    rec = tot_tp / tot_att if tot_att else 0
    pre = tot_tp / tot_pred if tot_pred else 0
    f1 = 2 * rec * pre / (rec + pre) if (rec + pre) else 0
    ikhafa_rec = tp[5] / attendu[5] if attendu[5] else float("nan")
    idgham_g_rec = tp[7] / attendu[7] if attendu[7] else float("nan")
    return {"recall": rec, "precision": pre, "f1": f1,
            "ikhafa_recall": ikhafa_rec, "idgham_ghunnah_recall": idgham_g_rec,
            "n": len(rows)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nemo", required=True)
    ap.add_argument("--head", required=True)
    ap.add_argument("--limit_wer", type=int, default=500)
    ap.add_argument("--limit_tajwid", type=int, default=1970)
    ap.add_argument("--label", default=None)
    args = ap.parse_args()

    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        args.nemo, map_location="cpu")
    if hasattr(model, "joint"):
        model.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    model.loss = _Zero()
    model.eval()

    print(f"\n=== {args.label or args.nemo} ===")
    wer, n_w = eval_letters(model, args.limit_wer)
    print(f"LETTRES : val_wer_ctc (methode NeMo, val_canonical.jsonl, n={n_w}) = {wer:.4f}")

    tw = nn.Linear(model.encoder._feat_out, N_RULES + 1)
    tw.load_state_dict(torch.load(args.head, map_location="cpu"))
    tw.eval()
    stats = eval_tajwid(model, tw, args.limit_tajwid)
    print(f"TAJWID  : rappel={stats['recall']:.3f} precision={stats['precision']:.3f} "
          f"F1={stats['f1']:.3f} (n={stats['n']})")
    print(f"          ikhafa_recall={stats['ikhafa_recall']:.3f} "
          f"idgham_ghunnah_recall={stats['idgham_ghunnah_recall']:.3f}")


if __name__ == "__main__":
    main()
