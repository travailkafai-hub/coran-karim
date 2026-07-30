package com.corankarim.coran_karim.recitation2

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * COUCHE B — le decoupage aux SILENCES REELS du recitateur.
 *
 * ── CE QUE CE FICHIER TESTAIT AVANT LE 2026-07-30, ET POURQUOI CA A CHANGE ──
 *
 * La v2.0 emettait des fenetres de DUREE CONSTANTE qui se recouvraient, et ces
 * tests verrouillaient exactement ca : « toutes les fenetres pleines ont la
 * meme taille », « pas constant », « tout instant couvert par >= 2 fenetres ».
 * L'idee etait qu'une longueur constante empeche la normalisation `per_feature`
 * de deriver.
 *
 * La mesure a tranche contre. Meme flux brut (recitation professionnelle,
 * 379,8 s, 296 mots), meme modele causal du telephone, seul le decoupage
 * change -- erreur mot du decodage libre :
 *
 *     fichier entier ............................. 54,05 %  (202 mots lus)
 *     clips du portier RMS recolles (44) ......... 29,05 %  (269 mots lus)
 *     regroupes ~18 s (17) ....................... 39,19 %  (244 mots lus)
 *     COUPE AUX SILENCES REELS, pause >= 0,5 s ... 14,86 %  (307 mots lus)
 *
 * Ce n'est donc pas la regularite qui compte, c'est que les bornes tombent la
 * ou le recitateur se tait : un bloc delimite par des silences reels EST un
 * clip d'entrainement, un bloc de 6 s qui commence en plein mot ne l'est pas.
 *
 * Les proprietes d'avant ne sont pas « perdues », elles sont REFUTEES : on les
 * laisse ecrites ici pour qu'un futur agent ne les reintroduise pas en croyant
 * les avoir inventees.
 */
class ConstructeurDeFenetresTest {

    private fun parole(secondes: Double, valeur: Float = 0.1f): FloatArray =
        FloatArray(Horloge.secondesVersEch(secondes)) { valeur }

    private fun jouer(c: ConstructeurDeFenetres, morceaux: List<FloatArray>): List<Fenetre> {
        val out = ArrayList<Fenetre>()
        for (m in morceaux) {
            var i = 0
            while (i < m.size) {
                val fin = minOf(i + Horloge.ECH_PAR_FRAME, m.size)
                out.addAll(c.alimenter(m.copyOfRange(i, fin)))
                i = fin
            }
        }
        out.addAll(c.terminer())
        return out
    }

    @Test
    fun `la coupe tombe dans le silence, jamais dans la parole`() {
        val c = ConstructeurDeFenetres(pauseMinSecondes = 0.5)
        val fenetres = jouer(c, listOf(
            parole(3.0), Synthese.silence(1.0),
            parole(3.0), Synthese.silence(1.0),
            parole(3.0), Synthese.silence(2.0),
        ))
        val simples = fenetres.filter { !it.fusion }
        assertTrue("trois enonces => au moins trois blocs, obtenu ${simples.size}",
            simples.size >= 3)
        // Chaque bloc contient de la parole ET finit dans du silence : c'est ce
        // qui donne au modele causal son contexte droit (1,04 s de lookahead).
        for (f in simples) {
            assertTrue("bloc trop court : ${f.dureeSecondes}", f.dureeSecondes > 0.8)
        }
    }

    @Test
    fun `chaque enonce est vu DEUX fois - seul puis fusionne avec le precedent`() {
        val c = ConstructeurDeFenetres(pauseMinSecondes = 0.5)
        val fenetres = jouer(c, listOf(
            parole(2.0), Synthese.silence(1.0),
            parole(2.0), Synthese.silence(1.0),
            parole(2.0), Synthese.silence(1.5),
        ))
        assertTrue("il doit exister des blocs de FUSION (2e preuve, autre contexte)",
            fenetres.any { it.fusion })
        val simple = fenetres.first { !it.fusion }
        val fusion = fenetres.first { it.fusion }
        assertTrue("la fusion doit apporter un contexte different",
            fusion.echantillons.size > simple.echantillons.size)
    }

    @Test
    fun `aucun bloc ne depasse le domaine d'entrainement du modele`() {
        // Les clips d'entrainement font <= 20 s. Au-dela le modele travaille
        // dans un regime jamais vu : 54 % d'erreur sur le fichier entier contre
        // 14,9 % en blocs. Le garde-fou coupe donc meme sans silence, au point
        // le moins energique disponible.
        val c = ConstructeurDeFenetres(pauseMinSecondes = 0.5, maxBlocSecondes = 8.0)
        val fenetres = jouer(c, listOf(parole(30.0)))  // aucun silence du tout
        assertTrue("un flux sans pause doit quand meme produire des blocs",
            fenetres.isNotEmpty())
        for (f in fenetres.filter { !it.fusion }) {
            assertTrue("bloc de ${f.dureeSecondes}s > garde-fou de 8 s",
                f.dureeSecondes <= 8.5)
        }
    }

    @Test
    fun `le silence n'est plus jete - le travail est le flux brut`() {
        // v2.0 : le portier ecartait le silence au-dela de 0,3 s, ce qui
        // reconstruisait exactement le flux mutile des clips de la v1 -- preuve
        // directe : rejouee sur le flux BRUT, la v2.0 rendait le meme taux au
        // centieme (36,61 %). v2.1 : plus rien n'est ecarte, le silence EST
        // l'information de decoupage et le contexte droit du modele causal.
        val c = ConstructeurDeFenetres(pauseMinSecondes = 0.5)
        val parole1 = parole(2.0)
        val silence = Synthese.silence(3.0)
        val parole2 = parole(2.0)
        jouer(c, listOf(parole1, silence, parole2))
        assertEquals(
            "tout l'audio recu doit se retrouver dans le flux de travail",
            (parole1.size + silence.size + parole2.size).toLong(),
            c.positionTravail,
        )
    }

    @Test
    fun `la table d'horloges reste bijective et monotone`() {
        val c = ConstructeurDeFenetres(pauseMinSecondes = 0.5)
        val fenetres = jouer(c, listOf(
            parole(2.5), Synthese.silence(1.0), parole(2.5), Synthese.silence(1.5),
        ))
        val f = fenetres.first { !it.fusion }
        var precedent = -1L
        for (frame in 0 until f.echantillons.size / Horloge.ECH_PAR_FRAME) {
            val abs = f.absoluDeFrame(frame)
            assertTrue("frame $frame non reconvertible en position brute", abs >= 0)
            assertTrue("la conversion doit etre monotone", abs > precedent)
            precedent = abs
        }
    }

    @Test
    fun `terminer ferme le dernier enonce`() {
        // Sans cet appel le dernier enonce n'est jamais analyse : la coupe est
        // declenchee par un silence, or la capture peut s'arreter avant lui.
        val c = ConstructeurDeFenetres(pauseMinSecondes = 0.5)
        var pendant = 0
        val morceau = parole(3.0)
        var i = 0
        while (i < morceau.size) {
            val fin = minOf(i + Horloge.ECH_PAR_FRAME, morceau.size)
            pendant += c.alimenter(morceau.copyOfRange(i, fin)).size
            i = fin
        }
        assertEquals("aucun bloc tant qu'aucun silence n'est venu", 0, pendant)
        assertTrue("terminer() doit fermer le bloc en cours", c.terminer().isNotEmpty())
    }
}
