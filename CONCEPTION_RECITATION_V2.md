# Conception de la chaîne de récitation v2 — proposition, AVANT toute ligne de code

Écrit le 2026-07-30 en réponse à `PROMPT_REECRITURE_RECITATION.md`.
**Aucun code n'a été écrit.** Ce document est la proposition à arbitrer.

Branche créée (pointeur seul, aucun fichier touché, aucun `checkout`) :
`recitation-v2`, basée sur `e735f99` — dernier commit dont la chaîne a une
mesure device (v24, médiane 11,78 %). Le premier commit de la branche
**supprimera** `BufferedTranscriber.kt`, `ForcedAligner.kt` et le chemin de
jugement de `recitation_provider.dart` : on ne refactore rien, on ne se conforme
à rien. L'ancien code reste atteignable par `git show` (règle projet : aucune
piste éliminée tant que le retour en arrière est possible).

Consigne utilisateur du jour : *« l'idée n'est pas de lire ce qui était déjà
fait sinon tu vas reproduire les mêmes problèmes »*. Le graphe n'a donc pas
servi de modèle à copier — il a servi de **liste d'interdits** : 14 pistes
mortes, 15 pièges, 10 symptômes avec la couche où ils naissent. La conception
ci-dessous est dérivée du besoin, puis confrontée à cette liste.

---

## 1. Ce que j'ai tiré du graphe

Lecture **exhaustive** des nœuds à préfixe (pas un échantillonnage par requête :
les 14 `[MORT]`, 15 `[PIEGE]`, 10 `[SYMPTOME]`, 10 `[EN ATTENTE]`, 7 `[REGLE]`,
6 `couche_*` ont été lus intégralement avec leur `rationale`), plus les
`rationale` chiffrés des commits de la chaîne.

### 1.1 Les pistes mortes que cette conception évite — et par quelle propriété

| `[MORT]` | mesure qui la tue | comment la v2 ne peut pas y retomber |
|---|---|---|
| Streaming cache-aware | gel après 35 s, 5 politiques de cache rejetées ; cause **dans le modèle** (clips ≤ 20 s, session non bornée) | v2 est **sans état** : chaque fenêtre est une fonction pure de son audio. Aucun cache à vider, donc aucune politique à deviner |
| Fenêtre glissante naïve | WER > 100 % **par duplication de texte** | v2 ne **coud aucun texte**. Le texte attendu est connu ; on ne construit jamais une transcription cumulée. La duplication est un défaut de couture, pas d'alignement |
| Couper à chaque pause | WER 103,5 % | v2 ne coupe **jamais**. Il n'y a plus de segment |
| Désactiver le portier RMS | 70,2 % contre 22,8 % | le portier reste. Il change seulement de nature : il **marque** au lieu de **détruire** (§4.4) |
| Stats de normalisation FIXES | ne corrige rien, +1,28 pt de WER | non repris. Reste bloqué sur un réentraînement (`P2.1`) |
| Garde de frontière `conserve=0` | corrélation r = 0,67 **réfutée par l'intervention** | sans objet : plus de frontière de segment, donc plus de `conserve` |
| Resync arbitré par score sur aperçu | 8,16 % → 13,40 %, mots 46-54 sautés | v2 ne déplace pas une ancre en abandonnant des mots : déplacer l'estimation de position et abandonner un mot sont **deux opérations distinctes** (§2, couche D/F) |
| Relâchement de la règle de proportion | palliatif : demi-mot validé | interdit par construction : le jugement ne voit que des mots **entièrement intérieurs** à une fenêtre (§4.2) |
| Sonde de 4 lettres | 9,18 % → 17,89 % | non repris |
| Rayon de coupe 2 s | la variance revient | sans objet (plus de coupe) |
| Validation groupée par GOP | aucun gain | non repris |
| Rescoring de variantes **harakat** | 49,6 % = pile ou face | **jamais** de verdict harakat verrouillé sur ce signal (§4.3) |
| Anneau 30 → 120 s comme cause | décrochage inchangé | l'anneau brut est conservé pour la **preuve**, jamais présenté comme un correctif |
| Entraînement on-device | échec documenté | hors périmètre |

