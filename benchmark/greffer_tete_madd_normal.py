# -*- coding: utf-8 -*-
"""Greffe la tete tajwid 12 classes (avec `madd_normal`) sur le pack int8 de
production, au lieu de deployer le modele diagnostique de 464 Mo.

── POURQUOI (question utilisateur, 2026-09-08) ────────────────────────────

« Pourquoi tu peux pas recuperer la tete et la coller au modele deja quantise,
encodeur qui n'a pas change ? »

Il a raison, et j'avais pris le chemin le plus lourd. Ce qui rend la greffe
legitime, verifie et non suppose :

  - l'encodeur est LE MEME : hash SHA-256 des 692 tenseurs, deux methodes
    independantes, meme resultat pour l'encodeur exporte, celui de la tete
    FAMILLE et celui de la tete FINE (cf. CONFIRMATION_ENCODEUR.md). Le
    LISEZ_MOI du run 12 classes le confirme aussi : encodeur
    `warsh-v4-e12-specaugment-2026-08-29`, non renvoye parce que partage.
  - `encoder_state` du pack de production sort en [batch, 512, time], soit
    EXACTEMENT ce que la conv de la tete recoit -- verifie dans le graphe :
    cette sortie et l'entree de `tete_tajwid` ont la meme source
    (`/encoder/layers.16/norm_out/LayerNormalization`) et la meme
    permutation.

CE QUE LA GREFFE FAIT GAGNER, par rapport au modele diagnostique complet :

    modele diagnostique   464 Mo   Hafs seul   pas de tete fine
    greffe sur le pack    135 Mo   Hafs+Warsh  tete fine conservee

── LA RESERVE, ET ELLE EST REELLE ────────────────────────────────────────

La tete a ete entrainee sur un encodeur FP32 ; ici elle lit un encodeur
QUANTISE int8. Mesure du 2026-09-07 sur parole reelle : `encoder_state` int8
contre FP32 donne un ecart median de 0,06 et une correlation de 0,981, et la
bascule de decision sur les tetes tajwid vaut 0,138 % / 0,049 %. L'ecart
existe donc, il est petit, et il est DEJA subi par les tetes actuellement
deployees -- ce n'est pas une degradation propre a cette greffe.

La tete greffee, elle, reste en FP32 : elle est minuscule (conv 512x512x5 +
lineaire 512x12, ~5 Mo) et rien n'oblige a la quantiser.
"""
import json
from pathlib import Path

import numpy as np
import onnx
import torch
import torch.nn as nn
from onnx import helper, numpy_helper

SRC = Path(r'C:\Users\kafai\transfert_2026-09-08_madd_normal')
PACK = Path(r'C:\Users\kafai\transfert_2026-09-07_situation_tajwid'
            r'\modele_production_5tetes')
DEST = Path(r'C:\Users\kafai\AppData\Local\Temp\claude'
            r'\c--Users-kafai-Coran-Karim-portable'
            r'\faf077ad-a7fb-46f2-81c6-c05ef5877686\scratchpad\pack12')

ORDRE_APP = [
    ("madda_necessary", "madd"), ("madda_obligatory", "madd"),
    ("madda_permissible", "madd"), ("madda_normal", "madd_normal"),
    ("ghunnah", "ghunnah"), ("ikhafa", "ikhafa"),
    ("ikhafa_shafawi", "ikhafa_shafawi"), ("idgham_ghunnah", "idgham_ghunnah"),
    ("idgham_shafawi", "idgham_shafawi"), ("iqlab", "iqlab"),
    ("idgham_wo_ghunnah", "idgham_wo_ghunnah"),
    ("idgham_mutajanisayn", "idgham_mutajanisayn"),
    ("idgham_mutaqaribayn", "idgham_mutaqaribayn"),
    ("laam_shamsiyah", None), ("ham_wasl", None), ("slnt", None),
    ("qalaqah", "qalaqah"),
]


class TeteRemappee(nn.Module):
    """La tete 12 classes, suivie du remappage vers les 17 de l'app.

    Structure relevee dans le graphe du modele deploye, pas supposee :
    Conv1d(512,512,noyau 5,padding 2) -> transpose -> GELU EXACT (noeud Erf,
    surtout pas l'approximation tanh) -> Linear -> LogSigmoid.
    """

    def __init__(self, n: int, source: list[int | None]):
        super().__init__()
        self.conv = nn.Conv1d(512, 512, kernel_size=5, padding=2)
        self.out = nn.Linear(512, n)
        self.source = source

    def forward(self, encoder_state):            # [B, 512, T]
        x = self.conv(encoder_state).transpose(1, 2)
        x = nn.functional.gelu(x, approximate='none')
        x = nn.functional.logsigmoid(self.out(x))   # [B, T, 12]
        vide = torch.full_like(x[:, :, :1], -20.0)
        return torch.cat([vide if c is None else x[:, :, c:c + 1]
                          for c in self.source], dim=2)   # [B, T, 17]


