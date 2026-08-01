# Revue application — structuration (état au 2026-08-01)

## 0. Méthode et périmètre

Ce document consolide en un seul endroit une revue orale/dictée de
l'application, donnée dans le désordre, section par section en suivant le
parcours réel : accueil → réglages → menu d'une sourate → lecture →
traduction → mémoriser (Coach) → une vision alternative de l'entraînement →
récitation continue. **Rien n'est implémenté ici.** Pour chaque point :
- **Constat/demande** : reformulation fidèle de ce qui a été dit.
- **État vérifié** : ce que le code montre RÉELLEMENT (fichier:ligne), quand
  ça a été audité cette passe — sinon marqué explicitement "non vérifié".
- **Statut** : bug confirmé / feature à construire / vision à arbitrer.

Ce fichier est la base d'un enchaînement de correctifs. Rien ne se code avant
d'avoir validé chaque point un par un (règle du projet : proposer et attendre
la validation avant de développer — un chantier qui touche un seuil ou un
critère de jugement passe en plus par le skill `solution-de-fond`).

**Hors périmètre, explicitement** : les réglages/écrans de Calibrage et de
Recette (les deux `FloatingActionButton` de l'accueil). Intacts, à ne pas
toucher — ils seront supprimés une fois la phase de recette terminée. Ne pas
les inclure dans les chantiers ci-dessous.

**Une clarification de transcription** : l'onglet cité "innovation" est
presque certainement l'onglet **Invocations/Duas** (`DuasScreen`, 2ᵉ onglet
réel de `main.dart`) — "innovation" ressemble à une confusion de dictée avec
"invocations". À confirmer si ce n'est pas ça.

---

## 1. Réglages globaux

### 1.1 Mode clair/sombre (nouveau — à construire entièrement)

**Demande** : ajouter un réglage clair/sombre, en particulier utile pour
l'écran de récitation (usage probable en contexte peu éclairé — mosquée,
nuit).

**État vérifié** : l'app n'a **aucun mécanisme de thème sombre**, même
partiel ou débranché.
- `theme/app_theme.dart:117-130` : une seule méthode `AppTheme.light()`,
  palette crème/vert/laiton figée. Pas de `AppTheme.dark()`.
- `main.dart:43-46` : `MaterialApp(theme: AppTheme.light())` — pas de
  `darkTheme`, pas de `themeMode`.
- Recherche exhaustive de `ThemeMode`/`Brightness`/`darkTheme` sur tout
  `providers/` et `main.dart` : zéro résultat.

**Statut** : fonctionnalité neuve, à concevoir de zéro (palette sombre à
définir, provider de préférence persistée, câblage `MaterialApp`).
**Question ouverte** : sombre sur toute l'app, ou prioritairement sur le flux
de récitation/lecture comme mentionné ?

### 1.2 Calibrage / Recette

Rappel : hors périmètre (cf. §0), aucune action ici.

---

## 2. Menu d'une sourate (Lire / Favoriser / Mémoriser / Traduction / Écoute / Plus)

**Non vérifié dans le code cette passe** — repris tel que décrit à l'oral. À
confirmer avec le code de l'écran de détail sourate avant de bâtir quoi que
ce soit dessus (nom exact des entrées, icônes, écran cible de chacune).

---

## 3. « Lire » — lecture audio du Mushaf

### 3.1 Bug play/pause signalé

**Constat** : "quand je fais pause, il recommence" — play/pause ne se
comporte pas comme sur une app audio normale.

**État vérifié** : le code de `pause()`/`resume()` semble correct à première
lecture — **le bug tel que décrit n'est PAS reproduit dans ces deux
fichiers** :
- `services/audio_player_service.dart:54-55` — `pause()` appelle seulement
  `_player.pause()`, `resume()` seulement `_player.resume()`. Aucun
  `dispose()`, aucune recréation du lecteur, aucun `seek(Duration.zero)`.
- `providers/player_provider.dart:66-74` — `PlayerNotifier.pause()`/
  `resume()` mettent juste à jour `state.status`, sans jamais rappeler
  `play(verse, playlist)` (qui, lui, rechargerait la source depuis le début).

