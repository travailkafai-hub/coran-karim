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
