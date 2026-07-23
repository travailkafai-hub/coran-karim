"""Augmentation ciblee ikhafa/idgham_ghunnah (2026-07-22).

Constat : ikhafa (rappel mesure 0.85) et idgham_ghunnah (0.87) sont les deux
classes les plus faibles de la tete tajwid parmi celles avec assez
d'occurrences pour etre fiables (cf. eval_tajwid_head.py sur le val set
complet). Le corpus d'entrainement actuel (train_mixed -> nemo_manifests_dual)
n'utilise que 54 des 85 recitateurs disponibles localement pour le Coran.

Comme la tete tajwid s'entraine en gelant l'encodeur + la tete lettres
(stage a), ajouter davantage de Coran ici n'a AUCUN impact sur le risque de
biais canonique de la tete lettres (elle n'apprend pas dans cette passe) --
la reserve habituelle sur le ratio Coran/ASC/TTS (cf. CLAUDE.md, PARTIE 3 du
plan) ne s'applique donc pas a cette augmentation specifique.

Methode :
  - versets contenant >=1 occurrence ikhafa OU idgham_ghunnah
    (data/quran_tajweed_rules/annotated.jsonl, deja corrige pour
    l'attribution mot precedent/suivant -- n'affecte pas ce script, qui ne
    fait qu'extraire la sequence de symboles du verset entier)
  - recitateurs NON utilises dans nemo_manifests_dual/train_manifest.jsonl,
    filtres a >=5000 fichiers wav presents (couverture quasi complete du
    Coran, ecarte les dossiers vides/partiels)
  - pour chaque verset cible, ajoute le clip de CHAQUE recitateur retenu qui
    le possede (diversite de voix maximale sur les memes regles)

Sortie : nemo_manifests_dual/train_augment_ikhafa_idgham.jsonl
(meme format que build_dual_head_manifests.py : text = nu, text_tajwid =
symboles seuls ou null)
"""
import json
import os
from pathlib import Path

import soundfile as sf

BASE = Path(__file__).parent
RULES_DIR = BASE / "data" / "quran_tajweed_rules"
WAV_ROOT = BASE / "data" / "train_wav_local"
TRAIN_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"
OUT = BASE / "nemo_manifests_dual" / "train_augment_ikhafa_idgham.jsonl"

IKHAFA = ""
IDGHAM_GHUNNAH = ""
PUA_LO = 0xE000
PUA_HI = 0xF8FF
MIN_FILES = 5000


def strip_pua(t: str) -> str:
    return "".join(c for c in t if not (PUA_LO <= ord(c) <= PUA_HI))


def tajwid_seq(t: str) -> str:
    return "".join(c for c in t if PUA_LO <= ord(c) <= PUA_HI)


def main():
    used_reciters = set()
    for l in open(TRAIN_MANIFEST, encoding="utf-8"):
        p = json.loads(l)["audio_filepath"]
        if "train_wav_local/" in p:
            used_reciters.add(p.split("train_wav_local/")[1].split("/")[0])
    print(f"recitateurs deja utilises (Coran) : {len(used_reciters)}")

    all_reciters = set(os.listdir(WAV_ROOT))
    candidates = []
    for r in sorted(all_reciters - used_reciters):
        rdir = WAV_ROOT / r
        if not rdir.is_dir():
            continue
        n = sum(1 for f in os.listdir(rdir) if f.endswith(".wav"))
        if n >= MIN_FILES:
            candidates.append(r)
    print(f"recitateurs NON utilises retenus (>= {MIN_FILES} fichiers) : "
          f"{len(candidates)}")
    for r in candidates:
        print(f"  {r}")

    verses = {}
    for l in open(RULES_DIR / "annotated.jsonl", encoding="utf-8"):
        d = json.loads(l)
        t = d["text"]
        if IKHAFA in t or IDGHAM_GHUNNAH in t:
            verses[d["verse_key"]] = t
    print(f"\nversets cibles (>=1 ikhafa ou idgham_ghunnah) : {len(verses)}")

    out_rows = []
    n_missing = 0
    for key, atext in verses.items():
        surah, ayah = key.split(":")
        text = strip_pua(atext)
        tw = tajwid_seq(atext)
        for r in candidates:
            wav = WAV_ROOT / r / f"{surah}_{ayah}.wav"
            if not wav.exists():
                n_missing += 1
                continue
            try:
                info = sf.info(str(wav))
                dur = info.frames / info.samplerate
            except Exception:
                continue
            if dur < 0.5 or dur > 20.0:
                continue
            out_rows.append({
                "audio_filepath": str(wav),
                "duration": round(dur, 3),
                "text": text,
                "text_tajwid": tw,
            })

    with open(OUT, "w", encoding="utf-8") as f:
        for r in out_rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    tot_h = sum(r["duration"] for r in out_rows) / 3600
    print(f"\n{OUT} : {len(out_rows)} clips ajoutes ({tot_h:.1f}h), "
          f"{n_missing} fichiers verset/recitateur absents")


if __name__ == "__main__":
    main()
