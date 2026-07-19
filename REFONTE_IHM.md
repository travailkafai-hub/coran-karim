# Refonte IHM — spécification détaillée (2026-07-19)

Demande utilisateur : "c'est une vraie refonte IHM, structure ça d'abord" puis
"détaillé, pour ne pas laisser aux autres agents inventer". Ce document est la
**spécification d'exécution** : un agent qui implémente un lot ne doit avoir
AUCUNE décision de design à prendre — tout ce qui est décidé est ici, tout ce
qui reste ouvert est explicitement listé en §9 comme question à poser à
l'utilisateur (ne pas trancher à sa place).

S'appuie sur : les capacités du modèle hybride (`PLAN_ENTRAINEMENT_HYBRIDE.md`
§5bis — 17 règles de tajwid détectées, tête RNNT, sortie fidèle au prononcé),
la ligne de partage vérification/localisation (`GLOSSAIRE_TECHNIQUES_ASR.md`),
et l'app réelle (`app/lib/` — fichiers vérifiés existants le 2026-07-19).

**Principe directeur verrouillé** : UN seul modèle, UNE sortie fidèle à ce qui
est prononcé. Tous les "modes" sont des **couches de jugement configurables
APRÈS décodage** (jamais des modèles différents, jamais un réentraînement).
Toute implémentation qui dévie de ce principe est une erreur.

---

## 1. Système de vérification unifié : presets + options

### 1.1 Modèle de données (nouveau fichier `app/lib/models/judgement_options.dart`)

```dart
/// Les 17 règles, EXACTEMENT les clés de rules_map.json (benchmark) —
/// ne pas renommer, c'est la jointure avec les symboles du modèle.
enum TajwidRule {
  maddaNecessary,      // "madda_necessary"
  maddaObligatory,     // "madda_obligatory"
  maddaPermissible,    // "madda_permissible"
  maddaNormal,         // "madda_normal"
  ghunnah,             // "ghunnah"
  ikhafa,              // "ikhafa"
  ikhafaShafawi,       // "ikhafa_shafawi"
  idghamGhunnah,       // "idgham_ghunnah"
  idghamShafawi,       // "idgham_shafawi"
  iqlab,               // "iqlab"
  idghamWoGhunnah,     // "idgham_wo_ghunnah"
  idghamMutajanisayn,  // "idgham_mutajanisayn"
  idghamMutaqaribayn,  // "idgham_mutaqaribayn"
  laamShamsiyah,       // "laam_shamsiyah"
  hamWasl,             // "ham_wasl"
  slnt,                // "slnt"
  qalaqah,             // "qalaqah"
}

class JudgementOptions {
  final Set<TajwidRule> activeRules;   // vide = aucune vérification tajwid
  final bool strictHarakat;            // false = harakat ignorées au verdict
  final bool tolerateConfusables;      // true = table CONFUSABLE_PAIRS tolérée
  // Le squelette du mot est TOUJOURS strict (pas une option) : un mot
  // méconnaissable reste faux dans tous les presets.
}
```

Presets (constantes, pas des classes séparées) :

| Champ | `preset tajwid` | `preset adulte` | `preset enfant` |
|---|---|---|---|
| `activeRules` | choix utilisateur (persisté) | `{}` | `{}` |
| `strictHarakat` | `true` | `true` | `false` par défaut (modifiable) |
| `tolerateConfusables` | `false` | `false` | `true` |

- Persistance : dans `app_settings_provider.dart`, même pattern que les
  settings existants (SharedPreferences, une clé par champ :
  `judgement.activeRules` = liste de noms snake_case,
  `judgement.strictHarakat`, `judgement.tolerateConfusables`,
  `judgement.preset` = "tajwid"|"adulte"|"enfant"|"custom").
