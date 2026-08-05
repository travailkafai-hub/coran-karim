import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Interrupteur global du diagnostic (log fichier + capture WAV), piloté par
  /// l'utilisateur (réglage `diagnosticEnabledProvider`, 2026-07-25).
  ///
  /// Pourquoi ce réglage existe : sur une session mesurée le 2026-07-25, la
  /// journalisation représentait à elle seule **22 à 32 écritures fichier
  /// synchrones par seconde** (chacune un `writeAsStringSync(flush: true)`,
  /// donc un appel système bloquant sur l'isolate Dart). L'utilisateur a
  /// demandé de pouvoir l'éteindre pour vérifier que le retard de validation
  /// n'est pas causé par l'instrumentation elle-même — question légitime :
  /// un diagnostic qui modifie ce qu'il mesure n'est pas un diagnostic.
  ///
  /// Quand c'est faux : aucune écriture fichier, aucun `debugPrint`, et aucun
  /// WAV capturé côté natif (cf. RecitationNotifier.startContinuous). Le
  /// natif est coupé par le même interrupteur (méthode `setLogEnabled`).
  static bool enabled = true;

  static String? get path => _file?.path;

  /// Identifiant du CODE embarqué dans l'APK — à bumper manuellement à chaque
  /// changement de comportement qu'on veut pouvoir tracer dans les logs.
  ///
  /// Ajouté 2026-07-16 après une perte de temps réelle : un correctif
  /// d'alignement (`maxReachable`) avait été compilé mais PAS installé sur le
  /// téléphone, et le log du test suivant était strictement indiscernable de
  /// celui de la version précédente -- diagnostic mené sur un binaire qui ne
  /// contenait pas le fix, conclusions faussées. Une ligne de version en tête
  /// de session rend l'erreur impossible à répéter silencieusement : si ce
  /// tag ne correspond pas au fix qu'on croit tester, le log le dit tout de
  /// suite.
  ///
  /// [_kBuildTimestamp] complète le tag manuel : injecté au build via
  /// `--dart-define=BUILD_TS=...`, il distingue deux compilations du même tag
  /// (utile quand on itère sans bumper le tag). Vide si non fourni.
  /// Exposé pour le relevé de paramètres en tête de session
  /// (RecitationNotifier._logParametresSession) : la ligne PARAMS doit pouvoir
  /// rappeler le binaire, sinon un log tiré hors contexte ne dit plus lequel.
  static String get buildTag => _kBuildTag;

  // Binaire de la branche `recitation-v2` : base v24 (e735f99) + le coeur de la
  // chaine v2 COMPILE MAIS NON BRANCHE (package recitation2, accessible par le
  // seul banc `v2AnalyserWav`). La chaine qui peint l'ecran est donc toujours
  // la v1, a l'identique -- ce tag sert precisement a le prouver : une mesure
  // sous ce tag doit reproduire la v24, sinon l'ajout du code v2 a eu un effet
  // qu'il ne devait pas avoir.
  // v5-trois-tetes (2026-08-04) : modele 3 sorties deploye (logprobs +
  // tajwid_logprobs + encoder_state). Tete 2 (tajwid) branchee dans la chaine
  // v2 live (decodeTajwid par mot, cf. ChaineRecitation.vecteurTete3/reglesTajwid).
  // Tete 3 (ecart canonique) calculee et JOURNALISEE SEULEMENT (logit + seuil
  // dans les logs [t3]) -- n'influence AUCUN verdict tant que la parite des 12
  // scores n'est pas verifiee sur device (cf. Tete3.kt).
  static const String _kBuildTag = 'v21-poignee-et-mot-seul';
  static const String _kBuildTimestamp =
      String.fromEnvironment('BUILD_TS', defaultValue: '');

  static Future<String?> init() async {
    if (_file != null) return _file!.path;
    // Le réglage est relu ICI et pas seulement dans DiagnosticEnabledNotifier :
    // ce notifier n'est construit qu'au premier `ref.watch`, donc si
    // l'utilisateur coupe le diagnostic puis relance l'app sans ouvrir les
    // réglages, rien ne l'aurait rétabli et la journalisation serait repartie
    // à son insu — exactement le contraire de ce que le réglage promet.
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('diagnostic_enabled') ?? true;
    } catch (_) {
      // Défaut sûr : le diagnostic reste actif.
    }
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;
      _file = File('${dir.path}/recitation_diagnostic.log');
      log('DiagnosticLog', '=== session démarrée ===');
      log('DiagnosticLog',
          '=== BUILD code=$_kBuildTag'
          '${_kBuildTimestamp.isEmpty ? '' : ' compile=$_kBuildTimestamp'} ===');
      // Lie le journal NATIF des l'ouverture de l'app.
      //
      // BUG LATENT CORRIGE ICI (2026-07-31). `setLogFile` n'etait appele que
      // depuis fastconformer_verifier.dart, au chargement du modele ASR. Or le
      // pendant Kotlin fait `val f = file ?: return` : SANS FICHIER IL N'ECRIT
      // RIEN. Tout composant natif qui journalise AVANT la premiere recitation
      // ecrivait donc dans le vide, en silence -- ce n'etait pas visible tant
      // que seul l'ASR journalisait, puisqu'il liait le fichier lui-meme juste
      // avant.
      //
      // Constate sur l'ecran de CALIBRAGE : il n'a pas besoin du modele, donc
      // il n'a jamais declenche setLogFile ; ses lignes [CALIB] n'atteignaient
      // aucun fichier et il n'y avait rien a recuperer par `adb pull`. Le
      // symptome etait trompeur -- « le calibrage n'ecrit pas » alors que le
      // defaut etait « le natif n'a pas de fichier ».
      try {
        await const MethodChannel('com.corankarim/fastconformer_ctc')
            .invokeMethod('setLogFile', {'path': _file!.path});
      } catch (_) {
        // Plugin pas encore attache : l'ASR le refera de son cote.
      }
      return _file!.path;
    } catch (e) {
      debugPrint('[DiagnosticLog] init échoué : $e');
      return null;
    }
  }

  // ── TRACE FINE (2026-07-27) : accumulée EN MÉMOIRE, écrite à la fin ───────
  // Même raison que le pendant Kotlin (DiagnosticLog.kt) : [log] fait un
  // `writeAsStringSync(flush: true)` par ligne, donc un appel système BLOQUANT
  // sur l'isolate — celui qui reçoit justement le flux PCM. Mesure déjà au
  // dossier (2026-07-25) : 22 à 32 écritures/s pour la seule instrumentation.
  // Tracer finement une latence avec ce mécanisme mesurerait l'instrumentation
  // elle-même.
  //
  // Ici : un ajout dans une liste (aucune I/O, aucun debugPrint, aucun
  // formatage de date — on stocke un écart en microsecondes), puis UNE seule
  // écriture au vidage, après la récitation.
  static final List<String> _trace = <String>[];
  static Stopwatch? _traceClock;

  /// Borne dure (~200k lignes) : au-delà on cesse d'ajouter plutôt que de
  /// risquer un OOM en pleine récitation.
  static const int _kTraceMax = 200000;

  static void traceReset() {
    _trace.clear();
    _traceClock = Stopwatch()..start();
  }

  static void trace(String step, String data) {
    if (!enabled || _trace.length >= _kTraceMax) return;
    final c = _traceClock ??= (Stopwatch()..start());
    final ms = c.elapsedMicroseconds ~/ 100;
    _trace.add('${ms ~/ 10}.${ms % 10}\t$step\t$data');
  }

  /// Écrit toute la trace accumulée en UNE ouverture de fichier. À appeler
  /// UNIQUEMENT hors récitation (fin de session).
  static int flushTrace() {
    final n = _trace.length;
    if (n == 0) return 0;
    final f = _file;
    if (f == null) {
      _trace.clear();
      return 0;
    }
    try {
      final sb = StringBuffer('--- TRACE DART ($n lignes) : ms\tetape\tdonnees ---\n');
      for (final l in _trace) {
        sb.write('D\t$l\n');
      }
      sb.write('--- FIN TRACE DART ---\n');
      f.writeAsStringSync(sb.toString(), mode: FileMode.append, flush: true);
    } catch (_) {
      // Jamais bloquant.
    }
    _trace.clear();
    return n;
  }

  static void log(String tag, String message) {
    // Sortie AVANT tout formatage : l'interpolation de chaîne est elle-même le
    // coût dominant sur les lignes verbeuses (GOP, TEXTDIFF).
    if (!enabled) return;
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
