package com.corankarim.coran_karim.recitation2

import com.corankarim.coran_karim.fastconformer.FastConformerCtc

/**
 * COUCHE C — FRONT ACOUSTIQUE.
 *
 * CONTRAT : fonction PURE de la fenetre. Meme fenetre en entree => memes
 * logprobs en sortie. Aucun etat conserve entre deux appels.
 *
 * C'est cette purete qui achete deux choses :
 *
 * 1. Le banc hors device EST l'app. Le graphe porte deux predictions hors
 *    device confiantes et fausses en une seule journee, et un piege repete deux
 *    jours de suite ("le banc mesurait mon decoupage, pas l'app"). Cause
 *    commune : chaque banc etait une REIMPLEMENTATION Python de la logique
 *    Kotlin. Ici les couches B/D/E/F/G n'ont aucune dependance Android ni ONNX
 *    et se rejouent telles quelles en test JVM ; seul C appelle le modele.
 *
 * 2. Le gel cache-aware ne peut pas revenir. [MORT] mort_cache_aware : le
 *    chemin stateful gelait apres ~35 s (compteur de tokens fige, aucun mot
 *    vert, curseur gele sans orange ni rouge — le pire mode de defaillance),
 *    et CINQ politiques de remise a zero du cache ont ete rejetees par la
 *    mesure. La conclusion du recul architectural du 2026-07-26 est que la
 *    cause est dans le MODELE (clips <= 20 s, session non bornee), pas dans la
 *    couche applicative. Sans etat, il n'y a plus de cache a vider, donc plus
 *    de politique a deviner.
 *
 * Le checkpoint reste le causal v1 (`causal-final.nemo`), alimente SANS ETAT,
 * en fenetres. L'export ONNX doit exposer `audio_signal` (mel), JAMAIS
 * `raw_audio` — [PIEGE] tombe DEUX fois : le modele se charge (log rassurant et
 * trompeur) et chaque transcription echoue en silence. Verification obligatoire
 * avant tout deploiement :
 *   python3 -c "import onnxruntime as ort; print([i.name for i in \
 *     ort.InferenceSession('<model.onnx>').get_inputs()])"
 */
interface FrontAcoustique {
    /**
     * Logprobs ET etat de l'encodeur en UN SEUL appel au modele.
     *
     * Deux methodes separees feraient tourner l'encodeur DEUX FOIS par
     * fenetre -- inacceptable, et d'autant plus avec le curseur glissant qui
     * emet une fenetre toutes les 3 s.
     *
     * L'etat est null quand le modele charge ne l'expose pas : l'export
     * deploye historiquement n'a qu'une sortie, et la chaine doit continuer de
     * fonctionner dessus. C'est aussi ce qui permet aux bancs JVM de ne rien
     * implementer de plus.
     */
    fun sorties(echantillons: FloatArray): Pair<Array<FloatArray>, Array<FloatArray>?> =
        Pair(logprobs(echantillons), null)

    /** Pieces BPE du vocabulaire, index = id de token. */
    val pieces: List<String>

    /** Index du blank CTC. */
    val blank: Int

    /** @return logprobs (T x V), T = echantillons / 1280. */
    fun logprobs(echantillons: FloatArray): Array<FloatArray>
}

/** Implementation reelle : mel calcule cote app + ONNX. */
class FrontOnnx(private val moteur: FastConformerCtc) : FrontAcoustique {
    override val pieces: List<String> get() = moteur.vocabPieces
    override val blank: Int get() = moteur.blank
    override fun logprobs(echantillons: FloatArray): Array<FloatArray> =
        moteur.computeLogProbs(echantillons)

    /** Un seul passage du modele, deux sorties recuperees. */
    override fun sorties(echantillons: FloatArray):
        Pair<Array<FloatArray>, Array<FloatArray>?> {
        val o = moteur.computeAll(echantillons)
        return Pair(o.letters, o.etatEncodeur)
    }

    /** Le modele charge expose-t-il l'etat de l'encodeur ? */
    val exposeEtat: Boolean get() = moteur.exposeEtatEncodeur
}
