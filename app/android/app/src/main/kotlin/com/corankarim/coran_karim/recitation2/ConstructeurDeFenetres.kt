package com.corankarim.coran_karim.recitation2

import kotlin.math.sqrt

/**
 * Correspondance entre l'horloge de TRAVAIL et l'horloge BRUTE.
 *
 * Depuis la v2.1 elle est l'IDENTITE : le flux de travail EST le flux brut,
 * rien n'est ecarte (cf. [ConstructeurDeFenetres]). L'objet est conserve parce
 * qu'il porte le contrat — toute frame de logprobs doit rester convertible en
 * position dans le flux brut, ou la preuve acoustique existe. Le jour ou une
 * couche recommencerait a jeter de l'audio, c'est ici que ca devrait se voir.
 */
class Correspondance(private val segments: List<Segment>) {
    data class Segment(val travailDebut: Long, val absDebut: Long, val longueur: Int)

    fun versAbsolu(travailIdx: Long): Long {
        for (s in segments) {
            if (travailIdx >= s.travailDebut && travailIdx < s.travailDebut + s.longueur) {
                return s.absDebut + (travailIdx - s.travailDebut)
            }
        }
        return -1
    }

    fun restreindre(travailDebut: Long, travailFin: Long): Correspondance {
        val out = ArrayList<Segment>()
        for (s in segments) {
            val d = maxOf(s.travailDebut, travailDebut)
            val f = minOf(s.travailDebut + s.longueur, travailFin)
            if (f > d) {
                out.add(Segment(d, s.absDebut + (d - s.travailDebut), (f - d).toInt()))
            }
        }
        return Correspondance(out)
    }
}

/**
 * Un bloc d'analyse. Objet IMMUABLE : l'unite d'entree des couches pures C/D/E.
 *
 * @param pleine vrai si le bloc est delimite des DEUX cotes par un silence reel
 *   du recitateur — c'est-a-dire s'il ressemble a un clip d'entrainement.
 * @param fusion vrai si le bloc regroupe plusieurs enonces : c'est la 2e
 *   observation, obtenue avec un contexte different, qui permet a la couche G
 *   de confirmer sans compter deux fois la meme preuve.
 */
data class Fenetre(
    val id: Long,
    val travailDebut: Long,
    val echantillons: FloatArray,
    val correspondance: Correspondance,
    val pleine: Boolean,
    val fusion: Boolean = false,
) {
    val travailFin: Long get() = travailDebut + echantillons.size
    val dureeSecondes: Double get() = echantillons.size.toDouble() / Horloge.TAUX

    fun absoluDeFrame(frame: Int): Long =
        correspondance.versAbsolu(travailDebut + Horloge.frameVersEch(frame))

    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = id.hashCode()
}

/**
 * COUCHE B — DECOUPAGE AUX SILENCES REELS DU RECITATEUR.
 *
 * ── CE QUI A CHANGE LE 2026-07-30, ET LA MESURE QUI L'IMPOSE ────────────────
 *
 * La v2.0 emettait des fenetres de DUREE CONSTANTE (6 s, pas 1,5 s) sur un flux
 * dont un portier RMS avait retire le silence. Raisonnement : une longueur
 * constante empeche la normalisation `per_feature` de deriver. Le raisonnement
 * etait faux, et une seule mesure l'a montre.
 *
 * MEME AUDIO (flux brut d'une recitation professionnelle, 379,8 s, 296 mots),
 * MEME modele causal du telephone, seule la POLITIQUE DE DECOUPAGE change --
 * erreur mot du decodage libre :
 *
 *   fichier entier, aucune coupe .................... 54,05 %  (202 mots lus)
 *   clips du portier RMS recolles (44 blocs) ........ 29,05 %  (269 mots lus)
 *   regroupes ~18 s ................................. 39,19 %  (244 mots lus)
 *   COUPE AUX SILENCES REELS, pause >= 0,5 s ........ 14,86 %  (307 mots lus)
 *                                    lettres seules :  7,43 %
 *
 * Ce n'est donc pas la LONGUEUR du bloc qui compte, c'est le fait que ses
 * bornes tombent la ou le recitateur se tait. Un bloc delimite par des silences
 * reels EST un clip d'entrainement ; un bloc de 6 s qui commence et finit en
 * plein mot est hors domaine, quelle que soit sa regularite.
 *
 * Preuve directe que la v2.0 se coupait de cette information : rejouee sur le
 * flux BRUT au lieu des clips recolles, elle rendait EXACTEMENT le meme taux
 * (108/295 = 36,61 %) -- son propre portier reconstruisait le meme flux mutile.
 *
 * ── ET LE NOEUD [MORT] "COUPER A CHAQUE PAUSE" (WER 103,5 %) ? ──────────────
 *
 * Il ne s'applique pas ici, et la difference n'est pas rhetorique :
 *   1. il a ete mesure le 2026-07-23 sur le modele NON CAUSAL, avant le
 *      fine-tune streaming. L'avertissement du §1.5 est explicite : les mesures
 *      pre-causal ne se transportent pas. La mesure ci-dessus est faite sur le
 *      modele du telephone, aujourd'hui ;
 *   2. en v1, couper FIGEAIT du texte : chaque coupe pouvait dupliquer ou
 *      perdre des mots, et c'est ce qui produisait le WER > 100 %. Ici une
 *      coupe ne fige rien du tout : elle delimite une FENETRE D'ANALYSE. Le
 *      texte attendu est connu, on ne coud aucune transcription.
 *
 * ── CONTRAT ────────────────────────────────────────────────────────────────
 *  - le flux de travail EST le flux brut : plus rien n'est jete. Le silence
 *    n'est pas du bruit a supprimer, c'est le SEPARATEUR qui porte toute
 *    l'information de decoupage, et c'est aussi le contexte droit dont le
 *    modele causal a besoin (1,04 s de lookahead) ;
 *  - un bloc va d'un milieu de silence au milieu du silence suivant : ses deux
 *    bords sont donc dans du silence, jamais en plein mot ;
 *  - chaque enonce est analyse DEUX fois — seul, puis fusionne avec le suivant.
 *    Deux contextes differents, donc deux preuves independantes au sens de la
 *    couche G, sans jamais compter deux fois la meme.
 */
