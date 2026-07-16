# Revue d'architecture — karaoké Coran temps réel (CTC NeMo)

*2026-07-16 — revue critique demandée après la journée de correctifs (token « ▁ »
parasite, seuils GOP, fuite de session, entraînement mixte). Objectif : améliorer
la **performance sans dégrader la qualité**, et identifier ce qui, dans les bugs
récurrents, vient de l'architecture elle-même. Suivi d'un **plan d'exécution
détaillé** destiné à un agent exécutant (Sonnet).*

---

## 1. Architecture actuelle (telle qu'implémentée)

```
Micro ── blocs PCM 80 ms ──> Dart (recitation_verifier)
   └─ MethodChannel (12,5 appels/s, payload texte+align retourné à CHAQUE bloc)
        └─> BufferedTranscriber.feed()   [Kotlin, singleton]
              ├─ buffer du SEGMENT courant (gel sur pause ≥450 ms, borne dure 12 s)
              ├─ toutes les ~1,5 s de nouvel audio :
              │     mel(SEGMENT ENTIER)  → ONNX(SEGMENT ENTIER) → logprobs
              │     ├─ greedyDecode  → texte « entendu » (aperçu)
              │     └─ ForcedAligner → gop/mot (aperçu, non verrouillé)
              └─ au GEL : re-transcription FINALE du segment + jugements
                 verrouillés + reset buffer + ancre avance
Dart juge (gop + textMatches + similarity + spellsDifferentWord) → couleurs UI
```

Modèle : FastConformer hybride export ONNX **fp32, 458 Mo**, encodeur+CTC seulement.
`OrtSession` créée avec `SessionOptions()` **par défaut** (pas de threads, pas d'EP).

## 2. Mesures réelles (logs device du jour)

| passe | durée mesurée | RTF |
|---|---|---|
| 1 s | 103–280 ms | ~0,10–0,28 |
| 3 s | 182–499 ms | ~0,06–0,17 |
| 5 s | 268–358 ms | ~0,05–0,07 |

**Redondance structurelle** : chaque passe re-transcrit tout le segment.
Segment de 3 s → passes à 1,5 s + 3 s + gel 3 s ≈ **2,5× l'audio payé**.
Segment de 12 s (borne dure) → 1,5+3+…+12 ≈ 54 s transcrites pour 12 s parlées ≈ **4,5×**.
Charge soutenue estimée : 15–50 % d'un cœur en continu, fp32, sans accélérateur.
Ce n'est pas (encore) la latence perçue le problème — c'est la **batterie/thermique
sur les longues sourates** et le plafond que ça met à toute amélioration future
(modèle plus gros, cadence plus fine).

## 3. Critique — les problèmes sont-ils architecturaux ? Oui, pour l'essentiel

### 3.1 La normalisation `per_feature` sur tout le buffer est LE verrou

Le mel est normalisé par bin sur **l'ensemble du buffer** (mean/std recalculés à
chaque passe). Conséquence en chaîne, documentée dans les commentaires v2/v3 de
`BufferedTranscriber.kt` :
- impossible de transcrire incrémentalement (chaque nouvel audio change la
  normalisation de TOUTES les frames passées) → **d'où** le « tout re-transcrire
  toutes les 1,5 s » (le coût ×2,5–4,5) ;
- la normalisation **dérive** sur les longs buffers → **d'où** la machinerie de
  gel par silence (450 ms) et la borne dure 12 s.

Autrement dit : une propriété du préprocesseur a dicté toute l'architecture aval.

À noter : les colonnes **log-mel brutes ne dépendent PAS du reste du buffer**
(étapes 1–4 de `MelSpectrogram.compute`) ; seule l'étape 5 (normalisation) est
globale. Le mel est donc cachable frame par frame dès aujourd'hui — seul l'ONNX
reste non incrémental.

### 3.2 La segmentation par silence engendre la classe de bugs « mot frontière »

