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
        val rms = System.getProperty("seuilRms")?.toFloat() ?: 0.03f
        val adaptatif = System.getProperty("adaptatif")?.toBoolean() ?: true
        // Couple (pas, largeur) du curseur glissant -- porte depuis la branche
        // `streaming` (2026-08-02) pour pouvoir balayer sans recompiler.
        val apercu = System.getProperty("apercu")?.toDouble() ?: 3.0
        val largeur = System.getProperty("largeurApercu")?.toDouble() ?: 9.0
        // SECONDE GRILLE (idee utilisateur : periodes premieres entre elles).
        val apercu2 = System.getProperty("apercu2")?.toDouble() ?: 0.0
        val largeur2 = System.getProperty("largeurApercu2")?.toDouble() ?: 0.0
        val maxFusion = System.getProperty("maxFusion")?.toDouble() ?: 30.0
        println("[banc] pauseMin=$pause maxBloc=$maxBloc fusion=$fusion rms=$rms " +
            "adaptatif=$adaptatif apercu=$apercu largeurApercu=$largeur")
        val constructeur = ConstructeurDeFenetres(
            pauseMinSecondes = pause, seuilRmsSilence = rms,
            seuilAdaptatif = adaptatif,
            maxBlocSecondes = maxBloc, fusionner = fusion,
            apercuSecondes = apercu, fenetreApercuSecondes = largeur,
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

    /**
     * Paires de lettres CONFUSABLES : elles changent le son, donc une
     * substitution est une VRAIE faute de prononciation. Ce sont celles que le
     * projet a mesurees separables par rescoring (80,8 % sur 854 clips).
     */
    private val confusables = listOf(
        // Famille jim/ha/kha : meme squelette graphique, sons proches. C'est LA
        // paire signalee par l'utilisateur apres son propre test (« mon cas
        // c'etait remplacer jim par ha ») -- elle manquait a cette liste, donc
        // le banc ne testait pas le cas qu'il avait sous les yeux.
        'ج' to 'ح', 'ح' to 'خ', 'ج' to 'خ',
        'ص' to 'س', 'ط' to 'ت', 'ض' to 'د', 'ذ' to 'ز',
        'ح' to 'ه', 'ق' to 'ك', 'ع' to 'ء',
    )

    /**
     * Remplace une lettre du mot ATTENDU par sa confusable.
     *
     * On altere la CIBLE, pas l'audio : l'app doit donc constater que ce qui
     * est dit n'est pas ce qui est attendu -- exactement ce qu'elle vit quand
     * le recitateur se trompe. Le protocole du projet (« reciter en
     * substituant 1 mot sur 5 ») teste la meme chose avec un humain ; ici on
     * l'obtient sans nouvelle session, donc sur le MEME audio que la mesure de
     * faux positifs.
     */
    /**
     * Fausse une HARAKAT (fatha/damma/kasra) -- le cas signale par
     * l'utilisateur en se servant de l'app : « j'ai fait des fautes deliberees,
     * il les colorie [vert] alors que le texte entendu en bas montre bien que
     * j'ai mal dit le mot ».
     *
     * C'est le cas le plus dur : le projet a mesure que le gop y est faible
     * (-0,16 a -0,90 sur fautes deliberees) et que le rescoring de variantes y
     * est au niveau du hasard (49,6 % sur 954 clips). Un banc qui ne teste que
     * les substitutions de LETTRES ne dit donc rien de ce cas.
     */
    private fun fausserHarakat(mot: String): String? {
        val paires = listOf('َ' to 'ُ', 'ُ' to 'ِ', 'ِ' to 'َ')
        for ((a, b) in paires) {
            val i = mot.indexOf(a)
            if (i >= 0) return mot.substring(0, i) + b + mot.substring(i + 1)
        }
        return null
    }

    private fun fausser(mot: String): String? {
        for ((a, b) in confusables) {
            val i = mot.indexOf(a)
            if (i >= 0) return mot.substring(0, i) + b + mot.substring(i + 1)
            val j = mot.indexOf(b)
            if (j >= 0) return mot.substring(0, j) + a + mot.substring(j + 1)
        }
        return null
    }

    @Test
    fun juger() {
        assumeTrue("logprobs absents (lancer la phase blocs puis le script python)",
            dossierLogprobs.isDirectory && blocsFichier.exists() && cible.exists())

        val motsVrais = motsAttendus()
        // -DfautesTous=N : on FAUSSE un mot attendu sur N (substitution de
        // lettre confusable). Mesure alors la DETECTION, pas les faux positifs.
        val fautesTous = System.getProperty("fautesTous")?.toInt() ?: 0
        // -DtypeFaute=harakat : substitution de VOYELLE au lieu de lettre.
        val harakat = System.getProperty("typeFaute") == "harakat"
        val fautes = HashSet<Int>()
        val mots = if (fautesTous <= 0) motsVrais else motsVrais.mapIndexed { i, m ->
            if (i > 0 && i % fautesTous == 0) {
                val f = if (harakat) fausserHarakat(m) else fausser(m)
                if (f != null) { fautes.add(i); f } else m
            } else m
        }
        if (fautes.isNotEmpty()) println("[banc] type de faute : " +
            if (harakat) "HARAKAT" else "lettre confusable")
        if (fautes.isNotEmpty()) println("[banc] ${fautes.size} mots FAUSSES sur ${mots.size}")
        val pieces = File(racine, "pieces.txt").readLines()
        val blank = pieces.size

        val registre = RegistreDePreuves()
        // -Dk=1 : UNE seule observation suffit a figer (au lieu de deux
        // fenetres concordantes). Ce n'est PAS un reglage a l'oeil, c'est
        // l'autre moitie de l'hypothese « les apercus 2/4 se suffisent » : sans
        // le bloc de FUSION, un mot ne recoit souvent qu'un seul regard, et
        // exiger deux preuves le laisse provisoire donc NON VERT. Couper la
        // fusion en gardant k=2 mesure donc un epouvantail, pas l'hypothese.
        val k = System.getProperty("k")?.toInt() ?: 2
        val decideur = Decideur(k = k)
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

            val bande = localisateur.localiser(
                lp, mots, dernierDefinitif,
                framesMinParMot = { i -> tokensAttendus.getOrNull(i)?.size ?: 0 },
            ) ?: continue
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
                        atteste = bande.attestesExacts.contains(m.index),
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
        if (fautes.isNotEmpty()) {
            // DETECTION : parmi les mots FAUSSES, combien sont signales ?
            // COLLATERAL : parmi les mots INTACTS, combien deviennent non verts ?
            // Les deux chiffres se lisent ENSEMBLE : une detection de 100 %
            // obtenue en signalant tout le monde ne vaut rien.
            var detectees = 0
            var fautesVues = 0
            var collateral = 0
            var intactsVus = 0
            for (i in 0..max) {
                val st = statuts[i]
                val vert = (st is Statut.Definitif && st.couleur == Couleur.VERT) ||
                    (st is Statut.Provisoire && st.couleur == Couleur.VERT)
                if (fautes.contains(i)) {
                    fautesVues++
                    if (!vert) detectees++
                    else println(String.format("  RATEE  %4d %-18s -> %s", i, mots[i], st))
                } else {
                    intactsVus++
                    if (!vert) collateral++
                }
            }
            println("[banc] DETECTION  : $detectees/$fautesVues fautes signalees = " +
                String.format("%.1f", 100.0 * detectees / maxOf(1, fautesVues)) + " %")
            println("[banc] COLLATERAL : $collateral/$intactsVus mots intacts non verts = " +
                String.format("%.2f", 100.0 * collateral / maxOf(1, intactsVus)) + " %")
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

    /**
     * CALIBRAGE — derive le rapport de pause depuis la recitation de reference,
     * exactement comme 0,344 a ete derive pour le seuil RMS.
     *
     * Ce banc ne verifie pas un comportement : il MESURE une constante, et il
     * montre la distribution qui la fonde. Si cette distribution n'est pas
     * separee en deux populations, aucun rapport ne sauvera le reglage -- et
     * c'est une conclusion aussi utile que la constante elle-meme.
     */
    @Test
    fun calibrage() {
        assumeTrue("flux brut absent", wav.exists())
        val pcm = lireWav(wav)
        val c = Calibrage()
        c.alimenter(pcm)
        val r = c.resultat()
        println("[calib] ${"%.1f".format(r.secondes)} s, ${r.blocs} blocs, fiable=${r.fiable}")
        if (!r.fiable) { println("[calib] ${r.pourquoi}"); return }
        println("[calib] niveau de parole (p75 rms) = ${"%.4f".format(r.niveauParole)}" +
                "  -> seuil silence ${"%.4f".format(r.seuilRms)}" +
                (if (r.seuilRmsBorne) "  (BORNE ATTEINTE)" else ""))
        println("[calib] ${r.silences.size} silences ; percentiles (s) :")
        for (p in intArrayOf(10, 25, 50, 75, 90, 95)) {
            println("           p$p = ${"%.3f".format(r.percentile(p))}")
        }
        println("[calib] separation p90/p25 = ${"%.2f".format(r.separation)}" +
                (if (r.separation < 2.0) "   <- FAIBLE : aucun seuil ne separe proprement"
                 else "   <- deux populations distinctes"))
        for (cible in doubleArrayOf(0.35, 0.40, 0.45)) {
            println("[calib] pour obtenir pause=$cible il faudrait rapport (sur p90) = " +
                    "${"%.3f".format(cible / r.percentile(90))}")
        }
        println("[calib] avec le rapport actuel (${Calibrage.RAPPORT_PAUSE}) -> pause " +
                "${"%.3f".format(r.pause)}" + (if (r.pauseBornee) "  (BORNE ATTEINTE)" else ""))
    }

}