- Changer une option depuis un preset bascule `preset` à `"custom"` (affiché
  comme tel dans l'UI) ; re-choisir un preset réécrit toutes les options.

### 1.2 La table des confusables (mode enfant)

Copier EXACTEMENT les paires de `benchmark/generate_tts_augmentation.py::
CONFUSABLE_PAIRS` (source de vérité — les paires sur lesquelles le modèle a
été entraîné à être strict, donc celles qu'on sait tolérer sciemment) :
`ص↔س, ط↔ت, ض↔د, ذ↔ز, ح↔ه, ق↔ك, ع↔ء` — en Dart :
`app/lib/data/confusable_pairs.dart`, une `const Map<String, String>`
symétrique (chaque sens présent). Un commentaire doit pointer vers le fichier
Python source et interdire d'éditer un côté sans l'autre.

### 1.3 Le juge (extension de `services/recitation_verifier.dart`)

Algorithme exact, appliqué à la comparaison hypothèse/référence (l'existant
`ArabicNormalizer` a déjà plusieurs niveaux — normalize/normalizeStrict/
normalizeTraining ; en ajouter un paramétré par `JudgementOptions`) :

1. **Symboles de règles** (chars U+E000–U+E010 dans la sortie modèle ET dans
   le texte de référence annoté) :
   - Pour chaque règle NON active : retirer son symbole des deux côtés.
   - Pour chaque règle active : le symbole participe à la comparaison — s'il
     est présent dans la référence mais absent de l'hypothèse au même mot →
     verdict "règle manquée" pour CE mot, avec l'identité de la règle
     (l'app sait dire "qalqala manquée ici", pas juste "faux").
2. **Harakat** : si `strictHarakat == false`, appliquer la fusion des
   diacritiques courts (fatha/damma/kasra/sukun/tanwin) des deux côtés AVANT
   comparaison (étendre la normalisation existante, ne pas en créer une
   parallèle).
3. **Confusables** : si `tolerateConfusables == true`, remplacer dans
   l'HYPOTHÈSE seule chaque lettre par son représentant canonique de paire
   (ex. ص→س) et faire pareil dans la référence — les deux membres d'une paire
   deviennent équivalents. Ne s'applique JAMAIS au preset adulte/tajwid.
4. Le verdict par mot distingue désormais 3 familles d'erreur :
   `lettre` / `harakat` / `règle:<nom>` — nécessaire pour l'UI (couleurs ou
   messages différents) et pour les stats de progression par règle.

⚠️ Le texte de référence annoté (avec symboles) doit être disponible côté
app : embarquer `benchmark/data/quran_tajweed_rules/annotated.jsonl` (6236
versets, ~2 Mo) dans les assets ou le dossier modèles téléchargé — même
convention de déploiement que `word_tokens.json`. NE PAS re-générer côté
Dart : c'est un artefact du pipeline Python, copié tel quel.

### 1.4 Écran de sélection des règles (preset Tajwid)

- Nouvel écran `screens/tajwid_rules_screen.dart`, accessible depuis la sheet
  contextuelle de récitation (§2) ET depuis `settings_screen.dart`.
- Une entrée par règle : nom arabe + translittération + interrupteur + bouton
  "?" ouvrant la fiche (réutiliser `widgets/tajwid_help_sheet.dart` existant,
  l'étendre : chaque fiche = définition courte, exemple de verset type, et
  phrase explicite "ce que l'app vérifie : ...").
- **Fiabilité par règle** (exigence actée dans le plan) : un fichier
  `app/assets/data/rule_reliability.json` versionné AVEC le modèle, généré
  depuis les évals benchmark (pas écrit à la main), schéma :
  ```json
  { "model": "hybrid-rules-v1-stage1b-final",
    "rules": { "qalaqah": {"status": "ready", "recall": 0.96},
               "madda_necessary": {"status": "not_ready", "recall": 0.72},
               "idgham_mutajanisayn": {"status": "insufficient_data"} } }
  ```
  Statuts : `ready` (activable), `not_ready` (grisé, libellé "bientôt
  disponible"), `insufficient_data` (grisé, même libellé). État au
  2026-07-19 : `madda_necessary` not_ready ; `idgham_mutajanisayn` et
  `idgham_mutaqaribayn` insufficient_data ; les 14 autres ready. **Ne jamais
  proposer une règle non-ready** : corriger un élève avec un détecteur peu
  fiable est pire que ne pas corriger.

---

## 2. Navigation : paramètres contextuels par page

- Nouveau widget générique `widgets/context_settings_sheet.dart` :
  ```dart
  showContextSettings(context, sections: [SettingsSection.reading]);
  enum SettingsSection { reading, recitation, judgement, prayerFollow, audio }
  ```
  Il rend les MÊMES tuiles que `settings_screen.dart` (mêmes providers, zéro
  duplication d'état) filtrées par section. Concrètement : extraire les tuiles
  actuelles de `settings_screen.dart` en widgets partagés réutilisés par les
  deux surfaces (l'écran complet et la sheet).
- Affectation des sections par écran :
  | Écran | Icône réglages ouvre |
  |---|---|
  | `mushaf_screen.dart` (lecture) | `[reading, audio]` — c'est l'évolution de `reading_settings_sheet.dart` existant, à faire absorber par le widget générique |
  | `karaoke_recitation_screen.dart`, `recitation_screen.dart`, `coach_screen.dart` | `[judgement, recitation, audio]` |
  | `prayer_follow_screen.dart` | `[prayerFollow, judgement]` |
  | `memorization_screen.dart` | `[recitation, judgement]` |
- `settings_screen.dart` reste l'index complet inchangé dans son rôle.
- Emplacement de l'icône : dans le menu/en-tête de chaque écran (pour la
  lecture plein écran, dans le header rétractable §3 — jamais un bouton
  flottant permanent qui mange de la place, cohérent avec §4).

---

## 3. Lecture : plein écran immersif

Comportement exact (`mushaf_screen.dart` + `widgets/mushaf_header.dart`) :

1. À l'entrée sur l'écran : `SystemChrome.setEnabledSystemUIMode(
   SystemUiMode.immersiveSticky)` — plus de barre système ni d'app bar, tout
   l'écran pour le mushaf. À la sortie (dispose/navigation) : restaurer
   `edgeToEdge` (ne pas laisser l'app entière en immersif).
2. Le header actuel (`mushaf_header.dart`) devient **rétractable** :
   - Masqué par défaut.
   - **Tap sur la zone haute de l'écran (bande de ~15% de hauteur) ou sur le
     titre** → le header glisse depuis le haut (AnimatedSlide/SlideTransition,
     ~200 ms) avec : titre de sourate, navigation, icône réglages (§2),
     bouton mindmap (§7).
   - Se re-masque automatiquement après **4 secondes** sans interaction, ou
     immédiatement sur tap dans la zone de lecture.
   - Le scroll du mushaf ne déclenche PAS l'apparition (seulement le tap —
     sinon il apparaîtrait sans arrêt pendant la lecture).
3. L'audio en lecture garde `mini_player_bar.dart` en overlay bas, dont la
   visibilité suit celle du header (apparaît/disparaît ensemble).
4. Ne pas toucher à la logique de rendu du texte (spans tajwid,
   `tajweed_text.dart`) — uniquement le chrome autour.

---

## 4. Récitation : zéro widget qui rétrécit la page

Décision : "pas besoin de rajouter un autre widget qui rétrécit encore la
page" (récitation audio).

- **Règle de design contraignante** pour `karaoke_recitation_screen.dart` (et
  `recitation_screen.dart`) : AUCUN nouveau bandeau/carte/barre empilé
  verticalement qui réduit la hauteur du texte. Tout indicateur passe en :
  - overlay flottant (coin d'écran, semi-transparent), ou
  - inline dans le texte (couleur/soulignement/badge sur le mot concerné —
    `_KaraokeVerseBadge` existe déjà comme exemple du bon pattern), ou
  - sheet à la demande (`_FullTranscriptSheet` existe déjà — bon pattern).
- Lot concret : **inventorier** les widgets actuellement empilés dans le
  `build()` de `karaoke_recitation_screen.dart` (le fichier fait ~1800
  lignes ; chercher la `Column` racine autour de la ligne ~954) et lister
  ceux qui compriment le texte → pour chacun, décider (avec l'utilisateur)
  s'il migre en overlay ou disparaît. NE PAS supprimer silencieusement une
  info existante.
- Le verdict par règle (§1.4) s'affiche inline : mot souligné + au tap, une
  bulle "qalqala manquée" (pas un panneau permanent).

---

## 5. Page principale : Suivre prière + identification réunies

- `surah_list_screen.dart` (page principale) reçoit une **zone "mains-libres"**
  en haut de liste : deux entrées côte à côte —
  1. **Suivre une prière** → `prayer_follow_screen.dart` (existant).
  2. **Identifier la récitation** (Shazam interne) → aujourd'hui dans
     `widgets/quran_shazam_sheet.dart` ; l'entrée principale ouvre cette
     sheet directement.
- Justification produit (à conserver en commentaire) : les deux répondent à
  "qu'est-ce qui est récité, sans que je le dise à l'app" et reposent sur la
  même capacité de localisation (tête RNNT à terme, §6).
- Ne pas dupliquer la logique : la sheet Shazam existante est réutilisée
  telle quelle, seul le point d'entrée change.

---

## 6. Suivre prière v2 : brancher la tête RNNT

- **v1 pragmatique décidée** : on-device, la localisation reste sur la tête
  CTC actuelle (pipeline `quran_verse_locator_service.dart` existant),
  PENDANT qu'on valide offline (PC, benchmark) le gain réel du décodage RNNT
  sur la tâche de localisation. Raison : le décodage RNNT on-device exige un
  export ONNX supplémentaire (decoder+joint séparés de l'encodeur) + une
  boucle greedy autorégressive en Kotlin — un chantier d'intégration entier
  qu'on ne lance que si le gain est prouvé.
- Mesure offline à faire AVANT tout code app (côté benchmark) : sur un
  échantillon de sessions réelles de `prayer_follow`, comparer le taux
  d'identification correcte du verset CTC vs RNNT (`change_decoding_strategy`
  suffit côté Python). Si RNNT ne gagne pas nettement → ce lot s'arrête là.
- ⚠️ Garde-fou verrouillé (`GLOSSAIRE_TECHNIQUES_ASR.md`) : RNNT sert la
  LOCALISATION uniquement, jamais la vérification.

---

## 7. Carte mentale des sourates (chantier parallèle)

Plan d'une autre session, intégré pour cohérence de navigation :

- **Données** : un JSON par sourate, `app/assets/mindmaps/{NNN}.json`
  (numéro sur 3 chiffres). Schéma exact :
  ```json
  { "theme_central": "string (titre arabe court)",
    "branches": [
      { "side": "left|right",
        "range": "1-8",
        "cat": "croyance|recit|loi|promesse|avertissement|louange",
        "title": "string court",
        "resume": "string 1-2 phrases",
        "children": [ { "v": "1-2", "t": "string" } ] } ] }
  ```
  (6 catégories = 6 nouvelles couleurs à ajouter dans `AppColors` — palette
  manuscrite validée par l'utilisateur, à récupérer auprès de lui, ne pas
  inventer les hex.)
- **Rendu** : package `graphview` (algorithme éventail gauche/droite),
  nouveau `screens/mind_map_screen.dart` :
  - Nœud central : Container circulaire, dégradé brass/vert de `AppTheme`/
    `AppColors`, police Scheherazade New.
  - Nœuds de branche : même style que les cartes existantes (coins arrondis,
    ombre douce), bordure colorée par `cat`.
  - Flip de fiche détail : `Transform` + `Matrix4.rotationY` piloté par un
    `AnimationController` (pas de package tiers).
  - Bouton « Aller au verset » → `MushafScreen(surah, ayah)`. **Vérifier
    d'abord** si `services/quran_verse_locator_service.dart` (non suivi)
    couvre déjà cette navigation avant d'écrire quoi que ce soit.
- **Entrée** : bouton dans le header rétractable du mushaf (§3) ET dans
  `surah_list_screen.dart` (menu contextuel par sourate).

---

## 7bis. Langue principale de l'app (arabe / français / anglais)

Constat utilisateur (vérifié dans le code) : l'UI mélange les langues —
`settings_screen.dart` a un titre arabe (`الإعدادات`) et des sheets en
français ("Vitesse de lecture", "Mode de répétition", "Répétitions de
mémorisation")... Aucune cohérence, aucun réglage.

### Spécification

1. **Nouveau réglage "Langue de l'application"** : `ar` / `fr` / `en`,
   persisté dans `app_settings_provider.dart` (clé `app.locale`), présent
   dans `settings_screen.dart` ET dans toutes les sheets contextuelles (§2,
   section transverse affichée en bas). Défaut au premier lancement : la
   langue système si elle est dans {ar, fr, en}, sinon `fr` (l'utilisateur du
   projet travaille en français — à confirmer, question §9).
2. **Mécanisme standard Flutter** : `flutter_localizations` + `intl` + ARB
   (`app/lib/l10n/app_ar.arb`, `app_fr.arb`, `app_en.arb`), `MaterialApp(
   locale: ..., localizationsDelegates: ..., supportedLocales: ...)` piloté
   par le provider. PAS de solution maison (map de strings à la main) — ARB
   donne la pluralisation, le RTL et l'outillage gratuits.
3. **Chantier d'inventaire** : extraire TOUTES les strings UI codées en dur
   des screens/widgets/providers vers les ARB (grep `Text('`/`Text("` +
   labels/tooltips/snackbars). C'est le gros du travail — le faire écran par
   écran, en commençant par ceux touchés par la refonte (réglages, mushaf,
   récitation, page principale) pour ne pas repasser deux fois.
4. **Logique par langue (décision utilisateur, verrouillée)** :
   | Langue choisie | Menus/UI | Texte coranique | Traductions, explications, mindmap, fiches tajwid |
   |---|---|---|---|
   | **Arabe** | arabe | arabe | **arabe uniquement** — il n'y a QUE de l'arabe à l'écran, aucune traduction affichée |
   | **Français** | français | **arabe (toujours)** | français |
   | **Anglais** | anglais | **arabe (toujours)** | anglais |
   Le texte coranique, les du'as et les noms arabes des règles de tajwid ne
   sont JAMAIS remplacés par une traduction — dans les modes fr/en, la
   traduction ACCOMPAGNE le texte arabe (comme la cascade d'explications le
   fait déjà), elle ne s'y substitue pas.
5. **RTL** : quand `ar` est choisi, toute l'UI passe en RTL (Flutter le fait
   via la locale) — vérifier écran par écran que les layouts asymétriques
   (mindmap gauche/droite, badges karaoké, header mushaf) restent corrects
   en RTL ; le mushaf lui-même est déjà RTL par nature, il ne doit PAS
   double-inverser.
6. **Contenus multilingues existants** : la cascade d'explications
   (`quran_sciences_service.dart`, paliers AR/FR/EN) et le TTS des
   explications (`explanation_tts_service.dart`, voix par langue) suivent
   la langue principale — en mode arabe, ils n'affichent QUE le palier arabe
   (cohérent avec le tableau ci-dessus, pas de mélange).
7. **Mindmap multilingue** (conséquence directe pour §7) : le contenu des
   cartes mentales suit la langue → un fichier par langue,
   `app/assets/mindmaps/{lang}/{NNN}.json` (`ar/`, `fr/`, `en/`), même
   schéma ; `theme_central` reste le titre arabe dans les trois versions
   (c'est un nom coranique), `title`/`resume`/`children[].t` sont dans la
   langue du dossier. Le chargeur prend le dossier de la langue courante et
   se replie sur `ar/` si le fichier n'existe pas encore dans la langue
   demandée.

### Place dans les lots

C'est le **Lot 2bis** — juste après la navigation contextuelle (§2), avant le
plein écran : les écrans refondus en Lot 3+ doivent naître avec leurs strings
en ARB, pas être repassés ensuite.

## 8. Ordre d'exécution & hygiène git (LOT 0 OBLIGATOIRE EN PREMIER)

L'état git de `app/` mélange plusieurs chantiers non commités. Règle CLAUDE.md :
committer par périmètre AVANT la refonte, AVEC l'utilisateur (pas en bloc).

Périmètres du Lot 0 (fichiers constatés dans `git status` au 2026-07-19) :
- (a) ASR/récitation : `fastconformer_verifier.dart`,
  `recitation_verifier.dart`, `recitation_provider.dart`,
  `recitation_state.dart`, `karaoke_recitation_screen.dart`,
  `ForcedAligner.kt`, `diagnostic_log.dart`...
- (b) Suivre prière + Shazam + calibration : `prayer_follow_screen.dart`,
  `quran_verse_locator_service.dart`, `quran_shazam_sheet.dart`,
  `voice_calibration_screen.dart` (tous non trackés).
- (c) Config/tooling : `build.gradle.kts`, manifests, `pubspec.yaml`,
  `gitignore`, styles.
- (d) Docs/assets : `SUIVI_PRIERE.md`, `HANDOFF*.md`, assets data.

Puis les lots, chacun = commits dédiés + test device avant le suivant :

| Lot | Contenu | Dépend de |
|---|---|---|
| 1 | Système de jugement (§1) : modèle d'options, juge, écran des règles, fiabilité | Lot 0 |
| 2 | Navigation contextuelle (§2) : sheet générique + extraction des tuiles | Lot 0 |
| 3 | Lecture plein écran (§3) + récitation overlay (§4) | Lot 2 (l'icône réglages du header utilise la sheet) |
| 4 | Page principale (§5) | Lot 0 |
| 5 | Suivre prière v2 (§6) | Mesure offline benchmark (hors app) |
| ∥ | Mindmap (§7) | Lot 0 seulement — parallélisable |

## 9. Questions OUVERTES à poser à l'utilisateur (ne pas trancher à sa place)

1. Les 6 couleurs de catégorie mindmap (palette manuscrite validée — la
   récupérer, ne pas inventer).
2. Le contenu pédagogique des 17 fiches de règles (§1.4) : rédigées par qui ?
   (générables à partir de sources de tafsir/tajwid du projet, mais la
   validation religieuse revient à l'utilisateur).
3. Mode enfant : quelles paires confusables tolérer par défaut ? (toutes les
   7 de la table, ou un sous-ensemble — décision pédagogique).
4. L'inventaire §4 des widgets à migrer en overlay : validation un par un
   avec l'utilisateur avant suppression/déplacement.
5. Faut-il un vrai "profil utilisateur" (adulte/enfant persistant, plusieurs
   utilisateurs sur le même téléphone ?) ou juste le preset courant ?

## 10. Décisions VERROUILLÉES (ne pas rouvrir sans l'utilisateur)

- Un seul modèle ; modes = couches de jugement post-décodage (§ principe).
- Squelette du mot toujours strict, même en mode enfant.
- Règles non fiables jamais activables (grisées), fiabilité versionnée avec
  le modèle.
- RNNT = localisation uniquement, jamais la vérification.
- Aucun widget empilé nouveau sur l'écran de récitation.
- Clés des règles = celles de `rules_map.json`, jamais renommées côté app.
