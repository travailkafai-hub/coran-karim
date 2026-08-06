package com.corankarim.coran_karim.fastconformer

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Deuxieme verificateur ASR (FastConformer CTC), en parallele de whisper.cpp
 * (canal FFI existant de whisper_ggml, inchange). Un MethodChannel est utilise ici
 * plutot que du FFI car l'API ONNX Runtime Android est Kotlin/Java, pas une lib C
 * a lier directement -- pas de pattern FFI adapte pour ce modele.
 *
 * Cote Dart : voir lib/services/fastconformer_verifier.dart.
 */
class FastConformerCtcPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private companion object { const val TAG = "FastConformerCtcPlugin" }

    private lateinit var channel: MethodChannel
    private var engine: FastConformerCtc? = null
    private var streaming: FastConformerStreamingSession? = null
    // TETE 3 (ecart canonique) : cf. Tete3.kt -- EN OBSERVATION SEULE tant que
    // la parite des 12 scores n'est pas verifiee sur device.
    private var tete3: com.corankarim.coran_karim.recitation2.Tete3? = null
    private var causalAlignment: CausalAlignmentSession? = null
    private var buffered: BufferedTranscriber? = null
    /** Etat du calibrage en cours (cf. "calibrageDemarrer"). Volontairement
     *  independant du moteur ASR : calibrer ne demande AUCUN modele, on mesure
     *  du RMS et des durees de silence. L'ecran doit donc fonctionner meme si
     *  le modele n'est pas charge. */
    @Volatile private var calibrage: com.corankarim.coran_karim.recitation2.Calibrage? = null
    // Seuil personnalise recu AVANT la creation (lazy) du BufferedTranscriber —
    // applique des sa construction, sinon un setCommitSilenceMs appele avant le
    // premier bloc audio serait perdu.
    @Volatile private var pendingCommitSilenceMs: Int? = null
    /** Retenu ici tant que `buffered` n'existe pas (le reglage arrive avant la
     *  premiere inference) -- meme motif que pendingCommitSilenceMs. */
    @Volatile private var pendingNeverBlockAnchor = false
    // Meme pattern : dossier de capture des clips de reference (mini-LoRA
    // personnalisation vocale, cf. setClipCapture), applique des la creation
    // du BufferedTranscriber si demande avant le premier bloc audio.
    @Volatile private var pendingClipCaptureDir: String? = null
    // Cible d'alignement force GOP (cf. ForcedAligner.kt) : mots attendus
    // tokenises + ancre. Stockee au niveau plugin (meme pattern que
    // pendingCommitSilenceMs : setAlignmentTarget peut arriver AVANT le premier
    // bloc audio qui cree le BufferedTranscriber) ET utilisee directement par
    // alignFile (mode coach, un seul WAV, pas de BufferedTranscriber).
    @Volatile private var alignTokens: List<IntArray>? = null
    @Volatile private var alignAnchor: Int = 0
    // Rescoring NLL par mot (cf. ForcedAligner.WordResult.rescoreMargin,
    // ConfusableVariants) : desactive par defaut -- diagnostic pas encore
    // valide sur device (offline seulement, cf. constrained_decoding_eval.py),
    // et calcule un forward CTC supplementaire par variante confusable sur
    // CHAQUE mot d'une passe finale. Active via setRescoringEnabled(true).
    @Volatile private var rescoringEnabled: Boolean = false
    @Volatile private var alignVariants: List<List<Pair<String, IntArray>>>? = null
    private var tokenizer: CtcTokenizer? = null
    // Dictionnaire mot->tokens precalcule (cf. loadModel) -- null si absent.
    @Volatile private var wordTokenLookup: Map<String, IntArray>? = null
    private var fingerprint: VoiceFingerprint? = null
    // ── CHAINE v2, BRANCHEE EN PARALLELE (2026-07-30) ────────────────────────
    // Elle tourne EN PLUS de la v1, sur le meme PCM, et rend ses verdicts a
    // part. C'est le motif que le projet utilise deja pour comparer deux
    // moteurs (`useGopScoring` : les deux calculent, un seul peint l'ecran) --
    // la v1 ne peut donc pas regresser du fait de son branchement.
    // Mesure de reference (banc, flux brut du 2026-07-30) : v1 10,10 % de mots
    // non verts, v2 2,03 %.
    @Volatile private var v2Actif = false
    private var v2Chaine: com.corankarim.coran_karim.recitation2.ChaineRecitation? = null
    @Volatile private var v2Mots: List<String> = emptyList()

    // ── MODE CONTROLE / TEST (2026-08-05, REFONTE_IHM.md §14) ────────────────
    //
    // Demande utilisateur : « je veux que tout le process soit duplique,
    // aucune communication, tout soit etanche ». Avant cette variable, AUCUN
    // flag de mode n'existait cote Kotlin : v2Actif/v2Mots etaient poses sans
    // distinction controle/reference, et le mecanisme d'ancre (Localisateur.kt)
    // ne savait donc pas dans quel mode il tournait -- un correctif fait en
    // mode reference (recette) touchait mecaniquement le mode controle (usage
    // reel).
    //
    // Etape 1 du cloisonnement (celle-ci) : le flag existe et est transmis,
    // MAIS `alimenterV2` instancie encore un seul et meme `ChaineRecitation`
    // pour les deux modes -- la duplication de Localisateur/AligneurForce/
    // ConstructeurDeFenetres/Decideur/ChaineRecitation elle-meme (§14.1-14.3)
    // reste a faire, chantier de plusieurs jours documente dans REFONTE_IHM.md.
    // Defaut 'CTL' : tant que Dart n'a pas encore appele v2SetMode (fenetre
    // de demarrage), un mode absent doit se comporter comme l'usage reel,
    // jamais comme la recette.
    @Volatile private var v2Mode = "CTL"

    /** L'etat v1/v2 a-t-il deja ete journalise pour cette session ? Remis a
     *  faux par `v2SetTarget` (nouvelle cible = nouvelle session). Cf. le bloc
     *  `[V1]` dans `feed` : on veut UNE ligne par session, pas une par bloc
     *  PCM (~12/s). */
    @Volatile private var v1EtatJournalise = false

    /** Bloc de FUSION actif ? Defaut `true` = comportement mesure et en place.
     *  Pilotable par `v2SetFusion` pour mesurer l'hypothese « les apercus 2/4
     *  suffisent » sur device, en recette de reference. */
    /** Index de mots jamais juges (Bismillah), fournis par Dart. Cf.
     *  ChaineRecitation.nonJugeables : sans eux, franchir une frontiere de
     *  sourate compte comme un saut de 4 mots et bloque l'ancre pour de bon. */
    private val v2NonJugeablesInit = mutableSetOf<Int>()
    @Volatile private var v2NonJugeables: MutableSet<Int> = v2NonJugeablesInit

    @Volatile private var v2Fusion = true

    /** Nombre de preuves concordantes exigees pour FIGER un verdict (Decideur.k).
     *  Pilotable par `v2SetFusion(preuves:)` pour tester en recette REELLE
     *  l'autre moitie de l'hypothese « une seule ligne 2/4 suffit ».
     *  MESURE JVM PREALABLE (Al-Baqara 433 s, 295 mots, meme audio, meme
     *  denominateur) -- k=1 ne fait PAS gagner, il fait perdre :
     *      fusion=true  k=2 : 14,24 %   fusion=true  k=1 : 15,59 %
     *      fusion=false k=2 : 19,32 %   fusion=false k=1 : 20,00 %
     *  Raison : un VERT ne passe deja PAS par k (cf. la regle `nette` du
     *  Decideur, qui fige sur UNE observation attestee). k ne retient que les
     *  NON-verts ; l'abaisser ne libere aucun vert, il fige des rouges de
     *  position plus tot. Les 12 mots qui changent d'etat vont tous de
     *  provisoire non-vert a definitif non-vert, aucun ne devient vert. */
    @Volatile private var v2Preuves = 2

    /** Pas et largeur de la ligne d'apercus. Le RECOUVREMENT (largeur - pas)
     *  avait ete choisi a 50 % en supposant une ligne UNIQUE : un mot coupe au
     *  bord d'une fenetre etait alors entier dans la suivante, et c'etait la
     *  seule facon de le revoir. Avec la seconde ligne (blocs fermes aux vrais
     *  silences + fusion), cette relecture existe deja par un autre chemin --
     *  d'ou la question, posee par l'utilisateur, de savoir si le recouvrement
     *  fait encore un travail utile.
     *  Banc JVM (Al-Baqara 433 s, 295 mots, fusion active, k=2) :
     *      pas 2 s (recouvrement 50 %) : 14,24 %  -- 1158 observations
     *      pas 3 s (recouvrement 25 %) : 14,92 %  -- 1084 observations
     *      pas 4 s (recouvrement  0 %) : 13,90 %  --  917 observations
     *  Soit aucun ecart au-dela du bruit pour 21 % de calcul en moins. */
    // DEFAUT PORTE A 4,0 / 4,0 -- RECOUVREMENT SUPPRIME (2026-08-06, decision
    // utilisateur apres mesure). Recette reelle a deux telephones, Al-Baqara
    // v6, 420 s, meme protocole, avec les DEUX lignes actives :
    //     recouvrement 50 % : 278 fenetres, 1838 s presentes -> 1,69 % non verts
    //     recouvrement 50 % : 275 fenetres, 1800 s presentes -> 1,02 %
    //     recouvrement  0 % : 214 fenetres, 1603 s presentes -> 1,02 %
    // Soit le meilleur des deux passes a 50 %, pour 23 % de fenetres en moins.
    // La cadence ne bouge pas (1,28 s contre 1,16 s) : la ligne de blocs
    // continue de produire des fenetres entre les apercus.
    // CE QUI EST AFFIRME : aucune perte detectable. PAS un gain de qualite --
    // les deux passes a 50 % donnaient deja 5 puis 3 mots non verts, l'ecart
    // mesure (0 mot) est plus petit que cette variance. Le gain certain est le
    // calcul. Le banc deterministe (meme audio) concorde : 13,90 % contre
    // 14,24 %.
    @Volatile private var v2Pas = 4.0
    @Volatile private var v2Largeur = 4.0

    /** Duree maximale d'un bloc de la SECONDE ligne (celle qui coupe aux vrais
     *  silences). Valait 30 s par defaut -- jamais passee explicitement, donc
     *  jamais choisie. Mesure : la mediane des fenetres longues etait de 9,2 s
     *  et le maximum de 21,8 s.
     *  ESSAYE A 5 s le 2026-08-06, puis REVENU A 30 s. Deux raisons, dans cet
     *  ordre :
     *  1. a 5 s, le bloc de FUSION n'etait plus jamais produit -- il vaut deux
     *     blocs, et il partageait alors ce meme plafond. Recette reelle :
     *     24,41 % de mots non verts dont 46 `omis`, ZERO fenetre de plus de
     *     6 s. Cause corrigee depuis (maxFusionSecondes, plafond separe) ;
     *  2. plafond separe une fois en place, la configuration retenue (apercus
     *     4 s sans recouvrement) n'avait ete MESUREE qu'avec maxBloc=30.
     *
     *  PORTE A 10 s LE 2026-08-06 apres balayage complet. Demande utilisateur
     *  (« je pense pas que c'est bien d'avoir autant de mots » dans un bloc) :
     *  a 30 s une fenetre portait jusqu'a 58 mots.
     *
     *  BANC JVM (Al-Baqara 433 s, meme audio, apercus 4/4, k=2) :
     *      maxBloc/maxFusion   blocs   obs    non verts
     *          30 / 30          265   1162      13,90 %
     *          15 / 30          273   1151      13,90 %
     *          10 / 18          302   1107      13,90 %   <- retenu
     *          12 / 24          286   1142      14,24 %
     *          10 / 16          299   1081      15,59 %
     *          10 / 15          296   1058      15,93 %
     *  La falaise est entre maxFusion 18 et 16 : en dessous, la fusion cesse
     *  d'etre produite et le rattrapage disparait avec elle.
     *
     *  RECETTE REELLE, rejeu deterministe du meme WAV, sur DEUX telephones :
     *      30 / 30  : 210 fenetres, plus longue 26,0 s, 38 au-dela de 12 s -> 1,02 %
     *      15 / 30  : 221 fenetres, plus longue 21,8 s, 39 au-dela de 12 s -> 1,02 %
     *      10 / 18  : 240 fenetres, plus longue 16,9 s, 19 au-dela de 12 s -> 1,02 %
     *  Memes trois mots non verts (172, 228, 285) dans les six passes, et
     *  resultat IDENTIQUE sur le Redmi. 10/18 est donc le plus serre a qualite
     *  strictement egale.
     *
     *  CE QU'IL NE FAUT PAS EN CONCLURE : que « le modele s'effondre au-dela
     *  de 12 s ». C'est l'inverse. Mot 67 `أَلَآ`, meme audio : a 30/30 il est
     *  d'abord declare `omis` (gop=-2,96, bord) puis REPECHE quatre secondes
     *  plus tard en `provisoire:vert` (gop=0,00, INT, obs=4) -- par les
     *  fenetres de 9,6 / 11,8 / 11,4 s. A 6/12, seules deux fenetres (4,0 s et
     *  6,0 s) le couvrent, obs=1, et il reste `omis`. Les fenetres longues NE
     *  SONT PAS du gaspillage : ce sont elles le rattrapage. Plafonner en
     *  dessous de 18 s degrade de facon monotone (2,37 % a 6/12, 4,07 % a 4/8,
     *  9,15 % a 8/8 ou la fusion disparait). */
    @Volatile private var v2MaxBloc = 10.0

    /** Plafond du bloc de FUSION. 30 s = valeur effective historique (elle
     *  etait celle de [v2MaxBloc] avant que les deux soient separes).
     *  PORTE A 18 s le 2026-08-06 : c'est la derniere valeur qui ne coute
     *  rien (cf. le tableau de [v2MaxBloc] -- 18 s : 13,90 %, 16 s : 15,59 %).
     *  Ne pas descendre en dessous sans remesurer : la fusion cesse alors
     *  d'etre produite, en silence. */
    @Volatile private var v2MaxFusion = 18.0
    private val scope = CoroutineScope(Dispatchers.Default)

    /** Cache de l'app -- seul besoin : ecrire l'extrait de voix rejoue au tap
     *  sur un mot (cf. `v2ExtraitVoix`). Capture ici parce que le plugin n'a
     *  aucun autre acces au contexte. */
    private var cacheDir: java.io.File? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.corankarim/fastconformer_ctc")
        channel.setMethodCallHandler(this)
        cacheDir = binding.applicationContext.cacheDir
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        engine?.close()
        engine = null
        streaming?.close()
        streaming = null
        causalAlignment = null
        fingerprint?.close()
        fingerprint = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Relie le fichier de log persistant sur le telephone (cf.
            // lib/services/diagnostic_log.dart) -- BufferedTranscriber et
            // ForcedAligner y ecrivent via DiagnosticLog.kt pour que TOUT le
            // pipeline (Dart + natif) atterrisse dans la meme chronologie,
            // recuperable par `adb pull` a la demande (demande utilisateur
            // 2026-07-11), independamment de toute connexion adb continue.
            "setLogFile" -> {
                val path = call.argument<String>("path")
                if (path != null) DiagnosticLog.setFile(path)
                result.success(null)
            }
            // ── CALIBRAGE ────────────────────────────────────────────────────
            // Le calcul reste en Kotlin, dans la classe Calibrage, et l'ecran
            // Flutter ne fait que l'alimenter et afficher. Refaire l'estimation
            // en Dart aurait duplique une logique de seuil dans deux langages --
            // ce que le projet a deja paye deux fois (« le banc mesurait mon
            // decoupage, pas l'app »). Ici il n'y a qu'une implementation, et
            // c'est la meme que le banc JVM mesure.
            "calibrageDemarrer" -> {
                // `cumuler` = garder les sessions precedentes. Demande
                // utilisateur : l'estimateur des silences est pauvre en donnees
                // (une minute n'en contient qu'une quarantaine), enchainer
                // plusieurs sessions le stabilise.
                val cumuler = call.argument<Boolean>("cumuler") ?: false
                if (!cumuler || calibrage == null) {
                    calibrage = com.corankarim.coran_karim.recitation2.Calibrage()
                }
                DiagnosticLog.log(
                    "CALIB",
                    "demarrage cumuler=$cumuler sessions=${calibrage?.sessions ?: 0} " +
                        "silences deja cumules=${calibrage?.silencesCumulesCount ?: 0}"
                )
                result.success(null)
            }
            // Cloture la session en cours : elle derive SON propre niveau de
            // parole avant d'en extraire ses silences. Deux sessions a des
            // distances differentes du micro n'ont pas le meme niveau ; un p75
            // commun serait trop haut pour l'une et trop bas pour l'autre.
            "calibrageCloturerSession" -> {
                val c = calibrage
                if (c == null) {
                    result.error("CALIBRAGE", "calibrage non demarre", null)
                } else {
                    val n = c.cloturerSession()
                    DiagnosticLog.log(
                        "CALIB",
                        "session ${c.sessions} close : +$n silences, " +
                            "total=${c.silencesCumulesCount} sur " +
                            "${"%.1f".format(c.secondesTotales)} s"
                    )
                    result.success(mapOf(
                        "sessions" to c.sessions,
                        "silences" to c.silencesCumulesCount,
                        "secondes" to c.secondesTotales,
                        "apportes" to n,
                    ))
                }
            }
            "calibrageAlimenter" -> {
                val c = calibrage
                if (c == null) {
                    result.error("CALIBRAGE", "calibrage non demarre", null)
                } else {
                    // PCM16 BRUT, exactement le format que la chaine de
                    // recitation recoit du paquet `record` (pcm16bits, 16 kHz,
                    // mono). Calibrer sur une AUTRE source aurait mesure autre
                    // chose que ce que la chaine verra -- et c'est precisement
                    // l'erreur qui a fait rendre une mesure vide au premier
                    // essai : l'ecran utilisait AudioRecorderPlugin, qui n'est
                    // enregistre nulle part (MainActivity n'ajoute que ce
                    // plugin-ci), donc `stop()` rendait une liste VIDE sans la
                    // moindre erreur.
                    //
                    // Envoi par blocs au fil de l'eau plutot qu'en un bloc
                    // final : une minute de recitation ferait 2 Mo sur le canal.
                    val pcm16 = call.argument<ByteArray>("pcm16")
                    if (pcm16 == null) {
                        result.error("CALIBRAGE", "pcm16 manquant", null)
                    } else {
                        c.alimenter(pcm16ToFloat(pcm16))
                        result.success(c.secondes)
                    }
                }
            }
            "calibrageResultat" -> {
                val c = calibrage
                if (c == null) {
                    result.error("CALIBRAGE", "calibrage non demarre", null)
                } else {
                    val r = c.resultat()
                    // TRACE PERSISTANTE — sans elle le calibrage ne laisse
                    // AUCUNE trace recuperable par `adb pull`, contrairement au
                    // reste de la chaine. Constate le 2026-07-31 : demande de
                    // « recuperer le log du calibrage », rien a rendre.
                    // On journalise la DISTRIBUTION, pas seulement la valeur :
                    // c'est elle qui dit si le reglage tient.
                    DiagnosticLog.log(
                        "CALIB",
                        "resultat fiable=${r.fiable} ${"%.1f".format(r.secondes)}s " +
                            "blocs=${r.blocs} silences=${r.silences.size} " +
                            "niveau=${"%.4f".format(r.niveauParole)} " +
                            "seuilRms=${"%.4f".format(r.seuilRms)}" +
                            (if (r.seuilRmsBorne) "(BORNE)" else "") +
                            " p10=${"%.2f".format(r.percentile(10))}" +
                            " p25=${"%.2f".format(r.percentile(25))}" +
                            " p50=${"%.2f".format(r.percentile(50))}" +
                            " p75=${"%.2f".format(r.percentile(75))}" +
                            " p90=${"%.2f".format(r.percentile(90))}" +
                            " p95=${"%.2f".format(r.percentile(95))}" +
                            " separation=${"%.2f".format(r.separation)}" +
                            " -> pause=${"%.3f".format(r.pause)}" +
                            (if (r.pauseBornee) "(BORNE)" else "") +
                            (if (r.pourquoi != null) " | ${r.pourquoi}" else "")
                    )
                    result.success(
                        mapOf(
                            "secondes" to r.secondes,
                            "blocs" to r.blocs,
                            "niveauParole" to r.niveauParole.toDouble(),
                            "seuilRms" to r.seuilRms.toDouble(),
                            "seuilRmsBorne" to r.seuilRmsBorne,
                            "nbSilences" to r.silences.size,
                            "p10" to r.percentile(10), "p25" to r.percentile(25),
                            "p50" to r.percentile(50), "p75" to r.percentile(75),
                            "p90" to r.percentile(90), "p95" to r.percentile(95),
                            "separation" to r.separation,
                            "pause" to r.pause,
                            "pauseBornee" to r.pauseBornee,
                            "fiable" to r.fiable,
                            "pourquoi" to r.pourquoi,
                            // Les reglages actuellement en vigueur, pour que
                            // l'ecran montre l'ECART et non un chiffre isole.
                            "pauseActuelle" to 0.35,
                            "rapportPause" to
                                com.corankarim.coran_karim.recitation2.Calibrage.RAPPORT_PAUSE,
                        )
                    )
                }
            }
            "loadModel" -> scope.launch {
                try {
                    // Correctif crash natif (2026-07-23) : voir le meme
                    // correctif et son explication complete dans
                    // BufferedTranscriber.kt (juste avant engine.computeAll).
                    // Ici en plus car c'est la PREMIERE fois que le thread
                    // touche la bibliotheque native (creation de la session
                    // ONNX) -- fixer le classloader des ce premier contact
                    // laisse la lib natif mettre en cache les bonnes
                    // references de classe pour tous les appels suivants,
                    // depuis n'importe quel thread du pool.
                    Thread.currentThread().contextClassLoader =
                        FastConformerCtc::class.java.classLoader
                    // Idempotent : NE PAS fermer/recreer un moteur deja charge.
                    // `engine` est partage par tous les appelants Dart (la
                    // transcription mono-shot ET le flux continu bufferise du
                    // karaoke, cf. feedBufferedAudio) -- chaque nouvelle
                    // instance Dart de FastConformerVerifier() a son propre
                    // flag `_loaded` local et rappelle loadModel() sans savoir
                    // qu'un moteur tourne deja. Bug reel constate 2026-07-06 :
                    // ouvrir la boucle de correction manuelle ("reessayer ce
                    // mot") pendant une recitation karaoke fermait la session
                    // ONNX en cours d'utilisation par le flux continu ->
                    // IllegalStateException "Trying to score a closed
                    // OrtSession" en boucle, recitation cassee jusqu'a relance.
                    if (engine != null) {
                        withContext(Dispatchers.Main) { result.success(true) }
                        return@launch
                    }
                    // Une autre instance Dart peut appeler loadModel pendant
                    // une recitation causale. Ne jamais fermer son moteur
                    // global : le changement explicite passe d'abord par
                    // disposeStreaming(), sinon ce chargement est refuse.
                    if (streaming != null) {
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val modelPath = call.argument<String>("modelPath")!!
                    val vocabPath = call.argument<String>("vocabPath")!!
                    // rules.json : noms des classes de la TETE 2 (modeles a deux
                    // tetes, cf. export_dual_head_checkpoint.py). Optionnel --
                    // absent sur les anciens modeles, la detection tajwid reste
                    // alors simplement inactive.
                    val rulesPath = call.argument<String>("rulesPath")
                    engine = FastConformerCtc(modelPath, vocabPath, rulesPath)
                    DiagnosticLog.log(TAG, "modele charge — tete tajwid : " +
                        if (engine!!.hasTajwid) "OUI (${engine!!.ruleNames.size} classes)"
                        else "non (modele a une seule tete)")
                    // TETE 3 (ecart canonique) : optionnelle, EN OBSERVATION
                    // SEULE (cf. Tete3.kt -- tant que la parite des 12 scores
                    // n'est pas verifiee sur device, sa sortie ne doit trancher
                    // aucun verdict). Absente sans erreur si le fichier manque.
                    val tete3Path = call.argument<String>("tete3Path")
                    tete3 = tete3Path?.let {
                        try { com.corankarim.coran_karim.recitation2.Tete3.charger(
                            java.io.File(it).readText(Charsets.UTF_8)) }
                        catch (e: Exception) { null }
                    }
                    DiagnosticLog.log(TAG, "tete3 chargee : ${tete3 != null}")
                    // Dictionnaire mot->tokens precalcule (optionnel, cf.
                    // build_word_token_lookup.py) -- source primaire du
                    // tokenizer de l'alignement force, null si absent
                    // (CtcTokenizer se rabat alors sur le greedy pour tout).
                    val wordTokensPath = call.argument<String>("wordTokensPath")
                    wordTokenLookup = wordTokensPath?.let { loadWordTokenLookup(it) }
                    tokenizer = null // reconstruit au prochain setAlignmentTarget avec le bon lookup
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("LOAD_FAILED", e.message, null) }
                }
            }
            "transcribe" -> scope.launch {
                try {
                    val wavPath = call.argument<String>("wavPath")!!
                    val current = engine
                    if (current == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val text = current.transcribe(pcm)
                    withContext(Dispatchers.Main) { result.success(text) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("TRANSCRIBE_FAILED", e.message, null) }
                }
            }
            "dispose" -> {
                buffered = null
                engine?.close()
                engine = null
                result.success(null)
            }
            // ── Streaming cache-aware (vrai flux continu, karaoke) ─────────────
            "loadStreamingModel" -> scope.launch {
                try {
                    if (streaming != null) {
                        withContext(Dispatchers.Main) { result.success(true) }
                        return@launch
                    }
                    // Symetrique de loadModel : une instance secondaire ne
                    // doit pas fermer le moteur stateless d'une session active.
                    // Le proprietaire appelle dispose() avant une bascule
                    // intentionnelle (FastConformerVerifier).
                    if (engine != null) {
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val modelPath = call.argument<String>("modelPath")!!
                    val vocabPath = call.argument<String>("vocabPath")!!
                    val configPath = call.argument<String>("configPath")!!
                    val wordTokensPath = call.argument<String>("wordTokensPath")
                    // Contrainte device 6 Go : le modele causal et le modele
                    // stateless ne doivent jamais cohabiter. Le fallback est
                    // recharge seulement si ce chargement echoue cote Dart.
                    buffered = null
                    Thread.currentThread().contextClassLoader =
                        FastConformerStreamingSession::class.java.classLoader
                    val newStreaming = FastConformerStreamingSession(
                        modelPath,
                        vocabPath,
                        configPath,
                    )
                    streaming = newStreaming
                    causalAlignment = CausalAlignmentSession(
                        newStreaming.vocabPieces,
                        newStreaming.blank,
                    )
                    wordTokenLookup =
                        wordTokensPath?.let { loadWordTokenLookup(it) }
                    tokenizer = null
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    streaming?.close()
                    streaming = null
                    causalAlignment = null
                    withContext(Dispatchers.Main) { result.error("LOAD_STREAMING_FAILED", e.message, null) }
                }
            }
            "feedAudioChunk" -> scope.launch {
                try {
                    val pcm16 = call.argument<ByteArray>("pcm16")!!
                    val current = streaming
                    if (current == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadStreamingModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val samples = pcm16ToFloat(pcm16)
                    val output = current.feedAudio(samples)
                    withContext(Dispatchers.Main) { result.success(output.text) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("FEED_CHUNK_FAILED", e.message, null) }
                }
            }
            "feedCausalAudio" -> scope.launch {
                try {
                    val pcm16 = call.argument<ByteArray>("pcm16")!!
                    val current = streaming
                    if (current == null) {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "NOT_LOADED",
                                "loadStreamingModel() n'a pas ete appele",
                                null,
                            )
                        }
                        return@launch
                    }
                    val output = current.feedAudio(pcm16ToFloat(pcm16))
                    val alignment = causalAlignment?.feed(output.logProbs)
                    val payload = mapOf(
                        "committed" to output.text,
                        "preview" to "",
                        "align" to alignment,
                        "inferenceCount" to output.inferenceCount,
                        "cacheLength" to output.cacheLength,
                    )
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("FEED_CAUSAL_FAILED", e.message, null)
                    }
                }
            }
            "resetStreaming" -> {
                streaming?.reset()
                causalAlignment?.reset()
                result.success(null)
            }
            "disposeStreaming" -> {
                streaming?.close()
                streaming = null
                causalAlignment = null
                result.success(null)
            }
            // ── Streaming "bufferise" (fallback fiable, cf. BufferedTranscriber) ──
            // Reutilise le moteur OFFLINE (engine) deja charge via loadModel --
            // pas de session/modele separe a charger ici.
            "feedBufferedAudio" -> scope.launch {
                try {
                    val pcm16 = call.argument<ByteArray>("pcm16")!!
                    val current = engine
                    if (current == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    // ── v1 COUPEE QUAND LA v2 PILOTE (2026-07-30) ──────────
                    // Les deux moteurs tournaient sur le meme audio : le
                    // telephone faisait le travail DEUX FOIS. Mesure : sur le
                    // Redmi, les seules passes v1 prenaient 1167 ms en mediane
                    // (2015 ms au pire), et l'affichage devenait lourd.
                    // La v1 reste entierement presente et redevient active des
                    // que `v2SetEnabled(false)` -- c'est toujours le filet de
                    // securite, il ne consomme simplement plus rien tant que la
                    // v2 fait mieux (2,03 % contre 10,10 %).
                    val v1Coupee = v2Actif && v2Mots.isNotEmpty()
                    // ── PREUVE QUE LA v1 NE SERT PLUS (2026-08-06, demande
                    // utilisateur : « rajoute du log V1 pour s'assurer que
                    // rien ne se declenche et que rien n'est necessaire au
                    // fonctionnement de la v2, comme ca on nettoie le code »).
                    //
                    // Journalise UNE FOIS par session, pas a chaque bloc PCM
                    // (~12 appels/s : le log serait inutilisable et fausserait
                    // la mesure du temps reel). Ce qu'on veut savoir tient en
                    // une ligne : la v1 a-t-elle ete instanciee, et a-t-elle
                    // consomme de l'audio ?
                    //
                    // Lecture : si `v1Coupee=true` et `bufferedExiste=false`
                    // sur toute une session, alors AUCUN code v1 n'a tourne et
                    // la suppression est sans risque. Si `bufferedExiste=true`
                    // alors qu'on est en v2, c'est un reste d'une session
                    // precedente -- a instruire avant de supprimer quoi que ce
                    // soit.
                    if (!v1EtatJournalise) {
                        v1EtatJournalise = true
                        DiagnosticLog.log(TAG, "[V1] etat au 1er bloc : " +
                            "v1Coupee=$v1Coupee v2Actif=$v2Actif " +
                            "v2Mots=${v2Mots.size} bufferedExiste=${buffered != null} " +
                            "-- si v1Coupee et !bufferedExiste, la v1 ne tourne pas")
                    }
                    if (buffered == null && !v1Coupee) {
                        DiagnosticLog.log(TAG, "[V1] INSTANCIATION de " +
                            "BufferedTranscriber -- la v1 VA tourner (v2Actif=$v2Actif " +
                            "v2Mots=${v2Mots.size})")
                        buffered = BufferedTranscriber(current)
                        pendingCommitSilenceMs?.let { buffered!!.setCommitSilenceMs(it) }
                        buffered!!.setNeverBlockAnchor(pendingNeverBlockAnchor)
                        buffered!!.setClipCapture(pendingClipCaptureDir)
                        alignTokens?.let { buffered!!.setAlignmentTarget(it, alignAnchor, alignVariants) }
                    }
                    val samples = pcm16ToFloat(pcm16)
                    // ── REDECOUPAGE EN BLOCS DE 80 ms (2026-07-27) ──────────
                    // Dart groupe desormais plusieurs blocs par appel pour
                    // reduire les allers-retours MethodChannel (la file
                    // atteignait ~35 s, cf. le commentaire du listener PCM).
                    // Mais le portier RMS et la detection de pause de
                    // BufferedTranscriber decident PAR APPEL a feed() :
                    // transmettre un gros paquet d'un coup rendrait le portier
                    // plus grossier et changerait la segmentation.
                    // On regroupe donc le TRANSPORT sans toucher au TRAITEMENT :
                    // le natif redecoupe a la granularite d'origine, et le
                    // comportement reste bit pour bit celui d'avant.
                    val block = 1280 // 80 ms a 16 kHz, la taille livree par le micro
                    if (!v1Coupee) {
                        var off = 0
                        while (off < samples.size) {
                            val end = minOf(off + block, samples.size)
                            buffered!!.feed(samples.copyOfRange(off, end), scope)
                            off = end
                        }
                    }
                    // Parties figee/apercu separees : le scoring Dart s'ancre sur
                    // la partie figee (append-only) au lieu de re-aligner du mot 0.
                    // "align" : dernier resultat d'alignement force GOP (nullable,
                    // deduplique cote Dart par son champ "seq").
                    // La v2 recoit LE MEME audio, en parallele, et rend ses
                    // propres changements de statut. Aucun etat partage avec la
                    // v1 : si elle echoue, la v1 continue exactement comme
                    // avant (le catch est local).
                    val v2 = if (v2Actif) alimenterV2(current, samples) else null
                    // DECROCHAGE : champ SEPARE du flux des statuts (2026-08-01).
                    // Volontairement pas un element de la liste "v2" : celle-ci
                    // ne transporte que des verdicts par mot attendu, et y
                    // glisser une entree d'un autre genre (index -1 ou statut
                    // inconnu du parseur) risquerait de casser sa lecture cote
                    // Dart. Ici, une cle a part que l'ancien code ignore.
                    val decrochage = v2Chaine?.decrochage == true
                    val motDecrochage = v2Chaine?.motDuDecrochage ?: -1
                    if (decrochage) v2Chaine?.accuserDecrochage()
                    val payload = mapOf(
                        "committed" to (buffered?.committed ?: ""),
                        "preview" to (buffered?.preview ?: ""),
                        "align" to buffered?.alignmentPayload(),
                    ) + (v2?.let { mapOf("v2" to it) } ?: emptyMap()) +
                        (if (decrochage) mapOf(
                            "v2Decrochage" to true,
                            // Mot a partir duquel reprendre : le dernier
                            // DEFINITIF, pas le pointeur (reste a 0 quand rien
                            // n'a pu etre juge -- mesure 2026-08-01).
                            "v2DecrochageMot" to motDecrochage,
                        ) else emptyMap())
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("FEED_BUFFERED_FAILED", e.message, null) }
                }
            }
            "resetBuffered" -> {
                buffered?.reset()
                result.success(null)
            }
            // Vide la trace fine accumulee en memoire (cf. DiagnosticLog.trace)
            // -- A APPELER HORS RECITATION uniquement : c'est une ecriture
            // fichier unique mais volumineuse.
            "flushTrace" -> {
                result.success(DiagnosticLog.flushTrace())
            }
            "setNeverBlockAnchor" -> {
                val v = call.argument<Boolean>("value") ?: false
                pendingNeverBlockAnchor = v
                buffered?.setNeverBlockAnchor(v)
                result.success(null)
            }
            "traceReset" -> {
                DiagnosticLog.traceReset()
                result.success(null)
            }
            // ── Alignement force GOP (cf. ForcedAligner.kt) ────────────────────
            // Le texte attendu est CONNU d'avance : chaque passe de transcription
            // aligne de force les mots restants sur les logprobs et retourne un
            // score par mot (gop = forced - free) au lieu de laisser Dart faire
            // un diff textuel flou apres coup.
            "setAlignmentTarget" -> scope.launch {
                try {
                    val current = engine
                    val currentStreaming = streaming
                    val vocabPieces =
                        current?.vocabPieces ?: currentStreaming?.vocabPieces
                    if (vocabPieces == null) {
                        // Pas une erreur : le modele n'est juste pas encore deploye.
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val words = call.argument<List<String>>("words")!!
                    val anchor = call.argument<Int>("anchor") ?: 0
                    if (tokenizer == null) {
                        tokenizer = CtcTokenizer(vocabPieces, wordTokenLookup)
                    }
                    val tokens = words.map { tokenizer!!.tokenizeWord(it) }
                    val empty = tokens.count { it.isEmpty() }
                    if (empty > 0) {
                        DiagnosticLog.log("FastConformerCtcPlugin",
                            "$empty mot(s) intokenisable(s) sur ${words.size} — alignement quand meme actif")
                    }
                    alignTokens = tokens
                    alignAnchor = anchor
                    val variants = if (rescoringEnabled) buildVariants(words) else null
                    alignVariants = variants
                    // Planchers de duree de reference (frames), envoyes par Dart
                    // (WordTimingService) en parallele de `words` -- null pour un
                    // mot hors couverture quran.com. Cf. ForcedAligner.combinedMinFrames.
                    val refMinFrames = call.argument<List<Int?>>("refMinFrames")
                    buffered?.setAlignmentTarget(tokens, anchor, variants, refMinFrames)
                    causalAlignment?.setTarget(tokens, anchor, variants, refMinFrames)
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("SET_ALIGN_TARGET_FAILED", e.message, null) }
                }
            }
            "setAlignmentAnchor" -> {
                val anchor = call.argument<Int>("anchor")
                if (anchor != null) {
                    alignAnchor = anchor
                    buffered?.setAlignmentAnchor(anchor)
                    causalAlignment?.setAnchor(anchor)
                }
                result.success(null)
            }
            // Enchainement sur la sourate suivante (demande utilisateur
            // 2026-07-11) : ajoute des mots a la SUITE de la cible actuelle sans
            // toucher l'ancre -- la recitation continue exactement ou elle en
            // etait, juste avec plus de texte a reciter derriere.
            "extendAlignmentTarget" -> scope.launch {
                try {
                    val current = engine
                    val currentStreaming = streaming
                    val vocabPieces =
                        current?.vocabPieces ?: currentStreaming?.vocabPieces
                    if (vocabPieces == null) {
                        withContext(Dispatchers.Main) { result.success(false) }
                        return@launch
                    }
                    val words = call.argument<List<String>>("words")!!
                    if (tokenizer == null) {
                        tokenizer = CtcTokenizer(vocabPieces, wordTokenLookup)
                    }
                    val newTokens = words.map { tokenizer!!.tokenizeWord(it) }
                    alignTokens = (alignTokens ?: emptyList()) + newTokens
                    val newVariants = if (rescoringEnabled) buildVariants(words) else null
                    if (newVariants != null) {
                        val currentV = alignVariants ?: List((alignTokens?.size ?: newTokens.size) - newTokens.size) { emptyList() }
                        alignVariants = currentV + newVariants
                    }
                    val newRefMinFrames = call.argument<List<Int?>>("refMinFrames")
                    buffered?.extendAlignmentTarget(newTokens, newVariants, newRefMinFrames)
                    causalAlignment?.extendTarget(newTokens, newVariants, newRefMinFrames)
                    DiagnosticLog.log("FastConformerCtcPlugin",
                        "cible etendue : +${newTokens.size} mots, total=${alignTokens?.size}")
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("EXTEND_ALIGN_TARGET_FAILED", e.message, null) }
                }
            }
            // Mode coach (segment WAV unique) : une inference + alignement force
            // one-shot sur la cible courante. Resultat toujours final (l'audio
            // est complet, il ne sera jamais reanalyse).
            "alignFile" -> scope.launch {
                try {
                    val current = engine
                    val tokens = alignTokens
                    if (current == null || tokens == null) {
                        withContext(Dispatchers.Main) { result.success(null) }
                        return@launch
                    }
                    val wavPath = call.argument<String>("wavPath")!!
                    val anchor = alignAnchor.coerceIn(0, tokens.size)
                    if (anchor >= tokens.size) {
                        withContext(Dispatchers.Main) { result.success(null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val outputs = current.computeAll(pcm)
                    val logprobs = outputs.letters
                    val segmentRules = current.decodeTajwid(outputs.tajwid)
                    val aligner = ForcedAligner(current.vocabPieces, current.blank)
                    val slice = tokens.subList(anchor, tokens.size)
                    val variantsSlice = alignVariants?.let {
                        if (anchor < it.size) it.subList(anchor, it.size) else null
                    }
                    var res = aligner.align(logprobs, slice, anchor, isFinal = true,
                                            wordVariants = variantsSlice, segmentRules = segmentRules)
                    if (res == null) {
                        withContext(Dispatchers.Main) { result.success(null) }
                        return@launch
                    }
                    // Bug corrige 2026-07-16 (revue de code, Finding #3) : ce
                    // mode one-shot ne rappelait jamais align() avec
                    // forceJudgeIndex -- un mot differe (res.deferredIndex)
                    // etait donc perdu DEFINITIVEMENT pour ce clip (pas de
                    // "prochain appel FINAL" possible ici, contrairement au
                    // mode continu ou BufferedTranscriber s'en charge via
                    // deferredOnceIndex). Comme tout l'audio du clip est deja
                    // disponible, le "prochain appel" peut se faire ICI MEME,
                    // dans le meme invocation : redemande l'alignement en
                    // forcant ce mot precis, garantissant le jugement promis
                    // par le contrat "2 chances max" meme en mode one-shot.
                    val deferred = res.deferredIndex
                    if (deferred != null) {
                        val retried = aligner.align(
                            logprobs, slice, anchor, forceJudgeIndex = deferred, isFinal = true,
                            wordVariants = variantsSlice, segmentRules = segmentRules)
                        if (retried != null) res = retried
                    }
                    val payload = mapOf(
                        "seq" to -1, // one-shot : pas de dedup necessaire cote Dart
                        "anchor" to anchor,
                        "frontier" to res!!.frontier,
                        "final" to true,
                        "words" to res!!.words.map {
                            mapOf(
                                "i" to it.index,
                                "gop" to it.gop,
                                "forced" to it.forced,
                                "covered" to it.covered,
                                "actual" to it.actual,
                                "starved" to it.starved,
                                "frames" to it.frames,
                                "noEvidence" to it.noEvidence,
                            ) + (it.rescoreMargin?.let { m -> mapOf("rescoreMargin" to m) } ?: emptyMap()) +
                                (it.rescoreHeard?.let { h -> mapOf("rescoreHeard" to h) } ?: emptyMap()) +
                                (if (it.detectedRules.isEmpty()) emptyMap() else mapOf(
                                    "rules" to it.detectedRules.map { r ->
                                        mapOf("id" to r.ruleId, "prob" to r.prob.toDouble())
                                    }))
                        },
                    )
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("ALIGN_FILE_FAILED", e.message, null) }
                }
            }
            // Rescoring NLL par mot (cf. ForcedAligner.WordResult.rescoreMargin) :
            // recalcule les variantes confusables de la cible d'alignement DEJA
            // fixee (si presente), pour ne pas exiger un nouvel appel
            // setAlignmentTarget cote Dart juste pour activer le diagnostic.
            "setRescoringEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                rescoringEnabled = enabled
                result.success(null)
            }
            // Profil de pauses personnel (par passage, cf. BufferedTranscriber) :
            // le seuil de gel s'adapte a la facon dont CET utilisateur recite CE
            // passage, appris de ses recitations validees precedentes.
            "setCommitSilenceMs" -> {
                val ms = call.argument<Int>("ms")
                if (ms != null) {
                    pendingCommitSilenceMs = ms
                    buffered?.setCommitSilenceMs(ms)
                }
                result.success(null)
            }
            "getSessionPauses" -> {
                result.success(buffered?.getSessionPausesMs() ?: emptyList<Int>())
            }
            // Capture de clips VERIFIES CORRECTS (mini-LoRA personnalisation
            // vocale, cf. FONCTIONNALITES_FUTURES.md "Personnalisation voix --
            // niveau 3", implemente 2026-07-12). [dir] = null desactive la
            // capture (defaut). C'est Dart qui decide, a la fin de la session,
            // si les clips ecrits sont conserves definitivement ou jetes.
            // Interrupteur du diagnostic natif (cf. DiagnosticLog.enabled).
            // Pilote par le meme reglage utilisateur que le cote Dart, pour que
            // "diagnostic desactive" veuille dire la MEME chose des deux cotes.
            // Active/desactive la chaine v2 en parallele de la v1. Tant que
            // c'est faux, RIEN de la v2 ne s'execute -- pas de cout, pas de
            // risque.
            "v2SetEnabled" -> {
                v2Actif = call.argument<Boolean>("enabled") ?: false
                if (!v2Actif) v2Chaine = null
                DiagnosticLog.log(TAG, "[v2] chaine parallele " +
                    if (v2Actif) "ACTIVE" else "desactivee")
                result.success(null)
            }
            // Mode CTL/REF -- cf. v2Mode. Appele AVANT v2SetTarget par
            // v2Activer() cote Dart, donc v2Chaine (recreee au prochain bloc
            // audio des que la cible change) voit toujours le bon mode des le
            // premier bloc d'une nouvelle session.
            "v2SetMode" -> {
                v2Mode = call.argument<String>("mode") ?: "CTL"
                DiagnosticLog.log(TAG, "[v2] mode = $v2Mode")
                result.success(null)
            }
            // Texte attendu de la v2. Separe de setAlignmentTarget : la v2
            // travaille sur des MOTS, la v1 sur des tokens deja calcules.
            "v2SetTarget" -> {
                v2Mots = call.argument<List<String>>("mots") ?: emptyList()
                // Index jamais juges (Bismillah) -- cf.
                // ChaineRecitation.nonJugeables. Dart en est l'autorite.
                v2NonJugeables = (call.argument<List<Int>>("nonJugeables")
                    ?: emptyList()).toMutableSet()
                v2Chaine = null // recree au prochain bloc audio, avec la cible
                v1EtatJournalise = false // nouvelle session -> nouvelle ligne [V1]
                DiagnosticLog.log(TAG, "[v2] cible = ${v2Mots.size} mots")
                result.success(null)
            }
            // Agrandit la cible EN COURS DE SESSION (2026-08-05, enchainement
            // de page) SANS recreer la chaine -- v2SetTarget mettrait
            // v2Chaine a null, ce qui perdrait l'ancre et tous les mots deja
            // verrouilles au prochain bloc audio. Cf. le commentaire de
            // ChaineRecitation.etendreTexte pour la mesure qui l'impose.
            // LA VOIX DU RECITATEUR sur une plage de mots, ecrite en WAV et
            // rendue par son chemin (2026-08-06). Cf.
            // ChaineRecitation.voixSurPlage : c'est l'audio EXACT qui a servi a
            // juger ces mots, pas une reconstitution.
            //
            // Fichier ECRASE a chaque appel (`voix_extrait.wav`) : c'est une
            // ecoute immediate pendant la recitation, pas un enregistrement a
            // conserver -- inutile d'accumuler des fichiers dans le cache.
            // FERMER LA SESSION : derniere analyse de la queue d'audio, hors
            // grille (2026-08-06). `ChaineRecitation.terminer()` existait
            // depuis le debut et son commentaire disait deja pourquoi --
            // « sans cet appel, les derniers mots resteraient PROVISOIRES a
            // jamais, la grille cesse d'avancer des que le recitateur se
            // tait » -- mais il n'etait appele QUE par le banc WAV
            // (`v2AnalyserWav`). Sur une vraie session : jamais.
            //
            // MESURE (session v61, 2026-08-06) : le recitateur s'arrete apres
            // le mot 39 `تَنْهَرْ`, gop=0,00, texte exact, 3 observations --
            // et le mot reste `provisoire` donc NON VERT, faute d'une
            // derniere passe. Constat utilisateur : « le dernier mot prononce
            // mais pas juge, pourtant je me suis arrete, normalement il doit
            // etre juge ».
            // Bascule le bloc de FUSION (cf. v2Fusion). Recree la chaine pour
            // que le changement prenne effet au prochain bloc audio.
            "v2SetFusion" -> {
                v2Fusion = call.argument<Boolean>("actif") ?: true
                v2Preuves = call.argument<Int>("preuves") ?: 2
                v2Pas = call.argument<Double>("pas") ?: 4.0
                v2Largeur = call.argument<Double>("largeur") ?: 4.0
                v2MaxBloc = call.argument<Double>("maxbloc") ?: 10.0
                v2MaxFusion = call.argument<Double>("maxfusion") ?: 18.0
                v2Chaine = null
                DiagnosticLog.log(TAG,
                    "[v2] bloc de fusion = $v2Fusion, preuves exigees = $v2Preuves, " +
                    "apercu pas=${v2Pas}s largeur=${v2Largeur}s maxBloc=${v2MaxBloc}s maxFusion=${v2MaxFusion}s")
                result.success(null)
            }
            "v2Terminer" -> {
                val chaine = v2Chaine
                if (chaine == null) {
                    result.success(null)
                } else {
                    val changements = chaine.terminer()
                    DiagnosticLog.log(TAG, "[v2] session fermee : " +
                        "${changements.size} mot(s) finalise(s)")
                    result.success(changements.map { c ->
                        mapOf("i" to c.motIndex, "statut" to nomStatut(c.statut))
                    })
                }
            }
            "v2ExtraitVoix" -> {
                val d = call.argument<Int>("motDebut") ?: -1
                val f = call.argument<Int>("motFin") ?: -1
                val chaine = v2Chaine
                if (chaine == null || d < 0 || f < d) {
                    DiagnosticLog.log(TAG, "[v2] extrait voix REFUSE : " +
                        "chaine=${chaine != null} motDebut=$d motFin=$f")
                    result.success(null)
                } else {
                    val pcm = chaine.voixSurPlage(d, f)
                    if (pcm == null || pcm.isEmpty()) {
                        // Cas legitime : l'audio est sorti de l'anneau (plus de
                        // 300 s), ou aucun de ces mots n'a de position connue.
                        // On le DIT plutot que de rendre un fichier vide.
                        DiagnosticLog.log(TAG, "[v2] extrait voix INDISPONIBLE " +
                            "mots $d..$f (hors anneau ou aucune position)")
                        result.success(null)
                    } else {
                        val p = "${cacheDir?.absolutePath}/voix_extrait.wav"
                        WavWriter.writeMono16k(p, pcm)
                        DiagnosticLog.log(TAG, "[v2] extrait voix mots $d..$f : " +
                            "${"%.2f".format(pcm.size / 16000.0)}s -> $p")
                        result.success(p)
                    }
                }
            }
            "v2ExtendTarget" -> {
                val plus = call.argument<List<String>>("mots") ?: emptyList()
                // Les index arrivent DEJA absolus (Dart les calcule sur la
                // cible complete) : la chaine vivante partage ce meme ensemble
                // mutable, l'extension la met donc a jour sans la recreer.
                v2NonJugeables.addAll(call.argument<List<Int>>("nonJugeables") ?: emptyList())
                v2Mots = v2Mots + plus
                v2Chaine?.etendreTexte(plus)
                DiagnosticLog.log(TAG, "[v2] cible etendue : +${plus.size} mots "
                    + "-> ${v2Mots.size} mots (chaine active=${v2Chaine != null})")
                result.success(null)
            }
            // ── CHAINE v2 (package recitation2) — BANC SUR AUDIO REEL ────────
            // Rejoue un WAV complet dans la chaine v2, bloc de 80 ms par bloc de
            // 80 ms, avec le VRAI modele. C'est le banc 1/2/4 de
            // CONCEPTION_RECITATION_V2.md, et il n'existe qu'ici : reimplementer
            // la politique de fenetrage en Python a produit, deux jours de suite,
            // des predictions confiantes et fausses ("le banc mesurait mon
            // decoupage, pas l'app"). Ici le banc APPELLE le code de l'app.
            //
            // Ne touche a rien du chemin v1 : aucun etat partage, aucune
            // instance commune. Les deux chaines peuvent coexister le temps de
            // la comparaison a WAV identique.
            "v2AnalyserWav" -> scope.launch {
                try {
                    val moteur = engine
                    if (moteur == null) {
                        withContext(Dispatchers.Main) {
                            result.error("NOT_LOADED", "loadModel() n'a pas ete appele", null)
                        }
                        return@launch
                    }
                    val wavPath = call.argument<String>("wavPath")!!
                    val mots = call.argument<List<String>>("mots")!!
                    val fenetreS = call.argument<Double>("fenetreSecondes") ?: 6.0
                    val pasS = call.argument<Double>("pasSecondes") ?: 1.5

                    // Tokenizer LOCAL, jamais l'instance partagee `tokenizer` :
                    // la v2 ne doit ecrire aucun etat lu par la v1, sinon la
                    // comparaison a WAV identique (banc 4) mesurerait les deux
                    // chaines en interaction. Meme construction, meme
                    // dictionnaire precalcule -- seule la duree de vie change.
                    val tk = CtcTokenizer(moteur.vocabPieces, wordTokenLookup)
                    val journal = ArrayList<String>()
                    val chaine = com.corankarim.coran_karim.recitation2.ChaineRecitation(
                        front = com.corankarim.coran_karim.recitation2.FrontOnnx(moteur),
                        tokeniser = { mot -> tk.tokenizeWord(mot) },
                    // Tokenisation SILENCIEUSE : une confusion est un mot
                    // volontairement hors-Coran, quasi jamais dans le
                    // dictionnaire precalcule -- logger chaque repli en ferait
                    // des milliers par sourate.
                    tokeniserConfusion = { mot -> tk.tokenizeVariantQuiet(mot) },
                    confusionsLettres = { mot -> ConfusableVariants.lettresOf(mot) },
                    confusionsHarakat = { mot -> ConfusableVariants.harakatOf(mot) },
                        constructeur = com.corankarim.coran_karim.recitation2
                            .ConstructeurDeFenetres(
                                pauseMinSecondes = fenetreS,
                                maxBlocSecondes = pasS,
                            ),
                        localisateur = com.corankarim.coran_karim.recitation2
                            .Localisateur(moteur.vocabPieces, moteur.blank),
                        aligneur = com.corankarim.coran_karim.recitation2
                            .AligneurForce(moteur.vocabPieces, moteur.blank),
                        journal = { l -> journal.add(l) },
                    )
                    chaine.definirTexte(mots)

                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val bloc = com.corankarim.coran_karim.recitation2.Horloge.ECH_PAR_FRAME
                    val debut = System.currentTimeMillis()
                    var i = 0
                    while (i < pcm.size) {
                        val fin = minOf(i + bloc, pcm.size)
                        chaine.alimenter(pcm.copyOfRange(i, fin))
                        i = fin
                    }
                    chaine.terminer()
                    val duree = System.currentTimeMillis() - debut

                    val statuts = chaine.statuts
                    val motsSortie = mots.indices.map { idx ->
                        val obs = chaine.preuves.observations(idx)
                        mapOf(
                            "i" to idx,
                            "mot" to mots[idx],
                            "statut" to nomStatut(statuts[idx]),
                            "observations" to obs.size,
                            "interieures" to obs.count { it.interieur },
                            "gop" to (obs.lastOrNull { it.interieur }?.gop?.toDouble()),
                            "free" to (obs.lastOrNull { it.interieur }?.free?.toDouble()),
                            "forced" to (obs.lastOrNull { it.interieur }?.forced?.toDouble()),
                            "entendu" to (obs.lastOrNull { it.interieur }?.entendu ?: ""),
                            // TOUTES les observations, pas seulement la derniere.
                            // Sans ca on ne peut pas distinguer « la preuve
                            // n'existe pas » de « la preuve existe et la regle
                            // de decision l'a ratee » -- c'est exactement le
                            // trou qui a rendu la piste "prefixe stable"
                            // invalidable hors device le 2026-07-29.
                            "obs" to obs.map { o ->
                                mapOf(
                                    "f" to o.fenetreId,
                                    "gop" to o.gop.toDouble(),
                                    "free" to o.free.toDouble(),
                                    "int" to o.interieur,
                                    "sc" to o.sansCreneau,
                                    "fr" to o.frames,
                                    "e" to o.entendu,
                                )
                            },
                        )
                    }
                    val payload = mapOf(
                        "dureeAudioMs" to (pcm.size * 1000L / 16000),
                        "dureeCalculMs" to duree,
                        "indexMaxVotant" to chaine.preuves.indexMaxVotant(),
                        "observations" to chaine.preuves.total(),
                        "mots" to motsSortie,
                        "journal" to journal,
                    )
                    DiagnosticLog.log(TAG, "[v2] banc WAV : ${pcm.size / 16000}s audio, " +
                        "${duree}ms calcul, ancre max ${chaine.preuves.indexMaxVotant()}")
                    withContext(Dispatchers.Main) { result.success(payload) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        result.error("V2_WAV_FAILED", e.message, null)
                    }
                }
            }
            "setLogEnabled" -> {
                DiagnosticLog.enabled = call.argument<Boolean>("enabled") ?: true
                result.success(null)
            }
            "setClipCapture" -> {
                val dir = call.argument<String>("dir")
                pendingClipCaptureDir = dir
                buffered?.setClipCapture(dir)
                result.success(null)
            }
            // ── Empreinte vocale (niveau 1, comparaison audio-a-audio) ─────────
            // Voir VoiceFingerprint.kt + memoire voice-personalization-idea.
            "loadFingerprintModel" -> scope.launch {
                try {
                    // Meme principe d'idempotence que "loadModel" ci-dessus :
                    // deux instances de VoiceFingerprintService (coach_screen.dart
                    // en cree une par etat) partagent ce meme moteur natif.
                    if (fingerprint != null) {
                        withContext(Dispatchers.Main) { result.success(true) }
                        return@launch
                    }
                    val modelPath = call.argument<String>("modelPath")!!
                    fingerprint = VoiceFingerprint(modelPath)
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("LOAD_FINGERPRINT_FAILED", e.message, null) }
                }
            }
            "saveFingerprint" -> scope.launch {
                try {
                    val wavPath = call.argument<String>("wavPath")!!
                    val outPath = call.argument<String>("outPath")!!
                    val fp = fingerprint
                    if (fp == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadFingerprintModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val embedding = fp.computeEmbedding(pcm)
                    VoiceFingerprint.save(outPath, embedding)
                    withContext(Dispatchers.Main) { result.success(true) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("SAVE_FINGERPRINT_FAILED", e.message, null) }
                }
            }
            "compareFingerprint" -> scope.launch {
                try {
                    val wavPath = call.argument<String>("wavPath")!!
                    val refPath = call.argument<String>("refPath")!!
                    val fp = fingerprint
                    if (fp == null) {
                        withContext(Dispatchers.Main) { result.error("NOT_LOADED", "loadFingerprintModel() n'a pas ete appele", null) }
                        return@launch
                    }
                    val pcm = WavReader.readMono16kFloat(wavPath)
                    val embedding = fp.computeEmbedding(pcm)
                    val reference = VoiceFingerprint.load(refPath)
                    val similarity = VoiceFingerprint.dtwSimilarity(embedding, reference)
                    withContext(Dispatchers.Main) { result.success(similarity) }
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) { result.error("COMPARE_FINGERPRINT_FAILED", e.message, null) }
                }
            }
            "disposeFingerprint" -> {
                fingerprint?.close()
                fingerprint = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Variantes confusables tokenisees, PARALLELE a la liste [words] (cf.
     *  ConfusableVariants, ForcedAligner.WordResult.rescoreMargin). Tokenisation
     *  SILENCIEUSE (tokenizeVariantQuiet) : les variantes sont volontairement
     *  hors-Coran, presque aucune n'est dans le dictionnaire precalcule. */
    private fun buildVariants(words: List<String>): List<List<Pair<String, IntArray>>> {
        val tok = tokenizer ?: return words.map { emptyList() }
        return words.map { w ->
            ConfusableVariants.variantsOf(w).map { v -> v to tok.tokenizeVariantQuiet(v) }
        }
    }

    /**
     * Alimente la chaine v2 et rend les mots dont le STATUT A CHANGE.
     *
     * Tout est enferme dans un try/catch : la v2 est en observation, elle ne
     * doit sous aucun pretexte faire tomber la chaine qui peint l'ecran.
     */
    private fun alimenterV2(moteur: FastConformerCtc, samples: FloatArray):
        List<Map<String, Any?>>? {
        if (v2Mots.isEmpty()) return null
        return try {
            var chaine = v2Chaine
            if (chaine == null) {
                val tk = CtcTokenizer(moteur.vocabPieces, wordTokenLookup)
                chaine = com.corankarim.coran_karim.recitation2.ChaineRecitation(
                    decideur = com.corankarim.coran_karim.recitation2
                        .Decideur(k = v2Preuves),
                    front = com.corankarim.coran_karim.recitation2.FrontOnnx(moteur),
                    tokeniser = { mot -> tk.tokenizeWord(mot) },
                    // CURSEUR GLISSANT toutes les 3 s -- fenetre de LONGUEUR
                    // FIXE qui avance, pas une fenetre qui grossit depuis la
                    // derniere coupe. Les quatre essais precedents partaient
                    // tous de `derniereCoupe` et relocalisaient jusqu'a 30 s
                    // toutes les 3 s : c'est la que la LCS decrochait.
                    constructeur = com.corankarim.coran_karim.recitation2
                        .ConstructeurDeFenetres(
                            // ── COUPLE (PAS, LARGEUR) PORTE DEPUIS LA BRANCHE
                            // `streaming` (2026-08-02), PAS ENCORE REVALIDE ICI.
                            // Balayage original (banc JVM, modele final-v1 --
                            // PAS le modele tete3) :
                            //   pas/largeur   non verts   obs.   rejugement
                            //     3 / 9        2,03 %     1358     58,5 %   <- avant (valeur ici avant ce commit)
                            //     2 / 6        1,69 %     1501     62,4 %
                            //     2 / 5        1,69 %     1496     62,0 %
                            //     2 / 4        1,69 %     1382     58,9 %   <- retenu
                            // Les observations UTILES sont constantes (295 mots
                            // x ~2 pour figer, cf. Decideur k=2) -- tout le
                            // reste est du recouvrement, et resserrer le pas
                            // supprime du recouvrement inutile sans toucher au
                            // taux. C'est une tuile de la couche SEGMENTATION,
                            // independante du modele acoustique derriere elle --
                            // d'ou le portage. Mais elle n'a ete MESUREE que sur
                            // final-v1 : a revalider ici au banc JVM
                            // (BancFluxBrut -Dapercu=2.0 -DlargeurApercu=4.0
                            // -DpauseMin=0.25) avant de la considerer acquise
                            // pour le modele tete3.
                            apercuSecondes = v2Pas,
                            fenetreApercuSecondes = v2Largeur,
                            // SEUIL DE PAUSE REMESURE (2026-07-31).
                            // WhisperX ne cherche pas un VRAI silence mais la
                            // « region la moins active en parole » -- critere
                            // bien plus permissif que nos 0,40 s.
                            // La falaise documentee (0,30 s -> 3,39 % ;
                            // 0,35 s -> 65,76 %) a ete mesuree dans l'ANCIENNE
                            // architecture, ou toute la justesse dependait de
                            // l'endroit de la coupe. Depuis qu'on coupe aux
                            // frontieres de mots et qu'on juge au centre d'un
                            // curseur, couper mal coute beaucoup moins cher :
                            // une mesure faite avant un changement
                            // d'architecture ne se transporte pas.
                            //
                            // MESURE (2026-07-31, recette scriptee, meme
                            // sourate/modele/recitateur, seul le seuil change) :
                            //   pause 0,40 s -> 2,37 % | attente 3,1 s | >5 s 11
                            //   pause 0,25 s -> 3,73 % | attente 3,2 s | >5 s 14
                            // HYPOTHESE REFUTEE : la falaise tient MALGRE le
                            // changement d'architecture. On perd sur les deux
                            // axes -- le taux depasse le plafond de 3,5 % ET
                            // l'attente empire. Surtout, couper plus souvent ne
                            // rend PAS plus reactif : le seuil de pause n'est
                            // donc plus le facteur limitant. Les 3,1 s sont le
                            // plancher de l'architecture a curseur (1,04 s de
                            // lookahead + cadence 3 s + inference).
                            // NE PAS RETENTER sans changer autre chose.
                            //
                            // ⚠️ HYPOTHESE RENVERSEE LE 2026-08-02 (sur
                            // final-v1, PAS le modele tete3) -- et la clause
                            // « sans changer autre chose » etait la bonne
                            // porte : le MODELE avait change. Mesure sur DEUX
                            // modeles, donc pas du bruit de passe :
                            //                  pause 0,40   pause 0,25   gain
                            //   v4-phrases       5,08 %       4,41 %    -0,67 pt
                            //   final-v1         3,05 %       2,37 %    -0,68 pt
                            // Le sens de l'effet s'INVERSE avec le nouvel
                            // encodeur. Le commentaire ci-dessus reste pour
                            // memoire (ce qui avait ete mesure, et sur quoi) --
                            // PORTE ICI SANS REVALIDATION : le modele tete3
                            // n'est ni final-v1 ni v4-phrases. A confirmer au
                            // banc JVM avant de faire confiance a ce sens-la.
                            maxBlocSecondes = v2MaxBloc,
                            // Plafond PROPRE a la fusion : elle vaut deux
                            // blocs, elle ne peut pas partager celui d'un bloc
                            // seul (cf. ConstructeurDeFenetres).
                            maxFusionSecondes = v2MaxFusion,
                            pauseMinSecondes = 0.25,
                            // BLOC DE FUSION pilotable depuis Dart (2026-08-06).
                            // Hypothese utilisateur : « les apercus 2/4 se
                            // recouvrent de 2 s, ils peuvent s'en sortir seuls,
                            // le second chemin fait trop de controle ».
                            // Banc JVM (Al-Baqara 433 s, 295 mots, meme audio) :
                            //   fusion=true  -> 359 blocs, 1494 obs, 14,24 %
                            //   fusion=false -> 279 blocs,  879 obs, 19,32 %
                            // Soit 41 % d'observations en moins : beaucoup de
                            // mots n'atteignent jamais leur 2e preuve et
                            // restent `provisoire`, donc non verts. Le banc
                            // tournait toutefois en repli glouton de
                            // tokenisation -- d'ou ce drapeau, pour trancher
                            // sur DEVICE en recette de reference.
                            fusionner = v2Fusion),
                    // Tokenisation SILENCIEUSE : une confusion est un mot
                    // volontairement hors-Coran, quasi jamais dans le
                    // dictionnaire precalcule -- logger chaque repli en ferait
                    // des milliers par sourate.
                    tokeniserConfusion = { mot -> tk.tokenizeVariantQuiet(mot) },
                    confusionsLettres = { mot -> ConfusableVariants.lettresOf(mot) },
                    confusionsHarakat = { mot -> ConfusableVariants.harakatOf(mot) },
                    localisateur = com.corankarim.coran_karim.recitation2
                        .Localisateur(moteur.vocabPieces, moteur.blank),
                    aligneur = com.corankarim.coran_karim.recitation2
                        .AligneurForce(moteur.vocabPieces, moteur.blank),
                    journal = { l -> DiagnosticLog.log(TAG, l) },
                    tete3 = tete3,
                    // CLOISONNEMENT CTL/REF -- cf. le commentaire de
                    // [ChaineRecitation.referenceSession]. v2Mode est mis a
                    // jour par v2SetMode, appele avant v2SetTarget (donc avant
                    // que v2Chaine soit recree), cf. le commentaire du handler.
                    referenceSession = v2Mode == "REF",
                    nonJugeables = v2NonJugeables,
                )
                chaine.definirTexte(v2Mots)
                v2Chaine = chaine
            }
            chaine.alimenter(samples).map { c ->
                // Les SCORES accompagnent le statut. Sans eux, le log dit ce que
                // la chaine a DECIDE et jamais POURQUOI -- c'est exactement le
                // manque qui a rendu le bloc de 8 mots omis de Yusuf
                // indiagnosticable le 2026-07-30. On remonte la derniere
                // observation VOTANTE, et a defaut la derniere tout court (un
                // mot `omis` n'en a aucune qui vote : savoir ce qu'il avait
                // quand meme est precisement l'information utile).
                val votantes = chaine.preuves.observationsVotantes(c.motIndex)
                val obs = votantes.lastOrNull()
                    ?: chaine.preuves.observations(c.motIndex).lastOrNull()
                // Cf. le commentaire de "rules" plus bas : on ne regarde le
                // tajwid QUE sur les observations qui ont le droit de voter
                // (mot entierement dans la fenetre, quelque chose d'entendu).
                val reglesVotantes = votantes.flatMap { it.reglesTajwid }.distinct()
                mapOf(
                    "i" to c.motIndex,
                    "statut" to nomStatut(c.statut),
                    "gop" to obs?.gop?.toDouble(),
                    "forced" to obs?.forced?.toDouble(),
                    "free" to obs?.free?.toDouble(),
                    "frames" to (obs?.frames ?: 0),
                    "entendu" to (obs?.entendu ?: ""),
                    "interieur" to (obs?.interieur ?: false),
                    "sansCreneau" to (obs?.sansCreneau ?: false),
                    // SANS CETTE TRACE, la marge est indiscernable d'un
                    // mecanisme qui n'a pas tourne — regle du superviseur, et
                    // lacune reellement payee le 2026-07-31 : impossible de
                    // dire, log en main, lesquels des 18 mots non verts elle
                    // avait touches.
                    "margeL" to obs?.margeLettres?.toDouble(),
                    "margeH" to obs?.margeHarakat?.toDouble(),
                    "nbObs" to chaine.preuves.observations(c.motIndex).size,
                    // TETE 2 : ids de regles (index dans rules.json, meme
                    // ordre que TajwidRule.values cote Dart -- cf.
                    // RegistreDePreuves.Observation.reglesTajwid). Vide sur un
                    // modele sans tete tajwid, rien d'autre ne change.
                    //
                    // UNION SUR LES OBSERVATIONS VOTANTES, et pas la derniere
                    // observation. MESURE QUI L'IMPOSE (commentaire de
                    // recitation_provider.dart, device 2026-07-23) : le MEME
                    // mot (mot=33 يَرَهُۥٓ, MEME audio) sortait `emises=` vide
                    // sur une passe puis `emises=madda_normal` sur la suivante,
                    // selon le decoupage du buffer. Une regle vit sur une
                    // DUREE ; coupee au bord d'une fenetre, elle disparait.
                    // Prendre la derniere observation, c'est donc tirer a pile
                    // ou face -- et accuser le recitateur sur ce tirage.
                    // L'union ne retient qu'une chose : la regle a-t-elle ete
                    // vue AU MOINS UNE FOIS dans de bonnes conditions.
                    "rules" to reglesVotantes,
                    // La regle du projet est « aucun verdict sans preuve ».
                    // Pour AFFIRMER qu'une regle est ABSENTE il faut donc
                    // avoir REGARDE plusieurs fois : deux observations
                    // votantes distinctes, exactement le k=2 que le Decideur
                    // exige deja pour figer une lettre. En dessous, Dart doit
                    // se taire plutot que de conclure.
                    "tajwidFiable" to (votantes.size >= 2),
                )
            }
        } catch (e: Exception) {
            DiagnosticLog.log(TAG, "[v2] echec (la v1 continue) : ${e.message}")
            null
        }
    }

    /** Nom lisible d'un statut v2 pour le payload Dart. `null` = jamais observe
     *  — c'est une reponse legitime, pas une erreur (aucun verdict par defaut). */
    private fun nomStatut(s: com.corankarim.coran_karim.recitation2.Statut?): String = when (s) {
        null, is com.corankarim.coran_karim.recitation2.Statut.Inconnu -> "inconnu"
        is com.corankarim.coran_karim.recitation2.Statut.Provisoire ->
            "provisoire:${s.couleur.name.lowercase()}"
        is com.corankarim.coran_karim.recitation2.Statut.Definitif ->
            "definitif:${s.couleur.name.lowercase()}"
        is com.corankarim.coran_karim.recitation2.Statut.Omis -> "omis"
    }

    /** PCM16 little-endian (format `AudioEncoder.pcm16bits` du package `record`) -> float [-1,1]. */
    private fun pcm16ToFloat(bytes: ByteArray): FloatArray {
        val n = bytes.size / 2
        val out = FloatArray(n)
        for (i in 0 until n) {
            val lo = bytes[i * 2].toInt() and 0xFF
            val hi = bytes[i * 2 + 1].toInt()
            val sample = (hi shl 8) or lo
            out[i] = sample / 32768.0f
        }
        return out
    }
}
