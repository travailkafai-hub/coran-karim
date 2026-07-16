import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recitation_state.dart';
import '../services/diagnostic_log.dart';
import '../services/fastconformer_verifier.dart' show AlignPayload;
import '../services/recitation_verifier.dart';

const double _kSimThreshold = 0.6;
// Au-dessus de ce seuil de similarité squelette (sans harakat), un mot aligné
// mais sans correspondance stricte est jugé "unclear" (orange : bon mot,
// articulation imprécise) plutôt que "error" (rouge : mot faux).
const double _kUnclearSimThreshold = 0.85;
const int _kLookahead = 3;
const int _kAlignLookahead = 6; // tolérance mots sautés/bruit dans le texte reconnu (realign complet)

// ── Seuils GOP (alignement forcé, cf. ForcedAligner.kt — refonte 2026-07-11) ──
// gop = logprob(chemin forcé = mot attendu) − logprob(meilleur chemin libre),
// moyenné par frame sur les frames de tokens du mot. Toujours ≤ 0.
//  - gop ≥ seuil "correct" : l'audio soutient le mot attendu (harakat
//    comprises) presque aussi bien que ce que le modèle préférerait dire →
//    correct (vert).
//  - gop ≥ seuil "unclear" : hésitation nette mais pas un rejet — typiquement
//    une harakat approximative ou une articulation floue → unclear (orange).
//  - sinon : le modèle est nettement plus sûr d'avoir entendu AUTRE CHOSE
//    (le champ `actual` dit quoi) → error (rouge).
// Valeurs par défaut CALIBRÉES sur device (correspondent à sensibilité=0.5,
// cf. `correctionSensitivityProvider`) — chaque jugement est logué avec son
// gop précis pour ajuster (chercher "[GOP]" dans le log persistant).
//
// ── Historique de calibrage (conserver, cf. règle : une piste invalidée reste
//    documentée AVEC sa raison, sinon elle se re-tente) ────────────────────
//
// RECALIBRAGE 2026-07-16 (matin) -> -5.0/-10.0 : **ERREUR, ANNULÉ le soir même**.
// Motif invoqué à l'époque : au passage au modèle tajweed (tokenizer
// tajweed_bpe_v1), des mots reconnus EXACTEMENT (entendu == mot attendu)
// donnaient gop=-4.43/-4.64/-4.70/-8.98 -- tous sous l'ancien seuil tolérant
// (-2.50), donc plus rien ne pouvait être jugé correct. Conclusion tirée :
// "ce checkpoint est moins confiant, décalons les seuils".
//
// POURQUOI C'ÉTAIT FAUX : ces gop dégradés n'avaient RIEN à voir avec le
// modèle. `word_tokens.json` était généré avec un token '▁' parasite en tête
// de chaque mot (bug de build_word_token_lookup.py, cf. le commentaire détaillé
// dans ce script) : un token que le modèle n'émet jamais, que l'alignement
// forcé devait quand même placer, et dont la logprob ~-inf polluait la moyenne
// du mot. Décaler les seuils revenait à ajuster le thermomètre parce que le
// thermomètre était cassé -- et ça a rendu l'app AVEUGLE : avec "correct" à
// -5.0, un mot dont le gop tombait à -1.28 avec une shadda manquante à
// l'oreille ("ٱلصِّرَٰطَ" entendu "ٱلصرَٰطَ") passait vert. Constat utilisateur
// 2026-07-16 15h06 : "j'ai forcé des erreurs de prononciation mais tout est en
// vert". Une erreur non détectée est bien pire qu'un faux positif ici.
//
// Le '▁' corrigé, le gop est revenu dans sa plage historique (0 à -1.5 sur la
// Fatiha entière, mesuré 15h05) -- exactement la plage pour laquelle les
// valeurs pcd ci-dessous avaient été calibrées sur device. Donc : RETOUR aux
// valeurs pcd, qui n'ont jamais été le problème.
//
// LEÇON : un gop hors plage attendue est un signal de BUG dans la chaîne de
// tokens, pas une invitation à bouger les seuils. Avant tout recalibrage,
// vérifier que `forced ≈ free` sur un mot correctement prononcé (gop ≈ 0) et
// qu'aucun token forcé n'est absent de ce que le modèle émet réellement.
const double _kGopCorrectDefault = -0.45;
const double _kGopUnclearDefault = -1.6;
// Bornes de la sensibilité réglable (demande utilisateur 2026-07-12 :
// "je veux que ça soit dynamique... la possibilité de modifier la
// sensibilité pour que le réciteur veuille quelque chose de strict... ou
// plus tolérant"). sensibilité=0 -> bande verte large (tolérant), =1 ->
// bande verte étroite (strict) ; =0.5 reproduit exactement les valeurs
// calibrées ci-dessus. Deux segments linéaires (tolérant<->défaut,
// défaut<->strict) pour garantir que 0.5 == comportement historique inchangé.
// Bornes revenues aux valeurs pcd en même temps que les défauts ci-dessus
// (elles avaient été décalées proportionnellement au recalibrage erroné du
// 2026-07-16 matin -> -7/-14/-3/-6, annulé, cf. explication plus haut).
const double _kGopCorrectTolerant = -0.90;
const double _kGopUnclearTolerant = -2.50;
const double _kGopCorrectStrict = -0.20;
const double _kGopUnclearStrict = -0.90;

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Moteur Whisper ONNX on-device.
/// Remplacer par MockRecitationVerifier() pour tester l'UI sans modèle.
final recitationVerifierProvider = Provider<RecitationVerifier>((ref) {
  final v = WhisperOnnxVerifier();
  ref.onDispose(v.dispose);
  return v;
});

final recitationProvider = StateNotifierProvider.autoDispose<
    RecitationNotifier, RecitationSessionState>((ref) {
  // Empêche l'autoDispose prématuré pendant le court instant où l'écran
  // karaoké s'abonne à `wordFailed` dans initState(), avant que build()
  // n'atteigne son propre ref.watch(recitationProvider) -- constat réel
  // 2026-07-10 : sans ça, Riverpod détruisait et recréait ce notifier entre
  // l'abonnement et le vrai démarrage de la récitation, laissant l'écran
  // accroché à une instance jetée. Résultat : aucune correction automatique
  // ne se déclenchait JAMAIS, silencieusement -- le flux `wordFailed` de la
  // nouvelle instance n'avait aucun abonné (confirmé en log,
  // `hasListener=false` au moment de l'émission).
  ref.keepAlive();
  return RecitationNotifier(ref.watch(recitationVerifierProvider));
});

class RecitationNotifier extends StateNotifier<RecitationSessionState> {
  final RecitationVerifier _verifier;
  StreamSubscription<RecognizedToken>? _tokenSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<String>? _rawSub;
  StreamSubscription<({String committed, String preview})>? _structSub;
  StreamSubscription<AlignPayload>? _alignSub;

  // Correction automatique (demande utilisateur 2026-07-05) : émis UNE fois
  // par mot, exactement au moment où il est verrouillé rouge pour la première
  // fois (les mots verrouillés ne sont plus jamais rejugés, donc pas de risque
  // de doublon). L'écran karaoké écoute ça pour déclencher pause + lecture
  // réciteur + reprise, sans aucune interaction manuelle.
  final _wordFailedCtrl = StreamController<int>.broadcast();
  Stream<int> get wordFailed => _wordFailedCtrl.stream;

  // ── Alignement ANCRÉ (mode continu) ────────────────────────────────────────
  // Les segments figés (committed) sont append-only : on les aligne UNE fois,
  // définitivement, et on avance l'ancre. Seul l'aperçu (preview) est ré-aligné
  // à chaque passe, à partir de l'ancre. Un mot jugé garde toujours son
  // meilleur statut (vert > orange > rouge > sauté) : une re-transcription
  // dégradée ne peut plus "déjuger" un mot déjà validé — c'est ce qui bloquait
  // le curseur (test réel 2026-07-05 : le début du texte disparaissait des
  // re-transcriptions, le ré-alignement depuis le mot 0 calait à jamais).
  String _prevCommitted = '';
  int _anchorExp = 0;
  StreamSubscription<int>? _pendingSub;

