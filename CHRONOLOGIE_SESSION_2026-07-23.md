# Chronologie session 2026-07-23 — diagnostic récitation / alignement / gestion du GOP

Document resserré sur le sujet ASR (récitation, alignement forcé, gestion du
GOP) — la mécanique git annexe (réorganisation mindmap, refactor de
localisation, commit de rattrapage) n'y figure pas, elle n'a aucun rapport
avec ce sujet.

Repères commits :
- `a2d3054` (2026-07-20 17:51) — dernier commit avant le travail sur les 2 GOP.
- `5d97e09` (2026-07-23 16:55) — introduction de l'architecture 2 têtes
  (encodeur partagé, tête lettres+harakat + tête tajwid, GOP dépiégé).

---

## 1. Point de départ : verset manquant chez un récitateur confirmé

Test du modèle 2-têtes sur la sourate 90, récitée en continu. Entre
18:35:08 (verset 90:10 validé) et 18:35:31 (verset 90:12 validé), le
verset **90:11 a disparu** sans jamais être signalé en erreur — juste
absent du texte figé.

## 2. Diagnostic mesuré (pas supposé)

Analyse du log brut (`asm.log`), fenêtre 18:35:09→18:35:31 :

- L'audio du verset 90:11 a été **capté et correctement transcrit** à
  18:35:25 : `"فَلَا ٱقْتَحَمَ ٱلْعَقَبَ"` (mots #43-45 exacts).
- Mais la transcription s'est **effondrée en re-transcrivant le même
  audio** à mesure que le buffer grossissait :
  ```
  18:35:25   1s   "فَلَا ٱقْتَحَمَ ٱلْعَقَبَ"   (3 mots, juste)
  18:35:29   3s   "فَلَاقْ"                      (1 mot)
  18:35:30   4s   ""                             (0 mot)
  ```
- Conséquence pour l'alignement : la DP n'avait plus rien à apparier
  (`mots=0` sept fois de suite), l'ancre est restée bloquée à 42 pendant 22s.

## 3. Quatre hypothèses de correctif, testées HORS DEVICE, trois rejetées

Mesurées avec des scripts dédiés (`benchmark/test_norm_fixed_vs_perfeature.py`,
`benchmark/simulate_sliding_window.py`) avant de toucher au moteur natif —
leçon d'une session antérieure où un changement de segmentation non mesuré
avait cassé quelque chose sur device.

| Hypothèse | Résultat mesuré | Verdict |
|---|---|---|
| Stats de normalisation FIXES au lieu de `per_feature` | Ne corrige pas l'effondrement (6/7 cas altérés dans les 2 modes) ET coûte +1,28 pt de WER (12,99%→14,27%, 150 clips) | **REJETÉE** |
| Désactiver le portier RMS (garder le silence entier) | WER 70,2% contre 22,8% avec le portier actif | **REJETÉE** |
| Couper le segment à chaque pause au lieu de recoller | WER 103,5% — le pire des 4, fragments trop courts | **REJETÉE** |
| Fenêtre glissante (taille fixe, glissement continu) | Aucun réglage (W=4 à W=8) ne bat la politique actuelle sur les 2 profils testés (fluide et avec pauses) | **REJETÉE pour l'instant** (piste réouverte, cf. §6) |

**Conclusion à ce stade** : la segmentation actuelle (`BufferedTranscriber.kt`)
est déjà la moins mauvaise des options testées. Le problème n'est pas un
bug de segmentation à corriger.

## 4. Correction de diagnostic : "hésitation" → pause normale entre versets

**Objection utilisateur, justifiée** : le mot "hésitation" employé dans le
diagnostic donnait l'impression d'un cas marginal (utilisateur peu sûr de
lui). Mesure sur `asm.log` : l'écart entre versets figés est de **4 à 8
secondes de façon quasi constante** (14 intervalles sur 16). Ce n'est pas de
l'hésitation erratique, c'est la **respiration normale entre versets** —
possiblement une pause de waqf obligatoire. Ça touche tout récitateur, y
compris confirmé.

**Conséquence sur le diagnostic** : la cause réelle est un **décalage de
domaine** — le modèle est entraîné sur des clips de versets isolés, propres,
sans pause interne (seulement 4,3% des clips d'entraînement ont ≥2s de
pause interne, mesuré sur 400 clips), alors qu'une récitation continue de
plusieurs versets en contient forcément.

## 5. Hypothèse alternative de l'utilisateur : le mot bloqué

**Hypothèse formulée** : quand le modèle ne détecte pas le bon mot, il se
bloque en l'attendant ; revenir en arrière pour le redire peut débloquer.

**Vérifié, mécanisme réel** — tracé dans `ay.log` :
```
seq=16  differe=15 (le mot "لَقَدْ" ne s'aligne pas, ancre bloquée)
   -> l'utilisateur redit "وَوَالِدٍ وَمَا وَلَدَ" (les mots D'AVANT)
seq=19  differe=15 (toujours bloqué -- la répétition ne portait pas sur
                     le mot en cause)
seq=22  differe=20 (débloqué -- "لَقَدْ خَلَقْنَا..." enfin reconnu)
```
Le mécanisme existe (un mot peut refuser de s'aligner et bloquer l'ancre),
mais ici ce n'est pas la répétition qui a débloqué, c'est la continuation
qui a fini par produire une transcription propre du mot bloqué.

**Vérifié également** : ce phénomène n'est **pas aggravé par `5d97e09`**
(2 GOP). Mesure sur toutes les sessions :
```
AVANT 5d97e09 (16:55) : 11 épisodes de blocage sur 129 alignements finaux (8,5%)
APRES 5d97e09         :  5 épisodes de blocage sur  69 alignements finaux (7,2%)
```
Taux identique ou légèrement plus bas après — mécanisme réel et distinct de
celui du §2-3, mais indépendant du commit du jour.

## 6. Décision : entraînement plutôt que fenêtre glissante

Choix initial de l'utilisateur : fenêtre glissante d'abord. Une simulation
offline plus poussée (`benchmark/simulate_sliding_window.py`) a montré
qu'aucun réglage ne bat la politique actuelle sur les 2 profils testés :
```
                        FLUIDE    AVEC PAUSES
ACTUELLE (2s/12s)       29,8%      73,7%
glissante W=8 S=4       56,1%      61,4%   <- meilleure en pauses, pire en fluide
glissante W=6 S=3       70,2%      78,9%
glissante W=5/4 S=2     91-100%   100%
```
**Bug de simulation initial, corrigé** : la première version figeait tout le
texte du buffer à chaque glissement au lieu de ne figer que les mots
sortant de la fenêtre → duplication de texte (WER >100%). Corrigé en ne
figeant que les mots AVANT la coupe.

**Décision utilisateur, révisée après ce chiffre** : passer à
l'entraînement, sans écraser l'ancien modèle. La fenêtre glissante est mise
de côté (piste non éliminée, réouvrable).

## 7. Augmentation par pauses + entraînement lancé

`benchmark/build_pause_augmented_manifest.py` : génère des clips avec
pauses insérées PUIS passées par le même portier RMS que
`BufferedTranscriber.kt` (mêmes seuils exacts), pour que l'audio
d'entraînement soit bit-pour-bit ce que le modèle voit réellement en
production. 6000 clips générés (10% du corpus Coran annoté), QA passée.

Manifest combiné : `train_manifest.jsonl` (156892 lignes, original
INTACT) + `train_pause_augment.jsonl` (6000 lignes) →
`train_manifest_pause_aug.jsonl` (nouveau fichier).

**Entraînement lancé** (`finetune_dual_head.py --stage b`), en continuation
depuis le meilleur checkpoint existant (`stageb-convhead-v1`, F1 tajwid
0,975, val_wer_ctc 0,1201) :
```
--init_nemo    stageb-convhead-v1/stageb-final.nemo
--init_tajwid_head stageb-convhead-v1/stageb-tajwid-head.pt
--head_hidden  256 (ConvTajwidHead)
--lr           1e-5 (même LR que le run source, déjà validé sans dégradation)
--epochs       8
--run_tag      convhead-pause-aug-v1
```
Sortie : nouveau dossier `stageb-convhead-pause-aug-v1/` — rien n'écrase le
checkpoint source. Vitesse stabilisée : 18,38 it/s → ~14 min/époque, ~1h50
au total. **Toujours en cours** au moment d'écrire ce document (sain,
aucune interruption).

