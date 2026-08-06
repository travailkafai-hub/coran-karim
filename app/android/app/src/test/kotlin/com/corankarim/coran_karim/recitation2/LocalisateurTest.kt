package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * L'AMBIGUITE D'UN PASSAGE QUI FIGURE DEUX FOIS DANS LA SOURATE.
 *
 * Cas REEL, mesure sur device le 2026-08-06 (Al-Ma'un, sourate 107, session
 * NORMALE, build v70). Le recitateur dit `ٱلَّذِينَ هُمْ يُرَآءُونَ` -- les mots
 * 24-26. Mais `ٱلَّذِينَ هُمْ` figure AUSSI aux mots 19-20. Deux alignements
 * expliquaient l'audio avec le meme nombre de correspondances (5), et la
 * marche arriere de la LCS prenait le plus petit index :
 *
 *     f=20/21/25  RECUL vers le mot 19 -- « le recitateur repete »
 *     f=22/24/32  SAUT REFUSE : trou de 3 mots apres le mot 23 (attestes=[27, 28])
 *
 * Consequence : ancre figee au mot 23, et les CINQ derniers mots de la sourate
 * jamais juges, alors que le flux brut les porte nettement. Meme signature sur
 * les trois recitations de la session.
 *
 * Ce test reproduit exactement cette configuration avec le banc synthetique --
 * aucun modele, aucun telephone, quelques millisecondes.
 */
class LocalisateurTest {

    /** Sourate jouet calquee sur Al-Ma'un : le couple (19, 20) revient en
     *  (24, 25). Seuls les rangs comptent, pas les lettres. */
    private val motsAttendus = listOf(
        "araayta", "alladhi", "yukadhdhibu", "biddin",          // 0-3
        "fadhalika", "alladhi", "yaduu", "alyatima",            // 4-7
        "wala", "yahuddu", "ala", "taami",                      // 8-11
        "almiskini", "fawaylun", "lilmusallina", "hatta",       // 12-15
        "thumma", "qala", "inna", "alladhina", "hum",           // 16-20  <- 1re occurrence
        "an", "salatihim", "sahuna",                            // 21-23
        "alladhina", "hum", "yuraouna", "wayamnauna", "almaoun" // 24-28  <- 2e occurrence
    )

    /** Ce que le recitateur vient de dire : la SUITE apres `sahuna` (23). */
    private val prononces = listOf("alladhina", "hum", "yuraouna", "wayamnauna", "almaoun")

    private fun localiser(): Localisateur.Bande? {
        val pieces = Synthese.vocabulaire(motsAttendus)
        val front = FauxFront(pieces)
        val tokeniser = Synthese.tokeniseur(pieces)
        // Pas de pause : on teste l'appariement, pas le decoupage.
        val pcm = Synthese.pcm(prononces, tokeniser, front.blank, pauseTousLes = 0)
        val loc = Localisateur(pieces, front.blank)
        return loc.localiser(
            front.logprobs(pcm),
            motsAttendus,
            dernierVerrouille = 23,
            // Meme fourniture que ChaineRecitation : n tokens => n frames.
            framesMinParMot = { i -> tokeniser(motsAttendus[i]).size },
        )
    }

    @Test
    fun `le passage repete est place sur la SECONDE occurrence, pas la premiere`() {
        val b = localiser()!!
        // AVANT le correctif : i0 = 19, attestes = {19, 20, 26, 27, 28}, et la
        // bande etait signalee `recul` -- « le recitateur repete ».
        assertEquals("la bande doit partir du mot 24", 24, b.i0)
        assertEquals("et couvrir jusqu'au dernier mot", 28, b.i1)
        assertEquals(
            "les cinq mots reellement dits doivent etre attestes",
            setOf(24, 25, 26, 27, 28), b.attestes.keys.toSet()
        )
    }