  // Seuils GOP EN VIGUEUR -- modifiables en direct pendant la récitation via
  // setSensitivity (demande utilisateur 2026-07-12), cf. constantes ci-dessus
  // pour le mapping exact 0-1 -> seuils.
  double _gopCorrect = _kGopCorrectDefault;
  double _gopUnclear = _kGopUnclearDefault;

  // Clips VÉRIFIÉS CORRECTS collectés pendant la session courante (mini-LoRA
  // personnalisation vocale, cf. FONCTIONNALITES_FUTURES.md "Personnalisation
  // voix -- niveau 3", implémenté 2026-07-12) -- seulement rempli quand la
  // capture est active (session de référence, cf. KaraokeRecitationScreen).
  // Un segment n'est retenu QUE si TOUS ses mots sont jugés WordStatus.correct
  // -- l'unique garantie qu'on a que le texte canonique correspond bien à ce
  // qui a été dit (même contrat que l'empreinte vocale : une tentative avec
  // erreur n'est pas une référence fiable).
  final List<({String path, String text})> _collectedClips = [];

  /// Retourne les clips collectés depuis le dernier appel et vide la liste.
  List<({String path, String text})> takeCollectedClips() {
    final clips = List<({String path, String text})>.of(_collectedClips);
    _collectedClips.clear();
    return clips;
  }

  /// Applique une sensibilité 0.0 (tolérant) .. 1.0 (strict) aux seuils GOP,
  /// EFFECTIVE DÈS LE PROCHAIN MOT JUGÉ (pas besoin de redémarrer la
  /// session) -- demande utilisateur 2026-07-12 : réglable "surtout pour
  /// celui qui récite", donc en cours de récitation, pas seulement avant.
  void setSensitivity(double sensitivity) {
    final s = sensitivity.clamp(0.0, 1.0);
    if (s <= 0.5) {
      final t = s / 0.5;
      _gopCorrect = _lerp(_kGopCorrectTolerant, _kGopCorrectDefault, t);
      _gopUnclear = _lerp(_kGopUnclearTolerant, _kGopUnclearDefault, t);
    } else {
      final t = (s - 0.5) / 0.5;
      _gopCorrect = _lerp(_kGopCorrectDefault, _kGopCorrectStrict, t);
      _gopUnclear = _lerp(_kGopUnclearDefault, _kGopUnclearStrict, t);
    }
  }

  /// Vrai pendant le stop() — empêche le double-stop et préserve le statut
  /// "processing" pendant que l'ASR tourne dans son isolate.
  bool _stopping = false;

  /// Vrai entre stopContinuous() et la vidange complète de la file de
  /// segments — le statut reste "processing" tant que pendingSegments > 0.
  bool _endingContinuous = false;

  /// Génération de session capturée juste après _verifier.start() (cf.
  /// Finding #1, revue de code 2026-07-16) — repassée à
  /// stopIfCurrentSession() au dispose pour que ce nettoyage fire-and-forget
  /// ne s'applique QUE si aucune session plus récente n'a démarré depuis
  /// (sinon il saboterait cette nouvelle session sur réouverture rapide de
  /// l'écran). -1 = aucune session démarrée par ce notifier.
  int _myGeneration = -1;

  RecitationNotifier(this._verifier) : super(const RecitationSessionState());

  void setup(String arabicText) {
    final words = ArabicNormalizer.splitExpectedWords(arabicText)
        .map((w) => RecitedWord(
              display: w,
              normalized: ArabicNormalizer.normalize(w),
              strict: ArabicNormalizer.normalizeStrict(w),
              training: ArabicNormalizer.normalizeTraining(w),
            ))
        .toList();
    state = RecitationSessionState(words: words);
  }

  /// Étend la session EN COURS avec du texte supplémentaire (enchaînement sur
  /// la sourate suivante, demande utilisateur 2026-07-11) — contrairement à
  /// [setup], ne touche RIEN de la progression déjà acquise (mots jugés,
  /// pointeur, ancre d'alignement) : ajoute seulement de nouveaux mots
  /// "pending" à la fin de la liste, et étend la cible native en conséquence
  /// SANS bouger son ancre (cf. RecitationVerifier.extendAlignmentTarget) —
  /// la récitation continue exactement où elle en était, juste avec plus de
  /// texte à réciter derrière.
  Future<void> extendWords(String moreArabicText) async {
    final newWords = ArabicNormalizer.splitExpectedWords(moreArabicText)
        .map((w) => RecitedWord(
              display: w,
              normalized: ArabicNormalizer.normalize(w),
              strict: ArabicNormalizer.normalizeStrict(w),
              training: ArabicNormalizer.normalizeTraining(w),
            ))
        .toList();
    if (newWords.isEmpty) return;
    state = state.copyWith(words: [...state.words, ...newWords]);
    await _verifier
        .extendAlignmentTarget(newWords.map((w) => w.training).toList());
  }

  Future<void> start() async {
    if (state.words.isEmpty || state.isActive) return;
    final reset = state.words
        .map((w) => w.copyWith(status: WordStatus.pending))
        .toList();
    if (reset.isNotEmpty) reset[0] = reset[0].copyWith(status: WordStatus.current);
    state = state.copyWith(
      words: reset,
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      status: RecitationStatus.listening,
      rawTranscript: '',
    );
    _tokenSub = _verifier.tokens.listen(_onToken);
    _levelSub = _verifier.soundLevel
        .listen((lvl) => state = state.copyWith(soundLevel: lvl));
    _rawSub = _verifier.rawTranscript.listen(_onRawSegment);
    _alignSub = _verifier.alignedWords.listen(_onAligned);
    // Forme fidèle à l'entraînement (PAS `strict`, qui fusionne des lettres
    // que le modèle a appris à distinguer — cf. normalizeTraining).
    await _verifier.start(state.words.map((w) => w.training).toList());
    _myGeneration = _verifier.sessionGeneration;
  }

  /// Démarre une récitation continue (plusieurs versets/une sourate entière),
  /// segmentée automatiquement par détection de silence (VAD). [arabicText]
  /// doit couvrir tout le fragment à réciter (setup() l'a déjà découpé en mots).
  Future<void> startContinuous() async {
    if (state.words.isEmpty || state.isActive) return;
    final reset = state.words.map((w) => w.copyWith(status: WordStatus.pending)).toList();
    if (reset.isNotEmpty) reset[0] = reset[0].copyWith(status: WordStatus.current);
    _endingContinuous = false;
    state = state.copyWith(
      words: reset,
      pointer: 0,
      correctCount: 0,
      unclearCount: 0,
      errorCount: 0,
      status: RecitationStatus.listening,
      rawTranscript: '',
      continuous: true,
      pendingSegments: 0,
    );
    _prevCommitted = '';
    _anchorExp = 0;
    _collectedClips.clear();
    _tokenSub = _verifier.tokens.listen(_onToken);
    _levelSub = _verifier.soundLevel
        .listen((lvl) => state = state.copyWith(soundLevel: lvl));
    _structSub = _verifier.structuredTranscript.listen(_onStructured);
    _pendingSub = _verifier.pendingSegments.listen(_onPendingChanged);
    _alignSub = _verifier.alignedWords.listen(_onAligned);
    // Forme fidèle à l'entraînement — cible de l'alignement forcé GOP.
    await _verifier.start(
      state.words.map((w) => w.training).toList(),
      continuous: true,
    );
    _myGeneration = _verifier.sessionGeneration;
  }

  /// Remplace (pas d'accumulation) : en mode streaming, chaque appel renvoie
  /// déjà le texte COMPLET décodé jusqu'ici ; en mode segment unique (Coach),
  /// il n'y a qu'un seul segment par session donc remplacer == accumuler.
  void _onRawSegment(String txt) {
    state = state.copyWith(rawTranscript: txt);
    // Diff textuel SEULEMENT en repli : quand l'alignement forcé GOP est actif
    // (modèle déployé), _onAligned est l'unique source de jugement — juger ici
    // en plus écraserait ses verdicts avec la méthode moins fiable.
    if (!_verifier.alignmentActive) _realignFromFullText(txt);
    // Phrase de clôture traditionnelle "Sadaqa Allahu al-'Adhim" (صدق الله
    // العظيم) dite en fin de récitation — la détecter arrête l'écoute
    // automatiquement, en complément du bouton dédié (demande utilisateur
    // 2026-07-09, suite au tap accidentel qui coupait les derniers mots
    // d'An-Nas). Gardée derrière `_anchorExp >= words.length` : elle n'est
    // vérifiée qu'une fois tout le texte attendu déjà atteint, pour ne
    // jamais interrompre une récitation en cours sur une coïncidence de mots
    // (le modèle n'a jamais appris cette formule comme un verset).
    if (_anchorExp >= state.words.length && _hasClosingPhrase(txt)) {
      stopContinuous();
    }
  }

