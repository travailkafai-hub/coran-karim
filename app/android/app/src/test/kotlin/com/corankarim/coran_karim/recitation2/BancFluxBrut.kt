package com.corankarim.coran_karim.recitation2

import java.io.DataInputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * BANC SUR FLUX BRUT REEL, SANS TELEPHONE.
 *
 * POURQUOI (2026-07-30). Chaque iteration passait par build APK + install +
 * intent + lecture du log : 5 minutes, et il faut les telephones branches.
 * Ici : ~20 secondes, sur le poste, sur le MEME flux brut.
 *
 * CE QUI GARANTIT QUE LE BANC MESURE BIEN L'APP. Les couches B, D, E, F, G
 * n'ont aucune dependance Android ni ONNX : ce sont EXACTEMENT les classes qui
 * tournent sur le telephone, appelees ici sans une ligne de re-implementation.
 * Seule la couche C (mel + ONNX) est fournie de l'exterieur -- et C n'est pas
 * une politique, c'est le modele. C'est la seule facon d'eviter le piege paye
 * deux jours de suite : « le banc mesurait mon decoupage, pas l'app ».
 *
 * DEROULEMENT EN TROIS TEMPS (le seul moyen d'avoir ONNX sans le lier au JVM) :
 *
 *   1) ./gradlew :app:testDebugUnitTest --tests "*BancFluxBrut*" -Dphase=blocs
 *      -> la couche B lit le WAV et ecrit la liste des blocs qu'elle decide.
 *
 *   2) python3 benchmark/logprobs_blocs.py
 *      -> le modele calcule les logprobs de CES blocs-la, et rien d'autre.
 *
 *   3) ... -Dphase=juger
 *      -> les couches D/E/F/G rendent le verdict et le taux.
 *
 * Les tests se desactivent d'eux-memes (assume) si les fichiers d'entree sont
 * absents : ce banc ne doit jamais faire echouer la suite de tests ordinaire.
 */
class BancFluxBrut {

    private val racine = File("/tmp/claude-1000")
    private val wav = File(racine, "brut.wav")
    private val cible = File(racine, "cible_v2.json")
    private val blocsFichier = File(racine, "blocs.txt")
    private val dossierLogprobs = File(racine, "logprobs")

    private fun lireWav(f: File): FloatArray {
        val octets = f.readBytes()
        // En-tete WAV canonique de 44 octets (celui qu'ecrit WavWriter).
        val bb = ByteBuffer.wrap(octets, 44, octets.size - 44).order(ByteOrder.LITTLE_ENDIAN)
        val n = (octets.size - 44) / 2
        return FloatArray(n) { bb.short / 32768f }
    }

    private fun motsAttendus(): List<String> {
        // Le JSON est un tableau plat de chaines : un parseur minimal suffit et
        // evite d'ajouter une dependance au sourceSet de test.
        val t = cible.readText(Charsets.UTF_8).trim().removePrefix("[").removeSuffix("]")
        return Regex("\"((?:[^\"\\\\]|\\\\.)*)\"").findAll(t)
            .map { it.groupValues[1] }.toList()
    }

    @Test
    fun blocs() {
        assumeTrue("flux brut absent", wav.exists())
        val pcm = lireWav(wav)
        // Parametres balayables depuis la ligne de commande : le banc doit
        // pouvoir explorer sans recompiler, sinon on ne balaie jamais.
        val pause = System.getProperty("pauseMin")?.toDouble() ?: 0.5
        val maxBloc = System.getProperty("maxBloc")?.toDouble() ?: 18.0
        val fusion = System.getProperty("fusion")?.toBoolean() ?: true
        val rms = System.getProperty("seuilRms")?.toFloat() ?: 0.02f
        println("[banc] pauseMin=$pause maxBloc=$maxBloc fusion=$fusion rms=$rms")
        val constructeur = ConstructeurDeFenetres(
            pauseMinSecondes = pause, seuilRmsSilence = rms,
            maxBlocSecondes = maxBloc, fusionner = fusion,
        )
        val sortie = StringBuilder()
        var n = 0
        val bloc = Horloge.ECH_PAR_FRAME
        var i = 0
        val toutes = ArrayList<Fenetre>()
        while (i < pcm.size) {
            val fin = minOf(i + bloc, pcm.size)
            toutes.addAll(constructeur.alimenter(pcm.copyOfRange(i, fin)))
            i = fin
        }
        toutes.addAll(constructeur.terminer())
        for (f in toutes) {
            sortie.append("${f.id};${f.travailDebut};${f.travailFin};${f.fusion}\n")
            n++
        }
        blocsFichier.writeText(sortie.toString())
        println("[banc] ${pcm.size / 16000.0} s -> $n blocs -> ${blocsFichier.path}")
        println("[banc] durees : " + toutes.joinToString(" ") {
            String.format("%.1f", it.dureeSecondes)
        })
    }

