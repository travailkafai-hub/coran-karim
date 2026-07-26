import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/prayer_settings.dart';
import '../providers/prayer_settings_provider.dart';
import '../theme/app_theme.dart';

const _methodLabels = {
  PrayerCalculationMethod.muslimWorldLeague: 'Muslim World League',
  PrayerCalculationMethod.ummAlQura: 'Umm al-Qura (Golfe)',
  PrayerCalculationMethod.egyptian: 'Égyptienne',
};

const _prayerLabels = {
  PrayerName.fajr: 'Sobh',
  PrayerName.dhuhr: 'Dhouhr',
  PrayerName.asr: 'Asr',
  PrayerName.maghrib: 'Maghrib',
  PrayerName.isha: 'Ichaa',
};

class PrayerTimesSettingsScreen extends ConsumerWidget {
  const PrayerTimesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(prayerSettingsProvider);
    final notifier = ref.read(prayerSettingsProvider.notifier);
    final settings = state.settings;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        title: Text('Horaires de prière',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.ink)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLocationCard(context, state, notifier),
          const SizedBox(height: 16),
          if (state.today != null) _buildTodayTimes(state.today!),
          const SizedBox(height: 20),
          _sectionTitle('Méthode de calcul'),
          _buildMethodSelector(settings, notifier),
          const SizedBox(height: 20),
          _sectionTitle('Adhan par prière'),
          ...PrayerName.values.map((p) => SwitchListTile.adaptive(
                value: settings.adhanEnabled[p] ?? true,
                onChanged: (v) => notifier.setAdhanEnabled(p, v),
                title: Text(_prayerLabels[p]!,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                activeColor: AppColors.green700,
              )),
          SwitchListTile.adaptive(
            value: settings.vibrateEnabled,
            onChanged: notifier.setVibrateEnabled,
            title: Text('Vibreur', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            subtitle: Text('Fait vibrer le téléphone en plus du son de l\'adhan',
                style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight)),
            activeColor: AppColors.green700,
            secondary: const Icon(Icons.vibration_rounded, color: AppColors.green700),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Rappel avant chaque prière'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Une notification distincte de l\'adhan, ${settings.reminderMinutesBefore} min avant l\'heure -- utile pour se préparer (se réveiller pour Sobh, s\'organiser pour les autres).',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight),
            ),
          ),
          if (settings.reminderEnabled.values.any((v) => v))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: [10, 15, 20, 30].map((m) {
                  final selected = settings.reminderMinutesBefore == m;
                  return ChoiceChip(
                    label: Text('$m min'),
                    selected: selected,
                    selectedColor: AppColors.green100,
                    onSelected: (_) => notifier.setReminderMinutesBefore(m),
                  );
                }).toList(),
              ),
            ),
          ...PrayerName.values.map((p) => SwitchListTile.adaptive(
                value: settings.reminderEnabled[p] ?? false,
                onChanged: (v) => notifier.setReminderEnabled(p, v),
                title: Text(_prayerLabels[p]!,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                activeColor: AppColors.green700,
              )),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s,
            style: GoogleFonts.manrope(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.green700)),
      );

  Widget _buildLocationCard(
      BuildContext context, PrayerState state, PrayerSettingsNotifier notifier) {
    final (icon, text) = switch (state.locationStatus) {
      PrayerLocationStatus.loading => (Icons.hourglass_top_rounded, 'Localisation en cours…'),
      PrayerLocationStatus.ready => (Icons.location_on_rounded,
          'Position acquise (${state.lat!.toStringAsFixed(2)}, ${state.lng!.toStringAsFixed(2)})'),
      PrayerLocationStatus.serviceDisabled => (Icons.location_off_rounded, 'GPS désactivé — active-le dans les réglages'),
      PrayerLocationStatus.permissionDenied => (Icons.location_off_rounded, 'Permission de localisation refusée'),
      PrayerLocationStatus.error => (Icons.error_outline_rounded, 'Position indisponible'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.green700),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink))),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.green700),
            onPressed: notifier.refreshLocation,
          ),
        ],
      ),
    );
  }

  Widget _buildTodayTimes(Map<PrayerName, DateTime> today) {
    String fmt(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: PrayerName.values
            .map((p) => Column(
                  children: [
                    Text(_prayerLabels[p]!,
                        style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight)),
                    const SizedBox(height: 2),
                    Text(fmt(today[p]!),
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppColors.green700)),
                  ],
                ))
            .toList(),
      ),
    );
  }

  Widget _buildMethodSelector(PrayerSettings settings, PrayerSettingsNotifier notifier) {
    // null = automatique (position GPS) ; sinon = methode figee manuellement.
    // Un seul groupe de radio sur un type unique (PrayerCalculationMethod?)
    // -- IMPORTANT : ne pas utiliser un bool partage entre 4 tuiles, ca
    // selectionnerait les 3 methodes manuelles simultanement (meme valeur
    // groupValue=false pour les 3).
    final PrayerCalculationMethod? current = settings.methodIsAuto ? null : settings.method;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cream300),
      ),
      child: Column(
        children: [
          RadioListTile<PrayerCalculationMethod?>(
            value: null,
            groupValue: current,
            onChanged: (_) => notifier.setMethodAuto(),
            title: Text('Automatique (selon la position GPS)',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            subtitle: Text('Actuellement : ${_methodLabels[settings.method]}',
                style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight)),
            activeColor: AppColors.green700,
          ),
          ..._methodLabels.entries.map((e) => RadioListTile<PrayerCalculationMethod?>(
                value: e.key,
                groupValue: current,
                onChanged: (_) => notifier.setMethod(e.key),
                title: Text(e.value, style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                activeColor: AppColors.green700,
              )),
        ],
      ),
    );
  }
}
