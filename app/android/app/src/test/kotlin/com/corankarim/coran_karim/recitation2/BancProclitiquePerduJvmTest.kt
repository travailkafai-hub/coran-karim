package com.corankarim.coran_karim.recitation2

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import com.corankarim.coran_karim.fastconformer.MelSpectrogram
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import org.json.JSONArray
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * LE MODELE EMET-IL VRAIMENT RIEN, OU EST-CE LE GLOUTON QUI JETTE ?
 *
 * Constat du 15/09 : les mots lus en suffixe perdent tous un PROCLITIQUE
 * (`وَ` 14 fois, `فَ` 10, `بِ` 6 -- 72 cas sur des mots corrects contre 15 sur
 * de vraies fautes). Etendre les bornes vers la gauche n'a rien recupere : les
 * frames y sont blanches. Restent deux explications, et elles n'appellent pas
 * du tout le meme correctif :
 *
 *   (a) le modele n'a AUCUNE masse sur ce token -> il faudra reentrainer ;
 *   (b) il en a, mais l'argmax par frame la jette -> un beam search suffirait.
 *
 * Ce banc tranche en lisant les logprobs bruts juste AVANT le mot ampute et en
 * regardant le RANG du token manquant. On ne decode rien, on ne juge rien : on
 * observe ce que le modele a reellement produit.
 */
class BancProclitiquePerduJvmTest {

    private fun racine(): File {
        var d = File(System.getProperty("user.dir")).absoluteFile
        while (!File(d, "benchmark/campagne_paliers_20260915").exists())
            d = requireNotNull(d.parentFile)
        return d
    }

    private fun pcm(f: File): FloatArray {
        val b = ByteBuffer.wrap(f.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
        var p = 12
        while (p + 8 <= b.limit()) {
            val id = b.getInt(p); val n = b.getInt(p + 4)
            if (id == 0x61746164) return FloatArray(n / 2) { b.getShort(p + 8 + 2 * it) / 32768f }
            p += 8 + n + (n and 1)
        }
        error("WAV PCM absent")
    }

    @Test
    fun `le proclitique perdu a-t-il de la masse dans les logprobs`() {
        assumeTrue("Banc audio explicite : -DasrBanc=true", System.getProperty("asrBanc") == "true")
        val root = racine()
        val pack = File(root, "app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal")
        val a = JSONArray(File(pack, "vocab.json").readText())
        val pieces = (0 until a.length()).map(a::getString)
        val blank = pieces.size

        // Cas releves par l'analyse : (cas, mot ampute, debut/fin du mot dans le
        // montage, debut de la fenetre, texte du proclitique perdu).
        data class Cas(val id: String, val attendu: String, val lu: String,
                       val debut: Int, val fenetreDebut: Int, val proclitique: String)
        val cas = listOf(
            Cas("T802", "فَهُمْ", "هُمْ", 1104640, 1056000, "ف"),
            Cas("T802", "وَخَشِىَ", "خَشِىَ", 1442560, 1413120, "و"),
            Cas("T804", "وَقُلْنَا", "قُلْنَا", 2004480, 1978880, "و"),
            Cas("T801", "ثَجَّاجًا", "جَّاجًا", 1085440, 1067520, "ث"),
        )

        val env = OrtEnvironment.getEnvironment()
        val opts = OrtSession.SessionOptions().also { it.setIntraOpNumThreads(4) }
        var avecMasse = 0
        var muet = 0
        env.createSession(File(pack, "model.onnx").path, opts).use { session ->
            for (c in cas) {
                val wav = File(root, "benchmark/campagne_paliers_20260915/wav/${c.id}.wav")
                if (!wav.exists()) { println("WAV absent : ${c.id}"); continue }
                val tout = pcm(wav)
                val fenDebut = c.fenetreDebut
                val debut = c.debut
                // Fenetre telle que la chaine l'a vue, bornee a l'audio.
                val fin = minOf(tout.size, fenDebut + 16000 * 8)
                val seg = tout.copyOfRange(fenDebut.coerceAtMost(tout.size), fin)
                val mel = MelSpectrogram.compute(seg)
                val t = mel[0].size
                val logp: Array<FloatArray>
                OnnxTensor.createTensor(env, FloatBuffer.wrap(FloatArray(80 * t) { mel[it / t][it % t] }),
                    longArrayOf(1, 80, t.toLong())).use { x ->
                    OnnxTensor.createTensor(env, LongBuffer.wrap(longArrayOf(t.toLong())), longArrayOf(1)).use { len ->
                        session.run(mapOf("audio_signal" to x, "length" to len)).use { r ->
                            @Suppress("UNCHECKED_CAST")
                            logp = (r.get("logprobs").get().value as Array<Array<FloatArray>>)[0]
                        }
                    }
                }
                // Frame du debut du mot, dans le repere de CETTE fenetre.
                val fDebut = ((debut - fenDebut) / Horloge.ECH_PAR_FRAME).coerceIn(0, logp.size - 1)
                // Le proclitique, s'il a ete prononce, est AVANT le mot : on
                // regarde les 15 frames qui precedent (1,2 s, l'ordre du retard
                // d'emission mesure).
                val de = (fDebut - 15).coerceAtLeast(0)
                val lettre = c.proclitique
                val ids = pieces.indices.filter { pieces[it].contains(lettre) }
                var meilleurRang = Int.MAX_VALUE
                var meilleurLp = Float.NEGATIVE_INFINITY
                for (f in de..fDebut) {
                    val ordre = logp[f].indices.sortedByDescending { logp[f][it] }
                    val r = ordre.indexOfFirst { it in ids }
                    if (r >= 0 && r < meilleurRang) { meilleurRang = r; meilleurLp = logp[f][ordre[r]] }
                }
                val argmaxBlanc = (de..fDebut).count {
                    logp[it].indices.maxByOrNull { k -> logp[it][k] } == blank
                }
                println("${c.id} ${c.attendu} lu ${c.lu} : proclitique '$lettre' " +
                    "meilleur rang=$meilleurRang logprob=%.3f".format(meilleurLp) +
                    "  frames blanches avant le mot=$argmaxBlanc/${fDebut - de + 1}")
                if (meilleurRang in 1..4) avecMasse++ else if (meilleurRang > 4) muet++
            }
        }
        opts.close()
        println()
        println("proclitique dans le TOP 5 sans etre choisi (le glouton le jette) : $avecMasse")
        println("proclitique hors du top 5 (le modele est muet dessus)            : $muet")
        assertTrue("aucun cas examine", avecMasse + muet > 0)
    }
}
