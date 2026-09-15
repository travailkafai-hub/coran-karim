package com.corankarim.coran_karim.recitation2

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.ln

class VoteFenetresTest {
    private fun observation(id: Long, texte: String, poids: Double) = RegistreDePreuves.Observation(
        fenetreId = id, motIndex = 0, gop = 0f, forced = 0f, free = 0f,
        entendu = texte, frames = 2, interieur = true, couvert = true,
        fenetrePleine = true, debutAbs = 5000, finAbs = 6280,
        lectureVote = VoteFenetres.Lecture(ConfianceLectureCtc.Mesure(poids, 1, poids, poids),
            null, 0, 16000 + id * 1280),
    )

    @Test fun `deux A de poids 08 gagnent contre B de poids 08 dans tous les ordres`() {
        val a1 = observation(1, "A", .8)
        val a2 = observation(2, "A", .8)
        val b = observation(3, "B", .8).copy(atteste = true)
        for (ordre in listOf(listOf(a1, a2, b), listOf(b, a1, a2), listOf(a1, b, a2))) {
            val r = VoteFenetres.calculer(ordre)
            assertEquals("A", r.gagnant)
            assertEquals(1.6, r.candidats.first().poids, 1e-9)
        }
    }

    @Test fun `une lecture B solide gagne contre deux textes incertains`() {
        val r = VoteFenetres.calculer(listOf(observation(1, "A", .2),
            observation(2, "B", .9), observation(3, "C", .1)))
        assertEquals("B", r.gagnant)
    }

    @Test fun `egalite donne doute sans avantage pour attestation`() {
        val r = VoteFenetres.calculer(listOf(observation(1, "A", .8),
            observation(2, "B", .8).copy(atteste = true)))
        assertNull(r.gagnant)
        assertEquals("INDECIS", r.etat)
    }

    @Test fun `premier B atteste ne bloque pas A aux fenetres suivantes`() {
        val obs = mutableListOf(observation(1, "B", .8).copy(atteste = true))
        assertEquals("B", VoteFenetres.calculer(obs).gagnant)
        obs.add(observation(2, "A", .8))
        assertNull(VoteFenetres.calculer(obs).gagnant)
        obs.add(observation(3, "A", .8))
        assertEquals("A", VoteFenetres.calculer(obs).gagnant)
    }

    @Test fun `une fenetre reanalyseee ne recoit pas deux voix`() {
        val a = observation(1, "A", .8)
        val r = VoteFenetres.calculer(listOf(a, a, observation(2, "B", .8)))
        assertNull(r.gagnant)
        assertEquals(1, r.exclusions["revision_meme_fenetre"])
        val revise = VoteFenetres.calculer(listOf(a, observation(1, "B", .9)))
        assertEquals(listOf("B"), revise.candidats.map { it.texte })
    }

    @Test fun `deux ids avec meme contexte audio ne font pas deux voix`() {
        val a = observation(1, "A", .8)
        val r = VoteFenetres.calculer(listOf(a, a.copy(fenetreId = 3), observation(2, "B", .8)))
        assertNull(r.gagnant)
        assertEquals(1, r.exclusions["contexte_duplique"])
    }

    @Test fun `bords silence voisins et fragments ne votent pas`() {
        val a = observation(1, "A", .8)
        val obs = listOf(a, observation(2, "B", .9).copy(interieur = false),
            observation(3, "B", .9).copy(sansCreneau = true), observation(4, "", .9),
            observation(5, "B", .9).copy(lectureVote = a.lectureVote!!.copy(exclusion = "fragment_alignement")))
        val r = VoteFenetres.calculer(obs)
        assertEquals("A", r.gagnant)
        assertEquals(4, r.exclusions.values.sum())
    }

    @Test fun `poids manquant ou non fini empeche de declarer un gagnant`() {
        for (b in listOf(observation(2, "B", Double.NaN), observation(2, "B", 2.0),
            observation(2, "B", .9).copy(lectureVote = null))) {
            val r = VoteFenetres.calculer(listOf(observation(1, "A", .8), b))
            assertEquals("INCOMPLET", r.etat)
            assertNull(r.gagnant)
        }
    }

    @Test fun `une frame non couverte reste une vraie lecture possible`() {
        val o = observation(1, "A", .8).copy(frames = 1, couvert = false, finAbs = 5000)
        assertEquals("A", VoteFenetres.calculer(listOf(o)).gagnant)
    }

