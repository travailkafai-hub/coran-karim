"""
Filtre les clips YouTube par WER avec Whisper Small (GPU).
Supprime les clips avec WER > 0.7 (alignement suspect).

Usage:
    python filter_youtube_wer.py
    python filter_youtube_wer.py --threshold 0.7 --device cuda
    python filter_youtube_wer.py --dry-run   # affiche stats sans écrire
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import sys, json, re, argparse
import numpy as np, soundfile as sf
import torch
from pathlib import Path
from tqdm import tqdm
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from jiwer import wer as compute_wer

ROOT     = Path(__file__).parent
FT_MODEL = ROOT / "models" / "whisper-small-ft"
MAN_IN   = ROOT / "data" / "manifest_youtube_aligned.jsonl"
MAN_OUT  = ROOT / "data" / "manifest_youtube_clean.jsonl"
MAN_BAD  = ROOT / "data" / "manifest_youtube_bad.jsonl"
SCORES   = ROOT / "data" / "youtube_wer_scores.jsonl"

_HAR = re.compile(r'[ً-ٰٟۖ-ۜ۟-ۭـ]')

def norm(t: str) -> str:
    t = _HAR.sub('', t)
    t = t.replace('أ','ا').replace('إ','ا').replace('آ','ا')
    t = t.replace('ى','ي').replace('ؤ','و').replace('ئ','ي')
    return re.sub(r'\s+', ' ', re.sub(r'[^؀-ۿ\s]','', t)).strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=float, default=0.7)
    ap.add_argument("--device",    default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--batch",     type=int, default=8)
    ap.add_argument("--dry-run",   action="store_true")
    ap.add_argument("--resume",    action="store_true", help="Reprendre si scores.jsonl existe déjà")
    args = ap.parse_args()

    rows = [json.loads(l) for l in open(MAN_IN, encoding="utf-8")]
    print(f"{len(rows)} clips YouTube à évaluer (seuil WER={args.threshold})")

    # Résumé existant ?
    done_keys = set()
    scores_cache = {}
    if args.resume and SCORES.exists():
        for l in open(SCORES, encoding="utf-8"):
            e = json.loads(l)
            done_keys.add(e["key"] + "|" + e["wav"])
            scores_cache[e["key"] + "|" + e["wav"]] = e["wer"]
        print(f"  {len(done_keys)} clips déjà scorés (--resume)")

    print(f"Chargement Whisper Small depuis {FT_MODEL}...")
    proc  = WhisperProcessor.from_pretrained(str(FT_MODEL), language="arabic", task="transcribe")
    model = WhisperForConditionalGeneration.from_pretrained(str(FT_MODEL)).to(args.device).eval()
    try:
        model.generation_config.is_multilingual = True
        model.generation_config.forced_decoder_ids = proc.get_decoder_prompt_ids(
            language="arabic", task="transcribe")
        model.generation_config.suppress_tokens = []
    except Exception:
        pass

    todo = [r for r in rows if (r["key"] + "|" + r["wav"]) not in done_keys]
    print(f"  {len(todo)} clips à scorer...")

    score_f = open(SCORES, "a", encoding="utf-8") if not args.dry_run else None

    with torch.no_grad():
        for r in tqdm(todo):
            wav_abs = ROOT / r["wav"]
            if not wav_abs.exists():
                scores_cache[r["key"] + "|" + r["wav"]] = 1.0
                continue
            try:
                audio, sr = sf.read(str(wav_abs), dtype="float32")
                if sr != 16000:
                    tqdm.write(f"  SR={sr} pour {r['wav']}")
                feats = proc.feature_extractor(audio, sampling_rate=16000,
                                               return_tensors="pt").input_features.to(args.device)
                ids  = model.generate(feats, max_new_tokens=200)
                hyp  = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()
                ref  = norm(r["text"])
                w    = compute_wer(ref, norm(hyp)) if ref else 1.0
            except Exception as ex:
                tqdm.write(f"  ERREUR {r['wav']}: {ex}")
                w = 1.0

            scores_cache[r["key"] + "|" + r["wav"]] = w
            if score_f:
                score_f.write(json.dumps({"key": r["key"], "wav": r["wav"], "wer": round(w, 3)},
                                          ensure_ascii=False) + "\n")

    if score_f:
        score_f.close()

    # Filtrage
    good = [r for r in rows if scores_cache.get(r["key"] + "|" + r["wav"], 0) <= args.threshold]
    bad  = [r for r in rows if scores_cache.get(r["key"] + "|" + r["wav"], 0)  > args.threshold]

    print(f"\n=== RÉSULTAT ===")
    print(f"  BONS  (WER ≤ {args.threshold}): {len(good)} clips")
    print(f"  MAUVAIS (WER > {args.threshold}): {len(bad)} clips")

    if not args.dry_run:
        with open(MAN_OUT, "w", encoding="utf-8") as f:
            for r in good: f.write(json.dumps(r, ensure_ascii=False) + "\n")
        with open(MAN_BAD, "w", encoding="utf-8") as f:
            for r in bad: f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"\n  → {MAN_OUT.name}: {len(good)} clips propres")
        print(f"  → {MAN_BAD.name}: {len(bad)} clips suspects")

        # Mettre à jour train_combined.jsonl (ancien pipeline, conserve pour compat)
        combined = []
        for l in open(ROOT / "data" / "train_full.jsonl", encoding="utf-8"):
            combined.append(json.loads(l))
        combined.extend(good)
        out_comb = ROOT / "data" / "train_combined_clean.jsonl"
        with open(out_comb, "w", encoding="utf-8") as f:
            for e in combined: f.write(json.dumps(e, ensure_ascii=False) + "\n")
        print(f"  → {out_comb.name}: {len(combined)} clips")

        # Fusionner aussi dans manifest_unified.jsonl (dataset reellement utilise
        # par les derniers trainings whisper-small/medium) — dedup sur reciter+key,
        # meme cle que rebuild_manifest_unified.ps1, tag reciter="youtube_clean".
        unified_path = ROOT / "data" / "manifest_unified.jsonl"
        if unified_path.exists():
            seen = set()
            unified_rows = []
            for l in open(unified_path, encoding="utf-8"):
                e = json.loads(l)
                unified_rows.append(e)
                seen.add(e.get("reciter", "") + "-" + e.get("key", ""))
            added = 0
            for r in good:
                dedup_key = "youtube_clean-" + r["key"]
                if dedup_key in seen:
                    continue
                seen.add(dedup_key)
                wav_abs = str((ROOT / r["wav"]).resolve())
                unified_rows.append({
                    "key": r["key"], "reciter": "youtube_clean",
                    "mp3": None, "text": r["text"], "wav": wav_abs,
                })
                added += 1
            with open(unified_path, "w", encoding="utf-8") as f:
                for e in unified_rows: f.write(json.dumps(e, ensure_ascii=False) + "\n")
            print(f"  → {unified_path.name}: +{added} clips youtube_clean ({len(unified_rows)} total)")
        else:
            print(f"  (manifest_unified.jsonl introuvable — fusion ignoree)")
    else:
        print("(--dry-run: aucun fichier écrit)")

if __name__ == "__main__":
    main()
