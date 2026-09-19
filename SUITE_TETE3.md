# Suite — tête 3 / écart canonique (état au 2026-08-01)

Branche : `tete3-ecart-canonique`. Point d'entrée court : ce fichier.
Le détail vit dans les messages de commit `4ecb5fb`, `df67e02`, `644d138`
(`git log -3 644d138`) — ils sont écrits pour être relus, ne pas les résumer
de mémoire.

---

## 0. MISE À JOUR (même journée, quelques heures plus tard) — l'encodeur a bougé DEUX FOIS DE PLUS

Tout ce qui suit (§1-§9) décrit l'état sur `fastconformer-causal-v4-phrases`.
**Ce n'est plus l'encodeur le plus avancé.** Deux runs supplémentaires,
non couverts par ce fichier avant cette section :

1. **Encodeur contrastif** (`fastconformer-contrastif-v1`, piste 10 —
   demande utilisateur explicite). Loss contrastive sur le corpus de paires
   `tts_phrases_concat` (audio correct vs audio fautif, même texte cible).
   Mesuré sur les 189 phrases tenues à l'écart, 2 % de collatéral :
   **détection règle C : 25 % → 53 %** ; **biais canonique (médiane gopC sur
   mot fauté) : +0,109 → −0,105**, signe inversé. C'est la première mesure de
   la nuit qui bouge le biais canonique lui-même, pas seulement un taux en
   aval.
2. **Fine-tune sur données vérifiées** (`fastconformer-verifie-v1`), base =
   contrastif, 6 epochs sur 131 723 lignes contrôlées (clips longs +
   fautes TTS déjà auditées à 93,9 %). `val_wer_ctc` = 0,180-0,182, stable
   par rapport au point de départ causal (0,182) — métrique **interne**,
   pas une preuve.

**Conséquence directe pour ce chantier** : la tête 3 (`tete3.json`) et la tête
tajwid sont calibrées sur `v4-phrases`, qui n'est plus l'encodeur candidat —
il l'est deux générations en arrière. Les recalibrer maintenant sur
`v4-phrases` serait du travail jeté si `verifie-v1` devient la référence
(ce qui est probable : gain de détection mesuré, WER stable). **Revoir §6 et
§7 ci-dessous, qui datent d'avant ce constat.**

**En parallèle, fiabilisation massive du dataset** (goal utilisateur
« fiabilisation des dataset des 3 têtes et encodeur ») :
- Corpus de base nettoyé, décodage individuel de chaque clip contre son
  texte : **52 081/59 232 clips gardés (87,9 %)**, WER médian 5,0 %.
