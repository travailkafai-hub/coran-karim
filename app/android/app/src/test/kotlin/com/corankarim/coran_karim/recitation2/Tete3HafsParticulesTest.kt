package com.corankarim.coran_karim.recitation2

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest

/** Candidate du 15/09, jamais substituee a l'asset deploye par ce test.
 * Reference Python : benchmark/reference_parite_tete3_deployee.py.
 * Ne prouve ni calibration, ni rappel sur fautes audio, ni parite encodeur. */
class Tete3HafsParticulesTest {
    @Test fun `arithmetique de la candidate exacte et absence explicite de calibration`() {
        val relatif = "benchmark/tetes_candidates/hafs_particules_20260915/tete3_hafs_particules.json"
        var d: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var fichier: File? = null
        while (d != null) {
            File(d, relatif).takeIf { it.exists() }?.let { fichier = it }
            if (fichier != null) break
            d = d.parentFile
        }
        assertNotNull("Candidate absente : parite NON verifiee", fichier)
        val bytes = fichier!!.readBytes()
        val sha = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        assertEquals("7e708b20a9a13e53f14b0491c36396992bdb2b078c05208215d774837e03b66e", sha)
        val tete = Tete3.charger(bytes.toString(Charsets.UTF_8))
        assertNotNull(tete)
        tete!!
        assertEquals(1036, tete.tailleEntree)
        val x = FloatArray(1036) { (((it * 37) % 101) - 50) / 25.0f }
        assertEquals(37.389693, tete.logit(x).toDouble(), 1e-3)
        assertNull(tete.seuil2Pct)
        assertNull(tete.seuil10Pct)
        assertEquals("NON_CALIBREE", tete.mesurer(x)!!.statut)
    }
}
