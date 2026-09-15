package com.corankarim.coran_karim.recitation2

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class VoteFenetresFluxTest {
    @Test fun `le decideur actif detecte la substitution et suit le flux jusqu au bout`() {
        val mots = listOf("abc", "def", "ghi", "jkl", "mno", "pqr", "stu", "vwx",
            "yza", "bcd", "efg", "hij", "klm", "nop", "qrs", "tuv")
        val pieces = Synthese.vocabulaire(mots + "vwy")
        val tok = Synthese.tokeniseur(pieces)
        val c = ChaineRecitation(front = FauxFront(pieces), tokeniser = tok,
            decideur = Decideur(votePondere = true),
            constructeur = ConstructeurDeFenetres(pauseMinSecondes = .5))
        c.definirTexte(mots)
        val pcm = Synthese.pcm(mots.toMutableList().also { it[7] = "vwy" }, tok, pieces.size, 3, 3) +
            Synthese.silence(3.5)
        var verdictPendant = false
        for (i in pcm.indices step Horloge.ECH_PAR_FRAME) {
            c.alimenter(pcm.copyOfRange(i, minOf(i + Horloge.ECH_PAR_FRAME, pcm.size)))
            if (c.statuts[7] == Statut.Provisoire(Couleur.ROUGE) ||
                c.statuts[7] == Statut.Definitif(Couleur.ROUGE)) verdictPendant = true
        }
        c.terminer()
        assertTrue("La faute doit etre signalee pendant le flux\n" + c.tracerMot(7) +
            "\n" + VoteFenetres.calculer(c.preuves.observationsPourJugement(7)), verdictPendant)
        assertEquals(c.tracerMot(7), Statut.Definitif(Couleur.ROUGE), c.statuts[7])
        assertTrue("L'ancre doit atteindre la fin", c.preuves.indexMaxVotant() >= 14)
        for (i in 1..14) if (i != 7) {
            assertTrue(c.tracerMot(i), c.statuts[i] == Statut.Definitif(Couleur.VERT) ||
                c.statuts[i] == Statut.Provisoire(Couleur.VERT))
        }
        assertEquals("vwy", c.observationRetenue(7)!!.entendu)
    }

    @Test fun `une substitution dont l aligneur ne voit qu un fragment reste du doute`() {
        val mots = listOf("abc", "def", "ghi", "jkl", "mno", "pqr", "stu", "vwx",
            "yza", "bcd", "efg", "hij", "klm", "nop", "qrs", "tuv")
        val pieces = Synthese.vocabulaire(mots + "zzz")
        val tok = Synthese.tokeniseur(pieces)
        val c = ChaineRecitation(front = FauxFront(pieces), tokeniser = tok,
            decideur = Decideur(votePondere = true),
            constructeur = ConstructeurDeFenetres(pauseMinSecondes = .5))
        c.definirTexte(mots)
        val pcm = Synthese.pcm(mots.toMutableList().also { it[7] = "zzz" }, tok, pieces.size, 3, 3) +
            Synthese.silence(3.5)
        for (i in pcm.indices step Horloge.ECH_PAR_FRAME) {
            c.alimenter(pcm.copyOfRange(i, minOf(i + Horloge.ECH_PAR_FRAME, pcm.size)))
        }
        c.terminer()
        // Mesure du 15/09 : la DP ne donne que le fragment z du mot libre zz.
        // Transformer ce fragment en vote ferait reapparaitre les faux rouges.
        assertEquals(c.tracerMot(7), Statut.Provisoire(Couleur.ORANGE), c.statuts[7])
        assertTrue(VoteFenetres.calculer(c.preuves.observationsPourJugement(7))
            .exclusions.containsKey("fragment_alignement"))
        assertTrue(c.preuves.indexMaxVotant() >= 14)
    }

    @Test fun `instrumentation conserve tous les statuts et trace aussi apres verrouillage`() {
        val mots = listOf("abc", "def", "ghi", "jkl", "mno", "pqr", "stu", "vwx",
            "yza", "bcd", "efg", "hij", "klm", "nop", "qrs", "tuv")
        val pieces = Synthese.vocabulaire(mots + "zzz")
        val tok = Synthese.tokeniseur(pieces)
        val journal = ArrayList<String>()
        fun chaine(observer: Boolean) = ChaineRecitation(front = FauxFront(pieces), tokeniser = tok,
            constructeur = ConstructeurDeFenetres(pauseMinSecondes = .5),
            observerVoteFenetres = observer, journal = { if (observer) journal.add(it) }
        ).also { it.definirTexte(mots) }
        val reference = chaine(false)
        val mesure = chaine(true)
        val pcm = Synthese.pcm(mots.toMutableList().also { it[7] = "zzz" }, tok, pieces.size, 3, 3) +
            Synthese.silence(3.5)
        var observationsApresVerrouillage = 0
        for (i in pcm.indices step Horloge.ECH_PAR_FRAME) {
            val bloc = pcm.copyOfRange(i, minOf(i + Horloge.ECH_PAR_FRAME, pcm.size))
            val figesAvant = mesure.statuts.filterValues { it is Statut.Definitif }.keys.toSet()
            val tracesAvant = journal.size
            reference.alimenter(bloc)
            mesure.alimenter(bloc)
            assertEquals("statuts apres $i echantillons", reference.statuts, mesure.statuts)
            observationsApresVerrouillage += journal.drop(tracesAvant).filter {
                it.startsWith("[vote-observation]")
            }.count { JSONObject(it.substringAfter("] ")).getInt("mot") in figesAvant }
        }
        reference.terminer(); mesure.terminer()
        assertEquals(reference.statuts, mesure.statuts)
        assertEquals(reference.preuves.indexMaxVotant(), mesure.preuves.indexMaxVotant())
        assertEquals(reference.preuves.total(), mesure.preuves.total())
        val observations = journal.filter { it.startsWith("[vote-observation]") }
        val resultats = journal.filter { it.startsWith("[vote-resultat]") }
        assertEquals(mesure.preuves.total(), observations.size)
        assertEquals(observations.size, resultats.size)
        assertTrue("Les reanalyses apres verdict doivent aussi etre visibles", observationsApresVerrouillage > 0)
        assertTrue(observations.any { JSONObject(it.substringAfter("] ")).optDouble("poids", 0.0) > 0.0 })
        for (r in resultats) assertTrue(JSONObject(r.substringAfter("] ")).isNull("statut_app"))
    }
}
