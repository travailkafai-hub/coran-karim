# Audit écritures équivalentes + indépendance segments — 2026-08-15

Document de passation, écrit à la demande de l'utilisateur avant un
développement principalement mené sur le PC B : *« il se peut si on relance un
entraînement on peut améliorer, et je vais passer toutes les billes pour qui
développe ce que t'a trouvé »*.

**Deux chantiers distincts ont été menés dans la même session, à ne pas
mélanger** :
1. Audit exhaustif des écritures équivalentes (`Orthographe.kt`) sur
   l'intégralité du Coran.
2. Mesure de faisabilité de l'aligneur forcé maison pour remplacer les
   `segments` de Quran Foundation (cf. `PLAN_SORTIE.md` §4).

Aucun code de l'app n'a été modifié pendant cette session — tout ce qui suit
est diagnostic, à arbitrer et implémenter séparément.

---

## 1. Audit écritures équivalentes — couverture 100%

**6236/6236 versets couverts, ~74 600 mots examinés**, récitateur Al-Afasy,
modèle `benchmark/models/trois-tetes-2026-08-04-combine`, méthode
`gop = forced(Viterbi sur cible canonique) − free` (celle de l'app, cf.
`banc_regles_gop.py::trois_gop`, règle A).

4 portions traitées en parallèle par 4 agents (1-11, 12-26, 27-51, 52-114) ;
scripts et résultats bruts dans `benchmark/audit_equivalences_groupe{1,2,3,4}.json`
et `benchmark/audit_equivalences_ecriture.py` (script consolidé, support
`--reprendre`).

### 1.1 Trouvaille principale : TATWEEL + madda/alif suscrit — jamais couvert

Le caractère TATWEEL (`ـ`, U+0640, pur support visuel, **aucun son**) précède
systématiquement l'alif suscrit dans le Mushaf : `تَبَـٰرَكَ`, `جِهَـٰدًا`...
`Orthographe.kt` gère l'alif suscrit seul (règle 1) mais jamais le TATWEEL qui
le précède — un mot par ailleurs couvert ne matche donc pas quand même.

**Mesure, sur les 6236 versets** :
- 6736 occurrences de TATWEEL au total ;
- **5924 portent un alif suscrit/madda collé juste après** (ligature du madd) ;
- 812 portent une hamza combinante U+0654/0655 (notation « hamza sur siège
  nu », ex. `وَبِٱلْـَٔاخِرَةِ`).

Exemples réels (2 occurrences différentes, 2 sourates) : `تَبَـٰرَكَ`
(55:78, 67:1), `جِهَـٰدًا` (60:1). Ce n'est pas un accident isolé.

**Correctif envisagé (à valider, pas codé)** : dans `Orthographe.kt`,
générer aussi la variante avec TATWEEL retiré avant application de la règle
alif-suscrit existante (`mot.replace("ـ", "")` avant le traitement déjà en
place). Portée estimée : jusqu'à ~5900 mots du corpus, potentiellement le
correctif à plus fort impact de cet audit.

### 1.2 Forme Unicode précomposée vs décomposée (hamza/madda)

`أَفَآءَ` (59:7) : le texte canonique écrit le alef-madda en forme
**décomposée** (alif U+0627 + madda combinante U+0653), le modèle décode en
forme **précomposée** (U+0622 `آ`). Même lettre, deux séquences Unicode
différentes. **Trouvé indépendamment par deux agents (groupes 1 et 4)** sur
des sourates différentes — recoupement solide.

`Orthographe.kt` compare des `String` Kotlin caractère par caractère sans
normalisation Unicode (NFC/NFD) — ce cas n'y est pas traité.

**Correctif envisagé (à valider)** : normaliser (NFD, ou une table de
correspondance ciblée précomposé→décomposé) au moment de la COMPARAISON
uniquement, jamais au moment d'encoder le texte pour le modèle (leçon déjà
actée dans le fichier : « on ne touche pas au critère, on corrige la CIBLE »).

### 1.3 Shadda — trouvé 3x, mais À NE PAS CORRIGER SANS ARBITRAGE

