package com.corankarim.coran_karim.recitation2

import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln

/** Mesure du chemin LIBRE, sans lecture du texte attendu ni du GOP.
 * Les poids sont des candidats de calibration, PAS des probabilites de justesse.
 * Le maximum de chaque run CTC non blanc compte une fois : les blancs et la
 * duree d'un token ne doivent pas fabriquer de nouvelles confirmations. */
object ConfianceLectureCtc {
    const val SOURCE = "pics_ctc_geometrique_v1_NON_CALIBRE"
    data class Mesure(val poids: Double, val tokens: Int, val minimum: Double,
                      val confianceEntropie: Double)

    fun mesurer(logp: Array<FloatArray>, blank: Int, de: Int, a: Int): Mesure? {
        if (de < 0 || a < de || a >= logp.size) return null
        val pics = ArrayList<Pair<Double, Double>>()
        var precedent = -1
        var pic = Double.NEGATIVE_INFINITY
        var entropieAuPic = 0.0
        fun terminerRun() {
            if (precedent >= 0 && precedent != blank) pics.add(pic to entropieAuPic)
        }
        for (t in de..a) {
            val frame = logp[t]
            if (blank !in frame.indices || frame.size < 2 ||
                frame.any { it.isNaN() || it == Float.POSITIVE_INFINITY || it > 0f }) return null
            val id = Decodage.argmax(frame)
            if (id != precedent) { terminerRun(); pic = Double.NEGATIVE_INFINITY }
            if (id != blank && frame[id].toDouble() > pic) {
                pic = frame[id].toDouble()
                var h = 0.0
                for (lp in frame) if (lp.isFinite()) h -= exp(lp.toDouble()) * lp
                entropieAuPic = (1.0 - h / ln(frame.size.toDouble())).coerceIn(0.0, 1.0)
            }
            precedent = id
        }
        terminerRun()
        if (pics.isEmpty() || pics.any { !it.first.isFinite() }) return null
        return Mesure(exp(pics.map { it.first }.average()), pics.size,
            exp(pics.minOf { it.first }), pics.map { it.second }.average())
    }
}

/** Comparaison en observation seulement. Ne produit ni couleur ni Statut.
 * Graphe : piege_verrou_sur_apercu, attente_sens_unique_provisoire,
 * piege_attestation_normalisee_blanchit et piege_gop_vs_free.
 * Cause nouvelle : demande explicite du 15/09 de comparer A/B/C, au lieu de
 * conserver la meilleure couleur historique. La calibration et la cloture
 * du vote en streaming restent a mesurer avant activation dans Decideur. */
object VoteFenetres {
    data class Lecture(
        val confiance: ConfianceLectureCtc.Mesure?,
        val exclusion: String?,
        val fenetreDebut: Long,
        val fenetreFin: Long,
    )
    data class Candidat(val texte: String, val poids: Double, val fenetres: List<Long>)
    data class Resultat(val candidats: List<Candidat>, val gagnant: String?,
                        val etat: String, val exclusions: Map<String, Int>,
                        /** Meme occurrence et memes exclusions pour le juge acoustique.
                         * Vide si l'attribution temporelle demeure ambigue. */
                        val fenetresRetenues: Set<Long> = emptySet())

    /** NFC ne retire aucune lettre/haraka ; la normalisation de localisation
     * est INTERDITE ici. Le texte attendu n'entre jamais dans l'agregateur.
     * 15/09, T805/0 : تَبَـٰرَكَ et sa variante تَبَـارَكَ etaient compares a
     * تَبَارَكَ avec le trait typographique U+0640 intact : faux rouge malgre
     * trois lectures concordantes. Seule cette kashida decorative est retiree,
     * jamais l'alif suscrit (voyelle longue), une consonne ou une haraka. */
    fun cle(texte: String): String =
        Normalizer.normalize(texte.trim().replace("\u0640", ""), Normalizer.Form.NFC)

