import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'diagnostic_log.dart';
import 'fastconformer_verifier.dart';

// ── Public types ─────────────────────────────────────────────────────────────

class RecognizedToken {
  final String text;
  final double confidence;
  const RecognizedToken(this.text, {this.confidence = 1.0});
}

/// Normalisation arabe tolérante aux harakat / variantes orthographiques.
class ArabicNormalizer {
  static final _harakat = RegExp(r'[ً-ٰٟؐ-ؚۖ-ۭـ]');

  static String _collapseVariants(String t) {
    // Variantes orthographiques du script Uthmani — MÊMES mappings que la
    // normalisation du corpus d'entraînement (prepare_nemo_data.normalize_text,
    // 2026-07-05) : le modèle écrit "الرَّحْمَانِ" (alif normal) là où le texte
    // de l'app contient "ٱلرَّحْمَـٰنِ" (wasla + dagger alif + tatweel). Sans ces
    // mappings côté comparaison, le MÊME mot bien récité ressort orange/rouge.
    t = t
        .replaceAll('ٱ', 'ا')  // alif wasla -> alif
        // Rasm ancien à "waw muet" (وٰ) porteur du petit alif suscrit —
        // audit du Coran entier 2026-07-10 (184 occurrences, 30 formes :
        // الصلاة، الحياة، الزكاة، الربا، الغداة، النجاة، مشكاة، مناة...).
        // Le waw ne se prononce pas (seul le petit alif porte le son "aa"),
        // mais rester "و" + alif normal (via la règle suivante seule)
        // laisse une lettre en trop face à toute transcription standard
        // ("صلواه" au lieu de "صلاه") -- écart mesuré de 0.80 à 0.875 de
        // similarité squelette, jamais "correct", parfois carrément rouge,
        // même prononcé parfaitement. Il faut retirer le waw ET le petit
        // alif ensemble (pas juste convertir ce dernier), d'où cette règle
        // AVANT la conversion générique du dagger alif ci-dessous.
        .replaceAll('وٰ', 'ا')
        .replaceAll('ٰ', 'ا')  // dagger alif (voyelle longue suscrite) -> alif
        .replaceAll('ۥ', 'و')  // petit waw -> waw
        .replaceAll('ۦ', 'ي')  // petit yeh -> yeh
        .replaceAll('ٔ', 'ء')  // hamza suscrite combinante -> hamza
        .replaceAll('ٓ', '')   // maddah combinante (portée par la lettre de base)
        .replaceAll('ـ', '')   // tatweel (allongement purement visuel)
        .replaceAll('۞', '')   // marque de rub el hizb
        .replaceAll('۩', '')   // marque de sajda
        // Marques d'annotation de lecture (waqf/sukun/imala/iqlab) — vérifiées
        // ABSENTES du vocabulaire du modèle une par une (0/1024 tokens,
        // 2026-07-09, cf. benchmark scratchpad check_vocab_gap.py sur un
        // échantillon de 1546 versets) : le modèle ne peut STRUCTURELLEMENT
        // jamais les produire, quelle que soit la prononciation. Sans ce
        // strip, tout mot portant l'une de ces marques reste bloqué en
        // "unclear" indéfiniment en mode strict (bug réel constaté sur
        // "لَيُنۢبَذَنَّ", sourate Al-Humazah -- ۢ était le seul déjà traité).
        .replaceAll('ۢ', '')   // petit meem suscrit (iqlab)
        .replaceAll('ۖ', '')   // waqf "صلى" (petite ligature sad-lam-alef maksura)
        .replaceAll('ۗ', '')   // waqf "قلى" (petite ligature qaf-lam-alef maksura)
        .replaceAll('ۘ', '')   // waqf "م" (arrêt obligatoire)
        .replaceAll('ۙ', '')   // waqf "لا" (pas d'arrêt)
        .replaceAll('ۚ', '')   // waqf "ج" (arrêt permis)
        .replaceAll('ۛ', '')   // waqf (l'un des deux/trois points d'arrêt optionnels)
        .replaceAll('ۜ', '')   // waqf "س"/saktah (pause brève sans reprendre son souffle)
        .replaceAll('۟', '')   // sukun (variante rond)
        .replaceAll('۠', '')   // sukun (variante rectangulaire)
        .replaceAll('ۧ', '')   // imalah (indication de nuance vocalique)
        .replaceAll('ۭ', '');  // petit meem souscrit (ikhfa/iqlab, variante basse)
    t = t
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');
    t = t.replaceAll(RegExp(r'[^؀-ۿ\s]'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalisation "squelette" (sans harakat) — tolérante au bruit ASR,
  /// utilisée uniquement pour ALIGNER le mot reconnu sur sa position dans
  /// le verset (pas pour juger si la prononciation est correcte).
  /// _collapseVariants d'ABORD : le dagger alif (ٰ) doit devenir un alif
  /// AVANT le retrait des harakat, sinon il est supprimé comme diacritique et
  /// "رحمٰن" (attendu) ne matche plus "رحمان" (sortie modèle).
  static String normalize(String input) {
    return _collapseVariants(input).replaceAll(_harakat, '');
  }

  /// Normalisation stricte (garde les harakat) — utilisée pour juger si le
  /// mot reconnu est réellement correct. Une voyelle courte différente
  /// (ex: رَبِّ vs رَبُّ) doit compter comme une erreur, pas un match.
  static String normalizeStrict(String input) {
    return _collapseVariants(input);
  }

  /// Normalisation "fidèle à l'entraînement" — EXACTEMENT la même
  /// transformation que `normalize_text()` dans benchmark/prepare_nemo_data.py
  /// (source de vérité du corpus d'entraînement). Contrairement à
  /// [normalizeStrict], NE fusionne PAS أ/إ/آ→ا, ى→ي, ؤ→و, ئ→ي, ة→ه — ces
  /// lettres sont des tokens BPE DISTINCTS que le modèle a appris à produire
  /// séparément (vérifié empiriquement 2026-07-11 : `_collapseVariants`
  /// convient à la comparaison textuelle tolérante mais PAS comme cible
  /// d'alignement forcé — un mot contenant l'une de ces lettres, très
  /// fréquent dans le Coran (ex. ة dans صَلَاة/حَيَاة/رَحْمَة), envoyait au
  /// tokenizer une forme que le modèle n'a jamais vue à l'entraînement).
  /// SEULE forme à utiliser pour construire la cible envoyée à
  /// setAlignmentTarget/tokenizeWord — jamais pour la comparaison tolérante
  /// (qui reste sur normalize/normalizeStrict, la fusion y est un atout).
  static String normalizeTraining(String input) {
    var t = input;
    t = t.replaceAll('ٱ', 'ا');
    t = t.replaceAll('وٰ', 'ا');
    t = t.replaceAll('ٰ', 'ا');
    t = t.replaceAll('ۥ', 'و');
    t = t.replaceAll('ۦ', 'ي');
    t = t.replaceAll('ٔ', 'ء');
    t = t.replaceAll('ٓ', '');
    t = t.replaceAll('ـ', '');
    t = t.replaceAll('۞', '');
    t = t.replaceAll('۩', '');
    t = t.replaceAll(RegExp(r'[ؖ-ؚۖ-ۜ۟-۪ۤۧۨ-ۭ]'), '');
    t = t.replaceAll(RegExp(r'[،؛؟.,!?:;\-_()\[\]{}"' r"'" r'»«]'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Découpe le texte coranique attendu (`text_uthmani`) en mots récitables,
  /// en filtrant les signes d'annotation isolés par des espaces (marques de
  /// waqf comme ۚ ۖ ۗ...) qui ne sont PAS de vrais mots à prononcer. Bug réel
  /// constaté 2026-07-06 (sourate 110, verset 3) : un tel signe, séparé par
  /// un espace dans `text_uthmani` mais COLLÉ au mot précédent dans
  /// `text_uthmani_tajweed`, désynchronisait le nombre de mots entre les
  /// deux représentations (décalant tout l'affichage tajwid à partir de ce
  /// point, jusqu'à faire apparaître le dernier mot en double) ET créait un
  /// "mot" fantôme dans la liste à réciter : `normalize("ۚ")` est vide (ce
  /// n'est que harakat/marques), donc `similarity()` renvoyait TOUJOURS 0
  /// contre n'importe quel mot reconnu -> échec automatique dès que la
  /// récitation atteignait ce point. À utiliser PARTOUT où `text_uthmani`
  /// est découpé en mots (jamais un `.split` direct), pour que la liste de
  /// mots à réciter reste alignée avec `tajweedSpansPerWord` (qui, lui,
  /// fusionne déjà naturellement ces marques au mot précédent).
  static List<String> splitExpectedWords(String text) => text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && normalize(w).isNotEmpty)
      .toList();

  static double similarity(String a, String b) {
    a = normalize(a);
    b = normalize(b);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final d = _levenshtein(a, b);
    return 1 - d / max(a.length, b.length);
  }

  /// Compare deux mots normalisés (strict) en tolérant un alef initial manquant
  /// côté reconnu. Rustine TEMPORAIRE : le checkpoint FastConformer actuellement
  /// déployé a été entraîné avant la correction du vocabulaire BPE (alef wasla
  /// "ٱ" absent des 1024 tokens, cf. SKILL.md 2026-07-05) — il transcrit "<unk>"
  /// à la place de l'alef de "ال", que `_collapseVariants` efface entièrement
  /// (hors bloc Unicode arabe), faisant "manquer" une lettre côté reconnu même
  /// quand la prononciation était correcte. À retirer une fois le modèle
  /// ré-entraîné avec le texte normalisé déployé sur le téléphone.
  static bool matchesTolerant(String recognizedStrict, String expectedStrict) {
    if (recognizedStrict == expectedStrict) return true;
    const alefLike = ['ا', 'ٱ', 'أ', 'إ', 'آ'];
    if (alefLike.contains(expectedStrict.isEmpty ? '' : expectedStrict[0]) &&
        expectedStrict.substring(1) == recognizedStrict) {
      return true;
    }
    // Waqf (pause) : la voyelle courte finale tombe naturellement quand le
    // récitant marque un arrêt (fin de verset ou simple respiration) --
    // constat réel 2026-07-10 (sourate 106, "وَالصَّيْفِ" récité en fin de verset
    // ressort "وَالصَّيْف" : squelette identique, seule la harakat finale est
    // absente). Le texte de référence porte toujours la forme "connectée"
    // (wasl) ; une lecture en pause qui abandonne SEULEMENT sa toute
    // dernière harakat doit compter comme correcte, pas "unclear".
    if (expectedStrict.isNotEmpty &&
        _harakat.hasMatch(expectedStrict[expectedStrict.length - 1]) &&
        expectedStrict.substring(0, expectedStrict.length - 1) ==
            recognizedStrict) {
      return true;
    }
    return false;
  }

  static int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    final dp = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      var prev = dp[0];
      dp[0] = i;
      for (var j = 1; j <= n; j++) {
        final tmp = dp[j];
        dp[j] = min(
          min(dp[j] + 1, dp[j - 1] + 1),
          prev + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
        prev = tmp;
      }
    }
    return dp[n];
  }
}

// ── Interface ────────────────────────────────────────────────────────────────

abstract class RecitationVerifier {
  Stream<RecognizedToken> get tokens;
  Stream<double> get soundLevel;

  /// Texte brut transcrit par le modèle (avant découpage en mots) — debug/visualisation.
  Stream<String> get rawTranscript;

  /// Transcript structuré du mode continu : `committed` = segments figés
  /// (append-only, plus jamais révisés par une re-transcription), `preview` =
  /// segment courant (encore révisable). Le scoring s'ANCRE sur committed —
  /// re-partir du mot 0 à chaque mise à jour calait dès qu'une re-transcription
  /// perdait le début du texte (curseur bloqué, test réel 2026-07-05).
  Stream<({String committed, String preview})> get structuredTranscript;

  /// Nombre de segments audio en attente/en cours de transcription (mode continu).
  Stream<int> get pendingSegments;

  /// Chemin d'un WAV stable (survit à la transcription, contrairement aux
  /// segments temporaires normalement supprimés aussitôt) contenant le DERNIER
  /// enregistrement transcrit — utilisé pour l'empreinte vocale (comparaison
  /// audio-à-audio, voir voice_fingerprint_service.dart). Null tant qu'aucune
  /// transcription n'a eu lieu dans la session courante.
  String? get lastAudioPath;

  /// Passes d'alignement forcé GOP (cf. ForcedAligner.kt, refonte 2026-07-11) :
  /// le texte attendu est connu d'avance, chaque passe d'inférence aligne de
  /// force les mots restants sur les log-probs du modèle et émet un score par
  /// mot (gop = forced − free). C'est la source de jugement PRIMAIRE du scoring
  /// quand [alignmentActive] est vrai — le diff textuel flou historique ne sert
  /// plus que de repli.
  Stream<AlignPayload> get alignedWords;

  /// Vrai si l'alignement forcé est actif pour la session courante (cible
  /// déclarée + modèle chargé). Faux → le scoring doit retomber sur le diff
  /// textuel historique.
  bool get alignmentActive;

  /// Repositionne l'ancre d'alignement natif (correction/recul) — la prochaine
  /// passe compare l'audio au mot [index], pas à la suite du texte.
  Future<void> setAlignmentAnchor(int index);

  /// Étend la cible d'alignement forcé avec des mots supplémentaires (formes
  /// STRICTES d'entraînement), à la SUITE de la cible actuelle — SANS toucher
  /// l'ancre en cours. Utilisé pour enchaîner sur la sourate suivante sans
  /// interrompre la session (demande utilisateur 2026-07-11) : la récitation
  /// continue exactement où elle en était, juste avec plus de texte derrière.
  Future<void> extendAlignmentTarget(List<String> moreTrainingWords);

  /// Active/désactive la capture de clips VÉRIFIÉS CORRECTS pour le futur
  /// mini-LoRA de personnalisation vocale (FONCTIONNALITES_FUTURES.md,
  /// "Personnalisation voix -- niveau 3", implémenté 2026-07-12). [dir] =
  /// null désactive. N'écrit rien tant que non activé -- zéro coût hors
  /// session de référence.
  Future<void> setClipCapture(String? dir);

  /// [continuous] : enregistrement continu segmenté par détection de silence
  /// (VAD énergie), pour réciter plusieurs versets/une sourate entière sans
  /// interaction manuelle entre chaque verset.
  Future<void> start(List<String> expectedWords, {bool continuous = false});
  Future<void> stop();

  /// Suspend/reprend la capture micro SANS arrêter la session (mots/score
  /// conservés) — utilisé par la correction automatique (demande utilisateur
  /// 2026-07-05) : on coupe l'écoute le temps de jouer la prononciation
  /// correcte, puis on reprend exactement où on en était.
  Future<void> pauseCapture();
  Future<void> resumeCapture();

  /// Vide le buffer de ré-transcription (texte figé + aperçu) SANS arrêter la
  /// session — à appeler entre pauseCapture()/resumeCapture() lors d'une
  /// correction automatique (demande utilisateur 2026-07-06) : sans ça, de
  /// l'audio déjà dans le buffer avant la pause (pas encore figé) peut
  /// ressurgir après la reprise et contaminer la nouvelle tentative — le mot
  /// semble "déjà rejugé" avant même que le réciteur ait fini de répéter.
  Future<void> resetBuffer();

  void dispose();
}

// ── ASR on-device ────────────────────────────────────────────────────────────
// FastConformer CTC (notre modèle, cf. benchmark/models/fastconformer-quran-pcd)
// est le SEUL moteur utilisé ici — pas whisper.cpp. Concept cible "karaoké" à un
// seul modèle qui vérifie le texte connu en continu (pas une transcription libre
// qu'on diff après coup). whisper.cpp reste disponible ailleurs dans le projet
// (modèle de production actuel, ~11% WER) mais n'est pas utilisé par CETTE classe
// pendant que le training du modèle maison est en cours.

const String _kAsrVersion = 'ASR-v45-gop-forced-align';

class WhisperOnnxVerifier implements RecitationVerifier {
  final _tokenCtrl = StreamController<RecognizedToken>.broadcast();
  final _levelCtrl = StreamController<double>.broadcast();
  final _rawCtrl = StreamController<String>.broadcast();
  final _structCtrl =
      StreamController<({String committed, String preview})>.broadcast();
  final _alignCtrl = StreamController<AlignPayload>.broadcast();
  final _recorder = AudioRecorder();
  Timer? _levelTimer;

  final _fastConformer = FastConformerVerifier();

  String? _lastAudioPath;

  bool _alignmentActive = false;
  int _lastAlignSeq = -1;

  @override
  Stream<RecognizedToken> get tokens => _tokenCtrl.stream;
  @override
  Stream<double> get soundLevel => _levelCtrl.stream;
  @override
  Stream<String> get rawTranscript => _rawCtrl.stream;
  @override
  Stream<({String committed, String preview})> get structuredTranscript =>
      _structCtrl.stream;
  @override
  Stream<AlignPayload> get alignedWords => _alignCtrl.stream;
  @override
  bool get alignmentActive => _alignmentActive;
  @override
  String? get lastAudioPath => _lastAudioPath;

  @override
  Future<void> setAlignmentAnchor(int index) =>
      _fastConformer.setAlignmentAnchor(index);

  @override
  Future<void> extendAlignmentTarget(List<String> moreTrainingWords) =>
      _fastConformer.extendAlignmentTarget(moreTrainingWords);

  @override
  Future<void> setClipCapture(String? dir) => _fastConformer.setClipCapture(dir);

  // ── Segmentation continue (VAD énergie) ──────────────────────────────────
  // dBFS en dessous duquel on considère qu'il y a silence (seuil à ajuster
  // selon la sensibilité du micro — point de réglage principal).
  static const double _kSilenceDbfs = -45.0;
  static const int _kSilenceCutMs = 700;   // silence soutenu -> on coupe
  static const int _kMinSegmentMs = 1200;  // segment mini avant d'autoriser une coupure
  static const int _kMaxSegmentMs = 25000; // coupure forcée (contexte encodeur ~30s)

  bool _continuous = false;
  bool _sessionEnding = false;
  String? _currentSegmentPath;
  DateTime? _segmentStart;
  DateTime? _silenceStart;

  final List<String> _queue = [];
  final _pendingCtrl = StreamController<int>.broadcast();
  bool _draining = false;

  @override
  Stream<int> get pendingSegments => _pendingCtrl.stream;

  StreamSubscription<Uint8List>? _pcmSub;

  @override
  Future<void> start(List<String> expectedWords, {bool continuous = false}) async {
    final hasPerm = await _recorder.hasPermission();
    debugPrint(
        '[ASR] [$_kAsrVersion] start() | perm=$hasPerm | mots=${expectedWords.length} | continu=$continuous');
    if (!hasPerm) return;

    _continuous = continuous;
    _sessionEnding = false;
    _alignmentActive = false;
    _lastAlignSeq = -1;

    if (continuous) {
      await _startStreamingCapture(expectedWords);
      return;
    }

    _rawCtrl.add('⏳ Chargement FastConformer CTC…');
    unawaited(_fastConformer.ensureLoaded().then((ok) async {
      if (ok) {
        // [expectedWords] = formes STRICTES (normalizeStrict : harakat
        // conservées, même normalisation que le corpus d'entraînement) — la
        // cible de l'alignement forcé GOP. false → repli diff textuel.
        _alignmentActive =
            await _fastConformer.setAlignmentTarget(expectedWords, 0);
        DiagnosticLog.log('ASR', 'alignement forcé actif = $_alignmentActive');
      }
      _rawCtrl.add(ok
          ? '✅ FastConformer chargé — en écoute'
          : '❌ FastConformer introuvable (modèle/vocab absents sur le device)');
    }));
    await _beginSegment();

    _levelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      try {
        final amp = await _recorder.getAmplitude();
        _levelCtrl.add(((amp.current + 60) / 60).clamp(0.0, 1.0));
      } catch (_) {}
    });
  }

  int _chunkCount = 0;

  /// Flux continu (karaoké) : capture PCM16 brute en direct (pas de
  /// fichiers/segments VAD). Le VRAI streaming cache-aware a été abandonné —
  /// voir SKILL.md "Streaming CTC : incompatibilité architecturale" — notre
  /// checkpoint est entraîné avec des convolutions non-causales, incompatibles
  /// avec l'inférence par cache en flux (même l'API officielle NeMo
  /// conformer_stream_step plante dessus, pas juste notre export ONNX).
  /// Solution qui marche : re-transcription du buffer complet toutes les
  /// ~1,5s via BufferedTranscriber.kt (modèle offline déjà validé) — latence
  /// perçue ~1,5-3s, mais continu, sans coupure manuelle.
  Future<void> _startStreamingCapture(List<String> expectedWords) async {
    _chunkCount = 0;
    _rawCtrl.add('⏳ Chargement FastConformer…');
    final ok = await _fastConformer.ensureLoaded();
    _rawCtrl.add(ok
        ? '✅ Chargé — en écoute (re-transcription ~1,5s)'
        : '❌ Modèle introuvable (modèle/vocab absents sur le device)');
    if (!ok) return;
    // Cible de l'alignement forcé GOP (formes strictes, harakat conservées).
    _alignmentActive = await _fastConformer.setAlignmentTarget(expectedWords, 0);
    DiagnosticLog.log('ASR', 'alignement forcé actif = $_alignmentActive');
    await _fastConformer.resetBuffered();

    DiagnosticLog.log('ASR', 'Appel _recorder.startStream()…');
    try {
      final hasPerm = await _recorder.hasPermission();
      DiagnosticLog.log('ASR', 'hasPermission (juste avant startStream) = $hasPerm');

      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      DiagnosticLog.log('ASR', 'startStream() a retourné un Stream — abonnement…');

      _pcmSub = stream.listen(
        (bytes) async {
          _chunkCount++;
          if (_chunkCount == 1) {
            DiagnosticLog.log('ASR', 'PREMIER bloc PCM reçu ! ${bytes.length} octets');
          } else if (_chunkCount % 20 == 0) {
            DiagnosticLog.log('ASR', 'bloc PCM #$_chunkCount (${bytes.length} octets)');
          }
          _levelCtrl.add(_estimatePcmLevel(bytes));
          try {
            final parts = await _fastConformer.feedBufferedAudio(bytes);
            if (parts != null &&
                (parts.committed.isNotEmpty || parts.preview.isNotEmpty)) {
              final display = [parts.committed, parts.preview]
                  .where((s) => s.isNotEmpty)
                  .join(' ');
              if (_chunkCount % 20 == 0) {
                debugPrint('[FastConformer] #$_chunkCount fige="${parts.committed}" '
                    'apercu="${parts.preview}"');
              }
              _rawCtrl.add(display); // affichage brut (debug/caption)
              // Scoring ancré : la partie figée est append-only, seule
              // l'aperçu est ré-aligné à chaque passe (voir recitation_provider).
              _structCtrl.add(
                  (committed: parts.committed, preview: parts.preview));
            }
            // Passe d'alignement forcé GOP : dédupliquée par `seq` (le natif
            // renvoie le DERNIER résultat connu à chaque bloc PCM, mais une
            // passe d'inférence n'a lieu que toutes les ~1,5s).
            final align = parts?.align;
            if (align != null && align.seq != _lastAlignSeq) {
              _lastAlignSeq = align.seq;
              _alignCtrl.add(align);
            }
          } catch (e) {
            debugPrint('[FastConformer] Erreur feedBufferedAudio : $e');
          }
        },
        onError: (e) => DiagnosticLog.log('ASR', 'Erreur sur le flux PCM : $e'),
        onDone: () => DiagnosticLog.log('ASR', 'Flux PCM terminé (onDone) — $_chunkCount blocs reçus au total'),
      );
    } catch (e, st) {
      DiagnosticLog.log('ASR', 'EXCEPTION dans _startStreamingCapture : $e\n$st');
      _rawCtrl.add('❌ Erreur démarrage capture audio : $e');
    }
  }

  /// Niveau approx (RMS -> pseudo-dBFS -> [0,1]) pour l'animation du halo,
  /// calculé directement sur le PCM reçu (pas d'API getAmplitude() en mode
  /// startStream — les deux mécanismes du package `record` sont distincts).
  double _estimatePcmLevel(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final data = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    double sumSq = 0;
    for (var i = 0; i < n; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSq += s * s;
    }
    final rms = sqrt(sumSq / n);
    if (rms <= 0) return 0;
    final db = 20 * (log(rms) / ln10);
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }

  Future<void> _beginSegment() async {
    final tmp = await getTemporaryDirectory();
    _currentSegmentPath = '${tmp.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: _currentSegmentPath!,
    );
    _segmentStart = DateTime.now();
    _silenceStart = null;
  }

  /// Coupe le segment en cours (silence détecté ou durée max) et enchaîne
  /// immédiatement un nouvel enregistrement pour ne pas perdre la suite.
  Future<void> _cutAndRestart() async {
    final path = await _recorder.stop();
    DiagnosticLog.log('ASR', 'Segment coupé (silence/durée max) → $path');
    _enqueueIfValid(path);
    if (!_sessionEnding) await _beginSegment();
  }

  void _enqueueIfValid(String? path) {
    if (path == null) return;
    final size = File(path).existsSync() ? File(path).lengthSync() : 0;
    if (size == 0) return;
    _queue.add(path);
    _pendingCtrl.add(_queue.length);
    if (!_draining) _drainQueue();
  }

  /// Traite la file un segment à la fois, en tâche de fond — n'empêche pas
  /// l'utilisateur de continuer à réciter pendant la transcription.
  Future<void> _drainQueue() async {
    _draining = true;
    while (_queue.isNotEmpty) {
      final path = _queue.removeAt(0);
      await _transcribeAndEmit(path);
      _pendingCtrl.add(_queue.length);
    }
    _draining = false;
  }

  /// POC FastConformer CTC : SEUL modèle utilisé ici (whisper.cpp désactivé —
  /// voir échange utilisateur du 2026-07-04, concept "karaoké" à un seul
  /// modèle qui vérifie le texte connu en continu). Le scoring vert/rouge est
  /// géré par RecitationNotifier._realignFromFullText à partir du texte brut
  /// émis ici (pas d'émission de tokens individuels — voir même remarque dans
  /// le chemin streaming plus haut).
  Future<void> _transcribeAndEmit(String path) async {
    final loaded = await _fastConformer.ensureLoaded();
    if (!loaded) {
      debugPrint('[FastConformer] Modèle introuvable — segment ignoré');
      _rawCtrl.add('❌ Segment ignoré — modèle FastConformer non chargé');
      _deleteQuiet(path);
      return;
    }

    debugPrint('[FastConformer] → transcribe $path');
    final sw = Stopwatch()..start();
    try {
      final text = await _fastConformer.transcribe(path);
      debugPrint('[FastConformer] (${sw.elapsedMilliseconds} ms) : "$text"');
      if (text == null || text.isEmpty) {
        _rawCtrl.add('⚠️ (${sw.elapsedMilliseconds}ms) segment transcrit vide');
        return;
      }
      _rawCtrl.add(text);
      // Alignement forcé GOP one-shot sur ce même WAV (mode coach, segment
      // unique) : source de jugement primaire quand actif — le provider
      // ignore alors le diff textuel sur `text` ci-dessus.
      if (_alignmentActive) {
        final payload = await _fastConformer.alignFile(path);
        if (payload != null) _alignCtrl.add(payload);
      }
      await _saveStableCopy(path);
    } catch (e) {
      debugPrint('[FastConformer] Erreur decode segment : $e');
      _rawCtrl.add('❌ Erreur inférence CTC : $e');
    } finally {
      _deleteQuiet(path);
    }
  }

  /// Copie le segment vers un emplacement STABLE (survit à `_deleteQuiet(path)`
  /// juste après) — permet à l'UI d'utiliser l'audio de cette tentative une
  /// fois `finished`, ex. pour l'empreinte vocale (voir `lastAudioPath`).
  Future<void> _saveStableCopy(String path) async {
    try {
      final tmp = await getTemporaryDirectory();
      final stablePath = '${tmp.path}/last_recitation.wav';
      await File(path).copy(stablePath);
      _lastAudioPath = stablePath;
    } catch (e) {
      DiagnosticLog.log('ASR', 'Échec copie stable pour empreinte vocale : $e');
    }
  }

  void _deleteQuiet(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _levelTimer?.cancel();
    _levelCtrl.add(0);
    _sessionEnding = true;

    if (_continuous) {
      await _pcmSub?.cancel();
      _pcmSub = null;
      await _recorder.stop();
      return;
    }

    // Coupe et met en file le dernier segment, PUIS attend que la file soit
    // vidée avant de retourner. Bug corrige le 2026-07-04 : sans ce await,
    // RecitationNotifier.stop() annule _rawSub/_tokenSub des que _verifier.stop()
    // retourne — hors _drainQueue() tourne en fire-and-forget (_enqueueIfValid
    // ne l'attend pas), donc la transcription qui arrive APRES coup (souvent
    // plusieurs centaines de ms plus tard) etait silencieusement perdue :
    // confirme sur device reel (logcat montrait la bonne transcription CTC,
    // "بِسْمِ اللَّهِ الرَّحْمَـٰنِ الرَّحِيمِ", mais l'ecran restait bloque sur
    // le message de chargement car plus personne n'ecoutait le stream).
    final path = await _recorder.stop();
    DiagnosticLog.log('ASR', '[$_kAsrVersion] stop() | dernier segment=$path');
    _enqueueIfValid(path);
    if (_draining) {
      await _pendingCtrl.stream.firstWhere((n) => n == 0);
    }
  }

  @override
  Future<void> pauseCapture() async {
    try {
      final wasRecording = await _recorder.isRecording();
      DiagnosticLog.log('ASR', 'pauseCapture() | isRecording=$wasRecording');
      if (wasRecording) await _recorder.pause();
      DiagnosticLog.log('ASR', 'pauseCapture() | après pause : '
          'isRecording=${await _recorder.isRecording()} '
          'isPaused=${await _recorder.isPaused()}');
    } catch (e) {
      DiagnosticLog.log('ASR', 'pauseCapture échec : $e');
    }
  }

  @override
  Future<void> resumeCapture() async {
    try {
      final wasPaused = await _recorder.isPaused();
      DiagnosticLog.log('ASR', 'resumeCapture() | isPaused=$wasPaused '
          'pcmSub actif=${_pcmSub != null} chunkCount avant=$_chunkCount');
      if (wasPaused) await _recorder.resume();
      DiagnosticLog.log('ASR', 'resumeCapture() | après resume : '
          'isRecording=${await _recorder.isRecording()} '
          'isPaused=${await _recorder.isPaused()}');
    } catch (e) {
      DiagnosticLog.log('ASR', 'resumeCapture échec : $e');
    }
  }

  @override
  Future<void> resetBuffer() => _fastConformer.resetBuffered();

  @override
  void dispose() {
    _levelTimer?.cancel();
    _pcmSub?.cancel();
    _recorder.dispose();
    unawaited(_fastConformer.dispose());
    unawaited(_fastConformer.disposeStreaming());
    _tokenCtrl.close();
    _levelCtrl.close();
    _rawCtrl.close();
    _pendingCtrl.close();
    _alignCtrl.close();
  }
}

// ── Simulateur (tests UI sans modèle) ────────────────────────────────────────

class MockRecitationVerifier implements RecitationVerifier {
  final _tokenCtrl = StreamController<RecognizedToken>.broadcast();
  final _levelCtrl = StreamController<double>.broadcast();
  Timer? _timer;
  Timer? _levelTimer;
  final _rng = Random();

