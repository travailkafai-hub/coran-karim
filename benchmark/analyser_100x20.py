"""Audit emitted V2 judgments against independently constructed edit indices.

Reports engine events, not a claim that every event was rendered by Flutter.
"""
import csv
import json
from pathlib import Path
import re
import unicodedata
from collections import Counter, defaultdict
from campagne_100x20 import OUT, save

EVENT = re.compile(r'\[V2\] mot=(\d+) "([^"]*)" -> ([^\s|]+)\s*\|([^\n]*)')
NEGATIVE = {
    'definitif:rouge', 'provisoire:rouge',
    'definitif:orange', 'provisoire:orange',
    'omis', 'deplace',
}

def norm(word):
    return ''.join(c for c in unicodedata.normalize('NFKD',word)
                   if unicodedata.category(c)[0] != 'M' and c != '\u0640').replace('ٱ','ا')

def events(text, expected):
    result = defaultdict(list)
    mismatches = []
    for m in EVENT.finditer(text):
        i, word, status, trace = int(m[1]), m[2], m[3], m[4]
        if i >= len(expected):
            continue
        if norm(word) != norm(expected[i]):
            mismatches.append(dict(index=i, expected=expected[i], logged=word))
            continue
        result[i].append(dict(status=status, trace=trace, line=text.count('\n',0,m.start())+1))
    return result, mismatches

def first_repeat_line(text):
    markers = ('DECROCHAGE', 'wordFailed déclenché', 'Correction-Audio')
    positions = [text[:text.find(marker)].count('\n') + 1
                 for marker in markers if marker in text]
    return min(positions) if positions else None

def session_closed(text, recorded=False):
    """The archive line may contain a numeric id (``session 80 fermee``)."""
    return recorded or bool(re.search(r'\bsession(?:\s+\d+)?\s+fermee\b', text, re.I))

def repeat_marker_count(text):
    """Count native control/repetition markers in UTF-8 and legacy logs."""
    return len(re.findall(
        r'\[CTL\]\[(?:Decrochage|Correction)\]|ANCRE RECULEE|'
        r'Correction-Audio|le recitant peut repeter|reprise demand(?:ee|ée)|'
        r'wordFailed (?:declenche|déclench)', text, re.I))