    fun mesurer(m: AligneurForce.MotAligne, libres: List<Decodage.MotEntendu>,
                logp: Array<FloatArray>, blank: Int, fenetre: Fenetre): Lecture {
        val recouvrants = libres.filter {
            it.premiereFrame <= m.derniereFrame && it.derniereFrame >= m.premiereFrame
        }
        val libre = recouvrants.singleOrNull()
        val exclusion = when {
            m.frames <= 0 || m.premiereFrame < 0 || m.derniereFrame < m.premiereFrame -> "sans_frames"
            m.sansCreneau -> "sans_creneau"
            !m.interieur -> "bord_fenetre"
            m.entendu.isBlank() -> "lecture_vide"
            libre == null -> "attribution_libre_ambigue"
            // Une DP peut couper la tenue d'un token sans perdre une lettre :
            // vwy est complet, meme si le dernier run y continue deux frames.
            // Le texte libre ENTIER doit etre identique ; AB dans ABC reste
            // un fragment exclu. Mesure du banc de flux du 15/09/2026.
            (libre.premiereFrame < m.premiereFrame || libre.derniereFrame > m.derniereFrame) &&
                cle(libre.texte) != cle(m.entendu) -> "fragment_alignement"
            cle(libre.texte) != cle(m.entendu) -> "lecture_non_complete"
            else -> null
        }
        // `couvert` depend de la longueur ATTENDUE : le filtrer effacerait
        // les vraies troncatures prononcees. Une frame CTC peut etre un mot.
        return Lecture(ConfianceLectureCtc.mesurer(logp, blank, m.premiereFrame, m.derniereFrame),
            exclusion, fenetre.travailDebut, fenetre.travailFin)
    }

