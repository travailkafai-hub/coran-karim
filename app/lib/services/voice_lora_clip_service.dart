import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Collecte et export des clips de récitation VÉRIFIÉS CORRECTS (session de
/// référence validée), en vue d'un futur mini-LoRA de personnalisation vocale
/// (FONCTIONNALITES_FUTURES.md, "Personnalisation voix -- niveau 3",
/// implémenté 2026-07-12 sur demande explicite malgré les deux inconnues du
/// plan d'origine -- ce service règle la première : pas de sync automatique
/// téléphone->PC, un export MANUEL via le partage natif Android à la place.
///
/// Stockage on-device UNIQUEMENT (donnée vocale sensible/religieuse, jamais
/// synchronisée en arrière-plan -- même contrat que VoiceFingerprintService) :
/// `ApplicationDocumentsDirectory/voice_lora_clips/{clip_*.wav, manifest.jsonl}`.
/// `manifest.jsonl` : une ligne JSON par clip, `{clip, text, capturedAt}`.
class VoiceLoraClipService {
  static const _kDirName = 'voice_lora_clips';
  static const _kManifestFile = 'manifest.jsonl';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_kDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Répertoire TEMPORAIRE dédié à une session de capture (cf.
  /// FastConformerVerifier.setClipCapture) -- distinct du stockage permanent :
  /// les clips y sont écrits par Kotlin au fil de la session, puis
  /// [commitClips] ne fait remonter au stockage permanent que ceux
  /// effectivement vérifiés corrects (cf. RecitationNotifier.takeCollectedClips) ;
  /// le reste est supprimé par [discardTempDir].
  Future<String> newTempCaptureDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(
        '${tmp.path}/voice_lora_capture_${DateTime.now().millisecondsSinceEpoch}');
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Déplace les clips [clips] (chemins dans le dossier temporaire de capture)
  /// vers le stockage permanent et ajoute leurs entrées au manifest, PUIS
  /// supprime tout le dossier temporaire (les clips non retenus, jamais
  /// vérifiés corrects, disparaissent avec lui).
  Future<int> commitClips(
      List<({String path, String text})> clips, String tempDir) async {
    if (clips.isEmpty) {
      await discardTempDir(tempDir);
      return 0;
    }
    final dir = await _dir();
    final manifestFile = File('${dir.path}/$_kManifestFile');
    var saved = 0;
    for (final clip in clips) {
      final src = File(clip.path);
      if (!await src.exists()) continue;
      final destName = 'clip_${DateTime.now().microsecondsSinceEpoch}_$saved.wav';
      final destPath = '${dir.path}/$destName';
      await src.copy(destPath);
      final entry = jsonEncode({
        'clip': destName,
        'text': clip.text,
        'capturedAt': DateTime.now().toIso8601String(),
      });
      await manifestFile.writeAsString('$entry\n',
          mode: FileMode.append, flush: true);
      saved++;
    }
    await discardTempDir(tempDir);
    return saved;
  }

  Future<void> discardTempDir(String tempDir) async {
    try {
      final dir = Directory(tempDir);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // best-effort -- des fichiers temporaires orphelins ne bloquent rien.
    }
  }

  /// Nombre de clips déjà mémorisés (affiché dans Réglages).
  Future<int> clipCount() async {
    final dir = await _dir();
    final manifestFile = File('${dir.path}/$_kManifestFile');
    if (!await manifestFile.exists()) return 0;
    final lines = await manifestFile.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).length;
  }

  /// Empaquette tous les clips + le manifest dans un .zip et ouvre le partage
  /// natif (email, Drive, câble... au choix de l'utilisateur) -- AUCUNE sync
  /// automatique, geste explicite à chaque fois.
  Future<bool> exportViaShare() async {
    final dir = await _dir();
    if (!await dir.exists()) return false;
    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    if (files.isEmpty) return false;

    final tmp = await getTemporaryDirectory();
    final zipPath =
        '${tmp.path}/coran_karim_voice_clips_${DateTime.now().millisecondsSinceEpoch}.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final f in files) {
      encoder.addFile(f);
    }
    encoder.close();

    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(zipPath)],
      text: 'Clips de récitation vérifiés — Coran Karim (personnalisation voix)',
    ));
    return result.status == ShareResultStatus.success;
  }
}
