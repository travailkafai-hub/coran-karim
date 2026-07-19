import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../models/player_state_model.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../theme/app_theme.dart';
import '../widgets/verse_tile.dart';
import '../widgets/mushaf_header.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/reading_settings_sheet.dart';
import '../widgets/coach_explanation_sheet.dart';
import '../widgets/quran_shazam_sheet.dart';
import 'coach_screen.dart';
import 'recitation_screen.dart';
import 'karaoke_recitation_screen.dart';

class MushafScreen extends ConsumerStatefulWidget {
  final Surah surah;
  // Verset à afficher/scroller directement à l'ouverture (demande utilisateur
  // 2026-07-18, "Shazam coranique" : après avoir identifié un passage entendu
  // en ambiance, ouvrir directement dessus plutôt que le début de la sourate).
  final int? initialAyahNumber;
  const MushafScreen({super.key, required this.surah, this.initialAyahNumber});

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

enum _EntryKind { verse, bismillah, surahBanner }

// Un item de la liste rendue : soit un verset (référence par index dans
// `_verses`, la liste plate à travers toutes les sourates chargées), soit
// une bannière insérée entre deux sourates (nom de sourate, puis Bismillah).
class _ListEntry {
  final _EntryKind kind;
  final int? verseIndex;
  final Verse? bismillah;
  final Surah? surah;
  const _ListEntry.verse(int index)
      : kind = _EntryKind.verse, verseIndex = index, bismillah = null, surah = null;
  const _ListEntry.bismillah(Verse verse)
      : kind = _EntryKind.bismillah, bismillah = verse, verseIndex = null, surah = null;
  const _ListEntry.surahBanner(Surah s)
      : kind = _EntryKind.surahBanner, surah = s, verseIndex = null, bismillah = null;
}

class _MushafScreenState extends ConsumerState<MushafScreen>
    with SingleTickerProviderStateMixin {
  List<Verse> _verses = [];
  bool _loading = true;
  String? _error;
  int _activeVerse = 0;
  bool _showTranslation = false;

  // Défilement infini entre sourates (demande utilisateur 2026-07-18 :
  // "actuellement on affiche sourate par sourate, impossible de passer à la
  // prochaine sourate" -> "défilement infini automatique", comme un vrai
  // Mushaf papier). `_verses`/`_verseKeys` restent une liste PLATE, à travers
  // toutes les sourates chargées -- tout le code existant (index actif,
  // fragment pour le karaoké, scroll par index) continue de fonctionner sans
  // changement. `_items` est la liste de RENDU (verset, ou bannière
  // Bismillah/nom de sourate insérée entre deux sourates).
  List<Surah> _loadedSurahs = [];
  int? _nextSurahNumber;
  bool _loadingMore = false;
  List<Surah>? _allSurahsCache;
  List<_ListEntry> _items = [];

  final _scrollController = ScrollController();
  Ticker? _autoScrollTicker;
  Duration _lastTick = Duration.zero;

  // Une clé par verset pour pouvoir faire défiler jusqu'au verset en cours de
  // lecture — hauteurs variables (texte + trad. optionnelle), donc
  // Scrollable.ensureVisible plutôt qu'un calcul d'offset.
  List<GlobalKey> _verseKeys = [];

  // À moins de 1200px du bas, on déclenche déjà le chargement de la sourate
  // suivante -- l'enchaînement doit être invisible, jamais un blanc/un à-coup
  // pendant que le lecteur arrive en bas.
  static const _kLoadMoreThreshold = 1200.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _autoScrollTicker?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final needsBismillah =
          widget.surah.number != 1 && widget.surah.number != 9;
      final verses = await QuranApi.fetchVerses(widget.surah.number);
      final bismillah =
          needsBismillah ? await QuranApi.fetchBismillah() : null;
      setState(() {
        _verses = verses;
        _verseKeys = List.generate(verses.length, (_) => GlobalKey());
        _loadedSurahs = [widget.surah];
        _nextSurahNumber = widget.surah.number < 114 ? widget.surah.number + 1 : null;
        _items = [
          if (bismillah != null) _ListEntry.bismillah(bismillah),
          for (var i = 0; i < verses.length; i++) _ListEntry.verse(i),
        ];
        _loading = false;
      });
      final targetAyah = widget.initialAyahNumber;
      if (targetAyah != null) {
        final idx = verses.indexWhere((v) => v.ayahNumber == targetAyah);
        if (idx >= 0) {
          setState(() => _activeVerse = idx);
          _scrollToIndex(idx, const Duration(milliseconds: 400));
        }
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!_loadingMore &&
        _nextSurahNumber != null &&
        pos.maxScrollExtent - pos.pixels < _kLoadMoreThreshold) {
      _loadNextSurah();
    }
  }