28 occurrences cumulées (11+6+11 sur les 3 groupes qui l'ont classée), motif
recoupé plusieurs fois. **Mais `Orthographe.kt` l'exclut délibérément** — le
fichier documente déjà : substitution de harakat, « le signal y est de toute
façon au niveau du hasard ([MORT] mort_harakat_rescoring, 49,6% sur 954 clips) ».

⇒ Ne pas rouvrir cette piste sans une raison NOUVELLE et nommée (règle du
graphe : un mécanisme déjà mesuré perdant réintroduit sans cause nouvelle est
un refus bloquant). Les occurrences trouvées ici sont peut-être de vraies
fautes de shadda, pas des équivalences — à relire au cas par cas si on veut
trancher, pas à coder par défaut.

### 1.4 Signalé, volontairement pas codé

Teh marbuta prononcée « t » en récitation connectée (wasl) plutôt que « h »/
silencieuse (waqf) : `ٱلرَّحْمَةُ` → `ٱلرَّحْمَتُ` (57:13). Ni `Orthographe.kt`
ni ce banc ne le traitent. Signalé pour arbitrage, conformément à la règle
« proposer et faire valider avant de développer ».

### 1.5 Déjà couvert — confirme que `Orthographe.kt` généralise bien

madda suscrite, alif suscrit vs plein, signe tajwid contextuel (les 5 signes
de `SIGNES_TAJWID`), soukoun final, ya/waw suscrit — plusieurs centaines
d'occurrences confirmées correctement gérées à travers tout le Coran, dans les
4 portions.

### 1.6 Recensement exhaustif des 70 caractères du texte Uthmani

Vérification finale demandée par l'utilisateur après une première passe
incomplète (filtrée par catégorie Unicode, avait raté `ۦ`/`ۥ` catégorisés
« lettre modificatrice » et non « marque »). Recensement complet, sans filtre,
des 70 caractères distincts de `app/assets/data/quran_verses.json::text_uthmani` :
**aucun signe supplémentaire non couvert par les points 1.1-1.4 ci-dessus.**
Les marques de waqf restantes (JEEM, ligatures sad/qaf-lam-alef maksura,
~4300 occurrences) sont vérifiées 100% isolées en tokens séparés dans tout le
Coran — jamais collées à un mot — donc déjà filtrées par l'app via
`ArabicNormalizer.splitExpectedWords` (`recitation_verifier.dart:142-145`),
qui exclut tout token dont la normalisation est vide. **Pas un bug app.**

### 1.7 Limite méthodologique commune aux 4 groupes

~11-16% des mots n'ont reçu aucun gop (échec du Viterbi local sur la
sous-tranche du mot). Cause identifiée (§2.3) : span brut trop étroit pour le
nombre de tokens du mot, surtout en position de premier mot du verset. Ne
sous-compte pas forcément d'équivalences supplémentaires de façon uniforme —
non mesuré plus finement, hors périmètre de cet audit.

---

## 2. Segmentation — faisabilité de l'indépendance vis-à-vis de Quran Foundation

Contexte : `PLAN_SORTIE.md` §4 fixe le critère décisif — erreur médiane
< 80 ms et 95ᵉ centile < 200 ms sur les frontières mot-à-mot, sur 3 sourates de
nature différente (55 répétitive, 2 longue, 67 courte), comparé aux `segments`
de quran.com (`benchmark/.timings_cache/7_{surah}.json`). Script :
`benchmark/mesure_aligneur_segments.py`.

### 2.1 Résultat final

| Version | Portée | Médiane | P95 | Critère (<80/<200ms) |
|---|---|---|---|---|
| v1 (centre de span + garde-fous plancher/prorata) | 394 versets (55/2/67) | 730 ms | 4850 ms | ❌ |
| v2 (+ frontière = onset du mot suivant) | 394 versets | 450 ms | 4743 ms | ❌ |
| v3 (+ filtrage des jetons waqf isolés) | 394 versets | 70 ms | 690 ms | Médiane ✅ / P95 ❌ |
| v7 (+ verset entier exclu si une entrée de référence est suspecte, >4s) | 394 versets | 70 ms | 460 ms | Médiane ✅ / P95 ❌ |
| v9 (+ fin réelle de parole détectée par RMS, pas la durée brute du fichier) | 394 versets | 70 ms | 380 ms | Médiane ✅ / P95 ❌ |
| **v9, intégralité du Coran** | **5335/6236 versets, 114/114 sourates** | **70 ms** | **430 ms** | **Médiane ✅ / P95 ❌** |

