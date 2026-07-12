import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/qibla_service.dart';
import '../theme/app_theme.dart';

/// Boussole Qibla — direction de la Kaaba depuis la position actuelle.
///
/// Reprend le vocabulaire visuel déjà validé de l'app ("moushaf premium",
/// cf. design/prototype.html) plutôt qu'un cadran générique : le même fond
/// dégradé vert émeraude que l'écran de mémorisation, le même médaillon à
/// double anneau laiton que les numéros de verset, la même aiguille en
/// dégradé que l'anneau de score, la même pulsation que le micro à l'écoute
/// une fois orienté vers la Mecque.
class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

enum _QiblaLoadState { loading, ready, serviceDisabled, permissionDenied, error }

class _QiblaScreenState extends State<QiblaScreen> {
  _QiblaLoadState _state = _QiblaLoadState.loading;
  double? _qiblaBearing;
  double? _distanceKm;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolvePosition();
  }

  Future<void> _resolvePosition() async {
    setState(() => _state = _QiblaLoadState.loading);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _state = _QiblaLoadState.serviceDisabled);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _state = _QiblaLoadState.permissionDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _qiblaBearing = QiblaService.bearingToMecca(pos.latitude, pos.longitude);
        _distanceKm = QiblaService.distanceToMeccaKm(pos.latitude, pos.longitude);
        _state = _QiblaLoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _state = _QiblaLoadState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.green900,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ambientBackground(),
          SafeArea(
            child: Column(
              children: [
                _topBar(context),
                Expanded(child: _body()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ambientBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.4),
          radius: 1.3,
          colors: [AppColors.green700, AppColors.green900],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'القِبْلَة',
                  style: GoogleFonts.scheherazadeNew(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brassLight,
                  ),
                ),
                Text(
                  'Direction de la Mecque',
                  style: GoogleFonts.manrope(
                    fontSize: 10.5,
                    letterSpacing: 1.1,
                    color: AppColors.cream.withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_state) {
      case _QiblaLoadState.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brassLight),
        );
      case _QiblaLoadState.serviceDisabled:
        return _guidance(
          icon: Icons.location_disabled_rounded,
          message: 'Active la localisation pour trouver la Qibla depuis '
              'ton emplacement actuel.',
          actionLabel: 'Activer la localisation',
          onAction: () async {
            await Geolocator.openLocationSettings();
            _resolvePosition();
          },
        );
      case _QiblaLoadState.permissionDenied:
        return _guidance(
          icon: Icons.pin_drop_outlined,
          message: 'La localisation est refusée pour Coran Karim. '
              'Autorise-la dans les réglages du téléphone pour voir la Qibla.',
          actionLabel: 'Ouvrir les réglages',
          onAction: () async {
            await Geolocator.openAppSettings();
            _resolvePosition();
          },
        );
      case _QiblaLoadState.error:
        return _guidance(
          icon: Icons.error_outline_rounded,
          message: 'Impossible de déterminer ta position : $_errorMessage',
          actionLabel: 'Réessayer',
          onAction: _resolvePosition,
        );
      case _QiblaLoadState.ready:
        return _compass();
    }
  }

  Widget _guidance({
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.brassLight.withOpacity(0.85), size: 44),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.5,
                color: AppColors.cream.withOpacity(0.85),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brass,
                foregroundColor: AppColors.green900,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: onAction,
              child: Text(actionLabel,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compass() {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        final heading = snapshot.data?.heading;
        if (FlutterCompass.events == null || heading == null) {
          return _guidance(
            icon: Icons.explore_off_rounded,
            message: 'Cet appareil ne possède pas de boussole. '
                'La distance jusqu\'à la Mecque reste disponible ci-dessous.',
            actionLabel: 'Réessayer',
            onAction: _resolvePosition,
          );
        }
        final qibla = _qiblaBearing!;
        final facingQibla = QiblaService.angleDiff(qibla, heading) < 5;
        return Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: _QiblaDial(
                  headingDeg: heading,
                  qiblaBearingDeg: qibla,
                  aligned: facingQibla,
                ),
              ),
            ),
            _distanceCard(),
            const SizedBox(height: 14),
            _hint(facingQibla),
            const SizedBox(height: 28),
          ],
        );
      },
    );
  }

  Widget _distanceCard() {
    final km = _distanceKm;
    if (km == null) return const SizedBox.shrink();
    return Column(
      children: [
        Text(
          km >= 1000 ? km.round().toString() : km.toStringAsFixed(1),
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            color: AppColors.cream,
          ),
        ),
        Text(
          'KM JUSQU\'À LA MECQUE',
          style: GoogleFonts.manrope(
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
            color: AppColors.brassLight.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _hint(bool facingQibla) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: facingQibla
          ? Text(
              'Tu fais face à la Qibla ✓',
              key: const ValueKey('aligned'),
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.brassLight,
              ),
            )
          : Row(
              key: const ValueKey('unaligned'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.explore_outlined,
                    size: 14, color: AppColors.cream.withOpacity(0.5)),
                const SizedBox(width: 6),
                Text(
                  'Tourne ton téléphone jusqu\'à ce que l\'aiguille pointe en haut',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.cream.withOpacity(0.5),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Cadran ornemental : médaillon à double anneau laiton (même motif que les
/// numéros de verset du moushaf), aiguille en dégradé (même langage que
/// l'anneau de score du mode mémorisation), pulsation douce une fois orienté
/// (même animation que le micro à l'écoute).
class _QiblaDial extends StatefulWidget {
  final double headingDeg;
  final double qiblaBearingDeg;
  final bool aligned;

  const _QiblaDial({
    required this.headingDeg,
    required this.qiblaBearingDeg,
    required this.aligned,
  });

  @override
  State<_QiblaDial> createState() => _QiblaDialState();
}

class _QiblaDialState extends State<_QiblaDial> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rotation de l'aiguille par rapport à l'écran : 0° = pointe vers le
    // haut quand l'appareil fait face à la Qibla.
    final needleAngle = (widget.qiblaBearingDeg - widget.headingDeg) * math.pi / 180;
    // Repère nord discret, tourne avec le cap réel de l'appareil.
    final northAngle = -widget.headingDeg * math.pi / 180;

    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.aligned)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => _pulseRing(_pulse.value),
            ),
          if (widget.aligned)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) =>
                  _pulseRing((_pulse.value + 0.5) % 1.0),
            ),
          _medallion(),
          Transform.rotate(angle: northAngle, child: _northMark()),
          Transform.rotate(angle: needleAngle, child: _needle()),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brassLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pulseRing(double t) {
    return Opacity(
      opacity: (1 - t) * 0.55,
      child: Transform.scale(
        scale: 0.86 + t * 0.3,
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brassLight, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _medallion() {
    return Container(
      width: 236,
      height: 236,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: AppColors.brass.withOpacity(0.55), width: 1.5),
      ),
      child: Center(
        child: Container(
          width: 206,
          height: 206,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brassLight.withOpacity(0.45), width: 1),
          ),
        ),
      ),
    );
  }

  Widget _northMark() {
    return Align(
      alignment: const Alignment(0, -0.92),
      child: Text(
        'N',
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.cream.withOpacity(0.45),
        ),
      ),
    );
  }

  Widget _needle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mosque_rounded, color: AppColors.brassLight, size: 26),
        Container(
          width: 3,
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.brassLight,
                AppColors.brass.withOpacity(0.15),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