Preuves accumulées (toutes réelles, ce mois-ci) : mots amputés aux bords
(`مْدُ`, `ٱلْعَ`), jugements catastrophiques sur 1–2 frames de transition,
d'où : `MIN_FRAMES_FOR_JUDGMENT`, `deferredOnceIndex`/forceJudge « 2 chances »,
tolérance aux fragments, tolérance au bleed préfixe, filet décodage-libre…
**La moitié de la logique de jugement existe pour compenser la segmentation.**
Chaque rustine est individuellement justifiée ; leur accumulation est le signal
que la cause est en amont.

### 3.3 Le jugement n'a pas de signal absolu

`gop = forced − free` est **relatif**. Mesuré aujourd'hui : attendu `صِرَٰطَ`,
entendu `سَرَٰطَ`, gop = −0,35 → vert, parce que le modèle hésitait sur tout
(`free` = −1,42) et que « pas beaucoup pire que le meilleur chemin » ≠ « correct ».
Les correctifs successifs (textMatches, similarity, spellsDifferentWord) empilent
des heuristiques de texte par-dessus un score relatif. Il manque la question
directe : **« sur CES frames, ص ou س ? »** — posable au décodeur, voir §4.3.

### 3.4 Pas de VAD réel

Seuil RMS fixe (0,02) qui ne fait que limiter le silence *conservé*. Le bruit
ambiant est transcrit (charabia observé : `تَسُجْززْ`) puis jugé. `hasSpeech`
teste « texte non vide » — le charabia passe.

### 3.5 Performance laissée sur la table (sans toucher à la qualité)

1. **ORT non configuré** : pas d'`intraOpNumThreads`, pas de XNNPACK/NNAPI.
   Sur un SoC récent, 1,5–2,5× possible à sortie identique.
2. **fp32 458 Mo** : int8 dynamique ≈ 115 Mo et 1,5–3× plus rapide sur ARM ;
   fp16 ≈ 230 Mo. ⚠ change l'échelle des logprobs → seuils GOP à re-valider
   (harnais désormais disponible : `eval_error_detection.py` + val mixte).
3. **FFT récursive allocante** (2 tableaux par niveau × 9 niveaux × frame) :
   pression GC inutile ; une FFT itérative in-place à buffers réutilisés est
   bit-exacte et 5–10× plus rapide sur cette brique.
4. **Mel recalculé de zéro à chaque passe** alors que les colonnes log-mel sont
   cachables (cf. 3.1) — seule la normalisation (80×T flops, négligeable) doit
   être refaite.
5. **Double inférence au gel** : l'aperçu à T−0,5 s et le gel re-transcrivent
   quasi le même audio. Le chemin « force-commit réutilise l'aperçu » existe
   déjà pour la borne 12 s ; le généraliser au gel-sur-pause quand <0,3 s de
   nouvel audio est trivial.
6. **MethodChannel bavard** : payload complet (texte cumulé + align) renvoyé
   12,5×/s même inchangé. Mineur, mais gratuit à corriger (retour delta par
   numéro de séquence).

## 4. Propositions d'architecture

### 4.1 P0 — cette semaine, zéro risque qualité (sortie identique ou parité vérifiable)

| # | quoi | gain attendu | validation |
|---|---|---|---|
| P0.1 | `SessionOptions` : threads = nb gros cœurs, + XNNPACK EP | 1,5–2,5× inférence | texte greedy identique sur 50 clips val + Δlogprobs < 1e-3 |
| P0.2 | Cache incrémental des colonnes log-mel + FFT itérative | mel quasi gratuit à chaque passe | bit-exact vs `compute()` actuel (test unitaire) |
| P0.3 | Gel réutilise l'aperçu si <0,3 s de nouvel audio depuis | −1 inférence par segment (~30 %) | déjà le comportement borne-12s ; log `apercu reutilise` |
| P0.4 | Payload MethodChannel en delta (seq) | mineur (GC/série) | aucun changement visible |

### 4.2 P1 — jours, mesurable offline AVANT tout déploiement