  static final _closingPhraseWords =
      ['صدق', 'الله', 'العظيم'].map(ArabicNormalizer.normalize).toList();

  bool _hasClosingPhrase(String rawText) {
    final tokens = ArabicNormalizer.normalize(rawText).split(RegExp(r'\s+'));
    var idx = 0;
    for (final t in tokens) {
      if (t == _closingPhraseWords[idx]) {
        idx++;
        if (idx == _closingPhraseWords.length) return true;
      }
    }
    return false;
  }

  // Un mot ayant reçu un jugement DÉFINITIF (vert/orange/rouge) est verrouillé
  // pour toujours — aucune passe ultérieure ne peut plus le modifier, dans
  // AUCUN sens. Décision utilisateur 2026-07-05, suite à un test réel : avec
  // la règle précédente ("jamais rétrograder", vert protégé mais rouge
  // librement upgradable), un mot correctement jugé rouge (harakat volontai-
  // rement fautive) est repassé vert dès qu'une repasse ultérieure — bénéfi-
  // ciant de plus de contexte — a vu le modèle "corriger" silencieusement
  // vers le texte canonique (biais du modèle vers les formules très
  // fréquentes, cf. SKILL.md). Verrouiller dans les deux sens élimine ce faux
  // négatif : le premier jugement honnête prime, y compris s'il est rouge.
  //
  // MAIS (bug réel constaté juste après, même jour) : verrouiller aveuglément
  // capture aussi les mots dont la reconnaissance est encore INCOMPLÈTE — le
  // DERNIER mot reconnu d'un aperçu en formation peut n'être qu'à moitié
  // prononcé/décodé (ex: "ايا" pour "اياك", "الرحمه" pour "الرحمان"). Verrouillé
  // trop tôt en rouge, jamais corrigé même quand la passe suivante (mot
  // complet, plus de contexte) le reconnaît parfaitement. Fix : ne verrouiller
  // un mot que s'il n'est PAS le dernier jeton de la passe courante (donc le
  // modèle a bien continué au-delà, preuve que ce mot est acoustiquement
  // "fermé") — sauf si le texte est définitivement figé (segment commit),
  // où là tout se verrouille immédiatement (l'audio de ce segment ne sera
  // plus jamais réanalysé).
  // Fenêtre de tolérance EN ARRIÈRE (demande utilisateur 2026-07-06) :
  // combien de mots déjà validés avant l'ancre peuvent être répétés sans
  // pénalité (reprise d'élan naturelle avant de continuer). Ne concerne QUE
  // les mots déjà jugés/verrouillés -- jamais une recherche en avant.
  // Élargie de 3 à 5 (demande utilisateur 2026-07-09) : après une correction
  // (rewindAndUnlock), le réciteur reprend parfois 3-4 mots AVANT le mot fautif
  // pour un élan naturel avant de le redire -- à 3, le 4e mot de recul sortait
  // de la fenêtre et se faisait juger (à tort) comme une erreur sur le mot
  // attendu courant, au lieu d'être toléré comme une simple reprise.
  static const int _kBackToleranceWindow = 5;

  void _judge(List<RecitedWord> words, int i, WordStatus judged,
      {required bool lock, List<int>? newErrors}) {
    if (words[i].locked) return;
    words[i] = words[i].copyWith(status: judged, locked: lock);
    // Rouge (faux), orange (imprécis) ET gris (sauté) déclenchent la
    // correction — demande utilisateur 2026-07-05 (rouge/orange) puis
    // 2026-07-06 (sauté) : "pour moi c'est une erreur aussi" — sauter un mot
    // n'est plus juste constaté passivement, ça doit aussi être corrigé.
    if (lock &&
        (judged == WordStatus.error ||
            judged == WordStatus.unclear ||
            judged == WordStatus.skipped)) {
      newErrors?.add(i);
    }
  }

