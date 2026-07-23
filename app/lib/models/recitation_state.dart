// État de la récitation dynamique (validation temps-réel mot-par-mot).
//
// Le principe : l'utilisateur récite en continu, et chaque mot du verset
// passe de pending → current → correct (vert) ou error (rouge),
// sans aucune interaction manuelle pendant la récitation.
import '../l10n/app_localizations.dart';
import 'judgement_options.dart';

enum WordStatus {
  pending,  // pas encore atteint (gris)
  current,  // en cours d'écoute (surligné)
  correct,  // validé (vert)
  unclear,  // reconnu mais imprécis — bon mot, articulation/harakat approximatives (orange)
  error,    // erreur détectée (rouge)
  skipped,  // sauté par le récitant (gris barré — l'orange est réservé à unclear)
}

enum RecitationStatus { idle, listening, processing, finished, error }

/// Phase du cycle de prière (mode "réciteur confiant" 2026-07-18, suivi d'un
/// imam) : une rak'ah dit "الله أكبر" PLUSIEURS fois (lever, rukū', chaque
/// sujūd...) mais SEULE la sourate suivie et Al-Fatiha sont du texte
/// coranique à corriger -- les autres takbirs sont suivis de silence/tasbih.
/// Comme un takbir seul ne dit pas LEQUEL il est, on ne peut pas décider
/// d'avance : TOUT takbir renvoie en [standby] (on arrête de juger l'ancienne
/// cible plutôt que de continuer à l'aveugle sur du contenu qui n'est plus
/// elle), et seule la RECONNAISSANCE EFFECTIVE du début d'Al-Fatiha fait
/// basculer vers [fatiha] -- les takbirs de rukū'/sujūd restent juste en
/// [standby] sans dégât, suivis d'un nouveau takbir plus tard.
enum PrayerPhase {
  none,            // comportement normal, hors cycle de prière
  standby,         // takbir détecté, en attente de reconnaître le début d'Al-Fatiha
  fatiha,          // Al-Fatiha en cours de suivi/correction
  detectingTarget, // Al-Fatiha terminée -- identification (Shazam) de la sourate suivante
  target,          // sourate en cours de suivi/correction après Al-Fatiha
}