**P1.1 Quantification int8 dynamique (ou fp16)**
Le plus gros levier brut (2–3× + 4× stockage). Protocole obligatoire :
export → `eval_error_detection.py` (détection erreurs + CER canonique) →
comparaison de la **distribution des gop** sur clips corrects (le zéro doit
rester ~zéro) → seuils retouchés seulement si dérive mesurée. Rollback trivial
(fichier .onnx par répertoire de modèle).

**P1.2 Rescoring par variantes confusables — le vrai fix du jugement**
Pour chaque mot aligné, générer les séquences de tokens des variantes
plausibles : paires confusables (`CONFUSABLE_PAIRS` : ص↔س, ط↔ت, ض↔د, ذ↔ز,
ح↔ه, ق↔ك, ع↔ء) + harakat alternatives aux positions vocalisées. Scorer chaque
variante **sur les mêmes frames** (DP locale minuscule, coût négligeable vs
ONNX) et rendre : `argmax + marge`.
- Signal **absolu** : « س bat ص de 2,1 nats sur tes frames » — plus de
  dépendance à un seuil relatif qui s'écrase quand le modèle hésite.
- Robuste au biais canonique résiduel : même un modèle biaisé départage
  souvent correctement deux variantes forcées tête-à-tête (observé : le
  transcript gardait bien ص dans `فَأَصَلْنَا`).
- Testable dès maintenant sur le holdout TTS annoté (`val_errors_annotated`,
  err_detail = vérité terrain par substitution) SANS toucher à l'app.
À terme, ce signal peut remplacer gop+similarity+spellsDifferentWord (3
heuristiques → 1 mesure), mais on le déploie d'abord EN PLUS, en ombre
(logué, pas encore décisionnel), pour comparer sur de vraies sessions.

