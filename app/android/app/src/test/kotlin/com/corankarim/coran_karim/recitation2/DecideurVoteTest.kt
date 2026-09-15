package com.corankarim.coran_karim.recitation2

import org.junit.Assert.*
import org.junit.Test

class DecideurVoteTest {
    private fun obs(id: Long, texte: String, poids: Double, mot: Int = 0) =
        RegistreDePreuves.Observation(id, mot, 0f, 0f, 0f, texte, 2, true, true,
            fenetrePleine = true, debutAbs = 5000L + mot*16000, finAbs = 6280L + mot*16000,
            lectureVote = VoteFenetres.Lecture(ConfianceLectureCtc.Mesure(poids, 1, poids, poids),
                null, 0, 32000 + id*1280))
    private fun contexte(attendu: String = "B", ferme: Boolean = false, frontiere: Long = 0) =
        Decideur.ContexteVote(listOf(attendu), frontiere, ferme)

    @Test fun `premier vert devient doute puis rouge quand A gagne sur le meme audio`() {
        val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
        r.ajouter(obs(1, "B", .8).copy(atteste = true))
        assertEquals(Statut.Provisoire(Couleur.VERT), d.statuts(r, 1, contexte())[0])
        r.ajouter(obs(2, "A", .8))
        assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 1, contexte())[0])
        r.ajouter(obs(3, "A", .8))
        assertEquals(Statut.Provisoire(Couleur.ROUGE), d.statuts(r, 1, contexte())[0])
        assertEquals(Statut.Definitif(Couleur.ROUGE), d.statuts(r, 1, contexte(ferme = true))[0])
        assertEquals("A", d.preuveRetenue(0)!!.entendu)
    }

    @Test fun `B solide gagne sur A et C faibles et fournit la preuve affichee`() {
        val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
        listOf(obs(1, "A", .2), obs(2, "B", .9), obs(3, "C", .1)).forEach(r::ajouter)
        assertEquals(Statut.Definitif(Couleur.VERT), d.statuts(r, 1, contexte(ferme = true))[0])
        assertEquals(2L, d.preuveRetenue(0)!!.fenetreId)
    }

    @Test fun `egalite reste doute meme en fermeture et malgre attestation`() {
        for (inverse in listOf(false, true)) {
            val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
            val lectures = listOf(obs(1, "A", .8), obs(2, "B", .8).copy(atteste = true))
            (if (inverse) lectures.reversed() else lectures).forEach(r::ajouter)
            assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 1, contexte(ferme = true))[0])
            assertNull(d.preuveRetenue(0))
        }
    }

    @Test fun `T023 trois lectures fautives ne passent plus vert a GOP proche de zero`() {
        val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
        listOf(obs(4, "ٱلْمُرْسَلُونَ", .803968).copy(gop = -.021622f),
            obs(5, "ٱلْمُرْسَلُونَ", .940463).copy(gop = -.672748f),
            obs(6, "إِلَىٰ", .760266).copy(interieur = false),
            obs(7, "ٱلْمُرْسَلُونَ", .797560).copy(gop = -.004960f)).forEach(r::ajouter)
        assertEquals(Statut.Provisoire(Couleur.ROUGE),
            d.statuts(r, 1, contexte("ٱلْمُرْسَلِينَ"))[0])
        assertEquals(Statut.Definitif(Couleur.ROUGE),
            d.statuts(r, 1, contexte("ٱلْمُرْسَلِينَ", ferme = true))[0])
        assertEquals(5L, d.preuveRetenue(0)!!.fenetreId)
    }

    @Test fun `deux observations restent revisables tant que la frame peut revenir`() {
        val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
        r.ajouter(obs(1, "B", .8)); r.ajouter(obs(2, "B", .8))
        assertEquals(Statut.Provisoire(Couleur.VERT), d.statuts(r, 1, contexte(frontiere = 6280))[0])
        assertEquals(Statut.Definitif(Couleur.VERT),
            d.statuts(r, 1, contexte(frontiere = 6280 + Horloge.ECH_PAR_FRAME.toLong()))[0])
    }

    @Test fun `fermeture ne fabrique pas la deuxieme observation`() {
        val r = RegistreDePreuves(); val d = Decideur(k = 1, votePondere = true)
        r.ajouter(obs(1, "B", .9).copy(atteste = true))
        assertEquals(Statut.Provisoire(Couleur.VERT), d.statuts(r, 1, contexte(ferme = true))[0])
        r.ajouter(obs(1, "B", .9).copy(atteste = true))
        assertEquals(Statut.Provisoire(Couleur.VERT), d.statuts(r, 1, contexte(ferme = true))[0])
    }

    @Test fun `bord atteste ne contourne pas le vote par le secours omission`() {
        val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
        r.ajouter(obs(1, "B", .99).copy(interieur = false, atteste = true))
        for (i in 1..3) { r.ajouter(obs(2, "B", .9, i)); r.ajouter(obs(3, "B", .9, i)) }
        val ctx = Decideur.ContexteVote(List(4) { "B" }, 100000, true)
        assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 4, ctx)[0])
        assertEquals(Statut.Definitif(Couleur.VERT), d.statuts(r, 4, ctx)[3])
    }

    @Test fun `silence et audio voisin ne donnent aucun rouge`() {
        val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
        r.ajouter(obs(1, "", .9)); r.ajouter(obs(2, "A", .9).copy(sansCreneau = true))
        assertNull(d.statuts(r, 1, contexte(ferme = true))[0])
    }

    @Test fun `equivalence phonétique gardee mais haraka differente signalee`() {
        for ((attendu, entendu, couleur) in listOf(
            Triple("فِرَٰشًا", "فِرَاشًا", Couleur.VERT),
            Triple("عَلِمَ", "عَلَمَ", Couleur.ROUGE))) {
            val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
            r.ajouter(obs(1, entendu, .8)); r.ajouter(obs(2, entendu, .8))
            assertEquals(Statut.Definitif(couleur), d.statuts(r, 1, contexte(attendu, true))[0])
        }
    }

    @Test fun `preuve finale stable puis oubliee uniquement lors de la reprise`() {
        val r = RegistreDePreuves(); val d = Decideur(votePondere = true)
        r.ajouter(obs(1, "A", .8)); r.ajouter(obs(2, "A", .8))
        d.statuts(r, 1, contexte(ferme = true))
        r.ajouter(obs(3, "B", 1.0).copy(atteste = true))
        assertEquals(Statut.Definitif(Couleur.ROUGE), d.statuts(r, 1, contexte(ferme = true))[0])
        d.oublierDepuis(0, effacerProvisoires = true)
        r.commencerTentative(0, 10000)
        r.ajouter(obs(4, "B", .9).copy(debutAbs = 11000, finAbs = 12000))
        assertEquals(Statut.Provisoire(Couleur.VERT), d.statuts(r, 1, contexte())[0])
        assertEquals(4L, d.preuveRetenue(0)!!.fenetreId)
    }
}
