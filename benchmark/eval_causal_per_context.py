"""WER du modele causal PAR CONTEXTE d'attention (2026-07-25).

Le `val_wer_ctc` du training est une MOYENNE sur les trois contextes tires au
hasard ([70,13], [70,6], [70,1]). Elle melange donc un reglage a 1,04 s de
look-ahead avec un reglage a 80 ms, dont on attend qu'ils n'aient pas du tout le
meme WER. Pour piloter l'entrainement il faut les separer :
  - si [70,13] est deja proche de la cible (0,124 offline) et que [70,1] traine,
    le probleme est le contexte le plus agressif, pas l'adaptation causale ;
  - si les trois sont loin, c'est l'entrainement qu'il faut prolonger.

Lit `val_wer_ctc` uniquement (le RNNT est neutralise, son WER est du bruit --
regle du projet).
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import torch.multiprocessing as _mp
try: _mp.set_start_method("fork", force=True)
except RuntimeError: pass

import argparse, json
from pathlib import Path
import torch
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent


def wer(ref, hyp):
    r, h = ref.split(), hyp.split()
    d = [[0]*(len(h)+1) for _ in range(len(r)+1)]
    for i in range(len(r)+1): d[i][0] = i
    for j in range(len(h)+1): d[0][j] = j
    for i in range(1, len(r)+1):
        for j in range(1, len(h)+1):
            d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1,
                          d[i-1][j-1] + (r[i-1] != h[j-1]))
    return d[-1][-1], len(r)


def norm(s):
    out = []
    for c in s:
        o = ord(c)
        if 0x064B <= o <= 0x0652 or o in (0x0670, 0x0640, 0x06DF, 0x06E0): continue
        if 0xE000 <= o <= 0xF8FF: continue
        if c in "أإآٱ": c = "ا"
        if c == "ى": c = "ي"
        out.append(c)
    return "".join(out)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", required=True, help=".nemo ou .ckpt")
    p.add_argument("--init_nemo", default=str(BASE / "models/streaming-causal-init.nemo"),
                   help="architecture de reference si --ckpt est un .ckpt Lightning")
    p.add_argument("--manifest", default=str(BASE / "nemo_manifests_dual/val_manifest.jsonl"))
    p.add_argument("--n", type=int, default=300)
    p.add_argument("--contexts", default="70,13 70,6 70,1")
    a = p.parse_args()

    if a.ckpt.endswith(".nemo"):
        m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(a.ckpt, map_location="cuda")
    else:
        m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(a.init_nemo, map_location="cuda")
        sd = torch.load(a.ckpt, map_location="cpu", weights_only=False)
        m.load_state_dict(sd.get("state_dict", sd), strict=False)
    m.eval()

    lines = [json.loads(l) for l in open(a.manifest, encoding="utf-8")][:a.n]
    lines = [d for d in lines if Path(d["audio_filepath"]).exists()]
    files = [d["audio_filepath"] for d in lines]
    refs = [d["text"] for d in lines]
    print(f"{len(files)} clips de validation\n")
    print(f"{'contexte':<12s} {'look-ahead':>11s} {'WER strict':>11s} {'WER squelette':>14s}")
    print("-" * 54)

    for spec in a.contexts.split():
        ctx = [int(x) for x in spec.split(",")]
        m.encoder.set_default_att_context_size(ctx)
        with torch.no_grad():
            hyps = m.transcribe(files, batch_size=8, verbose=False)
        hyps = [getattr(h, "text", h) for h in hyps]
        es = ns = eq = nq = 0
        for r, h in zip(refs, hyps):
            e, n = wer(r, str(h)); es += e; ns += n
            e, n = wer(norm(r), norm(str(h))); eq += e; nq += n
        la = ctx[1] * 8 * 0.01
        print(f"{str(ctx):<12s} {la*1000:>9.0f}ms {es/max(ns,1):>11.3f} {eq/max(nq,1):>14.3f}")
    print("\nreference offline (mixed-e14, non causal) : val_wer_ctc = 0,124")


if __name__ == "__main__":
    main()
