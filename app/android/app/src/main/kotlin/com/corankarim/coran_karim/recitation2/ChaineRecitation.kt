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
    private val constructeur: ConstructeurDeFenetres = ConstructeurDeFenetres(),
    private val localisateur: Localisateur = Localisateur(front.pieces, front.blank),
    private val aligneur: AligneurForce = AligneurForce(front.pieces, front.blank),
    private val decideur: Decideur = Decideur(),
    private val fluxBrut: FluxBrut = FluxBrut(),
    private val journal: ((String) -> Unit)? = null,
) {
    private var motsAttendus: List<String> = emptyList()
    private var tokensAttendus: List<IntArray> = emptyList()
    private val registre = RegistreDePreuves()
    private var statutsCourants: Map<Int, Statut> = emptyMap()

    /** Dernier mot DEFINITIF — sert de point de depart a la localisation, sans
     *  jamais interdire un recul (le recitateur a le droit de repeter). */
    private var dernierDefinitif = -1

    data class Changement(val motIndex: Int, val statut: Statut)

    fun definirTexte(mots: List<String>) {
        motsAttendus = mots
        tokensAttendus = mots.map(tokeniser)
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

        val bande = localisateur.localiser(logprobs, motsAttendus, dernierDefinitif)
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
        ) ?: return

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
                    frames = m.frames,
                    interieur = m.interieur,
                    couvert = m.couvert,
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
