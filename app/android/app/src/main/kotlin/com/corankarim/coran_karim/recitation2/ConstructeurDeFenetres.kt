package com.corankarim.coran_karim.recitation2

import kotlin.math.sqrt

/**
 * Correspondance entre l'horloge de TRAVAIL (audio effectivement donne au
 * modele, silence compresse) et l'horloge BRUTE (indices absolus de [FluxBrut]).
 *
 * Elle existe parce que le portier de silence est conserve — le desactiver est
 * [MORT] (WER 70,2 % contre 22,8 %) et lui rendre le silence n'aide pas
 * (mesure du 2026-07-28 : -2,8 pt EN FAVEUR du portier). Mais il ne DETRUIT
 * plus : ce qu'il ecarte est simplement absent du flux de travail, et cette
 * table dit exactement ou. Toute frame de logprobs est donc reconvertible en
 * position dans le flux brut, ou la preuve acoustique existe toujours.
 *
 * C'est la piste C du 2026-07-28 ("rendre le silence au 2e buffer : flux brut +
 * table de correspondance entre les deux horloges"), ecrite puis retiree avant
 * mesure, conservee a la demande de l'utilisateur.
 */
class Correspondance(private val segments: List<Segment>) {
    /** Un morceau contigu d'audio garde : `longueur` echantillons a partir de
     *  `travailDebut` cote travail, `absDebut` cote brut. */
    data class Segment(val travailDebut: Long, val absDebut: Long, val longueur: Int)

    /** @return l'indice absolu correspondant a [travailIdx], ou -1 hors couverture. */
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
 * Une fenetre d'analyse. Objet IMMUABLE : c'est l'unite d'entree des couches
 * pures C/D/E.
 *
 * @param pleine vrai des que la fenetre a la duree nominale W. Les toutes
 *   premieres fenetres d'une session sont plus courtes (l'audio n'existe pas
 *   encore) — elles restent dans le domaine des clips d'entrainement, mais le
 *   registre de preuves garde l'information pour que rien ne se decide sur un
 *   regime different sans qu'on puisse le voir.
 */
data class Fenetre(
    val id: Long,
    val travailDebut: Long,
    val echantillons: FloatArray,
    val correspondance: Correspondance,
    val pleine: Boolean,
) {
    val travailFin: Long get() = travailDebut + echantillons.size
    val dureeSecondes: Double get() = echantillons.size.toDouble() / Horloge.TAUX

    /** Indice absolu (flux brut) de la frame de logprobs [frame]. */
    fun absoluDeFrame(frame: Int): Long =
        correspondance.versAbsolu(travailDebut + Horloge.frameVersEch(frame))

    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = id.hashCode()
}

/**
 * COUCHE B — CONSTRUCTEUR DE FENETRES.
 *
 * CONTRAT :
 *  - duree CONSTANTE `W` en regime etabli, toutes fenetres confondues ;
 *  - pas d'emission constant `hop < W` : les fenetres SE RECOUVRENT ;
 *  - la correspondance travail <-> brut est publiee avec chaque fenetre.
 *
 * POURQUOI C'EST LA PIECE CENTRALE DE LA v2 :
 *
 * 1. Constat n°1 du graphe — la normalisation `per_feature` ne derive pas
 *    parce que le buffer est LONG, elle derive parce que sa longueur VARIE.
 *    En rendant cette longueur constante, la normalisation est tiree de la meme
 *    duree a chaque passe. Le gel, la borne dure 12 s, `findCutOffset`,
 *    `targetSeconds` n'ont plus de raison d'exister : ils etaient le
 *    contournement de cette derive, jamais une fonctionnalite voulue.
 *
 * 2. Il n'y a plus de COUPE, donc plus de coupe en plein mot (47,4 % des coupes
 *    mesurees en v1), plus de `conserve=0`, plus de mot de frontiere qui
 *    n'existe entier NULLE PART. Un mot est entierement contenu, avec son
 *    contexte des deux cotes, dans au moins une fenetre.
 *
 * 3. Ce n'est PAS la [MORT] "fenetre glissante naive" (WER > 100 %) : celle-la
 *    echouait en COUSANT du texte decode d'une fenetre a l'autre, d'ou la
 *    duplication. Ici aucun texte n'est cousu — le texte attendu est connu, on
 *    ne fait qu'ALIGNER dessus. La duplication est un defaut de couture, pas
 *    d'alignement.
 *
 * GARANTIE D'INTERIORITE, chiffree : un mot de duree `d` est interieur a au
 * moins une fenetre des que `hop <= W - d - margeGauche - margeDroite`, avec
 * margeDroite >= 1,04 s (lookahead causal). Avec W = 6 s et d <= 1,5 s :
 * hop <= 3,2 s. Le reglage propose (hop = 1,5 s) donne 4 fenetres contenant
 * chaque mot, dont >= 2 ou il est interieur — donc K = 2 observations
 * concordantes sont disponibles a un `hop` d'intervalle, pas plus.
 *
 * W et hop sont les DEUX SEULS parametres de segmentation restants, et ils sont
 * fixes par le banc 1 (couverture interieure), jamais regles en cours de route.
 */
