#!/usr/bin/env python3
"""EXPORT A TROIS SORTIES, variante TETE TAJWID LINEAIRE (2026-08-02).

Copie de export_trois_tetes.py qui suppose une ConvTajwidHead (--head_hidden
par defaut 256). Le run `tajwid-sur-final-v1/stagea-stageA` a ete lance SANS
--head_hidden, donc avec la tete par defaut de finetune_dual_head.py :
nn.Linear(512, 19), pas ConvTajwidHead. Charger ce state_dict dans une
ConvTajwidHead echouerait -- ou pire, se chargerait PARTIELLEMENT sans la
moindre erreur (piege documente dans le fichier d'origine). D'ou cette
variante plutot qu'un flag : les deux architectures ont des state_dict de
forme differente, mieux vaut deux fichiers explicites qu'un branchement qui
peut se tromper silencieusement.

    sortie 0  logprobs         (batch, T, 1025)  lettres, log_softmax
    sortie 1  tajwid_logprobs  (batch, T,   19)  regles, logSIGMOID (independantes)
    sortie 2  encoder_state    (batch, T,  512)  etat brut, pour la tete 3

── POURQUOI LE SCRIPT D'ORIGINE EXISTE ─────────────────────────────────────
Au 2026-07-31 le projet a DEUX tetes entrainees et ZERO deployee, faute d'un
exporteur capable de les sortir ensemble :
  exporter_tete3.py            -> logprobs + encoder_state
  export_dual_head_multilabel  -> logprobs + tajwid_logprobs
Chacun en sort deux, aucun les trois. C'etait le goulot reel -- pas
l'entrainement.

── L'ORDRE DES SORTIES EST UN CONTRAT ──────────────────────────────────────
`logprobs` DOIT rester en position 0 : le plugin Kotlin historique lit out[0].
Les deux autres sont recuperees PAR NOM (`FastConformerCtc.TAJWID_OUTPUT` et
`ENCODER_STATE_OUTPUT`), donc un modele qui ne les a pas continue de marcher
sans erreur -- c'est ce qui permet de revenir en arriere sans toucher a l'app.

── PIEGES DEJA PAYES, NE PAS LES REPAYER ───────────────────────────────────
1. `audio_signal` ET JAMAIS `raw_audio`. L'app calcule le mel elle-meme
   (MelSpectrogram.kt). Un export "E2E" valide pourtant tres bien PyTorch==ONNX
   et se charge sur le telephone (« Modele charge : true », rassurant et
   trompeur) mais CHAQUE transcription echoue en silence. Verifie ici avant
   d'ecrire quoi que ce soit.
2. Les poids ECRITS A COTE (model.onnx + model.onnx.data). Le fichier "marche"
   sur le PC parce que le .data est a cote, et echoue sur le telephone ou seul
   model.onnx est copie. On refusionne en un fichier unique.
3. « Le modele est charge » ne prouve RIEN sur son utilisabilite. Ce script
   decode donc un vrai signal et compare PyTorch a ONNX.

── CE QUE CE SCRIPT NE FAIT PAS ────────────────────────────────────────────
Il n'entraine rien et n'ecrit jamais sur la source. Le .nemo est lu, la tete
tajwid est lue, rien d'autre n'est touche.
"""
import os

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import argparse
import json
import shutil
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

BASE = Path(__file__).parent
N_RULES = 19


