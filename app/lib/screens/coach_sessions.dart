import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/verse.dart';
import '../providers/mind_map_provider.dart';
import '../providers/player_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_error_log_service.dart';
import '../services/session_archive_service.dart';
import '../services/voice_lora_clip_service.dart';
import '../services/word_correction_audio.dart';
import '../theme/app_theme.dart';
import 'coach_screen.dart';
import 'memorization_game_screen.dart';
import 'mind_map_screen.dart';

enum _ChoixEntrainement { jeu, paliers }

/// LE COACH REGARDE EN ARRIÈRE (2026-08-06).
///
/// Demande utilisateur : « comme maintenant la récitation, le jeu et la
/// mémorisation, ça se fait depuis l'écran du Mushaf, je veux que le coach se
/// concentre sur les erreurs [...] on doit retravailler la partie coach pour
/// se concentrer sur tout ce qui est résultat ».
///
/// Ce que le Coach répondait avant : « que veux-tu faire ? » — quatre boutons
/// de lancement que le Mushaf propose désormais au verset près. Ce qu'il
/// répond maintenant : « voilà ce que tu as fait, et ce qui a coincé ».
///
/// Deux échelles de temps, volontairement distinctes :
///   - CETTE section : la SESSION, datée, avec la voix du récitant
///     (`SessionArchiveService`, gardée une semaine) ;
///   - `_ErrorsSection` du hub : le CUMUL par sourate et par règle
///     (`RecitationErrorLogService`, jamais effacé).
/// La première dit « ce jour-là », la seconde « en général ». Les mélanger
/// ferait perdre les deux.
final sessionsArchiveProvider = FutureProvider<List<SessionResume>>(
    (ref) => SessionArchiveService.instance.sessions());

final motsDeSessionProvider =
    FutureProvider.family<List<MotArchive>, int>((ref, sessionId) =>
        SessionArchiveService.instance.motsDeSession(sessionId));

final tailleArchiveProvider =
    FutureProvider<int>((ref) => SessionArchiveService.instance.octetsAudio());

