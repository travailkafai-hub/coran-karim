package com.corankarim.coran_karim.fastconformer

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteBuffer

/**
 * Decode une PLAGE d'un fichier audio compresse (MP3, AAC…) en PCM mono 16 kHz
 * float32 [-1, 1] -- exactement la forme que `MelSpectrogram.compute` attend et
 * que `WavReader.readMono16kFloat` produit deja pour les WAV.
 *
 * ── POURQUOI CE FICHIER EXISTE (2026-09-06) ───────────────────────────────
 *
 * Le decoupage des paliers et celui de l'audio etaient DEUX mecaniques
 * independantes : le texte se coupait sur `coupes_palier_afasy.json` (des
 * coupes d'energie mesurees sur l'enregistrement d'AL-AFASY, donc justes pour
 * lui seul) tandis que l'audio se coupait, en Warsh, sur une « decoupe
 * ponderee, non mesuree ». Rien ne reliait les deux, et l'utilisateur
 * l'entendait : « le texte ne correspond pas a l'audio, l'audio dit un peu
 * plus ».
 *
 * Sa proposition, retenue : « en premier l'audio qui pilote -- on decoupe
 * l'audio, puis on affiche le texte ». Une seule source de verite au lieu de
 * deux, et c'est la bonne : le recitateur s'arrete aux waqf, le texte n'en sait
 * rien.
 *
 * Tout le reste existait deja -- `ConstructeurDeFenetres` rend les silences
 * reels, `AligneurForce` rend `premiereFrame`/`derniereFrame` par mot. Il
 * manquait uniquement de quoi transformer le MP3 d'un recitateur en
 * echantillons. C'est ce fichier.
 *
 * ── CE QU'ON NE PERD PAS EN DESCENDANT A 16 kHz ───────────────────────────
 *
 * Le modele a ete ENTRAINE a 16 kHz mono (cf. l'en-tete de `MelSpectrogram` :
 * `sample_rate=16000, n_fft=512, win_length=400, hop_length=160`). Descendre
 * de 44,1 kHz supprime les frequences au-dela de 8 kHz -- que le modele n'a
 * jamais vues. Ce n'est donc pas une degradation, c'est la mise au format.
 * La seule vraie perte est celle du MP3 lui-meme, et c'est ce que les sources
 * publient.
 *
 * ── A LA DEMANDE, PAS EN BLOC (choix valide par l'utilisateur) ────────────
 *
 * Convertir une sourate entiere en WAV couterait des centaines de Mo sur le
 * disque pour les plus longues. `MediaExtractor.seekTo` permet de n'ouvrir que
 * la plage d'un verset : quelques centaines de ko en memoire, et rien n'est
 * ecrit. L'appelant met le RESULTAT de l'analyse en cache, pas l'audio.
 *
 * ⚠️ LE REECHANTILLONNAGE EST LINEAIRE, ET C'EST UN CHOIX BORNE. Un filtre
 * anti-repliement en bonne et due forme serait plus propre ; l'interpolation
 * lineaire replie une partie du bruit au-dessus de 8 kHz dans la bande utile.
 * Sur de la voix, ou l'energie est concentree sous 4 kHz, l'effet est faible --
 * mais c'est une approximation ASSUMEE, pas un oubli. Si les probabilites du
 * modele semblaient basses sur un audio decode ici alors qu'elles sont hautes
 * sur le meme passage capte au micro, c'est le premier endroit ou regarder.
 */
object DecodeurAudio {

    private const val CIBLE_HZ = 16_000

