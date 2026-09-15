package com.corankarim.coran_karim.recitation2

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * PARITE PYTHON / KOTLIN EN WARSH, SUR VRAIE RECITATION (2026-09-15).
 *
 * ── CE QUE LE PENDANT HAFS NE POUVAIT PAS COUVRIR ───────────────────────────
 *
 * [Tete3ParitePaqueDeployeAudioReelTest] porte en tete deux avertissements :
 * son audio est du TTS, et « WARSH RESTE OUVERT » parce que
 * `reference_parite_tete3.py` codait en dur le decodeur et le tokenizer Hafs.
 * Ce test ferme la seconde reserve, et fait mieux que la premiere : la
 * reference vient d'un `ConvLettersDecoder` + tokenizer `warsh_seul_v1`
 * (script `reference_parite_tete3_warsh.py`, ecrit sur PC A pour cela) applique
 * a de la VRAIE RECITATION Warsh -- `AbdelKabirHadidi_assajda/100_10.wav` du
 * manifeste `train_warsh_final_2026-08-22.jsonl` -- pas a de la voix
 * synthetique ni a un montage.
 *
 * ── QUELLE TETE A PRODUIT CES LOGITS, ET POURQUOI CA COMPTE ─────────────────
 *
 * `tete3_warsh.json` du paquet deploye, VERIFIE ici et non suppose : les trois
 * `logit_attendu` ont ete recalcules hors Kotlin sur les trois candidates
 * possibles, et seule celle du paquet retombe dessus (a 1e-5). La candidate
 * `tete3_warsh_v1.json` donne -4,936 / -6,113 / -6,053 et la tete Hafs
 * -10,299 / 22,931 / -9,123 : aucune confusion possible.
 *
 * Ce que ce test prouve vaut pourtant pour LES DEUX tetes Warsh, et c'est tout
 * son interet : elles consomment le MEME vecteur (meme encodeur, memes 12
 * caracteristiques, 1036 entrees) et ne different que par leurs poids. Prouver
 * que le Kotlin CONSTRUIT le bon vecteur en Warsh valide donc aussi l'entree
 * de la candidate branchee par [JugementTete3.WARSH] -- dont l'arithmetique,
 * elle, est couverte a part (`JugementTete3Test`, empreinte + logit de
 * reference sur vecteur deterministe).
 *
 * ⚠️ CE QUE CE TEST NE PROUVE TOUJOURS PAS : aucun seuil, aucun rappel sur
 * fautes reelles, aucune mesure sur telephone. La tete Warsh de decision reste
 * `NON_CALIBREE`, avec la frontiere brute logit=0 -- exactement comme Hafs.
 *
 * ⚠️ NE PAS REGENERER LA REFERENCE POUR FAIRE PASSER CE TEST -- meme regle
 * que [Tete3TraitsTest].
 */
class Tete3PariteWarshAudioReelTest {

    private fun remonter(relatif: String): File? {
        var d: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (d != null) {
            val f = File(d, relatif)
            if (f.exists()) return f
            d = d.parentFile
        }
        return null
    }

    private fun matrice(a: org.json.JSONArray) = Array(a.length()) { i ->
        val l = a.getJSONArray(i)
        FloatArray(l.length()) { l.getDouble(it).toFloat() }
    }

    private fun entiers(a: org.json.JSONArray) = IntArray(a.length()) { a.getInt(it) }

    @Test
    fun `caracteristiques et logit reproduisent le Python sur recitation Warsh reelle`() {
        val fr = remonter("benchmark/tunnel_pc_a/reponses/reference_tete3_warsh.json")
        val ft = remonter(
            "app/android/model_pack/src/main/assets/models/" +
                "cinq-tetes-2026-09-11-madd-normal/tete3_warsh.json")
        assertNotNull("reference_tete3_warsh.json absent -- PARITE NON VERIFIEE", fr)
        assertNotNull("tete3_warsh.json absent du paquet -- PARITE NON VERIFIEE", ft)
        val tete = Tete3.charger(ft!!.readText())
        assertNotNull("tete3_warsh.json illisible", tete)
        tete!!
        assertEquals(1036, tete.tailleEntree)

        val ref = JSONObject(fr!!.readText())
        val cas = ref.getJSONArray("cas")
        assertTrue("la reference doit porter plusieurs mots reels", cas.length() >= 3)

        for (i in 0 until cas.length()) {
            val c = cas.getJSONObject(i)
            val nom = "${c.getString("mot")} (mot ${c.getInt("mot_index")})"
            val lp = matrice(c.getJSONArray("logprobs"))
            val etat = matrice(c.getJSONArray("etat"))
            val tokens = entiers(c.getJSONArray("tokens"))
            val vars = c.getJSONArray("variantes")
            val variantes = (0 until vars.length()).map { entiers(vars.getJSONArray(it)) }

            // 1. LES 12 CARACTERISTIQUES. C'est ici que Hafs et Warsh
            //    pouvaient diverger sans que rien ne le signale : le decodage
            //    libre, les variantes et le chemin force passent par un AUTRE
            //    decodeur et un AUTRE tokenizer.
            val traits = Tete3Traits.caracteristiques(lp, tokens, variantes)
            assertNotNull("$nom : caracteristiques nulles cote Kotlin", traits)
            traits!!
            val attendu = c.getJSONObject("attendu")
            for ((k, n) in Tete3Traits.NOMS.withIndex()) {
                assertEquals(
                    "PARITE WARSH ROMPUE sur $n pour $nom",
                    attendu.getDouble(n), traits[k].toDouble(), 1e-3,
                )
            }

            // 2. LE VECTEUR COMPLET, dans l'ordre que les deux tetes Warsh
            //    attendent (mean+std de l'etat, puis les 12 scores).
            val etatVec = Tete3Traits.etatMoyenEtEcartType(etat, 0, etat.size)
            assertNotNull("$nom : etat moyen+ecart-type nul", etatVec)
            val vecteur = etatVec!! + traits
            assertEquals("$nom : taille du vecteur", c.getInt("taille_vecteur"), vecteur.size)
            assertEquals(
                "$nom : la tete Warsh deployee attend une autre taille",
                tete.tailleEntree, vecteur.size,
            )

            // 3. LE LOGIT. Meme tolerance elargie que cote Hafs : somme de
            //    1036 produits, chaque terme portant l'arrondi float du JSON.
            assertEquals(
                "$nom : PARITE WARSH ROMPUE sur le logit -- cette tete ne doit " +
                    "PAS trancher de verdict tant que ceci echoue",
                c.getDouble("logit_attendu"), tete.logit(vecteur).toDouble(), 5e-2,
            )
        }
    }
}
