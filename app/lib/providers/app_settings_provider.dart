import 'dart:ui' show PlatformDispatcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/diagnostic_log.dart';

const _kPrefAutoCorrection = 'auto_correction_enabled';

/// Correction automatique en récitation continue (demande utilisateur
/// 2026-07-05) : dès qu'un mot passe au rouge, l'écoute se met en pause, le
/// réciteur prononce le verset, puis l'écoute reprend — sans aucun tap.
/// Réglable (settings) : à défaut, on revient au mode "normal" déjà en place
/// (jugement affiché, correction seulement au tap sur le mot).
final autoCorrectionEnabledProvider =
    StateNotifierProvider<AutoCorrectionSettingNotifier, bool>((ref) {
  return AutoCorrectionSettingNotifier();
});

class AutoCorrectionSettingNotifier extends StateNotifier<bool> {
  AutoCorrectionSettingNotifier() : super(true) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefAutoCorrection);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefAutoCorrection, value);
  }
}

const _kPrefTextScale = 'mushaf_text_scale';
const kTextScaleMin = 0.8;
const kTextScaleMax = 1.7;

/// Taille du texte du mushaf (demande utilisateur 2026-07-06 : "gérer le
/// zoom"). Facteur multiplicatif appliqué à la taille de police de base
/// (26px) du texte coranique — persisté, partagé entre les sessions.
final textScaleProvider =
    StateNotifierProvider<TextScaleNotifier, double>((ref) {
  return TextScaleNotifier();
});

class TextScaleNotifier extends StateNotifier<double> {
  TextScaleNotifier() : super(1.0) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kPrefTextScale);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(double value) async {
    state = value.clamp(kTextScaleMin, kTextScaleMax);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefTextScale, state);
  }
}

/// Vitesses prédéfinies du défilement automatique du mushaf (demande
/// utilisateur 2026-07-06 : "lire le Coran et ça scroll selon sa vitesse").
/// Valeurs en pixels/seconde — choix d'ergonomie (pas une règle religieuse à
/// vérifier), calibrées pour une lecture confortable à l'œil.
enum AutoScrollSpeed {
  off(0),
  slow(18),
  normal(32),
  fast(52);

  final double pixelsPerSecond;
  const AutoScrollSpeed(this.pixelsPerSecond);
}

// Volontairement NON persisté d'une session à l'autre : reprendre à
// défiler tout seul à l'ouverture de l'écran serait une mauvaise surprise.
// Activer le défilement auto reste un geste explicite à chaque session.
final autoScrollSpeedProvider =
    StateProvider<AutoScrollSpeed>((ref) => AutoScrollSpeed.off);

const _kPrefAdultChunkWordCount = 'adult_chunk_word_count';
const kAdultChunkWordCountMin = 1;
const kAdultChunkWordCountMax = 15;

/// Taille (en mots) d'une "unité" de répétition en mode Adulte/Tajwid/Custom
/// à l'étape "Répète" du Coach (demande utilisateur 2026-07-24) --
/// approxime une ligne du Mushaf imprimé (aucune vraie donnée de coupure de
/// ligne n'existe dans l'app). En mode Enfant l'unité est toujours 1 mot,
/// ce réglage ne s'y applique pas -- cf. IncrementalRepeatStep.
final adultChunkWordCountProvider =
    StateNotifierProvider<AdultChunkWordCountNotifier, int>((ref) {
  return AdultChunkWordCountNotifier();
});

class AdultChunkWordCountNotifier extends StateNotifier<int> {
  AdultChunkWordCountNotifier() : super(6) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kPrefAdultChunkWordCount);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(int value) async {
    state = value.clamp(kAdultChunkWordCountMin, kAdultChunkWordCountMax);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefAdultChunkWordCount, state);
  }
}

const _kPrefRepeatWindowSize = 'repeat_window_size';
const kRepeatWindowSizeMin = 1;
const kRepeatWindowSizeMax = 6;

