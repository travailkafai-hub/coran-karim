package com.corankarim.coran_karim.recitation2

/**
 * L'ORCHESTRATEUR : A -> B -> C -> D -> E -> F -> G.
 *
 * Il ne contient AUCUNE logique de decision. Son seul role est de faire
 * circuler les objets entre des couches qui ne se connaissent pas.
 *
 * Le graphe designe `runAlignment` (reecrit 7 fois) et `OVERLAP_SECONDS`
 * (6 fois) comme les points ou le code n'a JAMAIS converge, et les nomme
 * "la frontiere mal decoupee entre alignement, secours et gestion d'ancre".
 * C'est cette frontiere qui disparait ici : il n'y a plus ni secours (le
 * recouvrement des fenetres fait le travail EN AMONT), ni ancre mutable (la
 * position est reestimee a chaque fenetre), et l'alignement est une fonction
 * pure qui ne connait ni l'un ni l'autre.
 *
 * CE QUI N'EXISTE PLUS, et pourquoi ce n'est pas une omission :
 *   gel / borne dure 12 s / findCutOffset / targetSeconds  -> plus de coupe
 *   RescueBuffer / fenetreDeRecherche / secoursMeilleur     -> recouvrement
 *   findResyncOffset / RESYNC_ACTIF / rattrapage borne      -> couche D
 *   MIN_FRAMES_FOR_JUDGMENT / deferredOnceIndex / fragments -> `interieur`
 * Chacun de ces mecanismes compensait un defaut de segmentation. La
 * segmentation ayant disparu, les reintroduire serait le signal que le
 * probleme est revenu — pas un correctif.
 */
