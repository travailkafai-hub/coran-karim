package com.corankarim.coran_karim.adhan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Recu au moment exact d'une priere (programme via AlarmManager, cf.
 * AdhanSchedulerPlugin) -- demarre le service qui joue l'adhan complet.
 *
 * Chemin separe de flutter_local_notifications : celui-ci ne peut que poster
 * une notification a l'heure dite, pas demarrer un Service natif au meme
 * instant -- indispensable pour la lecture audio reelle (cf.
 * AdhanPlaybackService).
 */
class AdhanAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceIntent = Intent(context, AdhanPlaybackService::class.java).apply {
            putExtra(AdhanPlaybackService.EXTRA_LABEL,
                intent.getStringExtra(AdhanPlaybackService.EXTRA_LABEL) ?: "Adhan")
            putExtra(AdhanPlaybackService.EXTRA_PRAYER_ID,
                intent.getIntExtra(AdhanPlaybackService.EXTRA_PRAYER_ID, 0))
            putExtra(AdhanPlaybackService.EXTRA_VIBRATE,
                intent.getBooleanExtra(AdhanPlaybackService.EXTRA_VIBRATE, false))
        }
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
