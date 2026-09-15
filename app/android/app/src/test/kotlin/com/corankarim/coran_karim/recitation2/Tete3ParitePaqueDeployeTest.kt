package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest

/**
 * PARITE PYTHON / KOTLIN SUR LE PAQUET REELLEMENT EMBARQUE PAR L'APK.
 *
 * ── POURQUOI CE TEST EXISTE (2026-09-15) ────────────────────────────────────
 *
 * Ni [Tete3PariteTest] ni [Tete3Test.logit_reproduit_le_python_1036_entrees_modele_deploye]
 * ne portent sur le paquet que l'app charge aujourd'hui :
 *   - [Tete3PariteTest] verifie `modele_4tetes_2026-08-21/` (tete a 524 entrees) ;
 *   - l'autre verifie `modele_2geles_2026-08-22/` (tete a 1036 entrees, mais
 *     un fichier DIFFERENT -- le sien, pas celui-ci).
 * Le paquet embarque par `app/android/model_pack/` est
 * `cinq-tetes-2026-09-11-madd-normal` : AUCUN des deux tests existants ne
 * l'a jamais touche. Les deux passent au vert sans rien dire du paquet reel.
 *
 * ── CE QUE CE TEST PROUVE, ET CE QU'IL NE PROUVE PAS ────────────────────────
 *
 * Il verifie la COUCHE MLP SEULE : chargement du JSON, orientation des
 * matrices, ordre normalisation -> lineaire -> ReLU -> lineaire -> biais.
 * C'est la partie qui ne demande QUE les poids -- aucun encodeur necessaire --
 * et c'est deja la ou le projet s'est trompe deux fois (reimplementer une
 * meme logique dans deux langages, cf. la doc de [Tete3]).
 *
 * Il NE verifie PAS l'extraction des 12 caracteristiques depuis de l'audio
 * reel ([Tete3Traits.caracteristiques], ce que [Tete3TraitsTest] couvre pour
 * un AUTRE paquet). Cette partie-la exige de faire tourner l'encodeur NeMo
 * qui a entraine cette tete -- `warsh-v5-epoch6.nemo`, nomme dans le champ
 * `description` du JSON lui-meme -- pour produire de vrais logprobs/etat
 * d'encodeur. Ni torch, ni NeMo, ni ce checkpoint ne sont presents sur la
 * machine qui a ecrit ce test (2026-09-15) : cette moitie du risque reste
 * OUVERTE, pas close par erreur. La note de tache le nomme explicitement
 * comme prealable a toute decision de faire trancher cette tete un verdict.
 *
 * ── LA REFERENCE ─────────────────────────────────────────────────────────
 *
 * Produite par `benchmark/reference_parite_tete3_deployee.py`, qui n'a besoin
 * QUE du fichier tete3*.json -- pas de NeMo. Meme formule deterministe que
 * [Tete3Test.vecteurReference] : `(((i*37) % 101) - 50) / 25.0`, memes
 * flottants des deux cotes (formule ENTIERE, aucune fonction transcendante).
 *
 * Le SHA-256 de chaque fichier est verifie AVANT de comparer le logit : sans
 * cette garde, un paquet remplace un jour ferait comparer le Kotlin a une
 * reference qui ne decrit plus le meme fichier, en silence.
 *
 * ⚠️ NE PAS REGENERER LA REFERENCE POUR FAIRE PASSER CE TEST. Si les valeurs
 * ci-dessous divergent d'un futur paquet, c'est le SHA-256 qui doit echouer
 * en premier -- pas une reference qu'on aurait silencieusement rafraichie.
 */
class Tete3ParitePaqueDeployeTest {

    private val dossierPaquet =
        "app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal"

    private fun remonter(relatif: String): File? {
        var d: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (d != null) {
            val f = File(d, relatif)
            if (f.exists()) return f
            d = d.parentFile
        }
        return null
    }

    private fun sha256(f: File): String {
        val h = MessageDigest.getInstance("SHA-256").digest(f.readBytes())
        return h.joinToString("") { "%02x".format(it) }
    }

    private fun vecteurReference(n: Int) =
        FloatArray(n) { (((it * 37) % 101) - 50) / 25.0f }

    /** Un cas : nom du fichier, empreinte attendue, logit calcule en Python. */
    private data class Cas(val fichier: String, val sha256: String, val logitAttendu: Double)

    private val cas = listOf(
        // Empreintes et logits produits par
        // `python3 benchmark/reference_parite_tete3_deployee.py tete3.json tete3_warsh.json`
        // le 2026-09-15, sur le paquet cinq-tetes-2026-09-11-madd-normal.
        Cas("tete3.json",
            "c594993a1d3687aa33ba7f521866fbeb5e2c2078c2cb7225911540fb43e0ef99",
            -48.909840),
        Cas("tete3_warsh.json",
            "f6ac3851d5ed7896ff56443d151d129669aac03f5bff0efad0387603259f625d",
            13.663626),
    )

    @Test
    fun `le paquet embarque reproduit la reference Python, Hafs et Warsh`() {
        for (c in cas) {
            val f = remonter("$dossierPaquet/${c.fichier}")
            if (f == null) {
                // Copie de travail sans les assets du model_pack : ne pas
                // faire echouer la suite, mais ne pas laisser croire non
                // plus que la parite a ete verifiee ici.
                println("${c.fichier} absent de $dossierPaquet sur cette machine " +
                    "-- parite NON verifiee")
                continue
            }
            val empreinte = sha256(f)
            assertEquals(
                "${c.fichier} a change depuis que cette reference a ete calculee -- " +
                    "regenerer avec reference_parite_tete3_deployee.py, ne pas " +
                    "corriger juste le SHA attendu sans revoir le logit",
                c.sha256, empreinte,
            )
            val t = Tete3.charger(f.readText())
            assertNotNull("${c.fichier} present mais illisible par Tete3.charger", t)
            t!!
            assertEquals(1036, t.tailleEntree)
            val obtenu = t.logit(vecteurReference(t.tailleEntree))
            assertEquals(
                "${c.fichier} : PARITE ROMPUE avec le Python -- cette tete ne doit " +
                    "PAS trancher de verdict tant que ceci echoue",
                c.logitAttendu, obtenu.toDouble(), 0.02,
            )
            assertTrue(t.verifierParite(vecteurReference(t.tailleEntree), obtenu))
            // Le paquet livre le 2026-09-11 n'a AUCUNE cle `seuils_mesures`
            // (verifie par lecture directe du JSON) : l'absence doit rester
            // une absence, jamais un zero fabrique en son nom.
            assertNull("${c.fichier} : seuil 2% absent attendu", t.seuil2Pct)
            assertNull("${c.fichier} : seuil 10% absent attendu", t.seuil10Pct)
        }
    }
}