class ConstructeurDeFenetres(
    private val fenetreSecondes: Double = 6.0,
    private val pasSecondes: Double = 1.5,
    private val fenetreMinSecondes: Double = 2.0,
    private val seuilRmsSilence: Float = 0.02f,
    /**
     * Silence conserve apres une plage de parole. **Ce n'est pas un seuil
     * empirique : c'est une valeur DERIVEE, et sa derivation est le resultat de
     * mesure le plus utile de la journee du 2026-07-30.**
     *
     * Pour que le DERNIER mot dit avant une pause obtienne ses K=2 observations
     * interieures, le flux de TRAVAIL doit encore avancer, apres ce mot, de :
     *   - un lookahead (1,04 s) pour que la 1re observation soit interieure ;
     *   - un pas de grille pour que la 2e vienne d'une fenetre DISTINCTE.
     * En deca, le mot reste provisoire pour toujours : la grille de fenetres est
     * pilotee par la croissance du flux de travail, et un portier qui gele ce
     * flux gele aussi la validation.
     *
     * Defaut trouve PAR LE BANC (les 2-3 derniers mots d'une recitation
     * n'obtenaient jamais leur 2e preuve), pas par une intuition. En v1 la
     * constante equivalente valait 0,3 s ; la piste [EN ATTENTE]
     * `MAX_SILENCE_SAMPLES 0,3 -> 0,9 s` (`6d07754`) allait dans le bon sens
     * sans pouvoir dire POURQUOI 0,9 — la reponse est `lookahead + pas`.
     *
     * A confronter au reel dans le banc 1 : garder plus de silence met plus de
     * silence dans la fenetre d'analyse. La mesure du 2026-07-28 dit que rendre
     * TOUT le silence au modele degrade (-2,8 pt en faveur du portier) ; un
     * plafond derive n'est pas la meme chose que pas de plafond, mais ca reste
     * a verifier sur audio reel avant device.
     */
    private val silenceGardeSecondes: Double =
        (Horloge.LOOKAHEAD_FRAMES * Horloge.MS_PAR_FRAME) / 1000.0 + pasSecondes + 0.06,
) {
    private val w = Horloge.secondesVersEch(fenetreSecondes)
    private val pas = Horloge.secondesVersEch(pasSecondes)
    private val wMin = Horloge.secondesVersEch(fenetreMinSecondes)
    private val silenceGarde = Horloge.secondesVersEch(silenceGardeSecondes)
    private val bloc = Horloge.ECH_PAR_FRAME // 80 ms, la granularite du portier

    /** Flux de travail : l'audio effectivement donne au modele. */
    private var travail = FloatArray(w * 4)
    private var travailTaille = 0
    private var travailBase = 0L // indice travail absolu du 1er echantillon encore stocke

    private val segments = ArrayList<Correspondance.Segment>()
    private var absRecus = 0L
    private var enSilence = false
    private var silenceGardeRestant = 0

    private var prochaineEmission = -1L
    private var idSuivant = 0L

    private val enAttente = ArrayList<Float>(bloc)

    /** Nombre total d'echantillons ecrits dans le flux de travail. */
    val positionTravail: Long get() = travailBase + travailTaille

    /**
     * @param echantillons PCM 16 kHz mono [-1,1], taille quelconque.
     * @return les fenetres devenues disponibles (0, 1 ou plusieurs).
     */
    fun alimenter(echantillons: FloatArray): List<Fenetre> {
        val sorties = ArrayList<Fenetre>()
        for (v in echantillons) {
            enAttente.add(v)
            if (enAttente.size == bloc) {
                traiterBloc(enAttente.toFloatArray())
                enAttente.clear()
                sorties.addAll(emettre())
            }
        }
        return sorties
    }

    private fun traiterBloc(b: FloatArray) {
        val rms = rms(b)
        val absDebutBloc = absRecus
        absRecus += b.size

        if (rms < seuilRmsSilence) {
            if (!enSilence) {
                enSilence = true
                silenceGardeRestant = silenceGarde
            }
            if (silenceGardeRestant <= 0) return // ecarte du TRAVAIL, jamais detruit (cf. FluxBrut)
            val garde = minOf(silenceGardeRestant, b.size)
            silenceGardeRestant -= garde
            ajouterAuTravail(b.copyOfRange(0, garde), absDebutBloc)
        } else {
            enSilence = false
            silenceGardeRestant = 0
            ajouterAuTravail(b, absDebutBloc)
        }
    }

    private fun ajouterAuTravail(b: FloatArray, absDebut: Long) {
        val posTravail = positionTravail
        val dernier = segments.lastOrNull()
        // Contigu des DEUX cotes => on prolonge le segment, sinon on en ouvre un.
        if (dernier != null &&
            dernier.travailDebut + dernier.longueur == posTravail &&
            dernier.absDebut + dernier.longueur == absDebut
        ) {
            segments[segments.size - 1] = dernier.copy(longueur = dernier.longueur + b.size)
        } else {
            segments.add(Correspondance.Segment(posTravail, absDebut, b.size))
        }

        if (travailTaille + b.size > travail.size) compacter(b.size)
        System.arraycopy(b, 0, travail, travailTaille, b.size)
        travailTaille += b.size

        if (prochaineEmission < 0) prochaineEmission = wMin.toLong()
    }

    /** Ne garde en memoire de travail que ce qu'une fenetre future peut encore
     *  demander (W + un pas de marge). Le flux BRUT, lui, n'est jamais rogne. */
    private fun compacter(besoin: Int) {
        val aGarder = minOf(travailTaille, w + pas)
        val depart = travailTaille - aGarder
        if (depart > 0) {
            System.arraycopy(travail, depart, travail, 0, aGarder)
            travailBase += depart
            travailTaille = aGarder
        }
        if (travailTaille + besoin > travail.size) {
            travail = travail.copyOf(maxOf(travail.size * 2, travailTaille + besoin))
        }
        // Segments devenus inutiles cote travail : on les laisse, ils servent la
        // reconversion vers le flux brut (preuve) longtemps apres la fenetre.
    }

    /**
     * FIN DE SESSION — emet une derniere fenetre calee sur la fin reelle de
     * l'audio, hors grille.
     *
     * Pourquoi c'est necessaire, et pourquoi ce n'est pas un artifice : la
     * grille est pilotee par la CROISSANCE du flux de travail. Quand le
     * recitateur s'arrete, le flux cesse de croitre et plus aucune fenetre
     * n'est emise — le dernier mot resterait provisoire pour toujours. Cette
     * fenetre-ci a un bord gauche ET un bord droit differents de la derniere
     * fenetre de grille : c'est une analyse DISTINCTE (autre normalisation,
     * autre contexte), donc une preuve independante au sens de la couche G, pas
     * la meme preuve comptee deux fois.
     */
    fun terminer(): List<Fenetre> {
        if (enAttente.isNotEmpty()) {
            traiterBloc(enAttente.toFloatArray())
            enAttente.clear()
        }
        val out = ArrayList<Fenetre>(emettre())
        val fin = positionTravail
        val dejaEmise = prochaineEmission - pas
        if (fin - dejaEmise >= Horloge.secondesVersEch(0.3)) {
            val debut = maxOf(travailBase, fin - w)
            val taille = (fin - debut).toInt()
            if (taille >= wMin) {
                val depart = (debut - travailBase).toInt()
                out.add(
                    Fenetre(
                        id = idSuivant++,
                        travailDebut = debut,
                        echantillons = travail.copyOfRange(depart, depart + taille),
                        correspondance = Correspondance(segments).restreindre(debut, fin),
                        pleine = taille >= w,
                    )
                )
            }
        }
        return out
    }

    private fun emettre(): List<Fenetre> {
        val out = ArrayList<Fenetre>()
        while (prochaineEmission in 1..positionTravail) {
            val fin = prochaineEmission
            val debut = maxOf(travailBase, fin - w)
            val taille = (fin - debut).toInt()
            if (taille < wMin) break
            val depart = (debut - travailBase).toInt()
            val ech = travail.copyOfRange(depart, depart + taille)
            out.add(
                Fenetre(
                    id = idSuivant++,
                    travailDebut = debut,
                    echantillons = ech,
                    correspondance = Correspondance(segments).restreindre(debut, fin),
                    pleine = taille >= w,
                )
            )
            prochaineEmission = fin + pas
        }
        return out
    }

    private fun rms(b: FloatArray): Float {
        var acc = 0.0
        for (v in b) acc += v.toDouble() * v
        return sqrt(acc / b.size).toFloat()
    }
}
