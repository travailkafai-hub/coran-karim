"""Augmente une partie du corpus Coran avec des pauses internes, pour attaquer
la cause reelle du blocage mesure le 2026-07-23 (cf. FONCTIONNALITES_FUTURES.md
§4) : le modele n'a jamais vu de PAUSE INTERNE (seulement 4,3% des clips
d'entrainement ont >=2s de pause interne), et toute pause fait dérailler la
transcription -- WER avec pauses mesure 22,8% contre 10,5% propre, malgre
plusieurs politiques de segmentation cote app (toutes rejetees, cf. meme
paragraphe). Le vrai correctif est cote donnees, pas cote moteur natif.

⚠️ Correction de vocabulaire (2026-07-23, objection utilisateur justifiee) :
la premiere version de ce fichier parlait de recitation "hesitante", comme
si seul un utilisateur incertain etait concerne. Mesure sur le log ayant
motive ce diagnostic : l'ecart entre versets figes est de 4-8s de facon
QUASI CONSTANTE (14 intervalles sur 16), un rythme regulier qui est la
respiration NORMALE entre versets (potentiellement une pause de waqf
obligatoire, cf. §9), pas de l'hesitation erratique. Ce n'est donc pas un cas
marginal : ca touche tout recitateur, y compris confirme, des qu'il enchaine
plusieurs versets. La mesure et le mecanisme restent inchanges, seule la
portee (cas central, pas marge de robustesse) est corrigee ici.

CHOIX DE CONCEPTION : reproduire EXACTEMENT ce que l'app fait reellement
subir au modele, pas une pause abstraite. BufferedTranscriber.feed()
(le "portier RMS") ne conserve que 300ms de silence par pause ; au-dela, les
blocs sont JETES -- l'audio qui arrive au modele en production contient donc
des COUTURES (recollement), jamais du silence entier. Ce script applique la
MEME regle (SILENCE_RMS_THRESHOLD=0.02, MAX_SILENCE_SAMPLES=300ms, blocs de
80ms) a de l'audio-avec-pauses avant de l'ecrire sur disque : le clip
d'entrainement resultant est bit-pour-bit ce que le modele verra depuis le
buffer natif a chaque pause entre versets (respiration normale, pas
necessairement une hesitation -- cf. correction ci-dessus). Aucune autre
variante (silence entier, coupe a la pause) n'est generee : ce ne sont pas
des situations que l'app produit, les entrainer serait hors-distribution
dans l'AUTRE sens.

Contenu INCHANGE (texte, cibles tajwid) : on ne fait qu'inserer du silence
entre des morceaux du MEME audio, decoupe a des positions arbitraires (pas
necessairement des frontieres de mot -- en pratique une pause de respiration
peut tomber juste apres le debut du mot suivant si la coupure de segment
est legerement en avance).

Portee : ~10% des clips Coran annotes (train_annotated_only.jsonl, 58612
clips, 94% deja >=4s) -- proportionne a la rarete mesuree du phenomene sans
percuter l'equilibre Coran/ASC/TTS documente dans PLAN_ENTRAINEMENT_HYBRIDE.md
(la ci-dessus est un AJOUT, le corpus existant n'est pas touche).
100% REVERSIBLE : nouveaux fichiers audio dans un nouveau dossier, nouveau
manifest, le manifest source n'est jamais modifie (regle CLAUDE.md).

Usage :
    PYTHONPATH=benchmark/.venv_nemo/lib/python3.14/site-packages \
      /usr/bin/python3.14 benchmark/build_pause_augmented_manifest.py \
        --n 6000 [--seed 7] [--out-manifest train_pause_augment.jsonl]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

BASE = Path(__file__).parent
SRC_MANIFEST = BASE / "nemo_manifests_dual" / "train_annotated_only.jsonl"
OUT_WAV_DIR = BASE / "data" / "pause_augmentation" / "wav"
OUT_MANIFEST_DIR = BASE / "nemo_manifests_dual"

SR = 16000
BLOCK = 1280                     # 80ms -- BufferedTranscriber.feed() par bloc
SILENCE_RMS_THRESHOLD = 0.02     # meme seuil que BufferedTranscriber (Kotlin)
MAX_SILENCE_SAMPLES = int(SR * 0.3)  # 300ms conserves par pause, le reste jete
MIN_DURATION = 4.0                # assez de contenu pour couper 2-4 morceaux
PAUSE_RANGE = (0.5, 3.0)          # secondes, mesure device : hesitations reelles
N_PAUSES_RANGE = (1, 3)           # pauses internes par clip augmente


def remap(p: str) -> str:
    return (p.replace("/mnt/ssd5/Coran Karim/", str(BASE.parent) + "/")
             .replace("/mnt/hdd/Coran Karim/", "/run/media/kafai/HDD/Coran Karim/"))


def portier(audio: np.ndarray) -> np.ndarray:
    """Reproduit BufferedTranscriber.feed() bloc par bloc : au-dela de 300ms
    de silence CONTINU par pause, les blocs supplementaires sont jetes."""
    kept, retained = [], 0
    for i in range(0, len(audio) - BLOCK + 1, BLOCK):
        blk = audio[i:i + BLOCK]
        is_sil = np.sqrt(np.mean(blk.astype(np.float64) ** 2)) < SILENCE_RMS_THRESHOLD
        if not is_sil:
            retained = 0
            kept.append(blk)
        elif retained < MAX_SILENCE_SAMPLES:
            retained += len(blk)
            kept.append(blk)
        # sinon : bloc jete
    rem = len(audio) % BLOCK
    if rem:
        kept.append(audio[-rem:])
    return np.concatenate(kept) if kept else audio[:0]


def insert_pauses(audio: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    n_pauses = int(rng.integers(N_PAUSES_RANGE[0], N_PAUSES_RANGE[1] + 1))
    n_parts = n_pauses + 1
    # positions de coupe : espacees, pas forcement des frontieres de mot --
    # une hesitation reelle peut tomber en plein mot.
    cuts = sorted(rng.uniform(0.15, 0.85, size=n_pauses))
    idx = [0] + [int(c * len(audio)) for c in cuts] + [len(audio)]
    parts = [audio[idx[i]:idx[i + 1]] for i in range(n_parts)]
    out = [parts[0]]
    for p in parts[1:]:
        dur = rng.uniform(*PAUSE_RANGE)
        out.append(np.zeros(int(dur * SR), dtype=np.float32))
        out.append(p)
    return np.concatenate(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=6000)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out-manifest", default="train_pause_augment.jsonl")
    args = ap.parse_args()

    rows = [json.loads(l) for l in open(SRC_MANIFEST, encoding="utf-8")]
    candidates = [r for r in rows if r["duration"] >= MIN_DURATION]
    print(f"{len(rows)} clips annotes, {len(candidates)} >= {MIN_DURATION}s "
          f"({100 * len(candidates) / len(rows):.0f}%)")

    rng = np.random.default_rng(args.seed)
    rng.shuffle(candidates)
    picked = candidates[:args.n]

    OUT_WAV_DIR.mkdir(parents=True, exist_ok=True)
    out_manifest = OUT_MANIFEST_DIR / args.out_manifest
    written, skipped = 0, 0
    with open(out_manifest, "w", encoding="utf-8") as fout:
        for i, r in enumerate(picked):
            src = remap(r["audio_filepath"])
            try:
                audio, sr = sf.read(src, dtype="float32")
            except Exception as e:
                skipped += 1
                continue
            if sr != SR:
                skipped += 1
                continue
            hesitant = insert_pauses(audio, rng)
            trained_on = portier(hesitant)  # ce que le modele voit REELLEMENT
            out_path = OUT_WAV_DIR / f"pause_{i:06d}.wav"
            sf.write(out_path, trained_on, SR)
            fout.write(json.dumps({
                "audio_filepath": str(out_path),
                "duration": len(trained_on) / SR,
                "text": r["text"],
                "text_tajwid": r.get("text_tajwid", ""),
            }, ensure_ascii=False) + "\n")
            written += 1
            if written % 1000 == 0:
                print(f"  {written}/{len(picked)}")

    print(f"\n{out_manifest} : {written} clips ecrits, {skipped} sautes "
          f"(fichier source introuvable ou sample rate incorrect)")
    print(f"audio dans {OUT_WAV_DIR}")
    print("\nManifest source NON modifie -- pour entrainer avec cet ajout, "
          "concatener (ne jamais ecraser) :")
    print(f"  cat {SRC_MANIFEST.relative_to(BASE.parent)} "
          f"{out_manifest.relative_to(BASE.parent)} > "
          f"{(OUT_MANIFEST_DIR / 'train_manifest_pause_aug.jsonl').relative_to(BASE.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
