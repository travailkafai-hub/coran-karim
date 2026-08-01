"""Frontieres de mots par PROBABILITE DE BLANC -- corrige le defaut "pointu"
de l'alignement Viterbi CTC brut.

── LE PROBLEME MESURE (2026-08-01) ─────────────────────────────────────────
`spans_mots()` (banc_regles_gop.py) donne des largeurs de 1 a 31 frames pour
des mots de longueur comparable -- confirme par inspection directe (44:15,
Yasser_Ad-Dussary) : le premier mot occupe 1 frame quand le dernier en occupe
31. Utiliser ces spans comme bornes de decoupe a donne un WER PIRE (43,3 %)
que la methode par proportions externes qu'il devait remplacer (37,2 %).
Cause : le chemin Viterbi CTC est POINTU par nature -- il marque l'instant de
confiance maximale du modele pour CHAQUE token, pas l'etendue acoustique du
phoneme. Piege deja documente le 2026-07-14 (commit 2ae8dc7) et pas relu
avant d'ecrire la premiere tentative de correction.

── LA CORRECTION : LES PICS DONNENT L'ORDRE, LE BLANC DONNE LA COUPE ───────
Le CTC produit aussi une probabilite de BLANC par frame -- et elle culmine
naturellement entre deux mots consecutifs, la ou le modele estime que "rien
ne se passe" (transition, micro-silence). C'est la technique etablie pour ce
probleme (cf. CTC-segmentation, ESPnet) : ne jamais utiliser un span comme
frontiere directe, seulement comme repere de POSITION -- puis chercher la
vraie coupure en maximisant la probabilite de blanc dans la fenetre bornee
par deux reperes.

Methode :
  1. `spans_mots()` donne un span (ou None) par mot -- sert a placer un
     REPERE (ancre) au CENTRE du span, pas a ses bords.
  2. La frontiere entre le mot i et le mot i+1 = la frame de probabilite de
     blanc MAXIMALE dans la fenetre [ancre_i, ancre_{i+1}].
  3. Meme logique aux deux bords du clip (avant le premier mot, apres le
     dernier) en bornant par 0 et T-1.

A VERIFIER SUR ECHANTILLON AVANT toute generation a l'echelle -- c'est la
regle qui a manque deux fois de suite le 2026-07-31/08-01.
"""
import numpy as np


def ancres_mots(spans, n_frames):
    """Un reper (frame) par mot -- le CENTRE du span Viterbi, ou une
    interpolation si le mot n'a pas ete aligne. Jamais les bords du span :
    c'est leur largeur qui est peu fiable, pas leur position centrale."""
    n = len(spans)
    ancres = [None] * n
    for i, s in enumerate(spans):
        if s is not None:
            ancres[i] = (s[0] + s[1] - 1) / 2.0
    # comble les trous par interpolation lineaire entre voisins connus
    connus = [i for i, a in enumerate(ancres) if a is not None]
    if not connus:
        return None
    for i in range(n):
        if ancres[i] is not None:
            continue
        avant = max((k for k in connus if k < i), default=None)
        apres = min((k for k in connus if k > i), default=None)
        if avant is not None and apres is not None:
            t = (i - avant) / (apres - avant)
            ancres[i] = ancres[avant] + t * (ancres[apres] - ancres[avant])
        elif avant is not None:
            ancres[i] = ancres[avant]
        else:
            ancres[i] = ancres[apres]
    return ancres


def frontieres_par_blanc(lp, spans, blank_id):
    """Rend n+1 frontieres (en FRAMES, pas encore en secondes) : bornes[i] =
    debut du mot i, bornes[n] = fin du dernier mot -- meme convention que
    `frontieres_mots()` (v1) pour rester un remplacement direct.

    Chaque frontiere interieure = argmax de la probabilite de blanc dans la
    fenetre bornee par les deux ancres voisines. Les bords (avant le premier
    mot, apres le dernier) cherchent dans [0, ancre_0] et [ancre_{n-1}, T-1].
    """
    n = len(spans)
    T = lp.shape[0]
    ancres = ancres_mots(spans, T)
    if ancres is None:
        return None
    p_blanc = lp[:, blank_id]

    bornes = [0.0] * (n + 1)
    # bord gauche : silence/transition avant le premier mot
    lo, hi = 0, int(round(ancres[0]))
    bornes[0] = float(lo + np.argmax(p_blanc[lo:hi + 1])) if hi >= lo else 0.0
    # frontieres interieures
    for i in range(1, n):
        lo, hi = int(round(ancres[i - 1])), int(round(ancres[i]))
        if hi <= lo:
            bornes[i] = float(hi)
            continue
        bornes[i] = float(lo + np.argmax(p_blanc[lo:hi + 1]))
    # bord droit : apres le dernier mot
    lo, hi = int(round(ancres[n - 1])), T - 1
    bornes[n] = float(lo + np.argmax(p_blanc[lo:hi + 1])) if hi >= lo else float(T - 1)

    # monotonie stricte -- un argmax degenere ne doit jamais faire reculer le temps
    for i in range(1, n + 1):
        if bornes[i] < bornes[i - 1]:
            bornes[i] = bornes[i - 1]
    return bornes