- Corpus court 3-8 s, 10 récitateurs à horodatage API réel (quran.com,
  vérifié à quelques dizaines/centaines de ms près contre l'audio local) +
  filtre par décodage : **11 952 fragments gardés (52 %)**, 30 % réellement
  tronqués en plein mot (mot exclu de la cible texte).
- Corpus court, 44 récitateurs restants, alignement WhisperX
  (`jonatasgrosman/wav2vec2-large-xlsr-53-arabic`) + même filtre : en cours.
- ⚠️ **Correction d'une fausse piste** : une liste de « 9 récitateurs
  contaminés » construite tôt dans la nuit était fausse — le problème
  (`_assajda`) avait déjà été diagnostiqué et réparé le 2026-07-04
  (`realign_assajda.py`, cf. `BENCHMARK_RESULTS.md`). Vérifié sans impact
  réel sur les pipelines ci-dessus (aucun ne référençait cette liste).
  Détail : `benchmark/recitateurs_exclus.py`.

**Ce qui reste bloquant, inchangé** : téléphones débranchés cette nuit,
**aucune recette device n'a pu tourner sur `contrastif-v1` ni `verifie-v1`**.
Rien n'est déployé, le modèle sur le téléphone n'a pas bougé.

---

## 1. En cinq lignes

L'app juge la récitation avec **une seule tête CTC**. Pour détecter l'écart au
texte canonique on a longtemps utilisé une **règle écrite à la main** sur les
logprobs (« règle C »). On a mesuré qu'elle plafonne, et qu'une **tête
entraînée sur l'état de l'encodeur** (512 dim) fait mieux — mais **seulement
sur un encodeur réentraîné**, pas sur celui déployé. La brique de lecture est
posée et prouvée sans régression ; **la tête n'est pas branchée**, et le
changement d'encodeur n'est pas validé.

---

## 2. Les « 3 têtes » — plan, pas réalité

| Tête | État réel |
|---|---|
| CTC (transcription) | **La seule qui existe** dans le ONNX déployé |
| Tajwid (règles) | Vit dans un **autre run**, **incompatible** depuis que l'encodeur a bougé. Présente dans `benchmark/models/trois-tetes-v4/` (`rules.json`, `seuils_tajwid.json`), pas dans la chaîne |
| Écart canonique (« tête 3 ») | **Hors du ONNX**, dans un JSON (`tete3.json`). Volontaire : elle a besoin de grandeurs **conditionnées par la cible**, que seul l'appelant connaît. Une tête purement acoustique a été mesurée 6–13 % de détection — la pire de toutes |

Depuis `df67e02`, le modèle expose une 2ᵉ sortie `encoder_state`. **Ce n'est
pas une tête, c'est une prise** : les 512 dimensions étaient calculées de toute
façon puis jetées à la projection sur 1025 classes. Rien de plus n'est calculé.

---

## 3. Le modèle : ce qui tourne vs ce qui attend

**Déployé sur le téléphone** — dossier device `models/fastconformer-ctc-mixed-e02`,
contenu réel = **epoch 14** du run tajweed-mixed (nom historique, cf. `HANDOFF.md` §2).

**Prêt et vérifié, pas validé** — `benchmark/models/tete3-sur-v4-phrases/` :
`model.onnx` 461 Mo (fichier unique), entrées `audio_signal` + `length`
**contrôlées**, sorties `logprobs` + `encoder_state`, écart PyTorch/ONNX
2,10e-05, `vocab`/`word_tokens` identiques à l'export déployé.

---

## 4. Ce que dit la mesure — et ce qu'elle ne dit pas

189 phrases tenues à l'écart, audio **réellement fauté**, détection à 2 % de
collatéral :

| Encodeur | règle C | tête 3 | z |
|---|---|---|---|
| modèle de l'app (déployé) | 36/149 · 24,2 % | 32/149 · **21,5 %** | 0,55 |
| `fastconformer-causal-v4-phrases` | 40/148 · 27,0 % | 46/148 · **31,1 %** | 0,78 |

**Sur le modèle déployé, la tête ne fait PAS mieux que la règle.** Les 31 %
viennent de l'encodeur réentraîné, pas de la tête. Corollaire déjà au graphe :
**le plafond de la tête est fixé par l'encodeur.**

Pourquoi l'état et non les logprobs : règle 27 % · tête sur les mêmes logprobs
26 % · tête sur l'état **31 %**. Ce n'était pas la formule qui était mauvaise —
les logprobs ont déjà **jeté** l'information (projection apprise pour
*transcrire*, pas pour *juger un écart*).

⚠️ **Aucun de ces écarts n'est significatif pris isolément** (z = 0,55 et 0,78,
il faudrait 1,96 ; le trajet complet 24,2 % → 31,1 % ne donne que z = 1,33 sur
189 phrases). Ce qui soutient la direction est l'**AUC : 0,748 → 0,792**, bien
plus puissante qu'un point de la courbe. **C'est une direction, pas une preuve.**

---

## 5. Le chiffre de référence à ne pas casser

Tag `v2-frontiere-2.37pct`. Recette scriptée, même sourate/modèle/récitateur :

| | fenêtres | non verts | attente | bloquant |
|---|---|---|---|---|
| référence passe 1 | 165 | 2,71 % | 3,1 s | 0 |
| référence passe 2 | 167 | 2,03 % | 3,3 s | 0 |
| **avec la prise** | 169 | **2,37 %** | 3,1 s | 0 |

2,37 % tombe **entre** les deux passes de référence, l'attente ne bouge pas,
ancre 294, RESYNC 0, aucun mot non jugé. Lire la seconde sortie ne coûte rien.

---

## 6. La décision qui bloque tout — MISE À JOUR : ce n'est plus v4-phrases

