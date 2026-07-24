# Problématiques du module ASR — nos difficultés & l'état de l'art externe

Ce document fait la synthèse des **problèmes récurrents rencontrés dans le
module ASR** de Coran Karim (segmentation du buffer, GOP/alignement forcé,
gestion des pauses) et les met en regard de ce que **d'autres développeurs et
la recherche** rapportent sur les mêmes sujets. Objectif : montrer que nos
difficultés ne sont pas des bugs locaux isolés mais des limites connues de la
techno, et pointer les solutions déjà publiées.

> Le détail chiffré de chaque problème vit dans ses documents d'origine —
> ce fichier ne les remplace pas, il les relie et ajoute la dimension « ce que
> font les autres » :
> - Segmentation buffer → `FONCTIONNALITES_FUTURES.md` §4, header de
>   `BufferedTranscriber.kt`
> - GOP / alignement forcé → `FONCTIONNALITES_FUTURES.md` §5, mémoire
>   `project_asr_gop_calibration_investigation.md`, `PLAN_ENTRAINEMENT_HYBRIDE.md`
>   §5quater
> - Décalage de domaine (pauses) → `FONCTIONNALITES_FUTURES.md` §4 (mesures
>   2026-07-23)
> - Mémoire technique complète → `.claude/skills/model-training/references/asr.md`

Dernière mise à jour : 2026-07-24.

---

## Partie 1 — Nos problématiques (interne)

### 1.1 Segmentation du buffer : coupe en plein mot & effondrement de la re-transcription

**Symptôme.** `BufferedTranscriber` re-transcrit le segment courant toutes les
~1,5 s avec le modèle **offline**. Sur device, la transcription peut
**s'effondrer** (quasi-vide) une seconde après avoir parfaitement reconnu le
même début d'énoncé, et un segment peut se figer **en plein mot** sur une
consonne peu énergique (occlusives ب، ذ، ن), produisant un fragment vide
(« فين », « عَلَيْ » pour عَلَيْهِمْ).

**Causes identifiées (mesurées, pas supposées).**
- **Dérive de la normalisation `per_feature`** : mean/std recalculés sur TOUT
  le buffer à chaque appel ; au-delà de ~10 s le buffer sort du domaine des
  clips d'entraînement et les stats dérivent structurellement (header
  `BufferedTranscriber.kt` v2/v3).
- **Décalage de domaine** : le modèle est entraîné sur des clips de versets
  **propres et continus**, il n'a jamais vu de pause interne — toute pause le
  fait dérailler, quelle que soit la façon dont on la traite (mesure 2026-07-23).
- Ce n'est **pas** de l'hésitation marginale : l'écart entre versets est de
  4-8 s **quasi constant** = respiration normale / waqf, donc ça touche le cas
  d'usage central (récitation continue), même pour un récitateur confirmé.

**Ce qui a été tenté et REJETÉ par la mesure** (à ne pas re-tenter) :
stats de normalisation fixes (+1,28 pt WER, ne corrige rien), désactivation du
portier RMS (70,2 % vs 22,8 %), coupe à chaque pause (103,5 %), fenêtre
glissante naïve (WER > 100 % par duplication). **Le code en place est le moins
mauvais parmi ces options** — il n'y a pas de bug de segmentation à corriger,
la cause est un décalage de domaine → le vrai correctif est côté ENTRAÎNEMENT
(augmentation avec pauses insérées).

**Piste encore ouverte.** La dégradation suit le **nombre de coutures** créées
par le portier RMS (10 coutures → 27,7 % WER, 20 → 59,6 %). Une **fenêtre de
taille fixe** borne ce nombre par construction : elle ne guérit pas la pause
(seul l'entraînement le peut) mais elle **plafonne les dégâts**.

### 1.2 GOP / alignement forcé CTC : scores catastrophiques sur des mots bien prononcés

**Symptôme.** L'alignement forcé (score GOP = écart entre le chemin forcé et le
meilleur chemin libre, `ForcedAligner.kt`) donne des scores catastrophiques
(-5,1 à -5,8) sur des mots **correctement récités** — récurrent sur
ٱللَّهِ، ٱلرَّحْمَـٰنِ، ٱلرَّحِيمِ (chadda/gemination, hamzat wasl), aux
**frontières de mots** avec liaison phonétique.

**Causes identifiées.**
- **CTC « peaky »** : le CTC émet le token vers la fin du son réel, timing
  imprécis → l'alignement forcé, qui a besoin de savoir *où* commence/finit un
  mot, hérite de cette imprécision aux frontières (§5.2).