Deux bugs **voisins mais différents** ont déjà été corrigés le 2026-07-28 et
sont documentés en commentaire :
- pause **sans effet** pendant une fenêtre réseau en streaming
  (`audio_player_service.dart:32-40`) ;
- l'audio **repart tout seul** juste après une pause en toute fin de piste
  (`player_provider.dart:140-148`).

Ni l'un ni l'autre ne correspond exactement à "je fais pause, il recommence".
**Hypothèse** : soit un troisième bug non encore localisé (écran
`mushaf_screen.dart` non audité cette passe — un appel `play()` au lieu de
`resume()` quelque part côté UI est plausible), soit une confusion avec l'un
des deux bugs déjà connus, soit un comportement natif Android du plugin
`audioplayers` non visible côté Dart.

**Statut** : bug réel signalé, cause exacte **non confirmée** — nécessite un
retest ciblé sur device avec logs avant tout correctif (ne pas corriger à
l'aveugle un code qui semble déjà correct).

### 3.2 Regroupement des réglages du menu « ⋮ »

**Demande** : regrouper défilement automatique, arrêt lent/rapide, vitesse de
lecture, répétitions — actuellement dispersés.

**État vérifié partiellement** : la vitesse de lecture et les répétitions
vivent déjà dans un seul et même endroit, `widgets/reading_settings_sheet.dart`
(§3.3 ci-dessous pour le détail des répétitions). Reste à confirmer si le
défilement automatique et l'arrêt lent/rapide sont bien dans **ce même**
fichier ou ailleurs — non vérifié cette passe. Si c'est déjà le cas, la
demande est peut-être déjà satisfaite côté données et il ne reste qu'un
problème de **découvrabilité** (le point d'entrée « ⋮ » n'est peut-être pas
celui qui ouvre cette sheet).

**Statut** : à vérifier avant de trancher si c'est un chantier de
regroupement ou un chantier de découvrabilité (menu qui pointe au bon
endroit).

### 3.3 Refonte des paramètres de répétition (Lecture Mushaf)

**État actuel vérifié** — `widgets/reading_settings_sheet.dart:210-239`, six
choix fixes en `ChoiceChip` :

| Mode | Valeur | Libellé |
|---|---|---|
| off | — | Désactivé |
| verse | 3 | Répéter le verset 3 fois |
| verse | 5 | Répéter le verset 5 fois |
| verse | 10 | Répéter le verset 10 fois |
| verse | ∞ | Répéter le verset à l'infini |
| surah | — | Répéter la sourate |

Stocké en mémoire seulement (`PlayerStateModel.repeatMode`/`repeatCount`,
`models/player_state_model.dart`), **pas persisté** entre deux lancements de
l'app (contrairement au récitateur préféré, qui lui l'est).

**Constat utilisateur** : "c'est mal paramétré". Il manque un vrai second axe
— aujourd'hui on choisit une seule valeur dans une liste plate qui mélange
deux notions différentes.

**Proposition (vision à arbitrer)** : deux paramètres orthogonaux, comme deux
boucles imbriquées :
1. **Boucle interne — nombre de répétitions** : combien de fois rejouer le
   bloc choisi avant de passer au suivant.
2. **Boucle externe — portée du bloc** : quelle taille de bloc on répète —
   d'**un verset** jusqu'à **la sourate entière**, par un curseur continu
   (1 verset → 2 versets → 3 versets → … → sourate), **pas** de seuil fixe
   arbitraire ("à partir de 20 versets c'est la sourate").
3. Suggestion : la première boucle (portée) peut démarrer petite (1 à 3
   versets max) puis s'élargir par paliers — écho direct au mécanisme de
   paliers cumulatifs proposé en §6 pour le Coach, à possiblement unifier.
4. **Attachement à Lire** : proposition qu'un clic sur « Lire » ouvre une
   feuille de paramétrage de ces deux axes avant de démarrer (plutôt qu'un
   réglage caché dans un sous-menu).

