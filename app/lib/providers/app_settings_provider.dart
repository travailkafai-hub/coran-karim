import 'dart:ui' show PlatformDispatcher;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/objectif_coach.dart';
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

  /// ⚠️ COURSE CORRIGEE LE 2026-08-05 : le notifier demarre a `true` en dur,
  /// puis lit la valeur PERSISTEE en asynchrone. Ce provider n'etant cree
  /// qu'au PREMIER `ref.read`, et ce premier read etant justement celui de la
  /// premiere correction, celle-ci lisait le defaut `true` avant l'arrivee du
  /// `false` sauvegarde -- les suivantes lisaient la vraie valeur.
  ///
  /// SYMPTOME MESURE (log device, session 22:46) : reglage persiste a `false`,
  /// et pourtant
  ///     22:46:43  1re correction  -> wordFailed -> Correction-Audio  (passe)
  ///     22:46:50  2e decrochage   -> IGNORE : correction desactivee
  ///     22:47:09  3e decrochage   -> IGNORE : correction desactivee
  /// « toujours le deuxieme KO », systematique et non aleatoire -- c'est
  /// exactement la signature d'un defaut d'initialisation, pas d'un hasard.
  ///
  /// CORRECTIF : le provider est desormais cree DES L'OUVERTURE de l'ecran de
  /// recitation (cf. KaraokeRecitationScreen._initAsync), soit plusieurs
  /// secondes avant la premiere correction possible -- la lecture asynchrone a
  /// donc largement le temps d'aboutir. La course n'est plus atteignable en
  /// pratique, et le defaut reste documente ici pour qu'on ne la reintroduise
  /// pas en supprimant ce prechargement.
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

const _kPrefKindleMode = 'kindle_mode';

/// Mode Kindle (demande utilisateur 2026-08-01) : thème repos-yeux (anti
/// lumière bleue) + navigation par pages (tap sur les côtés / défilement
/// éclair) -- remplace l'ancien "défilement automatique" à 4 vitesses fixes
/// (off/slow/normal/fast), retiré du même coup (demande utilisateur : "plus
/// raison d'être" une fois le mode Kindle en place). Persisté comme un choix
/// de thème (contrairement à l'ancien défilement auto, se retrouver avec ce
/// thème actif à l'ouverture n'est pas une mauvaise surprise, c'est une
/// préférence de lecture comme la taille du texte).
/// Lecture sur FOND NOIR (demande utilisateur 2026-08-07). Independant du
/// mode Kindle : on peut vouloir le noir sans la pagination sepia, et
/// inversement. Persiste comme une preference de theme, au meme titre.
final modeSombreProvider =
    StateNotifierProvider<ModeSombreNotifier, bool>((ref) {
  return ModeSombreNotifier();
});

const _kPrefModeSombre = 'mushaf_mode_sombre';

class ModeSombreNotifier extends StateNotifier<bool> {
  ModeSombreNotifier() : super(false) {
    _restore();
  }
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefModeSombre);
    if (saved != null && mounted) state = saved;
  }
  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefModeSombre, value);
  }
}

final kindleModeProvider =
    StateNotifierProvider<KindleModeNotifier, bool>((ref) {
  return KindleModeNotifier();
});

class KindleModeNotifier extends StateNotifier<bool> {
  KindleModeNotifier() : super(false) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefKindleMode);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefKindleMode, value);
  }
}

const _kPrefKindlePageSeconds = 'kindle_page_seconds';
const kKindlePageSecondsMin = 4.0;
// Releve de 30 a 90 s (2026-08-07). Mesure : la cadence reelle de
// l'utilisateur est de 24 a 30 s par page, et une mesure de 30,3 s a ete
// ECRETEE a 30,0 en silence. Un plafond qui coupe la valeur observee n'est
// plus une securite, c'est une erreur -- il datait de l'epoque ou la cadence
// se reglait au curseur, et ou 30 s etait le maximum qu'on imaginait regler.
// Maintenant qu'elle se MESURE, la borne n'a plus qu'un role : ecarter une
// valeur absurde (page laissee ouverte une demi-heure).
const kKindlePageSecondsMax = 90.0;

