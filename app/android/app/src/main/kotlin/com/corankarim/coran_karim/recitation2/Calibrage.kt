package com.corankarim.coran_karim.recitation2

import kotlin.math.sqrt

/**
 * CALIBRAGE — deriver les deux seuils de decoupage depuis la voix du recitateur,
 * au lieu de les fixer une fois pour toutes.
 *
 * ── LE DEFAUT QU'ON TRAITE ──────────────────────────────────────────────────
 * Le graphe le nomme depuis le 2026-07-30 : « une falaise entre deux valeurs
 * voisines n'est pas un reglage, c'est un defaut de conception -- la chaine
 * depend d'un parametre qui n'a aucune plage stable. Un recitateur qui respire
 * autrement ferait basculer l'app d'un cote ou de l'autre sans que personne
 * comprenne pourquoi. »
 *
 * Le seuil RMS a deja ete traite ainsi et ca a MARCHE : fixe, il s'effondrait a
 * 65,76 % de mots non verts des qu'on montait le gain de 50 % ; derive
 * (0,344 x p75 des RMS de bloc), il rend 2,03 % A TOUS LES GAINS. On applique
 * ici la meme recette au seuil de PAUSE, qui est reste fixe.
 *
 * ── LE PRINCIPE : UN RAPPORT, PAS UNE VALEUR ────────────────────────────────
 * On ne cherche pas « la bonne duree de pause ». On cherche le RAPPORT entre le
 * seuil et l'echelle de silence propre a cette voix. Un recitateur lent etire
 * TOUT -- ses micro-pauses entre mots comme ses respirations de fin d'enonce --
 * donc une duree absolue ne transfere pas d'une voix a l'autre, alors qu'un
 * rapport, si. C'est exactement l'argument qui a fait passer le RMS d'un seuil
 * absolu a un rapport au niveau de parole.
 *
 * ── POURQUOI EN LOT ICI, ET GLISSANT A L'EXECUTION ──────────────────────────
 * A l'execution le seuil RMS suit une fenetre glissante de 30 s : il doit
 * SUIVRE un recitateur qui s'eloigne du micro. Un calibrage, lui, a le droit de
 * regarder tout l'enregistrement d'un coup -- et il le DOIT, parce que
 * l'estimateur des silences est pauvre en donnees : 30 s ne contiennent que
 * 5 a 10 silences la ou elles contiennent des centaines de blocs RMS. Un
 * percentile sur 8 valeurs saute d'un enonce a l'autre ; sur toute une
 * recitation, il tient.
 *
 * C'est LA raison d'etre de cette classe, et la raison pour laquelle le
 * calibrage de la pause ne peut pas simplement etre « le RMS avec une autre
 * grandeur ».
 *
 * ── CE QUE CETTE CLASSE NE FAIT PAS ─────────────────────────────────────────
 * Elle ne DECIDE rien et ne modifie aucun reglage. Elle mesure et rend un
 * [Resultat]. Ce qu'on en fait -- l'appliquer, le stocker par profil, le
 * refuser -- appartient a l'appelant. Une classe qui mesure et qui applique en
 * meme temps est une classe qu'on ne peut pas mettre sur un banc.
 */
