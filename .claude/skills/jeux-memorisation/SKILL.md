---
name: jeux-memorisation
description: Implémenter, faire évoluer ou déboguer les modes de jeu d'aide à la mémorisation coranique (rappel progressif par palier, et tout futur mode ludique de mémorisation). Utilise ce skill dès que la demande touche à un mode "jeu" pour mémoriser une sourate/aya, à l'ajout de paliers/niveaux de difficulté progressifs, ou à un écran de type flashcard/révélation progressive de mots. S'applique même si l'utilisateur ne dit pas "jeu" explicitement — par exemple "aide à la mémorisation avec des paliers", "cache des mots progressivement", "mode où je clique pour révéler".
---

# Mode jeu — mémorisation par rappel progressif

Fonctionnalité demandée le 2026-07-22 : un mode "jeu" où l'utilisateur choisit une
sourate (ou une aya de départ), et le texte se révèle par **paliers progressifs**
pour l'entraîner à réciter de mémoire.

## Mécanique validée avec l'utilisateur (ne pas re-dériver — corrigée le 2026-07-22)

⚠️ Une première implémentation (rappel progressif "mots affichés puis cachés
par tirets, tap pour révéler") était **fausse** — l'utilisateur l'a corrigée
explicitement le 2026-07-22 après l'avoir testée. La vraie mécanique est un
**QCM séquentiel mot par mot**, pas une révélation de tirets :

- Palier 1 : le mot 1 du verset s'affiche seul à l'écran (ex. "الحمد"). Il
  disparaît dès qu'on le valide.
- Palier 2 : l'écran affiche un **choix de plusieurs mots mélangés**, dont le
  mot 2 correct ("لله") et des **leurres**. L'utilisateur doit taper sur le
  bon mot pour continuer.
- Palier 3, 4, ... : même principe, un nouveau jeu de choix mélangés à chaque
  mot, tant que les réponses sont bonnes.
- Verset suivant : une fois le dernier mot du verset validé, on repart au
  palier 1 du verset suivant.
- **Leurres** : piochés parmi les autres mots de la même sourate (ceux qui
  n'ont pas encore été atteints dans la progression), pas au hasard dans tout
  le Coran — cohérence avec ce qui est en cours de mémorisation.
- **Mauvais mot cliqué** : pas de pénalité ni de retour en arrière — un
  feedback visuel léger (ex. tremblement/flash rouge bref) puis les mêmes
  choix restent affichés, l'utilisateur retente.
- Le mot précédemment validé **disparaît** de l'écran (pas de phrase qui se
  construit visuellement) — seul le jeu de choix courant est visible à
  l'écran à un instant donné.
- Pas de reconnaissance vocale (ASR) ni de saisie clavier : uniquement du tap
  sur un mot parmi une liste de choix affichée.

## Portée d'une session — décision utilisateur 2026-07-22

Ne JAMAIS lancer une session sur une sourate entière si elle s'étend sur
plusieurs pages du Mushaf (ex. Al-Baqarah, 286 versets) : demander d'abord
l'aya de départ (`MemorizationAyahPickerScreen`), puis limiter la session aux
versets de LA MÊME PAGE à partir de cette aya (`Verse.pageNumber`, comparaison
`>= chosen.ayahNumber` sur la même page — jamais toute la sourate). Détection
"sourate multi-page" : `verses.map((v) => v.pageNumber).toSet().length > 1`
(cf. `coach_hub_screen.dart`, zone Jouer). Pour une sourate tenant sur une
seule page, le jeu démarre directement dessus, pas de sélecteur d'aya.

Piège déjà rencontré et corrigé : la première version affichait un indicateur
de progression avec **une icône par verset** — inoffensif sur une petite
sourate, mais 286 icônes sur Al-Baqarah débordaient l'écran et masquaient le
jeu lui-même. Tout indicateur de progression doit être de taille FIXE quel
que soit le nombre de versets (barre de progression, pas une icône par
élément) — ne jamais réintroduire ce pattern sans le tester mentalement sur
Al-Baqarah (286) et An-Nisa (176).

## Identité visuelle — décision utilisateur 2026-07-22

Cet écran cible un **public enfant** et doit **trancher visuellement** avec le
reste de l'app (sobre, palette crème/vert/laiton façon manuscrit ancien).
Palette dédiée `AppColors.game*` dans `app_theme.dart` (fond dégradé clair,
puces de choix "bonbons" saturées, vert/rouge de feedback, or pour les
étoiles) — **jamais** les mêmes hex que les palettes tajwid/mindmap (même
règle anti-collision déjà en vigueur pour ces deux-là). S'inspirer des codes
des applis de jeu grand public pour enfants : gros boutons ronds, animations
de rebond/tremblement au tap, récompense visuelle (étoiles) à la fin plutôt
qu'un simple texte. Police `GoogleFonts.baloo2` (ronde, ludique) pour les
titres/UI de cet écran uniquement — le texte arabe du Coran reste toujours en
`scheherazadeNew` comme partout ailleurs dans l'app, ne jamais y toucher.

## Où ça s'intègre dans l'app

- Suivre le principe déjà établi dans `coach_hub_screen.dart` (§"CoachHub
  ORCHESTRE des écrans existants, il ne les réimplémente pas") : ce nouveau
  mode doit être un écran autonome (`lib/screens/memorization_game_screen.dart`
  ou nom similaire), accessible depuis le hub Coach (zone "Mémoriser" ou une
  nouvelle zone dédiée), pas mélangé dans un écran existant.
- Récupérer le texte source via `QuranApi` (`lib/services/quran_api.dart`),
  déjà 100% local (`assets/data/quran_verses.json`/`quran_chapters.json`) — ne
  pas retélécharger ou dupliquer les données de sourates.
- Le modèle `Verse` (`lib/models/verse.dart`) expose `textUthmani` (texte
  arabe). Découper en mots via un split sur les espaces ; attention aux
  diacritiques (tashkeel) qui font partie du mot arabe et ne doivent pas être
  traités comme des séparateurs.
- Suivre les conventions Riverpod existantes : un `StateNotifierProvider` (ou
  équivalent) pour l'état du palier courant + les mots déjà révélés, similaire
  en esprit à `last_coach_verse_provider.dart`.
- UI : `GoogleFonts.scheherazadeNew` pour le texte arabe (cohérent avec le
  reste de l'app, cf. `coach_hub_screen.dart`), palette `AppColors` de
  `lib/theme/app_theme.dart` (ne pas inventer de nouvelles couleurs sans
  vérifier qu'elles ne collisionnent pas avec celles du mind-map ou du
  tajwid — cf. historique de collision de couleurs documenté dans
  `REFONTE_IHM.md`).

## i18n — obligatoire dans les 3 langues dès l'implémentation

Le projet a une infrastructure i18n complète et récente (2026-07-20, cf.
`mind_map_provider.dart`/`app_*.arb`) : **toute nouvelle chaîne UI doit être
ajoutée aux 3 fichiers `.arb`** (`app_fr.arb`, `app_en.arb`, `app_ar.arb`) puis
régénérée via `flutter gen-l10n` — ne jamais coder une chaîne en dur dans le
nouvel écran. Pour l'arabe, composer nativement (pas de traduction mot à mot),
comme cela a été fait pour les cartes mentales.

## Choix de sourate/aya de départ

Réutiliser `surah_picker_screen.dart` (déjà utilisé ailleurs dans l'app, ex.
`CoachHubScreen`) pour le choix de la sourate — ne pas recréer un sélecteur de
sourate ad hoc.

## Après implémentation

- `dart analyze` sur les fichiers touchés doit être propre avant de considérer
  la tâche terminée.
- Rebuild + `adb install -r` sur le téléphone connecté (cf. `HANDOFF.md` pour
  l'état du device) — mais **ne pas naviguer dans l'UI ni prendre de
  screenshot soi-même** sauf demande explicite : l'utilisateur teste lui-même
  (règle établie during la session mind-map, 2026-07-22).
