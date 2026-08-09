import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Enregistrements audio on-device.
///
/// ── HISTORIQUE ET CHANGEMENT DE FINALITÉ (2026-07-25) ────────────────────
/// Ce service a été écrit le 2026-07-12 pour un mini-LoRA de personnalisation
/// vocale entraîné SUR LE TÉLÉPHONE (FONCTIONNALITES_FUTURES.md,
/// "Personnalisation voix -- niveau 3"). **Cet objectif est abandonné**
/// (décision utilisateur 2026-07-25 : l'entraînement on-device n'est plus
/// envisageable). Seule la mécanique d'ENREGISTREMENT est conservée, et
/// réorientée vers le DIAGNOSTIC de la chaîne ASR.
///
/// ⚠️ RENVERSEMENT DE LA RÈGLE DE RÉTENTION -- ne pas le refaire à l'envers :
/// la version mini-LoRA ne gardait que les segments **100 % corrects**
/// (filtre `allCorrect` dans `recitation_provider`, supprimé le 2026-07-25),
/// puisqu'elle cherchait des exemples propres pour entraîner. Un diagnostic
/// a besoin de l'EXACT INVERSE : ce sont les segments contenant les mots
/// signalés qui portent l'information. Mesuré ce jour-là : une session de
/// référence a écrit 8 WAV sans erreur, puis les a TOUS supprimés parce
/// qu'aucun segment n'était intégralement correct -- la preuve était créée
/// puis détruite. Désormais on garde TOUT (demande utilisateur explicite :
/// « il faut tout garder »).
///
/// Stockage on-device UNIQUEMENT (donnée vocale sensible/religieuse, jamais
/// synchronisée en arrière-plan -- même contrat que VoiceFingerprintService).
/// Deux espaces distincts :
///  • `recitation_captures/session_<ts>/clip_*.wav` -- capture de DIAGNOSTIC
///    des récitations, écrite directement par Kotlin, jamais filtrée ni
///    supprimée automatiquement (cf. [newRecitationCaptureDir]).
///  • `voice_lora_clips/{clip_*.wav, manifest.jsonl}` -- jeu de clips
///    ÉTIQUETÉS de l'écran de calibration (mots prononcés volontairement
///    juste/faux, cf. voice_calibration_screen.dart), toujours utile en
///    export pour un entraînement hors téléphone. Conservé tel quel.
class VoiceLoraClipService {
  static const _kDirName = 'voice_lora_clips';
  static const _kManifestFile = 'manifest.jsonl';
  static const _kRecitationDirName = 'recitation_captures';
  static const _kDisputedDirName = 'disputed_verdicts';

  /// Racine durable des captures de diagnostic des récitations.
  Future<Directory> _recitationDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_kRecitationDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Dossier de capture d'UNE session de récitation, dans le stockage
  /// DURABLE (et non le cache temporaire comme l'ancien
  /// [newTempCaptureDir]). Kotlin y écrit un WAV par segment figé, et
  /// **rien ne les supprime** : ni filtre de qualité, ni nettoyage de fin de
  /// session, ni `dispose()` de l'écran.
  ///
  /// POURQUOI DURABLE : l'ancien chemin passait par `getTemporaryDirectory()`
  /// et le `dispose()` de l'écran de récitation supprimait le dossier alors
  /// que le natif continuait d'y écrire -> `open failed: ENOENT` sur chaque
  /// segment, silencieusement avalé (bug constaté 2026-07-25, 30 échecs
  /// d'affilée). Un dossier durable et non supprimé ferme cette classe de
  /// bug par construction.
  Future<String> newRecitationCaptureDir() async {
    final root = await _recitationDir();
    final dir = Directory(
        '${root.path}/session_${DateTime.now().millisecondsSinceEpoch}');
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Nombre total de WAV de diagnostic conservés (toutes sessions).
  Future<int> recitationClipCount() async {
    final root = await _recitationDir();
    if (!await root.exists()) return 0;
    var n = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.wav')) n++;
    }
    return n;
  }

