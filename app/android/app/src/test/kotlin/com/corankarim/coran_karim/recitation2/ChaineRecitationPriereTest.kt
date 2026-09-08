package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** ChGPT: replay the localisation failure of 2026-09-08, independently of ONNX. */
class ChaineRecitationPriereTest {
    private class Session(priere: Boolean = true, warsh: Boolean = false, reference: Boolean = false) {
        val texte = List(68) { "تمهيد" } + listOf(
            "ذلك", "أدنى", "ألا", "تعولوا",
            "وآتوا", "النساء", "صدقاتهن", "نحلة", "فإن", "طبن", "لكم",
            "عن", "شيء", "منه", "نفسا", "فكلوه", "هنيئا", "مريئا",
            "ولا", "تؤتوا", "السفهاء", "أموالكم",
        )
        private val inconnu = listOf("حديث", "غريب", "مختلف")
        private val pieces = Synthese.vocabulaire(texte + inconnu)
        private val tokeniser = Synthese.tokeniseur(pieces)
        val journal = ArrayList<String>()
        val chaine = ChaineRecitation(
            front = FauxFront(pieces),
            tokeniser = tokeniser,
            variantesOrthographe = if (warsh) Orthographe::variantesWarsh else Orthographe::variantes,
            sautLibre = priere,
            referenceSession = reference,
            journal = { journal.add(it) },
        ).also { it.definirTexte(texte, positionDepart = 68) }
        private var id = 0L
        private var position = 0L

        // Inject whole windows at the acoustic boundary, without changing any
        // private state. Localisation, gap detection, alignment and verdicts are real.
        private val traiter = ChaineRecitation::class.java
            .getDeclaredMethod("traiter", Fenetre::class.java).apply { isAccessible = true }

        private fun entendrePcm(contenu: FloatArray) {
            val pcm = Synthese.silence(0.32) + contenu + Synthese.silence(1.28)
            val fenetre = Fenetre(
                id++, position, pcm,
                Correspondance(listOf(Correspondance.Segment(position, position, pcm.size))),
                pleine = true,
            )
            traiter.invoke(chaine, fenetre)
            chaine.alimenter(FloatArray(0))
            position += pcm.size
        }

        fun entendre(mots: List<String>) =
            entendrePcm(Synthese.pcm(mots, tokeniser, pieces.size, 2, 2))

        fun debut() = entendre(texte.subList(68, 72))
        fun trou() {
            // The missing transcript still occupies time: otherwise the real
            // localiser rejects 71 -> 86 as physically impossible, before PRIERE.
            val framesDuTrou = texte.subList(72, 86).sumOf { tokeniser(it).size }
            entendrePcm(
                Synthese.pcm(texte.subList(68, 72), tokeniser, pieces.size, 2, 2) +
                    Synthese.silence(framesDuTrou * Horloge.MS_PAR_FRAME / 1000.0) +
                    Synthese.pcm(listOf(texte[86]), tokeniser, pieces.size, 2, 2),
            )
        }
        fun horsTexte() = entendre(inconnu)
        fun perdre() = repeat(3) { horsTexte() }
        fun verifierTrou() = assertTrue(journal.joinToString("\n"),
            journal.any { "trou de 14 mot(s) apres le mot 71 MIS EN ATTENTE" in it })
    }

    private fun verifierRepriseDuTrou(warsh: Boolean) {
        val s = Session(warsh = warsh)
        s.debut()
        s.trou()
        s.verifierTrou()
        assertEquals(-1, s.chaine.sautPresumeDe)
        s.horsTexte()
        assertFalse("One unknown window must not trigger a hint", s.chaine.decrochage)
        repeat(2) { s.horsTexte() }
        assertTrue(s.journal.joinToString("\n"), s.chaine.decrochage)
        assertEquals("The Dart bridge adds one: hint must start at 72, not 87",
            71, s.chaine.motDuDecrochage)
        assertEquals("The hint must not become an omission verdict",
            -1, s.chaine.sautPresumeDe)
    }

    @Test fun `hafs prayer prompts the unresolved gap before the furthest attestation`() =
        verifierRepriseDuTrou(warsh = false)

    @Test fun `warsh prayer prompts the unresolved gap before the furthest attestation`() =
        verifierRepriseDuTrou(warsh = true)

    @Test fun `a filled gap no longer determines the next hint`() {
        val s = Session()
        s.debut()
        s.trou()
        s.verifierTrou()
        s.entendre(s.texte.subList(72, 87))
        assertTrue(s.journal.joinToString("\n"), s.journal.any { "trou en attente COMBLE" in it })
        assertEquals(-1, s.chaine.sautPresumeDe)
        s.perdre()
        assertTrue(s.chaine.decrochage)
        assertEquals(86, s.chaine.motDuDecrochage)
    }

    @Test fun `prayer without a pending gap keeps its last position`() {
        val s = Session()
        s.debut()
        s.perdre()
        assertTrue(s.chaine.decrochage)
        assertEquals(71, s.chaine.motDuDecrochage)
    }

    @Test fun `normal recitation still refuses a gap`() {
        val s = Session(priere = false)
        s.debut()
        s.trou()
        assertTrue(s.journal.joinToString("\n"), s.journal.any { "SAUT REFUSE" in it })
        s.perdre()
        assertTrue(s.chaine.decrochage)
        assertEquals(71, s.chaine.motDuDecrochage)
    }

    @Test fun `reference recitation still resumes after its furthest attestation`() {
        val s = Session(priere = false, reference = true)
        s.debut()
        s.trou()
        s.perdre()
        assertTrue(s.chaine.decrochage)
        assertEquals(86, s.chaine.motDuDecrochage)
    }

    @Test fun `after the hint the reciter can continue without repeating the gap`() {
        val s = Session()
        s.debut()
        s.trou()
        s.perdre()
        assertEquals(71, s.chaine.motDuDecrochage)
        s.chaine.repartirApresSouffle(s.chaine.motDuDecrochage + 1)
        s.entendre(s.texte.subList(82, 90))
        assertFalse(s.chaine.decrochage)
        assertTrue(s.journal.joinToString("\n"), s.chaine.preuves.indexMaxVotant() >= 88)
        assertFalse(s.journal.any { "SAUT REFUSE" in it })
    }

    @Test fun `changing target forgets the previous pending gap`() {
        val s = Session()
        s.debut()
        s.trou()
        s.verifierTrou()
        s.chaine.definirTexte(s.texte, positionDepart = 86)
        s.entendre(s.texte.subList(86, 90))
        s.perdre()
        assertTrue(s.chaine.decrochage)
        assertEquals(89, s.chaine.motDuDecrochage)
    }
}
