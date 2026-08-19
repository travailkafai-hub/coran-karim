import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/verse.dart';
import 'mp3quran_api.dart';
import 'quran_api.dart';

/// Téléchargement hors-ligne de l'audio de récitation, sourate par sourate.
///
/// Pourquoi la sourate et pas le récitateur comme unité : mesuré le 2026-07-28
/// sur l'API réelle (HEAD sur les 6236 fichiers échantillonnés 1/6), un
/// récitateur complet pèse **1,61 Go** (271 ko/verset en moyenne), et la
/// distribution est très déséquilibrée — Al-Baqara à elle seule fait 125 Mo
/// quand les 20 sourates les plus courtes tiennent sous 1 Mo. Imposer 1,6 Go à
/// qui ne veut qu'Al-Kahf (30 Mo) serait absurde. Le téléchargement complet
/// reste possible : il enfile simplement les 114 sourates.
///
/// Emplacement : stockage privé de l'app (`getApplicationDocumentsDirectory`),
/// choix utilisateur 2026-07-28. Aucune permission Android à demander, au prix
/// d'une ligne « données d'application » volumineuse dans les réglages système
/// et d'un effacement à la désinstallation.
///
/// Disposition sur disque :
///   `<docs>/recitations/<reciterId>/<sss>/<sss><aaa>.mp3`
///   `<docs>/recitations/<reciterId>/<sss>/.complete`  ← marqueur de fin
///
/// Le marqueur `.complete` est écrit UNIQUEMENT quand les `versesCount`
/// fichiers sont sur le disque. Sans lui, un téléchargement interrompu
/// laisserait un dossier à moitié plein qu'on croirait complet : la lecture
/// retomberait alors silencieusement en streaming au milieu d'une sourate,
/// exactement le symptôme qu'on cherche à supprimer.
class ReciterDownloadService {
  static final ReciterDownloadService _i = ReciterDownloadService._();
  factory ReciterDownloadService() => _i;
  ReciterDownloadService._();

