import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/reciter.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../services/voice_lora_clip_service.dart';
import '../theme/app_theme.dart';
import 'qibla_screen.dart';
import 'reciter_select_screen.dart';
import 'voice_calibration_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final autoCorrection = ref.watch(autoCorrectionEnabledProvider);
    final strictCorrection = ref.watch(strictCorrectionProvider);
    final followWithoutBlocking = ref.watch(followWithoutBlockingProvider);
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
          // "Mode de vérification" retiré d'ici (2026-07-19, retour
          // utilisateur : "alléger les paramètres globaux", chaque page a
          // son propre paramétrage §2) -- déplacé dans le Coach
          // (coach_screen.dart::_Header, icône à côté du titre), l'écran où
          // la vérification a réellement lieu.
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
          // "Vitesse de lecture" et "Répétition" retirées d'ici (2026-07-19,
          // retour utilisateur : "pas de redondance, chaque module a les
          // paramètres propres") -- déplacées dans widgets/
          // reading_settings_sheet.dart (accessible depuis "Plus" en
          // lecture), à côté du défilement automatique avec lequel elles
          // forment un seul groupe cohérent "lecture".
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
            icon: Icons.fast_forward_rounded,
            title: 'Suivre sans bloquer',
            subtitle: followWithoutBlocking
                ? 'Audio de correction rejoué une fois — ensuite, avance librement même sans reprise exacte'
                : 'Désactivé — chaque échec rejoue l\'audio et force à reprendre le mot',
            trailing: Switch.adaptive(
              value: followWithoutBlocking,
              onChanged: (v) =>
                  ref.read(followWithoutBlockingProvider.notifier).set(v),
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
          _SectionHeader('Prière'),
          _SettingsTile(
            icon: Icons.explore_rounded,
            title: 'Direction de la Qibla',
            subtitle: 'Boussole vers la Mecque depuis ta position',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const QiblaScreen())),
          ),

          const SizedBox(height: 12),
          _SectionHeader('Personnalisation vocale'),
          _SettingsTile(
            icon: Icons.tune_rounded,
            title: 'Calibration voix (lettres confusables)',
            subtitle: 'Enregistre ~14 mots exprès bien/mal prononcés (ص/س, ط/ت...) pour affiner ta sensibilité',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const VoiceCalibrationScreen())),
          ),
          const _VoiceLoraClipsTile(),

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

/// Clips de récitation VÉRIFIÉS CORRECTS (sessions de référence validées),
/// collectés en vue d'un futur mini-LoRA de personnalisation vocale
/// (FONCTIONNALITES_FUTURES.md, "Personnalisation voix -- niveau 3",
/// implémenté 2026-07-12). Export MANUEL uniquement (partage natif) -- aucune
/// synchronisation automatique, donnée vocale sensible.
class _VoiceLoraClipsTile extends StatefulWidget {
  const _VoiceLoraClipsTile();

  @override
  State<_VoiceLoraClipsTile> createState() => _VoiceLoraClipsTileState();
}

class _VoiceLoraClipsTileState extends State<_VoiceLoraClipsTile> {
  final _service = VoiceLoraClipService();
  int? _count;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final c = await _service.clipCount();
    if (mounted) setState(() => _count = c);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final ok = await _service.exportViaShare();
    if (!mounted) return;
    setState(() => _exporting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Export lancé — choisis où envoyer le fichier.'
          : 'Export annulé ou aucun clip disponible.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return _SettingsTile(
      icon: Icons.mic_external_on_rounded,
      title: 'Mes clips vérifiés',
      subtitle: count == null
          ? 'Chargement…'
          : count == 0
              ? 'Aucun clip pour l\'instant — enregistrés lors de tes récitations de référence'
              : '$count clip${count > 1 ? "s" : ""} vérifié${count > 1 ? "s" : ""} — exporter pour personnaliser le modèle à ta voix',
      trailing: _exporting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.green700))
          : const Icon(Icons.ios_share_rounded, color: AppColors.green700),
      onTap: (count != null && count > 0 && !_exporting) ? _export : null,
    );
  }
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
