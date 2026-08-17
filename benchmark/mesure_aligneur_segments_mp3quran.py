#!/usr/bin/env python3
"""Mesure l'aligneur force CTC contre les vrais timings mot-a-mot (quran.com,
via benchmark/.timings_cache/{rid}_{surah}.json), pour trancher la question
posee dans PLAN_SORTIE.md §4 : peut-on remplacer les `segments` de Quran
Foundation par notre propre aligneur ?

Critere fixe dans PLAN_SORTIE.md : erreur mediane < 80 ms et 95e centile
< 200 ms, sur au moins 3 passages de nature differente (repetitif, long,
court) -- ici sourates 55, 2, 67.

IMPORTANT -- pourquoi cette mesure est comparable a la tolerance visee et pas
a l'echec documente dans ETAT_CTC_NEMO.md (43,3% WER) : cet echec-la jugeait
des frontieres de clips d'ENTRAINEMENT (tolerance ~0 ms). Ici on tolere du
rejeu audio a l'utilisateur (+-100 ms inaudibles). Les deux mesures ne sont
PAS transposables, cf. PLAN_SORTIE.md §4.

Garde-fous contre le defaut connu du CTC (« peaky » -- une frame de confiance
maximale par mot, le reste du mot n'a pas d'evidence directe) :
  1. plancher de duree par mot (FLOOR_MS) ;
  2. quand l'evidence Viterbi manque pour un mot (span None), on interpole sa
     position au prorata du nombre de lettres plutot que de planter ;
  3. les frontieres finales sont forcees strictement croissantes et non
     chevauchantes (double passe avant/arriere + repli proportionnel si
     l'espace est structurellement insuffisant).

Usage :
    PYTHONPATH=".venv_nemo/lib/python3.14/site-packages" /usr/bin/python3.14 \\
        mesure_aligneur_segments.py [--sourates 55,2,67] [--rid 7] [--limite N]
"""
import argparse
import glob
import json
import os
import statistics as st
import sys
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import onnxruntime as ort
import sentencepiece as spm

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav  # noqa: E402
from banc_regles_gop import spans_mots  # noqa: E402
from gop_fenetre_etroite_vs_large import logprobs  # noqa: E402

FRAME_MS = 80.0  # 10 ms hop mel x 8 sous-echantillonnage encodeur -- verifie
                 # dans plusieurs scripts du projet (bench_durees_depuis_clips.py,
                 # generer_clips_courts_v2.py, export_streaming_onnx*.py)
FLOOR_MS = 150.0  # p5 reel des durees de mots (timings_cache) = 370 ms ;
                  # plancher pris nettement en dessous pour ne contraindre
                  # QUE les cas pathologiques (mot ecrase par la peakiness)
DUREE_MOT_SUSPECTE_MS = 4000.0  # p95 reel des durees de mots = 2990ms (sur
                  # 77392 mots, timings_cache complet) ; au-dessus, l'entree
                  # de reference quran.com est suspecte (fusion/omission),
                  # pas un vrai mot -- cf. 2:213/2:97/2:177/2:112/2:266.
                  # ESSAI ECARTE : seuil baisse a 2000ms pour attraper aussi
                  # les petits trous (2:246, ~2s) -- trop agressif, elimine
                  # aussi de vrais mots longs normaux (p95 reel = 2990ms,
                  # donc un seuil a 2000 rejette une bonne partie du corpus
                  # legitime). 4000ms reste le meilleur compromis mesure.

RECITER_DIR = BASE / "data" / "train_wav_local" / "Alafasy_mp3quran"  # variante MP3Quran (2026-08-16), cf. AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md
VERSES_JSON = BASE.parent / "app" / "assets" / "data" / "quran_verses.json"

RMS_BLOC_MS = 10.0
RMS_FENETRE_MS = 250.0  # rayon de recherche autour du candidat CTC
RMS_SEUIL_CREUX = 0.45  # le creux doit etre < 45% de la moyenne locale pour etre retenu
BLANC_FENETRE_MS = 250.0
BLANC_SEUIL_PIC = 0.60  # proba blanc doit depasser 60% pour etre un pic net
ACCORD_MS = 100.0  # si RMS et blanc s'accordent a moins de 100ms, confiance forte


