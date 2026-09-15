"""Dense deterministic campaign focused on near-word Quranic confusions.

The first campaign used four edits per 20-verse replay. This variant keeps
the same real-time runner but builds six edits per replay (30 percent of the
20 verses), including words from other verses that differ only in harakat or
by one Arabic letter.
"""
from __future__ import annotations

import argparse
import json
import random
import unicodedata
from collections import defaultdict
from pathlib import Path

import campagne_100x20 as base

q = base.q
ROOT = q.ROOT
SOURCE_OUT = ROOT / "benchmark" / "campagne_100x20"
OUT = ROOT / "benchmark" / "campagne_100x20_dense30"
base.OUT = OUT

FAMILIES = [
    "haraka_mutation", "extra_letter", "near_word_substitution",
    "omission_word", "omission_span", "omission_2words", "insertion",
    "permutation", "truncate", "dense_mixed",
]


def strip_marks(word: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFKD", word)
        if unicodedata.category(c)[0] != "M" and c != "\u0640"
    )


def edit_distance_at_most_one(a: str, b: str) -> bool:
    if a == b or abs(len(a) - len(b)) > 1:
        return False
    i = j = errors = 0
    while i < len(a) and j < len(b):
        if a[i] != b[j]:
            errors += 1
            if errors > 1:
                return False
            if len(a) > len(b):
                i += 1
                continue
            if len(b) > len(a):
                j += 1
                continue
        i += 1
        j += 1
    return errors + (len(a) - i) + (len(b) - j) <= 1


def load_scenarios():
    """Reuse already downloaded Hafs source audio and API timings."""
    old = json.loads((SOURCE_OUT / "manifest.json").read_text(encoding="utf-8"))
    scenarios, seen = [], set()
    for case in old["cases"]:
        key = (case["reciter"], case["surah"], case["depart"])
        if key in seen:
            continue
        seen.add(key)
        records = []
        for source in case["sources"]:
            surah, ayah = map(int, source["key"].split(":"))
            stem = SOURCE_OUT / "sources" / f"{case['reciter']}_{surah}_{ayah}"
            meta = json.loads(stem.with_suffix(".json").read_text(encoding="utf-8"))
            samples = q.read_wav(stem.with_suffix(".wav"))
            records.append({
                "key": source["key"], "words": source["words"],
                "segments": meta["segments"], "samples": samples,
            })
        scenarios.append((case["reciter"], case["surah"], case["depart"], records))
    if len(scenarios) != 10:
        raise RuntimeError(f"expected 10 source scenarios, got {len(scenarios)}")
    return scenarios


def make_pool(scenarios):
    pool = []
    for reciter, _, _, records in scenarios:
        for record in records:
            for index, word in enumerate(record["words"]):
                pool.append({"reciter": reciter, "record": record, "index": index, "word": word})
    return pool


def donor_for(target, pool, family, rng):
    """Find a same-voice Quranic word for the requested near confusion."""
    same_voice = [x for x in pool if x["reciter"] == target["reciter"] and x["word"] != target["word"]]
    if family == "haraka_mutation":
        candidates = [x for x in same_voice
                      if strip_marks(x["word"]) == strip_marks(target["word"])]
    elif family in ("extra_letter", "near_word_substitution"):
        candidates = [x for x in same_voice
                      if edit_distance_at_most_one(strip_marks(target["word"]), strip_marks(x["word"]))
                      and strip_marks(target["word"]) != strip_marks(x["word"])]
    else:
        candidates = same_voice
    # A target may be unique in one reciter's 20-verse passage.  Search the
    # other Hafs voice before falling back; the text candidate still comes
    # from the Quranic corpus and the recording is kept deterministic.
    if not candidates and same_voice is not pool:
        candidates = [x for x in pool if x["word"] != target["word"]]
        if family == "haraka_mutation":
            candidates = [x for x in candidates
                          if strip_marks(x["word"]) == strip_marks(target["word"])]
        elif family in ("extra_letter", "near_word_substitution"):
            candidates = [x for x in candidates
                          if edit_distance_at_most_one(strip_marks(target["word"]), strip_marks(x["word"]))
                          and strip_marks(target["word"]) != strip_marks(x["word"])]
    if not candidates:
        return None
    return rng.choice(candidates)


def clip(record, index):
    return q.segment_samples(record["samples"], record["segments"][index])


