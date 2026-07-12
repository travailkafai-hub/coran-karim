import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'diagnostic_log.dart';

// ── Alignement forcé GOP (cf. ForcedAligner.kt, refonte 2026-07-11) ──────────

/// Résultat d'alignement pour UN mot attendu. [gop] = forced - free (toujours
/// ≤ 0) : proche de 0 = l'audio soutient pleinement le mot attendu (harakat
/// comprises) ; très négatif = le modèle est bien plus sûr d'avoir entendu
/// autre chose ([actual] dit quoi — décodage libre sur la plage de frames que
/// l'alignement attribue à ce mot).
class AlignedWord {
  final int index; // index ABSOLU dans le texte attendu complet
  final double gop;
  final double forced;
  final bool covered; // false = mot encore en cours de prononciation (frontière)
  final String actual;

  const AlignedWord({
    required this.index,
    required this.gop,
    required this.forced,
    required this.covered,
    required this.actual,
  });
}

/// Une passe d'alignement complète. [isFinal] : segment figé — l'audio de ces
/// mots ne sera plus jamais réanalysé, jugements définitifs. [frontier] :
/// premier mot que l'audio ne couvre pas complètement (= mot courant UI).
class AlignPayload {
  final int seq;
  final int anchor;
  final int frontier;
  final bool isFinal;
  final List<AlignedWord> words;
  // Chemin du clip WAV capturé pour CE segment figé (mini-LoRA personnalisation
  // vocale, cf. FONCTIONNALITES_FUTURES.md "Personnalisation voix -- niveau 3",
  // implémenté 2026-07-12) -- non null seulement si la capture est active
  // (FastConformerVerifier.setClipCapture) ET que ce payload correspond à un
  // commit normal (pas le repli "borne dure" qui réutilise l'aperçu sans clip).
  final String? clipPath;

  const AlignPayload({
    required this.seq,
    required this.anchor,
    required this.frontier,
    required this.isFinal,
    required this.words,
    this.clipPath,
  });

  static AlignPayload? fromMap(dynamic m) {
    if (m is! Map) return null;
    final rawWords = m['words'];
    final words = <AlignedWord>[];
    if (rawWords is List) {
      for (final w in rawWords) {
        if (w is! Map) continue;
        words.add(AlignedWord(
          index: (w['i'] as num).toInt(),
          gop: (w['gop'] as num).toDouble(),
          forced: (w['forced'] as num).toDouble(),
          covered: w['covered'] as bool? ?? false,
          actual: w['actual'] as String? ?? '',
        ));
      }
    }
    return AlignPayload(
      seq: (m['seq'] as num?)?.toInt() ?? -1,
      anchor: (m['anchor'] as num?)?.toInt() ?? 0,
      frontier: (m['frontier'] as num?)?.toInt() ?? 0,
      isFinal: m['final'] as bool? ?? false,
      words: words,
      clipPath: m['clipPath'] as String?,
    );
  }
}

/// Deuxième vérificateur ASR (FastConformer CTC, entraîné sur le corpus Coran,
/// cf. benchmark/models/fastconformer-quran-pcd), tournant EN PARALLÈLE de
/// whisper.cpp — PAS un remplacement tant que le training n'est pas terminé et
/// comparé sur test_voice_full.jsonl (whisper-medium-ft ~11% WER de référence).
///
/// Objectif de cette intégration précoce : valider tout le pipeline (export
/// ONNX -> mel Kotlin -> inférence -> décodage CTC -> détokenisation) PENDANT
/// que le training tourne encore côté PC, pour qu'il suffise de remplacer le
/// fichier .onnx une fois le modèle final prêt — pas de surprise d'intégration
/// à ce moment-là.
///
/// Chaîne Kotlin : MethodChannel (pas FFI comme whisper_ggml — l'API ONNX
/// Runtime Android est Kotlin/Java, pas une lib C à lier directement) — voir
/// android/app/src/main/kotlin/.../fastconformer/FastConformerCtcPlugin.kt.
class FastConformerVerifier {
  static const _channel = MethodChannel('com.corankarim/fastconformer_ctc');
  static const _kModelSubdir = 'models/fastconformer-ctc-pcd';
  static const _kModelFile = 'model.onnx';
  static const _kVocabFile = 'vocab.json';
  // Dictionnaire mot -> IDs de tokens précalculé avec le VRAI tokenizer NeMo
  // (benchmark/build_word_token_lookup.py) — remplace la tokenisation greedy
  // heuristique de CtcTokenizer.kt comme source PRIMAIRE pour l'alignement
  // forcé (celle-ci reste un repli pour les mots hors dictionnaire, ex. texte
  // hors-Coran). Optionnel : absent → CtcTokenizer.kt gère tout en greedy.
  static const _kWordTokensFile = 'word_tokens.json';

  bool _loaded = false;

