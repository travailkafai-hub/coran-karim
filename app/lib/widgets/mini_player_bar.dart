import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/player_provider.dart';
import '../models/player_state_model.dart';
import '../theme/app_theme.dart';

/// Barre de lecture inline (demande utilisateur 2026-07-06 : la lecture reste
/// sur la page du Mushaf, jamais de navigation vers un écran séparé). Repliée
/// par défaut (infos + prev/play/next) ; un appui sur le chevron déplie une
/// rangée vitesse/répétition (reprend les réglages autrefois dans l'écran
/// plein écran, supprimé — plus jamais atteignable donc inutile de le garder).
class MiniPlayerBar extends ConsumerStatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  ConsumerState<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends ConsumerState<MiniPlayerBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProvider);
    if (!state.isActive && state.status != PlayerStatus.loading) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(playerProvider.notifier);

    final verse = state.currentVerse;
    final progressFraction = state.duration.inMilliseconds > 0
        ? state.position.inMilliseconds / state.duration.inMilliseconds
        : 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.green900.withAlpha(150),
            blurRadius: 16, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Reciter icon
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.brass,
                ),
                child: const Icon(Icons.record_voice_over,
                    color: AppColors.green900, size: 18),
              ),
              const SizedBox(width: 10),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.reciter.nameFr,
                      style: GoogleFonts.manrope(
                        fontSize: 11, color: AppColors.brassLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (verse != null)
                      Text(
                        '${verse.surahNumber}:${verse.ayahNumber}  •  ${_charsPreview(verse.textUthmani)}',
                        style: GoogleFonts.scheherazadeNew(
                          fontSize: 13, color: AppColors.cream.withAlpha(220),
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                  ],
                ),
              ),
              // Controls
              _MiniButton(
                icon: Icons.skip_previous_rounded,
                onTap: () => ref.read(playerProvider.notifier).prev(),
              ),
              _MiniButton(
                icon: state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 30,
                onTap: () =>
                    ref.read(playerProvider.notifier).togglePlayPause(),
              ),
              _MiniButton(
                icon: Icons.skip_next_rounded,
                onTap: () => ref.read(playerProvider.notifier).next(),
              ),
              _MiniButton(
                icon: _expanded
                    ? Icons.expand_more_rounded
                    : Icons.expand_less_rounded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progressFraction.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: AppColors.green700,
              valueColor: const AlwaysStoppedAnimation(AppColors.brass),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Pill(
                  label: '${state.speed}×',
                  icon: Icons.speed_rounded,
                  onTap: () => _cycleSpeed(notifier, state.speed),
                ),
                _Pill(
                  label: _repeatLabel(state),
                  icon: _repeatIcon(state.repeatMode),
                  active: state.repeatMode != RepeatMode.off,
                  onTap: () => _cycleRepeat(notifier, state),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _charsPreview(String text) {
    final words = text.split(' ');
    return words.take(4).join(' ');
  }

  void _cycleSpeed(PlayerNotifier n, double current) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final idx = speeds.indexOf(current);
    n.setSpeed(speeds[(idx + 1) % speeds.length]);
  }

  void _cycleRepeat(PlayerNotifier n, PlayerStateModel s) {
    switch (s.repeatMode) {
      case RepeatMode.off:
        n.setRepeatMode(RepeatMode.verse);
        n.setRepeatCount(3);
      case RepeatMode.verse:
        if (s.repeatCount < 10) {
          n.setRepeatCount(s.repeatCount == 3 ? 5 : s.repeatCount == 5 ? 10 : 3);
        } else {
          n.setRepeatMode(RepeatMode.surah);
        }
      case RepeatMode.surah:
        n.setRepeatMode(RepeatMode.off);
    }
  }

  String _repeatLabel(PlayerStateModel s) {
    switch (s.repeatMode) {
      case RepeatMode.off: return 'Répéter';
      case RepeatMode.verse: return '×${s.repeatCount} verset';
      case RepeatMode.surah: return 'Sourate ∞';
    }
  }

  IconData _repeatIcon(RepeatMode m) {
    switch (m) {
      case RepeatMode.off: return Icons.repeat;
      case RepeatMode.verse: return Icons.repeat_one_rounded;
      case RepeatMode.surah: return Icons.repeat_rounded;
    }
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const _MiniButton({required this.icon, required this.onTap, this.size = 22});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: AppColors.cream, size: size),
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.icon,
      this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.brass.withAlpha(30) : AppColors.green700,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? AppColors.brass : AppColors.green600),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14,
                  color: active ? AppColors.brass : AppColors.cream.withAlpha(200)),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: active ? AppColors.brass : AppColors.cream.withAlpha(200),
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      );
}