class SessionsSection extends ConsumerWidget {
  const SessionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsArchiveProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('MES RÉCITATIONS',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                )),
            const Spacer(),
            // Le budget de stockage a été fixé par l'utilisateur (~1 Mo par
            // session, une semaine) : il doit pouvoir le VÉRIFIER, pas le
            // croire sur parole.
            ref.watch(tailleArchiveProvider).maybeWhen(
                  data: (o) => Text(
                      '${(o / (1024 * 1024)).toStringAsFixed(1)} Mo · 7 j',
                      style: GoogleFonts.manrope(
                          fontSize: 10.5, color: AppColors.inkLight)),
                  orElse: () => const SizedBox.shrink(),
                ),
          ],
        ),
        const SizedBox(height: 10),
        sessions.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Archive illisible : $e',
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight)),
          data: (list) => list.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cream200,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cream300),
                  ),
                  child: Text(
                    'Aucune récitation enregistrée pour l’instant. '
                    'Après une récitation contrôlée, vous retrouverez ici '
                    'chaque mot signalé — avec votre voix.',
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, height: 1.45, color: AppColors.inkLight),
                  ),
                )
              : Column(
                  children: [
                    for (final s in list) _CarteSession(s),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CarteSession extends ConsumerWidget {
  final SessionResume s;
  const _CarteSession(this.s);

  Future<bool> _confirmerSuppression(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette récitation ?'),
        content: const Text(
            'Le résultat et les enregistrements audio de mots de cette '
            'session seront définitivement supprimés. Le journal cumulé '
            'du Coach (statistiques par sourate) n\'est pas affecté.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = s.reussite;
    final couleur = r == null
        ? AppColors.inkLight
        : r >= 0.95
            ? AppColors.green700
            : r >= 0.85
                ? AppColors.brass
                : Colors.redAccent.shade200;
    return Dismissible(
      key: ValueKey('session_${s.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmerSuppression(context),
      onDismissed: (_) async {
        await SessionArchiveService.instance.supprimerSession(s.id);
        ref.invalidate(sessionsArchiveProvider);
        ref.invalidate(tailleArchiveProvider);
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.shade200,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          s.surahNumber == null
              ? 'Récitation'
              : 'Sourate ${s.surahNumber}'
                  '${s.fromAyah != null ? ' · v.${s.fromAyah}-${s.toAyah}' : ''}',
          style: GoogleFonts.manrope(
              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        subtitle: Text(
          '${_dateCourte(s.startedAt)} · ${s.wordsReached} mot(s) récité(s)'
          '${s.nonVerts > 0 ? ' · ${s.nonVerts} à revoir' : ''}',
          style:
              GoogleFonts.manrope(fontSize: 11.5, color: AppColors.inkLight),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(r == null ? '—' : '${(r * 100).round()}%',
                    style: GoogleFonts.manrope(
                        fontSize: 17, fontWeight: FontWeight.w800, color: couleur)),
                Text('justes',
                    style: GoogleFonts.manrope(
                        fontSize: 9, color: AppColors.inkLight)),
              ],
            ),
            // Icône explicite (demande utilisateur 2026-08-08 : le glissement
            // seul n'était pas assez visible/découvrable -- « rajoute
            // supprimer sur chaque récitation »). Le glissement reste
            // disponible en plus, pas retiré.
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.inkLight),
              tooltip: 'Supprimer cette récitation',
              onPressed: () async {
                final ok = await _confirmerSuppression(context);
                if (!ok || !context.mounted) return;
                await SessionArchiveService.instance.supprimerSession(s.id);
                if (context.mounted) {
                  ref.invalidate(sessionsArchiveProvider);
                  ref.invalidate(tailleArchiveProvider);
                }
              },
            ),
          ],
        ),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SessionDetailScreen(session: s))),
      ),
      ),
    );
  }

  static String _dateCourte(DateTime d) {
    final maintenant = DateTime.now();
    final jours = DateTime(maintenant.year, maintenant.month, maintenant.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    final heure =
        '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
    return switch (jours) {
      0 => "Aujourd'hui $heure",
      1 => 'Hier $heure',
      _ => 'Il y a $jours jours',
    };
  }
}

/// Le détail d'une session : chaque mot non vert, avec SA VOIX telle qu'elle a
/// sonné ce jour-là, et celle du récitateur pour comparer.
///
/// C'est la raison d'être de l'archive audio. Sans elle, un mot signalé se
/// résume à un reproche sans preuve — et l'utilisateur ne peut ni le vérifier,
/// ni entendre ce qu'il a réellement dit.
class SessionDetailScreen extends ConsumerWidget {
  final SessionResume session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mots = ref.watch(motsDeSessionProvider(session.id));
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Text(
          session.surahNumber == null
              ? 'Récitation'
              : 'Sourate ${session.surahNumber}',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        // ── CARTE MENTALE IMBRIQUÉE ICI (2026-08-09, demande utilisateur) ──
        // « garde même format pour session et tu imbriques l'entraînement et
        // mindmap » -- le jeu (M'entraîner) était déjà accessible par mot
        // (`_LigneMot._entrainer`, plus bas) ; la carte mentale, elle,
        // n'existait que dans l'ancien volet "Mes erreurs". Même bouton que
        // `coach_hub_screen._SurahErrorTile` (masqué si aucun contenu pour
        // cette sourate -- jamais un bouton mort).
        actions: [
          if (session.surahNumber != null)
            Consumer(builder: (context, ref, _) {
              final mindMap =
                  ref.watch(mindMapProvider(session.surahNumber!));
              if (mindMap.asData?.value == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.hub_outlined),
                tooltip: 'Carte mentale',
                onPressed: () async {
                  final surahs = await QuranApi.fetchSurahs();
                  final surah = surahs
                      .firstWhere((s) => s.number == session.surahNumber);
                  if (!context.mounted) return;
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => MindMapScreen(surah: surah)));
                },
              );
            }),
        ],
      ),
      body: mots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Bilan(session),
            const SizedBox(height: 18),
            if (list.isEmpty)
              Text('Aucun mot signalé sur cette récitation.',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppColors.inkLight))
            else
              for (final m in list) _LigneMot(m),
          ],
        ),
      ),
    );
  }
}