SILENCE_FIN_SEUIL = 0.02  # meme seuil que le portier RMS de BufferedTranscriber (CLAUDE.md)
SILENCE_FIN_MIN_MS = 200.0  # duree min de silence continu pour compter comme "queue"


def fin_reelle_parole(pcm, total_ms):
    """Fin reelle de la parole (ms), en reculant depuis la fin du fichier tant
    que le bloc est sous le seuil de silence. DECOUVERTE (2026-08-15,
    debogage 67:17/67:30/67:1/67:6) : les 4 pires erreurs de FIN de la
    sourate 67 sont TOUTES le dernier mot du verset, et l'erreur correspond
    EXACTEMENT a la duree de silence de queue du fichier (verifie : 67:17
    2542ms d'erreur = 2542ms de silence de queue, a la ms pres). La frontiere
    de fin qui vaut `total_ms` brut est donc fausse des qu'il y a une queue
    d'enregistrement -- le silence de tete n'a pas ce probleme car le premier
    mot n'utilise jamais 0 comme hypothese, seulement les frontieres
    internes (onset du mot suivant)."""
    env = rms_enveloppe(pcm)
    if len(env) == 0:
        return total_ms
    i = len(env) - 1
    while i >= 0 and env[i] < SILENCE_FIN_SEUIL:
        i -= 1
    fin_ms = (i + 1) * RMS_BLOC_MS
    if total_ms - fin_ms >= SILENCE_FIN_MIN_MS:
        return fin_ms
    return total_ms


def rms_enveloppe(pcm):
    """CHEMIN B (energie brute) : RMS par bloc de RMS_BLOC_MS, meme grain que
    le hop mel (10ms). Peut se tromper sur un souffle ou un phoneme
    naturellement peu energique -- c'est de l'energie, pas de la parole."""
    n = int(RMS_BLOC_MS * 16)  # 16 ech/ms a 16kHz
    nb = len(pcm) // n
    if nb == 0:
        return np.array([])
    return np.sqrt(np.mean(pcm[: nb * n].reshape(nb, n) ** 2, axis=1))


def _creux_rms(t_ms, env):
    if len(env) == 0:
        return None
    demi = int(RMS_FENETRE_MS / RMS_BLOC_MS)
    centre = int(t_ms / RMS_BLOC_MS)
    lo, hi = max(0, centre - demi), min(len(env), centre + demi)
    if hi - lo < 3:
        return None
    fenetre = env[lo:hi]
    moyenne = fenetre.mean()
    if moyenne <= 0:
        return None
    i_min = int(np.argmin(fenetre))
    if fenetre[i_min] < RMS_SEUIL_CREUX * moyenne:
        return (lo + i_min) * RMS_BLOC_MS
    return None


def _pic_blanc(t_ms, lp, blank_idx):
    """CHEMIN C (silence APPRIS par le modele) : proba de "blanc" CTC, distincte
    de l'energie -- reflete ce que le modele juge non informatif/pause, pas le
    volume brut. Cherche le pic de proba blanc pres du candidat CTC."""
    demi = int(BLANC_FENETRE_MS / FRAME_MS)
    centre = int(t_ms / FRAME_MS)
    lo, hi = max(0, centre - demi), min(lp.shape[0], centre + demi)
    if hi - lo < 3:
        return None
    p_blanc = np.exp(lp[lo:hi, blank_idx])
    i_max = int(np.argmax(p_blanc))
    if p_blanc[i_max] > BLANC_SEUIL_PIC:
        return (lo + i_max) * FRAME_MS
    return None


TROU_SUSPECT_MS = 1500.0  # au-dela, plus une pause naturelle qu'un vrai trou
                           # d'enregistrement (souffle/hesitation/montage) que
                           # la reference n'anticipe pas -- cf. 2:213 (6s),
                           # 2:97 (7.6s), 2:246 (2s) : le decodage libre ne
                           # reconnait RIEN sur ce trou alors que tout le reste
                           # du verset s'enchaine correctement et sans faille.