/// Un mot du verset avec son texte affiché (harakat) et son état de validation.
class RecitedWord {
  final String display;     // texte original avec harakat (affichage)
  final String normalized;  // squelette sans harakat (alignement de position)
  final String strict;      // avec harakat (juge si la prononciation est correcte)
  // Forme fidèle à l'entraînement (ArabicNormalizer.normalizeTraining) — SEULE
  // forme à envoyer au tokenizer de l'alignement forcé (cf. recitation_verifier.dart) :
  // ne fusionne PAS أ/إ/آ/ى/ؤ/ئ/ة comme le fait `strict`, qui reste correct pour
  // la comparaison tolérante mais désaligne la cible envoyée au modèle.
  final String training;
  // Cible de l'alignement forcé ENVOYÉE au modèle. Pour le modèle stage1b-260h
  // (2026-07-19), c'est la forme ANNOTÉE de règles tajwid (lettres + harakat +
  // symboles PUA U+E000..U+E010) que le modèle a apprise à émettre -- aligner
  // sur `training` nu pénaliserait le chemin forcé sur chaque frame où le
  // modèle veut émettre un symbole appris, faussant la calibration du gop.
  // Repli sur `training` (== ancien comportement, sûr) quand aucune annotation
  // n'est disponible (texte hors-Coran, asset non chargé, ancien modèle sans
  // symboles). Les symboles n'apparaissent JAMAIS dans display/normalized/
  // strict (formes de comparaison/affichage) -- uniquement ici.
  //
  // ⚠️ CE RAISONNEMENT EST INVALIDÉ PAR LA MESURE (2026-07-20). Le commentaire
  // ci-dessus reste pour mémoire (ce qui avait été tenté et pourquoi), mais la
  // cible d'alignement est REPASSÉE sur `training` (texte nu) :
  //
  // Ce qu'on redoutait (pénaliser le chemin forcé quand le modèle veut émettre
  // un symbole) est réel, mais l'effet INVERSE l'est bien davantage : en
  // alignant sur la forme annotée, on EXIGE que le modèle émette le symbole
  // là où il est attendu. Un récitateur qui ne réalise pas une ghunnah -- ou
  // un modèle qui ne la détecte pas -- fait s'effondrer `forced` alors que ses
  // lettres et harakat sont justes. Résultat mesuré sur device : jugement
  // contaminé par le tajwid EN PERMANENCE, dans TOUS les modes, y compris
  // avec zéro règle activée (les toggles ne pilotent que l'affichage et le
  // plafonnement, jamais la cible d'alignement). L'utilisateur l'a diagnostiqué
  // en récitant : « j'ai l'impression toujours influencé par les règles de
  // tajweed » -- session en mode adulte, 17 corrections sur un récitateur
  // professionnel.
  //
  // La bonne architecture sépare les deux natures d'erreur, comme demandé :
  //   - PRONONCIATION (lettres + harakat) -> alignement forcé sur `training`
  //   - TAJWID (ghunnah, madd, qalqala...) -> vérification SÉPARÉE, à écrire,
  //     par confrontation de `expectedRules` aux symboles réellement émis.
  // رَبِّ vs رَبُّ (harakat, change le sens) n'est pas de même nature qu'une
  // qalqala ratée (texte identique, réalisation différente) : un seul verdict
  // mélangeant les deux n'a pas de sens pédagogique.
  final String alignTarget;
  // Règles tajwid ATTENDUES sur ce mot (extraites de la forme annotée), dans
  // l'ordre. Sert à confronter les symboles réellement émis par le modèle à
  // ceux attendus (détection "règle correctement réalisée ?") et à n'afficher
  // que les règles activées/fiables. Vide si le mot ne porte aucune règle.
  final List<TajwidRule> expectedRules;
  final WordStatus status;
  // Jugement DÉFINITIF (plus jamais réécrit) — distinct de [status] : un mot
  // peut avoir un statut (rouge/orange/vert) sans être verrouillé, tant qu'il
  // est le DERNIER mot reconnu d'un aperçu encore en formation (donc peut-être
  // encore incomplet — le modèle est peut-être encore en train de le décoder).
  // Bug réel constaté 2026-07-05 : sans cette distinction, un mot capté à
  // moitié ("ايا" au lieu de "اياك") était jugé rouge puis verrouillé, alors
  // qu'une passe suivante (mot complet, plus de contexte) le reconnaissait
  // parfaitement -- verrouillé trop tôt, jamais corrigé.
  final bool locked;
  // Ce qui a été RÉELLEMENT entendu sur ce mot (squelette normalisé), retenu
  // au moment du jugement. Ajouté le 2026-07-20 pour pouvoir CLASSER une
  // erreur (demande utilisateur : « les erreurs de récitation, les catégoriser
  // par type : tajwid ou prononciation ») : sans garder l'entendu, une erreur
  // journalisée ne dit que « ce mot a échoué », jamais POURQUOI. Vide tant que
  // le mot n'a pas été jugé.
  final String heard;
  // Règles de tajwid RÉELLEMENT détectées sur ce mot par la tête 2 du modèle
  // (architecture à deux têtes, 2026-07-22), conservées au moment du jugement
  // pour que la CLASSIFICATION d'erreur (classifyError, appelée plus tard sur
  // un mot déjà jugé) puisse s'y référer sans réanalyser l'audio — même
  // motivation que `heard` juste au-dessus. Vide tant que le mot n'est pas
  // jugé, ou si le modèle chargé n'a qu'une seule tête.
  final Set<TajwidRule> detectedRules;
  // GOP TAJWID gradué par classe de règle (index = id, même ordre que
  // TajwidRule.values) -- « 2ᵉ palier », cf. AlignedWord.tajwidGop. Conservé
  // au moment du jugement pour la même raison que `detectedRules` : la
  // classification d'erreur et la journalisation ont lieu APRÈS, sur un mot
  // déjà jugé, sans possibilité de réanalyser l'audio. Vide si le modèle n'a
  // qu'une seule tête -> on retombe alors sur la détection binaire.
  final List<double> tajwidGop;
  // Un des 4 mots de la formule d'ouverture "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ
  // ٱلرَّحِيمِ" -- vrai aussi bien pour Al-Fatiha 1:1 (texte verbatim
  // identique) que pour la Bismillah insérée devant une autre sourate (même
  // texte, même segment surah=1/ayah=1, cf. QuranApi.fetchBismillah).
  // Ajouté le 2026-07-20 : mesure sur le dataset d'entraînement (407k clips)
  // -- la Bismillah y est récitée ~44% plus vite en médiane que le reste du
  // Coran (plusieurs réciteurs à 3-4x le débit normal), traitée comme une
  // formule rituelle rapide plutôt qu'un verset posé. Conséquence mesurée sur
  // device, reproduite sur 3 pistes d'entraînement différentes le même soir :
  // le modèle est structurellement mal calibré (gop) sur CES mots précis,
  // quelle que soit la méthode d'entraînement -- pas un défaut de prononciation
  // du récitant. Décision utilisateur : ne plus juger ces 4 mots (ni gop ni
  // texte), plutôt que de continuer à chasser un correctif d'entraînement.
  final bool isBasmala;

  const RecitedWord({
    required this.display,
    required this.normalized,
    required this.strict,
    required this.training,
    String? alignTarget,
    this.expectedRules = const [],
    this.status = WordStatus.pending,
    this.locked = false,
    this.heard = '',
    this.detectedRules = const {},
    this.tajwidGop = const [],
    this.isBasmala = false,
  }) : alignTarget = alignTarget ?? training;

  RecitedWord copyWith({WordStatus? status, bool? locked, String? heard,
          Set<TajwidRule>? detectedRules, List<double>? tajwidGop}) =>
      RecitedWord(
        display: display,
        normalized: normalized,
        strict: strict,
        training: training,
        alignTarget: alignTarget,
        expectedRules: expectedRules,
        status: status ?? this.status,
        locked: locked ?? this.locked,
        heard: heard ?? this.heard,
        detectedRules: detectedRules ?? this.detectedRules,
        tajwidGop: tajwidGop ?? this.tajwidGop,
        isBasmala: isBasmala,
      );
}

