# Journal des tests — analyse de logs de récitation

Journal de découvertes brutes, horodatées, issues de l'analyse des logs
device (`adb logcat`) pendant des sessions de test réelles. Pas un document
de synthèse/decision comme `PROBLEMATIQUES_ASR.md` — ici on note ce qu'on
observe, au fil des tests, avant tri/action.

---

## 2026-07-25

### 10:28:59 — Mot "عَلَيْهِمْ" (90:20) marqué error/vide en 1ère passe, correct en retry

**Constat** : le mot n'a probablement pas été sauté par le récitant —
c'est la première capture audio qui est arrivée vide.

Séquence (test preset=tajwid, strictHarakat=true, 14 règles actives) :
- `10:28:59.242` — 1ʳᵉ passe : `gop=-21.01`, `entendu=""` (rien reconnu à
  cet endroit) → verrouillé `WordStatus.error`, `final=true`.
- `10:28:59.248` — `[Correction] wordFailed déclenché` (mécanisme de
  correction automatique existant).
- `10:28:59.252-254` — `pauseCapture()`, audio de référence rejoué
  (`[Correction-Audio] verset=90:20 errorWordIndex=0`).
- `10:29:04.267` — `[ANCRE] recul 86 -> 83 (correction sur "عَلَيْهِمْ")` —
  3 mots remis en attente.
- `10:29:04.613` — `resumeCapture()`.
- `10:29:09.270` — 2ᵉ évaluation : `gop=-0.53`, `entendu=""` encore,
  `lock=false final=false` (intermédiaire).
- `10:29:10.755` — 3ᵉ évaluation : `entendu="عَلَيْهِمْ"` reconnu
  correctement → `WordStatus.correct`, verrouillé.

**Lecture** : capture initiale ratée (buffer/segmentation, pas un vrai
silence), corrigée automatiquement par le mécanisme déjà en place (rejoue
l'audio, recule l'ancre, réévalue). Cohérent avec les fragilités de
segmentation déjà documentées dans `PROBLEMATIQUES_ASR.md` — pas de code
touché, juste le constat.

### Session preset=tajwid (10:24:15 → ~10:29:11) — règles "NON DÉTECTÉE(S)"

18 mots distincts flagués sur toute la session (sourate Al-Balad, 90) :

| Règle | Mots distincts concernés |
|---|---|
| qalaqah | 6 |
| slnt | 5 |
| ikhafa | 2 |
| madda_normal | 2 |
| idgham_wo_ghunnah | 2 |
| laam_shamsiyah | 1 |
| idgham_ghunnah | 1 |

`qalaqah` et `slnt` dominent. Effort tajwid actuellement en pause (cf.
mémoire `project_priority_shift_core_stability_before_tajwid`) — utilisateur
prévoit un test avec un vrai récitateur pour trancher "règle vraiment
absente" vs "détecteur pas assez sensible" avant de creuser plus loin.

### 10:51:45 — Fuite de transcript entre deux sessions de récitation (Al-Fatiha → Al-Balad)

**Constat** : à un changement de cible de récitation (nouvelle sourate),
4 mots consécutifs sont jugés avec le texte "entendu" de la session
PRÉCÉDENTE au lieu de l'audio réel de la nouvelle session — un vrai
carry-over de buffer, pas juste une coïncidence.

Contexte : test preset=adulte, harakatSouple, `regles=0` (mode adulte sans
tajwid — conforme au nouvel axe de priorité).

Session 1 (Al-Fatiha 1:7, "غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ") :
- mot=24 "غَيْرِ" → correct
- mot=25 "ٱلْمَغْضُوبِ" → 1ʳᵉ passe `entendu="ٱلْمَلْمَغْضُورِ"` (unclear,
  autreMot=OUI) → correction auto → retry `entendu="ٱلْمَغْضُوبِ"` → correct
- mot=26 "عَلَيْهِمْ" → correct, `entendu="عَلَيْهِمْ"`
- mot=27 "وَلَا" → correct, `entendu="وَلَا"`
- mot=28 "ٱلضَّآلِّينَ" → correct (fragment), `entendu="ٱلضَّ"`

Changement de cible :
- `10:51:45.758353` — `[ASR] PREMIER bloc PCM reçu` (nouvelle session,
  `generation=6`)
- `[ASR] start() | mots=86 | continu=true | generation=6` — nouvelle cible
  = sourate Al-Balad (86 mots)
- `10:51:45.826197` — `[ASR] alignement forcé actif = true (cible=86 mots)`
  — confirmation de l'alignement APRÈS les évaluations ci-dessous

Évaluations anormales, TOUTES horodatées ENTRE le premier bloc PCM reçu et
la confirmation d'alignement actif (donc avant que le nouvel alignement
soit officiellement pris en compte) :
- `10:51:45.763172` — mot=25 attendu **"أَحَدٌ"** (90:5) mais
  `entendu="ٱلْمَغْضُوبِ"` (= mot 25 de la session PRÉCÉDENTE, Al-Fatiha) →
  `autreMot=OUI`, unclear
- `10:51:45.764539` — mot=26 attendu **"يَقُولُ"** (90:6) mais
  `entendu="عَلَيْهِمْ"` (= ancien mot 26) → unclear
- `10:51:45.765485` — mot=27 attendu **"أَهْلَكْتُ"** mais
  `entendu="وَلَا"` (= ancien mot 27) → unclear
- `10:51:45.766622` — mot=28 attendu **"مَالًا"** mais
  `entendu="ٱلضَّ"` (= ancien mot 28, identique au fragment précédent) →
  unclear

Les 4 valeurs "entendu" reproduisent EXACTEMENT les 4 dernières valeurs
"entendu" de la session Al-Fatiha précédente, dans le même ordre, mot pour
mot. Coïncidence exclue.