def main():
    classes = json.loads((SRC / 'classes_12.json').read_text(encoding='utf-8'))
    idx = {n: i for i, n in enumerate(classes)}
    source = [None if s is None else idx[s] for _, s in ORDRE_APP]

    tete = TeteRemappee(len(classes), source)
    tete.load_state_dict(torch.load(SRC / 'tete_madd_union_plus_normal.pt',
                                    map_location='cpu', weights_only=True),
                         strict=True)
    tete.eval()

    DEST.mkdir(parents=True, exist_ok=True)
    tmp = DEST / '_tete_seule.onnx'
    ech = torch.randn(1, 512, 97)
    torch.onnx.export(
        tete, (ech,), str(tmp), input_names=['encoder_state'],
        output_names=['tajwid_logprobs'],
        dynamic_axes={'encoder_state': {0: 'batch', 2: 'time'},
                      'tajwid_logprobs': {0: 'batch', 1: 'time'}},
        opset_version=17, dynamo=False)

    # ── PARITE : CE QUI COMPTE EST LA BASCULE AU SEUIL ────────────────────
    #
    # L'ecart ABSOLU de log-probabilite est un mauvais critere ici, et c'est
    # mesure : median 2,4e-06, mais quelques valeurs entre -7,8 et -17,9
    # divergent jusqu'a 1,5. C'est la precision de `logsigmoid` en float32 dans
    # les QUEUES -- PyTorch le calcule de facon stable, ONNX l'exporte en
    # `-Softplus(-x)`. Or le seuil de decision vaut ln(0,5) = -0,69 : ces
    # valeurs sont tres loin dessous DES DEUX COTES, aucune decision ne bascule.
    #
    # Meme lecon que pour la quantification int8 le 2026-09-07 : un ecart de
    # log-prob n'est genant que s'il change une decision. On mesure donc la
    # BASCULE au seuil, sur plusieurs echelles d'entree.
    import onnxruntime as ort
    s = ort.InferenceSession(str(tmp), providers=['CPUExecutionProvider'])
    seuil = float(np.log(0.5))
    total = bascules = 0
    for echelle in (0.05, 0.2, 1.0):
        x = torch.randn(1, 512, 97) * echelle
        a = tete(x).detach().numpy()
        b = s.run(None, {'encoder_state': x.numpy()})[0]
        fini = np.isfinite(a) & np.isfinite(b)
        bascules += int(((a[fini] > seuil) != (b[fini] > seuil)).sum())
        total += int(fini.sum())
    pc = 100.0 * bascules / max(total, 1)
    print("tete seule : sortie %s, bascule au seuil %d/%d (%.4f %%) %s"
          % (b.shape, bascules, total, pc, "OK" if bascules == 0 else "A VERIFIER"))
    if bascules:
        raise SystemExit(1)

    # ── Fusion : la sortie tajwid du pack est remplacee par la tete greffee ──
    m = onnx.load(str(PACK / 'model_int8.onnx'))
    g = m.graph
    ancienne = next(o for o in g.output if o.name == 'tajwid_logprobs')
    g.output.remove(ancienne)
    for n in g.node:
        for k, o in enumerate(n.output):
            if o == 'tajwid_logprobs':
                n.output[k] = 'tajwid_logprobs_v7_inutilisee'

    t = onnx.load(str(tmp))
    prefixe = 'mdn_'
    for n in t.graph.node:
        n.name = prefixe + (n.name or '')
        for k, e in enumerate(n.input):
            if e != 'encoder_state':
                n.input[k] = prefixe + e
        for k, o in enumerate(n.output):
            if o != 'tajwid_logprobs':
                n.output[k] = prefixe + o
    for i in t.graph.initializer:
        i.name = prefixe + i.name
    g.node.extend(t.graph.node)
    g.initializer.extend(t.graph.initializer)
    g.output.append(helper.make_tensor_value_info(
        'tajwid_logprobs', onnx.TensorProto.FLOAT, ['batch', 'time', 17]))

    onnx.save(m, str(DEST / 'model.onnx'))
    tmp.unlink()

    (DEST / 'rules.json').write_text(
        json.dumps([n for n, _ in ORDRE_APP], ensure_ascii=False, indent=1),
        encoding='utf-8')
    (DEST / 'seuils_tajwid.json').write_text(
        json.dumps({"seuils": {n: (1.1 if s is None else 0.5)
                               for n, s in ORDRE_APP}},
                   ensure_ascii=False, indent=1), encoding='utf-8')
    mo = (DEST / 'model.onnx').stat().st_size / 1e6
    print("ecrit : %s (%.0f Mo)" % (DEST / 'model.onnx', mo))


if __name__ == '__main__':
    main()
