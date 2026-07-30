package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BANC 2 — la chaine complete, bout en bout, sans device et sans ONNX.
 *
 * Il repond aux questions que la v1 ne savait pas se poser hors device :
 *  - chaque mot recoit-il au moins K observations INTERIEURES ? (c'est la
 *    condition d'existence du verrouillage par prefixe stable) ;
 *  - le calendrier des verdicts est-il CONSTANT, ou depend-il de l'endroit de
 *    la session ? (en v1 il dependait de la longueur du segment : mesure
 *    `VALIDATION retard=10435ms`) ;
 *  - un recitateur qui REPETE est-il suivi ? Le banc v1 rejouait un audio
 *    lineaire et ne pouvait STRUCTURELLEMENT pas produire ce cas
 *    ([PIEGE] resync_avant_seulement). Ici on le construit.
 */
class ChaineRecitationTest {

    private val texte = listOf(
        "abc", "def", "ghi", "jkl", "mno", "pqr", "stu", "vwx",
        "yza", "bcd", "efg", "hij", "klm", "nop", "qrs", "tuv",
    )
    private val pieces = Synthese.vocabulaire(texte)
    private val blank = pieces.size
    private val tok = Synthese.tokeniseur(pieces)

    private fun chaine(journal: ((String) -> Unit)? = null): ChaineRecitation {
        val front = FauxFront(pieces)
        return ChaineRecitation(
            front = front,
            tokeniser = tok,
            constructeur = ConstructeurDeFenetres(
                fenetreSecondes = 6.0, pasSecondes = 1.5, fenetreMinSecondes = 2.0
            ),
            localisateur = Localisateur(pieces, blank),
            aligneur = AligneurForce(pieces, blank),
            decideur = Decideur(),
            journal = journal,
        ).also { it.definirTexte(texte) }
    }

    /**
     * La capture ne s'arrete pas au dernier mot : le micro tourne encore.
     * C'est indispensable — le modele causal exige 1,04 s d'audio POSTERIEUR
     * pour juger une frame, donc le dernier mot d'une recitation n'est jugeable
     * qu'une fois ce silence capte (defaut trouve par ce banc le 2026-07-30).
     */
    private fun avecQueue(pcm: FloatArray): FloatArray = pcm + Synthese.silence(3.5)

    /** Alimente par blocs de 80 ms, comme le vrai transport. */
    private fun jouer(c: ChaineRecitation, pcm: FloatArray): List<ChaineRecitation.Changement> {
        val tous = ArrayList<ChaineRecitation.Changement>()
        var i = 0
        while (i < pcm.size) {
            val fin = minOf(i + Horloge.ECH_PAR_FRAME, pcm.size)
            tous.addAll(c.alimenter(pcm.copyOfRange(i, fin)))
            i = fin
        }
        tous.addAll(c.terminer()) // fin de session : derniere analyse de la queue
        return tous
    }

    @Test
    fun `recitation propre - tous les mots sont juges verts et definitifs`() {
        val c = chaine()
        val pcm = Synthese.pcm(texte, tok, blank, framesParToken = 3, framesBlanc = 3)
        jouer(c, avecQueue(pcm))

        var definitifsVerts = 0
        var nonVerts = 0
        // Denominateur honnete : jusqu'au dernier mot ayant recu une preuve
        // votante (compter sur les mots JUGES ferait sortir du calcul tout mot
        // jamais observe -- erreur de methode deja commise).
        val max = c.preuves.indexMaxVotant()
        assertTrue("la chaine doit avoir suivi la recitation (max=$max)", max >= texte.size - 3)

        val statuts = c.statuts
        for (i in 0..max) {
            when (val s = statuts[i]) {
                is Statut.Definitif -> if (s.couleur == Couleur.VERT) definitifsVerts++ else nonVerts++
                else -> nonVerts++
            }
        }
        assertEquals(
            "aucun mot non vert attendu sur une recitation propre (${c.tracerMot(0)})",
            0, nonVerts
        )
        assertTrue(definitifsVerts >= texte.size - 3)
    }

    @Test
    fun `chaque mot recoit au moins deux observations INTERIEURES`() {
        val c = chaine()
        jouer(c, avecQueue(Synthese.pcm(texte, tok, blank, 3, 3)))
        val max = c.preuves.indexMaxVotant()
        for (i in 0..max) {
            val n = c.preuves.observationsVotantes(i).map { it.fenetreId }.toSet().size
            assertTrue(
                "mot $i : $n fenetre(s) interieure(s), il en faut >= 2 pour verrouiller\n" +
                    c.tracerMot(i),
                n >= 2
            )
        }
    }

    @Test
    fun `le calendrier de verrouillage est CONSTANT le long de la session`() {
        // On mesure, pour chaque mot, le nombre de fenetres ecoulees entre sa
        // premiere observation interieure et son verrouillage. En v1 ce delai
        // dependait de la longueur du segment ; ici il ne doit dependre de rien.
        val c = chaine()
        jouer(c, avecQueue(Synthese.pcm(texte, tok, blank, 3, 3)))
        val max = c.preuves.indexMaxVotant()

        val delais = ArrayList<Long>()
        for (i in 0..max) {
            val v = c.preuves.observationsVotantes(i)
            if (v.size < 2) continue
            delais.add(v[1].fenetreId - v[0].fenetreId)
        }
        assertTrue(delais.isNotEmpty())
        assertEquals(
            "le verrouillage doit tomber a un pas constant apres la 1re preuve, " +
                "delais observes = ${delais.distinct()}",
            1, delais.distinct().size
        )
    }

    @Test
    fun `un mot substitue est le SEUL a ne pas etre vert`() {
        val fautif = texte.toMutableList()
        fautif[7] = "zzz" // le recitateur dit autre chose au mot 7
        val piecesEtendues = Synthese.vocabulaire(texte + fautif)
        val blank2 = piecesEtendues.size
        val tok2 = Synthese.tokeniseur(piecesEtendues)
        val c = ChaineRecitation(
            front = FauxFront(piecesEtendues),
            tokeniser = tok2,
            constructeur = ConstructeurDeFenetres(6.0, 1.5, 2.0),
            localisateur = Localisateur(piecesEtendues, blank2),
            aligneur = AligneurForce(piecesEtendues, blank2),
            decideur = Decideur(),
        ).also { it.definirTexte(texte) }

        jouer(c, avecQueue(Synthese.pcm(fautif, tok2, blank2, 3, 3)))

        val statuts = c.statuts
        val nonVerts = (0..c.preuves.indexMaxVotant()).filter { i ->
            val s = statuts[i]
            !(s is Statut.Definitif && s.couleur == Couleur.VERT)
        }
        assertTrue(
            "le mot 7 doit etre signale, non-verts = $nonVerts\n${c.tracerMot(7)}",
            nonVerts.contains(7)
        )
        assertTrue(
            "aucun faux positif attendu ailleurs, non-verts = $nonVerts\n${c.tracerMot(8)}",
            nonVerts.all { it == 7 || it > c.preuves.indexMaxVotant() - 2 }
        )
    }

    @Test
    fun `un recitateur qui REPETE est suivi - cas impossible a produire sur le banc v1`() {
        val journal = ArrayList<String>()
        val c = chaine { journal.add(it) }
        // Il recite 0..9, puis REPREND a partir du mot 5.
        val prononce = texte.subList(0, 10) + texte.subList(5, 12)
        jouer(c, avecQueue(Synthese.pcm(prononce, tok, blank, 3, 3)))

        assertTrue(
            "la localisation doit avoir accepte un RECUL (v1 ne cherchait qu'en avant)\n" +
                journal.joinToString("\n"),
            journal.any { it.contains("RECUL") }
        )
        // Et surtout : les mots repetes ne doivent pas etre condamnes.
        val statuts = c.statuts
        val rouges = (5..9).filter { i ->
            val s = statuts[i]
            s is Statut.Definitif && s.couleur == Couleur.ROUGE
        }
        assertTrue("aucun mot repete ne doit devenir rouge, rouges = $rouges", rouges.isEmpty())
    }

    @Test
    fun `aucun audio n'est detruit - toute preuve reste reextractible`() {
        val brut = FluxBrut(secondesEnMemoire = 120)
        val front = FauxFront(pieces)
        val c = ChaineRecitation(
            front = front, tokeniser = tok,
            constructeur = ConstructeurDeFenetres(6.0, 1.5, 2.0),
            localisateur = Localisateur(pieces, blank),
            aligneur = AligneurForce(pieces, blank),
            decideur = Decideur(), fluxBrut = brut,
        ).also { it.definirTexte(texte) }

        val pcm = avecQueue(Synthese.pcm(texte, tok, blank, 3, 3))
        jouer(c, pcm)

        assertEquals("tout l'audio recu est dans le flux brut", pcm.size.toLong(), brut.total)
        var verifiees = 0
        for (i in 0..c.preuves.indexMaxVotant()) {
            for (o in c.preuves.observationsVotantes(i)) {
                assertTrue("position brute manquante pour le mot $i", o.debutAbs >= 0)
                val audio = brut.extraire(o.debutAbs, o.finAbs + Horloge.ECH_PAR_FRAME)
                assertFalse("la preuve du mot $i doit etre reextractible", audio == null)
                verifiees++
            }
        }
        assertTrue(verifiees > 0)
    }
}
