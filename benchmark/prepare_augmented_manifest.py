"""
Construit les manifests augmentés pour le prochain run FastConformer.
Mix : ~80% Coran + ~20% Arabic Speech Corpus (arabe non-coranique diacritisé).

Ce ratio expose le modèle à suffisamment d'arabe non-coranique pour
briser le biais "correction vers texte canonique", sans sacrifier la
dominance du domaine cible.

Entrées :
  benchmark/nemo_manifests/train_manifest.jsonl        ← corpus Coran (train)
  benchmark/nemo_manifests/val_manifest.jsonl          ← corpus Coran (val)
  benchmark/arabic_speech_corpus/asc_manifest.jsonl    ← Arabic Speech Corpus (Nawar Halabi)

Sortie :
  benchmark/augmented_manifests/train_augmented.jsonl
  benchmark/augmented_manifests/val_augmented.jsonl

Usage:
    "D:/Coran Karim/benchmark/.venv/Scripts/python.exe" -X utf8 prepare_augmented_manifest.py
    # Options :
    #   --asc_ratio 0.20        (défaut 0.20 = 20% Arabic Speech Corpus)
    #   --val_asc_frac 0.05     (5% de l'ASC va dans val, 95% dans train)
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import json, random, argparse
from pathlib import Path

BASE_DIR      = Path(__file__).parent
MANIFEST_DIR  = BASE_DIR / "nemo_manifests"
ASC_JSONL     = BASE_DIR / "arabic_speech_corpus" / "asc_manifest.jsonl"
OUT_DIR       = BASE_DIR / "augmented_manifests"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def load_jsonl(path: Path) -> list[dict]:
    entries = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                entries.append(json.loads(line))
    return entries


def write_jsonl(path: Path, entries: list[dict]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")


def stats(entries: list[dict], label: str) -> None:
    total_h = sum(e["duration"] for e in entries) / 3600
    print(f"  {label:30s}: {len(entries):7,} clips  {total_h:6.1f}h")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--asc_ratio",    type=float, default=0.20,
                   help="Fraction Arabic Speech Corpus dans le train final (défaut 0.20 = 20%%)")
    p.add_argument("--val_asc_frac", type=float, default=0.05,
                   help="Fraction de l'ASC réservée pour val (défaut 0.05 = 5%%)")
    p.add_argument("--seed",         type=int,   default=42)
    args = p.parse_args()
    random.seed(args.seed)

    # ── Chargement ───────────────────────────────────────────────────────────
    print("Chargement des manifests...")
    quran_train = load_jsonl(MANIFEST_DIR / "train_manifest.jsonl")
    quran_val   = load_jsonl(MANIFEST_DIR / "val_manifest.jsonl")

    if not ASC_JSONL.exists():
        print(f"ERREUR: {ASC_JSONL} introuvable.")
        print("Lance d'abord : python download_arabic_speech_corpus.py && python prepare_arabic_speech_corpus_manifest.py")
        return

    asc_all = load_jsonl(ASC_JSONL)
    random.shuffle(asc_all)

    print("\nDonnées sources :")
    stats(quran_train, "Coran train")
    stats(quran_val,   "Coran val")
    stats(asc_all,     "Arabic Speech Corpus total")

    # ── Split ASC en train/val ────────────────────────────────────────────────
    asc_val_n  = max(1, int(len(asc_all) * args.val_asc_frac))
    asc_val    = asc_all[:asc_val_n]
    asc_train  = asc_all[asc_val_n:]

    # ── Calcul du volume ASC train à garder ──────────────────────────────────
    # asc_ratio = N_asc / (N_quran + N_asc)
    # → N_asc = asc_ratio / (1 - asc_ratio) * N_quran
    n_quran = len(quran_train)
    n_asc_target = int(args.asc_ratio / (1.0 - args.asc_ratio) * n_quran)

    if n_asc_target > len(asc_train):
        print(f"\n[INFO] ASC train disponible ({len(asc_train)}) < cible ({n_asc_target}).")
        print("  → Sur-échantillonnage avec remplacement pour atteindre le ratio voulu.")
        factor = n_asc_target // len(asc_train) + 1
        asc_pool = (asc_train * factor)[:n_asc_target]
    else:
        asc_pool = asc_train[:n_asc_target]

    # ── Assemblage ───────────────────────────────────────────────────────────
    train_aug = quran_train + asc_pool
    val_aug   = quran_val   + asc_val
    random.shuffle(train_aug)
    random.shuffle(val_aug)

    # ── Écriture ─────────────────────────────────────────────────────────────
    train_path = OUT_DIR / "train_augmented.jsonl"
    val_path   = OUT_DIR / "val_augmented.jsonl"
    write_jsonl(train_path, train_aug)
    write_jsonl(val_path,   val_aug)

    print("\nManifests augmentés :")
    stats(train_aug, "Train augmenté")
    stats(val_aug,   "Val augmentée")

    asc_pct = len(asc_pool) / len(train_aug) * 100
    print(f"\n  Ratio ASC réel dans train : {asc_pct:.1f}%  (cible {args.asc_ratio*100:.0f}%)")

    print(f"\n  → {train_path}")
    print(f"  → {val_path}")

    print("\nÉtape suivante — lancer l'entraînement :")
    print(f'  "D:/Coran Karim/benchmark/.venv/Scripts/python.exe" -X utf8 ^')
    print(f'    finetune_fastconformer.py ^')
    print(f'    --train_manifest "{train_path}" ^')
    print(f'    --val_manifest "{val_path}" ^')
    print(f'    --resume "models/fastconformer-quran-pcd/fastconformer-quran-pcd-snapshot.nemo" ^')
    print(f'    --ckpt_dir "models/fastconformer-quran-augmented" ^')
    print(f'    --num_workers 0 --epochs 10 --batch_size 8 --lr 5e-5')


if __name__ == "__main__":
    main()
