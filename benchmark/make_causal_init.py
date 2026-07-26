"""Fabrique le checkpoint d'INITIALISATION pour le fine-tune streaming causal.

Un `.nemo` est une archive tar contenant `model_config.yaml` + `model_weights.ckpt`
(+ artefacts tokenizer). On la patche directement :
  1. config : convolutions causales + attention a contexte droit borne ;
  2. poids  : UN SEUL tenseur change de forme.

MESURE (2026-07-25) : sur 707 tenseurs, **706 sont transferables tels quels**.
Le seul incompatible est `encoder.pre_encode.out.weight` --
  reference : [512, 2560] = 256 canaux x 10 bandes de frequence
  causal    : [512, 2816] = 256 canaux x 11 bandes
Le padding causal du sous-echantillonnage `dw_striding` (facteur 8) conserve une
bande de frequence de plus. On ne reinitialise donc PAS ce tenseur au hasard :
on le reinterprete en (512, 256, 10) et on le recopie dans (512, 256, 11), la
bande supplementaire a ZERO. Chaque connexion apprise est preservee a
l'identique, la nouvelle bande ne contribue rien au depart et l'entrainement
apprend a s'en servir. C'est un demarrage a chaud, pas une reinitialisation.
"""
import argparse, shutil, tarfile, tempfile
from pathlib import Path
import torch
from omegaconf import OmegaConf

ap = argparse.ArgumentParser()
ap.add_argument("--src", default="benchmark/models/fastconformer-quran-tajweed-mixed/mixed-e14-snapshot.nemo")
ap.add_argument("--out", default="benchmark/models/streaming-causal-init.nemo")
ap.add_argument("--right-context", type=int, default=1,
                help="att_context_size = [70, R] ; R petit = plus reactif, WER plus haut")
a = ap.parse_args()

src, out = Path(a.src), Path(a.out)
tmp = Path(tempfile.mkdtemp(prefix="causal_"))
with tarfile.open(src) as t:
    t.extractall(tmp)
print(f"extrait : {sorted(p.name for p in tmp.iterdir())}")

cfgp = tmp / "model_config.yaml"
cfg = OmegaConf.load(cfgp)
avant = dict(att_context_style=cfg.encoder.get("att_context_style"),
             att_context_size=cfg.encoder.get("att_context_size"),
             conv_context_size=cfg.encoder.get("conv_context_size"),
             causal_downsampling=cfg.encoder.get("causal_downsampling"))
cfg.encoder.att_context_style = "chunked_limited"
cfg.encoder.att_context_size = [70, a.right_context]
cfg.encoder.conv_context_size = "causal"
cfg.encoder.causal_downsampling = True
OmegaConf.save(cfg, cfgp)
print(f"config : {avant}\n     -> chunked_limited [70,{a.right_context}], conv causal, downsampling causal")

wp = next(p for p in tmp.iterdir() if p.suffix == ".ckpt")
sd = torch.load(wp, map_location="cpu", weights_only=False)
sd = sd.get("state_dict", sd)
K = "encoder.pre_encode.out.weight"
ch = int(cfg.encoder.subsampling_conv_channels)
w = sd[K]
f_src = w.shape[1] // ch
f_tgt = f_src + 1          # verifie empiriquement : 10 -> 11
new = torch.zeros(w.shape[0], ch * f_tgt, dtype=w.dtype)
new.view(w.shape[0], ch, f_tgt)[:, :, :f_src] = w.view(w.shape[0], ch, f_src)
sd[K] = new
print(f"{K} : {tuple(w.shape)} ({ch}x{f_src}) -> {tuple(new.shape)} ({ch}x{f_tgt}), "
      f"bande supplementaire a zero")
torch.save(sd, wp)

out.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(out, "w") as t:
    for p in sorted(tmp.iterdir()):
        t.add(p, arcname=p.name)
shutil.rmtree(tmp)
print(f"ecrit : {out}  ({out.stat().st_size/1e6:.0f} Mo)")