  // Charge la sourate suivante et l'ajoute à la suite, dans le même scroll
  // continu -- avec une bannière de nom de sourate + Bismillah entre les deux
  // (sauf At-Tawbah, qui n'en a pas). Idempotent/sûr en cas d'appels
  // rapprochés grâce à `_loadingMore` (le scroll déclenche `_onScroll` à
  // chaque frame tant qu'on est proche du bas).
  Future<void> _loadNextSurah() async {
    final nextNum = _nextSurahNumber;
    if (nextNum == null || _loadingMore) return;
    _loadingMore = true;
    try {
      _allSurahsCache ??= await QuranApi.fetchSurahs();
      final nextSurah =
          _allSurahsCache!.firstWhere((s) => s.number == nextNum);
      final needsBismillah = nextNum != 1 && nextNum != 9;
      final verses = await QuranApi.fetchVerses(nextNum);
      final bismillah =
          needsBismillah ? await QuranApi.fetchBismillah() : null;
      if (!mounted) return;
      setState(() {
        final baseIdx = _verses.length;
        _verses = [..._verses, ...verses];
        _verseKeys = [
          ..._verseKeys,
          ...List.generate(verses.length, (_) => GlobalKey()),
        ];
        _items = [
          ..._items,
          _ListEntry.surahBanner(nextSurah),
          if (bismillah != null) _ListEntry.bismillah(bismillah),
          for (var i = 0; i < verses.length; i++) _ListEntry.verse(baseIdx + i),
        ];
        _loadedSurahs = [..._loadedSurahs, nextSurah];
        _nextSurahNumber = nextNum < 114 ? nextNum + 1 : null;
      });
    } catch (e) {
      debugPrint('[Mushaf] échec chargement sourate suivante $nextNum : $e');
    } finally {
      _loadingMore = false;
    }
  }

  // Nom de la sourate propriétaire d'un verset donné -- nécessaire pour les
  // titres (Coach IA, explication de mot) depuis que `_verses` peut couvrir
  // plusieurs sourates : `widget.surah` n'est plus forcément celle du verset
  // actif.
  Surah _surahForNumber(int number) => _loadedSurahs.firstWhere(
        (s) => s.number == number,
        orElse: () => widget.surah,
      );

  // Défilement automatique "téléprompteur" (demande utilisateur 2026-07-06 :
  // "lire le Coran et ça scroll selon sa vitesse") — un Ticker avance le
  // ScrollController à vitesse constante (px/s). Le geste manuel de
  // l'utilisateur (drag) coupe l'auto-scroll plutôt que de lutter contre lui
  // (même principe que le karaoké : le scroll manuel doit rester valide).
  void _syncAutoScroll(AutoScrollSpeed speed) {
    if (speed == AutoScrollSpeed.off) {
      _autoScrollTicker?.stop();
      return;
    }
    if (_autoScrollTicker == null) {
      _lastTick = Duration.zero;
      _autoScrollTicker = createTicker(_onAutoScrollTick)..start();
    } else if (!_autoScrollTicker!.isTicking) {
      _lastTick = Duration.zero;
      _autoScrollTicker!.start();
    }
  }

