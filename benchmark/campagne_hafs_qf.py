#!/usr/bin/env python3
"""Prepare a deterministic Hafs test campaign from the Quran Foundation API.

This script creates 60 distinct WAV cases. It does not run the Flutter app and
does not modify any ASR rule. The app execution phase needs a connected device
and is deliberately kept separate from corpus construction.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import random
import shutil
import subprocess
import time
import urllib.parse
import urllib.request
import wave
from array import array
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "benchmark" / "campagne_hafs_qf_2026-09-13"
API = "https://api.quran.com/api/v4"
UA = "CoranKarim-ChGPT-Hafs-Campaign/1.0"
SEED = 20260913
SAMPLE_RATE = 16_000

# The Quran Foundation recitation catalogue used by the application. These
# entries are the two Hafs voices used by this campaign.
RECITERS = (
    {"id": 7, "name": "Mishary Al-Afasy", "api_name": "Alafasy"},
    {"id": 6, "name": "Mahmoud Khalil Al-Husary", "api_name": "Husary"},
)

# Eight chapters give more than the required six and provide short and long
# passages, verse boundaries, and different word shapes.
SURAHS = (1, 2, 18, 36, 55, 78, 112, 114)

FAMILIES = (
    "correct_original",
    "splice_clean",
    "omission",
    "substitution",
    "insertion",
    "permutation",
    "truncation",
    "interruption_reprise",
)


def request_json(path: str, params: dict[str, object] | None = None) -> dict:
    query = urllib.parse.urlencode(params or {})
    url = f"{API}{path}{'?' + query if query else ''}"
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    last_error = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                return json.load(response)
        except Exception as error:  # network failures are retried explicitly
            last_error = error
            if attempt < 4:
                time.sleep(2**attempt)
    raise RuntimeError(f"Quran Foundation request failed: {url}: {last_error}")


def download(url: str, destination: Path) -> None:
    if destination.exists() and destination.stat().st_size > 0:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    temporary = destination.with_suffix(destination.suffix + ".part")
    with urllib.request.urlopen(request, timeout=120) as response:
        temporary.write_bytes(response.read())
    temporary.replace(destination)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audio_url(raw: str) -> str:
    if raw.startswith("//"):
        return "https:" + raw
    if raw.startswith("http://") or raw.startswith("https://"):
        return raw
    return "https://verses.quran.foundation/" + raw.lstrip("/")


def ensure_wav(mp3: Path, wav: Path) -> None:
    if wav.exists() and wav.stat().st_size > 44:
        return
    wav.parent.mkdir(parents=True, exist_ok=True)
    temporary = wav.with_suffix(".part.wav")
    command = [
        "ffmpeg",
        "-y",
        "-loglevel",
        "error",
        "-i",
        str(mp3),
        "-ar",
        str(SAMPLE_RATE),
        "-ac",
        "1",
        "-sample_fmt",
        "s16",
        str(temporary),
    ]
    subprocess.run(command, check=True)
    temporary.replace(wav)


def read_wav(path: Path) -> list[int]:
    with wave.open(str(path), "rb") as stream:
        if stream.getframerate() != SAMPLE_RATE or stream.getnchannels() != 1:
            raise ValueError(f"unsupported WAV format: {path}")
        return list(array("h", stream.readframes(stream.getnframes())))


def write_wav(path: Path, samples: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(SAMPLE_RATE)
        stream.writeframes(array("h", samples).tobytes())


def silence(milliseconds: int) -> list[int]:
    return [0] * int(SAMPLE_RATE * milliseconds / 1000)


def join_parts(parts: list[list[int]], crossfade_ms: int = 8) -> list[int]:
    """Join word clips with a small deterministic crossfade."""
    result: list[int] = []
    overlap_limit = int(SAMPLE_RATE * crossfade_ms / 1000)
    for part in parts:
        if not part:
            continue
        if not result:
            result.extend(part)
            continue
        overlap = min(overlap_limit, len(result), len(part))
        if overlap == 0:
            result.extend(part)
            continue
        start = len(result) - overlap
        for index in range(overlap):
            left_weight = (overlap - index) / overlap
            right_weight = index / overlap
            value = int(
                result[start + index] * left_weight
                + part[index] * right_weight
            )
            result[start + index] = max(-32768, min(32767, value))
        result.extend(part[overlap:])
    return result


def word_texts(text: str) -> list[str]:
    # Quran Foundation sometimes emits a waqf sign as a separate whitespace
    # token (for example the pause sign after 18:1). Audio segments index
    # lexical words only, so discard tokens that contain no Arabic letter.
    arabic_letter = re.compile(r"[\u0621-\u063a\u0641-\u064a\u0671-\u06d3\u06fa-\u06ff]")
    return [
        word
        for word in text.strip().split()
        if word and arabic_letter.search(word)
    ]


def segment_samples(samples: list[int], segment: list[int]) -> list[int]:
    start_ms, end_ms = int(segment[2]), int(segment[3])
    start = max(0, int(start_ms * SAMPLE_RATE / 1000))
    end = min(len(samples), int(end_ms * SAMPLE_RATE / 1000))
    return samples[start:end]


def build_text_pool() -> dict[int, list[dict]]:
    pool: dict[int, list[dict]] = {}
    for surah in SURAHS:
        response = request_json(
            f"/verses/by_chapter/{surah}",
            {"fields": "text_uthmani,page_number", "per_page": 286},
        )
        verses = []
        for verse in response.get("verses", []):
            words = word_texts(verse.get("text_uthmani", ""))
            if len(words) >= 3:
                verses.append(
                    {
                        "surah": surah,
                        "ayah": int(verse["verse_number"]),
                        "key": verse["verse_key"],
                        "text": verse["text_uthmani"].strip(),
                        "words": words,
                        "page": verse.get("page_number"),
                    }
                )
        pool[surah] = verses
    return pool


def flatten_pool(pool: dict[int, list[dict]]) -> list[dict]:
    result = []
    for surah in SURAHS:
        result.extend(pool[surah])
    return result


def choose_targets(pool: dict[int, list[dict]]) -> list[dict]:
    all_verses = flatten_pool(pool)
    if len(all_verses) < 30:
        raise RuntimeError("not enough verse candidates")
    # Round-robin chapters first, then fill from the complete pool. This keeps
    # at least six chapters represented even when one API page is unavailable.
    by_reciter = []
    for offset, reciter in enumerate(RECITERS):
        selected = []
        chapter_index = 0
        while len(selected) < 30:
            chapter = SURAHS[(chapter_index + offset) % len(SURAHS)]
            candidates = pool[chapter]
            if candidates:
                candidate = candidates[(chapter_index // len(SURAHS)) % len(candidates)]
                if candidate not in selected:
                    selected.append(candidate)
            chapter_index += 1
            if chapter_index > 5000:
                break
        if len(selected) < 30:
            for candidate in all_verses:
                if candidate not in selected:
                    selected.append(candidate)
                if len(selected) == 30:
                    break
        by_reciter.append(selected[:30])
    return [
        {"reciter": RECITERS[index % 2], "verse": by_reciter[index % 2][index // 2]}
        for index in range(60)
    ]


def case_family(index: int) -> str:
    if index < 20:
        return "correct_original"
    if index < 30:
        return "splice_clean"
    transformed = ("omission", "substitution", "insertion", "permutation", "truncation", "interruption_reprise")
    return transformed[(index - 30) % len(transformed)]


def make_split_and_replay(cases: list[dict]) -> None:
    heldout_limits = {
        "correct_original": 6,
        "splice_clean": 3,
        "omission": 2,
        "substitution": 2,
        "insertion": 2,
        "permutation": 2,
        "truncation": 2,
        "interruption_reprise": 1,
    }
    used = {family: 0 for family in heldout_limits}
    for case in cases:
        family = case["famille"]
        if used[family] < heldout_limits[family]:
            case["split"] = "heldout"
            used[family] += 1
        else:
            case["split"] = "development"

    # Ten stratified representatives: two clean originals, two clean splices,
    # then one from each transformed family. They are run three times total.
    wanted = {
        "correct_original": 2,
        "splice_clean": 2,
        "omission": 1,
        "substitution": 1,
        "insertion": 1,
        "permutation": 1,
        "truncation": 1,
        "interruption_reprise": 1,
    }
    selected = []
    for family, count in wanted.items():
        selected.extend([case for case in cases if case["famille"] == family][:count])
    for case in cases:
        case["representatif"] = case in selected


def api_audio_for(reciter_id: int, verse_key: str) -> dict:
    response = request_json(
        f"/recitations/{reciter_id}/by_ayah/{verse_key}",
        {"fields": "segments,url,duration"},
    )
    files = response.get("audio_files", [])
    if not files or not files[0].get("segments"):
        raise RuntimeError(f"missing audio segments for recitation {reciter_id} {verse_key}")
    return files[0]


def choose_word_source(records: list[dict], current: dict, desired_not: str) -> tuple[dict, int]:
    for record in records:
        if record is current:
            continue
        for index, word in enumerate(record["verse"]["words"]):
            if word != desired_not and index < len(record["segments"]):
                return record, index
    raise RuntimeError("no source word available for transformation")


def construct_case(case: dict, records: list[dict], wav_dir: Path) -> None:
    record = next(item for item in records if item["case_id"] == case["case_id"])
    source_samples = record["samples"]
    segments = record["segments"]
    words = record["verse"]["words"]
    parts = [segment_samples(source_samples, segment) for segment in segments]
    family = case["famille"]
    operation = {"family": family}

    if family == "correct_original":
        output = source_samples
        case["texte_present_audio"] = words
    elif family == "splice_clean":
        output = join_parts(parts)
        case["texte_present_audio"] = words
        operation["cuts"] = [
            {"word_index": index, "start_ms": segment[2], "end_ms": segment[3]}
            for index, segment in enumerate(segments)
        ]
    elif family == "omission":
        index = min(1, len(parts) - 1)
        output = join_parts(parts[:index] + parts[index + 1:])
        case["texte_present_audio"] = words[:index] + words[index + 1:]
        operation.update({"word_index": index, "removed": words[index]})
    elif family == "substitution":
        index = min(1, len(parts) - 1)
        source, source_index = choose_word_source(records, record, words[index])
        replacement = segment_samples(source["samples"], source["segments"][source_index])
        actual = list(words)
        actual[index] = source["verse"]["words"][source_index]
        output = join_parts(parts[:index] + [replacement] + parts[index + 1:])
        case["texte_present_audio"] = actual
        operation.update({
            "word_index": index,
            "expected": words[index],
            "present": actual[index],
            "source_case": source["case_id"],
        })
    elif family == "insertion":
        index = min(1, len(parts) - 1)
        source, source_index = choose_word_source(records, record, words[index])
        inserted = segment_samples(source["samples"], source["segments"][source_index])
        actual = list(words)
        actual.insert(index, source["verse"]["words"][source_index])
        output = join_parts(parts[:index] + [inserted] + parts[index:])
        case["texte_present_audio"] = actual
        operation.update({
            "insert_before_index": index,
            "inserted": actual[index],
            "source_case": source["case_id"],
        })
    elif family == "permutation":
        index = min(1, len(parts) - 2)
        reordered = parts[:]
        reordered[index], reordered[index + 1] = reordered[index + 1], reordered[index]
        actual = words[:]
        actual[index], actual[index + 1] = actual[index + 1], actual[index]
        output = join_parts(reordered)
        case["texte_present_audio"] = actual
        operation.update({"first_index": index, "second_index": index + 1})
    elif family == "truncation":
        index = min(1, len(parts) - 1)
        part = parts[index]
        cut = max(1, int(len(part) * 0.45))
        output = join_parts(parts[:index] + [part[:cut]] + parts[index + 1:])
        case["texte_present_audio"] = words[:]
        operation.update({"word_index": index, "kept_ratio": round(cut / len(part), 3)})
    elif family == "interruption_reprise":
        index = min(1, len(parts) - 1)
        part = parts[index]
        cut = max(1, int(len(part) * 0.5))
        output = join_parts(
            parts[:index] + [part[:cut], silence(700), part[cut:]] + parts[index + 1:]
        )
        case["texte_present_audio"] = words[:]
        case["repetition_legitime"] = True
        case["faute_a_detecter"] = False
        operation.update({"word_index": index, "pause_ms": 700, "resume": True})
    else:
        raise AssertionError(family)

    destination = wav_dir / f"{case['case_id']}.wav"
    write_wav(destination, output)
    case["wav_final"] = str(destination.relative_to(ROOT)).replace("\\", "/")
    case["wav_final_sha256"] = sha256(destination)
    case["operation"] = operation


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    out = args.out.resolve()
    source_dir = out / "sources"
    wav_dir = out / "wav_cases"
    out.mkdir(parents=True, exist_ok=True)
    source_dir.mkdir(parents=True, exist_ok=True)
    wav_dir.mkdir(parents=True, exist_ok=True)

    print("Quran Foundation: catalogue Hafs...", flush=True)
    catalogue = request_json("/resources/recitations")["recitations"]
    catalogue_by_id = {int(item["id"]): item for item in catalogue}
    for reciter in RECITERS:
        if reciter["id"] not in catalogue_by_id:
            raise RuntimeError(f"recitation id {reciter['id']} absent from API catalogue")

    pool = build_text_pool()
    targets = choose_targets(pool)
    rng = random.Random(SEED)
    rng.shuffle(targets)
    cases = []
    for index, target in enumerate(targets, start=1):
        verse = target["verse"]
        cases.append(
            {
                "case_id": f"H-{index:03d}",
                "riwaya": "Hafs",
                "famille": case_family(index - 1),
                "sourate": verse["surah"],
                "versets": verse["key"],
                "recitateur": target["reciter"]["name"],
                "recitation_id": target["reciter"]["id"],
                "texte_attendu": verse["words"],
                "texte_present_audio": None,
                "repetition_legitime": False,
                "faute_a_detecter": True,
                "representatif": False,
                "source": "Quran Foundation Content API v4",
                "seed": SEED,
            }
        )
    make_split_and_replay(cases)

    records = []
    for case in cases:
        reciter_id = case["recitation_id"]
        verse_key = case["versets"]
        print(f"{case['case_id']} {verse_key} recitation={reciter_id}", flush=True)
        audio = api_audio_for(reciter_id, verse_key)
        source_name = f"{reciter_id}_{verse_key.replace(':', '_')}"
        mp3 = source_dir / f"{source_name}.mp3"
        wav = source_dir / f"{source_name}.wav"
        url = audio_url(audio["url"])
        download(url, mp3)
        ensure_wav(mp3, wav)
        samples = read_wav(wav)
        verse = next(
            item for item in flatten_pool(pool)
            if item["key"] == verse_key
        )
        if len(verse["words"]) != len(audio["segments"]):
            raise RuntimeError(
                f"word/segment mismatch {verse_key}: "
                f"{len(verse['words'])} != {len(audio['segments'])}"
            )
        record = {
            "case_id": case["case_id"],
            "verse": verse,
            "segments": audio["segments"],
            "samples": samples,
        }
        records.append(record)
        case["source_url"] = url
        case["source_mp3"] = str(mp3.relative_to(ROOT)).replace("\\", "/")
        case["source_wav"] = str(wav.relative_to(ROOT)).replace("\\", "/")
        case["audio_duration_ms"] = int(audio.get("duration", 0) * 1000)
        case["audio_segments"] = audio["segments"]
        case["audio_source_sha256"] = sha256(mp3)

    for case in cases:
        construct_case(case, records, wav_dir)

    manifest = out / "manifest_cases.jsonl"
    with manifest.open("w", encoding="utf-8") as stream:
        for case in cases:
            stream.write(json.dumps(case, ensure_ascii=False, sort_keys=True) + "\n")
    (out / "manifest_hash.txt").write_text(sha256(manifest) + "\n", encoding="utf-8")

    replays = {
        "policy": "three total executions for each representative case",
        "total_distinct_cases": 60,
        "total_executions_if_device_available": 70,
        "cases": [
            {"case_id": case["case_id"], "runs": [1, 2, 3]}
            for case in cases
            if case["representatif"]
        ],
    }
    (out / "replays.json").write_text(
        json.dumps(replays, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (out / "source_inventory.json").write_text(
        json.dumps(
            {
                "api": API,
                "catalogue_ids": [7, 6],
                "catalogue_entries": [catalogue_by_id[7], catalogue_by_id[6]],
                "riwaya": "Hafs",
                "seed": SEED,
                "sourates": list(SURAHS),
                "note": "Audio and segments obtained from Quran Foundation; no Warsh case is included.",
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    counts = {}
    for case in cases:
        counts[case["famille"]] = counts.get(case["famille"], 0) + 1
    print(json.dumps({"out": str(out), "cases": len(cases), "families": counts}, indent=2))


if __name__ == "__main__":
    main()