/// Jauge de vitesse du tournage de page automatique en mode Kindle --
/// secondes par page, un curseur continu au lieu des 4 presets fixes de
/// `AutoScrollSpeed` (demande utilisateur 2026-08-01).
final kindlePageSecondsProvider =
    StateNotifierProvider<KindlePageSecondsNotifier, double>((ref) {
  return KindlePageSecondsNotifier();
});

class KindlePageSecondsNotifier extends StateNotifier<double> {
  KindlePageSecondsNotifier() : super(10.0) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kPrefKindlePageSeconds);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(double value) async {
    state = value.clamp(kKindlePageSecondsMin, kKindlePageSecondsMax);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefKindlePageSeconds, state);
  }

  // ── LA VITESSE S'APPREND, ELLE NE SE RÈGLE PLUS (2026-08-05) ─────────────
  //
  // Demande utilisateur : « dans le défilement il y a un temps, je ne veux
  // même pas qu'on affiche ce temps-là ». Et il a raison sur le fond : une
  // cadence de récitation ne se connaît pas à l'avance, elle ne s'exprime pas
  // en secondes par page, et personne ne sait déplacer un curseur pour dire
  // « je lis un peu plus lentement aujourd'hui ».
  //
  // Le geste qui porte l'information existe déjà : quand le lecteur touche
  // l'écran pour tourner AVANT que la page ne tourne toute seule, il dit
  // « trop lent ». Quand il revient en arrière, il dit « trop rapide ». On
  // apprend donc la cadence de CE lecteur sur CE passage au lieu de la lui
  // demander.
  //
  // ⚠️ POURQUOI UNE MOYENNE GLISSANTE ET NON LA DERNIÈRE MESURE. Un seul
  // écart ne dit rien : le lecteur peut avoir tourné parce qu'on l'a
  // interrompu, ou tapé deux fois de suite. Chaque observation ne déplace donc
  // l'estimation que d'une fraction — l'écran ne peut pas s'emballer sur un
  // geste isolé, et il converge quand même en quelques pages.
  static const _kInertie = 0.35;

  /// Les trois dernieres durees de page MESUREES (tap en avant uniquement).
  final _dernieres = <double>[];

  /// Le lecteur a tourné LUI-MÊME après [ecoule] secondes sur la page.
  ///
  /// [enAvant] false = il est revenu en arrière : il n'avait pas fini de lire,
  /// la page a donc tourné trop tôt et le temps doit AUGMENTER. C'est le seul
  /// cas où l'on ralentit, et il est volontairement plus prudent (on ne sait
  /// pas de combien il était en retard, seulement qu'il l'était).
  void apprendre(double ecoule, {required bool enAvant}) {
    // Un geste sous la seconde n'est pas une cadence de lecture : c'est un
    // double-tap, un rattrapage, ou un tap parasite. On l'ignore plutôt que de
    // laisser une valeur absurde entrer dans la moyenne -- exactement ce que
    // l'utilisateur a demandé d'éviter (« un temps illogique, on va pas le
    // considérer »).
    // ── SANS TRACE, RIEN N'EST DIAGNOSTICABLE (2026-08-07) ────────────────
    // Question de l'utilisateur : « y a-t-il de la log sur l'evolution de ce
    // delai ? » Il n'y en avait aucune. Or ce mecanisme decide TOUT SEUL
    // quand la page tourne : sans trace, un delai qui derive ou qui ne bouge
    // pas est indistinguable d'un mecanisme qui ne s'execute jamais -- c'est
    // exactement le piege paye le matin meme sur l'identification de sourate,
    // ou un chemin ecrit en `debugPrint` m'a fait conclure a tort qu'il
    // n'avait jamais tourne.
    if (ecoule < 1.0) {
      DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
          'geste ignore : ${ecoule.toStringAsFixed(2)}s < 1s '
          '(${enAvant ? "avant" : "arriere"}) -- tap parasite, delai inchange '
          'a ${state.toStringAsFixed(1)}s');
      return;
    }
    // ── EN AVANT : LA MESURE DEVIENT LA REFERENCE, SANS LISSAGE ───────────
    //
    // Demande utilisateur (2026-08-07) : « je trouve que l'adaptation se fait
    // lentement ; quand je tape avant qu'il tourne, au lieu de diminuer, il
    // vaut mieux remettre ce nouveau delai comme reference ».
    //
    // Et le raisonnement est juste : taper AVANT l'echeance n'est pas un
    // indice parmi d'autres, c'est une DECLARATION -- « j'ai fini de lire
    // cette page en tant de temps ». La moyenne glissante la traitait comme
    // une opinion a ponderer, d'où quatre ou cinq pages avant de converger.
    // Le temps ecoule est ici DIRECTEMENT observe, il n'y a rien a estimer.
    //
    // Le lissage reste pour le cas EN ARRIERE, et lui seul : revenir en
    // arriere ne donne PAS le bon temps, seulement le fait qu'il etait trop
    // court. On ne sait pas de combien. On allonge d'un quart et la
    // repetition du geste fait le reste -- on ne devine pas ce qu'on n'a pas
    // mesure.
    //
    // ⚠️ CONTREPARTIE ASSUMEE : un tap parasite en avant fixe desormais la
    // cadence a lui seul, alors que l'inertie l'aurait dilue. Le seul
    // garde-fou restant est le plancher `ecoule < 1.0`. Si des taps courts
    // parasites se voient a l'usage, c'est ce plancher qu'il faut relever
    // (vers 3-4 s), pas le lissage qu'il faut remettre : ce serait revenir au
    // defaut signale ici.
    final avant = state;
    if (enAvant) {
      // ── MEDIANE DES TROIS DERNIERES, PAS LA DERNIERE SEULE ─────────────
      //
      // L'affectation directe (2026-08-07, « l'adaptation se fait lentement »)
      // a bien supprime la convergence en cinq pages -- mais elle a supprime
      // AUSSI toute memoire : la derniere page gagnait toujours. Mesure du
      // meme jour : 24,5 -> 23,9 -> 30,0 -> 28,3, alors que les quatre pages
      // disent la meme chose (~26 s). Une page a long verset et une page a
      // versets courts donnent des temps tres differents, et le delai suivait
      // aveuglement la derniere.
      //
      // La mediane de trois garde la reactivite (trois pages, pas cinq) et
      // supprime l'a-coup : une page atypique ne peut plus imposer sa duree a
      // elle seule, il en faut deux pour deplacer la mediane.
      _dernieres.add(ecoule);
      if (_dernieres.length > 3) _dernieres.removeAt(0);
      final tri = [..._dernieres]..sort();
      final mediane = tri[tri.length ~/ 2];
      // ── UNE PAGE NE PEUT PAS ACCELERER DE PLUS DE 25 % D'UN COUP ────────
      //
      // Demande utilisateur (2026-08-07) : « pour le tap qui diminue le temps
      // de lecture, on fait un minimum qui doit etre etabli, exemple la
      // moyenne fois 0,75 -- la lecture ne va pas d'un coup devenir rapide de
      // 25 % de plus ».
      //
      // Le raisonnement est juste et il est asymetrique a dessein. Un tap
      // ANTICIPE peut avoir plusieurs causes : la page etait courte, on a
      // saute un passage deja connu, on a tape par reflexe. Rien n'oblige a
      // croire qu'on lit soudain deux fois plus vite. A l'inverse, se faire
      // couper en pleine page est un fait sans ambiguite -- c'est pour ca que
      // l'allongement, lui, n'a pas de bride ici (il a deja son lissage).
      //
      // Le plancher ne BLOQUE pas l'acceleration, il l'etale : 0,75 puis
      // encore 0,75 fait 0,56 en deux pages, 0,42 en trois. Une vraie lecture
      // rapide s'impose donc en quelques pages ; un tap isole, non.
      final plancher = avant * 0.75;
      final retenu = mediane < plancher ? plancher : mediane;
      set(retenu);
      DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
          'EN AVANT apres ${ecoule.toStringAsFixed(1)}s : '
          '${avant.toStringAsFixed(1)}s -> ${state.toStringAsFixed(1)}s '
          '(mediane de ${_dernieres.map((e) => e.toStringAsFixed(1)).join("/")})'
          '${retenu != mediane ? " -- PLANCHER -25 % applique (mediane brute "
              "${mediane.toStringAsFixed(1)}s)" : ""}'
          '${state != retenu ? " -- ECRETE aux bornes" : ""}');
      return;
    }
    set(avant + (avant * 1.25 - avant) * _kInertie);
    DiagnosticLog.log('Cadence', // TEMP-CADENCE : trace de mise au point, a retirer
        
        'EN ARRIERE apres ${ecoule.toStringAsFixed(1)}s : '
        '${avant.toStringAsFixed(1)}s -> ${state.toStringAsFixed(1)}s '
        '(trop tot, +25 % lisses a $_kInertie)');
  }
}