  void _onAutoScrollTick(Duration elapsed) {
    if (!_scrollController.hasClients) return;
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final speed = ref.read(autoScrollSpeedProvider);
    if (speed == AutoScrollSpeed.off) {
      _autoScrollTicker?.stop();
      return;
    }
    final pos = _scrollController.position;
    final next = (pos.pixels + speed.pixelsPerSecond * dt)
        .clamp(0.0, pos.maxScrollExtent);
    _scrollController.jumpTo(next);
    if (next >= pos.maxScrollExtent) {
      ref.read(autoScrollSpeedProvider.notifier).state = AutoScrollSpeed.off;
    }
  }

  void _openReadingSettings() {
    showReadingSettingsSheet(context, ref);
  }

  // Explique l'aya actuellement sélectionnée (celle sur laquelle l'utilisateur
  // a tapé, _activeVerse — demande utilisateur 2026-07-10 : accès direct au
  // Coach IA depuis la lecture, pas seulement depuis le journal d'erreurs).
  // useErrorLog: false -- lire un verset n'est pas une révision d'erreur,
  // même si ce verset a par ailleurs été raté en récitation ; le registre
  // doit rester "sens du verset", pas "mot que j'ai du mal à retenir"
  // (demande utilisateur 2026-07-10, cette page partait sur la mémorisation).
  void _openCoachExplanation() {
    if (_verses.isEmpty) return;
    final verse = _verses[_activeVerse];
    final surah = _surahForNumber(verse.surahNumber);
    showCoachExplanation(
      context,
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      title: '${surah.nameSimple} — verset ${verse.ayahNumber}',
      useErrorLog: false,
    );
  }

