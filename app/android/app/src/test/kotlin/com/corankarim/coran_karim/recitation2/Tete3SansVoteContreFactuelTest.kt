package com.corankarim.coran_karim.recitation2

import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * LA QUATRIEME CASE : la tete 3 SANS le vote, mesuree hors device.
 *
 * ── POURQUOI ────────────────────────────────────────────────────────────────
 *
 * La campagne du 15/09 (`benchmark/CAMPAGNE_PALIERS_20260915.md`) a mesure
 * trois configurations : ni l'un ni l'autre, vote seul, vote + tete 3. La
 * quatrieme -- tete 3 seule -- etait IMPOSSIBLE a produire : `utiliserTete3`
 * exige `votePondere`, parce que [JugementTete3.evaluer] lit le regroupement
 * d'occurrence du vote. Or la mesure a montre que le vote coute TROIS
 * accusations fausses par detection gagnee ; vouloir la tete sans lui devient
 * donc une question legitime, et elle n'avait aucune reponse.
 *
 * ── POURQUOI SUR BANC, ET PAS SUR TELEPHONE ─────────────────────────────────
 *
 * Regle du projet : toucher a la chaine sans mesure prealable hors device a
 * deja coute une journee entiere, quatre correctifs « evidents » tous rejetes
 * par la mesure. Ici les observations REELLES existent deja -- 3 485 archivees
 * par le journal `[vote-observation]`, dont 1 946 portant un logit de tete 3.
 * On rejoue donc les MEMES observations avec deux regles, en quelques
 * secondes, au lieu de 45 minutes de telephone par variante.
 *
 * ── CE QUE CE BANC NE PEUT PAS DIRE ─────────────────────────────────────────
 *
 * Les observations ont ete produites AVEC le vote actif. Elles ne dependent pas
 * de la regle de decision (elles viennent de l'alignement et du decodage), mais
 * le DECROCHAGE, lui, en depend : une chaine qui decroche ailleurs ne produit
 * pas les memes fenetres. Ce banc compare donc deux JUGEMENTS sur un meme flux
 * d'observations, pas deux sessions.
 * Le secours anti-`Omis` n'est pas soumis a la tete 3 (il vit hors de la boucle
 * ou l'avis est calcule) -- il ne concerne que 3 a 7 mots sur 295.
 */
class Tete3SansVoteContreFactuelTest {

    private fun racine(): File {
        var d = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (!File(d, "benchmark/campagne_paliers_20260915").exists())
            d = requireNotNull(d.parentFile)
        return d
    }

    private data class Score(val detectees: Int, val ratees: Int,
                             val fauxSignalements: Int, val correctsOk: Int) {
        operator fun plus(o: Score) = Score(detectees + o.detectees, ratees + o.ratees,
            fauxSignalements + o.fauxSignalements, correctsOk + o.correctsOk)
        val rappel get() = if (detectees + ratees == 0) null
            else 100.0 * detectees / (detectees + ratees)
        val faux get() = if (fauxSignalements + correctsOk == 0) null
            else 100.0 * fauxSignalements / (fauxSignalements + correctsOk)
    }

    private fun negatif(s: Statut?) = when (s) {
        is Statut.Definitif -> s.couleur != Couleur.VERT
        is Statut.Provisoire -> s.couleur != Couleur.VERT
        Statut.Omis, Statut.Deplace -> true
        else -> false
    }

    private fun compter(statuts: Map<Int, Statut>, fautes: Set<Int>, nbMots: Int): Score {
        var a = 0; var b = 0; var c = 0; var d = 0
        for (i in 0 until nbMots) {
            val s = statuts[i] ?: continue
            if (i in fautes) { if (negatif(s)) a++ else b++ } else { if (negatif(s)) c++ else d++ }
        }
        return Score(a, b, c, d)
    }

    @Test
    fun `la tete 3 sans le vote, sur les observations reelles de la campagne`() {
        val root = racine()
        val manifeste = JSONObject(
            File(root, "benchmark/campagne_paliers_20260915/manifest.json")
                .readText(Charsets.UTF_8))
        val cas = manifeste.getJSONArray("cases")
        val logs = File(root, "benchmark/campagne_paliers_20260915/logs")

        var sansT3 = Score(0, 0, 0, 0)
        var avecT3 = Score(0, 0, 0, 0)
        var observations = 0
        var avecLogit = 0
        val lignes = StringBuilder()

        for (n in 0 until cas.length()) {
            val c = cas.getJSONObject(n)
            val id = c.getString("case_id")
            val fichier = logs.listFiles()?.firstOrNull {
                it.name.startsWith("$id-") && it.name.endsWith(".log") &&
                    !it.name.endsWith(".before_close.log")
            } ?: continue
            val attendus = c.getJSONArray("expected_words").let { a ->
                (0 until a.length()).map { a.getString(it) }
            }
            val mots = attendus.size
            val fautes = HashSet<Int>()
            val ops = c.getJSONArray("operations")
            for (k in 0 until ops.length()) {
                val a = ops.getJSONObject(k).getJSONArray("affected_word_indices")
                for (x in 0 until a.length()) fautes.add(a.getInt(x))
            }

            val registre = RegistreDePreuves()
            fichier.forEachLine(Charsets.UTF_8) { l ->
                if ("[vote-observation] " in l) {
                    val j = JSONObject(l.substringAfter("[vote-observation] "))
                    fun f(k: String) = j.optDouble(k, Double.NaN).toFloat()
                    fun opt(k: String) = f(k).takeIf { it.isFinite() }
                    val logit = opt("t3_jugement_logit")
                    observations++
                    if (logit != null) avecLogit++
                    registre.ajouter(RegistreDePreuves.Observation(
                        fenetreId = j.getLong("fenetre"), motIndex = j.getInt("mot"),
                        gop = f("gop"), forced = f("forced"), free = f("free"),
                        entendu = j.getString("entendu"), frames = j.getInt("frames"),
                        interieur = j.getBoolean("interieur"), couvert = j.getBoolean("couvert"),
                        sansCreneau = j.getBoolean("sans_creneau"),
                        atteste = j.getBoolean("atteste"),
                        margeLettres = opt("marge_lettres"), margeHarakat = opt("marge_harakat"),
                        fenetrePleine = true,
                        debutAbs = j.getLong("debut"), finAbs = j.getLong("fin"),
                        mesureTete3Jugement = logit?.let { Tete3.Mesure(it, null) }))
                }
            }
            if (registre.motsObserves.isEmpty()) continue

            // `ContexteVote` sert ICI uniquement a porter le texte attendu :
            // `votePondere` est faux, donc la regle appliquee reste l'historique.
            val ctx = Decideur.ContexteVote(attendus, 0, true)
            val a = compter(Decideur().statuts(registre, mots), fautes, mots)
            val b = compter(
                Decideur(tete3SansVote = true).statuts(registre, mots, ctx), fautes, mots)
            sansT3 += a; avecT3 += b
            lignes.append(String.format(
                "  %-6s palier %3d%%  historique %2d/%2d faux %2d   + tete 3 %2d/%2d faux %2d%n",
                id, c.getInt("palier_pct"), a.detectees, a.detectees + a.ratees, a.fauxSignalements,
                b.detectees, b.detectees + b.ratees, b.fauxSignalements))
        }

        println("CONTRE-FACTUEL tete 3 SANS vote -- $observations observations, " +
            "$avecLogit avec logit")
        print(lignes)
        for ((nom, s) in listOf("historique seul" to sansT3, "historique + tete 3" to avecT3)) {
            println(String.format(
                "  %-22s detectees %3d  ratees %3d  faux %3d  corrects ok %4d" +
                    "   rappel %s  faux %s",
                nom, s.detectees, s.ratees, s.fauxSignalements, s.correctsOk,
                s.rappel?.let { String.format("%.0f%%", it) } ?: "-",
                s.faux?.let { String.format("%.1f%%", it) } ?: "-"))
        }

        // Le banc doit avoir REELLEMENT tourne : sans observation ni logit, les
        // deux colonnes seraient identiques et le test passerait en ne prouvant
        // rien -- le « zero trace = zero execution » deja paye ailleurs.
        assertTrue("aucune observation rejouee", observations > 1000)
        assertTrue("aucun logit de tete 3 dans les archives", avecLogit > 500)
        // La tete 3 ne peut que DEGRADER une couleur (cf. JugementTete3.couleur) :
        // elle ne doit jamais faire apparaitre une detection en moins, ni un
        // mot correct de plus. Si cela arrive, la regle branchee est fausse.
        assertTrue("la tete 3 a fait PERDRE des detections",
            avecT3.detectees >= sansT3.detectees)
        assertTrue("la tete 3 a fait GAGNER des mots corrects",
            avecT3.correctsOk <= sansT3.correctsOk)
    }
}
