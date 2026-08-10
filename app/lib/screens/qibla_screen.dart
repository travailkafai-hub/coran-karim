import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
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
                  AppLocalizations.of(context)!.qiblaSubtitle,
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
    final t = AppLocalizations.of(context)!;
    switch (_state) {
      case _QiblaLoadState.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brassLight),
        );
      case _QiblaLoadState.serviceDisabled:
        return _guidance(
          icon: Icons.location_disabled_rounded,
          message: t.qiblaEnableLocationMessage,
          actionLabel: t.qiblaEnableLocationAction,
          onAction: () async {
            await Geolocator.openLocationSettings();
            _resolvePosition();
          },
        );
      case _QiblaLoadState.permissionDenied:
        return _guidance(
          icon: Icons.pin_drop_outlined,
          message: t.qiblaPermissionDeniedMessage,
          actionLabel: t.qiblaOpenSettingsAction,
          onAction: () async {
            await Geolocator.openAppSettings();
            _resolvePosition();
          },
        );
      case _QiblaLoadState.error:
        return _guidance(
          icon: Icons.error_outline_rounded,
          message: t.qiblaPositionError('$_errorMessage'),
          actionLabel: t.commonRetry,
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
          final t = AppLocalizations.of(context)!;
          return _guidance(
            icon: Icons.explore_off_rounded,
            message: t.qiblaNoCompassMessage,
            actionLabel: t.commonRetry,
            onAction: _resolvePosition,
          );
        }
        final qibla = _qiblaBearing!;
        final facingQibla = QiblaService.angleDiff(qibla, heading) < 5;
        // Précision fournie par le capteur natif (fusion magnétomètre +
        // accéléromètre + gyroscope sur Android, cf. flutter_compass) --
        // c'est la SEULE partie du calcul qui peut se tromper : le cap vers
        // la Mecque lui-même est de la géométrie GPS pure (QiblaService),
        // fiable à quelques mètres près. Le magnétomètre, lui, dérive près
        // d'un objet métallique/aimant (coque, support voiture...) et se
        // recalibre par un mouvement en huit -- on l'indique plutôt que de
        // laisser croire que l'aiguille est toujours juste.
        final accuracy = snapshot.data?.accuracy;
        // accuracy == null INCLUS dans le déclencheur (2026-08-10, audit de
        // la demande utilisateur « message clair pour qu'il se réaimante »)
        // -- pas seulement `accuracy > 25`. Preuve dans le plugin natif
        // (flutter_compass 0.8.1, FlutterCompassPlugin.java#getAccuracy) :
        // sur Android, seuls 3 paliers HIGH=15/MEDIUM=30/LOW=45 sont
        // renvoyés ; le 4e statut natif SENSOR_STATUS_UNRELIABLE -- le PIRE
        // cas, celui pour lequel Android recommande justement de recalibrer
        // en huit -- tombe dans le `else` de ce mapping et vaut -1, traduit
        // par le plugin (CompassEvent.fromList) en `accuracy == null`. Avec
        // `accuracy != null && accuracy > 25`, ce pire cas ne déclenchait
        // PAS l'alerte (null échoue le premier `&&`) alors que les paliers
        // MEDIUM/LOW, pourtant moins graves, la déclenchaient bien -- trou
        // trouvé par lecture du code natif du plugin, à confirmer par
        // recette sur device si une perturbation magnétique forte est
        // reproductible.
        final lowAccuracy = accuracy == null || accuracy > 25;
        return Column(
          children: [
            const SizedBox(height: 8),
            if (lowAccuracy) _magneticAlert(),
            // ── FLÈCHE AU-DESSUS DE LA BOUSSOLE (2026-08-10) ────────────────
            // Demande utilisateur : « la flèche doit être au-dessus de la
            // boussole qui montre la direction de la rotation » -- avant,
            // `_hint` (badge aligné / flèche de rotation) vivait sous le
            // cadran, après la distance ; déplacé ICI, avant `_QiblaDial`,
            // pour que le sens à tourner se voie AVANT même de regarder
            // l'aiguille, pas après.
            _hint(facingQibla, qibla, heading),
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
          AppLocalizations.of(context)!.qiblaKmToMecca,
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

  Widget _hint(bool facingQibla, double qibla, double heading) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        // Fondu + léger zoom -- juste le fondu par défaut d'AnimatedSwitcher
        // rendait l'arrivée du badge "aligné" (cf. `_alignedBadge`) trop
        // discrète pour l'effet de renfort recherché ; le zoom accompagne
        // le fond/la bordure/le halo qui apparaissent en même temps.
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: facingQibla
            ? _alignedBadge(t)
            : _turnHint(t, qibla, heading),
      ),
    );
  }

  /// État "aligné" rendu NETTEMENT plus visible (2026-08-10, demande
  /// utilisateur « je veux quand qibla trouvé que ça soit plus visible »).
  /// Avant ce changement, le seul texte spécifique à l'alignement était un
  /// `Text` brassLight à peine plus gras (w700 vs w500 par défaut) que le
  /// hint "non aligné" juste à côté -- la vraie différence venait du cadran
  /// (`_pulseRing`, cf. `_QiblaDial`), pas de cette zone-ci. Ici : badge à
  /// fond et bordure laiton, halo, icône de validation, texte plus grand et
  /// plus gras -- pour que l'état se voie aussi là où le regard se pose
  /// après avoir levé les yeux du cadran.
  Widget _alignedBadge(AppLocalizations t) {
    return Container(
      key: const ValueKey('aligned'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brass.withOpacity(0.22),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.brassLight, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.brassLight.withOpacity(0.35),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.brassLight),
          const SizedBox(width: 8),
          Text(
            t.qiblaFacingQibla,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: AppColors.brassLight,
            ),
          ),
        ],
      ),
    );
  }

  /// Flèche directionnelle (2026-08-10, demande utilisateur « si on décale
  /// qu'il affiche une flèche qui montre où tourner le tel »). Remplace
  /// l'icône boussole générique `explore_outlined` qui disait "tourne" sans
  /// jamais dire de quel côté. Le sens vient de `_signedTurn`, calculé avec
  /// la MÊME convention de signe que l'aiguille du cadran (`needleAngle`
  /// dans `_QiblaDial.build`, plus bas dans ce fichier) : positif = la Qibla
  /// est à droite de l'écran, donc tourner à droite (sens horaire) rapproche
  /// le cap de la cible. Repris tel quel plutôt que d'inventer une deuxième
  /// convention qui contredirait l'aiguille affichée à l'écran.
  Widget _turnHint(AppLocalizations t, double qibla, double heading) {
    final turnRight = _signedTurn(qibla, heading) > 0;
    return Row(
      // Clé CONSTANTE (pas dépendante de `turnRight`) -- volontaire : la clé
      // ne doit changer que sur le vrai basculement aligné/non-aligné géré
      // par l'AnimatedSwitcher parent, pas à chaque fois que le cap oscille
      // autour de 0° et fait sauter la flèche de sens -- sinon le badge se
      // recréerait (fondu+zoom) en boucle au lieu de simplement changer
      // d'icône.
      key: const ValueKey('unaligned'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          turnRight ? Icons.turn_right_rounded : Icons.turn_left_rounded,
          size: 16,
          color: AppColors.cream.withOpacity(0.6),
        ),
        const SizedBox(width: 6),
        // Flexible -- sans lui le Text refuse de passer à la ligne dans un
        // Row et dépasse en largeur (dépassement signalé par l'utilisateur,
        // texte français plus long que ce que l'essai initial avait couvert).
        Flexible(
          child: Text(
            t.qiblaTurnPhoneHint,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.cream.withOpacity(0.5),
            ),
          ),
        ),
      ],
    );
  }

  /// Écart signé entre le cap Qibla et le cap courant, dans ]-180, 180] --
  /// MÊME convention que `needleAngle` dans `_QiblaDial.build`
  /// (`qiblaBearingDeg - headingDeg`, positif = rotation horaire à l'écran =
  /// cible à droite) : `QiblaService.angleDiff` ne donne que l'écart absolu
  /// (0-180°), utile pour juger "aligné ou pas" mais insuffisant pour dire
  /// de quel côté tourner -- d'où cette variante signée, gardée ici plutôt
  /// que dans `QiblaService` puisqu'elle n'a qu'un seul appelant.
  static double _signedTurn(double qiblaBearingDeg, double headingDeg) {
    final raw = (qiblaBearingDeg - headingDeg) % 360; // Dart : toujours dans [0, 360)
    return raw > 180 ? raw - 360 : raw;
  }

  /// Alerte visible dès qu'un champ magnétique perturbe le magnétomètre --
  /// demande utilisateur 2026-08-09. Placée EN HAUT (avant même le cadran) :
  /// une aiguille fausse sans avertissement est pire qu'une aiguille absente,
  /// mieux vaut le dire avant que l'utilisateur ne s'oriente dessus.
  Widget _magneticAlert() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brass.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brass.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.brassLight, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Champ magnétique détecté — éloigne-toi du métal ou d\'un aimant (coque, support, enceinte...), puis recalibre en dessinant un « 8 » avec le téléphone.',
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                color: AppColors.cream,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
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

  /// Médaillon : bordure et halo renforcés une fois aligné (2026-08-10,
  /// demande utilisateur « je veux quand qibla trouvé que ça soit plus
  /// visible »). Avant ce changement, le médaillon avait EXACTEMENT le même
  /// tracé aligné ou pas -- seule la pulsation passagère (`_pulseRing`,
  /// visible seulement pendant l'aller-retour de l'anneau) marquait la
  /// différence. `AnimatedContainer` fait la transition en douceur entre les
  /// deux décorations sans contrôleur dédié (pas besoin, c'est un simple
  /// aller-retour, pas une animation qui boucle).
  Widget _medallion() {
    final aligned = widget.aligned;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      width: 236,
      height: 236,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(aligned ? 0.08 : 0.05),
        border: Border.all(
          color: aligned ? AppColors.brassLight : AppColors.brass.withOpacity(0.55),
          width: aligned ? 2.2 : 1.5,
        ),
        boxShadow: aligned
            ? [
                BoxShadow(
                  color: AppColors.brassLight.withOpacity(0.4),
                  blurRadius: 26,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          width: 206,
          height: 206,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: aligned
                  ? AppColors.brassLight.withOpacity(0.85)
                  : AppColors.brassLight.withOpacity(0.45),
              width: aligned ? 1.6 : 1,
            ),
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

  /// Aiguille en forme de tapis de prière (sajjada) : le mihrab (l'arche)
  /// pointe vers la Mecque, exactement comme on oriente un vrai tapis --
  /// demande utilisateur 2026-08-09, plus parlant qu'une aiguille abstraite.
  Widget _needle() {
    return const SizedBox(
      width: 58,
      height: 92,
      child: CustomPaint(painter: _PrayerRugPainter()),
    );
  }
}

class _PrayerRugPainter extends CustomPainter {
  const _PrayerRugPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final archHeight = size.height * 0.30;
    final bodyTop = archHeight - 4; // léger chevauchement, pas de jointure visible
    final bodyRect = Rect.fromLTWH(4, bodyTop, size.width - 8, size.height - bodyTop - 4);
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(5));

    // Arche du mihrab -- pointe en (centre, 0), c'est elle qui indique la
    // direction une fois l'ensemble tourné par Transform.rotate.
    final archPath = Path()
      ..moveTo(6, archHeight)
      ..quadraticBezierTo(6, archHeight * 0.35, size.width / 2, 0)
      ..quadraticBezierTo(size.width - 6, archHeight * 0.35, size.width - 6, archHeight)
      ..close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [AppColors.brassLight, AppColors.brass.withOpacity(0.65)],
    );
    canvas.drawPath(
      archPath,
      Paint()..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, archHeight)),
    );
    canvas.drawRRect(body, Paint()..color = AppColors.green800.withOpacity(0.85));

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.brassLight;
    canvas.drawPath(archPath, stroke);
    canvas.drawRRect(body, stroke);

    // Bordure tissée : DEUX liserés (pas un seul) avec un fin espace entre
    // les deux, comme la double bande qui borde un vrai sajjada -- demande
    // utilisateur 2026-08-09 ("une image jolie"), un seul trait paraissait
    // trop nu pour évoquer un tapis plutôt qu'un simple rectangle.
    final thinStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = AppColors.brassLight.withOpacity(0.55);
    for (final inset in [5.0, 9.0]) {
      final r = bodyRect.deflate(inset);
      if (r.width > 0 && r.height > 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), thinStroke);
      }
    }

    // Lampe de mosquée suspendue dans le mihrab -- motif classique des
    // tapis de prière, accroche l'œil sur la pointe qui indique la Qibla.
    final lampCenter = Offset(size.width / 2, archHeight * 0.62);
    final lampPaint = Paint()..color = AppColors.green800.withOpacity(0.9);
    canvas.drawLine(
      Offset(size.width / 2, 2),
      Offset(size.width / 2, lampCenter.dy - 4),
      Paint()
        ..strokeWidth = 1
        ..color = AppColors.green800.withOpacity(0.8),
    );
    final lampPath = Path()
      ..moveTo(lampCenter.dx - 4, lampCenter.dy)
      ..lineTo(lampCenter.dx + 4, lampCenter.dy)
      ..lineTo(lampCenter.dx + 2.5, lampCenter.dy + 6)
      ..lineTo(lampCenter.dx - 2.5, lampCenter.dy + 6)
      ..close();
    canvas.drawPath(lampPath, lampPaint);

    // Petit médaillon central, écho du motif déjà utilisé sur les numéros
    // de verset et le cadran lui-même.
    final medallionCenter = Offset(size.width / 2, bodyTop + (size.height - bodyTop) * 0.5);
    canvas.drawCircle(medallionCenter, 4.5, Paint()..color = AppColors.brassLight.withOpacity(0.75));
    canvas.drawCircle(medallionCenter, 4.5, thinStroke..color = AppColors.green800.withOpacity(0.5));

    // Pompons du bas -- trois petites franges, comme la lisière tissée au
    // pied d'un vrai tapis (le bord qu'on ne pose jamais vers la Qibla).
    final fringePaint = Paint()
      ..strokeWidth = 1.2
      ..color = AppColors.brassLight.withOpacity(0.7);
    final fringeY = bodyRect.bottom;
    for (final dx in [0.28, 0.5, 0.72]) {
      final x = bodyRect.left + bodyRect.width * dx;
      canvas.drawLine(Offset(x, fringeY), Offset(x, fringeY + 4), fringePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
