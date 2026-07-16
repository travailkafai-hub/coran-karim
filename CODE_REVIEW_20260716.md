# Revue de code + investigation du lag — 2026-07-16 (soir)

*Revue `/code-review` (haute rigueur : 7 angles finder, 10 candidats, vérification
indépendante à 1 voix chacun — 10/10 CONFIRMÉS) sur les 3 commits du jour
(`fc506f6`, `22b27e3`, `9446c10`), suivie de l'investigation du lag signalé par
l'utilisateur sur device. Aucun de ces bugs n'est encore corrigé — ce document
sert de trace avant correction, pas de rapport de correction.*

---

## 1. Le lag observé — diagnostic

**Symptôme rapporté** : "le système s'alourdit, ça ne répond pas vite" pendant
une session de récitation (Al-Qalam, verset 68:17).

**Preuve dans `recitation_diagnostic.log`** : le mot `لَيَصْرِمُنَّهَا` a échoué
**17 fois de suite** entre 18:07 et 18:46 (39 minutes, avec des pauses où
l'utilisateur a visiblement abandonné puis réessayé). Chaque échec déclenche un
cycle `pauseCapture()` → jouer la correction → `resetBuffer()` → `resumeCapture()`.
Mesure de la durée réelle de ces cycles sur toute la session :

```
la plupart : 4-10s
plusieurs  : 9-10s+
un pic     : 37,29s  (18:45:38 -> 18:46:15)
```

**Root cause du pic de 37s** : `pauseCapture()` (recitation_verifier.dart:648)
logue une ligne AVANT `await _recorder.pause()` et une APRÈS. Sur ce cas précis,
27 secondes se sont écoulées ENTRE ces deux lignes — `_recorder.pause()`
lui-même (un appel plateforme natif) est resté bloqué 27s. Preuve que le micro
n'était pas réellement coupé pendant ce temps : `BufferedTranscriber` a continué
à produire des passes de retranscription et des jugements GOP sur DEUX AUTRES
mots (84 "مُصْبِحِينَ", 85 "وَلَا") pendant cette fenêtre — le flux audio
continuait d'arriver et d'être traité alors que l'app croyait avoir mis le
micro en pause.

**Cause primaire (pourquoi 39 minutes, pas juste un cycle lent)** : le mot
`لَيَصْرِمُنَّهَا` ne progressait JAMAIS — chaque tentative relançait un nouveau
cycle de correction. C'est exactement le mécanisme du **Finding #2 ci-dessous**
(confirmé par la revue de code indépendamment, avant que ce lien ne soit fait) :
un mot peut boucler différer → oublier → différer indéfiniment sans jamais être
tranché. Le lag n'est donc pas fondamentalement un problème de performance
(le moteur ONNX tourne à 100-900ms/passe, cf. mesures du jour) — c'est un mot
**structurellement incapable d'avancer**, chaque nouvel essai relançant un cycle
de 5-37s de pause/lecture/reprise, `~17` fois d'affilée.

**Cause secondaire (pourquoi chaque cycle individuel traîne)** : `_recorder.pause()`
qui prend occasionnellement 5-37s au lieu d'être quasi instantané suggère une
congestion du platform channel Android — probablement les appels natifs
`feedBufferedAudio`/inférence ONNX (canal `com.corankarim/fastconformer_ctc`)
retardant le traitement de l'appel `pause()` du plugin `record` (canal séparé,
mais les method channels Flutter sont par défaut sérialisés sur le thread
principal). Non confirmé avec certitude à ce stade (nécessiterait une trace au
niveau plateforme, hors de portée des logs applicatifs) — mais cohérent avec le
diagnostic déjà posé dans `REVUE_ARCHITECTURE_KARAOKE.md` (§3.5.6, "MethodChannel
bavard") sur la fréquence des appels natifs pendant une session active.

**Conclusion** : corriger le Finding #2 (garantie "2 chances max") est le
correctif le plus direct pour éliminer ce type de blocage. La lenteur de
`_recorder.pause()` elle-même mérite une mesure séparée et isolée (chronométrer
`_recorder.pause()` seul, sans inférence concurrente, pour confirmer si la
congestion du platform channel est la vraie cause).

---

## 2. Revue de code — 10 findings, tous confirmés

Portée : diff des 3 commits du jour (`fc506f6`, `22b27e3`, `9446c10`), ~1871
lignes sur 15 fichiers. Méthode : 7 agents finder indépendants (3 angles
correction + 3 angles nettoyage + 1 altitude ; angle conventions omis, aucun
CLAUDE.md dans le repo), dédupliqués en 10 candidats, chacun vérifié par un
agent indépendant supplémentaire (défaut PLAUSIBLE, CONFIRMED si prouvable dans
le code). **Résultat : 10/10 CONFIRMED.**

### 2.1 Course critique

**#1 — `recitation_provider.dart:1223`** — `dispose()` nettoie le verifier
partagé (singleton, PAS autoDispose — contrairement à `recitationProvider`
lui-même) sans aucun verrou :
```dart
unawaited(_verifier.stop().then((_) => _verifier.resetBuffer())...)
```
Scénario : sortie de l'écran karaoké puis réouverture rapide. Le `stop()` de
l'ancienne session (fire-and-forget) peut atterrir APRÈS que la nouvelle
session ait déjà appelé `_recorder.startStream()` et posé sa cible
d'alignement — tuant silencieusement le nouvel enregistrement ou vidant son
buffer tout juste initialisé.

### 2.2 La garantie "2 chances max, jamais différé indéfiniment" est cassée par 3 chemins distincts

Rappel du contrat (`ForcedAligner.kt:175-177`) : un mot différé une fois DOIT
être re-passé en `forceJudgeIndex` au prochain appel FINAL, pour qu'il soit
tranché (même sévèrement) plutôt que perdu en silence.

**#2 — `ForcedAligner.kt:311`** (le plus grave — **cause directe du lag §1**) :
```kotlin
if (wordFrames[wi] == 0) break // ligne 311, AVANT le check forceJudgeIndex
...
if (!covered && anchor + wi != forceJudgeIndex) {  // ligne 313
```
Si un mot forcé en 2e chance obtient à nouveau zéro frame de la DP, la boucle
sort AVANT même de vérifier `forceJudgeIndex` — le mot n'est ni jugé ni
re-différé, et `BufferedTranscriber.kt:200` (`deferredOnceIndex = res.deferredIndex ?: -1`)
remet le garde-fou à -1, effaçant toute mémoire que ce mot était en attente.
Peut boucler différer→oublier→différer à l'infini. **Preuve device directe** :
17 tentatives consécutives sur `لَيَصْرِمُنَّهَا` sans que l'ancre n'avance jamais.

**#3 — `FastConformerCtcPlugin.kt:280`** (mode "coach" en un coup) : n'a jamais
branché `forceJudgeIndex`, et chaque appel crée un `ForcedAligner` neuf sans
mémoire du précédent — un mot différé y est **perdu pour de bon** (pas de
2e appel possible sur ce mode one-shot).

**#7 — `BufferedTranscriber.kt:341-383`** (coupure dure à 12s,
`pendingForceCommit`) : promeut l'aperçu en cache directement en "final" par
mutation de map, sans jamais rappeler `align()`/`runAlignment()` — donc
`deferredOnceIndex` n'est jamais mis à jour pour cette instance précise. Moins
grave que #2/#3 (le mot aura une nouvelle tentative non forcée au segment
suivant, pas perdu à jamais), mais même défaut de fond.

