/// Réglages des horaires de prière et de l'adhan programmé.
library;

/// Les 3 méthodes de calcul demandées par l'utilisateur (2026-07-24) — le
/// défaut est choisi selon la position GPS (cf. PrayerTimesService), mais
/// les trois restent toujours sélectionnables manuellement.
enum PrayerCalculationMethod { muslimWorldLeague, ummAlQura, egyptian }

enum PrayerName { fajr, dhuhr, asr, maghrib, isha }

class PrayerSettings {
  final PrayerCalculationMethod method;
  final bool methodIsAuto; // true = suit la position GPS, false = figé par l'utilisateur
  final Map<PrayerName, bool> adhanEnabled; // toggle PAR prière (demande utilisateur)

  /// Vibreur en plus du son de l'adhan (demande utilisateur 2026-07-24).
  /// Contrôle un CANAL Android distinct (`adhan_channel_vibrate`) plutôt
  /// qu'un simple flag sur la notification : sur Android O+, le pattern de
  /// vibration d'un canal est figé à sa création, comme le son (cf.
  /// PrayerNotificationService) -- il faut donc deux canaux, pas un seul
  /// paramètre modifiable à la volée.
  final bool vibrateEnabled;

  /// Rappel configurable AVANT l'adhan, activable prière par prière (pas
  /// seulement Sobh : généralisé le 2026-07-24 sur demande utilisateur, qui
  /// ne l'a pas limité à une seule prière). Un seul délai partagé par les 5
  /// prières -- inutile de complexifier avec un délai par prière tant que
  /// personne ne l'a demandé.
  final Map<PrayerName, bool> reminderEnabled;
  final int reminderMinutesBefore; // 10/15/20... configurable

  const PrayerSettings({
    required this.method,
    required this.methodIsAuto,
    required this.adhanEnabled,
    required this.vibrateEnabled,
    required this.reminderEnabled,
    required this.reminderMinutesBefore,
  });

  static const defaultValues = PrayerSettings(
    method: PrayerCalculationMethod.muslimWorldLeague,
    methodIsAuto: true,
    adhanEnabled: {
      PrayerName.fajr: true,
      PrayerName.dhuhr: true,
      PrayerName.asr: true,
      PrayerName.maghrib: true,
      PrayerName.isha: true,
    },
    vibrateEnabled: true,
    reminderEnabled: {
      PrayerName.fajr: false,
      PrayerName.dhuhr: false,
      PrayerName.asr: false,
      PrayerName.maghrib: false,
      PrayerName.isha: false,
    },
    reminderMinutesBefore: 15,
  );

  PrayerSettings copyWith({
    PrayerCalculationMethod? method,
    bool? methodIsAuto,
    Map<PrayerName, bool>? adhanEnabled,
    bool? vibrateEnabled,
    Map<PrayerName, bool>? reminderEnabled,
    int? reminderMinutesBefore,
  }) {
    return PrayerSettings(
      method: method ?? this.method,
      methodIsAuto: methodIsAuto ?? this.methodIsAuto,
      adhanEnabled: adhanEnabled ?? this.adhanEnabled,
      vibrateEnabled: vibrateEnabled ?? this.vibrateEnabled,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
    );
  }

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'methodIsAuto': methodIsAuto,
        'adhanEnabled': adhanEnabled.map((k, v) => MapEntry(k.name, v)),
        'vibrateEnabled': vibrateEnabled,
        'reminderEnabled': reminderEnabled.map((k, v) => MapEntry(k.name, v)),
        'reminderMinutesBefore': reminderMinutesBefore,
      };

  factory PrayerSettings.fromJson(Map<String, dynamic> j) {
    final rawAdhan = (j['adhanEnabled'] as Map?)?.cast<String, dynamic>();
    final adhan = <PrayerName, bool>{
      for (final p in PrayerName.values)
        p: (rawAdhan?[p.name] as bool?) ?? defaultValues.adhanEnabled[p]!,
    };
    final rawReminder = (j['reminderEnabled'] as Map?)?.cast<String, dynamic>();
    final reminder = <PrayerName, bool>{
      for (final p in PrayerName.values)
        p: (rawReminder?[p.name] as bool?) ?? defaultValues.reminderEnabled[p]!,
    };
    return PrayerSettings(
      method: PrayerCalculationMethod.values.firstWhere(
          (m) => m.name == j['method'],
          orElse: () => PrayerCalculationMethod.muslimWorldLeague),
      methodIsAuto: j['methodIsAuto'] as bool? ?? true,
      adhanEnabled: adhan,
      vibrateEnabled: j['vibrateEnabled'] as bool? ?? true,
      reminderEnabled: reminder,
      reminderMinutesBefore: j['reminderMinutesBefore'] as int? ?? 15,
    );
  }
}