class TroisTetes(nn.Module):
    """UN encodeur, TROIS sorties. L'encodeur est le gros du calcul ; lire deux
    tetes de plus ne coute qu'une projection lineaire chacune. C'est tout
    l'interet de l'encodeur partage -- une passe, trois reponses."""

    def __init__(self, model, tajwid_head):
        super().__init__()
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder
        self.tajwid_head = tajwid_head

    def forward(self, audio_signal: torch.Tensor, length: torch.Tensor):
        encoded, _ = self.encoder(audio_signal=audio_signal, length=length)
        letters = torch.nn.functional.log_softmax(
            self.ctc_decoder(encoder_output=encoded), dim=-1)
        # logSIGMOID et non log_softmax : chaque regle est INDEPENDANTE.
        # Un softmax force un seul gagnant par frame -- c'est le defaut mesure
        # sur ٱلنَّاسِ, ou ghunnah et laam_shamsiyah se realisent sur les MEMES
        # frames et ne pouvaient jamais etre detectees ensemble.
        #
        # -softplus(-x) et NON F.logsigmoid (2026-08-02) : mathematiquement
        # identiques, mais l'export ONNX de F.logsigmoid (ORT n'a pas
        # d'operateur LogSigmoid natif, il decompose) a produit un ecart de
        # 1,05e-2 par rapport a PyTorch sur les logits tres negatifs (~-11,6,
        # le cas frequent ici : la plupart des regles sont absentes de la
        # plupart des frames) -- diagnostique : le logit brut ne divergeait
        # QUE de 1,1e-5, la divergence naissait bien dans la decomposition de
        # logsigmoid. `Softplus` EST un operateur ONNX natif ; l'ecrire
        # explicitement fait retomber l'ecart a 1,1e-5, sous le seuil de
        # verification (1e-3) qui suit plus bas.
        tajwid = -torch.nn.functional.softplus(-self.tajwid_head(
            encoded.transpose(1, 2)))
        # (B, D, T) -> (B, T, D) : meme convention temporelle que les deux
        # autres sorties, pour que la chaine indexe les trois par la meme frame.
        etat = encoded.transpose(1, 2)
        return letters, tajwid, etat


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", required=True,
                   help="checkpoint .nemo (encodeur + tete lettres)")
    p.add_argument("--tete_tajwid", required=True,
                   help="state_dict de la tete tajwid (stagea-tajwid-head.pt)")
    # Defaut 0 ICI (contrairement au script d'origine) : c'est nn.Linear par
    # defaut dans finetune_dual_head.py, et c'est ce qu'a produit le run
    # tajwid-sur-final-v1/stagea-stageA.
    p.add_argument("--head_hidden", type=int, default=0)
    p.add_argument("--tete3", default=None,
                   help="tete3.json a copier a cote (applique par l'appelant, "
                        "PAS dans le ONNX : elle a besoin de grandeurs "
                        "conditionnees par la CIBLE, que seul l'appelant connait)")
    p.add_argument("--deploy_source", default=None,
                   help="dossier d'ou copier vocab.json / word_tokens.json / rules.json")
    p.add_argument("--sortie", required=True)
    a = p.parse_args()

    out = Path(a.sortie)
    out.mkdir(parents=True, exist_ok=True)
    print(f"source (jamais modifiee) : {a.nemo}")
    print(f"sortie                   : {out}\n")

    import nemo.collections.asr as nemo_asr
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        a.nemo, map_location="cpu")
    model.eval()

    d = model.encoder._feat_out
    # Meme branchement que finetune_dual_head.py : head_hidden=0 -> Linear
    # directe, sinon ConvTajwidHead. Le state_dict tranche de lui-meme si le
    # mauvais type est choisi (cle "weight"/"bias" pour Linear contre
    # "conv.weight"/"out.weight" etc pour ConvTajwidHead) -- load_state_dict
    # leve une erreur explicite plutot que de charger a moitie en silence.
    if a.head_hidden > 0:
        from finetune_dual_head import ConvTajwidHead
        tete = ConvTajwidHead(d, a.head_hidden, N_RULES)
    else:
        tete = nn.Linear(d, N_RULES)
    tete.load_state_dict(torch.load(a.tete_tajwid, map_location="cpu"))
    tete.eval()
    print(f"tete tajwid chargee : {sum(x.numel() for x in tete.parameters())} parametres")

    wrapper = TroisTetes(model, tete).eval()

    # Signal de test : 400 frames de mel (~3,2 s). Sert a la fois de trace pour
    # l'export et de reference pour la comparaison PyTorch/ONNX plus bas.
    mel = torch.randn(1, 80, 400) * 0.5 - 4.0
    lg = torch.tensor([400], dtype=torch.int64)
    with torch.no_grad():
        ref = wrapper(mel, lg)

    tmp = out / "_tmp.onnx"
    torch.onnx.export(
        wrapper, (mel, lg), str(tmp),
        input_names=["audio_signal", "length"],
        output_names=["logprobs", "tajwid_logprobs", "encoder_state"],
        dynamic_axes={"audio_signal": {0: "B", 2: "T"}, "length": {0: "B"},
                      "logprobs": {0: "B", 1: "T"},
                      "tajwid_logprobs": {0: "B", 1: "T"},
                      "encoder_state": {0: "B", 1: "T"}},
        # dynamo=False : SANS ce flag, torch.onnx.export utilise par defaut le
        # nouvel exporteur base sur torch.export (visible dans les logs :
        # « Obtain model graph ... torch.export.export(strict=False) »).
        # Ce chemin a produit ici une divergence PyTorch/ONNX de 8 a 11e-3 sur
        # tajwid_logprobs SEUL (logprobs et encoder_state restaient a ~1e-5) --
        # diagnostique : la tete tajwid EN ISOLATION (Linear+logsigmoid seuls,
        # hors du graphe NeMo) etait fidele a 8,6e-6 avec le meme exporteur,
        # donc ce n'est pas la tete qui est en cause, c'est l'interaction avec
        # le graphe complet sous ce chemin d'export precis.
        # export_causal_checkpoint.py, export_dual_head_checkpoint.py et
        # export_dual_head_multilabel.py -- les trois scripts DEJA verifies
        # PyTorch==ONNX sur ce projet -- passent tous `dynamo=False` et
        # `opset_version=17`. Alignement sur ce qui est deja mesure fiable,
        # plutot que de continuer a chercher pourquoi le nouveau chemin diverge.
        opset_version=17, dynamo=False, do_constant_folding=True,
    )

    # PIEGE 2 : refusionner les poids externes en UN fichier. Un modele en deux
    # morceaux marche sur le PC (le .data est a cote) et echoue sur le telephone.
    import onnx
    m = onnx.load(str(tmp), load_external_data=True)
    final = out / "model.onnx"
    onnx.save_model(m, str(final), save_as_external_data=False)
    for f in out.glob("_tmp.onnx*"):
        f.unlink()

    # PIEGE 1 + 3 : verifier les ENTREES et une vraie inference, pas seulement
    # que le fichier se charge.
    import onnxruntime as ort
    sess = ort.InferenceSession(str(final), providers=["CPUExecutionProvider"])
    entrees = [i.name for i in sess.get_inputs()]
    sorties = [o.name for o in sess.get_outputs()]
    print(f"\nentrees : {entrees}")
    print(f"sorties : {sorties}")
    if "audio_signal" not in entrees:
        raise SystemExit("REFUS : pas d'entree `audio_signal` -- inutilisable "
                         "par l'app (elle calcule le mel elle-meme).")
    if sorties[0] != "logprobs":
        raise SystemExit("REFUS : `logprobs` doit rester en position 0 "
                         "(le plugin Kotlin historique lit out[0]).")

    o = sess.run(None, {"audio_signal": mel.numpy(), "length": lg.numpy()})
    for nom, att, obt in zip(sorties, ref, o):
        e = float(np.abs(att.numpy() - obt).max())
        print(f"  {nom:16s} {tuple(obt.shape)}  ecart PyTorch/ONNX {e:.2e}")
        if e > 1e-3:
            raise SystemExit(f"REFUS : {nom} diverge entre PyTorch et ONNX")

    for nom in ("vocab.json", "word_tokens.json", "rules.json"):
        if a.deploy_source:
            src = Path(a.deploy_source) / nom
            if src.exists():
                shutil.copy2(src, out / nom)
                print(f"  {nom} copie")
    if a.tete3:
        shutil.copy2(a.tete3, out / "tete3.json")
        print("  tete3.json copie")

    mo = final.stat().st_size / 1e6
    print(f"\nmodel.onnx : {mo:.0f} Mo, fichier UNIQUE")
    manquants = [n for n in ("vocab.json", "word_tokens.json", "rules.json")
                 if not (out / n).exists()]
    if manquants:
        print(f"⚠️  MANQUANT pour le deploiement : {', '.join(manquants)}")
        print("   rules.json absent = verdicts tajwid DESACTIVES cote app "
              "(hasTajwidHead exige les deux : la sortie ET les noms).")


if __name__ == "__main__":
    main()
