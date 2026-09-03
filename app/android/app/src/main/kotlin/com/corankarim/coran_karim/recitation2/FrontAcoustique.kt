package com.corankarim.coran_karim.recitation2

import com.corankarim.coran_karim.fastconformer.FastConformerCtc
import com.corankarim.coran_karim.fastconformer.DiagnosticLog

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
/**
 * Les trois sorties possibles d'un appel au modele. [tajwid] et [etat] sont
 * null sur un modele a une seule tete (deploiement historique) -- la chaine
 * doit rester fonctionnelle dans ce cas, rien de plus ne se calcule.
 */
data class SortiesFront(
    val logprobs: Array<FloatArray>,
    val tajwid: Array<FloatArray>?,
    val etat: Array<FloatArray>?,
)

interface FrontAcoustique {
    /**
     * Logprobs, tete tajwid ET etat de l'encodeur en UN SEUL appel au modele.
     *
     * Trois methodes separees feraient tourner l'encodeur PLUSIEURS FOIS par
     * fenetre -- inacceptable, et d'autant plus avec le curseur glissant qui
     * emet une fenetre toutes les 2-3 s.
     *
     * [SortiesFront.tajwid]/[SortiesFront.etat] sont null quand le modele
     * charge ne les expose pas : l'export deploye historiquement n'a qu'une
     * sortie, et la chaine doit continuer de fonctionner dessus. C'est aussi
     * ce qui permet aux bancs JVM de ne rien implementer de plus.
     */
    fun sorties(echantillons: FloatArray): SortiesFront =
        SortiesFront(logprobs(echantillons), null, null)

    /** Pieces BPE du vocabulaire, index = id de token. */
    val pieces: List<String>

    /** Index du blank CTC. */
    val blank: Int

    /** @return logprobs (T x V), T = echantillons / 1280. */
    fun logprobs(echantillons: FloatArray): Array<FloatArray>

    /** Detections de regles tajwid sur un extrait de [SortiesFront.tajwid] --
     *  cf. [FastConformerCtc.decodeTajwid]. Liste vide par defaut (bancs JVM,
     *  ou modele sans tete tajwid). */
    fun decodeTajwid(tajwid: Array<FloatArray>?):
        List<com.corankarim.coran_karim.fastconformer.DetectedRule> = emptyList()

    /** Noms des regles, index = ruleId. Vide si le modele n'a pas de tete
     *  tajwid (rien a nommer). */
    val nomsRegles: List<String> get() = emptyList()

    /** Seuil de detection de cette regle, en PROBABILITE (2026-09-02).
     *  0,5 par defaut : c'est la frontiere naturelle d'une sigmoide, et la
     *  valeur qu'utilisait le decodage avant les seuils calibres par classe.
     *  Sert uniquement au JOURNAL -- la decision, elle, est prise dans
     *  `decodeTajwid` avec le seuil en log, jamais recalculee ici. */
    fun seuilRegle(ruleId: Int): Float = 0.5f
}

/** Implementation reelle : mel calcule cote app + ONNX. */
class FrontOnnx(private val moteur: FastConformerCtc) : FrontAcoustique {
    override val pieces: List<String> get() = moteur.vocabPieces
    override val blank: Int get() = moteur.blank
    override val nomsRegles: List<String> get() = moteur.ruleNames
    override fun seuilRegle(ruleId: Int): Float = moteur.seuilProba(ruleId)
    override fun logprobs(echantillons: FloatArray): Array<FloatArray> =
        moteur.computeLogProbs(echantillons)

    /** Un seul passage du modele, trois sorties recuperees.
     *
     *  ── POURQUOI LA DUREE EST JOURNALISEE (2026-09-03) ──────────────────
     *
     *  La chaine v2 ne mesurait NULLE PART le temps de calcul du modele. Les
     *  traces `infDebut`/`infFin` existent bien, mais dans `BufferedTranscriber`
     *  -- la chaine v1, qui ne tourne plus : un premier banc les a cherchees en
     *  vain sur une session pourtant complete.
     *
     *  Sans cette mesure on ne peut pas arbitrer le reglage du parallelisme :
     *  borner les threads d'ONNX ferait baisser le CPU, mais si la duree
     *  d'inference explose le temps reel tombe, et on aurait echange un gain
     *  contre une perte -- invisible en ne regardant que le CPU.
     *
     *  Une ligne par fenetre, soit ~80 par session : negligeable devant le
     *  volume du journal, et cette ligne est le seul point de comparaison
     *  avant/apres dont on dispose. */
    override fun sorties(echantillons: FloatArray): SortiesFront {
        val t0 = System.nanoTime()
        val o = moteur.computeAll(echantillons)
        val ms = (System.nanoTime() - t0) / 1_000_000
        DiagnosticLog.log(
            "Inference",
            "computeAll ech=${echantillons.size} duree=${ms}ms",
        )
        return SortiesFront(o.letters, o.tajwid, o.etatEncodeur)
    }

    override fun decodeTajwid(tajwid: Array<FloatArray>?) = moteur.decodeTajwid(tajwid)

    /** Le modele charge expose-t-il l'etat de l'encodeur ? */
    val exposeEtat: Boolean get() = moteur.exposeEtatEncodeur
}
