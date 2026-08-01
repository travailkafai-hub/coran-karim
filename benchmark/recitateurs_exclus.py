"""RECITATEURS EXCLUS des manifestes d'entrainement -- mesure, pas opinion.

Trouve le 2026-07-31 en verifiant la qualite d'un corpus derive (clips courts
3-8 s decoupes sur des frontieres de mots ESTIMEES) : WER de 37 % meme sur des
fragments "propres", jusqu'a 600 % sur certains. Premiere hypothese (bornes de
mots mal estimees par ma decoupe) EXCLUE par le test decisif : decoder les
clips LONGS ORIGINAUX de `train_wav_local`, SANS AUCUN decoupage de ma part,
et comparer au champ `text` du manifeste. Certains recitateurs y restent a
0-25 % (WER normal du modele), d'autres explosent a 30-104 % -- la ou il n'y a
ni troncature ni estimation, seulement `audio_filepath` compare a `text`.

CONCLUSION : pour ces recitateurs, LE COUPLE (audio, texte) DU MANIFESTE
LUI-MEME NE CORRESPOND PAS. Ce n'est pas un defaut de decoupage, c'est une
CONTAMINATION A LA SOURCE -- probablement un decalage de mapping fichier/verset
au moment de la construction du manifeste (8 sur 9 portent le suffixe
`_assajda`, un lot construit differemment des collections `_128kbps` standard).

METHODE (reproductible, cf. banc_qualite_recitateurs.py) : 8 clips longs
ORIGINAUX par recitateur (54 recitateurs, 432 clips), decodage glouton CTC
(modele fastconformer-contrastif-v1), WER normalise (harakat retirees, hamza
unifiee -- meme normalisation que eval_causal_per_context.py) contre le champ
`text` du manifeste tel quel. Seuil de coupure : 30 %, choisi sur un ECART
NET dans la distribution (le 9e pire, 30,8 %, est isole du reste de la
distribution qui tombe ensuite a 5-25 %, plage coherente avec le WER normal du
modele -- cf. le detail complet dans /tmp/claude-1000/wer_par_recitateur.json
au moment de la mesure).

⚠️ CE QUE CETTE LISTE NE DIT PAS : elle ne dit rien sur un eventuel probleme
DIFFERENT et plus fin -- l'estimation de frontieres de MOTS a l'interieur d'un
clip par ailleurs bien aligne (utilisee par generer_clips_courts.py via
word_timings_ref.json, PROPORTIONS derivees de recitateurs MURATTAL). Un
recitateur absent de cette liste peut quand meme produire des courtes-durees
imparfaites si son phrase' interne differe fortement du murattal median
(mesure explicite non faite recitateur par recitateur pour ce sous-probleme).

UTILISATION -- import et filtre AVANT toute construction de manifeste
d'entrainement touchant `train_wav_local/` :

    from recitateurs_exclus import RECITATEURS_EXCLUS, est_exclu
    lignes = [l for l in lignes if not est_exclu(l["audio_filepath"])]
🔴 CETTE LISTE EST PROBABLEMENT FAUSSE -- NE PAS S'EN SERVIR SANS REVERIFIER
(trouve le 2026-08-01, quelques heures plus tard, dans la MEME session).

Ce que la mesure de depart avait rate : le projet a DEJA reparee cette
contamination le 2026-07-04 (`realign_assajda.py`, doc complete dans
`benchmark/BENCHMARK_RESULTS.md` -- « Qualite dataset : desalignement des
clips _assajda -- cause trouvee et reparee »). Cause reelle, deja identifiee a
l'epoque : `download_assajda.py::split_by_verse_uniform()` decoupait chaque
sourate a duree EGALE au lieu des vraies frontieres de versets -- PAS un
probleme de riwaya (Warsh/Hafs), PAS un desalignement de la methode utilisee
cette nuit. 141 899 clips sur 151 787 ont ete realignes par alignement force
CTC (`jonatasgrosman/wav2vec2-large-xlsr-53-arabic`, meme famille de modele
que WhisperX ce soir) et ecrits dans `benchmark/data/manifest_unified.jsonl`
(407 149 lignes, champ `align_score`).

VERIFIE le 2026-08-01 : `train_manifest.jsonl` (utilise par TOUS les
entrainements de la nuit) contient deja le TEXTE realigne (identique a
`manifest_unified.jsonl`, `align_score` compris) pour SaberAbdulHakam_assajda
-- et le decodage REEL d'un clip cite comme "contamine" ci-dessous
(19_78.wav) est PARFAIT, mot pour mot. La mesure initiale (8 clips par
recitateur, tot dans la nuit) etait un echantillon trop bruite ou entachee
d'un biais non identifie -- PAS une contamination reelle des donnees.

IMPACT REEL, verifie : NUL. Cette liste n'est utilisee QUE par
`generer_clips_courts_v2.py` (deja abandonne, sortie supprimee).
`nettoyer_corpus_base.py`, `generer_et_nettoyer_clips_courts.py` (v4) et
`generer_whisperx_reste.py` ne la referencent PAS -- ils jugent chaque clip
individuellement par decodage, methode qui a d'elle-meme garde
`SaberAbdulHakam_assajda` a un taux normal partout ou elle a tourne ce soir.

⇒ NE PAS reutiliser cette liste sans revalider par decodage individuel
(comme `nettoyer_corpus_base.py` le fait deja, correctement). Conservee
ci-dessous pour la tracabilite de l'erreur, pas comme verite.

── ancienne note (fausse, gardee pour memoire) ──────────────────────────────
CETTE LISTE N'EST PAS EXHAUSTIVE (trouve le 2026-08-01, apres coup) :
`train_manifest.jsonl` n'utilise que 54 des 85 recitateurs disponibles
localement (fait deja note le 2026-07-22 dans
`build_ikhafa_augment_manifest.py`, jamais explique). Les 31 laisses de cote
sont presque tous suffixes `_assajda` -- LA MEME FAMILLE que les 9 ci-dessous,
qui eux avaient reussi a entrer dans le manifeste. Ces 31 ne sont PAS
verifies : ils sont simplement ABSENTS, sans qu'on sache si c'est parce
qu'ils sont mauvais ou pour une autre raison. Si un script les reintroduit un
jour (ex. `build_ikhafa_augment_manifest.py`, qui ne filtre que sur le NOMBRE
de fichiers, pas sur la qualite de l'alignement), refaire l'audit WER avant
de les utiliser -- ne pas supposer qu'ils sont propres seulement parce qu'ils
manquent a cette liste.
"""
import re

RECITATEURS_EXCLUS = {
    "AntarMuslim_assajda": 103.6,
    "KhalidAlJalil_assajda": 94.5,
    "Abdullaah_3awwaad_Al-Juhaynee_128kbps": 86.9,
    "AbdallahKamel_assajda": 57.3,
    "AlzainMohamedAhmed_assajda": 48.5,
    "AbdallahMatroud_assajda": 40.4,
    "AbdulWadudHaneef_assajda": 35.0,
    "AdelKalbani_assajda": 34.4,
    "SaberAbdulHakam_assajda": 30.8,
}

_RE_RECITATEUR = re.compile(r"train_wav_local/([^/]+)/")


def recitateur_de(audio_filepath: str):
    m = _RE_RECITATEUR.search(audio_filepath)
    return m.group(1) if m else None


def est_exclu(audio_filepath: str) -> bool:
    r = recitateur_de(audio_filepath)
    return r is not None and r in RECITATEURS_EXCLUS
