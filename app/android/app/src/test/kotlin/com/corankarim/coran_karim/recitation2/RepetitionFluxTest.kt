package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Stream synthetic PCM through the real windows, localiser and decision chain. */
class RepetitionFluxTest {
    private val texte = listOf("abc", "def", "ghi", "jkl", "mno", "pqr", "stu", "vwx",
        "yza", "bcd", "efg", "hij", "klm", "nop", "qrs", "tuv")
    private val pieces = Synthese.vocabulaire(texte + "zzz")
    private val tok = Synthese.tokeniseur(pieces)

    private fun chaine() = ChaineRecitation(
        front = FauxFront(pieces), tokeniser = tok,
        constructeur = ConstructeurDeFenetres(pauseMinSecondes = 0.5),
    ).also { it.definirTexte(texte) }

    private fun jouer(c: ChaineRecitation, mots: List<String>) {
        val pcm = Synthese.pcm(mots, tok, pieces.size, 3, 3) + Synthese.silence(3.5)
        for (i in pcm.indices step Horloge.ECH_PAR_FRAME) {
            c.alimenter(pcm.copyOfRange(i, minOf(i + Horloge.ECH_PAR_FRAME, pcm.size)))
        }
        c.terminer()
    }

    @Test fun `a wrong repetition is detected after a correct first reading`() {
        val c = chaine()
        jouer(c, texte)
        assertEquals(Statut.Definitif(Couleur.VERT), c.statuts[7])
        c.reculerAncre(4)
        val suite = texte.drop(4).toMutableList().also { it[3] = "zzz" }
        jouer(c, suite)
        val s = c.statuts[7]
        assertTrue(c.tracerMot(7), s is Statut.Omis || s is Statut.Deplace ||
            s is Statut.Definitif && s.couleur != Couleur.VERT ||
            s is Statut.Provisoire && s.couleur != Couleur.VERT)
        assertTrue("Continue to the end of the repeated passage", c.preuves.indexMaxVotant() >= 13)
        for (i in 8..13) assertEquals("Correct word $i", Statut.Definitif(Couleur.VERT), c.statuts[i])
    }

    @Test fun `correct repetition clears the earlier error without accusing other words`() {
        val c = chaine()
        jouer(c, texte.toMutableList().also { it[7] = "zzz" })
        assertTrue(c.statuts[7] != Statut.Definitif(Couleur.VERT))
        c.reculerAncre(4)
        jouer(c, texte.drop(4))
        for (i in 4..13) assertEquals("Repeated word $i", Statut.Definitif(Couleur.VERT), c.statuts[i])
    }
}
