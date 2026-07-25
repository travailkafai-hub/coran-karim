# Architecture de la récitation — de l'audio au jugement du mot

Document de **lecture du code existant** : chaque couche traversée entre le
micro et la coloration d'un mot à l'écran, avec ses paramètres réels, ses
limites structurelles et les pistes d'amélioration (surtout côté buffer).

**Périmètre** : uniquement la chaîne de vérification de récitation (ASR, GOP,
buffer, alignement). Rien sur le graphisme/IHM.

**Complémentaire de** :
- `PROBLEMATIQUES_ASR.md` — énoncé des problèmes + état de l'art externe
  (forums/papers). Ici on décrit **le code tel qu'il est** et ce qu'on peut
  y changer, sans reprendre la bibliographie.
- `JOURNAL_TESTS_LOGS.md` — observations horodatées issues des tests réels.

---

## 1. La chaîne complète, couche par couche

```
┌─ MICRO ────────────────────────────────────────────────────────────────┐
│ package `record` — AudioRecorder.startStream()                         │
│ PCM 16 bits mono 16 kHz, blocs de 2560 octets = 1280 samples = 80 ms   │
└───────────────────────────┬────────────────────────────────────────────┘
                            │ ~12,5 blocs/seconde
┌───────────────────────────▼────────────────────────────────────────────┐
│ DART — AndroidRecitationVerifier._startStreamingCapture               │
│ recitation_verifier.dart (~L578)                                       │
│  • _levelCtrl.add(niveau)          → animation du halo micro           │
│  • await feedBufferedAudio(bytes)  → UN appel MethodChannel PAR BLOC   │
│  • dédup de l'alignement par `seq` (_lastAlignSeq)                     │
└───────────────────────────┬────────────────────────────────────────────┘
                            │ MethodChannel (~12,5 aller-retours/s)
┌───────────────────────────▼────────────────────────────────────────────┐
│ KOTLIN — FastConformerCtcPlugin."feedBufferedAudio" (~L193)            │
│  pcm16ToFloat() puis BufferedTranscriber.feed(samples, scope)          │
│  Retourne {committed, preview, align} À CHAQUE bloc                    │
└───────────────────────────┬────────────────────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────────────────────┐
│ KOTLIN — BufferedTranscriber (517 l.) : LE CŒUR DU BUFFER              │
│  a) portier RMS   : silence si RMS < 0,02 (~-34 dBFS)                  │
│  b) plafond silence conservé : 300 ms max par pause (blocs suivants     │
│     jetés, mais pauseSamples continue de compter)                      │
│  c) accumulation dans `samples` (plafond dur 180 s)                    │
│  d) décision de GEL (commit) :                                          │
│       – pause ≥ 450 ms (réglable 300-1500) ET segment ≥ 2,5 s          │
│       – OU segment ≥ 12 s (borne dure, sans pause)                     │
│  e) cadence de re-transcription : ≥ 1,5 s de nouvel audio              │
│  f) une seule inférence ONNX par passe → sert au texte ET au GOP       │
└───────────────────────────┬────────────────────────────────────────────┘
                            │ logprobs (T × 1024)
┌───────────────────────────▼────────────────────────────────────────────┐
│ KOTLIN — FastConformerCtc.computeAll()                                 │
│  MelSpectrogram.kt (mel 80 bandes) → ONNX Runtime                      │
│  ⚠ entrée `audio_signal` (mel), JAMAIS `raw_audio` (cf. CLAUDE.md)     │
│  Sorties : letters (tête 1) + tajwid (tête 2, 19 classes)              │
└──────────────┬───────────────────────────────┬─────────────────────────┘
               │ greedyDecode                  │ logprobs
               ▼                               ▼
     texte libre (« entendu »)      ┌──────────────────────────────────┐
                                    │ KOTLIN — ForcedAligner (928 l.)  │
                                    │  DP CTC : force les tokens       │
                                    │  attendus depuis l'ancre         │
                                    │  forced = logprob chemin forcé   │
                                    │  free   = max/frame (hors        │
                                    │           symboles de règles)    │
                                    │  gop    = forced − free  (≤ 0)   │
                                    │  max 80 mots/passe               │
                                    │  MIN_FRAMES_FOR_JUDGMENT = 3     │
                                    └──────────────┬───────────────────┘
                                                   │ payload {seq, anchor,
                                                   │  frontier, final, words[]}
┌──────────────────────────────────────────────────▼─────────────────────┐
│ DART — RecitationNotifier._onAligned (recitation_provider.dart ~L2493) │
│  • garde de génération de session (ajoutée 2026-07-25)                 │
│  • normGop = écart à la baseline par mot (_normalizedGop)              │
│  • seuils : correct ≥ -0,45 · unclear ≥ -1,60 (sensibilité 0,5)        │
│    tolérant -0,90/-2,50 · strict -0,20/-…                              │
│  • verrouillage (`lock`) définitif si `final=true`                     │
│  • émet `wordFailed` → boucle de correction de l'écran                 │
└──────────────────────────────────────────────────┬─────────────────────┘
                                                   │
┌──────────────────────────────────────────────────▼─────────────────────┐
│ DART — KaraokeRecitationScreen._onWordFailed                           │
│  pauseCapture → WordCorrectionAudio (audio réel du récitateur, timings │
│  quran.com) → resetBuffer → rewindAndUnlock → resumeCapture            │
└────────────────────────────────────────────────────────────────────────┘
```

