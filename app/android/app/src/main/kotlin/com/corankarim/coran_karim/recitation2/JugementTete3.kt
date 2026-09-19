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
        // FRONTIERE = LE SEUIL MESURE, quand la tete en porte un (2026-09-17).
        // `Tete3.Mesure` transporte `seuil2Pct` depuis toujours ; personne ne le
        // lisait, et la frontiere brute 0 etait appliquee a toutes les tetes.
        // C'etait sans consequence tant qu'aucune tete calibree n'existait --
        // `tete3_hafs_v2` est la premiere. Sans ce branchement, elle serait
        // mesuree BRIDEE dans l'ancienne politique, et son seuil (-1,782) ne
        // servirait a rien. `Tete3.kt` previent d'ailleurs explicitement :
        // « une calibration absente n'est PAS un seuil de zero » -- l'inverse
        // vaut aussi, un seuil present n'est pas zero non plus.
        //
        // ⚠️ MESURE DU 17/09 : ACTIVER CE SEUIL DEGRADE. Sur les paliers
        // 0/20/40 %, avec `tete3_hafs_v2` et son seuil -1,782 :
        //     frontiere 0      -> 83/130 detectees, 57 faux
        //     seuil -1,782     -> 83/130 detectees, 76 faux  (+19, 0 detection)
        // et sur le temoin SANS faute, les faux passent de 12,5 % a 18,8 %.
        // La raison est structurelle : PC A calibre sur des mots ISOLES, la
        // decision agrege 2 a 3 fenetres par mot avec une moyenne ponderee --
        // les deux distributions de logits n'ont pas la meme dispersion, donc
        // le seuil de l'une ne vaut pas pour l'autre. C'est la reserve deja
        // posee le 15/09 sur les seuils -2,222 / +3,099, et elle est confirmee.
        //
        // Le seuil reste donc LU mais DESACTIVE par defaut ; `-DseuilTete3=true`
        // le rebranche pour mesurer. Ne pas l'activer sans une calibration
        // faite sur des logits AGREGES, pas sur des clips.
        val seuil = if (System.getProperty("seuilTete3") == "true")
            observations.firstNotNullOfOrNull { it.mesureTete3Jugement?.seuil2Pct }
                ?.takeIf { it.isFinite() } ?: 0f
        else 0f
        val frontiere = 1.0 / (1.0 + exp(-seuil.toDouble()))
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
            abs(moyenne - frontiere) <= 1e-9 -> Etat.DOUTE
            moyenne < frontiere -> Etat.SOUS_FRONTIERE
            // Une forte alerte seule peut suspendre le vert, mais il faut au
            // moins deux fenetres favorables a l'ecart pour condamner.
            cs.size != vote.fenetresRetenues.size ||
                cs.count { it.logit > seuil } < maxOf(2, minimumPreuves) -> Etat.A_CONFIRMER
            else -> Etat.ECART
        }
        return Avis(etat, moyenne, cs)
    }

    /**
     * VARIANTE SANS VOTE (2026-09-15) — pour la chaine HISTORIQUE.
     *
     * Pourquoi elle existe : [evaluer] itere sur `vote.fenetresRetenues` et
     * pondere par `lectureVote.confiance.poids`. Ni l'un ni l'autre n'existe
     * hors du vote, si bien que la question « la tete 3 sert-elle SANS le
     * vote ? » n'avait aucune reponse mesurable -- alors que la campagne du
     * 15/09 a montre que le vote coute trois accusations fausses par detection
     * gagnee, donc qu'on pourrait vouloir la tete sans lui.
     *
     * ⚠️ LES FRAGMENTS DE BORD SONT EXCLUS, ET C'EST INDISPENSABLE.
     * Premiere version de cette fonction : elle gardait TOUTE observation
     * votante. Mesure du 15/09 sur les archives -- +2 detections pour +30 faux
     * signalements, et le detail montrait toujours le meme motif :
     *     mot 14 `رَفَعَهَا`, temoin SANS AUCUNE FAUTE
     *       f33 entendu "عَهَا"     gop -2,49  logit  +7,81
     *       f34 entendu "رَفَعَهَا"  gop  0,00  logit  -7,47
     *       f37 entendu "عَهَا"     gop -2,75  logit  +7,00
     * La fenetre qui voit le mot ENTIER ne s'alarme pas ; celles qui l'ont
     * COUPE AU BORD crient. Le vote, lui, ecarte ces lectures
     * (`fragment_alignement`, `lecture_non_complete`) : il ne masquait donc pas
     * les erreurs de la tete, il la PROTEGEAIT. Comparer sans ce filtre
     * mesurait le bord de fenetre, pas la tete.
     * Meme cause que le decrochage sur audio correct (cf. PROBLEMATIQUES_ASR).
     *
     * ⚠️ CE QU'ON PERD MALGRE TOUT. Le regroupement d'occurrence disparait :
     * deux lectures d'un mot separees de plusieurs secondes sont agregees comme
     * si elles portaient sur le meme son -- ce que [evaluer] refuse (« aucun max
     * pris sur un silence ou un autre son », cf. T023). Les poids uniformes sont
     * le second renoncement : la chaine historique ne mesure aucune confiance.
     */
    fun evaluerSansVote(observations: List<RegistreDePreuves.Observation>,
                        attendu: String, minimumPreuves: Int = 2): Avis {
        val cible = VoteFenetres.cle(attendu)
        val votantes = observations.filter {
            it.interieur && !it.sansCreneau && it.entendu.isNotBlank() &&
                !estFragment(VoteFenetres.cle(it.entendu), cible)
        }
        val cs = votantes.mapNotNull { o ->
            val l = o.mesureTete3Jugement?.logit ?: return@mapNotNull null
            if (!l.isFinite()) return@mapNotNull null
            Contribution(o.fenetreId, l, 1.0 / (1.0 + exp(-l.toDouble())), 1.0)
        }
        if (cs.isEmpty()) return Avis(Etat.INDISPONIBLE, null, cs)
        val moyenne = cs.sumOf { it.activation } / cs.size
        val etat = when {
            abs(moyenne - .5) <= 1e-9 -> Etat.DOUTE
            moyenne < .5 -> Etat.SOUS_FRONTIERE
            // Meme exigence que [evaluer] : une alerte isolee suspend le vert,
            // il faut deux fenetres favorables a l'ecart pour condamner. Et
            // toutes les observations votantes doivent avoir une mesure, sinon
            // on conclurait sur un sous-ensemble choisi par l'absence.
            cs.size != votantes.size ||
                cs.count { it.logit > 0f } < maxOf(2, minimumPreuves) -> Etat.A_CONFIRMER
            else -> Etat.ECART
        }
        return Avis(etat, moyenne, cs)
    }

    /** Un MORCEAU du mot attendu, dans un sens ou dans l'autre -- la fenetre a
     *  coupe, ou elle a deborde. Une lecture franchement AUTRE n'en est pas un :
     *  celle-la porte un vrai signal et doit rester. */
    private fun estFragment(entendu: String, attendu: String): Boolean =
        entendu != attendu && entendu.isNotEmpty() && attendu.isNotEmpty() &&
            (attendu.contains(entendu) || entendu.contains(attendu))

    /** L'absence d'alerte acoustique n'est pas une preuve de transcription
     * correcte. Elle ne peut effacer ni un rouge texte ni une indecision A/B. */
    fun couleur(texte: Couleur, avis: Avis): Couleur = when {
        texte == Couleur.ROUGE -> Couleur.ROUGE
        avis.etat == Etat.ECART -> Couleur.ROUGE
        avis.etat == Etat.A_CONFIRMER || avis.etat == Etat.DOUTE -> Couleur.ORANGE
        else -> texte
    }
}