def plus_long_trou_libre(lp):
    """Plus longue plage CONTINUE de "blanc" dans le decodage libre (argmax
    par frame), en ms. Signal DIRECT sur l'audio (pas sur la reference) : un
    long trou = le modele ne reconnait rien la, sans lien avec un mot precis
    -- plus fiable que de deduire l'anomalie via une duree de mot suspecte
    dans le cache quran.com (qui rate les trous en dessous de son seuil)."""
    blank = lp.shape[1] - 1
    ids = lp.argmax(axis=1)
    plus_long = courant = 0
    for i in ids:
        courant = courant + 1 if i == blank else 0
        plus_long = max(plus_long, courant)
    return plus_long * FRAME_MS


def juge_creux_silence(t_ms, env, lp=None, blank_idx=None):
    """LE JUGE : deux chemins independants (energie RMS brute, silence APPRIS
    par le CTC via sa proba de blanc). MESURE (2026-08-15) : le chemin RMS
    seul degrade le resultat (mediane 70->110ms) -- trop de faux positifs
    (un creux d'energie n'est pas toujours une frontiere de mot). Donc : on
    ne corrige QUE si les deux chemins s'accordent (a moins de ACCORD_MS
    l'un de l'autre) -- deux signaux independants qui convergent sont une
    preuve forte ; un seul signal, meme net, ne suffit pas a arbitrer contre
    le modele (chemin A, CTC onset, reste la valeur par defaut)."""
    b = _creux_rms(t_ms, env)
    c = _pic_blanc(t_ms, lp, blank_idx) if lp is not None else None
    if b is not None and c is not None and abs(b - c) <= ACCORD_MS:
        return (b + c) / 2
    return t_ms
    fenetre = env[lo:hi]
    moyenne = fenetre.mean()
    if moyenne <= 0:
        return t_ms
    i_min = int(np.argmin(fenetre))
    if fenetre[i_min] < RMS_SEUIL_CREUX * moyenne:
        return (lo + i_min) * RMS_BLOC_MS
    return t_ms


import unicodedata


def _est_un_mot(token):
    """Faux si le token est une marque de pause/waqf pure (ex. U+06D6..U+06DC,
    categorie Unicode Mn), sans aucune lettre arabe (categorie Lo). Decouvert
    en debuggant 2:30 : le split par espace du texte compte ces marques comme
    des "mots", mais l'API quran.com (source des .timings_cache) ne les compte
    pas -- decalage d'index qui s'accumule apres chaque marque, faussant toute
    mesure sur un verset qui en contient une."""
    return any(unicodedata.category(c) == "Lo" for c in token)


def charger_textes():
    verses = json.load(open(VERSES_JSON, encoding="utf-8"))
    return {v["verse_key"]: [m for m in v["text_uthmani"].split() if _est_un_mot(m)]
            for v in verses}


def frontieres_gardees(onsets_ms, lettres, total_ms, floor_ms=FLOOR_MS):
    """Construit les n+1 frontieres (ms) de n mots.

    DECOUVERTE (debug manuel sur 55:13) : le centre du span Viterbi d'un mot
    est un MAUVAIS estimateur de frontiere -- un madd/elongation produit un
    span brut minuscule (le CTC marque l'ONSET du mot avec precision, mais les
    frames de la voyelle tenue tombent en blanc plutot que d'etre attribuees
    au mot). En revanche l'ONSET (premiere frame) du mot SUIVANT est un tres
    bon estimateur de la fin du mot courant -- l'erreur mediane mesuree tombe
    de ~800ms a ~50-150ms sur l'exemple debogue. D'ou : frontiere[i] = onset
    du mot i+1 (le mot courant recupere tout le << blanc >> qui le suit),
    au lieu d'un milieu de centres de spans.
    """
    n = len(onsets_ms)
    if n <= 1:
        return [0.0, total_ms]

    cum = [0]
    for L in lettres:
        cum.append(cum[-1] + max(1, L))
    tot_lettres = cum[-1]

    def prorata_debut(i):
        return cum[i] / tot_lettres * total_ms

    remplis = [o if o is not None else prorata_debut(i)
               for i, o in enumerate(onsets_ms)]

    b = remplis + [total_ms]

    for i in range(1, n):
        if b[i] < b[i - 1] + floor_ms:
            b[i] = b[i - 1] + floor_ms
    for i in range(n - 1, 0, -1):
        if b[i] > b[i + 1] - floor_ms:
            b[i] = b[i + 1] - floor_ms

    if any(b[i] >= b[i + 1] for i in range(n)):
        b = [i / n * total_ms for i in range(n + 1)]  # repli : verset trop court pour n mots x floor

    return b


