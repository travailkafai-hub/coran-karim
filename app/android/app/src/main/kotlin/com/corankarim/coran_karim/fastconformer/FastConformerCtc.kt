package com.corankarim.coran_karim.fastconformer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONArray
import java.io.File
import java.nio.FloatBuffer
import java.nio.LongBuffer

/**
 * Verificateur ASR "parallele" (FastConformer CTC, modele Quran fine-tune, cf.
 * benchmark/models/fastconformer-quran-pcd) -- tourne EN PLUS de whisper.cpp
 * (pas un remplacement), le temps de valider precision/latence en conditions
 * reelles. Pipeline : PCM brut -> MelSpectrogram.compute() -> ONNX (encodeur+CTC
 * precalcules cote Python, cf. benchmark/export_pcd_checkpoint.py) -> greedy CTC
 * -> detokenisation BPE (simple jointure, pas besoin de SentencePiece natif).
 *
 * Modele et vocab deployes a cote des autres modeles (pas embarques dans l'APK),
 * voir la meme convention que whisper-medium-ggml.
 */
/** Une regle de tajwid detectee par la TETE 2, avec la frame ou elle culmine.
 *  [prob] = probabilite de la classe sur cette frame (0..1) -- permet de
 *  distinguer "regle franchement realisee" de "regle a peine esquissee",
 *  information qu'un simple symbole insere dans le texte ne portait pas. */
data class DetectedRule(val ruleId: Int, val frame: Int, val prob: Float)

/** Sorties du modele : la tete lettres (toujours presente) et, sur les modeles
 *  a DEUX tetes, la tete tajwid. [tajwid] est null sur les anciens modeles
 *  (une seule sortie) -- tout le code aval doit rester fonctionnel dans ce cas. */
class CtcOutputs(
    val letters: Array<FloatArray>,
    val tajwid: Array<FloatArray>?,
)

class FastConformerCtc(modelPath: String, vocabPath: String, rulesPath: String? = null) {

    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private val session: OrtSession = env.createSession(modelPath, OrtSession.SessionOptions())
    private val vocab: List<String> = loadVocab(vocabPath)
    private val blankId: Int = vocab.size // CTC blank = dernier index (vocab_size), verifie cote Python

    // ── TETE 2 (regles tajwid), modeles a deux tetes uniquement ──────────────
    // Architecture adoptee le 2026-07-22 : lettres et regles ne partagent plus
    // le meme softmax. Mesure qui l'a motivee : melangees, les regles volaient
    // ~20% de masse de probabilite aux lettres MEME sur un mot sans aucune
    // regle attendue, et le symbole ham_wasl cassait la fusion BPE `ٱ+ل`
    // (le modele n'apprenait jamais le token soude que l'alignement force lui
    // reclamait). Separees : detection tajwid F1=0,936 ET tete lettres intacte.
    //
    // `tajwidNames` vient de rules.json (ecrit par export_dual_head_checkpoint.py).
    // Absent => ancien modele a une seule tete => toute la partie tajwid de ce
    // fichier reste inerte, rien ne casse.
    private val tajwidNames: List<String> = rulesPath?.let { loadVocab(it) } ?: emptyList()
    private val hasTajwidHead: Boolean =
        tajwidNames.isNotEmpty() && session.outputNames.contains(TAJWID_OUTPUT)
    private val tajwidBlank: Int = tajwidNames.size

    /** Noms des classes de regles, index = ruleId de [DetectedRule]. Vide si le
     *  modele n'a pas de tete tajwid. */
    val ruleNames: List<String> get() = tajwidNames

    /** Le modele charge expose-t-il une tete tajwid exploitable ? */
    val hasTajwid: Boolean get() = hasTajwidHead

    /** Pieces BPE du vocabulaire — pour le tokenizer/aligneur force (cf. ForcedAligner.kt). */
    val vocabPieces: List<String> get() = vocab

    /** Index du blank CTC — pour l'aligneur force. */
    val blank: Int get() = blankId

    private fun loadVocab(path: String): List<String> {
        val json = File(path).readText(Charsets.UTF_8)
        val arr = JSONArray(json)
        return (0 until arr.length()).map { arr.getString(it) }
    }

    /** @param pcm audio brut mono 16kHz, [-1,1]. @return texte decode (harakat incluses). */
    fun transcribe(pcm: FloatArray): String = greedyDecode(computeLogProbs(pcm))

    /**
     * Detections de regles a partir des logprobs de la TETE 2 : decodage CTC
     * glouton (collapse des repetitions, retrait des blancs), en conservant la
     * frame de chaque emission.
     *
     * La frame est CAPITALE : c'est elle qui permet d'attribuer la regle au bon
     * MOT (recouvrement avec la fenetre de frames que l'alignement force donne
     * a ce mot, cf. ForcedAligner). Une approche par position dans le texte
     * serait approximative ; ici l'attribution est temporelle, donc exacte.
     */
    fun decodeTajwid(tajwid: Array<FloatArray>?): List<DetectedRule> {
        if (tajwid == null || !hasTajwidHead) return emptyList()
        val out = ArrayList<DetectedRule>()
        var prev = -1
        for ((frameIdx, frame) in tajwid.withIndex()) {
            var best = 0
            var bestVal = frame[0]
            for (c in 1 until frame.size) {
                if (frame[c] > bestVal) { bestVal = frame[c]; best = c }
            }
            if (best != prev && best != tajwidBlank) {
                // logprob -> probabilite, pour exposer une confiance lisible.
                out.add(DetectedRule(best, frameIdx, Math.exp(bestVal.toDouble()).toFloat()))
            }
            prev = best
        }
        return out
    }