Ce qui suit décrivait l'arbitrage sur `v4-phrases`. **Périmé par §0** :
l'encodeur a avancé deux fois depuis (contrastif → verifie-v1), avec un vrai
gain mesuré (détection 25→53 %, biais canonique inversé), pas seulement une
transcription stable. Recalibrer la tête 3 sur `v4-phrases` maintenant serait
calibrer sur l'avant-avant-dernier encodeur.

**Le blocage réel, ce soir, n'a pas changé de nature — il a changé de cible** :
téléphones débranchés, **aucune recette device sur `verifie-v1`**. Sans elle,
impossible de savoir si le gain de détection tient une fois la transcription
et le temps réel mesurés dans les conditions réelles (§5 est l'étalon à
reproduire, sur le nouvel encodeur).

➡️ **Prochaine action, dès les téléphones rebranchés : recette de
non-régression sur `verifie-v1`.** Pas de branchement de tête tant qu'elle
n'est pas passée — même raisonnement qu'avant, cible différente.

Ancien texte, gardé pour traçabilité (l'arbitrage v4-phrases avait bien été
fait et exécuté, ce n'est pas remis en cause — seulement dépassé) :
> `fastconformer-causal-v4-phrases` a été entraîné sur des **phrases
> fautées**. Rien ne garantit qu'il tienne les 2,37 % de mots non verts sur de
> la récitation JUSTE — et c'est ce taux que la référence protège. Décision
> utilisateur déjà prise : passer à v4-phrases (l'export est fait). Ce qui
> reste est la vérification, pas l'arbitrage.

---

## 7. Reste à faire, dans l'ordre — MISE À JOUR

1. **Recette de non-régression device sur `verifie-v1`** (pas v4-phrases,
   cf. §6) → le taux tient-il ? le temps réel ? (§5 est l'étalon)
2. **⚠️ Dépendance nouvelle** : si `verifie-v1` passe, la tête tajwid ET la
   tête 3 doivent être **réentraînées/recalibrées dessus** avant tout
   branchement — toutes deux vivent sur `v4-phrases`, encodeur maintenant
   périmé. Le stage a de la tête tajwid est rapide et sans risque (encodeur
   gelé pendant l'entraînement) ; la tête 3 demande de refaire tourner
   `entrainer_encodeur_contrastif.py`-style ou `tete_encodeur_ecart.py` sur le
   nouvel encodeur pour ré-extraire les 12 caractéristiques + réentraîner les
   deux couches.
3. **Les 12 caractéristiques** conditionnées par la cible, côté Kotlin (non
   écrites — inchangé)
4. **Branchement au Décideur** : moyenner l'état sur les frames du mot,
   concaténer les 12 scores, appliquer les deux couches, remonter le verdict
5. Le chantier « entraînement contrastif de l'encodeur » cité au point
   suivant à l'origine **a été fait** (§0) — l'ordre logique se poursuit
   maintenant par le point 1 ci-dessus (valider ce nouvel encodeur), pas par
   un nouveau contrastif.

Déjà posé et au vert : `Tete3.kt` (chargement, normalisation, deux couches,
ReLU, seuils — **appelé par personne**, rien ne change à l'exécution),
`Tete3Test.kt` (4 tests, dont la **parité** Python/Kotlin sur les vrais poids
contre la valeur NumPy `-65,610130`), 28 tests `recitation2` verts, 0 échec.

> La parité n'est pas un test de confort : une divergence Python/Kotlin ne
> lèverait **aucune erreur**, elle rendrait juste les poids dénués de sens. Le
> projet a déjà payé deux fois le fait de réimplémenter une logique dans deux
> langages et de croire le résultat.

---

## 8. Retour arrière — trois niveaux (condition posée par l'utilisateur)

| Niveau | Point de retour |
|---|---|
| code | branche `tete3-ecart-canonique` ; `recitation-v2` + ses 3 tags intacts |
| modèle | `model.onnx.avant_tete3` sauvegardé **sur le téléphone** avant le push |
| graphe | `graph_avant_stepNN` à chaque étape |

Un retour arrière qui ne couvrirait que le code laisserait le téléphone sur un
modèle que plus aucun commit ne décrit.

---

## 9. Pièges de ce chantier

- **L'information se perd en cours de journée.** Le commit `de414cd` disait
  déjà « la mesure dit de ne pas s'en servir là » ; l'oubli a été retrouvé le
  soir en ouvrant `tete3.json`. Interroger `GRAPHE_RECITATION.md` **avant** de
  lire le diff — c'est exactement ce qu'il existe pour empêcher.
- **Un gain d'AUC n'est pas un gain de détection.** Ne jamais présenter les
  31 % comme acquis : z < 1,96 partout.
- **Ne pas faire tourner l'encodeur deux fois.** `FrontAcoustique.sorties()`
  rend logprobs *et* état en **un seul appel** — le curseur glissant en émet
  une toutes les 3 s.
- **Les deux dernières recettes (2026-07-31) sont sur la sourate 2**, alors que
  la consigne enregistrée est de mesurer sur **la 18 (Al-Kahf)** : toujours
  mesurer le même passage revient à corriger ce passage. À trancher avant la
  recette du §7.1.
- Après toute modification de la chaîne : **`superviseur-recette` obligatoire**,
  sans attendre qu'on le demande. Le hook `exige-superviseur.py` bloque le gel
  de version sans preuve postérieure à la modification.

---

## 10. MISE À JOUR 2026-09-15 — les DEUX têtes entrent dans la décision

Le §6 posait la question « quel encodeur avant de brancher la tête ». Elle est
tranchée depuis : les deux têtes utilisées ici sont calibrées sur
`warsh-v5-epoch6.nemo` (empreinte encodeur `900a142d2b585d3c`), 1036 entrées
(mean+std de l'état + 12 caractéristiques). Le nœud `[MESURE] la tête 3
n'apporte RIEN sur le modèle de l'app` (2026-07-31) portait sur l'encodeur
d'alors et une tête à 524 entrées : **cause nouvelle nommée**, pas une
réintroduction d'un mécanisme mesuré perdant.

### Ce qui est branché

| riwaya | fichier de décision | SHA-256 (début) | logit de référence |
|---|---|---|---|
| Hafs | `tete3_hafs_particules_20260915.json` | `7e708b20…` | `37,389693` |
| Warsh | `tete3_warsh_v1_20260915.json` | `39011c20…` | `−0,976116` |

La riwaya choisit **un fichier de poids, jamais une règle** : `JugementTete3`
porte une `Politique` par riwaya, et `evaluer`/`couleur` n'ont pas bougé d'une
ligne. Le garde `!riwayaWarsh` du plugin n'excluait aucun défaut connu — il n'y
avait alors aucune tête 3 Warsh vérifiée à mettre en face. Le vote entre
fenêtres, lui, est aveugle à la riwaya (il compare des textes LIBRES entre eux)
et reçoit déjà les équivalences orthographiques de la riwaya courante par
`variantesOrthographePourRiwaya`.

### Ce qui est prouvé, et seulement cela

- **Identité + arithmétique des deux têtes**, sur le vecteur déterministe
  `(((i*37) % 101) − 50) / 25` — la même formule des deux côtés, sinon les
  deux nombres ne se comparent pas. Contrôle **croisé** : chaque politique
  refuse la tête de l'autre riwaya (`JugementTete3Test`). Sans ce croisement,
  une tête chargée pour la mauvaise riwaya produirait des logits plausibles
  sans jamais rien signaler — deux fichiers de même format, seule l'empreinte
  les distingue.
- **Parité d'extraction Warsh sur de la VRAIE récitation**
  (`Tete3PariteWarshAudioReelTest`, `AbdelKabirHadidi_assajda/100_10.wav`) : les
  12 caractéristiques une par une, puis le logit. Mieux que le pendant Hafs,
  qui est sur du TTS. Les logits de référence viennent de `tete3_warsh.json`
  **du paquet**, vérifié et non supposé : recalculés hors Kotlin sur les trois
  têtes candidates, seule celle du paquet retombe dessus à 1e-5.
  Cette parité vaut pour les DEUX têtes Warsh : elles consomment le même
  vecteur et ne diffèrent que par leurs poids.

### Ce qui n'est PAS prouvé — à ne pas présenter autrement

- **Aucune calibration.** Les deux fichiers n'ont pas de `seuils_mesures` ; la
  frontière est le logit brut 0. Le jour où l'un d'eux porte des seuils, la
  politique doit être revue, pas conservée en silence (le test le vérifie).
- **Aucune mesure sur téléphone en Warsh.** Les replays device du 15/09
  (11 cas `green_after_negative`) sont tous en Hafs.
- **Aucun rappel mesuré sur fautes Warsh réelles.** Les chiffres par catégorie
  du rapport de PC A sont une annonce de ce rapport, pas une mesure faite ici.
- Le chemin reste derrière le marqueur de debug `files/vote_fenetres_actif` :
  rien ne change pour un utilisateur de l'APK de production.

> ### ⚠️ CORRECTIF DU 15/09 AU SOIR — CES CHIFFRES SUR LA TÊTE 3 SONT CADUQUES
>
> Codex a trouvé, le même jour, que la tête 3 ne recevait **pas les bons
> jetons** : l'aligneur utilise un dictionnaire + découpage glouton, son
> entraînement utilisait SentencePiece BPE (`وَإِنْ` → `[393, 959]` attendu
> contre `[4, 615, 959]` fourni). Les 12 caractéristiques étaient donc
> calculées sur une segmentation fausse — cf.
> `CORRECTION_TOKENISATION_TETE3_JVM_20260915.md`.
>
> Tout ce qui suit concernant la **tête 3** a été mesuré avec ces entrées
> fausses, et notamment les quatre faux positifs cités en exemple, qui
> disparaissent une fois corrigés. Rejeu avec les bonnes entrées, sur 10 cas
> (103 mutations, 534 mots corrects) : la tête 3 détecte **autant** que le vote
> seul (69/103 dans les deux cas) et n'ajoute plus que 2 faux — elle est
> **neutre**, ni utile ni nuisible.
>
> Ce qui reste valable, parce que cela ne dépend pas d'elle : le coût du vote,
> le décrochage sur audio correct, et le décalage d'index de la fiche.
>
> Diagnostic complet et suite : `TACHE_CODEX_ALIGNEMENT_PLAFOND_20260915.md`.

### MESURÉ LE MÊME JOUR — et le verdict est négatif

Les trois réserves ci-dessus ont été levées en partie l'après-midi même, par
la campagne en paliers (`benchmark/CAMPAGNE_PALIERS_20260915.md`, 8 cas,
195 erreurs sur 1 113 mots, Samsung, Hafs). Trois configurations, mêmes WAV,
même modèle.

| | fautes détectées | faux signalements |
|---|---|---|
| ni vote ni tête 3 | 52 | 25 |
| vote seul | 68 | 73 |
| vote + tête 3 | 69 | 76 |

**La tête 3 en décision n'apporte rien : +1 détection, +3 faux.** Au palier
10 % — le seul où les trois configurations jugent exactement le même nombre de
mots (237), donc le seul strictement comparable — elle ne change **rien du
tout** (57 % de rappel, 9,3 % de faux, avec et sans elle).

⚠️ **Une hypothèse intermédiaire a été réfutée, et elle doit rester écrite.**
On l'avait d'abord accusée de porter les faux signalements, parce que 18 de ses
21 interventions portent sur un mot correct. C'est exact et sans effet : ces
mots étaient **déjà** signalés par le vote texte. Elle ne fait presque que
confirmer, dans un sens comme dans l'autre. Le coût vient du vote, pas d'elle.

Conséquence appliquée : la tête 3 a désormais **son propre marqueur**
(`files/tete3_decision_actif`), séparé de celui du vote, et elle est **éteinte
par défaut**. Sans cette séparation, la question « lequel des deux porte le
gain » n'avait pas de réponse mesurable — c'est ce qui manquait au §7.

Ce que cela ne dit pas : rien sur Warsh (aucune source Warsh dans ce banc),
rien sur un seuil calibré (ceux de PC A sont établis sur des mots isolés d'un
cache d'entraînement, pas sur la règle multi-fenêtres qui décide), rien sur de
la vraie récitation humaine (montage synthétique).
