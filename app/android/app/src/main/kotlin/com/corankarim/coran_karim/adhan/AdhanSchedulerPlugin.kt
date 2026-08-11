package com.corankarim.coran_karim.adhan

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Pont Dart -> AlarmManager natif pour l'adhan complet (cf.
 * AdhanPlaybackService, AdhanAlarmReceiver). flutter_local_notifications ne
 * donne aucune prise pour demarrer un Service au moment ou une notification
 * programmee se declenche -- il faut programmer l'alarme nous-memes pour
 * pouvoir lancer la lecture audio reelle au bon instant.
 */
class AdhanSchedulerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> {
                val id = call.argument<Int>("id")
                val whenMillis = (call.argument<Number>("whenMillis"))?.toLong()
                if (id == null || whenMillis == null) {
                    result.error("arg", "id/whenMillis manquant", null)
                    return
                }
                val label = call.argument<String>("label") ?: "Adhan"
                val vibrate = call.argument<Boolean>("vibrate") ?: false
                scheduleAlarm(id, whenMillis, label, vibrate)
                result.success(null)
            }
            "cancel" -> {
                val id = call.argument<Int>("id")
                if (id == null) {
                    result.error("arg", "id manquant", null)
                    return
                }
                cancelAlarm(id)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun alarmPendingIntent(id: Int, label: String? = null, vibrate: Boolean = false): PendingIntent {
        val intent = Intent(appContext, AdhanAlarmReceiver::class.java).apply {
            putExtra(AdhanPlaybackService.EXTRA_PRAYER_ID, id)
            if (label != null) putExtra(AdhanPlaybackService.EXTRA_LABEL, label)
            putExtra(AdhanPlaybackService.EXTRA_VIBRATE, vibrate)
        }
        return PendingIntent.getBroadcast(
            appContext, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun scheduleAlarm(id: Int, whenMillis: Long, label: String, vibrate: Boolean) {
        val am = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = alarmPendingIntent(id, label, vibrate)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
            // Permission d'alarme exacte refusee (rare -- deja demandee cote
            // Dart, cf. PrayerNotificationService.init) : repli inexact plutot
            // que planter, l'adhan sonnera avec un delai possible au lieu de
            // ne jamais sonner.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMillis, pending)
        } else {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMillis, pending)
        }
    }

    private fun cancelAlarm(id: Int) {
        val am = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(alarmPendingIntent(id))
    }

    companion object {
        private const val CHANNEL_NAME = "coran_karim/adhan_alarm"
    }
}
