package com.corankarim.coran_karim.recitation2

import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.exp

/** Participation demandee le 15/09/2026, Hafs uniquement.
 * Cause nouvelle vs mesure_tete3_sans_gain_sur_modele_app : nouvelle tete
 * 1036 entrees, encodeur et corpus differents. Politique EXPERIMENTALE :
 * frontiere brute logit=0 du rapport livre, PAS un seuil a 2 % de collateral.
 * On vote sur l'ecart a l'attendu, jamais sur l'identite du texte libre.
 * Les fenetres chevauchantes ne sont pas des essais independants : une moyenne
 * de leurs activations ne fabrique pas une probabilite par multiplication.
 *
 * ── WARSH AJOUTE LE 15/09/2026, SANS TOUCHER A LA DECISION ─────────────────
 * « Hafs uniquement » ci-dessus decrivait l'etat du jour, pas une exclusion :
 * la riwaya n'entre NULLE PART dans [evaluer] ni [couleur], qui ne lisent que
 * des logits et des poids. Seul le FICHIER de poids change, donc Warsh se
 * branche en ajoutant une [Politique], pas une branche de code.
 * Chaque riwaya porte son empreinte et son logit de reference propres : une
 * tete chargee pour l'autre riwaya est refusee par le controle d'identite,
 * jamais silencieusement acceptee (c'est ce que verifie JugementTete3Test).
 * Les DEUX restent NON CALIBREES (`seuils_mesures` absent des deux fichiers,
 * verifie) : meme frontiere brute, mêmes deux fenetres exigees pour condamner. */
object JugementTete3 {
    /** Ce qui distingue une riwaya de l'autre : un fichier de poids et son
     *  empreinte. Le [logitReference] est celui du vecteur deterministe
     *  `(((i*37) % 101) - 50) / 25` de `reference_parite_tete3_deployee.py` --
     *  la MEME formule des deux cotes, sinon les deux nombres ne se comparent
     *  pas. */
    data class Politique(val riwaya: String, val version: String, val asset: String,
                         val sha256: String, val logitReference: Float)

    val HAFS = Politique(
        riwaya = "hafs",
        version = "HAFS_PARTICULES_BRUT_V1_NON_CALIBRE",
        asset = "tete3_hafs_particules_20260915.json",
        sha256 = "7e708b20a9a13e53f14b0491c36396992bdb2b078c05208215d774837e03b66e",
        logitReference = 37.389693f,
    )

    /** Reconstruite depuis l'audio Warsh continu (9 recitateurs, 155 529 clips
     *  multi-mots contre 13 877 exploitables avant : le manifeste precedent
     *  etait a 99,8 % des clips d'UN SEUL mot, que l'entrainement rejette faute
     *  de contexte). Gain annonce sur 4 categories/5, +1 pt de faux positifs --
     *  annonce du rapport, PAS une mesure faite ici ni sur device. */
    val WARSH = Politique(
        riwaya = "warsh",
        version = "WARSH_V1_BRUT_NON_CALIBRE",
        asset = "tete3_warsh_v1_20260915.json",
        sha256 = "39011c207199533a2bafc63005dd446ae196d70c84a5b3b9d6b025b300bf20a7",
        logitReference = -0.976116f,
    )

    fun pour(riwayaWarsh: Boolean): Politique = if (riwayaWarsh) WARSH else HAFS

    /** Execute aussi sur telephone : identite ET arithmetique Python du paquet.
     * Ne pretend pas verifier l'encodeur ni calibrer la decision. */
    fun chargerVerifiee(bytes: ByteArray, politique: Politique = HAFS): Tete3? {
        val sha = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        if (sha != politique.sha256) return null
        val tete = Tete3.charger(bytes.toString(Charsets.UTF_8)) ?: return null
        if (tete.tailleEntree != 1036) return null
        val reference = FloatArray(1036) { (((it * 37) % 101) - 50) / 25.0f }
        return tete.takeIf { it.verifierParite(reference, politique.logitReference) }
    }

    enum class Etat { INDISPONIBLE, SOUS_FRONTIERE, DOUTE, A_CONFIRMER, ECART }
    data class Contribution(val fenetre: Long, val logit: Float, val activation: Double,
                            val poids: Double)
    data class Avis(val etat: Etat, val activationMoyenne: Double?,
                    val contributions: List<Contribution>) {
        val fenetresEcart: Set<Long> get() = contributions.filter { it.logit > 0f }
            .map { it.fenetre }.toSet()
    }

    fun evaluer(vote: VoteFenetres.Resultat,
                observations: List<RegistreDePreuves.Observation>, minimumPreuves: Int = 2): Avis {
        // Le regroupement temporel est celui du vote texte : aucune seconde
        // logique de position, aucun max pris sur un silence ou un autre son.
        val uniques = observations.associateBy { it.fenetreId }
        val cs = vote.fenetresRetenues.mapNotNull { id ->
            val o = uniques[id] ?: return@mapNotNull null
            val l = o.mesureTete3Jugement?.logit ?: return@mapNotNull null
            val w = o.lectureVote?.confiance?.poids ?: return@mapNotNull null
            if (!l.isFinite() || !w.isFinite() || w <= 0.0 || w > 1.0) return@mapNotNull null
            Contribution(id, l, 1.0 / (1.0 + exp(-l.toDouble())), w)
        }
        if (cs.isEmpty()) return Avis(Etat.INDISPONIBLE, null, cs)
        val moyenne = cs.sumOf { it.poids * it.activation } / cs.sumOf { it.poids }
        val etat = when {
            abs(moyenne - .5) <= 1e-9 -> Etat.DOUTE
            moyenne < .5 -> Etat.SOUS_FRONTIERE
            // Une forte alerte seule peut suspendre le vert, mais il faut au
            // moins deux fenetres favorables a l'ecart pour condamner.
            cs.size != vote.fenetresRetenues.size ||
                cs.count { it.logit > 0f } < maxOf(2, minimumPreuves) -> Etat.A_CONFIRMER
            else -> Etat.ECART
        }
        return Avis(etat, moyenne, cs)
    }

    /** L'absence d'alerte acoustique n'est pas une preuve de transcription
     * correcte. Elle ne peut effacer ni un rouge texte ni une indecision A/B. */
    fun couleur(texte: Couleur, avis: Avis): Couleur = when {
        texte == Couleur.ROUGE -> Couleur.ROUGE
        avis.etat == Etat.ECART -> Couleur.ROUGE
        avis.etat == Etat.A_CONFIRMER || avis.etat == Etat.DOUTE -> Couleur.ORANGE
        else -> texte
    }
}
