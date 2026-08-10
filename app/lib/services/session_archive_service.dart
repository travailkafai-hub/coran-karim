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
      version: 2,
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
        await _creerTablesPortions(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2 (2026-08-10) : suivi PERMANENT par sourate/Hizb, à côté de
        // `sessions`/`session_words` qui restent le journal daté par
        // tentative (7 jours, inchangé). Aucune table existante n'est
        // touchée : pas de perte des sessions déjà archivées.
        if (oldVersion < 2) {
          await _creerTablesPortions(db);
        }
      },
    );
  }

  /// Tables du suivi permanent (cf. le plan "Suivi permanent par
  /// sourate/Hizb dans Coach"). `portions` = une ligne par portion suivie
  /// (sourate entière, ou tranche de Hizb/demi-Hizb pour une sourate qui
  /// s'étale sur plusieurs Hizb) ; `portion_words` = le dernier verdict connu
  /// de CHAQUE mot de la portion, mis à jour (pas dupliqué) à chaque
  /// récitation qui rejoue ce mot.
  Future<void> _creerTablesPortions(Database db) async {
    await db.execute('''
      CREATE TABLE portions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        surah_number INTEGER NOT NULL,
        unit_key TEXT NOT NULL,
        label TEXT NOT NULL,
        first_ayah INTEGER NOT NULL,
        last_ayah INTEGER NOT NULL,
        words_total INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        last_recited_at TEXT NOT NULL,
        UNIQUE(surah_number, unit_key)
      )
    ''');
    // `status` inclut 'conteste' (pouce vers le bas sur "Ma voix") : un mot
    // contesté par l'utilisateur compte comme correct pour le badge de
    // réussite (cf. PortionResume.reussite/badge) sans effacer sa trace --
    // on garde `heard_word`/`audio_path` pour pouvoir revenir dessus.
    await db.execute('''
      CREATE TABLE portion_words(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        portion_id INTEGER NOT NULL REFERENCES portions(id) ON DELETE CASCADE,
        ayah_number INTEGER NOT NULL,
        word_in_ayah INTEGER NOT NULL,
        expected_word TEXT NOT NULL,
        heard_word TEXT,
        status TEXT NOT NULL,
        kind TEXT,
        audio_path TEXT,
        audio_expires_at TEXT,
        updated_at TEXT NOT NULL,
        UNIQUE(portion_id, ayah_number, word_in_ayah)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_portion_words ON portion_words(portion_id)');
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

  // ── SUIVI PERMANENT PAR PORTION (sourate/Hizb) ──────────────────────────
  //
  // Distinct de sessions/session_words : ici le VERDICT ne meurt jamais
  // (contrairement à la rétention 7 jours ci-dessus), seul l'audio non vert
  // suit encore cette durée de vie (`audio_expires_at`, purgé par
  // [purgerAnciennes]). Une récitation qui rejoue un mot déjà connu MET À
  // JOUR sa ligne (upsert sur `UNIQUE(portion_id, ayah_number, word_in_ayah)`)
  // au lieu d'en créer une nouvelle -- c'est ce qui permet au badge de
  // réussite de refléter le dernier verdict, pas un historique de tentatives.

  /// Retrouve la portion `(surahNumber, unitKey)` ou la crée, et rafraîchit
  /// `last_recited_at` (+ le reste, au cas où le texte ait changé de forme
  /// entre deux appels -- ne devrait pas arriver, mais rester correct ne
  /// coûte rien ici).
  Future<int> _upsertPortion({
    required int surahNumber,
    required String unitKey,
    required String label,
    required int firstAyah,
    required int lastAyah,
    required int wordsTotal,
  }) async {
    final db = await _database;
    final now = DateTime.now().toIso8601String();
    final existantes = await db.query('portions',
        where: 'surah_number = ? AND unit_key = ?',
        whereArgs: [surahNumber, unitKey]);
    if (existantes.isNotEmpty) {
      final id = existantes.first['id'] as int;
      await db.update(
        'portions',
        {
          'label': label,
          'first_ayah': firstAyah,
          'last_ayah': lastAyah,
          'words_total': wordsTotal,
          'last_recited_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    final id = await db.insert('portions', {
      'surah_number': surahNumber,
      'unit_key': unitKey,
      'label': label,
      'first_ayah': firstAyah,
      'last_ayah': lastAyah,
      'words_total': wordsTotal,
      'created_at': now,
      'last_recited_at': now,
    });
    DiagnosticLog.log('Archive',
        'portion $id creee : $label ($firstAyah-$lastAyah, $wordsTotal mots)');
    return id;
  }

  /// Archive/actualise LE VERDICT COURANT d'un mot dans sa portion -- appelé
  /// pour CHAQUE mot verrouillé (vert compris, cf. `RecitationNotifier.wordLocked`
  /// dans `karaoke_recitation_screen.dart`), contrairement à [archiverMot] qui
  /// ne voit que les mots non verts. [audioSource] suit la même règle que
  /// [archiverMot] : copié tout de suite (l'anneau natif est volatil), et
  /// seulement si fourni -- une mise à jour sans nouvel audio NE TOUCHE PAS à
  /// l'audio déjà archivé (un mot redevenu vert garde la preuve de son
  /// ancienne erreur au lieu de l'effacer silencieusement).
  Future<void> upsertPortionWord({
    required int surahNumber,
    required String unitKey,
    required String label,
    required int firstAyah,
    required int lastAyah,
    required int wordsTotal,
    required int ayahNumber,
    required int wordInAyah,
    required String expectedWord,
    required String status,
    String? heardWord,
    String? kind,
    String? audioSource,
  }) async {
    final portionId = await _upsertPortion(
      surahNumber: surahNumber,
      unitKey: unitKey,
      label: label,
      firstAyah: firstAyah,
      lastAyah: lastAyah,
      wordsTotal: wordsTotal,
    );
    String? destination;
    String? expiration;
    if (audioSource != null) {
      try {
        final src = File(audioSource);
        if (await src.exists()) {
          final d = await _audioDir;
          destination =
              p.join(d.path, 'p${portionId}_a${ayahNumber}_w$wordInAyah.wav');
          await src.copy(destination);
          expiration = DateTime.now()
              .add(const Duration(days: retentionJours))
              .toIso8601String();
        }
      } catch (e) {
        DiagnosticLog.log('Archive',
            'copie audio portion impossible ayah=$ayahNumber mot=$wordInAyah : $e');
      }
    }
    final db = await _database;
    final now = DateTime.now().toIso8601String();
    final existant = await db.query('portion_words',
        where: 'portion_id = ? AND ayah_number = ? AND word_in_ayah = ?',
        whereArgs: [portionId, ayahNumber, wordInAyah]);
    final valeurs = {
      'expected_word': expectedWord,
      'heard_word': heardWord,
      'status': status,
      'kind': kind,
      'updated_at': now,
      if (destination != null) 'audio_path': destination,
      if (expiration != null) 'audio_expires_at': expiration,
    };
    if (existant.isNotEmpty) {
      await db.update('portion_words', valeurs,
          where: 'id = ?', whereArgs: [existant.first['id'] as int]);
    } else {
      await db.insert('portion_words', {
        'portion_id': portionId,
        'ayah_number': ayahNumber,
        'word_in_ayah': wordInAyah,
        'audio_path': destination,
        'audio_expires_at': expiration,
        ...valeurs,
      });
    }
  }

  /// Pouce vers le bas ("Ma voix", cf. `tajwid_help_sheet.dart._onPouceBas`) :
  /// marque le mot comme contesté dans TOUTES les portions de cette sourate
  /// qui le contiennent (normalement une seule -- les portions d'une même
  /// sourate ne se chevauchent pas, sauf changement du réglage de granularité
  /// entre deux récitations, cas limite sans conséquence à traiter ici que de
  /// marquer les deux). Un mot contesté compte comme correct pour le badge de
  /// réussite (cf. `PortionResume.reussite`/`badge`) sans perdre sa trace
  /// (verdict/audio d'origine conservés) -- décision utilisateur 2026-08-08 :
  /// « 90% [...] les 10% il n'est pas d'accord, donc c'est 100% ».
  /// Ne fait rien si le mot n'a encore jamais été archivé (rien à contester).
  Future<void> contesterMotDePortion({
    required int surahNumber,
    required int ayahNumber,
    required int wordInAyah,
  }) async {
    final db = await _database;
    await db.rawUpdate('''
      UPDATE portion_words SET status = 'conteste', updated_at = ?
      WHERE ayah_number = ? AND word_in_ayah = ?
        AND portion_id IN (SELECT id FROM portions WHERE surah_number = ?)
    ''', [DateTime.now().toIso8601String(), ayahNumber, wordInAyah, surahNumber]);
  }

  Future<List<PortionResume>> portions({int limit = 60}) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT p.*,
        (SELECT COUNT(*) FROM portion_words w WHERE w.portion_id = p.id) AS words_reached,
        (SELECT COUNT(*) FROM portion_words w WHERE w.portion_id = p.id AND w.status IN ('correct','conteste')) AS words_green
      FROM portions p
      ORDER BY p.last_recited_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(PortionResume.fromMap).toList();
  }

  Future<List<PortionMot>> motsDePortion(int portionId) async {
    final db = await _database;
    final rows = await db.query('portion_words',
        where: 'portion_id = ?',
        whereArgs: [portionId],
        orderBy: 'ayah_number, word_in_ayah');
    return rows.map(PortionMot.fromMap).toList();
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
    await _purgerAudioPortions();
  }

  /// Purge de l'audio des `portion_words` (7 jours, comme l'audio des
  /// sessions), SANS toucher aux lignes ni au verdict -- c'est tout l'objet
  /// du suivi permanent : `audio_expires_at` est comparé à MAINTENANT (posé
  /// au moment de l'écriture, +7 jours), pas à `started_at` d'une session
  /// (cf. [purgerAnciennes] ci-dessus, qui purge un objet différent).
  Future<void> _purgerAudioPortions() async {
    final db = await _database;
    final maintenant = DateTime.now().toIso8601String();
    final fichiers = await db.rawQuery(
        'SELECT id, audio_path FROM portion_words WHERE audio_path IS NOT NULL AND audio_expires_at < ?',
        [maintenant]);
    if (fichiers.isEmpty) return;
    for (final f in fichiers) {
      try {
        final file = File(f['audio_path'] as String);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Fichier déjà parti ou stockage indisponible : sans conséquence.
      }
    }
    await db.rawUpdate(
        'UPDATE portion_words SET audio_path = NULL, audio_expires_at = NULL WHERE audio_path IS NOT NULL AND audio_expires_at < ?',
        [maintenant]);
    DiagnosticLog.log('Archive',
        '${fichiers.length} audio(s) de portion de plus de $retentionJours jours purge(s) (verdicts conserves)');
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
    await db.delete('portion_words');
    await db.delete('portions');
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

/// Bilan d'une PORTION (sourate entière, ou tranche de Hizb/demi-Hizb) --
/// suivi permanent, distinct de [SessionResume] qui décrit une tentative
/// datée. `wordsReached`/`wordsGreen` sont dérivés en base (COUNT sur
/// `portion_words`), jamais stockés : ils ne peuvent donc pas diverger des
/// lignes réellement écrites.
class PortionResume {
  final int id;
  final int surahNumber;
  final String unitKey;
  final String label;
  final int firstAyah;
  final int lastAyah;
  final int wordsTotal;
  final DateTime createdAt;
  final DateTime lastRecitedAt;
  final int wordsReached;
  final int wordsGreen;

  const PortionResume({
    required this.id,
    required this.surahNumber,
    required this.unitKey,
    required this.label,
    required this.firstAyah,
    required this.lastAyah,
    required this.wordsTotal,
    required this.createdAt,
    required this.lastRecitedAt,
    required this.wordsReached,
    required this.wordsGreen,
  });

  /// Part de mots corrects (mots contestés inclus, cf.
  /// `SessionArchiveService.contesterMotDePortion`) sur les mots ATTEINTS --
  /// même principe que `SessionResume.reussite`.
  double? get reussite => wordsReached == 0 ? null : wordsGreen / wordsReached;

  /// Badge de réussite (règle utilisateur du 2026-08-08, remplace le seuil de
  /// 95% initialement envisagé) : la portion doit être couverte à 100% ET
  /// 100% des mots atteints sont corrects ou contestés -- pas de seuil
  /// intermédiaire.
  bool get badge =>
      wordsTotal > 0 && wordsReached >= wordsTotal && wordsGreen == wordsReached;

  factory PortionResume.fromMap(Map<String, Object?> m) => PortionResume(
        id: m['id'] as int,
        surahNumber: m['surah_number'] as int,
        unitKey: m['unit_key'] as String,
        label: m['label'] as String,
        firstAyah: m['first_ayah'] as int,
        lastAyah: m['last_ayah'] as int,
        wordsTotal: m['words_total'] as int,
        createdAt: DateTime.parse(m['created_at'] as String),
        lastRecitedAt: DateTime.parse(m['last_recited_at'] as String),
        wordsReached: (m['words_reached'] as int?) ?? 0,
        wordsGreen: (m['words_green'] as int?) ?? 0,
      );
}

class PortionMot {
  final int id;
  final int ayahNumber;
  final int wordInAyah;
  final String expectedWord;
  final String? heardWord;
  final String status; // 'correct' | 'error' | 'unclear' | 'oubli' | 'skipped' | 'conteste'
  final String? kind;
  final String? audioPath;

  const PortionMot({
    required this.id,
    required this.ayahNumber,
    required this.wordInAyah,
    required this.expectedWord,
    required this.status,
    this.heardWord,
    this.kind,
    this.audioPath,
  });

  factory PortionMot.fromMap(Map<String, Object?> m) => PortionMot(
        id: m['id'] as int,
        ayahNumber: m['ayah_number'] as int,
        wordInAyah: m['word_in_ayah'] as int,
        expectedWord: m['expected_word'] as String,
        heardWord: m['heard_word'] as String?,
        status: m['status'] as String,
        kind: m['kind'] as String?,
        audioPath: m['audio_path'] as String?,
      );
}
