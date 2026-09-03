package com.corankarim.coran_karim.audio

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Bascule la CAPTURE vers le micro d'un casque Bluetooth, et la rend.
 *
 * ── POURQUOI (demande utilisateur 2026-09-03) ────────────────────────────────
 *
 * « Est-ce que "Lire" et "Réciter" fonctionnent avec mes micros d'oreillettes
 * et casque ? »
 *
 * Constat verifie dans le code avant d'ecrire une ligne : l'ECOUTE sort bien
 * sur le Bluetooth (route media A2DP, rien a faire), et le micro d'un casque
 * FILAIRE est pris automatiquement par Android. Mais pour un casque BLUETOOTH,
 * l'app n'avait AUCUN code de routage -- ni startBluetoothSco, ni
 * setCommunicationDevice, ni MODE_IN_COMMUNICATION -- et Android continuait
 * donc d'utiliser le micro du telephone.
 *
 * ── LE COUT, A CONNAITRE AVANT D'ACTIVER ─────────────────────────────────────
 *
 * Le micro d'un casque Bluetooth passe par le profil HFP/SCO, qui compresse la
 * voix en bande etroite (8 ou 16 kHz tres reduits) et fait basculer toute la
 * sortie en mono telephonie. Le modele ASR de l'app est entraine sur du 16 kHz
 * propre : la reconnaissance s'en trouve degradee, dans une mesure qui n'a pas
 * encore ete chiffree sur ce projet.
 *
 * C'est pourquoi ce routage est un REGLAGE, eteint par defaut, et non un
 * comportement automatique : livrer une bascule silencieuse reviendrait a
 * degrader la reconnaissance sans le dire a celui qui recite.
 *
 * ── DEUX CHEMINS, PARCE QUE minSdk = 24 ──────────────────────────────────────
 *
 * - API 31+ : `setCommunicationDevice(...)`, l'API officielle, qui remplace
 *   toute la gymnastique SCO et se defait proprement ;
 * - API 24..30 : `startBluetoothSco()` + `setBluetoothScoOn(true)`, deprecies
 *   mais seuls disponibles. Ils demandent le mode IN_COMMUNICATION, qui change
 *   le routage de TOUTE l'application -- d'ou la restauration explicite du mode
 *   precedent dans [desactiver].
 */
object RoutageMicro {

    private const val TAG = "RoutageMicro"

    /** Mode audio d'avant la bascule, a rendre tel quel. */
    private var modeAvant: Int? = null
    private var actif = false

    /** Micros disponibles, pour que l'ecran puisse dire ce qu'il a trouve. */
    fun entrees(context: Context): List<Map<String, Any>> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return am.getDevices(AudioManager.GET_DEVICES_INPUTS).map {
            mapOf(
                "type" to it.type,
                "nom" to (it.productName?.toString() ?: ""),
                "bluetooth" to estBluetooth(it.type),
            )
        }
    }

    private fun estBluetooth(type: Int) =
        type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                type == AudioDeviceInfo.TYPE_BLE_HEADSET)

    /**
     * Bascule la capture sur le micro Bluetooth. Rend `true` si un peripherique
     * a effectivement ete pris.
     *
     * Rendre `false` n'est PAS une erreur : cela veut dire qu'aucun casque avec
     * micro n'est connecte. L'appelant garde alors le micro du telephone, ce
     * qui est le comportement d'avant.
     */
    @SuppressLint("MissingPermission")
    fun activer(context: Context): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (actif) return true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val cible = am.availableCommunicationDevices
                    .firstOrNull { estBluetooth(it.type) }
                if (cible == null) {
                    Log.i(TAG, "aucun micro Bluetooth disponible")
                    return false
                }
                modeAvant = am.mode
                am.mode = AudioManager.MODE_IN_COMMUNICATION
                val ok = am.setCommunicationDevice(cible)
                actif = ok
                Log.i(TAG, "setCommunicationDevice(${cible.productName}) -> $ok")
                if (!ok) am.mode = modeAvant ?: AudioManager.MODE_NORMAL
                ok
            } else {
                @Suppress("DEPRECATION")
                if (!am.isBluetoothScoAvailableOffCall) {
                    Log.i(TAG, "SCO hors appel non disponible sur cet appareil")
                    return false
                }
                modeAvant = am.mode
                am.mode = AudioManager.MODE_IN_COMMUNICATION
                @Suppress("DEPRECATION")
                am.startBluetoothSco()
                @Suppress("DEPRECATION")
                am.setBluetoothScoOn(true)
                actif = true
                Log.i(TAG, "SCO demarre (chemin API < 31)")
                true
            }
        } catch (e: Exception) {
            // Une exception ici ne doit JAMAIS empecher de reciter : on rend le
            // micro du telephone et on continue.
            Log.w(TAG, "bascule impossible, on garde le micro du telephone", e)
            desactiver(context)
            false
        }
    }

    /** Rend le micro du telephone et restaure le mode audio d'avant.
     *
     *  ⚠️ SORTIE IMMEDIATE SI RIEN N'A ETE BASCULE (2026-09-03). L'appelant
     *  invoque cette methode a CHAQUE fermeture de capture, sans savoir si le
     *  reglage Bluetooth etait actif -- c'est voulu, pour qu'aucun chemin
     *  d'erreur ne laisse le mode audio sur IN_COMMUNICATION. Mais sans ce
     *  garde, `clearCommunicationDevice()` s'executait sur TOUTES les
     *  recitations, y compris celles qui n'ont jamais touche au Bluetooth :
     *  une intervention sur le routage audio du systeme a chaque session,
     *  pour rien, et invisible dans le journal.
     *
     *  Trouve en repondant a la question « est-ce que le travail sur les
     *  styles d'ecriture a cause une regression ? » -- il ne l'avait pas
     *  causee, mais la question a fait relire ce qui, lui, touchait vraiment
     *  la chaine de capture. */
    fun desactiver(context: Context) {
        if (!actif && modeAvant == null) return
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                am.setBluetoothScoOn(false)
                @Suppress("DEPRECATION")
                am.stopBluetoothSco()
            }
        } catch (e: Exception) {
            Log.w(TAG, "restauration partielle", e)
        } finally {
            // Le mode est restaure MEME si la coupure a echoue : le laisser sur
            // IN_COMMUNICATION rendrait toute l'app muette sur le haut-parleur,
            // bien apres la fin de la recitation.
            modeAvant?.let { am.mode = it }
            modeAvant = null
            actif = false
        }
    }

    fun brancher(context: Context, canal: MethodChannel) {
        canal.setMethodCallHandler { appel, resultat ->
            when (appel.method) {
                "entrees" -> resultat.success(entrees(context))
                "activer" -> resultat.success(activer(context))
                "desactiver" -> {
                    desactiver(context)
                    resultat.success(null)
                }
                else -> resultat.notImplemented()
            }
        }
    }
}
