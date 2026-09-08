package com.corankarim.coran_karim.fastconformer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import org.json.JSONArray
import org.json.JSONObject
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
    /** Tete tajwid FINE, 76 classes. Null sur un pack a 4 sorties.
     *  Cf. [FastConformerCtc.TAJWID_FINE_OUTPUT]. */
    val tajwidFine: Array<FloatArray>? = null,
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

// NOTE : l'ordre des parametres de [CtcOutputs] est (letters, tajwid,
// tajwidFine, etatEncodeur). `tajwidFine` a ete insere AVANT `etatEncodeur`
// pour rester a cote de la tete dont il est le pendant ; le seul appel
// positionnel du fichier a ete mis a jour en consequence.

class FastConformerCtc(
    modelPath: String,
    vocabPath: String,
    rulesPath: String? = null,
    seuilsPath: String? = null,
    vocabWarshPath: String? = null,
) {

    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()

    // ── PARALLELISME BORNE (2026-09-03) ──────────────────────────────────────
    //
    // Constat utilisateur : « je sens le tel devenir chaud ». Mesure : 226 % de
    // CPU en moyenne pendant une recitation, pointes a 333 % -- deux a trois
    // coeurs satures. Puis sa question, la bonne : « c'est un seul ASR qui fait
    // tourner 3 coeurs ? »
    //
    // Releve des threads du processus : CINQ threads `DefaultDispatch` actifs
    // simultanement. Ce sont ceux du pool de coroutines Kotlin, dimensionne au
    // nombre de coeurs (8 ici) -- donc PLUSIEURS inferences en vol, et aucun
    // mutex ne les serialise. Par-dessus, `SessionOptions()` par defaut laisse
    // ONNX Runtime paralleliser CHAQUE inference sur autant de threads qu'il
    // voit de coeurs. Deux parallelismes empiles : plus de threads que de
    // coeurs, donc de la sur-souscription -- le processeur arbitre entre des
    // inferences qui se disputent les memes unites, ce qui chauffe sans
    // accelerer.
    //
    // On borne le parallelisme INTERNE d'ONNX, qui est le moins risque des deux
    // leviers : aucune logique ne change, seulement le nombre de threads par
    // inference. Serialiser les inferences elles-memes toucherait la latence et
    // le temps reel -- a ne tenter qu'apres, et avec la recette complete.
    //
    // ⚠️ CE REGLAGE DOIT ETRE MESURE, PAS SUPPOSE. Baisser le CPU en faisant
    // exploser la duree d'inference ne serait pas un gain mais un echange
    // perdant, et invisible si l'on ne regardait que le CPU. Le banc
    // `banc_inference.py` rejoue un WAV identique et sort les deux colonnes :
    // duree mediane/p90 des inferences, et CPU moyen/max.
    private val session: OrtSession = env.createSession(
        modelPath,
        OrtSession.SessionOptions().apply {
            // 2 et non 1 : le modele reste assez large pour tirer parti d'un
            // second thread, et passer a 1 rallongerait chaque inference sans
            // supprimer la concurrence entre fenetres, qui vient de l'etage
            // au-dessus.
            setIntraOpNumThreads(2)
            // 1 : il n'y a qu'un graphe a executer par appel, paralleliser
            // ENTRE operateurs n'apporte rien ici et ajoute des threads.
            setInterOpNumThreads(1)
        },
    )

    // ── DEUX TETES DE LETTRES, UN SEUL ENCODEUR (2026-08-21) ─────────────────
    //
    // Le modele a quatre sorties expose `logprobs` (Hafs, position 0) ET
    // `warsh_logprobs` (position 2). Les deux partagent l'encodeur : choisir la
    // riwaya ne coute RIEN de plus en calcul, l'audio n'est encode qu'une fois.
    //
    // ⚠️ CE N'EST PAS QU'UN CHANGEMENT DE SORTIE. Les deux tetes ont leur
    // PROPRE vocabulaire SentencePiece : mesure du 2026-08-21, 1009 pieces sur
    // 1024 different entre `vocab.json` et `vocab_warsh.json`. Lire la sortie
    // Warsh en detokenisant avec le vocabulaire Hafs rendrait du charabia --
    // et, plus insidieux, l'alignement force TOKENISERAIT la cible Warsh avec
    // les pieces Hafs (`CtcTokenizer` retombe sur un decoupage glouton quand un
    // mot est absent de `word_tokens.json`, ce qui est le cas de tout mot
    // Warsh). On bascule donc le vocabulaire ENTIER, pas seulement l'index lu.
    private val vocabHafs: List<String> = loadVocab(vocabPath)
    private val vocabWarsh: List<String>? =
        vocabWarshPath?.let { runCatching { loadVocab(it) }.getOrNull() }

    /// Riwaya courante -- pilotee par Dart (`setRiwaya`). Hafs par defaut :
    /// c'est le comportement de toutes les versions precedentes, et un modele
    /// a trois tetes n'a tout simplement pas de sortie Warsh.
    @Volatile
    var riwayaWarsh: Boolean = false
        set(v) {
            if (field != v) {
                field = v
                DiagnosticLog.log("FastConformerCtc", "riwaya = " + (if (v) "WARSH (sortie 2)" else "HAFS (sortie 0)"))
            }
        }

    /// Le vocabulaire REELLEMENT utilise, decode comme tokenisation.
    /// Repli sur le Hafs si la tete Warsh est absente (ancien modele) ou si son
    /// vocabulaire n'a pas pu etre lu : mieux vaut du Hafs annonce au journal
    /// qu'un plantage au milieu d'une recitation.
    private var repliVocabJournalise = false
    private val vocab: List<String>
        get() {
            if (!riwayaWarsh) return vocabHafs
            val w = vocabWarsh
            if (w != null) return w
            // Repli BRUYANT, et une seule fois par session : juger du Warsh avec
            // le vocabulaire Hafs est precisement le defaut que cette bascule
            // existe pour supprimer. S il doit arriver quand meme (modele a
            // trois tetes, fichier illisible), il ne doit pas arriver en
            // silence -- sinon on rediagnostique un jour "le Warsh est mal
            // juge" sans savoir que c est le vocabulaire qui manquait.
            if (!repliVocabJournalise) {
                repliVocabJournalise = true
                DiagnosticLog.log("FastConformerCtc",
                    "REPLI : riwaya Warsh demandee mais vocab_warsh.json absent " +
                    "ou illisible -> le Hafs sert de vocabulaire. La detokenisation " +
                    "ET la tokenisation de la cible sont donc FAUSSES pour le Warsh.")
            }
            return vocabHafs
        }

    private val blankId: Int get() = vocab.size // CTC blank = dernier index (vocab_size), verifie cote Python

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

    // ── TETE FINE, cf. [TAJWID_FINE_OUTPUT] ─────────────────────────────────
    // `rules_fine.json` est cherche A COTE de `rules.json` : aucun parametre
    // de plus a faire traverser le pont, et un pack a 4 sorties (sans ce
    // fichier) reste charge exactement comme avant.
    private val tajwidFineNames: List<String> = rulesPath?.let { rp ->
        val f = java.io.File(java.io.File(rp).parentFile, "rules_fine.json")
        if (f.exists()) loadVocab(f.absolutePath) else null
    } ?: emptyList()
    private val hasTajwidFineHead: Boolean =
        tajwidFineNames.isNotEmpty() && session.outputNames.contains(TAJWID_FINE_OUTPUT)

    /** Noms des classes fines, index = position dans la sortie. Vide si absente. */
    val ruleFineNames: List<String> get() = tajwidFineNames

    /** Famille d'une classe fine : le prefixe avant `__`. C'est ainsi que les
     *  76 classes remontent aux 11 familles -- l'export les nomme pour que ce
     *  regroupement soit un simple decoupage, sans table de correspondance a
     *  tenir a jour. */
    fun familleDeRegleFine(i: Int): String? =
        tajwidFineNames.getOrNull(i)?.substringBefore("__")

    /** Seuil de detection PAR CLASSE, en LOG-PROBABILITE (comparable directement
     *  a `tajwid[t][c]`, deja en log-sigmoide). Charge depuis seuils_tajwid.json
     *  (2026-08-16) -- calibre sur audio reel pour que le nombre d'emissions
     *  colle au texte recite, remplace le seuil plat 0,5 ci-dessous. Repli a
     *  ln(0,5) classe par classe si le fichier est absent (anciens model_pack)
     *  OU si une classe de `rules.json` manque dans le fichier de seuils --
     *  jamais un echec bloquant, cf. le meme esprit de tolerance que rules.json
     *  lui-meme pour les modeles a une seule tete.
     *
     *  MESURE A L'APPUI (agregat toutes classes confondues, faute de la table
     *  symbole->classe sur ce poste -- cf. AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md
     *  §3ter) : seuil plat 0,5 sur-detecte de +209% sur la fenetre de calibrage
     *  et +240% hors fenetre (141 versets, Al-Afasy) ; ces seuils par classe
     *  ramenent l'ecart a +28%/+38% -- gain net, verifie hors de sa fenetre de
     *  calibrage donc pas un simple surapprentissage local. */
    private val tajwidSeuilsLog: FloatArray = FloatArray(tajwidNames.size) { Math.log(0.5).toFloat() }.also { arr ->
        // ── DEUX FORMES DE FICHIER, ET C EST VOULU (2026-08-21) ──────────
        //
        // ANCIENNE (modele 3 tetes) : {"seuils": {"nom": 0.87, ...}}
        // NOUVELLE (modele 4 tetes) : {"regles": {"nom": {"seuil": 0.9,
        //                              "rappel": 87.9, "invention": 42.4,
        //                              "n_verif": 340}, ...}}
        //
        // On lit les DEUX plutot que de convertir le fichier livre : la forme
        // nouvelle porte, a cote de chaque seuil, le rappel et le taux
        // d invention MESURES qui l ont fixe. Aplatir le fichier pour coller a
        // l ancien format jetterait ces chiffres -- et c est exactement ce qui
        // rend un seuil discutable plus tard : savoir ce qu il coute.
        //
        // Lire les deux permet aussi de revenir a l ancien modele sans
        // toucher au code, ce que la regle projet exige (aucune piste
        // eliminee tant que le retour arriere est possible).
        val racine = seuilsPath?.let { path ->
            try {
                JSONObject(File(path).readText(Charsets.UTF_8))
            } catch (e: Exception) {
                null
            }
        }
        val plats = racine?.optJSONObject("seuils")
        val riches = racine?.optJSONObject("regles")
        // TROISIEME FORME : LES SEUILS A LA RACINE (2026-08-22)
        //
        // Le paquet deux-geles-int8-2026-08-22-tajwid2 livre le fichier SANS
        // objet enveloppant : { "madd_long": 0.8, "ghunnah": 0.95, ... }.
        // Les deux lectures ci-dessus rendaient alors null toutes les deux, et
        // le repli portait les 17 classes a ln(0,5) SANS UNE LIGNE DE JOURNAL
        // -- soit exactement le seuil plat que ce fichier existe pour
        // remplacer, mesure a +209 % de sur-detection sur la fenetre de
        // calibrage et +240 % hors fenetre. Un fichier livre, lu, et sans
        // effet : la pire des trois situations, parce qu elle se lit comme un
        // succes.
        //
        // On accepte donc la racine elle-meme comme table de seuils, en ne
        // retenant qu une valeur NUMERIQUE portee par un nom de classe connu
        // -- les cles de commentaire du format riche (_a_lire, _madd, _waqf)
        // sont des chaines et ne peuvent pas etre prises pour des seuils.
        val aRacine = racine != null && tajwidNames.any { racine.optDouble(it, Double.NaN).let { d -> !d.isNaN() } }
        tajwidNames.forEachIndexed { i, nom ->
            val v = when {
                plats != null && plats.has(nom) -> plats.optDouble(nom, 0.5)
                riches != null && riches.has(nom) ->
                    riches.optJSONObject(nom)?.optDouble("seuil", 0.5) ?: 0.5
                aRacine -> racine!!.optDouble(nom, Double.NaN)
                else -> Double.NaN
            }
            if (!v.isNaN() && v > 0.0) arr[i] = Math.log(v).toFloat()
        }
        // CE QUE LE JOURNAL DOIT DIRE, ET POURQUOI (2026-08-22). Sans cette
        // ligne, rien ne distingue un fichier lu d un fichier ignore : les
        // deux donnent une app qui demarre. La forme retenue est nommee, et le
        // nombre de classes REELLEMENT servies est compte -- un seuil manquant
        // pour une classe est un repli silencieux de plus.
        val servis = tajwidNames.indices.count { arr[it] != Math.log(0.5).toFloat() }
        val forme = when {
            racine == null -> "absent (repli 0,5 pour tout)"
            plats != null -> "plat sous seuils"
            riches != null -> "riche sous regles"
            aRacine -> "plat a la racine"
            else -> "ILLISIBLE (repli 0,5 pour tout)"
        }
        // DiagnosticLog ET NON android.util.Log : ce fichier met lui-meme en
        // garde plus haut (commentaire du 2026-08-13) -- logcat ne se relit pas
        // apres coup, seul recitation_diagnostic.log sert a une analyse. Ecrit
        // d abord vers logcat le 2026-08-22, la ligne etait invisible dans le
        // journal de la session, donc inutilisable pour instruire une mesure.
        DiagnosticLog.log("FastConformerCtc",
            "seuils tajwid : forme=" + forme + " classes=" + tajwidNames.size +
            " servies=" + servis)
    }
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

    /** Seuil de detection PAR CLASSE, en probabilite (2026-09-02).
     *
     *  `tajwidSeuilsLog` est stocke en LOG (comparable directement aux
     *  logprobs de la tete) ; on rend ici la probabilite equivalente, seule
     *  forme comparable a `DetectedRule.prob` dans un journal lisible.
     *  Ajoute parce que le journal disait « detectee / non detectee » sans
     *  jamais montrer NI la valeur NI le seuil : impossible de voir qu'une
     *  regle passait de justesse, ou qu'une classe avait un seuil aberrant.
     *  Un seuil >= 1 est infranchissable par construction (c'est ainsi que
     *  les 4 regles portees par le texte sont neutralisees cote modele). */
    fun seuilProba(ruleId: Int): Float =
        if (ruleId in tajwidSeuilsLog.indices)
            Math.exp(tajwidSeuilsLog[ruleId].toDouble()).toFloat()
        else 0.5f

    /** Probabilite MAXIMALE atteinte par chaque classe sur cet extrait, que
     *  le seuil ait ete franchi ou NON.
     *
     *  ── LE TROU QUE CELA COMBLE (2026-09-03) ─────────────────────────────
     *
     *  `decodeTajwid` ne rend que les DETECTIONS : une classe qui culmine sous
     *  son seuil ne produit aucun span, donc aucune ligne de journal, donc
     *  aucune probabilite. On savait donc dire pourquoi une regle etait
     *  rejetee PAR SA DUREE (c'est journalise), jamais pourquoi elle l'etait
     *  par son SEUIL -- et impossible de repondre a la question « c'est le
     *  seuil ou la duree qui filtre ? ».
     *
     *  Pire, cela rendait toute statistique sur les probabilites trompeuse :
     *  ne lire que les lignes existantes revient a ne compter que les
     *  rescapes. J'ai moi-meme conclu a tort « 100 % des detections passent le
     *  seuil » a partir de ce biais de selection.
     *
     *  La valeur etait deja calculee a chaque frame : elle etait simplement
     *  jetee. Cette methode ne fait que la rendre.
     *
     *  @return tableau indexe par ruleId, en PROBABILITE (0..1). */
    fun probMaxParClasse(tajwid: Array<FloatArray>?): FloatArray {
        val n = tajwidNames.size
        val out = FloatArray(n)
        if (tajwid == null || !hasTajwidHead) return out
        for (ligne in tajwid) {
            for (c in 0 until minOf(n, ligne.size)) {
                val p = Math.exp(ligne[c].toDouble()).toFloat()
                if (p > out[c]) out[c] = p
            }
        }
        return out
    }

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
    /** @param facteurSeuil rigueur appliquee aux seuils de probabilite
     *  (2026-09-03). Les seuils du fichier sont les MOYENNES mesurees sur cinq
     *  recitateurs professionnels ; exiger la moyenne elle-meme en rejetterait
     *  la moitie. Regle posee par l'utilisateur : 0,90 en strict, 0,70 en
     *  tolerant -- « le strict ne doit pas etre plus que la moyenne mesuree ».
     *
     *  Les seuils sont stockes en LOG : multiplier une probabilite par f
     *  revient a AJOUTER ln(f) au log, d'ou l'addition ci-dessous et non une
     *  multiplication.
     *
     *  ⚠️ Un seuil >= 1 (les quatre regles neutralisees : madda_normal,
     *  laam_shamsiyah, ham_wasl, slnt) doit RESTER infranchissable. Le facteur
     *  ne leur est donc pas applique -- 1,1 x 0,7 = 0,77 les rallumerait, ce
     *  que l'utilisateur a explicitement refuse. */
    fun decodeTajwid(
        tajwid: Array<FloatArray>?,
        facteurSeuil: Float = 1f,
    ): List<DetectedRule> {
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
        //
        // ⚠️ SUPERSEDE (2026-08-16) : vrai comme frontiere mathematique d'une
        // sigmoide, mais mesure sur audio reel FAUX comme critere de decision
        // -- le seuil plat 0,5 sur-detecte de +209% a +240% (calibrage/hors
        // calibrage, cf. tajwidSeuilsLog ci-dessus pour le detail et la
        // source). Chaque classe a sa PROPRE confiance naturelle (mesure :
        // de 0,5 a 0,9633 selon la classe), pas une frontiere commune -- un
        // seuil unique traite donc `madda_permissible` (confiance naturelle
        // 0,9633) comme s'il fallait a peine plus de 50% de certitude pour
        // l'affirmer, d'ou la sur-detection massive sur cette classe et ses
        // semblables. `tajwidSeuilsLog` (par classe, calibre) remplace ce
        // seuil plat ci-dessous ; conserve pour memoire (ne jamais supprimer
        // un commentaire qui documente une decision passee).
        val out = ArrayList<DetectedRule>()
        val nClasses = tajwid.firstOrNull()?.size ?: return emptyList()
        for (c in 0 until nClasses) {
            var debut = -1
            var probMax = 0f
            val seuilBrut =
                if (c < tajwidSeuilsLog.size) tajwidSeuilsLog[c] else Math.log(0.5).toFloat()
            // Les regles neutralisees (seuil >= 1, donc log >= 0) gardent leur
            // seuil tel quel : le facteur les rallumerait.
            val seuilLog =
                if (seuilBrut >= 0f) seuilBrut
                else seuilBrut + Math.log(facteurSeuil.toDouble()).toFloat()
            // ── LES MADD SE DECIDENT PAR COMPARAISON (2026-08-21) ─────────
            //
            // `madd_long` et `madd_court` ne se seuillent PAS separement :
            // le plus grand des deux gagne, trame par trame. Ce sont deux
            // reponses a la MEME question (combien de temps la voyelle
            // tient-elle ?), pas deux phenomenes independants comme le sont
            // une ghunnah et une qalqala.
            //
            // MESURE fournie avec le modele : un madd court prononce la ou un
            // long est attendu sort `madd_long` a 0,538 ET `madd_court`
            // a 0,952. Les seuiller separement les fait donc passer TOUS LES
            // DEUX -- et `madd_long` seul affiche 42,4 % d invention, le pire
            // de toutes les classes. La tete sait ; elle hesite seulement a
            // trancher, et c est a nous de trancher pour elle.
            //
            // `rivalMadd` vaut -1 hors des deux classes de madd : la boucle
            // se comporte alors exactement comme avant, pour toutes les
            // autres regles et pour l ancien modele a 19 classes (dont les
            // noms de madd sont differents, donc jamais apparies ici).
            val rivalMadd = when (tajwidNames.getOrNull(c)) {
                "madd_long" -> tajwidNames.indexOf("madd_court")
                "madd_court" -> tajwidNames.indexOf("madd_long")
                else -> -1
            }
            for (t in tajwid.indices) {
                // Perdant de la comparaison : cette trame ne compte pas pour
                // cette classe. On n interrompt pas le span pour autant --
                // c est le `else if (debut >= 0)` ci-dessous qui le clot,
                // exactement comme un passage sous le seuil.
                val gagneLeDuel =
                    rivalMadd < 0 || tajwid[t][c] >= tajwid[t][rivalMadd]
                val actif = gagneLeDuel && tajwid[t][c] >= seuilLog
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
                    // Sortie 0 = Hafs, sortie 2 = Warsh. Par NOM plutot que par
                    // index quand on vise le Warsh : `logprobs` doit rester en 0
                    // (le contrat du modele le dit), mais rien ne garantit que
                    // `warsh_logprobs` reste en 2 sur un futur export.
                    val brut = if (riwayaWarsh && session.outputNames.contains(WARSH_OUTPUT)) {
                        results.get(WARSH_OUTPUT).get().value
                    } else {
                        results[0].value
                    }
                    @Suppress("UNCHECKED_CAST")
                    val letters = (brut as Array<Array<FloatArray>>)[0]
                    // Recuperation PAR NOM (et non par index) : robuste a un
                    // eventuel reordonnancement des sorties par l'exporteur.
                    val tajwid: Array<FloatArray>? = if (hasTajwidHead) {
                        @Suppress("UNCHECKED_CAST")
                        (results.get(TAJWID_OUTPUT).get().value
                            as Array<Array<FloatArray>>)[0]
                    } else null
                    // Recuperation PAR NOM, comme la tete 2 : un pack sans
                    // cette sortie rend `null` sans erreur (cf. hasTajwidFineHead).
                    val tajwidFine: Array<FloatArray>? = if (hasTajwidFineHead) {
                        @Suppress("UNCHECKED_CAST")
                        (results.get(TAJWID_FINE_OUTPUT).get().value
                            as Array<Array<FloatArray>>)[0]
                    } else null
                    // Meme recuperation PAR NOM que la tete tajwid : robuste a
                    // un reordonnancement des sorties, et absente sans erreur
                    // sur les modeles a une seule sortie.
                    // ── `encoder_state` PEUT ARRIVER TRANSPOSE (2026-09-05)
                    //
                    // La tete 3 attend `etat[frame][512]`. Le paquet v7 sort
                    // `(batch, 512, time)` -- son tenseur s'appelle d'ailleurs
                    // `Transposeencoder_state_dim_2`, l'export l'annonce. Lu
                    // tel quel, `etat[f0].size` vaut alors le NOMBRE DE FRAMES
                    // au lieu de 512, et la moyenne de `Tete3Traits.etatMoyen`
                    // porte sur les mauvaises valeurs -- silencieusement, car
                    // rien ne plante : on moyenne des nombres, juste pas les
                    // bons.
                    //
                    // On compare donc au nombre de frames CONNU (`letters`) et
                    // on retablit l'ordre si besoin. Marche avec les deux
                    // formes, sans rien supposer de l'export.
                    val etat: Array<FloatArray>? = if (hasEncoderState) {
                        @Suppress("UNCHECKED_CAST")
                        val brut = (results.get(ENCODER_STATE_OUTPUT).get().value
                            as Array<Array<FloatArray>>)[0]
                        val nFrames = letters.size
                        if (brut.isNotEmpty() && brut.size != nFrames &&
                            brut[0].size == nFrames) {
                            Array(nFrames) { f ->
                                FloatArray(brut.size) { d -> brut[d][f] }
                            }
                        } else {
                            brut
                        }
                    } else null
                    // .value materialise deja des copies JVM -> survit au close().
                    return CtcOutputs(letters, tajwid, tajwidFine, etat)
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

        /**
         * 5e sortie : tete tajwid FINE, 76 classes -- chaque famille eclatee
         * par paire de lettres exacte (`idgham_ghunnah__l>w`, `qalaqah__q`...),
         * plus un `__other` par famille pour les paires rares.
         *
         * ── POURQUOI EN PLUS, ET NON A LA PLACE (2026-09-07) ──────────────
         *
         * Elle ne remplace pas la tete famille : les deux sont CONFRONTEES.
         * Mesure du PC A, 400 fenetres reelles, 4 voix d'evaluation disjointes,
         * les DEUX tetes lues sur le MEME modele et les MEMES fenetres :
         *
         *     famille          rappel union  rappel inter  inv. union  inv. inter
         *     madd                93,5 %        81,2 %       11,8 %      1,9 %
         *     qalaqah             96,2 %        80,8 %        4,9 %      0,9 %
         *     idgham_ghunnah      88,1 %        81,4 %        2,3 %      0,3 %
         *
         * L'INTERSECTION divise l'invention par 6 a 8, pour ~12 points de
         * rappel. C'est le bon echange ici, et pas un arbitrage de gout : une
         * regle INVENTEE accuse le recitateur d'une faute qu'il n'a pas faite,
         * une regle manquee le laisse seulement sans retour. La hierarchie du
         * projet est « dire vrai » avant « bien juger ».
         *
         * Prise SEULE, la fine est moins bonne que la famille sur 8 familles
         * sur 11 (rappel macro 79,9 % contre 86,4 %) -- eclater 1 264 fenetres
         * `idgham_ghunnah` sur 25 classes coute cher. Son seul avantage propre
         * est l'invention, deux fois moindre (8,9 % contre 14,9 %). C'est ce
         * qui en fait une bonne CONFIRMATION et une mauvaise remplacante.
         *
         * ⚠️ AUCUN VERDICT NE LA LIT (2026-09-07). Elle est seulement
         * journalisee (`[tajwidFine]`), comme la tete 3 avant elle. Le cablage
         * au jugement attend que la recette ait montre l'accord sur du vrai
         * usage -- 400 fenetres de corpus ne suffisent pas a l'engager.
         */
        const val TAJWID_FINE_OUTPUT = "tajwid_fine_logprobs"
        const val ENCODER_STATE_OUTPUT = "encoder_state"
        const val WARSH_OUTPUT = "warsh_logprobs"
    }
}
