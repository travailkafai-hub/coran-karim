import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Niveau 1 de l'idée "personnalisation voix" (mémoire voice-personalization-idea,
/// proposée par l'utilisateur le 2026-06-27) : comparaison audio-à-audio entre
/// une récitation déjà vérifiée correcte (enregistrée pendant la phase
/// Lecture/Entraîne) et une nouvelle tentative — SANS repasser par un
/// décodage texte (instable à 20% d'entraînement, cf. SKILL.md). Validé côté
/// recherche (benchmark/test_embedding_dtw.py) : ~0.94 de similarité pour un
/// même contenu (récitateurs différents) vs ~0.86 pour un contenu différent —
/// nettement mieux que l'alignement forcé testé avant.
///
/// ⚠️ Piège identifié par l'utilisateur dès le départ : la 1ère lecture peut
/// contenir des erreurs, ce n'est PAS une référence fiable en soi. Cette classe
/// se contente de stocker/comparer — c'est à l'appelant de ne sauvegarder une
/// référence QUE si elle a été vérifiée correcte par ailleurs (ex: le score
/// ASR de la phase Entraîne était bon).
///
/// Empreintes stockées on-device uniquement (donnée vocale sensible), sous
/// `ApplicationDocumentsDirectory/voice_fingerprints/<passageKey>.bin`.
class VoiceFingerprintService {
  static const _channel = MethodChannel('com.corankarim/fastconformer_ctc');
  static const _kModelSubdir = 'models/fastconformer-ctc-pcd';
  static const _kModelFile = 'model_embed.onnx';

  bool _loaded = false;

  Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    final appDir = await getApplicationSupportDirectory();
    final modelFile = File('${appDir.path}/$_kModelSubdir/$_kModelFile');
    if (!await modelFile.exists()) {
      debugPrint('[VoiceFingerprint] Modèle embeddings absent (${modelFile.path}) — ignoré');
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('loadFingerprintModel', {
        'modelPath': modelFile.path,
      });
      _loaded = ok ?? false;
      debugPrint('[VoiceFingerprint] Modèle chargé : $_loaded');
      return _loaded;
    } catch (e) {
      debugPrint('[VoiceFingerprint] Échec chargement : $e');
      return false;
    }
  }

  Future<File> _refFile(String passageKey) async {
    final dir = await getApplicationDocumentsDirectory();
    final sub = Directory('${dir.path}/voice_fingerprints');
    if (!await sub.exists()) await sub.create(recursive: true);
    // Cle assainie (pas de caracteres de chemin) — ex: "1:1-1:7" -> "1_1-1_7".
    final safe = passageKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${sub.path}/$safe.bin');
  }

  Future<bool> hasReference(String passageKey) async {
    return (await _refFile(passageKey)).exists();
  }

  /// Enregistre [wavPath] comme référence pour [passageKey]. À n'appeler QUE
  /// si l'appelant a déjà vérifié que cette récitation est correcte (voir
  /// avertissement de la classe).
  Future<bool> saveReference(String wavPath, String passageKey) async {
    if (!_loaded) return false;
    try {
      final outPath = (await _refFile(passageKey)).path;
      final ok = await _channel.invokeMethod<bool>('saveFingerprint', {
        'wavPath': wavPath,
        'outPath': outPath,
      });
      debugPrint('[VoiceFingerprint] Référence sauvegardée pour "$passageKey" : ${ok ?? false}');
      return ok ?? false;
    } catch (e) {
      debugPrint('[VoiceFingerprint] Échec sauvegarde référence : $e');
      return false;
    }
  }

  /// Compare [wavPath] à la référence stockée pour [passageKey]. Retourne un
  /// score [0,1] (similarité DTW sur les embeddings) ou null si pas de
  /// référence disponible / erreur.
  Future<double?> compareToReference(String wavPath, String passageKey) async {
    if (!_loaded) return null;
    final ref = await _refFile(passageKey);
    if (!await ref.exists()) return null;
    try {
      return await _channel.invokeMethod<double>('compareFingerprint', {
        'wavPath': wavPath,
        'refPath': ref.path,
      });
    } catch (e) {
      debugPrint('[VoiceFingerprint] Échec comparaison : $e');
      return null;
    }
  }

  Future<void> dispose() async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('disposeFingerprint');
    } catch (_) {}
    _loaded = false;
  }
}
