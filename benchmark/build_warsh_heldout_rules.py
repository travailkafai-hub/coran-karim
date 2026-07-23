"""Set de validation cross-riwaya/cross-reciteur -- demande utilisateur
2026-07-19 : "utilise ceux de Warsh, mais pas sur les textes differents de
Hafs". Contrairement au YouTube (invalide, decoupage fixe 30s), les clips
Warsh viennent du MEME pipeline assajda/EveryAyah que le training (single
verset, duree quelques secondes, align_score deja calcule) -- pas de
confondant de duree.

6 reciteurs Warsh, JAMAIS utilises dans nemo_manifests_rules (exclus du
manifest Hafs-only par build_hafs_only_manifest.py) :
  OmarKazabri_assajda, LaayounKouchi_assajda, MohamedChahboun_assajda,
  RachidBelalia_assajda, HassanSaleh_assajda, AbdulRashidSufi_assajda

Piege documente (asr.md, contamination riwaya 2026-07-12) : le texte Warsh
n'est PAS toujours identique au Hafs (hamza, certaines finales de mots,
numerotation des versets decalee dans certaines sourates) -- ET les REGLES
de tajwid elles-memes peuvent differer entre les deux riwayat (notamment le
madd, dont Warsh a des conventions distinctes). Solution retenue (demande
utilisateur) : ne garder QUE les clips dont le texte reellement recite
correspond MOT POUR MOT au texte Hafs canonique pour ce verse_key -- dans ce
cas, les regles de tajwid derivees du Hafs (text_uthmani_tajweed) restent
valables, et le clip devient un test cross-reciteur PROPRE (nouvelle voix,
nouvel accent, mais texte/regles attendues identiques).

Sortie : nemo_manifests_rules/val_warsh_heldout.jsonl
"""
import json
from pathlib import Path

BASE = Path(__file__).parent
RULES_DIR = BASE / "data" / "quran_tajweed_rules"
OUT = BASE / "nemo_manifests_rules" / "val_warsh_heldout.jsonl"

WARSH_RECITERS = [
    "OmarKazabri_assajda", "LaayounKouchi_assajda", "MohamedChahboun_assajda",
    "RachidBelalia_assajda", "HassanSaleh_assajda", "AbdulRashidSufi_assajda",
]

WIN_PREFIX = "D:/Coran Karim/benchmark/data/train_wav/"
LOCAL_PREFIX = str(BASE / "data" / "train_wav_local") + "/"


def norm(s: str) -> str:
    return " ".join(s.replace("۞", " ").split())


def main():
    canonical = {}
    annotated = {}
    for l in open(RULES_DIR / "uthmani.jsonl", encoding="utf-8"):
        r = json.loads(l)
        canonical[r["verse_key"]] = norm(r["text"])
    for l in open(RULES_DIR / "annotated.jsonl", encoding="utf-8"):
        r = json.loads(l)
        annotated[r["verse_key"]] = norm(r["text"])

    rows_out = []
    stats = {"ok": 0, "text_differs_from_hafs": 0, "missing_verse": 0,
              "missing_audio": 0}
    for l in open(BASE / "data" / "manifest_unified.jsonl", encoding="utf-8"):
        r = json.loads(l)
        if r["reciter"] not in WARSH_RECITERS:
            continue
        key = r["key"]
        if key not in canonical or key not in annotated:
            stats["missing_verse"] += 1
            continue
        text_warsh = norm(r["text"])
        if text_warsh != canonical[key]:
            # texte reellement different entre Warsh et Hafs pour ce verset
            # (hamza, finale, ou verset decale) -- exclu comme demande.
            stats["text_differs_from_hafs"] += 1
            continue
        wav = r["wav"]
        if wav.startswith(WIN_PREFIX):
            wav = LOCAL_PREFIX + wav[len(WIN_PREFIX):]
        if not Path(wav).exists():
            stats["missing_audio"] += 1
            continue
        rows_out.append({
            "audio_filepath": wav,
            "text": annotated[key],
            "verse_key": key,
            "reciter": r["reciter"],
        })
        stats["ok"] += 1

    with open(OUT, "w", encoding="utf-8") as f:
        for r in rows_out:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{OUT.name}: {len(rows_out)} clips -- {stats}")

    rules = json.load(open(RULES_DIR / "rules_map.json", encoding="utf-8"))
    sym2name = {v: k for k, v in rules.items()}
    counts = {k: 0 for k in rules}
    clips_with_rule = {k: 0 for k in rules}
    for r in rows_out:
        seen = set()
        for c in r["text"]:
            if c in sym2name:
                counts[sym2name[c]] += 1
                seen.add(sym2name[c])
        for k in seen:
            clips_with_rule[k] += 1
    print("\ncouverture par regle (nb clips distincts, texte Hafs=Warsh confirme) :")
    for k, v in clips_with_rule.items():
        print(f"  {k:<24} {v} clips ({counts[k]} occurrences)")


if __name__ == "__main__":
    main()