    /**
     * @param chemin fichier local (MP3 telecharge de MP3Quran, ou tout format
     *   que la plateforme sait lire)
     * @param debutMs debut de la plage a decoder
     * @param finMs fin de la plage (exclusive)
     * @return PCM mono 16 kHz float32, ou `null` si le fichier ne contient
     *   aucune piste audio lisible. Jamais d'exception a l'appelant : un audio
     *   illisible doit degrader la fonction, pas faire tomber la session.
     */
    fun decoderPlage(chemin: String, debutMs: Long, finMs: Long): FloatArray? {
        if (finMs <= debutMs) return FloatArray(0)
        var extracteur: MediaExtractor? = null
        var codec: MediaCodec? = null
        try {
            val ex = MediaExtractor().also { extracteur = it }
            ex.setDataSource(chemin)
            var piste = -1
            var format: MediaFormat? = null
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    piste = i; format = f; break
                }
            }
            if (piste < 0 || format == null) {
                DiagnosticLog.log(TAG, "aucune piste audio dans $chemin")
                return null
            }
            ex.selectTrack(piste)
            // SEEK_TO_PREVIOUS_SYNC : on se place AVANT le debut demande, jamais
            // apres -- une trame perdue au debut couperait le premier mot, et
            // c'est precisement ce mot-la qu'on cherche a localiser. Le
            // surplus decode en tete est retire plus bas, a l'echantillon.
            ex.seekTo(debutMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val debutReelUs = ex.sampleTime.coerceAtLeast(0)

            val srcHz = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val canaux = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val c = MediaCodec.createDecoderByType(mime).also { codec = it }
            c.configure(format, null, null, 0)
            c.start()

            // Accumule en mono a la frequence SOURCE ; le reechantillonnage se
            // fait une seule fois, a la fin, sur le signal complet -- le faire
            // par paquet ferait deriver la phase a chaque frontiere de buffer.
            val mono = ArrayList<Float>(((finMs - debutMs) * srcHz / 1000).toInt().coerceAtLeast(1024))
            val info = MediaCodec.BufferInfo()
            var finEntree = false
            var finSortie = false
            val finUs = finMs * 1000

            while (!finSortie) {
                if (!finEntree) {
                    val iIn = c.dequeueInputBuffer(10_000)
                    if (iIn >= 0) {
                        val buf = c.getInputBuffer(iIn)!!
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0 || ex.sampleTime > finUs) {
                            c.queueInputBuffer(iIn, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            finEntree = true
                        } else {
                            c.queueInputBuffer(iIn, 0, n, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val iOut = c.dequeueOutputBuffer(info, 10_000)
                if (iOut >= 0) {
                    if (info.size > 0) {
                        val buf = c.getOutputBuffer(iOut)!!
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        ajouterMono(buf, canaux, mono)
                    }
                    c.releaseOutputBuffer(iOut, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        finSortie = true
                    }
                } else if (iOut == MediaCodec.INFO_TRY_AGAIN_LATER && finEntree) {
                    // Le decodeur n'a plus rien a rendre : on ne boucle pas
                    // indefiniment sur un flux tronque.
                    if (mono.isNotEmpty()) finSortie = true
                }
            }

            // Retire ce qui a ete decode AVANT la plage demandee (le seek nous a
            // places sur la trame de synchro precedente).
            val decalageMs = debutMs - debutReelUs / 1000
            val aRetirer = ((decalageMs * srcHz) / 1000).toInt().coerceAtLeast(0)
            val utile = if (aRetirer >= mono.size) FloatArray(0)
                        else FloatArray(mono.size - aRetirer) { mono[it + aRetirer] }
            return reechantillonner(utile, srcHz, CIBLE_HZ)
        } catch (e: Exception) {
            DiagnosticLog.log(TAG, "decodage ECHOUE ($chemin, ${debutMs}..${finMs}ms) : ${e.message}")
            return null
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { extracteur?.release() } catch (_: Exception) {}
        }
    }

    /** PCM 16-bit entrelace -> mono float32, en moyennant les canaux. */
    private fun ajouterMono(buf: ByteBuffer, canaux: Int, out: ArrayList<Float>) {
        val sb = buf.order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val n = sb.remaining()
        if (canaux <= 1) {
            for (i in 0 until n) out.add(sb.get(i) / 32768f)
            return
        }
        var i = 0
        while (i + canaux <= n) {
            var s = 0f
            for (k in 0 until canaux) s += sb.get(i + k) / 32768f
            out.add(s / canaux)
            i += canaux
        }
    }

    /** Interpolation lineaire -- cf. l'avertissement en tete de fichier. */
    private fun reechantillonner(src: FloatArray, deHz: Int, versHz: Int): FloatArray {
        if (src.isEmpty() || deHz == versHz) return src
        val n = ((src.size.toLong() * versHz) / deHz).toInt()
        if (n <= 0) return FloatArray(0)
        val out = FloatArray(n)
        val pas = deHz.toDouble() / versHz
        for (i in 0 until n) {
            val x = i * pas
            val j = x.toInt()
            val f = (x - j).toFloat()
            val a = src[j]
            val b = if (j + 1 < src.size) src[j + 1] else a
            out[i] = a + (b - a) * f
        }
        return out
    }

    private const val TAG = "DecodeurAudio"
}