def prepare():
    scenarios = load_scenarios()
    pool = make_pool(scenarios)
    OUT.mkdir(parents=True, exist_ok=True)
    cases = []
    # Adjacent slots deliberately create two-word and three-window decrochages.
    slots = [2, 3, 6, 9, 10, 15]
    for family_index, family in enumerate(FAMILIES):
        for scenario_index, (reciter, surah, first, records) in enumerate(scenarios):
            number = family_index * 10 + scenario_index + 1
            rng = random.Random(20260914_3 + number)
            expected, audio, operations, timeline = [], [], [], []
            selected = set(slots)
            for verse_index, record in enumerate(records):
                base_index = len(expected)
                expected.extend(record["words"])
                original = record["samples"]
                changed = original[:]
                timeline.append(dict(verse=record["key"], start_ms=len(audio) / 16,
                                     word_start=base_index, word_count=len(record["words"])))
                if verse_index in selected:
                    words, segs = record["words"], record["segments"]
                    count = len(words)
                    i = rng.randrange(count)
                    actual = family
                    if family == "dense_mixed":
                        actual = rng.choice(["haraka_mutation", "extra_letter", "near_word_substitution",
                                             "omission_word", "omission_span", "insertion", "permutation"])
                    if actual in ("omission_span", "omission_2words", "permutation"):
                        i = min(i, count - 2)
                    if actual in ("haraka_mutation", "extra_letter", "near_word_substitution"):
                        eligible = [j for j, word in enumerate(words)
                                    if donor_for({"reciter": reciter, "word": word}, pool, actual, rng)]
                        if eligible:
                            i = rng.choice(eligible)
                    start = int(segs[i][2] * 16)
                    end = min(len(original), int(segs[i][3] * 16))
                    original_clip = original[start:end]
                    affected = [base_index + i]
                    replacement = []
                    donor = donor_for({"reciter": reciter, "word": words[i]}, pool, actual, rng)
                    # A target with no exact near-word donor is kept as a
                    # deterministic one-mark/one-letter audio splice rather
                    # than silently turning into a clean control.
                    if actual in ("haraka_mutation", "extra_letter", "near_word_substitution") and donor is None:
                        donor = donor_for({"reciter": reciter, "word": words[i]}, pool, "near_word_substitution", rng)
                        actual = "near_word_substitution_fallback"
                    op = dict(verse=record["key"], family=actual, word_index=i,
                              expected=words[i], affected_word_indices=affected,
                              target_normalized=strip_marks(words[i]))
                    if donor:
                        donor_clip = clip(donor["record"], donor["index"])
                        op.update(donor_verse=donor["record"]["key"], donor_word=donor["index"],
                                  replacement_text=donor["word"],
                                  replacement_normalized=strip_marks(donor["word"]))
                    if actual == "haraka_mutation" and donor:
                        replacement = donor_clip
                        op["difference"] = "same_letters_different_harakat"
                    elif actual in ("extra_letter", "near_word_substitution", "near_word_substitution_fallback") and donor:
                        replacement = donor_clip
                        op["difference"] = "one_base_letter_or_near_word"
                    elif actual == "near_word_substitution_fallback":
                        # Keep the case a real audible error even when this
                        # short passage has no corpus neighbour: duplicate a
                        # short phoneme-sized slice and document the fallback.
                        prefix = original_clip[:max(1, min(len(original_clip), int(0.08 * 16000)))]
                        replacement = prefix + q.silence(25) + original_clip
                        op["difference"] = "synthetic_extra_phoneme_fallback"
                    elif actual == "omission_span":
                        end = min(len(original), int(segs[i + 1][3] * 16))
                        affected.append(base_index + i + 1)
                        op["affected_word_indices"] = affected
                    elif actual == "omission_2words":
                        end = min(len(original), int(segs[min(i + 2, count - 1)][3] * 16))
                        affected.extend([base_index + i + 1, base_index + min(i + 2, count - 1)])
                        op["affected_word_indices"] = affected
                    elif actual == "insertion":
                        donor = donor or donor_for({"reciter": reciter, "word": words[i]}, pool, "other", rng)
                        replacement = clip(donor["record"], donor["index"]) + q.silence(35) + original_clip
                        op["evaluation"] = "inserted donor word; nearby verdicts are proxy only"
                    elif actual == "permutation":
                        second_start = int(segs[i + 1][2] * 16)
                        second_end = min(len(original), int(segs[i + 1][3] * 16))
                        replacement = original[second_start:second_end] + original[end:second_start] + original_clip
                        end = second_end
                        affected.append(base_index + i + 1)
                        op["affected_word_indices"] = affected
                    if actual not in ("haraka_mutation", "extra_letter", "near_word_substitution",
                                      "near_word_substitution_fallback", "omission_span", "omission_2words",
                                      "insertion", "permutation"):
                        replacement = original_clip[:max(1, int(len(original_clip) * 0.48))]
                        op["difference"] = "truncated_word"
                    changed = original[:start] + replacement + original[end:]
                    op.update(source_start_sample=start, source_end_sample=end,
                              replacement_samples=len(replacement),
                              output_edit_start_ms=(len(audio) + start) / 16)
                    operations.append(op)
                audio.extend(changed)
                audio.extend(q.silence(350))
            case_id = f"T{number:03d}"
            wav = OUT / "wav" / f"{case_id}.wav"
            q.write_wav(wav, audio)
            assert len(operations) == 6
            cases.append(dict(case_id=case_id, family=family, reciter=reciter, surah=surah,
                              depart=first, verse_count=20, riwaya="hafs", expected_words=expected,
                              duration_seconds=len(audio) / 16000, wav=str(wav), sha256=q.sha256(wav),
                              operations=operations, timeline=timeline,
                              sources=[dict(key=r["key"], words=r["words"]) for r in records]))
            print(f"{case_id} {family} {surah}:{first}-{first+19} {len(audio)/16000:.1f}s", flush=True)
    base.save(OUT / "manifest.json", dict(seed=20260914_3, cases=cases,
        limitations=["Six edits per replay (30 percent of the 20 verses); adjacent slots deliberately stress decrochage and repetition.",
                     "haraka_mutation uses a Quranic word with identical letters and different diacritics when available.",
                     "extra_letter and near_word_substitution use a Quranic word at base edit distance one.",
                     "Synthetic montage at API timing boundaries; it is not a human tajwid recording."]))
    print(f"PREPARED dense 100 cases, {sum(c['duration_seconds'] for c in cases)/3600:.2f} hours audio", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["prepare", "run"])
    parser.add_argument("--serial", default="R3CY20XW7TD")
    args = parser.parse_args()
    if args.action == "prepare":
        prepare()
    else:
        base.OUT = OUT
        base.run(args.serial)