  /// Aligne séquentiellement [recNorm]/[recStrict] sur les mots attendus à
  /// partir de [from]. [isFinal] : true pour un segment figé (verrouille
  /// tout immédiatement), false pour un aperçu encore révisable (ne
  /// verrouille pas son dernier mot, possiblement incomplet). [newErrors]
  /// collecte les mots FRAÎCHEMENT verrouillés rouge/orange (pour déclencher
  /// la correction automatique après coup). Retourne l'index attendu atteint.
  ///
  /// COMPARAISON DIRECTE, SANS RECHERCHE EN AVANT (demande utilisateur
  /// 2026-07-06 : "je veux même pas que tu vérifies... tu compares juste
  /// avec le mot attendu direct") — chaque jeton reconnu est comparé
  /// UNIQUEMENT au mot attendu à la position courante, jamais à une fenêtre
  /// de mots plus loin. Un saut (l'utilisateur dit un mot plus loin dans le
  /// verset) n'est donc plus "détecté" spécialement : le mot attendu ne
  /// correspond juste à rien, et après quelques tentatives sans
  /// correspondance (voir l'abandon ci-dessous), il est marqué faux comme
  /// n'importe quelle erreur — cohérent avec la demande précédente de
  /// traiter un saut comme une erreur à corriger, pas un cas spécial détecté
  /// par avance.
  int _alignChunk(List<RecitedWord> words, List<String> recNorm,
      List<String> recStrict, int from,
      {required bool isFinal, List<int>? newErrors}) {
    var expIdx = from;
    // Un aperçu (isFinal=false) repart TOUJOURS de _anchorExp, qui n'avance
    // QUE sur du texte figé -- un abandon ("give-up") décidé pendant un
    // aperçu verrouille bien le mot, mais _anchorExp lui-même ne bouge pas.
    // Sans ce saut, l'appel suivant retente le MÊME mot déjà verrouillé,
    // échoue pareil, ré-abandonne, boucle indéfiniment (bug réel constaté
    // 2026-07-06 : "abandon sur ... " répété en continu, récitation bloquée).
    while (expIdx < words.length && words[expIdx].locked) {
      expIdx++;
    }
    for (var r = 0; r < recNorm.length && expIdx < words.length; r++) {
      var tokNorm = recNorm[r];
      var tokStrict = recStrict[r];
      var consumed = 1;
      var sim = ArabicNormalizer.similarity(tokNorm, words[expIdx].normalized);

      if (sim < _kSimThreshold) {
        // AVANT toute tentative de fusion avec le jeton suivant : ce jeton
        // seul n'est-il pas simplement la reprise d'un mot déjà validé, ou
        // l'écho d'une syllabe déjà traitée ? Un mot déjà passé ne doit
        // JAMAIS participer à une fusion avec le mot attendu courant —
        // régression réelle constatée 2026-07-10 (sourate 113) : "برب"
        // (déjà verrouillé juste avant) collé à tort à "الفلق" pour former
        // "بربالفلق", faisant chuter "الفلق" en rouge alors qu'il avait été
        // reconnu parfaitement (sim=1.00) quelques passes plus tôt.
        final prevTok = r > 0 ? recNorm[r - 1] : null;
        final isEcho =
            tokNorm.length <= 2 && prevTok != null && prevTok.endsWith(tokNorm);
        if (isEcho) {
          // Écho/doublon halluciné : un jeton très court qui n'est que la
          // syllabe finale du jeton reconnu JUSTE AVANT — constat réel
          // 2026-07-10 ("الْحَمْدُ" ressort parfois "الْحَمْدُ دُ", la syllabe finale
          // redite comme un "mot" séparé). Aucun vrai mot coranique isolé ne
          // fait 1-2 lettres ; ignorer ce cas précis n'affecte pas la
          // détection de vrais mots sautés/faux.
          debugPrint('[Align] rec="$tokNorm" -> écho/doublon halluciné '
              'ignoré (reprend la fin de "$prevTok")');
          continue;
        }
        // Tolérance sur ce qui est DÉJÀ PASSÉ, exigence sur ce qui VA VENIR
        // (demande utilisateur 2026-07-06) : recherche UNIQUEMENT en
        // arrière, jamais en avant (la règle "comparaison directe, sans
        // recherche en avant" du 2026-07-06 reste intacte pour le mot
        // attendu). Si ça correspond à du passé, c'est toléré sans pénalité.
        if (_matchesRecentPast(words, expIdx, tokNorm)) {
          debugPrint('[Align] rec="$tokNorm" exp=$expIdx -> toléré '
              '(reprise d\'un mot déjà validé, ignoré sans pénalité)');
          continue;
        }
        // Fusion de 2 jetons adjacents mal scindés par l'ASR (constat réel
        // 2026-07-10, sourate 111 : "وما" ressort parfois comme deux jetons
        // séparés par un espace, "و" puis "ما" — le second, isolé, ne matche
        // que partiellement "وما" et se verrouille faux à tort). Seulement
        // maintenant qu'on sait que ce jeton n'est ni un écho ni une reprise
        // du passé -- on ne l'utilise que si elle améliore réellement le
        // score.
        if (r + 1 < recNorm.length) {
          final mergedNorm = recNorm[r] + recNorm[r + 1];
          final simMerged = ArabicNormalizer.similarity(
              mergedNorm, words[expIdx].normalized);
          if (simMerged > sim) {
            tokNorm = mergedNorm;
            tokStrict = recStrict[r] + recStrict[r + 1];
            consumed = 2;
            sim = simMerged;
          }
        }
      }
      if (sim >= _kSimThreshold) {
        final isLastToken = (r + consumed - 1) == recNorm.length - 1;
        final isExact =
            ArabicNormalizer.matchesTolerant(tokStrict, words[expIdx].strict);
        final judged = isExact
            ? WordStatus.correct
            : (sim >= _kUnclearSimThreshold ? WordStatus.unclear : WordStatus.error);
        // Un jugement ERREUR ne se verrouille QUE sur un segment vraiment
        // figé (isFinal) -- jamais sur un simple aperçu, même si ce jeton
        // n'est pas le dernier de la passe (demande/constat utilisateur
        // 2026-07-10, répété sur "لينبذن" ET "الذين" : un aperçu encore
        // instable peut rater la dernière lettre d'un mot, puis un segment
        // figé ULTÉRIEUR reconnaît le même passage correctement -- mais le
        // mot était déjà verrouillé rouge à tort, donc jamais rattrapable).
        // Vert/orange restent verrouillables tôt (aucun souci constaté là).
        final lock = isFinal || (!isLastToken && judged != WordStatus.error);
        debugPrint('[Align] rec="$tokNorm" (strict="$tokStrict") '
            'exp=$expIdx sim=${sim.toStringAsFixed(2)} '
            'exp.norm="${words[expIdx].normalized}" exp.strict="${words[expIdx].strict}" '
            '-> $judged (lock=$lock)'
            '${consumed == 2 ? ' [fusion de 2 jetons]' : ''}');
        _judge(words, expIdx, judged, lock: lock, newErrors: newErrors);
        expIdx++;
        r += consumed - 1;
      } else {
        // L'écho/doublon halluciné et la reprise d'un mot déjà validé sont
        // déjà écartés plus haut (avant la tentative de fusion) -- ce qui
        // arrive ici n'est ni l'un ni l'autre : un vrai signal de bruit/mot
        // inconnu.
        debugPrint('[Align] rec="$tokNorm" exp=$expIdx '
            '("${words[expIdx].normalized}") -> AUCUNE correspondance '
            '(sim=${sim.toStringAsFixed(2)} < seuil $_kSimThreshold, '
            'ni avec un mot déjà passé) -- ignoré comme bruit');
        // Exigence immédiate sur du texte FIGÉ (demande utilisateur
        // 2026-07-06 : un mot inventé/inséré qui ne correspond ni à ce qui
        // vient ni à ce qui est déjà passé doit être détecté tout de suite,
        // pas après plusieurs tentatives). isFinal seulement : un aperçu
        // (isFinal=false) est ré-évalué très souvent PENDANT qu'un mot est
        // encore en train d'être prononcé -- l'audio incomplet produit
        // presque toujours des lectures partielles déformées avant de se
        // stabiliser ; juger sur un aperçu a déjà causé un abandon prématuré
        // en cascade (bug réel constaté 2026-07-06). Une fois le segment
        // FIGÉ (donc l'audio complet), un jeton qui ne correspond à rien de
        // connu est un signal fiable dès la première fois.
        if (isFinal) {
          debugPrint('[Align] "${words[expIdx].display}" ne correspond à '
              'rien de connu -> WordStatus.error immédiat');
          _judge(words, expIdx, WordStatus.error, lock: true, newErrors: newErrors);
          expIdx++;
        }
      }
    }
    return expIdx;
  }

  /// Vrai si [recNorm] ressemble à l'un des [_kBackToleranceWindow] derniers
  /// mots DÉJÀ VALIDÉS (verrouillés) avant [expIdx] — jamais une recherche en
  /// avant, seulement en arrière, et seulement des mots déjà jugés (pas de
  /// mots encore en attente).
  bool _matchesRecentPast(List<RecitedWord> words, int expIdx, String recNorm) {
    final start = (expIdx - _kBackToleranceWindow).clamp(0, expIdx);
    for (var e = start; e < expIdx; e++) {
      if (!words[e].locked) continue;
      if (ArabicNormalizer.similarity(recNorm, words[e].normalized) >= _kSimThreshold) {
        return true;
      }
    }
    return false;
  }

  List<String> _splitNorm(String txt) => txt
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(ArabicNormalizer.normalize)
      .toList();

  List<String> _splitStrict(String txt) => txt
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(ArabicNormalizer.normalizeStrict)
      .toList();