- **Vocabulaire étendu** (40 classes symboles tajwid en plus) : effet de bord
  sur la calibration GOP à certaines positions, **indépendant** de la méthode
  d'entraînement (même échec sur 3 recettes différentes).
- **Artefact de corpus** (cause racine trouvée) : la Basmala est récitée ~44 %
  plus vite que le reste du Coran (formule rituelle) → mauvaise calibration
  aux positions correspondantes, une fois par sourate × ~80 récitateurs.

**Ce qui a été fait.** Exclusion des classes-symboles du max libre, masquage +
renormalisation côté forcé et DP, exclusion de la « chadda nue »
(`ForcedAligner.kt`, commits `64215d0`, `a2d3054`) — gains réels mais
insuffisants seuls. Exemption `isBasmala` (4 mots forcés à `correct`). Toggle
`JudgementOptions.useGopScoring` : GOP et l'ancien diff textuel
(`_realignFromFullText`) tournent **en parallèle** et loguent tous deux chaque
mot, seul le sélectionné pilote les couleurs — pour trancher empiriquement.

**Tension de fond.** Le GOP est genuinement plus sensible aux swaps de harakat
(sa raison d'être) que le diff textuel — mais faiblement (-0,16 à -0,90 sur des
clips à harakat inversées, 3/5 passeraient quand même « correct »). Et le
modèle « corrige » parfois tout seul une vraie faute vers le texte canonique
(biais du corpus 100 % correct), effaçant la preuve avant tout décodage.

### 1.3 Streaming cache-aware : essayé et abandonné

Notre checkpoint est entraîné **offline avec convolutions non-causales** (~4
frames de futur). Le découpage chunk-par-chunk avec cache corrompt chaque
frontière → **décode 100 % blank** ; le chemin officiel NeMo
`conformer_stream_step` crashe (rel_shift sur tenseur vide). Le vrai streaming
exige un fine-tune dédié à **convolutions causales** (verdict 2026-07-04,
header `BufferedTranscriber.kt`). La fenêtre glissante offline, elle, re-transcrit
une fenêtre entière sans cache — elle ne tombe pas dans cet échec.

---

## Partie 2 — Ce que rapportent les autres (forums & recherche)

Nos trois problèmes sont **des limites connues et documentées** de la techno,
pas des accidents propres à ce projet.

### 2.1 CTC « peaky » → alignement forcé & GOP peu fiables (= notre §1.2)

C'est un phénomène **nommé et étudié**. La sortie CTC est « peaky » : le blank
est activé sur la quasi-totalité des pas de temps, les tokens cibles ne
s'activent que sur quelques frames. **Sans impact sur l'ASR pur**, mais cause
des **alignements forcés imprécis, surtout au grain fin** (phonème) — exactement
notre observation aux frontières de mots.

- **« Less Peaky and More Accurate CTC Forced Alignment by Label Priors »**
  (Interspeech 2024) : introduit des *label priors* pour booster les chemins
  contenant moins de blanks pendant l'entraînement → CTC moins peaky, offsets
  de tokens plus précis. **12-40 % de réduction** des erreurs de frontière
  phonème/mot (PBE/WBE). ⇒ Piste d'entraînement directement pertinente pour
  fiabiliser notre GOP aux frontières.
  https://arxiv.org/abs/2406.02560
- **« Segmentation-Free Goodness of Pronunciation »** (2025) : le GOP
  traditionnel « souffre de désalignements induits par l'acoustique qui
  dégradent la fiabilité de l'évaluation » ; le CTC-GOP contourne l'alignement
  forcé mais « est limité par le comportement peaky inhérent du CTC, qui produit
  des postérieurs épars et manque d'information temporelle stable » — description
  quasi mot pour mot de notre §1.2.
  https://arxiv.org/abs/2507.16838
- **« A Framework for Phoneme-Level Pronunciation Assessment Using CTC »**
  (Interspeech 2024) : cadre d'évaluation de prononciation au niveau phonème
  bâti sur CTC, confronté aux mêmes limites.
  https://www.isca-archive.org/interspeech_2024/cao24b_interspeech.pdf
- **Spécifique Coran** — « Mispronunciation Detection of Basic Quranic
  Recitation Rules using Deep Learning » (arXiv 2305.06429) et « Empirical Study
  on Mispronunciation Detection for Tajweed Rules » : comparent explicitement
  des classifieurs (Random Forest, LSTM, CNN…) au **GOP standard**, et le
  **Random Forest surpasse nettement le GOP**. LSTM atteint 95-96 % sur 3 règles
  (madd, ghunna/noon, ikhfa). ⇒ Confirme que le GOP n'est pas forcément le
  meilleur outil pour juger le tajwid, et légitime notre garde d'un comparateur
  alternatif (`useGopScoring` off) + l'idée d'une **tête de classification par
  règle** (cf. `FONCTIONNALITES_FUTURES.md` §6/§9).
  https://arxiv.org/abs/2305.06429