class ConstructeurDeFenetres(
    /**
     * Silence minimal qui vaut frontiere d'enonce.
     *
     * VALEUR MESUREE, et elle ne se lit PAS seule : elle forme un couple avec
     * [seuilRmsSilence]. Balayage sur le flux brut de reference, tout le reste
     * identique (mots non verts) :
     *
     *     pause  rms    blocs   non verts
     *     0,30   0,01     39     73,56 %
     *     0,35   0,01     39     73,56 %
     *     0,30   0,02     60      3,39 %
     *     0,35   0,02     53     65,76 %
     *     0,30   0,03    127      4,41 %
     *     0,35   0,03    104      2,71 %
     *     0,35   0,035   112      4,41 %
     *     0,40   0,03    102      2,03 %   <- retenu
     *     0,45   0,03    102      2,03 %   <- meme resultat : vrai PLATEAU
     *
     * Ce qui pilote le taux n'est ni la pause ni le RMS pris isolement, c'est le
     * NOMBRE DE BLOCS qu'ils produisent ensemble : trop peu (39) et les blocs
     * sortent du domaine du modele, trop (127) et chaque frontiere est une
     * occasion de se tromper. L'optimum est un plateau, pas un pic -- 0,40 et
     * 0,45 donnent le meme chiffre, ce qui est le seul reglage acceptable.
     */
    private val pauseMinSecondes: Double = 0.40,
    /** Cf. [pauseMinSecondes] : les deux se lisent ensemble. 0,02 etait herite
     *  du portier RMS de la v1, ou il servait a JETER de l'audio ; ici il sert a
     *  DETECTER une frontiere, ce n'est pas le meme role et pas la meme valeur. */
    private val seuilRmsSilence: Float = 0.03f,
    /** Garde-fou, pas une politique : les clips d'entrainement font <= 20 s
     *  (`max_duration: 20.0`). Au-dela le modele travaille dans un regime de
     *  longueur qu'il n'a JAMAIS vu -- c'est ce qui explique les 54 % du
     *  fichier entier. Si le recitateur enchaine sans pause, on coupe au plus
     *  bas RMS disponible plutot que de sortir du domaine.
     *
     *  MESURE : a 18 s ce garde-fou coupait en pleine parole et faisait passer
     *  le taux de 11,86 % a 51,53 %. Il est porte a 30 s -- avec le reglage
     *  retenu il ne se declenche JAMAIS (102 blocs de ~3,7 s en moyenne). S'il
     *  se declenche, c'est un symptome a instruire, pas un reglage a baisser. */
    private val maxBlocSecondes: Double = 30.0,
    /** Un enonce plus court que ca n'est pas un enonce : c'est une respiration
     *  entre deux silences. On l'agrege au suivant. */
    private val minBlocSecondes: Double = 0.8,
    private val fusionner: Boolean = true,
) {
    private val bloc = Horloge.ECH_PAR_FRAME // 80 ms, granularite de la detection
    private val pauseMinBlocs = (pauseMinSecondes * Horloge.TAUX / bloc).toInt()
    private val maxEch = Horloge.secondesVersEch(maxBlocSecondes)
    /**
     * Contexte droit exige par le modele causal : 13 frames de sortie = 1,04 s.
     *
     * Un bloc doit contenir AU MOINS ca apres sa derniere parole, sinon son
     * dernier mot n'est jamais « interieur », donc jamais votant, donc declare
     * `Omis` -- ALORS QU'IL EST LU PARFAITEMENT. Mesure du 2026-07-30 :
     *     mot 67  أَلَآ         f15 bord gop=0,00 entendu="أَلَآ"        -> Omis
     *     mot 287 مُتَشَـٰبِهًا  f58 bord gop=0,00 entendu="مُتَشَـٰبِهًا"  -> Omis
     * Une pause de 0,3 s ne fournit que 4 frames ; il en faut 13. On retarde
     * donc la fermeture du bloc jusqu'a les avoir, quitte a empieter sur le
     * debut de l'enonce suivant -- les blocs se recouvrent deja, c'est sans
     * consequence.
     */
    private val lookaheadEch =
        Horloge.frameVersEch(Horloge.LOOKAHEAD_FRAMES + 1).toInt()
    private val minEch = Horloge.secondesVersEch(minBlocSecondes)

    private var travail = FloatArray(Horloge.TAUX * 30)
    private var travailTaille = 0
    private var travailBase = 0L

    private var derniereCoupe = 0L        // debut du bloc en cours
    private var avantDerniereCoupe = -1L  // pour le bloc de fusion
    private var runSilence = 0            // blocs de 80 ms de silence consecutifs
    private var debutSilence = -1L        // ou commence le silence en cours
    private var vuDeLaParole = false
    /** Coupe decidee mais PAS ENCORE emise : on attend d'avoir capte un
     *  lookahead complet apres la derniere parole (cf. [lookaheadEch]). */
    private var coupeEnAttente = -1L
    private var prochainDebutEnAttente = -1L
    private var idSuivant = 0L
    private var minRmsDepuisCoupe = Float.MAX_VALUE
    private var posMinRms = -1L

    private val enAttente = ArrayList<Float>(bloc)

    val positionTravail: Long get() = travailBase + travailTaille

    fun alimenter(echantillons: FloatArray): List<Fenetre> {
        val sorties = ArrayList<Fenetre>()
        for (v in echantillons) {
            enAttente.add(v)
            if (enAttente.size == bloc) {
                sorties.addAll(traiterBloc(enAttente.toFloatArray()))
                enAttente.clear()
            }
        }
        return sorties
    }

    private fun traiterBloc(b: FloatArray): List<Fenetre> {
        val posBloc = positionTravail
        ajouter(b)
        val r = rms(b)

        if (r < minRmsDepuisCoupe) { minRmsDepuisCoupe = r; posMinRms = posBloc }

        if (r < seuilRmsSilence) {
            if (runSilence == 0) debutSilence = posBloc
            runSilence++
        } else {
            // LA PAROLE REPREND. Si le silence qu'on vient de quitter etait
            // assez long, il separait deux enonces : on ferme le bloc ICI.
            //
            // ── CORRECTION DU 2026-07-30, ET LA MESURE QUI L'IMPOSE ─────────
            // La version precedente coupait au MILIEU du silence. Consequence :
            // chaque bloc ne gardait qu'une demi-pause a droite (~0,15 s a
            // pause=0,3 s), alors que le modele causal exige 1,04 s d'audio
            // POSTERIEUR pour qu'une frame soit dans ses conditions
            // d'entrainement. Le dernier mot de chaque enonce etait donc
            // toujours « au bord », donc jamais votant, donc declare `Omis` --
            // ALORS QU'IL ETAIT LU PARFAITEMENT :
            //     mot 67  أَلَآ      f15 bord gop=0,00 entendu="أَلَآ"  -> Omis
            //     mot 204 تَتَّقُونَ  f45 bord gop=0,00 entendu="تَتَّقُونَ" -> Omis
            //
            // Le bloc va donc du DEBUT du silence precedent a la FIN du silence
            // courant : il contient les deux pauses ENTIERES, et les blocs se
            // recouvrent exactement sur les silences. Aucun mot n'est plus au
            // bord de quoi que ce soit -- ce sont les silences qui le sont.
            if (vuDeLaParole && runSilence >= pauseMinBlocs && coupeEnAttente < 0) {
                // On NE COUPE PAS tout de suite : il faut encore capter un
                // lookahead complet apres la derniere parole (cf. lookaheadEch).
                coupeEnAttente = posBloc + lookaheadEch
                prochainDebutEnAttente = debutSilence
            }
            runSilence = 0
            vuDeLaParole = true
        }

        // La coupe differee est-elle mure ? (assez de contexte droit capte)
        if (coupeEnAttente in 1..positionTravail) {
            val out = couper(coupeEnAttente, prochainDebutEnAttente)
            coupeEnAttente = -1
            prochainDebutEnAttente = -1
            if (out.isNotEmpty()) return out
        }

        // GARDE-FOU de domaine : jamais de bloc plus long que les clips
        // d'entrainement. On coupe alors au point le plus SILENCIEUX vu depuis
        // la derniere coupe -- le moins mauvais endroit, pas un endroit choisi.
        if (positionTravail - derniereCoupe >= maxEch) {
            val cible = if (posMinRms > derniereCoupe + minEch) posMinRms else positionTravail
            return couper(cible, cible)
        }
        return emptyList()
    }

    /**
     * @param finBloc fin du bloc qu'on ferme (inclut le silence en entier)
     * @param prochainDebut debut du bloc suivant -- plus petit que [finBloc]
     *   quand les deux se recouvrent sur le silence, ce qui est le cas normal.
     */
    private fun couper(finBloc: Long, prochainDebut: Long): List<Fenetre> {
        val position = finBloc
        if (position - derniereCoupe < minEch) return emptyList()
        val out = ArrayList<Fenetre>(2)
        out.add(bloquer(derniereCoupe, position, fusion = false))
        // 2e observation : le meme enonce vu AVEC le precedent. Contexte
        // different, normalisation differente, donc preuve independante.
        if (fusionner && avantDerniereCoupe >= 0 &&
            position - avantDerniereCoupe <= maxEch
        ) {
            out.add(bloquer(avantDerniereCoupe, position, fusion = true))
        }
        avantDerniereCoupe = derniereCoupe
        derniereCoupe = if (prochainDebut in derniereCoupe until position) {
            prochainDebut
        } else {
            position
        }
        minRmsDepuisCoupe = Float.MAX_VALUE
        posMinRms = -1
        return out
    }

    private fun bloquer(debut: Long, fin: Long, fusion: Boolean): Fenetre {
        val d = maxOf(debut, travailBase)
        val depart = (d - travailBase).toInt()
        val taille = (fin - d).toInt().coerceAtMost(travailTaille - depart)
        return Fenetre(
            id = idSuivant++,
            travailDebut = d,
            echantillons = travail.copyOfRange(depart, depart + taille),
            correspondance = Correspondance(
                listOf(Correspondance.Segment(d, d, taille))
            ),
            pleine = true,
            fusion = fusion,
        )
    }

    /**
     * FIN DE SESSION : ferme le bloc en cours.
     *
     * Sans cet appel, le dernier enonce n'est jamais analyse : la coupe est
     * declenchee par un silence, et le silence final peut ne jamais atteindre
     * la duree requise si la capture s'arrete avec le recitateur.
     */
    fun terminer(): List<Fenetre> {
        if (enAttente.isNotEmpty()) {
            ajouter(enAttente.toFloatArray())
            enAttente.clear()
        }
        coupeEnAttente = -1
        return couper(positionTravail, positionTravail)
    }

    private fun ajouter(b: FloatArray) {
        if (travailTaille + b.size > travail.size) compacter(b.size)
        System.arraycopy(b, 0, travail, travailTaille, b.size)
        travailTaille += b.size
    }

    /** Ne garde que ce qu'un bloc futur peut encore demander (deux blocs max,
     *  pour la fusion). Le flux BRUT, lui, n'est jamais rogne (cf. FluxBrut). */
    private fun compacter(besoin: Int) {
        val plusAncienUtile = if (avantDerniereCoupe >= 0) avantDerniereCoupe else derniereCoupe
        val depart = (plusAncienUtile - travailBase).toInt().coerceIn(0, travailTaille)
        if (depart > 0) {
            System.arraycopy(travail, depart, travail, 0, travailTaille - depart)
            travailBase += depart
            travailTaille -= depart
        }
        if (travailTaille + besoin > travail.size) {
            travail = travail.copyOf(maxOf(travail.size * 2, travailTaille + besoin))
        }
    }

    private fun rms(b: FloatArray): Float {
        var acc = 0.0
        for (v in b) acc += v.toDouble() * v
        return sqrt(acc / b.size).toFloat()
    }
}
