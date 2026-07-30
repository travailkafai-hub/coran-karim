package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Couches E et G : ce qui est mesure, et ce qui a le droit de decider.
 *
 * Les deux regles verrouillees ici sont celles dont la violation a produit les
 * defauts les plus chers de la v1 :
 *  - un mot qui touche un bord de fenetre ne VOTE PAS ([PIEGE] verrou_sur_apercu,
 *    "la majorite des mots sont verrouilles sur des apercus, donc sur un audio
 *    INCOMPLET") ;
 *  - un verdict definitif ne change plus jamais, et il exige K=2 fenetres
 *    DISTINCTES d'accord (stable-prefix rule).
 */
class AligneurEtDecideurTest {

    private val mots = listOf("abc", "def", "ghi")
    private val pieces = Synthese.vocabulaire(mots)
    private val blank = pieces.size
    private val tok = Synthese.tokeniseur(pieces)
    private val front = FauxFront(pieces)
    private val aligneur = AligneurForce(pieces, blank)

    private fun logprobs(prononces: List<String>, framesParToken: Int = 3, framesBlanc: Int = 3) =
        front.logprobs(Synthese.pcm(prononces, tok, blank, framesParToken, framesBlanc))

    @Test
    fun `un mot bien prononce au centre a un gop proche de zero et est interieur`() {
        val lp = logprobs(mots)
        val res = aligneur.aligner(lp, mots.map(tok), 0)!!
        val milieu = res.mots[1]
        assertTrue("le mot du milieu doit etre interieur", milieu.interieur)
        assertTrue("gop attendu proche de 0, obtenu ${milieu.gop}", milieu.gop > -0.1f)
        assertEquals("def", milieu.entendu.trim())
    }

    @Test
    fun `le dernier mot touche le bord droit - il n'est PAS interieur`() {
        val lp = logprobs(mots)
        val res = aligneur.aligner(lp, mots.map(tok), 0)!!
        assertFalse(
            "un mot colle au bord droit n'a pas le contexte du modele causal " +
                "(lookahead ${Horloge.LOOKAHEAD_FRAMES} frames)",
            res.mots.last().interieur
        )
    }

    @Test
    fun `un mot mal prononce a un gop tres negatif`() {
        // Le recitateur dit "abc xyz ghi" alors que le texte attendu est "abc def ghi".
        val motsFaux = listOf("abc", "aaa", "ghi")
        val piecesEtendues = Synthese.vocabulaire(mots + motsFaux)
        val blank2 = piecesEtendues.size
        val tok2 = Synthese.tokeniseur(piecesEtendues)
        val front2 = FauxFront(piecesEtendues)
        val al2 = AligneurForce(piecesEtendues, blank2)

        val lp = front2.logprobs(Synthese.pcm(motsFaux, tok2, blank2, 3, 3))
        val res = al2.aligner(lp, mots.map(tok2), 0)!!
        val juge = res.mots[1]
        assertTrue("le mot substitue doit s'effondrer, gop=${juge.gop}", juge.gop < -2f)
        assertTrue("les mots corrects restent bons", res.mots[0].gop > -0.5f)
    }

    @Test
    fun `aucun verdict sans observation interieure`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        registre.ajouter(obs(fenetre = 1, mot = 0, gop = -0.01f, interieur = false))
        registre.ajouter(obs(fenetre = 2, mot = 0, gop = -0.01f, interieur = false))
        val s = decideur.statuts(registre, 1)
        assertTrue("un mot vu seulement au bord reste INCONNU", s[0] == null)
    }

    @Test
    fun `il faut DEUX fenetres distinctes d'accord pour verrouiller`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()

        registre.ajouter(obs(1, 0, -0.01f, true))
        assertTrue(decideur.statuts(registre, 1)[0] is Statut.Provisoire)

        // Deux observations de la MEME fenetre ne se confirment pas l'une l'autre.
        registre.ajouter(obs(1, 0, -0.01f, true))
        assertTrue(
            "deux preuves de la meme fenetre = une seule preuve",
            decideur.statuts(registre, 1)[0] is Statut.Provisoire
        )

        registre.ajouter(obs(2, 0, -0.01f, true))
        val s = decideur.statuts(registre, 1)[0]
        assertTrue("deux fenetres distinctes d'accord => definitif", s is Statut.Definitif)
        assertEquals(Couleur.VERT, (s as Statut.Definitif).couleur)
    }

    @Test
    fun `un verdict definitif ne change plus jamais`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        registre.ajouter(obs(1, 0, -0.01f, true))
        registre.ajouter(obs(2, 0, -0.01f, true))
        assertTrue(decideur.statuts(registre, 1)[0] is Statut.Definitif)

        // Une observation ulterieure catastrophique ne doit PAS defaire le verdict.
        registre.ajouter(obs(3, 0, -9f, true))
        val s = decideur.statuts(registre, 1)[0] as Statut.Definitif
        assertEquals("monotonie de la decision", Couleur.VERT, s.couleur)
    }

    @Test
    fun `des verdicts qui ne convergent pas restent provisoires`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        registre.ajouter(obs(1, 0, -0.01f, true))   // vert
        registre.ajouter(obs(2, 0, -3f, true))      // rouge
        registre.ajouter(obs(3, 0, -0.01f, true))   // vert
        assertTrue(
            "sans accord sur K passes, on n'a pas le droit de figer",
            decideur.statuts(registre, 1)[0] is Statut.Provisoire
        )
    }

    @Test
    fun `un mot saute devient OMIS sur preuve positive, jamais rouge`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        // Le mot 0 n'est jamais observe ; les mots 1,2,3 sont definitifs.
        for (m in 1..3) {
            registre.ajouter(obs(1, m, -0.01f, true))
            registre.ajouter(obs(2, m, -0.01f, true))
        }
        val s = decideur.statuts(registre, 4)
        assertTrue("le mot saute est OMIS", s[0] is Statut.Omis)
        assertFalse("OMIS n'est pas un rouge", s[0] is Statut.Definitif)
    }

    private fun obs(fenetre: Long, mot: Int, gop: Float, interieur: Boolean) =
        RegistreDePreuves.Observation(
            fenetreId = fenetre, motIndex = mot, gop = gop, forced = gop, free = 0f,
            entendu = "x", frames = 5, interieur = interieur, couvert = true,
            fenetrePleine = true, debutAbs = 0, finAbs = 100,
        )
}
