import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'diagnostic_log.dart';

/// ARCHIVE DES SESSIONS DE RÉCITATION — la matière première du Coach.
///
/// Demande utilisateur (2026-08-06) : « le coach va se concentrer sur les
/// erreurs [...] on doit retravailler la partie coach pour se concentrer sur
/// tout ce qui est résultat », et, sur la question du coût de stockage, choix
/// explicite de l'option **verdicts + audio des mots non verts, ~1 Mo par
/// session, gardés une semaine**.
///
/// ── POURQUOI CE SERVICE EXISTE, alors que `RecitationErrorLogService` est
/// déjà là ──
///
/// Les deux ne répondent pas à la même question et ne doivent pas fusionner :
///
/// | service | question | granularité |
/// |---|---|---|
/// | `RecitationErrorLogService` | « sur quoi je me trompe, en général ? » | le MOT du Coran, cumulé sur toutes les sessions |
/// | celui-ci | « qu'est-ce que j'ai fait CE JOUR-LÀ, et comment ça sonnait ? » | la SESSION, avec sa voix |
///
/// Le premier agrège et ne meurt jamais (c'est une statistique). Le second est
/// un journal daté qui s'efface au bout d'une semaine, parce qu'il porte de
/// l'audio.
///
/// ── CE QUI A MOTIVÉ L'AUDIO PERSISTÉ ──
///
/// Constat utilisateur : « la première erreur, j'ai écouté ma voix et j'ai
/// corrigé, mais quand je voulais tester les autres, il n'y a plus de voix ».
/// Cause réelle, côté natif : la voix vit dans un ANNEAU de 300 s
/// (`ChaineRecitation.voixSurPlage`) et `v2ExtraitVoix` écrit toujours dans le
/// MÊME fichier de cache (`voix_extrait.wav`). Passé quelques minutes, ou dès
/// l'extrait suivant, le son du mot précédent n'existe plus nulle part.
/// L'écouter « plus tard » était donc structurellement impossible — ce n'est
/// pas un réglage à allonger, c'est un fichier à copier au moment où il
/// existe encore.
class SessionArchiveService {
  SessionArchiveService._();
  static final SessionArchiveService instance = SessionArchiveService._();

  static const int retentionJours = 7;