### 1.2 Les pistes `[EN ATTENTE]` reprises, avec leur commit

| piste | commit | ce que la v2 en fait |
|---|---|---|
| **Mel incrémental + FFT itérative** | `P0.2` | **repris tel quel**. C'est ce qui rend le coût de la fenêtre constant : les colonnes log-mel ne dépendent pas du reste du buffer, seule la normalisation est globale |
| **Resync comparant du TEXTE** (Maryam 15,46 → 9,18 %) | `4606d64` | **repris** : la localisation compare du texte, jamais des ids de tokens |
| **Contexte droit AUSSI à la DP** (jamais mesuré sur device) | `6ae0884` | **repris et généralisé** : plus aucune troncature de logprobs. Un mot est jugé avec son contexte des deux côtés, ou n'est pas jugé |
| **Buffer de secours DÉCALÉ** (idée utilisateur, jamais testée) | `4a91ff3` | **repris et généralisé** : au lieu d'un second buffer décalé d'une demi-fenêtre, **toutes** les fenêtres se recouvrent d'un pas. Tout mot coupé dans l'une est entier dans une autre |
| **Rescoring de variantes LETTRES** (80,8 %, marge +3,80) | `variant_rescoring_eval.py` | **repris, mais comme changement SÉPARÉ**, après mesure de la base (règle : un seul changement par version) |
| `MAX_SILENCE_SAMPLES` 0,3 → 0,9 s | `6d07754` | paramètre à balayer hors device dans le banc de fenêtre |
| **Couper à une fin de mot connue** (la piste la plus étayée) | `6d07754` | **rendue sans objet** : il n'y a plus de coupe. Documenté comme tel, pas supprimé |
| Borne droite de coupe, secours étendu amont | `f2d61bc`, `6d07754` | sans objet (plus de coupe, plus de secours) |
| VAD Silero | `P1.4` | **pas dans la v2 de base**. Changement séparé, après mesure |

### 1.3 Les trois faits du graphe qui commandent la conception

1. **Le verdict est rendu au rythme de la transcription alors que rien ne
   l'y oblige** (§1.6, 12 faux positifs sur 12, modèle hors de cause). Deux
   exigences opposées partagent une même variable — aucun seuil ne les
   départagera.
2. **Le « final » de l'app est un alignement neuf sur un buffer neuf, qui
   écrase l'accord des aperçus** (§1.7, Phase 4). L'état de l'art fait
   l'inverse : le FINAL est émis **quand les hypothèses successives convergent**
   (*stable-prefix rule*). L'app fait exactement le contraire de la recette
   canonique.
3. **825 s d'audio détruites, 635 mots que les aperçus avaient déjà placés
   dedans** (`audio_detruit.py`, 75 sessions). L'information existait, elle a
   été détruite deux fois : par le recalcul, puis par la purge.

Ces trois faits disent la même chose : **le défaut n'est pas dans la recherche
de la position, il est dans la façon de valider.** C'est le principe organisateur
de la v2.

---

## 2. Architecture proposée — huit couches, et le contrat exact entre chacune

Le graphe désigne `runAlignment` (7 réécritures) et `OVERLAP_SECONDS`
(6 réécritures) comme les points où le code n'a **jamais** convergé, et les
nomme *« la frontière mal découpée entre alignement, secours et gestion
d'ancre »*. La v2 supprime cette frontière : il n'y a plus ni secours ni ancre
mutable, et l'alignement devient une fonction pure.

```
A Capture ──> B Fenêtres ──> C Front acoustique ──> D Localisation
                                                          │
                             G Décision <── F Preuves <── E Alignement
                                  │
                                  └──> H Affichage
```

### Les cinq invariants de contrat (ce qui manquait, et ce qui a produit les régressions en cascade)

1. **Une seule horloge.** Tout objet porte des **indices d'échantillon absolus**
   depuis le début de session. Aucune couche ne manipule un offset relatif à
   un buffer. → tue `[PIEGE] deux échelles de temps` et le bug
   « fenêtre de secours décalée de 3 s » (`origine absolue corrigée`).
