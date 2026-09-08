# -*- coding: utf-8 -*-
"""Greffe les tetes tajwid FAMILLE (11) et FINE (76) sur `encoder_state`.

── POURQUOI CE SCRIPT (2026-09-07) ────────────────────────────────────────

Le transfert `transfert_2026-09-07_situation_tajwid` livre deux tetes tajwid
entrainees (poids PyTorch seuls) et son LISEZ_MOI precise qu'elles « ne sont
PAS encore assemblees ensemble dans un seul export ». Question utilisateur :
« c'est possible de le faire ici ? »

Oui, et sans l'encodeur PyTorch, parce que le modele DEPLOYE expose deja
`encoder_state` -- et l'inspection de son graphe montre que cette sortie et
l'entree de sa propre tete tajwid ont **la meme source et la meme
permutation** :

    /encoder/layers.16/norm_out/LayerNormalization  ->  Transpose(0,2,1)
        |                                                    |
        +--> entree de tete_tajwid.conv                       +--> encoder_state

`encoder_state` EST donc, au bit pres, ce que la conv de la tete recoit. Une
tete greffee dessus voit exactement ce que voit la tete d'origine.

── LA STRUCTURE, RELEVEE DANS LE GRAPHE ET NON SUPPOSEE ───────────────────

    Conv1d(512, 512, noyau 5, padding 2)  + biais
    Transpose(0, 2, 1)                     -> [B, T, 512]
    GELU EXACT : x * 0.5 * (1 + erf(x / sqrt(2)))
    Linear(512, N)                         + biais
    LogSigmoid : -softplus(-x)             -> log-probabilites, <= 0

Le GELU est *exact* (noeud `Erf`), pas l'approximation tanh -- releve dans le
graphe deploye, ou la chaine est Erf(Div(x, 1.414...)) -> Add(1) -> Mul(x) ->
Mul(0.5). Se tromper ici donnerait des logits credibles mais faux.

── CE QUE CE SCRIPT NE FAIT PAS ───────────────────────────────────────────

Il ne prouve PAS que ces deux tetes ont ete entrainees sur CET encodeur. Le
LISEZ_MOI l'exige explicitement (« a revérifier pour ces deux checkpoints,
ne pas supposer ») et les `model.onnx` de validation vivent sur l'autre
machine. C'est `comparer_tetes_tajwid.py` qui tranche cela empiriquement, en
confrontant la tete FAMILLE greffee a la tete 17 deja deployee.
"""
import json
from pathlib import Path

import torch
import torch.nn as nn

RACINE = Path(__file__).resolve().parent.parent
TRANSFERT = Path(r'C:\Users\kafai\transfert_2026-09-07_situation_tajwid')
SORTIE = RACINE / 'benchmark' / 'tetes_tajwid_greffees'


class TeteTajwid(nn.Module):
    """Reproduit `tete_tajwid` du modele deploye, pour un nombre de classes libre."""

    def __init__(self, n_classes: int):
        super().__init__()
        self.conv = nn.Conv1d(512, 512, kernel_size=5, padding=2)
        self.out = nn.Linear(512, n_classes)

    def forward(self, encoder_state):          # [B, 512, T]
        x = self.conv(encoder_state)           # [B, 512, T]
        x = x.transpose(1, 2)                  # [B, T, 512]
        # GELU exact, comme le graphe deploye (noeud Erf) -- surtout PAS
        # `approximate='tanh'`, qui donnerait des valeurs proches mais fausses.
        x = nn.functional.gelu(x, approximate='none')
        x = self.out(x)                        # [B, T, N]
        return nn.functional.logsigmoid(x)     # <= 0, comme tajwid_logprobs


def construire(nom_dossier: str, fichier_classes: str, nom_sortie: str):
    src = TRANSFERT / nom_dossier
    classes = json.loads((src / fichier_classes).read_text(encoding='utf-8'))
    poids = torch.load(src / 'tete.pt', map_location='cpu', weights_only=True)

    tete = TeteTajwid(len(classes))
    manquants, inattendus = tete.load_state_dict(poids, strict=True), None
    tete.eval()

    # Parite PyTorch == ONNX sur un vecteur DETERMINISTE. Regle du projet :
    # un export qui « se charge » ne prouve rien (cf. le piege audio_signal
    # tombe deux fois) -- on compare les valeurs, pas le chargement.
    torch.manual_seed(0)
    echantillon = torch.randn(1, 512, 97)

    SORTIE.mkdir(parents=True, exist_ok=True)
    chemin = SORTIE / f'{nom_sortie}.onnx'
    torch.onnx.export(
        tete, (echantillon,), str(chemin),
        input_names=['encoder_state'], output_names=['tajwid_logprobs'],
        dynamic_axes={'encoder_state': {0: 'batch', 2: 'time'},
                      'tajwid_logprobs': {0: 'batch', 1: 'time'}},
        opset_version=17, dynamo=False,
    )
    (SORTIE / f'{nom_sortie}.classes.json').write_text(
        json.dumps(classes, ensure_ascii=False, indent=1), encoding='utf-8')

    import numpy as np
    import onnxruntime as ort
    s = ort.InferenceSession(str(chemin), providers=['CPUExecutionProvider'])
    attendu = tete(echantillon).detach().numpy()
    obtenu = s.run(None, {'encoder_state': echantillon.numpy()})[0]

    # ── POURQUOI ON NE COMPARE PAS BRUTALEMENT LE MAX (2026-09-07) ─────────
    #
    # Premiere version : `np.abs(attendu - obtenu).max()` rendait `inf`.
    # Ce n'etait PAS une divergence : une entree N(0,1) n'a rien de la
    # distribution reelle d'`encoder_state`, les logits explosent, et
    # `logsigmoid` sature a -inf DES DEUX COTES. `-inf - (-inf)` vaut `nan`,
    # et le max le propage. Conclure « divergence » ici aurait ete une erreur
    # de mesure, pas un defaut du modele.
    #
    # On verifie donc DEUX choses separement : les saturations tombent aux
    # memes endroits, et les valeurs finies coincident.
    memes_inf = np.array_equal(np.isfinite(attendu), np.isfinite(obtenu))
    fini = np.isfinite(attendu) & np.isfinite(obtenu)
    ecart = float(np.abs(attendu[fini] - obtenu[fini]).max()) if fini.any() else 0.0
    ok = memes_inf and ecart < 1e-4
    print(f'{nom_sortie:<26} {len(classes):>3} classes  sortie={obtenu.shape}  '
          f'ecart={ecart:.3e}  saturations identiques={memes_inf}  '
          f'{"OK" if ok else "*** DIVERGENCE ***"}')
    return ok


if __name__ == '__main__':
    ok = construire('madd_union_v2_epoch0', 'classes_11.json', 'tajwid_famille_11')
    ok &= construire('fine_v1_cont3_epoch1', 'classes_76.json', 'tajwid_fine_76')
    print()
    print('Ecrit dans :', SORTIE)
    raise SystemExit(0 if ok else 1)