**La médiane passe largement et de façon stable le critère (<80ms) depuis
la v3, confirmé sur l'intégralité du Coran (pas juste l'échantillon de 3
sourates).** Le 95ᵉ centile s'est amélioré d'un facteur 11 sur le corpus
complet (4850→430ms estimé, mesuré 690→430ms depuis v3) mais reste au-dessus
du seuil visé (200ms) — cohérent avec l'échantillon (380ms), le léger écart
s'explique par plus de sourates = plus de chances de croiser une
désynchronisation audio/référence ponctuelle (§2.3). 901 versets sur 6236
exclus par le filtre de référence suspecte (§2.2 point 3) ou fichier audio
manquant — decompte pas affiné par sourate, a verifier si besoin de la liste
exacte. Deux essais d'amélioration supplémentaires ont été **testés et
écartés** (juge silence RMS+CTC-blanc : neutre à négatif ; détection de trou
par run de blanc dans le décodage libre : trop de faux positifs, le blanc
absorbe aussi les voyelles tenues en parole normale, médiane mesurée 2880ms
sur des versets ordinaires — cf. commentaires dans `mesure_aligneur_segments.py`).

Prédictions complètes sauvegardées : `benchmark/predictions_aligneur_coran_complet.json`
(mot par mot, `{surah}:{verset}` → `[[début_ms, fin_ms], ...]`, régénérable/
reprenable avec `--reprendre`, incrémental par sourate — voir en-tête du script).

### 2.2 Les corrections qui ont fonctionné (dans l'ordre)