**Statut** : remplace `RepeatMode`/`repeatCount` actuels — nouveau modèle de
données + nouvelle UI. Pas un bug, une refonte à concevoir puis faire
valider avant code.

---

## 4. Traduction

**Constat utilisateur** : fonctionne bien, rien à changer. Suit la langue
choisie dans Réglages ; clic sur un mot ouvre la cascade d'explications.
Confirmé fonctionnel par l'utilisateur — **aucune action requise ici**.

---

## 5. « Mémoriser » (Coach 3 étapes) — état des lieux

### 5.1 Question Whisper/FastConformer — RÉSOLU cette session

**Constat utilisateur** : en Contrôle, le spinner affiche "Analyse Whisper en
cours…" — deux modèles tournent-ils ?

**Réponse vérifiée** : non, un seul modèle réel (**FastConformer CTC**). La
classe `WhisperOnnxVerifier` (`recitation_provider.dart:112-115`) est un nom
**hérité** de l'époque où Whisper était le modèle de prod ; son code délègue
entièrement à `FastConformerVerifier`
(`services/recitation_verifier.dart:1047-1050`, whisper.cpp explicitement
désactivé). Détail complet dans
[COACH_MEMORISATION_PAR_VERSET.md §7](COACH_MEMORISATION_PAR_VERSET.md).
Correctif cosmétique (renommer la classe + corriger 2 libellés « Whisper »)
déjà listé dans `PLAN_CORRECTION_IHM.md`.

### 5.2 Redondance Lecture → Entraîne → Contrôle

**Constat utilisateur** : le Coach actuel est lourd — Lecture, puis Entraîne
(Écoute/Imite/Répète), puis Contrôle ; trop de clics/validations manuelles à
chaque étape, sensation de répétition entre les phases.

Fonctionnement actuel détaillé dans
[COACH_MEMORISATION_PAR_VERSET.md](COACH_MEMORISATION_PAR_VERSET.md) (écrit
cette session). Bug du palier bloqué (spinner infini en étape Répète) déjà
diagnostiqué, correctif d'un mot proposé et **en attente de validation** —
non encore appliqué.

**Statut** : l'utilisateur ne demande pas de casser ce mode — il propose une
alternative en §6, à construire **en parallèle**, à comparer ensuite.

---

## 6. Vision alternative — entraînement audio par paliers cumulatifs (nouveau, à construire en complément)

Idée développée pendant la session, présentée comme un **complément**, pas un
remplacement du Coach actuel (§5) — l'utilisateur ne sait pas encore lui-même
comment faire le pont entre les deux, et demande explicitement de l'aide pour
l'analyser et l'intégrer, ou à défaut de le construire à côté pour comparer.

### 6.1 Principe général

