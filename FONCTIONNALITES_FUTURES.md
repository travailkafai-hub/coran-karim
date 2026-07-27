# Coran Karim — Fonctionnalités futures (pistes, pas implémentées)

Ce document liste des idées de fonctionnalités discutées et validées comme
pertinentes, mais volontairement **pas encore implémentées**. Chaque entrée
précise le problème, les options envisagées, et ce qu'il resterait à faire.

---

## 1. Vérification de la durée du madd (tajwid) — discuté le 2026-07-06

### Le problème

Le système actuel vérifie déjà, dans une certaine mesure, la **shadda**
(doublement) : le texte d'entraînement du modèle FastConformer garde les
harakat (y compris la shadda), et la comparaison côté app (`normalizeStrict`
dans `recitation_verifier.dart`) les garde aussi — donc si une shadda est mal
prononcée et que le modèle la transcrit différemment, ça remonte bien en
orange/rouge.

En revanche, le **madd** (prolongation d'une voyelle, 2/4/6 temps selon la
règle) n'est PAS vérifié. Cause précise : le alif suscrit (ٰ), marqueur écrit
du madd, est systématiquement remplacé par un alif normal — à la fois dans
les labels d'entraînement (`prepare_nemo_data.py::normalize_text`, ligne
`text.replace("ٰ", "ا")`) et dans la normalisation de comparaison de l'app
(`ArabicNormalizer._collapseVariants`). La durée du son n'existe donc nulle
part dans le texte comparé : le système ne peut techniquement pas savoir si
une voyelle a été tenue 2, 4 ou 6 temps. Toute détection apparente d'un madd
mal fait aujourd'hui est un effet de bord (l'audio sonne assez différemment
pour perturber la transcription), pas une vérification délibérée.

### Pourquoi c'est intéressant à creuser

Le dataset d'entraînement vient de vrais récitateurs professionnels qui
appliquent le tajwid — l'information acoustique existe potentiellement déjà
dans les enregistrements, juste pas exploitée pour ce but précis.

### Options envisagées, par ordre de coût croissant

**Option A — Extraire le timing déjà produit par le modèle actuel (pas de
réentraînement).** Le décodage CTC associe chaque caractère à une plage de
frames audio ; ce timing existe mais n'est pas remonté à l'app aujourd'hui.
**Limite connue** : le CTC est réputé "peaky" (pointu) — il tend à émettre le
caractère vers la fin du son réel plutôt que réparti dessus, donc ce timing
serait approximatif, pas une mesure fiable de durée.

**Option B — Mesurer la durée directement sur l'audio, sans passer par le
modèle (traitement du signal classique).** Le madd est fondamentalement une
propriété acoustique simple : un segment vocalique soutenu. Détectable par
énergie/voisement, indépendamment de tout modèle ASR. Probablement l'option
la plus fiable et la moins coûteuse pour CE problème précis — pas besoin de
réentraîner quoi que ce soit.

**Option C — Un modèle dédié (tête de classification séparée), en
réutilisant l'encodeur FastConformer existant par transfer learning.**
L'encodeur actuel (déjà entraîné sur l'audio coranique de vrais récitateurs)
capte probablement déjà des nuances acoustiques utiles, même sans avoir été
entraîné pour juger la durée. On pourrait lui greffer une nouvelle tête
(pas celle qui prédit du texte) entraînée sur un nouvel objectif :
"ce madd a-t-il duré assez longtemps ?".
- **Réserve 1 — données manquantes** : il faudrait des exemples étiquetés
  "madd correct / madd trop court" par mot, qu'on n'a pas. Piste réaliste :
  fabriquer des exemples négatifs en coupant artificiellement la voyelle
  allongée dans des récitations déjà connues comme correctes (le dataset de
  récitateurs professionnels existant).
- **Réserve 2 — qualité de l'encodeur pour cette tâche** : ayant été entraîné
  via CTC (objectif "peaky", voir option A), ses représentations internes
  pourraient être moins précises sur la durée qu'un modèle entraîné dès le
  départ avec un objectif sensible à la durée. Reste un bon point de départ
  (beaucoup moins cher qu'un modèle from scratch), pas une garantie de
  précision parfaite.

**Option D — Arrêter de normaliser le alif suscrit (ٰ) pendant
l'entraînement, pour que le modèle apprenne à le distinguer lui-même
(discuté le 2026-07-06).** Constat direct : la shadda EST vérifiable
aujourd'hui précisément PARCE QU'elle est préservée telle quelle dans les
labels d'entraînement (`prepare_nemo_data.py` garde les harakat) — le madd ne
l'est pas pour la raison symétrique inverse : son marqueur écrit (ٰ) est
explicitement collapsé en alif normal (`text.replace("ٰ", "ا")`), donc le
modèle n'a jamais eu la possibilité d'apprendre à le prédire distinctement.
En gardant ce marqueur intact dans les labels (comme la shadda), le modèle
pourrait apprendre à le transcrire spécifiquement quand l'audio reflète une
prolongation correcte — activant une vérification texte-à-texte du madd,
exactement comme pour la shadda, SANS extraction de timing CTC (option A),
SANS traitement du signal séparé (option B), SANS nouveau modèle (option C).
Potentiellement l'option la MOINS chère des 4 si l'hypothèse tient — mais
elle repose sur une hypothèse non vérifiée : que l'audio des récitateurs
professionnels varie assez acoustiquement selon la prolongation réelle pour
que ce soit apprenable par le modèle (plausible, jamais testé). Nécessite un
réentraînement complet pour être évalué (pas un simple changement de
décodage comme l'option A).

### Prochaine étape suggérée

Si cette piste est reprise, l'option D est la plus simple à TESTER en
premier (un changement de normalisation + un réentraînement, aucune nouvelle
donnée à collecter) avant d'investir dans les options B/C, plus coûteuses en
travail d'ingénierie. Si l'option D ne suffit pas (le modèle n'apprend pas la
distinction), retomber sur l'option B (DSP, la plus fiable structurellement)
plutôt que l'option C (plus lourde, résultat incertain).

---

## 2. Autres pistes déjà identifiées (détails dans leurs fichiers d'origine)

Pour éviter les doublons, ces deux idées restent documentées en détail à
l'endroit où elles ont été discutées — pointeurs ici pour qu'elles ne soient
pas perdues :

- **Données d'entraînement avec fautes délibérées et auto-étiquetées** —
  le modèle "corrige" parfois une vraie erreur de prononciation vers le
  texte canonique une fois qu'il a plus de contexte (biais vers le texte
  connu, car le dataset actuel ne contient que des récitations correctes).
  Piste : ajouter des récitations délibérément fautives, étiquetées avec ce
  qui a été RÉELLEMENT dit (pas le texte corrigé). Détails complets, avec le
  point critique sur l'étiquetage : `.claude/skills/model-training/references/asr.md`,
  section "Biais du modèle vers le texte canonique".

- **Segmentation v2b guidée par les marques de waqf** — découper l'audio
  continu (karaoké/coach) aux positions de pause légitimes connues a priori
  (marques de waqf du texte) plutôt qu'au silence détecté seul, combiné au
  profil de pauses personnel déjà appris de la récitation de référence.
  Contexte complet : `.claude/skills/model-training/references/asr.md`,
  section sur le rejet de la piste "stats fixes" (2026-07-05).

- **Mini-LoRA personnel (personnalisation vocale, niveau 3)** — un adaptateur
  léger entraîné sur les clips de CET utilisateur déjà vérifiés corrects,
  pour réduire les faux positifs sur sa voix spécifique. Réutiliserait le
  pipeline NeMo existant (`finetune_fastconformer.py`), qui supporte déjà les
  adaptateurs LoRA/PEFT nativement (jamais configuré dans ce projet). Discuté
  à l'origine avec Whisper (2026-06-27), plan concret depuis mis à jour pour
  FastConformer, le modèle réellement utilisé. Deux points non résolus avant
  de s'y lancer : le mécanisme de synchronisation téléphone→PC des clips
  vérifiés n'existe pas encore, et le volume minimal de voix vérifiée
  nécessaire pour un LoRA utile reste à valider empiriquement. Contexte
  complet : `.claude/skills/model-training/references/asr.md`, section
  "Personnalisation voix — niveau 3 : mini-LoRA personnel" ; mémoire
  [[voice-personalization-idea]] pour les niveaux 1 et 2 (déjà en place ou
  plus simples).

---

## 3. Vocabulaire du modèle incomplet pour les marques d'annotation — discuté le 2026-07-09

### Le problème

21 caractères d'annotation du script Uthmani (marques de waqf ۖۗۘۙۚۛۜ,
sukun ۟۠, imalah ۧ, iqlab ۭۢ, etc.) sont **absents des 1024 tokens du
vocabulaire** du modèle FastConformer actuel (vérifié empiriquement,
script `check_vocab_gap.py`, sur un échantillon de 1546 versets couvrant
16 sourates variées). Le modèle ne peut donc **structurellement jamais**
les produire en sortie, quelle que soit la qualité de la prononciation.

