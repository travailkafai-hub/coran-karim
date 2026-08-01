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