### 2.3 Le nouveau bouton souffleur a deux bugs de concurrence

**#4 — `karaoke_recitation_screen.dart:467`** — `_onWordFailed` ne vérifie que
`_autoCorrecting`, pas le nouveau flag `_promptingWord`. Un mot qui échoue
pendant la lecture du souffleur relance `pauseCapture()`/`playWordRange()` en
parallèle sur le MÊME lecteur audio statique (`WordCorrectionAudio._player`) —
les abonnements `posSub`/`doneSub` des deux appels s'entrechoquent.

**#5 — `karaoke_recitation_screen.dart:411`** :
```dart
await Future.delayed(const Duration(milliseconds: 400));
if (!mounted) return;                          // sort AVANT resetBuffer()
if (wasListening) await verifier.resetBuffer(); // jamais atteint
} finally {
  if (wasListening) await verifier.resumeCapture();  // s'execute quand meme
```
Si l'utilisateur quitte l'écran pendant les 400ms d'attente du souffleur, le
`resetBuffer()` est sauté mais `resumeCapture()` s'exécute quand même via le
`finally` — le micro rouvre avec l'audio du récitateur (celui qu'on vient de
faire jouer) encore dans le buffer natif, qui peut être transcrit et jugé
comme si c'était l'utilisateur. **Réintroduit exactement la classe de bug de
fuite de session corrigée ailleurs dans ce même diff.**

### 2.4 Le correctif du jour (`spellsDifferentWord`) a un trou