Conséquence concrète observée : le mot "لَيُنۢبَذَنَّ" (sourate Al-Humazah,
verset 4) restait bloqué en jugement "unclear" (orange) indéfiniment en
mode strict — le modèle reconnaissait bien le mot lui-même (similarité
1.00), mais `normalizeStrict()` comparait aussi la petite marque de meem
suscrit (ۢ, iqlab) qui n'apparaîtra jamais dans une sortie du modèle.

### Fix appliqué immédiatement (2026-07-09)

Les 21 caractères ont été ajoutés à `ArabicNormalizer._collapseVariants()`
(`recitation_verifier.dart`), au même titre que les autres marques déjà
ignorées (tatweel, hamza suscrite, dagger alif...). Ce sont uniquement des
aides de lecture (recommandations de pause, nuances de prononciation) —
pas des phonèmes distincts que la comparaison strict devrait exiger.
Fix côté comparaison seulement : rapide, sûr, mais ne permet pas de
vérifier ces nuances de tajwid (impossible de toute façon avec ce modèle).

### Piste plus profonde, pas implémentée : élargir le vocabulaire à l'entraînement

Le vrai fix serait d'inclure ces marques dans le vocabulaire du modèle et
de les préserver dans les labels d'entraînement (même logique que la
shadda, déjà conservée et vérifiable). Permettrait, à terme, de vérifier
le respect du waqf/tajwid plutôt que de simplement les ignorer. Nécessite
un réentraînement complet avec vocabulaire étendu (BPE/tokenizer à
reconstruire) — pas un simple changement de normalisation comme le fix
immédiat ci-dessus. Non prioritaire tant que le modèle de base n'est pas
autrement stabilisé.

---

## 4. Segmentation ASR par fenêtre glissante — discuté le 2026-07-09

### Le problème actuel

Le découpage en segments (`BufferedTranscriber.kt`) fige un segment sur
silence détecté (RMS bloc par bloc, seuil ~450ms) ou sur une limite dure de
12s. Ce détecteur ne connaît pas la grammaire : certaines lettres arabes
(occlusives comme ب، ذ، ن dans "لَيُنۢبَذَنَّ") ont des phases naturellement
peu énergiques dans leur prononciation même, sans aucune pause réelle de
l'utilisateur — le système peut donc figer un segment EN PLEIN MOT,
produisant un fragment quasi vide ("فين", "وين"...) là où une reconnaissance
avec plus de contexte aurait été correcte (confirmé : le même mot est bien
reconnu quand il n'est pas coupé).

### Piste proposée (utilisateur, 2026-07-09) : fenêtre glissante à taille fixe

Au lieu d'accumuler jusqu'à un déclencheur puis geler définitivement,
garder en permanence un buffer d'une taille à peu près constante (~5-10
mots). Chaque nouveau bloc audio fait glisser la fenêtre ; on retranscrit à
chaque glissement. Un mot est vu plusieurs fois à des positions différentes
dans la fenêtre au fil du glissement, avec plus ou moins de contexte —
plusieurs chances d'être bien reconnu au lieu d'une seule décision figée.

**Avantages attendus :**
- Plus de coupure arbitraire en plein mot (pas de décision de silence).
- Taille bornée -> règle aussi la dérive de normalisation "per_feature"
  (raison d'être du système de gel actuel).
- Un mot mal placé en bord de fenêtre a une seconde chance une fois plus
  centré dans une position ultérieure de la fenêtre.

**Complexité à résoudre avant d'implémenter :**
- Nouvelle règle de "validation définitive" d'un mot (plus de silence
  déclencheur) : par position (sorti depuis N glissements) ou par stabilité
  (même résultat sur M passages consécutifs).
- Suivi d'un même mot vu à plusieurs positions de fenêtre différentes —
  plus complexe que l'actuel texte figé accumulé en append-only.

Changement d'architecture conséquent côté moteur natif Kotlin — pas encore
implémenté, en attente d'une décision sur la priorité par rapport aux
autres chantiers ASR en cours.

### Mesures du 2026-07-23 — ce qui est vrai, ce qui est faux

Déclencheur : sur le log device `asm.log` (sourate 90), le verset 90:11
(فَلَا ٱقْتَحَمَ ٱلْعَقَبَةَ) n'a JAMAIS été validé alors qu'il avait été
correctement transcrit une fois — la transcription s'effondrait quand le
buffer grossissait (3 mots justes à 1s → 1 mot à 3s → "" à 4s), donc
`mots=0` sept fois et ancre figée à 42 pendant 22s. Corrélation 3/3 sur la
session : les seuls segments où l'aperçu régresse sont les 3 intervalles où
le portier RMS jette massivement de l'audio.