def mesurer_verset(sess, sp, textes, cache, surah, verset, avec_juge_silence=False):
    cle = f"{surah}:{verset}"
    mots = textes.get(cle)
    verite = cache.get(cle)
    if not mots or not verite:
        return None
    wav = RECITER_DIR / f"{surah}_{verset}.wav"
    if not wav.exists():
        return None

    pcm = lire_wav(wav)
    total_ms = len(pcm) / 16000.0 * 1000.0
    lp = logprobs(sess, pcm)

    # VERSET ENTIER exclu si une seule entree de reference est suspecte (>4s
    # pour un mot -- p95 reel = 2990ms sur 77392 mots). Trouve par debogage
    # (2:213, 2:97) : ce n'est pas un mot isole mal etiquete, c'est un vrai
    # trou de plusieurs secondes dans CET enregistrement local (souffle/pause/
    # montage) que la reference quran.com ignore -- donc TOUS les mots
    # suivants du verset heritent du meme decalage, pas seulement celui qui a
    # declenche le seuil.
    #
    # ESSAI ECARTE (2026-08-15) : detecter le trou DIRECTEMENT dans l'audio
    # via le plus long run de "blanc" du decodage libre (plus_long_trou_libre)
    # -- semblait plus direct/fiable que deduire l'anomalie via la reference.
    # MESURE : rate completement, le blanc CTC absorbe aussi les voyelles
    # tenues (madd) en parole NORMALE -- mediane mesuree 2880ms sur 108
    # versets ordinaires de 55/67, largement au-dessus de tout seuil
    # raisonnable. Le signal ne distingue pas "elongation normale" de "vrai
    # trou d'enregistrement". Fonction gardee dans le fichier (TROU_SUSPECT_MS,
    # plus_long_trou_libre) pour memoire mais NON utilisee ici.
    if any((e_ms - s_ms) > DUREE_MOT_SUSPECTE_MS for _, s_ms, e_ms in verite):
        return None

    spans = spans_mots(sp, lp, mots)
    if spans is None:
        return None

    onsets_ms = [None if s is None else s[0] * FRAME_MS for s in spans]
    lettres = [len(m) for m in mots]
    fin_ms = fin_reelle_parole(pcm, total_ms)
    b = frontieres_gardees(onsets_ms, lettres, fin_ms)

    if avec_juge_silence:
        env = rms_enveloppe(pcm)
        blank_idx = lp.shape[1] - 1
        b = [b[0]] + [juge_creux_silence(t, env, lp, blank_idx) for t in b[1:-1]] + [b[-1]]
        for i in range(1, len(b)):  # re-garantir la monotonie apres arbitrage
            if b[i] <= b[i - 1]:
                b[i] = b[i - 1] + FLOOR_MS

    resultats = []
    for idx, s_ms, e_ms in verite:
        if idx >= len(mots) or e_ms <= s_ms:
            continue  # entree de reference corrompue (constate : ~qqs pourmille ont fin <= debut)
        pred_s, pred_e = b[idx], b[idx + 1]
        resultats.append((abs(pred_s - s_ms), abs(pred_e - e_ms)))
    predictions = [[round(b[i], 1), round(b[i + 1], 1)] for i in range(len(mots))]
    return resultats, predictions, mots


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sourates", default="all", help="'all' = 114 sourates, ou liste ex: 55,2,67")
    p.add_argument("--rid", type=int, default=7)
    p.add_argument("--limite", type=int, default=0, help="0 = toute la sourate")
    p.add_argument("--modele", default=str(BASE / "models_deployes" / "fastconformer-ctc-mixed-e02"))
    p.add_argument("--tokenizer", default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--juge-silence", action="store_true",
                    help="deuxieme chemin (creux RMS) + juge, en plus de l'onset CTC")
    p.add_argument("--sortie-json", default="",
                    help="si donne, ecrit les predictions (surah:verset -> [[debut,fin],...] par mot)")
    p.add_argument("--reprendre", action="store_true",
                    help="reprend depuis --sortie-json existant, saute les sourates deja faites -- "
                         "utile apres une interruption (extinction, coupure), rien n'est reperdu")
    args = p.parse_args()

    sp = spm.SentencePieceProcessor(model_file=args.tokenizer)
    sess = ort.InferenceSession(str(Path(args.modele) / "model.onnx"), providers=["CPUExecutionProvider"])
    textes = charger_textes()

    if args.sourates == "all":
        sourates = [int(f.stem.split("_")[1]) for f in (BASE / ".timings_cache").glob(f"{args.rid}_*.json")]
        sourates.sort()
    else:
        sourates = [int(x) for x in args.sourates.split(",")]

    predictions_globales = {}
    sourates_faites = set()
    if args.reprendre and args.sortie_json and Path(args.sortie_json).exists():
        predictions_globales = json.load(open(args.sortie_json, encoding="utf-8"))
        sourates_faites = {int(k.split(":")[0]) for k in predictions_globales}
        print(f"reprise : {len(sourates_faites)} sourates deja faites, sautees")

    toutes = []
    for surah in sourates:
        if surah in sourates_faites:
            continue
        cache_f = BASE / ".timings_cache" / f"{args.rid}_{surah}.json"
        if not cache_f.exists():
            print(f"sourate {surah} : pas de cache {cache_f.name}, ignoree")
            continue
        cache = json.load(open(cache_f, encoding="utf-8"))
        versets = sorted({int(k.split(":")[1]) for k in cache})
        if args.limite:
            versets = versets[: args.limite]

        erreurs_s, erreurs_e = [], []
        for v in versets:
            r = mesurer_verset(sess, sp, textes, cache, surah, v, avec_juge_silence=args.juge_silence)
            if r is None:
                continue
            stats, predictions, mots = r
            for es, ee in stats:
                erreurs_s.append(es)
                erreurs_e.append(ee)
            if args.sortie_json:
                predictions_globales[f"{surah}:{v}"] = predictions

        if not erreurs_s:
            print(f"sourate {surah} : aucun mot mesurable")
            continue

        toutes_v = erreurs_s + erreurs_e
        toutes += toutes_v
        print(f"sourate {surah:>3} ({len(versets)} versets, {len(erreurs_s)} mots) : "
              f"debut mediane={st.median(erreurs_s):.0f}ms p95={np.percentile(erreurs_s,95):.0f}ms | "
              f"fin mediane={st.median(erreurs_e):.0f}ms p95={np.percentile(erreurs_e,95):.0f}ms")

        if args.sortie_json:  # sauvegarde APRES CHAQUE SOURATE, pas seulement a la fin --
            # une interruption (extinction, coupure, timeout) ne perd alors que
            # la sourate en cours, jamais tout le travail deja fait.
            json.dump(predictions_globales, open(args.sortie_json, "w", encoding="utf-8"),
                       ensure_ascii=False, indent=0)

    if args.sortie_json:
        print(f"\nPredictions ecrites : {args.sortie_json} ({len(predictions_globales)} versets)")

    if toutes:
        med = st.median(toutes)
        p95 = np.percentile(toutes, 95)
        verdict = "PASSE" if (med < 80 and p95 < 200) else "NE PASSE PAS"
        print(f"\nGLOBAL ({len(toutes)} frontieres, debut+fin confondus) : "
              f"mediane={med:.0f}ms  p95={p95:.0f}ms  -- critere (<80ms / <200ms) : {verdict}")


if __name__ == "__main__":
    main()
