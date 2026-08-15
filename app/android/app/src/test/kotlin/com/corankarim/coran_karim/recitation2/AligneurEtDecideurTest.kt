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

    // ── ORDRE DE LECTURE : « dit, mais pas a sa place » (2026-08-11) ────────
    //
    // DEFAUT FERME. Le recitateur dit les groupes d'un verset dans le DESORDRE
    // (« pour AB CD EF, j'ai dit AB EF CD ») et TOUT ressortait vert -- alors
    // que reciter le Coran dans le desordre est une vraie faute, que l'app
    // existe pour detecter. Journal du telephone, sourate 103 verset 3 : la
    // fenetre qui entend la FIN du verset avant son DEBUT est celle qui ne juge
    // rien (`bande=inconnue`), et les mots ressortent `definitif:vert` par les
    // AUTRES fenetres, sans un seul `SAUT REFUSE`.
    //
    // Les deux tests qui suivent vont PAR PAIRE : le premier prouve que
    // l'inversion est signalee, le second qu'une repetition legitime ne l'est
    // pas. Pris seul, chacun se satisfait d'une regle idiote (tout signaler /
    // ne rien signaler) -- c'est leur conjonction qui prouve le discriminant.

    /**
     * « AB CD EF » recite « AB EF CD ».
     *
     * Les temps sont ceux de l'AUDIO (`debutAbs`/`finAbs`), pas ceux des
     * fenetres : c'est toute la difference. Les mots 4 et 5 sont prononces
     * AVANT les mots 2 et 3, et ces derniers n'ont aucune lecture anterieure
     * qui les aurait mis a leur place.
     */
    @Test
    fun `deux groupes inverses -- le groupe dit trop tard est signale DEPLACE`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        // Le recitateur dit AB (0,1), puis EF (4,5), puis CD (2,3).
        // Deux fenetres par groupe : c'est le chemin normal de verrouillage.
        fun groupe(f0: Long, mots: IntRange, t0: Long) {
            for ((n, m) in mots.withIndex()) {
                val d = t0 + n * 100
                registre.ajouter(obs(f0, m, -0.01f, true, d, d + 90))
                registre.ajouter(obs(f0 + 1, m, -0.01f, true, d, d + 90))
            }
        }
        groupe(1, 0..1, 0)
        decideur.statuts(registre, 6)
        groupe(3, 4..5, 1000)
        decideur.statuts(registre, 6)
        groupe(5, 2..3, 2000)
        val s = decideur.statuts(registre, 6)

        assertTrue("le mot 2, dit apres le mot 4, est hors de sa place : ${s[2]}",
            s[2] is Statut.Deplace)
        assertTrue("idem pour le mot 3 : ${s[3]}", s[3] is Statut.Deplace)
        // ── LES DEUX MOITIES, ET PLUS UNE SEULE (2026-08-14) ────────────────
        //
        // AVANT, cette assertion attendait VERT pour 4 et 5 : « ce qui a ete lu
        // dans l'ordre reste acquis ». C'etait faux, et une session live l'a
        // montre (Al-'Asr, deux mots inverses volontairement) : sur une
        // inversion, exactement UN mot sur deux etait signale -- celui dit trop
        // TARD -- pendant que celui dit trop TOT restait vert. Constat
        // utilisateur : « les mots inverses se mettent en vert sans se soucier
        // de l'ordre ».
        //
        // EF n'a pas ete « lu dans l'ordre » : ce groupe a ete dit AVANT CD,
        // qui le precede dans le texte. Il participe donc a l'inversion au meme
        // titre, et la regle miroir (`enAvance`) le signale desormais.
        for (i in listOf(4, 5)) {
            assertTrue("le mot $i a ete dit AVANT les mots 2-3 qui le precedent" +
                " dans le texte : ${s[i]}", s[i] is Statut.Deplace)
        }
        // Ce qui a VRAIMENT ete lu a sa place reste acquis : on ne repeint pas
        // toute la sourate parce qu'un groupe a bouge.
        for (i in listOf(0, 1)) {
            assertEquals("le mot $i a ete dit a sa place",
                Statut.Definitif(Couleur.VERT), s[i])
        }
        // ET SURTOUT : jamais rouge. Le mot a bien ete prononce -- l'accuser
        // d'une faute de PRONONCIATION serait faux (regle projet : « un mot
        // hors de sa place ne doit pas devenir rouge par le gop »).
        assertFalse("DEPLACE n'est pas une couleur", s[2] is Statut.Definitif)
    }

    /**
     * LE CAS REEL QUI A MOTIVE LA SYMETRIE (session live Al-'Asr, 2026-08-14).
     *
     * L'utilisateur inverse DEUX mots d'un verset, et le second est le DERNIER
     * mot du texte -- la ou l'ancienne regle etait structurellement aveugle :
     * `finApres` y vaut toujours ABSENT, il n'existe aucun mot posterieur a
     * comparer. Mesure du jour :
     *     mot=15 "بِٱلْحَقِّ"  -> deplace         (vu)
     *     mot=17 "بِٱلصَّبْرِ" -> definitif:vert  (INVISIBLE)
     *
     * Texte attendu : ... 14 15 16 17. Recite : 14, 17, 16, 15.
     */
    @Test
    fun `inversion de paire -- les DEUX mots sont signales, dernier mot compris`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        // Ordre de PRONONCIATION : 14 puis 17 puis 16 puis 15.
        val prononce = listOf(14 to 0L, 17 to 100L, 16 to 200L, 15 to 300L)
        for ((mot, t) in prononce) {
            registre.ajouter(obs(1, mot, -0.01f, true, t, t + 90))
            registre.ajouter(obs(2, mot, -0.01f, true, t, t + 90))
        }
        val s = decideur.statuts(registre, 18)

        assertTrue("le mot 15, dit APRES le 17 qui le suit : ${s[15]}",
            s[15] is Statut.Deplace)
        assertTrue("le mot 17, DERNIER du texte, dit AVANT le 15 qui le " +
            "precede -- c'est le cas que l'ancienne regle ne pouvait pas " +
            "voir : ${s[17]}", s[17] is Statut.Deplace)
        // 14 a bien ete dit en premier, et 16 est entre les deux mots inverses
        // sans avoir bouge lui-meme : ni l'un ni l'autre n'a participe.
        assertEquals("le mot 14 a ete dit a sa place",
            Statut.Definitif(Couleur.VERT), s[14])
        // Et jamais rouge : le recitateur a PRONONCE ces mots, il les a mal
        // places. Les accuser d'une faute de prononciation serait faux.
        assertFalse("un mot deplace n'est pas une couleur", s[15] is Statut.Definitif)
        assertFalse("un mot deplace n'est pas une couleur", s[17] is Statut.Definitif)
    }

    /**
     * Le RECITATEUR QUI REPETE ne doit rien recevoir -- meme quand le mot repete
     * n'avait PAS pu voter lors de son premier passage.
     *
     * C'est le cas limite du discriminant, et celui qui casserait la regle si
     * elle se contentait de « l'audio du mot i doit preceder celui du mot i+1 » :
     * une repetition est elle aussi NON LINEAIRE dans le temps. Ici le mot 4 n'a
     * ete vu qu'au BORD d'une fenetre pendant la lecture en place (donc sans
     * droit de vote, cf. `observationsVotantes`), puis correctement lors de la
     * repetition -- ses seules preuves VOTANTES sont donc posterieures a celles
     * du mot 5. Ce qui le disculpe est l'observation de bord : le mot etait bien
     * la, a sa place, au premier passage.
     */
    @Test
    fun `une repetition legitime n'est jamais signalee DEPLACE`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        // Passage en place : 0..5 dans l'ordre. Le mot 4 n'est vu qu'au bord.
        for (m in 0..5) {
            val d = m * 100L
            val auBord = m == 4
            registre.ajouter(obs(1, m, -0.01f, !auBord, d, d + 90))
            if (!auBord) registre.ajouter(obs(2, m, -0.01f, true, d, d + 90))
        }
        decideur.statuts(registre, 6)
        // Il repete 3..5, dans leur ORDRE INTERNE -- le cas AUTORISE.
        for ((n, m) in (3..5).withIndex()) {
            val d = 1000L + n * 100
            registre.ajouter(obs(3, m, -0.01f, true, d, d + 90))
            registre.ajouter(obs(4, m, -0.01f, true, d, d + 90))
        }
        val s = decideur.statuts(registre, 6)

        assertTrue(
            "aucun mot ne doit etre DEPLACE par une repetition : " +
                (0..5).filter { s[it] is Statut.Deplace },
            (0..5).none { s[it] is Statut.Deplace }
        )
        assertEquals(
            "le mot repete se juge normalement une fois qu'il a pu voter",
            Statut.Definitif(Couleur.VERT), s[4]
        )
    }

    /** Le controle d'ordre ne doit pas se declencher sur des mots CONTIGUS :
     *  le CTC est peaky et deux mots voisins se touchent a la frame pres. */
    @Test
    fun `une lecture lineaire ne produit aucun DEPLACE`() {
        val registre = RegistreDePreuves()
        val decideur = Decideur()
        for (m in 0..5) {
            val d = m * 100L
            registre.ajouter(obs(1, m, -0.01f, true, d, d + 100)) // fin == debut du suivant
            registre.ajouter(obs(2, m, -0.01f, true, d, d + 100))
        }
        val s = decideur.statuts(registre, 6)
        assertTrue("aucun DEPLACE sur une lecture lineaire",
            (0..5).none { s[it] is Statut.Deplace })
    }

    private fun obs(
        fenetre: Long, mot: Int, gop: Float, interieur: Boolean,
        debutAbs: Long = 0, finAbs: Long = 100,
    ) =
        RegistreDePreuves.Observation(
            fenetreId = fenetre, motIndex = mot, gop = gop, forced = gop, free = 0f,
            entendu = "x", frames = 5, interieur = interieur, couvert = true,
            fenetrePleine = true, debutAbs = debutAbs, finAbs = finAbs,
        )
}