    fun calculer(observations: List<RegistreDePreuves.Observation>): Resultat {
        val exclusions = linkedMapOf<String, Int>()
        fun exclure(raison: String) { exclusions[raison] = (exclusions[raison] ?: 0) + 1 }
        val uniques = LinkedHashMap<Long, RegistreDePreuves.Observation>()
        for (o in observations) {
            if (uniques.put(o.fenetreId, o) != null) exclure("revision_meme_fenetre")
        }
        val contextes = HashSet<Pair<Long, Long>>()
        val votes = ArrayList<RegistreDePreuves.Observation>()
        var incomplete = false
        for (o in uniques.values.sortedBy { it.fenetreId }) {
            val lecture = o.lectureVote
            val poids = lecture?.confiance?.poids
            val raison = when {
                !o.interieur -> "bord_fenetre"
                o.sansCreneau -> "sans_creneau"
                o.entendu.isBlank() -> "lecture_vide"
                o.debutAbs < 0 || o.finAbs < o.debutAbs -> "intervalle_invalide"
                lecture == null -> "mesure_absente"
                lecture.exclusion != null -> lecture.exclusion
                poids == null || !poids.isFinite() || poids !in 0.0..1.0 -> "poids_absent_ou_invalide"
                poids == 0.0 -> "poids_nul"
                else -> null
            }
            if (raison != null) {
                exclure(raison)
                if (raison == "mesure_absente" || raison == "poids_absent_ou_invalide") incomplete = true
                continue
            }
            // Deux ids portant exactement le meme contexte audio = une mesure.
            if (!contextes.add(lecture!!.fenetreDebut to lecture.fenetreFin)) {
                exclure("contexte_duplique"); continue
            }
            votes.add(o)
        }
        // Meme index ne prouve pas meme occurrence. On regroupe d'abord les
        // plages qui se recouvrent : les fenetres glissantes d'un meme son
        // retombent normalement sur le meme paquet de frames. Une attribution
        // parasite peut toutefois placer le mot beaucoup plus loin (mesure
        // T023 : trois lectures de "...ونَ" a 130560..142080, puis "إِلَىٰ"
        // a 193280..202240). Un indicateur global "il existe deux plages
        // disjointes" faisait alors disparaitre le vote majoritaire utile.
        //
        // Les composantes restent separees par prudence. Nous ne retenons une
        // composante parmi plusieurs que si elle a un gagnant strict soutenu
        // par au moins deux fenetres et domine chaque autre composante. Une
        // seule lecture eloignee ne peut donc ni blanchir ni rougir le mot ;
        // deux composantes solides restent un doute. Cette regle conserve le
        // cas historique A/A sur deux plages disjointes comme ambigu.
        fun recouvre(a: RegistreDePreuves.Observation,
                     b: RegistreDePreuves.Observation): Boolean =
            a.debutAbs <= b.finAbs + Horloge.ECH_PAR_FRAME &&
                b.debutAbs <= a.finAbs + Horloge.ECH_PAR_FRAME
        val composantes = ArrayList<MutableList<RegistreDePreuves.Observation>>()
        for (o in votes.sortedBy { it.debutAbs }) {
            val rejoint = composantes.indices.filter { c ->
                composantes[c].any { recouvre(it, o) }
            }
            if (rejoint.isEmpty()) composantes.add(arrayListOf(o))
            else {
                val premiere = rejoint.first()
                composantes[premiere].add(o)
                for (c in rejoint.drop(1).asReversed()) {
                    composantes[premiere].addAll(composantes.removeAt(c))
                }
            }
        }
        data class Bloc(val votes: List<RegistreDePreuves.Observation>,
                        val candidats: List<Candidat>, val total: Double,
                        val gagnant: Candidat?, val opposition: Double) {
            val majoritaire: Boolean
                get() = gagnant != null && gagnant.poids > opposition &&
                    abs(gagnant.poids - opposition) > 1e-9
        }
        fun bloc(vs: List<RegistreDePreuves.Observation>): Bloc {
            val cs = vs.groupBy { cle(it.entendu) }.map { (texte, obs) ->
                Candidat(texte, obs.sumOf {
                    it.lectureVote!!.confiance!!.poids
                }, obs.map { it.fenetreId })
            }.sortedWith(compareByDescending<Candidat> { it.poids }.thenBy { it.texte })
            val t = cs.firstOrNull()
            return Bloc(vs, cs, cs.sumOf { it.poids }, t,
                cs.drop(1).sumOf { it.poids })
        }
        val blocs = composantes.map(::bloc)
        val blocChoisi = when {
            blocs.isEmpty() -> null
            blocs.size == 1 -> blocs.first()
            else -> {
                val solides = blocs.filter {
                    it.majoritaire && it.gagnant!!.fenetres.size >= 2
                }
                if (solides.size == 1 && solides.all { solide ->
                        blocs.filter { it !== solide }.all {
                            solide.total > it.total
                        }
                    }) solides.first() else null
            }
        }
        val candidats = (blocChoisi?.candidats ?: blocs.flatMap { it.candidats })
            .sortedWith(compareByDescending<Candidat> { it.poids }.thenBy { it.texte })
        if (blocChoisi != null && blocs.size > 1) {
            val ecartes = blocs.filter { it !== blocChoisi }.sumOf { it.votes.size }
            if (ecartes > 0) exclusions["occurrence_non_retenue"] = ecartes
        }
        val tete = blocChoisi?.gagnant
        val opposition = blocChoisi?.opposition ?: 0.0
        val majoritaire = blocChoisi?.majoritaire == true
        val ambigu = votes.isNotEmpty() && composantes.size > 1 && blocChoisi == null
        val etat = when {
            incomplete -> "INCOMPLET"
            ambigu -> "OCCURRENCE_AMBIGUE"
            !majoritaire -> "INDECIS"
            else -> "HYPOTHESE_PROVISOIRE"
        }
        return Resultat(candidats, if (etat == "HYPOTHESE_PROVISOIRE") tete!!.texte else null,
            etat, exclusions, if (incomplete) emptySet()
                else blocChoisi?.votes?.map { it.fenetreId }?.toSet() ?: emptySet())
    }
}
