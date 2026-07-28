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

> **MISE À JOUR 2026-07-26** : le fine-tune causal évoqué ci-dessus comme
> condition manquante a été fait cette session (cf. `ETAT_CTC_NEMO.md`,
> `.claude/skills/model-training/references/asr.md`). Le blocage structurel
> décrit ici est donc levé, mais pas encore validé bout en bout côté app —
> voir §1.4 pour la comparaison complète ancienne/nouvelle méthode et l'état
> d'avancement réel.

### 1.4 Ancienne méthode vs nouvelle méthode (streaming causal) — comparatif

Document demandé par l'utilisateur (2026-07-26) pour clarifier ce qui change
concrètement avant de toucher à `BufferedTranscriber.kt` (règle projet :
proposer et faire valider avant de développer). Les deux méthodes ci-dessous
ne sont PAS interchangeables au même niveau de maturité : l'ancienne est en
production, mesurée sur device ; la nouvelle est un modèle entraîné mais
**pas encore portée côté Kotlin, pas encore validée sur audio réel device**.

#### Ancienne méthode — buffer offline re-transcrit en entier

**Principe.** Le buffer audio grandit à chaque frame captée. À intervalle
régulier (~1,5 s), `BufferedTranscriber` renvoie **tout le buffer depuis le
début du segment** au modèle **offline** (convolutions non-causales, voit
~4 frames de futur), qui le retranscrit intégralement ; le jugement (GOP,
alignement) est réévalué sur ce nouveau texte complet.

| Points forts | Points faibles |
|---|---|
| Chaque passage voit **tout le contexte disponible** → un mot mal jugé au premier passage peut être **corrigé rétroactivement** quand plus de contexte arrive (mécanisme observé et exploité, cf. `resume_log_recitation.py` : « signalé puis repassé vert ») | Coût de calcul **quadratique dans le temps** : chaque nouveau chunk refait tout le travail depuis le début → le calcul dupliqué croît avec la durée récitée |
| Modèle **offline standard, éprouvé** : WER de référence 0,116 sur Coran (mixed-e14) | **Dérive de normalisation `per_feature`** au-delà de ~10 s : le buffer sort du domaine des clips d'entraînement (mean/std recalculés sur un signal de plus en plus long) |
| Pas de gestion d'état complexe côté Kotlin (appel stateless, le buffer entier suffit) | **Coupe en plein mot / effondrement** documentés en détail au §1.1 (occlusives peu énergiques, portier RMS) |
| Comportement **connu et mesuré** sur device depuis longtemps (aucune inconnue de maturité) | **Retard de validation** croissant avec la durée (avant le dernier correctif de gel, mesuré à 15,9 s) |
| | La tentative de fenêtre glissante **naïve** (sans cache) a produit un WER > 100 % par **duplication de texte** — rejetée par la mesure, pas une option de repli |

#### Nouvelle méthode — streaming cache-aware, convolutions causales

**Principe.** Le modèle est ré-entraîné avec des **convolutions causales**
et une fenêtre d'attention `chunked_limited` (contexte droit **borné**, ex.
`[70,13]` ≈ 1,04 s de lookahead — cf. formule NVIDIA dans `asr.md`). Chaque
**nouveau** chunk audio n'est traité **qu'une seule fois** ; un état
(`cache_last_channel`, `cache_last_time`, `cache_last_channel_len`) est
conservé entre deux appels et réinjecté au chunk suivant — le décodage CTC
devient incrémental (append-only) plutôt que ré-évalué en bloc.

