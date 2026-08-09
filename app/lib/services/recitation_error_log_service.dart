import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/judgement_options.dart' show TajwidRule;
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
  // Texte du mot SUIVANT (avec harakat), rempli UNIQUEMENT quand ce mot est
  // "frontière" (RuleAnnotationService.isBoundaryWord) -- demande utilisateur
  // 2026-07-22 : « le double de mots comme ikhafa c'est entre deux mots ».
  // null pour toute règle qui ne concerne qu'un seul mot, et pour les entrées
  // antérieures à la migration v4.
  final String? pairWord;
  // Règles de tajwid précises non réalisées sur ce mot (table enfant
  // recitation_error_rules) -- vide si `kind != tajwid` ou entrée antérieure
  // à la migration v3 (colonne/table alors inexistante).
  final List<TajwidRule> rules;

  const RecitationErrorEntry({
    required this.id,
    required this.surahNumber,
    required this.ayahNumber,
    required this.wordIndex,
    required this.expectedWord,
    required this.createdAt,
    this.kind = RecitationErrorKind.inconnu,
    this.pairWord,
    this.rules = const [],
  });

  factory RecitationErrorEntry.fromMap(Map<String, Object?> m,
          {List<TajwidRule> rules = const []}) =>
      RecitationErrorEntry(
        id: m['id'] as int,
        surahNumber: m['surah_number'] as int,
        ayahNumber: m['ayah_number'] as int,
        wordIndex: m['word_index'] as int,
        expectedWord: m['expected_word'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        kind: _kindFromDb(m['kind'] as String?),
        pairWord: m['pair_word'] as String?,
        rules: rules,
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
      // v3 (2026-07-22) : table enfant `recitation_error_rules` -- QUELLE(S)
      // règle(s) de tajwid précise(s) étaient attendues et non détectées sur
      // un mot classé `tajwid` (demande utilisateur : stats par règle, pas
      // seulement un compteur global). Table à part plutôt qu'une colonne
      // `rule` unique sur `recitation_errors` : un même mot peut porter
      // PLUSIEURS règles simultanément (constaté sur device 2026-07-22, ex.
      // "وَشَفَتَيْنِ" -> idgham_ghunnah ET madda_permissible manquées
      // ensemble) -- une colonne unique aurait forcé soit à choisir
      // arbitrairement laquelle garder, soit à concaténer une chaîne
      // illisible en SQL pour l'agrégation. Migration NON destructive comme
      // la v2 : les erreurs déjà journalisées (v1/v2) n'ont simplement aucune
      // ligne enfant, elles comptent toujours dans le total et par type,
      // juste pas dans le détail par règle.
      // v4 (2026-07-22) : colonne `pair_word` -- afficher la PAIRE de mots
      // pour les règles à cheval sur deux mots (ikhafa/iqlab/idgham...) au
      // lieu d'un seul mot isolé (demande utilisateur). Nullable : ne
      // s'applique qu'aux règles "frontière" (cf. RuleAnnotationService.
      // isBoundaryWord), null pour toutes les autres et pour les entrées
      // antérieures.
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recitation_errors(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            surah_number INTEGER NOT NULL,
            ayah_number INTEGER NOT NULL,
            word_index INTEGER NOT NULL,
            expected_word TEXT NOT NULL,
            created_at TEXT NOT NULL,
            kind TEXT,
            pair_word TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE recitation_error_rules(
            error_id INTEGER NOT NULL,
            rule TEXT NOT NULL,
            FOREIGN KEY(error_id) REFERENCES recitation_errors(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_error_rules_error_id ON recitation_error_rules(error_id)');
        await db.execute(
            'CREATE INDEX idx_error_rules_rule ON recitation_error_rules(rule)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE recitation_errors ADD COLUMN kind TEXT');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE recitation_error_rules(
              error_id INTEGER NOT NULL,
              rule TEXT NOT NULL,
              FOREIGN KEY(error_id) REFERENCES recitation_errors(id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_error_rules_error_id ON recitation_error_rules(error_id)');
          await db.execute(
              'CREATE INDEX idx_error_rules_rule ON recitation_error_rules(rule)');
        }
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE recitation_errors ADD COLUMN pair_word TEXT');
        }
      },
      onConfigure: (db) async {
        // ON DELETE CASCADE ci-dessus n'a d'effet que si les clés étrangères
        // sont explicitement activées -- SQLite les ignore par défaut.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// [rules] : règles de tajwid précises non réalisées sur ce mot (cf.
  /// RecitationNotifier.unrealizedRulesFor) -- n'a de sens que pour
  /// `kind == RecitationErrorKind.tajwid`, ignoré sinon. Une ligne enfant par
  /// règle (cf. schéma v3) : un mot peut en manquer plusieurs à la fois.
  Future<void> logError({
    required int surahNumber,
    required int ayahNumber,
    required int wordIndex,
    required String expectedWord,
    RecitationErrorKind kind = RecitationErrorKind.inconnu,
    List<TajwidRule> rules = const [],
    String? pairWord,
  }) async {
    final db = await _database;
    final id = await db.insert('recitation_errors', {
      'surah_number': surahNumber,
      'ayah_number': ayahNumber,
      'word_index': wordIndex,
      'expected_word': expectedWord,
      'created_at': DateTime.now().toIso8601String(),
      'kind': kind.name,
      'pair_word': pairWord,
    });
    if (kind == RecitationErrorKind.tajwid && rules.isNotEmpty) {
      final batch = db.batch();
      for (final r in rules) {
        batch.insert('recitation_error_rules', {'error_id': id, 'rule': r.key});
      }
      await batch.commit(noResult: true);
    }
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

  /// Détail par mot, avec ses règles précises jointes (cf. RecitationErrorEntry
  /// .rules) -- demande utilisateur 2026-07-22 : afficher le mot + type
  /// d'erreur en détail, pas seulement un compteur agrégé par verset.
  Future<List<RecitationErrorEntry>> errorsForAyah(
      int surahNumber, int ayahNumber) async {
    final db = await _database;
    final rows = await db.query(
      'recitation_errors',
      where: 'surah_number = ? AND ayah_number = ?',
      whereArgs: [surahNumber, ayahNumber],
      orderBy: 'created_at DESC',
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((m) => m['id'] as int).toList();
    final ruleRows = await db.query(
      'recitation_error_rules',
      where: 'error_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
    final rulesByError = <int, List<TajwidRule>>{};
    for (final r in ruleRows) {
      final rule = TajwidRule.fromKey(r['rule'] as String);
      if (rule == null) continue;
      (rulesByError[r['error_id'] as int] ??= []).add(rule);
    }
    return rows
        .map((m) => RecitationErrorEntry.fromMap(m,
            rules: rulesByError[m['id'] as int] ?? const []))
        .toList();
  }

  /// Répartition des erreurs de type tajwid PAR RÈGLE PRÉCISE (demande
  /// utilisateur 2026-07-22), optionnellement restreinte à une sourate.
  /// Clés inconnues (`TajwidRule.fromKey` renvoie null -- ne devrait pas
  /// arriver puisqu'on écrit toujours `TajwidRule.key`, mais une règle a pu
  /// être renommée côté modèle depuis) sont ignorées plutôt que de planter.
  Future<Map<TajwidRule, int>> errorCountsByRule({int? surahNumber}) async {
    final db = await _database;
    final rows = await db.rawQuery(
      surahNumber == null
          ? '''
            SELECT er.rule as rule, COUNT(*) as count
            FROM recitation_error_rules er
            GROUP BY er.rule
          '''
          : '''
            SELECT er.rule as rule, COUNT(*) as count
            FROM recitation_error_rules er
            JOIN recitation_errors e ON e.id = er.error_id
            WHERE e.surah_number = ?
            GROUP BY er.rule
          ''',
      surahNumber == null ? null : [surahNumber],
    );
    final out = <TajwidRule, int>{};
    for (final m in rows) {
      final rule = TajwidRule.fromKey(m['rule'] as String);
      if (rule == null) continue;
      out[rule] = (out[rule] ?? 0) + (m['count'] as int);
    }
    return out;
  }

  /// Efface DÉFINITIVEMENT tout le journal d'erreurs (demande utilisateur
  /// 2026-07-22 : « remettre à zéro ces stats »). Irréversible -- l'appelant
  /// UI doit confirmer avant d'appeler ceci, ce n'est pas fait ici.
  Future<void> resetAll() async {
    final db = await _database;
    await db.delete('recitation_error_rules');
    await db.delete('recitation_errors');
  }

  /// Efface les erreurs d'UNE sourate (demande utilisateur 2026-07-23 :
  /// « si je veux réciter une sourate, elle met à zéro les stats de cette
  /// sourate »). Appelé AUTOMATIQUEMENT au démarrage d'une récitation, pour
  /// que les stats reflètent la TENTATIVE EN COURS et non un cumul de toutes
  /// les récitations passées -- sinon les compteurs ne font que croître et on
  /// ne voit jamais si on progresse. Les autres sourates ne sont pas touchées.
  ///
  /// Les lignes de `recitation_error_rules` suivent via ON DELETE CASCADE
  /// (PRAGMA foreign_keys activé dans onConfigure).
  Future<void> clearSurah(int surahNumber) async {
    final db = await _database;
    await db.delete('recitation_errors',
        where: 'surah_number = ?', whereArgs: [surahNumber]);
  }

  /// Retire l'entrée la PLUS RÉCENTE pour ce mot précis (demande utilisateur
  /// 2026-08-07 : le pouce vers le bas de la feuille "Ma voix" conteste un
  /// verdict -- le journal ne doit pas garder une erreur que l'utilisateur a
  /// lui-même invalidée, sous peine de fausser les stats du Coach avec un
  /// faux positif connu comme tel). `logError` est appelé SANS condition à
  /// chaque jugement (`karaoke_recitation_screen.dart`) ; c'est CETTE entrée,
  /// la dernière pour (sourate, verset, mot), qu'on retire -- jamais un
  /// historique plus ancien du même mot lors d'une session précédente.
  Future<void> removeLatestError({
    required int surahNumber,
    required int ayahNumber,
    required int wordIndex,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'recitation_errors',
      columns: ['id'],
      where: 'surah_number = ? AND ayah_number = ? AND word_index = ?',
      whereArgs: [surahNumber, ayahNumber, wordIndex],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.delete('recitation_errors', where: 'id = ?', whereArgs: [rows.first['id']]);
  }
}