### Le double chemin de jugement

Deux moteurs tournent **toujours en parallèle** et loguent chacun leur verdict
(`[GOP]` et `[TEXTDIFF]`), mais un seul pilote l'affichage
(`JudgementOptions.useGopScoring`) :

| | GOP (défaut) | Text-diff (repli historique) |
|---|---|---|
| Source | logprobs, alignement forcé | texte décodé librement |
| Sensible aux harakat | oui (tokens BPE distincts) | non (le décodage libre « corrige » déjà) |
| Émet `wordFailed` | oui (`_onAligned`) | **non** (`_realignFromFullText`) |
| Garde de génération | oui (depuis 2026-07-25) | **non** |

---

## 2. Les paramètres réels du buffer (référence chiffrée)

| Constante | Valeur | Fichier | Rôle |
|---|---|---|---|
| `SAMPLE_RATE` | 16 000 | BufferedTranscriber | — |
| bloc PCM | 80 ms (2560 o) | package `record` | granularité d'entrée |
| `SILENCE_RMS_THRESHOLD` | 0,02 (~-34 dBFS) | BufferedTranscriber | portier de silence |
| `MAX_SILENCE_SAMPLES` | 300 ms | BufferedTranscriber | silence conservé/pause |
| `MIN_NEW_SECONDS` | 1,5 s | BufferedTranscriber | cadence re-transcription |
| `DEFAULT_COMMIT_SILENCE_MS` | 450 ms | BufferedTranscriber | pause → gel |
| `MIN_COMMIT_SECONDS` | 2,5 s | BufferedTranscriber | plancher avant gel |
| `MAX_SEGMENT_SECONDS` | 12 s | BufferedTranscriber | borne dure de gel |
| `MAX_SECONDS` | 180 s | BufferedTranscriber | garde-fou mémoire |
| `maxAlignWords` | 80 | BufferedTranscriber | borne coût DP |
| `MIN_FRAMES_FOR_JUDGMENT` | 3 (~240 ms) | ForcedAligner | opportunité minimale |
| seuils GOP | -0,45 / -1,60 | recitation_provider | correct / unclear |

**Conséquence de la cadence** : un mot n'est jugé qu'au plus tôt ~1,5 s après
avoir été prononcé, et un verdict n'est *définitif* qu'au gel du segment
(pause ≥ 450 ms, ou 12 s). D'où la latence perçue de 1,5 à 3 s.

---

## 3. Limites structurelles du code actuel

### 3.1 Le verrouillage est irréversible mais décidé sur une information partielle

`final=true` (segment figé) → Dart verrouille **tous** les mots du payload,
frontière incluse. L'audio du segment n'est plus jamais réanalysé. Si la coupe
tombe juste avant qu'un mot soit prononcé, la DP doit « expliquer » des frames
de silence en y forçant le token attendu → score catastrophique verrouillé
pour toujours.

Deux garde-fous existent déjà, tous deux **partiels** :
- `MIN_FRAMES_FOR_JUDGMENT` (3 frames) diffère le mot frontière — mais
  seulement si l'audio *après* le dernier mot confirmé est lui-même quasi nul.
- `deferredOnceIndex` limite le report à **une seule fois** (« 2 chances
  max »), pour qu'un vrai mot sauté finisse quand même en rouge.