def main():
    manifest = json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
    executions = {}
    path = OUT/'executions.jsonl'
    if path.exists():
        for line in path.read_text(encoding='utf-8').splitlines():
            r = json.loads(line)
            executions[r['case_id']] = r
    details, rows, controls, audits = [], [], [], []
    for case in manifest['cases']:
        run = executions.get(case['case_id'])
        if not run:
            continue
        final_text = Path(run['log']).read_text(encoding='utf-8')
        before = Path(run['before_close_log']).read_text(encoding='utf-8')
        # Closing the screen can truncate/rebase DiagnosticLog.  The snapshot
        # taken immediately before BACK is the authoritative session stream
        # whenever it contains the recipe boundary.
        text = before if 'versets=20/' in before and 'borner=true' in before else final_text
        decrochage_count = len(re.findall(r'\[v2\].*\bDECROCHAGE\b', text))
        repeat_count = repeat_marker_count(text)
        history, mismatches = events(text, case['expected_words'])
        live, _ = events(before, case['expected_words'])
        repeat_line = first_repeat_line(text)
        audits.append(dict(case_id=case['case_id'],status=run['status'],
                           closed=session_closed(final_text + '\n' + text, run.get('session_closed', False)),
                           decrochage_signals=decrochage_count,
                           repeat_requests=repeat_count,
                           first_repeat_line=repeat_line,
                           mapping_mismatches=mismatches, judged_indices=len(history),
                           expected_indices=len(case['expected_words'])))
        for op in case['operations']:
            indices = op['affected_word_indices']
            states = [history[i][-1]['status'] if history[i] else 'no_verdict' for i in indices]
            pre_history = defaultdict(list)
            for index, observations in history.items():
                pre_history[index] = ([x for x in observations
                                       if repeat_line is None or x['line'] < repeat_line])
            pre_states = [pre_history[i][-1]['status'] if pre_history[i] else 'no_verdict'
                          for i in indices]
            live_states = [live[i][-1]['status'] if live[i] else 'no_verdict' for i in indices]
            proxy = op['family'] == 'insertion'
            row = dict(case_id=case['case_id'],scenario_family=case['family'],family=op['family'],
                       verse=op['verse'],indices=indices,states=states,live_states=live_states,
                       pre_repeat_states=pre_states,
                       after_repeat_request=repeat_line is not None and any(
                           any(e['line'] >= repeat_line for e in history[i]) for i in indices),
                       any_negative=any(s in NEGATIVE for s in states),
                       all_green=all(s=='definitif:vert' for s in states),
                       no_verdict=any(s=='no_verdict' for s in states),insertion_proxy_only=proxy,
                       trace=[dict(index=i,events=history[i]) for i in indices],log=run['log'])
            details.append(row)
            rows.append({k:v for k,v in row.items() if k != 'trace'})
        changed_verses = {op['verse'] for op in case['operations']}
        for passage in case['timeline']:
            if passage['verse'] in changed_verses:
                continue
            for i in range(passage['word_start'],passage['word_start']+passage['word_count']):
                status = history[i][-1]['status'] if history[i] else 'no_verdict'
                controls.append(dict(case_id=case['case_id'],verse=passage['verse'],index=i,status=status))
    save(OUT/'analysis_details.json',dict(audits=audits,errors=details,unaltered_words=controls))
    if rows:
        with (OUT/'error_outcomes.csv').open('w',encoding='utf-8-sig',newline='') as f:
            writer = csv.DictWriter(f,fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    grouped = defaultdict(Counter)
    for row in details:
        group = grouped[row['family']]
        group['operations'] += 1
        for field in ['any_negative','all_green','no_verdict']:
            group[field] += int(row[field])
    report = ['# Campagne 100 x 20 — résultats observés', '',
              f'Exécutions enregistrées : {len(executions)}/100. Fin audio confirmée : {sum(r["status"]=="AUDIO_FINISHED" for r in executions.values())}.',
              f'Clôtures de session confirmées : {sum(a["closed"] for a in audits)}. Cas avec incohérence d’index/texte : {sum(bool(a["mapping_mismatches"]) for a in audits)}.', '',
              f'Signaux de décrochage : {sum(a["decrochage_signals"] for a in audits)}. Demandes/reprises automatiques : {sum(a["repeat_requests"] for a in audits)}.', '',
              f'Cas avec demande de reprise : {sum(a["first_repeat_line"] is not None for a in audits)}. Les événements après cette ligne sont marqués `after_repeat_request` et ne doivent pas servir à conclure sur la faute originale.', '',
              'Mesure des événements V2 journalisés. Les captures d’écran sont conservées séparément. Une fin audio ne prouve pas une détection.', '',
              '| Famille | Transformations | Au moins un signal négatif | Tous les mots concernés verts définitifs | Au moins un mot sans verdict |',
              '|---|---:|---:|---:|---:|']
    for family, c in sorted(grouped.items()):
        report.append(f'| {family} | {c["operations"]} | {c["any_negative"]} | {c["all_green"]} | {c["no_verdict"]} |')
    report += ['', 'Les insertions n’ont pas de mot attendu correspondant : les signaux au voisinage sont des indicateurs, pas un taux de détection des insertions.',
               'Les signaux sur les versets intacts peuvent provenir d’un désalignement après une erreur antérieure. Ce ne sont pas des faux positifs indépendants.',
               'Les montages utilisent les frontières API et ne sont pas validés à l’écoute. Ils ne mesurent pas des erreurs phonétiques humaines ni la qualité du tajwid.', '',
               '## Versets intacts dans les passages modifiés', '',str(dict(Counter(c['status'] for c in controls))), '',
               'Les pistes d’amélioration déduites de cette série sont dans `benchmark/PISTES_AMELIORATION_CAMPAGNE_DENSE30.md`.']
    (OUT/'RESULTATS.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
    print('\n'.join(report[:6]))

if __name__ == '__main__': main()
