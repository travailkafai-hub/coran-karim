package com.corankarim.coran_karim.recitation2

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * PARITE PYTHON / KOTLIN DES CARACTERISTIQUES DE LA TETE 3.
 *
 * Ce test est la seule chose qui autorise la tete 3 a trancher un verdict. Sans
 * lui, le Kotlin calcule 1036 nombres, la tete rend un logit, et RIEN ne dit
 * s'il veut dire quelque chose : une divergence de calcul ne leve aucune erreur,
 * elle rend simplement les poids denues de sens -- et les 47 % de detection
 * mesures hors device redeviennent du hasard.
 *
 * Le fichier de reference est produit par `benchmark/reference_parite_tete3.py`
 * a partir d'un VRAI audio et d'un VRAI modele : logprobs, etat d'encodeur,
 * tokens, variantes, les 12 caracteristiques attendues et le logit final. Ses
 * flottants sont arrondis AVANT que le Python ne calcule les valeurs attendues,
 * pour que le contrat soit clos sur lui-meme -- sinon un ecart d'arrondi se
 * confondrait avec un vrai defaut de parite.
 *
 * ⚠️ NE PAS REGENERER LA REFERENCE POUR FAIRE PASSER LE TEST. Une reference
 * qu'on regenere apres chaque modification ne teste plus rien : elle enregistre
 * le bug au lieu de le signaler.
 */
class Tete3TraitsTest {

    private fun remonter(relatif: String): File? {
        var d: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (d != null) {
            val f = File(d, relatif)
            if (f.exists()) return f
            d = d.parentFile
        }
        return null
    }

    private fun matrice(a: JSONArray) = Array(a.length()) { i ->
        val l = a.getJSONArray(i)
        FloatArray(l.length()) { l.getDouble(it).toFloat() }
    }

    private fun entiers(a: JSONArray) = IntArray(a.length()) { a.getInt(it) }

    @Test
    fun caracteristiques_reproduisent_le_python() {
        val f = remonter("benchmark/reference_tete3.json")
        if (f == null) {
            println("reference_tete3.json absent : PARITE NON VERIFIEE")
            return
        }
        val ref = JSONObject(f.readText())
        val cas = ref.getJSONArray("cas")
        assertTrue("la reference doit porter plusieurs mots", cas.length() >= 2)

        for (i in 0 until cas.length()) {
            val c = cas.getJSONObject(i)
            val nom = "${c.getString("mot")} (mot ${c.getInt("mot_index")})"
            val lp = matrice(c.getJSONArray("logprobs"))
            val tokens = entiers(c.getJSONArray("tokens"))
            val vars = c.getJSONArray("variantes")
            val variantes = (0 until vars.length()).map { entiers(vars.getJSONArray(it)) }

            val obtenu = Tete3Traits.caracteristiques(lp, tokens, variantes)
            assertNotNull("$nom : caracteristiques nulles cote Kotlin", obtenu)
            obtenu!!
            assertEquals(Tete3Traits.N_TRAITS, obtenu.size)

            val attendu = c.getJSONObject("attendu")
            for ((k, n) in Tete3Traits.NOMS.withIndex()) {
                assertEquals(
                    "PARITE ROMPUE sur $n pour $nom",
                    attendu.getDouble(n), obtenu[k].toDouble(), 1e-3,
                )
            }
        }
    }

    /**
     * La parite des caracteristiques ne suffit pas : c'est le vecteur COMPLET
     * -- etat d'encodeur inclus, dans le bon ORDRE -- qui entre dans la tete.
     * Une moyenne et un ecart-type intervertis passeraient le test precedent.
     */
    @Test
    fun vecteur_complet_reproduit_le_logit_python() {
        val fr = remonter("benchmark/reference_tete3.json")
        val ft = remonter("benchmark/models/tete3-v2-2026-08-05/tete3.json")
        if (fr == null || ft == null) {
            println("reference ou tete3.json absent : PARITE NON VERIFIEE")
            return
        }
        val tete = Tete3.charger(ft.readText())
        assertNotNull("tete3.json illisible", tete)
        tete!!

        val ref = JSONObject(fr.readText())
        val cas = ref.getJSONArray("cas")
        for (i in 0 until cas.length()) {
            val c = cas.getJSONObject(i)
            if (!c.has("logit_attendu")) continue
            val nom = "${c.getString("mot")} (mot ${c.getInt("mot_index")})"
            val lp = matrice(c.getJSONArray("logprobs"))
            val etat = matrice(c.getJSONArray("etat"))
            val tokens = entiers(c.getJSONArray("tokens"))
            val vars = c.getJSONArray("variantes")
            val variantes = (0 until vars.length()).map { entiers(vars.getJSONArray(it)) }

            val traits = Tete3Traits.caracteristiques(lp, tokens, variantes)!!
            val etatVec = Tete3Traits.etatMoyenEtEcartType(etat, 0, etat.size)!!
            val vecteur = etatVec + traits

            assertEquals(
                "$nom : taille du vecteur",
                c.getInt("taille_vecteur"), vecteur.size,
            )
            assertEquals(
                "$nom : le vecteur n'a pas la taille attendue par la tete",
                tete.tailleEntree, vecteur.size,
            )
            // Tolerance plus large que sur les caracteristiques : le logit est
            // une somme de 1036 produits, chaque terme portant l'arrondi float.
            assertEquals(
                "PARITE ROMPUE sur le logit pour $nom",
                c.getDouble("logit_attendu"), tete.logit(vecteur).toDouble(), 5e-2,
            )
        }
    }