  /// Nombre de fichiers téléchargés en parallèle. 4 est un compromis :
  /// assez pour saturer une connexion mobile correcte, assez peu pour ne pas
  /// marteler `verses.quran.com` ni faire exploser la mémoire sur les grosses
  /// sourates (286 fichiers pour Al-Baqara).
  static const _kParallel = 4;

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    responseType: ResponseType.bytes,
  ));

  Directory? _root;

  /// Progression des téléchargements en cours, diffusée à l'IHM.
  final _progressCtrl = StreamController<SurahDownloadProgress>.broadcast();
  Stream<SurahDownloadProgress> get progressStream => _progressCtrl.stream;

  /// Téléchargements en cours, clés `<reciterId>:<surah>`. Sert à la fois à
  /// l'annulation et à empêcher qu'un double appui lance deux fois la même
  /// sourate.
  final _active = <String, CancelToken>{};

  String _key(int reciterId, int surah) => '$reciterId:$surah';

  bool isDownloading(int reciterId, int surah) =>
      _active.containsKey(_key(reciterId, surah));

  Future<Directory> _rootDir() async {
    final cached = _root;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/recitations');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _root = dir;
  }

  /// Chemin du dossier d'une sourate. Synchrone une fois [_rootDir] résolu.
  String _surahDirPath(String rootPath, int reciterId, int surah) =>
      '$rootPath/$reciterId/${surah.toString().padLeft(3, '0')}';

  static String _fileName(int surah, int ayah) =>
      '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';

  /// Nom du fichier SOURATE ENTIÈRE (source MP3Quran), dans le même dossier
  /// que les fichiers par verset de la source quran.com.
  ///
  /// ── POURQUOI LA MÊME ARBORESCENCE (2026-08-17) ──────────────────────────
  /// Les deux sources ne découpent pas pareil : quran.com sert un mp3 PAR
  /// VERSET, MP3Quran un seul fichier PAR SOURATE. La tentation serait un
  /// second dossier -- ce serait aussi un second système à gérer, et l'écran
  /// de gestion (taille occupée, suppression par sourate, par récitateur) ne
  /// verrait jamais ces fichiers.
  ///
  /// En les rangeant DANS le dossier de la sourate, tout ce qui existe déjà
  /// continue de fonctionner sans une ligne de plus : `bytesUsed` somme les
  /// fichiers du dossier, `deleteSurah` supprime le dossier, `deleteReciter`
  /// l'arborescence, et `downloadedSurahs` lit le marqueur `.complete` que
  /// les deux chemins écrivent de la même façon.
  static const _fichierSourateEntiere = 'sourate.mp3';

  // ── Lecture : ce que le lecteur audio interroge ────────────────────────────

  /// Racine résolue une fois pour toutes, pour que [localPathIfPresent] reste
  /// synchrone sur le chemin chaud de la lecture.
  String? _rootPathSync;

  /// À appeler une fois au démarrage. Sans ça, [localPathIfPresent] renvoie
  /// toujours null et tout repasse en streaming — silencieusement.
  Future<void> ensureReady() async {
    _rootPathSync = (await _rootDir()).path;
  }

  /// Chemin local du verset s'il est présent sur le disque, sinon null.
  ///
  /// Synchrone et volontairement tolérant : en cas de doute on renvoie null,
  /// c'est-à-dire « repli sur le streaming ». Un faux négatif coûte une requête
  /// réseau ; un faux positif ferait échouer la lecture.
  String? localPathIfPresent(int reciterId, Verse verse) {
    final root = _rootPathSync;
    if (root == null) return null;
    final path =
        '${_surahDirPath(root, reciterId, verse.surahNumber)}/${_fileName(verse.surahNumber, verse.ayahNumber)}';
    return File(path).existsSync() ? path : null;
  }

  /// Chemin du fichier SOURATE ENTIÈRE gardé sur le disque, ou `null`.
  ///
  /// C'est ce que `Mp3QuranApi.fichierLocalSourate` interroge EN PREMIER : un
  /// audio que l'utilisateur a explicitement demandé à garder ne doit jamais
  /// être retéléchargé, ni pour écouter, ni pour corriger un mot.
  ///
  /// Synchrone, et volontairement tolérant comme [localPathIfPresent] : en
  /// cas de doute on rend `null`, donc on retombe sur le téléchargement. Un
  /// faux négatif coûte du réseau ; un faux positif ferait échouer la lecture.
  String? sourateLocaleSiPresente(int reciterId, int surah) {
    final root = _rootPathSync;
    if (root == null) return null;
    final p = '${_surahDirPath(root, reciterId, surah)}/$_fichierSourateEntiere';
    final f = File(p);
    return (f.existsSync() && f.lengthSync() > 0) ? p : null;
  }

  /// Télécharge la sourate ENTIÈRE depuis MP3Quran et la garde durablement.
  ///
  /// Distinct de [downloadSurah] (un fichier par verset, source quran.com) :
  /// MP3Quran ne sert qu'un seul fichier par sourate. Le marqueur `.complete`
  /// est écrit de la même façon, donc l'écran de gestion ne voit aucune
  /// différence entre les deux origines.
  ///
  /// Mêmes garde-fous que `Mp3QuranApi.fichierLocalSourate`, et pour les mêmes
  /// raisons mesurées : comparaison à `content-length` (un téléchargement
  /// tronqué de 120 Mo avait été accepté en silence, cf. son commentaire) et
  /// écriture `.part` puis `rename`.
  Future<bool> telechargerSourateMp3Quran(int reciterId, int surah) async {
    final k = _key(reciterId, surah);
    if (_active.containsKey(k)) return false;

    final root = await _rootDir();
    final dirPath = _surahDirPath(root.path, reciterId, surah);
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final cible = File('$dirPath/$_fichierSourateEntiere');
    final marker = File('$dirPath/.complete');
    if (cible.existsSync() && cible.lengthSync() > 0 && marker.existsSync()) {
      return true;
    }

    final cancel = CancelToken();
    _active[k] = cancel;
    _emit(reciterId, surah, 0, 1, DownloadPhase.running);
    try {
      final url = Mp3QuranApi.urlSourate(reciterId, surah);
      final r = await _dio.get<List<int>>(url,
          cancelToken: cancel,
          options: Options(responseType: ResponseType.bytes));
      final bytes = r.data;
      if (bytes == null || bytes.isEmpty) {
        _emit(reciterId, surah, 0, 1, DownloadPhase.failed);
        return false;
      }
      final annonce = r.headers.value('content-length');
      final attendu = annonce == null ? null : int.tryParse(annonce);
      if (attendu != null && bytes.length != attendu) {
        _emit(reciterId, surah, 0, 1, DownloadPhase.failed);
        return false;
      }
      final tmp = File('$dirPath/$_fichierSourateEntiere.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(cible.path);
      await marker.writeAsString('ok');
      _emit(reciterId, surah, 1, 1, DownloadPhase.complete);
      return true;
    } catch (_) {
      _emit(reciterId, surah, 0, 1, DownloadPhase.failed);
      return false;
    } finally {
      _active.remove(k);
    }
  }

  // ── État : ce que l'écran de gestion affiche ───────────────────────────────

  /// Sourates complètes pour ce récitateur (présence du marqueur `.complete`).
  Future<Set<int>> downloadedSurahs(int reciterId) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/$reciterId');
    if (!dir.existsSync()) return {};
    final out = <int>{};
    for (final e in dir.listSync()) {
      if (e is! Directory) continue;
      final n = int.tryParse(e.path.split('/').last);
      if (n != null && File('${e.path}/.complete').existsSync()) out.add(n);
    }
    return out;
  }

  /// Octets réellement occupés par ce récitateur sur le disque.
  Future<int> bytesUsed(int reciterId) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}/$reciterId');
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }

  /// Octets occupés par tous les récitateurs confondus.
  Future<int> bytesUsedTotal() async {
    final root = await _rootDir();
    var total = 0;
    for (final e in root.listSync(recursive: true)) {
      if (e is File) total += e.lengthSync();
    }
    return total;
  }

  /// Octets par caractère de `text_uthmani`, pour annoncer une taille AVANT
  /// téléchargement sans aucun appel réseau.
  ///
  /// Calibré le 2026-07-28 contre la mesure réelle (HEAD sur l'API, 1 verset
  /// sur 6 des 114 sourates) : erreur médiane 11,9 %, total estimé 1,60 Go
  /// contre 1,61 Go mesuré. Le nombre de VERSETS serait un bien plus mauvais
  /// prédicteur — 397 ko/verset en sourate 2 contre 112 ko en sourate 78 — là
  /// où la longueur du texte suit la durée récitée, donc la taille du mp3.
  ///
  /// Reste une estimation : le débit varie d'un récitateur à l'autre (mesure
  /// faite sur Al-Afasy), d'où l'affichage systématiquement préfixé « ≈ ».
  static const _kBytesPerChar = 2414;

  Future<int> estimatedBytes(int surahNumber) async {
    final verses = await QuranApi.fetchVerses(surahNumber);
    var chars = 0;
    for (final v in verses) {
      chars += v.textUthmani.length;
    }
    return chars * _kBytesPerChar;
  }

  /// Taille approximative d'un récitateur complet (~1,6 Go).
  Future<int> estimatedBytesAll() async {
    var total = 0;
    for (var s = 1; s <= 114; s++) {
      total += await estimatedBytes(s);
    }
    return total;
  }

  // ── Téléchargement ─────────────────────────────────────────────────────────

  /// Télécharge une sourate entière. Idempotent et reprenable : les fichiers
  /// déjà présents sont sautés, donc relancer après une coupure réseau ne
  /// retélécharge que ce qui manque.
  ///
  /// Renvoie true si la sourate est complète à la sortie.
  Future<bool> downloadSurah(int reciterId, int surah) async {
    // MP3Quran ne sert qu'un fichier par SOURATE : router vers le chemin
    // dédié (2026-08-17). Sans ce branchement, ce service serait resté sur
    // `QuranApi.fetchSurahAudioUrls`, c'est-à-dire sur Quran Foundation --
    // la dépendance que le reste de l'app a précisément supprimée. Garder un
    // service de téléchargement branché dessus l'aurait fait revenir par la
    // porte de derrière, au moment même où l'utilisateur croit télécharger
    // depuis la source qu'il a choisie.
    if (Mp3QuranApi.sertCeReciter(reciterId)) {
      return telechargerSourateMp3Quran(reciterId, surah);
    }
    final k = _key(reciterId, surah);
    if (_active.containsKey(k)) return false;

    final root = await _rootDir();
    final dirPath = _surahDirPath(root.path, reciterId, surah);
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final marker = File('$dirPath/.complete');
    if (marker.existsSync()) return true;

    final cancel = CancelToken();
    _active[k] = cancel;

    var done = 0;
    var total = 0;
    try {
      final urls = await QuranApi.fetchSurahAudioUrls(reciterId, surah);
      final verses = await QuranApi.fetchVerses(surah);
      total = verses.length;
      _emit(reciterId, surah, 0, total, DownloadPhase.running);

      // File d'attente consommée par [_kParallel] ouvriers : garde le
      // parallélisme constant même quand les fichiers ont des tailles très
      // différentes (74 ko à 832 ko selon le verset).
      final queue = List<Verse>.from(verses);
      var failed = false;

      Future<void> worker() async {
        while (queue.isNotEmpty && !cancel.isCancelled && !failed) {
          final v = queue.removeAt(0);
          final target = File('$dirPath/${_fileName(surah, v.ayahNumber)}');
          if (target.existsSync() && target.lengthSync() > 0) {
            _emit(reciterId, surah, ++done, total, DownloadPhase.running);
            continue;
          }
          final url = urls[v.key];
          if (url == null) {
            failed = true;
            return;
          }
          try {
            final r = await _dio.get<List<int>>(url, cancelToken: cancel);
            final bytes = r.data;
            if (bytes == null || bytes.isEmpty) {
              failed = true;
              return;
            }
            // Écriture sous nom temporaire puis renommage : un fichier
            // partiellement écrit (batterie coupée, process tué) ne doit
            // jamais être pris pour un fichier valide par la lecture.
            final tmp = File('${target.path}.part');
            await tmp.writeAsBytes(bytes, flush: true);
            await tmp.rename(target.path);
            _emit(reciterId, surah, ++done, total, DownloadPhase.running);
          } on DioException catch (e) {
            if (CancelToken.isCancel(e)) return;
            failed = true;
            return;
          }
        }
      }

      await Future.wait(List.generate(_kParallel, (_) => worker()));

      if (cancel.isCancelled) {
        _emit(reciterId, surah, done, total, DownloadPhase.cancelled);
        return false;
      }
      if (failed) {
        _emit(reciterId, surah, done, total, DownloadPhase.failed);
        return false;
      }
      // Marqueur écrit seulement si le compte y est (cf. commentaire de tête).
      final present = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp3'))
          .length;
      if (present < total) {
        _emit(reciterId, surah, present, total, DownloadPhase.failed);
        return false;
      }
      await marker.writeAsString('$total');
      _emit(reciterId, surah, total, total, DownloadPhase.complete);
      return true;
    } catch (_) {
      _emit(reciterId, surah, done, total, DownloadPhase.failed);
      return false;
    } finally {
      _active.remove(k);
    }
  }

  /// Annule le téléchargement en cours de cette sourate. Les fichiers déjà
  /// écrits sont conservés : une relance reprendra là où on s'est arrêté.
  void cancel(int reciterId, int surah) {
    _active[_key(reciterId, surah)]?.cancel('annulé par l\'utilisateur');
  }

  void cancelAll() {
    for (final t in _active.values) {
      t.cancel('annulé par l\'utilisateur');
    }
  }

  /// Supprime une sourate téléchargée (fichiers + marqueur).
  Future<void> deleteSurah(int reciterId, int surah) async {
    cancel(reciterId, surah);
    final root = await _rootDir();
    final dir = Directory(_surahDirPath(root.path, reciterId, surah));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _emit(reciterId, surah, 0, 0, DownloadPhase.absent);
  }

  /// Supprime tout l'audio téléchargé d'un récitateur.
  Future<void> deleteReciter(int reciterId) async {
    cancelAll();
    final root = await _rootDir();
    final dir = Directory('${root.path}/$reciterId');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _emit(reciterId, 0, 0, 0, DownloadPhase.absent);
  }

  void _emit(int reciterId, int surah, int done, int total, DownloadPhase p) {
    if (_progressCtrl.isClosed) return;
    _progressCtrl.add(SurahDownloadProgress(
      reciterId: reciterId,
      surahNumber: surah,
      done: done,
      total: total,
      phase: p,
    ));
  }
}

enum DownloadPhase { absent, running, complete, failed, cancelled }

class SurahDownloadProgress {
  final int reciterId;
  final int surahNumber;
  final int done;
  final int total;
  final DownloadPhase phase;

  const SurahDownloadProgress({
    required this.reciterId,
    required this.surahNumber,
    required this.done,
    required this.total,
    required this.phase,
  });

  double get fraction => total == 0 ? 0 : done / total;
}
