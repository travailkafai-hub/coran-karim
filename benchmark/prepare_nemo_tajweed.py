"""
Genere les manifests NeMo train/val a partir de manifest_hafs_only.jsonl,
avec une normalisation TAJWEED-PRESERVANTE (contrairement a prepare_nemo_data.py
qui supprimait wasla/dagger alif/madda/marques de waqf).

Objectif : entrainer un modele CTC qui apprend reellement le tajweed et toutes
les marques coraniques. On ne retire QUE ce qui n'a aucune valeur phonetique
ni comportementale a la recitation :
  - ۞ (U+06DE, rub el hizb) : repere de decoupage du livre, aucun son, aucune
    pause induite -> SEUL caractere retire.

Tout le reste est CONSERVE (decision utilisateur, verifiee char par char sur le
corpus, 70 caracteres uniques) :
  - wasla ٱ, dagger alif ٰ, maddah ٓ, tatweel ـ (support/duree d'allongement),
  - petit waw ۥ / petit yeh ۦ, hamza flottante ٔ,
  - les 7+ marques de waqf (ۖ ۗ ۘ ۙ ۚ ۛ ۜ) et marques hautes/basses rares,
  - ۩ sajda (arret marque a la recitation, comportement acoustique reel).

Corpus 100% Hafs verifie (cf. build_hafs_only_manifest.py + verification
riwaya manuelle assabile + test audio 2026-07-12).
"""
import json, re, random
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import soundfile as sf

BASE_DIR = Path(__file__).parent
IN_PATH  = BASE_DIR / "data" / "manifest_hafs_only.jsonl"
OUT_DIR  = BASE_DIR / "nemo_manifests_tajweed"
OUT_DIR.mkdir(exist_ok=True)


def wav_duration(path):
    try:
        info = sf.info(path)
        return info.frames / info.samplerate
    except Exception:
        return -1.0

REMOVE_CHARS = {
    "۞",  # ۞ rub el hizb (aucune valeur phonetique)
    "﻿",  # BOM eventuel
}


def normalize_tajweed(text: str) -> str:
    text = "".join(c for c in text if c not in REMOVE_CHARS)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def main():
    print(f"Lecture {IN_PATH.name}...", flush=True)
    entries = []
    skipped_nowav = 0
    skipped_short = 0
    skipped_dur = 0

    # 1re passe : normalisation texte + resolution du wav, collecte des durees manquantes
    pending = []  # (wav_abs, text, dur_or_None)
    with open(IN_PATH, encoding="utf-8") as f:
        for line in f:
            o = json.loads(line)
            wav = o.get("wav", "")
            if not wav:
                skipped_nowav += 1
                continue
            wav_abs = (wav if Path(wav).is_absolute() else str(BASE_DIR / wav)).replace("\\", "/")
            text = normalize_tajweed(o.get("text", ""))
            if len(text) < 3:
                skipped_short += 1
                continue
            dur = o.get("duration")
            pending.append([wav_abs, text, dur])

    # 2e passe : calcule les durees manquantes depuis les WAV (en-tete seul, parallelise)
    missing_idx = [i for i, p in enumerate(pending) if not p[2] or p[2] <= 0]
    print(f"  Durees a calculer depuis les WAV : {len(missing_idx)}", flush=True)
    if missing_idx:
        with ThreadPoolExecutor(max_workers=16) as ex:
            durs = list(ex.map(lambda i: wav_duration(pending[i][0]), missing_idx))
        for i, d in zip(missing_idx, durs):
            pending[i][2] = d

    for wav_abs, text, dur in pending:
        if not dur or dur <= 0 or dur < 0.5 or dur > 60.0:
            skipped_dur += 1
            continue
        entries.append({
            "audio_filepath": wav_abs,
            "duration": round(float(dur), 3),
            "text": text,
        })

    print(f"  Conserves : {len(entries)}", flush=True)
    print(f"  Ignores  : nowav={skipped_nowav} short={skipped_short} duree={skipped_dur}", flush=True)

    random.seed(42)
    random.shuffle(entries)
    split = int(len(entries) * 0.95)
    train, val = entries[:split], entries[split:]

    with open(OUT_DIR / "train_manifest.jsonl", "w", encoding="utf-8") as f:
        for e in train:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    with open(OUT_DIR / "val_manifest.jsonl", "w", encoding="utf-8") as f:
        for e in val:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    # corpus texte pour l'entrainement du tokenizer (une phrase par ligne)
    with open(OUT_DIR / "corpus_text.txt", "w", encoding="utf-8") as f:
        for e in entries:
            f.write(e["text"] + "\n")

    total_h = sum(e["duration"] for e in train) / 3600
    print(f"\n  Train : {len(train)} clips -> {OUT_DIR/'train_manifest.jsonl'}", flush=True)
    print(f"  Val   : {len(val)} clips   -> {OUT_DIR/'val_manifest.jsonl'}", flush=True)
    print(f"  Corpus tokenizer : {OUT_DIR/'corpus_text.txt'}", flush=True)
    print(f"  Duree train : {total_h:.1f}h", flush=True)


if __name__ == "__main__":
    main()