Script : `benchmark/test_norm_fixed_vs_perfeature.py` (+ variantes inline),
modèle `fastconformer-dual-head-v1`, 12 clips `val_canonical` 6-9s avec
hésitation simulée (4 pauses de 2s insérées).

**Trois hypothèses testées, TROIS REJETÉES** — à ne pas re-tenter :

1. *"C'est la dérive de normalisation per_feature, des stats FIXES la
   corrigeront"* (piste notée en fin de header de `BufferedTranscriber.kt`,
   jamais testée avant). **FAUX deux fois** : les stats fixes ne suppriment
   pas l'effondrement (transcription altérée 6/7 dans les deux modes) ET
   coûtent du WER (12,99% → 14,27%, +1,28 pt sur 150 clips) — le checkpoint
   n'a jamais vu ces stats à l'entraînement. La longueur seule ne dégrade
   d'ailleurs rien (7,3s se transcrit mieux que 1,8s), et 3s de silence
   ajoutés *à la fin* n'ont aucun effet (10,6% → 10,6%).
2. *"Le portier RMS est le coupable, il faut le désactiver"*. **FAUX** :
   sans lui, le silence conservé entier donne 70,2% de WER contre 22,8%
   avec. C'est un pansement utile, pas un bug.
3. *"Il faut couper le segment à chaque pause au lieu de recoller"*.
   **FAUX, et c'est le pire** : 103,5% de WER. Des fragments de ~1,3s
   privent le modèle de contexte et génèrent des insertions.

```
audio propre (référence)                       10,5 %
recollage — COMPORTEMENT ACTUEL                22,8 %   <- le moins mauvais
silence conservé entier (portier désactivé)    70,2 %
coupe à chaque pause (450ms ou 250ms)         103,5 %
```

**Conclusion : le code actuel est déjà optimal parmi ces options.** Il n'y a
pas de bug de segmentation à corriger. La cause réelle est un DÉCALAGE DE
DOMAINE — le modèle est entraîné sur des clips de versets propres et
continus, il n'a jamais vu de pause interne, et toute pause le fait
dérailler quelle que soit la façon dont on la traite.
→ Le vrai correctif est côté ENTRAÎNEMENT : augmenter les données avec des
pauses insérées (pleines ET recollées façon portier RMS). Pure augmentation
audio sur le corpus existant, aucune collecte nouvelle. Cf. §5.

⚠️ **Correction de vocabulaire (2026-07-23, objection utilisateur justifiée)** :
tout ce paragraphe parlait de "récitation hésitante", comme si le problème ne
touchait qu'un utilisateur incertain qui bute sur un mot — MESURE ET FAUX.
Sur la session `asm.log` qui a servi de départ à ce diagnostic, l'écart entre
versets figés est de **4 à 8 secondes de façon quasi constante** sur 14
intervalles sur 16 (`[6,5,5,6,7,6,8,5,5,5,5,4]` + deux valeurs hors norme à
19s et 13s, elles-mêmes en partie polluées par des re-transcriptions
dégradées en boucle, donc non attribuables avec certitude à une vraie pause
longue). Un rythme aussi régulier n'est pas de l'hésitation erratique, c'est
la **respiration normale entre versets** — potentiellement même une pause de
waqf obligatoire (cf. §9, le signe ۖ tombe justement avant 90:4 dans ce même
log). Ce n'est donc PAS un cas marginal réservé aux récitateurs peu sûrs
d'eux : ça touche tout le monde, y compris un récitateur confirmé (cf. le
tout premier test de cette session, sur un enregistrement professionnel).
La mesure technique (WER, coutures, rejet des 3 correctifs) reste
entièrement valable ; c'est la PORTÉE qui change — ce n'est pas une marge de
robustesse en périphérie, c'est une lacune sur le cas d'usage central
(« récitation continue » de plusieurs versets).

**Ce qui reste valable pour la fenêtre glissante** : la dégradation suit le
NOMBRE DE COUTURES créées par le portier — 10 coutures (3s de silence jeté)
→ 27,7% de WER, 20 coutures (6s) → 59,6%, contre 10,6% propre. Une fenêtre
de taille fixe **borne** ce nombre par construction. Elle ne guérit pas la
pause entre versets (seul l'entraînement le peut) mais elle plafonne les
dégâts —
c'est un gain mesuré, et c'est le meilleur argument pour cette piste.

⚠️ Ne pas confondre avec le **streaming cache-aware**, lui bel et bien
essayé et abandonné (verdict 2026-07-04, header de `BufferedTranscriber.kt`) :
convolutions non-causales → décodage 100% blank. La fenêtre glissante
re-transcrit une fenêtre ENTIÈRE en mode offline, sans cache — elle ne tombe
pas dans cet échec.

---

## 5. Pistes pour un prochain entraînement — découvertes pendant la refonte GOP (2026-07-11)

Contexte : refonte complète du scoring karaoké, remplaçant le diff textuel
flou par un **alignement forcé CTC** (le texte attendu est connu d'avance,
on aligne de force la séquence de tokens dessus et on mesure l'écart entre
la probabilité du chemin forcé et celle du meilleur chemin libre — score
GOP, cf. `ForcedAligner.kt`). Cette refonte a fait remonter des signaux
directement exploitables pour évaluer/améliorer le prochain modèle.

### 5.1 — Anomalie GOP constatée sur un mot bien prononcé : piste de diagnostic à grande échelle

En testant sur device, le mot "ٱلرَّحْمَـٰنِ" (ar-Rahman) est ressorti avec un
score GOP catastrophique (-5.11 puis -5.81 sur deux récitations séparées,
contre ~0.00 pour les mots voisins "الله" et "الرحيم") **alors que la
prononciation était correcte** (le décodage libre épelle bien le mot
attendu). Deux hypothèses vérifiées et écartées : divergence de tokenizer
(le greedy Kotlin coïncide exactement avec le vrai tokenizer NeMo, testé
mot par mot ET phrase complète) et normalisation incohérente (corrigée
séparément, cf. §5.3). La cause reste donc soit un vrai phénomène acoustique
(liaison/coarticulation entre "الله" et "الرحمن", l'un finissant et l'autre
commençant par un son proche, qui perturberait spécifiquement l'alignement
à CETTE frontière de mots), soit une limite de la DP d'alignement forcé
elle-même sur ce type de transition — pas encore tranché.

**Piste concrète pour la prochaine itération** : construire un script
d'évaluation systématique (pas juste ce mot isolé) qui fait tourner
l'alignement forcé sur tout `test_voice_full.jsonl` (récitations déjà
connues comme correctes) et relève tous les mots/positions dont le GOP est
anormalement bas malgré une reconnaissance libre correcte. Ça donnerait :
(a) un vrai jeu de calibration pour fixer `_kGopCorrect`/`_kGopUnclear` sur
des données réelles plutôt qu'à la main sur quelques exemples, (b) une
liste de positions structurellement fragiles (probablement concentrées aux
frontières de mots avec liaison phonétique) qui pourrait justifier un
objectif d'entraînement complémentaire si le phénomène est confirmé
récurrent.