class ChaineRecitation(
    private val front: FrontAcoustique,
    private val tokeniser: (String) -> IntArray,
    /** Tokenise une CONFUSION generee (mot volontairement hors-Coran). Separe de
     *  [tokeniser] parce que ces mots ne sont presque jamais dans le
     *  dictionnaire precalcule : logger chaque repli en ferait des milliers par
     *  sourate (piege deja documente dans CtcTokenizer.tokenizeVariantQuiet).
     *  Par defaut on retombe sur [tokeniser] — les tests JVM n'ont pas besoin
     *  de la distinction. */
    private val tokeniserConfusion: (String) -> IntArray = tokeniser,
    /** Confusions de LETTRE d'un mot. Injectee plutot qu'importee : le paquet
     *  recitation2 ne doit pas dependre de `fastconformer`. */
    private val confusionsLettres: (String) -> List<String> = { emptyList() },
    /** Confusions de HARAKAT. Signal faible sur le modele actuel (7,9 %), tenu
     *  SEPARE des lettres : leur union fait tomber la detection de 30 a 21 %. */
    private val confusionsHarakat: (String) -> List<String> = { emptyList() },
    private val constructeur: ConstructeurDeFenetres = ConstructeurDeFenetres(),
    private val localisateur: Localisateur = Localisateur(front.pieces, front.blank),
    private val aligneur: AligneurForce = AligneurForce(front.pieces, front.blank),
    private val decideur: Decideur = Decideur(),
    private val fluxBrut: FluxBrut = FluxBrut(),
    private val journal: ((String) -> Unit)? = null,
) {
    private var motsAttendus: List<String> = emptyList()
    private var tokensAttendus: List<IntArray> = emptyList()
    private var variantesAttendues: List<List<IntArray>> = emptyList()
    private var confusionsLettresAttendues: List<List<IntArray>> = emptyList()
    private var confusionsHarakatAttendues: List<List<IntArray>> = emptyList()
    private val registre = RegistreDePreuves()
    private var statutsCourants: Map<Int, Statut> = emptyMap()

    /** Dernier mot DEFINITIF — sert de point de depart a la localisation, sans
     *  jamais interdire un recul (le recitateur a le droit de repeter). */
    private var dernierDefinitif = -1

    /** Derniere bande etablie par une fenetre FERMEE sur un silence. Les
     *  apercus la reutilisent au lieu d'en calculer une sur un audio tronque
     *  (cf. la mesure dans [traiter]). */
    private var derniereBande: Localisateur.Bande? = null

    /** De combien de mots un apercu regarde AU-DELA de la derniere bande sure.
     *  Assez pour couvrir ce qui vient d'etre dit entre deux apercus (3 s de
     *  recitation posee), pas assez pour que la DP ait a placer des mots
     *  lointains -- c'est cet entassement qui corrompait la bande. */
    private val motsEnAvanceApercu = 6

    data class Changement(val motIndex: Int, val statut: Statut)

    fun definirTexte(mots: List<String>) {
        motsAttendus = mots
        tokensAttendus = mots.map(tokeniser)
        // Ecritures equivalentes (cf. Orthographe) : la premiere entree est le
        // mot canonique, deja couvert par la DP -- on ne garde que les autres.
        variantesAttendues = mots.map { m ->
            Orthographe.variantes(m).drop(1).map(tokeniser).filter { it.isNotEmpty() }
        }
        // CONCURRENTES : elles se prononcent AUTREMENT. Leur score sert a
        // repondre « l'audio prefere-t-il le mot attendu ou sa confusion la plus
        // plausible ? » -- une question a frontiere naturelle (zero), la ou le
        // gop contre le decodage libre ecrase tous les mots corrects a 0,000 et
        // impose des seuils regles a la main.
        confusionsLettresAttendues = mots.map { m ->
            confusionsLettres(m).map(tokeniserConfusion).filter { it.isNotEmpty() }
        }
        confusionsHarakatAttendues = mots.map { m ->
            confusionsHarakat(m).map(tokeniserConfusion).filter { it.isNotEmpty() }
        }
        decideur.reinitialiser()
        dernierDefinitif = -1
        statutsCourants = emptyMap()
        journal?.invoke("[v2] cible = ${mots.size} mots")
    }

    val preuves: RegistreDePreuves get() = registre

    /**
     * Statuts courants. A LIRE ICI, jamais en rejouant un [Decideur] neuf sur
     * le registre : la couche G est STATEFUL par contrat (un verdict definitif
     * ne change plus jamais), donc une reevaluation en bloc apres coup ne
     * reproduit PAS ce qu'a vu l'utilisateur. Piege tombe dans le banc lui-meme
     * le 2026-07-30 : un mot verrouille VERT ressortait "rouge provisoire" a la
     * relecture, parce que la relecture ne voyait que les 2 dernieres preuves.
     */
    val statuts: Map<Int, Statut> get() = statutsCourants
    val brut: FluxBrut get() = fluxBrut

    /**
     * Point d'entree unique de l'audio.
     * @return les mots dont le statut a CHANGE depuis l'appel precedent.
     */
    fun alimenter(pcm: FloatArray): List<Changement> {
        fluxBrut.ajouter(pcm)
        val changements = ArrayList<Changement>()
        for (fenetre in constructeur.alimenter(pcm)) {
            traiter(fenetre)
        }
        val nouveaux = decideur.statuts(registre, motsAttendus.size)
        for ((i, s) in nouveaux) {
            if (statutsCourants[i] != s) changements.add(Changement(i, s))
            if (s is Statut.Definitif && i > dernierDefinitif) dernierDefinitif = i
        }
        statutsCourants = nouveaux
        return changements
    }

    /**
     * Fin de session : derniere analyse de la queue d'audio, hors grille.
     * Sans cet appel, les derniers mots resteraient PROVISOIRES a jamais — la
     * grille de fenetres cesse d'avancer des que le recitateur se tait
     * (defaut trouve par le banc 2, cf. [ConstructeurDeFenetres.terminer]).
     */
    fun terminer(): List<Changement> {
        val changements = ArrayList<Changement>()
        for (fenetre in constructeur.terminer()) traiter(fenetre)
        val nouveaux = decideur.statuts(registre, motsAttendus.size)
        for ((i, s) in nouveaux) {
            if (statutsCourants[i] != s) changements.add(Changement(i, s))
        }
        statutsCourants = nouveaux
        return changements
    }

    private fun traiter(fenetre: Fenetre) {
        if (motsAttendus.isEmpty()) return
        val logprobs = front.logprobs(fenetre.echantillons)
        if (logprobs.isEmpty()) return

        // LE LOCALISATEUR NE VOIT PAS LA QUEUE TRONQUEE DE L'APERCU.
        //
        // TROIS ESSAIS ONT ECHOUE EN AGISSANT SUR LA BANDE (2026-07-31) :
        //   apercu 2 s, bande libre     :  2,2 s / 52,44 %
        //   apercu 3 s, bande figee     : 11,1 s /  3,29 %
        //   apercu 3 s, ancre + 6 mots  :  8,5 s / 46,52 %
        //   (reference sans apercu      : 10,2 s /  2,61 %)
        // Tous traitaient le SYMPTOME (la bande decroche) au lieu de la cause.
        //
        // LA CAUSE, MESUREE : 95 % des erreurs etaient dans trois blocs
        // CONSECUTIFS, avec `entendu` vide et `free` proche de 0 -- le modele
        // entend bien, on lui demande les mauvais mots. Un apercu est coupe EN
        // PLEINE PAROLE : son dernier mot sort en FRAGMENT, et c'est ce
        // fragment que la LCS de localisation prend pour un mot atteste.
        //
        // On cache donc simplement cette queue au localisateur. Le jugement,
        // lui, garde toutes les frames : l'aligneur a deja sa propre marge
        // droite et sait ne pas juger un mot du bord. Le localisateur, non --
        // c'est la qu'il manquait quelque chose.
        val pourLocaliser = if (fenetre.apercu &&
            logprobs.size > Horloge.LOOKAHEAD_FRAMES * 2) {
            logprobs.copyOfRange(0, logprobs.size - Horloge.LOOKAHEAD_FRAMES)
        } else logprobs

        val bande = localisateur.localiser(
            pourLocaliser, motsAttendus, dernierDefinitif,
            framesMinParMot = { i -> tokensAttendus.getOrNull(i)?.size ?: 0 },
        )
        if (bande == null) {
            // Resultat legitime : la fenetre ne dit rien de la position. Aucun
            // jugement n'en sort — regle "aucun verdict sans preuve acoustique".
            journal?.invoke("[v2] f=${fenetre.id} bande=inconnue " +
                "entendu=\"${Decodage.texte(logprobs, front.pieces, front.blank)}\"")
            return
        }
        if (bande.recul) {
            journal?.invoke("[v2] f=${fenetre.id} RECUL vers le mot ${bande.i0} " +
                "(dernier definitif = $dernierDefinitif) — le recitateur repete")
        }

        val tokens = tokensAttendus.subList(bande.i0, bande.i1 + 1)
        val res = aligneur.aligner(
            logprobs, tokens, bande.i0,
            bordGaucheEstDebutDeSession = fenetre.travailDebut == 0L,
            attestes = bande.attestes,
            variantesParMot = variantesAttendues.subList(bande.i0, bande.i1 + 1),
            confusionsLettresParMot =
                confusionsLettresAttendues.subList(bande.i0, bande.i1 + 1),
            confusionsHarakatParMot =
                confusionsHarakatAttendues.subList(bande.i0, bande.i1 + 1),
        ) ?: return

        // ON REMONTE LA FRONTIERE DU DERNIER MOT SUR AU CONSTRUCTEUR.
        //
        // Inversion de l'ordre : au lieu de couper puis aligner, on aligne puis
        // on coupe a une frontiere CONNUE. L'energie ne porte pas cette
        // information -- une occlusive arabe a une phase peu energique au
        // MILIEU d'un mot -- et le projet l'a mesure : 47,4 % des coupes
        // tombaient en plein mot, et 19 des 22 mots non verts en etaient les
        // victimes.
        //
        // On ne remonte QUE des mots INTERIEURS : un mot du bord peut etre
        // tronque, sa `derniereFrame` ne serait pas sa vraie fin. Et on garde
        // une marge d'une frame, l'alignement CTC etant peaky (il marque le pic
        // du token, pas l'etendue du son) -- c'est ce defaut qui a tue le
        // montage audio dans ce projet.
        res.mots.lastOrNull { it.interieur && it.frames > 0 }?.let { dernier ->
            val fin = fenetre.absoluDeFrame(dernier.derniereFrame + 1)
            if (fin > 0) constructeur.frontiereMotSure(fin)
        }

        for (m in res.mots) {
            val debutAbs = if (m.frames > 0) fenetre.absoluDeFrame(m.premiereFrame) else -1L
            val finAbs = if (m.frames > 0) fenetre.absoluDeFrame(m.derniereFrame) else -1L
            registre.ajouter(
                RegistreDePreuves.Observation(
                    fenetreId = fenetre.id,
                    motIndex = m.index,
                    gop = m.gop,
                    forced = m.forced,
                    free = m.free,
                    entendu = m.entendu,
                    margeLettres = m.margeLettres,
                    margeHarakat = m.margeHarakat,
                    frames = m.frames,
                    interieur = m.interieur && !m.sansCreneau,
                    couvert = m.couvert,
                    sansCreneau = m.sansCreneau,
                    // ATTESTATION EXACTE, pas normalisee : c'est elle qui a le
                    // droit de verrouiller un vert sur une seule observation.
                    atteste = bande.attestesExacts.contains(m.index),
                    fenetrePleine = fenetre.pleine,
                    debutAbs = debutAbs,
                    finAbs = finAbs,
                )
            )
        }

        journal?.invoke(
            "[v2] f=${fenetre.id} duree=${"%.2f".format(fenetre.dureeSecondes)}s " +
                "bande=${bande.i0}..${bande.i1} conf=${"%.2f".format(bande.confiance)} " +
                "interieurs=${res.mots.count { it.interieur }}/${res.mots.size}" +
                if (res.bandeTronquee) " (bande tronquee)" else ""
        )
    }

    /** Journalisation par mot — la trace qui manquait en v1 : le log disait ce
     *  que la chaine avait DECIDE, jamais POURQUOI. Ici chaque observation est
     *  restituable, avec sa fenetre et sa position dans le flux brut. */
    fun tracerMot(i: Int): String {
        val obs = registre.observations(i)
        if (obs.isEmpty()) return "mot $i : aucune observation"
        val sb = StringBuilder("mot $i (${motsAttendus.getOrNull(i)}) :\n")
        for (o in obs) {
            sb.append(
                "  f=${o.fenetreId} ${if (o.interieur) "INTERIEUR" else "bord     "} " +
                    "gop=${"%.2f".format(o.gop)} forced=${"%.2f".format(o.forced)} " +
                    "free=${"%.2f".format(o.free)} frames=${o.frames} " +
                    "entendu=\"${o.entendu}\" abs=[${o.debutAbs},${o.finAbs}]\n"
            )
        }
        sb.append("  statut = ${statutsCourants[i] ?: Statut.Inconnu}")
        return sb.toString()
    }
}