/// Nature d'une erreur de récitation (demande utilisateur 2026-07-20 :
/// catégoriser « tajwid ou prononciation »).
///
/// Dérivée de la COMPARAISON entre l'attendu et l'entendu, pas d'une
/// annotation manuelle :
///  - squelette différent      -> lettre (ص/س, ط/ت...)      = prononciation
///  - squelette égal, harakat différentes -> harakat         = prononciation
///  - lettres ET harakat justes, mais le mot portait une règle tajwid
///    attendue -> tajwid (la règle est le seul écart restant plausible)
///  - rien d'entendu           -> mot sauté
///
/// HONNÊTETÉ SUR LA LIMITE : `tajwid` est une déduction PAR ÉLIMINATION, pas
/// une détection directe de la règle ratée. Le modèle peut avoir échoué pour
/// une autre raison subtile (durée, liaison). Tant que la mesure « détection
/// de fautes délibérées » n'existe pas (cf. REFONTE_IHM.md §12), cette
/// catégorie doit être lue comme « écart non expliqué par les lettres ni les
/// harakat, sur un mot qui porte une règle » — pas comme une preuve.
enum RecitationErrorKind { lettre, harakat, tajwid, saute, inconnu }

String recitationErrorKindLabel(AppLocalizations t, RecitationErrorKind k) =>
    switch (k) {
      RecitationErrorKind.lettre => t.errorKindLettre,
      RecitationErrorKind.harakat => t.errorKindHarakat,
      RecitationErrorKind.tajwid => t.errorKindTajwid,
      RecitationErrorKind.saute => t.errorKindSkippedWord,
      RecitationErrorKind.inconnu => t.errorKindUnknown,
    };

/// Famille de haut niveau demandée par l'utilisateur : tajwid vs prononciation.
String recitationErrorFamilyLabel(RecitationErrorKind k) => switch (k) {
      RecitationErrorKind.lettre ||
      RecitationErrorKind.harakat =>
        'Prononciation',
      RecitationErrorKind.tajwid => 'Tajwid',
      RecitationErrorKind.saute => 'Mot sauté',
      RecitationErrorKind.inconnu => 'Indéterminé',
    };

class RecitationSessionState {
  final List<RecitedWord> words;
  final int pointer;            // index du mot attendu courant
  final RecitationStatus status;
  final int correctCount;
  final int unclearCount;       // mots reconnus mais imprécis (orange)
  final int errorCount;
  final double soundLevel;      // niveau micro 0..1 (animation onde)
  final String rawTranscript;   // texte brut du modèle (debug/visualisation)
  final bool continuous;        // mode récitation continue (multi-versets, VAD)
  final int pendingSegments;    // segments en file d'attente/en cours d'analyse
  final PrayerPhase prayerPhase; // cycle de prière (mode "réciteur confiant")

  const RecitationSessionState({
    this.words = const [],
    this.pointer = 0,
    this.status = RecitationStatus.idle,
    this.correctCount = 0,
    this.unclearCount = 0,
    this.errorCount = 0,
    this.soundLevel = 0,
    this.rawTranscript = '',
    this.continuous = false,
    this.pendingSegments = 0,
    this.prayerPhase = PrayerPhase.none,
  });

  int get total => words.length;
  bool get isActive =>
      status == RecitationStatus.listening || status == RecitationStatus.processing;
  bool get isComplete => pointer >= total && total > 0;

  /// Score = mots corrects / total (0..100).
  double get score => total == 0 ? 0 : (correctCount / total) * 100;

  /// Précision parmi les mots évalués. Un mot "unclear" (bon mot, articulation
  /// imprécise) compte pour moitié — encourageant sans être laxiste.
  double get accuracy {
    final evaluated = correctCount + unclearCount + errorCount;
    return evaluated == 0
        ? 0
        : ((correctCount + unclearCount * 0.5) / evaluated) * 100;
  }

  RecitationSessionState copyWith({
    List<RecitedWord>? words,
    int? pointer,
    RecitationStatus? status,
    int? correctCount,
    int? unclearCount,
    int? errorCount,
    double? soundLevel,
    String? rawTranscript,
    bool? continuous,
    int? pendingSegments,
    PrayerPhase? prayerPhase,
  }) {
    return RecitationSessionState(
      words: words ?? this.words,
      pointer: pointer ?? this.pointer,
      status: status ?? this.status,
      correctCount: correctCount ?? this.correctCount,
      unclearCount: unclearCount ?? this.unclearCount,
      errorCount: errorCount ?? this.errorCount,
      soundLevel: soundLevel ?? this.soundLevel,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      continuous: continuous ?? this.continuous,
      pendingSegments: pendingSegments ?? this.pendingSegments,
      prayerPhase: prayerPhase ?? this.prayerPhase,
    );
  }
}