### 5.2 — CTC "peaky" et frontières de mots : lien avec la piste madd (§1)

Le doc §1 notait déjà que le CTC est réputé "pointu" (peaky — émet le
caractère vers la fin du son réel) comme limite de l'option A (timing par
extraction CTC). L'anomalie 5.1 est cohérente avec cette même limite vue
sous un autre angle : si le modèle a appris à placer ses tokens de façon
imprécise dans le temps, l'alignement forcé — qui a besoin de savoir
précisément OÙ un mot commence/finit pour calculer un score par mot — hérite
directement de cette imprécision aux frontières. Si l'hypothèse liaison/CTC
peaky se confirme via 5.1, une piste d'entraînement à évaluer : un objectif
auxiliaire qui pénalise l'étalement temporel des tokens (encourage des
transitions plus nettes), ou un fine-tuning spécifique orienté alignement
plutôt que seulement reconnaissance libre.

### 5.3 — Dérive silencieuse entre normalisation d'entraînement et normalisation app : mettre un garde-fou

Bug trouvé et corrigé pendant cette session (pas une piste, un fait à ne pas
reproduire) : `ArabicNormalizer.normalizeStrict()` côté app avait accumulé
des fusions de lettres (أ/إ/آ→ا, ى→ي, ؤ→و, ئ→ي, ة→ه) qui n'existent PAS dans
`normalize_text()` du pipeline d'entraînement (`prepare_nemo_data.py`) — le
modèle a appris à distinguer ces lettres, mais la cible envoyée à
l'alignement forcé les fusionnait, désynchronisant silencieusement la cible
et ce que le modèle a réellement appris à prédire pour une grande partie du
vocabulaire coranique (ة apparaît dans des centaines de mots : صَلَاة،
حَيَاة، رَحْمَة...). Fixé en ajoutant `normalizeTraining()`, une copie fidèle
de la normalisation d'entraînement, réservée à la cible d'alignement.

**Piste pour éviter la récidive** : les deux fonctions (Python
`normalize_text` et Dart `normalizeTraining`) sont dupliquées à la main dans
deux langages — rien n'empêche qu'elles redivergent silencieusement au
prochain ajustement de l'une des deux. Envisager un test automatisé (script
qui compare la sortie des deux fonctions sur un échantillon de mots
coraniques et échoue si elles divergent) à faire tourner avant tout nouveau
déploiement de modèle, plutôt que de compter sur une relecture manuelle
pour l'attraper comme cette fois-ci.

### 5.4 — Dictionnaire mot→tokens précalculé avec le vrai tokenizer NeMo

Pas une idée pour le PROCHAIN entraînement à proprement parler, mais un
changement d'outillage qui devrait accompagner CHAQUE nouveau modèle
déployé désormais : au lieu de réimplémenter la tokenisation BPE
("greedy longest-match") côté Kotlin pour l'alignement forcé, précalculer
le dictionnaire mot→IDs de tokens avec le vrai tokenizer NeMo
(`build_word_token_lookup.py`, ajouté 2026-07-11) et le déployer comme
asset à côté de `vocab.json`. Élimine tout risque de divergence entre la
tokenisation utilisée pour l'alignement et celle réellement apprise par le
modèle — à régénérer et redéployer à chaque nouveau checkpoint entraîné.

---

## 6. Encoder les RÈGLES de tajwid (pas juste les marques) dans le texte d'entraînement — idée utilisateur, 2026-07-13

### Le problème / l'idée

Le modèle CTC actuel (tajweed, val_wer_ctc 5.82%, cf. session 2026-07-12/13)
apprend déjà les MARQUES écrites du tajwid préservées dans le texte (wasla,
dagger alif, maddah, waqf, sajda — cf. `prepare_nemo_tajweed.py`). Mais les
RÈGLES classiques de tajwid (idghâm, ikhfâ', iqlâb, qalqala, les 4 nuances
de madd...) n'ont PAS de symbole écrit distinct dans le texte Uthmani
standard — elles se déduisent de la séquence des lettres, et ne sont
aujourd'hui exploitées dans l'app que pour de la COULEUR d'affichage (pas
vérifiées à la récitation).

Idée : puisque ces règles ont chacune une vraie signature acoustique
(assimilation, nasalisation, rebond, allongement), inventer un symbole par
règle (ou famille de règles), l'insérer dans le texte d'entraînement aux
positions concernées, et laisser le modèle apprendre à les reconnaître —
exactement comme il a appris le madd/waqf/sajda. Objectif final : pouvoir
comparer une récitation non seulement au texte + harakat, mais au texte +
règles de tajwid, et détecter qu'une règle précise n'a pas été respectée
(pas seulement que le mot est mal prononcé).

### Bonne nouvelle : la source de données annotée existe déjà dans le projet

Pas besoin de la chercher ni de la construire : l'app récupère déjà depuis
l'API quran.com le champ `text_uthmani_tajweed`, qui contient le texte avec
des balises `<tajweed class=X>...</tajweed>` marquant précisément quelles
lettres relèvent de quelle règle. **17 classes déjà catalogées et
vérifiées** dans `app/lib/widgets/tajweed_text.dart` (`_classColors`) :
madda_necessary, madda_obligatory, madda_permissible, madda_normal,
ghunnah, ikhafa, ikhafa_shafawi, idgham_ghunnah, idgham_shafawi, iqlab,
idgham_wo_ghunnah, idgham_mutajanisayn, idgham_mutaqaribayn,
laam_shamsiyah, ham_wasl, slnt, qalaqah — aujourd'hui mappées à des
couleurs, à remapper vers des symboles textuels pour l'entraînement.

Piège déjà documenté à ne pas retraverser (même fichier, commentaire
2026-07-10) : `text_uthmani_tajweed` ne contient PAS toujours exactement
les mêmes caractères que `text_uthmani` une fois les balises retirées
(4278/6236 versets diffèrent, ex. dagger alif ٰ remplacé par ٲ U+0672) —
toujours ancrer les caractères affichés/entraînés sur `text_uthmani`
canonique, et n'utiliser `text_uthmani_tajweed` QUE comme source de
règle/position, jamais comme source de caractères (cf. `_remapWordColors`
et son commentaire pour le pattern déjà validé côté app).

### Ampleur du chantier si repris

