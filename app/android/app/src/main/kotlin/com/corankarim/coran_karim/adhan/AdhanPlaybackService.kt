package com.corankarim.coran_karim.adhan

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import com.corankarim.coran_karim.R

/**
 * Joue l'adhan COMPLET (2 min 11, `res/raw/adhan_makkah.mp3`) au moment de la
 * priere.
 *
 * Le mecanisme utilise avant -- le SON DE CANAL de notification
 * (`RawResourceAndroidNotificationSound` cote Dart) -- ne peut pas jouer un
 * fichier aussi long de facon fiable : ce canal est concu par Android pour de
 * courts bips d'alerte, pas un flux de plusieurs minutes. Constat utilisateur
 * 2026-08-09 : la notification s'affichait, aucun son ne sortait -- verifie
 * (`ffprobe`) le fichier fait bien 131,5 s, largement hors gabarit. Ce
 * service remplace ce mecanisme par un VRAI lecteur (MediaPlayer), sur le
 * flux ALARME comme avant, avec wakelock pour tourner ecran eteint.
 *
 * Bouton "Arreter" sur la notification (demande utilisateur : « pas d'ecran
 * en plus, juste l'arret si on touche un bouton pour couper ») -- intercepter
 * les touches volume/power en arriere-plan est impossible sans un Activity au
 * premier plan (categoriquement refusee) ; le bouton sur la notification est
 * l'equivalent qui ne demande aucun ecran supplementaire.
 */
class AdhanPlaybackService : Service() {
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopPlayback()
            return START_NOT_STICKY
        }
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "Adhan"
        val vibrate = intent?.getBooleanExtra(EXTRA_VIBRATE, false) ?: false
        startPlayback(label, vibrate)
        return START_NOT_STICKY
    }

    private fun startPlayback(label: String, vibrate: Boolean) {
        ensureChannel()
        startForeground(NOTIF_ID, buildNotification(label, vibrate))

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "corankarim:adhan").apply {
            // Filet de securite : le fichier dure 131 s, 3 min laisse de la
            // marge sans risquer de garder le CPU eveille indefiniment si
            // `onCompletion`/`onError` ne se declenchaient pas.
            acquire(3 * 60 * 1000L)
        }
        if (vibrate) startVibration()

        player?.release()
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            try {
                val afd = resources.openRawResourceFd(R.raw.adhan_makkah)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
                setOnCompletionListener { stopPlayback() }
                setOnErrorListener { _, _, _ -> stopPlayback(); true }
                prepare()
                start()
            } catch (e: Exception) {
                stopPlayback()
            }
        }
    }

    private fun stopPlayback() {
        player?.let { p ->
            runCatching { if (p.isPlaying) p.stop() }
            p.release()
        }
        player = null
        stopVibration()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * Vibreur en plus du son (demande utilisateur 2026-08-11 : « je veux
     * aussi gerer les vibreurs apres priere »). Declenche ici, en meme temps
     * que le MediaPlayer, plutot que via `builder.setVibrate()` sur la
     * notification (cf. commentaire dans `buildNotification` ci-dessous) :
     * c'est le seul moyen fiable de piloter la vibration a la demande sur
     * Android 8+, pour la meme raison que le son passe par un vrai
     * MediaPlayer plutot que par le canal de notification.
     */
    private fun startVibration() {
        // VIBRATOR_SERVICE est deprecie au profit de VIBRATOR_MANAGER_SERVICE
        // depuis Android 12 (API 31) -- les deux chemins sont necessaires pour
        // couvrir le parc reel d'appareils.
        val vib = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vib == null || !vib.hasVibrator()) return
        vibrator = vib
        // Motif qui se repete (indice de bouclage 0) tant que l'adhan joue,
        // comme le son -- un seul buzz initial se perdrait facilement si le
        // telephone est en poche ou sur une table au moment precis du signal.
        val pattern = longArrayOf(0, 700, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vib.vibrate(pattern, 0)
        }
    }

    private fun stopVibration() {
        vibrator?.cancel()
        vibrator = null
    }

    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Adhan (en cours)", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Affichee pendant la lecture de l'adhan -- le son vient du lecteur, pas du canal"
                // Le son est joue par le MediaPlayer ci-dessus, pas par le canal
                // (c'est justement ce que ce service corrige) -- canal muet.
                setSound(null, null)
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(label: String, vibrate: Boolean): Notification {
        val stopIntent = Intent(this, AdhanPlaybackService::class.java).apply { action = ACTION_STOP }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Adhan — $label")
            .setContentText("C'est l'heure de la prière du $label.")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .addAction(0, "Arrêter", stopPending)
        if (vibrate) {
            // NOTE 2026-08-11 : ce `setVibrate()` sur le builder est en
            // pratique un NO-OP sur Android 8+ (API 26) -- une fois un canal
            // de notification cree (`ensureChannel` ci-dessus), c'est LUI qui
            // decide du comportement de vibration, pas le builder par
            // notification ; et ce canal ne configure jamais de vibration
            // (`enableVibration`/`setVibrationPattern` jamais appeles). C'est
            // le defaut a l'origine du symptome signale par l'utilisateur
            // (« je veux aussi gerer les vibreurs ») alors que le reglage
            // existait deja de bout en bout (Dart -> EXTRA_VIBRATE -> ici).
            // Garde tel quel (harmless, peut encore servir sur un appareil
            // pre-O reel) mais la vibration effective vient desormais de
            // `startVibration()` (Vibrator direct, cf. `startPlayback`) qui,
            // lui, n'est pas soumis a cette limitation de canal.
            builder.setVibrate(longArrayOf(0, 400, 200, 400))
        }
        return builder.build()
    }

    companion object {
        const val ACTION_STOP = "com.corankarim.coran_karim.adhan.STOP"
        const val EXTRA_LABEL = "label"
        const val EXTRA_PRAYER_ID = "prayerId"
        const val EXTRA_VIBRATE = "vibrate"
        private const val CHANNEL_ID = "adhan_playback_channel"
        private const val NOTIF_ID = 9001
    }
}