    @Test
    fun `aucun faux recul sur ce cas`() {
        // Le recul est ce qui a fige l'ancre a 23 pendant toute la fin de la
        // sourate : la chaine croyait que le recitateur repetait le verset 4.
        assertTrue("la bande ne doit pas etre marquee `recul`", !localiser()!!.recul)
    }

    /** DEUX VERSETS IDENTIQUES -- le cas ou la contrainte temporelle ne peut
     *  RIEN, parce que le trou EST paye en audio.
     *
     *  Cas REEL (2026-08-06, sourate 94 Ash-Sharh, session live, build v78).
     *  Versets 5 et 6 : `فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا` (mots 17-20) puis
     *  `إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا` (mots 21-24). Le recitateur dit le verset 6
     *  puis enchaine ; la chaine apparie le verset 6 aux index du verset 5, et
     *  le log donne SEPT fois :
     *      f=22 SAUT REFUSE : trou de 4 mots apres le mot 20
     *           (attestes=[17, 18, 19, 20, 25]), dernier definitif=20, max=2
     *  Ancre bloquee au mot 20 sur 31, toute la fin de la recitation perdue.
     *
     *  La contrainte temporelle ne peut pas trancher : les quatre mots sautes
     *  ONT ete prononces, l'audio en porte le cout. Seule la COMPACITE
     *  distingue [17,18,19,20,25] (portee 8) de [21,22,23,24,25] (portee 4).
     *
     *  ⚠️ AUCUNE LETTRE DOUBLEE dans les mots jouets : le decodeur synthetique
     *  replie deux tokens identiques consecutifs (comportement CTC), `inna`
     *  ressortirait `ina` et ne s'apparierait plus a lui-meme. Piege paye en
     *  ecrivant ce test. */
    @Test
    fun `deux versets identiques -- c'est le SECOND qui est retenu`() {
        val mots = listOf(
            "alam", "nashrah", "laka", "sadrak",          // 0-3
            "wawadana", "anka", "wizrak",                 // 4-6
            "aladhi", "anqada", "zahrak",                 // 7-9
            "warafana", "laka", "dhikrak",                // 10-12
            "inza", "mata", "alusri", "yusran",           // 13-16  <- verset 5
            "inza", "mata", "alusri", "yusran",           // 17-20  <- verset 6, IDENTIQUE
            "faidha", "faragta", "fansab",                // 21-23
            "wailan", "rabika", "fargab",                 // 24-26
        )
        val pieces = Synthese.vocabulaire(mots)
        val front = FauxFront(pieces)
        val tokeniser = Synthese.tokeniseur(pieces)
        // Le recitateur vient de finir le verset 5 (ancre 12 : il l'entame) et
        // dit le verset 6 puis le premier mot du 7. Les deux alignements ont
        // EXACTEMENT cinq appariements ; seule la portee les separe.
        val prononces = listOf("inza", "mata", "alusri", "yusran", "faidha")
        val pcm = Synthese.pcm(prononces, tokeniser, front.blank, pauseTousLes = 0)
        val b = Localisateur(pieces, front.blank).localiser(
            front.logprobs(pcm), mots, dernierVerrouille = 12,
            framesMinParMot = { i -> tokeniser(mots[i]).size },
        )!!
        assertEquals(
            "l'alignement COMPACT doit gagner : aucun mot suppose non prononce",
            setOf(17, 18, 19, 20, 21), b.attestes.keys.toSet()
        )
    }