  /// Mode continu : scoring ancré sur les segments figés.
  /// REPLI uniquement — quand l'alignement forcé GOP est actif, _onAligned
  /// juge et cette méthode ne fait plus que rafraîchir le texte affiché.
  void _onStructured(({String committed, String preview}) parts) {
    if (state.words.isEmpty) return;
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;

    if (_verifier.alignmentActive) {
      final display = [parts.committed, parts.preview]
          .where((t) => t.isNotEmpty)
          .join(' ');
      state = state.copyWith(rawTranscript: display);
      return;
    }

    final words = [...state.words];
    final newErrors = <int>[];

    // 1. Nouveau texte figé ? Aligné UNE fois, définitivement, depuis l'ancre.
    if (parts.committed != _prevCommitted) {
      if (parts.committed.startsWith(_prevCommitted)) {
        final newPart = parts.committed.substring(_prevCommitted.length);
        _anchorExp = _alignChunk(
            words, _splitNorm(newPart), _splitStrict(newPart), _anchorExp,
            isFinal: true, newErrors: newErrors);
      } else {
        // Le buffer figé natif a redémarré (nouveau segment VAD) au lieu de
        // prolonger le précédent -- constat réel 2026-07-10 (sourate 98) :
        // le verset 1 entier revenait comme "nouveau" texte alors que
        // l'ancre attendait déjà le verset 2/3 ; chaque mot réellement dit
        // était comparé au mauvais mot attendu -> avalanche de 10 mots faux
        // d'un coup dans le même appel. Impossible de savoir de façon fiable
        // où ce texte redémarré se situe dans l'attendu (pas de recherche en
        // avant, cf. _alignChunk) -- dans tous les cas observés, il s'agit
        // d'une reconfirmation de contenu déjà entendu, jamais de contenu
        // qui ne reviendrait plus. On l'ignore plutôt que de le comparer à
        // l'aveugle contre l'ancre courante ; du contenu vraiment nouveau
        // reviendra dans un commit suivant, avec au pire un cycle de retard.
        debugPrint('[Align] Redémarrage du texte figé détecté (ne prolonge '
            'plus le précédent, ${parts.committed.length} car.) -- segment '
            'ignoré pour éviter une comparaison au mauvais endroit');
      }
      _prevCommitted = parts.committed;
    }

    // 2. Aperçu : ré-aligné à chaque passe depuis l'ancre. isFinal=false : le
    //    dernier mot reconnu peut être incomplet, pas verrouillé tant qu'une
    //    passe ultérieure ne confirme pas qu'on est passé au-delà.
    var reach = _anchorExp;
    if (parts.preview.isNotEmpty) {
      reach = _alignChunk(
          words, _splitNorm(parts.preview), _splitStrict(parts.preview), _anchorExp,
          isFinal: false, newErrors: newErrors);
    }

    // 3. Pointeur = premier mot encore pending/current (les mots jugés ou
    //    sautés sont verrouillés/avancés, donc il ne recule jamais).
    var pointer = 0;
    while (pointer < words.length &&
        words[pointer].status != WordStatus.pending &&
        words[pointer].status != WordStatus.current) {
      pointer++;
    }
    if (pointer < reach) pointer = reach;

    // Invariant : au plus UN mot "current" à la fois. Une passe d'aperçu
    // révisée peut recalculer un `reach` plus petit que celui d'une passe
    // précédente (transcription réévaluée) et laisser un ancien marqueur
    // "current" orphelin plus loin dans la liste, jamais nettoyé. Bug réel
    // constaté en test (2026-07-06) : deux mots "current" simultanément ->
    // crash Flutter (GlobalKey dupliquée côté UI, qui suppose un seul mot
    // courant). On nettoie tout marqueur "current" qui n'est pas au nouveau
    // pointeur avant d'en poser un nouveau.
    for (var i = 0; i < words.length; i++) {
      if (i != pointer && words[i].status == WordStatus.current) {
        words[i] = words[i].copyWith(status: WordStatus.pending);
      }
    }
    if (pointer < words.length &&
        words[pointer].status == WordStatus.pending) {
      words[pointer] = words[pointer].copyWith(status: WordStatus.current);
    }

    var correct = 0, unclear = 0, errors = 0;
    for (final w in words) {
      switch (w.status) {
        case WordStatus.correct:
          correct++;
        case WordStatus.unclear:
          unclear++;
        case WordStatus.error:
          errors++;
        default:
          break;
      }
    }

    final display = [parts.committed, parts.preview]
        .where((t) => t.isNotEmpty)
        .join(' ');
    final done = pointer >= words.length;
    state = state.copyWith(
      words: words,
      pointer: pointer,
      correctCount: correct,
      unclearCount: unclear,
      errorCount: errors,
      rawTranscript: display,
      status: done ? RecitationStatus.finished : state.status,
    );
    if (done) _finish();
    // Émis APRÈS que `state` reflète déjà le nouveau statut, pour que les
    // écouteurs (correction automatique) voient un état cohérent.
    for (final i in newErrors) {
      _wordFailedCtrl.add(i);
    }
  }

