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

## 11. Refonte du volet COACH — la mémorisation rassemblée (2026-07-20)

**Demande utilisateur (verbatim)** : « tout ce qui est en lien avec la
mémorisation il faut le mettre dans coach ; donc le micro de récitation
mémorisation doit être déplacé dans coach ; et pareil tu revois le volet
coach pour inclure cette partie de mémorisation ayah par ayah et la
récitation globale avec tous les paramètres — **il ne faut pas faire juste
une copie-coller**, refonte IHM coach. Il y aura également l'accès à la
carte mentale **que je veux que tu enlèves de la première page**. Il y aura
le volet des erreurs que tu dois penser et organiser **par sourate**,
peut-être tu fais le lien avec carte mentale ; et surtout **tous les
paramètres de récitation globale doivent être accessibles** pour
modification. »

### 11.1 État des lieux réel (mesuré, pas supposé)

| Élément | Fichier | Situation actuelle |
|---|---|---|
| Onglet « Coach » | `coach_ai_screen.dart` (174 l.) | **N'est qu'un journal d'erreurs à plat** (liste `_AyahErrorTile` triée par nombre d'erreurs, toutes sourates mélangées) |
| Vrai coach mémorisation | `coach_screen.dart` (1863 l.) | 3 étapes Lecture→Apprentissage→Contrôle, micro, verset flouté, score. **Atteignable UNIQUEMENT depuis la lecture** (`mushaf_screen.dart:558`) |
| Micro récitation globale | `karaoke_recitation_screen.dart` (1857 l.) | Lancé depuis le bouton micro jaune de la lecture (`mushaf_screen.dart:578`) |
| Carte mentale | `mind_map_screen.dart` | Deux entrées : en-tête lecture (`mushaf_screen.dart:417`) **et page principale** (`surah_list_screen.dart:239`) |
| Journal d'erreurs (données) | `recitation_error_log_service.dart` | sqlite. `errorCountsByAyah()` → liste plate `{surah, ayah, count}` ; `errorsForAyah()` → entrées détaillées (`wordIndex`, `expectedWord`) ; **aucun agrégat par sourate** |
| `memorization_screen.dart` (421 l.) | — | **Orphelin** : plus référencé nulle part (vérifié par grep). À traiter en §11.6 |

**Conséquence** : la mémorisation est aujourd'hui éclatée (coach réel dans la
lecture, onglet Coach = simple journal), exactement ce que la demande veut
corriger.

### 11.2 Cible : l'onglet Coach devient un vrai hub, en 4 zones