    /** LE CAS REEL DE LA SOURATE 94 : deux copies, le mot distinctif PERDU.
     *
     *  Ash-Sharh, session live du 2026-08-06 (build v78). Versets 5 et 6 :
     *      17-20  فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا
     *      21-24  إِنَّ  مَعَ ٱلْعُسْرِ يُسْرًا
     *  Le mot distinctif aurait du trancher -- `فان` et `ان` ne s'apparient
     *  pas entre eux. Mais le modele l'a lu `إِنَّمَا`, qui ne correspond ni a
     *  l'un ni a l'autre : il ne restait que TROIS mots communs aux deux
     *  copies. Meme longueur, meme portee, egalite PARFAITE -- ni la
     *  contrainte temporelle (l'alignement fautif ne saute rien) ni la
     *  compacite ne peuvent trancher. Seul le sens le peut.
     *
     *  Consequence mesuree : `RECUL vers le mot 18` trois fois, ancre jamais
     *  passee au verset 6, puis quatre `SAUT REFUSE` et un DECROCHAGE quand le
     *  recitateur a enchaine sur le verset 7. Ancre bloquee a 20 sur 31. */
    @Test
    fun `a egalite parfaite, l'alignement qui AVANCE gagne`() {
        val mots = listOf(
            "alam", "nashrah", "laka", "sadrak",          // 0-3
            "wawadana", "anka", "wizrak",                 // 4-6
            "aladhi", "anqada", "zahrak",                 // 7-9
            "warafana", "laka", "dhikrak",                // 10-12
            "zayd", "amru", "bakr", "khalid",             // 13-16  (bourrage)
            "fainza", "mata", "alusri", "yusran",         // 17-20  <- verset 5
            "inza", "mata", "alusri", "yusran",           // 21-24  <- verset 6
            "faidha", "faragta", "fansab",                // 25-27
        )
        val pieces = Synthese.vocabulaire(mots)
        val front = FauxFront(pieces)
        val tokeniser = Synthese.tokeniseur(pieces)
        // Le verset 5 est juge (ancre 20). Le recitateur dit le verset 6, mais
        // le modele n'a PAS lu son premier mot -- exactement comme sur device.
        // Les trois mots restants vont aux deux copies : egalite parfaite.
        val prononces = listOf("mata", "alusri", "yusran")
        val pcm = Synthese.pcm(prononces, tokeniser, front.blank, pauseTousLes = 0)
        val b = Localisateur(pieces, front.blank).localiser(
            front.logprobs(pcm), mots, dernierVerrouille = 20,
            framesMinParMot = { i -> tokeniser(mots[i]).size },
        )!!
        assertEquals(
            "l'alignement doit se poser sur le verset 6, pas relire le verset 5",
            setOf(22, 23, 24), b.attestes.keys.toSet()
        )
        assertTrue("et ne pas etre signale comme une repetition", !b.recul)
    }

    @Test
    fun `un trou de mots reellement sautes n'est PAS apparie`() {
        // DECISION UTILISATEUR (2026-08-06) : « le saut n'est pas autorise, en
        // plus c'est ce que je veux detecter pour arreter la recitation et
        // qu'il recite les mots reellement attendus ». Un saut ne doit donc pas
        // faire avancer l'ancre en silence -- il doit tomber dans le
        // decrochage, qui souffle les mots omis.
        val pieces = Synthese.vocabulaire(motsAttendus)
        val front = FauxFront(pieces)
        val tokeniser = Synthese.tokeniseur(pieces)
        // Le recitateur saute `alladhina hum yuraouna` (24-26) et enchaine
        // directement sur 27-28. L'audio des mots sautes n'existe pas.
        val pcm = Synthese.pcm(
            listOf("wayamnauna", "almaoun"), tokeniser, front.blank, pauseTousLes = 0)
        val b = Localisateur(pieces, front.blank).localiser(
            front.logprobs(pcm), motsAttendus, dernierVerrouille = 23,
            framesMinParMot = { i -> tokeniser(motsAttendus[i]).size },
        )
        // Les deux mots sont bien attestes -- ils ONT ete prononces. Ce qui est
        // interdit, c'est de pretendre que 24-26 l'ont ete aussi.
        assertTrue("les mots dits restent attestes", b!!.attestes.keys.containsAll(setOf(27, 28)))
        assertTrue(
            "les mots sautes ne doivent PAS etre attestes",
            b.attestes.keys.none { it in 24..26 }
        )
    }
}
