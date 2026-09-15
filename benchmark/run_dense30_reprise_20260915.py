"""Launch a fresh 100 x 20 replay against the current DEV APK.

The historical WAV/manifest stay immutable.  The runner writes logs and
terminal outcomes to a new directory; WAV paths in the copied manifest still
point to the audited source campaign.
"""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import sys

import campagne_100x20 as runner

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "benchmark" / "campagne_100x20_dense30"
# Keep the earlier interrupted attempt intact and write this Samsung run to a
# clean directory with its own environment fingerprint.
OUT = ROOT / "benchmark" / "campagne_100x20_dense30_reprise_20260915_samsung"


def main() -> None:
    if not (SOURCE / "manifest.json").exists():
        raise SystemExit(f"manifest absent: {SOURCE / 'manifest.json'}")
    OUT.mkdir(parents=True, exist_ok=True)
    target_manifest = OUT / "manifest.json"
    source_bytes = (SOURCE / "manifest.json").read_bytes()
    if target_manifest.exists() and target_manifest.read_bytes() != source_bytes:
        raise SystemExit(f"manifest différent déjà présent: {target_manifest}")
    if not target_manifest.exists():
        target_manifest.write_bytes(source_bytes)
    runner.OUT = OUT
    serial = sys.argv[1] if len(sys.argv) > 1 else "R3CY20XW7TD"
    print(f"SOURCE={SOURCE}", flush=True)
    print(f"OUT={OUT}", flush=True)
    print(f"SERIAL={serial}", flush=True)
    print("Les WAV restent ceux de la campagne auditée; seuls les journaux sont nouveaux.", flush=True)
    runner.run(serial)


if __name__ == "__main__":
    main()