    @Test
    fun juger() {
        assumeTrue("logprobs absents (lancer la phase blocs puis le script python)",
            dossierLogprobs.isDirectory && blocsFichier.exists() && cible.exists())

        val mots = motsAttendus()
        val pieces = File(racine, "pieces.txt").readLines()
        val blank = pieces.size

        val registre = RegistreDePreuves()
        val decideur = Decideur()
        val localisateur = Localisateur(pieces, blank)
        val aligneur = AligneurForce(pieces, blank)
        val tokens = HashMap<String, IntArray>()
        for (l in File(racine, "word_tokens.txt").readLines()) {
            val p = l.split("\t")
            if (p.size == 2) tokens[p[0]] = p[1].split(",").filter { it.isNotBlank() }
                .map { it.toInt() }.toIntArray()
        }
        // Repli glouton, comme CtcTokenizer cote app : le dictionnaire
        // precalcule ne contient QUE les mots canoniques du Coran, donc aucune
        // ecriture equivalente. Sans ce repli, les variantes etaient toutes
        // filtrees et la mesure ne bougeait pas d'un centieme -- ce qui se lit
        // a tort comme « la piste ne sert a rien ».
        val parPiece = pieces.withIndex().associate { (i, p) -> p to i }
        val maxPiece = pieces.maxOf { it.length }
        fun greedy(mot: String): IntArray {
            val cible = "\u2581" + mot
            val ids = ArrayList<Int>(cible.length)
            var pos = 0
            while (pos < cible.length) {
                var len = minOf(maxPiece, cible.length - pos)
                var trouve = false
                while (len >= 1) {
                    val id = parPiece[cible.substring(pos, pos + len)]
                    if (id != null) { ids.add(id); pos += len; trouve = true; break }
                    len--
                }
                if (!trouve) pos++
            }
            return ids.toIntArray()
        }
        val tokensAttendus = mots.map { tokens[it] ?: greedy(it) }
        val variantes = mots.map { m ->
            Orthographe.variantes(m).drop(1)
                .map { v -> tokens[v] ?: greedy(v) }.filter { it.isNotEmpty() }
        }

        var dernierDefinitif = -1
        var statuts: Map<Int, Statut> = emptyMap()
        var fenetresVues = 0

        for (ligne in blocsFichier.readLines()) {
            if (ligne.isBlank()) continue
            val p = ligne.split(";")
            val id = p[0].toLong()
            val debut = p[1].toLong()
            val f = File(dossierLogprobs, "$id.bin")
            if (!f.exists()) continue
            val lp = lireLogprobs(f)
            fenetresVues++

            val bande = localisateur.localiser(lp, mots, dernierDefinitif) ?: continue
            val res = aligneur.aligner(
                lp, tokensAttendus.subList(bande.i0, bande.i1 + 1), bande.i0,
                bordGaucheEstDebutDeSession = debut == 0L,
                attestes = bande.attestes,
                variantesParMot = variantes.subList(bande.i0, bande.i1 + 1),
            ) ?: continue
            for (m in res.mots) {
                registre.ajouter(
                    RegistreDePreuves.Observation(
                        fenetreId = id, motIndex = m.index, gop = m.gop,
                        forced = m.forced, free = m.free, entendu = m.entendu,
                        frames = m.frames, interieur = m.interieur && !m.sansCreneau,
                        couvert = m.couvert, sansCreneau = m.sansCreneau,
                        atteste = bande.attestes.containsKey(m.index),
                        fenetrePleine = true, debutAbs = -1, finAbs = -1,
                    )
                )
            }
            statuts = decideur.statuts(registre, mots.size)
            statuts.forEach { (i, s) ->
                if (s is Statut.Definitif && i > dernierDefinitif) dernierDefinitif = i
            }
        }

        val max = registre.indexMaxVotant()
        val n = max + 1
        var nonVerts = 0
        var borneHaute = 0
        val detail = StringBuilder()
        for (i in 0..max) {
            val s = statuts[i]
            val vert = s is Statut.Definitif && s.couleur == Couleur.VERT ||
                s is Statut.Provisoire && s.couleur == Couleur.VERT
            if (!vert) {
                nonVerts++
                val o = registre.observations(i)
                detail.append(String.format("%4d %-16s %s\n", i, mots.getOrNull(i), s))
                for (x in o.take(4)) {
                    detail.append(String.format(
                        "        f%-4d %s gop=%7.2f free=%6.2f fr=%3d \"%s\"\n",
                        x.fenetreId, if (x.interieur) "INT " else "bord",
                        x.gop, x.free, x.frames, x.entendu))
                }
            }
            if (registre.observationsVotantes(i).none { it.gop >= -0.45f }) borneHaute++
        }
        println("[banc] $fenetresVues blocs, ${registre.total()} observations, ancre max $max")
        println("[banc] NON VERTS      : $nonVerts/$n = " +
            String.format("%.2f", 100.0 * nonVerts / n) + " %")
        println("[banc] BORNE HAUTE    : $borneHaute/$n = " +
            String.format("%.2f", 100.0 * borneHaute / n) + " %")
        println(detail.toString().take(6000))
    }

    private fun lireLogprobs(f: File): Array<FloatArray> {
        DataInputStream(f.inputStream().buffered()).use { s ->
            val entete = ByteArray(8)
            s.readFully(entete)
            val bb = ByteBuffer.wrap(entete).order(ByteOrder.LITTLE_ENDIAN)
            val t = bb.int
            val v = bb.int
            val brut = ByteArray(t * v * 4)
            s.readFully(brut)
            val fb = ByteBuffer.wrap(brut).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            return Array(t) { FloatArray(v) { fb.get() } }
        }
    }
}
