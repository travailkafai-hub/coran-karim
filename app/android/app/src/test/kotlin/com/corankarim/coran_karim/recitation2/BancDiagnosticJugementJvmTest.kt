package com.corankarim.coran_karim.recitation2

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import com.corankarim.coran_karim.fastconformer.CtcTokenizer
import com.corankarim.coran_karim.fastconformer.MelSpectrogram
import com.corankarim.coran_karim.fastconformer.loadWordTokenLookup
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Banc d'investigation explicite, infere les MEMES fenetres archivees avec
 * le mel Kotlin et le pack de l'app. Aucun encodeur Python ni faux front.
 * Ne simule pas l'ordonnancement Android : il compare les entrees du jugement. */
class BancDiagnosticJugementJvmTest {
    private fun racine(): File {
        var d = File(System.getProperty("user.dir")).absoluteFile
        while (!File(d, "benchmark/campagne_paliers_20260915").exists()) d = requireNotNull(d.parentFile)
        return d
    }

    private fun pcm(f: File): FloatArray {
        val b = ByteBuffer.wrap(f.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
        require(b.getInt(0) == 0x46464952 && b.getInt(8) == 0x45564157)
        var p = 12
        while (p + 8 <= b.limit()) {
            val id = b.getInt(p); val n = b.getInt(p + 4)
            if (id == 0x20746d66) {
                require(b.getShort(p + 8).toInt() == 1 && b.getShort(p + 10).toInt() == 1)
                require(b.getInt(p + 12) == 16000 && b.getShort(p + 22).toInt() == 16)
            }
            if (id == 0x61746164) return FloatArray(n / 2) { b.getShort(p + 8 + 2 * it) / 32768f }
            p += 8 + n + (n and 1)
        }
        error("WAV PCM absent")
    }

    @Test fun `diagnostiquer faux rouges et erreurs connues sur les vrais tenseurs`() {
        assumeTrue("Banc audio explicite : -DasrBanc=true",System.getProperty("asrBanc") == "true")
        val root = racine()
        val pack = File(root, "app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal")
        val vocab = JSONArray(File(pack, "vocab.json").readText()).let { a ->
            (0 until a.length()).map { a.getString(it) }
        }
        val tk = CtcTokenizer(vocab, loadWordTokenLookup(File(pack, "word_tokens.json").path))
        val oracle = JSONObject(File(root,"benchmark/oracle_tokenizer_tete3_jvm.json").readText())
        fun sp(texte: String): IntArray = oracle.getJSONArray(texte).let { a ->
            IntArray(a.length()) { a.getInt(it) } }
        val tete = requireNotNull(Tete3.charger(File(root,
            "benchmark/tetes_candidates/hafs_particules_20260915/tete3_hafs_particules.json").readText()))
        val env = OrtEnvironment.getEnvironment()
        val options = OrtSession.SessionOptions().also { it.setIntraOpNumThreads(4) }
        val sortie = JSONArray()
        val selection = mapOf(
            "campagne_paliers_20260915" to ("T805" to setOf(68,94,131,155,158,180,202,211,216)),
            "vote_T023_36_3_decision_occurrence_20260915" to ("T023" to setOf(4)),
            "vote_T005_115_decision_20260915" to ("T005" to setOf(27)))
        env.createSession(File(pack, "model.onnx").path, options).use { session ->
            for ((dossier, cible) in selection) {
                val dir = File(root, "benchmark/$dossier")
                val cases = JSONObject(File(dir, "manifest.json").readText()).getJSONArray("cases")
                val cas = (0 until cases.length()).map { cases.getJSONObject(it) }
                    .first { it.getString("case_id") == cible.first }
                val audio = pcm(File(cas.getString("wav")))
                val execution = File(dir, "executions.jsonl").readLines().filter { it.isNotBlank() }
                    .map(::JSONObject).first { it.getString("case_id") == cible.first }
                val log = File(execution.getString("log"))
                val os = log.readLines(Charsets.UTF_8).filter { "[vote-observation] " in it }
                    .map { JSONObject(it.substringAfter("[vote-observation] ")) }
                    .filter { it.getInt("mot") in cible.second && !it.isNull("poids") &&
                        it.getBoolean("interieur") && it.isNull("exclusion") }
                for ((intervalle, observations) in os.groupBy {
                    it.getInt("fenetre_debut") to it.getInt("fenetre_fin") }) {
                    val mel = MelSpectrogram.compute(audio.copyOfRange(intervalle.first, intervalle.second))
                    val t = mel[0].size
                    OnnxTensor.createTensor(env, FloatBuffer.wrap(FloatArray(80*t) { mel[it/t][it%t] }),
                        longArrayOf(1,80,t.toLong())).use { x ->
                        OnnxTensor.createTensor(env, LongBuffer.wrap(longArrayOf(t.toLong())), longArrayOf(1)).use { len ->
                            session.run(mapOf("audio_signal" to x, "length" to len)).use { result ->
                                @Suppress("UNCHECKED_CAST")
                                val lp = (result.get("logprobs").get().value as Array<Array<FloatArray>>)[0]
                                @Suppress("UNCHECKED_CAST")
                                val etatBrut = (result.get("encoder_state").get().value as Array<Array<FloatArray>>)[0]
                                val etat = if (etatBrut.size == 512) Array(lp.size) { f ->
                                    FloatArray(512) { k -> etatBrut[k][f] } } else etatBrut
                                for (o in observations) {
                                    val index = o.getInt("mot")
                                    val attendu = cas.getJSONArray("expected_words").getString(index)
                                    val f0 = (o.getInt("debut") - intervalle.first)/1280
                                    val f1 = (o.getInt("fin") - intervalle.first)/1280 + 1
                                    if (f0 < 0 || f1 > lp.size || f1 <= f0) continue
                                    val tranche = lp.copyOfRange(f0,f1)
                                    val ids = tk.tokenizeVariantQuiet(attendu)
                                    val variants = ConfusionsRecitation.variantes(attendu).map(tk::tokenizeVariantQuiet)
                                    val traits = Tete3Traits.caracteristiques(tranche,ids,variants)
                                    val vec = Tete3Traits.etatMoyenEtEcartType(etat,f0,f1)!!
                                    val score = traits?.let { tete.mesurer(vec+it)?.logit }
                                    val traitsSp = Tete3Traits.caracteristiques(tranche,sp(attendu),
                                        ConfusionsRecitation.variantes(attendu).map(::sp))
                                    val scoreSp = traitsSp?.let { tete.mesurer(vec+it)?.logit }
                                    val entendu = Decodage.texte(tranche,vocab,vocab.size)
                                    val pistes = JSONArray()
                                    for (texte in Orthographe.variantes(attendu).distinct()) {
                                        val toks = tk.tokenizeVariantQuiet(texte)
                                        val vars = ConfusionsRecitation.variantes(texte).map(tk::tokenizeVariantQuiet)
                                        val tr = Tete3Traits.caracteristiques(tranche,toks,vars)
                                        pistes.put(JSONObject().put("texte",texte)
                                            .put("tokens",JSONArray(toks.toList()))
                                            .put("traits",if(tr==null) JSONObject.NULL else JSONArray(tr.toList()))
                                            .put("logit",tr?.let { tete.mesurer(vec+it)?.logit } ?: JSONObject.NULL))
                                    }
                                    val j = JSONObject().put("cas",cible.first).put("mot",index)
                                        .put("fenetre",o.getLong("fenetre")).put("attendu",attendu)
                                        .put("entendu_archive",o.getString("entendu")).put("entendu_jvm",entendu)
                                        .put("logit_archive",o.opt("t3_jugement_logit") ?: JSONObject.NULL)
                                        .put("logit_jvm",score ?: JSONObject.NULL).put("graphies",pistes)
                                        .put("tokens_app",JSONArray(ids.toList())).put("tokens_sp",JSONArray(sp(attendu).toList()))
                                        .put("logit_sp",scoreSp ?: JSONObject.NULL)
                                        .put("traits_app",traits?.let { JSONArray(it.toList()) } ?: JSONObject.NULL)
                                        .put("traits_sp",traitsSp?.let { JSONArray(it.toList()) } ?: JSONObject.NULL)
                                    sortie.put(j)
                                    println("${cible.first}/$index f=${o.getLong("fenetre")} " +
                                        "$attendu -> $entendu logit=$score sp=$scoreSp archive=${o.opt("t3_jugement_logit")}")
                                }
                            }
                        }
                    }
                }
            }
        }
        options.close()
        File(root,"benchmark/diagnostic_jugement_jvm_20260915.json").writeText(sortie.toString(2),Charsets.UTF_8)
        assertTrue("Les vrais tenseurs doivent avoir ete exploites",sortie.length() >= 20)
    }
}
