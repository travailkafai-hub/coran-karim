import 'package:audioplayers/audioplayers.dart' show AssetSource, UrlSource;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/duas_data.dart';
import '../l10n/app_localizations.dart';
import '../models/dua.dart';
import '../models/player_state_model.dart';
import '../providers/player_provider.dart';
import '../services/dua_audio_service.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/dua_card.dart';

/// Liste des invocations d'une collection.
///
/// `highlightDuaId` sert au retour depuis les favoris : on ouvre la
/// collection sur la bonne carte, déjà dépliée, plutôt que de laisser
/// l'utilisateur la rechercher dans la liste.
class DuaCollectionScreen extends ConsumerStatefulWidget {
  final String collectionId;
  final String? highlightDuaId;

  const DuaCollectionScreen({
    super.key,
    required this.collectionId,
    this.highlightDuaId,
  });

  @override
  ConsumerState<DuaCollectionScreen> createState() =>
      _DuaCollectionScreenState();
}

class _DuaCollectionScreenState extends ConsumerState<DuaCollectionScreen> {
  // ── Lecture enchaînée « Lire tout » (demande utilisateur 2026-08-07) ──────
  //
  // DEUX moteurs audio distincts selon la nature de l'invocation :
  //   - coranique (`Dua.isQuranic`) → lecteur GLOBAL `playerProvider`,
  //     partagé avec le Mushaf ;
  //   - hadith avec `Dua.audioUrl` (hisnmuslim.com, branché le 2026-08-07,
  //     cf. commentaire du modèle `Dua`) → `DuaAudioService`, un lecteur
  //     DÉDIÉ et séparé -- `playerProvider` est bâti autour du modèle
  //     `Verse` (sourate/réciteur/playlist), le détourner pour une URL MP3
  //     externe sans verset aurait obligé à toucher sa machine à états déjà
  //     fragile pour un besoin qui n'a rien à voir.
  // Les invocations sans aucun des deux sont sautées silencieusement
  // (décision utilisateur : pas de synthèse vocale de repli).
  //
  // `_sequence` vide = pas de lecture enchaînée en cours. Le mode/nombre de
  // répétitions du lecteur PARTAGÉ est sauvegardé avant d'être écrasé, et
  // restauré à la fin/à l'arrêt/à la sortie d'écran -- sans ça, un réglage
  // de répétition choisi ailleurs dans l'app serait silencieusement modifié.
  List<Dua> _sequence = const [];
  int _sequenceIndex = 0;
  RepeatMode? _savedRepeatMode;
  int? _savedRepeatCount;
  // Coupe l'auto-avance des deux listeners pendant un arrêt explicite
  // (« Arrêter » ou sortie d'écran) : sans ce garde-fou, le changement d'état
  // déclenché par `stop()` serait lu comme « cette invocation est terminée »
  // et enchaînerait sur la suivante au lieu de vraiment s'arrêter.
  bool _stoppingSequence = false;
  // Progression de l'invocation hadith en cours (le pendant du `repeatDone`
  // du lecteur partagé, mais côté `DuaAudioService`).
  int _hadithRepeatDone = 0;
  bool _hadithLoading = false;
  bool _hadithPaused = false;

  bool get _sequenceActive => _sequence.isNotEmpty;

  @override
  void initState() {
    super.initState();
    DuaAudioService.instance.onProgress = _onHadithProgress;
    DuaAudioService.instance.onFinished = _onHadithFinished;
    DuaAudioService.instance.onError = (_, _) => _onHadithFinished(null);
  }

  @override
  void dispose() {
    // Ne détache les callbacks du singleton QUE s'ils sont encore les nôtres
    // -- un écran B ouvert par-dessus a pu les réassigner à sa propre
    // séquence entre-temps ; les effacer inconditionnellement couperait SA
    // lecture en cours.
    if (identical(DuaAudioService.instance.onFinished, _onHadithFinished)) {
      DuaAudioService.instance.onProgress = null;
      DuaAudioService.instance.onFinished = null;
      DuaAudioService.instance.onError = null;
    }
    if (_sequenceActive) {
      final notifier = ref.read(playerProvider.notifier);
      notifier.stop();
      if (_savedRepeatMode != null) notifier.setRepeatMode(_savedRepeatMode!);
      if (_savedRepeatCount != null) notifier.setRepeatCount(_savedRepeatCount!);
      DuaAudioService.instance.stop();
    }
    super.dispose();
  }