class _Bilan extends StatelessWidget {
  final SessionResume s;
  const _Bilan(this.s);

  @override
  Widget build(BuildContext context) {
    final r = s.reussite;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r == null ? '—' : '${(r * 100).round()} % de mots justes',
              style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brassLight)),
          const SizedBox(height: 6),
          // Le dénominateur est dit explicitement : c'est la question la plus
          // souvent mal comprise d'un score de récitation (« pourquoi 100 %
          // alors que je me suis arrêté au milieu ? »).
          Text(
            '${s.wordsGreen} mots justes sur ${s.wordsReached} récités. '
            'Les mots jamais atteints ne comptent pas.',
            style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.cream.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

class _LigneMot extends ConsumerStatefulWidget {
  final MotArchive m;
  const _LigneMot(this.m);

  @override
  ConsumerState<_LigneMot> createState() => _LigneMotState();
}

class _LigneMotState extends ConsumerState<_LigneMot> {
  bool _joue = false;
  String? _message;

  // ── POUCES, AUSSI DEPUIS L'ARCHIVE (2026-08-09, demande utilisateur) ─────
  // « même dans cette session, le user peut valider ou invalider les
  // pouces ». Même mécanisme que la fiche tajwid en direct
  // (`tajwid_help_sheet._onPouceHaut`/`_onPouceBas`), adapté : ici l'audio
  // est DÉJÀ un fichier archivé (`m.audioPath`), pas une extraction v2 à
  // faire à la demande -- pas besoin de rejouer avant de pouvoir contester.
  bool _feedbackEnvoye = false;
  bool _feedbackEnCours = false;

  /// Pouce HAUT : accusé de réception visuel seulement (l'erreur est déjà en
  /// base depuis le jugement, même choix que la fiche tajwid en direct).
  void _onPouceHaut() {
    if (_feedbackEnvoye || _feedbackEnCours) return;
    setState(() => _feedbackEnvoye = true);
  }

  /// Pouce BAS : « je l'ai bien dit ». Archive l'extrait déjà présent dans
  /// l'archive de session (pas une nouvelle extraction, il n'y en a plus à
  /// faire hors session vivante) pour export manuel ultérieur, et retire
  /// l'erreur du journal cumulé pour ne pas compter un faux positif que
  /// l'utilisateur vient lui-même d'invalider.
  Future<void> _onPouceBas() async {
    final m = widget.m;
    if (_feedbackEnvoye || _feedbackEnCours) return;
    setState(() => _feedbackEnCours = true);
    try {
      if (m.audioPath != null) {
        await VoiceLoraClipService().commitDisputedClip(
          sourcePath: m.audioPath!,
          text: m.expectedWord,
          verdict: 'conteste_par_utilisateur',
        );
      }
      if (m.surahNumber != null &&
          m.ayahNumber != null &&
          m.wordInAyah != null) {
        await RecitationErrorLogService.instance.removeLatestError(
          surahNumber: m.surahNumber!,
          ayahNumber: m.ayahNumber!,
          wordIndex: m.wordInAyah!,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _feedbackEnCours = false;
          _feedbackEnvoye = true;
        });
      }
    }
  }

  Future<void> _maVoix() async {
    final chemin = widget.m.audioPath;
    if (chemin == null) {
      setState(() => _message = 'Voix non enregistrée pour ce mot');
      return;
    }
    setState(() {
      _joue = true;
      _message = null;
    });
    try {
      await WordCorrectionAudio.playFile(chemin);
    } catch (_) {
      if (mounted) setState(() => _message = 'Lecture impossible');
    } finally {
      if (mounted) setState(() => _joue = false);
    }
  }

  /// Le récitateur sur le MÊME mot. Le verset n'est pas en base (l'archive ne
  /// stocke que la position) : on va le chercher au moment du tap plutôt que
  /// de dupliquer le texte coranique dans une seconde base.
  Future<void> _leRecitateur() async {
    final m = widget.m;
    if (m.surahNumber == null || m.ayahNumber == null || m.wordInAyah == null) {
      setState(() => _message = 'Position du mot inconnue');
      return;
    }
    setState(() {
      _joue = true;
      _message = null;
    });
    try {
      final versets = await QuranApi.fetchVerses(m.surahNumber!);
      final Verse verset = versets.firstWhere(
          (v) => v.ayahNumber == m.ayahNumber,
          orElse: () => versets.first);
      await WordCorrectionAudio.playWordRange(
        verset,
        ref.read(playerProvider).reciter,
        errorWordIndex: m.wordInAyah!,
        wordsBefore: 1,
        wordsAfter: 0,
      );
    } catch (_) {
      if (mounted) setState(() => _message = 'Audio du récitateur indisponible');
    } finally {
      if (mounted) setState(() => _joue = false);
    }
  }

  /// Demande QUEL entraînement, avant de lancer quoi que ce soit (demande
  /// utilisateur 2026-08-09 : « pour s'entraîner y a deux options, soit avec
  /// le jeu, soit avec l'entraînement avec les paliers, la mémorisation, le
  /// verset qui contient le mot »).
  ///
  /// Les deux options ne ciblent PAS le même texte, à dessein :
  ///   - le JEU part deux versets AVANT (cf. sa doc plus bas) : le lapsus se
  ///     produit souvent à la transition vers un nouveau verset ;
  ///   - les PALIERS (CoachScreen, écoute/imite/contrôle) ciblent le SEUL
  ///     verset qui contient le mot -- c'est le mode qui approfondit un
  ///     passage précis, pas celui qui teste l'enchaînement.
  Future<void> _entrainer() async {
    final m = widget.m;
    if (m.surahNumber == null || m.ayahNumber == null) {
      setState(() => _message = 'Position du mot inconnue');
      return;
    }
    final choix = await showModalBottomSheet<_ChoixEntrainement>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videogame_asset_rounded,
                  color: Colors.lightBlue),
              title: const Text('Jeu de mémorisation'),
              subtitle: const Text('En partant deux versets avant'),
              onTap: () =>
                  Navigator.pop(ctx, _ChoixEntrainement.jeu),
            ),
            ListTile(
              leading: const Icon(Icons.school_rounded,
                  color: AppColors.green700),
              title: const Text('Entraînement par paliers'),
              subtitle: const Text('Écoute, imite, contrôle -- sur ce verset'),
              onTap: () =>
                  Navigator.pop(ctx, _ChoixEntrainement.paliers),
            ),
          ],
        ),
      ),
    );
    if (choix == null || !mounted) return;
    setState(() {
      _joue = true;
      _message = null;
    });
    try {
      final tousVersets = await QuranApi.fetchVerses(m.surahNumber!);
      if (choix == _ChoixEntrainement.paliers) {
        final verset = tousVersets.firstWhere(
            (v) => v.ayahNumber == m.ayahNumber,
            orElse: () => tousVersets.first);
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(
            builder: (_) => CoachScreen(verses: [verset])));
        return;
      }
      final surahs = await QuranApi.fetchSurahs();
      final surah = surahs.firstWhere((s) => s.number == m.surahNumber);
      final depart = (m.ayahNumber! - 2).clamp(1, m.ayahNumber!);
      final versets =
          tousVersets.where((v) => v.ayahNumber >= depart).toList();
      if (versets.isEmpty || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MemorizationGameScreen(surah: surah, verses: versets),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _message = 'Entraînement indisponible');
    } finally {
      if (mounted) setState(() => _joue = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    // 'oubli' (2026-08-09) : décrochage repris ou souffleur sollicité -- ni
    // une erreur de prononciation (rouge) ni une approximation (brass), donc
    // une couleur à part. Cf. `_archiverOubli` dans karaoke_recitation_screen.
    final couleur = switch (m.status) {
      'error' => Colors.redAccent.shade200,
      'unclear' => AppColors.brass,
      'oubli' => Colors.lightBlue.shade300,
      _ => AppColors.inkLight,
    };
    final estOubli = m.kind == 'oubli';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 26, color: couleur),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m.expectedWord,
                    textDirection: TextDirection.rtl,
                    style: GoogleFonts.scheherazadeNew(
                        fontSize: 24, color: AppColors.ink)),
              ),
              if (estOubli)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.lightBlue.shade200),
                    ),
                    child: Text('Oubli',
                        style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.lightBlue.shade700)),
                  ),
                ),
              if (m.ayahNumber != null)
                Text('${m.surahNumber}:${m.ayahNumber}',
                    style: GoogleFonts.manrope(
                        fontSize: 11, color: AppColors.inkLight)),
            ],
          ),
          // Ce que la chaîne a entendu : la seule information qui permette à
          // l'utilisateur de contester un verdict. Un signalement sans elle
          // n'est pas vérifiable.
          if (m.heardWord != null && m.heardWord!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 14),
              child: Text('entendu : ${m.heardWord}',
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.scheherazadeNew(
                      fontSize: 17, color: AppColors.inkLight)),
            ),
          const SizedBox(height: 8),
          // ── TROIS BOUTONS SUR UNE LIGNE FAISAIENT DEBORDER LE TEXTE
          // (2026-08-09, constat utilisateur sur capture d'écran) : "Le
          // récitateur" et "M'entraîner" se retrouvaient coupés sur deux
          // lignes, `Expanded` divisant la largeur en trois parts trop
          // étroites. "M'entraîner" (mots "oubli" seulement) passe donc en
          // pleine largeur, sur sa propre ligne -- les deux boutons du
          // verdict (Ma voix / Le récitateur) gardent leur ligne à eux,
          // toujours présents.
          Row(
            children: [
              Expanded(
                child: _Bouton(
                  icone: Icons.record_voice_over_outlined,
                  texte: 'Ma voix',
                  couleur: AppColors.brass,
                  actif: !_joue && m.audioPath != null,
                  onTap: _maVoix,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Bouton(
                  icone: Icons.play_circle_outline_rounded,
                  texte: 'Le récitateur',
                  couleur: AppColors.green700,
                  actif: !_joue,
                  onTap: _leRecitateur,
                ),
              ),
            ],
          ),
          if (estOubli) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _Bouton(
                icone: Icons.school_outlined,
                texte: 'M\'entraîner',
                couleur: Colors.lightBlue.shade700,
                actif: !_joue,
                onTap: _entrainer,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('L\'app a bien vu ?',
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppColors.inkLight)),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.thumb_up_outlined,
                    size: 18,
                    color: _feedbackEnvoye
                        ? AppColors.green700
                        : AppColors.inkLight),
                tooltip: 'D\'accord, c\'est une vraie erreur',
                onPressed: _feedbackEnvoye || _feedbackEnCours
                    ? null
                    : _onPouceHaut,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: _feedbackEnCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.thumb_down_outlined,
                        size: 18,
                        color: _feedbackEnvoye
                            ? AppColors.inkLight
                            : Colors.redAccent.shade200),
                tooltip: 'Pas d\'accord, je l\'ai bien dit',
                onPressed: _feedbackEnvoye || _feedbackEnCours
                    ? null
                    : _onPouceBas,
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_message!,
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppColors.inkLight)),
            ),
        ],
      ),
    );
  }
}

class _Bouton extends StatelessWidget {
  final IconData icone;
  final String texte;
  final Color couleur;
  final bool actif;
  final VoidCallback onTap;
  const _Bouton({
    required this.icone,
    required this.texte,
    required this.couleur,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Plus d'`Expanded` ici (retiré 2026-08-09) : ce widget doit pouvoir
    // vivre soit dans un `Row` (deux boutons côte à côte, chacun enveloppé
    // d'`Expanded` par l'appelant), soit seul en pleine largeur (bouton
    // "M'entraîner", via `SizedBox(width: double.infinity)`) -- `Expanded`
    // en dur cassait ce second cas (« Expanded widgets must be placed
    // inside a Flex widget »).
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        side: BorderSide(color: actif ? couleur : AppColors.cream300),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: actif ? onTap : null,
      icon: Icon(icone, size: 18, color: actif ? couleur : AppColors.inkLight),
      label: Text(texte,
          style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: actif ? couleur : AppColors.inkLight)),
    );
  }
}