Écran `CoachHubScreen` (remplace `CoachAiScreen` dans l'onglet), défilable,
4 zones dans cet ordre (ordre = priorité d'usage réel, pas esthétique) :

**Zone A — Reprendre** (en tête, seulement si une session existe)
Carte « Reprendre la mémorisation » : dernière sourate/verset travaillé,
progression. Un tap relance `CoachScreen` exactement où on s'était arrêté.
Rationale : c'est l'action n°1 d'un utilisateur qui mémorise au quotidien ;
elle ne doit jamais demander de re-naviguer.

**Zone B — Mémoriser (ayah par ayah)**
Sélection sourate → plage de versets → lance `CoachScreen(verses:[...])`
(les 3 étapes existantes, **réutilisées telles quelles**, pas réécrites).
C'est ici que vit désormais le micro de mémorisation.

**Zone C — Réciter (récitation globale)**
Lance `KaraokeRecitationScreen`. **C'est ici que le micro de récitation
globale déménage** (retiré de la barre du bas de la lecture).
Accompagné de **tous les paramètres de récitation, modifiables sur place**
(exigence explicite) — cf. §11.4.

**Zone D — Mes erreurs, par sourate**
Le volet erreurs repensé — cf. §11.3.

### 11.3 Volet erreurs : organisation par sourate (conception demandée)

**Problème du volet actuel** : liste plate toutes sourates confondues, triée
par nombre d'erreurs. On voit « An-Nisa v1 : 9 » à côté de « Al-Qalam v20 :
6 » sans aucune vue d'ensemble : impossible de savoir *quelle sourate* est
fragile, ni de travailler par bloc cohérent.

**Cible — deux niveaux, repliables :**

1. **Niveau sourate** (agrégat) : `nom de sourate — N erreurs sur M versets`.
   Tri par nombre d'erreurs décroissant (= le plus actionnable en premier :
   « où dois-je travailler ? »). Barre de progression fine indiquant la part
   de versets touchés dans la sourate (contexte : 5 versets fragiles sur 7
   n'a pas le même sens que 5 sur 286).
2. **Niveau verset** (au dépliage) : les versets fautifs de CETTE sourate,
   avec leur compte. Trois actions par verset :
   - **Revoir** → `CoachScreen(verse)` : attaque la mémorisation exactement
     sur le verset faible (boucle de correction fermée) ;
   - **Explication** → `coach_explanation_sheet` existant (Gemma on-device) ;
   - **Carte mentale** → `MindMapScreen(surah)` (cf. lien ci-dessous).

**Le lien erreurs ↔ carte mentale (idée utilisateur, retenue et motivée)** :
la carte mentale donne la structure thématique de la sourate et sait déjà
« Aller au verset ». Depuis une erreur sur le verset N, ouvrir la carte
mentale situe ce verset **dans le sens du passage** — on ne répète plus un
verset isolé hors contexte, on voit à quel thème il appartient et ce qui
l'entoure. C'est une aide de mémorisation par le sens, pas une décoration.
Lien dans les deux sens : erreur → carte (situer), carte → verset (réviser,
déjà en place).
*Réserve honnête* : le contenu de carte mentale n'existe que pour 12 sourates
courtes aujourd'hui. Le bouton ne doit donc apparaître que si le JSON existe
pour cette sourate (`mindMapProvider` renvoie non-null), sinon il est masqué
— jamais un bouton mort.

**Données** : agrégat par sourate calculé **côté client** en regroupant
`errorCountsByAyah()` (déjà existant) plutôt qu'en ajoutant une requête SQL.
Volumes réels de l'ordre de quelques centaines de lignes → coût négligeable,
et zéro risque de régression sur le schéma sqlite. À réévaluer seulement si
le journal grossit beaucoup.

### 11.4bis CORRECTION UTILISATEUR (2026-07-20, après première livraison)

La §11.4 ci-dessous plaçait TOUS les réglages dans le hub Coach. L'utilisateur
a corrigé sur trois points ; le critère de rangement devient **« à quoi sert ce
réglage ? »** et non « dans quel écran suis-je ? » :

1. **Récitateur → Réglages généraux** (« le récitateur c'est dans réglages
   générale »). C'est un choix **transverse** : il sert à l'écoute d'une
   sourate, au souffleur, aux corrections audio — pas seulement à la
   récitation. Le mettre dans Coach le rendait introuvable pour ses autres
   usages.
2. **Paramètres de VÉRIFICATION → sur l'écran de récitation, derrière une
   icône** (« tous les paramètres de vérification seront sur la page de
   récitation moyennant une icône »). Concernés : mode de vérification
   (presets + 17 règles), sensibilité, rigueur, correction automatique,
   suivre sans bloquer. Raison : ils ne servent QUE là, et souvent **en cours**
   de récitation (« je suis jugé trop sévèrement, je desserre tout de suite »).
   Les enfermer dans un écran distant obligerait à sortir de la session.
   Implémentation : `karaoke_recitation_screen.dart::_openVerificationSheet`,
   icône `tune_rounded` de la barre du haut — élargit la feuille « sensibilité »
   qui existait déjà là depuis le 2026-07-12 (même principe, portée étendue).
3. **« Réciter une sourate » = le MOTEUR de l'app, à mettre en valeur** (« ce
   n'est pas mis en valeur »). Il était une simple ligne de liste parmi les
   réglages. Devient une **grande carte d'action** (dégradé, bordure laiton,
   micro en pastille, ombre portée) : c'est la fonction centrale du produit,
   elle doit se voir et s'atteindre en un geste.

**Ce que le hub Coach garde donc** : Reprendre, Mémoriser, la grande carte
Réciter, et Mes erreurs par sourate. Plus aucun réglage de vérification.

### 11.4 « Tous les paramètres de récitation accessibles » (exigence explicite)
### — table d'origine, corrigée par §11.4bis ci-dessus

Regroupés dans la zone C, modifiables sans quitter Coach :

| Paramètre | Provider / écran existant |
|---|---|
| Mode de vérification (presets tajwid/adulte/enfant + 17 règles) | `TajwidRulesScreen` / `judgementOptionsProvider` |
| Sensibilité du jugement | `correctionSensitivityProvider` |
| Rigueur de la correction | `strictCorrectionProvider` |
| Correction automatique | `autoCorrectionEnabledProvider` |
| Suivre sans bloquer | `followWithoutBlockingProvider` |
| Répétitions de mémorisation | `repeatDrillCountProvider` |
| Récitateur | `reciter_select_screen` |

**Cohérence avec la règle « pas de redondance » (§2)** : ces réglages
**quittent** l'écran Réglages global (ils y sont aujourd'hui) pour vivre ici,
au contact de leur usage. Le Réglages global ne garde que ce qui est
transverse (langue, Qibla, à-propos). Même mouvement que celui déjà fait pour
vitesse/répétition → tiroir de lecture.