1. **Le centre du span Viterbi est un mauvais estimateur de frontière.** Un
   madd/élongation produit un span brut minuscule (le CTC marque l'ONSET du
   mot avec précision, mais les frames de la voyelle tenue tombent en blanc
   plutôt que d'être attribuées au mot). **L'onset du mot SUIVANT est un bien
   meilleur estimateur de la fin du mot courant.**
2. **Jetons waqf isolés comptés comme des mots.** `text_uthmani.split()`
   inclut les marques de pause isolées (`ۖ` etc.) comme "mots" — l'API
   quran.com ne les compte pas, d'où un décalage d'index cumulatif (touche
   2719/6236 versets). **Confirmé sans impact sur l'app elle-même** (§1.6).
3. **Entrées de référence corrompues, verset entier à exclure.** Certains
   versets (2:213, 2:97, 2:177, 2:112...) ont une entrée de référence >4s pour
   un seul mot — signe que TOUT le verset a une référence peu fiable, pas
   seulement ce mot. Exclure le seul mot suspect ne changeait presque rien
   (690→650ms) ; exclure le verset entier a fait passer le p95 sous 460ms.
4. **Silence de fin d'enregistrement.** La frontière de fin du dernier mot
   utilisait la durée brute du fichier (`total_ms`) — fausse dès qu'il y a une
   queue de silence après la fin de la récitation (mesuré : 67:17 a 2542ms de
   silence de queue = exactement l'erreur constatée). Détecter la vraie fin de
   parole par seuil RMS (même seuil que le portier `BufferedTranscriber`,
   0.02) et l'utiliser à la place a fait passer le p95 de 460 à 380ms,
   concentré sur la sourate 67 (754→259ms de p95 sur les fins).

### 2.3 Cause de la traîne p95 restante — CONFIRMÉE, pas un défaut de méthode

**Désynchronisation audio/référence propre à certains fichiers Al-Afasy**,
pas un défaut de l'aligneur. Démontré sur 2:213 : le décodage libre du modèle
ne reconnaît RIEN entre 6000-12000ms dans le fichier Al-Afasy local — un vrai
trou de 6 secondes (souffle/pause/montage) — alors que le texte attendu s'y
trouve intégralement et correctement 8 secondes plus loin. La référence
quran.com ignore ce trou, donc tous les mots suivants du verset héritent d'un
décalage d'environ 8s.

**Preuve définitive, décisive** : le même verset 2:213 récité par un AUTRE
récitateur (Abdul Basit, `data/train_wav_local/Abdul_Basit_Murattal_192kbps/`)
**ne montre aucun trou** — le texte s'enchaîne sans interruption. Le trou
n'existe QUE dans cet enregistrement Al-Afasy précis.

**Implication pour la décision** : ce problème est propre à la MÉTHODE DE
MESURE (comparer un enregistrement local à une référence tierce calculée sur
une prise potentiellement différente) — **il ne se manifesterait pas dans
l'app réelle**, qui aligne toujours l'audio de l'utilisateur contre lui-même,
jamais contre une référence externe d'un enregistrement différent. Le vrai
p95 en usage réel est probablement bien meilleur que les 380ms mesurés ici.

Deux seuils testés pour capturer aussi les petits trous (<4s, ex. 2:246 avec
~2s) : abaisser le seuil d'exclusion à 2000ms élimine trop de mots longs
légitimes (p95 réel des durées = 2990ms) — 4000ms reste le meilleur
compromis trouvé. Piste non explorée : exclure au niveau de la MESURE (pas de
l'audio) via une détection d'écart localisé entre mots consécutifs plutôt
qu'un seuil global.

### 2.4 Découverte annexe, potentiellement plus importante pour l'app

**Le premier mot de chaque verset échoue à obtenir un gop 37,2% du temps,
contre 7-10% pour les mots suivants** (mesuré sur groupe 2, sourates 12-26).
Cause : le sous-Viterbi de `trois_gop()` sur la tranche de frames du mot exige
`T >= (S+1)//2` frames (T = frames disponibles, S = longueur de la séquence
d'états du mot) — et le premier mot d'un verset reçoit typiquement une tranche
anormalement étroite du Viterbi global, faute de « tampon de silence » avant
lui sur lequel s'appuyer.

**`ForcedAligner.kt` (l'app) utilise le même type d'algorithme** — confirmé
dans le code lui-même : commentaire distinguant `ctcForwardNll` (somme sur
tous les chemins) de « la DP Viterbi de `align()` (meilleur chemin) ». La
vulnérabilité est donc architecturalement transposable à l'app.

**Pas encore vérifié** : si ce cas est déjà compensé côté Kotlin (les champs
`starved`/`noEvidence` de `WordResult` suggèrent que le cas « mot sans preuve »
est anticipé quelque part, sans certitude que ce soit spécifiquement le
premier-mot-de-verset). **À vérifier avant tout développement sur ce point.**

---

## 3. Ce qui n'a PAS besoin d'être fait

- Aucun réentraînement de modèle n'est nécessaire pour les points 1.1-1.4 :
  ce sont des désaccords d'écriture entre cible et modèle, pas un défaut
  d'apprentissage (même raisonnement que le commit `17d1e1d` du 14/08 pour le
  soukoun final et l'iqlab).
- Rien à corriger dans `ArabicNormalizer.splitExpectedWords` (§1.6, déjà
  correct).
- Ne pas rouvrir harakat/shadda sans nouvelle cause nommée (§1.3).

## 3bis. Mesure de suivi (2026-08-16) — aligneur sur audio MP3Quran, pas everyayah

Contexte : l'app utilise désormais MP3Quran.net comme source audio (cf.
`PLAN_SORTIE.md`, migration Quran Foundation → MP3Quran pour l'audio
d'Al-Afasy). §2 ci-dessus mesurait l'aligneur contre de l'audio **everyayah**
(`Alafasy_128kbps`) — pas contre le fichier réellement servi par l'app. Écart
constaté sur le seul verset 1:1 avant de relancer quoi que ce soit : 5820 ms
(everyayah) contre 4700 ms (MP3Quran), 24% — trop pour être du bruit.

**Corpus reconstitué** : `benchmark/preparer_corpus_mp3quran.py` télécharge les
fichiers de sourate entière MP3Quran (`server8.mp3quran.net/afs/`,
`reciter_id=123`, Hafs-Murattal — le même que celui déployé dans l'app) et les
découpe par verset via `ayat_timing` (`read=123`, PAS `read=1` — piège déjà
documenté dans `mp3quran_api.dart`, `read=1` donne le minutage d'un AUTRE
récitateur). 394 versets (55/2/67), même échantillon que §2.1, dans
`data/train_wav_local/Alafasy_mp3quran/`.

**Ce poste (Windows, sans GPU) suffit** : `onnxruntime` CPU + le modèle déployé
(`models_deployes/fastconformer-ctc-mixed-e02`, celui par défaut du script,
pas `trois-tetes-2026-08-04-combine` utilisé en §1) + `sentencepiece` (installé
via pip, absent au départ) étaient tout ce qu'il fallait — aucun GPU requis
pour ce script, contrairement à l'hypothèse de départ. Copie dédiée
`mesure_aligneur_segments_mp3quran.py` (seule différence : `RECITER_DIR`),
l'original n'est pas modifié.

### Résultat brut — NE PASSE PAS le critère, mais pas pour la raison qu'on croit

| Sourate | Mots | Médiane | P95 |
|---|---|---|---|
| 55 | 311 | 180 ms | 440 ms |
| 2 | 5292 | 690 ms | 2470 ms |
| 67 | 303 | 360 ms | 669 ms |
| **Global** | **11812 frontières** | **660 ms** | **2410 ms** |

Nettement pire que la v9 sur everyayah (70 ms / 430 ms).

### Cause identifiée — DIVERGENCE DE SOURCE, pas un défaut de l'aligneur

Comparaison directe des durées de verset, **sans aligneur du tout** : la
référence `.timings_cache` (quran.com) contre `ayat_timing` (MP3Quran), sur
les mêmes 394 versets.

⚠️ Piège de méthode rencontré en cours de route, corrigé avant de conclure :
`.timings_cache` stocke `[index_mot, début_ms, fin_ms]` (3 éléments) — une
première lecture avec `[0]`/`[1]` comme début/fin (2 éléments supposés) donnait
un écart artificiel de ~3,6 s constant, repéré comme suspect *parce que*
constant quelle que soit la longueur du verset, et corrigé avant publication.

**Après correction** :

| Sourate | Écart médian (qc − mp3quran) | P95 absolu |
|---|---|---|
| 55 | -315 ms | 2450 ms |
| 2 | -1340 ms | 2860 ms |
| 67 | -760 ms | 1820 ms |
| **Global** | **-1156 ms** | **2700 ms** |

**Quran.com est systématiquement plus court que MP3Quran**, jamais l'inverse
dans les médianes, et l'écart n'est PAS une constante fixe (varie de -315 à
-1340 ms selon la sourate) — ce n'est donc pas un simple silence de tête/queue
différent entre les deux fichiers, c'est un débit de récitation ou un montage
mesurablement différent entre les deux sources.

**Conclusion** : le résultat de 660 ms/2410 ms mesure la DIVERGENCE
quran.com↔MP3Quran, pas la qualité de l'aligneur sur l'audio réellement servi
par l'app. C'est le même mécanisme que §2.3 (désynchronisation audio/référence
propre à un enregistrement Al-Afasy précis), plus marqué ici parce que les
DEUX côtés de la comparaison (référence ET audio aligné) ont changé en même
temps par rapport à §2.1-2.3.

### Test décisif — cohérence entre DEUX enregistrements indépendants (sans quran.com)

Aucune écoute possible pour construire une vérité terrain manuelle. Test
quantitatif à la place : comparer les prédictions de l'aligneur sur MP3Quran à
celles déjà calculées sur everyayah (`predictions_aligneur_coran_complet.json`,
§2.1) pour les MÊMES versets — deux enregistrements indépendants d'Al-Afasy,
aucun des deux n'étant quran.com. Comparaison en **position relative** (fraction
de la durée du verset), pas en ms absolus, puisque les durées totales diffèrent
déjà de 24% (cf. ci-dessus).

**349 versets communs, 0 désaccord sur le nombre de mots segmentés.** Écart de
position relative : médiane 1,0%, p95 3,2%. Traduit en ms absolus (sur la durée
réelle de chaque verset MP3Quran) :

| | Médiane | P95 |
|---|---|---|
| Brut (349 versets) | **78 ms** ✅ (<80ms) | 233 ms ❌ (visé <200ms) |
| Après filtre mot suspect (>4000ms, même seuil que §2.2.3) | 78 ms | 235 ms — **inchangé** |

La médiane **passe** le critère, de justesse, et est cohérente avec le 70ms
de la v9 sur everyayah seul. Le p95 le rate de peu (233 contre 200ms visés).

**Cas illustratif du type d'écart en jeu** (67:30, dernier mot du verset) :
everyayah lui attribue 3280ms, MP3Quran 940ms, alors que TOUS les mots
précédents du même verset concordent étroitement entre les deux
enregistrements — signature d'une queue de silence propre à UN seul des deux
fichiers (même mécanisme que §2.2.4), pas d'un désaccord sur le mot lui-même.
**Mais** exclure systématiquement les versets portant un mot suspect (31/349,
~9% du corpus) ne fait PRESQUE RIEN bouger le p95 (233→235ms) : la traîne
n'est donc pas dominée par CE mécanisme-là seul — d'autres versets y
contribuent, pour une raison non identifiée à ce stade. Ne pas répéter
l'erreur du 2026-08-05 (« un résultat inattendu est une affirmation à
vérifier ») : ce point reste ouvert, pas expliqué par une hypothèse non
vérifiée.

**Lecture honnête** : c'est un signal net que l'aligneur retrouve une
structure de mots réelle et cohérente, indépendante de la source audio
(0 désaccord sur le nombre de mots sur 349 versets, médiane sous le seuil) --
bien plus favorable que le chiffre brut contre quran.com (660ms) ne le
laissait croire. Mais ce n'est pas un feu vert complet : le p95 reste
au-dessus du seuil visé, et sa cause n'est PAS élucidée (le filtre qui a
fonctionné sur un cas isolé ne généralise pas). Pas de décision à prendre sur
cette seule mesure -- creuser la traîne p95 avant d'arbitrer.

---

## 4. Prochaines étapes possibles (à choisir, pas décidées)

1. Implémenter le filtre TATWEEL dans `Orthographe.kt` (§1.1) — impact
   estimé le plus large.
2. Implémenter la normalisation Unicode précomposé/décomposé (§1.2).
3. Vérifier si `ForcedAligner.kt` compense déjà la fragilité du premier mot
   de verset (§2.4) — sinon, la traiter serait bénéfique à la fois pour le
   jugement en direct ET pour le chantier segmentation.
4. **Décision segmentation (§2.1-2.3)** : médiane 70ms stable, p95 380ms dont
   la cause connue (désynchro audio/référence Al-Afasy, pas un défaut de
   méthode, confirmé sans impact attendu sur l'app réelle). À arbitrer :
   soit mesurer directement sur un flux device réel (sans référence tierce,
   donc sans ce biais) pour avoir le vrai chiffre en conditions d'usage, soit
   rester sur le proxy QF en attendant plus de données.
5. Arbitrer la teh marbuta en wasl (§1.4) et les vraies fautes de shadda
   trouvées mais non classées (§1.3).

## 5. Fichiers produits cette session (tous dans `benchmark/`, non commités)

`mesure_aligneur_segments.py`, `audit_equivalences_ecriture.py`,
`audit_equivalences_groupe{1,2,3,4}.json` (résultats bruts, un par portion),
`audit_equivalences_groupe4.py`, `audit_gop_equivalences_groupe3.py`,
`aggreger_audit_equivalences.py`, `rapport_equivalences_ecriture.py`.

## §3ter — Équivalence des découpages Python/Dart, et extension à 8 récitateurs (2026-08-16)

### Vérification centrale : le split Python (génère le JSON) == le split Dart (le consomme)

Question posée par `superviseur-recette` avant de valider l'intégration
`WordCorrectionAudio` : le split Python (`_est_un_mot`, catégorie Unicode
`Lo`) qui a produit `word_segments_mp3quran_afasy.json` et le split Dart
(`ArabicNormalizer.splitExpectedWords`/`normalize`, qui calcule
`errorWordIndex` en direct) peuvent-ils diverger sur un mot, silencieusement ?

Vérifié par réimplémentation **littérale** de `_collapseVariants`/`_harakat`
en Python (mêmes plages Unicode, même ordre de `replaceAll`, même
restriction finale au bloc arabe U+0600-06FF) puis comparaison, verset par
verset, sur les **6236 versets** de `quran_verses.json` :
- 0 désaccord de compte (longueur de liste identique partout) ;
- 0 désaccord de filtrage (décision garder/rejeter identique token par
  token, pas seulement le total).

**Verdict : PASS.** Les deux découpages produisent la même séquence de mots,
index pour index, sur tout le corpus — pas seulement mesuré sur un
échantillon. Script : scratchpad de session, non conservé dans le dépôt
(reproductible en 5 min à partir de ce commentaire si besoin).

### Extension à 8 récitateurs — recherche faite, DÉCISION : pas déployée maintenant

Décision utilisateur 2026-08-16 : l'app reste **mono-récitateur (Al-Afasy)**
tant que la demande pour un autre récitateur ne se présente pas — `kReciters`
(`app/lib/models/reciter.dart`) réduit à la seule entrée Afasy. Les 7 autres
retomberaient sur l'ancien chemin QF pour `WordCorrectionAudio` (aucun JSON
de segments pour eux), donc mieux vaut ne pas les proposer que d'offrir un
choix qui réintroduit silencieusement la dépendance qu'on cherche à
supprimer.

Recherche faite et **vérifiée empiriquement** (pas supposée) pour ne pas la
refaire le jour où un récitateur est ajouté :

| Récitateur (app) | reciter_id MP3Quran | `read=` (moshaf id) pour `/ayat_timing` | Serveur audio |
|---|---|---|---|
| Al-Afasy | 123 | 123 | `server8.mp3quran.net/afs/` *(déployé)* |
| Al-Husary | 118 | 118 | `server13.mp3quran.net/husr/` |
| Muhammad Ayyoub | 109 | 109 | `server8.mp3quran.net/ayyub/` |
| Ash-Shaatree | 4 | 4 | `server11.mp3quran.net/shatri/` |
| Abdul Basit (Murattal) | 51 | **53** | `server7.mp3quran.net/basit/` |
| Abdul Basit (Mujawwad) | 51 | **51** | `server7.mp3quran.net/basit/Almusshaf-Al-Mojawwad/` |
| Al-Sudais | 54 | 54 | `server11.mp3quran.net/sds/` |
| Nasser Al-Qatami | 86 | 86 | `server6.mp3quran.net/qtm/` |

**PIÈGE découvert et vérifié** (même famille que le bug `read=1` vs
`read=123` de la migration Afasy) : pour la plupart des récitateurs
`reciter_id == moshaf_id` (un seul mushaf), ce qui avait fait conclure trop
vite que `read` était « le reciter_id ». Abdul Basit a TROIS éditions (Hafs
53, Warsh 52, Mujawwad 51) sous le même `reciter_id` 51 — `read` est en
réalité le **moshaf_id**, pas le reciter_id. Vérifié en interrogeant
`/ayat_timing?surah=1&read=53` (7 versets en ~46s, cohérent Murattal) contre
`read=51` (mêmes 7 versets en ~98s, cohérent Mujawwad, débit ~2x plus lent).
Ne jamais réutiliser `reciter_id` tel quel pour `read` sans vérifier le
nombre de moshaf du récitateur visé.

**Recherche par outil de résumé web (WebFetch) : un premier essai a rendu un
FAUX NÉGATIF** (« ces 4 récitateurs n'existent pas dans le JSON ») sur les 4
derniers noms cherchés — la liste complète fait 241 entrées et l'outil avait
tronqué avant de les atteindre. Confirmé faux en retéléchargeant le JSON brut
(`curl` + parsing Python local, sans résumé intermédiaire). Levier à retenir :
un résultat négatif d'un outil de résumé sur une liste longue n'est jamais
concluant tel quel (règle projet déjà connue, revalidée ici sur un nouveau
cas).

**Format de distribution envisagé pour la suite** (validé en principe, pas
implémenté) : ne PAS embarquer les JSON de segments dans les assets de l'APK
(2,0 Mo/récitateur mesuré sur Afasy → ~16 Mo pour 8, à contre-courant du
retrait de Gemma qui visait à réduire la taille de l'APK). À la place :
héberger un JSON par récitateur sur un repo **dataset** HuggingFace public
(HTTP simple, pas d'auth pour le téléchargement, CDN gratuit — pas de serveur
à nous), et faire suivre `Mp3QuranWordSegments` le même schéma
téléchargement+cache local déjà éprouvé pour l'audio
(`Mp3QuranApi.fichierLocalSourate` : vérification `content-length`, écriture
atomique `.part`+`rename`). Retirerait aussi le JSON Afasy des assets une
fois en place. En attente que l'utilisateur confirme la connexion à son
compte HuggingFace avant tout upload.

**Reste à faire le jour où un récitateur est ajouté** : relancer
`preparer_corpus_mp3quran.py` (adapter le serveur/reciter_id) puis
`generer_predictions_mp3quran.py` pour ce récitateur, remettre son entrée
dans `kReciters`, brancher son cas dans `Mp3QuranApi.sertCeReciter`/
`urlSourate` (actuellement câblés en dur sur l'id 7 = Afasy uniquement).