Comparable à ce qui vient d'être fait pour le tajweed actuel : télécharger
`text_uthmani_tajweed` pour les 114 sourates (même API/méthode que les
téléchargements tafsir), convertir les classes en symboles réservés,
reconstruire le tokenizer BPE (nouveau vocabulaire), régénérer les
manifests, et réentraîner (`change_vocabulary` + fine-tuning complet,
comme fait pour la bascule pc→pcd→tajweed). Non prioritaire tant que le
modèle tajweed actuel n'est pas validé en usage réel sur l'appareil.

---

## 7. Export ONNX end-to-end (audio brut) au lieu de mel calculé côté Kotlin — piste, 2026-07-13

### Le constat

En déployant le modèle tajweed, confusion entre deux formats d'export
possibles pour FastConformer CTC, tous deux déjà écrits dans le projet :

1. **Mel calculé côté Kotlin** (`export_pcd_checkpoint.py`, `model.export()`
   natif NeMo) : le plugin (`FastConformerCtc.kt`, `MelSpectrogram.kt`)
   calcule lui-même le mel-spectrogramme et l'envoie à l'ONNX sous le nom
   `audio_signal` + `length` — l'ONNX ne contient QUE encodeur+décodeur CTC.
   **C'est le format réellement utilisé aujourd'hui par l'app.**
2. **Pipeline E2E audio brut** (`export_pcd_full_pipeline.py`,
   `export_tajweed_full_pipeline.py`) : l'ONNX prend l'audio brut
   (`raw_audio` + `length`) et fait TOUT en interne, y compris le calcul
   mel — pensé justement pour éviter d'avoir à maintenir ce calcul (FFT,
   fenêtrage, dither, log-guard) dupliqué et synchronisé à la main entre
   Python (entraînement) et Kotlin (inférence mobile). **Écrit, validé
   (PyTorch==ONNX), mais jamais branché côté Kotlin** — le plugin envoie
   toujours `audio_signal`, pas `raw_audio`, donc ce format E2E casse la
   transcription si déployé tel quel (constaté en déployant le modèle
   tajweed le 2026-07-13 : `Unknown input name audio_signal, expected one
   of [raw_audio, length]`).

### L'avantage du format E2E, s'il était un jour branché

Élimine un risque de divergence silencieuse déjà bien réel dans ce projet
(cf. §5.3 : la normalisation d'entraînement et celle de comparaison avaient
déjà dérivé sans que personne ne le remarque immédiatement). Le calcul mel
est une étape numérique fine (fenêtrage exact, dither, garde logarithmique)
— la reproduire à l'identique en Kotlin est un risque permanent de bug
subtil (résultats légèrement différents de l'entraînement, dégradant le
WER sans erreur visible). Le format E2E supprime ce risque : Kotlin n'a
plus qu'à envoyer les échantillons audio bruts, le graphe ONNX fait
exactement ce que PyTorch a fait à l'entraînement.

### Ce qu'il faudrait pour le brancher réellement

Réécrire `FastConformerCtc.kt` (et `MelSpectrogram.kt` deviendrait inutile)
pour envoyer `raw_audio`/`length` au lieu du mel précalculé — changement
côté app, pas côté modèle (le graphe ONNX E2E est déjà prêt et validé).
Non prioritaire tant que le format mel-côté-Kotlin actuel fonctionne
correctement (cf. §5.3 pour le vrai risque : s'assurer que le mel Kotlin
reste synchronisé avec celui de l'entraînement à chaque changement).

---

## 8. Corpus de récitations à harakat délibérément fautives — repris de la session Windows, 2026-07-14

### Le problème (déjà documenté ailleurs, jamais construit)

`.claude/skills/model-training/references/asr.md` (§"Biais du modèle vers
le texte canonique", 2026-07-05) documente un bug réel et déjà observé :
si l'utilisateur récite volontairement une harakat fautive (ex. "الحمدِ"
avec kasra au lieu de "الحمدُ" attendu avec damma), le modèle transcrit
correctement l'erreur sur un aperçu court (peu de contexte), puis "corrige"
tout seul vers le texte canonique dès qu'il a plus de contexte — alors que
l'utilisateur n'a rien redit de travers. Cause probable : le corpus
d'entraînement ne contient QUE des récitations correctes (aucune paire
audio/texte fautive), donc pour les formules très répétées le modèle a
appris "ce son → exactement ce texte canonique" avec une confiance
écrasante.

Cette piste était déjà "discutée avec l'utilisateur, PAS implémentée"
dans le doc Windows d'origine, et **reste non implémentée** : vérifié
2026-07-14, aucun dataset de ce type n'existe sur le disque (`arabic_speech_corpus/`
est un corpus académique générique sans lien avec le Coran ni avec des
erreurs délibérées ; les manifests `manifest_youtube_bad/clean.jsonl` sont
un tri qualité ASR, pas des erreurs volontaires).

### Idée retenue à l'époque : auto-étiquetage par erreur volontaire

Protocole envisagé (2026-07-05) : quelqu'un qui sait exactement quelle
erreur il vient de faire enregistre une récitation délibérément fautive
(harakat inversée, mot substitué/sauté), étiquetée avec le texte
**réellement dit** (fautif), jamais le texte corrigé — coller le texte
canonique en face d'un audio fautif reproduirait exactement le mécanisme
qui a créé le biais. Limite déjà notée : ne scale pas à des milliers
d'heures (dépend d'un humain qui s'auto-corrige consciemment).

### Complément évoqué le 2026-07-14 : synthèse TTS pour scaler le volume

Repris en session le 2026-07-14 (référence floue à un sigle "RLS20%" —
non identifié avec certitude, l'utilisateur ne se souvenait plus du terme
exact utilisé dans la session Windows d'origine ; **à clarifier si
retrouvé**). L'idée sous-jacente évoquée : utiliser un moteur TTS arabe
pour SYNTHÉTISER de l'audio avec des harakat volontairement fausses,
plutôt que de dépendre uniquement d'enregistrements humains — un TTS
permet de générer à volonté n'importe quelle combinaison harakat/texte
avec un étiquetage garanti exact (on contrôle exactement ce qu'on demande
au moteur de prononcer), réglant le problème de scalabilité du protocole
d'auto-étiquetage humain. Contrepartie à évaluer si repris : l'acoustique
TTS diffère de la voix humaine (risque de sur-ajustement à des artefacts
de synthèse plutôt qu'à la vraie confusion harakat) — mélanger avec une
petite quantité d'erreurs humaines réelles (protocole ci-dessus) plutôt
que de tout synthétiser. Ratio évoqué mais non confirmé : ~20% du corpus
total en erreurs délibérées (synthétiques et/ou humaines), reste à valider
par expérimentation avant de s'engager sur ce chiffre.

### Statut

Piste non prioritaire au moment de la rédaction initiale, distincte du fix
de normalisation 2026-07-14 (§5.3) et du bug BPE/alignement — n'affecte pas
la fiabilité du suivi de couleur, seulement le biais du modèle en cas de
faute réelle de l'utilisateur. **Confirmée par un test réel le 2026-07-14**
(cf. §8bis ci-dessous) : substitution volontaire ص/س sur Sourate An-Nas,
gop=0.00 partout, aucune détection — preuve concrète du biais, pas
seulement théorique. Deux pistes de mise en œuvre concrètes proposées et
en cours d'implémentation (§8bis et §8ter).

---

## 8bis. Montage audio par lettres confusables — piste modèle de BASE, 2026-07-14

### Le principe : "chemin inverse" plutôt que génération

Au lieu d'enregistrer de nouvelles fautes ou de synthétiser par TTS (§8),
réutiliser l'alignement forcé CTC (fiabilisé le jour même, cf. §5.3 et le
fix `ForcedAligner.kt`/`MIN_FRAMES_FOR_JUDGMENT`) pour repérer les
frontières EXACTES (en frames) de lettres précises dans l'audio déjà
existant (284k clips, 54 récitateurs), puis **monter/splicer** des segments
réels entre eux pour fabriquer des "fautes" composées à 100% de vraie voix
humaine — sans jamais enregistrer une seule nouvelle prise.

