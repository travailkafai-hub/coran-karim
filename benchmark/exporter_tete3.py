#!/usr/bin/env python3
"""Colle la TETE 3 (ecart au canonique) sur le modele ACTUEL DE L'APP.

Demande utilisateur 2026-07-31 : « tu colles la tete 3 sur le modele actuel de
l'app, fais une copie pour ne pas toucher celui de l'application ».

CE QUI EST TOUCHE : rien. Le .nemo source est lu, jamais ecrit ; tout est
produit dans un dossier NEUF. Le model.onnx du telephone reste tel quel tant que
personne ne le remplace.

CE QUE LE MODELE EXPORTE CHANGE, ET CE QU'IL NE CHANGE PAS
  - sortie 0 = logprobs (batch, T, 1025)  -- INCHANGEE, meme tenseur qu'avant,
    donc le plugin Kotlin actuel continue de fonctionner sans modification ;
  - sortie 1 = etat de l'encodeur (batch, T, 512) -- AJOUTEE. C'est ce que la
    tete lit, et c'est ce qui manquait : les logprobs sont la projection de ces
    512 dimensions sur 1025 classes, apprise pour TRANSCRIRE. Mesure du
    2026-07-31 : une tete sur les logprobs seuls ne gagne rien (26 % contre
    28 %), la meme tete sur l'etat de l'encodeur gagne.
  - entrees INCHANGEES (audio_signal, length). Piege documente dans CLAUDE.md :
    un export en `raw_audio` se charge tres bien et echoue silencieusement a
    chaque transcription.

LA TETE N'EST PAS DANS LE ONNX, ET C'EST VOULU. Elle a besoin de grandeurs
CONDITIONNEES PAR LA CIBLE (score force du mot attendu, score de sa meilleure
confusion...) que seul l'appelant connait -- l'app sait quel mot est attendu, le
modele non. Elle est donc livree a part, en JSON : 16 833 parametres, ~70 Ko,
appliques par mot cote Kotlin. Une tete qui ne lirait QUE l'acoustique a ete
mesuree : 6 a 13 % de detection, la PIRE de toutes. Sans la cible, la question
n'a pas de sens -- un ص correct et un س correct sonnent tous deux corrects.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 exporter_tete3.py
"""
import argparse
import json
import os
import shutil
import sys
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from tete_ecart_canonique import NOMS, detection_a_collateral, entrainer  # noqa: E402

SRC_NEMO = ("/run/media/kafai/HDD/Coran Karim/benchmark/models/"
            "fastconformer-streaming-causal-v1-lr3e4/causal-final.nemo")
SRC_DEPLOY = ("/run/media/kafai/HDD/Coran Karim/benchmark/models/"
              "fastconformer-streaming-causal-v1-lr3e4/deploy/fastconformer-ctc-causal-v1")