  /// Supprime toutes les captures de diagnostic (geste EXPLICITE de
  /// l'utilisateur uniquement -- rien ne les efface automatiquement).
  Future<void> deleteAllRecitationCaptures() async {
    final root = await _recitationDir();
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Empaquette toutes les captures de diagnostic dans un .zip et ouvre le
  /// partage natif -- même contrat que [exportViaShare] : aucune sync
  /// automatique, geste explicite à chaque fois.
  Future<bool> exportRecitationCaptures() async {
    final root = await _recitationDir();
    if (!await root.exists()) return false;
    final files = await root
        .list(recursive: true)
        .where((e) => e is File)
        .cast<File>()
        .toList();
    if (files.isEmpty) return false;

    final tmp = await getTemporaryDirectory();
    final zipPath =
        '${tmp.path}/coran_karim_diag_${DateTime.now().millisecondsSinceEpoch}.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final f in files) {
      encoder.addFile(f);
    }
    encoder.close();

    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(zipPath)],
      text: 'Captures de diagnostic récitation — Coran Karim',
    ));
    return result.status == ShareResultStatus.success;
  }

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

  // ── Verdicts contestés (demande utilisateur 2026-08-07) ──────────────────
  //
  // Troisième espace, distinct des deux ci-dessus : quand l'utilisateur tape
  // le pouce vers le bas sur l'extrait "Ma voix" (tajwid_help_sheet.dart), il
  // dit "l'app a jugé ce mot faux/incertain à tort". L'extrait exact déjà
  // rejoué (issu du flux brut, cf. `v2ExtraitVoix`) est archivé ici -- un
  // faux positif confirmé par l'utilisateur est exactement la matière qui
  // manque pour recalibrer un futur entraînement. Même contrat que les deux
  // espaces existants : stockage on-device uniquement, export MANUEL via le
  // partage natif, aucune synchronisation automatique.
  Future<Directory> _disputedDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_kDisputedDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copie (jamais déplace -- la source est un fichier de cache partagé,
  /// réécrasé à la prochaine écoute) l'extrait contesté vers le stockage
  /// permanent, avec le texte attendu et le verdict contesté dans le
  /// manifest.
  Future<void> commitDisputedClip({
    required String sourcePath,
    required String text,
    required String verdict,
  }) async {
    final src = File(sourcePath);
    if (!await src.exists()) return;
    final dir = await _disputedDir();
    final destName = 'clip_${DateTime.now().microsecondsSinceEpoch}.wav';
    await src.copy('${dir.path}/$destName');
    final manifestFile = File('${dir.path}/$_kManifestFile');
    final entry = jsonEncode({
      'clip': destName,
      'text': text,
      'verdict': verdict,
      'capturedAt': DateTime.now().toIso8601String(),
    });
    await manifestFile.writeAsString('$entry\n', mode: FileMode.append, flush: true);
  }

  /// Nombre de verdicts contestés déjà archivés (affiché dans Réglages).
  Future<int> disputedClipCount() async {
    final dir = await _disputedDir();
    final manifestFile = File('${dir.path}/$_kManifestFile');
    if (!await manifestFile.exists()) return 0;
    final lines = await manifestFile.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).length;
  }

  /// Empaquette les verdicts contestés + le manifest dans un .zip et ouvre le
  /// partage natif -- même contrat que [exportViaShare]/[exportRecitationCaptures].
  Future<bool> exportDisputedClips() async {
    final dir = await _disputedDir();
    if (!await dir.exists()) return false;
    final files = await dir.list().where((e) => e is File).cast<File>().toList();
    if (files.isEmpty) return false;

    final tmp = await getTemporaryDirectory();
    final zipPath =
        '${tmp.path}/coran_karim_verdicts_contestes_${DateTime.now().millisecondsSinceEpoch}.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final f in files) {
      encoder.addFile(f);
    }
    encoder.close();

    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(zipPath)],
      text: 'Verdicts contestés — Coran Karim (amélioration du modèle)',
    ));
    return result.status == ShareResultStatus.success;
  }
}