    /**
     * FORWARD ET VITERBI NE DOIVENT PAS DONNER LE MEME NOMBRE. Le code precedent
     * recopiait l'un dans l'autre faute de scoreur forward ; le test l'aurait
     * attrape. La somme de tous les chemins est >= le meilleur d'entre eux.
     */
    @Test
    fun forward_domine_viterbi() {
        val lp = arrayOf(
            floatArrayOf(-0.1f, -3.0f, -4.0f),
            floatArrayOf(-2.0f, -0.2f, -3.0f),
            floatArrayOf(-3.0f, -2.0f, -0.3f),
            floatArrayOf(-0.4f, -2.5f, -3.0f),
        )
        val ids = intArrayOf(0, 1)
        val lab = Tete3Traits.viterbiForce(lp, ids)
        assertNotNull(lab)
        var viterbi = 0.0
        for (t in lp.indices) viterbi += lp[t][lab!![t]].toDouble()
        val forward = Tete3Traits.scoreForce(lp, ids)
        assertTrue(
            "le forward ($forward) doit dominer le viterbi ($viterbi)",
            forward >= viterbi - 1e-9,
        )
        assertTrue("les deux ne doivent pas coincider ici", forward > viterbi + 1e-6)
    }

    /**
     * SENTINELLE : audio trop court pour la sequence. Le Python rend NEG et
     * l'appelant DOIT l'ecarter au lieu de la faire concourir -- c'est le
     * defaut corrige le 2026-08-05, ou la sentinelle divisee par le nombre de
     * frames passait le filtre et produisait un logit a 3,7e29.
     */
    @Test
    fun sequence_infaisable_rend_la_sentinelle() {
        val lp = arrayOf(floatArrayOf(-0.1f, -3.0f, -4.0f))
        assertEquals(Tete3Traits.NEG, Tete3Traits.scoreForce(lp, intArrayOf(0, 1)), 0.0)
        assertNull(Tete3Traits.viterbiForce(lp, intArrayOf(0, 1)))
    }

    /** Aucune variante scorable : abstention, jamais un vecteur par defaut --
     *  un zero entrerait dans la tete comme une observation. */
    @Test
    fun sans_variante_scorable_on_s_abstient() {
        val lp = arrayOf(
            floatArrayOf(-0.1f, -3.0f, -4.0f),
            floatArrayOf(-2.0f, -0.2f, -3.0f),
            floatArrayOf(-3.0f, -2.0f, -0.3f),
        )
        assertNull(Tete3Traits.caracteristiques(lp, intArrayOf(0), emptyList()))
        // Variante plus longue que l'audio : non scorable, donc ecartee.
        assertNull(
            Tete3Traits.caracteristiques(lp, intArrayOf(0), listOf(intArrayOf(0, 1, 0, 1)))
        )
    }

    /** Ecart-type de POPULATION (diviseur T), comme `np.std`. Un diviseur T-1
     *  donnerait 12 % d'ecart sur un mot de 5 frames et fausserait toute la
     *  normalisation sans que rien ne le signale. */
    @Test
    fun ecart_type_est_celui_de_population() {
        val etat = arrayOf(
            floatArrayOf(0f), floatArrayOf(2f), floatArrayOf(4f), floatArrayOf(6f),
        )
        val v = Tete3Traits.etatMoyenEtEcartType(etat, 0, 4)
        assertNotNull(v)
        assertEquals(2, v!!.size)
        assertEquals(3.0, v[0].toDouble(), 1e-6)          // moyenne
        assertEquals(2.236068, v[1].toDouble(), 1e-5)     // sqrt(20/4), pas sqrt(20/3)
    }

    /**
     * LE GENERATEUR DE CONFUSIONS, pas seulement le scoreur. `alt` et `alt2`
     * sont les deux meilleurs scores parmi les variantes : si le Kotlin n'en
     * genere pas exactement les memes que le Python, ces deux caracteristiques
     * sont fausses -- et rien ne le dirait, puisque le calcul, lui, aboutit.
     *
     * C'est le piege qu'avait `ConfusableVariants` : il substitue TOUTES les
     * occurrences la ou le Python n'en substitue qu'une, et compte sept harakat
     * la ou le Python en compte quatre.
     */
    @Test
    fun variantes_reproduisent_le_python() {
        val f = remonter("benchmark/reference_tete3.json")
        if (f == null) {
            println("reference_tete3.json absent : PARITE NON VERIFIEE")
            return
        }
        val cas = JSONObject(f.readText()).getJSONArray("cas")
        for (i in 0 until cas.length()) {
            val c = cas.getJSONObject(i)
            if (!c.has("variantes_texte")) continue
            val mot = c.getString("mot")
            val a = c.getJSONArray("variantes_texte")
            val attendu = (0 until a.length()).map { a.getString(it) }
            val obtenu = ConfusionsRecitation.variantes(mot)
            assertEquals(
                "PARITE ROMPUE sur les variantes de $mot",
                attendu, obtenu,
            )
        }
    }
}