2. **Pureté de C, D, E.** Même entrée ⇒ même sortie, aucun état conservé entre
   appels. → le banc hors device **est** l'app (§5), et le gel cache-aware
   ne peut pas revenir.
3. **Monotonie de la décision.** Seule G verrouille. Un verdict verrouillé ne
   change plus jamais ; un verdict provisoire peut changer. Aucune autre couche
   n'a le droit de figer quoi que ce soit.
4. **Non-destruction.** Aucune couche n'efface d'audio ni d'observation. A est
   la vérité terrain, écrite sur disque en continu.
5. **Pas de défaut par absence.** Absence de preuve ⇒ statut `inconnu`, jamais
   une couleur. Un mot non observé n'est ni vert ni rouge.

### A — Capture

**Produit** : `RawStream` — PCM 16 kHz mono, append-only, écrit sur disque au
fil de l'eau.
**Contrat** : contigu, jamais modifié, jamais purgé pendant la session. L'indice
absolu d'un échantillon est **la** référence de temps de toute la chaîne.
**Ce que ça rend impossible** : `[PIEGE] 35 % de l'audio n'existait dans aucun
fichier`. La preuve acoustique de n'importe quel verdict est réextractible
après coup.

### B — Constructeur de fenêtres

**Produit** : `Window { id, startAbs, endAbs, samples[W], silenceMap }`, émise
tous les `hop`.
**Contrat** :
- durée **constante** `W` (toutes les fenêtres ont exactement la même longueur) ;
- pas d'émission constant `hop < W` (les fenêtres se recouvrent) ;
- `silenceMap` : bijection explicite entre l'horloge de travail (fenêtre) et
  l'horloge brute (A) quand du silence est compressé (§4.4). Rien n'est
  irréversiblement perdu, la correspondance est calculable dans les deux sens.

**Ce que ça rend impossible** : la coupe en plein mot (47,4 % des coupes
aujourd'hui), `conserve=0`, le mot de frontière qui n'existe entier nulle part,
la dérive de normalisation liée à la longueur, le retard qui dépend de la
longueur du segment.

### C — Front acoustique

**Produit** : `logprobs[T × V]` (T = W/80 ms).
**Contrat** : fonction **pure** de la fenêtre. Log-mel calculé par colonne et
mis en cache (les colonnes ne dépendent pas du reste du buffer), normalisation
`per_feature` recalculée sur **exactement W** — donc toujours sur la même
durée. Modèle : causal v1, export `audio_signal` (mel), **jamais** `raw_audio` ;
vérification `onnxruntime` obligatoire avant tout déploiement.

### D — Localisation

**Produit** : `Band { i0, i1, confiance }` — quelle tranche du texte attendu
cette fenêtre couvre.
**Contrat** :
- entrée : `logprobs`, texte attendu, `dernierMotVerrouillé` ;
- appariement du **décodage libre au texte attendu**, comparaison sur le
  **texte** (piste mesurée `4606d64`), recherche **dans les deux sens** autour
  de la dernière position connue, bornée ;
- **aucun effet de bord** : D ne déplace aucun état global, ne verrouille rien,
  n'abandonne aucun mot. Elle peut répondre `inconnu` → la fenêtre ne produit
  alors aucun jugement.

**Ce que ça rend impossible** : `[PIEGE] findResyncOffset ne cherche qu'en
avant` — un récitateur qui répète devient suivi par construction. Et la
régression v22 (`8,16 → 13,40 %`) ne peut pas se reproduire : elle venait du
**couplage** « déplacer l'ancre » ⇒ « les mots derrière sont perdus ». Ici les
deux sont décorrélés : les mots dépassés restent dans F, éligibles à n'importe
quelle fenêtre ultérieure, et leur audio est toujours dans A.

### E — Alignement

**Produit** : pour chaque mot de la bande :
`{ index, premiereFrame, derniereFrame, forced, free, gop, entendu, interieur }`.
**Contrat** : fonction **pure** (DP CTC Viterbi, la méthode standard —
`torchaudio.functional.forced_align` fait la même chose). Ne juge pas, ne
verrouille pas, ne connaît aucun seuil.
`interieur = true` ⇔ les frames du mot ne touchent **ni** le bord gauche **ni**
le bord droit de la fenêtre, marges comprises (marge droite ≥ 1,04 s = le
lookahead du modèle causal, 13 × 8 × 10 ms).
Les mots **déjà verrouillés** en tête de fenêtre sont donnés à l'encodeur comme
contexte mais **exclus de la bande** — règle mesurée le 2026-07-27 : les
laisser entrer fait re-accrocher la DP dessus.

### F — Registre de preuves

**Produit** : par index de mot attendu, la **liste** des observations reçues,
chacune avec l'id de sa fenêtre.
**Contrat** : append-only. Aucune observation n'est jamais écrasée ni supprimée.
C'est le remède direct au fait n°3 du §1.3 (l'information existait et a été
détruite).

