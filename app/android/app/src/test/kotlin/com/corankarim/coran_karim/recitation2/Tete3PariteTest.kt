package com.corankarim.coran_karim.recitation2

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * PARITE DE LA TETE 3 — la condition que sa propre documentation pose.
 *
 * `Tete3.kt` l'ecrit noir sur blanc : « TANT QU'ELLE N'A PAS ETE PASSEE SUR
 * DEVICE, la sortie de cette tete ne doit PAS trancher un verdict. » Ce test
 * est le moyen de lever cette condition, et rien d'autre ne peut la lever.
 *
 * ── POURQUOI CE TEST EXISTE, ET CE QU'IL ATTRAPE ────────────────────────────
 *
 * La tete a ete entrainee sur des caracteristiques calculees EN PYTHON. Le
 * Kotlin doit les reproduire A L'IDENTIQUE -- meme forward, memes variantes,
 * meme ORDRE. Une divergence ne leve AUCUNE erreur : elle rend simplement les
 * poids denues de sens. Le chiffre du README dit le cout : appliquer des poids
 * calibres sur un autre encodeur fait tomber la detection de 91,1 % a 14,4 %,
 * sans qu'une seule exception soit levee.
 *
 * DEUX DEFAUTS DEJA TROUVES PAR CETTE VOIE, un de chaque cote :
 *  - cote PYTHON (corrige le 2026-08-21 par la machine d'entrainement) :
 *    `reference_parite_tete3.py` concatenait moyenne ET ecart-type de l'etat
 *    (1024 dims) alors que `tete3.json` declare `etat_encodeur_moyen[512]` ;
 *  - cote KOTLIN (corrige ici le meme jour) : `ChaineRecitation` construisait
 *    toujours 1036 valeurs -- la forme de la tete du modele a TROIS tetes --
 *    face a une tete qui en attend 524. L'ecart de taille etait detecte plus
 *    haut et le calcul SAUTE : la tete 3 etait donc ETEINTE depuis le
 *    deploiement du modele a quatre tetes, sans autre trace qu'une ligne de
 *    journal.
 *
 * Deux erreurs symetriques sur la meme grandeur, trouvees seulement en
 * confrontant les deux cotes. C'est exactement ce que ce test institutionnalise.
 *
 * ── CE QUE LE TEST VERIFIE, DANS CET ORDRE ──────────────────────────────────
 *  1. les 12 caracteristiques calculees par le Kotlin, une par une, contre les
 *     valeurs nommees du fichier de reference -- c'est LA source de divergence ;
 *  2. la taille du vecteur d'entree (512 + 12 = 524) ;
 *  3. le logit final, a 1e-3 pres.
 *
 * L'etape 1 est la plus importante : si le logit final tombe juste alors qu'une
 * caracteristique est fausse, c'est une compensation fortuite, pas une parite.
 *
 * ── SI CE TEST EST IGNORE ───────────────────────────────────────────────────
 * Il s'ignore (`assumeTrue`) quand les fichiers du paquet ne sont pas la --
 * une copie de travail sans le modele reste testable. Un test IGNORE ne
 * prouve rien : il ne vaut pas un test VERT.
 */
class Tete3PariteTest {

    /** Le paquet du modele, cherche depuis le repertoire du module Gradle. */
    private fun paquet(): File? = listOf(
        File("../../../modele_4tetes_2026-08-21"),
        File("../../modele_4tetes_2026-08-21"),
        File("modele_4tetes_2026-08-21"),
    ).firstOrNull { File(it, "reference_tete3.json").exists() }

    private fun vec(a: JSONArray) = FloatArray(a.length()) { a.getDouble(it).toFloat() }
    private fun mat(a: JSONArray) = Array(a.length()) { vec(a.getJSONArray(it)) }
    private fun ints(a: JSONArray) = IntArray(a.length()) { a.getInt(it) }

    @Test
    fun `les caracteristiques et le logit correspondent au calcul Python`() {
        val dir = paquet()
        assumeTrue("paquet modele_4tetes_2026-08-21 absent -- test ignore", dir != null)
        val d = dir!!

        val tete = Tete3.charger(File(d, "tete3.json").readText(Charsets.UTF_8))
        assertNotNull("tete3.json illisible", tete)

        val ref = JSONObject(File(d, "reference_tete3.json").readText(Charsets.UTF_8))
        val noms = ref.getJSONArray("noms")
        val cas = ref.getJSONArray("cas")
        assertEquals("le fichier de reference doit porter au moins un cas",
            true, cas.length() > 0)

        for (i in 0 until cas.length()) {
            val c = cas.getJSONObject(i)
            val quoi = "cas $i (mot=${c.optString("mot")})"

            val lp = mat(c.getJSONArray("logprobs"))
            val etat = mat(c.getJSONArray("etat"))
            val tokens = ints(c.getJSONArray("tokens"))
            val variantes = c.getJSONArray("variantes").let { a ->
                (0 until a.length()).map { ints(a.getJSONArray(it)) }
            }

            // 1. LES CARACTERISTIQUES, UNE PAR UNE -- la vraie source de divergence.
            val traits = Tete3Traits.caracteristiques(lp, tokens, variantes)
            assertNotNull("$quoi : caracteristiques nulles", traits)
            val attendu = c.getJSONObject("attendu")
            for (k in 0 until noms.length()) {
                val nom = noms.getString(k)
                if (!attendu.has(nom)) continue
                assertEquals(
                    "$quoi : caracteristique '$nom' divergente",
                    attendu.getDouble(nom), traits!![k].toDouble(), 1e-3,
                )
            }

            // 2. LA TAILLE DU VECTEUR : moyenne SEULE de l'etat (512) + 12 scores.
            val moyenne = Tete3Traits.etatMoyen(etat, 0, etat.size)
            assertNotNull("$quoi : etat moyen nul", moyenne)
            val entree = moyenne!! + traits!!
            assertEquals("$quoi : taille du vecteur d'entree",
                c.getInt("taille_vecteur"), entree.size)
            assertEquals("$quoi : la tete chargee attend une autre taille",
                tete!!.tailleEntree, entree.size)

            // 3. LE LOGIT FINAL.
            assertEquals(
                "$quoi : logit divergent -- la tete 3 ne doit PAS tourner sur l'appareil",
                c.getDouble("logit_attendu"), tete.logit(entree).toDouble(), 1e-3,
            )
        }
    }
}