/// Taille FIXE (le "curseur") de la fenêtre d'unités qu'il faut réciter
/// ensemble pour valider un palier à l'étape "Répète" du Coach (demande
/// utilisateur 2026-07-24, précisée explicitement : "le curseur ça doit
/// être fixe, pas palier croissant" -- la fenêtre GLISSE au fil des unités
/// introduites, sa TAILLE ne change pas). Ex. curseur=2 : on récite les
/// unités {1,2} pour valider l'introduction de l'unité 2, puis {2,3} pour
/// celle de l'unité 3, etc.
final repeatWindowSizeProvider =
    StateNotifierProvider<RepeatWindowSizeNotifier, int>((ref) {
  return RepeatWindowSizeNotifier();
});

class RepeatWindowSizeNotifier extends StateNotifier<int> {
  RepeatWindowSizeNotifier() : super(2) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kPrefRepeatWindowSize);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(int value) async {
    state = value.clamp(kRepeatWindowSizeMin, kRepeatWindowSizeMax);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefRepeatWindowSize, state);
  }
}

const _kPrefExplanationLanguage = 'explanation_language';

/// Langue de réponse pour les explications mot/verset (Coach IA, cascade
/// offline `QuranSciencesService` -- demande utilisateur 2026-07-12,
/// WORD_AYAH_EXPLANATION_PLAN.md section 1). 'ar'/'fr'/'en' -- 'fr' par
/// défaut (langue dominante de l'interface). Persisté entre les sessions.
final explanationLanguageProvider =
    StateNotifierProvider<ExplanationLanguageNotifier, String>((ref) {
  return ExplanationLanguageNotifier();
});

class ExplanationLanguageNotifier extends StateNotifier<String> {
  ExplanationLanguageNotifier() : super('fr') {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefExplanationLanguage);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefExplanationLanguage, value);
  }
}

/// Sensibilité du jugement GOP (vert/orange/rouge), réglable EN DIRECT
/// pendant la récitation (demande utilisateur 2026-07-12 : "je veux que ça
/// soit dynamique surtout pour celui qui récite... la possibilité de
/// modifier la sensibilité"). 0.0 = très tolérant (bande verte large), 1.0 =
/// très strict (bande verte étroite) ; 0.5 = valeurs calibrées par défaut
/// (cf. `_kGopCorrectDefault`/`_kGopUnclearDefault` dans
/// recitation_provider.dart -- le mapping exact 0-1 -> seuils GOP y reste
/// encapsulé, ce provider ne fait que porter le curseur utilisateur).
///
/// PAS persisté entre sessions (précisé par l'utilisateur : "récitation
/// indépendante avec valeur par défaut que on peut modifier avec le curseur
/// durant la récitation") -- chaque NOUVELLE récitation repart de 0.5
/// (bandes vert/orange/rouge inchangées), et KaraokeRecitationScreen la
/// remet explicitement à 0.5 au démarrage de chaque session (cf. _toggle) :
/// un ajustement fait pendant une récitation ne doit pas se répercuter
/// silencieusement sur la suivante.
final correctionSensitivityProvider = StateProvider<double>((ref) => 0.5);

/// Sensibilité de jugement pour l'écran "Suivre une prière" -- demande
/// utilisateur 2026-07-19 : "je veux que le paramètre de la sensibilité soit
/// sur la même page indépendamment de la sensibilité dans la récitation, ils
/// peuvent avoir deux niveaux différents". Volontairement un provider séparé
/// de [correctionSensitivityProvider] (pas partagé) : ajuster l'un ne doit
/// jamais changer l'autre, les deux contextes (pratique karaoké vs suivi
/// d'un imam en conditions réelles) n'appellent pas la même tolérance.
final prayerSensitivityProvider = StateProvider<double>((ref) => 0.5);

/// Souffleur automatique sur hésitation longue, spécifique à l'écran
/// "Suivre une prière" (demande utilisateur 2026-07-19, "puis celui du
/// souffleur" -- même page que la sensibilité ci-dessus). ACTIVÉ par défaut :
/// c'est la seule aide offerte dans ce mode (jamais de blocage/correction
/// forcée, cf. RecitationNotifier._confidentMode).
final prayerSouffleurEnabledProvider = StateProvider<bool>((ref) => true);

const _kPrefStrictCorrection = 'strict_correction_enabled';

