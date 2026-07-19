# "Suivre une prière" — journal de développement (pour revue Fable)

Ce document récapitule la conception, les bugs trouvés et les correctifs
appliqués pour la fonctionnalité "Suivre une prière" (`prayer_follow_screen.dart`),
développée le 2026-07-18/19. Objectif de ce fichier : donner à un autre modèle
(Fable) tout le contexte nécessaire pour évaluer la solution actuelle et
proposer des pistes, sans avoir à rejouer toute la conversation.

**Statut au moment de l'écriture** : implémenté, partiellement testé en
conditions réelles (mosquée), plusieurs bugs trouvés et corrigés sur la base
de logs device réels. Pas encore de test de bout en bout confirmant que tous
les correctifs combinés résolvent le problème. Plusieurs questions ouvertes
en fin de document.

---

## 1. Objectif de la fonctionnalité

L'app "Coran Karim" vérifie déjà une récitation mot par mot en la comparant à
un texte CONNU À L'AVANCE (mode "karaoké" classique, sourate choisie sur
l'écran de lecture). "Suivre une prière" répond à un cas d'usage différent :
un imam qui mène la salât, sans choisir de sourate au préalable.

Contraintes propres à ce cas :
- Après chaque takbir de lever (rak'ah), l'imam récite Al-Fatiha, PUIS une
  sourate/passage de son choix — qui peut différer d'une rak'ah à l'autre.
  Rien n'est donc connu à l'avance après Al-Fatiha : il faut l'identifier à
  la volée (même moteur que "Shazam coranique",
  `quran_verse_locator_service.dart`).
- "الله أكبر" (takbir) est dit PLUSIEURS FOIS par rak'ah (lever, chaque
  changement de position rukū'/sujūd), pas seulement au moment de reprendre
  la récitation. Impossible de distinguer ces occurrences entre elles par
  leur seul son.
- Le récitateur est "maître" : l'app doit suivre sa position réelle et se
  resynchroniser si elle décroche, jamais bloquer/forcer une correction
  (mode confiant : aucune erreur ne bloque, cf. `_confidentMode`).

## 2. Architecture actuelle

### 2.1 Machine à états `PrayerPhase` (`app/lib/models/recitation_state.dart`)

```
none            -- hors cycle de prière (comportement karaoké classique inchangé)
standby         -- en attente de reconnaître le DÉBUT d'Al-Fatiha (texte, pas takbir)
fatiha          -- Al-Fatiha en cours de suivi/correction
detectingTarget -- Al-Fatiha finie, sourate suivante pas encore identifiée (Shazam)
target          -- sourate identifiée, en cours de suivi/correction
```

Transitions :
- Un takbir détecté (`_hasTakbir`, présence de "الله" + un mot
  égal/terminant par "أكبر", n'importe où dans le texte) → `standby`,
  **quelle que soit la phase courante** (interrompt tout).
- En `standby`, dès que le début d'Al-Fatiha est reconnu dans le texte
  (`_looksLikeFatihaStart`) → `fatiha`.
- En `fatiha`, dès que la fin est reconnue dans le texte
  (`_looksLikeFatihaEnd`, présence de "الضالين") → `detectingTarget` (mode
  "Suivre une prière") ou directement `target` avec la sourate déjà connue
  (ancien flux karaoké avec toggle, aujourd'hui retiré).
- En `detectingTarget`, dès qu'un match Shazam suffisamment confiant est
  trouvé → `target`.
- En `target`, à la fin normale (pointeur au bout) → retour `standby`.

**Important** : les transitions de fin de phase (fin d'Al-Fatiha, sourate
suivante) sont détectées par le TEXTE reconnu, PAS par le pointeur
d'alignement forcé GOP (`_onAligned`/`state.pointer`) — voir §3.4, c'est un
bug corrigé, le pointeur GOP peut rester bloqué très en retard.

### 2.2 Fichiers clés

- `app/lib/providers/recitation_provider.dart` — toute la logique
  (`RecitationNotifier`). Méthodes principales :
  - `startPrayerFollow()` — point d'entrée, démarre en `standby`, cible VIDE
    (pas de sourate pré-chargée).
  - `_enterPrayerStandby()`, `_beginFatihaPhase()`, `_beginTargetDetection()`,
    `_beginIdentifiedTargetPhase(QuranMatch)`, `_beginTargetPhase()` (ancien
    flux, sourate pré-chargée) — transitions de phase.
  - `_maybeResyncPosition({probe, surahNumber, verses})` — resynchronisation
    continue (§3.5).
  - `verseAndLocalIndexFor(int wordIndex)` — mappe un index de mot absolu
    vers `(Verse, indexLocal)`, utilisé par le souffleur.
  - `_onStructured`/`_onAligned` — callbacks du flux ASR natif (texte figé/
    aperçu, et alignement forcé GOP respectivement).
- `app/lib/services/quran_verse_locator_service.dart` — `QuranVerseLocatorService`,
  moteur de localisation ("Shazam coranique"). Index mot→versets
  (`Map<String, List<int>>`), filtre les mots trop fréquents (>400
  occurrences), scoring par recouvrement ordonné, seuil générique 0.45,
  minimum 2 mots.
- `app/lib/screens/prayer_follow_screen.dart` — écran dédié, réglages
  indépendants (sensibilité + souffleur, §3.7).
- `app/android/.../fastconformer/BufferedTranscriber.kt` /
  `ForcedAligner.kt` — moteur natif (streaming re-transcrit + alignement
  forcé GOP). Buffer audio par segment borné (12s max, gel sur pause
  ~450ms) — PAS de croissance illimitée contrairement à une hypothèse
  initiale (voir §3.4).

## 3. Historique chronologique des bugs et correctifs

### 3.1 Détection du takbir retardée (~13s)

**Symptôme (log device)** : "ٱللَّهُ ٱللَّهُ أَكْبَرُ" reconnu dès la 1ère
passe mais resté en APERÇU pur (jamais figé) pendant ~13s / 11 passes avant
détection.

**Cause** : la détection ne scrutait que le texte FIGÉ (`committed`), jamais
l'aperçu (`preview`) — l'ASR ne fige un segment que sur un déclencheur externe
(silence, phrase suivante), pas juste parce que le contenu est stable.

**Fix** : scruter aussi `preview`, avec un verrou `_takbirArmed` (réarmé
quand l'aperçu redevient vide) pour ne déclencher qu'une fois par occurrence.

### 3.2 Reset du takbir sans effet réel

**Symptôme (log device)** : juste après "[Takbir] détecté", le natif a
continué à juger mot=17→18→19→20 (mots de la sourate D'AVANT le takbir)
pendant que l'utilisateur récitait déjà autre chose.

**Cause** : `resetTrackingToStart()` ne remettait à zéro QUE l'état Dart
(`_anchorExp`, `state.pointer`) — jamais l'ancre NATIVE
(`ForcedAligner.kt`), qui écrase `_anchorExp` à chaque passe suivante
(`_onAligned` : `if (trueExtent > _anchorExp) _anchorExp = trueExtent`).

**Fix** : appeler `_verifier.setAlignmentAnchor(0)` en plus du reset Dart.

### 3.3 Prise de conscience : le takbir seul ne suffit pas

Retour utilisateur : une salât dit "الله أكبر" plusieurs fois par rak'ah
(rukū', sujūd), pas seulement pour reprendre la récitation — impossible de
distinguer ces occurrences par leur son. **Conséquence architecturale** :
refonte complète en machine à états `PrayerPhase` (§2.1) — TOUT takbir
renvoie en `standby` (pas de jugement), seule la RECONNAISSANCE EFFECTIVE
du texte d'Al-Fatiha fait avancer vers `fatiha`.

### 3.4 Le pointeur GOP prend un retard croissant sur le flux réel

**Symptôme (log device)** : Al-Fatiha reconnue à T+0s ; mot=0 jugé à T+9s ;
mot=4 jugé à T+40s — alors que le texte FIGÉ montrait Al-Fatiha ENTIÈREMENT
récitée dès T+26s, et même la sourate suivante déjà commencée en aperçu à
T+36s.

**Hypothèse initiale (INVALIDÉE)** : buffer audio natif qui grandirait sans
borne, ralentissant chaque passe. Vérifiée FAUSSE en lisant
`BufferedTranscriber.kt` : le buffer est bien tronqué à chaque segment figé
(`MAX_SEGMENT_SECONDS=12s`, gel sur pause ~450ms, `MIN_COMMIT_SECONDS=2.5s`).
Donc PAS un problème de taille de buffer.

**Cause réelle non totalement élucidée** : en comparant les logs
"alignement seq=N ... mots=X" (émis par `runAlignment` dans
`BufferedTranscriber.kt`), un segment figé de plusieurs mots (ex. "مَـٰلِكِ
يَوْمِ ٱلدِّينِ", 3 mots) ne fait souvent avancer l'ancre que de 0 ou 1 mot
par appel — le mécanisme `deferredOnceIndex`/"2 chances max"
(`ForcedAligner.MIN_FRAMES_FOR_JUDGMENT`, cf. commentaires 2026-07-14 dans
le code) semble reporter le jugement de la plupart des mots au lieu de les
juger tous d'un coup. **Piste non creusée en profondeur** : lire
`ForcedAligner.align()` (le fichier Kotlin lui-même, pas seulement les
logs) pour comprendre pourquoi si peu de mots sont verrouillés par passe.

**Fix appliqué (contournement, pas une correction du natif)** : détecter la
fin d'Al-Fatiha par le TEXTE reconnu (`_looksLikeFatihaEnd`, présence du mot
"الضالين") plutôt que par `pointer >= words.length`. Le jugement mot-à-mot
continue de tourner en arrière-plan (utile pour la coloration/correction)
mais la PROGRESSION DE PHASE n'en dépend plus.

### 3.5 Pivot : plus de sourate pré-sélectionnée

Retour utilisateur : "on va dans une sourate puis on récite, ce n'est pas
adéquat... il vaut mieux utiliser Shazam pour détecter où commence la
sourate après Fatiha". Décision (confirmée via question posée à
l'utilisateur) : nouveau point d'entrée `startPrayerFollow()`, SANS aucune
sourate pré-chargée. La sourate qui suit Al-Fatiha est identifiée à la volée
via `QuranVerseLocatorService`, à CHAQUE rak'ah (peut différer).

Conséquence : `_onAligned`/`_onStructured` ont dû tolérer `state.words`
VIDE pendant `standby`/`detectingTarget` (avant, un garde-fou
`if (state.words.isEmpty) return` supposait une cible toujours pré-chargée).
`_startStreamingCapture` (recitation_verifier.dart) a aussi dû être corrigé
pour ne PAS dégrader la transcription libre quand la cible est vide au
départ (même bug déjà connu pour "Shazam coranique" en mode segment
unique) — `alignmentActive` signifie maintenant "moteur prêt", pas "cible
fixée".

### 3.6 Ambiguïté structurelle de la Bismillah

**Symptôme (log device)** : "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ" → Shazam répond
"1:1" (Al-Fatiha elle-même) avec confiance **1.000**, alors que l'utilisateur
enchaînait sur une AUTRE sourate.

**Cause** : la formule d'ouverture "بسم الله الرحمن الرحيم", récitée devant
CHAQUE sourate par convention, est identique mot pour mot à Al-Fatiha 1:1 —
et c'est la SEULE entrée de l'index qui la contient réellement comme verset
(les autres sourates ne l'ont pas dans leur texte indexé côté
`api.quran.com`, elle est rejouée séparément à l'affichage, cf.
`QuranApi.fetchBismillah`). Tant que seule la bismillah a été entendue,
match garanti sur 1:1.

**Fix (double garde-fou)** :
1. `_stripBismillahPrefix` — retire la formule du DÉBUT du texte avant
   recherche (tolère un peu de bruit avant elle, cf. §3.7) ; retourne `null`
   si une formule incomplète se termine pile en fin de texte connu (attendre
   la suite plutôt que chercher sur du contenu tronqué).
2. Garde-fou explicite : tout match `surahNumber == 1` pendant
   `detectingTarget` est REJETÉ (log + nouvelle tentative), quel que soit le
   score — à ce moment précis, ça ne peut être que la bismillah ou la fin
   d'Al-Fatiha encore présente dans la fenêtre récente (jamais la vraie
   sourate suivante).

### 3.7 Détecteurs trop stricts sur la POSITION (bruit de mosquée réel)

**Symptôme (log device, test en conditions réelles de mosquée)** : ~20s de
texte fortement halluciné par l'ASR (shahada répétée de façon déformée,
probable écho/réverbération) AVANT que "بسم الله" n'apparaisse enfin —
jamais en position 0/1 du texte scruté. Session restée bloquée en `standby`
indéfiniment malgré Al-Fatiha bel et bien récitée.

**Cause** : `_looksLikeFatihaStart` ne comparait que les 2 PREMIERS mots du
texte scruté à la paire ("بسم","الله")/("الحمد","لله").

**Fix** : cherche la paire N'IMPORTE OÙ dans la liste de tokens, pas
seulement en position 0/1. Même traitement appliqué à `_stripBismillahPrefix`
(cherche la formule à partir de n'importe laquelle des 10 premières
positions, pas strictement en tout début).

### 3.8 Fenêtre de recherche : cumul illimité → micro-fenêtre glissante

Retour utilisateur (reformulant le principe voulu) : "la logique pour moi
c'est de lancer des micro écoutes 3-4 mots, si ça ne correspond pas on
refait, jusqu'à ce qu'on tombe sur le verset qui correspond, et on
enchaîne."

**Avant** : les probes envoyées à `locate()` étaient le texte CUMULÉ depuis
le début de la phase (`_targetDetectScanStart`, `_fatihaScanStart`,
`_targetTrackingScanStart`) — grossissant sans borne sur une longue sourate.

**Fix** : `_lastWords(text, n)` — ne garde que les [n] DERNIERS mots avant
recherche. `_kRecentWindowWords = 15` (pas 3-4 littéralement : une fenêtre
trop courte peut tomber pile à cheval entre la fin de la bismillah et le
début du vrai verset, coupant le contenu utile en deux — 15 mots laisse de
la marge tout en restant une fenêtre récente, pas un texte qui traîne).
Toujours recalculée à chaque nouveau texte reconnu : un essai raté est
"oublié" naturellement.

### 3.9 Rattrapage continu du pointeur GOP (compense §3.4)

Constat : même après 3.4, le jugement mot-à-mot (coloration, silence-hint)
reste utile mais lent/en retard PENDANT la phase (pas seulement à sa fin).

**Solution ajoutée** : `_maybeResyncPosition` — pendant `fatiha`/`target`,
relance PÉRIODIQUEMENT `locate()` sur la micro-fenêtre récente (§3.8). Si un
match confiant retrouve une position PLUS AVANCÉE que l'ancre actuelle
**dans la même sourate**, l'ancre est rattrapée directement (mots sautés
entre les deux marqués `skipped`, jamais jugés faux) — jamais en arrière,
jamais vers une autre sourate. `setAlignmentAnchor()` natif mis à jour en
conséquence.

### 3.10 Faux rattrapage par confiance trop faible (bug le plus grave trouvé)

**Symptôme (log device, confirmé en direct)** :
```
[Prière] sourate identifiée : 2:277 (confiance 0.50) -- suivi actif dès le mot 5775/6117
```
Un match à 0.50 (à peine au-dessus du seuil générique 0.45 de
`QuranVerseLocatorService`, calibré pour "Shazam coranique" — un geste
explicite et ponctuel de l'utilisateur) a verrouillé tout le suivi sur le
verset 277 d'Al-Baqarah (sur 286 versets), sans rapport avec ce qui était
réellement récité. Correspond exactement à la plainte utilisateur : "je
récite ayat 5... il y a le même mot ou deux dans ayat 15, ça active la 15."

**Fix (double garde-fou, appliqué à l'identification ET à la
resynchronisation continue)** :
1. `_kMinIdentifyConfidence = 0.70` — seuil dédié, bien plus strict que le
   seuil générique du service partagé.
2. `_kMaxPlausibleWordsPerSecond = 4.0` — garde-fou de plausibilité
   temporelle : `_lastAnchorAdvanceAt` (horodatage du dernier avancement
   CONFIRMÉ de l'ancre, mis à jour à chaque jugement GOP normal ET à chaque
   rattrapage accepté) permet de calculer combien de mots il est
   PHYSIQUEMENT possible d'avoir récités depuis ce moment. Un saut/une
   identification qui dépasse ce plafond est rejeté, quelle que soit sa
   confiance.

**Pas encore retesté en conditions réelles après ce fix.**

### 3.11 Retrait de l'ancien toggle "Réciteur confiant"

Toute la logique de cycle de prière vivait initialement dans le karaoké
classique (toggle réglages + sourate pré-sélectionnée). Une fois le nouveau
point d'entrée dédié confirmé (§3.5), ce toggle — devenu redondant/moins
adapté — a été entièrement retiré : `confidentReciterModeProvider` (et sa
notion `ConfidentReciterModeNotifier`) supprimés de
`app_settings_provider.dart`/`settings_screen.dart`, wiring retiré de
`karaoke_recitation_screen.dart` (souffleur automatique, blocage
désactivable, `ref.listen`). `RecitationNotifier._confidentMode` reste en
interne, mais n'est plus positionné QUE par `startPrayerFollow()`.

### 3.12 Réglages indépendants + souffleur sur le nouvel écran

Demande utilisateur : sensibilité de jugement propre à cet écran
(`prayerSensitivityProvider`, séparé de `correctionSensitivityProvider` du
karaoké classique — ajuster l'un ne doit jamais changer l'autre), plus un
réglage pour le souffleur automatique. Ajoutés :
- `prayerSensitivityProvider` (double, 0.5 par défaut) + feuille de réglage
  sur `PrayerFollowScreen` (icône ⚙, mêmes libellés Tolérant/Strict que le
  karaoké classique).
- `prayerSouffleurEnabledProvider` (bool, activé par défaut) + mécanisme du
  souffleur LUI-MÊME implémenté pour la première fois sur cet écran (il
  n'existait qu'auparavant sur le karaoké classique, retiré avec le toggle
  §3.11, jamais porté vers le nouvel écran avant cette étape) : `Timer` 6s
  de silence → joue l'extrait audio du mot attendu
  (`WordCorrectionAudio.playWordRange`), via `verseAndLocalIndexFor` pour
  retrouver le verset réel derrière le pointeur (Al-Fatiha ou sourate
  identifiée). Suspendu pendant `standby`/`detectingTarget` (pas de "mot
  courant" légitime à ce moment).

**Pas encore testé en conditions réelles.**

### 3.13 Délai du souffleur réduit (6s → 3s)

Demande utilisateur directe. Justification : dans ce mode, le pointeur peut
déjà être en retard sur ce qui est réellement récité (§3.4/§3.9) — un délai
plus court aide à proposer de l'aide plus tôt plutôt que de laisser un long
silence avant la première intervention.

### 3.14 Continuité entre rak'ah (répond à la question ouverte §4.2 d'origine)

Confirmation utilisateur explicite : "dans la deuxième rak'ah normalement
après Fatiha, s'il n'entend rien, il doit me proposer ce que je lisais
avant, la continuité." Une sourate longue peut être répartie sur plusieurs
rak'ah — si rien n'est identifié après un délai de silence, il faut
supposer que l'imam continue la MÊME sourate plutôt que d'attendre
indéfiniment une nouvelle identification.

**Implémentation** :
- `_lastTargetSurahForContinuation`/`_lastTargetAnchorForContinuation` --
  mémorisés à chaque sortie de `PrayerPhase.target` (fin normale OU
  interruption par un takbir de rukū'/sujūd en plein milieu), dans
  `_enterPrayerStandby()`. Jamais effacés ailleurs, donc toujours la
  DERNIÈRE position atteinte.
- `_armDetectingTargetFallbackTimer()` -- minuteur de 5s, armé à l'entrée en
  `detectingTarget` et RÉARMÉ tant que du texte NOUVEAU arrive (comparaison
  de la micro-fenêtre `rawProbe` avant/après, cf. §3.8) -- ne se déclenche
  donc que sur un silence réellement prolongé, jamais pendant une
  identification lente mais toujours en cours (ex. §4.3, ouverture par
  lettres disjointes mal transcrite : il ne faut pas interrompre cette
  tentative légitime au profit d'une reprise de continuité prématurée).
- `_resumeContinuationIfAvailable()` -- au déclenchement, reconstruit la
  liste de mots de la sourate mémorisée (déjà en cache, `_currentTargetVerses`)
  et reprend EXACTEMENT à l'ancre où la rak'ah précédente s'était arrêtée
  (pas depuis le début) ; no-op silencieux si aucune rak'ah précédente
  n'existe encore (1er cycle de la session).

**Pas encore testé en conditions réelles.**

### 3.15 Défilement automatique vers le mot courant

`_WordsArea` n'avait aucun mécanisme de scroll -- au-delà de l'écran, le
mot courant sortait du cadre visible sans que la vue ne suive ("le texte
reste figé"). Ajouté : une `GlobalKey` par mot (reconstruites à chaque
changement de longueur de la liste, i.e. à chaque bascule de phase) +
`Scrollable.ensureVisible` sur le mot courant à chaque avancée du pointeur
-- même principe que `karaoke_recitation_screen.dart`/`mushaf_screen.dart`.

### 3.16 Pointeur en retard visuel sur la coloration réelle (§3.4/§3.9)

**Symptôme (log device, "2ème rak'ah")** : les mots 25 à 36 d'Al-Ahzab ont
bien reçu un statut GOP correct au fil de plusieurs passes -- correspondant
exactement à ce qui était récité -- mais l'utilisateur a perçu l'écran comme
"resté bloqué". **Cause** : `pointer` n'avançait, sur une passe NON finale,
que jusqu'à `p.frontier` (valeur native prudente) -- alors que des mots
au-delà de ce frontier avaient déjà reçu un statut individuel (`r.covered`)
dans la MÊME passe. Le marqueur "mot courant"/le défilement automatique
(§3.15) suivait donc `pointer`, pas la coloration réelle, et paraissait figé
même quand le jugement progressait.

**Fix** : `coveredExtent` (non-final) = `max(p.frontier, plus_haut_index_jugé_cette_passe + 1)`
-- le pointeur peut désormais avancer jusqu'au dernier mot réellement jugé
dans la passe courante, pas seulement jusqu'à ce que le natif appelle
"frontier". Ne touche pas au verrouillage/à l'ancre (toujours gouvernés par
`p.isFinal` séparément) -- seulement à ce que l'UI considère "atteint".

### 3.17 Pas de correction affichée pendant Al-Fatiha

Demande utilisateur directe : "je ne veux pas de correction dans la
récitation de Al-Hamdo [Al-Fatiha], elle est très connue et rare, les
erreurs dans cette sourate c'est juste du bruit." Al-Fatiha étant récitée
des dizaines de fois par jour, une vraie erreur de prononciation y est
rarissime -- un rouge/orange dessus reflète presque toujours du bruit ASR
(écho/réverbération de mosquée, segmentation), pas une vraie faute.

**Fix** : dans `_onAligned`, si `state.prayerPhase == PrayerPhase.fatiha`,
le statut est forcé à `WordStatus.correct` inconditionnellement, AVANT même
d'évaluer le gop/la similarité textuelle. Le suivi de POSITION (avancement
de l'ancre, nécessaire pour la bascule de phase) n'est pas affecté --
seul l'affichage rouge/orange est supprimé pour cette phase.

### 3.18 Filtrage "mots sûrs / mots douteux" pour l'identification

Retour utilisateur (comparant au scoring actuel, jugé pas assez fiable) :
"avec une boucle, si on trouve pas il recommence en gardant les mots sûrs
et enlève les mots avec doute." Constat à l'origine : les derniers mots
d'un aperçu (`preview`) peuvent encore changer d'une passe de
re-transcription à l'autre (log réel : "اهدنااصراط" légèrement différent
d'un appel au suivant) -- les inclure tels quels dans la recherche Shazam
pollue la requête avec du contenu pas encore stabilisé.

**Fix** (ancienne fenêtre glissante brute gardée en COMMENTAIRE dans le
code, juste au-dessus, à la demande de l'utilisateur -- pas supprimée) :
`_stablePreviewPrefix(preview)` -- ne garde que le plus long préfixe de
l'aperçu resté IDENTIQUE, à la même position, entre deux passes
consécutives ; le reste ("douteux", encore en train de changer) est
tronqué avant recherche. Le texte déjà FIGÉ (`committed`) reste toujours
considéré "sûr" par construction (jamais réévalué). Coût : au plus un cycle
de re-transcription (~1,5-3s) de latence supplémentaire sur le tout
dernier mot, en échange de ne jamais soumettre à la recherche un mot
encore à moitié décodé.

**Alternative envisagée et écartée pour l'instant** (discutée avec
l'utilisateur) : recherche séquentielle façon arbre/trie (intersection
progressive mot après mot, en respectant l'ordre, plutôt que comptage de
mots communs suivi d'un score de fenêtre). Jugée plus robuste en théorie
mais plus coûteuse à construire (nécessite un index positionnel, pas
seulement mot→liste de versets) et risquée pour "Shazam coranique" (service
partagé, qui fonctionne bien aujourd'hui) -- reportée sauf nouvelle preuve
que le seuil de confiance 0.70 (§3.10) ne suffit pas.

**Pas encore testé en conditions réelles.**

### 3.19 Pas de repli sur le candidat suivant + recherches redondantes + fenêtre trop courte

**Symptôme (log device, confirmé en direct)** : requête "ما جعل الله"
(véritable ouverture d'Al-Ahzab 33:4) matchait systématiquement "50:26"
(Qaf, score élevé) — rejeté à raison par le garde-fou de plausibilité
temporelle (§3.10), mais **aucune identification n'aboutissait jamais**,
alors que l'utilisateur avait bel et bien récité tout le verset. Retour
utilisateur : "pourquoi ça s'arrête juste sur 'ma ja3ala Allah' alors que
j'ai dit toute la verset, est-ce qu'il ne récupère que 3-4 mots et oublie
les autres ?" Deux autres symptômes remontés en parallèle sur le même log :
répétition de recherches identiques ("ma ja3ala allah se répète plusieurs
fois !!") et refus explicite de la fenêtre glissante bornée introduite en
§3.8 pour CETTE phase précise ("non il doit prendre en continu... pour
vérifier").

**Causes (trois, cumulées)** :
1. `locate()` ne renvoyait QUE le meilleur candidat. Si celui-ci échouait un
   garde-fou (ici la plausibilité), aucun mécanisme n'existait pour essayer
   le suivant — alors même que le bon verset (33:4) était probablement
   parmi les candidats scorés, juste pas en première position.
2. `_onStructured` relançait une recherche à CHAQUE appel (~80-100ms par
   chunk PCM), y compris quand la micro-fenêtre de texte n'avait pas changé
   depuis la recherche précédente — gaspillage pur, et bruit dans les logs
   masquant les vrais changements.
3. La fenêtre glissante bornée à 15 mots (`_kRecentWindowWords`, §3.8),
   pensée pour `fatiha`/`target` (phases pouvant durer longtemps), privait
   `detectingTarget` — phase courte par nature — du contexte disambiguant
   supplémentaire qu'un verset plus long aurait pu apporter.

**Fix (trois volets, tous dans `recitation_provider.dart` +
`quran_verse_locator_service.dart`)** :
1. `quran_verse_locator_service.dart` : logique de scoring extraite dans
   `_rankCandidates()` (partagée), renvoyant TOUS les candidats triés par
   score décroissant. `locate()` garde EXACTEMENT son comportement externe
   d'origine (meilleur seul, seuil 0.45) pour ne rien changer à "Shazam
   coranique". Nouvelle méthode `locateTopMatches(heardText, {k=5,
   minScore=0.45})` qui renvoie jusqu'à `k` candidats au-dessus du seuil.
2. `recitation_provider.dart` : `_beginIdentifiedTargetPhase` retourne
   maintenant `Future<bool>` (true = verrouillé, false = rejeté par
   n'importe quel garde-fou y compris la plausibilité) au lieu de
   `Future<void>`. Nouvelle méthode `_tryIdentifyTarget(probe)` qui appelle
   `locateTopMatches`, puis essaie chaque candidat DANS L'ORDRE (en
   sautant tout `surahNumber == 1` et tout score `< _kMinIdentifyConfidence`
   comme avant, §3.6/§3.10) jusqu'à ce qu'un candidat soit accepté ou que la
   liste soit épuisée — remplace l'ancienne chaîne `.then()` à essai unique.
3. Dans `_onStructured`, branche `detectingTarget` : (a) la recherche n'est
   dispatchée QUE si `rawProbe != _lastDetectingTargetProbe` (le texte de la
   micro-fenêtre a réellement changé depuis la dernière fois) — corrige le
   gaspillage de recherches identiques ; (b) le plafond
   `_kRecentWindowWords` est RETIRÉ spécifiquement pour cette probe (le
   texte "sûr" + préfixe stable de l'aperçu, §3.18, s'accumule maintenant
   SANS plafond tant que la phase `detectingTarget` dure) — gardé
   intentionnellement pour les probes de resynchronisation `fatiha`/`target`
   (§3.8, ces phases peuvent durer longtemps, un cumul illimité y serait
   coûteux et inutile). L'ancienne construction bornée est gardée en
   COMMENTAIRE juste au-dessus (même convention que §3.18), pas supprimée.

**Build validé (`flutter analyze` propre, `flutter build apk --debug`
réussi) et installé sur device (2026-07-19). Pas encore retesté en
conditions réelles après ce fix précis.**

### 3.20 Garde-fou de plausibilité temporelle bugué : bloquait le VRAI verset

**Symptôme (log device, test complet)** : Shazam retrouve "33:30" (Al-Ahzab,
confiance 0.87) puis "33:29" (0.81) de façon STABLE sur plus de 10 secondes
(8+ passes consécutives, 09:37:57 à 09:38:08, confiance restant entre 0.61 et
0.87) — signature claire d'un vrai match, pas d'une coïncidence. Pourtant
**chaque tentative rejetée**, indéfiniment (capture de log arrêtée avant toute
résolution) :
```
[Prière] candidat 33:30 rejeté : ancre 503 invraisemblable (max plausible 137 mots en 34112ms depuis la fin d'Al-Fatiha)
```

**Cause** : `_beginIdentifiedTargetPhase` (garde-fou introduit en §3.10)
comparait l'ancre PROPOSÉE (position absolue du verset 29/30 dans la liste de
mots de la sourate 33 entière, ≈500 — ces versets sont ~40% dans une sourate
de 73) au nombre de mots jugé "possible de réciter" depuis la fin d'Al-Fatiha.
Ce calcul suppose implicitement que l'imam reprend TOUJOURS au verset 1 de la
nouvelle sourate — confirmé par l'utilisateur : **rien n'empêche de commencer
au milieu d'une sourate**, cas parfaitement normal en prière. L'ancre ne
représente alors pas une "distance parcourue depuis Al-Fatiha" mais juste où
se trouve le verset choisi dans la sourate — comparer les deux n'a pas de
sens et bloque à tort toute identification légitime démarrant après le
verset 1.

**Pourquoi le garde-fou n'est plus nécessaire** : il visait à l'origine
(§3.10) un faux match à confiance 0.50 (Al-Baqarah 2:277) — déjà exclu
aujourd'hui par le seuil `_kMinIdentifyConfidence=0.70` à lui seul, en place
depuis ce même correctif. Vérifié sur le log : sans ce garde-fou, la
détection aurait réussi dès la 1ère passe dépassant 0.70 (09:37:57.325, soit
34s après la fin d'Al-Fatiha) — pas besoin d'attendre une confirmation
répétée sur plusieurs passes, un seul passage au-dessus du seuil (et pas
sourate 1) doit suffire à accepter immédiatement.

**Fix** : le garde-fou est retiré de `_beginIdentifiedTargetPhase` (ancien
code gardé en commentaire, même convention que §3.18/§3.19). Le garde-fou
ÉQUIVALENT dans `_maybeResyncPosition` (resynchronisation continue, §3.9)
reste, lui, en place et reste valide : il mesure un SAUT relatif à une ancre
DÉJÀ suivie dans la même sourate (donc borner sa vitesse a du sens, un
récitateur déjà positionné ne peut pas sauter 100 mots en avant en 2
secondes), pas une position absolue depuis Al-Fatiha.

**Build validé (`flutter analyze` propre, `flutter build apk --debug`
réussi) et installé sur device (2026-07-19). Pas encore retesté en
conditions réelles après ce fix précis.**

## 4. Questions ouvertes / non résolu

1. **Cause exacte du sous-jugement GOP (§3.4)** — non investiguée en
   profondeur côté `ForcedAligner.kt`. Le contournement (détection de fin
   par texte + rattrapage continu par Shazam) fonctionne mais ne corrige
   pas la cause : la coloration mot-à-mot temps réel reste probablement en
   retard tant que ce n'est pas résolu nativement.

2. ~~Continuité entre rak'ah~~ — **RÉSOLU, cf. §3.14** : confirmé par
   l'utilisateur et implémenté (repli sur silence prolongé après Fatiha,
   reprend la sourate/position de la rak'ah précédente). Pas encore testé
   en conditions réelles.

3. **Qualité de transcription ASR sur les lettres disjointes (muqattaʿat)**
   — constat réel (log) : l'ouverture de Maryam ("كهيعص") est très mal
   transcrite (quasi méconnaissable), retardant l'identification de
   plusieurs versets le temps qu'un passage plus "normal" arrive. C'est une
   limite du MODÈLE (entraînement), pas un bug de logique Dart — aucun
   correctif de seuil/fenêtre ne peut compenser une transcription qui ne
   contient tout simplement pas les bons mots. Risque résiduel avec §3.14 :
   si cette lenteur dépasse le délai de repli (5s) alors qu'une
   identification légitime était en cours, la continuité pourrait se
   déclencher prématurément -- mitigé par le réarmement du minuteur sur
   tout texte nouveau (§3.14), mais pas vérifié en conditions réelles sur
   CE cas précis (texte nouveau mais très dégradé, ni silence ni vraiment
   "rien").

4. **Aucun test de bout en bout après le cumul des correctifs §3.6 à
   §3.20** — chaque fix a été validé individuellement sur la base d'un log
   après-coup, jamais tous ensemble sur une salât complète rejouée depuis le
   début.

5. **Souffleur, continuité entre rak'ah et défilement (§3.12, §3.13, §3.14,
   §3.15) jamais testés du tout** — implémentés/ajustés sur la base du
   raisonnement et de mécanismes équivalents déjà validés ailleurs dans
   l'app, mais aucun n'a encore été revérifié en conditions réelles dans ce
   nouvel écran.

## 5. Ce qui serait utile de la part de Fable

- Un avis sur la piste §4.1 (pourquoi si peu de mots verrouillés par passe
  GOP) : vaut-il le coup de lire `ForcedAligner.kt`/`align()` en détail
  maintenant, ou le contournement (§3.4, §3.9) est-il suffisant pour l'usage
  réel visé (aide/correction, pas mesure de précision) ?
- Une opinion sur §4.2 (continuité entre rak'ah) : faut-il l'implémenter
  proactivement, ou attendre une clarification utilisateur plus précise ?
- Toute alternative architecturale au cumul actuel de garde-fous ad hoc
  (seuil de confiance dédié + fenêtre glissante + plausibilité temporelle +
  rejet sourate=1) qui semblerait plus robuste ou plus simple.