Observé dans le log du 2026-07-25 (`entendu=""` verrouillé) : mots 141, 169,
174 — jugés rouges avec transcript vide, alors qu'un audio existait.

### 3.2 Le portier RMS est un seuil fixe, sans calibration au bruit ambiant

`RMS < 0,02` en dur. Aucune estimation du plancher de bruit de la pièce ni du
niveau de voix de l'utilisateur. Conséquences aux deux extrêmes :
- pièce bruyante → aucun silence détecté → le gel sur pause ne tire jamais,
  seule la borne 12 s agit (et coupe en plein mot) ;
- voix douce / micro éloigné → début de mot classé silence et **jeté**
  (au-delà des 300 ms conservés) → le mot arrive tronqué à l'aligneur.

Observé : de nombreux `entendu` tronqués par la gauche ou la droite
(« وٰةَ » pour « ٱلصَّلَوٰةَ », « أَضَ » pour « أَضَآءَتْ », « كُمْ » pour
« مَعَكُمْ »).

⚠️ Le portier RMS a déjà été **désactivé en test** : WER 70,2 % contre 22,8 %.
Il ne s'agit donc pas de l'enlever, mais de le rendre adaptatif.

### 3.3 La normalisation per-feature dérive avec la longueur du segment

Le modèle recalcule mean/std sur **tout** le buffer à chaque passe. Plus le
segment est long, plus les statistiques s'éloignent de celles d'un clip
d'entraînement → la re-transcription peut s'effondrer après avoir été parfaite.
Le gel de segment est précisément le contournement de ce défaut, pas une
fonctionnalité voulue.

Piste identifiée mais **jamais validée** (notée dans le code) : statistiques
FIXES précalculées sur le corpus (`fixed_mean`/`fixed_std` NeMo), ce qui
supprimerait la dérive quelle que soit la durée. Mesure existante
(`test_norm_fixed_vs_perfeature.py`) : ne corrige rien **et** +1,28 pt de WER
sur le checkpoint actuel — donc à ne retenter qu'avec un checkpoint réentraîné
avec ces stats.

### 3.4 Coût du pont : ~12,5 aller-retours MethodChannel par seconde

`feedBufferedAudio` est appelé **par bloc de 80 ms**, sérialise le PCM, et
retourne à chaque fois `committed` + `preview` + tout le payload d'alignement —
alors qu'une vraie inférence n'a lieu que toutes les ~1,5 s. Le reste du temps,
c'est de la recopie pure. La déduplication par `seq` se fait **côté Dart**,
donc après avoir déjà payé la sérialisation.

### 3.5 L'ancre native et l'état Dart peuvent diverger pendant les corrections

`setAlignmentAnchor`, `extendAlignmentTarget`, `rewindAndUnlock`,
`resetBuffer` agissent sur des états séparés (natif vs Dart) avec des
latences différentes. Le code porte déjà plusieurs correctifs de courses de ce
type (`stopIfCurrentSession` 2026-07-16, garde de génération 2026-07-25) —
signe que la synchronisation repose sur des gardes ajoutées au cas par cas
plutôt que sur un modèle unique de session.

Restant identifié : `_onStructured`/`_realignFromFullText` (chemin text-diff)
n'a **pas** de garde de génération, et n'émet **pas** `wordFailed`.

### 3.6 Une seule passe, pas de second avis

Le segment figé est transcrit une fois, jugé, verrouillé. Aucun mécanisme ne
rejoue un segment douteux avec un contexte différent (fenêtre décalée,
recouvrement) pour confirmer un verdict rouge avant de le rendre définitif.

⚠️ Une fenêtre glissante naïve a déjà été testée : WER > 100 % par duplication
de texte. Ce n'est pas une piste « gratuite ».

---

## 4. Pistes d'amélioration du buffer — par rapport bénéfice/risque

Toutes à valider **hors device d'abord** (`simulate_sliding_window.py`,
`analyze_device_log.py`, `test_norm_fixed_vs_perfeature.py`) : quatre
correctifs « évidents » ont déjà été rejetés par la mesure (cf. CLAUDE.md).

### A. Portier RMS adaptatif — *fort bénéfice, risque moyen*
Estimer le plancher de bruit sur les ~500 premières ms de session (ou en
continu par percentile glissant) et fixer le seuil à `bruit × k` plutôt qu'à
0,02 en dur. Adresse directement §3.2 et les troncatures observées.
À mesurer : WER + taux de `entendu` tronqué, sur les mêmes audios qu'aujourd'hui.

