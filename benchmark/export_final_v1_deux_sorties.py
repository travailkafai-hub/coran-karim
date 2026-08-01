#!/usr/bin/env python3
"""Exporte final-v1 avec DEUX sorties (logprobs + etat encodeur), meme
contrat que le modele actuellement sur le telephone (deploye via
exporter_tete3.py). But : ne pas regresser le contrat d'entree/sortie au
moment de remplacer le modele deploye.

CE QUE CE SCRIPT NE FAIT PAS : il n'entraine PAS tete3.json pour ce nouvel
encodeur -- ca demanderait de reextraire les etats d'encodeur (cf.
tete_encodeur_ecart.py) sur final-v1, jamais fait. tete3.json reste donc celui
de l'ancien encodeur sur le telephone (inerte : rien ne l'appelle, cf.
SUITE_TETE3.md §7 -- a refaire seulement quand un encodeur est valide par
recette device).
"""
import os
import sys
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import torch

BASE = Path(__file__).parent

SRC_NEMO = ("/run/media/kafai/HDD/Coran Karim/benchmark/models/"
            "fastconformer-final-v1/causal-final.nemo")
SRC_DEPLOY = ("/run/media/kafai/HDD/Coran Karim/benchmark/models/"
              "fastconformer-streaming-causal-v1-lr3e4/deploy/fastconformer-ctc-causal-v1")
OUT = BASE / "models" / "final-v1-deux-sorties"


class EncCTCEtatWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder

    def forward(self, audio_signal: torch.Tensor, length: torch.Tensor):
        encoded, _ = self.encoder(audio_signal=audio_signal, length=length)
        logits = self.ctc_decoder(encoder_output=encoded)
        logprobs = torch.nn.functional.log_softmax(logits, dim=-1)
        return logprobs, encoded.transpose(1, 2)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"source : {SRC_NEMO}")
    print(f"sortie : {OUT}\n")

    import nemo.collections.asr as nemo_asr
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(SRC_NEMO, map_location="cpu")
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    w = EncCTCEtatWrapper(model)
    w.eval()
    n_mels = model.cfg.preprocessor.features
    mel = torch.randn(1, n_mels, 400)
    ln = torch.tensor([400], dtype=torch.int64)
    torch.onnx.export(
        w, (mel, ln), str(OUT / "model.onnx"), opset_version=17,
        input_names=["audio_signal", "length"],
        output_names=["logprobs", "encoder_state"],
        dynamic_axes={"audio_signal": {0: "B", 2: "T"}, "length": {0: "B"},
                      "logprobs": {0: "B", 1: "T"}, "encoder_state": {0: "B", 1: "T"}})

    import onnx
    _m = onnx.load(str(OUT / "model.onnx"))
    onnx.save_model(_m, str(OUT / "model.onnx"), save_as_external_data=False)
    (OUT / "model.onnx.data").unlink(missing_ok=True)

    import onnxruntime as ort
    sess = ort.InferenceSession(str(OUT / "model.onnx"), providers=["CPUExecutionProvider"])
    entrees = [i.name for i in sess.get_inputs()]
    sorties = [o.name for o in sess.get_outputs()]
    if "audio_signal" not in entrees:
        raise SystemExit(f"EXPORT INUTILISABLE : entrees {entrees} (cf. CLAUDE.md)")
    o = sess.run(None, {"audio_signal": mel.numpy(), "length": ln.numpy()})
    with torch.no_grad():
        ref_t = w(mel, ln)
    ecart = max(float(np.abs(o[k] - ref_t[k].numpy()).max()) for k in (0, 1))
    print(f"model.onnx ecrit ({(OUT/'model.onnx').stat().st_size/1e6:.1f} Mo)")
    print(f"  entrees : {entrees}")
    print(f"  sorties : {sorties}   logprobs={o[0].shape}, etat={o[1].shape}")
    print(f"  ecart PyTorch/ONNX : {ecart:.2e}")

    import shutil
    for nom in ("vocab.json", "word_tokens.json"):
        src = Path(SRC_DEPLOY) / nom
        if src.exists():
            shutil.copy2(src, OUT / nom)
            print(f"  {nom} copie")


if __name__ == "__main__":
    main()
