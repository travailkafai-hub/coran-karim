package com.corankarim.coran_karim.recitation2

/** Les trois couleurs de l'app : vert = correct, orange = douteux, rouge = faux. */
enum class Couleur { VERT, ORANGE, ROUGE }

/**
 * Statut d'un mot. `OMIS` n'est PAS une couleur : c'est "le recitateur est passe
 * outre, et on peut le prouver". Sans ce statut, un mot saute redevient
 * invisible — c'etait le vrai defaut de v22 (`305db63`), ou les mots enjambes
 * quittaient silencieusement le denominateur.
 */
sealed class Statut {
    object Inconnu : Statut()
    data class Provisoire(val couleur: Couleur) : Statut()
    data class Definitif(val couleur: Couleur) : Statut()
    object Omis : Statut()
}

/**
 * COUCHE G — DECISION.
 *
 * CONTRAT :
 *  - SEUL endroit du systeme ou vit un seuil. Aucune autre couche n'en connait ;
 *  - MONOTONIE : un verdict definitif ne change plus jamais. Un provisoire peut
 *    changer ;
 *  - une observation ne compte que si elle est INTERIEURE (couche E) ;
 *  - jamais de verdict sur absence de donnee, jamais de verdict par defaut.
 *
 * ── LA REGLE, ET CE QU'ELLE REMPLACE ───────────────────────────────────────
 *
 * PROVISOIRE des la 1re observation interieure ; DEFINITIF quand [k] = 2
 * observations interieures issues de fenetres DISTINCTES donnent la meme
 * couleur (stable-prefix rule).
 *
 * En v1 : `lock = p.isFinal || (judged == correct && !deferredTajwid)`. Un mot
 * juge correct sur un simple APERCU etait fige immediatement — consequence
 * mesuree : [PIEGE] verrou_sur_apercu, "la majorite des mots sont verrouilles
 * sur des apercus, donc sur un audio INCOMPLET". Ici il n'existe aucun chemin
 * qui verrouille sur une seule observation, ni sur une observation de bord.
 *
 * ── LE CALENDRIER, CHIFFRE (W = 6 s, hop = 1,5 s) ──────────────────────────
 * Soit `t` l'instant ou le mot finit d'etre prononce :
 *   + 1,04 s  contexte droit du modele causal
 *   + 0 a 1,5 s  attente de la prochaine fenetre de la grille
 *   + ~0,4 s  inference (mesure : 413 ms pour 5,7 s de buffer)
 *   = PROVISOIRE a t + 1,4 a 2,9 s
 *   + 1,5 s  seconde observation interieure
 *   = DEFINITIF a t + 2,9 a 4,4 s
 *
 * Ce delai est CONSTANT : il ne depend ni de la longueur d'un segment, ni du
 * rythme des pauses, ni de la duree deja recitee. C'est une propriete de
 * conception, pas une consequence a constater. Reference v1 mesuree dans le
 * log : `VALIDATION retard=10435ms` puis `8463ms`.
 */
class Decideur(
    private val seuilCorrect: Float = -0.45f,
    private val seuilDouteux: Float = -1.60f,
    private val k: Int = 2,
    private val motsPosterieursPourOmission: Int = 3,
) {
    private val definitifs = HashMap<Int, Couleur>()
    private val omis = HashSet<Int>()

    /** @return statut courant de chaque mot ayant au moins une observation. */
    fun statuts(registre: RegistreDePreuves, nbMots: Int): Map<Int, Statut> {
        val out = HashMap<Int, Statut>()

        for (i in 0 until nbMots) {
            val dejaFige = definitifs[i]
            if (dejaFige != null) { out[i] = Statut.Definitif(dejaFige); continue }

            val votantes = registre.observationsVotantes(i)
            if (votantes.isEmpty()) continue

            val couleurs = votantes.map { couleur(it) }
            val fenetres = votantes.map { it.fenetreId }

            // k dernieres observations, de fenetres DISTINCTES, toutes d'accord.
            if (votantes.size >= k) {
                val dernieres = couleurs.takeLast(k)
                val idsDistincts = fenetres.takeLast(k).toSet().size == k
                if (idsDistincts && dernieres.all { it == dernieres.first() }) {
                    definitifs[i] = dernieres.first()
                    out[i] = Statut.Definitif(dernieres.first())
                    continue
                }
            }
            out[i] = Statut.Provisoire(couleurs.last())
        }

        // OMISSION : preuve POSITIVE que le recitateur est passe outre — au
        // moins N mots POSTERIEURS sont definitifs alors que celui-ci n'a jamais
        // recu d'observation votante. Ce n'est pas un verdict par absence de
        // donnee : c'est un constat sur des mots qui, eux, ont leur preuve.
        val definitifsTries = definitifs.keys.sorted()
        for (i in 0 until nbMots) {
            if (out[i] != null || omis.contains(i)) {
                if (omis.contains(i) && out[i] == null) out[i] = Statut.Omis
                continue
            }
            val posterieurs = definitifsTries.count { it > i }
            if (posterieurs >= motsPosterieursPourOmission) {
                omis.add(i)
                out[i] = Statut.Omis
            }
        }
        return out
    }

    fun couleur(o: RegistreDePreuves.Observation): Couleur = when {
        o.gop >= seuilCorrect -> Couleur.VERT
        o.gop >= seuilDouteux -> Couleur.ORANGE
        else -> Couleur.ROUGE
    }

    fun reinitialiser() {
        definitifs.clear()
        omis.clear()
    }
}
