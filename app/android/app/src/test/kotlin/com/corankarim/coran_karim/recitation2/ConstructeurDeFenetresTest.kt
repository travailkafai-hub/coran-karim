package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * BANC 1 — la propriete qui remplace toute la machinerie de segmentation.
 *
 * Ce que ces tests verrouillent (et qu'aucune version v1 ne pouvait garantir) :
 *  - la duree d'analyse est CONSTANTE en regime etabli => la normalisation
 *    `per_feature` ne peut plus deriver avec la longueur (constat n°1) ;
 *  - les fenetres SE RECOUVRENT => aucun mot ne peut etre definitivement coupe
 *    (47,4 % des coupes v1 tombaient en plein mot) ;
 *  - la table d'horloges est bijective => le portier de silence ne cree plus
 *    d'echelle de temps fantome ([PIEGE] deux_echelles_temps).
 */
class ConstructeurDeFenetresTest {

    private fun bruit(secondes: Double, valeur: Float = 0.1f): FloatArray =
        FloatArray(Horloge.secondesVersEch(secondes)) { valeur }

    @Test
    fun `la duree des fenetres devient constante en regime etabli`() {
        val c = ConstructeurDeFenetres(fenetreSecondes = 6.0, pasSecondes = 1.5, fenetreMinSecondes = 2.0)
        val fenetres = c.alimenter(bruit(20.0))

        assertTrue("des fenetres doivent etre emises", fenetres.size >= 10)
        val pleines = fenetres.filter { it.pleine }
        assertTrue("le regime etabli doit etre atteint", pleines.size >= 8)
        val tailles = pleines.map { it.echantillons.size }.toSet()
        assertEquals("toutes les fenetres pleines ont EXACTEMENT la meme taille", 1, tailles.size)
        assertEquals(Horloge.secondesVersEch(6.0), tailles.first())
    }

    @Test
    fun `les fenetres se recouvrent d'un pas constant`() {
        val c = ConstructeurDeFenetres(fenetreSecondes = 6.0, pasSecondes = 1.5)
        val f = c.alimenter(bruit(20.0)).filter { it.pleine }
        for (i in 1 until f.size) {
            assertEquals(
                "pas constant entre deux fenetres consecutives",
                Horloge.secondesVersEch(1.5).toLong(),
                f[i].travailDebut - f[i - 1].travailDebut
            )
            assertTrue(
                "les fenetres doivent se RECOUVRIR (sinon un mot peut tomber entre deux)",
                f[i].travailDebut < f[i - 1].travailFin
            )
        }
    }

    @Test
    fun `tout instant de parole est couvert par au moins deux fenetres pleines`() {
        val c = ConstructeurDeFenetres(fenetreSecondes = 6.0, pasSecondes = 1.5)
        val f = c.alimenter(bruit(30.0)).filter { it.pleine }
        // On teste le regime etabli : apres la premiere fenetre pleine et avant
        // la derniere, chaque instant doit tomber dans >= 2 fenetres. C'est la
        // condition qui rend K=2 observations concordantes ATTEIGNABLE.
        val debut = f.first().travailFin
        val fin = f.last().travailDebut
        var pas = Horloge.secondesVersEch(0.5).toLong()
        var pos = debut
        while (pos < fin) {
            val n = f.count { pos >= it.travailDebut && pos < it.travailFin }
            assertTrue("instant $pos couvert par $n fenetre(s), attendu >= 2", n >= 2)
            pos += pas
        }
        pas = 0 // (evite un avertissement de variable non utilisee)
    }

    @Test
    fun `le portier de silence ne detruit rien - la table d'horloges reste bijective`() {
        val c = ConstructeurDeFenetres(fenetreSecondes = 4.0, pasSecondes = 1.0, fenetreMinSecondes = 1.0)
        // parole - long silence - parole : le portier ne garde que 0,3 s de pause
        c.alimenter(bruit(3.0))
        c.alimenter(Synthese.silence(4.0))
        val fenetres = c.alimenter(bruit(3.0))

        assertTrue(fenetres.isNotEmpty())
        val derniere = fenetres.last()
        // Chaque frame de la fenetre doit se reconvertir en une position REELLE
        // du flux brut, et l'ordre doit etre strictement croissant.
        var precedent = -1L
        var testees = 0
        for (frame in 0 until derniere.echantillons.size / Horloge.ECH_PAR_FRAME) {
            val abs = derniere.absoluDeFrame(frame)
            assertTrue("frame $frame non reconvertible en position brute", abs >= 0)
            assertTrue("la conversion doit etre monotone", abs > precedent)
            precedent = abs
            testees++
        }
        assertTrue(testees > 0)
    }

    @Test
    fun `le silence long est ecarte du travail mais l'audio brut reste complet`() {
        val brut = FluxBrut(secondesEnMemoire = 60)
        val c = ConstructeurDeFenetres(fenetreSecondes = 4.0, pasSecondes = 1.0, fenetreMinSecondes = 1.0)

        val parole1 = bruit(2.0)
        val silence = Synthese.silence(5.0)
        val parole2 = bruit(2.0)
        for (bloc in listOf(parole1, silence, parole2)) {
            brut.ajouter(bloc)
            c.alimenter(bloc)
        }

        assertEquals(
            "le flux brut contient TOUT ce qui est entre par le micro",
            (parole1.size + silence.size + parole2.size).toLong(), brut.total
        )
        // Le flux de travail ne garde de la pause de 5 s que le lookahead du
        // modele causal (1,04 s + marge) — ni plus (le silence long fait
        // deriver le modele) ni moins (le dernier mot serait injugeable).
        val attenduMax = parole1.size + Horloge.secondesVersEch(1.04 + 1.0 + 0.15) + parole2.size
        assertTrue(
            "le travail doit avoir compresse le silence (${c.positionTravail} <= $attenduMax)",
            c.positionTravail <= attenduMax
        )
        assertTrue("le travail ne doit rien avoir invente", c.positionTravail >= parole1.size + parole2.size)
    }
}
