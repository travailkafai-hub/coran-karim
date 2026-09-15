"""Lit les votes calcules par Kotlin ; ne simule pas les observations absentes.

Les hypotheses du vote experimental sont distinctes des statuts emis par
l'app. Un changement d'hypothese n'est jamais compte comme un gain de detection.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re

from analyser_100x20 import events


def charger(dossier: Path):
    m = json.loads((dossier/'manifest.json').read_text(encoding='utf-8'))
    runs = {r['case_id']: r for line in (dossier/'executions.jsonl').read_text(encoding='utf-8').splitlines()
            if line.strip() for r in [json.loads(line)]}
    return m, runs


def analyser(dossier: Path, temoin: Path | None = None):
    manifest, runs = charger(dossier)
    baseline, reference_runs = charger(temoin) if temoin else (None, {})
    report = []
    md = ['# Vote entre fenetres — observations natives', '',
          'Mode de mesure : les votes ci-dessous ne pilotent pas les couleurs.',
          'Poids CTC bruts non calibres ; leurs sommes ne sont pas des probabilites de justesse.',
          'Verite de construction : manifest et PCM extrait verifies. Reecoute et balayage independant non effectues.', '']
    for case in manifest['cases']:
        run = runs[case['case_id']]
        text = Path(run['log']).read_text(encoding='utf-8')
        traces, votes = defaultdict(list), defaultdict(list)
        for n, line in enumerate(text.splitlines(), 1):
            for marqueur, target in [('[vote-observation] ', traces), ('[vote-resultat] ', votes)]:
                if marqueur in line:
                    payload = json.loads(line.split(marqueur, 1)[1])  # trace tronquee = erreur explicite
                    if payload['schema'] != 1 or payload['mode'] != 'observation':
                        raise ValueError('Schema ou mode non pris en charge')
                    target[payload['mot']].append(dict(payload, ligne=n))
        if not traces:
            raise ValueError('Aucune observation du vote : mauvais binaire ou instrumentation inactive')
        ev, mismatches = events(text, case['expected_words'])
        if mismatches:
            raise ValueError(f'Cible native differente du manifeste : {mismatches}')
        comparison = None
        if baseline:
            bcase = next(c for c in baseline['cases'] if c['case_id'] == case['case_id'])
            if bcase['sha256'] != case['sha256'] or bcase['expected_words'] != case['expected_words']:
                raise ValueError('A/B exige le meme WAV et la meme cible')
            ref_text = Path(reference_runs[case['case_id']]['log']).read_text(encoding='utf-8')
            ref_events, ref_mismatches = events(ref_text, bcase['expected_words'])
            if ref_mismatches:
                raise ValueError('Cible du temoin incoherente')
            differences = []
            for i in range(len(case['expected_words'])):
                a = [e['status'] for e in ref_events[i]]
                b = [e['status'] for e in ev[i]]
                if a != b:
                    differences.append(dict(mot=i, temoin=a, mesure=b))
            comparison = dict(meme_wav=True, differences_statuts=differences,
                              apk_temoin=reference_runs[case['case_id']]['apk_sha256'],
                              apk_mesure=run['apk_sha256'])
        modifications = defaultdict(list)
        for op in case['operations']:
            for i in op['affected_word_indices']:
                modifications[i].append(op)
        words = []
        for i, attendu in enumerate(case['expected_words']):
            words.append(dict(mot=i, attendu=attendu, mutations=modifications[i],
                              evenements_app=ev[i], observations=traces[i], votes=votes[i]))
        last = {i: es[-1]['status'] for i, es in ev.items() if es}
        counts = Counter(last.values())
        counts['non_juge'] = len(words)-len(last)
        summary = dict(case=case['case_id'], session_closed=run['session_closed'],
                       status_execution=run['status'], nb_mots=len(words), statuts=dict(counts),
                       nb_observations=sum(map(len, traces.values())),
                       nb_votes=sum(map(len, votes.values())),
                       decrochages=run.get('decrochage_signals'),
                       correction_audio=run.get('correction_audio_events'),
                       comparaison=comparison, mots=words)
        report.append(summary)
        md += [f'## {case["case_id"]} — {case.get("extrait", {}).get("target_verse", "")}', '',
               f'Execution : `{run["status"]}` ; fermeture journalisee : `{run["session_closed"]}`.',
               f'Total : {len(words)} mots ; {summary["nb_observations"]} observations ; {summary["nb_votes"]} calculs du vote.', '',
               '| mot | attendu | derniere lecture tracee | statut app | observations | etat vote | hypothese retenue |',
               '|---:|---|---|---|---:|---|---|']
        for w in words:
            i = w['mot']
            v = votes[i][-1] if votes[i] else {}
            heard = traces[i][-1]['entendu'] if traces[i] else '(aucune)'
            md.append(f'| {i} | {w["attendu"]} | {heard} | {last.get(i, "non_juge")} | '
                      f'{len(traces[i])} | {v.get("etat", "aucun")} | {v.get("gagnant") or "doute/absence"} |')
        md += ['', 'Les statuts du tableau viennent exclusivement de `[V2] mot=`. La derniere lecture tracee ne justifie pas a elle seule ce statut.', '']
        if comparison:
            md += [f'Differences de suites de statuts A/B : {len(comparison["differences_statuts"])} / {len(words)} mots.',
                   '```json', json.dumps(comparison, ensure_ascii=False, indent=2), '```', '']
        for i in sorted(modifications):
            md += [f'### Mot mute {i} : {case["expected_words"][i]}', '',
                   '```json', json.dumps(modifications[i], ensure_ascii=False, indent=2), '```', '',
                   '| fenetre | entendu | poids brut | interieur | exclusion | audio debut/fin (ech.) |',
                   '|---:|---|---:|---|---|---|']
            for o in traces[i]:
                poids = '-' if o['poids'] is None else f'{o["poids"]:.6f}'
                md.append(f'| {o["fenetre"]} | {o["entendu"] or "(vide)"} | {poids} | {o["interieur"]} | '
                          f'{o["exclusion"] or "admissible"} | {o["debut"]}/{o["fin"]} |')
            md += ['', 'Calculs successifs du Kotlin :', '', '```json',
                   json.dumps(votes[i], ensure_ascii=False, indent=2), '```', '']
    (dossier/'OBSERVATIONS_VOTE.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    (dossier/'OBSERVATIONS_VOTE.md').write_text('\n'.join(md), encoding='utf-8')
    return [{k: v for k, v in r.items() if k != 'mots'} for r in report]


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('dossier', type=Path)
    p.add_argument('--temoin', type=Path)
    a = p.parse_args()
    print(json.dumps(analyser(a.dossier, a.temoin), ensure_ascii=False, indent=2))
