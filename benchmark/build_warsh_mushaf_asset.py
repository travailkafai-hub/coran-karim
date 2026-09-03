#!/usr/bin/env python3
"""Build the lightweight, native 604-page Warsh display asset.

The recitation asset intentionally keeps Hafs verse keys for audio alignment.
This separate asset is display-only: it preserves the native Warsh ayah
numbers and page boundaries from KFGQPC without shipping page photographs.
"""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "benchmark" / "warshData_v10.json"
AUDIO_ASSET = ROOT / "app" / "assets" / "data" / "quran_verses_warsh.json"
OUTPUT = ROOT / "app" / "assets" / "data" / "quran_mushaf_warsh.json"

TRAILING_AYAH_NUMBER = re.compile(r"[\s\u00a0]*[٠-٩]+[\s\u00a0]*$")


def clean_text(text: str) -> str:
    text = TRAILING_AYAH_NUMBER.sub("", text)
    return re.sub(r"[\s\u00a0]+", " ", text).strip()


def entry(row: dict, page: int, text: str, ayah: int) -> dict:
    return {
        "verse_key": f"{row['sura_no']}:{ayah}",
        "text_uthmani": clean_text(text),
        "text_uthmani_tajweed": None,
        "page_number": page,
        "juz_number": int(row["jozz"]),
    }


def main() -> None:
    source = json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    audio = json.loads(AUDIO_ASSET.read_text(encoding="utf-8"))
    bismillah = audio[0]["text_uthmani"]

    output = []
    previous_surah = None
    split_rows = 0

    for row in source:
        surah = int(row["sura_no"])
        page_value = str(row["page"]).strip()
        first_page = int(page_value.split("-", 1)[0])

        if surah != previous_surah:
            if surah != 9:
                synthetic = dict(row)
                synthetic["sura_no"] = surah
                output.append(entry(synthetic, first_page, bismillah, 0))
            previous_surah = surah

        if "-" not in page_value:
            output.append(
                entry(row, first_page, row["aya_text"], int(row["aya_no"]))
            )
            continue

        start_page, end_page = (int(value) for value in page_value.split("-", 1))
        parts = re.split(r" {2,}", row["aya_text"], maxsplit=1)
        if len(parts) != 2:
            raise RuntimeError(
                f"Missing page-break separator in {surah}:{row['aya_no']}"
            )
        # The first fragment has no medallion. Ayah 0 is an internal display
        # sentinel; the native ayah number is attached only to the last part.
        output.append(entry(row, start_page, parts[0], 0))
        output.append(entry(row, end_page, parts[1], int(row["aya_no"])))
        split_rows += 1

    OUTPUT.write_text(
        json.dumps(output, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    pages = {item["page_number"] for item in output}
    if pages != set(range(1, 605)):
        raise RuntimeError("The generated asset does not cover pages 1..604")

    print(f"entries: {len(output)}")
    print(f"split cross-page ayahs: {split_rows}")
    print(f"pages: {min(pages)}..{max(pages)} ({len(pages)})")
    print(f"output: {OUTPUT} ({OUTPUT.stat().st_size / 1_000_000:.2f} MB)")


if __name__ == "__main__":
    main()
