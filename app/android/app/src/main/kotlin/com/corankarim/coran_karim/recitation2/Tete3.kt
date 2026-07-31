package com.corankarim.coran_karim.recitation2

import org.json.JSONArray
import org.json.JSONObject

/**
 * TETE 3 — ecart au canonique. Deux couches lineaires, 16 833 parametres.
 *
 * ── POURQUOI UNE TETE PLUTOT QU'UNE REGLE ECRITE ───────────────────────────
 *
 * Argument de l'utilisateur (2026-07-31) : « je prefere gerer la regle C par
 * modele, car il y a possibilite d'amelioration apres par entrainement ; sinon
 * avec la regle C on ne peut pas ameliorer ». La mesure lui donne raison :
 *
 *   regle ecrite a la main sur les logprobs      27 %   <- PLAFOND FIXE
 *   tete entrainee sur les MEMES logprobs        26 %
 *   tete entrainee sur l'ETAT DE L'ENCODEUR      31 %
 *
 * (detection a 2 % de collateral, audio reellement faute, 189 phrases tenues a
 * l'ecart de l'entrainement). Deux tentatives d'amelioration de la regle ont
 * echoue : le forward au lieu du Viterbi n'a AUCUN effet, cibler la queue de
 * distribution par negatifs durs fait PIRE (AUC 0,79 -> 0,67).
 *
 * La ligne du milieu est la plus instructive : une tete entrainee sur les MEMES
 * grandeurs ne bat pas la formule. Ce n'etait donc pas la formule qui etait
 * mauvaise -- les logprobs ont deja JETE l'information. Ils sont la projection
 * de 512 dimensions sur 1025 classes, apprise pour TRANSCRIRE.
 *
 * ── POURQUOI ELLE N'EST PAS DANS LE ONNX, ET C'EST VOULU ───────────────────
 *
 * Elle a besoin de grandeurs CONDITIONNEES PAR LA CIBLE (score force du mot
 * attendu, score de sa meilleure confusion...) que seul l'appelant connait :
 * l'app sait quel mot est attendu, le modele non.
 * Une tete qui ne lirait QUE l'acoustique a ete mesuree : 6 a 13 % de
 * detection, la PIRE de toutes. Sans la cible la question n'a pas de sens --
 * un ص correct et un س correct sonnent tous deux corrects.
 *
 * ── ⚠️ PARITE DES CARACTERISTIQUES : LE RISQUE PRINCIPAL ───────────────────
 *
 * La tete a ete entrainee sur des caracteristiques calculees EN PYTHON
 * (`tete_encodeur_ecart.py`). Le Kotlin doit les reproduire A L'IDENTIQUE --
 * meme algorithme forward, meme liste de variantes, meme ORDRE. Une divergence
 * ne provoque aucune erreur : elle rend simplement les poids denues de sens, et
 * les 31 % redeviennent du hasard.
 *
 * C'est exactement le piege que le projet a paye deux jours de suite (« le banc
 * mesurait mon decoupage, pas l'app ») : reimplementer une logique dans deux
 * langages produit des resultats confiants et faux.
 *
 * ⇒ [verifierParite] existe pour ca : elle rejoue un vecteur de reference
 * produit par le Python et compare la sortie. TANT QU'ELLE N'A PAS ETE PASSEE
 * SUR DEVICE, la sortie de cette tete ne doit PAS trancher un verdict.
 */
class Tete3 private constructor(
    private val moyenne: FloatArray,
    private val ecartType: FloatArray,
    private val poids1: Array<FloatArray>,   // (cache, entree)
    private val biais1: FloatArray,
    private val poids2: FloatArray,          // (cache) -> 1 sortie
    private val biais2: Float,
    /** Seuil mesure hors device pour 2 % de collateral. Ce n'est PAS zero :
     *  la sortie est un logit, sa frontiere naturelle n'a aucune raison d'etre
     *  a 0 comme celle d'un rapport de vraisemblance. */
    val seuil2Pct: Float,
    val seuil10Pct: Float,
) {
    /** Taille attendue du vecteur d'entree : 512 (etat) + 12 (scores cible). */
    val tailleEntree: Int get() = moyenne.size

    /**
     * @param entree [etat encodeur moyenne sur les frames du mot (512),
     *               puis les 12 scores conditionnes par la cible]
     * @return le logit : plus il est haut, plus le mot DEVIE de l'attendu.
     */
    fun logit(entree: FloatArray): Float {
        require(entree.size == moyenne.size) {
            "tete3 : ${entree.size} caracteristiques, ${moyenne.size} attendues"
        }
        val x = FloatArray(entree.size) { (entree[it] - moyenne[it]) / ecartType[it] }
        var s = 0f
        for (j in poids1.indices) {
            var a = biais1[j]
            val w = poids1[j]
            for (k in x.indices) a += w[k] * x[k]
            if (a > 0f) s += poids2[j] * a       // ReLU
        }
        return s + biais2
    }

    /**
     * Contre-mesure au risque de parite decrit en tete de classe : on rejoue un
     * vecteur dont la sortie Python est connue. Un ecart > 1e-3 signifie que le
     * chargement ou l'arithmetique divergent, et la tete doit alors etre
     * ignoree plutot que crue.
     */
    fun verifierParite(entree: FloatArray, sortieAttendue: Float): Boolean =
        kotlin.math.abs(logit(entree) - sortieAttendue) < 1e-3f

    companion object {
        /** @return null si le fichier est absent ou illisible -- la chaine se
         *  rabat alors sur la regle ecrite a la main, sans rien casser. */
        fun charger(json: String): Tete3? = try {
            val o = JSONObject(json)
            val n = o.getJSONObject("normalisation")
            fun vec(a: JSONArray) = FloatArray(a.length()) { a.getDouble(it).toFloat() }
            fun mat(a: JSONArray) = Array(a.length()) { vec(a.getJSONArray(it)) }
            val c = o.getJSONArray("couches")
            val c1 = c.getJSONObject(0)
            val c2 = c.getJSONObject(1)
            val s = o.optJSONObject("seuils_mesures")
            Tete3(
                moyenne = vec(n.getJSONArray("moyenne")),
                ecartType = vec(n.getJSONArray("ecart_type")),
                poids1 = mat(c1.getJSONArray("poids")),
                biais1 = vec(c1.getJSONArray("biais")),
                // seconde couche : une seule sortie, donc une seule ligne
                poids2 = vec(c2.getJSONArray("poids").getJSONArray(0)),
                biais2 = c2.getJSONArray("biais").getDouble(0).toFloat(),
                seuil2Pct = s?.optDouble("collateral_2pct", 0.0)?.toFloat() ?: 0f,
                seuil10Pct = s?.optDouble("collateral_10pct", 0.0)?.toFloat() ?: 0f,
            )
        } catch (e: Exception) {
            null
        }
    }
}