  @override
  Stream<RecognizedToken> get tokens => _tokenCtrl.stream;
  @override
  Stream<double> get soundLevel => _levelCtrl.stream;
  @override
  Stream<String> get rawTranscript => const Stream.empty();
  @override
  Stream<({String committed, String preview})> get structuredTranscript =>
      const Stream.empty();
  @override
  Stream<int> get pendingSegments => const Stream.empty();
  @override
  String? get lastAudioPath => null;
  @override
  Stream<AlignPayload> get alignedWords => const Stream.empty();
  @override
  bool get alignmentActive => false;
  @override
  Future<void> setAlignmentAnchor(int index) async {}
  @override
  Future<void> extendAlignmentTarget(List<String> moreTrainingWords) async {}

  @override
  Future<void> setClipCapture(String? dir) async {}

  @override
  Future<void> start(List<String> expectedWords, {bool continuous = false}) async {
    var i = 0;
    _levelTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      _levelCtrl.add(0.25 + _rng.nextDouble() * 0.75);
    });
    _timer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (i >= expectedWords.length) {
        t.cancel();
        return;
      }
      final roll = _rng.nextDouble();
      if (roll < 0.04) {
        // saut
      } else if (roll < 0.12) {
        _tokenCtrl.add(RecognizedToken('خطأ', confidence: 0.35));
      } else {
        _tokenCtrl.add(RecognizedToken(expectedWords[i], confidence: 0.92));
      }
      i++;
    });
  }

  @override
  Future<void> pauseCapture() async {}
  @override
  Future<void> resumeCapture() async {}
  @override
  Future<void> resetBuffer() async {}

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _levelTimer?.cancel();
    _levelCtrl.add(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _levelTimer?.cancel();
    _tokenCtrl.close();
    _levelCtrl.close();
  }
}