À faire une fois terminé : `eval_dual_stats.py` pour vérifier que la tête
tajwid ne régresse pas (objectif du jour : tajwid<0,1 sans dégrader le duo).

## 8. Tentative de test comparatif device "avant/après 2-GOP" — non aboutie

Objectif : comparer le comportement device avant et après l'introduction
des 2 GOP (`5d97e09`), en revenant temporairement à l'état `a2d3054` sur le
moteur ASR (`BufferedTranscriber.kt`, `ForcedAligner.kt`, `FastConformerCtc.kt`,
`FastConformerCtcPlugin.kt`, `recitation_provider.dart`,
`fastconformer_verifier.dart`, `recitation_state.dart`).

**Constat en tentant de compiler cet état** : `recitation_state.dart` et
`fastconformer_verifier.dart` sont des fichiers centraux, référencés par de
nombreux écrans à travers l'app, et ont évolué en plusieurs vagues
indépendantes depuis `a2d3054` (le passage aux 2 GOP, ET des évolutions
sans rapport). Les ramener isolément à `a2d3054` casse la compilation des
écrans qui dépendent de leur évolution ultérieure — pas seulement ceux liés
au GOP. Chaque tentative de revert minimal révélait une nouvelle
incompatibilité, sans fin visible en un temps raisonnable.

**Décision** : test comparatif device abandonné pour l'instant, retour à
l'état courant (post-2-GOP + augmentation par pauses). Rien n'est perdu :
l'état `a2d3054` reste consultable et ré-extractible via git à tout moment
si ce test est repris. Pour le reprendre proprement, il faudrait soit
vérifier fichier par fichier qu'aucune évolution indépendante du GOP ne
s'est glissée dans le périmètre reverté, soit accepter de patcher au fur et
à mesure chaque incompatibilité rencontrée.

## 9. État courant sur ce sujet

- **Entraînement en cours** (`stageb-convhead-pause-aug-v1`), sain.
- **Test comparatif device "avant/après 2-GOP"** : non abouti, reporté.
- **Fenêtre glissante** : mesurée perdante sur les profils testés, non
  éliminée, réouvrable si l'entraînement par pauses ne suffit pas.
- **Reste en attente** : `eval_dual_stats.py` sur le nouveau checkpoint,
  export ONNX si concluant, calibrage du seuil tajwid (`qalaqah` mesuré à
  -12/-19, loin du seuil -1,2), règle waqf (asset déjà construit, service
  Dart manquant).