    @Test fun `harakat et lettres distinctes restent en competition`() {
        val r = VoteFenetres.calculer(listOf(observation(1, "عَلِمَ", .8),
            observation(2, "عَلَمَ", .8)))
        assertEquals(2, r.candidats.size)
        assertNull(r.gagnant)
        assertEquals(VoteFenetres.cle("أَ"), VoteFenetres.cle("أَ"))
    }

    @Test fun `plages disjointes ne sont pas declarees meme occurrence`() {
        val r = VoteFenetres.calculer(listOf(observation(1, "A", .8),
            observation(2, "A", .8).copy(debutAbs = 32000, finAbs = 33000)))
        assertEquals("OCCURRENCE_AMBIGUE", r.etat)
        assertNull(r.gagnant)
    }

    @Test fun `une composante majoritaire survit a une attribution parasite eloignee`() {
        val a1 = observation(1, "A", .8)
        val a2 = observation(2, "A", .8)
        val parasite = observation(3, "B", .7).copy(debutAbs = 32000, finAbs = 33000)
        val r = VoteFenetres.calculer(listOf(a1, a2, parasite))
        assertEquals("A", r.gagnant)
        assertEquals(listOf("A"), r.candidats.map { it.texte })
        assertEquals(1, r.exclusions["occurrence_non_retenue"])
    }

    @Test fun `nouvelle tentative exclut les anciennes lectures sans effacer archive`() {
        val registre = RegistreDePreuves()
        registre.ajouter(observation(1, "B", .8))
        registre.commencerTentative(0, 10000)
        registre.ajouter(observation(2, "A", .8).copy(debutAbs = 11000, finAbs = 12000))
        assertEquals("A", VoteFenetres.calculer(registre.observationsPourJugement(0)).gagnant)
        assertEquals(2, registre.observations(0).size)
        assertEquals(1L, registre.tentativeId)
    }

    private fun frame(vararg p: Double) = FloatArray(p.size) { ln(p[it]).toFloat() }

    @Test fun `blancs et allongement CTC ne gonflent pas confiance`() {
        val a = frame(.8, .1, .1)
        val b = frame(.1, .6, .3)
        val blanc = frame(.0001, .0001, .9998)
        val court = ConfianceLectureCtc.mesurer(arrayOf(a, b), 2, 0, 1)!!
        val long = ConfianceLectureCtc.mesurer(arrayOf(blanc, a, a, a, b, b, blanc), 2, 0, 6)!!
        assertEquals(2, long.tokens)
        assertEquals(court.poids, long.poids, 1e-9)
        assertEquals(kotlin.math.sqrt(.8 * .6), long.poids, 1e-6)
        assertNull(ConfianceLectureCtc.mesurer(arrayOf(blanc), 2, 0, 0))
    }

    @Test fun `blanc entre deux emissions identiques preserve deux tokens`() {
        val a = frame(.8, .1, .1)
        val blanc = frame(.1, .1, .8)
        assertEquals(2, ConfianceLectureCtc.mesurer(arrayOf(a, blanc, a), 2, 0, 2)!!.tokens)
        assertNull(ConfianceLectureCtc.mesurer(arrayOf(a), 2, -1, 0))
        assertNull(ConfianceLectureCtc.mesurer(arrayOf(floatArrayOf(Float.NaN, 0f)), 1, 0, 0))
    }

    @Test fun `fragment de DP interieur exclu mais vraie troncature libre conservee`() {
        val f = Fenetre(1, 0, FloatArray(32000), Correspondance(emptyList()), true)
        val logp = Array(20) { frame(.8, .1, .1) }
        val m = AligneurForce.MotAligne(0, 5, 7, 3, -1f, -.1f, -.9f,
            "AB", true, false, false)
        val fragment = VoteFenetres.mesurer(m, listOf(Decodage.MotEntendu("ABC", 4, 8)), logp, 2, f)
        assertEquals("fragment_alignement", fragment.exclusion)
        val complet = VoteFenetres.mesurer(m, listOf(Decodage.MotEntendu("AB", 5, 7)), logp, 2, f)
        assertNull(complet.exclusion)
        assertNotNull(complet.confiance)
        val tenue = VoteFenetres.mesurer(m, listOf(Decodage.MotEntendu("AB", 4, 8)), logp, 2, f)
        assertNull("La tenue d'un token ne doit pas effacer une lecture complete", tenue.exclusion)
    }
}