class EncCTCEtatWrapper(torch.nn.Module):
    """Meme wrapper que l'export deploye, avec l'etat de l'encodeur EN PLUS.

    L'ordre des sorties compte : logprobs d'abord, pour que le plugin Kotlin
    actuel (qui lit out[0]) continue de fonctionner sans modification.
    """

    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder

    def forward(self, audio_signal: torch.Tensor, length: torch.Tensor):
        encoded, _ = self.encoder(audio_signal=audio_signal, length=length)
        logits = self.ctc_decoder(encoder_output=encoded)
        logprobs = torch.nn.functional.log_softmax(logits, dim=-1)
        return logprobs, encoded.transpose(1, 2)      # (B,T,V), (B,T,512)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", default=SRC_NEMO)
    p.add_argument("--deploy-source", default=SRC_DEPLOY)
    p.add_argument("--sortie", default=str(BASE / "models" / "tete3-sur-modele-app"))
    p.add_argument("--etats", default="/tmp/claude-1000/etats_encodeur_AVANT.npz",
                   help="etats d'encodeur DE CE MODELE, extraits par tete_encodeur_ecart.py")
    p.add_argument("--n-test", type=int, default=189)
    args = p.parse_args()

    out = Path(args.sortie)
    out.mkdir(parents=True, exist_ok=True)
    print(f"source (jamais modifiee) : {args.nemo}")
    print(f"sortie                   : {out}\n")

    # --- 1. la tete, entrainee sur les etats de CE modele -------------------
    z = np.load(args.etats)
    E, X, y, test = z["E"], z["X"], z["y"], z["test"]
    ok = np.isfinite(X).all(axis=1) & (np.abs(X) < 1e6).all(axis=1) \
        & np.isfinite(E).all(axis=1)
    E, X, y, test = E[ok], X[ok], y[ok], test[ok]
    ap, at = ~test, test
    A = np.hstack([E, X]).astype(np.float32)
    mu, sd = A[ap].mean(0), A[ap].std(0) + 1e-6
    An = (A - mu) / sd
    poids = float((y[ap] == 0).sum() / max(1, (y[ap] == 1).sum()))
    tete, npar, _ = entrainer(An[ap], y[ap], poids, epochs=1200)
    with torch.no_grad():
        s = tete(torch.tensor(An[at], dtype=torch.float32)).squeeze(1).numpy()
    det2, seuil2 = detection_a_collateral(s[y[at] == 1], s[y[at] == 0], 0.02)
    det10, seuil10 = detection_a_collateral(s[y[at] == 1], s[y[at] == 0], 0.10)
    ref = -X[at][:, NOMS.index("gopC")]
    detC, _ = detection_a_collateral(ref[y[at] == 1], ref[y[at] == 0], 0.02)
    print(f"tete entrainee : {npar} parametres, {ap.sum()} mots d'entrainement")
    print(f"  detection a  2 % de collateral : {100*det2:.0f} %  "
          f"(regle C seule sur ce modele : {100*detC:.0f} %)")
    print(f"  detection a 10 % de collateral : {100*det10:.0f} %\n")

    poids_json = {
        "description": "tete 3 -- ecart au canonique. Entree = [etat encodeur "
                       "moyenne sur les frames du mot (512), puis les 12 scores "
                       "conditionnes par la cible]. Sortie = logit ; plus il est "
                       "haut, plus le mot devie de ce qui etait attendu.",
        "caracteristiques": ["etat_encodeur_moyen[512]"] + NOMS,
        "normalisation": {"moyenne": mu.tolist(), "ecart_type": sd.tolist()},
        "couches": [{"poids": tete[0].weight.detach().numpy().tolist(),
                     "biais": tete[0].bias.detach().numpy().tolist(),
                     "activation": "relu"},
                    {"poids": tete[2].weight.detach().numpy().tolist(),
                     "biais": tete[2].bias.detach().numpy().tolist(),
                     "activation": "aucune"}],
        "seuils_mesures": {"collateral_2pct": float(seuil2),
                           "collateral_10pct": float(seuil10)},
        "mesure": {"detection_a_2pct": float(det2), "detection_a_10pct": float(det10),
                   "regle_C_seule_a_2pct": float(detC),
                   "jeu": f"{args.n_test} phrases tenues a l'ecart, audio reellement faute"},
    }
    (out / "tete3.json").write_text(json.dumps(poids_json, ensure_ascii=False),
                                    encoding="utf-8")
    ko = (out / "tete3.json").stat().st_size / 1024
    print(f"tete3.json ecrit ({ko:.0f} Ko)")

    # --- 2. le modele, avec l'etat de l'encodeur en sortie ------------------
    import nemo.collections.asr as nemo_asr
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        args.nemo, map_location="cpu")
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    w = EncCTCEtatWrapper(model)
    w.eval()
    n_mels = model.cfg.preprocessor.features
    mel = torch.randn(1, n_mels, 400)
    ln = torch.tensor([400], dtype=torch.int64)
    torch.onnx.export(
        w, (mel, ln), str(out / "model.onnx"), opset_version=17,
        input_names=["audio_signal", "length"],
        output_names=["logprobs", "encoder_state"],
        dynamic_axes={"audio_signal": {0: "B", 2: "T"}, "length": {0: "B"},
                      "logprobs": {0: "B", 1: "T"}, "encoder_state": {0: "B", 1: "T"}})

    # PIEGE : l'exporteur ecrit les poids A COTE (model.onnx.data, 458 Mo) et
    # ne laisse que le graphe (3 Mo) dans le .onnx. Le fichier « marche » sur
    # cette machine parce que le .data est a cote -- et echouerait sur le
    # telephone, ou seul model.onnx est copie. On refusionne en UN fichier,
    # comme l'export deploye.
    import onnx
    _m = onnx.load(str(out / "model.onnx"))
    onnx.save_model(_m, str(out / "model.onnx"), save_as_external_data=False)
    (out / "model.onnx.data").unlink(missing_ok=True)

    import onnxruntime as ort
    sess = ort.InferenceSession(str(out / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    entrees = [i.name for i in sess.get_inputs()]
    sorties = [o.name for o in sess.get_outputs()]
    if "audio_signal" not in entrees:
        raise SystemExit(f"EXPORT INUTILISABLE : entrees {entrees} (cf. CLAUDE.md)")
    o = sess.run(None, {"audio_signal": mel.numpy(), "length": ln.numpy()})
    with torch.no_grad():
        ref_t = w(mel, ln)
    ecart = max(float(np.abs(o[k] - ref_t[k].numpy()).max()) for k in (0, 1))
    print(f"model.onnx ecrit ({(out/'model.onnx').stat().st_size/1e6:.1f} Mo)")
    print(f"  entrees : {entrees}   (audio_signal confirme)")
    print(f"  sorties : {sorties}   logprobs={o[0].shape}, etat={o[1].shape}")
    print(f"  ecart PyTorch/ONNX : {ecart:.2e}")

    for nom in ("vocab.json", "word_tokens.json"):
        src = Path(args.deploy_source) / nom
        if src.exists():
            shutil.copy2(src, out / nom)
            print(f"  {nom} copie")
    print(f"\nLe modele du telephone n'a pas ete touche : "
          f"{args.deploy_source}/model.onnx")


if __name__ == "__main__":
    main()
