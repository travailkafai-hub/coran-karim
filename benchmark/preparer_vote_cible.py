"""Extrait un verset en echec et son contexte immediat, sans resynthese audio.

Le contexte change par rapport aux 20 versets : rejouer le MEME extrait sur
l'APK temoin puis l'APK mesure. Ne pas annoncer une comparaison identique avec
l'ancienne campagne complete. Aucun lancement des 100 cas.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'benchmark/campagne_100x20_dense30'


def preparer(case_id: str, mot: int, out: Path, contexte: int = 1) -> dict:
    manifest = json.loads((SOURCE / 'manifest.json').read_text(encoding='utf-8'))
    source = next(c for c in manifest['cases'] if c['case_id'] == case_id)
    timeline = source['timeline']
    cible = next(i for i, t in enumerate(timeline)
                 if t['word_start'] <= mot < t['word_start'] + t['word_count'])
    mutations = [o for o in source['operations'] if mot in o['affected_word_indices']]
    if not mutations:
        raise ValueError('Le mot cible doit etre une mutation du manifest')
    if contexte < 0:
        raise ValueError('Contexte negatif')
    lo, hi = max(0, cible-contexte), min(len(timeline), cible+contexte+1)
    selected = timeline[lo:hi]
    word_lo = selected[0]['word_start']
    word_hi = selected[-1]['word_start'] + selected[-1]['word_count']
    original = Path(source['wav'])
    if hashlib.sha256(original.read_bytes()).hexdigest() != source['sha256']:
        raise ValueError('WAV source modifie')
    with wave.open(str(original), 'rb') as f:
        params = f.getparams()
        start = round(selected[0]['start_ms'] * f.getframerate() / 1000)
        end = round(timeline[hi]['start_ms'] * f.getframerate() / 1000) if hi < len(timeline) else f.getnframes()
        f.setpos(start)
        pcm = f.readframes(end-start)
    out.mkdir(parents=True, exist_ok=True)
    if (out/'manifest.json').exists() or (out/'cible.wav').exists():
        raise ValueError('Sortie deja preparee ; choisir un nouveau dossier')
    wav = out/'cible.wav'
    with wave.open(str(wav), 'wb') as f:
        f.setparams(params)
        f.writeframes(pcm)
    # Verification byte a byte du PCM extrait, jamais simple confiance au nom.
    with wave.open(str(wav), 'rb') as f:
        assert f.getnframes() == end-start and f.readframes(f.getnframes()) == pcm
    offset_ms = start * 1000 / params.framerate
    c = copy.deepcopy(source)
    c.update(depart=int(selected[0]['verse'].split(':')[1]), verse_count=len(selected),
             duration_seconds=(end-start)/params.framerate, wav=str(wav.resolve()),
             sha256=hashlib.sha256(wav.read_bytes()).hexdigest(),
             expected_words=source['expected_words'][word_lo:word_hi])
    c['timeline'] = [dict(t, start_ms=t['start_ms']-offset_ms, word_start=t['word_start']-word_lo)
                     for t in selected]
    verses = {t['verse'] for t in selected}
    c['sources'] = [s for s in source['sources'] if s['key'] in verses]
    c['operations'] = []
    for o in source['operations']:
        if o['verse'] in verses:
            edit = copy.deepcopy(o)
            edit['affected_word_indices'] = [i-word_lo for i in o['affected_word_indices']]
            edit['output_edit_start_ms'] -= offset_ms
            c['operations'].append(edit)
    c['extrait'] = dict(source_case=case_id, source_sha256=source['sha256'],
                        source_start_sample=start, source_end_sample=end,
                        source_word_start=word_lo, source_target_word=mot,
                        target_word=mot-word_lo, target_verse=timeline[cible]['verse'],
                        contexte_versets=contexte, pcm_sha256=hashlib.sha256(pcm).hexdigest())
    result = dict(seed=manifest['seed'], cases=[c], limitations=manifest['limitations'] + [
        'Extrait ciblant une mutation ; contexte immediat conserve pour le modele.',
        'Le contexte differe du run 20 versets. Comparaison A/B sur cet extrait uniquement.',
        'Vote en observation : les hypotheses ne sont pas des statuts de detection.',
    ])
    (out/'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return c


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--case', required=True)
    p.add_argument('--mot', required=True, type=int)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--contexte', type=int, default=1)
    a = p.parse_args()
    c = preparer(a.case, a.mot, a.out.resolve(), a.contexte)
    print(json.dumps(dict(case=c['case_id'], extrait=c['extrait'], duree=c['duration_seconds'],
                         versets=c['verse_count'], wav=c['wav']), ensure_ascii=False, indent=2))