  /// Jugement PRIMAIRE (refonte 2026-07-11) : alignement forcé GOP calculé
  /// nativement sur les log-probabilités du modèle (cf. ForcedAligner.kt).
  /// Remplace le diff textuel flou (_alignChunk/_realignFromFullText, gardés
  /// en repli quand le modèle n'est pas déployé) : chaque mot couvert par
  /// l'audio reçoit gop = P(mot attendu|audio) − P(meilleur chemin|audio) —
  /// on mesure si l'AUDIO soutient le mot attendu (harakat comprises), au lieu
  /// de comparer deux textes après qu'un décodeur biaisé vers le texte
  /// canonique (cf. SKILL.md) a déjà lissé les erreurs. Les rustines
  /// d'alignement historiques (écho/doublon, fusion de jetons, tolérance
  /// arrière, redémarrage de segment) deviennent sans objet ici : la position
  /// de chaque mot est déterminée acoustiquement par la DP, plus par une
  /// correspondance de chaînes.
  void _onAligned(AlignPayload p) {
    if (state.words.isEmpty) return;
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;

    final words = [...state.words];
    final newErrors = <int>[];

    for (final r in p.words) {
      if (r.index < 0 || r.index >= words.length) continue;
      if (words[r.index].locked) continue;
      // Mot à la frontière d'un aperçu : encore en cours de prononciation,
      // l'audio ne le couvre pas entièrement — ne pas juger (le verrouillage
      // prématuré d'un mot à moitié décodé est LE bug historique 2026-07-05).
      if (!r.covered && !p.isFinal) continue;

      final expected = words[r.index];
      final actualStrict = ArabicNormalizer.normalizeStrict(r.actual);
      final actualNorm = ArabicNormalizer.normalize(r.actual);
      final textMatches =
          ArabicNormalizer.matchesTolerant(actualStrict, expected.strict);

      // IMPORTANT : la confirmation textuelle (`textMatches`) ne peut que
      // RATTRAPER un score limite vers "correct" — jamais sauver un gop
      // franchement rejeté (< _kGopUnclear). Bug corrigé 2026-07-11 : la
      // version précédente acceptait `textMatches` seule, sans plancher —
      // un mot avec gop=-5.1 (rejet massif du chemin forcé) ressortait quand
      // même "correct" dès que le décodage libre épelait le mot attendu.
      // Comme le décodage libre est PRÉCISÉMENT ce que le GOP est censé
      // contourner (biais du modèle vers le texte canonique, cf. SKILL.md),
      // ce bypass sans plancher annulait tout l'intérêt de la refonte.
      // Bug corrigé 2026-07-16 : sur des frames quasi-silencieuses (utilisateur
      // qui ne parle pas / pause), `r.actual` (entendu) est vide -- le chemin
      // forcé ET le chemin libre prédisent alors tous deux du blank quasi-pur,
      // donc leur différence (gop) tombe près de 0 par pur hasard, sans
      // qu'aucun contenu réel n'ait été confirmé. Observé sur device : gop=0.00,
      // entendu="" -> jugé "correct" alors que l'utilisateur n'avait rien dit
      // ("le mot se met au vert tout seul après un silence"). `hasSpeech`
      // bloque ce cas : jamais "correct" sans au moins un caractère décodé.
      final hasSpeech = r.actual.trim().isNotEmpty;

      // Le décodage libre épelle-t-il franchement un AUTRE mot ? (2026-07-16)
      //
      // Jusqu'ici la comparaison textuelle ne servait que dans UN sens : rendre
      // le verdict plus INDULGENT (`textMatches` rattrape un gop limite). Rien
      // n'empêchait l'inverse -- être vert alors que le modèle a écrit un autre
      // mot. Cas réel mesuré sur device (log 16h59, modèle mixed-e02) :
      //     attendu "صِرَٰطَ" (sad) / entendu "سَرَٰطَ" (sin)
      //     gop=-0.35 forced=-1.77 free=-1.42  -> jugé CORRECT (vert)
      // Le modèle avait PARFAITEMENT entendu le sin de l'utilisateur, mais le
      // gop est une mesure RELATIVE (forced - free) : le modèle hésitant sur
      // tout à cet endroit (free=-1.42), le chemin forcé n'était "pas beaucoup
      // pire" que son meilleur choix -> écart faible -> vert. Aucun réglage de
      // seuil ne corrige ça proprement (en strict, -0.35 passerait orange par
      // chance, pas par raisonnement), alors que l'information est là, écrite
      // noir sur blanc dans `entendu`.
      //
      // Distinction essentielle -- SUBSTITUTION vs TRONCATURE : le texte
      // reconnu diffère aussi pour un pur artefact de découpage, quand la
      // coupure de segment ampute le mot (même log : attendu "ٱلْحَمْدُ",
      // entendu "مْدُ", gop=-0.04). Traiter les deux pareil ferait passer
      // orange des mots parfaitement récités. Un fragment (préfixe ou suffixe
      // de l'attendu) reste donc jugé sur le gop seul, comme avant ; seule une
      // vraie substitution (lettre/harakat changée) bloque le vert.
      // Bug corrigé 2026-07-16 (revue de code, Finding #6) : cette borne
      // (>=2 caractères ET >=1/3 de la longueur du mot attendu) était absente
      // -- `endsWith`/`startsWith` sur UN SEUL caractère coïncidant avec la
      // première/dernière lettre de `expected.strict` suffisait à passer
      // isFragment=true, rouvrant exactement le bug sin/sad de ce même jour
      // (une transcription fausse d'un seul caractère aurait forcé
      // spellsDifferentWord=false et renvoyé au jugement gop seul). Calculé
      // sur les cas réels observés : troncature légitime ("ٱلْحَمْدُ"->"مْدُ")
      // = ratio 0.44, coïncidence 1 caractère = ratio 0.14 -- un seuil à 1/3
      // sépare proprement les deux sans perdre le cas de troncature.
      final isLongEnoughToBeFragment =
          actualStrict.length >= 2 && actualStrict.length * 3 >= expected.strict.length;
      final isFragment = hasSpeech &&
          actualStrict.isNotEmpty &&
          expected.strict.isNotEmpty &&
          isLongEnoughToBeFragment &&
          (expected.strict.endsWith(actualStrict) ||
              expected.strict.startsWith(actualStrict));
      final spellsDifferentWord = hasSpeech && !textMatches && !isFragment;

      final WordStatus judged;
      if (!hasSpeech) {
        // Bug corrigé 2026-07-16 (revue de code, Finding #9) : `hasSpeech` ne
        // protégeait QUE la branche `correct` ci-dessous -- un mot jamais
        // prononcé (r.actual=="") avec un gop proche de 0 par coïncidence
        // (forced≈free≈0 sur du blank pur, cf. commentaire plus haut) tombait
        // dans la branche `unclear` juste en dessous (elle ne vérifiait que
        // `r.gop >= _gopUnclear`, sans hasSpeech). Un mot sans aucun son
        // capté n'a de sens NI en "correct" NI en "unclear" (les deux
        // impliquent une tentative) -- toujours `error`, avant même de
        // regarder gop/similarité.
        judged = WordStatus.error;
      } else if (!spellsDifferentWord &&
          (r.gop >= _gopCorrect || (textMatches && r.gop >= _gopUnclear))) {
        judged = WordStatus.correct;
      } else if (r.gop >= _gopUnclear ||
          ArabicNormalizer.similarity(actualNorm, expected.normalized) >=
              _kUnclearSimThreshold) {
        // Bon mot mais rendu imprécis : hésitation acoustique modérée, ou
        // squelette quasi identique avec harakat divergentes.
        judged = WordStatus.unclear;
      } else {
        judged = WordStatus.error;
      }
      // Une erreur ne se verrouille QUE sur un segment figé (décision
      // utilisateur 2026-07-10, conservée) : un aperçu peut encore mal couvrir
      // la fin d'un mot ; le segment figé ultérieur tranche définitivement.
      final lock = p.isFinal || judged != WordStatus.error;
      // `free` (= forced - gop) et `autreMot` sont logués car le gop seul ne
      // permet PAS de diagnostiquer : un gop proche de 0 signifie soit "bien
      // récité", soit "modèle hésitant sur tout" (free très négatif), deux
      // situations opposées. Cf. le cas sin/sad ci-dessus.
      DiagnosticLog.log('GOP', 'mot=${r.index} "${expected.display}" '
          'gop=${r.gop.toStringAsFixed(2)} forced=${r.forced.toStringAsFixed(2)} '
          'free=${(r.forced - r.gop).toStringAsFixed(2)} '
          'entendu="${r.actual}"'
          '${spellsDifferentWord ? " autreMot=OUI" : ""}'
          '${isFragment ? " fragment" : ""}'
          ' -> $judged (lock=$lock, final=${p.isFinal})');
      _judge(words, r.index, judged, lock: lock, newErrors: newErrors);
    }

    // Capture de clip (mini-LoRA personnalisation vocale) : ne retenir ce
    // segment que si TOUS ses mots sont ressortis corrects -- sinon le fichier
    // WAV écrit côté Kotlin reste orphelin (nettoyé par l'appelant à la fin de
    // la session, cf. KaraokeRecitationScreen._maybeSaveProfile).
    if (p.isFinal && p.clipPath != null && p.words.isNotEmpty) {
      final allCorrect = p.words.every((r) =>
          r.index >= 0 &&
          r.index < words.length &&
          words[r.index].status == WordStatus.correct);
      if (allCorrect) {
        final text = p.words.map((r) => words[r.index].display).join(' ');
        _collectedClips.add((path: p.clipPath!, text: text));
      }
    }

    // L'ancre (utilisée par la correction, cf. rewindRangeEnd) doit avancer
    // EXACTEMENT jusqu'où ce bloc a verrouillé des mots — pas jusqu'à
    // `frontier` seul. Sur un segment figé, TOUS les mots de p.words sont
    // jugés/verrouillés ci-dessus (y compris celui à la frontière, non
    // couvert mais quand même jugé puisque isFinal bypasse le garde-fou
    // `!r.covered`) — donc la vraie étendue verrouillée est
    // `p.anchor + p.words.length`, pas `p.frontier` (peut être strictement
    // inférieur d'un mot). Bug corrigé 2026-07-11 : sous-évaluer l'ancre ici
    // désynchronisait Dart de l'ancre native (cf. BufferedTranscriber.kt,
    // runAlignment) — l'appel suivant redemandait à la DP de forcer
    // l'alignement sur un mot déjà verrouillé, absent du nouvel audio,
    // corrompant l'attribution de frames du mot RÉELLEMENT suivant (constat :
    // "مَـٰلِكِ" verrouillé error à tort, gop=-7.36, alors que le décodage
    // libre du même segment le montrait parfaitement reconnu).
    if (p.isFinal) {
      final trueExtent = p.anchor + p.words.length;
      if (trueExtent > _anchorExp) _anchorExp = trueExtent;
    }

    // Pointeur = frontière acoustique (premier mot que l'audio ne couvre pas
    // entièrement) — mais sur un segment figé, tous les mots jusqu'à
    // `_anchorExp` viennent d'être verrouillés (cf. ci-dessus), donc le
    // pointeur doit au moins les dépasser aussi, pas juste `p.frontier`
    // (identique à la correction de l'ancre). Jamais en arrière : une passe
    // ponctuellement dégradée ne fait pas reculer l'UI.
    final coveredExtent = p.isFinal ? _anchorExp : p.frontier;
    final pointer =
        max(state.pointer, coveredExtent.clamp(0, words.length).toInt());

    // Invariant : au plus UN mot "current" à la fois (cf. crash GlobalKey
    // dupliquée, 2026-07-06).
    for (var i = 0; i < words.length; i++) {
      if (i != pointer && words[i].status == WordStatus.current) {
        words[i] = words[i].copyWith(status: WordStatus.pending);
      }
    }
    if (pointer < words.length && words[pointer].status == WordStatus.pending) {
      words[pointer] = words[pointer].copyWith(status: WordStatus.current);
    }

    var correct = 0, unclear = 0, errors = 0;
    for (final w in words) {
      switch (w.status) {
        case WordStatus.correct:
          correct++;
        case WordStatus.unclear:
          unclear++;
        case WordStatus.error:
          errors++;
        default:
          break;
      }
    }

    final done = pointer >= words.length;
    state = state.copyWith(
      words: words,
      pointer: pointer,
      correctCount: correct,
      unclearCount: unclear,
      errorCount: errors,
      status: done ? RecitationStatus.finished : state.status,
    );
    if (done) _finish();
    // Émis APRÈS que `state` reflète le nouveau statut (cohérence écouteurs).
    for (final i in newErrors) {
      _wordFailedCtrl.add(i);
    }
  }

