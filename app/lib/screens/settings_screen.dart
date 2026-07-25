import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/reciter.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../providers/recitation_provider.dart' show recitationVerifierProvider;
import '../services/voice_lora_clip_service.dart';
import '../theme/app_theme.dart';
import 'prayer_times_settings_screen.dart';
import 'qibla_screen.dart';
import 'reciter_select_screen.dart';
import 'voice_calibration_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final locale = ref.watch(appLocaleProvider);
    final reciter = ref.watch(playerProvider).reciter;
    // En arabe, aucun mot latin à l'écran (règle verrouillée REFONTE_IHM.md
    // §7bis) : le nom du récitateur et son style passent en arabe ; en fr/en,
    // le nom romanisé + le style (termes techniques déjà transparents dans
    // les deux langues) restent, avec le nom arabe en flourish à droite.
    final reciterStyleLabel = reciter.style == 'Mujawwad'
        ? t.settingsStyleMujawwad
        : t.settingsStyleMurattal;
    final reciterSubtitle = locale == 'ar'
        ? '${reciter.nameAr} • $reciterStyleLabel'
        : '${reciter.nameFr}  •  ${reciter.style}';
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        title: Text(t.settingsTitle,
            style: GoogleFonts.scheherazadeNew(
                fontSize: 22, color: AppColors.brassLight)),
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Historique de cette section (ne pas re-déplacer sans relire) :
          //  - 2026-07-19 : "Mode de vérification" retiré d'ici (« alléger les
          //    paramètres globaux »).
          //  - 2026-07-20 (matin) : toute la section « Récitation » déplacée
          //    dans le hub Coach.
          //  - 2026-07-20 (correction utilisateur) : partage plus juste, sur
          //    le critère « à quoi sert ce réglage ? » plutôt que « où est
          //    l'écran ? » :
          //      * paramètres de VÉRIFICATION (mode tajwid, sensibilité,
          //        rigueur, correction auto, suivre sans bloquer) -> sur
          //        l'ÉCRAN DE RÉCITATION, derrière une icône : ils ne servent
          //        que là, et souvent EN COURS de récitation ;
          //      * RÉCITATEUR -> reste ici (ci-dessous) : transverse (écoute,
          //        souffleur, corrections audio), pas propre à la récitation.
          _SectionHeader(t.settingsSectionAudio),
          // Le RÉCITATEUR reste ici, dans les réglages généraux (précision
          // utilisateur 2026-07-20 : « le récitateur c'est dans réglages
          // générale »). C'est un choix TRANSVERSE : il sert à l'écoute d'une
          // sourate, au souffleur, aux corrections audio -- pas seulement à la
          // récitation. Les paramètres de VÉRIFICATION, eux, vivent sur
          // l'écran de récitation (icône dédiée), cf. REFONTE_IHM.md §11.
          _SettingsTile(
            icon: Icons.record_voice_over,
            title: t.settingsReciterTitle,
            subtitle: reciterSubtitle,
            // Flourish calligraphique -- uniquement en fr/en (en arabe, le
            // nom arabe est déjà le sous-titre principal, pas de doublon).
            trailing: locale == 'ar'
                ? null
                : Text(reciter.nameAr,
                    textDirection: TextDirection.rtl,
                    style: GoogleFonts.scheherazadeNew(
                        fontSize: 14, color: AppColors.green700)),
            onTap: () async {
              final picked = await Navigator.push<Reciter>(
                context,
                MaterialPageRoute(
                    builder: (_) => ReciterSelectScreen(
                        currentId: ref.read(playerProvider).reciter.id)),
              );
              if (picked != null) {
                ref.read(playerProvider.notifier).setReciter(picked);
              }
            },
          ),

          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionPrayer),
          _SettingsTile(
            icon: Icons.explore_rounded,
            title: t.settingsQiblaTitle,
            subtitle: t.settingsQiblaSubtitle,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const QiblaScreen())),
          ),
          _SettingsTile(
            icon: Icons.access_time_rounded,
            title: 'Horaires de prière',
            subtitle: 'Adhan programmé, rappel avant Sobh',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PrayerTimesSettingsScreen())),
          ),

          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionVoicePersonalization),
          _SettingsTile(
            icon: Icons.tune_rounded,
            title: t.settingsVoiceCalibTitle,
            subtitle: t.settingsVoiceCalibSubtitle,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const VoiceCalibrationScreen())),
          ),
          const _VoiceLoraClipsTile(),

          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionDisplay),
          _SettingsTile(
            icon: Icons.color_lens_rounded,
            title: t.settingsTajweedColorsTitle,
            subtitle: t.settingsTajweedColorsSubtitle,
            trailing: Switch.adaptive(
              value: true, // TODO: persist
              onChanged: (_) {},
              activeColor: AppColors.green700,
            ),
          ),

          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionDiagnostic),
          const _DiagnosticTile(),

          const SizedBox(height: 12),
          _SectionHeader(t.settingsSectionApp),
          _SettingsTile(
            icon: Icons.language_rounded,
            title: t.settingsLocaleTitle,
            subtitle: _localeLabel(locale),
            onTap: () => _pickLocale(context, ref),
          ),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: t.appTitle,
            subtitle: t.settingsAboutSubtitle,
          ),
        ],
      ),
    );
  }

  String _localeLabel(String locale) => switch (locale) {
        'ar' => 'العربية',
        'en' => 'English',
        _ => 'Français',
      };

  void _pickLocale(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.green800,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LocaleSheet(
        current: ref.read(appLocaleProvider),
        onPick: (locale) {
          ref.read(appLocaleProvider.notifier).set(locale);
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

/// Interrupteur du diagnostic : journal fichier (Dart + natif) ET capture des
/// WAV de chaque segment figé, pilotés ensemble.
///
/// Demande utilisateur 2026-07-25 : « je veux m'assurer que ces retards ne
/// sont pas dus à la création des logs ». Mesuré ce jour-là : 22 à 32
/// écritures fichier synchrones par seconde côté Dart, plus les lignes natives
/// émises depuis le thread d'inférence. Il faut pouvoir éteindre
/// l'instrumentation et refaire la mesure, sinon on ne peut pas distinguer le
/// retard de la chaîne ASR du retard causé par son observation.
///
/// Le natif est poussé ICI en plus du démarrage de session
/// (RecitationNotifier._applyDiagnosticCapture) pour que le basculement soit
/// effectif immédiatement, sans avoir à relancer une récitation.
class _DiagnosticTile extends ConsumerWidget {
  const _DiagnosticTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final on = ref.watch(diagnosticEnabledProvider);
    return _SettingsTile(
      icon: Icons.bug_report_outlined,
      title: t.settingsDiagnosticTitle,
      subtitle: on
          ? t.settingsDiagnosticSubtitleOn
          : t.settingsDiagnosticSubtitleOff,
      trailing: Switch.adaptive(
        value: on,
        activeColor: AppColors.green700,
        onChanged: (v) {
          ref.read(diagnosticEnabledProvider.notifier).set(v);
          unawaited(ref.read(recitationVerifierProvider).setLogEnabled(v));
        },
      ),
    );
  }
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

  // Captures de DIAGNOSTIC des récitations depuis le 2026-07-25 (et non plus
  // les clips "vérifiés corrects" du mini-LoRA, objectif abandonné) : on
  // compte/exporte désormais TOUS les enregistrements conservés, cf.
  // VoiceLoraClipService.newRecitationCaptureDir.
  Future<void> _refresh() async {
    final c = await _service.recitationClipCount();
    if (mounted) setState(() => _count = c);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final ok = await _service.exportRecitationCaptures();
    if (!mounted) return;
    setState(() => _exporting = false);
    final t = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? t.settingsExportStarted : t.settingsExportCancelled),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final count = _count;
    return _SettingsTile(
      icon: Icons.mic_external_on_rounded,
      title: t.settingsMyClipsTitle,
      subtitle: count == null
          ? t.settingsMyClipsLoading
          : count == 0
              ? t.settingsMyClipsEmpty
              : t.settingsMyClipsCount(count),
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

class _LocaleSheet extends StatelessWidget {
  final String current;
  final void Function(String) onPick;
  const _LocaleSheet({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.settingsLocaleTitle,
                style: GoogleFonts.fraunces(
                    fontSize: 16, color: AppColors.brassLight)),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)!.settingsLocaleSheetDescription,
              style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.cream.withAlpha(200)),
            ),
            const SizedBox(height: 16),
            for (final (code, label) in const [
              ('ar', 'العربية'),
              ('fr', 'Français'),
              ('en', 'English'),
            ])
              ListTile(
                title: Text(label,
                    style: GoogleFonts.manrope(
                        color: AppColors.cream,
                        fontWeight: code == current ? FontWeight.w700 : FontWeight.normal)),
                trailing: code == current
                    ? const Icon(Icons.check_rounded, color: AppColors.brass)
                    : null,
                onTap: () => onPick(code),
                dense: true,
              ),
          ],
        ),
      );
}

