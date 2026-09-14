import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../l10n/prayer_labels.dart';
import '../models/prayer_settings.dart';
import '../providers/prayer_settings_provider.dart';
import '../screens/prayer_times_settings_screen.dart';
import '../screens/qibla_screen.dart';
import '../services/qibla_service.dart';
import '../theme/app_theme.dart';

// ChGPT: display-only composition; prayer calculations and ASR stay unchanged.
class HomePrayerPanel extends ConsumerStatefulWidget {
  const HomePrayerPanel({super.key});
  @override
  ConsumerState<HomePrayerPanel> createState() => _HomePrayerPanelState();
}

class _HomePrayerPanelState extends ConsumerState<HomePrayerPanel>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _visible = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _syncClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    _syncClock();
  }

  void _syncClock() {
    _timer?.cancel();
    if (!_foreground || !_visible) return;
    _refreshDate();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _refreshDate();
    });
  }

  Future<void> _refreshDate() async {
    final state = ref.read(prayerSettingsProvider);
    final date = state.today?.values.firstOrNull?.toLocal();
    final now = DateTime.now();
    if (_refreshing ||
        date == null ||
        DateUtils.isSameDay(date, now) ||
        state.locationStatus != PrayerLocationStatus.ready) {
      return;
    }
    _refreshing = true;
    // Defer provider writes outside dependency/build notifications.
    await Future<void>.delayed(Duration.zero);
    try {
      if (mounted) {
        await ref.read(prayerSettingsProvider.notifier).refreshLocation();
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(prayerSettingsProvider);
    void openQibla() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QiblaScreen()));
    final bearing =
        state.lat != null &&
            state.lng != null &&
            state.locationStatus == PrayerLocationStatus.ready
        ? QiblaService.bearingToMecca(state.lat!, state.lng!)
        : null;
    return PrayerOverview(
      state: state,
      now: DateTime.now(),
      onTimes: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PrayerTimesSettingsScreen()),
      ),
      qibla: StreamBuilder<CompassEvent>(
        stream: _foreground && _visible && bearing != null
            ? FlutterCompass.events
            : null,
        builder: (context, snapshot) => QiblaMiniature(
          bearing: bearing,
          heading: _foreground && _visible && !snapshot.hasError
              ? snapshot.data?.heading
              : null,
          accuracy: snapshot.data?.accuracy,
          onTap: openQibla,
        ),
      ),
    );
  }
}

String prayerCountdown(AppLocalizations t, Duration duration) {
  if (duration.inMinutes < 1) return t.prayerInNow;
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  if (hours == 0) return t.prayerInMinutes(minutes);
  // Generated localization API orders minutes BEFORE hours.
  return minutes == 0
      ? t.prayerInHours(hours)
      : t.prayerInHoursMinutes(minutes, hours);
}