Un mode **guidé, automatique, orienté audio en premier** — l'écoute suffit,
regarder le texte à l'écran devient optionnel (peut rester affiché, mais
n'est plus nécessaire pour progresser). Le modèle connaît le texte attendu
dès le départ (comme aujourd'hui), mais l'enchaînement des paliers est
**100% automatique** : pas de bouton à valider entre deux tentatives.

### 6.2 Le palier — unité de travail, granularité réglable

- **Mode adulte + tajwid** (traités comme un couple, cf. §6.5) : un palier =
  un bloc de mots, taille réglable (suggestion de départ : 2 à 5 mots, pas de
  minimum imposé à 2 — peut démarrer à 5 selon la sourate).
- **Découpage conscient du waqf** : quand la limite naturelle du palier tombe
  près d'un point d'arrêt (waqf) **autorisé**, couper là plutôt qu'au compte
  de mots brut — jamais couper sur un waqf **interdit**. À utiliser comme
  règle de l'algorithme de découpage.
- **Curseur de granularité continu** : de "N mots" jusqu'à "un verset entier"
  jusqu'à "la sourate" — pas des seuils fixes. Un verset court peut être un
  palier entier à lui seul ; un verset qui prend une page entière reste
  découpé en blocs de mots.
- **Mode enfant** : granularité ~1 mot par palier, progression réglée
  indépendamment du mode adulte (un enfant peut aussi choisir le mode
  adulte s'il le souhaite — la séparation n'est pas une barrière technique).

### 6.3 Mécanique cumulative — algorithme NOUVEAU, différent de l'existant

⚠️ Ceci est un algorithme **différent** de la fenêtre glissante déjà
implémentée dans `coach_incremental_repeat.dart` (cf.
[COACH_MEMORISATION_PAR_VERSET.md §4.3](COACH_MEMORISATION_PAR_VERSET.md)) :
l'existant fait glisser une fenêtre de **taille fixe** qui avance d'une unité
à chaque succès (jamais de cumul, jamais de reset). Le mécanisme décrit ici
est **cumulatif jusqu'à un plafond, puis repart sur une base neuve** — à ne
pas confondre.

Deux paramètres : **taille du palier** (§6.2) et **plafond de cumul** (`N`,
ex. 3 dans l'exemple donné). Déroulé exact donné par l'utilisateur pour
plafond = 3 :

```
palier 1 seul           → réussi
palier 2 seul           → réussi
palier 3 seul           → réussi
palier 1+2+3 (cumul)    → réussi  ── plafond atteint, nouveau cycle
palier 4 seul           → réussi  ── PAS 2+3+4 : on repart à zéro
palier 5 seul           → réussi
palier 4+5 (cumul)      → réussi
palier 6 seul           → réussi
palier 4+5+6 (cumul)    → réussi  ── plafond atteint, nouveau cycle
palier 7 seul           → …
```

- Un échec ne fait **pas reculer** : le même palier (ou cumul en cours) est
  simplement rejoué et retenté — même logique de retry que l'existant.
- **Contrainte de découpage au reset** : un nouveau cycle doit démarrer sur un
  waqf autorisé ou une fin de verset — jamais couper la reprise en plein mot
  ou en pleine construction grammaticale.

### 6.4 Cycle d'interaction — entièrement automatique

1. Le réciteur (audio) énonce le palier courant.
2. L'utilisateur répète.
3. Un seuil d'acceptation détermine réussite/échec.
4. Échec → le réciteur redit **le même** palier, nouvel essai — sans action
   manuelle de l'utilisateur pour relancer.
5. Réussite → enchaînement automatique vers le palier/cumul suivant selon
   §6.3 — pas de bouton "suivant" à taper.

### 6.5 Portée : adulte+tajwid ensemble, enfant à part

Décision actée par l'utilisateur : le mode tajwid et le mode adulte
partagent ce mécanisme de paliers (mêmes réglages de granularité/plafond) ;
le mode enfant est traité par une branche indépendante de l'algorithme
(granularité mot-à-mot), sans empêcher un enfant de basculer sur le mode
adulte s'il le souhaite.

### 6.6 Lien avec le Contrôle

Une fois l'entraînement par paliers terminé, le mode **Contrôle** démarre en
continu à partir du point atteint — pas de répétitions, récitation en flux
jusqu'à la fin (ou jusqu'à blocage, cf. §7). C'est conceptuellement le mode
« récitation continue » déjà existant (karaoké), mais dont le comportement de
blocage doit changer — voir §7, qui s'applique aussi bien ici qu'à la
récitation classique.

### 6.7 Statut et question ouverte (posée explicitement par l'utilisateur)

Comment articuler ce mode avec le Coach 3-étapes existant (§5) — l'utilisateur
n'a pas de réponse tranchée et demande explicitement de l'aide pour
"trouver le pont", ou à défaut de construire ce mode **en parallèle**, sans
casser l'existant, pour comparer ensuite. **Ne pas trancher unilatéralement
cette architecture — à discuter avant tout code.**

---

## 7. Récitation continue — redéfinir le déclencheur de blocage

**État vérifié** — confirmé exactement conforme au constat utilisateur :
aujourd'hui, en mode "avec blocage", **un seul mot mal reconnu** déclenche
systématiquement un blocage complet (pause de capture + recul de l'ancre +
audio de correction rejoué), quel que soit le contexte.

- Déclencheur : chaque émission sur le flux `wordFailed`
  (`recitation_provider.dart`, alimenté lignes 2766/3713/3732/3748) appelle
  `_onWordFailed` (`karaoke_recitation_screen.dart:519`) — **un mot = un
  événement**, aucune agrégation de plusieurs mots consécutifs.
- La seule tolérance existante, `followWithoutBlockingProvider`
  (`app_settings_provider.dart:257-263`, activé par défaut), n'empêche de
  rebloquer QUE si c'est **le même mot** déjà corrigé une fois
  (`karaoke_recitation_screen.dart:632-639`) — pas une notion de "décrochage"
  sur plusieurs mots différents.

**Constat/demande utilisateur** : une erreur isolée (haraka, lettre,
prononciation) sur un mot au milieu d'une récitation par ailleurs fluide ne
devrait **pas** bloquer — juste se colorer et laisser continuer. Le blocage
ne devrait se déclencher que quand le réciteur **perd réellement le fil** :
plusieurs mots consécutifs (2-3) qui ne s'alignent pas du tout avec le texte
attendu (signe d'un saut de verset ou d'un vrai décrochage). Dans ce cas
précis : le modèle doit rejouer l'audio **depuis le point de décrochage**
pour raccrocher le réciteur — pas seulement bloquer sur le mot fautif isolé.

**Statut** : c'est un changement de **critère de jugement/déclenchement**
sur la chaîne de récitation. Rappel de la règle du projet : ce type de
changement passe par le skill `solution-de-fond` avant tout correctif — et
par une proposition explicite + validation avant code (effets de bord à
identifier d'abord : risque de laisser passer un vrai décrochage court, ou
au contraire de retarder la correction utile).

---

## 8. Dépendances entre les chantiers

| Chantier | Dépend de | Peut se faire indépendamment |
|---|---|---|
| §1.1 Thème sombre | rien | ✅ |
| §3.1 Bug play/pause | rien (retest ciblé d'abord) | ✅ |
| §3.2 Regroupement menu ⋮ | vérif du contenu réel de reading_settings_sheet.dart | ✅ après vérif |
| §3.3 Refonte répétitions Lecture | — | possible en //, mais partage une idée avec §6.3 (paliers cumulatifs) — à concevoir ensemble pour ne pas inventer deux systèmes différents pour la même notion |
| §5 Coach existant | — | déjà en place, correctif du bug palier (§5.2) indépendant |
| §6 Vision paliers cumulatifs | arbitrage §6.7 (où ça vit dans l'IHM) | non — bloqué tant que §6.7 n'est pas discuté |
| §7 Redéfinition du blocage | `solution-de-fond` (règle projet) | ✅ mais nécessite le skill avant tout code — sert aussi bien à §6.6 qu'à la récitation classique actuelle |

---

## 9. Questions ouvertes à trancher avant tout code

1. §1.1 : thème sombre partout, ou prioritairement sur le flux de
   récitation/lecture ?
2. §2 : confirmer le contenu exact du menu d'une sourate (non vérifié dans le
   code cette passe).
3. §3.1 : retest ciblé du bug play/pause AVANT correctif — le code lu ne
   reproduit pas le symptôme, la vraie cause reste à isoler.
4. §3.2 : le défilement auto et l'arrêt lent/rapide sont-ils déjà dans
   `reading_settings_sheet.dart` (problème de découvrabilité seulement) ou
   ailleurs (vrai regroupement à faire) ?
5. §3.3 / §6.3 : construire un système de granularité/cumul **unique**,
   partagé entre la répétition de Lecture et l'entraînement par paliers du
   Coach, ou deux systèmes séparés par design ?
6. §6.7 : où vit le nouveau mode par paliers dans l'IHM — remplace une entrée
   du hub Coach, s'ajoute à côté, ou vit ailleurs ? Comment bascule-t-on entre
   ce mode et le Coach 3-étapes existant ?
7. §7 : quel seuil exact pour "perdre le fil" (2 mots ? 3 mots ? un mélange
   distance/nombre) — à définir avec mesure avant implémentation, pas une
   valeur choisie à l'aveugle (cf. historique du projet : plusieurs seuils
   empiriques déjà rejetés par la mesure sur ce même sujet de segmentation).