### G — Décision

**Produit** : par mot, `inconnu | provisoire(couleur) | définitif(couleur) | omis`.
**Contrat** : **seul endroit du système où vit un seuil**. Règle :
- une observation ne compte que si `interieur == true` (sinon elle est
  enregistrée mais ne vote pas) ;
- **provisoire** dès la 1ʳᵉ observation intérieure ;
- **définitif** quand `K = 2` observations intérieures issues de **fenêtres
  distinctes** donnent le **même** verdict (*stable-prefix rule*) ;
- **omis** (statut distinct, jamais rouge) quand ≥ N mots postérieurs sont
  définitifs et qu'aucune fenêtre n'a jamais contenu ce mot — preuve positive
  que le récitateur est passé outre, pas une absence de donnée ;
- jamais de verdict sur absence de donnée, jamais de verdict par défaut.

### H — Affichage

**Contrat** : distingue visuellement provisoire et définitif. Périmètre IHM,
hors de cette proposition sauf pour ce point (effet de bord n°1, §6).

---

## 3. Comment la v2 traite le constat n°1 (normalisation / segmentation)

**Le constat** : `per_feature` recalcule mean/std sur tout le buffer. Elle
interdit l'incrémental (d'où « tout re-transcrire toutes les 1,5 s ») et dérive
sur les longs buffers (d'où le gel et la borne 12 s). *Le gel est un
contournement, jamais une fonctionnalité voulue.*

**La décision de conception** : la normalisation ne dérive pas parce que le
buffer est long — elle dérive parce que **sa longueur varie**. La v2 rend cette
longueur **constante** : chaque inférence porte sur exactement `W` secondes,
toujours. Les statistiques de normalisation sont alors tirées de la même durée
à chaque passe, dans le régime des clips d'entraînement.

Conséquences en chaîne, toutes des **suppressions** :

| aujourd'hui | v2 |
|---|---|
| gel sur pause 450 ms, borne dure 12 s | **supprimés** — plus de gel |
| `findCutOffset`, `CUT_SEARCH_RADIUS_SECONDS`, `targetSeconds` | **supprimés** — plus de coupe |
| `MIN_FRAMES_FOR_JUDGMENT`, `deferredOnceIndex`, tolérance aux fragments, tolérance au bleed préfixe, filet décodage-libre | **supprimés** — un mot non intérieur n'est simplement pas jugé sur cette fenêtre |
| `RescueBuffer`, `fenetreDeRecherche`, `cibleAvecVoisins`, `secoursMeilleur` | **supprimés** — le recouvrement des fenêtres fait le travail du secours, en amont |
| ancre mutable, `findResyncOffset`, `RESYNC_ACTIF`, rattrapage borné | **supprimés** — la position est ré-estimée à chaque fenêtre, jamais incrémentée depuis l'historique |

C'est la réponse directe au constat n°2 du prompt : *« si tu réintroduis une de
ces rustines, c'est que la segmentation te pose le même problème »*. La v2 n'en
réintroduit aucune — non par discipline, mais parce que le problème qu'elles
compensaient (un mot peut être **définitivement** coupé) n'existe plus : la
fenêtre continue de glisser, et tout mot finit intérieur à au moins une fenêtre.

**Ce que la v2 ne fait PAS** : les stats de normalisation fixes (`[MORT]`,
+1,28 pt) restent hors de portée sans réentraînement. La v2 ne les utilise pas.

**Garantie d'intériorité, chiffrée.** Un mot de durée `d` est intérieur à au
moins une fenêtre dès que `hop ≤ W − d − mG − mD`, avec `mD ≥ 1,04 s`
(lookahead causal) et `mG ≈ 0,2 s`. Avec `W = 6 s`, `d ≤ 1,5 s` : `hop ≤ 3,2 s`.
Le point de départ proposé est `W = 6 s`, `hop = 1,5 s` — soit **4 fenêtres**
qui contiennent chaque mot, dont ≥ 2 où il est intérieur. `W` et `hop` sont les
deux seuls paramètres de segmentation restants, et ils sont **fixés par mesure**
(§5, banc 1), pas par réglage empirique en cours de route.

---

## 4. Quand un mot est jugé, quand son verdict devient définitif

### 4.1 Le calendrier, chiffré (W = 6 s, hop = 1,5 s)

Soit `t` l'instant où le récitateur finit de prononcer le mot.

| étape | délai après `t` |
|---|---|
| assez d'audio postérieur pour que le modèle causal ait son contexte droit | + 1,04 s |
| attente de la prochaine fenêtre sur la grille | + 0 à 1,5 s |
| inférence (mesuré : 413 ms pour 5,7 s de buffer) | + ~0,4 s |
| **⇒ verdict PROVISOIRE affiché** | **+ 1,4 à 2,9 s** |
| 2ᵉ observation intérieure (fenêtre suivante) | + 1,5 s |
| **⇒ verdict DÉFINITIF** | **+ 2,9 à 4,4 s** |

**Ce délai est constant.** Il ne dépend ni de la longueur d'un segment, ni du
rythme des pauses du récitateur, ni de la durée déjà récitée. C'est la
contrainte n°5 du prompt tenue comme **propriété de conception** : le nombre
ci-dessus se dérive de `W`, `hop` et du lookahead, il ne se constate pas après
coup.

Référence : la chaîne actuelle affiche un aperçu à ~1,5 s mais **mesure**
`VALIDATION retard=10435ms puis 8463ms` — 8 à 10 s, et croissant avec le
segment. Le pire cas de la v2 (4,4 s) est meilleur que le cas courant
d'aujourd'hui ; son meilleur cas (2,9 s) est moins bon que l'aperçu actuel
(1,5 s) — **c'est l'arbitrage n°1 du §6**.

### 4.2 Ce qui ne peut plus arriver

- Un mot jugé sur un audio incomplet (`[PIEGE] verrou sur aperçu`) : une
  observation ne vote que si le mot est **intérieur**, donc entièrement présent
  avec son contexte des deux côtés.
- Un demi-mot validé (`[MORT] relâchement de proportion`) : idem — un fragment
  touche forcément un bord.
- Un rouge définitif sur `entendu=""` : `entendu` vide sur un mot intérieur avec
  `free` normal est le signe d'une **mauvaise position** (`[PIEGE] gop vs free`),
  pas d'une faute. D consigne alors `inconnu`, et la fenêtre suivante retranche.

### 4.3 Ce que la v2 ne prétend PAS corriger

`gop = forced − free` reste **relatif** (`[PIEGE] gop relatif` : `صِرَٰطَ` /
`سَرَٰطَ` à gop = −0,35 → vert). La v2 supprime les faux positifs **nés du
découpage** — elle ne fournit pas le signal absolu manquant. Celui-ci est le
rescoring de variantes sur les **lettres** (80,8 %, marge +3,80), qui viendra
comme **version suivante et changement unique**, jamais mélangé à la base. Et
jamais sur les harakat (49,6 % = hasard).

Non traité non plus, et qui met un plancher au taux atteignable : `[PIEGE] 33 %
des mots passent par le repli glouton de CtcTokenizer` (chantier distinct : GOP
invariant au découpage BPE), et `[PIEGE] waqf` (à absorber dans le contrat de D,
pas par réentraînement).

### 4.4 Le portier de silence : marquer au lieu de détruire

Le désactiver est `[MORT]` (70,2 % contre 22,8 %) ; lui rendre le silence n'aide
pas (−2,8 pt **en faveur** du portier, mesuré le 2026-07-28). Il reste donc.
Ce qui change : il ne **jette** plus rien. Le silence excédentaire est compressé
dans la fenêtre de travail, et B publie la table de correspondance entre les
deux horloges. C'est la piste C du 2026-07-28 (écrite puis retirée avant mesure,
conservée à la demande de l'utilisateur). Contrainte n°4 du prompt tenue sans
payer le coût WER.

---

## 5. Comment je mesure, avant tout déploiement device

### 5.0 Le préalable de méthode : le banc doit être le code, pas sa copie

Le graphe porte deux prédictions hors device **confiantes et fausses** en une
seule journée (`ancre_vs_realite`, `arbitrer_resync`), et un piège répété deux
jours de suite : *« le banc mesurait mon découpage, pas l'app »*. Cause commune :
**chaque banc était une ré-implémentation Python de la logique Kotlin**.

⇒ En v2, les couches C, D, E, F, G sont des fonctions **pures**, donc les bancs
sont des **tests JVM qui appellent le code de l'app** sur de vrais WAV. Aucune
politique de fenêtrage n'est réécrite en Python. C'est ce que la pureté du
contrat (invariant 2) achète.

### 5.1 Banc 1 — choix de `W` et `hop` (avant d'écrire D, E, F, G)

Métrique : **couverture intérieure** = % de mots attendus ayant ≥ 1 fenêtre où
ils sont intérieurs **et** correctement lus par le décodage libre.
Balayage `W ∈ {4, 6, 8, 10, 12} s` × `hop ∈ {1,0 ; 1,5 ; 2,0} s`, grille fixe
(jamais une fenêtre choisie autour du mot — c'est l'erreur du 2026-07-29), sur
les WAV device déjà capturés.
Critère d'arrêt : le couple retenu est celui qui maximise la couverture
intérieure à coût d'inférence tenable, pas celui qui minimise un WER.

Ce banc répond aussi à la question ouverte du graphe : `12 s → عَظِيمٌ PERDU`
alors que `3 s` le sort, mais des tranches arbitraires de 5 s donnent de la
bouillie. La métrique d'intériorité départage ces deux observations
contradictoires.

### 5.2 Banc 2 — calendrier des verdicts

Sur une session complète : pour chaque mot, instant de 1ʳᵉ observation
intérieure, instant de verrouillage, verdict. Vérifie que les chiffres du §4.1
sont tenus **et** qu'ils ne dépendent pas de la position dans la session.
Dénominateur : **ancre max**, pas les mots jugés (sinon un mot jamais observé
sort du calcul — erreur déjà commise).

### 5.3 Banc 3 — le récitateur qui répète

Le banc actuel rejoue un audio linéaire : il ne peut **structurellement pas**
produire ce cas (`[PIEGE] resync avant seulement`). Construction : découper un
WAV réel et recoller un passage deux fois. Sans ce banc, la recherche
bidirectionnelle de D n'est pas mesurable — donc pas justifiable.

### 5.4 Banc 4 — même WAV, deux binaires

Le seul banc que le graphe déclare fiable. Comparaison v24 (référence mesurée,
médiane 11,78 %) contre v2, même WAV rejoué au bit près, sur les deux binaires.
C'est le **portail avant device**.

### 5.5 Ordre, et ce qui est mesuré à chaque étape

1. C seul → bit-exactitude du mel incrémental vs calcul à froid, et
   `[i.name for i in ort.InferenceSession(...).get_inputs()] == ['audio_signal', ...]`.
2. B + C → banc 1, fige `W` et `hop`.
3. D → banc 3 (répétition) + taux de bande correcte sur session réelle.
4. E + F + G → banc 2.
5. tout → banc 4, puis device.

Un seul changement par version, à chaque étape. Le skill `superviseur-recette`
passe derrière chaque modification, sans attendre qu'on le demande.

---

## 6. Effets de bord identifiés — leur existence interdit l'implémentation directe

Ils sont listés ici pour être **arbitrés**, pas assumés.

1. **Le verdict définitif est plus lent qu'aujourd'hui dans le meilleur cas**
   (2,9–4,4 s contre un aperçu à 1,5 s), et **les couleurs bougent avant de se
   figer** (provisoire → définitif). C'est un changement de ressenti visible à
   l'écran. Option : teinte plus claire tant que provisoire. **Décision
   utilisateur.**
2. **Coût d'inférence en régime permanent** : ~0,4 s toutes les 1,5 s ≈ **27 %
   d'un cœur en continu**, contre un régime aujourd'hui intermittent. Batterie
   et thermique sur une longue sourate. Mesurable avant device, mais l'arbitrage
   « fluidité contre autonomie » est utilisateur.
3. **Toute la chaîne de diagnostic devient caduque.** `segment FIGE`,
   `conserve=`, `ancre`, `secours`, `RESYNC` disparaissent des logs. Les scripts
   `analyze_device_log.py`, `ancre_vs_realite.py`, `audio_detruit.py`,
   `inventaire_non_verts.py`, `verifier_erreurs.py`, `recette_2tel.sh` et le
   skill `analyse-session-recitation` reposent dessus. **Il faut réécrire la
   journalisation et les bancs en même temps que la chaîne** — sinon on est
   aveugle pendant toute la mesure. C'est un coût réel, à budgéter explicitement.
4. **Le mécanisme de secours disparaît** alors qu'il tourne en production. Sa
   mesure (33 tentatives : 16 OK, **7 faux positifs**, 6 ratés) suggère un gain
   à le retirer, mais c'est une suppression de fonctionnalité vivante. **À
   valider.**
5. **La recherche bidirectionnelle peut s'accrocher à la mauvaise occurrence**
   d'un passage quasi identique (refrains, versets jumeaux — fréquents dans le
   Coran). Elle rend possible le suivi d'un récitateur qui répète, mais crée une
   classe d'erreur qui n'existait pas. Atténuation prévue : bande bornée +
   préférence à la continuité à égalité. **À arbitrer, avec le banc 3 comme
   juge.**