| Points forts | Points faibles |
|---|---|
| Coût de calcul **linéaire** : chaque frame traitée exactement une fois par construction (résout structurellement la duplication qui a tué la fenêtre glissante naïve ci-dessus) | Contexte droit **borné par construction** — un mot dont l'interprétation ne se clarifie qu'avec beaucoup de contexte futur **ne bénéficie plus** de la correction rétroactive de l'ancienne méthode (effet de bord identifié, pas encore arbitré avec l'utilisateur) |
| Aligné avec l'état de l'art mesuré (cache-aware FastConformer : jusqu'à 17× de réduction de latence rapportée, §2.4) et les modèles NVIDIA récents conçus pour ça (Nemotron Speech ASR) | **WER actuellement moins bon** que l'offline : 0,195 vs 0,116 sur Coran (cycle 1, décodage CTC forcé) — écart pas encore comblé, structurellement attendu (moins de contexte futur = moins d'info) mais son ampleur reste à valider |
| Pas de dérive de normalisation sur un buffer qui grandit sans borne (chaque chunk traité dans une fenêtre de taille fixe) | Décodage CTC incrémental doit **fusionner les répétitions à travers la frontière de chunk** — logique **pas encore écrite côté Kotlin** ; mal faite, elle peut dédoubler ou couper des mots |
| Latence de bout en bout indépendante de la durée déjà récitée (pas de retard croissant) | **Complexité d'état nouvelle** : la session ONNX porte un état mutable entre appels (reset sur erreur/interruption plus délicat qu'un appel stateless) |
| | **Pas encore validé sur audio réel device** : seul un export SANS état (drop-in, mêmes entrées/sorties que l'ancien modèle) a été testé à ce stade ; l'export cache-aware réel (`export_streaming_onnx.py`) doit être refait pour pointer sur le nouveau checkpoint causal, et le portage Kotlin (gestion du cache) n'a pas commencé |

**Où on en est (2026-07-26)** : le fine-tune causal existe
(`fastconformer-streaming-causal-v1-lr3e4/causal-final.nemo`), un export
stateless a été produit pour tester la qualité de transcription seule dans
l'app (sans changer l'architecture de `BufferedTranscriber`), et un second
entraînement joint encodeur+tête tajwid (stage b) est en cours. Le passage à
l'architecture streaming réelle (cache + décodage incrémental côté Kotlin)
est une étape **distincte, non commencée**, avec l'effet de bord ci-dessus
(perte possible de la correction rétroactive) qui doit être tranché avant
d'y toucher — pas assumé unilatéralement.

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

---

## 1.5 Recul architectural (2026-07-26) — le causal gèle après ~35 s sur device

⚠️ **AVERTISSEMENT DE LECTURE, remarque utilisateur du 2026-07-26** : tout ce
qui précède dans les §1.3/§2.x a été mesuré sur le modèle **NON CAUSAL**,
jamais entraîné pour le streaming. Ces conclusions ne se transportent PAS
telles quelles au modèle causal. Ne pas les invoquer comme « déjà tenté » sans
vérifier sur quel modèle la mesure a été faite — c'est l'erreur commise au
début de cette analyse.

### Le symptôme, mesuré sur une récitation réelle (43,5 s, 2:1-2:4)

La chaîne suit parfaitement 25 s (mots 4→19 validés, ancre 8→20), puis **plus
rien pendant 18 s** : blocs PCM toujours reçus, inférence toujours exécutée,
mais aucun mot confirmé — donc **ni orange, ni rouge, ni correction**. Le
curseur gèle en silence. C'est le pire mode de défaillance possible pour cette
app : elle ne signale même pas qu'elle a décroché.

### Les trois hypothèses testées hors device, sur CE audio réel

| Tentative | Hypothèse implicite | Mesure | Verdict |
|---|---|---|---|
| Fenêtre glissante 20 s sur les stats de normalisation | features hors distribution | 49 tokens, arrêt 34,8 s — **identique** au cumulatif, alors que les stats diffèrent bien (écart moyenne 0,70) | **REJETÉE** |
| Remise à zéro du cache **sur silence** (RMS<0,02, ≥400 ms) | un silence = une frontière d'énoncé | WER 79 % (et 86 % avec plafond) contre 64 % | **REJETÉE, pire** |
| Remise à zéro du cache à **intervalle fixe** | le cache sature | débloque l'émission (34,8 s → 41,5 s) mais WER erratique 50-86 % sur 11 valeurs, sans tendance | **Sans signal exploitable** |

Les deux premières partagent la même hypothèse implicite — « les entrées du
modèle sont hors distribution, il faut corriger la normalisation ou le
contexte ». C'est le suspect n°1 au sens du skill, et la mesure l'a écartée.

Le seul résultat ROBUSTE et reproductible : **ne jamais remettre le cache à
zéro tue l'émission ; n'importe quelle remise à zéro la rétablit.** L'intervalle
optimal, lui, n'est pas déterminable sur un seul clip de 33 mots (1 mot = 3 pt
de WER).

### La faille structurelle

**Les clips d'entraînement font ≤ 20 s (`max_duration: 20.0`). La session
d'inférence n'a AUCUNE borne.** Le cache s'accumule sur toute la session, donc
au-delà de 20 s le modèle travaille dans un régime de longueur qu'il n'a jamais
vu. L'ancien chemin bufférisé bornait la session par construction
(`MAX_SEGMENT_SECONDS = 12 s`) ; le chemin causal a **supprimé cette borne sans
la remplacer**.

Ce n'est donc pas un seuil à régler, c'est une **information manquante** : la
couche qui remet le cache à zéro n'a aucun moyen de savoir où un énoncé finit.
Régler l'intervalle, c'est lui demander de deviner — exactement le signal
d'alerte du skill.