  Database? _db;
  Directory? _dossierAudio;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final chemin = p.join(await getDatabasesPath(), 'session_archive.db');
    return openDatabase(
      chemin,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            surah_number INTEGER,
            surah_name TEXT,
            from_ayah INTEGER,
            to_ayah INTEGER,
            preset TEXT,
            words_total INTEGER NOT NULL DEFAULT 0,
            words_green INTEGER NOT NULL DEFAULT 0,
            words_reached INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // Un mot NON VERT d'une session. `audio_path` peut être null : l'audio
        // est un bonus (l'anneau peut ne rien rendre), le verdict, lui, ne se
        // perd jamais.
        await db.execute('''
          CREATE TABLE session_words(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            word_index INTEGER NOT NULL,
            surah_number INTEGER,
            ayah_number INTEGER,
            word_in_ayah INTEGER,
            expected_word TEXT NOT NULL,
            heard_word TEXT,
            status TEXT NOT NULL,
            kind TEXT,
            audio_path TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_session_words ON session_words(session_id)');
      },
    );
  }

  Future<Directory> get _audioDir async {
    if (_dossierAudio != null) return _dossierAudio!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'archive_sessions'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dossierAudio = d;
  }

  int? _sessionCourante;
  int? get sessionCourante => _sessionCourante;

  /// Ouvre une session. Purge au passage ce qui a dépassé la rétention : c'est
  /// le seul moment où l'on est sûr que l'app est active et qu'aucune lecture
  /// d'archive n'est en cours.
  Future<int> demarrer({
    int? surahNumber,
    String? surahName,
    int? fromAyah,
    int? toAyah,
    String? preset,
  }) async {
    await purgerAnciennes();
    final db = await _database;
    _sessionCourante = await db.insert('sessions', {
      'started_at': DateTime.now().toIso8601String(),
      'surah_number': surahNumber,
      'surah_name': surahName,
      'from_ayah': fromAyah,
      'to_ayah': toAyah,
      'preset': preset,
    });
    DiagnosticLog.log('Archive',
        'session $_sessionCourante ouverte (sourate=$surahNumber $fromAyah-$toAyah)');
    return _sessionCourante!;
  }

  /// Ferme la session en cours en y inscrivant son bilan. [wordsReached] est
  /// l'ANCRE MAX (le dernier mot atteint), pas le nombre de mots jugés :
  /// compter sur les mots jugés ferait *baisser* le taux d'erreur à chaque mot
  /// perdu — piège documenté dans le skill d'analyse de session.
  Future<void> terminer({
    required int wordsTotal,
    required int wordsGreen,
    required int wordsReached,
  }) async {
    final id = _sessionCourante;
    if (id == null) return;
    final db = await _database;
    await db.update(
      'sessions',
      {
        'ended_at': DateTime.now().toIso8601String(),
        'words_total': wordsTotal,
        'words_green': wordsGreen,
        'words_reached': wordsReached,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    DiagnosticLog.log('Archive',
        'session $id fermee : $wordsGreen vert(s) / $wordsReached atteint(s)');
    _sessionCourante = null;
  }

  /// Archive un mot non vert. [audioSource] est le fichier RENDU PAR
  /// `v2ExtraitVoix` — volatil, réécrit à chaque extraction : il est COPIÉ
  /// ici, tout de suite. Passer null si l'extraction n'a rien donné (audio
  /// sorti de l'anneau) : le verdict est archivé quand même.
  Future<void> archiverMot({
    required int wordIndex,
    required String expectedWord,
    required String status,
    int? surahNumber,
    int? ayahNumber,
    int? wordInAyah,
    String? heardWord,
    String? kind,
    String? audioSource,
  }) async {
    final id = _sessionCourante;
    if (id == null) return;
    String? destination;
    if (audioSource != null) {
      try {
        final src = File(audioSource);
        if (await src.exists()) {
          final d = await _audioDir;
          destination = p.join(d.path, 's${id}_m$wordIndex.wav');
          await src.copy(destination);
        }
      } catch (e) {
        // L'audio est un bonus, jamais une condition : on garde le verdict.
        DiagnosticLog.log('Archive', 'copie audio impossible mot=$wordIndex : $e');
        destination = null;
      }
    }
    final db = await _database;
    await db.insert('session_words', {
      'session_id': id,
      'word_index': wordIndex,
      'surah_number': surahNumber,
      'ayah_number': ayahNumber,
      'word_in_ayah': wordInAyah,
      'expected_word': expectedWord,
      'heard_word': heardWord,
      'status': status,
      'kind': kind,
      'audio_path': destination,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Met à jour le bilan SANS fermer la session.
  ///
  /// Existe parce qu'une session peut mourir avec le processus : si le bilan
  /// n'était écrit qu'à la clôture, une récitation interrompue par un plantage
  /// ou par Android n'aurait aucun chiffre — elle apparaîtrait vide, ce qui
  /// est pire que pas de ligne du tout. Appelé périodiquement par l'écran
  /// (pas à chaque mot : c'est une écriture disque, elle n'a rien à faire dans
  /// le chemin de jugement).
  Future<void> majBilan({
    required int wordsTotal,
    required int wordsGreen,
    required int wordsReached,
  }) async {
    final id = _sessionCourante;
    if (id == null) return;
    final db = await _database;
    await db.update(
      'sessions',
      {
        'words_total': wordsTotal,
        'words_green': wordsGreen,
        'words_reached': wordsReached,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Ferme les sessions restées ouvertes (processus tué, écran quitté sans
  /// passer par un chemin de clôture).
  ///
  /// SANS CETTE RÉPARATION, UNE RÉCITATION DISPARAÎT PUREMENT ET SIMPLEMENT :
  /// la liste ne montre que `ended_at IS NOT NULL`, donc une session non
  /// fermée est invisible — exactement le défaut constaté par l'utilisateur le
  /// 2026-08-06 (« j'ai effectué une récitation, aucune n'est enregistrée »).
  /// La bonne réponse n'est pas d'ajouter un troisième hook de clôture en
  /// espérant les avoir tous : c'est de ne plus faire dépendre la VISIBILITÉ
  /// d'une fermeture propre.
  ///
  /// `ended_at` prend l'heure du dernier mot archivé si on en a un, sinon
  /// l'heure de début : ne jamais inventer une durée qu'on ne connaît pas.
  Future<int> reparerSessionsOuvertes() async {
    final db = await _database;
    final ouvertes = await db.query('sessions',
        columns: ['id', 'started_at'], where: 'ended_at IS NULL');
    if (ouvertes.isEmpty) return 0;
    var n = 0;
    for (final s in ouvertes) {
      final id = s['id'] as int;
      if (id == _sessionCourante) continue; // celle qui tourne, on n'y touche pas
      final dernier = await db.rawQuery(
          'SELECT MAX(created_at) AS t FROM session_words WHERE session_id = ?',
          [id]);
      final fin = (dernier.first['t'] as String?) ?? (s['started_at'] as String);
      await db.update('sessions', {'ended_at': fin},
          where: 'id = ?', whereArgs: [id]);
      n++;
    }
    if (n > 0) {
      DiagnosticLog.log('Archive', '$n session(s) laissee(s) ouverte(s) refermee(s)');
    }
    return n;
  }

  Future<List<SessionResume>> sessions({int limit = 40}) async {
    await reparerSessionsOuvertes();
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT s.*, (SELECT COUNT(*) FROM session_words w WHERE w.session_id = s.id) AS non_verts
      FROM sessions s
      WHERE s.ended_at IS NOT NULL
      ORDER BY s.started_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(SessionResume.fromMap).toList();
  }

  Future<List<MotArchive>> motsDeSession(int sessionId) async {
    final db = await _database;
    final rows = await db.query('session_words',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'word_index');
    return rows.map(MotArchive.fromMap).toList();
  }

  /// La plus RÉCENTE archive avec audio pour un mot précis (sourate/verset/
  /// position dans le verset), toutes sessions confondues.
  ///
  /// ── POURQUOI (2026-08-09) : fusion Coach hub ──────────────────────────
  /// Le volet "Mes erreurs" (cumul par sourate, `RecitationErrorLogService`)
  /// n'a jamais porté de voix -- seule l'archive par session en a. Demande
  /// utilisateur : « une seule liste fusionnée, groupée par sourate » --
  /// chaque mot fautif doit donc pouvoir retrouver SA voix la plus récente
  /// sans passer par un écran de session séparé. `word_in_ayah` existe déjà
  /// dans `session_words` (rempli par `karaoke_recitation_screen._archiverMotNonVert`
  /// / `_archiverOubli`), donc la recherche est directe.
  Future<MotArchive?> dernierMotAvecAudio(
      int surahNumber, int ayahNumber, int wordInAyah) async {
    final db = await _database;
    final rows = await db.query(
      'session_words',
      where: 'surah_number = ? AND ayah_number = ? AND word_in_ayah = ? '
          'AND audio_path IS NOT NULL',
      whereArgs: [surahNumber, ayahNumber, wordInAyah],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MotArchive.fromMap(rows.first);
  }

  /// Efface sessions et fichiers audio au-delà de la rétention. L'audio est
  /// supprimé AVANT la ligne : si l'app meurt entre les deux, on garde un
  /// fichier orphelin (récupéré au passage suivant par le balayage du
  /// dossier), jamais une ligne qui pointe vers un fichier disparu.
  Future<void> purgerAnciennes() async {
    final db = await _database;
    final limite = DateTime.now()
        .subtract(const Duration(days: retentionJours))
        .toIso8601String();
    final vieilles = await db
        .query('sessions', columns: ['id'], where: 'started_at < ?', whereArgs: [limite]);
    if (vieilles.isEmpty) return;
    final ids = vieilles.map((r) => r['id'] as int).toList();
    final marks = List.filled(ids.length, '?').join(',');
    final fichiers = await db.rawQuery(
        'SELECT audio_path FROM session_words WHERE session_id IN ($marks) AND audio_path IS NOT NULL',
        ids);
    for (final f in fichiers) {
      try {
        final file = File(f['audio_path'] as String);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Fichier déjà parti ou stockage indisponible : sans conséquence.
      }
    }
    await db.delete('session_words', where: 'session_id IN ($marks)', whereArgs: ids);
    await db.delete('sessions', where: 'id IN ($marks)', whereArgs: ids);
    DiagnosticLog.log('Archive',
        '${ids.length} session(s) de plus de $retentionJours jours purgee(s)');
  }

  /// Taille occupée par l'audio archivé, pour l'afficher à l'utilisateur —
  /// il a fixé lui-même le budget (~1 Mo par session), il doit pouvoir le
  /// vérifier plutôt que le croire.
  Future<int> octetsAudio() async {
    try {
      final d = await _audioDir;
      var total = 0;
      await for (final e in d.list()) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Supprime UNE session précise (demande utilisateur 2026-08-07 : « avoir
  /// la possibilité de supprimer le résultat d'une récitation »), avec son
  /// audio -- même ordre que [purgerAnciennes] (fichiers d'abord, lignes
  /// ensuite : un fichier orphelin après un plantage ne casse rien, une ligne
  /// qui pointe vers un fichier disparu si). Pas de `ON DELETE CASCADE`
  /// fiable ici (aucun `PRAGMA foreign_keys = ON` sur cette base,
  /// contrairement à `recitation_error_log_service.dart`) : les deux tables
  /// sont donc nettoyées explicitement.
  Future<void> supprimerSession(int sessionId) async {
    final db = await _database;
    final fichiers = await db.query('session_words',
        columns: ['audio_path'],
        where: 'session_id = ? AND audio_path IS NOT NULL',
        whereArgs: [sessionId]);
    for (final f in fichiers) {
      try {
        final chemin = f['audio_path'] as String?;
        if (chemin == null) continue;
        final file = File(chemin);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Fichier déjà parti ou stockage indisponible : sans conséquence.
      }
    }
    await db.delete('session_words', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    DiagnosticLog.log('Archive', 'session $sessionId supprimee (geste utilisateur)');
  }

  Future<void> toutEffacer() async {
    final db = await _database;
    await db.delete('session_words');
    await db.delete('sessions');
    try {
      final d = await _audioDir;
      await for (final e in d.list()) {
        if (e is File) await e.delete();
      }
    } catch (_) {}
  }
}

class SessionResume {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? surahNumber;
  final String? surahName;
  final int? fromAyah;
  final int? toAyah;
  final String? preset;
  final int wordsTotal;
  final int wordsGreen;
  final int wordsReached;
  final int nonVerts;

  const SessionResume({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.surahNumber,
    this.surahName,
    this.fromAyah,
    this.toAyah,
    this.preset,
    this.wordsTotal = 0,
    this.wordsGreen = 0,
    this.wordsReached = 0,
    this.nonVerts = 0,
  });

  /// Part de mots verts sur les mots RÉELLEMENT ATTEINTS (l'ancre max), pas
  /// sur la cible : s'arrêter au milieu d'une sourate n'est pas une erreur, et
  /// diviser par la cible ferait passer une récitation juste pour mauvaise.
  double? get reussite => wordsReached == 0 ? null : wordsGreen / wordsReached;

  factory SessionResume.fromMap(Map<String, Object?> m) => SessionResume(
        id: m['id'] as int,
        startedAt: DateTime.parse(m['started_at'] as String),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.parse(m['ended_at'] as String),
        surahNumber: m['surah_number'] as int?,
        surahName: m['surah_name'] as String?,
        fromAyah: m['from_ayah'] as int?,
        toAyah: m['to_ayah'] as int?,
        preset: m['preset'] as String?,
        wordsTotal: (m['words_total'] as int?) ?? 0,
        wordsGreen: (m['words_green'] as int?) ?? 0,
        wordsReached: (m['words_reached'] as int?) ?? 0,
        nonVerts: (m['non_verts'] as int?) ?? 0,
      );
}

class MotArchive {
  final int id;
  final int wordIndex;
  final int? surahNumber;
  final int? ayahNumber;
  final int? wordInAyah;
  final String expectedWord;
  final String? heardWord;
  final String status; // 'error' | 'unclear' | 'skipped'
  final String? kind;
  final String? audioPath;

  const MotArchive({
    required this.id,
    required this.wordIndex,
    required this.expectedWord,
    required this.status,
    this.surahNumber,
    this.ayahNumber,
    this.wordInAyah,
    this.heardWord,
    this.kind,
    this.audioPath,
  });

  factory MotArchive.fromMap(Map<String, Object?> m) => MotArchive(
        id: m['id'] as int,
        wordIndex: m['word_index'] as int,
        surahNumber: m['surah_number'] as int?,
        ayahNumber: m['ayah_number'] as int?,
        wordInAyah: m['word_in_ayah'] as int?,
        expectedWord: m['expected_word'] as String,
        heardWord: m['heard_word'] as String?,
        status: m['status'] as String,
        kind: m['kind'] as String?,
        audioPath: m['audio_path'] as String?,
      );
}