**Hypothèse** : au changement de cible (nouvelle sourate), un buffer/état
de transcription de la session précédente n'est pas purgé avant que la
nouvelle cible soit comparée — un flush tardif de l'ancien buffer se
retrouve évalué contre les nouveaux mots attendus. Rappelle le commentaire
déjà présent dans `recitation_verifier.dart` sur `resetBuffer()` ("de
l'audio déjà dans le buffer avant la pause... peut ressurgir après la
reprise et contaminer la nouvelle tentative") — mais ce correctif semble
scopé à la boucle pause/reprise de correction automatique, pas au
changement de cible entre deux sourates en mode continu.

Conséquence pratique observée : `[Correction] wordFailed déclenché :
wordIndex(global)=25` puis `[ANCRE] recul 29 -> 25` — 4 mots remis en
attente et re-évalués inutilement à cause de ce carry-over, avant de
repartir sur du bon audio.

#### CAUSE RACINE TROUVÉE (même jour) + correctif appliqué

**Preuve décisive** : les valeurs numériques des 4 mauvaises évaluations sont
IDENTIQUES à celles de la session précédente pour les mêmes index :

| | gop | forced | free | rescore | entendu |
|---|---|---|---|---|---|
| ancienne session mot=28 | -0.53 | -0.68 | -0.15 | 6.68 | "ٱلضَّ" |
| nouvelle session mot=28 | -0.53 | -0.68 | -0.15 | 6.68 | "ٱلضَّ" |

Seul `normGop` diffère (0.47 → 0.01), car recalculé sur le nouveau mot
attendu. Donc ce n'est PAS du nouvel audio mal transcrit : c'est
littéralement **la même passe d'alignement native, re-jugée contre les
nouveaux mots attendus**.

**Mécanisme** (`recitation_provider.dart`, `startContinuous`) :
1. ligne ~1782 : `_alignSub = _verifier.alignedWords.listen(_onAligned)` —
   on s'abonne au flux d'alignement…
2. ligne ~1784 : `await _verifier.start(...)` — …AVANT cet await, qui seul
   remplace la cible native (`setAlignmentTarget`) et purge le buffer
   (`resetBuffered`, `recitation_verifier.dart` ~L566).
3. Toute passe native encore **en vol** pendant cet await est donc livrée au
   nouveau `_onAligned`, qui l'indexe sur les NOUVEAUX `state.words`.
4. `_onAligned` ne contrôlait PAS la génération de session (il vérifiait
   seulement `prayerPhase`, `words.isEmpty`, `status`) → payload périmé
   accepté.

Cohérent avec l'ordre des horodatages : les 4 mauvaises évaluations
(.763→.766) tombent bien entre `PREMIER bloc PCM reçu` (.758) et
`alignement forcé actif = true (cible=86 mots)` (.826).

**Correctif appliqué** — garde de génération en tête de `_onAligned` :
```dart
if (_myGeneration < 0 || _verifier.sessionGeneration != _myGeneration) return;
```
`_myGeneration` n'étant affecté qu'APRÈS l'await de `start()`, la fenêtre
est couverte (rejet aussi quand il vaut encore -1). Aucun risque de perdre
une passe légitime : aucun audio ne peut être transcrit avant que `start()`
ait créé le flux micro. L'infrastructure existait déjà
(`sessionGeneration`/`stopIfCurrentSession`, ajoutés en 2026-07-16 pour un
bug voisin sur le nettoyage au dispose) — elle n'était simplement pas
appliquée au flux d'alignement.

**Note** : le nettoyage à la sortie d'écran existait déjà et n'était pas le
maillon manquant (`RecitationNotifier.dispose` → `stopIfCurrentSession` =
`stop()` + `resetBuffer()`, gardé par génération). Le trou était côté
RÉCEPTION des passes, pas côté purge.

**Reste à vérifier** : le chemin TEXTDIFF (`_onStructured` →
`_realignFromFullText`) est exposé à la même classe de course (même flux
re-livré, garde de génération absente aussi) — pas encore constaté dans un
log, à surveiller si l'utilisateur bascule le moteur de jugement sur
text-diff.

---

## 2026-07-25 (2) — Session Al-Baqara 2:3→2:17, mode adulte sans tajwid

Session unique, preset `adulte/harakatSouple`, seuils -0,45/-1,60,
**0 règle tajwid active**. 26 mots signalés, 13 pauses de correction.

**Correctif de fuite inter-sessions validé** : aucun mot jugé avant que le
récitant parle, aucun report d'« entendu » d'une session précédente. La
garde de génération tient.

### Répartition des 26 mots signalés — 3 familles

**A. Corrections qui ont abouti (10 mots)** — comportement voulu
Mots 16, 49, 96, 111, 123, 131, 141, 142, 147 : signalés → audio rejoué →
répétition → **corrects et verrouillés**.

**B. Troncatures de capture (9 mots) — FAUX POSITIFS**

| mot | attendu | entendu | verdict |
|---|---|---|---|
| 138 | ءَامَنَّا | ءَامَ | error |
| 140 | خَلَوْا۟ | خَلَوْ | error |
| 145 | مَعَكُمْ | كُمْ | error |
| 172 | فَلَمَّآ | فَلَم | error |
| 173 | أَضَآءَتْ | أَضَ | error |
| 162 | رَبِحَت | *(vide)* | error |
| 169 | ٱلَّذِى | *(vide)* | error |
| 174 | مَا | *(vide)* | error |

Le mot est amputé (début ou fin) ou entièrement vide. Détail révélateur :
les mots **172-175 ont été jugés dans la même milliseconde**
(11:45:49.78x) — une seule coupe de segment malheureuse a détruit 4 mots
d'un coup.

**C. Vraies confusions de lettres (4 mots)** — jugement légitime
- mot 51 : خَتَمَ → خَثَبَ (ت/ث et م/ب)
- mot 79 : يَخْدَعُونَ → يَخْذَعُونَ (د/ذ)
- mot 163 : تِّجَـٰرَتُهُمْ → مَا ٱبِقَهُمْ (autre chose)
- mot 175 : حَوْلَهُۥ → حَوْلَلَهُۥ (لَ dupliqué)

### Conclusion : ~9 faux positifs contre ~4 vraies erreurs

Le maillon faible n'est pas le moteur de jugement mais la **chaîne
d'acquisition audio**.

### ⛔ Correctif tenté puis ANNULÉ le même jour — « mot tronqué jamais accusé »

**Refusé par l'utilisateur, à juste titre.** Conservé ici comme trace de ce
qui a été tenté et pourquoi c'était faux (cf. consigne ajoutée à `CLAUDE.md` :
pas de correctif palliatif, traiter la cause d'origine).

**Pourquoi c'était faux** : requalifier `correct` un mot dont on n'a entendu
qu'un fragment fait **valider un récitateur qui ne dit que la moitié du
mot** — exactement ce que l'app existe pour détecter. Le correctif
neutralisait le symptôme dans la couche de JUGEMENT alors que le défaut naît
dans la couche de CAPTURE (le buffer coupe en plein mot). C'est une couche de
tolérance posée par-dessus le vrai problème, qui l'aurait en plus rendu
invisible dans les logs.

**La bonne cible reste** : `BufferedTranscriber` — recouvrement d'audio au
gel, ou coupe qui évite de tomber au milieu d'un mot
(cf. `ARCHITECTURE_RECITATION.md` §3.1 et piste C), à valider sur les bancs
hors device avant toute modification.

<details>
<summary>Détail de la tentative annulée (pour mémoire)</summary>

**Mécanisme du faux rouge** (`recitation_provider.dart`, `_onAligned`) :
1. `isFragment` (L2640) détecte déjà que le texte entendu est un
   préfixe/suffixe/sous-séquence ordonnée de l'attendu (≥2 caractères ET
   ≥1/3 de la longueur).
2. Mais ce flag ne servait qu'à **empêcher de bloquer le vert** (via
   `spellsDifferentWord`, L2647). Il n'empêchait **pas** le rouge.
3. Sur un mot tronqué, le gop est **mécaniquement** effondré : la DP force
   la totalité des tokens attendus sur un audio partiel → `forced`
   s'écroule sur les frames manquantes.
4. `final lock = p.isFinal || ...` (L2852) → sur un segment figé le
   verrouillage est **inconditionnel**, quel que soit le verdict → faux
   rouge définitif.

**Correctif** : un mot dont le verdict serait `error` mais dont le texte
entendu est un fragment cohérent de l'attendu est requalifié `correct` —
on fait confiance au TEXTE plutôt qu'au gop contaminé. Tracé dans le log
par ` tronque=RATTRAPE` pour audit (`grep "tronque=RATTRAPE"`).

