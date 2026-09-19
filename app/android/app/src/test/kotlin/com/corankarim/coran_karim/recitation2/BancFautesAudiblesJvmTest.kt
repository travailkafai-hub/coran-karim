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
import java.text.Normalizer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * LES FAUTES DU BANC SONT-ELLES SEULEMENT AUDIBLES ?
 *
 * ── POURQUOI CE BANC EXISTE ────────────────────────────────────────────────
 *
 * Le 15/09 au soir, huit reglages de la chaine ont ete mesures et aucun n'a
 * bouge les taux (detection 66-67 %, faux ~9 %). La conclusion « le plafond est
 * acoustique » a ete tiree SANS jamais confronter l'audio au modele seul --
 * exactement ce que la regle n°1 du projet interdit (`verifier_erreurs.py` :
 * « un mot que le modele lit correctement sur l'audio brut est un faux positif
 * de la chaine, pas une faute de recitation »).
 *
 * Ici on retire TOUTE la chaine : pas de fenetres, pas d'alignement force, pas
 * de vote, pas de decision. On donne au modele la zone reellement editee par le
 * generateur, avec un court contexte, et on lit son decodage LIBRE.
 *
 *   - il lit le mot ATTENDU alors que l'audio est monte -> la faute est
 *     INAUDIBLE pour ce modele ; aucune chaine ne pourra la detecter, et le
 *     plafond est bien acoustique ;
 *   - il lit AUTRE CHOSE -> l'information existe des la sortie du modele, et
 *     c'est la chaine qui la perd. Le plafond n'est pas acoustique.
 *
 * Tant que ce partage n'est pas fait, tout diagnostic sur « ou ca rate » est
 * une supposition.
 */
class BancFautesAudiblesJvmTest {

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

    private fun cle(t: String) = Normalizer.normalize(t.replace("ـ", "").trim(), Normalizer.Form.NFC)

    @Test
    fun `le modele seul entend-il les fautes que la chaine a ratees`() {
        assumeTrue("Banc audio explicite : -DasrBanc=true", System.getProperty("asrBanc") == "true")
        val root = racine()
        val pack = File(root, "app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal")
        val a = JSONArray(File(pack, "vocab.json").readText())
        val pieces = (0 until a.length()).map(a::getString)
        val blank = pieces.size

        val man = JSONObject(File(root, "benchmark/campagne_paliers_20260915/manifest.json").readText())
        val cases = man.getJSONArray("cases")
        val resultats = JSONObject(
            File(root, "benchmark/replay_chaine_jvm_20260915/resultats.json").readText()
                .let { "{\"l\":$it}" })
            .getJSONArray("l")
        // statut rendu par la chaine, config vote_t3_bpe
        val statutPar = HashMap<String, JSONObject>()
        for (i in 0 until resultats.length()) {
            val r = resultats.getJSONObject(i)
            if (r.getString("configuration") == "vote_t3_bpe")
                statutPar[r.getString("cas")] = r.getJSONObject("statuts")
        }

        val env = OrtEnvironment.getEnvironment()
        val opts = OrtSession.SessionOptions().also { it.setIntraOpNumThreads(4) }
        var inaudibles = 0; var audibles = 0; var examinees = 0
        val exemples = StringBuilder()

        env.createSession(File(pack, "model.onnx").path, opts).use { session ->
            fun lire(seg: FloatArray): String {
                val mel = MelSpectrogram.compute(seg)
                val t = mel[0].size
                OnnxTensor.createTensor(env, FloatBuffer.wrap(FloatArray(80 * t) { mel[it / t][it % t] }),
                    longArrayOf(1, 80, t.toLong())).use { x ->
                    OnnxTensor.createTensor(env, LongBuffer.wrap(longArrayOf(t.toLong())), longArrayOf(1)).use { len ->
                        session.run(mapOf("audio_signal" to x, "length" to len)).use { r ->
                            @Suppress("UNCHECKED_CAST")
                            val lp = (r.get("logprobs").get().value as Array<Array<FloatArray>>)[0]
                            return Decodage.texte(lp, pieces, blank, 0, lp.size - 1)
                        }
                    }
                }
            }
            for (ci in 0 until cases.length()) {
                val c = cases.getJSONObject(ci)
                val id = c.getString("case_id")
                val statuts = statutPar[id] ?: continue
                val wav = File(root, "benchmark/campagne_paliers_20260915/wav/$id.wav")
                if (!wav.exists()) continue
                val audio = pcm(wav)
                val mots = c.getJSONArray("expected_words")
                val ops = c.getJSONArray("operations")
                for (oi in 0 until ops.length()) {
                    val o = ops.getJSONObject(oi)
                    val idx = o.getJSONArray("affected_word_indices")
                    val i = idx.getInt(0)
                    val s = statuts.optString(i.toString(), "inconnu")
                    // on n'examine QUE ce que la chaine a laisse passer
                    if (s == "inconnu" || s !in listOf("definitif:VERT", "provisoire:VERT")) continue
                    val deb = (o.getDouble("output_edit_start_ms") * 16).toInt()
                    val n = o.optInt("replacement_samples", 0)
                    // contexte : 0,4 s de part et d'autre, le mot n'est pas au bord
                    val de = (deb - 6400).coerceAtLeast(0)
                    val fin = (deb + n + 6400).coerceAtMost(audio.size)
                    if (fin - de < 4800) continue
                    val lu = cle(lire(audio.copyOfRange(de, fin)))
                    val attendu = cle(mots.getString(i))
                    examinees++
                    val contient = lu.contains(attendu)
                    if (contient) inaudibles++ else audibles++
                    if (exemples.lines().size < 12)
                        exemples.append("  %-5s/%-4d %-16s %-22s lu par le modele seul : %s%n"
                            .format(id, i, o.getString("family"), attendu,
                                if (lu.length > 40) lu.substring(0, 40) + "…" else lu))
                }
            }
        }
        opts.close()
        println("=== FAUTES QUE LA CHAINE A DECLAREES VERTES, relues par le MODELE SEUL ===")
        println("  examinees : $examinees")
        println("  le modele lit QUAND MEME le mot attendu -> faute INAUDIBLE  : $inaudibles")
        println("  le modele lit autre chose -> l'info EXISTE, la chaine la perd : $audibles")
        println()
        print(exemples)
        assertTrue("aucune faute examinee", examinees > 0)
    }
}