  /// Ré-aligne TOUT le scoring vert/rouge à partir du texte complet reconnu
  /// jusqu'ici, en repartant de zéro à chaque appel (au lieu d'accumuler mot
  /// par mot via [_onToken]). Nécessaire pour le mode streaming "bufferisé" :
  /// chaque re-transcription re-décode tout le buffer audio et peut légèrement
  /// réviser ce qui précède (voir SKILL.md "Streaming CTC : incompatibilité
  /// architecturale") — le texte n'est PAS garanti strictement append-only,
  /// donc une simple accumulation mot-par-mot afficherait des correspondances
  /// fausses dès qu'une révision survient. Recalculer à chaque fois est plus
  /// coûteux mais toujours cohérent avec la meilleure compréhension actuelle.
  void _realignFromFullText(String fullText) {
    if (state.words.isEmpty) return;
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;

    final recNorm = fullText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(ArabicNormalizer.normalize)
        .toList();
    final recStrict = fullText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(ArabicNormalizer.normalizeStrict)
        .toList();

    final words = state.words.map((w) => w.copyWith(status: WordStatus.pending)).toList();

    var expIdx = 0;
    var recIdx = 0;
    var correct = 0;
    var unclear = 0;
    var errors = 0;

    while (expIdx < words.length && recIdx < recNorm.length) {
      var bestRec = -1;
      var bestSim = 0.0;
      final windowEnd = (recIdx + _kAlignLookahead).clamp(0, recNorm.length - 1);
      for (var j = recIdx; j <= windowEnd; j++) {
        final sim = ArabicNormalizer.similarity(recNorm[j], words[expIdx].normalized);
        if (sim > bestSim) {
          bestSim = sim;
          bestRec = j;
        }
      }

      if (bestSim >= _kSimThreshold && bestRec >= 0) {
        // Jugement à 3 niveaux :
        //  - vert   : correspondance stricte (harakat comprises, alef tolérant)
        //  - orange : c'est manifestement le bon mot (squelette quasi-identique)
        //             mais rendu imprécis — harakat différentes ou consonne
        //             floue. Feedback "effort de prononciation", pas une faute.
        //  - rouge  : aligné mais trop éloigné = mot réellement faux.
        final isExact =
            ArabicNormalizer.matchesTolerant(recStrict[bestRec], words[expIdx].strict);
        final WordStatus judged;
        if (isExact) {
          judged = WordStatus.correct;
          correct++;
        } else if (bestSim >= _kUnclearSimThreshold) {
          judged = WordStatus.unclear;
          unclear++;
        } else {
          judged = WordStatus.error;
          errors++;
        }
        words[expIdx] = words[expIdx].copyWith(status: judged);
        recIdx = bestRec + 1;
        expIdx++;
      } else {
        // Pas de correspondance suffisante dans la fenêtre de tolérance :
        // on s'arrête ici, ce mot devient le mot "courant" (pas encore confirmé).
        break;
      }
    }

    // Garde-fou : une re-transcription ponctuelle peut être ponctuellement
    // dégradée (cf. SKILL.md) et faire "reculer" l'alignement recalculé à
    // partir de zéro. On n'affiche jamais un recul — un nouveau calcul qui
    // couvre MOINS de mots que la meilleure position déjà atteinte est ignoré
    // (on garde l'affichage précédent, en attendant une meilleure lecture).
    if (expIdx < state.pointer) return;

    if (expIdx < words.length) {
      words[expIdx] = words[expIdx].copyWith(status: WordStatus.current);
    }

    final done = expIdx >= words.length;
    state = state.copyWith(
      words: words,
      pointer: expIdx,
      correctCount: correct,
      unclearCount: unclear,
      errorCount: errors,
      status: done ? RecitationStatus.finished : state.status,
    );
    if (done) _finish();
  }

  void _onPendingChanged(int pending) {
    state = state.copyWith(pendingSegments: pending);
    // La session est en cours de finalisation (stopContinuous) et la file
    // vient de se vider : tout est transcrit, on peut vraiment terminer.
    if (_endingContinuous && pending == 0) {
      _cleanup();
    }
  }

  /// Traite un mot reconnu — accepte les tokens en état listening ET processing
  /// (le mode batch Whisper émet tous les tokens PENDANT stop()).
  void _onToken(RecognizedToken token) {
    final s = state.status;
    if (s == RecitationStatus.finished || s == RecitationStatus.idle) return;
    if (state.isComplete) return;

    final words = [...state.words];
    final p = state.pointer;
    final recognized = ArabicNormalizer.normalize(token.text);
    final recognizedStrict = ArabicNormalizer.normalizeStrict(token.text);

    // Alignement de position : tolérant (squelette sans harakat), pour savoir
    // à quel mot du verset le token reconnu correspond à peu près.
    int bestIdx = -1;
    double bestSim = 0;
    final end = (p + _kLookahead).clamp(0, words.length - 1);
    for (var i = p; i <= end; i++) {
      final sim = ArabicNormalizer.similarity(recognized, words[i].normalized);
      if (sim > bestSim) {
        bestSim = sim;
        bestIdx = i;
      }
    }

    var correct = state.correctCount;
    var errors = state.errorCount;
    int newPointer;

    if (token.confidence >= 0.5 && bestSim >= _kSimThreshold && bestIdx >= 0) {
      for (var i = p; i < bestIdx; i++) {
        words[i] = words[i].copyWith(status: WordStatus.skipped);
        errors++;
      }
      // Jugement de correction : strict, harakat inclus. Un mot aligné sur la
      // bonne position mais prononcé avec une voyelle courte différente
      // (ex: رَبِّ récité رَبُّ) compte comme une erreur, pas un match.
      final isExact = recognizedStrict == words[bestIdx].strict;
      words[bestIdx] =
          words[bestIdx].copyWith(status: isExact ? WordStatus.correct : WordStatus.error);
      if (isExact) {
        correct++;
      } else {
        errors++;
      }
      newPointer = bestIdx + 1;
    } else {
      words[p] = words[p].copyWith(status: WordStatus.error);
      errors++;
      newPointer = p + 1;
    }

    if (newPointer < words.length) {
      words[newPointer] = words[newPointer].copyWith(status: WordStatus.current);
    }

    final done = newPointer >= words.length;
    state = state.copyWith(
      words: words,
      pointer: newPointer,
      correctCount: correct,
      errorCount: errors,
      // En mode batch (stopping=true) on garde "processing" pour les tokens
      // intermédiaires ; "finished" uniquement quand tous les mots sont traités.
      status: done
          ? RecitationStatus.finished
          : (_stopping ? RecitationStatus.processing : RecitationStatus.listening),
    );
    if (done) _finish();
  }

  /// Appelé quand tous les mots ont été traités (streaming Mock ou batch Whisper).
  void _finish() {
    // En mode batch, _verifier.stop() est déjà en cours → ne pas rappeler
    if (!_stopping) {
      _verifier.stop(); // streaming : stopper le Mock
    }
    _cleanup();
  }

  void _cleanup() {
    _tokenSub?.cancel();
    _levelSub?.cancel();
    _rawSub?.cancel();
    _structSub?.cancel();
    _pendingSub?.cancel();
    _alignSub?.cancel();
    _stopping = false;
    _endingContinuous = false;
    state = state.copyWith(status: RecitationStatus.finished, soundLevel: 0);
  }

  /// Stop manuel (bouton rouge). Change le statut immédiatement en "processing"
  /// → l'UI reste réactive pendant que l'inférence tourne dans compute().
  Future<void> stop() async {
    if (_stopping || !state.isActive) return;
    _stopping = true;

    // Arrêt de l'affichage du niveau micro
    _levelSub?.cancel();
    _levelSub = null;

    // ← L'UI voit "processing" tout de suite ; le bouton change de couleur
    state = state.copyWith(status: RecitationStatus.processing, soundLevel: 0);

    try {
      // WhisperOnnxVerifier.stop() : enregistrement + compute() ASR + emit tokens
      // Les tokens arrivent ici via _onToken pendant l'await
      await _verifier.stop();
    } finally {
      _tokenSub?.cancel();
      _rawSub?.cancel();
      _structSub?.cancel();
      _alignSub?.cancel();
      _stopping = false;
      if (state.status != RecitationStatus.finished) {
        state = state.copyWith(status: RecitationStatus.finished);
      }
    }
  }

  /// Arrêt manuel d'une récitation continue (l'utilisateur peut s'arrêter
  /// avant la fin du fragment). Le statut reste "processing" tant que la file
  /// de segments n'est pas vidée — voir [_onPendingChanged].
  Future<void> stopContinuous() async {
    if (!state.isActive || !state.continuous) return;
    _endingContinuous = true;
    _levelSub?.cancel();
    _levelSub = null;
    state = state.copyWith(status: RecitationStatus.processing, soundLevel: 0);

    await _verifier.stop(); // enfile le dernier segment, retourne vite

    // Si la file était déjà vide au moment du stop (dernier segment invalide
    // ou pas de nouveau segment), _onPendingChanged ne sera pas redéclenché.
    if (state.pendingSegments == 0) _cleanup();
  }