### B. Ne pas verrouiller un rouge dont le transcript est vide — *fort bénéfice, risque faible*
Aujourd'hui `entendu=""` + `final=true` → rouge définitif. Or un transcript
vide sur un mot est plus probablement un artefact de coupe/capture qu'une vraie
faute (la faute typique produit un *autre* mot, pas rien). Politique possible :
ne jamais rendre `final` un verdict rouge à transcript vide — le laisser
`unclear` non verrouillé, ou forcer un report supplémentaire.
Bien délimiter avec le cas « mot réellement sauté » que `deferredOnceIndex`
protège déjà.

### C. Recouvrement au gel plutôt que coupe franche — *bénéfice moyen, risque moyen*
Conserver les ~300 ms d'audio précédant la coupe en tête du segment suivant
(sans re-juger les mots déjà verrouillés), pour que le premier mot du nouveau
segment ne démarre pas sur une transitoire tronquée. Différent de la fenêtre
glissante naïve déjà invalidée : le recouvrement sert au **contexte
acoustique**, pas à re-décoder du texte déjà figé.

### D. Alléger le pont — *bénéfice faible sur la qualité, réel sur la batterie/latence*
Déduplication du payload **côté Kotlin** (ne renvoyer `align` que si `seq` a
changé), et/ou accumulation de 2-3 blocs avant traversée du channel. Aucun
impact attendu sur le WER, mais moins de charge CPU/GC pendant la récitation.

### E. Gel piloté par le profil de pauses de l'utilisateur — *bénéfice moyen, risque faible*
`sessionPausesMs` collecte déjà les pauses réelles, et `setCommitSilenceMs()`
existe déjà (300-1500 ms). La boucle est branchée pour la **session de
référence** ; l'étendre à un ré-ajustement continu (médiane glissante des
pauses de la session en cours) rendrait le gel robuste aux récitateurs
rapides comme lents, sans nouveau paramètre exposé.

### F. Statistiques de normalisation fixes — *fort bénéfice théorique, bloqué*
Supprimerait la cause racine de §3.3 (donc la raison d'être du gel forcé à
12 s). Mais mesuré négatif sur le checkpoint actuel : ne peut se tenter
qu'avec un modèle réentraîné avec ces statistiques. À garder en tête pour le
prochain cycle d'entraînement, pas comme correctif applicatif.

---

## 5. Ce qu'il faut mesurer avant de toucher quoi que ce soit

| Banc | Répond à |
|---|---|
| `benchmark/analyze_device_log.py <log>` | ce que l'app a réellement fait (texte figé, blocages d'ancre, audio jeté par le portier) |
| `benchmark/simulate_sliding_window.py` | WER d'une politique de segmentation rejouée bloc par bloc sur du vrai audio |
| `benchmark/test_norm_fixed_vs_perfeature.py` | effet de la normalisation, du silence et de la longueur de buffer |

Rappel de la règle projet : **toucher à `BufferedTranscriber` sans mesure
préalable hors device = perte de temps garantie** (décision 2026-07-23, après
quatre correctifs « évidents » tous invalidés par la mesure).

---

# Refonte proposée (2026-07-25) — découpler la DÉCISION de la SEGMENTATION

Objectif fixé par l'utilisateur : **validation fluide**. Buffer long (bonne
transcription), décisions par mot rapides, sans attendre la fin d'un segment.

## Le constat qui impose la refonte

L'architecture actuelle fait dépendre **le retard de validation de la longueur du
segment**, parce qu'un mot n'est jugé définitivement qu'au GEL du segment qui le
contient. Toute tentative de réduire le retard passe donc par des segments plus
courts — et c'est mesuré comme nuisible :

| cible de segment | retard | qualité de transcription |
|---|---|---|
| 4,5 s (cible dynamique emballée) | 7–8 s, jusqu'à 17 s | `مِ ٱللَّهِ ٱلرَّحْمَحِيمِ`, `هُ` |
| 3,0 s (cible fixe) | 2,1–4,6 s | `ٱللَّهُمٍ`, `قِينَ`, `إِنَّقُونَ` — **pire** |
| 3,08 s hors device, coupe choisie sur tout l'audio | — | `ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِ` parfait |

