import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/prayer_settings.dart';
import '../providers/prayer_settings_provider.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../l10n/prayer_labels.dart';

const _methodLabels = {
  PrayerCalculationMethod.muslimWorldLeague: 'Muslim World League',
  PrayerCalculationMethod.ummAlQura: 'Umm al-Qura (Golfe)',
  PrayerCalculationMethod.egyptian: 'Égyptienne',
  PrayerCalculationMethod.franceUoif: 'France (UOIF, 12°)',
};

// Libellés courts -- les chips de sélection de méthode (une ligne) n'ont pas
// la place pour le nom complet ci-dessus.
const _methodShortLabels = {
  PrayerCalculationMethod.muslimWorldLeague: 'MWL',
  PrayerCalculationMethod.ummAlQura: 'Umm al-Qura',
  PrayerCalculationMethod.egyptian: 'Égyptienne',
  PrayerCalculationMethod.franceUoif: 'France (UOIF)',
};

const _prayerLabels = {
  PrayerName.fajr: 'Sobh',
  PrayerName.dhuhr: 'Dhouhr',
  PrayerName.asr: 'Asr',
  PrayerName.maghrib: 'Maghrib',
  PrayerName.isha: 'Ichaa',
};

const _prayerIcons = {
  PrayerName.fajr: Icons.nightlight_round,
  PrayerName.dhuhr: Icons.wb_sunny_rounded,
  PrayerName.asr: Icons.light_mode_rounded,
  PrayerName.maghrib: Icons.wb_twilight_rounded,
  PrayerName.isha: Icons.dark_mode_rounded,
};

const _reminderChoices = [5, 10, 15, 20, 30, 45];

// Le calcul de la prochaine priere vivait ICI, en prive. Il a ete DEPLACE le
// 2026-08-19 sur `PrayerState` (extension `ProchainePriere`, cf.
// prayer_settings_provider.dart) pour que la liste des sourates l'utilise sans
// le recopier. Sa regle et son commentaire d'origine ont suivi tels quels --
// notamment « apres Ichaa, la prochaine est le Sobh de DEMAIN », qui est la
// seule partie non evidente.