### Étapes

1. **Table des paires confusables** (tajweed classique, makharij proches) :
   ص↔س, ض↔د↔ظ, ط↔ت, ذ↔ز↔ظ, ح↔ه↔خ, ق↔ك, ع↔ء, غ↔خ.
2. **Repérage automatique** : pour chaque mot du corpus contenant une lettre
   cible, utiliser la DP d'alignement forcé pour trouver ses frames exactes.
3. **Montage** : chercher ailleurs dans le corpus un passage où la lettre
   confusable apparaît naturellement (idéalement même récitateur, pour la
   cohérence timbre/voix), extraire ce segment réel, le substituer dans
   l'audio cible à la place du son visé.
4. **Étiquette = texte réellement obtenu après montage** (avec la lettre
   substituée), jamais le texte canonique — même principe que §8.
5. **Dosage** : ~10-20% du corpus en exemples synthétiques, sans remplacer
   les données propres.

### Risque principal

Artefact acoustique au point de raccord (discontinuité timbre/pitch) que le
modèle pourrait apprendre à repérer comme signal "montage" plutôt que la
vraie confusion phonétique. Mitigation : couper uniquement aux frontières
de blank/silence déjà détectées par la DP, prioriser les raccords
intra-récitateur.

### Statut

Chantier lourd (table de confusion + extraction + montage + réentraînement
complet du modèle de base) — bénéficie à TOUS les utilisateurs, contrairement
à §8ter. En cours d'implémentation (script Python), 2026-07-14.

---

## 8ter. Calibration voix personnelle par mots confusables — piste mini-LoRA, 2026-07-14

### Le principe

Étendre l'infra de personnalisation vocale existante (`finetune_fastconformer_lora.py`,
"mini-LoRA personnel niveau 3", implémenté 2026-07-12, PC-assisté — **distinct**
de la tentative "100% on-device" via `onnxruntime-training-android` qui,
elle, a échoué et a été revertée le même jour, cf. commits `2ebb383`→
`6861b0b`→`9a61b77` ; la conclusion de cet échec dit explicitement de
rester sur le mini-LoRA v1 PC-assisté). Ce pipeline prend déjà en entrée
des clips exportés depuis l'app avec le texte **réellement prononcé**
comme étiquette (`VoiceLoraClipService`) — exactement ce qu'il faut ici.

### Étapes

1. **Liste de calibration** (~15-30 vrais mots coraniques contenant des
   lettres confusables, cf. table §8bis).
2. **Écran guidé "calibration voix"** : pour chaque mot, demander à
   l'utilisateur de le dire deux fois — correctement, puis en substituant
   délibérément la lettre confusable, avec instruction explicite affichée.
3. **Réutiliser le pipeline de capture existant tel quel** — aucun nouveau
   code d'entraînement, juste alimenter `VoiceLoraClipService` avec ces
   nouveaux clips (texte fautif = étiquette pour les prises "exprès").

### Différence avec §8bis

Corrige UNIQUEMENT la sensibilité de CET utilisateur (adaptateur LoRA
personnel léger, base gelée) — rapide (~5-10 min d'enregistrement guidé),
mais ne bénéficie qu'à lui. Complémentaire à §8bis, pas un substitut.

### Statut

Chantier léger, infra de base déjà en place. En cours d'implémentation
(écran Flutter + liste de mots), 2026-07-14.

---

## 9. Le WAQF (règles d'arrêt) comme classe de tajwid à part entière — idée utilisateur, 2026-07-23

### Le constat

L'arrêt EST une règle de tajwid, et certains arrêts sont **interdits**
(waqf mamnū'). Or **aucune des 17 classes** du modèle actuel ne la couvre
(vérifié) et l'app ne la vérifie nulle part. Un « coach qui contrôle le
tajwid » sans rien dire des arrêts a un trou fonctionnel visible.

### Ce qui est déjà faisable SANS ré-entraîner (implémenté le 2026-07-23)

Les signes sont **déjà dans le texte uthmani** — 4 363 mots en portent un,
extraits par `benchmark/build_waqf_asset.py` vers
`app/assets/data/quran_waqf.json` :

```
jaiz       1972   ۚ ج    arrêt permis
wasl_awla  1682   ۖ صلى  mieux vaut continuer
waqf_awla   603   ۗ قلى  mieux vaut s'arrêter
mamnu        68   ۙ لا   arrêt INTERDIT
lazim        22   ۘ م    arrêt OBLIGATOIRE
muanaqah     12   ۛ ···  s'arrêter à l'UN des deux, jamais aux deux
sakta         5   ۜ س    pause brève SANS reprendre son souffle
```

Et l'app **mesure déjà les pauses** (`BufferedTranscriber`,
`MIN_TRACKED_PAUSE_MS = 150`, durées collectées pour le profil de rythme).
Juger le waqf ne demande donc qu'une comparaison « pause détectée » ×
« signe attendu à cette position » : aucune tête de modèle, aucun
entraînement.

⚠️ Piège d'indexation : ces signes sont des tokens SÉPARÉS placés APRÈS le
mot concerné (`'رَيْبَ', 'ۛ', 'فِيهِ'`) et sont FILTRÉS de la liste des mots
récitables (`splitExpectedWords` — le regex `_harakat` couvre la plage
ۖ-ۭ). L'asset stocke donc l'index du mot RÉCITABLE, pas celui du split brut.
Le rub-el-hizb ۞ tombe dans la même plage Unicode mais n'est PAS un waqf.

### Ce qui justifierait un ENTRAÎNEMENT (demande utilisateur 2026-07-23)

La détection binaire « il y a un silence » est triviale, mais elle ne
distingue pas ce qu'un professeur distingue :

- un **arrêt propre** (waqf : on coupe le son ET on reprend son souffle)
  d'une **sakta** (pause brève, sans reprendre son souffle — 5 occurrences,
  règle à part entière) ;
