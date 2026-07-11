import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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
    if (!await modelFile.exists() || !await vocabFile.exists()) {
      debugPrint('[FastConformer] Modèle/vocab absents (${modelFile.path}) — ignoré');
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('loadModel', {
        'modelPath': modelFile.path,
        'vocabPath': vocabFile.path,
      });
      _loaded = ok ?? false;
      debugPrint('[FastConformer] Modèle chargé : $_loaded');
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
  Future<({String committed, String preview})?> feedBufferedAudio(Uint8List pcm16) async {
    if (!_loaded) return null;
    try {
      final raw = await _channel
          .invokeMapMethod<String, String>('feedBufferedAudio', {'pcm16': pcm16});
      if (raw == null) return null;
      return (committed: raw['committed'] ?? '', preview: raw['preview'] ?? '');
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
}