class PrayerTimesSettingsScreen extends ConsumerWidget {
  const PrayerTimesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(prayerSettingsProvider);
    final notifier = ref.read(prayerSettingsProvider.notifier);
    final settings = state.settings;
    final next = state.prochainePriere;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Text(AppLocalizations.of(context)!.prayerTimesTitle,
            style: GoogleFonts.scheherazadeNew(fontSize: 22, color: AppColors.brassLight)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (next != null) _buildNextPrayerHero(context, next),
          const SizedBox(height: 12),
          if (state.today != null) KeyedSubtree(
            key: const ValueKey('guide.prayer.times'),
            child: _buildTodayTimes(context, state.today!, next?.name)),
          const SizedBox(height: 12),
          KeyedSubtree(key: const ValueKey('guide.prayer.location'),
            child: _buildLocationAndMethod(context, state, settings, notifier)),
          const SizedBox(height: 16),
          _sectionTitle('Notifications'),
          KeyedSubtree(key: const ValueKey('guide.prayer.notifications'),
            child: _card(child: _NotificationsTable(settings: settings, notifier: notifier))),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cream300),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(s.toUpperCase(),
            style: GoogleFonts.manrope(
                fontSize: 10, color: AppColors.green700, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      );

  /// Bandeau vedette : prochaine prière + compte à rebours. C'est la première
  /// chose que l'utilisateur vient chercher sur cet écran -- avant même la
  /// liste des cinq horaires du jour.
  // `context` en parametre (2026-09-09) : cette methode affiche desormais
  // un libelle traduit, et `ConsumerWidget` n'expose pas `context` hors de
  // `build`.
  Widget _buildNextPrayerHero(
      BuildContext context, ({PrayerName name, DateTime time}) next) {
    final local = next.time.toLocal();
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final remaining = next.time.difference(DateTime.now());
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final countdown = h > 0 ? 'dans ${h}h${m.toString().padLeft(2, '0')}' : 'dans $m min';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.green900, AppColors.green700],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(_prayerIcons[next.name], color: AppColors.brassLight, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.prayerTimesNext,
                    style: GoogleFonts.manrope(
                        fontSize: 10, color: AppColors.cream.withAlpha(200), fontWeight: FontWeight.w600)),
                Text(nomPriere(context, next.name),
                    style: GoogleFonts.fraunces(
                        fontSize: 19, color: AppColors.cream, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(hm,
                  style: GoogleFonts.manrope(
                      fontSize: 21, color: AppColors.brassLight, fontWeight: FontWeight.w700)),
              Text(countdown,
                  style: GoogleFonts.manrope(fontSize: 10, color: AppColors.cream.withAlpha(200))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayTimes(BuildContext context,
      Map<PrayerName, DateTime> today, PrayerName? current) {
    String fmt(DateTime d) {
      final local = d.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: PrayerName.values.map((p) {
            final active = p == current;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.green50 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(_prayerIcons[p],
                      size: 14, color: active ? AppColors.green700 : AppColors.inkLight),
                  const SizedBox(height: 2),
                  Text(nomPriere(context, p),
                      style: GoogleFonts.manrope(
                          fontSize: 10,
                          color: active ? AppColors.green700 : AppColors.inkLight,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                  Text(fmt(today[p]!),
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: active ? AppColors.green700 : AppColors.ink)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Position + méthode de calcul réunies dans une seule carte compacte : la
  /// position tient sur une ligne, la méthode devient une rangée de chips
  /// (au lieu de 5 RadioListTile empilées) -- gain vertical net, demande
  /// utilisateur 2026-08-08 ("travail pour que le design soit plus compact").
  Widget _buildLocationAndMethod(BuildContext context, PrayerState state,
      PrayerSettings settings, PrayerSettingsNotifier notifier) {
    final (icon, text) = switch (state.locationStatus) {
      PrayerLocationStatus.loading => (Icons.hourglass_top_rounded, 'Localisation en cours…'),
      PrayerLocationStatus.ready => (Icons.location_on_rounded,
          'Position acquise (${state.lat!.toStringAsFixed(2)}, ${state.lng!.toStringAsFixed(2)})'),
      PrayerLocationStatus.serviceDisabled => (Icons.location_off_rounded, 'GPS désactivé — active-le dans les réglages'),
      PrayerLocationStatus.permissionDenied => (Icons.location_off_rounded, 'Permission de localisation refusée'),
      PrayerLocationStatus.error => (Icons.error_outline_rounded, 'Position indisponible'),
    };
    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.green700, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(text,
                        style: GoogleFonts.manrope(fontSize: 11, color: AppColors.ink))),
                InkWell(
                  onTap: notifier.refreshLocation,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh_rounded, color: AppColors.green700, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _methodChip(
                  label: 'Auto',
                  selected: settings.methodIsAuto,
                  onTap: notifier.setMethodAuto,
                ),
                ..._methodShortLabels.entries.map((e) => _methodChip(
                      label: e.value,
                      selected: !settings.methodIsAuto && settings.method == e.key,
                      onTap: () => notifier.setMethod(e.key),
                    )),
              ],
            ),
            if (settings.methodIsAuto) ...[
              const SizedBox(height: 4),
              Text(AppLocalizations.of(context)!
                  .prayerTimesDetected(nomMethode(context, settings.method)),
                  style: GoogleFonts.manrope(fontSize: 10, color: AppColors.inkLight)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _methodChip({required String label, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.green100 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.green700 : AppColors.cream300),
        ),
        child: Text(label,
            style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.green700 : AppColors.inkLight)),
      ),
    );
  }

}

/// Sorti de la classe (2026-08-23) pour être réutilisable par
/// [_prayerNotificationRow] -- fonction pure, aucune dépendance à l'état de
/// l'écran.
Widget _toggleIcon({
  required bool active,
  required IconData onIcon,
  required IconData offIcon,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? AppColors.green50 : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(active ? onIcon : offIcon,
          size: 17, color: active ? AppColors.green700 : AppColors.inkLight),
    ),
  );
}

/// Table des notifications : une ligne PAR prière (icône, nom, heure, bascule
/// adhan, bascule rappel + délai propre à CETTE prière -- demande utilisateur
/// 2026-08-08, remplace le délai unique partagé par les 5). Remplace les 3
/// blocs d'origine (section adhan, vibreur, section rappel + description +
/// chips) par une seule carte.
///
/// La bascule vibreur globale, puis un lien « Avancé » qui ajoute une 3ᵉ
/// icône (vibreur) à CHACUNE des lignes déjà affichées ci-dessus -- pas une
/// seconde liste des 5 prières en dessous (2026-08-23, corrigé après retour
/// utilisateur : « tu appliques bêtement » sur la première version, qui
/// dupliquait noms/icônes déjà visibles juste au-dessus pour une seule icône
/// en plus).
///
/// ⚠️ CE PARAGRAPHE DÉCRIT L'ÉTAT D'AVANT LE 2026-09-04 : la bascule globale
/// et le dépliant « Avancé » ont été RETIRÉS ce jour-là (« plus besoin de
/// garder le toggle vibreur et avancé »). Ils étaient devenus redondants dès
/// que le vibreur est passé en 2ᵉ icône de chaque ligne, toujours visible
/// (2026-09-03) : trois façons de régler la même chose, dont un dépliant qui
/// ne révélait plus rien. Le réglage vit désormais à un seul endroit, la ligne
/// de la prière. Conservé pour garder trace de ce qui a existé et pourquoi.
class _NotificationsTable extends StatefulWidget {
  final PrayerSettings settings;
  final PrayerSettingsNotifier notifier;
  const _NotificationsTable({required this.settings, required this.notifier});

  @override
  State<_NotificationsTable> createState() => _NotificationsTableState();
}

class _NotificationsTableState extends State<_NotificationsTable> {
  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final notifier = widget.notifier;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.notifications_active_rounded, size: 12, color: AppColors.inkLight),
              const SizedBox(width: 3),
              Text('adhan',
                  style: GoogleFonts.manrope(fontSize: 9, color: AppColors.inkLight)),
              // ── L'EN-TETE ANNONCAIT DEUX COLONNES SUR TROIS (2026-09-04) ─
              // Le vibreur est passe en 2ᵉ icone de chaque ligne le
              // 2026-09-03, toujours visible -- mais son en-tete etait reste
              // conditionne au mode avance, donc absent. Trois icones, deux
              // libelles : la colonne du milieu n'avait pas de nom.
              const SizedBox(width: 14),
              Icon(Icons.vibration_rounded, size: 12, color: AppColors.inkLight),
              const SizedBox(width: 3),
              Text('vibreur',
                  style: GoogleFonts.manrope(fontSize: 9, color: AppColors.inkLight)),
              const SizedBox(width: 14),
              Icon(Icons.alarm_rounded, size: 12, color: AppColors.inkLight),
              const SizedBox(width: 3),
              Text('rappel',
                  style: GoogleFonts.manrope(fontSize: 9, color: AppColors.inkLight)),
            ],
          ),
        ),
        // ── PLUS DE BASCULE GLOBALE NI DE SECTION « AVANCE » (2026-09-04)
        //
        // Demande utilisateur, capture a l'appui : « plus besoin de garder le
        // toggle vibreur et avance ».
        //
        // Les deux etaient devenus redondants le 2026-09-03, quand le vibreur
        // est passe en 2ᵉ icone de CHAQUE ligne, toujours visible. Restaient
        // donc trois facons de regler la meme chose : l'icone de la ligne, une
        // bascule globale qui les ecrasait toutes les cinq, et un depliant
        // « Avance » qui ne revelait plus rien (son unique role, ajouter la
        // colonne vibreur, n'avait plus d'objet). Un reglage a un seul endroit.
        ...PrayerName.values
            .map((p) => _prayerNotificationRow(context, p, settings, notifier)),
      ],
    );
  }
}

