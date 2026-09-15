"""Contrats du prototype, sans mesure de performance ASR."""
from dataclasses import replace
from itertools import permutations
import unittest

from vote_hypotheses_hafs import Observation, voter


class VoteHypothesesTest(unittest.TestCase):
    def obs(self, f, texte='A', poids=.8, **kwargs):
        return Observation('t1', 5, 'p1', f, texte, poids, **kwargs)

    def vote(self, observations, terminee=True):
        return voter(observations, tentative='t1', mot=5, prononciation='p1',
                     lecture_terminee=terminee)

    def test_deux_a_soutenus_gagnent_sur_b_isole(self):
        result = self.vote([self.obs(1), self.obs(2), self.obs(3, 'B')])
        self.assertEqual('A', result['hypothese_majoritaire_des_poids_connus'])
        self.assertIsNone(result['statut_app'])

    def test_b_solide_gagne_sur_lectures_incertaines(self):
        result = self.vote([self.obs(1, 'A', .2), self.obs(2, 'B', .9), self.obs(3, 'C', .1)])
        self.assertEqual('B', result['hypothese_majoritaire_des_poids_connus'])

    def test_le_premier_vert_ne_gagne_pas_selon_ordre_arrivee(self):
        observations = [self.obs(1, 'B'), self.obs(2), self.obs(3)]
        attendu = self.vote(observations)
        for ordre in permutations(observations):
            self.assertEqual(attendu, self.vote(list(ordre)))

    def test_aucun_verrou_pendant_arrivee_des_fenetres(self):
        debut = self.vote([self.obs(1, 'B')], terminee=False)
        self.assertEqual('PROVISOIRE', debut['etat'])
        suite = self.vote([self.obs(1, 'B'), self.obs(2), self.obs(3)], terminee=False)
        self.assertEqual('A', suite['hypothese_majoritaire_des_poids_connus'])
        self.assertEqual('PROVISOIRE', suite['etat'])

    def test_doublons_de_fenetre_ne_creent_pas_de_majorite(self):
        a, b = self.obs(1), self.obs(2, 'B')
        self.assertEqual(self.vote([a, b]), self.vote([a] * 10 + [b]))
        self.assertEqual('INDECIS', self.vote([a, b])['etat'])

    def test_revision_remplace_ancienne_preuve_sans_dependre_de_ordre_arrivee(self):
        a = self.obs(1)
        b = replace(a, revision=1, texte='B')
        self.assertEqual(self.vote([a, b]), self.vote([b, a]))
        self.assertEqual('B', self.vote([a, b])['hypothese_majoritaire_des_poids_connus'])

    def test_aucun_vote_des_autres_tentatives_mots_ou_prononciations(self):
        a = self.obs(1)
        autres = [replace(a, tentative='ancienne'), replace(a, mot=6), replace(a, prononciation='p0')]
        self.assertEqual(self.vote([self.obs(2, 'B')]), self.vote(autres + [self.obs(2, 'B')]))

    def test_fragments_sans_creneau_ou_bord_ne_condamnent_pas_un_mot_complet(self):
        fragments = [self.obs(1, interieur=False), self.obs(2, creneau_propre=False),
                     self.obs(3, intervalle_complet=False)]
        self.assertEqual('B', self.vote(fragments + [self.obs(4, 'B')])['hypothese_majoritaire_des_poids_connus'])

    def test_harakat_distinctes_ne_sont_pas_fusionnees(self):
        result = self.vote([self.obs(1, 'أَصْحَـٰبَ'), self.obs(2, 'أَصْحَـٰبِ')])
        self.assertEqual(2, len(result['candidats']))
        self.assertEqual('INDECIS', result['etat'])

    def test_premier_sans_majorite_ne_decide_pas(self):
        result = self.vote([self.obs(1, 'A', .4), self.obs(2, 'B', .35), self.obs(3, 'C', .25)])
        self.assertEqual('INDECIS', result['etat'])

    def test_absence_de_confiance_reste_explicite(self):
        result = self.vote([self.obs(1, 'A', None), self.obs(2, 'B')])
        self.assertEqual('INCOMPLET', result['etat'])
        self.assertEqual(1, result['exclusions']['poids_absent'])

    def test_poids_invalides_ou_revision_ambigue_signales(self):
        for poids in (float('nan'), float('inf'), -.1, 1.1):
            with self.assertRaises(ValueError):
                self.vote([self.obs(1, poids=poids)])
        with self.assertRaises(ValueError):
            self.vote([self.obs(1), self.obs(1, 'B')])


if __name__ == '__main__':
    unittest.main()
