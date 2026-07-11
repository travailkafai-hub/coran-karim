import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/verse.dart';
import '../models/player_state_model.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/verse_tile.dart';
import '../widgets/mushaf_header.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/reading_settings_sheet.dart';
import '../widgets/coach_explanation_sheet.dart';
import 'coach_screen.dart';
import 'recitation_screen.dart';
import 'karaoke_recitation_screen.dart';

class MushafScreen extends ConsumerStatefulWidget {
  final Surah surah;
  const MushafScreen({super.key, required this.surah});

  @override
  ConsumerState<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends ConsumerState<MushafScreen>
    with SingleTickerProviderStateMixin {
  List<Verse> _verses = [];
  bool _loading = true;
  String? _error;
  int _activeVerse = 0;
  bool _showTranslation = false;
  // Récupérée via l'API (verset 1:1 réel), jamais tapée à la main -- texte
  // sacré (cf. karaoke_recitation_screen.dart, bug réel du 2026-07-09).
  Verse? _bismillah;

  final _scrollController = ScrollController();
  Ticker? _autoScrollTicker;
  Duration _lastTick = Duration.zero;

  // Une clé par verset pour pouvoir faire défiler jusqu'au verset en cours de
  // lecture — hauteurs variables (texte + trad. optionnelle), donc
  // Scrollable.ensureVisible plutôt qu'un calcul d'offset.
  List<GlobalKey> _verseKeys = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
        _bismillah = bismillah;
        _verseKeys = List.generate(verses.length, (_) => GlobalKey());
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

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
    showCoachExplanation(
      context,
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      title: '${widget.surah.nameSimple} — verset ${verse.ayahNumber}',
      useErrorLog: false,
    );
  }

  // Explique un mot précis tapé dans le verset (demande utilisateur
  // 2026-07-10 : granularité mot, pas seulement verset entier).
  void _openWordExplanation(Verse verse, int wordIdx) {
    final words = verse.textUthmani.split(' ');
    if (wordIdx < 0 || wordIdx >= words.length) return;
    showCoachExplanation(
      context,
      surahNumber: verse.surahNumber,
      ayahNumber: verse.ayahNumber,
      title: '${widget.surah.nameSimple} ${verse.ayahNumber} — ${words[wordIdx]}',
      focusWord: words[wordIdx],
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
            onMoreTap: _openReadingSettings,
            showTranslation: _showTranslation,
            isPlaying: playerState.isPlaying,
          ),
        ],
      ),
    );
  }

  Widget _buildVerses(String? playingVerseKey) {
    final showBismillah = widget.surah.number != 1 &&
        widget.surah.number != 9 &&
        _bismillah != null;
    final textScale = ref.watch(textScaleProvider);
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
        itemCount: _verses.length + (showBismillah ? 1 : 0),
        itemBuilder: (context, i) {
          if (showBismillah && i == 0) {
            return _BismillahBanner(text: _bismillah!.textUthmani);
          }
          final idx = showBismillah ? i - 1 : i;
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
  /// expérience cible) depuis le verset actif jusqu'à la fin de la sourate.
  void _openKaraoke() {
    final fragment = _verses.sublist(_activeVerse);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => KaraokeRecitationScreen(verses: fragment)));
  }

  /// Double-tap sur le micro : écran de test/debug (transcript brut visible),
  /// utilisé en interne pour juger la qualité du modèle pendant l'entraînement.
  void _openContinuousRecitation() {
    final fragment = _verses.sublist(_activeVerse);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => RecitationScreen(verses: fragment)));
  }
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
  final VoidCallback? onMoreTap;
  final bool showTranslation;
  final bool isPlaying;

  const _BottomBar({
    this.onPlayTap, this.onMicTap, this.onMicLongPress, this.onMicDoubleTap,
    this.onTranslationTap, this.onCoachTap, this.onMoreTap,
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
