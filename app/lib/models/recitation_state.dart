/// État de la récitation dynamique (validation temps-réel mot-par-mot).
///
/// Le principe : l'utilisateur récite en continu, et chaque mot du verset
/// passe de [pending] → [current] → [correct] (vert) ou [error] (rouge),
/// sans aucune interaction manuelle pendant la récitation.

enum WordStatus {
  pending,  // pas encore atteint (gris)
  current,  // en cours d'écoute (surligné)
  correct,  // validé (vert)
  unclear,  // reconnu mais imprécis — bon mot, articulation/harakat approximatives (orange)
  error,    // erreur détectée (rouge)
  skipped,  // sauté par le récitant (gris barré — l'orange est réservé à unclear)
}

enum RecitationStatus { idle, listening, processing, finished, error }

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

  const RecitedWord({
    required this.display,
    required this.normalized,
    required this.strict,
    required this.training,
    this.status = WordStatus.pending,
    this.locked = false,
  });

  RecitedWord copyWith({WordStatus? status, bool? locked}) => RecitedWord(
        display: display,
        normalized: normalized,
        strict: strict,
        training: training,
        status: status ?? this.status,
        locked: locked ?? this.locked,
      );
}

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
    );
  }
}