  void reset() {
    _stopping = false;
    _endingContinuous = false;
    final cleared = state.words
        .map((w) => w.copyWith(status: WordStatus.pending))
        .toList();
    state = RecitationSessionState(words: cleared);
  }

  /// Boucle de correction interactive (demande utilisateur 2026-07-05) : marque
  /// le mot [index] comme corrigé après un ré-essai validé (l'appelant a déjà
  /// vérifié la prononciation via une transcription séparée, cf.
  /// `WordCorrectionSheet`). Verrouillé comme n'importe quel jugement définitif
  /// — mais celui-ci vient d'une vérification EXPLICITE demandée par
  /// l'utilisateur, pas d'une passe automatique, donc jamais suspect
  /// d'incomplétude : verrouillage immédiat justifié.
  void markWordCorrected(int index) {
    if (index < 0 || index >= state.words.length) return;
    final words = [...state.words];
    final wasError = words[index].status == WordStatus.error;
    final wasUnclear = words[index].status == WordStatus.unclear;
    words[index] = words[index].copyWith(status: WordStatus.correct, locked: true);
    // Mot validé par correction explicite : l'ancre d'alignement (native et
    // locale) doit repartir APRÈS lui, pour que la suite de la récitation soit
    // comparée au mot suivant.
    if (_anchorExp < index + 1) _anchorExp = index + 1;
    unawaited(_verifier.setAlignmentAnchor(index + 1));
    state = state.copyWith(
      words: words,
      correctCount: state.correctCount + 1,
      errorCount: wasError ? state.errorCount - 1 : state.errorCount,
      unclearCount: wasUnclear ? state.unclearCount - 1 : state.unclearCount,
    );
  }

  /// Recul + déverrouillage d'un mot fautif (demande utilisateur 2026-07-06,
  /// répétée et précisée à plusieurs reprises) : après avoir entendu la
  /// correction (mot précédent + mot fautif), le réciteur doit pouvoir
  /// REFAIRE ce mot précis avec un NOUVEL audio -- contrairement au
  /// verrouillage normal (qui protège contre le biais du modèle sur le MÊME
  /// audio réévalué avec plus de contexte, cf. commentaire de _judge), ici
  /// c'est une tentative différente, donc le mot doit pouvoir redevenir vert
  /// si elle est correcte. On déverrouille le mot ET on ramène l'ancre
  /// d'alignement dessus, pour que la prochaine transcription soit comparée
  /// à CE mot plutôt qu'au suivant.
  /// Fin (exclusive) de la plage qui sera déverrouillée par
  /// [rewindAndUnlock] si on l'appelle MAINTENANT sur [wordIndex] — à lire
  /// AVANT d'appeler rewindAndUnlock (qui modifie l'ancre), pour savoir
  /// jusqu'où étendre l'audio de correction (demande utilisateur 2026-07-06 :
  /// pour un saut de plusieurs mots, le réciteur doit dire TOUS les vrais
  /// mots sautés, pas juste le premier).
  int rewindRangeEnd() => _anchorExp;

  /// Recul + déverrouillage d'une plage fautive (demande utilisateur
  /// 2026-07-06, précisée à plusieurs reprises) : après avoir entendu la
  /// correction, le réciteur doit pouvoir REFAIRE cette plage avec un NOUVEL
  /// audio -- contrairement au verrouillage normal (qui protège contre le
  /// biais du modèle sur le MÊME audio réévalué avec plus de contexte, cf.
  /// commentaire de _judge), ici c'est une tentative différente, donc les
  /// mots doivent pouvoir redevenir verts si elle est correcte. Déverrouille
  /// TOUT depuis [wordIndex] jusqu'à l'ancre actuelle (pas seulement
  /// [wordIndex] seul) : un saut de plusieurs mots verrouille plusieurs mots
  /// d'un coup (les sautés + celui qui a causé le saut) et un seul événement
  /// de correction est émis pour toute la plage — reculer sur un seul mot
  /// laisserait les autres verrouillés "sauté" pour toujours.
  void rewindAndUnlock(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= state.words.length) return;
    final words = [...state.words];
    final end = _anchorExp.clamp(wordIndex + 1, words.length);
    var errorDelta = 0, unclearDelta = 0;
    for (var i = wordIndex; i < end; i++) {
      if (words[i].status == WordStatus.error) errorDelta++;
      if (words[i].status == WordStatus.unclear) unclearDelta++;
      words[i] = words[i].copyWith(status: WordStatus.pending, locked: false);
    }
    _anchorExp = wordIndex;
    // Le buffer natif est vidé séparément (verifier.resetBuffer(), appelé par
    // l'écran avant resumeCapture()) -- on oublie ici le texte figé déjà vu,
    // pour que le prochain texte figé reçu (la nouvelle tentative) soit
    // traité comme entièrement nouveau, pas comme une suite du texte d'avant
    // le recul.
    _prevCommitted = '';
    // Ancre de l'alignement forcé GOP : la prochaine passe doit comparer le
    // nouvel audio à CE mot, pas à la suite du texte.
    unawaited(_verifier.setAlignmentAnchor(wordIndex));
    state = state.copyWith(
      words: words,
      errorCount: state.errorCount - errorDelta,
      unclearCount: state.unclearCount - unclearDelta,
    );
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    _levelSub?.cancel();
    _rawSub?.cancel();
    _structSub?.cancel();
    _pendingSub?.cancel();
    _alignSub?.cancel();
    _wordFailedCtrl.close();

    // Bug corrigé 2026-07-16 — FUITE DE SESSION. Ce dispose n'annulait que les
    // abonnements Dart : le MICRO continuait d'enregistrer et le
    // BufferedTranscriber natif (un SINGLETON, côté Kotlin) continuait
    // d'empiler de l'audio après la sortie de l'écran. Ce provider est
    // autoDispose, mais `recitationVerifierProvider` NE L'EST PAS -- le
    // verifier (et son enregistreur) survit donc à l'écran qui l'a lancé.
    //
    // Constaté sur device (log 17h17-17h21, sourate Al-Baqara) : la session
    // précédente en était à `bloc PCM #1800` quand la nouvelle démarrait --
    // deux flux micro concurrents alimentant le MÊME buffer natif. D'où :
    //   - un `wordFailed` sur "الٓمٓ" 100 ms après l'ouverture, AVANT même le
    //     premier bloc PCM de la nouvelle session (impossible d'avoir récité) ;
    //   - des transcriptions de bruit ambiant ("تَسُجْززْ", "يَ") jugées comme
    //     de vrais mots -> mots marqués rouges, correction automatique
    //     déclenchée toute seule, audio du récitateur joué sans raison ;
    //   - remarque utilisateur : "quand je veux tester Baqara il ne part pas du
    //     début, il retient ce que j'ai fait il y a longtemps".
    //
    // `stop()` annule _pcmSub ET arrête l'enregistreur ; `resetBuffer()` purge
    // l'état natif (samples, texte figé, aperçu) pour que la session suivante
    // reparte réellement de zéro. Fire-and-forget : dispose() est synchrone et
    // ne doit jamais bloquer la fermeture de l'écran.
    //
    // Bug corrigé 2026-07-16 (revue de code, Finding #1) : ce nettoyage
    // appelait stop()+resetBuffer() SANS AUCUNE garde contre une nouvelle
    // session démarrée entre-temps (recitationVerifierProvider n'est PAS
    // autoDispose -- une réouverture rapide de l'écran karaoké réutilise le
    // MÊME verifier). Le stop() de cette ancienne session pouvait s'exécuter
    // APRÈS que la nouvelle ait déjà appelé _recorder.startStream(), tuant
    // silencieusement le nouvel enregistrement. `stopIfCurrentSession`
    // (verrou sérialisé + vérification de génération côté verifier) ne fait
    // plus rien si une session plus récente a déjà pris le relais.
    if (_myGeneration >= 0) {
      unawaited(_verifier.stopIfCurrentSession(_myGeneration).catchError(
          (e) => DiagnosticLog.log('ASR', 'arrêt de session au dispose échoué : $e')));
    }

    super.dispose();
  }
}
