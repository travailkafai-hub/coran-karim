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
data class DetectedRule(
    val ruleId: Int,
    val frame: Int,
    val prob: Float,
    /**
     * Nombre de frames CONSECUTIVES sur lesquelles la tete a emis cette classe
     * (80 ms par frame). 1 par defaut -- les appelants historiques ne le
     * passent pas et ne s'en servent pas.
     *
     * POURQUOI CE CHAMP EXISTE (raisonnement utilisateur, 2026-08-04). La
     * distinction `madda_obligatory` / `madda_normal` n'est PAS acoustique :
     * un madd est *wajib* parce qu'une hamza le suit DANS LE MEME MOT
     * (`إِلَّآ`), pas parce qu'il sonne autrement -- et les deux peuvent avoir
     * la meme longueur. Demander a une tete ACOUSTIQUE de trancher une
     * categorie GRAMMATICALE est donc la mauvaise question, et son echec n'est
     * pas un defaut d'entrainement.
     *
     * Constate sur device le 2026-08-04 (preset tajwid, recitation
     * PROFESSIONNELLE rejouee) : mot 76 `إِلَّآ` signale « madda_obligatory
     * absente » alors que la tete avait bien detecte `madda_normal` -- un madd
     * A ETE fait, il a juste ete classe dans la mauvaise sous-famille.
     *
     * Le bon decoupage est donc : le TYPE vient du texte (l'annotation le sait
     * deja, cf. RecitedWord.expectedRules), et l'acoustique ne repond qu'a
     * « y a-t-il eu un allongement, et de quelle DUREE ». Ce champ apporte la
     * duree qui manquait. ⚠️ JOURNALISE SEULEMENT pour l'instant : aucune
     * decision ne s'y appuie tant qu'on n'a pas mesure ce que valent
     * reellement ces durees sur du vrai audio.
     */
    val frames: Int = 1,
)

/** Sorties du modele : la tete lettres (toujours presente) et, sur les modeles
 *  a DEUX tetes, la tete tajwid. [tajwid] est null sur les anciens modeles
 *  (une seule sortie) -- tout le code aval doit rester fonctionnel dans ce cas. */