String _hm(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class PrayerOverview extends StatelessWidget {
  final PrayerState state;
  final DateTime now;
  final VoidCallback onTimes;
  final Widget qibla;
  const PrayerOverview({
    super.key,
    required this.state,
    required this.now,
    required this.onTimes,
    required this.qibla,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final next = state.prochainePriere;
    final today = state.today;
    final fresh =
        today != null &&
        today.isNotEmpty &&
        DateUtils.isSameDay(today.values.first.toLocal(), now);
    final ready = fresh && state.locationStatus == PrayerLocationStatus.ready;
    return Material(
      color: const Color(0xFFF3F6F4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.prayerTimesTitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF53665E),
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onTimes,
                  tooltip: t.prayerTimesTitle,
                  icon: const Icon(
                    Icons.tune_rounded,
                    size: 19,
                    color: AppColors.green800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onTimes,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: 12,
                        top: 8,
                        bottom: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.prayerTimesNext,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: const Color(0xFF53665E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (ready && next != null) ...[
                            Text(
                              nomPriere(context, next.name),
                              style: GoogleFonts.manrope(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: AppColors.green900,
                              ),
                            ),
                            Text(
                              _hm(next.time),
                              textDirection: TextDirection.ltr,
                              style: GoogleFonts.manrope(
                                fontSize: 34,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: AppColors.green900,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              prayerCountdown(t, next.time.difference(now)),
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: const Color(0xFF53665E),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Icon(
                              state.locationStatus ==
                                      PrayerLocationStatus.loading
                                  ? Icons.hourglass_top_rounded
                                  : Icons.location_off_outlined,
                              color: AppColors.green800,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              state.locationStatus ==
                                      PrayerLocationStatus.loading
                                  ? t.prayerTimesTitle
                                  : t.qiblaEnableLocationAction,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: AppColors.green800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 104, child: qibla),
              ],
            ),
            if (ready) ...[
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFDCE5DF)),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      MediaQuery.textScalerOf(context).scale(12) > 17 ||
                          constraints.maxWidth < 270
                      ? 3
                      : 5;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 5) / columns;
                  return Wrap(
                    spacing: 5,
                    runSpacing: 8,
                    children: [
                      for (final prayer in PrayerName.values)
                        SizedBox(
                          width: width,
                          child: _PrayerTime(
                            name: nomPriere(context, prayer),
                            time: _hm(today[prayer]!),
                            selected:
                                next?.name == prayer &&
                                DateUtils.isSameDay(next?.time.toLocal(), now),
                            onTap: onTimes,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrayerTime extends StatelessWidget {
  final String name;
  final String time;
  final bool selected;
  final VoidCallback onTap;
  const _PrayerTime({
    required this.name,
    required this.time,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.green900 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              name,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 10,
                color: selected
                    ? AppColors.brassLight
                    : const Color(0xFF53665E),
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                time,
                textDirection: TextDirection.ltr,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.green900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class QiblaMiniature extends StatelessWidget {
  final double? bearing;
  final double? heading;
  final double? accuracy;
  final VoidCallback onTap;
  const QiblaMiniature({
    super.key,
    this.bearing,
    this.heading,
    this.accuracy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final available =
        bearing != null &&
        heading != null &&
        bearing!.isFinite &&
        heading!.isFinite;
    final reliable =
        available &&
        accuracy != null &&
        accuracy!.isFinite &&
        accuracy! >= 0 &&
        accuracy! <= 25;
    final aligned = reliable && QiblaService.angleDiff(bearing!, heading!) < 5;
    final message = bearing == null
        ? t.qiblaEnableLocationMessage
        : !available
        ? t.qiblaNoCompassMessage
        : !reliable
        ? t.qiblaMagneticWarning
        : aligned
        ? t.qiblaFacingQibla
        : t.qiblaSubtitle;
    return Semantics(
      button: true,
      label: '${t.settingsQiblaTitle}. $message',
      child: Tooltip(
        message: message,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CustomPaint(
                    painter: const _CompassTicks(),
                    child: Center(
                      child: available
                          ? Transform.rotate(
                              angle: (bearing! - heading!) * math.pi / 180,
                              child: Icon(
                                Icons.navigation_rounded,
                                size: 38,
                                color: reliable
                                    ? AppColors.green800
                                    : const Color(0xFF99762B),
                              ),
                            )
                          : const Icon(
                              Icons.explore_off_outlined,
                              size: 30,
                              color: Color(0xFF78867F),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'القبلة'
                      : 'Qibla',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.green900,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 18,
                  child: Icon(
                    aligned
                        ? Icons.check_circle_outline_rounded
                        : available && !reliable
                        ? Icons.warning_amber_rounded
                        : Icons.open_in_full_rounded,
                    size: 16,
                    color: reliable
                        ? AppColors.green800
                        : const Color(0xFF99762B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bandeau compact fusionnant Qibla + prochaine priere, en zone verte.
///
/// ── POURQUOI CETTE FUSION (2026-09-13) ──────────────────────────────────
///
/// Demande utilisateur, apres retour sur le remaniement de codex : « il y a
/// beaucoup de repetitions d'informations, je veux que tu agreges [...] je
/// veux garder que l'emoticone pour la Qibla, on la mette dans la zone
/// verte [...] agreger sur une seule colonne ou on a a la fois le qibla qui
/// tourne et les prieres ». Avant : un gros bloc "prochaine priere"
/// (`PrayerOverview`) ET, a cote, un cadran Qibla tout aussi grand
/// (`QiblaMiniature`) -- deux blocs distincts, ET l'horaire de la priere en
/// cours apparaissait A LA FOIS dans ce bandeau ET dans la rangee separee
/// des 5 horaires du jour, juste en dessous.
///
/// Ce widget remplace les deux sur l'accueil : UNE seule ligne verte, la
/// fleche Qibla (petite, tournante) a gauche, l'info de prochaine priere a
/// droite -- rien n'est affiche deux fois. Reprend le style de l'ancien
/// `_RappelPriere` (2026-08-19, `surah_list_screen.dart`) ; le calcul Qibla
/// (bearing, seuil d'alignement 5°, capteur) reprend exactement celui de
/// `HomePrayerPanel`/`QiblaMiniature` ci-dessus -- ces deux classes restent
/// dans ce fichier (non branchees sur l'accueil, non supprimees : elles
/// restent testees par `home_prayer_panel_test.dart` et servent de reference
/// si un usage futur les reclame).
///
/// Pas de nom "Qibla" affiche (demande explicite) : la fleche seule suffit,
/// et sa couleur dit l'etat -- `AppColors.brassLight` (or) des que
/// l'orientation est correcte (`QiblaService.angleDiff(...) < 5`, meme seuil
/// que `QiblaMiniature`), `AppColors.cream` sinon. Un tap sur la fleche ouvre
/// l'ecran Qibla complet ; un tap ailleurs sur le bandeau ouvre les reglages
/// des horaires -- deux zones de tap distinctes, comme dans le widget
/// d'origine (`InkWell` imbrique, celui du dessus gagne l'arene de gestes).
class PrayerQiblaBanner extends ConsumerStatefulWidget {
  const PrayerQiblaBanner({super.key});
  @override
  ConsumerState<PrayerQiblaBanner> createState() => _PrayerQiblaBannerState();
}

class _PrayerQiblaBannerState extends ConsumerState<PrayerQiblaBanner>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Meme garde que `HomePrayerPanel` : desabonne le capteur boussole des
    // que l'onglet Accueil n'est plus visible (onglet cache, route par-dessus,
    // app en arriere-plan) -- cf. ACCUEIL_CHGPT_2026-09-13.md.
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _syncClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    _syncClock();
  }

  void _syncClock() {
    _timer?.cancel();
    if (!_foreground || !_visible) return;
    // Une minute : le compte a rebours s'affiche en heures et minutes, donc
    // rafraichir plus souvent redessinerait pour rien (meme raison que
    // l'ancien `_RappelPriere`).
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(prayerSettingsProvider);
    final suivante = state.prochainePriere;
    // Position pas encore connue, ou refusee : rien a annoncer, comme
    // l'ancien bandeau -- pas de "-- : --" qui ferait croire a une panne.
    if (suivante == null) return const SizedBox.shrink();

    final bearing =
        state.lat != null &&
            state.lng != null &&
            state.locationStatus == PrayerLocationStatus.ready
        ? QiblaService.bearingToMecca(state.lat!, state.lng!)
        : null;
    final reste = suivante.time.difference(DateTime.now());

    void openTimes() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrayerTimesSettingsScreen()),
    );
    void openQibla() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QiblaScreen()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      child: Material(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openTimes,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            child: Row(
              children: [
                InkWell(
                  onTap: openQibla,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: StreamBuilder<CompassEvent>(
                      stream: _foreground && _visible && bearing != null
                          ? FlutterCompass.events
                          : null,
                      builder: (context, snapshot) {
                        final heading =
                            _foreground && _visible && !snapshot.hasError
                            ? snapshot.data?.heading
                            : null;
                        final accuracy = snapshot.data?.accuracy;
                        final available =
                            bearing != null &&
                            heading != null &&
                            bearing.isFinite &&
                            heading.isFinite;
                        final reliable =
                            available &&
                            accuracy != null &&
                            accuracy.isFinite &&
                            accuracy >= 0 &&
                            accuracy <= 25;
                        final aligned =
                            reliable &&
                            QiblaService.angleDiff(bearing, heading) < 5;
                        final message = bearing == null
                            ? t.qiblaEnableLocationMessage
                            : !available
                            ? t.qiblaNoCompassMessage
                            : !reliable
                            ? t.qiblaMagneticWarning
                            : aligned
                            ? t.qiblaFacingQibla
                            : t.qiblaSubtitle;
                        final icone = Icon(
                          available
                              ? Icons.navigation_rounded
                              : Icons.explore_off_outlined,
                          size: 26,
                          color: !available
                              ? AppColors.cream.withValues(alpha: 0.5)
                              : aligned
                              ? AppColors.brassLight
                              : AppColors.cream,
                        );
                        return Tooltip(
                          message: message,
                          child: available
                              ? Transform.rotate(
                                  angle: (bearing - heading) * math.pi / 180,
                                  child: icone,
                                )
                              : icone,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.prayerTimesNext.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 9.5,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brassLight,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${nomPriere(context, suivante.name)} · ${_hm(suivante.time)}',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.cream,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  prayerCountdown(t, reste),
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brassLight,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.brassLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompassTicks extends CustomPainter {
  const _CompassTicks();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()
      ..color = const Color(0xFFBFCAA9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 1, paint);
    canvas.drawCircle(
      center,
      radius - 9,
      paint..color = const Color(0xFFDBE3D7),
    );
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final direction = Offset(math.sin(angle), -math.cos(angle));
      paint.color = i % 6 == 0 ? AppColors.green800 : const Color(0xFFB2BEAD);
      canvas.drawLine(
        center + direction * (radius - 3),
        center + direction * (radius - (i % 6 == 0 ? 10 : 6)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CompassTicks oldDelegate) => false;
}

/// Qibla (cadran gradue) + horaires du jour, dans UNE seule carte compacte.
///
/// ── TROISIEME VERSION DE CE BANDEAU EN UNE SESSION (2026-09-13) ─────────
///
/// 1. `HomePrayerPanel`/`PrayerOverview` (codex) : cadran Qibla 84 px ET
///    bloc "prochaine priere" cote a cote, chacun deja assez grand seul --
///    « ca prend beaucoup d'espace ».
/// 2. `PrayerQiblaBanner` (ce fichier, plus haut) : simplifie a l'extreme,
///    fleche seule sans cadran ni rangee d'horaires -- retour utilisateur
///    IMMEDIAT : « je veux garder la representation de qibla et les
///    horaires, c'est plutot avant qui est mieux, je veux juste en plus
///    compact ». Le style (cadran gradue, rangee des 5 horaires) etait bon ;
///    seul l'ENCOMBREMENT etait le probleme, pas le contenu.
/// 3. Celle-ci : REPREND le cadran gradue (`_CompassTicks`, reutilise tel
///    quel, il est deja independant de la taille) et la rangee des 5
///    horaires (`_PrayerTime`, inchangee), mais dans **une seule colonne**
///    au lieu de deux blocs poses cote a cote, et a une echelle reduite
///    (cadran 56 px au lieu de 84, pas de temps en 34 px). Rien n'est retire
///    du CONTENU -- seul l'agencement et la taille changent.
///
/// `PrayerQiblaBanner` (version 2, trop depouillee) reste definie plus haut,
/// non supprimee, non branchee -- meme raison que `HomePrayerPanel` : garder
/// une trace de ce qui a ete essaye et ecarte plutot que l'effacer.
class CompactPrayerQiblaCard extends ConsumerStatefulWidget {
  const CompactPrayerQiblaCard({super.key});
  @override
  ConsumerState<CompactPrayerQiblaCard> createState() =>
      _CompactPrayerQiblaCardState();
}

class _CompactPrayerQiblaCardState extends ConsumerState<CompactPrayerQiblaCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  bool _visible = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _syncClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
    _syncClock();
  }

  void _syncClock() {
    _timer?.cancel();
    if (!_foreground || !_visible) return;
    _refreshDate();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _refreshDate();
    });
  }

  Future<void> _refreshDate() async {
    final state = ref.read(prayerSettingsProvider);
    final date = state.today?.values.firstOrNull?.toLocal();
    final now = DateTime.now();
    if (_refreshing ||
        date == null ||
        DateUtils.isSameDay(date, now) ||
        state.locationStatus != PrayerLocationStatus.ready) {
      return;
    }
    _refreshing = true;
    await Future<void>.delayed(Duration.zero);
    try {
      if (mounted) {
        await ref.read(prayerSettingsProvider.notifier).refreshLocation();
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final state = ref.watch(prayerSettingsProvider);
    final now = DateTime.now();
    final next = state.prochainePriere;
    final today = state.today;
    final fresh =
        today != null &&
        today.isNotEmpty &&
        DateUtils.isSameDay(today.values.first.toLocal(), now);
    final ready = fresh && state.locationStatus == PrayerLocationStatus.ready;
    final bearing =
        state.lat != null &&
            state.lng != null &&
            state.locationStatus == PrayerLocationStatus.ready
        ? QiblaService.bearingToMecca(state.lat!, state.lng!)
        : null;
    void openTimes() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PrayerTimesSettingsScreen()),
    );
    void openQibla() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QiblaScreen()));

    return Padding(
      // ── ENCORE PLUS COMPACT (2026-09-13, meme session) ────────────────
      //
      // Retour utilisateur immediat sur la version precedente : « en plus
      // compact, enleve le lien parametrage, avance pour gagner espace, les
      // prieres a enlever, que la prochaine interesse ». Trois retraits :
      // le titre "Horaires de priere" + son icone reglages (`Icons.tune_rounded`,
      // redondante -- toute la carte ouvre deja les reglages au tap) ; la
      // rangee des 5 horaires du jour (seule la PROCHAINE priere interesse) ;
      // les marges, resserrees. Le tap sur la carte entiere pour ouvrir les
      // reglages reste actif -- seul le BOUTON dedie disparait, pas l'acces.
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Material(
        color: const Color(0xFFF3F6F4),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openTimes,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                  // Cadran Qibla, compact (56 px contre 84) -- zone de tap
                  // DISTINCTE (ouvre l'ecran Qibla), le reste de la carte
                  // ouvre les reglages d'horaires.
                  InkWell(
                    onTap: openQibla,
                    borderRadius: BorderRadius.circular(28),
                    child: StreamBuilder<CompassEvent>(
                      stream: _foreground && _visible && bearing != null
                          ? FlutterCompass.events
                          : null,
                      builder: (context, snapshot) {
                        final heading =
                            _foreground && _visible && !snapshot.hasError
                            ? snapshot.data?.heading
                            : null;
                        final accuracy = snapshot.data?.accuracy;
                        final available =
                            bearing != null &&
                            heading != null &&
                            bearing.isFinite &&
                            heading.isFinite;
                        final reliable =
                            available &&
                            accuracy != null &&
                            accuracy.isFinite &&
                            accuracy >= 0 &&
                            accuracy <= 25;
                        final aligned =
                            reliable &&
                            QiblaService.angleDiff(bearing, heading) < 5;
                        final message = bearing == null
                            ? t.qiblaEnableLocationMessage
                            : !available
                            ? t.qiblaNoCompassMessage
                            : !reliable
                            ? t.qiblaMagneticWarning
                            : aligned
                            ? t.qiblaFacingQibla
                            : t.qiblaSubtitle;
                        return Tooltip(
                          message: message,
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: CustomPaint(
                              painter: const _CompassTicks(),
                              child: Center(
                                child: available
                                    ? Transform.rotate(
                                        angle:
                                            (bearing - heading) *
                                            math.pi /
                                            180,
                                        child: Icon(
                                          Icons.navigation_rounded,
                                          size: 24,
                                          // Or/dore des que l'orientation est
                                          // correcte (demande explicite,
                                          // aucun nom "Qibla" a cote) ; vert
                                          // sinon, comme le cadran d'origine.
                                          color: aligned
                                              ? AppColors.brass
                                              : reliable
                                              ? AppColors.green800
                                              : const Color(0xFF99762B),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.explore_off_outlined,
                                        size: 20,
                                        color: Color(0xFF78867F),
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.prayerTimesNext,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: const Color(0xFF53665E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (ready && next != null) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                nomPriere(context, next.name),
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.green900,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _hm(next.time),
                                textDirection: TextDirection.ltr,
                                style: GoogleFonts.manrope(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.green900,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            prayerCountdown(t, next.time.difference(now)),
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: const Color(0xFF53665E),
                            ),
                          ),
                        ] else
                          Icon(
                            state.locationStatus ==
                                    PrayerLocationStatus.loading
                                ? Icons.hourglass_top_rounded
                                : Icons.location_off_outlined,
                            size: 20,
                            color: AppColors.green800,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
