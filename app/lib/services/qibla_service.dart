import 'dart:math' as math;

/// Calculs géométriques purs pour la direction/distance de la Qibla —
/// aucune dépendance capteur/permission ici (cf. qibla_screen.dart pour
/// la position et le cap de l'appareil).
class QiblaService {
  /// Coordonnées de la Kaaba (Masjid al-Haram, La Mecque).
  static const double kaabaLat = 21.4225;
  static const double kaabaLng = 39.8262;

  /// Cap initial du grand cercle (0-360°, 0 = nord géographique) allant de
  /// [lat]/[lng] vers la Kaaba — formule standard de navigation orthodromique.
  static double bearingToMecca(double lat, double lng) {
    final phi1 = _toRad(lat);
    final phi2 = _toRad(kaabaLat);
    final deltaLambda = _toRad(kaabaLng - lng);
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (_toDeg(theta) + 360) % 360;
  }

  /// Distance approximative (km) jusqu'à la Kaaba (formule de haversine,
  /// rayon terrestre moyen — précision suffisante pour un usage d'orientation,
  /// pas de navigation maritime).
  static double distanceToMeccaKm(double lat, double lng) {
    const earthRadiusKm = 6371.0;
    final phi1 = _toRad(lat);
    final phi2 = _toRad(kaabaLat);
    final deltaPhi = _toRad(kaabaLat - lat);
    final deltaLambda = _toRad(kaabaLng - lng);
    final a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Écart angulaire absolu le plus court entre deux caps (0-180°) — sert à
  /// juger si l'appareil "fait face" à la Qibla à quelques degrés près.
  static double angleDiff(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;
}
