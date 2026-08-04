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
    /**
     * Fenetre APERCU : coupee en pleine parole, sans le silence de droite.
     *
     * MESURE QUI IMPOSE DE LA DISTINGUER (2026-07-31) : avec des apercus toutes
     * les 2 s, 113 mots non verts dont **95 % dans 3 BLOCS CONSECUTIFS**
     * (103-138, 144-209, 219-223), 66 avec `entendu` vide et 51 avec `free`
     * proche de 0. Ce n'est pas un verrouillage hatif -- celui-la donnerait des
     * erreurs EPARSES. C'est la signature d'une BANDE PARTIE AU MAUVAIS
     * ENDROIT : le modele entend parfaitement, on lui demande les mauvais mots,
     * pendant 66 mots d'affilee.
     * Cause : le dernier mot d'un apercu est coupe, il sort en fragment, et la
     * LCS de localisation s'appuie dessus pour poser la bande.
     */
    val apercu: Boolean = false,
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
     *
     * ── 2026-07-31 : PASSAGE A 0,35, demande utilisateur, A MESURER SUR DEVICE ──
     * Le tableau ci-dessus reste vrai et n'est pas efface : il donne 0,35 a
     * 2,71 % contre 2,03 % pour 0,40. MAIS il a ete etabli HORS DEVICE, et cet
     * ecart de 0,68 point est INDISCERNABLE du bruit du banc reel -- deux passes
     * identiques ont donne 2,03 % et 2,71 % le meme soir, sur le meme audio et le
     * meme binaire. Le projet a deja paye deux fois une prediction hors device
     * confiante et fausse (cf. memoire "les bancs hors ligne doivent reproduire
     * l'entree partielle").
     * Ce que le balayage ne peut PAS voir et qui motive l'essai : il compare des
     * taux a decoupage fige, alors que sur device la pause gouverne aussi QUAND
     * la fenetre part, donc la reactivite. 104 blocs contre 102 : le cout attendu
     * est faible.
     * 0,25 a ete essaye et REJETE (echec constate par l'utilisateur) -- ne pas y
     * revenir sans cause nouvelle nommee.
     * ⚠️ Si la recette device confirme une degradation reelle (hors bruit), la
     * valeur revient a 0,40 : le plateau 0,40-0,45 est la seule zone ou deux
     * reglages voisins donnent le MEME chiffre, ce qui est la vraie preuve de
     * robustesse, alors que 0,35 est un bord de plateau.
     */
    private val pauseMinSecondes: Double = 0.35,
    /** Cf. [pauseMinSecondes] : les deux se lisent ensemble. 0,02 etait herite
     *  du portier RMS de la v1, ou il servait a JETER de l'audio ; ici il sert a
     *  DETECTER une frontiere, ce n'est pas le meme role et pas la meme valeur.
     *
     *  N'est plus utilise que comme valeur de DEMARRAGE et comme repli, depuis
     *  que le seuil est adaptatif (cf. [seuilAdaptatif]). */
    private val seuilRmsSilence: Float = 0.03f,
    /**
     * SEUIL ADAPTATIF — le seuil de silence suit le NIVEAU DE LA VOIX.
     *
     * ── LA MESURE QUI L'IMPOSE (2026-07-30) ─────────────────────────────────
     * Meme recitation, meme code, on change SEULEMENT le gain du signal (ce que
     * fait une voix plus douce, ou un micro plus loin) :
     *
     *     gain x0,4   287 blocs   15,93 % de mots non verts
     *     gain x0,7   145 blocs    5,08 %
     *     gain x1,0   102 blocs    2,03 %   <- le reglage
     *     gain x1,5    49 blocs   65,76 %
     *     gain x2,5    39 blocs   73,22 %
     *
     * +50 % de volume et la chaine s'effondre. Un seuil ABSOLU sur un signal
     * dont le niveau depend de la voix et de la distance au micro ne peut pas
     * marcher : c'est le defaut que le projet avait deja nomme pour le portier
     * de la v1 (« voix douce / micro eloigne -> debut de mot classe silence »),
     * jamais corrige.
     *
     * ── LA VALEUR, DERIVEE ET NON REGLEE ────────────────────────────────────
     * Sur la recitation de reference, le seuil qui marche (0,03) vaut
     * exactement 0,344 x le percentile 75 des RMS de bloc. Le p75 est un
     * estimateur du NIVEAU DE PAROLE ; le rapport, lui, est invariant au gain.
     * On garde donc le rapport et on recalcule le niveau en continu.
     *
     * Pourquoi un rapport au niveau de parole plutot qu'un percentile fixe :
     * un percentile suppose que la PROPORTION de silence est la meme chez tous
     * les recitateurs. Elle ne l'est pas -- quelqu'un qui respire plus souvent
     * en aurait plus. Le contraste parole/silence, lui, est une propriete de la
     * voix et du micro, bien plus stable.
     */
    private val seuilAdaptatif: Boolean = true,
    /** Fenetre glissante d'estimation du niveau de parole. 30 s : assez long
     *  pour contenir de la parole meme pendant une longue pause, assez court
     *  pour suivre un recitateur qui s'eloigne du micro en cours de session. */
    private val fenetreNiveauSecondes: Double = 30.0,
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
    /**
     * APERCU PERIODIQUE — cadence a laquelle on emet une fenetre NON FINALE,
     * sans attendre le silence qui ferme le bloc. 0 = desactive (comportement
     * d'avant).
     *
     * MESURE QUI L'IMPOSE (2026-07-31, meme sourate, meme modele, meme audio) :
     *                     rafales  mots/rafale  attente entre rafales  >5 s
     *   v1 (27/07)           98         2             1,7 s            9
     *   v2 par blocs         28         8            10,2 s           23
     * Les mots sortent UN PAR UN des deux cotes : la « validation groupee »
     * n'est pas plusieurs mots simultanes, c'est une longue ATTENTE suivie
     * d'une rafale. La v2 attend 6x plus longtemps que la v1.
     *
     * L'apercu ne change RIEN au jugement : le Decideur exige deux
     * observations de fenetres DISTINCTES pour verrouiller, et l'aligneur
     * refuse deja de juger un mot situe dans le dernier lookahead. Un apercu
     * apporte donc une PREMIERE observation plus tot, jamais un verrou hatif --
     * c'est la difference avec la v1, dont le defaut mesure etait justement de
     * verrouiller sur un apercu ([PIEGE] verrou_sur_apercu).
     *
     * COUT : l'apercu retraite l'audio depuis la derniere coupe. C'est la
     * pathologie de la v1 (21 s traitees pour 7 s de parole) -- bornee ici par
     * la cadence ET par maxBloc. A surveiller sur le temps reel.
     */
    private val apercuSecondes: Double = 0.0,
    /** Longueur FIXE de la fenetre glissante d'apercu (cf. [fenetreApercuEch]).
     *  Parametrable depuis le 2026-08-02 (porte depuis la branche `streaming`)
     *  pour pouvoir BALAYER le couple (pas, largeur) au banc JVM : c'est le
     *  seul moyen de trancher entre des configurations dont la mesure a deja
     *  montre qu'elles ne se devinent pas (quatre essais perdants le
     *  2026-07-31). */
    private val fenetreApercuSecondes: Double = 9.0,
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
    private val apercuEch: Long = if (apercuSecondes > 0)
        Horloge.secondesVersEch(apercuSecondes).toLong() else 0L
    private var dernierApercu: Long = 0L

    /**
     * Fin ABSOLUE du dernier mot dont l'alignement est sûr, renseignée par la
     * couche au-dessus (cf. [frontiereMotSure]).
     *
     * POURQUOI CE RETOUR D'INFORMATION. La coupe était décidée sur l'ÉNERGIE,
     * or l'énergie ne porte pas la frontière de mot : une occlusive arabe
     * (ب ذ ن ق ت) a une phase peu énergique AU MILIEU d'un mot, acoustiquement
     * identique à une pause. Mesure du projet (2026-07-28) : **47,4 % des
     * coupes tombaient en plein mot**, et 19 des 22 mots non verts étaient les
     * victimes de ces coupes.
     *
     * L'information existe pourtant déjà dans la chaîne : l'alignement forcé
     * rend `premiereFrame`/`derniereFrame` de chaque mot. On INVERSE donc
     * l'ordre — au lieu de couper puis aligner, on aligne puis on coupe à la
     * frontière connue. C'est ce que la littérature appelle une segmentation
     * *word-boundary-aware* (WhisperAlign : « partitionner l'audio en segments
     * respectant strictement les frontières de mots »).
     *
     * ⚠️ RÉSERVE : l'alignement CTC est *peaky* — il marque la frame où le
     * token culmine, pas l'étendue du son. La frontière peut donc être décalée
     * de quelques frames. C'est le défaut qui a tué le montage audio dans ce
     * projet. On garde une marge, et on ne s'en sert QUE quand aucun vrai
     * silence n'a été trouvé — jamais à la place d'un silence réel, qui reste
     * la meilleure frontière possible.
     */
    private var finDernierMotSur: Long = -1L
    /** Un apercu plus court que ceci ne rend aucune frame utilisable : il faut
     *  au moins le lookahead du modele, plus de quoi couvrir un mot. */
    /** Longueur FIXE de la fenetre glissante d'apercu. Assez pour donner au
     *  modele son contexte gauche (5,6 s) plus de quoi juger quelques mots ;
     *  pas plus, sinon on retombe sur la fenetre qui grossit. */
    private val fenetreApercuEch: Long = Horloge.secondesVersEch(fenetreApercuSecondes).toLong()
    private val apercuMinEch: Long =
        Horloge.secondesVersEch(Horloge.LOOKAHEAD_FRAMES * 0.08 + 2.0).toLong()

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

    // ── Estimation continue du niveau de parole (cf. seuilAdaptatif) ────────
    private val tailleNiveau = (fenetreNiveauSecondes * Horloge.TAUX / bloc).toInt()
    private val niveaux = FloatArray(tailleNiveau)
    private var niveauxRemplis = 0
    private var niveauxPos = 0
    private val tri = FloatArray(tailleNiveau)

    /** Seuil courant : rapport fixe au niveau de parole observe, ou la valeur
     *  de demarrage tant qu'on n'a pas assez de signal pour l'estimer. */
    private fun seuilCourant(): Float {
        if (!seuilAdaptatif || niveauxRemplis < MIN_BLOCS_NIVEAU) return seuilRmsSilence
        System.arraycopy(niveaux, 0, tri, 0, niveauxRemplis)
        java.util.Arrays.sort(tri, 0, niveauxRemplis)
        val p75 = tri[(niveauxRemplis * 75) / 100]
        return (RAPPORT_SEUIL_NIVEAU * p75).coerceIn(SEUIL_MIN, SEUIL_MAX)
    }

    private fun noterNiveau(r: Float) {
        niveaux[niveauxPos] = r
        niveauxPos = (niveauxPos + 1) % tailleNiveau
        if (niveauxRemplis < tailleNiveau) niveauxRemplis++
    }

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
        val seuil = seuilCourant()
        noterNiveau(r)

        if (r < seuil) {
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

        // APERCU : une fenetre NON FINALE sur le bloc en cours, pour que les
        // mots deja prononces recoivent leur premiere observation sans
        // attendre le silence. Emis seulement s'il y a de quoi juger (minEch)
        // et si la cadence est ecoulee.
        // MESURE QUI IMPOSE `apercuMinEch` ET NON `minEch` (2026-07-31) :
        // autoriser l'apercu des 0,8 s a produit 975 fenetres au lieu de ~30,
        // TOUTES avec `bande=inconnue entendu=""`. Un bloc de 0,8 s est plus
        // court que le lookahead du modele causal (1,04 s) : il ne rend AUCUNE
        // frame de sortie exploitable. La chaine a ete inondee de fenetres
        // vides et n'a plus rien localise du tout.
        if (apercuEch > 0 &&
            positionTravail - derniereCoupe >= apercuMinEch &&
            positionTravail - dernierApercu >= apercuEch) {
            dernierApercu = positionTravail
            // CURSEUR GLISSANT, PAS FENETRE QUI GROSSIT (idee utilisateur,
            // 2026-07-31). Les quatre essais precedents partaient tous de
            // `derniereCoupe` : la fenetre grossissait jusqu'a 30 s et etait
            // RELOCALISEE ENTIEREMENT toutes les 3 s. La LCS de localisation
            // devait alors reapparier des dizaines de mots a chaque fois, et
            // c'est la qu'elle decrochait -- 95 % des erreurs en blocs
            // consecutifs.
            // Ici la fenetre a une LONGUEUR FIXE et AVANCE. Chaque appel
            // reappariee toujours le meme nombre de mots, et un mot coupe au
            // bord n'est pas juge : il le sera au passage suivant, quand le
            // curseur l'aura amene au centre (l'aligneur refuse deja de juger
            // un mot situe dans le dernier lookahead).
            val debutApercu = maxOf(derniereCoupe, positionTravail - fenetreApercuEch)
            return listOf(bloquer(debutApercu, positionTravail,
                                  fusion = false, apercu = true))
        }

        // GARDE-FOU de domaine : jamais de bloc plus long que les clips
        // d'entrainement. On coupe alors au point le plus SILENCIEUX vu depuis
        // la derniere coupe -- le moins mauvais endroit, pas un endroit choisi.
        if (positionTravail - derniereCoupe >= maxEch) {
            // PRIORITÉ À LA FRONTIÈRE DE MOT quand elle est disponible et
            // utilisable : c'est la seule grandeur qui porte réellement
            // l'information cherchée. L'énergie reste le repli — mieux vaut
            // l'ancienne politique que pas de coupe.
            val frontiere = finDernierMotSur
            val cible = when {
                frontiere > derniereCoupe + minEch && frontiere <= positionTravail -> frontiere
                posMinRms > derniereCoupe + minEch -> posMinRms
                else -> positionTravail
            }
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
        // NE PAS reinitialiser `dernierApercu` ici : la cadence d'apercu doit
        // etre INDEPENDANTE des coupes.
        //
        // MESURE QUI L'IMPOSE (2026-07-31) : en repartant de chaque coupe, deux
        // passes sur le MEME audio produisaient 159 et 170 fenetres. Les
        // fenetres ne tombaient donc pas aux memes endroits, et un mot juge au
        // CENTRE dans une passe se retrouvait au BORD dans l'autre -- ou il est
        // mal juge. C'est la source du bruit qui a rendu le banc inutilisable :
        // 2,37 %, 3,05 % et 4,41 % mesures sur la meme configuration a un
        // changement favorable pres, tous indiscernables.
        //
        // Avec une cadence sur l'horloge absolue, le decoupage devient
        // reproductible et un ecart d'un demi-point redevient interpretable.
        // Le projet paie ce defaut depuis longtemps : « une passe n'est pas une
        // mesure » etait un contournement, pas une fatalite.
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

    /** Renseigné par [ChaineRecitation] après chaque alignement : fin absolue
     *  du dernier mot ENTIÈREMENT contenu dans la fenêtre. Cf.
     *  [finDernierMotSur] pour la mesure qui impose ce retour d'information. */
    fun frontiereMotSure(finAbsolue: Long) {
        if (finAbsolue > finDernierMotSur) finDernierMotSur = finAbsolue
    }

    private fun bloquer(debut: Long, fin: Long, fusion: Boolean,
                        apercu: Boolean = false): Fenetre {
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
            apercu = apercu,
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

    private companion object {
        /** 0,344 = 0,03 / p75 mesure sur la recitation de reference. Ce n'est
         *  pas un reglage : c'est le rapport qui reproduit exactement le seuil
         *  valide, rendu invariant au gain. */
        const val RAPPORT_SEUIL_NIVEAU = 0.344f
        /** Bornes de securite : une piece totalement silencieuse ou saturee ne
         *  doit pas produire un seuil absurde. */
        const val SEUIL_MIN = 0.004f
        const val SEUIL_MAX = 0.20f
        /** 2 s de signal avant d'oser estimer un niveau. */
        const val MIN_BLOCS_NIVEAU = 25
    }

    private fun rms(b: FloatArray): Float {
        var acc = 0.0
        for (v in b) acc += v.toDouble() * v
        return sqrt(acc / b.size).toFloat()
    }
}
