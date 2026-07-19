// État de la récitation dynamique (validation temps-réel mot-par-mot).
//
// Le principe : l'utilisateur récite en continu, et chaque mot du verset
// passe de pending → current → correct (vert) ou error (rouge),
// sans aucune interaction manuelle pendant la récitation.
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

  const RecitedWord({
    required this.display,
    required this.normalized,
    required this.strict,
    required this.training,
    String? alignTarget,
    this.expectedRules = const [],
    this.status = WordStatus.pending,
    this.locked = false,
  }) : alignTarget = alignTarget ?? training;

  RecitedWord copyWith({WordStatus? status, bool? locked}) => RecitedWord(
        display: display,
        normalized: normalized,
        strict: strict,
        training: training,
        alignTarget: alignTarget,
        expectedRules: expectedRules,
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
