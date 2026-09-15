package com.corankarim.coran_karim.recitation2

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class JugementTete3Test {
    private fun obs(id: Long, texte: String = "B", logit: Float? = 4f, poids: Double = .8) =
        RegistreDePreuves.Observation(id, 0, 0f, 0f, 0f, texte, 2, true, true,
            fenetrePleine = true, debutAbs = 5000, finAbs = 6280,
            atteste = texte == "B",
            lectureVote = VoteFenetres.Lecture(ConfianceLectureCtc.Mesure(poids, 1, poids, poids),
                null, 0, 32000 + id * 1280),
            mesureTete3Jugement = logit?.let { Tete3.Mesure(it, null) })
    private fun ctx(ferme: Boolean = true) = Decideur.ContexteVote(listOf("B"), 0, ferme)
    private fun juge() = Decideur(votePondere = true, utiliserTete3 = true)
    private fun registre(vararg os: RegistreDePreuves.Observation) =
        RegistreDePreuves().also { r -> os.forEach(r::ajouter) }

    @Test fun `deux ecarts acoustiques rougissent meme une transcription exacte attestee`() {
        val r = registre(obs(1), obs(2)); val d = juge()
        assertEquals(Statut.Provisoire(Couleur.ROUGE), d.statuts(r, 1, ctx(false))[0])
        assertEquals(Statut.Definitif(Couleur.ROUGE), d.statuts(r, 1, ctx())[0])
        assertEquals("B", d.preuveRetenue(0)!!.entendu)
        assertTrue(d.preuveRetenue(0)!!.mesureTete3Jugement!!.logit > 0)
    }

    @Test fun `alerte isolee suspend le vert sans condamner meme a la fermeture`() {
        val r = registre(obs(1)); val d = juge()
        assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 1, ctx())[0])
        r.ajouter(obs(1)) // meme fenetre, pas de confirmation
        assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 1, ctx())[0])
        r.ajouter(obs(2, logit = null)) // donnee absente, pas un vote favorable
        assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 1, ctx())[0])
    }

    @Test fun `tete peu inquiete ne blanchit jamais un vote texte fautif`() {
        val r = registre(obs(1, "A", -9f), obs(2, "A", -8f), obs(3, "B", -10f))
        assertEquals(Statut.Definitif(Couleur.ROUGE), juge().statuts(r, 1, ctx())[0])
    }

    @Test fun `observations acoustiques discordantes sont ponderees et non maximisées`() {
        val r = registre(obs(1, logit = -5f), obs(2, logit = -5f), obs(3, logit = 20f))
        assertEquals(Statut.Definitif(Couleur.VERT), juge().statuts(r, 1, ctx())[0])
        val doute = registre(obs(1, logit = -5f), obs(2, logit = 5f))
        assertEquals(Statut.Provisoire(Couleur.ORANGE), juge().statuts(doute, 1, ctx())[0])
    }

    @Test fun `une mesure sure domine deux faibles mais attend sa confirmation`() {
        val r = registre(obs(1, logit = -.1f), obs(2, logit = 8f), obs(3, logit = -.1f))
        assertEquals(Statut.Provisoire(Couleur.ORANGE), juge().statuts(r, 1, ctx())[0])
        r.ajouter(obs(4, logit = 4f))
        assertEquals(Statut.Definitif(Couleur.ROUGE), juge().statuts(r, 1, ctx())[0])
    }

    @Test fun `sans mesure et non fini conservent exactement le vote texte`() {
        for (logit in listOf(null, Float.NaN, Float.POSITIVE_INFINITY)) {
            val r = registre(obs(1, logit = logit), obs(2, logit = logit))
            assertEquals(Statut.Definitif(Couleur.VERT), juge().statuts(r, 1, ctx())[0])
        }
    }

    @Test fun `silence bord fragment et attribution parasite ne votent pas tete3`() {
        val r = registre(obs(1, logit = -8f), obs(2, logit = -8f),
            obs(3, logit = 30f).copy(interieur = false), obs(4, "", 30f),
            obs(5, logit = 30f).copy(sansCreneau = true),
            obs(6, logit = 30f).let { it.copy(lectureVote = it.lectureVote!!.copy(exclusion = "fragment_alignement")) },
            obs(7, "A", 30f).copy(debutAbs = 90000, finAbs = 91280))
        val vote = VoteFenetres.calculer(r.observationsPourJugement(0))
        assertEquals(setOf(1L, 2L), vote.fenetresRetenues)
        assertEquals(Statut.Definitif(Couleur.VERT), juge().statuts(r, 1, ctx())[0])
    }

    @Test fun `deux occurrences solides disjointes interdisent le jugement acoustique`() {
        val r = registre(obs(1), obs(2),
            obs(3).copy(debutAbs = 90000, finAbs = 91280),
            obs(4).copy(debutAbs = 90000, finAbs = 91280))
        assertEquals(Statut.Provisoire(Couleur.ORANGE), juge().statuts(r, 1, ctx())[0])
    }

    @Test fun `tete peut detecter ecart sans savoir departager A et C`() {
        val r = registre(obs(1, "A"), obs(2, "C"))
        val d = juge()
        assertEquals(Statut.Definitif(Couleur.ROUGE), d.statuts(r, 1, ctx())[0])
        assertTrue(d.preuveRetenue(0)!!.entendu.isNotBlank())
    }

    @Test fun `alerte peut etre dementie avant cloture mais definitif reste stable`() {
        val r = registre(obs(1)); val d = juge()
        assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 1, ctx(false))[0])
        r.ajouter(obs(2, logit = -8f)); r.ajouter(obs(3, logit = -8f))
        assertEquals(Statut.Definitif(Couleur.VERT), d.statuts(r, 1, ctx())[0])
        r.ajouter(obs(4, logit = 30f)); r.ajouter(obs(5, logit = 30f))
        assertEquals(Statut.Definitif(Couleur.VERT), d.statuts(r, 1, ctx())[0])
        d.oublierDepuis(0, true); r.commencerTentative(0, 10000)
        r.ajouter(obs(6).copy(debutAbs = 11000, finAbs = 12280))
        assertEquals(Statut.Provisoire(Couleur.ORANGE), d.statuts(r, 1, ctx())[0])
    }

    @Test fun `identite et parite de la tete embarquee refuse toute autre tete`() {
        var racine = File(System.getProperty("user.dir")).absoluteFile
        while (!File(racine, "benchmark/tetes_candidates").exists())
            racine = requireNotNull(racine.parentFile)
        fun asset(p: JugementTete3.Politique) =
            File(racine, "app/android/app/src/debug/assets/${p.asset}").readBytes()
        // CROISE, ET C'EST LE POINT : deux riwayat = deux fichiers de poids de
        // meme format (1036, deux couches). Seule l'empreinte les distingue, et
        // une tete chargee pour la mauvaise riwaya produirait des logits
        // plausibles sans jamais rien signaler -- exactement le mode de panne
        // silencieuse que `Tete3.kt` documente.
        for (politique in listOf(JugementTete3.HAFS, JugementTete3.WARSH)) {
            val bytes = asset(politique)
            assertNotNull(politique.riwaya, JugementTete3.chargerVerifiee(bytes, politique))
            assertNull(politique.riwaya, JugementTete3.chargerVerifiee(bytes + 32.toByte(), politique))
            for (autre in listOf(JugementTete3.HAFS, JugementTete3.WARSH)) {
                if (autre === politique) continue
                assertNull("${autre.riwaya} accepte la tete ${politique.riwaya}",
                    JugementTete3.chargerVerifiee(bytes, autre))
            }
        }
        // Le defaut reste Hafs : un appel sans politique ne doit pas se mettre
        // a accepter la tete Warsh au pretexte qu'elle existe maintenant.
        assertNotNull(JugementTete3.chargerVerifiee(asset(JugementTete3.HAFS)))
        assertNull(JugementTete3.chargerVerifiee(asset(JugementTete3.WARSH)))
    }

    @Test fun `la riwaya choisit la tete et le journal la nomme`() {
        assertSame(JugementTete3.WARSH, JugementTete3.pour(true))
        assertSame(JugementTete3.HAFS, JugementTete3.pour(false))
        assertNotEquals(JugementTete3.HAFS.sha256, JugementTete3.WARSH.sha256)
        assertNotEquals(JugementTete3.HAFS.asset, JugementTete3.WARSH.asset)
        // Sans la riwaya dans la trace, deux campagnes de calibration menees
        // avec deux fichiers de poids differents seraient indistinguables.
        val r = registre(obs(1), obs(2))
        val vote = VoteFenetres.calculer(r.observationsPourJugement(0))
        val avis = JugementTete3.evaluer(vote, r.observationsPourJugement(0), 2)
        for (p in listOf(JugementTete3.HAFS, JugementTete3.WARSH)) {
            val ligne = JournalVoteFenetres.jugementTete3(0, r.tentativeId, vote, avis,
                Couleur.VERT, Statut.Provisoire(Couleur.ROUGE), null, p)
            assertTrue(ligne, ligne.contains("\"riwaya\":\"${p.riwaya}\""))
            assertTrue(ligne, ligne.contains(p.sha256))
        }
    }

    @Test fun `la candidate Warsh embarquee est celle validee hors depot`() {
        var racine = File(System.getProperty("user.dir")).absoluteFile
        while (!File(racine, "benchmark/tetes_candidates").exists())
            racine = requireNotNull(racine.parentFile)
        // L'asset de l'APK et la candidate recue de PC A doivent etre le MEME
        // fichier : une copie divergente rendrait le SHA du journal faux.
        val source = File(racine,
            "benchmark/tetes_candidates/warsh_v1_20260915/tete3_warsh_v1.json")
        val embarquee = File(racine,
            "app/android/app/src/debug/assets/${JugementTete3.WARSH.asset}")
        assertTrue("candidate Warsh absente du depot", source.exists())
        assertArrayEquals(source.readBytes(), embarquee.readBytes())
        val tete = requireNotNull(
            JugementTete3.chargerVerifiee(embarquee.readBytes(), JugementTete3.WARSH))
        assertEquals(1036, tete.tailleEntree)
        // Non calibree, et ca doit rester visible : la politique brute
        // (frontiere logit=0) n'est legitime QUE tant qu'aucun seuil mesure
        // n'existe. Le jour ou ce fichier en porte, la politique doit etre
        // revue, pas silencieusement conservee.
        assertNull(tete.seuil2Pct)
        assertNull(tete.seuil10Pct)
        val x = FloatArray(1036) { (((it * 37) % 101) - 50) / 25.0f }
        assertEquals("NON_CALIBREE", tete.mesurer(x)!!.statut)
        assertEquals(-0.976116, tete.logit(x).toDouble(), 1e-3)
    }
}
