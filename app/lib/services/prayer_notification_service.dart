import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/prayer_settings.dart';

/// Programme l'adhan (5 prières + rappel configurable par prière) via des
/// notifications locales EXACTES (pas d'API réseau, pas de serveur --
/// tout se joue sur l'appareil à l'heure calculée par PrayerTimesService).
///
/// Persistance au redémarrage du téléphone : gérée NATIVEMENT par le plugin
/// (ScheduledNotificationBootReceiver, cf. AndroidManifest.xml) -- aucun code
/// Dart supplémentaire nécessaire pour ça.
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
  bool _initialized = false;

  static const _adhanChannelId = 'adhan_channel';
  // Canal séparé pour le vibreur (demande utilisateur 2026-07-24) : sur
  // Android O+, le pattern de vibration d'un canal est figé à sa création,
  // comme le son -- impossible de le rendre modifiable à la volée avec un
  // seul canal, d'où ce deuxième canal identique sauf sur la vibration.
  static const _adhanChannelVibrateId = 'adhan_channel_vibrate';
  static const _reminderChannelId = 'prayer_reminder_channel';

  static final _vibrationPattern = Int64List.fromList([0, 400, 200, 400]);

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
      // Canal ADHAN : son personnalisé (fichier natif res/raw/, cf.
      // build.gradle/copie -- PAS le chemin assets/ Flutter, Android exige un
      // raw resource pour le son d'un canal de notification). Le son d'un
      // canal Android est figé à sa CRÉATION -- recréer le canal avec un ID
      // différent serait nécessaire pour changer le son plus tard.
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _adhanChannelId,
        'Adhan',
        description: 'Appel à la prière programmé',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('adhan_makkah'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ));
      await android?.createNotificationChannel(AndroidNotificationChannel(
        _adhanChannelVibrateId,
        'Adhan (avec vibreur)',
        description: 'Appel à la prière programmé, avec vibration',
        importance: Importance.max,
        sound: const RawResourceAndroidNotificationSound('adhan_makkah'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern: _vibrationPattern,
      ));
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

  Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required bool isAdhan,
    bool vibrate = false,
  }) async {
    final scheduled = tz.TZDateTime.from(when, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      // Deja passe (ex. reouverture de l'app en fin de journee) -- annuler
      // l'eventuel ancien creneau au lieu de programmer dans le passe
      // (zonedSchedule sur une date passee declenche immediatement, ce qui
      // spammerait une notif a chaque ouverture d'app).
      await _plugin.cancel(id);
      return;
    }
    final channelId = isAdhan
        ? (vibrate ? _adhanChannelVibrateId : _adhanChannelId)
        : _reminderChannelId;
    final channelName = isAdhan
        ? (vibrate ? 'Adhan (avec vibreur)' : 'Adhan')
        : 'Rappel avant la prière';
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: isAdhan ? Importance.max : Importance.high,
          priority: isAdhan ? Priority.max : Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: isAdhan,
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
        await _scheduleOne(
          id: _idForToday(p),
          title: 'Adhan — $label',
          body: 'C\'est l\'heure de la prière du $label.',
          when: today[p]!,
          isAdhan: true,
          vibrate: settings.vibrateEnabled,
        );
        await _scheduleOne(
          id: _idForTomorrow(p),
          title: 'Adhan — $label',
          body: 'C\'est l\'heure de la prière du $label.',
          when: tomorrow[p]!,
          isAdhan: true,
          vibrate: settings.vibrateEnabled,
        );
      } else {
        await _plugin.cancel(_idForToday(p));
        await _plugin.cancel(_idForTomorrow(p));
      }

      final reminderEnabled = settings.reminderEnabled[p] ?? false;
      if (reminderEnabled) {
        final offset = Duration(minutes: settings.reminderMinutesBefore);
        await _scheduleOne(
          id: _reminderIdForToday(p),
          title: 'Bientôt — $label dans ${settings.reminderMinutesBefore} min',
          body: 'La prière du $label approche, prépare-toi.',
          when: today[p]!.subtract(offset),
          isAdhan: false,
        );
        await _scheduleOne(
          id: _reminderIdForTomorrow(p),
          title: 'Bientôt — $label dans ${settings.reminderMinutesBefore} min',
          body: 'La prière du $label approche, prépare-toi.',
          when: tomorrow[p]!.subtract(offset),
          isAdhan: false,
        );
      } else {
        await _plugin.cancel(_reminderIdForToday(p));
        await _plugin.cancel(_reminderIdForTomorrow(p));
      }
    }
  }
}
