package com.corankarim.coran_karim.recitation2

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import com.corankarim.coran_karim.fastconformer.CtcTokenizer
import com.corankarim.coran_karim.fastconformer.ConfusableVariants
import com.corankarim.coran_karim.fastconformer.MelSpectrogram
import com.corankarim.coran_karim.fastconformer.loadWordTokenLookup
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Audio reel -> mel Kotlin -> ONNX deploye -> ChaineRecitation entiere.
 * Comparaison synchrone par blocs de 80 ms, sans attente murale. Meme flux,
 * constructeur et front pour chaque politique ; les verrouillages se font
 * PENDANT le flux. Arret au premier decrochage comme le demande le produit.
 * Ne reproduit ni le scheduling Android, ni les relances de l'interface Dart.
 */
class BancChaineOnnxJvmTest {
    private fun root(): File {
        var d = File(System.getProperty("user.dir")).absoluteFile
        while (!File(d,"benchmark/exporter_tokenizers_tete3.py").isFile) d = requireNotNull(d.parentFile)
        return d
    }

    private fun pcm(f: File): FloatArray {
        val b = ByteBuffer.wrap(f.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
        require(b.getInt(0) == 0x46464952 && b.getInt(8) == 0x45564157)
        var p = 12
        while (p + 8 <= b.limit()) {
            val id = b.getInt(p); val n = b.getInt(p + 4)
            if (id == 0x20746d66) {
                require(b.getShort(p+8).toInt() == 1 && b.getShort(p+10).toInt() == 1)
                require(b.getInt(p+12) == 16000 && b.getShort(p+22).toInt() == 16)
            }
            if (id == 0x61746164) return FloatArray(n/2) { b.getShort(p+8+2*it)/32768f }
            p += 8+n+(n and 1)
        }
        error("WAV PCM absent")
    }

    private fun statut(s: Statut?): String = when (s) {
        is Statut.Definitif -> "definitif:${s.couleur.name}"
        is Statut.Provisoire -> "provisoire:${s.couleur.name}"
        Statut.Omis -> "omis"
        Statut.Deplace -> "deplace"
        else -> "inconnu"
    }

    @Test fun `rejouer le flux cible et les temoins avec le vrai ONNX`() {
        assumeTrue("Banc audio explicite : -DasrBanc=true",System.getProperty("asrBanc") == "true")
        val root = root()
        val pack = File(root,"app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal")
        val assets = File(root,"app/android/app/src/main/assets/tokenizers_tete3")
        val a = JSONArray(File(pack,"vocab.json").readText())
        val pieces = (0 until a.length()).map(a::getString)
        val tk = CtcTokenizer(pieces,loadWordTokenLookup(File(pack,"word_tokens.json").path))
        val sp = TokeniseurBpeTete3.charger(File(assets,"hafs.json").readText(),
            File(assets,"hafs.normalizer.bin").readBytes(),pieces)
        // Tete 3 de decision, choisie par -DteteT3 (chemin relatif au depot).
        // Defaut : la candidate du 15/09, celle qui a servi a toutes les
        // mesures precedentes -- changer ce defaut invaliderait la comparaison.
        val cheminTete = System.getProperty("teteT3")
            ?: "benchmark/tetes_candidates/hafs_particules_20260915/tete3_hafs_particules.json"
        val tete = requireNotNull(Tete3.charger(File(root, cheminTete).readText()))
        println("TETE 3 DE DECISION : $cheminTete  seuil2pct=${tete.seuil2Pct ?: "aucun"}")
        val env = OrtEnvironment.getEnvironment()
        val options = OrtSession.SessionOptions().also { it.setIntraOpNumThreads(4) }
        val sortie = JSONArray()
        // 16/09 : banc des ERREURS REELLES (substitutions de flexion et de
        // particule, aucun mot tronque). Les cas T8xx restent disponibles en
        // changeant cette liste -- ils mesuraient surtout des fautes que nul
        // recitateur ne commet, cf. campagne_erreurs_reelles_20260916.py.
        // Corpus choisi par -DcorpusBanc : "paliers" (0/20/40 % du 15/09) ou
        // "reelles" (substitutions de flexion et de particule du 16/09).
        val dossiers = if (System.getProperty("corpusBanc") == "paliers")
            listOf("campagne_paliers_20260915" to setOf("T801","T802","T803","T804","T807","T808"))
        else listOf("campagne_erreurs_reelles_20260916" to
            setOf("R901","R902","R903","R904","R905","R906","R907","R908","R909","R910"))
        env.createSession(File(pack,"model.onnx").path,options).use { session ->
            // Cache borne aux derniers appels, pur et commun aux politiques.
            val cache = object : LinkedHashMap<String,SortiesFront>(16,.75f,true) {
                override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String,SortiesFront>?) = size > 8
            }
            var inferences = 0
            val front = object : FrontAcoustique {
                override val pieces = pieces
                override val blank = pieces.size
                override fun logprobs(echantillons: FloatArray) = sorties(echantillons).logprobs
                override fun sorties(echantillons: FloatArray): SortiesFront {
                    val bytes = ByteBuffer.allocate(echantillons.size*4).order(ByteOrder.LITTLE_ENDIAN)
                    bytes.asFloatBuffer().put(echantillons)
                    val cle = MessageDigest.getInstance("SHA-256").digest(bytes.array())
                        .joinToString("") { "%02x".format(it) }
                    cache[cle]?.let { return it }
                    val mel = MelSpectrogram.compute(echantillons)
                    val t = mel[0].size
                    OnnxTensor.createTensor(env,FloatBuffer.wrap(FloatArray(80*t) { mel[it/t][it%t] }),
                        longArrayOf(1,80,t.toLong())).use { x ->
                        OnnxTensor.createTensor(env,LongBuffer.wrap(longArrayOf(t.toLong())),longArrayOf(1)).use { len ->
                            session.run(mapOf("audio_signal" to x,"length" to len)).use { r ->
                                @Suppress("UNCHECKED_CAST")
                                val lp = (r.get("logprobs").get().value as Array<Array<FloatArray>>)[0]
                                @Suppress("UNCHECKED_CAST")
                                val e = (r.get("encoder_state").get().value as Array<Array<FloatArray>>)[0]
                                val etat = Array(lp.size) { f -> FloatArray(512) { k -> e[k][f] } }
                                inferences++
                                return SortiesFront(lp,null,etat).also { cache[cle] = it }
                            }
                        }
                    }
                }
            }
            for ((dossier, ids) in dossiers) {
                val cases = JSONObject(File(root,"benchmark/$dossier/manifest.json").readText()).getJSONArray("cases")
                for (i in 0 until cases.length()) {
                    val cas = cases.getJSONObject(i)
                    val id = cas.getString("case_id")
                    if (id !in ids) continue
                    val mots = cas.getJSONArray("expected_words").let { ar -> (0 until ar.length()).map(ar::getString) }
                    val audio = pcm(File(cas.getString("wav")))
                    val outDir = File(root,"benchmark/replay_chaine_jvm_20260915").also { it.mkdirs() }
                    val noms = listOf("historique","vote","vote_t3_legacy","vote_t3_bpe")
                    val logs = noms.associateWith { File(outDir,"${id}_$it.log").bufferedWriter() }
                    try {
                        val chaines = noms.associateWith { nom ->
                            ChaineRecitation(front=front, tokeniser=tk::tokenizeWord,
                                tokeniserConfusion=tk::tokenizeVariantQuiet,
                                confusionsLettres=ConfusableVariants::lettresOf,
                                confusionsHarakat=ConfusableVariants::harakatOf,
                                constructeur=ConstructeurDeFenetres(apercuSecondes=4.0,fenetreApercuSecondes=4.0,
                                    maxBlocSecondes=10.0,maxFusionSecondes=18.0,pauseMinSecondes=.25,fusionner=true),
                                decideur=Decideur(votePondere=nom!="historique",utiliserTete3=nom.startsWith("vote_t3")),
                                tete3Jugement=if(nom.startsWith("vote_t3")) tete else null,
                                tokeniserTete3=if(nom=="vote_t3_bpe") sp::tokeniser else null,
                                // Balayage du rattrapage de debut de mot (cf.
                                // AligneurForce.framesAvanceeDebut). 0 par
                                // defaut = chaine inchangee ; -DavanceeDebut=N
                                // pour mesurer, sans toucher la production.
                                aligneur=AligneurForce(front.pieces,front.blank,
                                    // Contexte exige a gauche : -DmargeGauche=N frames
                                    // (1 frame = 80 ms). Defaut 2 = valeur de
                                    // production, a balayer avant de la changer.
                                    margeGaucheFrames=
                                        (System.getProperty("margeGauche") ?: "2").toInt(),
                                    framesAvanceeDebut=
                                        (System.getProperty("avanceeDebut") ?: "0").toInt()),
                                observerVoteFenetres=true,
                                journal={ l -> logs.getValue(nom).apply { write(l); newLine() } },
                            ).also { it.definirTexte(mots) }
                        }
                        val arrets = HashMap<String,Int>()
                        for (p in audio.indices step Horloge.ECH_PAR_FRAME) {
                            val fin = minOf(p+Horloge.ECH_PAR_FRAME,audio.size)
                            val bloc = audio.copyOfRange(p,fin)
                            for ((nom,c) in chaines) if (nom !in arrets) {
                                c.alimenter(bloc)
                                if (c.decrochage) arrets[nom]=fin
                            }
                        }
                        for ((nom,c) in chaines) {
                            c.terminer()
                            val result = JSONObject().put("cas",id).put("dossier",dossier).put("configuration",nom)
                                .put("ech_total",audio.size).put("arret_decrochage",arrets[nom] ?: JSONObject.NULL)
                                .put("observations",c.preuves.total())
                                .put("statuts",JSONObject(mots.indices.associate { it.toString() to statut(c.statuts[it]) }))
                            sortie.put(result)
                            println("$id $nom observations=${c.preuves.total()} juges=${c.statuts.size} arret=${arrets[nom]}")
                        }
                        File(outDir,"resultats.json").writeText(sortie.toString(2))
                    } finally { logs.values.forEach { it.close() } }
                }
            }
            println("Inferences ONNX natives : $inferences")
        }
        options.close()
        // 4 politiques par cas : la garde suit desormais la liste `dossiers`
        // au lieu d'etre figee. Elle valait 20 quand le banc portait 5 cas, et
        // a fait echouer l'extension a 8 alors que les 40 resultats etaient
        // corrects et deja ecrits -- une garde qui compte doit compter ce qui
        // est demande, pas ce qui l'etait a l'ecriture.
        assertEquals(4 * dossiers.sumOf { it.second.size },sortie.length())
    }
}
