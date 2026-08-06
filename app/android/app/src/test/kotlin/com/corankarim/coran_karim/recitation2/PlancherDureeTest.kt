package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * LE PLANCHER DE DUREE COMPTE DES JETONS, PAS DE LA PAROLE.
 *
 * Cas REEL (2026-08-06, Al-Baqara, session live de l'utilisateur, build v79) :
 *     mot=42 "كَفَرُوا۟" -> definitif:rouge | gop=-5.33 forced=-5.34 free=-0.01
 *                            frames=1 INT obs=4 entendu="كَفَ"
 * Le flux brut porte le mot ENTIER, lu parfaitement par le modele aux largeurs
 * 4 s et 6 s (`▁إِنَّ ▁ٱلَّذِينَ ▁كَفَرُوا۟ ▁سَوَآءٌ`). Quatre fenetres l'ont vu, dont
 * une de 11,76 s ou les ONZE mots de la bande etaient interieurs -- ce n'est
 * donc ni le modele, ni le fenetrage, ni un bord de fenetre.
 *
 * CE QUE LE DICTIONNAIRE DIT : `كَفَرُوا۟` vaut UN SEUL jeton (piece 413,
 * `▁كَفَرُوا۟`) -- 184 mots sur 19 001 sont dans ce cas. Or
 * `AligneurForce.framesMinimales` derive le plancher de duree du NOMBRE DE
 * JETONS : un jeton => une frame => 80 ms. L'aligneur juge donc « couvert » un
 * mot de cinq lettres AVEC un madd auquel il n'a laisse que 80 ms, et
 * `entendu` -- qui est le decodage libre RESTREINT aux frames attribuees au
 * mot -- ne peut evidemment rendre qu'un fragment.
 *
 * Le nombre de jetons est une propriete du VOCABULAIRE, pas de la parole :
 * deux mots de meme longueur en ont 1 ou 6 selon que le tokeniseur les a
 * memorises. Remarque de l'utilisateur qui a mene au diagnostic : « l'alignement
 * connait la taille du mot, il ne teste pas la taille attendue » puis « avec le
 * tajwid encore, s'il etait en mode tajweed il va prolonger ».
 *
 * ── LE CORRECTIF « PLANCHER FONDE SUR LES LETTRES » EST REFUTE ─────────────
 *
 * L'idee etait de remplacer le comptage de jetons par une duree articulatoire
 * attendue (lettres + madd). MESURE AVANT ECRITURE, sur 906 observations de
 * mots juges CORRECTS (quatre sessions deterministes Al-Baqara) :
 *
 *     lettres   n     frames min   5e centile   mediane
 *        2     118        1            1           2
 *        3     178        1            1           2
 *        4     230        1            1           4
 *        5     155        1            1           3
 *        6     175        1            2           5
 *     rapport frames/lettre : 1er centile 0,20  5e 0,33  mediane 1,00
 *
 * A CHAQUE longueur, des mots parfaitement juges n'ont qu'UNE frame : le CTC
 * est « pique », il emet un jeton sur une frame et met du blanc autour. Un
 * plancher fonde sur les lettres, meme tres permissif, exclurait une part
 * importante de mots corrects -- il ferait plus de degats qu'il n'en repare.
 * L'hypothese est donc MORTE, et `frames=1` n'est PAS une anomalie en soi.
 *
 * CE QUI RESTE, ET QUI EST LA VRAIE CAUSE : a frames egales, un mot correct a
 * `gop = 0,00` et `كَفَرُوا۟` a `gop = -5,33`. Ce qui les separe n'est pas la
 * duree, c'est que la CIBLE impose une piece que le modele n'a pas produite
 * sur cet audio (cf. le second test). Et les deux mesures ci-dessous montrent
 * les deux echecs SYMETRIQUES : forcer la piece entiere quand le modele epelle
 * donne gop=-12 ; forcer l'epellation quand le modele emet la piece entiere
 * serait tout aussi faux. La seule forme correcte est de laisser l'aligneur
 * CHOISIR entre les deux decompositions -- ce qui touche le treillis CTC
 * lui-meme, et reste a faire.
 */
class PlancherDureeTest {

    /** Vocabulaire ou `kafarou` est UNE SEULE piece, comme dans le vrai
     *  modele, alors que ses voisins sont epeles lettre par lettre. */
    private fun vocabulaireAvecMotEntier(): List<String> {
        // Les LETTRES de `kafarou` doivent etre des pieces, sinon le mot n'est
        // pas decomposable et le graphe des ecritures n'a qu'un seul chemin --
        // le banc ne testerait alors rien du tout (piege paye en l'ecrivant).
        val base = Synthese.vocabulaire(
            listOf("inna", "aladhina", "sawaa", "kafarou"))
        return base + "▁kafarou"
    }

    private fun tokeniseur(pieces: List<String>): (String) -> IntArray {
        val parLettre = Synthese.tokeniseur(pieces)
        return { mot ->
            if (mot == "kafarou") intArrayOf(pieces.indexOf("▁kafarou"))
            else parLettre(mot)
        }
    }

    @Test
    fun `un mot en UN SEUL jeton n'a qu'une frame de plancher`() {
        val pieces = vocabulaireAvecMotEntier()
        val blank = pieces.size
        val tok = tokeniseur(pieces)
        val front = FauxFront(pieces)
        val aligneur = AligneurForce(pieces, blank)

        val mots = listOf("inna", "aladhina", "kafarou", "sawaa")
        // Le recitateur prononce TOUT, et `kafarou` dure autant que ses
        // voisins : 8 frames, soit 640 ms -- une duree realiste pour un mot de
        // cinq lettres portant un madd.
        val frames = ArrayList<Int>()
        for (m in mots) {
            val toks = tok(m)
            val parToken = if (toks.size == 1) 8 else 2
            for (tk in toks) repeat(parToken) { frames.add(tk) }
            repeat(3) { frames.add(blank) }
        }
        val pcm = FloatArray(frames.size * Horloge.ECH_PAR_FRAME)
        frames.forEachIndexed { i, id ->
            java.util.Arrays.fill(pcm, i * Horloge.ECH_PAR_FRAME,
                (i + 1) * Horloge.ECH_PAR_FRAME, Synthese.valeurPourId(id))
        }

        val res = aligneur.aligner(front.logprobs(pcm), mots.map(tok), 0)!!
        val m = res.mots[2]
        println("[mesure] kafarou : frames=${m.frames} gop=${m.gop} " +
            "forced=${m.forced} free=${m.free} couvert=${m.couvert} " +
            "entendu=\"${m.entendu}\"")
        for (x in res.mots) {
            println("[mesure]   mot ${x.index} frames=${x.frames} couvert=${x.couvert}")
        }

        // CE QUE LE TEST VERROUILLE AUJOURD'HUI : le mot est declare COUVERT
        // alors qu'il occupe une fraction de sa duree reelle. C'est le defaut,
        // pas le comportement souhaite -- ce test devra changer avec le
        // correctif, et c'est voulu : il documente l'etat de depart mesure.
        assertTrue(
            "le voisin epele doit avoir plus de frames que le mot entier " +
                "(c'est l'anomalie : ${res.mots[1].frames} contre ${m.frames})",
            res.mots[1].frames >= m.frames
        )
    }

    /** LE VRAI CAS : la cible force la piece ENTIERE, le modele EPELLE.
     *
     *  C'est ce que le device montre. Le mot est dans l'audio, le modele le lit
     *  parfaitement en decodage LIBRE -- mais il le rend en plusieurs pieces,
     *  pas avec la piece entiere que la cible lui impose. Le chemin force n'a
     *  alors aucun bon endroit ou poser ce jeton unique : Viterbi le colle sur
     *  UNE frame, et `entendu` (decodage libre restreint a cette frame) rend un
     *  fragment. Signature exacte du log : frames=1, free ~ 0, forced tres
     *  negatif.
     */
    @Test
    fun `cible en un jeton, audio epele -- le mot s'ecrase sur une frame`() {
        val pieces = vocabulaireAvecMotEntier()
        val blank = pieces.size
        val tokEntier = tokeniseur(pieces)
        val parLettre = Synthese.tokeniseur(pieces)
        val front = FauxFront(pieces)
        val aligneur = AligneurForce(pieces, blank)

        val mots = listOf("inna", "aladhina", "kafarou", "sawaa")
        // AUDIO : `kafarou` est EPELE (pieces lettre a lettre), comme le fait
        // le vrai modele. Les autres mots inchanges.
        val frames = ArrayList<Int>()
        for (m in mots) {
            for (tk in parLettre(m)) repeat(2) { frames.add(tk) }
            repeat(3) { frames.add(blank) }
        }
        val pcm = FloatArray(frames.size * Horloge.ECH_PAR_FRAME)
        frames.forEachIndexed { i, id ->
            java.util.Arrays.fill(pcm, i * Horloge.ECH_PAR_FRAME,
                (i + 1) * Horloge.ECH_PAR_FRAME, Synthese.valeurPourId(id))
        }

        // CIBLE : `kafarou` est demande comme UNE SEULE piece.
        val res = aligneur.aligner(front.logprobs(pcm), mots.map(tokEntier), 0)!!
        val m = res.mots[2]
        println("[mesure2] kafarou : frames=${m.frames} gop=${m.gop} " +
            "forced=${m.forced} free=${m.free} couvert=${m.couvert} " +
            "entendu=\"${m.entendu}\"")
        println("[mesure2] plancher exige pour ce mot : " +
            "${tokEntier("kafarou").size} frame(s) -- soit " +
            "${tokEntier("kafarou").size * 80} ms pour 7 lettres")
        assertTrue("reproduction attendue : le mot s'ecrase", m.frames <= 2)
        assertTrue("et il est pourtant declare COUVERT", m.couvert)
    }

    /** LE CORRECTIF : avec le TEXTE, l'aligneur explore toutes les ecritures.
     *
     *  Meme audio et meme cible que le test precedent -- le modele EPELLE, la
     *  tokenisation du dictionnaire donne la piece ENTIERE. Seule difference :
     *  `textesParMot` est fourni, donc l'aligneur aligne LE MOT et non une
     *  tokenisation figee (cf. AligneurForce.grapheEcritures).
     */
    @Test
    fun `avec le texte, l'ecriture epelee est retrouvee et le gop remonte`() {
        val pieces = vocabulaireAvecMotEntier()
        val blank = pieces.size
        val tokEntier = tokeniseur(pieces)
        val parLettre = Synthese.tokeniseur(pieces)
        val front = FauxFront(pieces)
        val aligneur = AligneurForce(pieces, blank)

        val mots = listOf("inna", "aladhina", "kafarou", "sawaa")
        val frames = ArrayList<Int>()
        for (m in mots) {
            for (tk in parLettre(m)) repeat(2) { frames.add(tk) }
            repeat(3) { frames.add(blank) }
        }
        val pcm = FloatArray(frames.size * Horloge.ECH_PAR_FRAME)
        frames.forEachIndexed { i, id ->
            java.util.Arrays.fill(pcm, i * Horloge.ECH_PAR_FRAME,
                (i + 1) * Horloge.ECH_PAR_FRAME, Synthese.valeurPourId(id))
        }

        val res = aligneur.aligner(
            front.logprobs(pcm), mots.map(tokEntier), 0,
            textesParMot = mots,
        )!!
        val m = res.mots[2]
        println("[correctif] kafarou : frames=${m.frames} gop=${m.gop} " +
            "forced=${m.forced} free=${m.free} entendu=\"${m.entendu}\"")
        assertTrue("le mot doit retrouver sa duree (etait 1), obtenu ${m.frames}",
            m.frames >= 6)
        assertTrue("le gop doit remonter (etait -11,99), obtenu ${m.gop}",
            m.gop > -0.5f)
    }
}