  void _onHadithProgress(String key, int done, int target) {
    if (!mounted || !_sequenceActive || _stoppingSequence) return;
    final expected = _sequence[_sequenceIndex];
    if (expected.audioKey != key) return;
    setState(() => _hadithRepeatDone = done);
  }

  void _onHadithFinished(String? key) {
    if (!mounted || !_sequenceActive || _stoppingSequence) return;
    final expected = _sequence[_sequenceIndex];
    if (expected.audioKey != key) return;
    _advanceSequence();
  }

  Future<void> _startSequence(List<Dua> ordered) async {
    // Garde anti double-tap : le bouton n'est retiré de l'arbre qu'au
    // prochain frame, deux appuis rapprochés avant le rebuild appelleraient
    // sinon tous les deux ce même chemin.
    if (_sequenceActive) return;
    final queue = ordered.where((d) => d.hasAudio).toList();
    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.duaSequenceNoneAudio)),
      );
      return;
    }
    final current = ref.read(playerProvider);
    _savedRepeatMode = current.repeatMode;
    _savedRepeatCount = current.repeatCount;
    setState(() {
      _sequence = queue;
      _sequenceIndex = 0;
    });
    await _playSequenceStep();
  }

  Future<void> _playSequenceStep() async {
    if (!_sequenceActive) return;
    final dua = _sequence[_sequenceIndex];
    if (dua.isQuranic) {
      final notifier = ref.read(playerProvider.notifier);
      try {
        final ranges = dua.verseRanges;
        if (ranges != null) {
          // Plusieurs versets, potentiellement plusieurs sourates (ex. les
          // muʿawwidhāt) -- le mécanisme de répétition du lecteur partagé
          // (RepeatMode.verse, ou le groupe imbriqué) suppose une plage
          // CONTIGUË D'UNE SEULE sourate (cf. bornage par `surahNumber` dans
          // `_onComplete` de `player_provider.dart`), incompatible avec un
          // enchaînement de sourates différentes. Plutôt que de toucher à ce
          // code partagé et déjà fragile : la playlist est construite DÉJÀ
          // répétée `dua.repeat` fois par concaténation, jouée une seule
          // fois en RepeatMode.off -- l'avancement naturel de playlist
          // couvre tout, sans dépendre du bornage par sourate.
          notifier.setRepeatMode(RepeatMode.off);
          final base = await QuranApi.fetchVerseRanges(ranges);
          if (base.isEmpty) {
            _advanceSequence();
            return;
          }
          final playlist = [for (var i = 0; i < dua.repeat; i++) ...base];
          await notifier.play(playlist.first, playlist);
        } else {
          notifier.setRepeatMode(RepeatMode.verse);
          notifier.setRepeatCount(dua.repeat);
          final verses = await QuranApi.fetchVerses(dua.surahNumber!);
          final verse = verses.firstWhere((v) => v.ayahNumber == dua.ayahNumber);
          await notifier.play(verse, [verse]);
        }
      } catch (_) {
        // Audio introuvable pour cette entrée précise : on ne bloque pas
        // toute la file, on passe à la suivante.
        _advanceSequence();
      }
      return;
    }
    // Invocation hadith (`dua.audioAsset`/`dua.audioUrl`) : coupe le lecteur
    // partagé (un seul son à la fois dans l'app) puis passe la main à
    // `DuaAudioService`.
    setState(() {
      _hadithRepeatDone = 0;
      _hadithLoading = true;
    });
    await ref.read(playerProvider.notifier).stop();
    try {
      final asset = dua.audioAsset;
      await DuaAudioService.instance.play(
        asset != null ? AssetSource(asset) : UrlSource(dua.audioUrl!),
        key: dua.audioKey!,
        repeat: dua.repeat,
        cutMs: dua.audioCutMs,
      );
    } catch (_) {
      _advanceSequence();
    } finally {
      if (mounted) setState(() => _hadithLoading = false);
    }
  }

  void _advanceSequence() {
    if (!_sequenceActive) return;
    final next = _sequenceIndex + 1;
    if (next >= _sequence.length) {
      _finishSequence();
      return;
    }
    setState(() => _sequenceIndex = next);
    _playSequenceStep();
  }

  void _finishSequence() {
    final notifier = ref.read(playerProvider.notifier);
    if (_savedRepeatMode != null) notifier.setRepeatMode(_savedRepeatMode!);
    if (_savedRepeatCount != null) notifier.setRepeatCount(_savedRepeatCount!);
    setState(() {
      _sequence = const [];
      _sequenceIndex = 0;
      _savedRepeatMode = null;
      _savedRepeatCount = null;
      _hadithRepeatDone = 0;
      _hadithPaused = false;
    });
  }

  Future<void> _stopSequence() async {
    _stoppingSequence = true;
    await ref.read(playerProvider.notifier).stop();
    await DuaAudioService.instance.stop();
    _stoppingSequence = false;
    if (mounted) _finishSequence();
  }

  // « Passer » = considérer l'invocation courante comme terminée sans finir
  // ses répétitions. Asymétrie entre les deux moteurs : côté Coran, arrêter
  // le lecteur partagé fait transiter son état vers `idle`, capté par le
  // `ref.listen` plus bas qui enchaîne tout seul. Côté hadith,
  // `DuaAudioService.stop()` ne déclenche PAS `onFinished` (distinction
  // volontaire arrêt/fin réelle) -- sans l'appel explicite ci-dessous, la
  // séquence restait figée sur place (bug trouvé à la relecture du flux).
  Future<void> _skipSequence() async {
    if (!_sequenceActive) return;
    final dua = _sequence[_sequenceIndex];
    if (dua.isQuranic) {
      await ref.read(playerProvider.notifier).stop();
    } else {
      await DuaAudioService.instance.stop();
      _hadithPaused = false;
      _advanceSequence();
    }
  }

  Future<void> _toggleSequencePause() async {
    if (!_sequenceActive) return;
    final dua = _sequence[_sequenceIndex];
    if (dua.isQuranic) {
      await ref.read(playerProvider.notifier).togglePlayPause();
      return;
    }
    if (_hadithPaused) {
      await DuaAudioService.instance.resume();
    } else {
      await DuaAudioService.instance.pause();
    }
    if (mounted) setState(() => _hadithPaused = !_hadithPaused);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final collectionId = widget.collectionId;
    final highlightDuaId = widget.highlightDuaId;
    final collection = kCollectionsById[collectionId];
    final univers = kUniversByCollectionId[collectionId];
    final accent = univers?.color ?? AppColors.brass;
    final duas = duasForCollection(collectionId);

    // Une invocation mise en avant remonte en tête : sur une collection de
    // 15 entrées, la retrouver au milieu annulerait l'intérêt du raccourci.
    final ordered = highlightDuaId == null
        ? duas
        : [
            ...duas.where((d) => d.id == highlightDuaId),
            ...duas.where((d) => d.id != highlightDuaId),
          ];

    ref.listen<PlayerStateModel>(playerProvider, (prev, next) {
      if (!_sequenceActive || _stoppingSequence) return;
      // Le lecteur est GLOBAL (partagé avec le Mushaf, et avec le bouton
      // « Écouter » de chaque carte). Si la playlist qui vient de s'arrêter
      // n'est pas celle que la séquence attendait, cette transition ne
      // vient pas de nous -- ne pas avancer à la place d'une lecture qu'on
      // n'a pas déclenchée.
      //
      // Comparaison sur le PREMIER élément de la playlist, pas sur
      // `currentVerse` (2026-08-07) : pour une invocation à plusieurs
      // versets (`Dua.verseRanges`, ex. les muʿawwidhāt), `currentVerse`
      // change en cours de lecture au fil de la playlist -- au moment où
      // elle se termine, il ne vaut plus le premier verset, et l'ancienne
      // comparaison rejetait à tort la transition de fin.
      final expected = _sequence[_sequenceIndex];
      final expectedKey = '${expected.surahNumber}:${expected.ayahNumber}';
      final prevFirstKey =
          (prev?.playlist.isNotEmpty ?? false) ? prev!.playlist.first.key : null;
      if (prevFirstKey != expectedKey) return;
      final enteredIdle =
          next.status == PlayerStatus.idle && prev?.status != PlayerStatus.idle;
      if (enteredIdle || next.status == PlayerStatus.error) {
        _advanceSequence();
      }
    });

    final playerState = ref.watch(playerProvider);
    final hasAudio = duas.any((d) => d.hasAudio);

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            // 132 -> 100 (2026-08-09) : les 32 px rendus par l'emoji du
            // bandeau (28 px + 4 px d'écart, cf. `background` plus bas).
            // Cette valeur est ce qui fait réellement gagner de la place :
            // le contenu du FlexibleSpaceBar ne dicte pas la hauteur, c'est
            // elle qui la dicte.
            expandedHeight: 100,
            backgroundColor: accent,
            foregroundColor: AppColors.cream,
            actions: [
              if (hasAudio)
                IconButton(
                  onPressed: _sequenceActive
                      ? _stopSequence
                      : () => _startSequence(ordered),
                  icon: Icon(_sequenceActive
                      ? Icons.stop_circle_rounded
                      : Icons.playlist_play_rounded),
                  tooltip: _sequenceActive
                      ? t.duaSequenceStop
                      : t.duaSequencePlayAll,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 14, right: 16),
              title: Text(
                isArabic
                    ? (collection?.labelAr ?? t.navDuas)
                    : (collection?.labelFr ?? t.navDuas),
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                style: isArabic
                    ? GoogleFonts.scheherazadeNew(
                        fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.cream)
                    : GoogleFonts.fraunces(
                        fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.cream),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.green900, accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 44),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Emoji du bandeau retiré (2026-08-09, demande
                        // utilisateur : gagner de la place sur cette page).
                        // Il occupait 28 px + 4 px d'écart ; `expandedHeight`
                        // a été réduit d'autant, sans quoi le bandeau aurait
                        // gardé sa hauteur et le gain aurait été nul --
                        // l'espace libéré se serait juste redistribué autour
                        // du titre arabe.
                        // `collection.emoji` reste dans les données (il sert
                        // encore à l'onglet Invocations).
                        Text(
                          collection?.labelAr ?? '',
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.scheherazadeNew(
                            fontSize: 20,
                            color: AppColors.brassLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (collection != null && !isArabic)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: Text(
                  collection.hint,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.inkLight,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          if (_sequenceActive)
            SliverToBoxAdapter(
              child: _SequenceBar(
                dua: _sequence[_sequenceIndex],
                index: _sequenceIndex + 1,
                total: _sequence.length,
                repeatDone: _sequence[_sequenceIndex].isQuranic
                    ? playerState.repeatDone
                    : _hadithRepeatDone,
                loading: _sequence[_sequenceIndex].isQuranic
                    ? playerState.status == PlayerStatus.loading
                    : _hadithLoading,
                paused: _sequence[_sequenceIndex].isQuranic
                    ? playerState.isPaused
                    : _hadithPaused,
                accent: accent,
                isArabic: isArabic,
                onTogglePause: _toggleSequencePause,
                onSkip: _skipSequence,
                onStop: _stopSequence,
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            sliver: ordered.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          t.duaCollectionEmpty,
                          style: const TextStyle(color: AppColors.inkLight),
                        ),
                      ),
                    ),
                  )
                : SliverList.builder(
                    itemCount: ordered.length,
                    itemBuilder: (_, i) => DuaCard(
                      dua: ordered[i],
                      accent: accent,
                      initiallyExpanded:
                          highlightDuaId != null && ordered[i].id == highlightDuaId,
                      playingInSequence: _sequenceActive &&
                          ordered[i].id == _sequence[_sequenceIndex].id,
                      audioLocked: _sequenceActive,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau de progression de la lecture enchaînée (« Lire tout »).
class _SequenceBar extends StatelessWidget {
  final Dua dua;
  final int index;
  final int total;
  final int repeatDone;
  final bool loading;
  final Color accent;
  final bool isArabic;
  final VoidCallback onSkip;
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onStop;

  const _SequenceBar({
    required this.dua,
    required this.index,
    required this.total,
    required this.repeatDone,
    required this.loading,
    required this.paused,
    required this.accent,
    required this.isArabic,
    required this.onTogglePause,
    required this.onSkip,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withAlpha(24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withAlpha(90)),
        ),
        child: Row(
          children: [
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              )
            else
              Icon(Icons.volume_up_rounded, color: accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.duaSequenceProgress(index, total),
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isArabic ? dua.titleAr : dua.titleFr,
                    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  if (dua.repeat > 1) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${repeatDone.clamp(0, dua.repeat)} / ${dua.repeat}',
                      style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: loading ? null : onTogglePause,
              icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              color: accent,
              tooltip: paused ? t.mushafPlay : t.mushafPause,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onSkip,
              icon: const Icon(Icons.skip_next_rounded),
              color: accent,
              tooltip: t.duaSequenceSkip,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onStop,
              icon: const Icon(Icons.close_rounded),
              color: AppColors.inkLight,
              tooltip: t.duaSequenceStop,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste d'invocations référencées par id — utilisée par l'écran de rite
/// pour afficher les duas propres à une étape.
class DuaIdList extends StatelessWidget {
  final List<String> duaIds;
  final Color accent;

  const DuaIdList({super.key, required this.duaIds, required this.accent});

  @override
  Widget build(BuildContext context) {
    final duas = duaIds.map((id) => kDuasById[id]).whereType<Dua>().toList();
    if (duas.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [for (final d in duas) DuaCard(dua: d, accent: accent)],
    );
  }
}