// Volontairement NON persisté (même raison que le mode Kindle lui-même est
// persisté mais pas ceci) : redémarrer en tournage automatique dès
// l'ouverture serait une mauvaise surprise, même si le mode Kindle et sa
// vitesse, eux, sont persistés.
final kindleAutoTurnProvider = StateProvider<bool>((ref) => false);

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
  /// État initial aligné sur `DiagnosticLog.enabled` (soit `!kReleaseMode`
  /// depuis le 2026-08-09) et NON sur `true` en dur : sans cet alignement,
  /// l'interrupteur des Réglages afficherait « activé » dans un build release
  /// où la journalisation est en réalité éteinte — un réglage qui ment sur
  /// l'état de la collecte de la voix de l'utilisateur.
  DiagnosticEnabledNotifier() : super(DiagnosticLog.enabled) {
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

const _kPrefMarquePages = 'marque_pages';

/// MARQUE-PAGES (2026-08-05) — décision utilisateur : « 5, sur le verset, pour
/// moi c'est le marque-page, ou le remplacer par un marque-page ».
///
/// Remplace l'étoile « Favoris » de la barre du bas, qui portait un
/// `onTap: () {}` vide depuis sa création : la fonction n'a jamais existé, ce
/// n'était pas une régression. Un signet dit mieux ce qu'on attend d'un
/// Mushaf — retrouver où on s'était arrêté — qu'un favori, qui suppose un
/// classement dont personne n'a besoin ici.
///
/// STOCKAGE : `"sourate:verset"`, la même clé que partout ailleurs dans l'app.
/// Un couple de nombres serait plus « propre » et obligerait à inventer une
/// sérialisation de plus ; la clé texte se relit à l'œil dans les préférences
/// et se compare sans conversion.
final marquePagesProvider =
    StateNotifierProvider<MarquePagesNotifier, Set<String>>((ref) {
  return MarquePagesNotifier();
});

class MarquePagesNotifier extends StateNotifier<Set<String>> {
  MarquePagesNotifier() : super(const {}) {
    _restore();
  }

  static String cle(int sourate, int verset) => '$sourate:$verset';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kPrefMarquePages);
    if (saved != null && mounted) state = saved.toSet();
  }

  bool contient(int sourate, int verset) => state.contains(cle(sourate, verset));

  /// @return true si le verset vient d'être marqué, false s'il vient d'être
  ///   retiré — l'appelant en a besoin pour dire lequel des deux s'est produit
  ///   sans relire l'état (qui est asynchrone à la persistance).
  Future<bool> basculer(int sourate, int verset) async {
    final k = cle(sourate, verset);
    final suivant = Set<String>.from(state);
    final ajoute = suivant.add(k);
    if (!ajoute) suivant.remove(k);
    state = suivant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefMarquePages, suivant.toList());
    return ajoute;
  }
}