- un arrêt **volontaire** d'une **hésitation** ou d'une reprise de souffle
  mal placée ;
- la façon dont la **dernière syllabe est traitée à l'arrêt** (le waqf
  modifie la prononciation finale : sukūn, rendu du tanwīn, hâ' de pause…),
  qui est la vraie compétence évaluée.

Ces distinctions sont acoustiques et graduées : c'est exactement le profil
d'une classe apprise, comme les autres règles de la tête 2. À ajouter au
corpus annoté d'un prochain run (les positions sont déjà connues via les
signes du texte — reste à étiqueter, dans l'audio, si le récitant s'est
effectivement arrêté et comment).

### Lien avec la segmentation du buffer (important)

Le gel technique d'un segment et l'arrêt du récitant sont **deux choses
différentes** qu'il ne faut jamais confondre : le premier est invisible, le
second est une note pédagogique. Conséquence pour le choix du point de
coupe : ne jamais couper là où les mots doivent rester LIÉS (arrêt `mamnu`,
ou règle de jonction enjambant la frontière) — couper là détruit la
continuité acoustique que la tête tajwid doit justement mesurer.

## Idée utilisateur (2026-07-26) — utiliser TOUT le Warsh, pas l'exclure

Au lieu d'exclure les clips Warsh d'un manifest Hafs (approche actuelle,
`build_hafs_only_manifest.py`), **aligner chaque clip avec le texte de SA
propre riwaya** : audio Warsh → texte Warsh canonique, audio Hafs → texte
Hafs. Aucune donnée n'est jetée.

**Pourquoi ce n'est pas fait aujourd'hui** (`CLAUDE.md`, piste 🔴) : chantier
séparé et lourd — texte Warsh différent du Hafs, numérotation des versets
décalée (déjà constaté sur les sourates 1, 2, 57 — cf. `asr.md` §Warsh),
nécessite un ré-alignement forcé complet, une source de texte Warsh canonique
verset par verset, et une détection fiable Hafs/Warsh par clip (le script
`verify_reciters_hafs_warsh.py` écrit le 2026-07-26 pour une vérification
rapide a un bug de normalisation des harakat le rendant inutilisable en l'état
— à refaire proprement si ce chantier est un jour prioritaire).

Non prioritaire tant que le pipeline Hafs seul n'est pas stabilisé (règle déjà
actée). Piste à reprendre une fois la piste streaming causale terminée.

---

## 10. Durées de référence : la source quran.com est un cul-de-sac sur les cas durs — déduire les durées de la RÉCITATION DE RÉFÉRENCE (idée utilisateur, 2026-07-27)

### Ce qui est implémenté aujourd'hui (commit f634f92)

Un plancher de durée par mot, médiane sur 9 récitateurs murattal, collecté par
`benchmark/collect_word_timings.py` via l'API quran.com
(`/api/v4/recitations/{id}/by_chapter/{s}?fields=segments`), embarqué en asset
(`app/assets/data/word_timings_ms.json`, 156 Ko) et acheminé jusqu'à
`ForcedAligner` (`WordTimingService` → `RecitedWord.refMinFrames` →
`setAlignmentTarget`). Aucun appel réseau au runtime. Sert **uniquement** à
excuser un mot étranglé (`starved`), jamais à en condamner un — cf. le bloc
« DEUX PLANCHERS, DEUX USAGES » en tête de `ForcedAligner.kt`.

### Le défaut mesuré le 2026-07-27 : la couverture s'effondre là où on en a besoin

Le découpage en mots de quran.com ne correspond pas toujours au découpage
canonique `text_uthmani.split()` (vérifié sur les 9 récitateurs : ils donnent
TOUS le même nombre de segments pour un verset donné — c'est le référentiel
quran.com qui fusionne des groupes de mots, pas un récitateur). Tout écart de
comptage est exclu, par la règle positionnelle du projet. Résultat :

| Longueur du verset | Versets couverts |
|---|---|
| 1-5 mots | 1503/1528 (**98 %**) |
| 6-10 mots | 1177/1528 (77 %) |
| 11-20 mots | 773/2083 (37 %) |
| 21-40 mots | 66/958 (7 %) |
| 41+ mots | 1/139 (**1 %**) |

Médiane de longueur : **6 mots** pour les versets couverts, **18 mots** pour
les absents. La couverture est donc **inversement corrélée à la longueur du
verset** — or c'est exactement sur les versets longs que les problèmes
d'alignement se concentrent (segments coupés en plein mot, décrochage de la DP,
mots de frontière).

**Vérification sur une session réelle** (2026-07-27 13:43→13:49, sourate 3) :
la quasi-totalité des corrections et des `ZERO FRAME` tombe dans le verset
**3:7 (50 mots)**, absent de l'asset. Conséquence : le log
`ETRANGLE PAR LA REFERENCE` (qui ne se déclenche que quand la référence change
le verdict) est sorti **0 fois sur toute la session**, alors qu'il sortait bien
sur la session précédente (13:00, sourate 2, versets courts). La référence
quran.com n'est donc pas « imparfaite » sur les cas durs : elle y est
**absente**.

Ajouter des récitateurs n'y change rien (déjà vérifié sur les 9 disponibles,
hors Mujawwad/Muallim) : ça affine la médiane des versets déjà couverts, ça
n'en couvre pas un seul de plus.

### Apport réel du timing dans la DP, mesuré sur deux sessions du 2026-07-27

Le garde-fou n'excuse un mot que si RIEN n'a été décodé dessus (`!hasSpeech`).
Le nombre de déclenchements du log est donc très supérieur au nombre de
verdicts réellement changés — il faut mesurer le second, pas le premier.