  // Explique un mot précis tapé dans le verset (demande utilisateur
  // 2026-07-10 : granularité mot, pas seulement verset entier).
  void _openWordExplanation(Verse verse, int wordIdx) {
    // Même filtre que tajweedSpansPerWord/TajweedText (source de [wordIdx]
    // via onWordTap) -- sans lui, une marque décorative isolée (ex. "۞")
    // désynchronise cet index de la liste ici recalculée, et le mauvais mot
    // s'affiche dans l'explication (bug corrigé 2026-07-11, même classe que
    // le décalage de coloration tajwid).
    final words = verse.textUthmani
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && ArabicNormalizer.normalize(w).isNotEmpty)
        .toList();
    if (wordIdx < 0 || wordIdx >= words.length) return;
    final surah = _surahForNumber(verse.surahNumber);
    showCoachExplanation(
      context,
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      title: '${surah.nameSimple} ${verse.ayahNumber} — ${words[wordIdx]}',
      focusWord: words[wordIdx],
      focusWordIndex: wordIdx,
      useErrorLog: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final playerActive = playerState.isActive ||
        playerState.status == PlayerStatus.loading;
    final autoScroll = ref.watch(autoScrollSpeedProvider);
    ref.listen(autoScrollSpeedProvider, (prev, next) => _syncAutoScroll(next));

    // Curseur de lecture (demande utilisateur 2026-07-06 : la lecture reste
    // sur cette page, avec un fond bleu qui suit le verset en cours et un
    // scroll automatique jusqu'à lui — pas de navigation vers un autre écran).
    final playingVerseKey =
        playerState.isActive ? playerState.currentVerse?.key : null;
    // Ne PAS filtrer sur isPlaying/isPaused ici : au moment exact où
    // currentVerse change (play()), le statut vaut encore "loading" — un
    // filtre sur le statut ratait donc systématiquement le déclenchement.
    ref.listen<PlayerStateModel>(playerProvider, (prev, next) {
      final key = next.currentVerse?.key;
      if (key != null && key != prev?.currentVerse?.key) {
        _scrollToVerseKey(key, next.speed);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: MushafHeader(surah: widget.surah),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.green800))
          : _error != null
              ? _ErrorView(onRetry: _load)
              : Stack(
                  children: [
                    _buildVerses(playingVerseKey),
                    if (autoScroll != AutoScrollSpeed.off)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: _AutoScrollBadge(
                          onStop: () => ref
                              .read(autoScrollSpeedProvider.notifier)
                              .state = AutoScrollSpeed.off,
                        ),
                      ),
                  ],
                ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playerActive) const MiniPlayerBar(),
          _BottomBar(
            onPlayTap: _verses.isEmpty ? null : _playFromActive,
            onMicTap: _verses.isEmpty ? null : _openMemorization,
            onMicLongPress: _verses.isEmpty ? null : _openKaraoke,
            onMicDoubleTap: _verses.isEmpty ? null : _openContinuousRecitation,
            onTranslationTap: () =>
                setState(() => _showTranslation = !_showTranslation),
            onCoachTap: _verses.isEmpty ? null : _openCoachExplanation,
            onIdentifyTap: _openShazam,
            onMoreTap: _openReadingSettings,
            showTranslation: _showTranslation,
            isPlaying: playerState.isPlaying,
          ),
        ],
      ),
    );
  }

  Widget _buildVerses(String? playingVerseKey) {
    final textScale = ref.watch(textScaleProvider);
    final showLoadingFooter = _loadingMore;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          ref.read(autoScrollSpeedProvider.notifier).state = AutoScrollSpeed.off;
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: _items.length + (showLoadingFooter ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.green800),
              ),
            );
          }
          final entry = _items[i];
          switch (entry.kind) {
            case _EntryKind.bismillah:
              return _BismillahBanner(text: entry.bismillah!.textUthmani);
            case _EntryKind.surahBanner:
              return _SurahBanner(surah: entry.surah!);
            case _EntryKind.verse:
              final idx = entry.verseIndex!;
              final verse = _verses[idx];
              return VerseTile(
                key: _verseKeys[idx],
                verse: verse,
                isActive: _activeVerse == idx,
                isPlayingCursor: playingVerseKey != null && verse.key == playingVerseKey,
                showTranslation: _showTranslation,
                textScale: textScale,
                onTap: () => setState(() => _activeVerse = idx),
                // Tap sur un mot précis = l'expliquer (demande utilisateur
                // 2026-07-10), pas le jouer -- la lecture reste accessible via
                // le bouton "Lire" une fois le verset sélectionné.
                onWordTap: (wordIdx) {
                  setState(() => _activeVerse = idx);
                  _openWordExplanation(verse, wordIdx);
                },
              );
          }
        },
      ),
    );
  }

  void _playFromActive() {
    if (_verses.isEmpty) return;
    _playVerse(_verses[_activeVerse]);
  }

  void _playVerse(Verse verse) {
    ref.read(playerProvider.notifier).play(verse, _verses);
  }

  // Fait défiler la liste jusqu'au verset dont la clé est passée. Durée de
  // l'animation calée sur la vitesse de lecture (demande utilisateur
  // 2026-07-06) : à 1.25×/1.5× le scroll doit suivre plus vite, pas traîner
  // derrière l'audio ; bornée pour rester lisible aux vitesses extrêmes.
  void _scrollToVerseKey(String key, double speed) {
    final idx = _verses.indexWhere((v) => v.key == key);
    if (idx < 0 || idx >= _verseKeys.length) return;
    final ms = (400 / speed).round().clamp(150, 600);
    _scrollToIndex(idx, Duration(milliseconds: ms));
  }

  // ListView.builder ne construit que les items proches de l'écran : si le
  // verset ciblé est loin (lecture qui saute plusieurs versets, ou liste
  // scrollée manuellement ailleurs), son GlobalKey n'a pas encore de
  // BuildContext. On saute d'abord vers une position estimée pour forcer sa
  // construction, puis on affine avec ensureVisible une fois le vrai
  // BuildContext disponible (quelques frames suffisent).
  void _scrollToIndex(int idx, Duration duration, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _verseKeys[idx].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: duration,
          curve: Curves.easeInOut,
        );
        return;
      }
      if (attempt >= 4 || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final estimate = (idx / _verses.length) * pos.maxScrollExtent;
      _scrollController.jumpTo(estimate.clamp(0.0, pos.maxScrollExtent));
      _scrollToIndex(idx, duration, attempt: attempt + 1);
    });
  }

  void _openMemorization() {
    final verse = _verses[_activeVerse];
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CoachScreen(verses: [verse])));
  }

  /// Appui long sur le micro : mode karaoké (récitation continue immersive,
  /// expérience cible) depuis le verset actif. La suite est chargée PAGE PAR
  /// PAGE par l'écran lui-même (cf. `_maybeExtendNextPage`), à l'approche de
  /// la fin -- l'enchaînement reste donc illimité, y compris sur la sourate
  /// suivante.
  ///
  /// Bug corrigé 2026-07-16 : on passait ici `_verses.sublist(_activeVerse)`,
  /// soit TOUTE la fin de la sourate. Sur Al-Baqara ça faisait **6121 mots**
  /// d'un coup (log device : "cible d'alignement : 6121 mots"), là où le
  /// principe retenu est une page à la fois. Effet pervers : l'extension
  /// page par page se cale sur `_verses.last.pageNumber` -- en chargeant tout,
  /// cette dernière page était celle de la FIN de la sourate, donc le
  /// mécanisme ne pouvait jamais servir, et toute la sourate restait tokenisée
  /// et alignée en mémoire pour rien.
  void _openKaraoke() {
    Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => KaraokeRecitationScreen(verses: _fragmentFromActive())));
  }

  /// Versets du verset actif jusqu'à la fin de SA page (repli : toute la fin de
  /// la sourate si la pagination est inconnue -- `pageNumber` est nullable côté
  /// API).
  List<Verse> _fragmentFromActive() {
    final rest = _verses.sublist(_activeVerse);
    final page = rest.first.pageNumber;
    if (page == null) return rest;
    final sameFirstPage = rest.takeWhile((v) => v.pageNumber == page).toList();
    return sameFirstPage.isEmpty ? rest : sameFirstPage;
  }

  /// Double-tap sur le micro : écran de test/debug (transcript brut visible),
  /// utilisé en interne pour juger la qualité du modèle pendant l'entraînement.
  void _openContinuousRecitation() {
    // Même borne d'une page qu'en karaoké (cf. _fragmentFromActive) : cet écran
    // de debug partageait le bug des 6121 mots chargés d'un coup.
    Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => RecitationScreen(verses: _fragmentFromActive())));
  }

  /// "Shazam coranique" (demande utilisateur 2026-07-18) : écoute un extrait
  /// entendu en ambiance (pas la voix de l'utilisateur en train de réciter un
  /// texte déjà choisi -- ici le texte est encore INCONNU) et ouvre le Mushaf
  /// directement au passage identifié.
  Future<void> _openShazam() async {
    final match = await showQuranShazamSheet(context, ref);
    if (match == null || !mounted) return;
    // Déjà dans le scroll continu actuel (sourate initiale ou une des
    // suivantes déjà enchaînées par le défilement infini) : on y saute
    // directement plutôt que de rouvrir un nouvel écran par-dessus.
    if (_loadedSurahs.any((s) => s.number == match.surahNumber)) {
      final idx = _verses.indexWhere((v) =>
          v.surahNumber == match.surahNumber && v.ayahNumber == match.ayahNumber);
      if (idx >= 0) {
        setState(() => _activeVerse = idx);
        _scrollToIndex(idx, const Duration(milliseconds: 400));
      }
      return;
    }
    final surahs = await QuranApi.fetchSurahs();
    final target = surahs.firstWhere((s) => s.number == match.surahNumber,
        orElse: () => widget.surah);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MushafScreen(
          surah: target,
          initialAyahNumber: match.ayahNumber,
        ),
      ),
    );
  }
}