  /// Résout les chemins modèle/vocab côté app-support (même convention que
  /// whisper-medium-ggml) et charge la session ONNX côté Kotlin. Idempotent :
  /// ne recharge pas si déjà fait. Retourne false si le modèle n'est pas
  /// encore déployé sur l'appareil (pas une erreur — juste "pas encore prêt").
  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    final appDir = await getApplicationSupportDirectory();
    final modelFile = File('${appDir.path}/$_kModelSubdir/$_kModelFile');
    final vocabFile = File('${appDir.path}/$_kModelSubdir/$_kVocabFile');
    final wordTokensFile = File('${appDir.path}/$_kModelSubdir/$_kWordTokensFile');
    if (!await modelFile.exists() || !await vocabFile.exists()) {
      debugPrint('[FastConformer] Modèle/vocab absents (${modelFile.path}) — ignoré');
      return false;
    }
    final hasWordTokens = await wordTokensFile.exists();
    if (!hasWordTokens) {
      debugPrint('[FastConformer] word_tokens.json absent — alignement forcé '
          'utilisera la tokenisation greedy (repli) pour tous les mots');
    }
    try {
      final ok = await _channel.invokeMethod<bool>('loadModel', {
        'modelPath': modelFile.path,
        'vocabPath': vocabFile.path,
        'wordTokensPath': hasWordTokens ? wordTokensFile.path : null,
      });
      _loaded = ok ?? false;
      debugPrint('[FastConformer] Modèle chargé : $_loaded');
      // Relie le fichier de log natif (BufferedTranscriber, ForcedAligner) au
      // MÊME fichier persistant que le côté Dart (cf. diagnostic_log.dart) —
      // une seule chronologie, récupérable par adb pull sans connexion
      // continue (demande utilisateur 2026-07-11).
      final logPath = DiagnosticLog.path;
      if (_loaded && logPath != null) {
        unawaited(
            _channel.invokeMethod('setLogFile', {'path': logPath}));
      }
      return _loaded;
    } catch (e) {
      debugPrint('[FastConformer] Échec chargement modèle : $e');
      return false;
    }
  }

  /// Transcrit un segment WAV déjà découpé (même fichier que whisper.cpp reçoit
  /// — pas de refonte du pipeline audio pour ce premier jet). Retourne null en
  /// cas d'échec (modèle non chargé, erreur native) — appelant doit tolérer.
  Future<String?> transcribe(String wavPath) async {
    if (!_loaded) return null;
    try {
      final text = await _channel.invokeMethod<String>('transcribe', {'wavPath': wavPath});
      return text;
    } catch (e) {
      debugPrint('[FastConformer] Échec transcription : $e');
      return null;
    }
  }

  Future<void> dispose() async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {}
    _loaded = false;
  }

  // ── Streaming cache-aware (vrai flux continu, karaoké) ──────────────────────
  // Modèle distinct de celui du mode segment-par-segment ci-dessus : encodeur
  // basculé en attention chunked_limited + cache d'état en entrée/sortie
  // (benchmark/export_streaming_onnx.py, validé fidèle au PyTorch natif).
  static const _kStreamingModelSubdir = 'models/fastconformer-ctc-pcd-streaming';
  static const _kStreamingModelFile = 'model_streaming.onnx';
  bool _streamingLoaded = false;

  Future<bool> ensureStreamingLoaded() async {
    if (_streamingLoaded) return true;
    final appDir = await getApplicationSupportDirectory();
    final modelFile = File('${appDir.path}/$_kStreamingModelSubdir/$_kStreamingModelFile');
    final vocabFile = File('${appDir.path}/$_kStreamingModelSubdir/$_kVocabFile');
    if (!await modelFile.exists() || !await vocabFile.exists()) {
      debugPrint('[FastConformer] Modèle streaming absent (${modelFile.path}) — ignoré');
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('loadStreamingModel', {
        'modelPath': modelFile.path,
        'vocabPath': vocabFile.path,
      });
      _streamingLoaded = ok ?? false;
      debugPrint('[FastConformer] Modèle streaming chargé : $_streamingLoaded');
      return _streamingLoaded;
    } catch (e) {
      debugPrint('[FastConformer] Échec chargement modèle streaming : $e');
      return false;
    }
  }

  /// Envoie un bloc de PCM16LE brut (mono 16kHz) et retourne le texte COMPLET
  /// décodé jusqu'ici (pas un delta — plus simple à afficher, on remplace au
  /// lieu d'accumuler côté UI). Retourne null si le modèle streaming n'est pas
  /// chargé ou en cas d'erreur native.
  Future<String?> feedAudioChunk(Uint8List pcm16) async {
    if (!_streamingLoaded) return null;
    try {
      return await _channel.invokeMethod<String>('feedAudioChunk', {'pcm16': pcm16});
    } catch (e) {
      debugPrint('[FastConformer] Échec feedAudioChunk : $e');
      return null;
    }
  }

  Future<void> resetStreaming() async {
    if (!_streamingLoaded) return;
    try {
      await _channel.invokeMethod('resetStreaming');
    } catch (_) {}
  }

  Future<void> disposeStreaming() async {
    if (!_streamingLoaded) return;
    try {
      await _channel.invokeMethod('disposeStreaming');
    } catch (_) {}
    _streamingLoaded = false;
  }

  // ── Streaming "bufferisé" (fallback fiable) ─────────────────────────────────
  // Le vrai streaming cache-aware (ci-dessus) ne fonctionne pas : notre
  // checkpoint est entraîné avec des convolutions non-causales, incompatibles
  // avec l'inférence par cache en flux (confirmé : même l'API officielle NeMo
  // conformer_stream_step plante dessus). Solution qui marche : re-transcrire
  // le buffer audio complet de la session avec le modèle OFFLINE (déjà validé)
  // toutes les ~1,5s de nouvel audio — latence perçue ~1,5-3s, mais continu,
  // sans coupure manuelle. Réutilise le modèle chargé via ensureLoaded().
  /// Retourne les deux parties du transcript : `committed` (segments figés,
  /// append-only, plus jamais révisés) et `preview` (segment courant, encore
  /// susceptible de changer à chaque re-transcription). Le scoring s'ancre sur
  /// la partie figée — re-partir du mot 0 à chaque passe calait dès que le
  /// début du texte était perdu par une re-transcription.
  Future<({String committed, String preview, AlignPayload? align})?>
      feedBufferedAudio(Uint8List pcm16) async {
    if (!_loaded) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('feedBufferedAudio', {'pcm16': pcm16});
      if (raw == null) return null;
      return (
        committed: raw['committed'] as String? ?? '',
        preview: raw['preview'] as String? ?? '',
        align: AlignPayload.fromMap(raw['align']),
      );
    } catch (e) {
      debugPrint('[FastConformer] Échec feedBufferedAudio : $e');
      return null;
    }
  }

  Future<void> resetBuffered() async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('resetBuffered');
    } catch (_) {}
  }

  // ── Alignement forcé GOP ────────────────────────────────────────────────────

  /// Déclare le texte attendu (formes STRICTES : harakat conservées, variantes
  /// uthmani rabattues — ArabicNormalizer.normalizeStrict, même normalisation
  /// que le corpus d'entraînement) et l'ancre de départ. Retourne true si
  /// l'alignement est actif (modèle chargé + tokenisation OK) — sinon le
  /// scoring Dart doit retomber sur le diff textuel historique.
  Future<bool> setAlignmentTarget(List<String> strictWords, int anchor) async {
    if (!_loaded) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setAlignmentTarget', {
        'words': strictWords,
        'anchor': anchor,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[FastConformer] Échec setAlignmentTarget : $e');
      return false;
    }
  }

  /// Repositionne l'ancre d'alignement (correction/recul : la prochaine passe
  /// compare l'audio au mot [anchor], pas à la suite).
  Future<void> setAlignmentAnchor(int anchor) async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('setAlignmentAnchor', {'anchor': anchor});
    } catch (e) {
      debugPrint('[FastConformer] Échec setAlignmentAnchor : $e');
    }
  }

  /// Active/désactive la capture de clips VÉRIFIÉS CORRECTS (mini-LoRA
  /// personnalisation vocale, cf. FONCTIONNALITES_FUTURES.md
  /// "Personnalisation voix -- niveau 3", implémenté 2026-07-12). [dir] =
  /// null désactive (défaut). N'écrit rien tant que non activé — zéro coût
  /// hors session de référence.
  Future<void> setClipCapture(String? dir) async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('setClipCapture', {'dir': dir});
    } catch (e) {
      debugPrint('[FastConformer] Échec setClipCapture : $e');
    }
  }

  /// Alignement one-shot d'un WAV complet (mode coach, segment unique) contre
  /// la cible déclarée via [setAlignmentTarget]. Null si indisponible.
  Future<AlignPayload?> alignFile(String wavPath) async {
    if (!_loaded) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('alignFile', {'wavPath': wavPath});
      return AlignPayload.fromMap(raw);
    } catch (e) {
      debugPrint('[FastConformer] Échec alignFile : $e');
      return null;
    }
  }

  /// Étend la cible d'alignement avec des mots supplémentaires (formes
  /// STRICTES d'entraînement), à la SUITE de la cible actuelle — SANS toucher
  /// l'ancre. Enchaînement sur la sourate suivante sans interrompre la session.
  Future<bool> extendAlignmentTarget(List<String> strictWords) async {
    if (!_loaded) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('extendAlignmentTarget', {
        'words': strictWords,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[FastConformer] Échec extendAlignmentTarget : $e');
      return false;
    }
  }
}
