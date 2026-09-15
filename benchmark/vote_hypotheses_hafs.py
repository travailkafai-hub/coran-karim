"""Prototype de vote, hors application : aucun statut V2 n'est produit.

Les poids sont FOURNIS par l'appelant. Les exemples utilisent des valeurs
fictives ; ce module n'est ni un estimateur de confiance ni une calibration.
Le texte attendu ne participe jamais au vote. Une majorité de poids n'est
pas une probabilité que le mot soit correct.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
import math
from pathlib import Path


@dataclass(frozen=True)
class Observation:
    tentative: str
    mot: int
    prononciation: str
    fenetre: int
    texte: str
    poids: float | None
    revision: int = 0
    interieur: bool = True
    creneau_propre: bool = True
    intervalle_complet: bool = True


def voter(observations: list[Observation], *, tentative: str, mot: int,
          prononciation: str, lecture_terminee: bool) -> dict:
    """Compare les lectures d'UNE occurrence audio dans UNE tentative.

    `prononciation` est un identifiant fourni par le banc, pas une détection
    automatique des répétitions. Pour une fenêtre réanalysée, seule sa dernière
    révision existe dans le vote. Des fenêtres distinctes peuvent recouvrir
    le même son : leurs votes ne sont pas statistiquement indépendants.
    """
    par_fenetre: dict[int, Observation] = {}
    for obs in observations:
        if (obs.tentative, obs.mot, obs.prononciation) != (tentative, mot, prononciation):
            continue
        if obs.poids is not None and (not math.isfinite(obs.poids) or not 0 <= obs.poids <= 1):
            raise ValueError('Un poids fourni doit être fini, entre 0 et 1.')
        ancienne = par_fenetre.get(obs.fenetre)
        if ancienne is not None and obs.revision == ancienne.revision and obs != ancienne:
            raise ValueError('Deux observations différentes portent la même fenêtre et révision.')
        if ancienne is None or obs.revision > ancienne.revision:
            par_fenetre[obs.fenetre] = obs

    poids = defaultdict(list)
    fenetres = defaultdict(list)
    exclusions = defaultdict(int)
    for obs in sorted(par_fenetre.values(), key=lambda o: o.fenetre):
        if not (obs.interieur and obs.creneau_propre and obs.intervalle_complet) or not obs.texte.strip():
            exclusions['preuve_inexploitable'] += 1
        elif obs.poids is None:
            exclusions['poids_absent'] += 1
        elif obs.poids == 0:
            exclusions['poids_nul'] += 1
        else:
            # Aucun retrait de harakat, aucune fusion de lettres proches.
            poids[obs.texte].append(obs.poids)
            fenetres[obs.texte].append(obs.fenetre)
    scores = {texte: math.fsum(valeurs) for texte, valeurs in poids.items()}
    classes = sorted(scores, key=lambda texte: (-scores[texte], texte))
    total = math.fsum(scores.values())
    premier = classes[0] if classes else None
    score_premier = scores[premier] if premier is not None else 0.0
    opposition = math.fsum(scores[texte] for texte in classes[1:])
    majoritaire = (score_premier > opposition and
                   not math.isclose(score_premier, opposition, rel_tol=1e-12, abs_tol=1e-12))
    gagnant = premier if majoritaire else None
    # Une observation de poids inconnu peut modifier le gagnant : ne pas
    # présenter le vote partiel comme une comparaison achevée.
    incomplet = exclusions['poids_absent'] > 0
    etat = ('INCOMPLET' if incomplet else 'INDECIS' if gagnant is None else
            'HYPOTHESE_A_EVALUER' if lecture_terminee else 'PROVISOIRE')
    return {
        'etat': etat,
        'hypothese_majoritaire_des_poids_connus': gagnant,
        'candidats': [{'texte': texte, 'poids_cumule': scores[texte],
                       'fenetres': fenetres[texte]} for texte in classes],
        'poids_total': total,
        'part_du_premier': score_premier / total if total else None,
        'avance_sur_toute_opposition': score_premier - opposition,
        'exclusions': dict(exclusions),
        'statut_app': None,
    }


def analyser(entree: dict) -> dict:
    if entree.get('riwaya') != 'hafs':
        raise ValueError('Ce prototype est limité au banc Hafs.')
    return voter([Observation(**o) for o in entree['observations']],
                 **entree['cible'], lecture_terminee=entree['lecture_terminee'])


def demonstrations() -> list[dict]:
    cas = [
        ('Deux A solides contre un B de même poids', [('A', .8), ('A', .8), ('B', .8)], True),
        ('Un B solide contre A et C incertains', [('A', .2), ('B', .9), ('C', .1)], True),
        ('B seul alors que les fenêtres arrivent encore', [('B', .9)], False),
        ('Deux lectures aussi soutenues', [('A', .8), ('B', .8)], True),
    ]
    return [dict(exemple=nom, poids_fictifs=True, attendu='B', resultat=voter(
        [Observation('t1', 0, 'p1', i, texte, poids) for i, (texte, poids) in enumerate(seq)],
        tentative='t1', mot=0, prononciation='p1', lecture_terminee=terminee,
    )) for nom, seq, terminee in cas]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    choix = parser.add_mutually_exclusive_group(required=True)
    choix.add_argument('--demo', action='store_true')
    choix.add_argument('--entree', type=Path)
    parser.add_argument('--sortie', type=Path)
    args = parser.parse_args()
    resultat = demonstrations() if args.demo else analyser(json.loads(args.entree.read_text(encoding='utf-8')))
    rendu = json.dumps(resultat, ensure_ascii=False, indent=2) + '\n'
    if args.sortie:
        args.sortie.write_text(rendu, encoding='utf-8')
    else:
        print(rendu, end='')


if __name__ == '__main__':
    main()
