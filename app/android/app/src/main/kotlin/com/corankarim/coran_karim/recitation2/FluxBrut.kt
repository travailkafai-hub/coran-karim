package com.corankarim.coran_karim.recitation2

/**
 * COUCHE A — CAPTURE.
 *
 * CONTRAT : append-only, contigu, jamais modifie, jamais purge par une decision
 * de jugement. L'indice absolu d'un echantillon est LA reference de temps de
 * toute la chaine (cf. [Horloge]).
 *
 * CE QUE CA REND IMPOSSIBLE : [PIEGE] "35 % de l'audio n'existait dans AUCUN
 * fichier" (mesure du 2026-07-27 : le chemin de la borne dure reutilisait
 * l'apercu sans jamais ecrire de WAV, silencieusement). Ici, tout audio entre
 * par [ajouter] et reste extractible tant qu'il est dans la fenetre memoire ;
 * ce qui en sort a ete ecrit par [puits] AVANT d'etre oublie. Aucun chemin ne
 * peut ecrire un verdict sur un audio qui n'existe nulle part.
 *
 * Le stockage memoire est un ANNEAU borne : 300 s a 16 kHz en Short = 9,6 Mo.
 * L'anneau n'est pas un mecanisme de rattrapage (l'anneau 30->120 s a ete
 * mesure SANS effet sur le decrochage, [MORT] mort_anneau_120s_cause) : c'est
 * uniquement le magasin de PREUVE qui permet de reextraire l'audio d'un
 * verdict apres coup.
 *
 * [extraire] rend `null` si la fenetre demandee est sortie de l'anneau — il ne
 * rend JAMAIS une fenetre tronquee. Une preuve partielle reproduirait
 * exactement le defaut qu'elle est censee documenter.
 */
class FluxBrut(
    secondesEnMemoire: Int = 300,
    private val puits: ((FloatArray) -> Unit)? = null,
) {
    private val capacite: Int = secondesEnMemoire * Horloge.TAUX
    private val anneau = ShortArray(capacite)

    /** Nombre total d'echantillons recus depuis le debut de session. */
    var total: Long = 0
        private set

    /** Premier indice absolu encore present en memoire. */
    val premierDisponible: Long
        get() = maxOf(0L, total - capacite)

    fun ajouter(echantillons: FloatArray) {
        puits?.invoke(echantillons)
        for (v in echantillons) {
            val pos = (total % capacite).toInt()
            anneau[pos] = (v.coerceIn(-1f, 1f) * 32767f).toInt().toShort()
            total++
        }
    }

    /**
     * @return les echantillons [debutAbs, finAbs) ou `null` si la plage sort de
     *   l'anneau — jamais une plage tronquee.
     */
    fun extraire(debutAbs: Long, finAbs: Long): FloatArray? {
        if (finAbs <= debutAbs) return null
        if (debutAbs < premierDisponible || finAbs > total) return null
        val n = (finAbs - debutAbs).toInt()
        val out = FloatArray(n)
        for (i in 0 until n) {
            val pos = ((debutAbs + i) % capacite).toInt()
            out[i] = anneau[pos] / 32767f
        }
        return out
    }
}
