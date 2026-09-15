package com.corankarim.coran_karim.recitation2

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * PARITE PYTHON / KOTLIN, SUR AUDIO REEL, POUR LE PAQUET DEPLOYE (2026-09-15).
 *
 * ── CE QUE [Tete3ParitePaqueDeployeTest] NE COUVRAIT PAS ────────────────────
 *
 * Ce fichier-la verifie la couche MLP (poids, normalisation, ReLU) avec un
 * vecteur SYNTHETIQUE -- aucun encodeur necessaire, mais aucune preuve non
 * plus que [Tete3Traits.caracteristiques] extrait les 12 scores de la MEME
 * facon que le Python qui a entraine la tete. C'etait le trou explicitement
 * laisse ouvert dans sa doc : « exige de faire tourner l'encodeur NeMo... Ni
 * torch, ni NeMo, ni ce checkpoint ne sont presents sur la machine qui a
 * ecrit ce test. »
 *
 * ── COMMENT CE TROU A ETE FERME ──────────────────────────────────────────────
 *
 * Ni torch ni NeMo n'ont ete installes ici : la reference a ete produite sur
 * PC A (Ubuntu, `.venv_nemo`, le checkpoint `warsh-v5-epoch6.nemo`) via
 * `benchmark/tunnel_pc_a/` -- demande deposee, reponse recue en retour, cf.
 * `benchmark/tunnel_pc_a/reponses/`. Deux allers-retours ont ete necessaires :
 * le premier essai de PC A a echoue sur un `reference_parite_tete3.py` LOCAL
 * et jamais commite, resultat d'un reliquat de l'episode du 21 aout (rien a
 * voir avec le fichier suivi par git, verifie par blob identique a HEAD) --
 * remplace par la version du depot avant de relancer. La chaine de preuve
 * complete (empreintes, diagnostic, correctif) est dans
 * `benchmark/tunnel_pc_a/reponses/SUITE_2026-09-15_correction_blocage1_et_resultat_hafs.md`.
 *
 * ── CE QUE CE TEST PROUVE, ET CE QU'IL NE PROUVE PAS ────────────────────────
 *
 * Il verifie, sur 4 mots REELLEMENT PASSES PAR L'ENCODEUR `warsh-v5-epoch6.nemo`
 * (le meme qui a entraine cette tete, hash `900a142d2b585d3c`, deja verifie
 * dans le graphe causal) : les 12 caracteristiques une par une
 * ([Tete3Traits.caracteristiques]), la taille du vecteur complet (1036,
 * mean+std), et le logit final ([Tete3.logit]) -- pour le paquet HAFS
 * reellement embarque par l'APK.
 *
 * ⚠️ SUR DU TTS, PAS DE LA VRAIE RECITATION. La phrase source
 * (`وَإِنْ عَزَمُوا۟ ٱلطَّلَـٰقَ فَإِنَّ ٱللَّهَ سَمِيعٌ عَلِيمٌ`, corpus
 * `data/tts_phrases_concat`) est une voix synthetique, pas un recitateur.
 * Ce test ferme le risque « le calcul diverge », pas la question de
 * fidelite de l'extraction sur une vraie voix -- cf. la reponse de PC A
 * pour ce qui manque encore (corpus Warsh reel, non trouve compatible).
 *
 * ⚠️ WARSH RESTE OUVERT. `reference_parite_tete3.py` code en dur le
 * decodeur/tokenizer Hafs (`model.ctc_decoder`, `model.tokenizer.tokenizer`),
 * verifie independamment des deux cotes du tunnel -- aucune reference Warsh
 * ne peut en sortir tant que cette branche n'existe pas. Pas de test Warsh
 * ici pour cette raison, pas par oubli.
 *
 * ⚠️ NE PAS REGENERER LA REFERENCE POUR FAIRE PASSER CE TEST -- meme regle
 * que [Tete3TraitsTest].
 */
class Tete3ParitePaqueDeployeAudioReelTest {

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
    // Precision apres reception du fichier PC A (15/09) : la reference
    // fournie porte p000000_faute.wav, du TTS. L'intitule historique de la
    // classe ne doit pas transformer cette parite en preuve sur recitateur.
    fun `caracteristiques et logit reproduisent la reference TTS du paquet Hafs deploye`() {
        val fr = remonter("benchmark/tunnel_pc_a/reponses/reference_tete3_hafs.json")
        val ft = remonter(
            "app/android/model_pack/src/main/assets/models/" +
                "cinq-tetes-2026-09-11-madd-normal/tete3.json")
        assertNotNull("reference_tete3_hafs.json absent -- PARITE NON VERIFIEE", fr)
        assertNotNull("tete3.json absent -- PARITE NON VERIFIEE", ft)
        val tete = Tete3.charger(ft!!.readText())
        assertNotNull("tete3.json illisible", tete)
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

            // 1. LES 12 CARACTERISTIQUES, une par une -- la vraie source de
            //    divergence possible entre les deux langages.
            val traits = Tete3Traits.caracteristiques(lp, tokens, variantes)
            assertNotNull("$nom : caracteristiques nulles cote Kotlin", traits)
            traits!!
            val attendu = c.getJSONObject("attendu")
            for ((k, n) in Tete3Traits.NOMS.withIndex()) {
                assertEquals(
                    "PARITE ROMPUE sur $n pour $nom",
                    attendu.getDouble(n), traits[k].toDouble(), 1e-3,
                )
            }

            // 2. LE VECTEUR COMPLET -- etat d'encodeur (mean+std, 1024) + 12
            //    scores, dans l'ordre que la tete deployee attend reellement.
            val etatVec = Tete3Traits.etatMoyenEtEcartType(etat, 0, etat.size)
            assertNotNull("$nom : etat moyen+ecart-type nul", etatVec)
            val vecteur = etatVec!! + traits
            assertEquals("$nom : taille du vecteur", c.getInt("taille_vecteur"), vecteur.size)
            assertEquals(
                "$nom : la tete deployee attend une autre taille",
                tete.tailleEntree, vecteur.size,
            )

            // 3. LE LOGIT FINAL. Tolerance plus large que sur les
            //    caracteristiques seules : somme de 1036 produits, chaque
            //    terme portant l'arrondi float du JSON.
            assertEquals(
                "$nom : PARITE ROMPUE sur le logit -- cette tete ne doit PAS " +
                    "trancher de verdict tant que ceci echoue",
                c.getDouble("logit_attendu"), tete.logit(vecteur).toDouble(), 5e-2,
            )
        }
    }
}
