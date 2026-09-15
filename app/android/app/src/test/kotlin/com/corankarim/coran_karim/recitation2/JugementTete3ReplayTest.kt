package com.corankarim.coran_karim.recitation2

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Contre-factuel sur les observations natives archivees, avec LE decideur
 * Kotlin. Cloture en fin de log : ne reproduit PAS les verrouillages en direct.
 * Sert a choisir les replays device, pas a annoncer un gain de detection. */
class JugementTete3ReplayTest {
    @Test fun `compare vote seul et vote avec tete3 sur les memes observations archivees`() {
        var root = File(System.getProperty("user.dir")).absoluteFile
        while (!File(root, "benchmark/campagne_100x20_dense30").exists())
            root = requireNotNull(root.parentFile)
        val repertoires = listOf("vote_T023_36_3_decision_occurrence_20260915",
            "vote_T004_30_decision_20260915", "vote_T005_115_decision_20260915",
            "vote_T006_30_decision_20260915", "vote_T013_50_decision_20260915",
            "vote_T016_25_decision_20260915", "vote_T033_6_decision_20260915",
            "vote_T038_4_decision_20260915", "vote_T064_5_decision_20260915",
            "vote_T075_112_decision_20260915", "vote_T095_38_decision_20260915",
            "vote_T014_55_10_candidate_20260915_run", "vote_T002_78_23_candidate_20260915_run",
            "vote_T031_78_3_candidate_20260915_run", "vote_T081_78_4_candidate_20260915_run")
        val resultat = JSONArray()
        fun statut(s: Statut?): String = when(s) {
            is Statut.Definitif -> "definitif:${s.couleur.name}"
            is Statut.Provisoire -> "provisoire:${s.couleur.name}"
            Statut.Omis -> "omis"
            Statut.Deplace -> "deplace"
            else -> "inconnu"
        }
        for (nom in repertoires) {
            val dossier = File(root, "benchmark/$nom")
            val manifest = JSONObject(File(dossier, "manifest.json").readText(Charsets.UTF_8))
            val cas = manifest.getJSONArray("cases").getJSONObject(0)
            val mots = cas.getJSONArray("expected_words").let { a ->
                (0 until a.length()).map { a.getString(it) }
            }
            val logs = File(dossier, "logs").listFiles()!!.filter {
                it.name.endsWith(".log") && !it.name.endsWith(".before_close.log")
            }
            assertEquals("Une seule execution par dossier", 1, logs.size)
            val r = RegistreDePreuves()
            val scores = HashMap<Pair<Long, Int>, Float>()
            logs.single().forEachLine(Charsets.UTF_8) { l ->
                if ("[t3-comparaison] " in l) {
                    val j = JSONObject(l.substringAfter("[t3-comparaison] "))
                    if (!j.isNull("candidate")) scores[j.getLong("fenetre") to j.getInt("mot")] =
                        j.getDouble("candidate").toFloat()
                }
                if ("[vote-observation] " in l) {
                    val j = JSONObject(l.substringAfter("[vote-observation] "))
                    fun f(k: String) = j.optDouble(k, Double.NaN).toFloat()
                    fun opt(k: String) = f(k).takeIf { it.isFinite() }
                    val id = j.getLong("fenetre"); val m = j.getInt("mot")
                    val poids = j.optDouble("poids", Double.NaN)
                    val lecture = if (j.isNull("fenetre_debut")) null else VoteFenetres.Lecture(
                        if (poids.isFinite()) ConfianceLectureCtc.Mesure(poids,
                            j.optInt("tokens_emis"), j.optDouble("pic_minimum"),
                            j.optDouble("confiance_entropie")) else null,
                        if (j.isNull("exclusion")) null else j.getString("exclusion"),
                        j.getLong("fenetre_debut"), j.getLong("fenetre_fin"))
                    r.ajouter(RegistreDePreuves.Observation(id, m, f("gop"), f("forced"), f("free"),
                        j.getString("entendu"), j.getInt("frames"), j.getBoolean("interieur"),
                        j.getBoolean("couvert"), sansCreneau = j.getBoolean("sans_creneau"),
                        atteste = j.getBoolean("atteste"), margeLettres = opt("marge_lettres"),
                        margeHarakat = opt("marge_harakat"), fenetrePleine = true,
                        debutAbs = j.getLong("debut"), finAbs = j.getLong("fin"), lectureVote = lecture,
                        mesureTete3Jugement = scores[id to m]?.let { Tete3.Mesure(it, null) }))
                }
            }
            assertTrue("Observations absentes $nom", r.total() > 0)
            val ctx = Decideur.ContexteVote(mots, 0, true)
            val base = Decideur(votePondere = true).statuts(r, mots.size, ctx)
            val d = Decideur(votePondere = true, utiliserTete3 = true)
            val apres = d.statuts(r, mots.size, ctx)
            for (m in mots.indices) {
                val os = r.observationsPourJugement(m)
                val vote = VoteFenetres.calculer(os)
                val avis = JugementTete3.evaluer(vote, os)
                val avant = base[m]; val suite = apres[m]
                if (suite == Statut.Definitif(Couleur.ROUGE))
                    assertTrue("Rouge sans preuve $nom/$m", d.preuveRetenue(m)?.entendu?.isNotBlank() == true)
                if (avant == Statut.Definitif(Couleur.ROUGE)) assertEquals(avant, suite)
                resultat.put(JSONObject().put("dossier", nom).put("mot", m).put("attendu", mots[m])
                    .put("avant", statut(avant)).put("apres", statut(suite))
                    .put("etat_t3", avis.etat.name).put("activation", avis.activationMoyenne ?: JSONObject.NULL)
                    .put("fenetres", JSONArray(vote.fenetresRetenues))
                    .put("logits", JSONArray(avis.contributions.map { it.logit })))
            }
        }
        File(root, "benchmark/contre_factuel_tete3_jugement_20260915.json")
            .writeText(resultat.toString(2), Charsets.UTF_8)
        assertTrue(resultat.length() > 100)
    }
}