// Marque le passage à la sourate suivante dans le scroll continu (défilement
// infini automatique, demande utilisateur 2026-07-18) -- distincte de la
// Bismillah (qui la suit juste en dessous) pour que le lecteur voie sans
// ambiguïté qu'une nouvelle sourate commence, comme le ferait une page de
// Mushaf papier.
class _SurahBanner extends StatelessWidget {
  final Surah surah;
  const _SurahBanner({required this.surah});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 28, 16, 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.green800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${surah.number}. ${surah.nameSimple}',
              style: GoogleFonts.manrope(
                  fontSize: 13, color: AppColors.cream, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Text(
              surah.nameArabic,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiri(fontSize: 18, color: AppColors.brassLight),
            ),
          ],
        ),
      );
}

class _BismillahBanner extends StatelessWidget {
  final String text;
  const _BismillahBanner({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.green50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.green100, width: 1),
        ),
        child: Center(
          child: Text(
            text,
            textDirection: TextDirection.rtl,
            style: GoogleFonts.scheherazadeNew(
              fontSize: 24, color: AppColors.green800, height: 1.8),
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  final VoidCallback? onPlayTap;
  final VoidCallback? onMicTap;
  final VoidCallback? onMicLongPress;
  final VoidCallback? onMicDoubleTap;
  final VoidCallback? onTranslationTap;
  final VoidCallback? onCoachTap;
  final VoidCallback? onIdentifyTap;
  final VoidCallback? onMoreTap;
  final bool showTranslation;
  final bool isPlaying;

  const _BottomBar({
    this.onPlayTap, this.onMicTap, this.onMicLongPress, this.onMicDoubleTap,
    this.onTranslationTap, this.onCoachTap, this.onIdentifyTap, this.onMoreTap,
    this.showTranslation = false, this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.green800,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppColors.green900.withAlpha(120),
              blurRadius: 20, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BarButton(
                  icon: isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  label: isPlaying ? 'Pause' : 'Lire',
                  color: AppColors.brass,
                  onTap: onPlayTap ?? () {},
                ),
                _BarButton(icon: Icons.star_border_rounded, label: 'Favoris',
                    onTap: () {}),
                // Mic — prominent. Tap = ce verset, appui long = mode karaoké
                // (continu, immersif), double-tap = écran de test/debug interne.
                GestureDetector(
                  onTap: onMicTap,
                  onLongPress: onMicLongPress,
                  onDoubleTap: onMicDoubleTap,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.brass,
                      boxShadow: [
                        BoxShadow(color: AppColors.brass.withAlpha(100),
                            blurRadius: 12, spreadRadius: 2)
                      ],
                    ),
                    child: const Icon(Icons.mic, color: AppColors.green900, size: 28),
                  ),
                ),
                _BarButton(
                  icon: showTranslation
                      ? Icons.translate : Icons.translate_outlined,
                  label: 'Trad.',
                  color: showTranslation ? AppColors.brass : null,
                  onTap: onTranslationTap ?? () {},
                ),
                _BarButton(
                  icon: Icons.psychology_alt_rounded,
                  label: 'Coach IA',
                  onTap: onCoachTap ?? () {},
                ),
                // "Shazam coranique" (demande utilisateur 2026-07-18) : écoute
                // un passage entendu en ambiance et retrouve où il se trouve.
                _BarButton(
                  icon: Icons.hearing_rounded,
                  label: 'Identifier',
                  onTap: onIdentifyTap ?? () {},
                ),
                _BarButton(icon: Icons.more_horiz_rounded, label: 'Plus',
                    onTap: onMoreTap ?? () {}),
              ],
            ),
          ),
        ),
      );
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _BarButton({required this.icon, required this.label,
      this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.cream.withAlpha(200);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.manrope(
              fontSize: 10, color: c, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Petit contrôle flottant pour arrêter le défilement automatique sans
/// rouvrir les réglages (demande utilisateur 2026-07-06 : le scroll manuel/
/// l'arrêt doivent rester faciles d'accès pendant que ça défile tout seul).
class _AutoScrollBadge extends StatelessWidget {
  final VoidCallback onStop;
  const _AutoScrollBadge({required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onStop,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.green900.withAlpha(230),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 10),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pause_rounded, color: AppColors.brassLight, size: 18),
              const SizedBox(width: 6),
              Text(
                'Défilement auto',
                style: GoogleFonts.manrope(
                    fontSize: 12, color: AppColors.cream, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: AppColors.green700),
            const SizedBox(height: 12),
            Text('Connexion requise',
                style: GoogleFonts.manrope(
                    color: AppColors.inkLight, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      );
}
