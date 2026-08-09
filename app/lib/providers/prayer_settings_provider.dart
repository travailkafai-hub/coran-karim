// Provider des horaires de prière + adhan programmé (2026-07-24, demande
// utilisateur). Persistance SharedPreferences, même pattern que
// judgement_provider.dart.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prayer_settings.dart';
import '../services/prayer_notification_service.dart';
import '../services/prayer_times_service.dart';

const _kPrefPrayerSettings = 'prayer_settings_v1';
const _kPrefLastPosition = 'prayer_last_position_v1';

enum PrayerLocationStatus { loading, ready, serviceDisabled, permissionDenied, error }

class PrayerState {
  final PrayerSettings settings;
  final PrayerLocationStatus locationStatus;
  final double? lat;
  final double? lng;
  final Map<PrayerName, DateTime>? today;
  final Map<PrayerName, DateTime>? tomorrow;

  const PrayerState({
    required this.settings,
    required this.locationStatus,
    this.lat,
    this.lng,
    this.today,
    this.tomorrow,
  });

  factory PrayerState.initial() => const PrayerState(
        settings: PrayerSettings.defaultValues,
        locationStatus: PrayerLocationStatus.loading,
      );

  PrayerState copyWith({
    PrayerSettings? settings,
    PrayerLocationStatus? locationStatus,
    double? lat,
    double? lng,
    Map<PrayerName, DateTime>? today,
    Map<PrayerName, DateTime>? tomorrow,
  }) {
    return PrayerState(
      settings: settings ?? this.settings,
      locationStatus: locationStatus ?? this.locationStatus,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      today: today ?? this.today,
      tomorrow: tomorrow ?? this.tomorrow,
    );
  }
}

final prayerSettingsProvider =
    StateNotifierProvider<PrayerSettingsNotifier, PrayerState>((ref) {
  final n = PrayerSettingsNotifier();
  n._bootstrap();
  return n;
});

class PrayerSettingsNotifier extends StateNotifier<PrayerState> {
  PrayerSettingsNotifier() : super(PrayerState.initial());

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final rawSettings = prefs.getString(_kPrefPrayerSettings);
    var settings = PrayerSettings.defaultValues;
    if (rawSettings != null) {
      try {
        settings =
            PrayerSettings.fromJson(jsonDecode(rawSettings) as Map<String, dynamic>);
      } catch (_) {
        // Reglages corrompus -> defaut plutot que planter.
      }
    }
    if (mounted) state = state.copyWith(settings: settings);
    await refreshLocation();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefPrayerSettings, jsonEncode(state.settings.toJson()));
  }

  Future<void> _recomputeAndSchedule() async {
    final lat = state.lat, lng = state.lng;
    if (lat == null || lng == null) return;
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final method = state.settings.method;
    final today = PrayerTimesService.compute(
        lat: lat, lng: lng, date: now, method: method);
    final tmr = PrayerTimesService.compute(
        lat: lat, lng: lng, date: tomorrow, method: method);
    if (mounted) state = state.copyWith(today: today, tomorrow: tmr);
    await PrayerNotificationService.instance.scheduleUpcoming(
      today: today,
      tomorrow: tmr,
      settings: state.settings,
    );
  }

  /// Récupère la position GPS (même flux de permission que QiblaScreen) et
  /// recalcule/reprogramme. À appeler à l'ouverture de l'app et si
  /// l'utilisateur force un rafraîchissement (changement de lieu de vie).
  Future<void> refreshLocation() async {
    state = state.copyWith(locationStatus: PrayerLocationStatus.loading);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = state.copyWith(locationStatus: PrayerLocationStatus.serviceDisabled);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(locationStatus: PrayerLocationStatus.permissionDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kPrefLastPosition, jsonEncode({'lat': pos.latitude, 'lng': pos.longitude}));

      var settings = state.settings;
      if (settings.methodIsAuto) {
        settings = settings.copyWith(
          method: PrayerTimesService.defaultMethodFor(pos.latitude, pos.longitude),
        );
      }
      state = state.copyWith(
        locationStatus: PrayerLocationStatus.ready,
        lat: pos.latitude,
        lng: pos.longitude,
        settings: settings,
      );
      await _persist();
      await _recomputeAndSchedule();
    } catch (_) {
      // Dernier recours : position deja connue en cache (ex. pas de GPS
      // ponctuellement disponible) -- mieux que de ne rien afficher du tout.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefLastPosition);
      if (raw != null) {
        try {
          final cached = jsonDecode(raw) as Map<String, dynamic>;
          state = state.copyWith(
            locationStatus: PrayerLocationStatus.ready,
            lat: (cached['lat'] as num).toDouble(),
            lng: (cached['lng'] as num).toDouble(),
          );
          await _recomputeAndSchedule();
          return;
        } catch (_) {}
      }
      state = state.copyWith(locationStatus: PrayerLocationStatus.error);
    }
  }

  Future<void> setMethod(PrayerCalculationMethod method) async {
    state = state.copyWith(
        settings: state.settings.copyWith(method: method, methodIsAuto: false));
    await _persist();
    await _recomputeAndSchedule();
  }

  Future<void> setMethodAuto() async {
    final lat = state.lat, lng = state.lng;
    final method = (lat != null && lng != null)
        ? PrayerTimesService.defaultMethodFor(lat, lng)
        : state.settings.method;
    state = state.copyWith(
        settings: state.settings.copyWith(method: method, methodIsAuto: true));
    await _persist();
    await _recomputeAndSchedule();
  }

  Future<void> setAdhanEnabled(PrayerName prayer, bool enabled) async {
    final map = {...state.settings.adhanEnabled, prayer: enabled};
    state = state.copyWith(settings: state.settings.copyWith(adhanEnabled: map));
    await _persist();
    await _recomputeAndSchedule();
  }

  Future<void> setVibrateEnabled(bool enabled) async {
    state = state.copyWith(
        settings: state.settings.copyWith(vibrateEnabled: enabled));
    await _persist();
    await _recomputeAndSchedule();
  }

  Future<void> setReminderEnabled(PrayerName prayer, bool enabled) async {
    final map = {...state.settings.reminderEnabled, prayer: enabled};
    state = state.copyWith(
        settings: state.settings.copyWith(reminderEnabled: map));
    await _persist();
    await _recomputeAndSchedule();
  }

  /// Délai PAR prière depuis le 2026-08-08 (cf. commentaire sur
  /// PrayerSettings) -- même forme que [setReminderEnabled].
  Future<void> setReminderMinutesBefore(PrayerName prayer, int minutes) async {
    final map = {...state.settings.reminderMinutesBefore, prayer: minutes};
    state = state.copyWith(
        settings: state.settings.copyWith(reminderMinutesBefore: map));
    await _persist();
    await _recomputeAndSchedule();
  }
}