6. **Le statut `omis` est nouveau** et demande un rendu IHM (ni vert, ni orange,
   ni rouge). Sans lui, un mot sauté redevient invisible — le défaut exact de
   v22. Périmètre IHM touché malgré la consigne « pas l'IHM ».
7. **La v2 de base ne réduira pas les faux positifs d'origine phonétique**
   (§4.3). Attente à fixer maintenant : le gain visé est la disparition des faux
   positifs **de découpage** (mesurés 12/12 sur une session professionnelle),
   pas un taux sous 1 %.
8. **Le contrat `StreamingModelConfig` du prompt décrit le chemin cache-aware**
   (121 / 112 / 14, caches `cache_last_channel`/`cache_last_time`) — chemin
   `[MORT]` mesuré (gel après 35 s, 5 politiques rejetées, cause dans le
   modèle). Je lis la contrainte n°1 comme **« garder le checkpoint causal v1,
   ne pas changer de modèle »**, et je propose de l'alimenter **sans état**, en
   fenêtres. **Si la contrainte signifiait « rétablir le chemin cache-aware », la
   conception ci-dessus tombe** — c'est le premier point à trancher.

---

---

## Journal — ce que le banc a trouvé, et que la conception n'avait pas vu

Écrit au fil de l'implémentation (2026-07-30). **Aucun de ces trois défauts
n'avait été anticipé** ; tous ont été trouvés par un test JVM en quelques
secondes, avant tout déploiement. C'est le retour sur investissement direct de
l'invariant n°2 (pureté des couches ⇒ le banc appelle le code de l'app).