La troisième ligne explique les deux premières : hors device je choisissais la
coupe **librement** dans tout l'audio ; dans l'app, la coupe du segment N+1 est
contrainte par celle du segment N. Une coupe qui tombe mal décale toutes les
suivantes — **les erreurs de frontière se composent**. Réduire la cible augmente
le nombre de frontières, donc le nombre d'occasions de se tromper.

⇒ On ne peut pas gagner en jouant sur la longueur. Il faut **cesser de lier la
décision au gel**.

## Architecture proposée : deux horloges indépendantes

Le concept de « segment » disparaît côté verdict. Il reste un **buffer roulant**.

### 1. Horloge de TRANSCRIPTION (inchangée dans son principe)
Ré-transcription du buffer entier toutes les ~1,5 s, jusqu'à 12 s de buffer.
Contexte long = transcription bonne (mesuré : aucune dégradation jusqu'à 5,6 s
quand le début est propre, et 9 mots justes sur 5,56 s).

### 2. Horloge de DÉCISION (nouvelle) — verrouillage par mot
À chaque passe, un mot est **verrouillé** si les trois conditions sont réunies :
- **(a)** il est entièrement couvert (`covered == true`, strictement avant la
  frontière) ;
- **(b)** son verdict est **identique sur les K dernières passes** (K = 2) ;
- **(c)** au moins un mot postérieur a reçu des frames (le récitateur est passé
  à la suite).

Retard de décision ≈ **1,5 à 3 s, indépendant de la longueur du buffer**.

La condition (b) remplace exactement ce que le gel apportait : le gel existait
parce qu'un aperçu peut être révisé (dérive de normalisation). La stabilité sur
K passes atteste la même chose, sans attendre la fin du segment.

### 3. Ancre et purge, continues
- L'ancre = premier mot non verrouillé. Elle avance **à chaque passe**, plus
  seulement au gel.
- Le buffer est rogné par l'avant jusqu'à la **frame de fin du dernier mot
  verrouillé**. Continu.
- Conséquence directe et décisive : le buffer commence **toujours sur une
  frontière de mot connue de l'aligneur**. C'est ce que la mesure a désigné comme
  facteur dominant de qualité — meilleur que n'importe quelle heuristique RMS.
- Le texte figé = celui des frames rognées (borne `toFrameIncl` de
  `greedyDecode`, déjà en place) → pas de duplication.

### 4. Garde-fous
- Buffer à 12 s sans aucun verrouillage (aligneur bloqué) → forcer une décision
  sur le mot de frontière (mécanisme « 2 chances max » existant) et rogner d'un
  montant fixe : la progression est garantie.
- `findCutOffset` / la coupe sur micro-silence deviennent **inutiles** : le point
  de rognage est une frontière de mot. Code à conserver en commentaire (règle du
  projet) avec la mesure qui l'a rendu obsolète.

## Effets de bord à arbitrer AVANT de coder

1. **Les verdicts peuvent changer avant de se figer** (un mot orange puis vert).
   C'est visible à l'écran. Atténué par la règle des K passes, mais c'est un
   changement de ressenti. Option : afficher le verdict provisoire dans une
   teinte plus claire jusqu'au verrouillage — décision utilisateur.
2. **Coût d'inférence.** Transcrire 12 s toutes les 1,5 s : mesuré 413 ms pour
   5,7 s de buffer, donc ~900 ms–1 s pour 12 s. À la limite de la cadence. En
   pratique le rognage continu devrait maintenir le buffer autour de 3–6 s, mais
   **à vérifier sur device**.
3. **Contexte gauche et normalisation.** Juste après un rognage le buffer est
   court → statistiques `per_feature` moins stables. Tentation : garder N ms
   d'audio déjà verrouillé comme contexte gauche. ⚠️ **La mesure du 2026-07-25
   dit que rajouter du contexte DÉGRADE** (±300 ms : `هُدًى لِّلْمُتَّقِينَ` → `هُ`).
   Mais elle testait de l'audio ajouté **des deux côtés** en allongeant le
   segment, pas un contexte gauche déjà jugé. **À mesurer séparément avec
   `benchmark/compare_onnx_on_device_wavs.py` avant de fixer cette constante.**
4. Ne corrige pas la sous-couverture de l'aligneur elle-même (33 % des mots
   tokenisés par le repli glouton de `CtcTokenizer`, d'où des `forced` très
   négatifs sur des mots bien prononcés). Chantier distinct : GOP invariant au
   découpage BPE.
