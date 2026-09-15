"""Passage fixe 78:1-20, Al-Afasy, cinq erreurs espacees; sources QF archivees."""
import json
from pathlib import Path
import campagne_hafs_qf as q

OUT = q.ROOT / 'benchmark' / 'replay_20_versets_erreurs'
OUT.mkdir(parents=True, exist_ok=True)
response = q.request_json('/verses/by_chapter/78', {'fields': 'text_uthmani', 'per_page': 50})
(OUT / 'texte_api.json').write_text(json.dumps(response, ensure_ascii=False), encoding='utf-8')
verses = {v['verse_number']: v for v in response['verses']}
plan = {4: 'omission', 8: 'substitution', 12: 'insertion', 16: 'permutation', 19: 'truncation'}
records = []
for n in range(1, 21):
    print(f'Source 78:{n}', flush=True)
    meta = q.api_audio_for(7, f'78:{n}')
    (OUT / f'source_{n}.json').write_text(json.dumps(meta), encoding='utf-8')
    mp3, wav = OUT / f'source_{n}.mp3', OUT / f'source_{n}.wav'
    q.download(q.audio_url(meta['url']), mp3)
    q.ensure_wav(mp3, wav)
    words = q.word_texts(verses[n]['text_uthmani'])
    assert len(words) == len(meta['segments']), (n, words, meta['segments'])
    samples = q.read_wav(wav)
    for seg in meta['segments']:
        assert 0 <= seg[2] < seg[3] and seg[2] * 16 < len(samples), (n, seg)
    records.append(dict(n=n, words=words, samples=samples, meta=meta, sha256=q.sha256(mp3)))
audio, clean, manifest = [], [], []
donor = records[0]
donor_clip = q.segment_samples(donor['samples'], donor['meta']['segments'][0])
for rec in records:
    n, samples, segs = rec['n'], rec['samples'], rec['meta']['segments']
    changed = samples[:]
    family = plan.get(n, 'correct_original')
    operation = dict(family=family)
    if n in plan:
        i = min(1, len(segs)-2) if family == 'permutation' else 1
        start, end = int(segs[i][2] * 16), min(len(samples), int(segs[i][3] * 16))
        clip = samples[start:end]
        replacement = []
        operation.update(word_index=i, expected=rec['words'][i], source_start_ms=segs[i][2], source_end_ms=segs[i][3])
        if family == 'substitution':
            assert rec['words'][i] != donor['words'][0]
            replacement = donor_clip
            operation.update(present=donor['words'][0], donor='78:1', donor_word_index=0)
        elif family == 'insertion':
            replacement = donor_clip + q.silence(40) + clip
            operation.update(inserted=donor['words'][0], donor='78:1', donor_word_index=0)
        elif family == 'permutation':
            next_start = int(segs[i+1][2] * 16)
            next_end = min(len(samples), int(segs[i+1][3] * 16))
            replacement = samples[next_start:next_end] + samples[end:next_start] + clip
            end = next_end
            operation.update(second_word_index=i+1)
        elif family == 'truncation':
            replacement = clip[:int(len(clip)*0.45)]
            operation.update(kept_ratio=0.45)
        changed = samples[:start] + replacement + samples[end:]
    manifest.append(dict(verse=f'78:{n}', expected_words=rec['words'], operation=operation,
                         start_ms=round(len(audio)/16), duration_ms=round(len(changed)/16),
                         source_url=q.audio_url(rec['meta']['url']), source_sha256=rec['sha256']))
    audio.extend(changed + q.silence(350))
    clean.extend(samples + q.silence(350))
q.write_wav(OUT / '20_versets_erreurs.wav', audio)
q.write_wav(OUT / '20_versets_temoin.wav', clean)
result = dict(surah=78, depart=1, versets=20, reciter='Al-Afasy', riwaya='Hafs', errors=5,
              duration_seconds=len(audio)/16000, wav_sha256=q.sha256(OUT/'20_versets_erreurs.wav'),
              note='Erreurs synthetiques; frontieres API, sans validation humaine des decoupes.', cases=manifest)
(OUT/'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k != 'cases'}, ensure_ascii=False), flush=True)
