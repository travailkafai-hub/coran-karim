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

    /** Le fichier REELLEMENT DEPLOYE (2026-08-23) -- forme a 1036 entrees
     *  (etat_encodeur_moyen_et_ecart_type[1024] + 12 scores), distincte de la
     *  forme a 524 de [fichierReel] (etat moyen SEUL[512] + 12). Les deux
     *  variantes coexistent dans le code (Tete3.tailleEntree s'adapte, cf.
     *  ChaineRecitation) -- chercher un chemin different evite que ce test
     *  et [logit_reproduit_le_python] ne se marchent dessus. */
    private fun fichierDeploye1036(): File? {
        var d: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (d != null) {
            val f = File(d, "modele_2geles_2026-08-22/tete3.json")
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

    /**
     * MEME PRINCIPE que [logit_reproduit_le_python], sur le fichier REELLEMENT
     * DEPLOYE aujourd'hui (2026-08-23) -- 1036 entrees, pas 524.
     *
     * Contexte : le graphe du projet portait un noeud [EN ATTENTE] bloquant
     * ("la tete 3 ne tranche aucun verdict, et sa parite n'a jamais ete
     * verifiee") faute de vecteur de reference pour cette forme -- l'ancien
     * test ne couvrait que la forme a 524 du 21 aout, absente de cette
     * machine. Valeur de reference calculee en Python/NumPy, poids et
     * normalisation copies OCTET POUR OCTET depuis
     * `modele_2geles_2026-08-22/tete3.json` (celui que l'app charge
     * reellement, cf. `FastConformerVerifier._kModelSubdir`), meme vecteur
     * deterministe que [vecteurReference] (memes flottants des deux cotes,
     * cf. la doc de tete de fichier).
     *
     * README de livraison (2026-08-22, PC A) : le `tete3.json` de CE JOUR-LA
     * etait mesure VALIDE sur ce modele -- `encoder_state`/`logprobs`/
     * `warsh_logprobs` identiques bit a bit (ecart 0,00000) entre le paquet
     * qui portait cette tete (12:25) et le paquet final deploye (17:00).
     *
     * ⚠️ RECALIBRE le 2026-08-23 (nouveau fichier recu de PC A,
     * `tete3_2026-08-23.json`, poids DIFFERENTS -- MD5 different du fichier
     * du 22 -- meme si la description embarquee n'a pas ete mise a jour cote
     * Python). La valeur de reference ci-dessous a ete recalculee sur CES
     * poids-la, pas sur ceux du 22 : ne pas la confondre avec l'ancienne
     * (100.0752334595, poids du 22, desormais remplaces sur le device).
     */
    @Test
    fun logit_reproduit_le_python_1036_entrees_modele_deploye() {
        val f = fichierDeploye1036()
        if (f == null) {
            println("modele_2geles_2026-08-22/tete3.json absent : parite NON verifiee sur cette machine")
            return
        }
        val t = Tete3.charger(f.readText())
        assertNotNull("tete3.json deploye present mais illisible", t)
        t!!
        assertEquals(1036, t.tailleEntree)

        // Valeur calculee en Python/NumPy (float32), meme algorithme que
        // Tete3.logit() -- boucle fidele (accum float64) ET forme vectorisee
        // (float32), les deux convergent a 2e-6 pres (2026-08-23, poids
        // recalibres du meme jour).
        val attendu = -70.07485961914062
        val obtenu = t.logit(vecteurReference(t.tailleEntree))
        assertEquals(
            "PARITE ROMPUE avec le Python -- la tete deployee ne doit PAS trancher de verdict tant que ceci echoue",
            attendu, obtenu.toDouble(), 0.02,
        )
        assertTrue(t.verifierParite(vecteurReference(t.tailleEntree), obtenu))

        // ⚠️ ECART CONNU, PAS UN BUG DE CE TEST : le tete3.json livre le
        // 2026-08-22 n'a AUCUNE cle `seuils_mesures` (verifie : ses 4 seules
        // cles sont description/caracteristiques/normalisation/couches).
        // `Tete3.charger` retombe donc sur son defaut documente (0f) --
        // fidelement reproduit ici, PAS un seuil mesure a 2 %/10 % de
        // collateral. Brancher cette tete sur un verdict avec ce seuil-la
        // serait arbitraire : il manque encore la mesure de calibrage
        // (audio reellement fautif contre ce modele), distincte de la
        // parite de calcul que ce test couvre.
        assertEquals(0.0, t.seuil2Pct.toDouble(), 1e-9)
        assertEquals(0.0, t.seuil10Pct.toDouble(), 1e-9)
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
