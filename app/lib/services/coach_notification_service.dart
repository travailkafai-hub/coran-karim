import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/objectif_coach.dart';
import '../models/prayer_settings.dart' show PrayerName;

/// Rappels de mémorisation, ADOSSÉS AUX HORAIRES DE PRIÈRE déjà calculés par
/// l'app (cf. `PrayerTimesService`) -- décision utilisateur 2026-08-13,
/// `PLAN_COACH.md` §4 : « ça suit les saisons sans réglage, et tombe à des
/// moments où l'utilisateur est déjà tourné vers le Coran ».
///
/// Renforcés le SOIR (Maghrib, toujours) et le WEEK-END (Dhuhr, en plus) --
/// « les moments où le temps existe réellement ». Trois créneaux possibles
/// selon le [NiveauCoach] :
///   - Maghrib +20 min : le rappel de base, tous les niveaux sauf "à mon
///     rythme" ;
///   - Asr +20 min : ajouté en niveau EXIGEANT seulement ;
///   - Dhuhr +30 min : ajouté le WEEK-END, sauf "à mon rythme".
///
/// Même patron que `PrayerNotificationService` (même paquet, mêmes réglages
/// de canal Android, même `zonedSchedule`) -- volontairement un service
/// SÉPARÉ : les deux ne partagent qu'un mécanisme, pas un sujet. Fusionner
/// aurait mélangé l'adhan (obligation religieuse, jamais silencieuse) et
/// l'encouragement à réciter (qui doit au contraire savoir se taire, cf.
/// [scheduleUpcoming] : silence total si l'objectif du jour est déjà atteint).
class CoachNotificationService {
  CoachNotificationService._();
  static final instance = CoachNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'coach_reminder_channel';
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    // Le fuseau horaire local est déjà configuré globalement par
    // `PrayerNotificationService.init()` (`tz.setLocalLocation`), appelé
    // avant celui-ci dans le même cycle de démarrage -- pas la peine de le
    // refaire, `tz.local` est déjà le bon fuseau à ce stade.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        'Rappel de mémorisation',
        description: 'Rappel quotidien pour la mémorisation du Coran',
        importance: Importance.defaultImportance,
      ));
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    }
    _initialized = true;
  }

  // IDs stables (rescheduling = écrase l'ancien, même principe que
  // PrayerNotificationService) -- plage 50-52 aujourd'hui, 60-62 demain,
  // pour ne jamais empiéter sur la plage 1-34 déjà prise par l'adhan.
  static const _idSoirAuj = 50;
  static const _idApresMidiAuj = 51;
  static const _idWeekendAuj = 52;
  static const _idSoirDemain = 60;
  static const _idApresMidiDemain = 61;
  static const _idWeekendDemain = 62;

  static const _tousLesIds = [
    _idSoirAuj, _idApresMidiAuj, _idWeekendAuj, //
    _idSoirDemain, _idApresMidiDemain, _idWeekendDemain,
  ];

  Future<void> _programmer({
    required int id,
    required String titre,
    required String corps,
    required DateTime quand,
  }) async {
    final scheduled = tz.TZDateTime.from(quand, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      await _plugin.cancel(id);
      return;
    }
    await _plugin.zonedSchedule(
      id,
      titre,
      corps,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Rappel de mémorisation',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Coupe tout rappel programmé -- niveau "à mon rythme", ou aucun objectif
  /// fixé (cf. `ObjectifCoach.actif`).
  Future<void> annulerTout() async {
    await init();
    for (final id in _tousLesIds) {
      await _plugin.cancel(id);
    }
  }

  (String, String) _messageDuSoir(int serie) => serie > 0
      ? (
          'Ta série de $serie jour${serie > 1 ? 's' : ''} s\'arrête ce soir',
          'Récite un quart de Hizb pour la garder.'
        )
      : ('Un moment pour réciter ?', 'Avance vers ton objectif de mémorisation.');

  static const _titreApresMidi = 'Un moment pour réciter ?';
  static const _corpsApresMidi =
      'Un quart de Hizb aujourd\'hui te rapproche de ton objectif.';
  static const _titreWeekend = 'Le week-end, le bon moment';
  static const _corpsWeekend =
      'Profite d\'avoir un peu plus de temps pour mémoriser aujourd\'hui.';
  static const _titreGenerique = 'Ta mémorisation t\'attend';
  static const _corpsGenerique = 'Un moment pour réciter aujourd\'hui ?';

  bool _weekend(Map<PrayerName, DateTime> jour) {
    final w = jour[PrayerName.fajr]!.weekday;
    return w == DateTime.saturday || w == DateTime.sunday;
  }

  /// Reprogramme les rappels d'aujourd'hui et de demain. À appeler à chaque
  /// ouverture de l'app et à chaque changement d'objectif/niveau/position
  /// (cf. `coachNotificationBootstrapProvider`).
  ///
  /// [objectifAtteintAujourdhui] SILENCE tous les rappels du jour (règle
  /// posée dans `PLAN_COACH.md` §3 : « silencieux si l'objectif du jour est
  /// déjà atteint »). Il ne peut porter que sur AUJOURD'HUI -- l'état de
  /// demain n'est pas encore connu, ses rappels restent donc génériques.
  Future<void> scheduleUpcoming({
    required Map<PrayerName, DateTime> today,
    required Map<PrayerName, DateTime> tomorrow,
    required NiveauCoach niveau,
    required bool objectifAtteintAujourdhui,
    required int serie,
  }) async {
    await init();
    if (niveau == NiveauCoach.aMonRythme) {
      await annulerTout();
      return;
    }

    if (objectifAtteintAujourdhui) {
      await _plugin.cancel(_idSoirAuj);
      await _plugin.cancel(_idApresMidiAuj);
      await _plugin.cancel(_idWeekendAuj);
    } else {
      final (titre, corps) = _messageDuSoir(serie);
      await _programmer(
        id: _idSoirAuj,
        titre: titre,
        corps: corps,
        quand: today[PrayerName.maghrib]!.add(const Duration(minutes: 20)),
      );
      if (niveau == NiveauCoach.exigeant) {
        await _programmer(
          id: _idApresMidiAuj,
          titre: _titreApresMidi,
          corps: _corpsApresMidi,
          quand: today[PrayerName.asr]!.add(const Duration(minutes: 20)),
        );
      } else {
        await _plugin.cancel(_idApresMidiAuj);
      }
      if (_weekend(today)) {
        await _programmer(
          id: _idWeekendAuj,
          titre: _titreWeekend,
          corps: _corpsWeekend,
          quand: today[PrayerName.dhuhr]!.add(const Duration(minutes: 30)),
        );
      } else {
        await _plugin.cancel(_idWeekendAuj);
      }
    }

    // Demain : état futur inconnu -> message générique, jamais de silence
    // (on ne peut pas savoir si l'objectif sera déjà atteint).
    await _programmer(
      id: _idSoirDemain,
      titre: _titreGenerique,
      corps: _corpsGenerique,
      quand: tomorrow[PrayerName.maghrib]!.add(const Duration(minutes: 20)),
    );
    if (niveau == NiveauCoach.exigeant) {
      await _programmer(
        id: _idApresMidiDemain,
        titre: _titreApresMidi,
        corps: _corpsApresMidi,
        quand: tomorrow[PrayerName.asr]!.add(const Duration(minutes: 20)),
      );
    } else {
      await _plugin.cancel(_idApresMidiDemain);
    }
    if (_weekend(tomorrow)) {
      await _programmer(
        id: _idWeekendDemain,
        titre: _titreWeekend,
        corps: _corpsWeekend,
        quand: tomorrow[PrayerName.dhuhr]!.add(const Duration(minutes: 30)),
      );
    } else {
      await _plugin.cancel(_idWeekendDemain);
    }
  }
}
