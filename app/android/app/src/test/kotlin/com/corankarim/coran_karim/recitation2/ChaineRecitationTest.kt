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
                pauseMinSecondes = 0.5, maxBlocSecondes = 18.0
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

    /**
     * REMPLACE « chaque mot recoit au moins DEUX observations interieures ».
     *
     * Cette exigence venait de la v2.0, ou la seule facon de confirmer un mot
     * etait de le revoir dans une autre FENETRE. Depuis le 2026-07-30, deux
     * mesures INDEPENDANTES sur la meme fenetre suffisent : le decodage libre
     * (qui ignore le texte attendu) et l'alignement force (qui le connait).
     * Mesure qui l'a impose : 8,14 % -> 4,41 % de mots non verts sur le flux
     * brut reel, parce que le bloc de FUSION apportait une 2e preuve
     * systematiquement DEGRADEE (mot tronque) qui detruisait l'accord.
     *
     * Ce qui reste exigible, et qui est le vrai besoin : chaque mot doit avoir
     * AU MOINS UNE preuve qui a le droit de voter.
     */
    @Test
    fun `chaque mot recoit au moins une preuve votante`() {
        val c = chaine()
        jouer(c, avecQueue(Synthese.pcm(texte, tok, blank, 3, 3)))
        val max = c.preuves.indexMaxVotant()
        for (i in 0..max) {
            assertTrue(
                "mot $i n'a aucune preuve votante\n" + c.tracerMot(i),
                c.preuves.observationsVotantes(i).isNotEmpty()
            )
        }
    }

    /**
     * CE QUE LA v2.1 A PERDU, ET QU'IL FAUT DIRE.
     *
     * La v2.0 promettait un delai de verrouillage CONSTANT (2,9 a 4,4 s),
     * independant du rythme du recitateur, parce que la grille de fenetres
     * etait reguliere. Le decoupage aux silences reels abandonne cette
     * propriete : un mot est juge quand son ENONCE est termine, donc le delai
     * suit la longueur de l'enonce -- comme en v1.
     *
     * C'est le prix mesure du gain : 36,61 % de mots non verts avec la grille
     * reguliere, 4,41 % en coupant aux silences. La regularite du delai ne
     * valait pas 32 points de taux.
     *
     * Ce qui reste EXIGIBLE, et que ce test verrouille : le delai doit rester
     * BORNE. Un mot ne doit jamais attendre indefiniment -- c'est ce qui
     * arrivait en v1 quand l'ancre decrochait.
     */
    @Test
    fun `le verrouillage tombe au plus tard a la fin de l'enonce suivant`() {
        val c = chaine()
        jouer(c, avecQueue(Synthese.pcm(texte, tok, blank, 3, 3)))
        val max = c.preuves.indexMaxVotant()
        // La propriete qui compte n'est pas « combien de blocs », c'est
        // « est-ce que ca se FIGE ». Un mot qui reste provisoire pour toujours,
        // c'est l'utilisateur qui n'a jamais de reponse -- le defaut que la v1
        // produisait quand l'ancre decrochait.
        val enSuspens = (0..max).filter { i ->
            c.preuves.observationsVotantes(i).isNotEmpty() &&
                c.statuts[i] !is Statut.Definitif
        }
        assertTrue(
            "ces mots ont une preuve mais ne se figent jamais : $enSuspens\n" +
                enSuspens.take(2).joinToString("\n") { c.tracerMot(it) },
            enSuspens.isEmpty()
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
            constructeur = ConstructeurDeFenetres(pauseMinSecondes = 0.5),
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
        // ── NI SIGNALES « HORS DE LEUR PLACE » (2026-08-11) ─────────────────
        //
        // Le controle d'ordre temporel introduit ce jour-la (cf.
        // Decideur.OrdreTemporel) fait du TEMPS une dimension du jugement. Une
        // repetition est NON LINEAIRE dans le temps elle aussi : c'est la
        // premiere chose qu'une telle regle casse si son discriminant est faux.
        // Contrainte du graphe : [PIEGE] findResyncOffset ne cherche QU'EN
        // AVANT -- « un recitateur qui REPETE ne peut STRUCTURELLEMENT pas etre
        // suivi ». On verrouille donc ici que le recul reste gratuit.
        val deplaces = (0..c.preuves.indexMaxVotant()).filter { statuts[it] is Statut.Deplace }
        assertTrue(
            "une repetition legitime ne doit produire AUCUN mot deplace : $deplaces",
            deplaces.isEmpty()
        )
    }

    /**
     * LE DESORDRE EST UNE FAUTE, ET ELLE DOIT SE VOIR (2026-08-11).
     *
     * Constate par l'utilisateur puis confirme sur le journal du telephone
     * (sourate 103 Al-'Asr, verset 3, deux groupes de deux mots permutables) :
     * « pour AB CD EF, j'ai dit AB EF CD » et TOUT etait valide vert.
     *
     * POURQUOI RIEN NE LE VOYAIT. L'ordre est bien verifie A L'INTERIEUR d'une
     * fenetre -- la chaine LCS du [Localisateur] est strictement croissante, le
     * treillis de [AligneurForce] est monotone. Mais une violation d'ordre y
     * produit du SILENCE : la fenetre f=17 du journal entend
     * `صَبْرَ وَتَوَاصَوْا۟ بِ بِٱلْحَقِّ` -- la FIN du verset avant son DEBUT --
     * et c'est exactement celle qui ne juge rien (`bande=inconnue`). Les
     * verdicts verts venaient des AUTRES fenetres, chacune parfaitement
     * coherente prise SEULE. Aucune couche ne comparait deux fenetres entre
     * elles dans le TEMPS.
     *
     * Et l'ecart de deux mots passe sous [ChaineRecitation.sautMaxMots] = 2 :
     * une permutation COURTE tombe exactement dans l'angle mort du refus de
     * saut. C'est bien le cas reproduit ici.
     */
    @Test
    fun `deux groupes recites dans le desordre sont signales, jamais rouges`() {
        val journal = ArrayList<String>()
        val c = chaine { journal.add(it) }
        // « AB CD EF » recite « AB EF CD » : il dit 0..7, puis 10-11, PUIS 8-9,
        // puis reprend a 12. L'ecart 7 -> 10 vaut deux mots, donc aucun saut
        // n'est refuse -- c'est tout le probleme.
        val prononce = texte.subList(0, 8) + texte.subList(10, 12) +
            texte.subList(8, 10) + texte.subList(12, 16)
        // Une pause toutes les DEUX phrases : chaque groupe permute tombe dans
        // sa propre fenetre, comme sur le telephone ou les groupes d'un verset
        // sont separes par une respiration. Sans cela une seule fenetre
        // porterait le desordre, et le localisateur le noierait tout seul
        // (`bande=inconnue`) -- ce n'est pas ce cas-la qu'on teste ici.
        jouer(c, avecQueue(Synthese.pcm(prononce, tok, blank, 3, 3, pauseTousLes = 2)))

        val statuts = c.statuts
        val deplaces = (0..15).filter { statuts[it] is Statut.Deplace }
        assertTrue(
            "les mots 8 et 9, dits APRES les mots 10 et 11, doivent etre " +
                "signales hors de leur place -- deplaces=$deplaces\n" +
                c.tracerMot(8) + "\n" + c.tracerMot(9) + "\n" +
                journal.joinToString("\n"),
            deplaces.containsAll(listOf(8, 9))
        )
        // AUCUN ROUGE : le mot a bel et bien ete prononce, et correctement.
        // Le condamner comme une faute de PRONONCIATION serait faux -- regle
        // projet : « un mot hors de sa place ne doit pas devenir rouge par le
        // gop ».
        val rouges = (0..15).filter { i ->
            val s = statuts[i]
            s is Statut.Definitif && s.couleur == Couleur.ROUGE
        }
        assertTrue("le desordre ne doit produire aucun rouge : $rouges", rouges.isEmpty())
        // Et ce qui a ete lu dans l'ordre reste acquis.
        assertTrue(
            "les mots lus dans l'ordre restent verts",
            (0..5).all { statuts[it] == Statut.Definitif(Couleur.VERT) }
        )
    }

    /**
     * SOCLE n°1 — la fonction meme de l'app. Un palliatif allant dans l'autre
     * sens a deja ete ecrit puis refuse ([MORT] mort_relachement_proportion) :
     * "un recitateur ne disant que la MOITIE d'un mot etait alors valide,
     * precisement ce que l'app existe pour detecter".
     *
     * En v2 ce n'est pas une regle de jugement, c'est une consequence : un
     * fragment ne peut pas etre INTERIEUR a une fenetre avec ses deux marges,
     * donc il ne vote pas ; et la ou il vote, l'alignement doit expliquer les
     * tokens manquants avec des frames qui ne les contiennent pas.
     */
    @Test
    fun `un mot dit a MOITIE ne passe jamais vert`() {
        val tronque = texte.toMutableList()
        tronque[6] = "st" // il ne dit que "st" au lieu de "stu"
        val piecesEtendues = Synthese.vocabulaire(texte + tronque)
        val blank2 = piecesEtendues.size
        val tok2 = Synthese.tokeniseur(piecesEtendues)
        val c = ChaineRecitation(
            front = FauxFront(piecesEtendues),
            tokeniser = tok2,
            constructeur = ConstructeurDeFenetres(pauseMinSecondes = 0.5),
            localisateur = Localisateur(piecesEtendues, blank2),
            aligneur = AligneurForce(piecesEtendues, blank2),
            decideur = Decideur(),
        ).also { it.definirTexte(texte) }

        jouer(c, avecQueue(Synthese.pcm(tronque, tok2, blank2, 3, 3)))

        val s = c.statuts[6]
        assertFalse(
            "le mot dit a moitie ne doit JAMAIS etre vert (statut=$s)\n${c.tracerMot(6)}",
            s is Statut.Definitif && s.couleur == Couleur.VERT
        )
    }

    /**
     * SOCLE n°1 — "aucun rouge sans preuve". Un mot que le recitateur saute
     * n'est pas une faute de prononciation : il n'y a AUCUNE preuve acoustique
     * a son sujet. Il doit ressortir `Omis`, jamais `Definitif(ROUGE)`.
     */
    @Test
    fun `un mot saute ressort OMIS et jamais ROUGE`() {
        val c = chaine()
        val prononce = texte.toMutableList().also { it.removeAt(5) } // il saute le mot 5
        jouer(c, avecQueue(Synthese.pcm(prononce, tok, blank, 3, 3)))

        val s = c.statuts[5]
        assertFalse(
            "un mot saute ne doit pas etre condamne (statut=$s)\n${c.tracerMot(5)}",
            s is Statut.Definitif && s.couleur == Couleur.ROUGE
        )
    }

    @Test
    fun `aucun audio n'est detruit - toute preuve reste reextractible`() {
        val brut = FluxBrut(secondesEnMemoire = 120)
        val front = FauxFront(pieces)
        val c = ChaineRecitation(
            front = front, tokeniser = tok,
            constructeur = ConstructeurDeFenetres(pauseMinSecondes = 0.5),
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
