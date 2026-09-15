# -*- coding: utf-8 -*-
"""Remappe la tete tajwid 12 classes vers les 17 de l'app, avec un VRAI
canal pour `madda_normal`.

── POURQUOI (2026-09-08) ──────────────────────────────────────────────────

`madd-union-plus-normal-v1` apprend `madd_normal` (rappel brut 83,15 %) la ou
le modele deploye n'a pour elle qu'une CONSTANTE. L'utilisateur veut l'essayer
sur l'appareil.

Mais son export est DIAGNOSTIQUE : 12 classes dans l'ordre d'ENTRAINEMENT, et
`TajwidRule.fromKey` ne connait ni `madd` ni `madd_normal`. Sans remappage,
l'app lirait les bonnes probabilites sous les mauvais noms -- le genre de
defaut qui ne plante pas et colorie faux.

── LE MAPPAGE, ET SON SEUL POINT DELICAT ──────────────────────────────────

Les trois madd longs (necessary / obligatory / permissible) recoivent tous le
canal `madd` : le modele ne les distingue pas, c'est le principe de la fusion.
`madda_normal`, lui, recoit ENFIN son canal propre au lieu d'une constante --
c'est tout l'objet de ce test.

Les quatre regles portees par le texte qui restent (laam_shamsiyah, ham_wasl,
slnt) gardent une constante a -20 : le modele ne les apprend pas.

⚠️ CE MODELE N'A PAS DE SORTIE WARSH. Le pack produit est donc HAFS SEUL --
`FastConformerCtc` traite `warsh_logprobs` comme optionnel, la bascule Warsh
retombera silencieusement sur le Hafs. A ne pas laisser installe pour un
usage Warsh.
"""
import json
from pathlib import Path

import numpy as np
import onnx
from onnx import helper, numpy_helper

SRC = Path(r'C:\Users\kafai\transfert_2026-09-08_madd_normal')
DEST = Path(r'C:\Users\kafai\AppData\Local\Temp\claude'
            r'\c--Users-kafai-Coran-Karim-portable'
            r'\faf077ad-a7fb-46f2-81c6-c05ef5877686\scratchpad\pack12')

# Ordre APP (rules.json du pack de production), et d'ou vient chaque canal.
# None = constante -20 (le modele ne connait pas cette regle).
ORDRE_APP = [
    ("madda_necessary",     "madd"),
    ("madda_obligatory",    "madd"),
    ("madda_permissible",   "madd"),
    ("madda_normal",        "madd_normal"),   # <-- LE canal qui manquait
    ("ghunnah",             "ghunnah"),
    ("ikhafa",              "ikhafa"),
    ("ikhafa_shafawi",      "ikhafa_shafawi"),
    ("idgham_ghunnah",      "idgham_ghunnah"),
    ("idgham_shafawi",      "idgham_shafawi"),
    ("iqlab",               "iqlab"),
    ("idgham_wo_ghunnah",   "idgham_wo_ghunnah"),
    ("idgham_mutajanisayn", "idgham_mutajanisayn"),
    ("idgham_mutaqaribayn", "idgham_mutaqaribayn"),
    ("laam_shamsiyah",      None),
    ("ham_wasl",            None),
    ("slnt",                None),
    ("qalaqah",             "qalaqah"),
]


def main():
    classes = json.loads((SRC / 'classes_12.json').read_text(encoding='utf-8'))
    idx = {nom: i for i, nom in enumerate(classes)}
    manquants = [src for _, src in ORDRE_APP if src and src not in idx]
    if manquants:
        raise SystemExit(f"classes absentes du modele : {manquants}")

    m = onnx.load(str(SRC / 'model_diagnostique_12classes.onnx'))
    g = m.graph
    sortie = next(o for o in g.output if o.name == 'tajwid_logprobs')
    g.output.remove(sortie)
    interne = 'tajwid_logprobs_12'
    for n in g.node:
        for k, o in enumerate(n.output):
            if o == 'tajwid_logprobs':
                n.output[k] = interne

    noeuds, morceaux = [], []
    # Constante -20 : meme forme que la sortie, un seul canal.
    forme = helper.make_node('Shape', [interne], ['forme12'], name='rm_shape')
    deb = numpy_helper.from_array(np.array([0], dtype=np.int64), 'rm_deb')
    fin = numpy_helper.from_array(np.array([2], dtype=np.int64), 'rm_fin')
    ax0 = numpy_helper.from_array(np.array([0], dtype=np.int64), 'rm_ax0')
    val = helper.make_tensor('rm_val', onnx.TensorProto.FLOAT, [1], [-20.0])
    g.initializer.extend([deb, fin, ax0])
    noeuds.append(forme)
    noeuds.append(helper.make_node('Slice', ['forme12', 'rm_deb', 'rm_fin',
                                             'rm_ax0'], ['forme_bt'],
                                   name='rm_slice_bt'))
    un = numpy_helper.from_array(np.array([1], dtype=np.int64), 'rm_un')
    g.initializer.append(un)
    noeuds.append(helper.make_node('Concat', ['forme_bt', 'rm_un'],
                                   ['forme_bt1'], axis=0, name='rm_cat_bt1'))
    noeuds.append(helper.make_node('ConstantOfShape', ['forme_bt1'],
                                   ['rm_const'], value=val, name='rm_const'))

    for i, (nom_app, src) in enumerate(ORDRE_APP):
        if src is None:
            morceaux.append('rm_const')
            continue
        c = idx[src]
        d = numpy_helper.from_array(np.array([c], dtype=np.int64), f'rm_d{i}')
        f = numpy_helper.from_array(np.array([c + 1], dtype=np.int64), f'rm_f{i}')
        a = numpy_helper.from_array(np.array([2], dtype=np.int64), f'rm_a{i}')
        g.initializer.extend([d, f, a])
        noeuds.append(helper.make_node(
            'Slice', [interne, f'rm_d{i}', f'rm_f{i}', f'rm_a{i}'],
            [f'rm_c{i}'], name=f'rm_slice{i}'))
        morceaux.append(f'rm_c{i}')

    noeuds.append(helper.make_node('Concat', morceaux, ['tajwid_logprobs'],
                                   axis=-1, name='rm_concat'))
    g.node.extend(noeuds)
    g.output.append(helper.make_tensor_value_info(
        'tajwid_logprobs', onnx.TensorProto.FLOAT, ['batch', 'time', 17]))

    DEST.mkdir(parents=True, exist_ok=True)
    onnx.save(m, str(DEST / 'model.onnx'), save_as_external_data=False)

    (DEST / 'rules.json').write_text(
        json.dumps([n for n, _ in ORDRE_APP], ensure_ascii=False, indent=1),
        encoding='utf-8')
    # Seuil brut 0,5 partout SAUF les trois portees par le texte (1,1 =
    # infranchissable). `madda_normal` a 0,5 : c'est ce qu'on teste.
    seuils = {n: (1.1 if s is None else 0.5) for n, s in ORDRE_APP}
    (DEST / 'seuils_tajwid.json').write_text(
        json.dumps({"seuils": seuils}, ensure_ascii=False, indent=1),
        encoding='utf-8')
    print("ecrit dans", DEST)
    for n, s in ORDRE_APP:
        print("  %-22s <- %s" % (n, s if s else "CONSTANTE -20"))


if __name__ == '__main__':
    main()