const _kPrefPortionGranularity = 'portion_granularity';

/// Granularité de découpe des sourates trop longues pour être suivies en un
/// bloc dans le Coach (suivi permanent par portion, décision utilisateur
/// 2026-08-08 : « on va dire par 1/2 Hizb ou Hizb selon le réciteur »). Une
/// sourate qui tient dans un seul Hizb n'est JAMAIS découpée, quel que soit ce
/// réglage (cf. `PortionService.resolve`) -- il ne s'applique qu'aux sourates
/// qui s'étalent sur plusieurs Hizb (Al-Baqarah, Al-Imran, An-Nisa...).
/// Découpe d'une sourate trop longue pour être suivie d'un bloc.
///
/// `rubElHizb` (le QUART de Hizb) est le défaut depuis le 2026-08-13 :
/// « c'est ce qui est souvent utilisé pour la mémorisation » (utilisateur).
/// Les deux autres restent disponibles pour qui veut des tranches plus
/// larges. Une sourate qui tient dans un seul Hizb n'est JAMAIS découpée,
/// quel que soit ce réglage (cf. `PortionService.resolve`).
enum PortionGranularity { rubElHizb, demiHizb, hizb }

final portionGranularityProvider = StateNotifierProvider<
    PortionGranularitySettingNotifier, PortionGranularity>((ref) {
  return PortionGranularitySettingNotifier();
});