### 2.2 Segmentation streaming, VAD & coupes en plein mot (= notre §1.1)

Problème central et récurrent de tout ASR streaming :

- **Coupe en plein mot.** WhisperPipe tranche le buffer **précisément à la fin
  du dernier mot committé** (slicing guidé par timestamp) plutôt qu'à une
  frontière de chunk fixe : « réduit la dérive de frontière et **évite les
  coupes en plein mot qui déstabilisent les hypothèses suivantes** et gonflent
  le taux de révision ». ⇒ C'est exactement notre effondrement §1.1 ; leur
  correctif (couper sur le dernier mot stable, pas sur un timer/silence brut)
  est transposable.
  https://arxiv.org/pdf/2604.25611
- **Les pauses ne sont pas des frontières.** « Pour la dictée, les pauses
  n'indiquent pas nécessairement des frontières de segmentation idéales » ; une
  phrase à prendre d'un bloc « peut contenir des hésitations au milieu ». Un
  seuil de silence minimal (défaut 0,75 s) « évite les coupures prématurées
  quand le locuteur marque une brève pause ». ⇒ Valide notre choix de ne PAS
  couper à chaque pause (mesure : 103,5 % WER), et notre `DEFAULT_COMMIT_SILENCE_MS`.
- **VAD hybride.** Combiner Silero VAD + filtrage énergétique réduit les fausses
  activations de **34 %** — notre « portier RMS » est une version simple de la
  même idée (et la mesure a confirmé qu'il aide : 22,8 % vs 70,2 % sans lui).
  https://apxml.com/courses/speech-recognition-synthesis-asr-tts/chapter-6-optimization-deployment-toolkits/streaming-asr-deployment
- **Fenêtres de contexte à recouvrement.** « Un mécanisme de buffering dynamique
  avec fenêtres de contexte à recouvrement évite la perte d'information aux
  frontières de segments. » ⇒ Argument externe pour notre piste fenêtre
  glissante (§1.1), à condition de gérer la dédup (cf. §2.4).
- **Segmentation sémantique / E2E.** « Les segmenteurs VAD peuvent être
  sous-optimaux ; solutions : modèles ASR E2E capables de prédire les frontières
  de segment en streaming, conditionnées sur les features sémantiques du texte
  décodé. » — « E2E Segmenter: Joint Segmenting and Decoding for Long-Form ASR »
  (arXiv 2204.10749). ⇒ Piste lourde mais alignée avec notre §9 (waqf comme
  frontière connue a priori) : au lieu de deviner la frontière au silence, la
  connaître par le texte (marques de waqf déjà extraites dans `quran_waqf.json`).
  https://arxiv.org/abs/2204.10749

### 2.3 Hallucination / effondrement sur silences & pauses (= notre §1.1)

Le fait qu'un modèle **déraille sur le silence** est massivement documenté sur
Whisper — même famille de problème que notre effondrement de re-transcription :

- « Les hallucinations sont les plus fréquentes en transcription **long-form**,
  particulièrement quand l'audio contient de grandes plages de **silence entre
  les énoncés** » ; « les silences en début/fin déclenchent directement des
  hallucinations » ; sous 30 % de masquage, le décodeur « **répète des phrases
  des centaines de fois** » (cycle autorégressif catastrophique).
  https://arxiv.org/html/2402.08021v2
- Explication mécaniste : sur du silence, les embeddings audio sont ~nuls et le
  modèle, entraîné sur de la parole, « comble » en bouclant la dernière phrase.
  Discussions dev : https://github.com/openai/whisper/discussions/1606 ,
  https://dev.to/nareshipme/whisper-hallucination-on-silence-why-your-transcript-loops-the-same-phrase-2pg4
- **Remède courant = VAD** (couper/sauter le silence avant le modèle) et un
  paramètre pour ignorer N secondes de silence initial. ⇒ Même logique que notre
  portier RMS + plafond de silence conservé. **Enseignement clé** : le remède
  universel est de **ne pas donner de silence au modèle**, ce qui conforte que
  notre vrai levier est l'entraînement (voir le silence) OU une segmentation qui
  ne laisse jamais le buffer sortir du domaine.

### 2.4 La « bonne » réponse au recouvrement : cache-aware (et pourquoi ça ne s'applique pas encore) (= notre §1.3)

La recherche NeMo confirme **et** notre diagnostic **et** pourquoi la solution
idéale nous est fermée aujourd'hui :

- « Les chunks à recouvrement causent une **duplication de calcul importante** ;
  le caching supprime le besoin de buffer/recouvrement et évite les calculs
  dupliqués — chaque frame est traitée exactement une fois. » Les modèles
  cache-aware « surpassent les modèles buffered sur tous les benchmarks »
  (jusqu'à **17× de réduction de latence**). ⇒ C'est LA réponse propre à la
  duplication qui a tué notre fenêtre glissante naïve (WER > 100 %).
  https://arxiv.org/html/2312.17279v2
- **Mais** : ces modèles ont « des contextes gauche/droit limités **à
  l'entraînement** pour maintenir des conditions cohérentes avec l'inférence
  streaming ». C'est précisément ce qui manque à notre checkpoint (entraîné
  offline, convs non-causales) → d'où notre 100 % blank. Le fix est un
  **fine-tune dédié streaming** (convs causales), pas un changement de décodage.
  NVIDIA a d'ailleurs sorti des modèles conçus pour ça (Nemotron Speech ASR
  0.6B, cache-aware FastConformer).
  https://huggingface.co/blog/nvidia/nemotron-speech-asr-scaling-voice-agents

