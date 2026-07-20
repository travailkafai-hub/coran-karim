import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/recitation_state.dart' show RecitationErrorKind;

RecitationErrorKind _kindFromDb(String? v) => switch (v) {
      'lettre' => RecitationErrorKind.lettre,
      'harakat' => RecitationErrorKind.harakat,
      'tajwid' => RecitationErrorKind.tajwid,
      'saute' => RecitationErrorKind.saute,
      _ => RecitationErrorKind.inconnu,
    };

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
  // Nature de l'erreur (lettre / harakat / tajwid / sauté), calculée au moment
  // du jugement par RecitationNotifier.classifyError -- demande utilisateur
  // 2026-07-20 : « catégoriser par type : tajwid ou prononciation ».
  // `inconnu` pour les entrées ANTÉRIEURES à cette version (colonne ajoutée en
  // migration v2, valeur par défaut) : ne pas les compter comme du tajwid.
  final RecitationErrorKind kind;

  const RecitationErrorEntry({
    required this.id,
    required this.surahNumber,
    required this.ayahNumber,
    required this.wordIndex,
    required this.expectedWord,
    required this.createdAt,
    this.kind = RecitationErrorKind.inconnu,
  });

  factory RecitationErrorEntry.fromMap(Map<String, Object?> m) =>
      RecitationErrorEntry(
        id: m['id'] as int,
        surahNumber: m['surah_number'] as int,
        ayahNumber: m['ayah_number'] as int,
        wordIndex: m['word_index'] as int,
        expectedWord: m['expected_word'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        kind: _kindFromDb(m['kind'] as String?),
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
      // v2 (2026-07-20) : ajout de `kind` (type d'erreur). Migration NON
      // destructive -- les erreurs déjà journalisées sont conservées et
      // restent lisibles ; elles ressortent simplement en « indéterminé »,
      // puisqu'on ne peut pas reconstruire après coup ce qui avait été
      // entendu. Ne jamais recréer la table : ce journal est l'historique
      // réel de l'utilisateur.
      version: 2,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE recitation_errors(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          surah_number INTEGER NOT NULL,
          ayah_number INTEGER NOT NULL,
          word_index INTEGER NOT NULL,
          expected_word TEXT NOT NULL,
          created_at TEXT NOT NULL,
          kind TEXT
        )
      '''),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE recitation_errors ADD COLUMN kind TEXT');
        }
      },
    );
  }

  Future<void> logError({
    required int surahNumber,
    required int ayahNumber,
    required int wordIndex,
    required String expectedWord,
    RecitationErrorKind kind = RecitationErrorKind.inconnu,
  }) async {
    final db = await _database;
    await db.insert('recitation_errors', {
      'surah_number': surahNumber,
      'ayah_number': ayahNumber,
      'word_index': wordIndex,
      'expected_word': expectedWord,
      'created_at': DateTime.now().toIso8601String(),
      'kind': kind.name,
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

  /// Répartition des erreurs par TYPE (demande utilisateur 2026-07-20).
  /// Optionnellement restreinte à une sourate.
  Future<Map<RecitationErrorKind, int>> errorCountsByKind({int? surahNumber}) async {
    final db = await _database;
    final rows = await db.rawQuery(
      surahNumber == null
          ? 'SELECT kind, COUNT(*) as count FROM recitation_errors GROUP BY kind'
          : 'SELECT kind, COUNT(*) as count FROM recitation_errors '
              'WHERE surah_number = ? GROUP BY kind',
      surahNumber == null ? null : [surahNumber],
    );
    final out = <RecitationErrorKind, int>{};
    for (final m in rows) {
      final k = _kindFromDb(m['kind'] as String?);
      out[k] = (out[k] ?? 0) + (m['count'] as int);
    }
    return out;
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