class PortionGranularitySettingNotifier
    extends StateNotifier<PortionGranularity> {
  PortionGranularitySettingNotifier() : super(PortionGranularity.rubElHizb) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kPrefPortionGranularity);
    if (!mounted || saved == null) return;
    // Lecture par NOM : un réglage enregistré avant l'ajout du quart de Hizb
    // (`hizb`/`demiHizb`) est respecté tel quel. Seuls ceux qui n'ont jamais
    // tranché basculent sur le nouveau défaut.
    for (final g in PortionGranularity.values) {
      if (g.name == saved) {
        state = g;
        return;
      }
    }
  }

  Future<void> set(PortionGranularity value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefPortionGranularity, value.name);
  }
}

// ── L'ENGAGEMENT DE MEMORISATION (Coach, 2026-08-13) ──────────────────────
// Clés de l'ANCIEN réglage (volume + période), conservées en lecture seule
// pour la migration ci-dessous. Elles ne sont plus écrites depuis le
// 2026-08-14 -- et volontairement pas effacées : tant qu'elles restent, la
// migration reste rejouable et un retour en arrière reste possible.
const _kPrefObjectifQuarts = 'coach_objectif_quarts';
const _kPrefObjectifPeriode = 'coach_objectif_periode';
const _kPrefObjectifAnnees = 'coach_objectif_annees';
const _kPrefCoachNiveau = 'coach_niveau';

/// Objectif de mémorisation et niveau d'accompagnement (cf. `PLAN_COACH.md`).
///
/// Un seul réglage saisi par l'utilisateur — en combien d'ANNÉES mémoriser
/// tout le Coran — dont l'app dérive le rythme par jour, semaine et mois. Le
/// niveau, lui, ne change QUE la fréquence des relances : il ne touche ni au
/// jugement de la récitation, ni aux paliers. Un utilisateur « À mon rythme »
/// voit exactement la même progression qu'un « Exigeant », il n'est simplement
/// pas relancé.
final objectifCoachProvider =
    StateNotifierProvider<ObjectifCoachNotifier, ObjectifCoach>((ref) {
  return ObjectifCoachNotifier();
});

class ObjectifCoachNotifier extends StateNotifier<ObjectifCoach> {
  ObjectifCoachNotifier() : super(const ObjectifCoach()) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final niveau = NiveauCoach.values.firstWhere(
        (n) => n.name == prefs.getString(_kPrefCoachNiveau),
        orElse: () => NiveauCoach.regulier);
    var annees = prefs.getInt(_kPrefObjectifAnnees) ?? 0;
    if (annees <= 0) {
      annees = _migrerDepuisVolumeParPeriode(prefs);
      if (annees > 0) await prefs.setInt(_kPrefObjectifAnnees, annees);
    }
    if (!mounted) return;
    state = ObjectifCoach(annees: annees, niveau: niveau);
  }

  /// Convertit un ancien objectif « N quarts par jour/semaine/mois » en une
  /// échéance en années, une seule fois.
  ///
  /// On repart du RYTHME QUOTIDIEN, seule grandeur commune aux deux modèles :
  /// N quarts sur une période de J jours donne N/J quart par jour, donc
  /// 240 / (N/J) jours pour tout le Coran. Borné à [ObjectifCoach.anneesMin] /
  /// [ObjectifCoach.anneesMax] — un ancien « 1 quart par mois » vaudrait 20
  /// ans, hors du curseur ; le ramener à 6 ans est le choix le plus proche que
  /// l'utilisateur peut désormais exprimer, et il reste libre de le rouvrir.
  ///
  /// Volontairement calculée sur les 240 quarts ENTIERS, pas sur le reste à
  /// mémoriser : la migration doit être reproductible et ne pas dépendre d'un
  /// état de progression qui, lui, bouge à chaque récitation.
  int _migrerDepuisVolumeParPeriode(SharedPreferences prefs) {
    final quarts = prefs.getInt(_kPrefObjectifQuarts) ?? 0;
    if (quarts <= 0) return 0; // aucun objectif n'avait été fixé
    final jours = switch (prefs.getString(_kPrefObjectifPeriode)) {
      'jour' => 1,
      'mois' => 30,
      _ => 7, // 'semaine', et défaut historique du réglage
    };
    final parJour = quarts / jours;
    final annees = (ObjectifCoach.quartsDuCoran / parJour / 365).round();
    return annees.clamp(ObjectifCoach.anneesMin, ObjectifCoach.anneesMax);
  }

  Future<void> definir({required int annees}) async {
    final borne = annees <= 0
        ? 0
        : annees.clamp(ObjectifCoach.anneesMin, ObjectifCoach.anneesMax);
    state = state.copyWith(annees: borne);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefObjectifAnnees, state.annees);
  }

  Future<void> setNiveau(NiveauCoach niveau) async {
    state = state.copyWith(niveau: niveau);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefCoachNiveau, niveau.name);
  }

  /// Réduit l'objectif après une semaine manquée — JAMAIS en silence, toujours
  /// depuis une proposition acceptée par l'utilisateur (cf. PLAN_COACH.md §2 :
  /// « un objectif qui baisse tout seul n'est plus un engagement »).
  ///
  /// Baisser l'objectif, c'est désormais ALLONGER l'échéance d'un an — « mieux
  /// vaut des petits pas qu'on réussit que des grands pas qu'on rate ». Au
  /// maximum du curseur il n'y a plus rien à détendre : on ne descend jamais à
  /// « aucun objectif », qui serait un abandon, pas une baisse.
  /// (AVANT le 2026-08-14 : `quarts * 2 ~/ 3`, plancher à 1 quart.)
  Future<void> reduireApresAccord() async {
    if (!state.actif || state.annees >= ObjectifCoach.anneesMax) return;
    await definir(annees: state.annees + 1);
  }
}

