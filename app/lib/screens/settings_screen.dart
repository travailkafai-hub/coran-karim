import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/reciter.dart';
import '../models/player_state_model.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import 'reciter_select_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final autoCorrection = ref.watch(autoCorrectionEnabledProvider);
    final strictCorrection = ref.watch(strictCorrectionProvider);
    final repeatDrillCount = ref.watch(repeatDrillCountProvider);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text('الإعدادات',
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Récitation'),
          _SettingsTile(
            icon: Icons.record_voice_over,
            title: 'Réciteur',
            subtitle: '${playerState.reciter.nameFr}  •  ${playerState.reciter.style}',
            trailing: Text(playerState.reciter.nameAr,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 14, color: AppColors.green700)),
            onTap: () async {
              final picked = await Navigator.push<Reciter>(
                context,
                MaterialPageRoute(
                    builder: (_) => ReciterSelectScreen(
                        currentId: playerState.reciter.id)),
              );
              if (picked != null) notifier.setReciter(picked);
            },
          ),
          _SettingsTile(
            icon: Icons.speed_rounded,
            title: 'Vitesse de lecture',
            subtitle: '${playerState.speed}×',
            onTap: () => _pickSpeed(context, playerState.speed, notifier),
          ),
          _SettingsTile(
            icon: Icons.repeat_rounded,
            title: 'Répétition',
            subtitle: _repeatDesc(playerState.repeatMode, playerState.repeatCount),
            onTap: () => _pickRepeat(context, notifier),
          ),
          _SettingsTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Correction automatique',
            subtitle: autoCorrection
                ? 'Mot rouge → pause, le réciteur corrige, reprise auto'
                : 'Désactivée — jugement affiché, correction au tap seulement',
            trailing: Switch.adaptive(
              value: autoCorrection,
              onChanged: (v) =>
                  ref.read(autoCorrectionEnabledProvider.notifier).set(v),
              activeColor: AppColors.green700,
            ),
          ),
          _SettingsTile(
            icon: Icons.rule_rounded,
            title: 'Rigueur de la correction',
            subtitle: strictCorrection
                ? 'Strict — rouge ET orange (imprécis) sont repris'
                : 'Tolérant — seul le rouge (mot faux) est repris',
            trailing: Switch.adaptive(
              value: strictCorrection,
              onChanged: (v) =>
                  ref.read(strictCorrectionProvider.notifier).set(v),
              activeColor: AppColors.green700,
            ),
          ),
          _SettingsTile(
            icon: Icons.repeat_on_rounded,
            title: 'Répétitions de mémorisation',
            subtitle:
                'Répéter le verset × $repeatDrillCount avant de tester ta mémoire',
            onTap: () =>
                _pickRepeatDrillCount(context, ref, repeatDrillCount),
          ),

          const SizedBox(height: 12),
          _SectionHeader('Affichage'),
          _SettingsTile(
            icon: Icons.color_lens_rounded,
            title: 'Couleurs Tajweed',
            subtitle: 'Coloration selon les règles de récitation',
            trailing: Switch.adaptive(
              value: true, // TODO: persist
              onChanged: (_) {},
              activeColor: AppColors.green700,
            ),
          ),

          const SizedBox(height: 12),
          _SectionHeader('Application'),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'Coran Karim',
            subtitle: 'Version 1.0.0  •  Propulsé par Gemma 4 + Whisper',
          ),
        ],
      ),
    );
  }

  String _repeatDesc(RepeatMode mode, int count) {
    switch (mode) {
      case RepeatMode.off: return 'Désactivé';
      case RepeatMode.verse: return count == 0 ? 'Verset — infini' : 'Verset × $count';
      case RepeatMode.surah: return 'Sourate entière';
    }
  }

  void _pickSpeed(BuildContext context, double current, PlayerNotifier n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SpeedSheet(current: current, onPick: (s) {
        n.setSpeed(s);
        Navigator.pop(context);
      }),
    );
  }

  void _pickRepeat(BuildContext context, PlayerNotifier n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RepeatSheet(onPick: (mode, count) {
        n.setRepeatMode(mode);
        n.setRepeatCount(count);
        Navigator.pop(context);
      }),
    );
  }

  void _pickRepeatDrillCount(BuildContext context, WidgetRef ref, int current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RepeatDrillCountSheet(
        current: current,
        onPick: (n) {
          ref.read(repeatDrillCountProvider.notifier).set(n);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(title.toUpperCase(),
            style: GoogleFonts.manrope(
                fontSize: 10,
                color: AppColors.green700,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile({
    required this.icon, required this.title, required this.subtitle,
    this.trailing, this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cream300),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: AppColors.green50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.green700, size: 20),
          ),
          title: Text(title,
              style: GoogleFonts.manrope(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
          subtitle: Text(subtitle,
              style: GoogleFonts.manrope(
                  fontSize: 11, color: AppColors.inkLight)),
          trailing: trailing ??
              (onTap != null
                  ? const Icon(Icons.chevron_right, color: AppColors.inkLight)
                  : null),
          onTap: onTap,
        ),
        ),
      );
}

class _SpeedSheet extends StatelessWidget {
  final double current;
  final void Function(double) onPick;
  const _SpeedSheet({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vitesse de lecture',
                style: GoogleFonts.fraunces(
                    fontSize: 16, color: AppColors.brassLight)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                final active = s == current;
                return GestureDetector(
                  onTap: () => onPick(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? AppColors.brass : AppColors.green700,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text('${s}×',
                        style: GoogleFonts.manrope(
                            color: active ? AppColors.green900 : AppColors.cream,
                            fontWeight: FontWeight.w700)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
}

class _RepeatSheet extends StatelessWidget {
  final void Function(RepeatMode, int) onPick;
  const _RepeatSheet({required this.onPick});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mode de répétition',
                style: GoogleFonts.fraunces(
                    fontSize: 16, color: AppColors.brassLight)),
            const SizedBox(height: 16),
            ...[
              (RepeatMode.off,   0,  'Pas de répétition'),
              (RepeatMode.verse, 3,  'Verset × 3'),
              (RepeatMode.verse, 5,  'Verset × 5'),
              (RepeatMode.verse, 10, 'Verset × 10'),
              (RepeatMode.verse, 0,  'Verset × ∞'),
              (RepeatMode.surah, 0,  'Sourate entière'),
            ].map(((RepeatMode, int, String) item) => ListTile(
                  title: Text(item.$3,
                      style: GoogleFonts.manrope(color: AppColors.cream)),
                  onTap: () => onPick(item.$1, item.$2),
                  dense: true,
                )),
            const SizedBox(height: 8),
          ],
        ),
      );
}

class _RepeatDrillCountSheet extends StatefulWidget {
  final int current;
  final void Function(int) onPick;
  const _RepeatDrillCountSheet({required this.current, required this.onPick});

  @override
  State<_RepeatDrillCountSheet> createState() =>
      _RepeatDrillCountSheetState();
}

class _RepeatDrillCountSheetState extends State<_RepeatDrillCountSheet> {
  late int _value = widget.current;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Répétitions de mémorisation',
                style: GoogleFonts.fraunces(
                    fontSize: 16, color: AppColors.brassLight)),
            const SizedBox(height: 4),
            Text(
              'Nombre de fois à répéter le verset avant de tester ta mémoire (1 à $kRepeatDrillCountMax).',
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.cream.withAlpha(180)),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _value > kRepeatDrillCountMin
                      ? () => setState(() => _value--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: AppColors.cream,
                  disabledColor: AppColors.cream.withAlpha(70),
                  iconSize: 30,
                ),
                SizedBox(
                  width: 64,
                  child: Text('$_value',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.cream)),
                ),
                IconButton(
                  onPressed: _value < kRepeatDrillCountMax
                      ? () => setState(() => _value++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: AppColors.cream,
                  disabledColor: AppColors.cream.withAlpha(70),
                  iconSize: 30,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => widget.onPick(_value),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brass,
                  foregroundColor: AppColors.green900,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                child: Text('Valider',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
}