Widget _prayerNotificationRow(BuildContext context,
    PrayerName p, PrayerSettings settings, PrayerSettingsNotifier notifier) {
  final adhanOn = settings.adhanEnabled[p] ?? true;
  final reminderOn = settings.reminderEnabled[p] ?? false;
  final minutes = settings.reminderMinutesBefore[p] ?? 15;
  final vibrateOn = settings.vibrateEnabled[p] ?? true;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    child: Row(
      children: [
        Icon(_prayerIcons[p], size: 16, color: AppColors.inkLight),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          child: Text(nomPriere(context, p),
              style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        _toggleIcon(
          active: adhanOn,
          onIcon: Icons.notifications_active_rounded,
          offIcon: Icons.notifications_off_rounded,
          onTap: () => notifier.setAdhanEnabled(p, !adhanOn),
        ),
        const SizedBox(width: 4),
        // ── LE VIBREUR JUSTE A COTE DE L'ADHAN (2026-09-03) ───────────────
        // Demande utilisateur : « rajoute signe vibreur a cote de chaque
        // priere, a cote de l'adhan ». Il etait la 3ᵉ icone ET cache derriere
        // le mode avance depuis le 2026-08-23 : personne ne le trouvait.
        // Il passe en 2ᵉ position, toujours visible -- le son et la vibration
        // sont deux facons d'etre prevenu, elles se lisent ensemble.
        _toggleIcon(
          active: vibrateOn,
          onIcon: Icons.vibration_rounded,
          offIcon: Icons.phone_android_rounded,
          onTap: () => notifier.setVibrateEnabledForPrayer(p, !vibrateOn),
        ),
        const SizedBox(width: 4),
        _toggleIcon(
          active: reminderOn,
          onIcon: Icons.alarm_on_rounded,
          offIcon: Icons.alarm_off_rounded,
          onTap: () => notifier.setReminderEnabled(p, !reminderOn),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<int>(
          enabled: reminderOn,
          initialValue: minutes,
          onSelected: (m) => notifier.setReminderMinutesBefore(p, m),
          itemBuilder: (_) => _reminderChoices
              .map((m) => PopupMenuItem(
                    value: m,
                    child: Text('$m min',
                        style: GoogleFonts.manrope(fontSize: 13)),
                  ))
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: reminderOn ? AppColors.brass.withAlpha(28) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: reminderOn ? null : Border.all(color: AppColors.cream300),
            ),
            child: Text('$minutes’',
                style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: reminderOn ? AppColors.brass : AppColors.inkLight)),
          ),
        ),
      ],
    ),
  );
}