| # | ce que le banc a montré | où le défaut NAÎT | traitement |
|---|---|---|---|
| 1 | le **tout premier mot** d'une session n'était jamais intérieur, donc jamais verrouillé, donc déclaré `Omis` — alors qu'il était parfaitement aligné (gop 0,00 sur trois fenêtres) | couche E : la marge gauche écarte une **troncature**, pas un **bord**. Au début de session il n'y a rien à tronquer | `bordGaucheEstDebutDeSession` : la marge gauche ne s'applique pas au vrai début de l'audio |
| 2 | les **2-3 derniers mots** n'obtenaient jamais leur 2ᵉ preuve | couche B : la grille de fenêtres est pilotée par la **croissance** du flux de travail, et le portier gelait ce flux 0,3 s après le dernier mot | le silence conservé n'est pas un réglage : c'est `lookahead + pas` = **2,6 s**, dérivé. Plus `terminer()`, qui émet une dernière fenêtre hors grille quand le récitateur se tait |
| 3 | un mot que le récitateur **saute** ressortait `Definitif(ROUGE)`, avec `gop = −11,99` et **`free = −0,01`** | couche E : la DP est obligée de placer tous les mots qu'on lui donne. Elle avait volé 3 frames au voisin | `sansCreneau` : on compare la plage alignée du mot à l'audio laissé **libre** par ses voisins attestés au décodage libre. Géométrie, pas seuil |

