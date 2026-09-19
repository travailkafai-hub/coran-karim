package com.corankarim.coran_karim.recitation2

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class TokeniseurBpeTete3Test {
    private fun racine(): File {
        var d = File(System.getProperty("user.dir")).absoluteFile
        while (!File(d,"benchmark/exporter_tokenizers_tete3.py").isFile) d = requireNotNull(d.parentFile)
        return d
    }

    @Test fun `parite SentencePiece du lexique et de toutes les confusions Hafs et Warsh`() {
        assumeTrue("Oracle complet a generer : -DasrBanc=true",System.getProperty("asrBanc") == "true")
        val root = racine()
        val assets = File(root,"app/android/app/src/main/assets/tokenizers_tete3")
        for (riwaya in listOf("hafs","warsh")) {
            val j = JSONObject(File(assets,"$riwaya.json").readText())
            val a = j.getJSONArray("pieces")
            val tk = TokeniseurBpeTete3.charger(j.toString(),File(assets,"$riwaya.normalizer.bin").readBytes(),
                (0 until a.length()).map(a::getString))
            var n = 0
            File(root,"benchmark/parite_tokenizer_tete3_$riwaya.jsonl").forEachLine { ligne ->
                val r = JSONObject(ligne)
                val texte = r.getString("texte")
                assertEquals("normalisation $riwaya/$texte", r.getString("normalise"), tk.normaliser(texte))
                val ids = r.getJSONArray("ids")
                assertArrayEquals("tokens $riwaya/$texte", IntArray(ids.length()) { ids.getInt(it) }, tk.tokeniser(texte))
                n++
            }
            assertTrue(n > 10000)
            println("$riwaya : $n textes conformes au SentencePiece Python (normalisation + ids)")
        }
    }

    @Test fun `les references audio passent par les vrais tokeniseurs de la tete`() {
        val root = racine()
        val assets = File(root,"app/android/app/src/main/assets/tokenizers_tete3")
        for (riwaya in listOf("hafs","warsh")) {
            val j = JSONObject(File(assets,"$riwaya.json").readText())
            val a = j.getJSONArray("pieces")
            val tk = TokeniseurBpeTete3.charger(j.toString(),File(assets,"$riwaya.normalizer.bin").readBytes(),
                (0 until a.length()).map(a::getString))
            val cases = JSONObject(File(root,"benchmark/tunnel_pc_a/reponses/reference_tete3_$riwaya.json")
                .readText()).getJSONArray("cas")
            for (i in 0 until cases.length()) {
                val c = cases.getJSONObject(i)
                val mot = c.getString("mot")
                val ids = c.getJSONArray("tokens")
                assertArrayEquals("$riwaya/$mot", IntArray(ids.length()) { ids.getInt(it) },tk.tokeniser(mot))
                val vars = c.getJSONArray("variantes")
                val variantes = ConfusionsRecitation.variantes(mot).map(tk::tokeniser)
                assertEquals(vars.length(),variantes.size)
                for (k in variantes.indices) {
                    val v = vars.getJSONArray(k)
                    assertArrayEquals("$riwaya/$mot variante $k",IntArray(v.length()) { v.getInt(it) },variantes[k])
                }
            }
        }
    }
}