    /**
     * Log-probabilites par frame (T, vocab+1) — la matiere premiere du decodage
     * glouton ET de l'alignement force GOP (ForcedAligner). Exposee separement
     * pour ne lancer l'inference ONNX qu'UNE fois quand les deux en ont besoin.
     */
    fun computeLogProbs(pcm: FloatArray): Array<FloatArray> = computeAll(pcm).letters

    /**
     * UNE seule inference ONNX -> les DEUX tetes. L'encodeur (le gros du calcul)
     * est partage : lire la tete tajwid ne coute donc quasiment rien de plus
     * qu'une projection lineaire, c'est tout l'interet de l'encodeur commun.
     *
     * Sur un modele a une seule sortie (anciens deploiements), [CtcOutputs.tajwid]
     * vaut null et rien d'autre ne change.
     */
    fun computeAll(pcm: FloatArray): CtcOutputs {
        val feats = MelSpectrogram.compute(pcm) // (80, T)
        val nMels = feats.size
        val t = feats[0].size

        val audioBuf = FloatBuffer.allocate(nMels * t)
        for (m in 0 until nMels) for (i in 0 until t) audioBuf.put(feats[m][i])
        audioBuf.rewind()

        val lengthBuf = LongBuffer.allocate(1)
        lengthBuf.put(t.toLong())
        lengthBuf.rewind()

        OnnxTensor.createTensor(env, audioBuf, longArrayOf(1, nMels.toLong(), t.toLong())).use { audioTensor ->
            OnnxTensor.createTensor(env, lengthBuf, longArrayOf(1)).use { lengthTensor ->
                val inputs = mapOf("audio_signal" to audioTensor, "length" to lengthTensor)
                session.run(inputs).use { results ->
                    @Suppress("UNCHECKED_CAST")
                    val letters = (results[0].value as Array<Array<FloatArray>>)[0]
                    // Recuperation PAR NOM (et non par index) : robuste a un
                    // eventuel reordonnancement des sorties par l'exporteur.
                    val tajwid: Array<FloatArray>? = if (hasTajwidHead) {
                        @Suppress("UNCHECKED_CAST")
                        (results.get(TAJWID_OUTPUT).get().value
                            as Array<Array<FloatArray>>)[0]
                    } else null
                    // .value materialise deja des copies JVM -> survit au close().
                    return CtcOutputs(letters, tajwid)
                }
            }
        }
    }

    /** Decodage glouton, eventuellement borne aux frames [0..toFrameIncl].
     *
     *  [toFrameIncl] = -1 (defaut) : tout le segment, comportement historique.
     *  Sinon on ne decode que le debut -- utilise par BufferedTranscriber pour
     *  ne FIGER que le texte de l'audio reellement consomme par l'aligneur
     *  (2026-07-25). Sans cette borne, figer le texte du segment ENTIER tout en
     *  conservant sa queue audio ferait reapparaitre cette queue une seconde
     *  fois dans le texte au segment suivant -- la duplication qui avait mis la
     *  fenetre glissante naive a WER > 100 %. */
    fun greedyDecode(logprobs: Array<FloatArray>, toFrameIncl: Int = -1): String {
        val end = if (toFrameIncl in 0 until logprobs.size) toFrameIncl else logprobs.size - 1
        val ids = ArrayList<Int>(end + 1)
        var prev = -1
        for (fi in 0..end) {
            val frame = logprobs[fi]
            var best = 0
            var bestVal = frame[0]
            for (c in 1 until frame.size) {
                if (frame[c] > bestVal) { bestVal = frame[c]; best = c }
            }
            if (best != prev && best != blankId) ids.add(best)
            prev = best
        }
        // Detokenisation BPE : jointure directe des pieces + "▁" -> espace (verifie
        // identique a tokenizer.ids_to_text() de NeMo cote Python, pas besoin de SentencePiece).
        val sb = StringBuilder()
        for (id in ids) if (id < vocab.size) sb.append(vocab[id])
        return sb.toString().replace('▁', ' ').trim()
    }

    fun close() {
        session.close()
    }

    companion object {
        /** Nom de la 2e sortie ONNX (cf. export_dual_head_checkpoint.py). La 1re
         *  garde son nom historique "logprobs" -> un modele a deux tetes reste
         *  lisible par du code qui n'en attend qu'une. */
        const val TAJWID_OUTPUT = "tajwid_logprobs"
    }
}