Le défaut n°3 est le plus grave des trois : c'est le socle n°1 (« dire vrai »)
qui tombait — un rouge définitif sur un audio qui ne contient pas le mot. Il est
aussi la démonstration exacte du `[PIEGE] gop_vs_free` du graphe : *un gop
effondré avec un free proche de 0 signifie mauvaise **position**, pas mauvaise
prononciation*. La v1 traitait ce cas par des rustines de jugement ; ici il est
traité par la géométrie des créneaux, en amont du jugement.

Un quatrième défaut a été trouvé **dans le banc lui-même** : relire le registre
de preuves avec un `Decideur` neuf ne reproduit pas ce qu'a vu l'utilisateur (la
couche G est *stateful* par contrat — un définitif ne bouge plus). Un mot
verrouillé VERT ressortait « rouge provisoire » à la relecture. Les tests lisent
désormais `ChaineRecitation.statuts`, jamais un décideur rejoué.

### État de la mesure

| niveau du socle | mesuré ? | comment |
|---|---|---|
| 1 — dire vrai | **oui**, hors device | 21 tests JVM : pas de verdict sans preuve intérieure, monotonie, demi-mot jamais vert, mot sauté jamais rouge |
| 2 — suivre | **oui**, hors device | ancre max, ≥ 2 fenêtres intérieures par mot, récitateur qui répète, audio jamais détruit |
| 3 — streaming | **partiellement** | le calendrier de verrouillage est vérifié **constant** ; le coût d'inférence réel reste **non mesuré** (il faut le device) |
| 4 — taux | **non** | rien n'a encore tourné sur audio réel ni sur téléphone |

---

## Ce que j'attends comme arbitrage

| # | question | ma recommandation |
|---|---|---|
| 1 | contrainte modèle = checkpoint causal, ou chemin cache-aware ? (effet 8) | **checkpoint causal, alimentation sans état** |
| 2 | délai définitif 2,9–4,4 s constant, contre aperçu 1,5 s instable (effet 1) | **oui**, c'est l'échange qui supprime la classe de défauts |
| 3 | budgéter la réécriture des logs et bancs en même temps (effet 3) | **oui**, sinon la mesure est impossible |
| 4 | suppression du secours (effet 4) et statut `omis` (effet 6) | **oui** aux deux |
| 5 | recherche bidirectionnelle dès la base, ou après ? (effet 5) | **dès la base**, mais activée seulement après le banc 3 |
| 6 | rescoring lettres : version suivante, jamais mélangé (§4.3) | **version suivante** |

Rien ne sera codé avant ces réponses.
