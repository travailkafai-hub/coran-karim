import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Une erreur de récitation journalisée : un mot verrouillé rouge, avec sa
/// position exacte dans le Coran (sourate/verset/mot), pour analyse a
/// posteriori par le Coach IA.
class RecitationErrorEntry {
  final int id;
  final int surahNumber;
  final int ayahNumber;
  final int wordIndex; // index du mot DANS le verset (0-based)
  final String expectedWord; // texte attendu, avec harakat
  final DateTime createdAt;

  const RecitationErrorEntry({
    required this.id,
    required this.surahNumber,
    required this.ayahNumber,
    required this.wordIndex,
    required this.expectedWord,
    required this.createdAt,
  });

  factory RecitationErrorEntry.fromMap(Map<String, Object?> m) =>
      RecitationErrorEntry(
        id: m['id'] as int,
        surahNumber: m['surah_number'] as int,
        ayahNumber: m['ayah_number'] as int,
        wordIndex: m['word_index'] as int,
        expectedWord: m['expected_word'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// Nombre d'erreurs journalisées pour un verset donné.
class AyahErrorCount {
  final int surahNumber;
  final int ayahNumber;
  final int count;

  const AyahErrorCount({
    required this.surahNumber,
    required this.ayahNumber,
    required this.count,
  });
}

/// Journal persistant des erreurs de récitation (mots verrouillés rouges).
///
/// Alimente le futur Coach IA : chaque erreur reste en base au-delà de la
/// session (contrairement à [RecitationSessionState], purement en mémoire),
/// pour qu'un modèle puisse plus tard les analyser et les expliquer.
class RecitationErrorLogService {
  RecitationErrorLogService._();
  static final RecitationErrorLogService instance = RecitationErrorLogService._();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'coran_karim.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE recitation_errors(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          surah_number INTEGER NOT NULL,
          ayah_number INTEGER NOT NULL,
          word_index INTEGER NOT NULL,
          expected_word TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      '''),
    );
  }

  Future<void> logError({
    required int surahNumber,
    required int ayahNumber,
    required int wordIndex,
    required String expectedWord,
  }) async {
    final db = await _database;
    await db.insert('recitation_errors', {
      'surah_number': surahNumber,
      'ayah_number': ayahNumber,
      'word_index': wordIndex,
      'expected_word': expectedWord,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Erreurs les plus récentes d'abord.
  Future<List<RecitationErrorEntry>> recentErrors({int limit = 200}) async {
    final db = await _database;
    final rows = await db.query(
      'recitation_errors',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(RecitationErrorEntry.fromMap).toList();
  }

  /// Comptage d'erreurs par verset, pour le tableau de bord du Coach IA
  /// (les versets les plus fautifs en premier).
  Future<List<AyahErrorCount>> errorCountsByAyah() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT surah_number, ayah_number, COUNT(*) as count
      FROM recitation_errors
      GROUP BY surah_number, ayah_number
      ORDER BY count DESC
    ''');
    return rows
        .map((m) => AyahErrorCount(
              surahNumber: m['surah_number'] as int,
              ayahNumber: m['ayah_number'] as int,
              count: m['count'] as int,
            ))
        .toList();
  }

  Future<List<RecitationErrorEntry>> errorsForAyah(
      int surahNumber, int ayahNumber) async {
    final db = await _database;
    final rows = await db.query(
      'recitation_errors',
      where: 'surah_number = ? AND ayah_number = ?',
      whereArgs: [surahNumber, ayahNumber],
      orderBy: 'created_at DESC',
    );
    return rows.map(RecitationErrorEntry.fromMap).toList();
  }
}
