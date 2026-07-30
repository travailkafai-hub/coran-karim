package com.corankarim.coran_karim.recitation2

/**
 * COUCHE F — REGISTRE DE PREUVES.
 *
 * CONTRAT : APPEND-ONLY. Aucune observation n'est jamais ecrasee ni supprimee.
 *
 * C'est le remede direct au fait le plus cher du graphe : mesure
 * `benchmark/audio_detruit.py` sur 75 sessions — **100 gels ou la passe finale
 * ne place aucun mot, 825 s d'audio detruites, et 635 mots que les apercus
 * avaient DEJA places dans cet audio**. L'information existait ; elle a ete
 * detruite deux fois, par le recalcul puis par la purge.
 *
 * En v1, chaque passe ECRASAIT le resultat de la precedente ("le final est un
 * alignement neuf sur un buffer neuf"). L'etat de l'art fait l'inverse : le
 * FINAL est emis quand les hypotheses successives CONVERGENT (stable-prefix
 * rule, cf. deflickering / arXiv 2006.01416). Pour pouvoir constater une
 * convergence, il faut garder les hypotheses — c'est tout ce que fait cette
 * couche.
 *
 * Note de methode : la piste "verdict par prefixe stable" avait ete annoncee
 * comme simulable hors device sur les logs existants. VERIFIE FAUX le
 * 2026-07-29 (58 a 70 alignements d'apercu ne laissaient que 0 a 10 verdicts
 * par mot). Ici la donnee existe par construction, et [journal] la rend
 * observable — c'est la passe d'instrumentation qui manquait, faite d'emblee.
 */
class RegistreDePreuves {

    /**
     * @param fenetreId identifie la fenetre — deux observations d'une MEME
     *   fenetre ne peuvent pas se confirmer l'une l'autre (ce serait compter
     *   deux fois la meme preuve).
     * @param fenetrePleine la fenetre avait-elle la duree nominale ? (les
     *   premieres fenetres d'une session sont plus courtes)
     * @param debutAbs/finAbs position de la preuve dans le FLUX BRUT : c'est
     *   avec ca qu'on reextrait l'audio d'un verdict apres coup.
     */
    data class Observation(
        val fenetreId: Long,
        val motIndex: Int,
        val gop: Float,
        val forced: Float,
        val free: Float,
        val entendu: String,
        val frames: Int,
        /** A le droit de VOTER : entierement dans la fenetre, ET pose sur un
         *  audio qui lui appartient (cf. [sansCreneau]). */
        val interieur: Boolean,
        val couvert: Boolean,
        /** L'alignement force a du poser ce mot sur l'audio d'un voisin —
         *  il n'a donc AUCUNE preuve acoustique propre. Cf. AligneurForce. */
        val sansCreneau: Boolean = false,
        /** Le DECODAGE LIBRE a entendu ce mot, a cet endroit, sans qu'on le lui
         *  demande. C'est une mesure INDEPENDANTE de l'alignement force : le
         *  decodage libre ne connait pas le texte attendu. Deux mesures
         *  independantes qui concordent valent mieux que deux fois la meme. */
        val atteste: Boolean = false,
        val fenetrePleine: Boolean,
        val debutAbs: Long,
        val finAbs: Long,
    )

    private val parMot = HashMap<Int, MutableList<Observation>>()

    fun ajouter(o: Observation) {
        parMot.getOrPut(o.motIndex) { ArrayList(4) }.add(o)
    }

    fun observations(motIndex: Int): List<Observation> = parMot[motIndex] ?: emptyList()

    /** Observations qui ont le droit de VOTER (cf. AligneurForce.interieur). */
    fun observationsVotantes(motIndex: Int): List<Observation> =
        observations(motIndex).filter { it.interieur }

    val motsObserves: Set<Int> get() = parMot.keys

    /** Plus grand index de mot ayant recu au moins une observation votante —
     *  le denominateur honnete d'un taux (compter sur les mots JUGES ferait
     *  sortir du calcul tout mot jamais observe : erreur deja commise). */
    fun indexMaxVotant(): Int =
        parMot.entries.filter { e -> e.value.any { it.interieur } }
            .maxOfOrNull { it.key } ?: -1

    fun total(): Int = parMot.values.sumOf { it.size }
}