| | session 12:56 (sourate 2, versets courts, **couverts**) | session 13:43 (sourate 3, versets longs, **non couverts**) |
|---|---|---|
| `ZERO FRAME` | 112 | 123 (dont 33 sur passes finales : 26 reportés, 7 jugés sautés) |
| `ETRANGLE PAR LA REFERENCE` | 165 | **0** |
| mots non jugés (trou d'alignement) | 8 | 6 |
| … déjà couverts par `free` seul | 3 | 6 |
| **… épargnés uniquement grâce à `starved`** | **5 (3 mots distincts)** | **0** |

Les 3 mots épargnés grâce à la référence — `ٱلنَّاسِ` (free −0,38 / −0,54),
`بِٱللَّهِ` (−0,17 / −0,22), `ٱلْـَٔاخِرِ` (−0,18) — rataient tous le seuil de
confiance `free` (−0,15 en tolérant) de peu, et **tous les trois ont été jugés
`correct` sur une passe suivante** : le report était le bon verdict, la
référence a évité 3 faux négatifs. C'est un gain réel mais étroit.

Deux constats structurels en découlent :

1. **Sans la référence, beaucoup de mots n'ont aucun plancher utile** :
   `plancher_ctc = 1` frame sur **114 des 165** déclenchements (le tokenizer
   mappe souvent un mot entier sur un seul token). Le rapport
   plancher_ref/plancher_ctc est de x3 en médiane, jusqu'à x9. Le plancher CTC
   seul ne protège donc quasiment rien sur ces mots — c'est là que la
   référence a sa valeur.
2. **Mais elle est absente exactement là où ça casse** : dans la session
   sourate 3, **85 des 131 incidents (65 %) tombent dans le seul verset 3:7**
   (50 mots, absent de l'asset), et 82 % des incidents sont dans un verset non
   couvert. D'où l'apport de 0.

### La piste : déduire les durées de la récitation de référence de l'utilisateur

Idée utilisateur du 2026-07-27, à tester juste après (l'utilisateur prévoit
d'ajouter l'enregistrement de référence). Le principe : au lieu d'importer des
durées d'un référentiel externe au découpage incompatible, les **mesurer
nous-mêmes** par alignement forcé hors ligne sur une récitation de référence,
une fois, puis réutiliser les frontières de mots obtenues.

Ce que ça résout, point par point :

| Défaut de la source quran.com | Ce que la récitation de référence apporte |
|---|---|
| Découpage incompatible → 44 % des versets exclus, 99 % des versets longs | Le découpage est **le nôtre** (`splitExpectedWords`), par construction : couverture 100 % de ce qui est récité, aucune règle positionnelle à appliquer |
| Tempo d'un autre récitateur (marge de sécurité fixe x0,4 pour compenser) | Le tempo est **celui de l'utilisateur** → plancher juste, plus besoin de marge grossière |
| Pauses de waqf incluses dans la durée (mesuré : `هُمُ` à 3030 ms) | La pause est au bon endroit puisque c'est la même personne qui récite |
| Voix/timbre différents | Même voix → utile aussi pour l'empreinte vocale (§8ter) |
| Nécessite un asset embarqué de 156 Ko | Rien à embarquer : produit à la demande, sur le passage travaillé |

### Comment le mesurer (déjà faisable avec l'existant, rien à écrire côté modèle)

L'alignement forcé de bout en bout existe déjà côté natif :
`"alignFile"` dans `FastConformerCtcPlugin.kt` fait une inférence + un
alignement forcé one-shot sur un WAV complet, avec `isFinal=true`. Sur un
enregistrement de référence entier (pas de segmentation, pas de streaming,
donc **aucun** des problèmes de buffer), `ForcedAligner.Result` donne déjà
`wordFirstFrame`/`wordLastFrame` par mot — soit exactement les frontières
cherchées, en frames, dans la même unité que `refMinFrames` (80 ms/frame).
Il n'y a donc pas de nouvelle brique de modèle à construire : juste à stocker
le résultat et à le relire.

### Précisions apportées par l'utilisateur le 2026-07-27 (résolvent 2 des 4 points ci-dessous)

1. **« On a le texte, donc la lecture gère bien le timing. »** Exact, et c'est
   le point structurel : une lecture de référence passe par `alignFile` — une
   inférence sur l'audio COMPLET, `isFinal=true`, sans streaming ni
   segmentation. Aucun des défauts qui occupent la piste live (décrochage de la
   DP, mots de frontière, coupe à 12 s en plein mot) n'existe dans ce mode.
2. **« Si on enlève les blancs, les pauses ou silences entre mots. »** C'est
   déjà ce que le code compte : `ForcedAligner.wordFrames` n'incrémente que sur
   les états non-blank (`if (si % 2 == 0) continue`), donc c'est la durée
   ARTICULÉE, silences internes exclus. C'est structurellement supérieur à
   quran.com, dont les segments sont des bornes `[start_ms, end_ms]` INCLUANT
   le silence jusqu'au mot suivant — d'où le `هُمُ` à 3030 ms qui avait imposé
   le facteur ×0,4. Avec des frames articulées il n'y a plus rien à compenser.
   La ligne de log `DUREES` (commit 3f75b94) sort exactement cette grandeur en
   `f=`.
3. **« Le user ne va pas sauter, en plus on a la validation. »** Ces deux
   arguments ferment le point 1 ci-dessous : une lecture attentive ne saute pas
   de mot (donc pas de zéro-frame parasite à interpréter), et le GOP filtre le
   reste — on ne retient la durée que des mots jugés `correct`.

**Ce que ça ne couvre pas, et la conséquence de conception.** Une lecture de
référence est plus LENTE qu'une récitation de mémoire à vitesse normale : un
plancher tiré de la lecture serait trop haut pour la récitation réelle, donc
excuserait trop (effet borné, puisque le garde-fou n'excuse que si rien n'est
entendu, mais réel). Et une seule lecture = un seul échantillon, sans la
robustesse que donnaient les 9 récitateurs.

⇒ **Un plancher est une borne INFÉRIEURE : la bonne statistique n'est donc pas
la médiane mais le MINIMUM.** Le `médiane × 0,4` actuel est un bricolage faute
de mieux ; avec deux ou trois lectures de l'utilisateur, le minimum observé par
mot EST directement la grandeur cherchée — plus aucun facteur arbitraire à
régler. C'est le rapport « durée en lecture / durée en récitation » que la
ligne `DUREES` doit établir.

Points à trancher avant de coder (non résolus) :
1. ~~**Que faire si la récitation de référence est elle-même fautive ?**~~
   Tranché ci-dessus (validation GOP en filtre). Le garde-fou reste : n'accepter
   les durées que des mots jugés `correct`, retomber sur le plancher CTC seul
   pour les autres.
2. **Quelle marge appliquer** : reformulé ci-dessus — prendre le MINIMUM sur
   plusieurs lectures plutôt qu'une médiane amputée d'un facteur. Reste à
   mesurer le rapport lecture/récitation avant de fixer quoi que ce soit.
3. **Où stocker** : contrainte utilisateur déjà posée (2026-07-27) —
   enregistrement de référence plafonné à **15-30 min**, tout en local.
4. **Repli** : garder l'asset quran.com comme source de second rang pour les
   passages sans récitation de référence (il couvre bien les versets courts,
   98 % sous 5 mots), plutôt que de le retirer.

### Décision

Piste **validée sur le principe**, non implémentée. À reprendre quand
l'enregistrement de référence existera dans l'app. L'asset quran.com reste en
place en attendant : il ne nuit pas (il ne sert qu'à excuser, jamais à
condamner) et il couvre correctement les sourates courtes.