**P1.3 Fenêtre glissante bornée** (si les longs segments restent fréquents)
Re-transcrire seulement la queue (5 s + 1 s d'overlap ignoré), coudre au texte
committé. Tue le terme quadratique. À valider offline : WER de la couture vs
re-transcription pleine sur 100 segments val.

**P1.4 VAD léger** (Silero VAD onnx, ~1 Mo, <1 ms/bloc) en garde de `feed()` :
le bruit n'entre plus ni dans le buffer ni dans le jugement ; la détection de
pause devient robuste (le RMS fixe est dépendant du micro/environnement).

### 4.3 P2 — prochain cycle d'entraînement : supprimer la cause, pas les symptômes

**P2.1 Stats de normalisation FIXES au prochain fine-tune.**
Une ligne de config NeMo (mean/std précalculés sur le corpus). Débloque le
mel incrémental **et** l'inférence par fenêtres sans dérive → la borne 12 s et
une partie de la machinerie de gel deviennent inutiles. Le fine-tune mixte
tournant déjà, c'est un ajout quasi gratuit au run suivant.

**P2.2 Fine-tune streaming cache-aware (convs causales).**
Déjà identifié (verdict 2026-07-04 : le checkpoint offline a des convs
non-causales, le chunking corrompt les frontières). C'est l'état final propre :
latence constante ~100–200 ms, **plus de segmentation du tout** → la classe
entière de bugs « mot frontière » (deferred/forceJudge/fragments/bleed)
disparaît structurellement. Le pipeline de données mixte + le harnais d'éval
construits aujourd'hui se réutilisent tels quels.

### Ce que je ne recommande PAS
- Réécrire l'aligneur ou le jugement de fond en comble avant P2 : les rustines
  actuelles compensent la segmentation ; les refondre pour ensuite supprimer la
  segmentation serait du travail jeté.
- Toucher aux scores gop bruts (pénalités, renormalisations) : trois tentatives
  documentées dans `ForcedAligner.kt` ont échoué pour une raison structurelle
  (journal des tentatives, à lire avant toute idée dans cette famille).

---

## 5. PLAN D'EXÉCUTION DÉTAILLÉ (pour agent exécutant — Sonnet)

**Règles générales (issues des mémoires projet, non négociables) :**
- Jamais réécrire un fichier entier de mémoire : partir du fichier réel, edits
  chirurgicaux, vérifier lignes/symboles après chaque sync avant tout build.
- Bumper `_kBuildTag` (diagnostic_log.dart) à CHAQUE changement de comportement ;
  vérifier `BUILD code=` dans le log device avant d'interpréter un test.
- Tout script Python qui transcrit : `model.change_decoding_strategy(decoder_type="ctc")`
  (la tête RNNT n'est jamais entraînée ici).
- Une piste invalidée se documente sur place avec sa raison, jamais supprimée.
- Vider `recitation_diagnostic.log` sur le device après chaque récupération.
- Build : scp vers `C:\coran_karim_build\app` puis
  `flutter.bat build apk --debug --dart-define=BUILD_TS=...` via ssh
  (clé `~/.ssh/id_ed25519_pcb`, hôte 100.126.49.93), install via adb du PC.

### Étape 1 — P0.1 ORT SessionOptions (½ journée)
1. `FastConformerCtc.kt` : construire `SessionOptions` avec
   `setIntraOpNumThreads(4)` (puis tester 2 et 6),
   `addConfigEntry("session.intra_op.allow_spinning","0")`,
   et tenter `addXnnpack(mapOf("intra_op_num_threads" to "4"))` dans un
   try/catch (fallback CPU par défaut si l'EP n'est pas dispo dans le paquet
   `onnxruntime-android` embarqué — vérifier la version dans build.gradle.kts).
2. Bench in-app : loguer la durée des passes (`retranscription Xs -> Yms`,
   déjà présent) sur la MÊME récitation Fatiha avant/après.
3. **Acceptation** : texte greedy identique sur la session de test ; durées ÷1,5
   minimum ; aucun changement des gop logués (>0,01 d'écart = investiguer).

### Étape 2 — P0.2 mel incrémental + FFT itérative (1 jour)
1. Nouvelle méthode `MelSpectrogram.computeIncremental(cache, pcmNouveau)` :
   conserver `logMel` par colonne (le buffer preémphasé + paddé aussi — attention
   la préemphasis dépend de l'échantillon précédent, conserver le dernier
   échantillon brut) ; ne calculer que les nouvelles frames ; re-normaliser
   toutes les colonnes à chaque appel (étape 5 actuelle, inchangée).
2. FFT itérative in-place (Cooley-Tukey bit-reversal), buffers membres réutilisés.
3. Test unitaire Kotlin (ou main() de debug) : pour 5 tailles de buffer
   aléatoires, `compute(pcm)` vs version incrémentale → **écart max 0 (bit-exact
   souhaité, sinon <1e-6)**. Ne PAS brancher dans BufferedTranscriber avant ça.
4. Brancher : `BufferedTranscriber` garde le cache, l'invalide sur reset()/gel.
5. **Acceptation** : mêmes transcriptions sur session test ; durée des passes
   1 s réduite (le mel est ~20–40 % du coût des petites passes).

### Étape 3 — P0.3 gel sans re-transcription (½ journée)
1. Dans le chemin `pendingCommit` (gel sur pause) : si
   `samples.size - lastPreviewSize < 0.3 * SAMPLE_RATE` et `latestText` non
   vide → réutiliser l'aperçu + son alignement comme au force-commit
   (code existant lignes ~341-382, à factoriser en une fonction commune).
2. **Acceptation** : log `segment FIGE (apercu reutilise)` sur gels rapides ;
   aucun changement de couleurs sur session test ; ~1 inférence de moins par
   segment dans le log.

### Étape 4 — P1.1 quantification (1–2 jours, OFFLINE d'abord)
1. `python -m onnxruntime.quantization.preprocess` puis `quantize_dynamic`
   (poids int8, activations fp32) sur `model.onnx` du meilleur checkpoint mixte.
2. Éval OFFLINE complète : `eval_error_detection.py` sur le .onnx quantifié
   (adapter le script pour charger un onnx au lieu d'un .nemo : réutiliser le
   wrapper mel→onnx de `benchmark/export_ckpt_to_onnx.py`, partie validation).
   Comparer : détection erreurs, CER canonique, et **histogramme des gop** sur
   50 clips corrects (µ et σ ; le pic à ~0 doit rester à ~0).
3. Si dérive gop ≤0,1 : déployer tel quel. Sinon recalibrer les 6 seuils
   proportionnellement et documenter dans recitation_provider.dart (bloc
   historique de calibrage, à ÉTENDRE, pas remplacer).
4. **Acceptation** : détection ≥ valeur fp32 −2 pts ; CER canonique ≤ +0,5 pt ;
   taille ~115 Mo ; passes ÷2 sur device.

### Étape 5 — P1.2 rescoring par variantes (2–3 jours, le plus important qualité)
1. **[FAIT, cf. §6.6] Offline d'abord** : script `benchmark/variant_rescoring_eval.py`
   (implémentation réelle : NLL CTC pleine séquence par candidat, pas de DP
   locale — les clips holdout sont des mots isolés, cf. docstring du script
   pour la justification). Résultat réel sur 1808 clips : **letter 80,8% (GO)**,
   **harakat 49,6% (NO-GO, quasi hasard)** — vérifié non-artefact de
   tokenisation. **Portée de la suite RESTREINTE aux paires `letter`
   (CONFUSABLE_PAIRS) : ne jamais étendre le verrouillage de verdict aux
   harakat, où ce signal n'est pas meilleur qu'un tirage au sort.**
2. Génération des variantes côté app : depuis `word_tokens.json` on n'a que le
   mot canonique → tokeniser les variantes via le greedy `CtcTokenizer`
   (repli déjà validé cohérent) OU précalculer un `word_variants.json` côté
   Python (préférable : même outil que word_tokens, vérité SentencePiece).
   Borne : ≤16 variantes/mot (paires confusables présentes + 1 harakat swap
   par position, plafonné).
3. Kotlin : dans `ForcedAligner`, après l'agrégation par mot, pour chaque mot
   couvert, scorer les variantes sur `[wordFirstFrame..wordLastFrame]`
   (DP contrainte début/fin de la plage — PAS de recherche partielle) ;
   joindre au payload : `variantBest`, `variantMargin`.
4. Dart : **mode ombre** — loguer `[VAR] mot=.. attendu=.. meilleur=..
   marge=..` sans toucher au verdict. Collecter ≥3 vraies sessions avec
   erreurs volontaires (sin/sad, harakat — protocole : réciter la Fatiha en
   substituant 1 mot sur 5, noter lesquels).
5. Si la précision en ombre confirme l'offline : brancher au verdict
   (variante ≠ attendu ET marge > seuil déterminé par la distribution ombre →
   jamais vert ; l'attendu gagne avec marge → autorise vert même si gop
   moyen). Retirer alors `spellsDifferentWord` (le documenter comme remplacé,
   pas supprimé silencieusement).
6. **Acceptation finale** : sur erreurs volontaires en session réelle, ≥8/10
   signalées orange/rouge ; sur récitation propre, 0 nouveau faux
   orange/rouge par rapport au build précédent (comparer les logs).

### Étape 6 — P1.4 VAD (1 jour, optionnel si Étape 5 suffit)
Silero VAD onnx en amont de `feed()` ; en dessous du seuil de parole, le bloc
ne rentre ni dans le buffer ni dans le RMS de pause (le silence de pause reste
compté). Acceptation : plus de retranscriptions de charabia sur bruit ambiant
seul (test : 30 s de bruit sans parler → 0 ligne `[GOP]`).

### Étape 7 — P2 (à lancer avec le PROCHAIN entraînement, pas avant)
1. Ajouter au config du prochain fine-tune : normalisation à stats fixes
   (calculer mean/std 80-dim sur le manifeste mixte via un script one-shot ;
   NeMo : `preprocessor.normalize: fixed_mean_std` + tensors). ⚠ jamais vu à
   l'entraînement par le checkpoint actuel — c'est un CHANGEMENT d'entraînement,
   pas un switch d'inférence.
2. Après convergence du mixte : fine-tune streaming
   (`fastconformer_hybrid_transducer_ctc_bpe_streaming.yaml`, convs causales,
   att_context chunked) depuis le meilleur checkpoint mixte, mêmes manifestes.
   Éval : eval_error_detection + val mixte, puis latence chunk sur device via
   `FastConformerStreamingSession.kt` (existant, jamais validé — le réactiver).
3. Une fois le streaming validé : dépréciation progressive de la machinerie de
   segmentation (gel/deferred/fragments) — grosse PR séparée, ne pas mélanger.

### Ordre recommandé et jalons de mesure
```
S1 : Étapes 1+2+3  → même qualité, passes ÷2-3        [mesure : durées log]
S1 : Étape 5.1     → Go/No-Go rescoring (offline pur)  [mesure : précision holdout]
S2 : Étape 4       → passes ÷2 encore, 115 Mo          [mesure : eval offline + gop hist]
S2 : Étapes 5.2-5.6→ jugement absolu                   [mesure : sessions ombre]
S3+: Étape 7       → suppression de la cause racine    [mesure : val mixte + device]
```
Chaque étape est indépendamment livrable et réversible ; ne JAMAIS empiler deux
étapes non validées dans le même APK (un seul changement par `_kBuildTag`).

---

## 6. Contre-revue (Sonnet, exécutant désigné) — à approuver ou contester

Relecture avant exécution, avec vérifications concrètes (pas juste un accord de
principe). Verdict global : le diagnostic tient, le plan est exécutable tel
quel, avec un chiffre à corriger et un risque à durcir avant l'Étape 7.

### 6.1 Confirmé par vérification directe du code
- `SessionOptions()` vide et mel recalculé à froid à chaque passe (§3.5.1/.4) :
  relu `FastConformerCtc.kt`/`MelSpectrogram.kt`, exact.
- `FastConformerStreamingSession.kt` (271 lignes) existe, corrige déjà 2 bugs
  (fenêtre de normalisation, causalité) mais **n'est appelé nulle part côté
  Dart** (`loadStreamingModel`/`feedAudioChunk` définis, jamais invoqués par un
  écran) — code mort aujourd'hui, cohérent avec le verdict 2026-07-04 cité en
  P2.2. Confirme la recommandation, pas de contradiction.

### 6.2 À corriger — le chiffre de redondance (§2) est un pire cas, pas la norme
Distribution réelle des durées de segment sur les logs du jour (141 segments,
toutes sessions confondues) :
```
  62× 3s   38× 2s   24× 4s   11× 5s   qq. 6-9s   1× 12s
```
88 % des segments durent 2–4 s. Recalcul pour ces tailles (passes tous les
1,5 s + re-transcription complète au gel) :
```
  2s → compute ≈ 3,5s → ×1,75      3s → compute ≈ 4,5s → ×1,5
  4s → compute ≈ 8,5s → ×2,1
```
Le ×4,5 cité est réel mais concerne le SEUL segment à 12 s observé aujourd'hui
(1/141). Le régime typique est **×1,5–2,1**, pas ×2,5–4,5. Ne change ni le
diagnostic (le calcul redondant existe bel et bien) ni la priorité de l'Étape 3
(qui cible justement le terme dominant du cas typique — le gel qui re-transcrit
un segment déjà couvert par l'aperçu) — seulement l'ampleur annoncée. À corriger
dans §2 pour ne pas sur-vendre le gain attendu de P0.3.

### 6.3 Risque à durcir — P2.1 (stats de normalisation fixes)
Décrit comme « ajout quasi gratuit au run suivant ». Réserve : le fine-tune
mixte en cours **continue depuis un checkpoint déjà entraîné en normalisation
`per_feature`** — changer la statistique de normalisation change la
distribution des entrées vues par l'encodeur, ce n'est pas un simple
toggle de config au milieu d'une continuation. Proposition : traiter P2.1
comme nécessitant soit (a) un warm-restart dédié depuis le checkpoint mixte
validé, avec surveillance du WER canonique sur les 1-2 premières epochs pour
détecter une dérive, soit (b) le combiner directement avec P2.2 (streaming)
qui de toute façon repart d'un fine-tune séparé — (b) est probablement le bon
choix, ça évite un cycle d'entraînement intermédiaire pour rien.

### 6.4 Sur les seuils d'acceptation
« >75 % » (Étape 5.1) et « ≥8/10 » (Étape 5.6) sont des points de départ
raisonnables mais arbitraires, pas des cibles dérivées de données. À traiter
comme tels pendant l'exécution : si l'offline sort par exemple 68 %, ce n'est
pas un échec binaire, c'est un signal à examiner (par type d'erreur, par
position dans le mot) avant de décider d'arrêter ou d'ajuster.

### 6.5 Approbation demandée
Sous réserve des points 6.2 (chiffre à corriger, pas de changement de plan) et
6.3 (P2.1 à fusionner avec P2.2 plutôt qu'exécuté seul), le plan est approuvé
pour exécution dans l'ordre proposé. Prochaine action : Étape 5.1 (Go/No-Go
rescoring, offline, zéro risque) en parallèle des Étapes 1-3 (perf, zéro
risque qualité) — développée ci-dessous.

### 6.6 Étape 5.1 EXÉCUTÉE — résultat réel, split par type d'erreur

Script : `benchmark/variant_rescoring_eval.py`. Comparaison tête-à-tête
NLL(prononcé) vs NLL(canonique) via `torch.nn.functional.ctc_loss`, sur les
1808 clips fautifs du holdout TTS (`val_errors_annotated.jsonl`), modèle
`mixed-e02-144-snapshot.nemo` (celui déployé aujourd'hui). Incident en cours de
route : la 1ère exécution a silencieusement sauté les 1808/1808 lignes (refus
strict sur un sample rate ≠16kHz -- les clips TTS/XTTS sont en 24kHz natif) et
sorti un faux "NO-GO 0.0%". Corrigé (rééchantillonnage explicite via librosa) et
re-vérifié sur 5 clips avant de relancer le run complet.

```
type       n     gagne     %      marge médiane
letter    854     690    80.8%      +3.80
harakat   954     473    49.6%      -0.10
------------------------------------------------
TOTAL    1808    1163    64.3%
cibles infaisables : 0
```

Contrôle fait avant de conclure : les 954 clips `harakat` ont bien des séquences
de tokens BPE DIFFÉRENTES entre prononcé et canonique (0% de collision) --
le résultat n'est pas un artefact de tokenisation, c'est une vraie limite
acoustique du signal.

**Interprétation :**
- **`letter` (ص↔س, ط↔ت, etc.) : GO net, 80,8%.** Le rescoring règle exactement
  le problème diagnostiqué ce jour même (sin/sad à gop=-0.35, jugé vert par le
  score relatif). Une substitution de lettre a une signature spectrale assez
  large pour qu'une comparaison directe tranche.
- **`harakat` : NO-GO, quasi pile-ou-face (49,6%, marge médiane ~0).** Une
  harakat (voyelle brève, 1-3 frames) ne porte pas assez de signal pour
  qu'une comparaison CTC tête-à-tête discrimine -- ni mieux ni pire que le
  hasard. Le rescoring N'EST PAS la solution aux harakat ; ni lui ni le gop
  actuel ne les couvrent bien. Piste à explorer séparément si prioritaire :
  comparaison directement sur les logprobs de la frame de la voyelle plutôt
  que sur un NLL de séquence entière (le CTC dilue le signal court sur le
  chemin complet) -- non testé ici, hors du périmètre P1.2 initial.

**Révision de l'Étape 5 (§5, plan initial) :** le déploiement en mode ombre
(5.2-5.6) est justifié pour `letter` seulement -- généraliser à `harakat`
donnerait un signal aussi peu fiable qu'un tirage au sort et NE DOIT PAS
remplacer le gop pour ce cas. Design révisé : le rescoring vient EN PLUS du
gop, pas à sa place ; il ne verrouille un verdict que pour les paires
`CONFUSABLE_PAIRS` (lettres), le gop garde la main sur tout le reste
(y compris les harakat, où il reste, avec ses limites connues, le seul signal
disponible pour l'instant).