**#6 — `recitation_provider.dart:730`** :
```dart
final isFragment = hasSpeech &&
    actualStrict.isNotEmpty &&
    expected.strict.isNotEmpty &&
    (expected.strict.endsWith(actualStrict) ||
        expected.strict.startsWith(actualStrict));
```
Aucune borne minimale sur `actualStrict` (contrairement à
`ArabicNormalizer.matchesTolerant` qui a `maxBleedPrefix = 4`). Un match d'UN
SEUL caractère coïncidant avec la première ou dernière lettre du mot attendu
suffit à mettre `isFragment=true`, ce qui force `spellsDifferentWord=false` et
renvoie le mot au jugement gop seul — **rouvrant exactement le bug sin/sad
qu'on vient de fermer aujourd'hui** (gop=-0.35 → vert malgré un mot différent).

### 2.5 Régression fonctionnelle

**#8 — `mushaf_screen.dart:361`** — `_openContinuousRecitation` (écran debug
utilisé pour juger la qualité du modèle) est maintenant borné à 1 page via
`_fragmentFromActive()`, mais `RecitationScreen` n'a aucun mécanisme
d'extension (contrairement à `KaraokeRecitationScreen._maybeExtendNextPage`).
Avant ce diff : toute la fin de la sourate. Après : 1 page, sans suite possible
dans la même session.

### 2.6 Mineurs

**#9 — `recitation_provider.dart:742`** — `hasSpeech` (ajouté pour empêcher
qu'un silence pur soit jugé "correct") ne protège QUE la branche `correct`, pas
la branche `unclear` juste en dessous. Un mot jamais prononcé (`r.actual == ""`)
avec un gop proche de 0 (documenté dans ce même diff : forced≈free≈0 sur du
blank) tombe dans la branche `unclear` au lieu d'être exclu — moins grave que
le bug original (silence→vert) mais toujours faux (silence→orange).

**#10 — `ForcedAligner.kt:351`** (efficacité, pas correction) — le fallback de
rattrapage (`buildFrom` + `greedyTokenIds`) refait tout le calcul O(t) au lieu
de n'étendre que la queue non résolue par la passe naturelle — double le
travail de backtrace/argmax à chaque déclenchement (rare : seulement sur
segment figé + alignement bloqué).

---

## 3. Situation entraînement (mixed, checkpoint `mixed-e02` déployé)

```
Process   : vivant, epoch 5 à 51% (32 min sur cette epoch)
GPU       : 7,86/16,3 Go alloués (utilisation instantanée 3% — creux normal
            entre batches/sauvegarde de checkpoint, pas un blocage)
OOM/erreurs : aucun
```

**Tendance `val_wer_ctc` (val mixte, 50% erreurs / 50% canonique) — 20 mesures :**
```
0.184 → 0.168 → 0.163 → 0.151 → 0.156 → 0.149 → 0.150 → 0.146 → 0.144 → 0.145
→ 0.140 → 0.142 → 0.143 → 0.141 → 0.142 → 0.142 → 0.141 → 0.137 → 0.139 → 0.134
```
Descente régulière avec plateau/bruit normal epoch par epoch, **meilleur
checkpoint actuel : epoch=05, val_wer_ctc=0.134** (`fastconformer-quran-
epoch=05-val_wer_ctc=0.134.ckpt`, sauvé 18:46).

Rappel du gain déjà mesuré sur le checkpoint epoch=02 (déployé sur le
téléphone) vs l'ancien modèle, sur 150 clips d'erreurs tenus hors
entraînement : détection d'erreur 18,7% → 57,3%, CER canonique stable
(9,03% → 9,46%). Le modèle continue de s'améliorer ; une nouvelle mesure
séparée (détection erreurs / CER canonique) sur epoch=05 sera nécessaire pour
confirmer le gain avant un éventuel redéploiement.

---

## 4. Prochaines étapes (proposées, pas encore décidées)

1. Corriger le Finding #2 (garantie 2-chances) en priorité — c'est la cause
   directe et confirmée du lag vécu ce soir.
2. Corriger le Finding #1 (course dispose/reopen) et les Findings #4/#5
   (souffleur) — bugs de concurrence réels, risque de corrompre une session.
3. Corriger le Finding #6 (borne `isFragment`) — referme un trou dans le
   correctif principal du jour.
4. Findings #3, #7, #9, #10 : moins urgents, à planifier.
5. Finding #8 (régression écran debug) : décider si l'écran debug a encore
   besoin de couvrir plus d'une page, ou si c'est acceptable tel quel.