**Sûreté** : une vraie faute de lettre casse la propriété de
préfixe/suffixe/sous-séquence et ressort en `spellsDifferentWord` — elle
continue d'être jugée normalement. Le laisser-passer ne couvre que « bon
mot, pas entendu en entier », jamais « autre mot ».

**Non traité volontairement** : le transcript VIDE (3 mots ci-dessus).
Réellement ambigu (mot sauté vs capture ratée) et son rouge est une
décision documentée (Finding #9, 2026-07-16) — relève du correctif buffer
(recouvrement au gel, cf. `ARCHITECTURE_RECITATION.md` piste C), à valider
sur les bancs hors device.

</details>

---

## 2026-07-25 (3) — Al-Baqara, mode adulte : coupures de mots et retard de validation

Session 12:33:35 → 12:37:19. Analyse restreinte à la **première récitation**
(avant toute demande de répétition), à la demande de l'utilisateur.

### Constat 1 — Le texte FIGÉ diverge de l'aperçu qui était bon

| heure | type | buffer | texte |
|---|---|---|---|
| 12:33:59.52 | aperçu | 9 s | `هُدًى لِّلْمُتَّقِينَ` ✅ |
| 12:34:01.84 | **FIGÉ** | 10 s | `أَلِ ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ وَيُ ٱلصَّلَوٰةَ وَمِمّ` ❌ |

Le texte définitif **n'a aucun rapport** avec l'aperçu de 2 secondes plus
tôt, qui était correct. C'est l'effondrement de la re-transcription déjà
documenté dans l'en-tête de `BufferedTranscriber` (v2/v3) : à ~10 s de
buffer, la normalisation per-feature dérive et la passe de gel produit un
texte dégradé. **Le verdict définitif est pris sur la PIRE des deux passes.**

### Constat 2 — Coupures en plein mot, mesurées

| segment figé | mot amputé | attendu |
|---|---|---|
| `وَيُ ٱلصَّلَوٰةَ` | `وَيُ` | `وَيُقِيمُونَ` |
| `وَمِمّ` (fin de segment) | `وَمِمّ` | `وَمِمَّا` |
| `بِمَآزِلَ أُنزِلَ` | fusion | `بِمَآ أُنزِلَ` |
| `أُو۟لَـٰٓئِكَرُونَ` | fusion 2 mots | `أُو۟لَـٰٓئِكَ` + `…رُونَ` |
| `تَمَ ٱللَّهُ` (12:36:06) | `تَمَ` | `خَتَمَ` |

Le cas `خَتَمَ` est probant : le **même** passage est figé `خَتَمَ ٱللَّهُ` à
12:35:19 puis `تَمَ ٱللَّهُ` à 12:36:06 — seule la position de la coupe a
changé. Ce n'est donc pas la prononciation, c'est le découpage.

Anomalie associée : `12:34:18.29 FIGE 1s "أُو۟لَـٰٓئِكَرُونَ"` — un segment
d'**1 seconde** a été figé, sous le plancher `MIN_COMMIT_SECONDS = 2,5 s`
censé l'empêcher (statistiques de normalisation non fiables sur si court).

### Constat 3 — Le retard de validation : cause identifiée

L'ancre (validation DÉFINITIVE) n'avance **que sur un gel de segment**. Or
le gel dépend d'une pause de ≥ 450 ms. Cadence réelle des gels :

| gel | intervalle depuis le précédent |
|---|---|
| 12:33:37 (3 s) | — |
| 12:33:42 (2 s) | 5 s |
| 12:33:47 (3 s) | 5 s |
| 12:34:01 (10 s) | **14 s** |
| 12:34:16 (10 s) | **15 s** |

Les 3 premiers versets sont courts → pauses naturelles → gels rapides. Sur
les versets longs (2:3, 2:4) récités **d'un seul souffle**, aucune pause de
450 ms n'apparaît → le buffer gonfle à 10 s → **14 à 15 secondes sans
aucune validation définitive**, puis 10 à 12 mots validés d'un bloc.

Exemple chiffré (passe seq=15, 12:34:01) : `ancre=10 → frontiere=19,
mots=10`. Les mots 10 à 19 ont été prononcés entre ~12:33:50 et 12:34:01 et
sont tous validés **au même instant, à la fin**.

⇒ **Le retard n'a rien à voir avec la vitesse de récitation.** Il est
structurel : la validation est suspendue à une pause que justement une
récitation fluide ne produit pas. Plus on récite proprement, plus on attend.

### Cercle vicieux constaté

Segment long (10 s) → re-transcription de gel dégradée (constat 1) →
faux verdicts → correction déclenchée → micro coupé pendant la lecture de
l'audio de référence → audio de la suite perdu → nouvelles coupures →
nouvelles corrections. Mesuré sur cette session : **~26 s de micro coupé sur
220 s**, soit ~12 % de la session.

### Ce qu'il faut corriger (cause d'origine, pas symptôme)

1. **Ne pas figer sur la passe dégradée** : quand l'aperçu précédent était
   meilleur que la passe de gel, c'est l'aperçu qui devrait être retenu (le
   mécanisme existe déjà pour la borne dure — `pendingForceCommit` réutilise
   l'aperçu sans re-transcrire — mais pas pour le gel sur pause).
2. **Découpler la validation de la pause** : permettre à l'ancre d'avancer
   sur les mots déjà largement couverts d'un aperçu stable, sans attendre un
   gel. C'est le vrai correctif du retard.
3. **Ne jamais figer un segment sous `MIN_COMMIT_SECONDS`** — le plancher est
   contourné par un chemin (à identifier).
4. **Éviter que la coupe tombe au milieu d'un mot** (recouvrement au gel,
   cf. `ARCHITECTURE_RECITATION.md` piste C).

⚠️ Tous ces points touchent `BufferedTranscriber` : **mesure obligatoire sur
les bancs avant toute modification** (`simulate_sliding_window.py`,
`analyze_device_log.py`) — règle projet, quatre correctifs « évidents » déjà
invalidés par la mesure.

---

## 2026-07-25 (4) — ⛔ Correctif « borne de gel en temps réel » : TENTÉ, MESURÉ, ANNULÉ

### Le diagnostic (lui, reste valide)

Mesure sur session en mode référence (aucune correction, aucune coupure
micro) : **l'ancre d'alignement gelée 22 s puis 43 s d'affilée**, 37 mots
validés en 2 minutes. Retour utilisateur : « j'étais sur l'aya 6 alors que le
modèle traite l'aya 2 ou 3 ».

Ce n'est **pas** le coût d'inférence (mesuré : 887 ms au pire pour 10 s de
buffer, 125 ms pour 1 s) ni la puissance du téléphone.

**Cause racine confirmée** : `alignAnchor` n'avance qu'au gel d'un segment, et
toutes les conditions de gel se mesurent en audio **retenu** (`sizeSeconds`),
jamais en temps écoulé. Le portier RMS jetant les silences (mesuré : 38 s
retenus pour 107 s d'horloge, ~36 %), `sizeSeconds` avance ~3× moins vite que
l'horloge → la borne dure de 12 s exige 12 s de *parole*, soit 40 s+ de temps
réel. Rien ne bornait le retard tel que l'utilisateur le perçoit.

### Le correctif tenté et son échec, chiffré

Ajout d'une seconde borne de gel en **temps réel** (5 s), forçant le gel même
avec peu d'audio retenu.

| | avant | après |
|---|---|---|
| retard de validation | 22-43 s | médiane **8,2 s** (max 9,5 s) |
| segments commençant en pleine parole | 5/7 (71 %) | **11/14 (79 %)** |
| ressenti utilisateur | retard | « beaucoup de rouge » |

**Pourquoi ça a échoué** : avant, les gels tombaient sur des pauses, donc sur
du silence — frontières propres. Forcés au bout de 5 s, ils tombent **en
pleine parole** : le segment suivant repart exactement là où le snapshot
précédent s'est arrêté (`copyOfRange(snapshot.size, …)`), donc démarre au
milieu d'un mot → mots tronqués → rouges.

Le pre-roll ajouté en même temps (240 ms d'hystérésis sur le portier RMS)
n'y a rien changé, et pour une raison instructive : **la coupure ne vient pas
du portier RMS mais de la frontière de segment elle-même**. Corriger le
portier ne pouvait pas corriger un défaut situé ailleurs.

Note : le plancher `MIN_COMMIT_SECONDS` (2,5 s d'audio) est devenu la
contrainte dominante — d'où 8,2 s et non 5 s. Tous les segments faisaient
« buffer 2s ».

### Décision : ANNULÉ (2026-07-25)

Les deux modifications de comportement ont été retirées de
`BufferedTranscriber` (retour à l'état git). **Seul l'horodatage de mesure est
conservé** : chaque gel logue désormais
`VALIDATION retard=NNNNms depuis le debut de cet audio | wav=clip_….wav`,
sans influencer ni la segmentation ni le jugement. C'est l'outil qui manquait
pour évaluer toute solution future sans la déduire.

### Ce que cet échec apprend, pour la prochaine proposition

1. **Le compromis est réel** : gel sur pause = frontières propres mais retard
   non borné ; gel sur temps = retard borné mais coupes en plein mot. Toute
   solution doit traiter les DEUX, pas en échanger un contre l'autre.
2. **Le recouvrement d'audio au gel est écarté** : re-présenter de l'audio
   déjà transcrit désaligne la DP (l'ancre a avancé au-delà de ces mots) —
   piège déjà mesuré et documenté (`ForcedAligner` « TENTATIVE 1 », fenêtre
   glissante naïve à WER > 100 %).
3. Piste non testée, à proposer et faire valider avant tout code : **armer**
   le gel sur la borne temps réel puis attendre un silence *bref*
   (~160 ms au lieu de 450 ms) pour le déclencher — frontière propre ET
   retard borné. Écrite puis retirée sans être mesurée, faute de validation
   préalable.
4. Consigne process ajoutée à `CLAUDE.md` : proposer, exposer les effets de
   bord, **attendre validation** avant d'implémenter. Un effet de bord
   identifié pendant l'analyse interdit l'implémentation directe.

### Diagnostic conservé (sans changer aucun verdict)

Les mots tronqués restent identifiables dans le log par le flag `fragment`
déjà émis : `grep 'fragment' | grep error` en donne le compte. C'est la
métrique à suivre pour mesurer l'effet du futur correctif buffer, sans avoir
besoin d'altérer les jugements.

## 2026-07-25 14:10 — Solution A v2 : cible DYNAMIQUE selon le débit

### Pourquoi la v1 (cible fixe 2,0s, coupe au DERNIER silence) a été rejetée

Mesuré sur le log de l'utilisateur, deux défauts cumulés :

1. **Cascade de gels.** Je cherchais le *dernier* micro-silence du buffer. S'il
   tombe tôt, la queue laissée derrière dépasse elle-même la cible de 2 s → une
   nouvelle coupe est armée immédiatement, puis encore. Signature dans le log,
   répétée à l'identique :
   `ancre=13 frontiere=13 final=true mots=1 nouvelle_ancre=14`
   → **278 mots tamponnés « correct »** en enchaînant les gels, y compris
   pendant que l'utilisateur **ne parlait plus**.
2. **Segments trop courts pour l'aligneur.** À 2 s, la DP n'a pas assez de
   frames pour placer plusieurs mots : `mots=1` par gel, frontière qui n'avance
   pas. Comme `isFinal=true` force le jugement ET le verrouillage de tout ce
   qui est renvoyé, chaque tour verrouille un mot à vide.

Retour utilisateur correspondant : « il valide avant que je dise le mot », « je
suis arrêté de parler », « je me suis arrêté de réciter quand j'ai vu qu'il
valide rouge alors je n'ai pas encore dit le mot ».

### Ce qui change en v2

| Point | v1 (rejetée) | v2 |
|---|---|---|
| Cible | 2,0 s **fixes** | `WORDS_PER_SEGMENT (3) × secPerWord`, borné [2,5 s ; 8 s] |
| `secPerWord` | — | mesuré en continu : `samples figés / mots réellement placés`, moyenne glissante 30 %, bornes de crédibilité 0,3–3 s/mot ; départ 1,0 s (médiane quran.com) |
| Choix du silence | le **dernier** du buffer | celui **le plus proche de la cible**, dans ±0,8 s — supprime la queue résiduelle donc la cascade |
| Plancher de segment | contourné | `minKeep = MIN_TARGET_SECONDS (2,5 s)` passé à `findCutOffset` — un gel programmé respecte la durée minimale par construction |

Inchangé : résolution d'analyse 20 ms (c'est la mesure qui débloque le
problème : 15 silences vus à 80 ms contre 38 à 20 ms sur le même audio),
micro-silence minimal 40 ms, l'audio après la coupe reste dans le buffer (aucun
mot sauté, aucun mot jugé deux fois), et si aucun silence n'est trouvé on ne
coupe **pas** (pause franche + borne dure 12 s reprennent la main → jamais de
coupe en plein mot).

`secPerWord` n'est **pas** remis à zéro par `reset()` : celui-ci est appelé à
chaque correction, pas seulement en début de session.

### À vérifier au prochain test
- `mots=` par gel final **> 1** et frontière qui avance (signature de l'échec v1).
- `coupe sur micro-silence a Xms` présent, avec `cible` proche de 3 × débit réel.
- `VALIDATION retard=` : viser < 5 s (43 s avant tout correctif).
- Aucun rouge sur des mots non prononcés, aucun gel pendant un silence prolongé.

## 2026-07-25 14:12 — PREUVE de « la validation m'a devancé » + 5 correctifs

### La preuve, à la milliseconde (log 14:12:22, Al-Baqara 3)

| Heure | Événement |
|---|---|
| 22.270 | `coupe sur micro-silence a 3320ms (buffer 3,4s) -- 40ms conserves` → extrait 0–3320 ms parti à l'inférence |
| **22.274** | **4 ms plus tard, la MÊME coupe est armée une 2ᵉ fois** (`a 3320ms`, `buffer 3,4s`, `-- 120ms conserves`). `busy` pris → elle reste en attente |
| 22.537 | `segment FIGE 3s` → `alignement seq=13 mots=4 nouvelle_ancre=19 `**`differe=19`** (mot 19 différé, à juste titre). Buffer purgé → **120 ms restants** |
| **22.609** | **`segment FIGE 0s -> 34ms : "مٍ"`** ← l'offset périmé fige les 200 ms restants |
| 22.610 | `alignement seq=14 ancre=19 frontiere=19 final=true mots=1 nouvelle_ancre=20` |
| **22.919** | `[GOP] mot=19 "يُنفِقُونَ" gop=-20.00 forced=-20.00 free=0.00 entendu="" -> error (lock=true, final=true)` |
| 22.9→24.0 | l'utilisateur dit `يُنفِقُونَ` : aperçu `"إِنَّـٰـٰفِقُونَ"` (on y voit `فِقُونَ`) |
| 24.251 | ancre déjà à 20 → cet audio est comparé à `وَٱلَّذِينَ` (verset 4) → `unclear`. **Curseur un mot en avance** |
| 26.997 | `pauseCapture()` — arrêt de l'utilisateur |

`يُنفِقُونَ` verrouillé **rouge sur 200 ms de silence** (`entendu=""`), 300 ms avant
d'être prononcé. Pas de WAV pour ce test (`capture de clips desactivee`) — le log
suffit, un `entendu=""` sur une inférence de 34 ms ne demande pas de contre-preuve.

### Cause racine : `samples` mentait pendant une inférence de gel

`feed()` prélève l'extrait mais **ne purge pas** `samples` — la purge a lieu dans
la coroutine ~265 ms plus tard. Pendant cette fenêtre, `samples.size` compte de
l'audio déjà en cours de verrouillage. Les blocs PCM arrivant **par rafales**
(deux `feed()` à 4 ms d'écart, 80 ms d'audio chacun), il y a toujours au moins
une décision prise sur une taille fausse.

Trois défauts empilés dessus, **dont deux introduits par le correctif v2 lui-même** :
1. Le garde-fou `MIN_COMMIT_SECONDS` avait été **désarmé** par l'exclusion
   `&& pendingCutOffset < 0` (ajoutée au motif qu'une coupe programmée respecte
   déjà `minKeep`) — vrai dans le buffer où l'offset a été calculé, **faux** dès
   qu'il est purgé. C'est exactement le trou emprunté.
2. Un offset hors buffer **dégradait vers « figer tout le buffer »** au lieu d'être
   invalidé.
3. Le mécanisme « 2 chances max » a été **consommé par ce faux segment** :
   `seq=13` avait correctement différé le mot 19, le gel parasite est arrivé avec
   `forceJudgeIndex=19` et l'a jugé de force sur 200 ms.

### Correctifs appliqués (BufferedTranscriber.kt)
- **A** `commitInFlight` : aucune décision de segmentation (coupe, gel sur pause,
  borne dure) pendant qu'un gel n'a pas purgé le buffer. Levé dans le `finally`
  pour qu'une inférence en échec ne bloque pas la session.
- **B** garde-fou de durée minimale sur la longueur **prévue**
  (`min(pendingCutOffset, size)`) au lieu de `sizeSeconds`, et annulation de
  l'offset avec le flag. L'exclusion fautive est documentée sur place comme
  « ne pas réintroduire ».
- **C** offset ≥ taille du buffer → invalidé et journalisé ; le repli
  « figer tout » ne reste qu'en dernier recours, et il **log** désormais.
- **D** `forceJudgeIndex` seulement sur un segment ≥ `MIN_COMMIT_SECONDS` (un
  segment de 0,2 s n'est pas une « seconde chance »), et le sursis n'est plus
  consommé quand on n'a pas forcé.

### Correctif de la surcharge de l'isolate Dart (recitation_provider.dart)
Mesuré : **299 lignes `[TEXTDIFF]` rigoureusement identiques pour le mot 0 et 299
pour le mot 1** en 27 s (22 à 32 écritures fichier synchrones/s), sur des mots
verrouillés depuis la 3ᵉ seconde. En plus, `_realignFromFullText(apply: false)`
recopiait **tout** `state.words` (6121 mots sur Al-Baqara) à chaque appel
(~12,5/s) alors que la boucle s'arrête au 2ᵉ mot et n'écrit rien.
→ copie mutable construite **seulement si `apply`** ; journalisation **seulement
sur changement de verdict** (`_lastTextDiffLine`, vidé à chaque nouvelle cible).
C'est le candidat le plus plausible pour la rafale de blocs PCM qui a déclenché
la course ci-dessus.

### Inchangé et validé par ce test
Cible dynamique : retard **3,17–4,46 s** (médiane 3,34 s) contre 43 s avant tout
correctif ; mots par gel **4/1/5/2/3/4** avec frontière qui avance (le `1` est
légitime : verset 2 = `الٓمٓ`, un seul mot). **Aucune cascade.**

## 2026-07-25 14:25 — Retard SILENCE RETIRÉ + désynchronisation de fin + orange

### Le retard réel = la durée du segment, rien d'autre

Les `retard=16702ms` / `17073ms` sont des artefacts : l'horloge démarre au
premier bloc audio, pas à la première parole, donc elle compte les silences.
Audio retenu et inférence soustraits :

| # | audio | retard brut | inférence | reste |
|---|---|---|---|---|
| 2 | 2 s | 3303 ms | 240 ms | ~1,1 s |
| 8 | 2 s | 2749 ms | 214 ms | ~0,5 s |
| 13 | 4 s | 4839 ms | 356 ms | ~0,5 s |
| 18 | 6 s | 7483 ms | 524 ms | ~1,0 s |
| 30 | 7 s | 7887 ms | 617 ms | ~0,3 s |
| 36 | 2 s | 16702 ms | 151 ms | **~14,6 s de silence** |
| 44 | 3 s | 17073 ms | 218 ms | **~13,9 s de silence** |

**Conclusion : retard ≈ durée du segment + 0,3 à 1,5 s.** L'inférence
(150–620 ms) et le téléphone ne comptent pour rien. Un seul levier existe :
raccourcir les segments.

### La fenêtre de recherche de coupe était FIGÉE (défaut de la v2)

Sur 15 gels, **5 coupes seulement**, toutes dans les 15 premières secondes :

| Gel | 2 | 4 | 6 | 8 | 10 | 13 | 18 | 20 | 25 | 30 | 34 | 36 | 39 | 42 | 44 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| coupe | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| durée | 2s | 3s | 2s | 2s | 2s | 4s | 6s | 2s | 6s | **7s** | 5s | 2s | 3s | 3s | 3s |

`findCutOffset` cherchait dans un couloir FIXE `[cible−0,8 s ; cible+0,8 s]`.
Si ce couloir de 1,6 s ne contient aucun micro-silence → −1, et au bloc suivant
on rescanne **le même couloir** avec le même résultat, indéfiniment.
→ **Correctif validé** : borne droite = fin du buffer (fenêtre glissante), en
gardant « le silence le plus proche de la cible » et `minKeep = 2,5 s` (donc pas
de retour de la cascade v1, aucun segment < 2,5 s possible).

### La désynchronisation de fin, conséquence directe

1. `14:26:09`, gel de **7 s** → la transcription libre s'effondre :
   `"إِنَّ ٱلَّذِينَ كَفَرُوا۟ سَآءٌ عَلَيْهِمْ لَا يُُونَ"` — **4 mots avalés**
   (`ءَأَنذَرْتَهُمْ أَمْ لَمْ تُنذِرْهُمْ` absents). Dérive de normalisation au-delà
   de ~6 s, déjà documentée en tête de `BufferedTranscriber.kt`.
2. L'aligneur place 4 mots là où 11 ont été dits → **l'ancre prend 7 mots de
   retard**.
3. `14:26:14`–`14:26:17` : le réciteur est au verset 7 (la transcription le
   confirme), l'aligneur force encore `عَلَيْهِمْ أَأَنذَرْتَهُمْ…` → `mots=0`,
   `mots=0`, `mots=0`.
4. Ensuite **un seul mot par gel** (ancre 45→46→47→48→49) : l'audio ne contient
   plus les mots attendus, seul le sursis forcé avance. **Décrochage
   auto-entretenu, jamais rattrapé.**

### Les 5 orange étaient TOUS des artefacts d'aperçu

| mot | attendu | entendu |
|---|---|---|
| 43 | `سَوَآءٌ` | `سَ` |
| 48 | `تُنذِرْهُمْ` | `ٱلْ` |
| 45 | `ءَأَنذَرْتَهُمْ` | `يَسْتَ` |
| 16 | `ٱلصَّلَوٰةَ` | `ٱلصَّدْةَ` (aperçu d'1 s) |
| 15 | `وَيُقِيمُونَ` | `وَٱللَّهُ يَعْلَمُونَ` |

Preuve directe : mots 15/16 verrouillés orange à `14:25:37`, puis le segment
figé suivant à `14:25:42` transcrit **parfaitement** `وَيُقِيمُونَ ٱلصَّلَوٰةَ وَمِمَّا
رَزَقْنَـٰهُمْ يُنفِقُونَ`. Cause : `lock = p.isFinal || judged != error` verrouillait
un `unclear` **sur un aperçu**.
→ **Correctif validé** : `lock = p.isFinal || judged == correct`. Un « je ne
suis pas sûr » ne se fige plus sur une preuve incomplète. Ce n'est pas de la
tolérance : au gel, le verdict est appliqué tel quel.

### Bouton PAUSE inatteignable (capture d'écran utilisateur)

`RIGHT OVERFLOWED BY 12 PIXELS` sur la barre du haut. Écran 360 dp : 5 boutons
de 48 dp + 28 dp de marges = 268 dp, il ne restait que 92 dp au titre et **le
bouton pause était rogné hors écran**. C'est l'icône du jeu ajoutée le
2026-07-24 qui a fait déborder la rangée.
→ icône du jeu masquée pendant l'écoute (on ne bascule pas vers un QCM en pleine
récitation), marge droite 20→4, `visualDensity: compact`, titre `maxLines: 1`.
Le bandeau « RÉFÉRENCE EN COURS D'ENREGISTREMENT » débordait aussi (titre non
`Expanded`) — corrigé.

### Réglage « diagnostic » (demande utilisateur)

Réglages → Diagnostic : un interrupteur unique coupe le journal **Dart ET
natif** plus la capture WAV. Motif : vérifier que le retard ne vient pas de
l'instrumentation (22 à 32 écritures fichier synchrones/s mesurées).
La capture WAV est passée de l'écran karaoké au **provider**
(`RecitationNotifier.startContinuous`) : deux tests de suite avaient produit un
log sans audio (`capture de clips desactivee`) parce qu'ils partaient d'un écran
qui ne l'activait pas.

## 2026-07-25 16:15 — VÉRIFICATION AUDIO : pas de régression du modèle 2 têtes

23 WAV captés sur device (81 s), rejoués hors device par
`benchmark/compare_onnx_on_device_wavs.py` (mel recopié de `MelSpectrogram.kt`,
donc ce que le modèle reçoit RÉELLEMENT dans l'app), contre le meilleur modèle
UNE tête de l'historique (`fastconformer-ctc-mixed-e02` = epoch 14 du run
tajweed-mixed).

### 1. Le modèle 2 têtes n'a PAS régressé — il est meilleur

| audio | 2 têtes | 1 tête (mixed-e14) |
|---|---|---|
| clip…773024 (3,44 s) | `بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ` | idem |
| clip…784140 (3,33 s) | `ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِ` | idem |
| clip…791443 tronqué 2,5 s | `هُدًى لِّلْ` | **(vide)** |
| clip…791443 tronqué 3,0 s | `هُدًى لِّلْمُتَّقِينَ` | `هًُىقِينَ` |
| clip…829489 (2,85 s) | `إِنَّ يَـٰـٰهُمُْونَ` | `ُونَ` |
| 6 clips quasi-silencieux | bruit (`وَرُونَ`) | **(vide)** |

**2 têtes ≥ 1 tête partout.** Hypothèse « régression du modèle » écartée.

### 2. La cause est la LONGUEUR du segment — prouvé sur audio IDENTIQUE

`clip_1784983791443.wav`, même audio, seule la fenêtre change :

| longueur | 2 têtes | 1 tête |
|---|---|---|
| **2,00 s** | `هُدًى لِّلْمُتَّقِينَ` ✅ | `هُدًى لِّلْمُتَّقِينَ` ✅ |
| 3,00 s | `هُدًى لِّلْمُتَّقِينَ` ✅ | `هًُىقِينَ` |
| 4,00 s | `هُدًىقِينَ` | `هًُىمُ` |
| 6,00 s | `هُدًى لِّلْتَّ` | `هُدًىمُ` |
| **6,27 s (réel)** | **`هُ`** | **`هُ`** |

Le clip fait 90,4 % de parole, RMS 0,18 — de la vraie parole dense, pas du
silence. **À 2 s les deux modèles rendent le texte parfait ; à 6,27 s ils
rendent UNE lettre.** Même conclusion sur `clip…715790` (parfait ≤ 3 s,
`ذَٰلِكَ فِيهِ حَكِيدًا` à 4,43 s).

⇒ La dérive de normalisation `per_feature` est réelle et commence **vers
3,5–4 s**, pas à 10-12 s comme le supposait le code (`MAX_TARGET_SECONDS = 8`,
`MAX_SEGMENT_SECONDS = 12`).

Dans le log, ce segment de 6,27 s est exactement celui qui a lancé la
désynchronisation : `alignement seq=41 ancre=10 frontiere=10 final=true mots=1
nouvelle_ancre=11` — l'app a verrouillé 1 mot alors que l'audio contenait les
DEUX mots, parfaitement reconnaissables à 2 s.

### 3. `secPerWord` s'emballe (défaut de la cible dynamique)

Log : `cible 4,5s = 3 mots x 1,50s` puis `4,6s = 3 mots x 1,53s`, partant de
1,00. L'EMA est alimentée par `samples figés / mots placés`. Quand l'aligneur
échoue (`mots=0`/`mots=1` sur 4 s), ce n'est pas un débit mais un **signal
d'échec** — et il pousse la cible vers le haut. Cible longue → segment long →
transcription dégradée → encore moins de mots placés. **Boucle qui s'emballe.**

### 4. 11 segments figés et JUGÉS sur du silence

| clip | RMS | % parole | plus longue plage de parole |
|---|---|---|---|
| …849527 | 0,022 | 18,1 % | 60 ms |
| …878395 | 0,015 | 14,6 % | 60 ms |
| …894054 | 0,020 | 16,1 % | 60 ms |
| …906227 | 0,015 | 16,4 % | 60 ms |

Le plancher de bruit de cet enregistrement est à RMS ≈ 0,015–0,020, et
`SILENCE_RMS_THRESHOLD = 0,02` tombe **pile dessus**. Le portier classe donc le
bruit comme parole ~18 % du temps : `pauseSamples` se remet à zéro sans arrêt,
le gel sur pause ne tire jamais, le buffer se remplit à 2,6–3,8 s, se fait
couper, figer et **juger** — d'où les 8 hallucinations `وَرُونَ` qui tamponnent
des mots alors que le réciteur s'est tu.

### 5. `MIN_MICRO_SILENCE_MS = 40` est trop exigeant pour ce passage

Sur le clip de 6,27 s (90 % de parole, plus longue plage 2,62 s), la coupe est
tombée à 6272 ms alors que la cible était à 3400 ms : entre 2,6 s et 6,27 s,
**aucun silence de 40 ms**. Les inter-mots de ce passage tiennent en une seule
fenêtre de 20 ms.

## 2026-07-25 16:45 — CORRECTION D'UNE CONCLUSION FAUSSE + cible fixe 3 s

### Ce que j'avais affirmé à tort

« La dérive de normalisation commence vers 3,5–4 s. » **FAUX.** Artefact de
méthode : je comparais des segments qui ne commençaient pas au même endroit
(troncatures à 2,0 / 2,5 / 3,0 s pile, donc souvent en plein mot).

### La bonne mesure : mots ÉMIS depuis un MÊME vrai inter-mot

Critère corrigé — non pas « les mots émis sont-ils bien orthographiés » (piège
dans lequel je suis tombé en notant un cœur de 5,3 s « parfait » alors qu'il
n'avait rendu que 2 mots) mais « combien de mots pour la parole présente ».

| départ | coupe | durée | mots émis | texte |
|---|---|---|---|---|
| 6,52 s | 9,60 s | 3,08 s | 5 | `ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِ` ✅ |
| 6,52 s | 11,32 s | 4,80 s | 8 | `… فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ` ✅ |
| 6,52 s | 12,08 s | 5,56 s | 9 | tous justes ✅ |
| 3,16 s | 6,52 s | 3,36 s | 1 | `الٓمٓ` |
| 3,16 s | 8,74 s | 5,58 s | 7 | `الٓم ۚ ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِمِ` |

⇒ **Plus long = plus de mots, SANS dégradation jusqu'à 5,6 s.** Le débit reste
constant (1,6–2,0 mots/s de parole).
⇒ Ce qui détruit une transcription, c'est un segment qui **DÉMARRE au milieu
d'un mot**, pas sa longueur. Preuve : le segment de 6,27 s capté par l'app rend
`هُ` ; le MÊME audio recoupé depuis un vrai inter-mot rend `هُدًى لِّلْمُتَّقِينَ`.
(Intuition initiale de l'utilisateur sur les extrémités : validée.)

### Deux propositions RETIRÉES par la mesure

- **Critère de silence RELATIF (RMS ≤ 3 % du niveau de parole local).** Il
  sépare pourtant parfaitement le faux silence intra-mot (ratio 0,089) des 5
  vrais inter-mots connus (0,005–0,020). Mais simulé bout en bout, il **affame
  la recherche** : session B passe de 5 cœurs (5/5 justes) à 4, session A d'un
  cœur de 3,9 s à un cœur de 5,7 s. Net neutre à négatif → **non implémenté**.
- **Recouvrement audio aux extrémités** (idée utilisateur). Mesuré : le cœur
  seul gagne ou égalise **5 fois sur 5**. ±300 ms détruit `هُدًى لِّلْمُتَّقِينَ` →
  `هُ` ; ±800 ms détruit `الٓمٓ` → `م ۚ ۚمُ`. Le contexte ne compense pas, il
  déclenche la dérive en allongeant le segment. → **non implémenté**, documenté
  pour ne pas être retenté à l'aveugle.
- **Ne pas verrouiller le mot de tête** : sa cause disparaît, et ne pas
  verrouiller la tête **gèlerait l'ancre** (échec v1 `mots=1`). → **retiré**.

### Ce qui EST implémenté : cible fixe 3,0 s

`TARGET_SECONDS = 3.0f`, bornes 2,5–3,5 s, et **suppression complète de
`secPerWord`** (+ son EMA, `WORDS_PER_SEGMENT`, `DEFAULT_SEC_PER_WORD`,
`lastFinalSamples`).

Justification : à 3,08 s on obtient 5 mots justes ; le débit d'avancement de
l'ancre est le même qu'à 5,5 s ; mais le retard de validation vaut la durée du
segment. Même précision, même avancement, **retard divisé par deux**.

⚠️ Le plafond à 3,5 s est justifié par le RETARD, **jamais** par l'acoustique —
noté explicitement dans le code pour qu'un futur agent ne croie pas à une limite
de stabilité du modèle.

Validation par simulation avant de toucher au Kotlin (règle CLAUDE.md) : avec
cible fixe 3 s et le critère de silence actuel, session B donne **5 cœurs sur 5
justes** sur l'audio où l'app produisait des déchets.

## 2026-07-25 16:32 — Cible fixe 3 s : retard RÉGLÉ, désynchronisation isolée

### Ce qui est réglé

| | avant (14:48) | maintenant (16:32) |
|---|---|---|
| coupes / gels | 5 / 15 | **13 / 13** |
| durées de segment | 2,3,2,2,2,4,6,2,6,**7**,5,2,3,3,3 s | 2,3,3,2,2,3,2,3,3,3,3,2,4 s |
| retard | 2,7 → **17,1 s** | **2,58 – 4,93 s** (médiane ~3,5 s) |
| `secPerWord` | 1,00 → 1,53 (emballé) | supprimé |
| exceptions `defunct` | 24 148 | **0** |

### Ce qui reste : l'ancre décroche

Progression de l'ancre : 0→3→5→10→12→15→19→**20→25→26→27→27→28→28**.
À partir de seq=20, `mots=1` ou `mots=0` par gel alors que l'utilisateur récite
des versets entiers. Il s'est arrêté en constatant que « la validation ne me
suit pas » — l'ancre était à 28, lui au mot 43.

**La chaîne exacte, avec les lignes du log :**

1. `seq=20` — `segment FIGE 3s : "وَمَآ أُنزِلَ مِنبِ"`,
   `ancre=25 frontiere=25 final=true mots=1 nouvelle_ancre=26 differe=26`.
   L'audio contient clairement les mots 25 (`وَمَآ`), 26 (`أُنزِلَ`), 27 (`مِن`)
   et le début de 28. **L'aligneur n'a placé QUE le mot 25.** L'ancre avance de
   1 — et l'audio des mots 26 et 27 est **jeté avec le segment**.
2. `seq=22` — audio = mots 29-31 (`وَبِٱلْـَٔاخِرَةِ هُمْ يُوقِنُونَ`), ancre = 26 :
   `[GOP] mot=26 "أُنزِلَ" gop=-20.00 forced=-20.00 free=0.00 entendu="" -> error (lock=true, final=true)`
   **Rouge définitif sur un mot qui AVAIT été prononcé, jugé sur un audio qui ne
   le contient pas.**
3. `seq=25` — idem : `mot=27 "مِن" ... entendu="" -> error`.
4. L'écart se creuse et ne se rattrape jamais.

**Pourquoi l'aligneur ne place qu'un mot** : dans `ForcedAligner`, la boucle de
construction des résultats **`break`** au premier mot qui reçoit zéro frame de
la DP (`if (wordFrames[wi] == 0) … break`). Sur seq=20, le mot 25 avait
`forced=-5.33` contre `free=-0.02` — chemin DP fortement déformé — le mot 26 n'a
reçu aucune frame, la boucle a cassé, `mots=1`.

### CAUSE RACINE

**Le buffer jette TOUT le segment alors que l'ancre n'avance que sur ce que
l'aligneur a placé.** Toute sous-couverture détruit donc définitivement l'audio
des mots non placés, qui sont ensuite tamponnés rouges sur de l'audio étranger.
La couche où l'information est perdue est la purge du buffer, pas le jugement.

### Correctif proposé (non implémenté, en attente de validation)

Purger seulement l'audio **réellement consommé**. `ForcedAligner.buildFrom`
calcule déjà `lastUsedFrame` (lignes 469 et 562) et le renvoie via
`Pair<Result, Int>` — mais `align()` le **jette** (signature `Result?`). Le
remonter dans `Result` est un changement de 3 lignes ; `BufferedTranscriber`
purge alors jusqu'à `lastUsedFrame` converti en samples (1 frame = 80 ms :
sous-échantillonnage 8× × hop 10 ms) au lieu de `snapshot.size`.

Bénéfice de fond : le segment suivant démarre **exactement sur une frontière de
mot connue de l'aligneur** — strictement mieux que n'importe quelle heuristique
RMS, et ça attaque directement ce que la mesure a désigné comme facteur dominant
(la qualité du DÉBUT de segment).

Ce n'est pas un recouvrement : l'audio conservé n'a jamais été jugé, donc le
piège de duplication (`ForcedAligner` « TENTATIVE 1 », fenêtre glissante naïve à
WER > 100 %) ne s'applique pas.

Effets de bord à arbitrer :
- Le buffer peut croître si la sous-couverture persiste. `MAX_SEGMENT_SECONDS`
  (12 s) reste le garde-fou, mais le pire cas devient un segment de 12 s.
- Durées de segment irrégulières (un segment couvert jusqu'à 1,2 s laisse 1,8 s
  de tête au suivant).
- Le retard de certains mots augmente d'un segment — mais aujourd'hui ils ne
  sont pas validés du tout, ils sont mis en rouge.
- **Ça ne corrige pas la sous-couverture elle-même** (pourquoi `وَمَآ` obtient
  `forced=-5.33` reste à élucider) : ça la rend non destructive. Question
  distincte, à traiter ensuite.

## 2026-07-25 17:15 — Implémenté : purge de l'audio consommé + pas de verdict sans preuve

Validé par l'utilisateur (B + A + C ; D volontairement écartée).

### B — Purger seulement l'audio réellement consommé (cause racine)

`ForcedAligner.Result` expose désormais `lastFrame` (la dernière frame consommée
par le dernier mot placé) — `buildFrom` la calculait déjà mais `align()` la
jetait. `BufferedTranscriber` **aligne d'abord, purge ensuite**, et ne retire du
buffer que `(lastFrame + 1) × samplesPerFrame`.

`samplesPerFrame` est **déduit** (`snapshot.size / logprobs.size`), jamais codé
en dur : le facteur de sous-échantillonnage est une propriété du modèle exporté,
une constante fausse ne se verrait pas et décalerait tout.

Le texte figé n'est plus celui du segment entier mais celui des frames
consommées (`greedyDecode(logprobs, toFrameIncl)`) — sans quoi la queue audio
conservée réapparaîtrait une seconde fois dans le transcript au segment suivant,
la duplication qui avait mis la fenêtre glissante naïve à WER > 100 %.

Garde-fou anti-blocage : si **aucun** mot n'a été placé (`lastFrame < 0`, cas
`mots=0`), on purge tout comme avant. Conserver le buffer là gèlerait la session
(on recommitterait sans fin le même audio sans progresser).

Nouveau log : `segment FIGE 3s -> 214ms | consomme=1120ms conserve=1915ms | …`

### A — `entendu=""` interdit tout verdict positif

Le test `!hasSpeech` a été **remonté au-dessus** du laisser-passer
Al-Fatiha/Basmala, qui le contournait. Preuve mesurée (log 16:32), même absence
totale de son donnant des verdicts opposés :

```
mot=3  "ٱلرَّحِيمِ" forced=-18.99 entendu="" -> correct  (laisser-passer basmala)
mot=26 "أُنزِلَ"    forced=-20.00 entendu="" -> error
```

Le laisser-passer existe pour un problème de **calibration** (basmala récitée
~44 % plus vite dans le dataset). Sans aucun son, il n'y a rien à calibrer.
Le commentaire du Finding #9 (2026-07-16) est conservé sur place avec la mention
« remonté le 2026-07-25, ne pas le redescendre ».

### C — Provenance de `entendu` tracée

`ForcedAligner.WordResult.actualFromFree` → payload `srcFree` →
`AlignedWord.actualFromFree` → log `entendu="…" src=dp|libre`.

Motif : `actual` **décide la couleur** (`textMatches` court-circuite le gop), et
la « validation globale » (déclenchée **4 fois** dans le log du 16:32) le remplace
par le décodage libre GLOBAL du segment. Ce n'est alors plus une mesure de CE
mot — et sur un passage à mots répétés (2:4 contient `أُنزِلَ` aux index 23 ET 26,
`بِمَآ`/`وَمَآ` aux index 22 et 25) l'attribution par le texte ne peut pas
distinguer les occurrences. Sans cette trace, une ligne `entendu="بِمَآ"` était
indéchiffrable.

### D — écartée pour l'instant

Retirer la substitution par le décodage libre sur les mots répétés ferait
réapparaître d'anciens faux rouges (`لَآ`, `إِيَّاكَ` : forced très négatif, texte
exact). Le vrai correctif est celui que le commentaire du code nomme déjà — un
GOP invariant au découpage BPE. Contexte utile mesuré : **1 990 mots sur 6 110
(33 %)** sont tokenisés par le repli glouton de `CtcTokenizer`
(`hits=4113 misses=1987`), donc pour un tiers du texte la suite de pièces imposée
à l'aligneur est une supposition.

### À vérifier au prochain test
- `consomme=` / `conserve=` cohérents, et l'ancre qui **suit** le récitateur.
- Plus aucun `entendu="" -> correct`.
- `src=libre` vs `src=dp` sur les mots à `forced` très négatif.
- Pas de duplication de texte dans le transcript.
- Pas de croissance sans fin du buffer (`segment FIGE` doit rester ≤ 12 s).