---

## Partie 3 — Enseignements

1. **Nos problèmes sont des limites connues de la techno, pas des bugs locaux.**
   Le peaky-CTC dégradant le GOP, la coupe en plein mot en streaming, et
   l'effondrement sur silence sont tous documentés dans la littérature et sur
   les forums dev. Cela valide *a posteriori* la règle projet « ne rien toucher
   à la segmentation sans mesure » : les correctifs « évidents » que d'autres
   ont aussi essayés échouent pour les mêmes raisons.

2. **Les deux vrais leviers sont côté ENTRAÎNEMENT**, pas côté décodage :
   - contre le peaky-CTC / GOP fragile → *label priors* (arXiv 2406.02560),
     objectif auxiliaire pénalisant l'étalement temporel (cf. §5.2), et/ou
     tête de classification par règle (Random Forest/LSTM battent le GOP sur
     Coran, arXiv 2305.06429) ;
   - contre l'effondrement sur pause → augmentation de données avec pauses
     insérées + fine-tune streaming à convolutions causales pour débloquer le
     cache-aware (la seule vraie solution au recouvrement).

3. **Ce qui reste actionnable côté app sans réentraîner** :
   - fenêtre de taille fixe pour **borner le nombre de coutures** (plafonne les
     dégâts, mesuré) ;
   - slicing guidé par le dernier mot stable plutôt que par timer/silence brut
     (WhisperPipe) ;
   - frontières connues a priori via les marques de waqf (`quran_waqf.json`,
     §9) — notre équivalent « segmentation sémantique » sans modèle E2E ;
   - garder le comparateur non-GOP disponible (`useGopScoring`), la recherche
     Coran montrant que le GOP n'est pas toujours le meilleur juge.

---

### Sources

- Less Peaky and More Accurate CTC Forced Alignment by Label Priors — https://arxiv.org/abs/2406.02560
- Segmentation-Free Goodness of Pronunciation — https://arxiv.org/abs/2507.16838
- A Framework for Phoneme-Level Pronunciation Assessment Using CTC — https://www.isca-archive.org/interspeech_2024/cao24b_interspeech.pdf
- Mispronunciation Detection of Basic Quranic Recitation Rules using Deep Learning — https://arxiv.org/abs/2305.06429
- WhisperPipe (streaming, slicing guidé par timestamp) — https://arxiv.org/pdf/2604.25611
- Deployment Considerations for Streaming ASR (VAD hybride, seuils de pause) — https://apxml.com/courses/speech-recognition-synthesis-asr-tts/chapter-6-optimization-deployment-toolkits/streaming-asr-deployment
- E2E Segmenter: Joint Segmenting and Decoding for Long-Form ASR — https://arxiv.org/abs/2204.10749
- Careless Whisper: Speech-to-Text Hallucination Harms — https://arxiv.org/html/2402.08021v2
- Whisper — hallucination sur silence (discussions dev) — https://github.com/openai/whisper/discussions/1606
- Stateful Conformer with Cache-based Inference for Streaming ASR — https://arxiv.org/html/2312.17279v2
- Nemotron Speech ASR (cache-aware FastConformer, streaming) — https://huggingface.co/blog/nvidia/nemotron-speech-asr-scaling-voice-agents