class CtcOutputs(
    val letters: Array<FloatArray>,
    val tajwid: Array<FloatArray>?,
    /**
     * Etat interne de l'encodeur, (frames, 512). Null si le modele charge ne
     * l'expose pas -- l'export deploye historiquement n'a qu'une sortie.
     *
     * CE N'EST PAS UNE TETE, c'est une PRISE : ces 512 dimensions sont
     * calculees de toute facon, et etaient jusqu'ici jetees apres leur
     * projection sur les 1025 classes de lettres. On ne calcule rien de plus,
     * on rend visible ce qui existait deja.
     *
     * POURQUOI ON EN A BESOIN (mesure du 2026-07-31, audio reellement faute,
     * 189 phrases tenues a l'ecart, detection a 2 % de collateral) :
     *   regle ecrite a la main sur les logprobs      27 %
     *   tete entrainee sur les MEMES logprobs        26 %
     *   tete entrainee sur l'ETAT DE L'ENCODEUR      31 %
     * Une tete sur les logprobs ne fait pas mieux que la formule : ce n'etait
     * donc pas la formule qui etait mauvaise, c'est que les logprobs ont deja
     * JETE l'information. Ils sont une projection apprise pour TRANSCRIRE, pas
     * pour juger une deviation.
     */
    val etatEncodeur: Array<FloatArray>? = null,
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
    /**
     * ⚠️ N'EST PLUS UTILISE, ET NE DOIT PAS L'ETRE (2026-08-04). Conserve pour
     * memoire : c'etait l'indice de blanc du temps ou la tete 2 etait une tete
     * CTC + softmax (avant le 2026-07-24). La tete actuelle est MULTI-LABEL A
     * SIGMOIDE : « aucune regle ici » ne s'exprime pas par une classe dediee
     * mais par TOUTES les probabilites basses -- il n'y a donc pas de blanc, et
     * ce n'est pas un oubli d'annotation. Verifie sur le modele deploye :
     * `rules.json` porte 19 noms et la sortie a 19 classes (0..18), si bien que
     * cette valeur vaut 19, un indice HORS PLAGE que l'argmax ne pouvait jamais
     * rendre -- le decodeur ne se taisait donc jamais. Cf. [decodeTajwid].
     */
    private val tajwidBlank: Int = tajwidNames.size

    /** Noms des classes de regles, index = ruleId de [DetectedRule]. Vide si le
     *  modele n'a pas de tete tajwid. */
    val ruleNames: List<String> get() = tajwidNames

    /** Le modele charge expose-t-il une tete tajwid exploitable ? */
    val hasTajwid: Boolean get() = hasTajwidHead

    private val hasEncoderState: Boolean =
        session.outputNames.contains(ENCODER_STATE_OUTPUT)

    /** Le modele charge expose-t-il l'etat de l'encodeur ? Permet a la chaine de
     *  se rabattre sur la regle ecrite a la main quand ce n'est pas le cas. */
    val exposeEtatEncodeur: Boolean get() = hasEncoderState

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
        // ── UN SEUIL PAR CLASSE, ET NON UN ARGMAX ENTRE CLASSES ─────────────
        //
        // BUG STRUCTUREL CORRIGE ICI (2026-08-04). Ce decodage etait celui
        // d'une tete CTC + SOFTMAX -- argmax entre classes, collapse des
        // repetitions, classe de blanc. La tete 2 n'est plus celle-la depuis
        // le 2026-07-24 : elle est MULTI-LABEL A SIGMOIDE (BCE par classe a
        // l'entrainement, `-softplus(-x)` = logsigmoid a l'export) et elle est
        // apprise sur des SPANS DENSES [classe, frame_debut, frame_fin], tout
        // cela precisement pour que deux regles puissent coexister sur les
        // MEMES frames (cas fondateur : `ٱلنَّاسِ`, ou l'assimilation du lam
        // DANS le noun double EST la ghunnah). Le decodeur, lui, n'avait pas
        // suivi le changement d'architecture.
        //
        // TROIS DEFAUTS QUE CA PRODUISAIT, mesures sur 20 s de recitation
        // reelle avec le modele deploye :
        //   1. `tajwidBlank` vaut `tajwidNames.size` = 19, alors que la sortie
        //      n'a QUE 19 classes (indices 0..18) : l'indice de blanc est HORS
        //      PLAGE, le garde `best != tajwidBlank` est toujours vrai, et
        //      100 % des frames emettaient donc une regle. Sur ces frames,
        //      49,8 % avaient leur « gagnant » SOUS 0,5 de probabilite : une
        //      regle sur deux etait purement inventee.
        //   2. La simultaneite etait detruite : 13,9 % des frames portent
        //      REELLEMENT deux regles au-dessus du seuil, ce qu'un argmax ne
        //      peut jamais rendre. C'est exactement ce que les spans avaient
        //      ete construits pour permettre.
        //   3. Les spans denses ressortaient hachés en pics d'UNE frame (une
        //      classe ne « gagne » que la ou elle bat les 18 autres), ce qui
        //      m'a fait conclure a tort a la peakiness du CTC en analysant les
        //      durees : p25 = 1 frame sur `madda_obligatory`. C'etait le
        //      decodage, pas le modele.
        //
        // Le seuil est 0,5 en PROBABILITE, la frontiere naturelle d'une
        // sigmoide -- pas un reglage a calibrer.
        val out = ArrayList<DetectedRule>()
        val nClasses = tajwid.firstOrNull()?.size ?: return emptyList()
        val seuilLog = Math.log(0.5).toFloat()
        for (c in 0 until nClasses) {
            var debut = -1
            var probMax = 0f
            for (t in tajwid.indices) {
                val actif = tajwid[t][c] >= seuilLog
                if (actif) {
                    if (debut < 0) { debut = t; probMax = 0f }
                    val p = Math.exp(tajwid[t][c].toDouble()).toFloat()
                    if (p > probMax) probMax = p
                } else if (debut >= 0) {
                    out.add(DetectedRule(c, debut, probMax, t - debut))
                    debut = -1
                }
            }
            if (debut >= 0) {
                out.add(DetectedRule(c, debut, probMax, tajwid.size - debut))
            }
        }
        // Ordre chronologique : les appelants (ForcedAligner.segmentRules,
        // attribution par recouvrement de frames) raisonnent sur la position.
        out.sortBy { it.frame }
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
                    // Meme recuperation PAR NOM que la tete tajwid : robuste a
                    // un reordonnancement des sorties, et absente sans erreur
                    // sur les modeles a une seule sortie.
                    val etat: Array<FloatArray>? = if (hasEncoderState) {
                        @Suppress("UNCHECKED_CAST")
                        (results.get(ENCODER_STATE_OUTPUT).get().value
                            as Array<Array<FloatArray>>)[0]
                    } else null
                    // .value materialise deja des copies JVM -> survit au close().
                    return CtcOutputs(letters, tajwid, etat)
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
    /** [fromFrame] (2026-07-27) : borne de DEBUT, pour exclure du texte les
     *  frames de CONTEXTE d'un segment chevauchant -- cet audio a deja ete fige
     *  au segment precedent, le redecoder ici dupliquerait le texte (piege
     *  mesure : fenetre glissante naive a WER > 100 %). Defaut 0 = comportement
     *  d'avant, inchange pour tous les autres appelants. */
    fun greedyDecode(logprobs: Array<FloatArray>, toFrameIncl: Int = -1,
                     fromFrame: Int = 0): String {
        val end = if (toFrameIncl in 0 until logprobs.size) toFrameIncl else logprobs.size - 1
        val start = fromFrame.coerceIn(0, maxOf(0, end))
        val ids = ArrayList<Int>(end - start + 1)
        var prev = -1
        for (fi in start..end) {
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
        const val ENCODER_STATE_OUTPUT = "encoder_state"
    }
}
