"""100 distinct deterministic 20-verse app replays. No production changes.

prepare: cached QF audio + exact edit manifests; run: real-time Android UI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess
import time
import uuid
import campagne_hafs_qf as q

OUT = q.ROOT / 'benchmark' / 'campagne_100x20'
FAMILIES = ['omission_word', 'omission_span', 'omission_verse', 'substitution',
            'insertion', 'permutation', 'truncate_head', 'truncate_tail', 'verse_swap', 'mixed']
PASSAGES = [(78, 1), (78, 21), (36, 1), (55, 1), (67, 1)]

def save(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')

def cached_json(path, fetch):
    if not path.exists():
        save(path, fetch())
    return json.loads(path.read_text(encoding='utf-8'))

def prepare():
    scenarios = []
    for reciter in [7, 6]:
        for surah, first in PASSAGES:
            text = cached_json(OUT/'sources'/f'text_{surah}.json', lambda: q.request_json(
                f'/verses/by_chapter/{surah}', {'fields':'text_uthmani', 'per_page':286}))
            verses = {v['verse_number']: v for v in text['verses']}
            records = []
            for ayah in range(first, first+20):
                key = f'{surah}:{ayah}'
                base = OUT/'sources'/f'{reciter}_{surah}_{ayah}'
                meta = cached_json(base.with_suffix('.json'), lambda: q.api_audio_for(reciter, key))
                q.download(q.audio_url(meta['url']), base.with_suffix('.mp3'))
                q.ensure_wav(base.with_suffix('.mp3'), base.with_suffix('.wav'))
                samples = q.read_wav(base.with_suffix('.wav'))
                words = q.word_texts(verses[ayah]['text_uthmani'])
                segments = meta['segments']
                assert len(words) == len(segments), (key, len(words), len(segments))
                for seg in segments:
                    assert 0 <= seg[2] < seg[3] and seg[2]*16 < len(samples), (key, seg)
                records.append(dict(key=key, words=words, segments=segments, samples=samples,
                                    source_url=q.audio_url(meta['url']), sha256=q.sha256(base.with_suffix('.mp3'))))
                print(f'source {reciter} {key}', flush=True)
            scenarios.append((reciter, surah, first, records))
    cases = []
    # Interleave families and passages, so early results cover varied errors.
    for family_index, family in enumerate(FAMILIES):
        for scenario_index, (reciter, surah, first, records) in enumerate(scenarios):
            number = family_index*10 + scenario_index + 1
            rng = random.Random(20260914 + number)
            changed_verses = sorted(rng.sample(list(range(2,18)), 4))
            audio, expected, operations, timeline = [], [], [], []
            for vi, rec in enumerate(records):
                base_index = len(expected)
                expected.extend(rec['words'])
                samples = rec['samples']
                changed = samples[:]
                actual_family = FAMILIES[(vi+scenario_index)%9] if family == 'mixed' else family
                timeline.append(dict(verse=rec['key'], start_ms=len(audio)/16,
                                     word_start=base_index, word_count=len(rec['words'])))
                if vi in changed_verses:
                    segs, words = rec['segments'], rec['words']
                    count = len(words)
                    i = rng.randrange(count)
                    if actual_family in ('omission_span', 'permutation') and count < 2:
                        actual_family = 'omission_word'
                    if actual_family in ('omission_span', 'permutation'):
                        i = rng.randrange(count-1)
                    donor = records[(vi+7)%20]
                    di = next((j for j,w in enumerate(donor['words']) if w != words[i]), None)
                    assert di is not None
                    donor_clip = q.segment_samples(donor['samples'], donor['segments'][di])
                    start = int(segs[i][2]*16)
                    end = min(len(samples), int(segs[i][3]*16))
                    clip = samples[start:end]
                    affected = [base_index+i]
                    replacement = []
                    op = dict(verse=rec['key'], family=actual_family, word_index=i,
                              expected=words[i], donor_verse=donor['key'], donor_word=di,
                              inserted_or_replacement=donor['words'][di])
                    if actual_family == 'omission_span':
                        end = min(len(samples), int(segs[i+1][3]*16))
                        affected.append(base_index+i+1)
                    elif actual_family == 'omission_verse':
                        start, end = 0, len(samples)
                        affected = list(range(base_index, base_index+count))
                    elif actual_family == 'substitution':
                        replacement = donor_clip
                    elif actual_family == 'insertion':
                        replacement = donor_clip + q.silence(40) + clip
                        op['evaluation'] = 'insertion has no expected-word counterpart; nearby alerts are only proxies'
                    elif actual_family == 'permutation':
                        second_start = int(segs[i+1][2]*16)
                        second_end = min(len(samples), int(segs[i+1][3]*16))
                        replacement = samples[second_start:second_end] + samples[end:second_start] + clip
                        end = second_end
                        affected.append(base_index+i+1)
                    elif actual_family == 'truncate_head':
                        replacement = clip[int(len(clip)*0.55):]
                    elif actual_family == 'truncate_tail':
                        replacement = clip[:int(len(clip)*0.45)]
                    elif actual_family == 'verse_swap':
                        start, end = 0, len(samples)
                        replacement = donor['samples']
                        affected = list(range(base_index, base_index+count))
                    changed = samples[:start] + replacement + samples[end:]
                    op.update(affected_word_indices=affected, source_start_sample=start,
                              source_end_sample=end, replacement_samples=len(replacement),
                              output_edit_start_ms=(len(audio)+start)/16)
                    operations.append(op)
                audio.extend(changed)
                audio.extend(q.silence(350))
            case_id = f'T{number:03d}'
            wav = OUT/'wav'/f'{case_id}.wav'
            q.write_wav(wav, audio)
            assert len(timeline) == 20 and len(operations) == 4
            cases.append(dict(case_id=case_id, family=family, reciter=reciter, surah=surah,
                              depart=first, verse_count=20, riwaya='hafs', expected_words=expected,
                              duration_seconds=len(audio)/16000, wav=str(wav), sha256=q.sha256(wav),
                              operations=operations, timeline=timeline,
                              sources=[{k:v for k,v in r.items() if k not in ('samples','segments')} for r in records]))
            print(f'{case_id} {family} {surah}:{first}-{first+19} {len(audio)/16000:.1f}s', flush=True)
    assert len(cases) == 100 and len({c['sha256'] for c in cases}) == 100
    save(OUT/'manifest.json', dict(seed=20260914, cases=cases,
         limitations=['Synthetic edits using API timings, not human-validated phonetic errors.',
                      'Hafs only; 2 reciters, 5 passages; 16 unedited verses per case serve as internal controls.',
                      'Real-time WAV injection bypasses physical microphone and room acoustics.',
                      'Insertion attribution requires separate interpretation; missing verdicts are not detections.']))
    print(f'PREPARED 100 cases, {sum(c["duration_seconds"] for c in cases)/3600:.2f} hours audio', flush=True)

def run(serial):
    manifest = json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
    total_cases = len(manifest['cases'])
    adb_path = Path(os.environ['LOCALAPPDATA'])/'Android/Sdk/platform-tools/adb.exe'
    def adb(*args, timeout=60):
        p = subprocess.run([str(adb_path), '-s', serial, *args], capture_output=True, timeout=timeout)
        if p.returncode:
            raise RuntimeError(p.stderr.decode('utf-8', errors='replace'))
        return p.stdout.decode('utf-8', errors='replace')
    def adb_optional(*args, timeout=60):
        """Best-effort UI housekeeping; Android may deny shell input events."""
        try:
            return adb(*args, timeout=timeout)
        except RuntimeError as error:
            print(f'OPTIONAL_ADB_SKIPPED {args[0:2]}: {error}', flush=True)
            return ''
    package = 'com.corankarim.coran_karim.dev'
    adb('get-state')
    remote = f'/sdcard/Android/data/{package}/files/campaign100.wav'
    journal = f'/sdcard/Android/data/{package}/files/recitation_diagnostic.log'
    apk = adb('shell', 'pm', 'path', package).splitlines()[0].removeprefix('package:').strip()
    apk_hash = adb('shell', 'sha256sum', apk).split()[0]
    envpath = OUT/'environment.json'
    if envpath.exists():
        assert json.loads(envpath.read_text())['apk_sha256'] == apk_hash, 'Installed APK changed; do not mix builds'
    else:
        save(envpath, dict(serial=serial, apk_sha256=apk_hash, apk_path=apk,
                          package_info=adb('shell','dumpsys','package',package),
                          git_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=q.ROOT,text=True).strip(),
                          manifest_sha256=q.sha256(OUT/'manifest.json')))
    results = OUT/'executions.jsonl'
    done = set()
    if results.exists():
        # Both terminal outcomes are complete executions.  A repetition case
        # must not be launched a second time when Claude resumes surveillance.
        done = {r['case_id'] for line in results.read_text().splitlines() if line.strip()
                for r in [json.loads(line)]
                if r['status'] in ('AUDIO_FINISHED', 'REQUIRES_HUMAN_REPETITION')}
    def execution_order(case):
        number = int(case['case_id'][1:])-1
        family_index, scenario_index = divmod(number,10)
        return ((scenario_index-family_index)%10, family_index)
    for case in sorted(manifest['cases'], key=execution_order):
        if case['case_id'] in done:
            continue
        verse_count = int(case.get('verse_count', 20))
        if verse_count < 1:
            raise ValueError('verse_count doit etre positif')
        assert q.sha256(Path(case['wav'])) == case['sha256']
        assert adb('shell','sha256sum',apk).split()[0] == apk_hash, 'APK changed during run'
        marker = 'C100-' + uuid.uuid4().hex
        logpath = OUT/'logs'/f'{case["case_id"]}-{marker}.log'
        logpath.parent.mkdir(exist_ok=True)
        adb('shell','am','force-stop',package)
        adb('push',case['wav'],remote)
        adb_optional('shell','input','keyevent','KEYCODE_WAKEUP')
        adb_optional('shell','wm','dismiss-keyguard')
        started = time.time()
        adb('shell','am','start','-n',f'{package}/com.corankarim.coran_karim.MainActivity',
            '--es','recette','ecoute','--ez','normal','true','--ei','sourate',str(case['surah']),
            '--ei','depart',str(case['depart']),'--ei','versets',str(verse_count),'--es','wav',remote,
            '--es','riwaya','hafs','--ez','borner','true')
        print(f'START {case["case_id"]}/{total_cases} {case["family"]} {case["duration_seconds"]:.0f}s',flush=True)
        eof_at = None
        repeat_at = None
        session = ''
        anchor = None
        while time.time()-started < case['duration_seconds']*1.5+120:
            time.sleep(5)
            raw = adb('shell','tail','-c','6000000',journal)
            # DiagnosticLog opens/truncates the file during app startup, so a
            # marker written before `am start` is not reliable. The recipe
            # line is written after the screen has accepted all extras and is
            # the authoritative session boundary.
            recipe_pos = raw.rfind('borner=true')
            if recipe_pos >= 0:
                line_start = raw.rfind('[RECETTE]', 0, recipe_pos)
                anchor = line_start if line_start >= 0 else recipe_pos
            if anchor is None:
                continue
            session = raw[anchor:]
            logpath.write_text(session,encoding='utf-8')
            if 'SOURCE DETERMINISTE : fin du fichier' in session:
                eof_at = eof_at or time.time()
            if repeat_at is None and re.search(r'\[v2\].*\bDECROCHAGE\b', session):
                repeat_at = time.time()
                print(f'REPEAT_REQUEST {case["case_id"]}: capture 10 s puis arrêt — WAV ne peut pas répondre', flush=True)
            if repeat_at and time.time()-repeat_at >= 10:
                break
            if eof_at and time.time()-eof_at >= 10:
                break
        status = ('REQUIRES_HUMAN_REPETITION' if repeat_at and not eof_at
                  else 'AUDIO_FINISHED' if eof_at else 'TIMEOUT')
        valid_mode = ('session NORMALE' in session and f'versets={verse_count}/' in session and
                      'borner=true' in session and remote in session and
                      'Enchaînement page' not in session and 'Enchainement page' not in session)
        if not valid_mode:
            status = 'INVALID_MODE'
        # Preserve the live UI evidence, then finalize through normal navigation.
        before_close_path = logpath.with_suffix('.before_close.log')
        before_close_path.write_text(session, encoding='utf-8')
        screenshot = subprocess.run([str(adb_path),'-s',serial,'exec-out','screencap','-p'],
                                    capture_output=True,timeout=30)
        if screenshot.returncode == 0 and screenshot.stdout.startswith(b'\x89PNG'):
            logpath.with_suffix('.png').write_bytes(screenshot.stdout)
        if eof_at or repeat_at:
            adb_optional('shell','input','keyevent','KEYCODE_BACK')
            time.sleep(12)
            raw = adb('shell','tail','-c','6000000',journal)
            if anchor is None:
                raise RuntimeError('Recipe session boundary lost during close')
            session = raw[anchor:]
            logpath.write_text(session,encoding='utf-8')
        decrochage_signals = len(re.findall(r'\[v2\].*\bDECROCHAGE\b', session))
        repeat_requests = (session.count('wordFailed déclenché') +
                           session.count('reprise demandee') +
                           session.count('reprise demandée') +
                           session.count('ANCRE RECULEE') +
                           session.count('le recitant peut repeter') +
                           session.count('Correction-Audio'))
        result = dict(case_id=case['case_id'],status=status,log=str(logpath),started_at=started,
                      ended_at=time.time(),apk_sha256=apk_hash,valid_mode=valid_mode,
                      before_close_log=str(before_close_path), session_closed=bool(re.search(r'\bsession(?:\s+\d+)?\s+fermee\b', session, re.I)),
                      decrochage_signals=decrochage_signals, repeat_requests=repeat_requests,
                      correction_audio_events=session.count('Correction-Audio'),
                      requires_human_repetition=(repeat_requests > 0 or repeat_at is not None))
        with results.open('a',encoding='utf-8') as f:
            f.write(json.dumps(result)+'\n')
        print(f'END {case["case_id"]} {status}',flush=True)
        if status not in ('AUDIO_FINISHED', 'REQUIRES_HUMAN_REPETITION'):
            raise RuntimeError(f'{status}: inspect evidence before resuming')
    print(f'COMPLETE {total_cases} executions; analysis still required',flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare','run'])
    parser.add_argument('--serial',default='R3CY20XW7TD')
    args = parser.parse_args()
    if args.action == 'prepare': prepare()
    else: run(args.serial)