class Calibrage(
    private val bloc: Int = Horloge.ECH_PAR_FRAME,
) {
    private val rmsBlocs = ArrayList<Float>()
    private val enAttente = ArrayList<Float>()

    // ── CUMUL SUR PLUSIEURS SESSIONS ────────────────────────────────────────
    // Demande utilisateur (2026-07-31) et elle est fondee : l'estimateur des
    // silences est PAUVRE EN DONNEES -- une minute n'en contient qu'une
    // quarantaine, la ou elle contient des centaines de blocs RMS. Cumuler est
    // le bon remede.
    //
    // MAIS ON NE CUMULE PAS LE SIGNAL BRUT, ON CUMULE LES SILENCES. La nuance
    // est tout le sujet : le seuil de silence se derive du NIVEAU DE PAROLE, et
    // deux sessions enregistrees a des distances differentes du micro n'ont pas
    // le meme niveau. Empiler leurs blocs donnerait UN p75 a mi-chemin, donc un
    // seuil trop haut pour la session douce et trop bas pour la forte -- les
    // silences des deux seraient mal decoupes. C'est exactement le defaut que
    // le seuil adaptatif a corrige, on ne va pas le reintroduire ici.
    //
    // Donc : chaque session cloture avec SON PROPRE niveau, on en extrait ses
    // silences, et ce sont les SILENCES qui s'additionnent.
    private val silencesCumules = ArrayList<Double>()
    private val niveauxSessions = ArrayList<Float>()
    private var secondesCumulees = 0.0
    var sessions: Int = 0
        private set

    /** Alimente le calibrage en PCM 16 kHz mono, par paquets de taille libre. */
    fun alimenter(echantillons: FloatArray) {
        for (v in echantillons) {
            enAttente.add(v)
            if (enAttente.size == bloc) {
                rmsBlocs.add(rms(enAttente))
                enAttente.clear()
            }
        }
    }

    /**
     * Cloture la session en cours : derive SON niveau, en extrait SES silences,
     * les verse au cumul, puis repart a vide pour la suivante.
     *
     * @return le nombre de silences que cette session a apportes.
     */
    fun cloturerSession(): Int {
        if (rmsBlocs.size < MIN_BLOCS) { rmsBlocs.clear(); enAttente.clear(); return 0 }
        val niveau = rmsBlocs.sorted()[(rmsBlocs.size * 75) / 100]
        val seuil = (RAPPORT_SEUIL_NIVEAU * niveau)
            .coerceIn(SEUIL_RMS_MIN, SEUIL_RMS_MAX)
        val avant = silencesCumules.size
        extraireSilences(rmsBlocs, seuil, silencesCumules)
        niveauxSessions.add(niveau)
        secondesCumulees += rmsBlocs.size.toDouble() * bloc / Horloge.TAUX
        sessions++
        rmsBlocs.clear()
        enAttente.clear()
        return silencesCumules.size - avant
    }

    /** Durée de la session en cours, hors cumul. */
    val secondes: Double get() = rmsBlocs.size.toDouble() * bloc / Horloge.TAUX
    val nombreDeBlocs: Int get() = rmsBlocs.size
    val secondesTotales: Double get() = secondesCumulees + secondes
    val silencesCumulesCount: Int get() = silencesCumules.size

    /**
     * Silences d'une suite de RMS de bloc, pour un seuil donne.
     *
     * Les silences de TETE et de QUEUE sont ecartes : le temps qu'a mis
     * l'utilisateur a commencer, ou a poser le telephone a la fin, n'est pas une
     * pause de recitation. Les inclure tirerait le p90 vers le haut -- et le p90
     * est justement l'ancrage du seuil.
     */
    private fun extraireSilences(rms: List<Float>, seuil: Float, dans: MutableList<Double>) {
        var run = 0
        var vuDeLaParole = false
        for (r in rms) {
            if (r < seuil) {
                run++
            } else {
                if (vuDeLaParole && run > 0) dans.add(run.toDouble() * bloc / Horloge.TAUX)
                run = 0
                vuDeLaParole = true
            }
        }
    }

    /**
     * @param rapportPause rapport a appliquer au p75 des silences. La valeur par
     *   defaut est DERIVEE de la recitation de reference (cf. [RAPPORT_PAUSE]),
     *   pas choisie.
     */
    fun resultat(rapportPause: Double = RAPPORT_PAUSE): Resultat {
        // La session en cours compte comme les autres : on la cloture d'abord,
        // avec SON propre niveau de parole. Sans ca un calibrage en une seule
        // session ne rendrait rien du tout.
        if (rmsBlocs.size >= MIN_BLOCS) cloturerSession()

        val niveau = if (niveauxSessions.isEmpty()) 0f else niveauxSessions.average().toFloat()
        val seuilBrut = RAPPORT_SEUIL_NIVEAU * niveau
        val seuil = seuilBrut.coerceIn(SEUIL_RMS_MIN, SEUIL_RMS_MAX)

        if (sessions == 0) {
            return Resultat(
                secondes = secondesTotales, blocs = 0, niveauParole = 0f,
                seuilRms = 0f, seuilRmsBorne = false, silences = emptyList(),
                pause = 0.0, pauseBornee = false, sessions = 0, fiable = false,
                pourquoi = "trop court : il faut au moins $MIN_BLOCS blocs " +
                    "(~${"%.0f".format(MIN_BLOCS * bloc / Horloge.TAUX.toDouble())} s) " +
                    "dans une session",
            )
        }

        val st = silencesCumules.sorted()
        if (st.size < MIN_SILENCES) {
            return Resultat(
                secondes = secondesTotales, blocs = 0, niveauParole = niveau,
                seuilRms = seuil, seuilRmsBorne = seuilBrut != seuil,
                silences = st, pause = 0.0, pauseBornee = false,
                sessions = sessions, fiable = false,
                pourquoi = "seulement ${st.size} silences sur $sessions session(s), " +
                    "il en faut $MIN_SILENCES pour qu'un percentile veuille dire " +
                    "quelque chose -- enchainez une session de plus",
            )
        }

        // ANCRAGE SUR p90, ET C'EST MESURE, PAS SUPPOSE (2026-07-31, recitation
        // de reference, 214 silences) :
        //     p10 = p25 = p50 = 0,080 s   <- une seule frame : micro-pauses
        //     p75 = 0,320 s               <- zone de TRANSITION
        //     p90 = 0,800 s               <- vraies frontieres d'enonce
        // Ancrer sur p75 reproduirait l'objection que le projet a deja ecrite
        // contre les percentiles fixes : « un percentile suppose que la
        // PROPORTION de silence est la meme chez tous les recitateurs ; elle ne
        // l'est pas -- quelqu'un qui respire plus souvent en aurait plus ». p75
        // tombe dans la transition, donc un recitateur qui multiplie les
        // micro-pauses le tire vers le BAS et le seuil suit dans le mauvais
        // sens. p90 est domine par les vraies pauses : il estime la grandeur
        // physique qu'on veut, « combien dure une frontiere chez cette voix ».
        val ancre = st[((st.size - 1) * 90) / 100]
        val pauseBrute = rapportPause * ancre
        val pause = pauseBrute.coerceIn(PAUSE_MIN, PAUSE_MAX)

        return Resultat(
            secondes = secondesTotales, blocs = 0, niveauParole = niveau,
            seuilRms = seuil, seuilRmsBorne = seuilBrut != seuil,
            silences = st, pause = pause, pauseBornee = pauseBrute != pause,
            sessions = sessions, fiable = true, pourquoi = null,
        )
    }

    data class Resultat(
        val secondes: Double,
        val blocs: Int,
        /** p75 des RMS de bloc — estimateur du niveau de parole. */
        val niveauParole: Float,
        val seuilRms: Float,
        /** true = la borne a mordu, donc la voix sort du domaine mesure. */
        val seuilRmsBorne: Boolean,
        /** Toutes les durees de silence observees, triees. C'est la matiere
         *  premiere : une distribution NETTE (deux populations separees)
         *  signifie que le reglage est fiable ; une distribution etalee
         *  signifie qu'aucun seuil ne separera proprement, et il vaut mieux le
         *  VOIR que de lire un chiffre rassurant. */
        val silences: List<Double>,
        val pause: Double,
        val pauseBornee: Boolean,
        /** Nombre de sessions cumulees. */
        val sessions: Int,
        val fiable: Boolean,
        val pourquoi: String?,
    ) {
        fun percentile(p: Int): Double =
            if (silences.isEmpty()) 0.0
            else silences[((silences.size - 1) * p) / 100]

        /**
         * Ecart entre les deux populations attendues : micro-pauses entre mots
         * (bas) et frontieres d'enonce (haut). Plus c'est grand, plus le seuil
         * est robuste. Sous ~2, aucun seuil ne separe proprement -- c'est le
         * cas qu'il faut montrer a l'utilisateur au lieu de le masquer.
         */
        val separation: Double
            get() = if (percentile(25) <= 0.0) 0.0 else percentile(90) / percentile(25)
    }

    private fun rms(b: List<Float>): Float {
        var acc = 0.0
        for (v in b) acc += v.toDouble() * v
        return sqrt(acc / b.size).toFloat()
    }

    companion object {
        /** Identique a ConstructeurDeFenetres : c'est le MEME rapport, il n'y a
         *  aucune raison qu'un calibrage derive un seuil RMS different de celui
         *  que la chaine appliquera. */
        const val RAPPORT_SEUIL_NIVEAU = 0.344f
        const val SEUIL_RMS_MIN = 0.004f
        const val SEUIL_RMS_MAX = 0.20f

        /**
         * DERIVE sur la recitation de reference (BancFluxBrut.calibrage,
         * 2026-07-31) : p90 des silences = 0,800 s, et la pause validee sur
         * device vaut 0,40 s -> rapport 0,50. Meme methode que 0,344 pour le
         * seuil RMS : c'est le rapport qui REPRODUIT la valeur validee, rendu
         * invariant a la vitesse de la voix. Ce n'est pas un reglage.
         *
         * Ce que ce rapport dit, en clair : « coupe a la moitie de ce qui est
         * une vraie pause chez ce recitateur ».
         *
         * ⚠️ Derive sur UN recitateur, comme 0,344 avant lui. Le calibrage
         * existe justement pour que la VALEUR s'adapte ; c'est le RAPPORT qu'on
         * suppose partage, et cette supposition n'a ete verifiee sur aucune
         * seconde voix a ce jour.
         */
        const val RAPPORT_PAUSE = 0.50

        /**
         * BORNES DE LA PAUSE — et il faut savoir d'ou elles viennent.
         *
         * Le balayage historique donnait un plateau 0,40-0,45 et une falaise
         * sous 0,35. CE BALAYAGE PRECEDE LE SEUIL RMS ADAPTATIF et ne decrit
         * plus la chaine actuelle. Mesure du 2026-07-31 sur la chaine reelle :
         *
         *     pause   blocs   mots atteints   non verts
         *     0,35     91         294           2,72 %
         *     0,40     75         227           2,64 %
         *
         * Ni falaise ni plateau visible, et 0,40 laisse 67 mots hors du compte.
         * Sur device : 0,40 -> 2,03 / 2,37 / 2,71 %, 0,35 -> 3,05 %.
         *
         * Les bornes ci-dessous sont donc LARGES a dessein : elles ne servent
         * qu'a empecher l'absurde (une piece bruyante, un recitateur qui ne
         * s'arrete jamais), pas a imposer un reglage. Les resserrer demande un
         * balayage refait sur la chaine actuelle.
         */
        const val PAUSE_MIN = 0.25
        const val PAUSE_MAX = 0.80

        /** ~2 s de signal, comme MIN_BLOCS_NIVEAU cote chaine. */
        const val MIN_BLOCS = 25

        /** En dessous, un percentile ne veut rien dire. Choisi pour qu'un
         *  calibrage trop court se declare NON FIABLE plutot que de rendre un
         *  chiffre precis et faux. */
        const val MIN_SILENCES = 12
    }
}