const _kPrefPhraseFinRecitation = 'phrase_fin_recitation_enabled';

/// « صدق الله العظيم » attendue APRÈS le dernier mot d'une sourate.
///
/// ── POURQUOI CE RÉGLAGE EXISTE (idée utilisateur, 2026-08-14) ──────────────
///
/// Le dernier mot d'une sourate ne pouvait JAMAIS être verrouillé : le
/// Décideur exige deux observations issues de fenêtres distinctes (`k = 2`) et
/// qu'un mot POSTÉRIEUR ait été observé -- deux conditions qu'aucune fenêtre
/// future ne peut plus satisfaire quand le récitateur s'arrête. Mesuré sur
/// device (An-Nasr, 2026-08-14) :
///     mot=22 "تَوَّابًۢا" -> provisoire:orange  obs=1  entendu="تَوَّابًا"
/// Le mot était bien récité, bien entendu, et n'a jamais pu être figé.
///
/// Proposition de l'utilisateur, préférée à un assouplissement de `k` : « on
/// peut garder k=2 mais rajouter à la fin de chaque sourate صدق الله العظيم si
/// on a un audio ». En récitant une phrase APRÈS la sourate, le dernier mot du
/// Coran cesse d'être le dernier -- il obtient sa seconde observation et son
/// contexte droit NATURELLEMENT, sans qu'aucune règle de preuve ne cède.
///
/// ⚠️ DÉSACTIVÉ PAR DÉFAUT, et ce n'est pas un choix technique : dire
/// « صدق الله العظيم » après la récitation est une pratique DÉBATTUE entre
/// savants, plusieurs la considérant non établie de la Sunna. L'application ne
/// l'impose donc à personne ; elle sait seulement l'attendre pour ceux qui la
/// disent déjà.
///
/// Les mots de la phrase sont ajoutés à la cible de la chaîne mais déclarés
/// NON JUGEABLES (même mécanisme que la Bismillah non récitée) : ils ne
/// reçoivent jamais de verdict, ne comptent dans aucun score, et ne sont pas
/// affichés dans le texte coranique.
final phraseFinRecitationProvider =
    StateNotifierProvider<PhraseFinRecitationNotifier, bool>((ref) {
  return PhraseFinRecitationNotifier();
});

class PhraseFinRecitationNotifier extends StateNotifier<bool> {
  PhraseFinRecitationNotifier() : super(false) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kPrefPhraseFinRecitation);
    if (saved != null && mounted) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefPhraseFinRecitation, value);
  }
}
