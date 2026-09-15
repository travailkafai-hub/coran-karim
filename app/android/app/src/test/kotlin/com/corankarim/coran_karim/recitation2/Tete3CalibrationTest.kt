package com.corankarim.coran_karim.recitation2

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class Tete3CalibrationTest {
    private fun poids(seuils: String? = null): String {
        val json = JSONObject("""
            {"normalisation":{"moyenne":[0.0],"ecart_type":[1.0]},
             "couches":[{"poids":[[1.0]],"biais":[0.0]},
                        {"poids":[[1.0]],"biais":[0.0]}]}
        """)
        if (seuils != null) json.put("seuils_mesures", JSONObject(seuils))
        return json.toString()
    }

    @Test fun `a positive uncalibrated logit is not a measured deviation`() {
        val tete = Tete3.charger(poids())!!
        assertNull(tete.seuil2Pct)
        val mesure = tete.mesurer(floatArrayOf(3f))!!
        assertEquals(3f, mesure.logit)
        assertEquals("NON_CALIBREE", mesure.statut)
    }

    @Test fun `an explicit measured zero is valid and differs from absence`() {
        val tete = Tete3.charger(poids("""{"collateral_2pct":0.0}"""))!!
        assertEquals(0f, tete.seuil2Pct)
        assertEquals("DEVIATION_SUSPECTEE", tete.mesurer(floatArrayOf(1f))!!.statut)
        assertEquals("SOUS_SEUIL", tete.mesurer(floatArrayOf(0f))!!.statut)
    }

    @Test fun `the ten percent threshold cannot substitute for missing two percent calibration`() {
        val tete = Tete3.charger(poids("""{"collateral_10pct":-2.0}"""))!!
        assertEquals(-2f, tete.seuil10Pct)
        assertEquals("NON_CALIBREE", tete.mesurer(floatArrayOf(1f))!!.statut)
    }

    @Test fun `an invalid or null threshold cannot silently become zero`() {
        for (value in listOf("null", "\"invalide\"", "1e100")) {
            val tete = Tete3.charger(poids("""{"collateral_2pct":$value}"""))!!
            assertEquals("NON_CALIBREE", tete.mesurer(floatArrayOf(1f))!!.statut)
        }
    }

    @Test fun `nonfinite or wrong dimension input cannot be logged as correct`() {
        val tete = Tete3.charger(poids())!!
        assertNull(tete.mesurer(floatArrayOf(Float.NaN)))
        assertNull(tete.mesurer(floatArrayOf(Float.POSITIVE_INFINITY)))
        assertNull(tete.mesurer(floatArrayOf(1f, 2f)))
    }

    @Test fun `invalid model normalisation is rejected before inference`() {
        val json = JSONObject(poids())
        json.getJSONObject("normalisation").put("ecart_type", org.json.JSONArray("[0.0]"))
        assertNull(Tete3.charger(json.toString()))
    }
}
