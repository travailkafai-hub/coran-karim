package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A rewind starts a new attempt; archived evidence is not a new recitation. */
class RepetitionPreuvesTest {
    private val texte = listOf("abc", "def", "ghi", "jkl", "mno", "pqr")
    private val pieces = Synthese.vocabulaire(texte)

    private fun chaine(): ChaineRecitation = ChaineRecitation(
        front = FauxFront(pieces), tokeniser = Synthese.tokeniseur(pieces),
    ).also {
        it.definirTexte(texte)
        it.alimenter(FloatArray(16000))
    }

    private fun obs(f: Long, mot: Int, gop: Float = 0f, debut: Long = 1000L,
                    atteste: Boolean = false) = RegistreDePreuves.Observation(
        fenetreId = f, motIndex = mot, gop = gop, forced = gop - 0.1f,
        free = -0.1f, entendu = texte[mot], frames = 4,
        interieur = true, couvert = true, atteste = atteste,
        fenetrePleine = true, debutAbs = debut + mot * 100L,
        finAbs = debut + mot * 100L + 80L,
    )

    private fun ancienPassage(c: ChaineRecitation) {
        for (i in texte.indices) {
            c.preuves.ajouter(obs(100, i, atteste = true))
            c.preuves.ajouter(obs(101, i, atteste = true))
        }
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[1])
    }

    @Test fun `rewind cannot restore old greens without any new audio`() {
        val c = chaine()
        ancienPassage(c)
        val archiveSize = c.preuves.total()
        c.reculerAncre(1)
        repeat(3) { c.alimenter(FloatArray(0)) }
        c.terminer()
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[0])
        assertFalse("Waiting for a real repetition", c.statuts.keys.any { it >= 1 })
        assertEquals("Keep evidence for audit and listening", archiveSize, c.preuves.total())
        assertEquals(2, c.preuves.observations(1).size)
    }

    @Test fun `wrong repetition is not rescued by an earlier exact green`() {
        val c = chaine()
        ancienPassage(c)
        c.reculerAncre(1)
        c.preuves.ajouter(obs(102, 1, gop = -3f, debut = 17000))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Provisoire(Couleur.ROUGE), c.statuts[1])
        c.preuves.ajouter(obs(103, 1, gop = -3f, debut = 17000))
        // New words provide the positive evidence of having moved on.
        for (i in 2..4) c.preuves.ajouter(obs(103, i, debut = 18000, atteste = true))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Definitif(Couleur.ROUGE), c.statuts[1])
    }

    @Test fun `a genuinely corrected repetition can turn green`() {
        val c = chaine()
        for (f in 100L..101L) c.preuves.ajouter(obs(f, 1, gop = -3f))
        c.preuves.ajouter(obs(101, 4, atteste = true))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Definitif(Couleur.ROUGE), c.statuts[1])
        c.reculerAncre(1)
        c.preuves.ajouter(obs(102, 1, debut = 17000, atteste = true))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[1])
    }

    @Test fun `a buffered window of the old audio cannot validate the new attempt`() {
        val c = chaine()
        ancienPassage(c)
        c.reculerAncre(1)
        // A new window id still covering the first attempt is not a repetition.
        c.preuves.ajouter(obs(102, 1, debut = 1000, atteste = true))
        c.preuves.ajouter(obs(103, 1, debut = 15000, atteste = true).copy(finAbs = 16500))
        c.alimenter(FloatArray(0))
        assertFalse(c.statuts.containsKey(1))
        c.preuves.ajouter(obs(104, 1, debut = 17000, atteste = true))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[1])
    }

    @Test fun `old later words cannot force omission during the next attempt`() {
        val c = chaine()
        ancienPassage(c)
        c.reculerAncre(1)
        c.preuves.ajouter(obs(102, 2, debut = 17000, atteste = true))
        c.alimenter(FloatArray(0))
        assertFalse("One new following word is insufficient for omission", c.statuts.containsKey(1))
        assertEquals(2, c.preuves.indexMaxVotant())
    }

    @Test fun `hint restart also waits for evidence from the new attempt`() {
        val c = chaine()
        ancienPassage(c)
        c.repartirApresSouffle(1)
        c.alimenter(FloatArray(0))
        assertTrue(c.statuts.keys.none { it >= 1 })
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[0])
    }

    @Test fun `a second rewind cannot reuse the first repetition`() {
        val c = chaine()
        ancienPassage(c)
        c.reculerAncre(1)
        c.preuves.ajouter(obs(102, 1, debut = 17000, atteste = true))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[1])
        c.reculerAncre(1)
        c.alimenter(FloatArray(0))
        assertFalse(c.statuts.containsKey(1))
        c.preuves.ajouter(obs(103, 1, gop = -3f, debut = 18000))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Provisoire(Couleur.ROUGE), c.statuts[1])
    }

    @Test fun `a one-frame word can be judged in the new attempt`() {
        val c = chaine()
        ancienPassage(c)
        c.reculerAncre(1)
        val o = obs(102, 1, debut = 17000, atteste = true)
        c.preuves.ajouter(o.copy(finAbs = o.debutAbs, frames = 1))
        c.alimenter(FloatArray(0))
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[1])
    }

    @Test fun `rewind preserves the raw clock including a partial capture block`() {
        val constructeur = ConstructeurDeFenetres()
        val c = ChaineRecitation(front = FauxFront(pieces),
            tokeniser = Synthese.tokeniseur(pieces), constructeur = constructeur)
        c.definirTexte(texte)
        c.alimenter(FloatArray(16017))
        c.reculerAncre(1)
        assertEquals(16017L, constructeur.positionTravail)
        assertEquals(c.brut.total, constructeur.positionTravail)
    }

    @Test fun `old tajwid evidence cannot excuse a rule missed on repetition`() {
        val c = chaine()
        ancienPassage(c)
        c.reglesVuesParMot[0] = mutableSetOf(1)
        c.reglesVuesParMot[1] = mutableSetOf(2)
        c.probasParMot[1] = mapOf("test" to (1f to 0.5f))
        c.dureesParMot[1] = mutableMapOf(2 to 120)
        c.reculerAncre(1)
        assertEquals(setOf(1), c.reglesVuesParMot[0])
        assertFalse(c.reglesVuesParMot.containsKey(1))
        assertFalse(c.probasParMot.containsKey(1))
        assertFalse(c.dureesParMot.containsKey(1))
    }
}
