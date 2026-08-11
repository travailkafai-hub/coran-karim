import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/prayer_settings.dart';

/// Programme l'adhan (5 prières + rappel configurable par prière).
///
/// Deux mécanismes distincts depuis le 2026-08-09 (constat utilisateur :
/// la notification d'adhan s'affichait mais AUCUN son ne sortait) :
///  - le RAPPEL (bref, avant l'heure) reste un son de canal Android via
///    `flutter_local_notifications` -- adapté à un bip court.
///  - l'ADHAN LUI-MÊME (2 min 11, `adhan_makkah.mp3`) passe par
///    `AdhanSchedulerPlugin`/`AdhanAlarmReceiver`/`AdhanPlaybackService`
///    (natif Kotlin) : un vrai lecteur audio démarré par une alarme système
///    au bon instant, avec bouton "Arrêter" sur sa propre notification. Le
///    son de canal ne peut PAS jouer un fichier aussi long de façon fiable
///    (conçu pour de courts bips d'alerte) -- vérifié par mesure
///    (`ffprobe`) avant de changer de mécanisme.
///
/// Persistance au redémarrage du téléphone pour le RAPPEL : gérée NATIVEMENT
/// par flutter_local_notifications (ScheduledNotificationBootReceiver, cf.
/// AndroidManifest.xml). L'ADHAN, lui, est reprogrammé comme tout le reste à
/// chaque ouverture de l'app (cf. [scheduleUpcoming]) -- même modèle de
/// fiabilité que ce qui existait déjà, pas de régression.
///
/// IDs stables et réutilisés (1-5 aujourd'hui, 11-15 demain pour l'adhan ;
/// 20-24 aujourd'hui, 30-34 demain pour le rappel avant chaque prière) :
/// reprogrammer avec le même ID écrase l'ancien au lieu d'empiler des
/// notifications obsolètes -- appeler [scheduleUpcoming] à chaque ouverture
/// de l'app et à chaque changement de réglage suffit, sans avoir à traquer
/// manuellement ce qui est déjà programmé.
class PrayerNotificationService {
  PrayerNotificationService._();
  static final instance = PrayerNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _adhanAlarmChannel = MethodChannel('coran_karim/adhan_alarm');
  bool _initialized = false;

  static const _reminderChannelId = 'prayer_reminder_channel';

  static const _prayerLabels = {
    PrayerName.fajr: 'Sobh',
    PrayerName.dhuhr: 'Dhouhr',
    PrayerName.asr: 'Asr',
    PrayerName.maghrib: 'Maghrib',
    PrayerName.isha: 'Ichaa',
  };

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      // Repli : UTC plutôt que planter -- les horaires seraient décalés mais
      // l'app reste fonctionnelle ; mieux vaut ça qu'un crash au démarrage.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Canal du RAPPEL uniquement -- le canal "adhan" à son personnalisé
      // (RawResourceAndroidNotificationSound) a été retiré le 2026-08-09,
      // remplacé par AdhanPlaybackService (cf. commentaire de la classe) :
      // il ne servait plus à rien, son son ne jouait jamais en pratique.
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _reminderChannelId,
        'Rappel avant la prière',
        description: 'Rappel avant l\'heure d\'une prière',
        importance: Importance.high,
      ));
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    }
    _initialized = true;
  }

  int _idForToday(PrayerName p) => 1 + PrayerName.values.indexOf(p);
  int _idForTomorrow(PrayerName p) => 11 + PrayerName.values.indexOf(p);
  int _reminderIdForToday(PrayerName p) => 20 + PrayerName.values.indexOf(p);
  int _reminderIdForTomorrow(PrayerName p) => 30 + PrayerName.values.indexOf(p);

  /// Programme l'ADHAN natif (AdhanPlaybackService) pour un [id]/[when]/
  /// [label] donnés. Contrairement au rappel, aucun passage par
  /// `flutter_local_notifications` : l'alarme est posée directement côté
  /// Kotlin (`AdhanSchedulerPlugin`), seul chemin capable de démarrer un
  /// Service au bon instant.
  Future<void> _scheduleAdhan({
    required int id,
    required String label,
    required DateTime when,
    required bool vibrate,
  }) async {
    if (when.isBefore(DateTime.now())) {
      // Déjà passé (ex. réouverture de l'app en fin de journée) -- annule
      // plutôt que de programmer dans le passé (déclencherait immédiatement).
      await _adhanAlarmChannel.invokeMethod('cancel', {'id': id});
      return;
    }
    await _adhanAlarmChannel.invokeMethod('schedule', {
      'id': id,
      'whenMillis': when.toUtc().millisecondsSinceEpoch,
      'label': label,
      'vibrate': vibrate,
    });
  }

  Future<void> _cancelAdhan(int id) async {
    await _adhanAlarmChannel.invokeMethod('cancel', {'id': id});
  }

  Future<void> _scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final scheduled = tz.TZDateTime.from(when, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      await _plugin.cancel(id);
      return;
    }
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannelId,
          'Rappel avant la prière',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // Requis par cette version du plugin (18.0.1) meme si iOS n'est pas
      // cible ici -- absoluteTime : la date deja calculee (tz.TZDateTime)
      // est prise telle quelle, pas recalculee en "temps ecoule".
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Reprogramme les prières d'aujourd'hui et de demain (+ les rappels
  /// activés) selon [settings] et les horaires déjà calculés. À appeler à
  /// chaque ouverture de l'app et à chaque changement de réglage/position.
  Future<void> scheduleUpcoming({
    required Map<PrayerName, DateTime> today,
    required Map<PrayerName, DateTime> tomorrow,
    required PrayerSettings settings,
  }) async {
    await init();
    for (final p in PrayerName.values) {
      final enabled = settings.adhanEnabled[p] ?? true;
      final label = _prayerLabels[p]!;
      if (enabled) {
        await _scheduleAdhan(
          id: _idForToday(p),
          label: label,
          when: today[p]!,
          vibrate: settings.vibrateEnabled,
        );
        await _scheduleAdhan(
          id: _idForTomorrow(p),
          label: label,
          when: tomorrow[p]!,
          vibrate: settings.vibrateEnabled,
        );
      } else {
        await _cancelAdhan(_idForToday(p));
        await _cancelAdhan(_idForTomorrow(p));
      }

      final reminderEnabled = settings.reminderEnabled[p] ?? false;
      if (reminderEnabled) {
        final minutesBefore = settings.reminderMinutesBefore[p] ?? 15;
        final offset = Duration(minutes: minutesBefore);
        await _scheduleReminder(
          id: _reminderIdForToday(p),
          title: 'Bientôt — $label dans $minutesBefore min',
          body: 'La prière du $label approche, prépare-toi.',
          when: today[p]!.subtract(offset),
        );
        await _scheduleReminder(
          id: _reminderIdForTomorrow(p),
          title: 'Bientôt — $label dans $minutesBefore min',
          body: 'La prière du $label approche, prépare-toi.',
          when: tomorrow[p]!.subtract(offset),
        );
      } else {
        await _plugin.cancel(_reminderIdForToday(p));
        await _plugin.cancel(_reminderIdForTomorrow(p));
      }
    }
  }
}
