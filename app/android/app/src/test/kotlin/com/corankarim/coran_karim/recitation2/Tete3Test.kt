package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Le risque que ces tests couvrent n'est PAS « est-ce que ca compile » : c'est
 * la PARITE avec le Python qui a entraine la tete.
 *
 * Une divergence de chargement ou d'arithmetique ne leve aucune erreur -- elle
 * rend simplement les poids denues de sens, et une detection mesuree a 31 %
 * redevient du hasard. Le projet a deja paye deux fois le fait de reimplementer
 * une logique dans deux langages et de croire le resultat.
 *
 * D'ou [logit_reproduit_le_python] : un vecteur genere par une formule ENTIERE
 * (donc identique au bit pres des deux cotes, contrairement a un sin() ou a un
 * generateur pseudo-aleatoire) est passe dans les VRAIS poids, et compare a la
 * valeur calculee par NumPy.
 */
class Tete3Test {

    /** Le fichier reel, cherche depuis le repertoire de travail des tests. */
    private fun fichierReel(): File? {
        var d: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (d != null) {
            val f = File(d, "benchmark/models/tete3-sur-modele-app/tete3.json")
            if (f.exists()) return f
            d = d.parentFile
        }
        return null
    }

    /**
     * Vecteur d'entree deterministe. Formule ENTIERE volontairement : elle donne
     * exactement les memes flottants en Python et en Kotlin, ce qu'aucune
     * fonction transcendante ne garantit.
     */
    private fun vecteurReference(n: Int) =
        FloatArray(n) { (((it * 37) % 101) - 50) / 25.0f }

    @Test
    fun logit_reproduit_le_python() {
        val f = fichierReel()
        if (f == null) {
            // Le modele n'est pas sur cette machine : ne pas faire echouer la
            // suite pour autant, mais ne pas faire croire non plus que la
            // parite a ete verifiee.
            println("tete3.json absent : parite NON verifiee sur cette machine")
            return
        }
        val t = Tete3.charger(f.readText())
        assertNotNull("tete3.json present mais illisible", t)
        t!!
        assertEquals(524, t.tailleEntree)

        // Valeur calculee par NumPy sur les MEMES poids et le MEME vecteur
        // (cf. la commande qui l'a produite dans le message de commit).
        val attendu = -65.610130f
        val obtenu = t.logit(vecteurReference(t.tailleEntree))
        assertEquals(
            "PARITE ROMPUE avec le Python qui a entraine la tete",
            attendu.toDouble(), obtenu.toDouble(), 0.02,
        )
        assertTrue(t.verifierParite(vecteurReference(t.tailleEntree), obtenu))
        assertEquals(1.567111f.toDouble(), t.seuil2Pct.toDouble(), 1e-5)
    }

    /** Poids connus a la main : verifie le ReLU et l'ordre des couches. */
    @Test
    fun relu_et_ordre_des_couches() {
        //  x = [1, 3] ; mu = [1, 1] ; sd = [1, 2]  ->  xn = [0, 1]
        //  unite 0 :  1*0 + 0*1 + 0   =  0   -> ReLU 0
        //  unite 1 :  0*0 + 2*1 - 5   = -3   -> ReLU 0   (doit etre COUPEE)
        //  unite 2 :  0*0 + 4*1 + 1   =  5   -> ReLU 5
        //  sortie  :  3*0 + 7*0 + 2*5 + 0,5  =  10,5
        val json = """
        {"normalisation":{"moyenne":[1.0,1.0],"ecart_type":[1.0,2.0]},
         "couches":[{"poids":[[1.0,0.0],[0.0,2.0],[0.0,4.0]],"biais":[0.0,-5.0,1.0]},
                    {"poids":[[3.0,7.0,2.0]],"biais":[0.5]}],
         "seuils_mesures":{"collateral_2pct":1.0,"collateral_10pct":-2.0}}
        """
        val t = Tete3.charger(json)
        assertNotNull(t)
        assertEquals(10.5, t!!.logit(floatArrayOf(1f, 3f)).toDouble(), 1e-5)
        assertEquals(2, t.tailleEntree)
    }

    /** Un fichier absent ou casse ne doit pas jeter : la chaine se rabat sur la
     *  regle ecrite a la main. Un plantage ici ferait perdre la RECITATION
     *  entiere pour un fichier annexe. */
    @Test
    fun json_casse_rend_null_sans_jeter() {
        assertNull(Tete3.charger(""))
        assertNull(Tete3.charger("{}"))
        assertNull(Tete3.charger("""{"normalisation":{"moyenne":[1.0]}}"""))
        assertNull(Tete3.charger("pas du json du tout"))
    }

    /** Un vecteur de la mauvaise taille est une erreur de PROGRAMMATION (les
     *  caracteristiques ne correspondent plus), pas un alea d'execution : il
     *  doit se voir immediatement et non produire un score silencieusement faux. */
    @Test
    fun taille_incoherente_est_signalee() {
        val t = Tete3.charger("""
        {"normalisation":{"moyenne":[0.0,0.0],"ecart_type":[1.0,1.0]},
         "couches":[{"poids":[[1.0,1.0]],"biais":[0.0]},{"poids":[[1.0]],"biais":[0.0]}]}
        """)
        assertNotNull(t)
        var vu = false
        try {
            t!!.logit(floatArrayOf(1f, 2f, 3f))
        } catch (e: IllegalArgumentException) {
            vu = true
        }
        assertTrue("une entree de taille incoherente doit etre signalee", vu)
    }
}