/// Rigueur de la correction automatique (demande utilisateur 2026-07-06) :
/// STRICT (par défaut) — rouge ET orange déclenchent la correction (un mot
/// juste mais mal articulé doit aussi être repris). TOLÉRANT — seul le rouge
/// (mot faux) déclenche la correction ; l'orange (imprécis mais reconnu) est
/// accepté sans interruption.
final strictCorrectionProvider =
    StateNotifierProvider<StrictCorrectionSettingNotifier, bool>((ref) {
  return StrictCorrectionSettingNotifier();
});

class StrictCorrectionSettingNotifier extends StateNotifier<bool> {
  StrictCorrectionSettingNotifier() : super(true) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefStrictCorrection);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefStrictCorrection, value);
  }
}

const _kPrefFollowWithoutBlocking = 'follow_without_blocking_enabled';

/// "Suit sans bloquer" (demande utilisateur 2026-07-16 soir) : ACTIVÉ (par
/// défaut) -- sur un mot en échec, l'audio de correction ne se rejoue QU'UNE
/// FOIS ; si wordFailed refire sur ce même mot juste après, on ne rebloque
/// plus (pas de nouveau recul d'ancre) -- le réciteur peut avancer sur la
/// suite, le modèle suit sans forcer. DÉSACTIVÉ -- comportement d'origine :
/// chaque échec rejoue l'audio et recule l'ancre, le réciteur DOIT reprendre
/// exactement le mot avant de pouvoir avancer. Cf. cas réel : boucle de 4+
/// minutes sur "لَيَصْرِمُنَّهَا" sans jamais aboutir alors que le réciteur était
/// confiant d'avoir bien récité.
final followWithoutBlockingProvider =
    StateNotifierProvider<FollowWithoutBlockingSettingNotifier, bool>((ref) {
  return FollowWithoutBlockingSettingNotifier();
});

class FollowWithoutBlockingSettingNotifier extends StateNotifier<bool> {
  FollowWithoutBlockingSettingNotifier() : super(true) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefFollowWithoutBlocking);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefFollowWithoutBlocking, value);
  }
}

// Ancien toggle "réciteur confiant" (demande utilisateur 2026-07-18) --
// RETIRÉ (2026-07-18, même jour) : cette logique vit désormais entièrement
// dans l'écran dédié "Suivre une prière" (prayer_follow_screen.dart,
// RecitationNotifier.startPrayerFollow), plus adéquat pour l'usage réel
// (imam qui ne pré-sélectionne pas de sourate) que ce toggle sur le karaoké
// classique. Voir historique git pour l'implémentation précédente si besoin.

const _kPrefAppLocale = 'app.locale';
const kSupportedAppLocales = ['ar', 'fr', 'en'];

/// Langue principale de l'application (REFONTE_IHM.md §7bis) : pilote les
/// menus/UI ET le RTL. Distincte de [explanationLanguageProvider] (qui ne
/// contrôle que la langue des explications/cascade, réglage plus ancien et
/// plus étroit, 2026-07-12) -- les deux coexistent pour l'instant ; la
/// réconciliation (faire suivre explanationLanguageProvider sur celui-ci par
/// défaut, cf. §7bis point 6) reste à faire lors de l'extraction ARB
/// écran par écran.
/// Règle verrouillée : en arabe, tout l'écran est en arabe (aucune
/// traduction affichée) ; en fr/en, le texte coranique reste TOUJOURS en
/// arabe, seuls les menus/traductions/explications suivent la langue.
/// Défaut : langue système si dans {ar, fr, en}, sinon 'fr'.
final appLocaleProvider =
    StateNotifierProvider<AppLocaleNotifier, String>((ref) {
  return AppLocaleNotifier();
});

class AppLocaleNotifier extends StateNotifier<String> {
  AppLocaleNotifier() : super(_systemDefault()) {
    _restore();
  }

  static String _systemDefault() {
    final systemLang = PlatformDispatcher.instance.locale.languageCode;
    return kSupportedAppLocales.contains(systemLang) ? systemLang : 'fr';
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefAppLocale);
    if (saved != null && mounted && kSupportedAppLocales.contains(saved)) {
      state = saved;
    }
  }

  Future<void> set(String value) async {
    if (!kSupportedAppLocales.contains(value)) return;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefAppLocale, value);
  }
}

