package com.corankarim.coran_karim.fastconformer

/**
 * Second buffer, EN LECTURE SEULE, pour rejuger un mot que le buffer principal
 * n'a pas su placer -- idee utilisateur du 2026-07-27.
 *
 * ── POURQUOI UN BUFFER SEPARE PLUTOT QU'UN CHEVAUCHEMENT ────────────────────
 * Le chevauchement, essaye le meme jour, modifie la PURGE du buffer principal.
 * Chaque erreur y contamine donc le chemin critique, et il en est arrive trois
 * en deux commits :
 *   - boucle de re-gel (quatre gels de 3000 ms en une seconde) ;
 *   - ancre qui n'avance plus d'un mot par gel (contexte donne a la DP) ;
 *   - clips qui se recouvrent de 3 s (142,3 s ecrites pour 121,0 s d'audio).
 * L'utilisateur avait annonce ce risque AVANT l'implementation : « rejouer sur
 * le buffer peut causer des problemes, c'est pour ca que je parle d'un buffer
 * memoire decale qui ne sert qu'en cas de secours ».
 *
 * Ici, rien n'est modifie : cet anneau est ecrit puis LU, jamais consomme,
 * jamais purge par le jugement. Le chemin principal l'ignore completement.
 *
 * ── SANS ETAT, DONC SANS CLASSE DE BUG POSSIBLE ─────────────────────────────
 * Pas d'ancre, pas de progression, pas de memoire entre deux appels. Une
 * extraction, une inference, un verdict, on rend la main. Une desynchronisation
 * entre deux ancres, une boucle, une duplication de texte deviennent
 * IMPOSSIBLES -- pas seulement evitees par vigilance.
 *
 * ── LE FLUX STOCKE EST CELUI D'APRES LE PORTIER ─────────────────────────────
 * Point critique. Le buffer principal travaille sur l'audio APRES le portier
 * RMS (silences retires). Stocker ici le flux BRUT ferait diverger les deux
 * echelles de temps des qu'un bloc est jete -- c'est exactement l'erreur qui
 * avait fausse `bench_double_decoupage.py` le matin meme (positions de coupe
 * calculees sur un flux, appliquees sur l'autre). On stocke donc le MEME flux,
 * ce qui rend la position d'un mot exacte et non approchee :
 *
 *     position absolue du mot = offset absolu du segment
 *                             + premiereFrame x echantillonsParFrame
 *
 * Aucune recherche, aucun appariement de texte.
 */
class RescueBuffer(private val capacitySamples: Int) {

    private val ring = FloatArray(capacitySamples)

    /** Nombre total d'echantillons jamais ecrits -- l'horloge absolue. */
    @Volatile private var total = 0L

    @Synchronized
    fun append(samples: FloatArray) {
        if (samples.isEmpty()) return
        var src = 0
        // Un bloc plus grand que l'anneau ne peut garder que sa fin.
        if (samples.size >= capacitySamples) src = samples.size - capacitySamples
        var pos = ((total + src) % capacitySamples).toInt()
        while (src < samples.size) {
            val n = minOf(samples.size - src, capacitySamples - pos)
            System.arraycopy(samples, src, ring, pos, n)
            src += n
            pos = (pos + n) % capacitySamples
        }
        total += samples.size
    }

    /** Horloge absolue : index du prochain echantillon a ecrire. */
    @Synchronized
    fun totalSamples(): Long = total

    @Synchronized
    fun reset() {
        total = 0L
    }

    /**
     * Extrait [fromAbs, toAbs) en indices ABSOLUS, ou null si la fenetre est
     * deja sortie de l'anneau (trop ancienne) ou pas encore ecrite.
     *
     * Retourner null plutot qu'une fenetre tronquee est deliberé : un secours
     * qui juge sur un audio partiel reproduirait le defaut qu'il est cense
     * corriger.
     */
    @Synchronized
    fun extract(fromAbs: Long, toAbs: Long): FloatArray? {
        if (toAbs <= fromAbs) return null
        val oldest = maxOf(0L, total - capacitySamples)
        if (fromAbs < oldest || toAbs > total) return null
        val n = (toAbs - fromAbs).toInt()
        if (n <= 0 || n > capacitySamples) return null
        val out = FloatArray(n)
        var pos = (fromAbs % capacitySamples).toInt()
        var dst = 0
        while (dst < n) {
            val k = minOf(n - dst, capacitySamples - pos)
            System.arraycopy(ring, pos, out, dst, k)
            dst += k
            pos = (pos + k) % capacitySamples
        }
        return out
    }
}
