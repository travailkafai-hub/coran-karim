"""Replay only the historical repetition regressions on the connected Samsung.

The full dense30 campaign has 100 cases.  ``verification_rapport.json`` lists
the cases where a word first received a negative V2 status and was later
overwritten by a final green.  Those are the cases relevant to the repetition
fix, so this runner copies only those case records into a fresh manifest and
uses the normal real-time Android runner.
"""
from __future__ import annotations

import json
from pathlib import Path
import sys

import campagne_100x20 as runner

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmark" / "campagne_100x20_dense30"
OUT = ROOT / "benchmark" / "campagne_100x20_dense30_regressions_20260915_samsung"


def main() -> None:
    source_manifest = SOURCE / "manifest.json"
    source_report = SOURCE / "verification_rapport.json"
    if not source_manifest.exists() or not source_report.exists():
        raise SystemExit("manifest.json ou verification_rapport.json absent")

    manifest = json.loads(source_manifest.read_text(encoding="utf-8"))
    report = json.loads(source_report.read_text(encoding="utf-8"))
    selected_ids = [item["case_id"] for item in report["green_after_negative"]]
    selected = [case for case in manifest["cases"] if case["case_id"] in selected_ids]
    if {case["case_id"] for case in selected} != set(selected_ids):
        raise SystemExit("un des cas de green_after_negative manque du manifeste")
    if len(selected) != 11:
        raise SystemExit(f"sous-ensemble inattendu: {len(selected)} cas")

    OUT.mkdir(parents=True, exist_ok=True)
    target_manifest = OUT / "manifest.json"
    subset_manifest = dict(
        seed=manifest.get("seed"),
        cases=selected,
        limitations=list(manifest.get("limitations", []))
        + [
            "Sous-ensemble: uniquement les cas green_after_negative du rapport historique.",
            f"Source: {source_report}",
        ],
    )
    encoded = json.dumps(subset_manifest, ensure_ascii=False, indent=2).encode("utf-8")
    if target_manifest.exists() and target_manifest.read_bytes() != encoded:
        raise SystemExit(f"manifest déjà présent mais différent: {target_manifest}")
    if not target_manifest.exists():
        target_manifest.write_bytes(encoded)

    runner.OUT = OUT
    serial = sys.argv[1] if len(sys.argv) > 1 else "R3CY20XW7TD"
    print(f"SOURCE={SOURCE}", flush=True)
    print(f"OUT={OUT}", flush=True)
    print(f"SERIAL={serial}", flush=True)
    print(f"CAS={','.join(selected_ids)}", flush=True)
    print(
        f"DUREE_AUDIO={sum(float(case['duration_seconds']) for case in selected)/60:.1f} min; "
        "les WAV restent ceux de la campagne auditée.",
        flush=True,
    )
    runner.run(serial)


if __name__ == "__main__":
    main()
