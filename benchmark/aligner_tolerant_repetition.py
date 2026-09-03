#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Alignement mot-a-mot TOLERANT AUX REPETITIONS du recitateur.

── LE DEFAUT QU'IL CORRIGE (mesure du 2026-08-27) ──────────────────────────

`word_segments_mp3quran_afasy.json` attribue 8 880 ms au mot 5 de 4:3
(`ٱلْيَتَـٰمَىٰ`) alors que tous les autres mots du verset font 320-2 480 ms.
Consequence a l'ecran : le palier de memorisation affiche le texte jusqu'a
`ٱلْيَتَـٰمَىٰ` pendant que l'audio, lui, va jusqu'a `مِّنَ ٱلنِّسَآءِ`.
Constat utilisateur : « toujours decalage texte verset 3 ».

CAUSE MESUREE, et ce n'est PAS un bug d'aligneur au sens habituel : Al-Afasy
REPETE « فَٱنكِحُوا۟ مَا طَابَ لَكُم مِّنَ ٱلنِّسَآءِ » dans cet
enregistrement. L'audio contient donc ~34 mots prononces pour un verset de 28.
Verifie en decodant SEPAREMENT les deux plages (6,0-12,7 s et 13,7-20,5 s) :
les deux rendent la meme phrase, avec de legeres differences de consonnes --
signature de deux enonciations REELLES, la ou une duplication de donnees
aurait rendu un texte identique au caractere pres.

L'alignement force classique suppose que l'audio contient la cible EXACTEMENT
UNE FOIS. Confronte a 6 mots en trop, il les absorbe dans le segment du mot
qui precede -- d'ou les 8,9 s.

Decision utilisateur (2026-08-27) : « oui l'audio repete mais c'est pas
grave ». La repetition est un fait legitime de la recitation, pas un defaut a
supprimer : c'est l'ALIGNEMENT qui doit savoir la traverser.

── LA METHODE ─────────────────────────────────────────────────────────────

1. Decodage LIBRE (CTC glouton) -> la suite des mots REELLEMENT prononces,
   avec leurs frames. On ne suppose rien sur leur nombre.
2. Appariement de la suite prononcee sur la suite ATTENDUE par plus longue
   sous-sequence commune (LCS) sur les mots normalises. Un passage repete
   produit deux candidats pour les memes mots attendus ; la LCS, qui est
   monotone par construction, n'en retient qu'UNE occurrence -- c'est
   exactement la propriete recherchee, sans avoir a detecter la repetition
   explicitement ni a decider laquelle garder par une regle ad hoc.
3. Les mots attendus qu'aucun mot prononce ne porte (le modele a fondu deux
   mots, ou mal decode) sont interpoles au prorata de leur nombre de lettres
   entre leurs deux voisins ancres -- meme repli que la generation d'origine.

