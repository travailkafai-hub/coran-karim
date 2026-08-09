import 'package:adhan_dart/adhan_dart.dart';

import '../models/prayer_settings.dart';

/// Calcul LOCAL des horaires de prière (adhan_dart, pas d'API réseau --
/// cohérent avec le reste de l'app : Coran/ASR déjà embarqués sur
/// l'appareil, pas de dépendance à une connexion au moment de la prière).
class PrayerTimesService {
  /// Méthode par défaut selon la position GPS (demande utilisateur
  /// 2026-07-24 : "les trois avec une par défaut selon la localisation").
  /// Heuristique simple par boîte lat/lng, volontairement grossière --
  /// l'utilisateur peut toujours choisir manuellement dans les réglages,
  /// ceci ne sert qu'à proposer un défaut raisonnable au premier lancement.
  static PrayerCalculationMethod defaultMethodFor(double lat, double lng) {
    // Péninsule arabique / Golfe (Arabie Saoudite, Émirats, Qatar, Bahreïn,
    // Koweït, Oman) -> Umm al-Qura, convention du Golfe.
    if (lat >= 12 && lat <= 32 && lng >= 34 && lng <= 60) {
      return PrayerCalculationMethod.ummAlQura;
    }
    // Égypte (et proche voisinage) -> méthode égyptienne.
    if (lat >= 20 && lat <= 32 && lng >= -10 && lng < 34) {
      return PrayerCalculationMethod.egyptian;
    }
    // France métropolitaine (boîte large, même granularité volontairement
    // grossière que les boîtes ci-dessus) -> convention UOIF 12°/12°,
    // ajoutée le 2026-08-08 : Muslim World League (17° Ichaa) donnait un
    // écart de ~40 min avec l'heure retenue par les mosquées françaises,
    // très visible en été à cette latitude (crépuscule long).
    if (lat >= 41 && lat <= 51.5 && lng >= -5.5 && lng <= 9.7) {
      return PrayerCalculationMethod.franceUoif;
    }
    // Partout ailleurs -> Muslim World League, la plus répandue
    // internationalement, bon défaut neutre.
    return PrayerCalculationMethod.muslimWorldLeague;
  }

  static CalculationParameters _params(PrayerCalculationMethod m) {
    return switch (m) {
      PrayerCalculationMethod.muslimWorldLeague =>
        CalculationMethodParameters.muslimWorldLeague(),
      PrayerCalculationMethod.ummAlQura =>
        CalculationMethodParameters.ummAlQura(),
      PrayerCalculationMethod.egyptian =>
        CalculationMethodParameters.egyptian(),
      // Pas de préréglage "France" dans adhan_dart -- construite à la main
      // (méthode UOIF, angles Fajr/Ichaa 12°/12°, pas d'ajustement connu).
      PrayerCalculationMethod.franceUoif => CalculationParameters(
          method: CalculationMethod.other, fajrAngle: 12, ishaAngle: 12),
    };
  }

  /// Horaires des 5 prières pour [date] (jour civil, heure locale) à la
  /// position [lat]/[lng], selon la méthode [method].
  static Map<PrayerName, DateTime> compute({
    required double lat,
    required double lng,
    required DateTime date,
    required PrayerCalculationMethod method,
  }) {
    final coordinates = Coordinates(lat, lng);
    final params = _params(method);
    final prayerTimes = PrayerTimes(
      coordinates: coordinates,
      date: date,
      calculationParameters: params,
    );
    return {
      PrayerName.fajr: prayerTimes.fajr,
      PrayerName.dhuhr: prayerTimes.dhuhr,
      PrayerName.asr: prayerTimes.asr,
      PrayerName.maghrib: prayerTimes.maghrib,
      PrayerName.isha: prayerTimes.isha,
    };
  }
}