Et le silence n'est PAS cette information dans notre cas : en récitation, une
pause est très souvent un **waqf** imposé au milieu d'un verset, pas une fin
d'énoncé. D'où l'échec mesuré de la remise à zéro sur silence.

### État de l'art (recherche 2026-07-26)

- Le traitement long-form standard segmente **en amont par VAD**, puis traite
  chaque segment indépendamment ([arXiv 2309.09950](https://arxiv.org/html/2309.09950)).
- NVIDIA a publié un modèle cache-aware qui fait **ASR + détection de fin
  d'énoncé (EOU) conjointement**, le signal EOU servant à déclencher
  explicitement les remises à zéro du cache aux frontières de tour
  ([NVIDIA/HF](https://huggingface.co/blog/nvidia/nemotron-speech-asr-scaling-voice-agents)).
- Le paper de référence du Conformer stateful cache-based
  ([arXiv 2312.17279](https://arxiv.org/html/2312.17279v2)) **ne traite pas** la
  dégradation sur audio beaucoup plus long que les énoncés d'entraînement :
  vérifié, aucune mention de remise à zéro, de longueur maximale de session, ni
  du décalage durée-entraînement/durée-inférence. C'est un angle mort de la
  littérature, pas une bêtise de notre implémentation.

### Piste A (frontière de verset) — MESURÉE ET REJETÉE le 2026-07-26

Idée : remettre le cache à zéro quand l'ancre d'alignement franchit une
frontière de verset — information que l'app possède déjà, contrairement à un
seuil de silence ou d'horloge. C'était la piste recommandée à l'issue du recul
architectural, au motif qu'elle « donne l'information à la couche » au lieu de
la lui faire deviner.

Mesure sur l'audio réel (43,5 s, 2:1-2:4, 28 mots de référence) :

| politique | resets | mots émis | WER |
|---|---|---|---|
| actuel (jamais remis à zéro) | 0 | 21/28 | **64 %** |
| **piste A — frontière de verset** | 3 | 26/28 | **75 %** ❌ |
| intervalle fixe 6 s | 6 | 26/28 | 50 % |

**Rejetée** : pire que le statu quo. La remise à zéro fait bien émettre plus de
mots (26 au lieu de 21) mais les mots gagnés sont FAUX — l'émission reprend
sans que la reconnaissance soit correcte.

### Conclusion du recul architectural : le levier applicatif est ÉPUISÉ

Quatre politiques testées côté app sur le même audio réel, **quatre rejetées
par la mesure** : fenêtre glissante de normalisation (identique), remise à zéro
sur silence (79-86 %), à intervalle fixe (erratique 50-86 %, sans optimum sur
11 valeurs), à la frontière de verset (75 %). Aucun réglage ne rattrape le
statu quo de façon fiable, et le statu quo lui-même est mauvais (64 %).

⇒ **Le défaut ne naît pas dans la couche applicative.** Il naît dans le
MODÈLE : entraîné sur des clips ≤ 20 s, jamais entraîné dans le régime
cache-aware où il est déployé (session non bornée, cache propagé sur des
minutes). Chercher le bon endroit pour vider le cache, c'est demander à l'app
de compenser une information que le modèle n'a jamais apprise — un palliatif au
sens de CLAUDE.md.

Ne pas relancer de 5ᵉ variante de politique de cache sans avoir d'abord traité
le modèle (piste B : entraîner sur des sessions concaténées > 20 s). C'est la
même leçon que le 2026-07-23 sur la segmentation : le code en place était le
moins mauvais, et le vrai correctif était côté données.

### 5ᵉ tentative (2026-07-26) — reset COMBINÉ cache+normalisation sur la politique BufferedTranscriber : REJETÉE

Idée : synchroniser la remise à zéro du cache ET de la fenêtre de normalisation
sur la politique de segmentation déjà éprouvée de l'ancien `BufferedTranscriber`
(pause ≥450 ms après 2,5 s minimum, plafond dur 12 s), plutôt qu'un intervalle
arbitraire.

Mesure sur l'audio réel (43,5 s) : **WER = 93 %**, pire que le statu quo
(64 %) et pire que toutes les variantes précédentes sauf la remise à zéro sur
silence seule. 6 resets déclenchés. Hypothèse d'échec : remettre le cache ET
la normalisation en même temps crée une DOUBLE rupture (mémoire du modèle et
repères statistiques perdus simultanément) — plus violent que l'un ou l'autre
isolément.

**Bilan : 5 politiques de gestion du cache testées sur ce modèle causal,
5 rejetées par la mesure** (fenêtre glissante de normalisation seule, reset
sur silence seul, reset à intervalle fixe seul, reset à la frontière de verset
seul, reset combiné cache+normalisation sur la politique BufferedTranscriber).
Le levier applicatif est définitivement épuisé pour CE modèle — cf. conclusion
déjà écrite plus haut (§ "le défaut ne naît pas dans la couche applicative").
Ne pas tenter de 6ᵉ variante sans données nouvelles (piste B, entraînement sur
sessions longues, ou changement de modèle de base).

---

## 1.6 Recul architectural (2026-07-28) — 12 faux positifs sur 12, le modèle hors de cause

### Le fait qui change tout

Session de 268 mots, récitation **professionnelle**, moteur GOP aux commandes
(`[PARAMS] moteur=GOP`). 12 mots non verts. Vérification faite mot par mot en
donnant au **modèle du device** l'audio de la session, hors device :

| mot | fenêtre où le modèle le sort exactement |
|---|---|
| `عَظِيمٌ` | 3 s → `وَلَهُمْ عَذَابٌ عَظِيمٌ` (et PERDU sur 12 s) |
| `مُهْتَدِينَ` | 3 s → `وَمَا كَانُوا۟ مُهْتَدِينَ` |
| `لَذَهَبَ` | 2 s → `ٱللَّهُ لَذَهَبَ` |
| les 9 autres | trouvés d'emblée |

**12/12 produits correctement par le modèle.** Zéro faute de récitation, zéro
limite de modèle : douze faux positifs nés du découpage et de l'alignement.

### La faille centrale (nouvelle par rapport au recul du 26/07)

Le **verdict est rendu au rythme de la TRANSCRIPTION**, alors que rien ne l'y
oblige. La transcription doit être temps réel (le curseur avance) ; le jugement,
lui, peut attendre. Deux exigences opposées se partagent la même variable —
aucun seuil ne les départagera.

Corollaire : le **2ᵉ buffer tel qu'il est construit est un palliatif dans la
mauvaise couche**. Il tente de reconstruire mot par mot une information que la
couche de jugement a jetée en figeant trop tôt. D'où la boucle : chaque
correctif de fenêtre en appelle un autre.

Mesure du 2ᵉ buffer sur cette session — 33 tentatives, 18 mots :
**16 OK, 7 FAUX POSITIFS, 6 ratés, 4 indéterminés.** Un faux positif fait passer
au VERT un mot correctement signalé (le secours ne peut que « rattraper »).
Exemple net : mot 132 `يَعْلَمُونَ`, fenêtre décodant `وَإِذَا لَقُوا۟`
(verset 14 au lieu de la fin du 13), rendu `gop 0,00` trois fois.

### État de l'art

Le nom canonique de ce qu'on a construit est **two-pass / second-pass
rescoring**. Écart avec la littérature : la seconde passe y porte sur un
**segment avec contexte complet**, jamais sur un mot isolé — c'est exactement
la source des faux positifs et des ratés. Cf. arXiv 2008.13093, 2211.15432.
Sur les frontières, arXiv 2406.02560 (label priors) donne 12-40 % — côté
entraînement.

### Pistes (arbitrage utilisateur 2026-07-28 : autonomie accordée, objectif zéro orange)

- **A — Découpler jugement et transcription : juger au VERSET.** Le curseur reste
  temps réel ; le verdict d'un mot n'est rendu qu'au bout du verset, par
  ré-alignement du verset entier sur son audio complet. Traite la décision
  irréversible trop tôt ET l'alignement d'un mot isolé. Supprime toute la
  famille des correctifs de fenêtre. Coût : verdict retardé d'un verset
  (5-15 s). Effet de bord : le souffleur ne peut plus se déclencher au mot.
  **Recommandée.**
- **B — Couper uniquement aux marques de waqf** (`quran_waqf.json`, déjà
  identifié le 26/07, jamais fait). Traite la frontière au mauvais endroit,
  rend impossible la coupe en plein mot. Coût : segments longs si le récitant
  ne respecte pas le waqf.
- **C — Rendre le silence au 2ᵉ buffer** (flux brut + table de correspondance
  entre les deux horloges). **Écrite puis retirée le 2026-07-28 avant mesure**,
  pour ne pas committer un demi-changement — À GARDER COMME PISTE À TESTER
  (demande utilisateur). Mesuré ce jour-là : rendre le silence au modèle
  n'améliore PAS le WER (−2,8 pt en moyenne EN FAVEUR du portier, fenêtres
  disjointes 8/12/16/20/30 s sur audio réel). Ne se justifie donc qu'avec B,
  où le silence devient la donnée utile (waqf).
- **D — Label priors côté entraînement.** Seul vrai levier sur le peaky-CTC.
  Autre chantier.
