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
      version: 7,
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
            words_reached INTEGER NOT NULL DEFAULT 0,
            words_skipped INTEGER NOT NULL DEFAULT 0
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
        await _creerTableJours(db);
        await _creerTablePointsQuart(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2 (2026-08-10) : suivi PERMANENT par sourate/Hizb, à côté de
        // `sessions`/`session_words` qui restent le journal daté par
        // tentative (7 jours, inchangé). Aucune table existante n'est
        // touchée : pas de perte des sessions déjà archivées.
        if (oldVersion < 2) {
          await _creerTablesPortions(db);
        }
        // v2 -> v3 (2026-08-11) : `deja_rate` -- cf. sa doc sur la colonne.
        // Les installations qui viennent de passer par `_creerTablesPortions`
        // ci-dessus l'ont déjà (colonne incluse dans le CREATE TABLE), donc
        // seules celles qui étaient DÉJÀ en v2 ont besoin de l'ALTER.
        if (oldVersion == 2) {
          await db.execute(
              'ALTER TABLE portion_words ADD COLUMN deja_rate INTEGER NOT NULL DEFAULT 0');
        }
        // v3 -> v4 (2026-08-11) : `sessions.words_skipped` -- mots que
        // l'ancre a dépassés sans que la chaîne ne fige de verdict. Stocké
        // À CÔTÉ de `words_green`/`words_reached` (jamais à leur place) pour
        // que le taux montré à l'utilisateur cesse de pénaliser un défaut de
        // l'application SANS faire perdre au diagnostic la lecture brute
        // (cf. le piège du 2026-07-29 rappelé dans `_compterMots`).
        // Les sessions déjà archivées restent à 0 : on ne peut pas
        // reconstituer après coup ce que la chaîne n'a pas su juger, et un 0
        // rend exactement le comportement d'avant pour ces lignes-là.
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE sessions ADD COLUMN words_skipped INTEGER NOT NULL DEFAULT 0');
        }
        // v4 -> v5 (2026-08-13) : journal des JOURS actifs (cf. PLAN_COACH.md
        // §7). Aucune table existante n'est touchee.
        if (oldVersion < 5) {
          await _creerTableJours(db);
        }
        // v5 -> v6 (2026-08-13) : plafond anti-boucle des points (cf.
        // `incrementerRepetitionQuart`, PLAN_COACH.md §6).
        if (oldVersion < 6) {
          await _creerTablePointsQuart(db);
        }
        // v6 -> v7 (2026-08-14) : `objectif_mots_du_jour`. L'objectif se
        // saisit désormais en ANNÉES pour tout le Coran, et l'engagement
        // quotidien qui en découle est un nombre de MOTS (cf.
        // `RythmeCoach.seuilMotsParJour`). Une colonne dédiée plutôt que de
        // réutiliser `objectif_du_jour` : celle-ci porte des QUARTS sur toutes
        // les lignes écrites avant ce jour, et changer l'unité d'une colonne
        // en place rendrait l'historique ininterprétable sans qu'aucun calcul
        // n'échoue -- exactement le genre de faux silencieux que la table des
        // jours existe pour éviter.
        if (oldVersion < 7) {
          await db.execute(
              'ALTER TABLE jours_actifs ADD COLUMN objectif_mots_du_jour INTEGER NOT NULL DEFAULT 0');
        }
      },
    );
  }

  /// LE JOURNAL DES JOURS ACTIFS — la seule mémoire longue du Coach.
  ///
  /// ── POURQUOI UNE TABLE DE PLUS (2026-08-13, cf. PLAN_COACH.md §7) ────────
  ///
  /// `sessions` est purgée à [retentionJours] (7 jours). Une série de 30 jours,
  /// une courbe mensuelle, un objectif tenu sur un mois : rien de tout cela ne
  /// peut en être dérivé. Le piège est qu'un calcul fait sur `sessions`
  /// PARAÎTRAIT fonctionner — il donnerait des chiffres, simplement faux dès le
  /// huitième jour, et faux EN SILENCE. Mieux vaut une table minuscule que des
  /// statistiques qui mentent.
  ///
  /// Une ligne par jour où l'utilisateur a récité : quelques dizaines d'octets,
  /// de l'ordre du kilo-octet par an. Jamais purgée — c'est tout son intérêt.
  ///
  /// `objectif_atteint` est stocké et non recalculé : l'objectif du jour peut
  /// changer (cf. la proposition de baisse, PLAN_COACH.md §2), et une série
  /// déjà acquise ne doit pas se réécrire rétroactivement parce que la cible a
  /// bougé depuis. Ce qui a été gagné reste gagné.
  ///
  /// DEUX colonnes d'objectif, et ce n'est pas un doublon (2026-08-14) :
  ///   - `objectif_du_jour` : en QUARTS. Écrite jusqu'au 2026-08-14, quand
  ///     l'objectif se saisissait en « N quarts par période ». Plus alimentée,
  ///     conservée telle quelle — c'est la seule trace de ce qui était engagé
  ///     ces jours-là.
  ///   - `objectif_mots_du_jour` : en MOTS, le seuil qui décide de la série
  ///     depuis la refonte en « durée pour tout le Coran » (cf.
  ///     `RythmeCoach.seuilMotsParJour`). Vaut 0 sur toutes les lignes
  ///     antérieures : l'engagement de ces jours-là n'était pas exprimable en
  ///     mots, et l'inventer après coup serait une donnée fabriquée.
  Future<void> _creerTableJours(Database db) async {
    await db.execute('''
      CREATE TABLE jours_actifs(
        jour TEXT PRIMARY KEY,
        mots_recites INTEGER NOT NULL DEFAULT 0,
        quarts_valides INTEGER NOT NULL DEFAULT 0,
        points INTEGER NOT NULL DEFAULT 0,
        objectif_du_jour INTEGER NOT NULL DEFAULT 0,
        objectif_atteint INTEGER NOT NULL DEFAULT 0,
        objectif_mots_du_jour INTEGER NOT NULL DEFAULT 0
      )
    ''');
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
    //
    // `deja_rate` (2026-08-11, constat utilisateur : « on doit garder
    // l'historique des mots ratés [...] pas avec les audios [...] mais le
    // mot raté avec la possibilité de s'entraîner ») -- MONOTONE, jamais
    // remis à 0 une fois passé à 1 : `status` ne porte que le DERNIER
    // verdict (une correction écrase 'error' par 'correct'), donc sans ce
    // drapeau séparé un mot corrigé perdrait toute trace d'avoir été raté un
    // jour. `audio_path`, lui, continue de suivre le cycle de vie normal
    // (7 jours) -- seul le FAIT d'avoir été raté est permanent, pas le son.
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
        deja_rate INTEGER NOT NULL DEFAULT 0,
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
    int wordsSkipped = 0,
  }) async {
    final id = _sessionCourante;
    if (id == null) return;
    final db = await _database;
    // ── UNE SESSION SANS AUCUN MOT JUGÉ N'EST PAS UNE RÉCITATION ─────────
    // (2026-08-11, constat utilisateur sur le log device : `session 11
    // fermee : 0 vert(s) / 0 atteint(s)` après 3 secondes d'écran, archivée
    // et affichée dans « Mes récitations » comme les autres.) Ouvrir l'écran
    // puis ressortir aussitôt -- ce qui arrive constamment en navigation --
    // créait une ligne vide de plus à chaque fois. On SUPPRIME la ligne au
    // lieu de la fermer : il n'y a rien à y perdre (aucun mot jugé, donc
    // aucun `session_words` rattaché, donc aucun audio non plus).
    if (wordsReached == 0) {
      await db.delete('session_words', where: 'session_id = ?', whereArgs: [id]);
      await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
      DiagnosticLog.log(
          'Archive', 'session $id vide (aucun mot juge) : supprimee au lieu d\'etre archivee');
      _sessionCourante = null;
      return;
    }
    await db.update(
      'sessions',
      {
        'ended_at': DateTime.now().toIso8601String(),
        'words_total': wordsTotal,
        'words_green': wordsGreen,
        'words_reached': wordsReached,
        'words_skipped': wordsSkipped,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    DiagnosticLog.log(
        'Archive',
        'session $id fermee : $wordsGreen vert(s) / $wordsReached atteint(s)'
        '${wordsSkipped > 0 ? ' -- $wordsSkipped non juge(s) par la chaine' : ''}');
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
    int wordsSkipped = 0,
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
        'words_skipped': wordsSkipped,
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
  ///
  /// ── COURSE CORRIGÉE (2026-08-11) ──────────────────────────────────────
  /// Constat utilisateur, session Al-Falaq : 21/23 mots couverts au lieu de
  /// 23. Cause, confirmée par le log device : au tout premier lot de mots
  /// jugés d'une session (plusieurs mots verrouillés dans la même passe
  /// synchrone, cf. `nouveauxVerrouilles` dans `recitation_provider.dart`),
  /// DEUX appels à `upsertPortionWord` s'entrelacent -- le premier fait son
  /// `SELECT` (rien trouvé), commence son `INSERT`, mais avant qu'il ne se
  /// termine le second fait AUSSI son `SELECT` (toujours rien trouvé, le
  /// premier n'a pas fini) puis tente aussi d'insérer :
  /// `UNIQUE constraint failed: portions.surah_number, portions.unit_key`
  /// -- l'exception a fait perdre les 2 mots de ce second appel, sans
  /// qu'aucune autre tentative ne les rattrape ensuite (portion déjà créée
  /// par le premier appel, plus jamais recréée). `INSERT OR IGNORE` rend le
  /// scénario impossible : les deux appels peuvent insérer en concurrence
  /// sans qu'aucun n'échoue, on relit ensuite l'id dans tous les cas.
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
    await db.insert(
      'portions',
      {
        'surah_number': surahNumber,
        'unit_key': unitKey,
        'label': label,
        'first_ayah': firstAyah,
        'last_ayah': lastAyah,
        'words_total': wordsTotal,
        'created_at': now,
        'last_recited_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final rows = await db.query('portions',
        where: 'surah_number = ? AND unit_key = ?',
        whereArgs: [surahNumber, unitKey]);
    final id = rows.first['id'] as int;
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
    // MONOTONE : une fois posé, `deja_rate` ne redescend jamais -- cf. la doc
    // sur la colonne (`_creerTablesPortions`). Une correction (`status` ==
    // 'correct') n'efface pas un `deja_rate` déjà à 1 ; seul un NOUVEAU
    // verdict non-correct peut le poser.
    final dejaRateAvant =
        existant.isEmpty ? 0 : (existant.first['deja_rate'] as int? ?? 0);
    // ── SEULE UNE VRAIE FAUTE MARQUE « DÉJÀ RATÉ » (2026-08-12) ─────────────
    // Constat utilisateur : « ce qui me perturbe c'est les déjà acquis, il y
    // en a plein juste avec UNE SEULE récitation, je n'ai pas testé de redire
    // des mots ».
    //
    // La condition était `status != 'correct'`, ce qui embarquait `skipped` --
    // le statut des mots que l'ancre a dépassés SANS que la chaîne les juge.
    // Une récitation en produit des dizaines ; ils ressortaient donc tous en
    // « déjà ratés, maintenant acquis » alors que le récitateur n'avait ni
    // fauté ni redit quoi que ce soit. C'est la contradiction directe de la
    // règle posée le 2026-08-11 (« un mot non jugé ne pénalise pas ») :
    // `skipped` est déjà compté comme acquis dans `words_green`, il ne pouvait
    // pas dans le même temps valoir historique de faute.
    //
    // `conteste` est exclu pour la même raison : l'utilisateur a précisément
    // déclaré qu'il avait bien prononcé ce mot.
    const vraiesFautes = {'error', 'oubli', 'unclear'};
    final dejaRate =
        (dejaRateAvant == 1 || vraiesFautes.contains(status)) ? 1 : 0;
    final valeurs = {
      'expected_word': expectedWord,
      'heard_word': heardWord,
      'status': status,
      'kind': kind,
      'updated_at': now,
      'deja_rate': dejaRate,
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

  /// Même geste que [contesterMotDePortion], côté SESSION cette fois --
  /// constat utilisateur (2026-08-11, exemple chiffré : session à 91 %,
  /// 5 mots contestés, doit passer à 100 %) : une contestation mettait déjà à
  /// jour la portion, mais pas la session d'où le mot avait été ouvert. Sa
  /// carte restait figée à un pourcentage que l'utilisateur venait pourtant de
  /// prouver faux.
  ///
  /// Cible UNE ligne `session_words` précise par son `id` (pas par position
  /// sourate/ayah/mot comme `contesterMotDePortion`) : contrairement à une
  /// portion, une même position peut apparaître dans PLUSIEURS sessions
  /// passées -- on ne corrige que celle depuis laquelle la fiche a été
  /// ouverte, pas tout l'historique.
  ///
  /// `words_green` de la session est incrémenté UNE SEULE FOIS (idempotent :
  /// si la ligne est déjà `conteste`, `changes` vaut 0 et rien d'autre ne
  /// bouge) -- `words_reached` ne change pas, un mot contesté était déjà
  /// compté comme atteint.
  Future<void> contesterMotDeSession(int motSessionId) async {
    final db = await _database;
    final lignes = await db.query('session_words',
        columns: ['session_id', 'status'],
        where: 'id = ? AND status != ?',
        whereArgs: [motSessionId, 'conteste']);
    if (lignes.isEmpty) return; // deja conteste, ou id inconnu
    final sessionId = lignes.first['session_id'] as int;
    await db.update('session_words', {'status': 'conteste'},
        where: 'id = ?', whereArgs: [motSessionId]);
    await db.rawUpdate(
        'UPDATE sessions SET words_green = words_green + 1 WHERE id = ?',
        [sessionId]);
  }

  /// Triée dans l'ORDRE DU CORAN (sourate puis premier verset de la portion),
  /// pas par date de dernière récitation (constat utilisateur 2026-08-11 :
  /// « les sourates doivent respecter l'ordre dans le Coran »). C'est une
  /// liste de portions SUIVIES DANS LA DURÉE, pas un historique d'activité
  /// récente -- l'ordre canonique est celui qui permet de la parcourir comme
  /// on parcourt le Mushaf.
  Future<List<PortionResume>> portions({int limit = 60}) async {
    final db = await _database;
    // `words_green` = mots ACQUIS : corrects, contestés par l'utilisateur, ou
    // laissés sans verdict par la chaîne ('skipped') -- ces derniers ne
    // pénalisent pas (règle utilisateur 2026-08-11, cf. `PortionResume.reussite`).
    final rows = await db.rawQuery('''
      SELECT p.*,
        (SELECT COUNT(*) FROM portion_words w WHERE w.portion_id = p.id) AS words_reached,
        (SELECT COUNT(*) FROM portion_words w WHERE w.portion_id = p.id AND w.status IN ('correct','conteste','skipped')) AS words_green,
        (SELECT COUNT(*) FROM portion_words w WHERE w.portion_id = p.id AND w.status = 'skipped') AS words_skipped
      FROM portions p
      ORDER BY p.surah_number ASC, p.first_ayah ASC
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

  /// Une portion, par sa clé exacte -- pour savoir si ELLE VIENT d'être
  /// complétée (badge) sans recharger toute la liste. `null` si la portion
  /// n'a encore aucune ligne.
  Future<PortionResume?> portionParCle(int surahNumber, String unitKey) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT p.*,
        (SELECT COUNT(*) FROM portion_words w WHERE w.portion_id = p.id) AS words_reached,
        (SELECT COUNT(*) FROM portion_words w WHERE w.portion_id = p.id AND w.status IN ('correct','conteste','skipped')) AS words_green
      FROM portions p WHERE p.surah_number = ? AND p.unit_key = ?
    ''', [surahNumber, unitKey]);
    if (rows.isEmpty) return null;
    return PortionResume.fromMap(rows.first);
  }

  /// Plafond anti-boucle des points (PLAN_COACH.md §6). Table SÉPARÉE de
  /// `jours_actifs` : elle compte les répétitions PAR QUART, pas le total du
  /// jour -- « plafonner le nombre de fois qu'un même quart rapporte dans une
  /// journée », pas le nombre total de récitations.
  Future<void> _creerTablePointsQuart(Database db) async {
    await db.execute('''
      CREATE TABLE points_quart_jour(
        jour TEXT NOT NULL,
        unit_key TEXT NOT NULL,
        fois INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(jour, unit_key)
      )
    ''');
  }

  // ── LE JOURNAL DES JOURS (Coach) ──────────────────────────────────────────

  static String _cleJour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Ajoute l'activité d'une récitation au jour courant (cumulatif).
  ///
  /// Appelée à la clôture d'une session, jamais pendant : un jour se juge sur
  /// ce qui a été mené à son terme. Les compteurs s'ADDITIONNENT — plusieurs
  /// récitations dans la journée comptent toutes.
  Future<void> ajouterActiviteDuJour({
    int mots = 0,
    int quartsValides = 0,
    int points = 0,
    DateTime? quand,
  }) async {
    if (mots <= 0 && quartsValides <= 0 && points <= 0) return;
    final db = await _database;
    final jour = _cleJour(quand ?? DateTime.now());
    await db.rawInsert('''
      INSERT INTO jours_actifs(jour, mots_recites, quarts_valides, points)
      VALUES(?, ?, ?, ?)
      ON CONFLICT(jour) DO UPDATE SET
        mots_recites   = mots_recites   + excluded.mots_recites,
        quarts_valides = quarts_valides + excluded.quarts_valides,
        points         = points         + excluded.points
    ''', [jour, mots, quartsValides, points]);
    DiagnosticLog.log('Coach',
        'jour $jour : +$mots mot(s), +$quartsValides quart(s), +$points point(s)');
  }

  /// Fige l'objectif du jour et le fait qu'il ait été atteint.
  ///
  /// Séparé de [ajouterActiviteDuJour] à dessein : l'activité est un fait
  /// brut, l'objectif est une décision qui peut changer (cf. la proposition de
  /// baisse). Une fois `objectif_atteint` posé à 1, il n'est jamais rabaissé —
  /// une journée gagnée reste gagnée, même si l'objectif est relevé ensuite.
  ///
  /// [seuilMots] est l'engagement du jour tel qu'il a été calculé au moment où
  /// la journée s'est jouée (cf. `RythmeCoach.seuilMotsParJour`) : il est FIGÉ
  /// pour la même raison que `objectif_atteint`, l'échéance pouvant être
  /// allongée ensuite sans que le passé n'ait à se réécrire.
  Future<void> marquerObjectifDuJour({
    required int seuilMots,
    required bool atteint,
    DateTime? quand,
  }) async {
    final db = await _database;
    final jour = _cleJour(quand ?? DateTime.now());
    await db.rawInsert('''
      INSERT INTO jours_actifs(jour, objectif_mots_du_jour, objectif_atteint)
      VALUES(?, ?, ?)
      ON CONFLICT(jour) DO UPDATE SET
        objectif_mots_du_jour = excluded.objectif_mots_du_jour,
        objectif_atteint = MAX(objectif_atteint, excluded.objectif_atteint)
    ''', [jour, seuilMots, atteint ? 1 : 0]);
  }

  /// Quarts de Hizb DÉJÀ ACQUIS sur tout le Coran (0 à 240) — la base de
  /// calcul de l'objectif depuis le 2026-08-14 : l'échéance porte sur le
  /// RESTE à mémoriser, pas sur les 240 quarts.
  ///
  /// ── POURQUOI COMPTER DES MOTS DISTINCTS, ET PAS DES PORTIONS ────────────
  ///
  /// Une portion vaut selon les cas une sourate entière, un demi-Hizb ou un
  /// quart (cf. `PortionGranularity`) : additionner des portions acquises ne
  /// donnerait donc pas des quarts. Pire, la granularité est un RÉGLAGE — en
  /// changer laisse en base les anciennes portions, dont les versets sont
  /// aussi couverts par les nouvelles. Compter les portions, ou même leurs
  /// mots, compterait deux fois les mêmes mots.
  ///
  /// D'où le `DISTINCT (sourate, verset, mot)` : un mot acquis compte une
  /// fois, quel que soit le nombre de portions qui le contiennent. Le total
  /// est ensuite converti en quarts par la moyenne du Coran
  /// (`ObjectifCoach.motsParQuart`) — la même approximation que le seuil
  /// quotidien, assumée : elle sert à donner un RYTHME, jamais à décider qu'un
  /// quart est validé (ça, c'est `PortionResume.badge`, qui exige une
  /// couverture réelle à 100 %).
  ///
  /// « Acquis » = le même critère que `PortionResume.wordsGreen` : correct,
  /// contesté par l'utilisateur, ou laissé sans verdict par la chaîne — ces
  /// derniers ne pénalisent pas (règle utilisateur 2026-08-11).
  ///
  /// [depuis] restreint aux mots acquis À PARTIR de cette date (`updated_at`,
  /// donc le mot lui-même, pas la portion : une portion revisitée ne fait pas
  /// rentrer dans la fenêtre les mots acquis des mois plus tôt). C'est ce que
  /// lit la barre de progression du mois.
  Future<int> motsAcquisTousCoran({DateTime? depuis}) async {
    final db = await _database;
    final filtreDate = depuis == null ? '' : 'AND w.updated_at >= ?';
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM (
        SELECT DISTINCT p.surah_number, w.ayah_number, w.word_in_ayah
        FROM portion_words w
        JOIN portions p ON p.id = w.portion_id
        WHERE w.status IN ('correct','conteste','skipped') $filtreDate
      )
    ''', [if (depuis != null) depuis.toIso8601String()]);
    return rows.isEmpty ? 0 : ((rows.first['n'] as int?) ?? 0);
  }

  /// Les [n] derniers jours enregistrés, du plus récent au plus ancien.
  Future<List<JourActif>> derniersJours({int n = 60}) async {
    final db = await _database;
    final rows = await db.query('jours_actifs',
        orderBy: 'jour DESC', limit: n);
    return rows.map(JourActif.fromMap).toList();
  }

  /// Série en cours : nombre de jours CONSÉCUTIFS, en remontant depuis
  /// aujourd'hui, où l'objectif a été atteint.
  ///
  /// La série EST ce compteur (décision utilisateur 2026-08-13), elle n'est pas
  /// stockée à part : deux compteurs finissent toujours par se contredire.
  ///
  /// La journée EN COURS ne casse pas la série tant qu'elle n'est pas finie —
  /// on part d'hier si aujourd'hui n'est pas encore validé, sinon une série de
  /// 40 jours afficherait 0 chaque matin au réveil.
  Future<int> serieEnCours({DateTime? aujourdHui}) async {
    final db = await _database;
    final rows = await db.query('jours_actifs',
        columns: ['jour', 'objectif_atteint'],
        where: 'objectif_atteint = 1',
        orderBy: 'jour DESC',
        limit: 400);
    if (rows.isEmpty) return 0;
    final atteints = rows.map((r) => r['jour'] as String).toSet();
    final base = aujourdHui ?? DateTime.now();
    var curseur = DateTime(base.year, base.month, base.day);
    if (!atteints.contains(_cleJour(curseur))) {
      curseur = curseur.subtract(const Duration(days: 1));
    }
    var serie = 0;
    while (atteints.contains(_cleJour(curseur))) {
      serie++;
      curseur = curseur.subtract(const Duration(days: 1));
    }
    return serie;
  }

  /// Incrémente le compteur de répétitions RÉCOMPENSÉES de [unitKey]
  /// aujourd'hui, et renvoie le nouveau total.
  ///
  /// C'est le PLAFOND ANTI-BOUCLE (PLAN_COACH.md §6) : sans lui, le barème
  /// rendrait rentable de rejouer en boucle un même quart facile -- ce
  /// compteur, lui, ne borne QUE les points. Au-delà du plafond, le quart
  /// continue de compter pour la mémorisation réelle (mots récités, journal
  /// du jour) : seule sa valeur en points s'arrête de croître.
  Future<int> incrementerRepetitionQuart(String unitKey, {DateTime? quand}) async {
    final db = await _database;
    final jour = _cleJour(quand ?? DateTime.now());
    await db.rawInsert('''
      INSERT INTO points_quart_jour(jour, unit_key, fois) VALUES(?, ?, 1)
      ON CONFLICT(jour, unit_key) DO UPDATE SET fois = fois + 1
    ''', [jour, unitKey]);
    final rows = await db.query('points_quart_jour',
        columns: ['fois'], where: 'jour = ? AND unit_key = ?', whereArgs: [jour, unitKey]);
    return rows.isEmpty ? 1 : (rows.first['fois'] as int);
  }

  /// Remet une portion À ZÉRO : ses verdicts disparaissent, la portion aussi.
  ///
  /// Demande utilisateur (2026-08-13) : « rajoute pour mémorisation par
  /// sourate la possibilité de supprimer le statut pour refaire ». Le suivi
  /// d'une portion est CUMULÉ et volontairement permanent -- un mot déjà
  /// acquis le reste. Il fallait donc un geste explicite pour repartir de
  /// zéro sur une sourate qu'on veut retravailler entièrement.
  ///
  /// La ligne `portions` est supprimée elle aussi, pas seulement ses mots :
  /// une portion vide réapparaîtrait dans la liste avec 0 %, alors que
  /// l'intention est de la faire DISPARAÎTRE jusqu'à la prochaine récitation,
  /// qui la recréera proprement (`upsertPortion`).
  ///
  /// L'audio archivé des mots est effacé avec eux -- comme pour une session
  /// (cf. [supprimerSession]) : garder des clips orphelins occuperait le
  /// stockage sans que rien ne puisse plus les rejouer.
  Future<void> supprimerPortion(int portionId) async {
    final db = await _database;
    final fichiers = await db.query('portion_words',
        columns: ['audio_path'],
        where: 'portion_id = ? AND audio_path IS NOT NULL',
        whereArgs: [portionId]);
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
    await db.delete('portion_words',
        where: 'portion_id = ?', whereArgs: [portionId]);
    await db.delete('portions', where: 'id = ?', whereArgs: [portionId]);
    DiagnosticLog.log(
        'Archive', 'portion $portionId remise a zero (geste utilisateur)');
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

  /// Mots que l'ancre a dépassés sans que la chaîne ne fige de verdict
  /// (2026-08-11). Stocké À CÔTÉ de [wordsGreen]/[wordsReached], jamais à
  /// leur place : ces deux-là gardent leur sens brut pour le diagnostic
  /// (cf. le piège du 2026-07-29 documenté dans `_compterMots`), et c'est
  /// [reussite] qui applique la règle utilisateur « un mot non jugé ne
  /// pénalise pas ».
  final int wordsSkipped;

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
    this.wordsSkipped = 0,
  });

  /// Mots ACQUIS : les verts, PLUS ceux que la chaîne n'a pas su juger.
  ///
  /// Règle utilisateur du 2026-08-11 : « les mots non jugés dans récitation
  /// ne doivent pas pénaliser, ils doivent être jugés justes dans le
  /// pourcentage ». Un mot que l'ancre a dépassé sans verdict figé est un
  /// défaut de l'application, pas une faute du récitateur. Même règle que
  /// côté portion (`PortionResume.reussite`) -- les deux écrans répondaient
  /// différemment à une question identique, ce qui était le TROISIÈME écart
  /// relevé sur les pourcentages ce jour-là.
  int get wordsAcquis => wordsGreen + wordsSkipped;

  /// Part de mots acquis sur les mots RÉELLEMENT ATTEINTS (l'ancre max), pas
  /// sur la cible : s'arrêter au milieu d'une sourate n'est pas une erreur, et
  /// diviser par la cible ferait passer une récitation juste pour mauvaise.
  ///
  /// Le DÉNOMINATEUR reste l'ancre max, inchangé : un mot perdu par la chaîne
  /// n'en sort pas (sinon une chaîne qui casse afficherait un meilleur taux,
  /// piège mesuré le 2026-07-29). Il passe au NUMÉRATEUR, ce qui neutralise
  /// son effet sans fausser le compte des mots parcourus.
  double? get reussite => wordsReached == 0 ? null : wordsAcquis / wordsReached;

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
        wordsSkipped: (m['words_skipped'] as int?) ?? 0,
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

  /// Mots que l'ancre a dépassés SANS que le modèle ne les ait jamais jugés
  /// (2026-08-11, constat utilisateur : « je parle de ceux que le modèle n'a
  /// pas jugé [...] il reste indéfiniment non jugé »). Cf.
  /// `karaoke_recitation_screen._archiverMotsNonJugesDansPortions`. Ni un
  /// succès ni un échec -- sortent des deux compteurs de [reussite]/[badge],
  /// même principe que la Bismillah dans `_compterMots` (session).
  final int wordsSkipped;

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
    this.wordsSkipped = 0,
  });

  /// Part de mots ACQUIS sur le total de la portion (Bismillah déjà exclue du
  /// total en amont, cf. `PortionService.resolve`).
  ///
  /// « Acquis » = correct, OU contesté par l'utilisateur, OU laissé sans
  /// verdict par la chaîne alors que l'ancre l'avait dépassé -- ces trois cas
  /// sont comptés au NUMÉRATEUR (`words_green` en base, cf.
  /// `SessionArchiveService.portions`).
  ///
  /// ── RÈGLE POSÉE PAR L'UTILISATEUR (2026-08-11) ────────────────────────
  /// « les mots non jugés alors qu'on a déjà passé l'ancre, pour les
  /// distinguer des mots pas encore traités : du coup on ne pénalise pas, ça
  /// compte correct [...] on va partir du 100 % et on enlève les mots en
  /// erreur ». Un mot que la chaîne n'a pas su figer est un défaut de
  /// l'application, pas une faute du récitateur : il ne doit rien lui coûter.
  /// Le pourcentage se lit donc « 100 % moins mes vraies erreurs ».
  ///
  /// Le dénominateur reste le TOTAL de la portion, jamais les seuls mots
  /// atteints (choix explicite de l'utilisateur, exemple arbitré le même
  /// jour : 53 mots justes sur une portion de 300 doivent afficher 18 %, pas
  /// 100 %). Une portion représente la maîtrise de TOUTE la sourate/Hizb dans
  /// la durée -- contrairement à `SessionResume.reussite`, qui décrit UNE
  /// tentative datée et garde volontairement son calcul d'origine.
  double? get reussite => wordsTotal <= 0 ? null : wordsGreen / wordsTotal;

  /// Badge de réussite : toute la portion acquise (cf. [reussite]).
  /// Comparaison d'entiers plutôt qu'une égalité en point flottant sur
  /// `reussite == 1.0`.
  bool get badge => wordsTotal > 0 && wordsGreen >= wordsTotal;

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
        wordsSkipped: (m['words_skipped'] as int?) ?? 0,
      );
}

/// Une journée du Coach. Cf. `_creerTableJours` pour le pourquoi de cette
/// table, et `PLAN_COACH.md` §7.
class JourActif {
  final DateTime jour;
  final int motsRecites;
  final int quartsValides;
  final int points;

  /// En QUARTS, et seulement pour les jours antérieurs au 2026-08-14 : c'est
  /// l'ancien objectif « N quarts par période ». 0 depuis la refonte — l'
  /// engagement du jour se lit alors dans [objectifMotsDuJour].
  final int objectifDuJour;

  /// En MOTS : le seuil qui a décidé, ce jour-là, si la journée comptait pour
  /// la série (cf. `RythmeCoach.seuilMotsParJour`). 0 sur les jours antérieurs
  /// à la refonte.
  final int objectifMotsDuJour;
  final bool objectifAtteint;

  const JourActif({
    required this.jour,
    this.motsRecites = 0,
    this.quartsValides = 0,
    this.points = 0,
    this.objectifDuJour = 0,
    this.objectifMotsDuJour = 0,
    this.objectifAtteint = false,
  });

  factory JourActif.fromMap(Map<String, Object?> m) => JourActif(
        jour: DateTime.parse(m['jour'] as String),
        motsRecites: (m['mots_recites'] as int?) ?? 0,
        quartsValides: (m['quarts_valides'] as int?) ?? 0,
        points: (m['points'] as int?) ?? 0,
        objectifDuJour: (m['objectif_du_jour'] as int?) ?? 0,
        objectifMotsDuJour: (m['objectif_mots_du_jour'] as int?) ?? 0,
        objectifAtteint: ((m['objectif_atteint'] as int?) ?? 0) == 1,
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

  /// A été raté AU MOINS UNE FOIS, même si `status` est redevenu 'correct'
  /// depuis -- cf. la doc de la colonne `deja_rate`. Sert à garder un
  /// historique des mots ratés (sans l'audio, qui suit son cycle de vie
  /// normal) et à toujours pouvoir s'entraîner dessus depuis « Mes portions ».
  final bool dejaRate;

  const PortionMot({
    required this.id,
    required this.ayahNumber,
    required this.wordInAyah,
    required this.expectedWord,
    required this.status,
    this.heardWord,
    this.kind,
    this.audioPath,
    this.dejaRate = false,
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
        dejaRate: ((m['deja_rate'] as int?) ?? 0) == 1,
      );
}