### 11.5 Retraits (conséquences directes de la demande)

- `surah_list_screen.dart` : **retirer l'icône carte mentale par sourate**
  (demande explicite « enlève de la première page »). La page principale
  redevient une simple liste de sourates + les 2 icônes d'app bar
  (Suivre prière, Identifier).
- `mushaf_screen.dart` : **retirer le bouton micro** de la barre du bas
  (la récitation se lance depuis Coach).
- L'en-tête de lecture **garde** son icône carte mentale (la demande ne visait
  que la première page).

### 11.6 Points tranchés par l'utilisateur (2026-07-20) — VERROUILLÉS

1. **Raccourci « travailler ce verset » depuis la lecture**
   (`mushaf_screen.dart:558`, bouton Coach IA) : **GARDÉ**. L'écran de
   mémorisation reste unique et vit dans Coach ; la lecture ne fait qu'y
   renvoyer (ce n'est pas une duplication de code). Pratique quand on bute
   sur un verset en lisant.
2. **`memorization_screen.dart` (421 l., orphelin)** : **SUPPRIMÉ**. Examiné
   avant de trancher — c'est une **maquette morte** (`// Demo feedback
   state`, `_WordResult` factices, aucun ASR réel, un seul verset, aucune
   sélection de plage à réutiliser), supplantée par `coach_screen.dart`
   (3 étapes, vrai micro). Rien à en récupérer ; l'historique git la
   conserve si besoin.
3. **Réglages de récitation : DÉPLACÉS** (pas dupliqués). Ils quittent
   l'écran Réglages global pour vivre dans Coach. Réglages global ne garde
   que le transverse (langue, Qibla, à-propos). Conforme à la règle
   verrouillée « pas de redondance, chaque module a ses propres
   paramètres ».

### 11.7 Ordre d'exécution — ÉTAT RÉEL

0. ✅ Commit de l'état courant — point de reprise `59dbae9`.
1. ✅ `providers/error_review_provider.dart` : `SurahErrorSummary` +
   `surahErrorSummariesProvider` (regroupement client-side, tri par erreurs
   décroissantes, ratio de versets touchés).
2. ✅ `screens/coach_hub_screen.dart` (zones A–D) branché dans l'onglet Coach
   (`main.dart`). Briques annexes créées :
   - `screens/surah_picker_screen.dart` : sélecteur de sourate RÉUTILISÉ par
     les zones B et C (évite la duplication de liste que la demande interdit) ;
   - `providers/last_coach_verse_provider.dart` : mémoire du dernier verset
     travaillé (zone A « Reprendre »), écrite par `CoachScreen.initState`.
3. ✅ Déplacements :
   - gros micro retiré de la barre du bas de la lecture, remplacé par un
     bouton discret « Mémoriser » (raccourci verset conservé, §11.6.1) ;
   - icône carte mentale retirée de la page principale.
4. ✅ Section « Récitation » entièrement retirée de Réglages global
   (Réciteur, Correction auto, Rigueur, Suivre sans bloquer, Répétitions)
   → vit dans le hub Coach zone C, + Mode de vérification, Récitateur et
   Sensibilité du jugement.
5. ✅ Fichiers morts supprimés : `memorization_screen.dart` (maquette à
   feedback factice, §11.6.2) et `coach_ai_screen.dart` (remplacé par le hub).
6. Build + install + captures de vérification.
7. Commit par périmètre.

**Reste à faire (non couvert par cette passe)** : sélection d'une PLAGE de
versets (aujourd'hui la zone B lance la sourate entière) ; ancrage de la carte
mentale sur le verset précis d'une erreur (aujourd'hui elle ouvre la sourate).

---

## 12. Fiabilité des règles : d'un blocage à un plafond (2026-07-20)

**REVIREMENT d'une décision antérieure.** La §1 verrouillait : « règles non
fiables jamais activables (grisées) ». L'utilisateur a contesté : « pourquoi
il y a des toggles désactivés, exemple madd 6 et autres, même pour enfants ? ».
Il a raison, et la vérification des chiffres le confirme.

### Pourquoi le blocage était mal fondé (3 raisons mesurées)

1. **La mesure évalue la mauvaise chose.** Protocole utilisé : *quand le
   récitateur applique la règle CORRECTEMENT, le modèle émet-il le symbole ?*
   C'est de la détection de règle **bien réalisée**. Or ce qui compte pour
   enseigner est l'inverse : *quand l'utilisateur RATE la règle, le modèle le
   voit-il ?* — jamais mesuré (cf. `PLAN_ENTRAINEMENT_HYBRIDE.md` : « le set
   humain reste le juge de paix », toujours pas fait). Une règle a donc été
   grisée sur la foi d'un proxy.

2. **Échantillons minuscules, verdicts fragiles** (IC95% Wilson) :

   | Règle | n | recall | IC 95% |
   |---|---|---|---|
   | `madda_necessary` (madd 6) | 32 | 72% | **[55% – 84%]** |
   | `idgham_mutajanisayn` | 13 | 85% | [58% – 96%] |
   | `idgham_mutaqaribayn` | **3** | «100%» | **[44% – 100%]** — aucune information |
   | `qalaqah` (référence) | 50 | 96% | [87% – 99%] |

3. **La cause probable est la rareté, pas la difficulté.** `madda_necessary`
   n'a que **143 occurrences dans tout le Coran** : le modèle l'a très peu vue.
   Et un madd est une **durée** — probablement ce qu'un système mesure le plus
   facilement, pas l'inverse.

**Coût pédagogique du blocage** : le madd 6 est une des règles les plus
fondamentales et les plus audibles. La bloquer, même en mode enfant, privait
l'app de ce qu'elle devrait enseigner en premier.

### Ce qui remplace le blocage

Le garde-fou ne disparaît pas, il **change de nature** : au lieu d'interdire,
il **refuse de certifier**.

- **Toutes les règles sont activables** (`RuleReliability.selectable == true`).
- Chaque règle porte un **badge de fiabilité** dans l'écran des règles
  (« fiable · 96% », « peu fiable · 72% », « non mesurée »).
- Une règle active dont la fiabilité est insuffisante (`capsToUnclear` :
  statut ≠ ready, ou recall < 0,90) **plafonne le verdict du mot à « incertain »
  (orange)** au lieu de le laisser passer au vert
  (`RecitationNotifier._capByRuleReliability`).

**Le principe conservé** : afficher un **vert franc sur une faute réelle** est
le pire comportement possible — c'est le biais canonique combattu depuis le
début du projet (l'utilisateur croit avoir juste). L'orange dit honnêtement
« il se passe quelque chose ici, je ne peux pas trancher », ce qui est
strictement mieux que l'absence de retour ET que la fausse validation.

### Reste ouvert

- **La vraie mesure** (détection de fautes délibérées sur un set humain) n'est
  toujours pas faite. Les seuils de `rule_reliability.json` restent donc des
  proxys — à remplacer dès que ce set existera.
- **Le madd est structurellement mal servi par le symbole ASR** : le alif
  suscrit (ٰ) est remplacé par un alif normal dans les labels d'entraînement
  ET dans la normalisation de l'app — la durée n'existe nulle part dans le
  texte comparé (cf. `FONCTIONNALITES_FUTURES.md` §1, documenté depuis le
  2026-07-06). La seule voie qui rend le madd vraiment vérifiable est une
  **mesure de durée** (option A du §1 : exploiter les timings déjà produits
  par le CTC, sans ré-entraînement). **Reporté** (décision utilisateur
  2026-07-20 : « plus tard, on note et on avance »).

---

## 13. Erreurs catégorisées par type (2026-07-20)

**Demande** : « pour les erreurs de récitation, les catégoriser par type :
tajwid ou prononciation ».

### Ce qui manquait

Le journal (`recitation_errors`) ne stockait que *où* : sourate, verset, index
du mot, mot attendu. Jamais *pourquoi*. Et l'information nécessaire — **ce qui
a été réellement entendu** — n'était conservée nulle part : elle existait le
temps du jugement puis disparaissait. Impossible donc de reclasser après coup.

### Méthode : comparer, pas étiqueter

`RecitedWord.heard` (nouveau) retient le squelette entendu au moment du
jugement (point de passage unique : `_judge`). La classification
(`RecitationNotifier.classifyError`) va du plus concret au plus déductif :

| Constat | Type | Famille |
|---|---|---|
| rien entendu | `saute` | Mot sauté |
| squelette différent | `lettre` (ص/س, ط/ت…) | **Prononciation** |
| squelette égal, harakat différentes | `harakat` (رَبِّ vs رَبُّ) | **Prononciation** |
| lettres ET harakat justes, mais le mot porte une règle | `tajwid` | **Tajwid** |
| sinon | `inconnu` | — |

### ⚠️ Limite assumée, affichée à l'utilisateur

`tajwid` est une **déduction par élimination**, pas une détection directe de la
règle ratée : l'écart peut venir d'autre chose (durée, liaison) sans qu'on
sache le distinguer aujourd'hui. Tant que la mesure « détection de fautes
délibérées » n'existe pas (§12), cette catégorie se lit **« écart non expliqué
par les lettres ni les harakat, sur un mot porteur d'une règle »**.
C'est écrit **dans l'UI** sous la barre de répartition — pas seulement dans le
code : l'utilisateur doit pouvoir juger de la confiance à accorder au chiffre.

### Persistance

Base v1 → **v2**, migration **non destructive** (`ALTER TABLE ADD COLUMN kind`).
Les erreurs déjà journalisées sont conservées et ressortent en « indéterminé »
— on ne peut pas reconstruire après coup ce qui avait été entendu, et les
compter comme du tajwid serait une invention. Le journal est l'historique réel
de l'utilisateur : jamais de `DROP`/recréation.

### Affichage

Barre empilée + légende chiffrée en tête du volet erreurs du hub Coach, AVANT
la liste par sourate : les deux répondent à des questions différentes —
« sur quoi je bute ? » (type) puis « où travailler ? » (sourate).

---

## 10. Décisions VERROUILLÉES (ne pas rouvrir sans l'utilisateur)

- Un seul modèle ; modes = couches de jugement post-décodage (§ principe).
- Squelette du mot toujours strict, même en mode enfant.
- Règles non fiables jamais activables (grisées), fiabilité versionnée avec
  le modèle.
- RNNT = localisation uniquement, jamais la vérification.
- Aucun widget empilé nouveau sur l'écran de récitation.
- Clés des règles = celles de `rules_map.json`, jamais renommées côté app.

---

## 12. Un seul écran, trois pilotes (décision utilisateur 2026-08-05)

Dicté par l'utilisateur, transcrit ici pour qu'aucun agent n'ait à le
re-deviner. La page du Mushaf devient **le seul lieu** ; ce qui change n'est
pas l'écran, c'est **qui le pilote**.

| pilote | déclencheur | ce qui commande l'affichage |
|---|---|---|
| **Lecture** (défaut) | ouvrir une sourate | le lecteur, par le doigt |
| **Récitation** | choisir « récitation » sur la sourate | l'ASR : le texte est masqué, il ne se révèle qu'à mesure qu'il est validé |
| **Jeu** | choisir « jeu » | les paliers de mémorisation, par 20 versets ou jusqu'à la fin de la sourate si elle est plus courte |

L'écran karaoké séparé disparaît. Le curseur de lecture est le point de départ :
lancer la récitation la fait commencer **là où on en est**, pas au verset 1.

### 12.1 La cadence de page s'APPREND, elle ne se règle plus

> « il y a un temps, je ne veux même pas qu'on affiche ce temps-là »

Le curseur « secondes par page » posait une question sans réponse possible :
personne ne sait dire en secondes à quelle vitesse il lit, et cela change avec
le passage, la fatigue et le jour.

Le geste qui porte l'information existe déjà :

- tourner la page **à la main avant l'échéance** = « trop lent » → on retient
  le temps réellement écoulé ;
- **revenir en arrière** = « trop rapide » → la page a tourné avant la fin de
  la lecture ; on rallonge, sans savoir de combien (on ne mesure pas ce qui
  n'a pas eu lieu).

Trois garde-fous, tous demandés explicitement :

1. **départ au maximum** — mieux vaut une page qui tarde qu'une page qui
   s'échappe ; le premier geste corrigera ;
2. **plancher** — `kKindlePageSecondsMin`, pour qu'aucune suite de gestes ne
   rende la lecture impossible ;
3. **rejet des valeurs illogiques** — sous la seconde, ce n'est pas une cadence
   de lecture mais un double-tap ; l'observation est ignorée, pas moyennée.

L'estimation bouge d'une fraction à chaque observation (inertie 0,35) : un
geste isolé ne peut pas emballer l'écran, et la convergence tient en quelques
pages. Implémenté : `KindlePageSecondsNotifier.apprendre`,
`MushafScreen._tapManuel`.

⚠️ Ne pas réintroduire le curseur « pour laisser le choix » sans supprimer
l'apprentissage : deux sources écrivant la même valeur se contrediraient en
silence — l'utilisateur règlerait 12 s et verrait le nombre bouger tout seul.

### 12.2 La récitation de référence quitte l'interface, pas le projet

Question de l'utilisateur : « est-ce que c'est vraiment maintenant d'utilité ».

Elle n'a jamais servi à comparer un audio à un autre. Elle sert à savoir **qui
a tort**. Le 2026-08-05, elle a tranché deux fois en une matinée : le violet
sur `حَوْلَهُۥ` et le rouge sur `أَبْصَـٰرَهُمْ` n'ont pu être qualifiés de faux
positifs *que* parce que l'audio venait d'un récitateur professionnel — donc
forcément juste. Avec la voix de l'utilisateur, les deux cas restaient
indécidables.

⇒ **Retirée de l'interface** (aucun usage pour le récitateur), **conservée dans
le banc** (`benchmark/recette_2tel.sh`). C'est un instrument de mesure, pas une
fonctionnalité.

### 12.3 Ce qui reste à arbitrer avant de coder le pilote « récitation »

Deux points ne sont pas décidés par ce qui précède :

- **le mot affiché alors qu'il n'est pas encore prononcé.** L'ancre avance
  avant le verdict — c'est structurel, pas un défaut d'affichage. Révéler « ce
  qui est validé » exige donc de choisir entre révéler à l'ANCRE (en avance,
  donc parfois à tort) ou au VERDICT (juste, mais en retard sur la voix).
- **qui gagne si le lecteur fait défiler à la main pendant que l'ancre suit.**


---

## 13. Abandon de l'écran vert — plan d'exécution (2026-08-05)

Décision utilisateur : « abandonne l'écran de récitation vert et bascule tout
sur l'écran principal ». Cette section est l'INVENTAIRE, pas une intention :
elle dit ce qui migre, ce qui meurt, et ce qui doit être décidé — pour que
l'exécution n'ait rien à redécouvrir.

### 13.1 Ce que l'écran vert porte réellement

2 915 lignes, 43 méthodes privées. Elles ne sont pas de même nature, et c'est
ce qui rend la migration faisable :

| nature | méthodes | destin |
|---|---|---|
| **Pilotage de la chaîne** | `_toggle`, `_togglePause`, `_startWithCountdown`, `_maybeExtendNextPage` | **migrent** — c'est le cœur |
| **Réaction aux verdicts** | `_onWordFailed`, `_promptCurrentWord`, `_maybePrefetchCorrectionAudio` | **migrent** |
| **Rendu du mot** | `_wordSpan` | **remplacé** par `VerseTile`/`TajweedText` (le Mushaf sait déjà dessiner) |
| **Feuilles annexes** | `_openWordHelp`, `_openVerificationSheet`, `_openMemorizationGame` | **migrent tels quels** |
| **Debug** | `_showFullTranscript` | **meurt** (cf. §13.4) |
| **Profil de pauses** | `_maybeSaveProfile` | **migre** |

Le Mushaf, lui, apporte ce que l'écran vert n'a jamais eu : défilement infini
entre sourates, mode Kindle, pagination, marque-page, appui long.

### 13.2 Le point dur : le rendu

L'écran vert construit **un bloc de texte plat** (`_buildChunk` → `text` +
`spans` + `wordKeys`) et dessine mot à mot avec `_wordSpan`. Le Mushaf dessine
**par verset**, via `VerseTile`.

⚠️ **C'est la seule vraie difficulté de la migration.** L'index de mot de
`RecitedWord` est GLOBAL sur le passage ; celui de `TajweedText` est LOCAL au
verset. Le pont existe déjà et il est testé : `_verseContaining(i)` et
`_localIndexInVerse(i)` (écran vert), plus `wordStart`/`wordEnd` de
`TajweedText` (écrits pour le mode Kindle, réutilisés pour la fusion des mots
en erreur le 2026-08-05).

⇒ Ne PAS réécrire un rendu plat dans le Mushaf. `VerseTile` reçoit un paramètre
de plus — l'état de jugement par mot — et `TajweedText` colore le fond selon
cet état, exactement comme `_wordSpan` le fait aujourd'hui.

### 13.3 Les trois pilotes (cf. §12), traduits en états

Un seul champ `_pilote` sur `MushafScreen` :

    lecture    (défaut)  le doigt commande, tout est visible
    recitation           l'ASR commande ; le texte non validé est MASQUÉ ;
                         le défilement suit le pointeur ; le toucher est ignoré
    jeu                  paliers de mémorisation

Décisions déjà prises, à ne pas re-arbitrer :

- **révélation au VERDICT**, jamais à l'ancre (l'ancre avance avant le verdict ;
  révéler à l'ancre montre des mots non prononcés — symptôme constaté) ;
- **la récitation pilote SEULE** le défilement : pas de tournage automatique en
  parallèle, le toucher n'a aucun effet. Cela supprime le besoin d'un arbitre
  entre deux sources concurrentes ;
- **départ au curseur** (`_activeVerse`), jamais au verset 1 ;
- le jeu : 20 versets, ou la sourate entière si elle est plus courte.

### 13.4 Ce qui meurt avec l'écran vert

- `RecitationScreen` (transcript brut, atteint par double-tap sur le micro) —
  écran de debug interne, sans usage pour le récitateur ;
- `_showFullTranscript` ;
- `KaraokeRecitationScreen` lui-même, une fois les migrations faites.

⚠️ **NE MEURENT PAS** : le journal de diagnostic (`DiagnosticLog`) et l'écran
de recette. Le premier est ce qui a permis de trouver tout ce qui a été trouvé
le 2026-08-05 ; le second est le seul chemin vers le mode RÉFÉRENCE, l'unique
instrument qui dise QUI a tort quand un mot est signalé.

### 13.5 Préalable non négociable

**Le banc doit redevenir déterministe avant d'exécuter cette section.**

Six passes du 2026-08-05, même audio rejoué, même binaire de chaîne — ancre
atteinte : **294, 208, 40, 294, 210, 70**. Un facteur sept sur elle-même.

Une migration de cette taille produira des régressions ; c'est normal. Ce qui
ne l'est pas, c'est de ne pas pouvoir les distinguer du bruit. Le mode
`WAV=<fichier>` existe déjà (même code, même cadence, entrée identique au bit
près, au lieu du chemin haut-parleur → micro) : c'est lui qu'il faut employer.

Sans ça, chaque étape de la migration se jugera sur un tirage au sort.

---

## 14. Cloisonnement complet contrôle / test — inventaire pour exécution future

Décision utilisateur (2026-08-05), après le cloisonnement du point d'entrée
Dart (`startControle`/`startTest`, cf. commit git du même jour) : « je veux
que tout le process soit dupliqué, aucune communication, tout soit étanche ».

Le point d'entrée seul ne suffit pas : le mécanisme d'ANCRE lui-même
(`Localisateur.kt`, celui du recul exclusif tenté ce jour) **ne connaît même
pas** la distinction contrôle/référence — code Kotlin partagé à 100 %, sans
paramètre pour la différencier. Une modification de l'ancre en mode référence
impacte donc aujourd'hui le mode normal, systématiquement.

**Ce chantier n'a PAS été exécuté** : à cette taille, le faire dans le temps
restant d'une session aurait été le risque de régression que l'utilisateur
demande justement d'éviter. Cette section est l'inventaire, prêt à exécuter
d'un trait dans une session dédiée avec le budget nécessaire.

### 14.1 Ce qui doit être dupliqué — le pipeline Kotlin (`recitation2/`)

3672 lignes, 8 fichiers, dépendances imbriquées (mesuré le 2026-08-05) :

| fichier | lignes | dépend de |
|---|---|---|
| `ChaineRecitation.kt` | 619 | Localisateur, AligneurForce, ConstructeurDeFenetres, Decideur, FrontAcoustique |
| `ConstructeurDeFenetres.kt` | 604 | — |
| `AligneurForce.kt` | 434 | — |
| `Decideur.kt` | 328 | — |
| `Localisateur.kt` | 295 | — (le mécanisme d'ancre lui-même) |
| `Calibrage.kt` | 296 | AligneurForce |
| `Decodage.kt` | 151 | — |
| `Tete3Traits.kt` | 273 | — |
| `RegistreDePreuves.kt` | 123 | — |
| `Tete3.kt` | 126 | — |
| `Orthographe.kt` | 108 | — |
| `FrontAcoustique.kt` | 102 | — |
| `ConfusionsRecitation.kt` | 94 | — |
| `FluxBrut.kt` | 66 | — |
| `Horloge.kt` | 53 | — |

`ChaineRecitation` est le point d'assemblage : dupliquer implique deux arbres
complets (`ChaineRecitationControle` + ses dépendances propres,
`ChaineRecitationTest` + les siennes), pas un fichier isolé.

### 14.2 Ce qui doit être dupliqué — côté Dart (`recitation_provider.dart`)

Déjà séparé (2026-08-05) : `startControle()` / `startTest()` — le point
d'entrée de session.

Reste PARTAGÉ, à dupliquer pour l'étanchéité complète :
- `_onAligned` (ligne ~3094) — traite les résultats de l'ancre v1 ;
- `_onV2` (ligne ~2945) — traite les statuts de la chaîne v2, donc de
  `Localisateur` ;
- `_judge` (ligne ~2391) — verrouille un verdict, commun aux deux modes ;
- `_onDecrochageV2` (ligne ~233) — traite un décrochage signalé par la v2.

### 14.3 Ce qui doit être dupliqué — le pont natif (`FastConformerCtcPlugin.kt`)

`alimenterV2()` instancie `ChaineRecitation` (deux sites d'appel identifiés,
cf. `v2Chaine`) : c'est ICI que le choix Controle/Test doit se faire, à partir
d'un mode transmis depuis Dart. Aujourd'hui **aucun flag de mode n'existe côté
Kotlin** — `v2Actif`/`v2Mots` sont posés sans distinction ; il faut l'ajouter
(nouveau paramètre sur `v2SetEnabled` ou nouvelle méthode `v2SetMode`).

### 14.4 Ce qui NE PEUT PAS être dupliqué, et pourquoi ce n'est pas un défaut

Le **modèle ONNX chargé en mémoire** (`FastConformerCtc`, l'inférence
elle-même) est un partage MATÉRIEL, pas logiciel : le dupliquer chargerait
deux fois le modèle en RAM sur le téléphone. Il reste commun aux deux modes,
et c'est sans conséquence pour l'étanchéité demandée — le modèle ne PREND
aucune décision de jugement, il ne fait que produire des logprobs ; c'est tout
ce qui vient APRÈS (Localisateur, AligneurForce, Decideur) qui doit être
étanche, et qui l'est dans ce plan.

### 14.5 Ordre d'exécution recommandé

1. Ajouter le flag de mode côté Kotlin (`FastConformerCtcPlugin.kt`) et le fil
   Dart -> MethodChannel qui le transmet (`startControle`/`startTest` le
   connaissent déjà, il manque le relais vers le natif).
2. Dupliquer `Localisateur.kt` en premier — c'est le fichier sans dépendance
   interne, le plus isolé, et celui où un correctif a déjà failli toucher les
   deux modes le jour même (recul exclusif).
3. Remonter vers `AligneurForce`, `ConstructeurDeFenetres`, `Decideur`,
   `FrontAcoustique` — chacun sans dépendance interne, duplicables
   indépendamment.
4. `ChaineRecitation` en dernier — l'assemblage, une fois que toutes ses
   dépendances existent en double.
5. Côté Dart : `_onAligned`, `_onV2`, `_judge`, `_onDecrochageV2`.
6. Recette à deux téléphones sur CHAQUE mode séparément, avant tout commit.

⚠️ Le banc de recette doit être rendu déterministe (§13.5, mode `WAV=<fichier>`)
AVANT d'entamer ce chantier : sans ça, aucune des deux copies ne pourra être
vérifiée contre l'autre de façon fiable.
