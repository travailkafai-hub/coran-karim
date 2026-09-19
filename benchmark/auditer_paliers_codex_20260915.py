"""Verifie les trois campagnes depuis leurs statuts app, sans rejuger l'audio.

Les oranges, rouges, omissions et deplacements restent separes. Les insertions
sont des proxies exclus du rappel sur mutations. Comparaison sur indices communs;
un meme nombre de verdicts ne prouve pas des observations natives identiques.
"""
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MODES = {
    'temoin': 'campagne_paliers_temoin_20260915',
    'vote': 'campagne_paliers_vote_seul_20260915',
    'vote_t3': 'campagne_paliers_20260915',
}
EVENT = re.compile(r'\[V2\] mot=(\d+) "([^"]*)" -> ([^\s|]+)\s*\|([^\n]*)')
VERT = {'definitif:vert', 'provisoire:vert'}
NEGATIFS = {'definitif:rouge', 'provisoire:rouge', 'definitif:orange',
            'provisoire:orange', 'omis', 'deplace'}
CHAMPS_OBSERVATION = ['mot', 'fenetre', 'tentative', 'entendu', 'gop', 'forced',
    'free', 'frames', 'interieur', 'couvert', 'sans_creneau', 'atteste', 'debut',
    'fin', 'fenetre_debut', 'fenetre_fin', 'poids', 'exclusion']


def lire(mode):
    dossier = ROOT / MODES[mode]
    manifest = json.loads((dossier/'manifest.json').read_text(encoding='utf-8'))
    executions = {j['case_id']: j for j in map(json.loads,
        (dossier/'executions.jsonl').read_text(encoding='utf-8').splitlines())}
    runs = {}
    for cas in manifest['cases']:
        run = executions[cas['case_id']]
        texte = Path(run['log']).read_text(encoding='utf-8')
        hist = {}
        for m in EVENT.finditer(texte):
            i = int(m[1])
            if i >= len(cas['expected_words']):
                raise ValueError(f"Verdict hors cible: {mode}/{cas['case_id']}/{i}")
            hist[i] = dict(statut=m[3], mot=m[2], trace=m[4])
        observations, jugements = [], []
        for ligne in texte.splitlines():
            if '[vote-observation] ' in ligne:
                observations.append(json.loads(ligne.split('[vote-observation] ', 1)[1]))
            if '[t3-jugement] ' in ligne:
                jugements.append(json.loads(ligne.split('[t3-jugement] ', 1)[1]))
        signatures = [{k: o.get(k) for k in CHAMPS_OBSERVATION} for o in observations]
        runs[cas['case_id']] = dict(cas=cas, hist=hist, observations=observations,
            jugements=jugements, log=run['log'], apk_sha256=run['apk_sha256'],
            signature_observations=hashlib.sha256(json.dumps(signatures,
                sort_keys=True, ensure_ascii=False).encode()).hexdigest())
    return runs


def compter(run, indices, separer_insertions=True):
    edits = {i: o for o in run['cas']['operations'] for i in o['affected_word_indices']}
    compte = Counter()
    for i in indices:
        h = run['hist'].get(i)
        if h is None:
            compte['sans_verdict'] += 1
            continue
        op = edits.get(i)
        groupe = ('insertion_proxy' if separer_insertions and op and op['family'] == 'insertion'
                  else 'mutation' if op else 'correct')
        compte[groupe+'_total'] += 1
        compte[groupe+'_signales'] += h['statut'] in NEGATIFS
        compte[groupe+'_'+h['statut']] += 1
    for groupe in ['correct', 'mutation', 'insertion_proxy']:
        n = compte[groupe+'_total']
        if n:
            compte[groupe+'_taux_signalement'] = compte[groupe+'_signales']/n
    return dict(compte)


def main():
    runs = {mode: lire(mode) for mode in MODES}
    rapport = {'limites': [
        'Verite des constructions du manifest, pas reecoute independante des WAV.',
        'Dernier statut app; provisoire vert distinct du definitif vert dans les details.',
        'Un signalement inclut le doute orange; ne pas le nommer accusation rouge.',
        'Les logits et poids sont des signaux bruts, pas des probabilites calibrees.',
    ], 'cas': []}
    for cid in runs['temoin']:
        rs = {mode: runs[mode][cid] for mode in MODES}
        assert len({r['cas']['sha256'] for r in rs.values()}) == 1, 'WAV differents'
        assert all(r['cas']['expected_words'] == rs['temoin']['cas']['expected_words']
                   and r['cas']['operations'] == rs['temoin']['cas']['operations']
                   for r in rs.values()), 'Cibles ou montages differents'
        communs = set.intersection(*(set(r['hist']) for r in rs.values()))
        c = dict(case_id=cid, palier=rs['temoin']['cas']['palier_pct'],
            communs=sorted(communs), modes={})
        for mode, r in rs.items():
            c['modes'][mode] = dict(log=r['log'], apk_sha256=r['apk_sha256'],
                total_cible=len(r['cas']['expected_words']), juges=len(r['hist']),
                observations=len(r['observations']),
                signature_observations=r['signature_observations'],
                brut=compter(r, r['hist'], False),
                comparable=compter(r, communs))
        c['observations_vote_t3_identiques'] = bool(rs['vote']['observations']) and (
            rs['vote']['signature_observations'] == rs['vote_t3']['signature_observations'])
        changements = []
        for i in sorted(set(rs['vote']['hist']) & set(rs['vote_t3']['hist'])):
            avant, apres = rs['vote']['hist'][i], rs['vote_t3']['hist'][i]
            if avant['statut'] == apres['statut']:
                continue
            changements.append(dict(mot=i, attendu=rs['vote']['cas']['expected_words'][i],
                avant=avant, apres=apres,
                avis_t3=[a for a in rs['vote_t3']['jugements'] if a['mot']==i][-1:],
                observations_vote=[o for o in rs['vote']['observations'] if o['mot']==i],
                observations_t3=[o for o in rs['vote_t3']['observations'] if o['mot']==i]))
        c['changements_vote_t3'] = changements
        rapport['cas'].append(c)
        print(cid, 'communs', len(communs), 'observations identiques vote/t3',
              c['observations_vote_t3_identiques'])
        if c['palier'] == 10:
            for mode in MODES:
                print(' ', mode, c['modes'][mode]['comparable'])
    out = ROOT/'AUDIT_PALIERS_CODEX_20260915.json'
    out.write_text(json.dumps(rapport, ensure_ascii=False, indent=2), encoding='utf-8')
    print(out)


if __name__ == '__main__':
    main()
