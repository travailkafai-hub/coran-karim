package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Les ecritures equivalentes — et surtout CE QU'ELLES NE DOIVENT PAS PRODUIRE.
 *
 * Ce test existe parce qu'une variante de trop ne se voit pas : elle ne fait
 * pas echouer la chaine, elle rend VERT un mot fautif. Le seul garde-fou est
 * donc d'ecrire noir sur blanc, ici, ce qui est interdit -- la regle d'entree
 * du fichier teste etant « une variante ne rentre que si elle se prononce
 * STRICTEMENT pareil ».
 *
 * Les deux cas mesures viennent de la session Al-Fil du 2026-08-14 :
 *   `تَرْمِيهِم`  gop=-0,46 (seuil de vert : -0,45) -- soukoun final
 *   `مَّأْكُولٍۭ` gop=-0,69                          -- petit meem d'iqlab
 */
class OrthographeTest {

    @Test
    fun `le mot canonique vient toujours en premier`() {
        val mot = "تَرْمِيهِم"
        assertEquals(mot, Orthographe.variantes(mot).first())
    }

    // ── (8) SOUKOUN FINAL ────────────────────────────────────────────────────

    @Test
    fun `finale nue - la forme avec soukoun est proposee`() {
        val v = Orthographe.variantes("تَرْمِيهِم")
        assertTrue("la forme du modele doit etre alignable", v.contains("تَرْمِيهِمْ"))
    }

    @Test
    fun `finale en soukoun - la forme nue est proposee`() {
        val v = Orthographe.variantes("كَيْدَهُمْ")
        assertTrue(v.contains("كَيْدَهُم"))
    }

    @Test
    fun `le soukoun INTERIEUR n'est jamais touche`() {
        // `يَجْعَلْ` : soukoun sur le ج (interieur) ET sur le ل (final).
        // Seul le final peut bouger -- retirer celui du ج vocaliserait une
        // consonne muette, c'est-a-dire une autre prononciation.
        val v = Orthographe.variantes("يَجْعَلْ")
        assertTrue(v.contains("يَجْعَل"))
        assertFalse("le soukoun interieur ne doit pas disparaitre",
            v.any { it.contains("يَجعَل") })
    }

    @Test
    fun `une finale VOYELLEE n'engendre pas de forme en soukoun`() {
        // C'est le waqf, et il n'est PAS traite ici : sa licite depend de la
        // position dans le verset, information dont cette couche ne dispose
        // pas. Remplacer la voyelle finale a l'aveugle blanchirait une faute
        // d'i'rab en plein verset.
        val v = Orthographe.variantes("رَبُّكَ")
        assertFalse(v.any { it.endsWith("رَبُّكْ") })
        assertFalse(v.any { it == "رَبُّك" })
    }

    // ── (9) SIGNES DE TAJWID CONTEXTUELS ────────────────────────────────────

    @Test
    fun `le petit meem d'iqlab peut etre absent`() {
        val v = Orthographe.variantes("مَّأْكُولٍۭ")
        assertTrue("la forme que le modele emet doit etre alignable",
            v.contains("مَّأْكُولٍ"))
    }

    @Test
    fun `retirer le signe ne retire aucune LETTRE`() {
        // Selectionner la variante par sa FORME, jamais par sa position : la
        // liste contient aussi le madd tenu (`مَّأْكُوولٍۭ`), genere avant.
        val sansSigne = Orthographe.variantes("مَّأْكُولٍۭ")
            .single { !it.contains('ۭ') }
        assertEquals("مَّأْكُولٍ", sansSigne)
        // Le tanwin (U+064D) est du SON : il reste.
        assertTrue(sansSigne.contains('ٍ'))
        // Et les lettres sont intactes, une a une.
        assertEquals("مَّأْكُولٍۭ".filter { it in 'ء'..'ي' },
            sansSigne.filter { it in 'ء'..'ي' })
    }

    // ── LE PLAFOND ──────────────────────────────────────────────────────────

    @Test
    fun `un mot tres marque ne perd plus ses variantes par troncature`() {
        // Defaut latent trouve le 2026-08-14 : avec MAX=7, un mot cumulant
        // plusieurs marques atteignait le plafond et perdait EN SILENCE la
        // derniere famille generee.
        val v = Orthographe.variantes("ٱلصَّوَٰعِقِ")
        assertTrue("le canonique et ses variantes doivent tenir", v.size >= 3)
        assertTrue(v.contains("ٱلصَّوَاعِقِ"))
        assertTrue(v.contains("الصَّوَٰعِقِ"))
    }

    @Test
    fun `aucune variante n'est vide ni dupliquee`() {
        for (mot in listOf("تَرْمِيهِم", "كَيْدَهُمْ", "مَّأْكُولٍۭ", "ٱلْفِيلِ", "فِى")) {
            val v = Orthographe.variantes(mot)
            assertTrue(v.none { it.isEmpty() })
            assertEquals(v.size, v.toSet().size)
        }
    }
}
