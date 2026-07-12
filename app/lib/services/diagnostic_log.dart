import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// Journal PERSISTANT sur le stockage du téléphone — indépendant de toute
/// connexion adb (demande utilisateur 2026-07-11 : "un fichier log qui
/// tourne sans être écrasé... qui fonctionne même que le tel ne soit pas
/// branché... je veux récupérer quand je te demande"). Contrairement au
/// buffer logcat de l'OS (circulaire, perd les entrées anciennes sous forte
/// charge et inaccessible sans adb), ce fichier :
///   - grandit en ANNEXE (append), jamais tronqué entre deux sessions ;
///   - vit dans le stockage externe propre à l'app (pas de permission
///     spéciale requise, `adb pull` fonctionne directement dessus) ;
///   - est écrit par Dart ET Kotlin (cf. DiagnosticLog.kt côté natif,
///     chemin transmis via setLogFile) pour capturer tout le pipeline
///     (ASR, alignement GOP, correction, extension de sourate) dans le
///     MÊME fichier chronologique.
///
/// Bug corrigé 2026-07-11 (constaté sur un vrai test : quasi aucune ligne
/// native dans le fichier, la seule présente tronquée en plein milieu) :
/// la version précédente gardait un `IOSink` ouvert en permanence côté Dart
/// (écritures bufferisées, jamais explicitement vidées) pendant que Kotlin
/// ouvre/écrit/ferme un `FileWriter` À CHAQUE appel -- les deux runtimes
/// écrivaient dans le MÊME fichier sans aucune synchronisation, et les
/// écritures Kotlin se faisaient quasi systématiquement écraser par le
/// buffer Dart pas encore vidé. Fix : Dart ouvre/écrit/ferme aussi à
/// CHAQUE appel (`writeAsStringSync`, un seul appel système par ligne,
/// borné et donc quasi-atomique sous O_APPEND) -- même discipline des deux
/// côtés, plus de fenêtre de course entre un flush différé et une écriture
/// native concurrente.
///
/// Récupération : `adb pull <chemin retourné par init()> .` — pas besoin
/// que la capture tourne pendant le test, le fichier est déjà sur le
/// téléphone, prêt à être tiré à la demande.
class DiagnosticLog {
  static File? _file;

  static String? get path => _file?.path;

  static Future<String?> init() async {
    if (_file != null) return _file!.path;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;
      _file = File('${dir.path}/recitation_diagnostic.log');
      log('DiagnosticLog', '=== session démarrée ===');
      return _file!.path;
    } catch (e) {
      debugPrint('[DiagnosticLog] init échoué : $e');
      return null;
    }
  }

  static void log(String tag, String message) {
    final line = '${DateTime.now().toIso8601String()} [$tag] $message';
    debugPrint(line); // garde aussi la visibilité logcat habituelle
    final f = _file;
    if (f == null) return;
    try {
      // Ouvre/écrit/ferme en UNE fois, comme DiagnosticLog.kt côté natif --
      // jamais de buffer Dart qui traîne pendant qu'un write natif survient.
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Le fichier n'est pas critique au fonctionnement -- ne jamais
      // faire planter la récitation pour un souci d'écriture disque.
    }
  }
}