⚠️ CE QUE CE SCRIPT N'EST PAS : une regeneration du jeu de donnees livre. Il
mesure, sur des versets choisis, si cette methode corrige le defaut sans en
introduire un autre. La decision de regenerer (et OU faire tourner le calcul,
cf. la question « pas moyen de faire ca dans l'app ? ») vient apres, au vu de
ces chiffres.

Usage :
    python3 benchmark/aligner_tolerant_repetition.py <verset.wav> <cle_verset>
    ex. : ... /tmp/v4_3.wav 4:3
"""
import io
import json
import os
import re
import sys
import wave
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import onnxruntime as ort

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from mel_numpy_reference import compute_mel_features  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

RACINE = BASE.parent
MODELE = RACINE / "modele_2geles_2026-08-22"
LETTRES = re.compile(r"[ء-غف-يٱٰ]")
DIACRITIQUES = re.compile(r"[ً-ٰٟۖ-ۭـ]")
MARQUE_MOT = "▁"


def normaliser(mot: str) -> str:
    """Reduit un mot a ses consonnes, pour l'appariement SEUL.

    Volontairement plus permissif que `ArabicNormalizer.normalize` de l'app :
    ici on cherche a RECONNAITRE qu'un mot decode correspond a un mot attendu
    malgre les ecarts du decodage libre (`قَابَلَ` pour `طَابَ`), pas a juger
    une prononciation. Comparer exactement ferait echouer l'appariement la ou
    l'oreille, elle, ne doute pas.
    """
    return DIACRITIQUES.sub("", mot).replace("ٱ", "ا").replace("ـ", "")


def mots_du_texte(texte: str):
    return [w for w in texte.split() if LETTRES.search(w)]


def decoder_mots(wav_path: str):
    """@return (mots_prononces, ms_par_frame) -- chaque mot porte ses frames."""
    session = ort.InferenceSession(
        str(MODELE / "model_int8.onnx"), providers=["CPUExecutionProvider"])
    vocab = json.load(open(MODELE / "vocab.json", encoding="utf-8"))
    blank = len(vocab)

    with wave.open(wav_path, "rb") as w:
        audio = (np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
                 .astype(np.float32) / 32768.0)
    mel = compute_mel_features(audio).astype(np.float32)[None]
    logprobs = session.run(
        None, {"audio_signal": mel,
               "length": np.array([mel.shape[2]], dtype=np.int64)})[0][0]
    n_frames = logprobs.shape[0]
    ms_par_frame = (len(audio) / 16000 * 1000) / n_frames

    emissions, precedent = [], -1
    for frame, k in enumerate(logprobs.argmax(-1)):
        if k != precedent and k != blank:
            emissions.append((frame, vocab[k]))
        precedent = k

    mots, courant = [], []
    for frame, tok in emissions:
        if tok.startswith(MARQUE_MOT) and courant:
            mots.append(_finir_mot(courant))
            courant = []
        courant.append((frame, tok))
    if courant:
        mots.append(_finir_mot(courant))
    # Les marques de waqf isolees ne sont pas des mots (meme regle que
    # `GameVerse.fromVerse` cote app) : les garder decalerait l'appariement.
    mots = [m for m in mots if LETTRES.search(m["texte"])]
    return mots, ms_par_frame


def _finir_mot(tokens):
    texte = "".join(t for _, t in tokens).replace(MARQUE_MOT, "")
    return {"debut": tokens[0][0], "fin": tokens[-1][0], "texte": texte}


#: Cout d'ENJAMBER un mot prononce sans l'apparier. Strictement positif, et
#: c'est ce qui distingue cette version d'une LCS ordinaire.
#:
#: DEFAUT MESURE SANS LUI (4:3, premier jet) : la LCS maximise le NOMBRE
#: d'appariements, jamais leur compacite. Le mot `مَا` (attendu 7) s'ancrait
#: sur la 1re occurrence tandis que `طَابَ` (attendu 8) s'ancrait sur la
#: SECONDE -- la 1re ayant ete decodee `َابَ`, sans le ط, elle echouait a
#: `_proches`. L'appariement enjambait donc tout le passage repete, et `مَا`
#: heritait d'un segment de 8 135 ms : le defaut d'origine, deplace d'un mot.
#:
#: Avec un cout par mot enjambe, sauter les six mots de la repetition pour
#: gagner UN appariement de plus n'est plus rentable : l'alignement reste dans
#: la meme occurrence.
COUT_SAUT = 0.34

#: Au-dela de ce trou entre deux mots apparies, l'audio intercalaire n'est
#: attribue A PERSONNE (cf. la fin de `aligner`). Cale sur la mesure : les
#: silences ORDINAIRES entre deux mots d'un meme souffle restent tres en
#: dessous, tandis qu'un passage repete ou une longue pause de waqf les
#: depassent largement (8,1 s sur 4:3). Un seuil trop bas hacherait la
#: lecture en retirant les respirations ; trop haut, il rendrait la
#: repetition a son voisin -- exactement le defaut corrige.
TROU_MAX_MS = 2500.0

#: Duree minimale rendue a un mot dont le CTC n'a emis qu'une ou deux frames
#: (cf. le plancher applique en fin d'`aligner`). Ordre de grandeur d'une
#: syllabe : en dessous, la lecture du mot seul est inaudible.
PLANCHER_MOT_MS = 240.0


def apparier(attendus, prononces):
    """Apparie mots ATTENDUS et mots PRONONCES, en penalisant les sauts.

    @return dict {index_attendu: index_prononce}

    C'est ICI que la repetition est traversee : l'appariement est monotone,
    donc un passage dit deux fois ne peut apparier ses mots qu'UNE fois -- la
    seconde occurrence reste non appariee, sans avoir a detecter la
    repetition ni a choisir explicitement quelle occurrence garder.
    """
    a = [normaliser(m) for m in attendus]
    b = [normaliser(m["texte"]) for m in prononces]
    n, p = len(a), len(b)
    NEG = float("-inf")
    # score[i][j] = meilleur score en alignant attendus[i:] sur prononces[j:]
    score = [[0.0] * (p + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(p - 1, -1, -1):
            meilleur = score[i + 1][j]  # mot attendu non prononce (gratuit :
            #                             le modele a pu fondre deux mots)
            saut = score[i][j + 1] - COUT_SAUT  # enjamber un mot prononce
            if saut > meilleur:
                meilleur = saut
            if _proches(a[i], b[j]):
                avec = 1.0 + score[i + 1][j + 1]
                if avec > meilleur:
                    meilleur = avec
            # ── UN MOT PRONONCE POUR DEUX MOTS ATTENDUS ───────────────────
            # Le decodage libre FUSIONNE regulierement deux mots courts en un
            # seul (`مَا` + `طَابَ` -> `مَاطَابَ`) : sans ce cas, aucun des
            # deux ne s'ancre, et tout le passage part en interpolation.
            # MESURE qui l'impose (lot sourate 4, 2026-08-27) : les seuls
            # versets qui resistaient ou regressaient etaient ceux ou le
            # modele rendait MOINS de mots que le texte (4:11, 71 attendus
            # pour 65 dits, couverture 76 % -> pire duree 4 315 ms, une
            # REGRESSION). Les versets a couverture 100 % etaient tous
            # corrects.
            # EGALITE STRICTE, pas `_proches` : mesure du 2026-08-27, avec la
            # tolerance d'une substitution la regle produisait des fusions
            # FANTOMES -- 4:7 passait de 3 048 ms (corrige) a 9 145 ms
            # (aberrant), et le bilan du lot tombait de 4 corriges a 3. Deux
            # mots concatenes forment une chaine longue : y tolerer un ecart
            # rend l'appariement bien trop permissif.
            if i + 1 < n and a[i] + a[i + 1] == b[j]:
                fusion = 1.6 + score[i + 2][j + 1]
                if fusion > meilleur:
                    meilleur = fusion
            score[i][j] = meilleur if meilleur != NEG else 0.0
    paires, i, j = {}, 0, 0
    while i < n and j < p:
        if _proches(a[i], b[j]) and score[i][j] == 1.0 + score[i + 1][j + 1]:
            paires[i] = j
            i, j = i + 1, j + 1
        elif (i + 1 < n and a[i] + a[i + 1] == b[j]
              and score[i][j] == 1.6 + score[i + 2][j + 1]):
            # Les DEUX mots attendus partagent le meme mot prononce : chacun
            # recevra une part de son audio, au prorata des lettres (cf.
            # `aligner`). Mieux que de n'en ancrer aucun.
            paires[i] = j
            paires[i + 1] = j
            i, j = i + 2, j + 1
        elif score[i][j] == score[i + 1][j]:
            i += 1
        else:
            j += 1
    return paires


def _proches(x: str, y: str) -> bool:
    """Deux mots normalises designent-ils le meme mot ?"""
    if x == y:
        return True
    if not x or not y:
        return False
    # Tolerance d'UNE substitution/omission sur les mots assez longs : le
    # decodage libre rend `قَابَلَ` la ou le texte porte `طَابَ`. Exiger
    # l'egalite ferait rater l'ancre sur des mots pourtant bien prononces.
    if abs(len(x) - len(y)) > 1:
        return False
    distance, i, j, ecarts = 0, 0, 0, 0
    while i < len(x) and j < len(y):
        if x[i] == y[j]:
            i, j = i + 1, j + 1
            continue
        ecarts += 1
        if ecarts > 1:
            return False
        if len(x) > len(y):
            i += 1
        elif len(y) > len(x):
            j += 1
        else:
            i, j = i + 1, j + 1
    distance = ecarts + (len(x) - i) + (len(y) - j)
    return distance <= 1 and min(len(x), len(y)) >= 3


def aligner(attendus, prononces, ms_par_frame, duree_ms):
    """@return liste [debut_ms, fin_ms] par mot ATTENDU."""
    paires = apparier(attendus, prononces)
    bornes = [None] * len(attendus)
    # Deux mots attendus peuvent PARTAGER un mot prononce (le modele les a
    # fusionnes, cf. `apparier`) : on decoupe alors son audio entre eux au
    # prorata des lettres, plutot que de leur donner a chacun tout le span --
    # ce qui ferait rejouer deux fois la meme syllabe.
    partages = {}
    for i, j in paires.items():
        partages.setdefault(j, []).append(i)
    for j, indices in partages.items():
        m = prononces[j]
        debut, fin = m["debut"] * ms_par_frame, m["fin"] * ms_par_frame
        if len(indices) == 1:
            bornes[indices[0]] = [debut, fin]
            continue
        indices.sort()
        poids = [max(1, len(normaliser(attendus[k]))) for k in indices]
        total = sum(poids)
        curseur = debut
        for k, w in zip(indices, poids):
            part = (fin - debut) * w / total
            bornes[k] = [curseur, curseur + part]
            curseur += part

    # Mots attendus non ancres -> interpolation au prorata des lettres entre
    # les deux ancres qui les encadrent (meme repli que la generation
    # d'origine, cf. l'en-tete de `mesure_aligneur_segments_mp3quran.py`).
    i = 0
    while i < len(bornes):
        if bornes[i] is not None:
            i += 1
            continue
        debut_trou = i
        while i < len(bornes) and bornes[i] is None:
            i += 1
        fin_trou = i - 1
        gauche = bornes[debut_trou - 1][1] if debut_trou > 0 else 0.0
        droite = bornes[i][0] if i < len(bornes) else duree_ms
        poids = [max(1, len(normaliser(attendus[k])))
                 for k in range(debut_trou, fin_trou + 1)]
        total = sum(poids)
        curseur = gauche
        for k, w in zip(range(debut_trou, fin_trou + 1), poids):
            part = (droite - gauche) * w / total
            bornes[k] = [curseur, curseur + part]
            curseur += part

    # ── LA REPETITION SE COUPE, ELLE NE S'ABSORBE PAS ─────────────────────
    #
    # Frontieres croissantes -- mais PAS jointives a tout prix. La version
    # jointive naive (`milieu = max(fin[k], debut[k+1])`) rend au mot k tout
    # l'audio qui le separe du suivant : quand ce qui les separe est un
    # passage REPETE, le mot herite de plusieurs secondes qu'il n'a pas
    # prononcees. C'est le defaut d'origine (mot 5 de 4:3, 8 880 ms), et il
    # revenait a l'identique sur `مَا` (8 135 ms) apres correction de
    # l'appariement -- deplace, pas supprime.
    #
    # Au-dela de [TROU_MAX_MS], on laisse donc le trou SANS PROPRIETAIRE :
    # le mot garde sa propre fin mesuree. Preference utilisateur explicite
    # (2026-08-27) : « soit on arrive a couper la repetition, c'est bien ;
    # mais si c'est pas possible on laisse la repetition ». Couper est
    # possible ici, et c'est ce que fait cette borne.
    #
    # En deca du seuil, on rejoint bien les bornes : un silence ordinaire
    # entre deux mots doit rester attache au mot qui precede, sinon la
    # lecture d'une plage laisserait tomber ses respirations naturelles.
    for k in range(len(bornes) - 1):
        trou = bornes[k + 1][0] - bornes[k][1]
        if trou <= 0:
            milieu = max(bornes[k][1], bornes[k + 1][0])
            bornes[k][1] = milieu
            bornes[k + 1][0] = milieu
        elif trou <= TROU_MAX_MS:
            bornes[k][1] = bornes[k + 1][0]
        # else : trou laisse tel quel -- personne ne le possede.
    bornes[0][0] = min(bornes[0][0], bornes[0][1])
    if duree_ms - bornes[-1][1] <= TROU_MAX_MS:
        bornes[-1][1] = max(bornes[-1][1], duree_ms)

    # ── PLANCHER DE DUREE ─────────────────────────────────────────────────
    # Le CTC est « peaky » : un mot court peut n'emettre qu'UNE frame, d'ou
    # `debut == fin` et un segment de duree nulle. Sans plancher, demander la
    # lecture de ce mot seul ne fait rien entendre du tout. Le defaut ne se
    # voyait pas avant, la mise en contiguite masquant tout : elle etirait le
    # mot jusqu'au suivant. Maintenant qu'un trou peut rester sans
    # proprietaire, il faut le traiter pour lui-meme.
    #
    # On empiete UNIQUEMENT sur le trou libre a droite, jamais sur le mot
    # suivant : allonger un mot au detriment de son voisin ferait entendre
    # deux fois la meme syllabe.
    for k in range(len(bornes)):
        manque = PLANCHER_MOT_MS - (bornes[k][1] - bornes[k][0])
        if manque <= 0:
            continue
        limite = bornes[k + 1][0] if k + 1 < len(bornes) else duree_ms
        bornes[k][1] = min(bornes[k][1] + manque, limite)
    return bornes


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    wav_path, cle = sys.argv[1], sys.argv[2]

    versets = json.load(
        open(RACINE / "app/assets/data/quran_verses.json", encoding="utf-8"))
    verset = next(v for v in versets if v["verse_key"] == cle)
    attendus = mots_du_texte(verset["text_uthmani"])

    livre = json.load(open(
        RACINE / "app/assets/data/word_segments_mp3quran_afasy.json",
        encoding="utf-8"))[cle]

    prononces, ms_par_frame = decoder_mots(wav_path)
    with wave.open(wav_path, "rb") as w:
        duree_ms = w.getnframes() / w.getframerate() * 1000

    print(f"verset {cle} : {len(attendus)} mots attendus, "
          f"{len(prononces)} mots prononces "
          f"({len(prononces) - len(attendus):+d})")
    print(f"decodage libre : {' '.join(m['texte'] for m in prononces)}\n")

    nouveau = aligner(attendus, prononces, ms_par_frame, duree_ms)
    paires = apparier(attendus, prononces)

    print(f"{'i':>2} {'mot':<15} {'LIVRE debut':>11} {'fin':>8} {'duree':>7}"
          f" | {'NOUVEAU debut':>13} {'fin':>8} {'duree':>7}  ancre")
    for i, mot in enumerate(attendus):
        a0, a1 = livre[i]
        b0, b1 = nouveau[i]
        ancre = "oui" if i in paires else "interpole"
        print(f"{i:>2} {mot:<15} {a0:>11.0f} {a1:>8.0f} {a1 - a0:>7.0f}"
              f" | {b0:>13.0f} {b1:>8.0f} {b1 - b0:>7.0f}  {ancre}")

    pires_livre = max(range(len(attendus)), key=lambda i: livre[i][1] - livre[i][0])
    pires_neuf = max(range(len(attendus)), key=lambda i: nouveau[i][1] - nouveau[i][0])
    print(f"\npire duree LIVRE   : mot {pires_livre} "
          f"({livre[pires_livre][1] - livre[pires_livre][0]:.0f} ms)")
    print(f"pire duree NOUVEAU : mot {pires_neuf} "
          f"({nouveau[pires_neuf][1] - nouveau[pires_neuf][0]:.0f} ms)")


if __name__ == "__main__":
    main()
