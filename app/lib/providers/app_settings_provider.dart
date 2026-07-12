import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

const _kPrefRepeatDrillCount = 'repeat_drill_count';
const kRepeatDrillCountMin = 1;
const kRepeatDrillCountMax = 50;

/// Nombre de répétitions du verset visées à l'étape "Répète" du mode
/// Apprentissage (demande utilisateur 2026-07-06 : technique de mémorisation
/// classique — répéter le même verset N fois de suite). Réglable de 1 à 50,
/// persisté entre les sessions.
final repeatDrillCountProvider =
    StateNotifierProvider<RepeatDrillCountNotifier, int>((ref) {
  return RepeatDrillCountNotifier();
});

class RepeatDrillCountNotifier extends StateNotifier<int> {
  RepeatDrillCountNotifier() : super(5) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kPrefRepeatDrillCount);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(int value) async {
    state = value.clamp(kRepeatDrillCountMin, kRepeatDrillCountMax);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefRepeatDrillCount, state);
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