const _kPrefDiagnosticEnabled = 'diagnostic_enabled';

/// Interrupteur global du DIAGNOSTIC : journal fichier (Dart + natif) et
/// capture des WAV de chaque segment figé.
///
/// Demande utilisateur 2026-07-25, formulée exactement comme il faut : « je
/// veux m'assurer que ces retards ne sont pas dus à la création des logs ».
/// Mesuré ce jour-là sur une session réelle : 22 à 32 écritures fichier
/// synchrones par seconde côté Dart (`writeAsStringSync(flush: true)`, donc un
/// appel système bloquant par ligne), plus les lignes natives émises depuis le
/// thread d'inférence. Un instrument qui perturbe la grandeur qu'il mesure ne
/// permet aucune conclusion — il faut pouvoir l'éteindre et refaire la mesure.
///
/// Défaut `true` : le diagnostic est l'outil de travail principal de cette
/// phase du projet, on ne veut pas le perdre par oubli. Les WAV sont liés au
/// MÊME interrupteur volontairement : quand on analyse un log, on a besoin de
/// l'audio correspondant pour vérifier ce que le modèle a réellement entendu ;
/// et quand on mesure la performance sans instrumentation, l'écriture des WAV
/// ne doit pas rester allumée en douce.
final diagnosticEnabledProvider =
    StateNotifierProvider<DiagnosticEnabledNotifier, bool>((ref) {
  return DiagnosticEnabledNotifier();
});

/// Suppression de bruit du micro (Android `NoiseSuppressor`, via le package
/// `record`). **Désactivée par défaut, et c'est délibéré.**
///
/// POURQUOI PAS PAR DÉFAUT (analyse 2026-07-27) :
///  1. Décalage entraînement/inférence : le modèle a été affiné sur un corpus
///     de récitations NON traité par ce filtre. Les artefacts d'une suppression
///     de bruit (bruit musical de soustraction spectrale, attaques de consonnes
///     atténuées) sont un signal qu'il n'a jamais vu. Ces traitements sont
///     conçus pour l'oreille humaine, pas pour la reconnaissance.
///  2. Effet de bord direct : la doc du package prévient que le volume d'entrée
///     baisse. Or le portier de segmentation est un seuil ABSOLU (0,02) --
///     mesuré sur une session réelle, il écartait déjà 96 s d'audio sur 253.
///     Baisser le niveau aggrave mécaniquement ce chiffre.
///  3. Le bruit n'est pas le défaut mesuré : sur les erreurs relevées, le
///     modèle affiche `gop=0,00` et `free≈0` -- il est CERTAIN de ce qu'il
///     entend, il n'a reçu qu'un fragment de mot. Un modèle gêné par le bruit
///     montrerait des `free` bas partout.
///
/// Le réglage existe donc pour TRANCHER PAR LA MESURE (demande utilisateur
/// 2026-07-27) : réciter deux fois le même passage, avec et sans, et comparer
/// hors ligne. Son état est journalisé au démarrage de chaque session, sans
/// quoi une comparaison de logs serait ininterprétable.
final noiseSuppressProvider =
    StateNotifierProvider<NoiseSuppressNotifier, bool>((ref) {
  return NoiseSuppressNotifier();
});

const _kPrefNoiseSuppress = 'noise_suppress_enabled';

class NoiseSuppressNotifier extends StateNotifier<bool> {
  NoiseSuppressNotifier() : super(false) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefNoiseSuppress);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefNoiseSuppress, value);
  }
}

class DiagnosticEnabledNotifier extends StateNotifier<bool> {
  DiagnosticEnabledNotifier() : super(true) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefDiagnosticEnabled);
    if (saved != null && mounted) {
      state = saved;
      DiagnosticLog.enabled = saved;
    }
  }

  Future<void> set(bool value) async {
    state = value;
    // Appliqué immédiatement côté Dart ; le côté natif est poussé par
    // l'écran de réglage (qui a accès au vérificateur) -- cf.
    // settings_screen.dart.
    DiagnosticLog.enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefDiagnosticEnabled, value);
  }
}
