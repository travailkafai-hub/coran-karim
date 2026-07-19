"""Construit un set de validation VRAIMENT non-vu (0 recouvrement reciteur
avec le training) pour tester la detection des 17 regles de tajwid --
demande utilisateur 2026-07-19 : "on a 480h par regle" / "meme telechargement
youtube" -- en premier, utiliser l'existant avant de televerser quoi que ce
soit de nouveau.

Source : data/manifest_youtube_clean.jsonl (3371 clips, 112/114 sourates,
audio sur le disque HDD externe) -- confirme JAMAIS utilise dans
nemo_manifests_rules (0 occurrence "youtube" dans train/val). Reciteurs
YouTube distincts des 54 reciteurs Hafs deja epuises par le train/val actuel
(overlap train/val = 53/53, aucun reciteur "neuf" restant dans
manifest_hafs_only.jsonl) -- c'est donc le seul pool de generalisation
cross-reciteur disponible sans nouveau telechargement.

Chaine annotee VERIFIEE le 2026-07-19 : ces videos font-elles vraiment du
tajwid (pas une simple lecture) ? Croise les titres video (manifest_youtube*
.jsonl) avec les video_id du set clean -- 66% attribues a des Qaris reconnus
(Alafasy, Sudais, Al-Hussary "Accurate Tajweed recitation" explicite dans le
titre, Al-Dosari, Maher Al-Muaqly, Bandar Baleelah...), 31% a des reciteurs
nommes moins celebres (recitation publique coranique = norme culturelle
d'application du tajwid, contrairement a une lecture casual), seulement 3%
(103 clips) sans AUCUNE attribution (titre = simple ref verset ou vide) --
ceux-la exclus ci-dessous par prudence.

Chaque clip couvre PLUSIEURS versets consecutifs (`key` = "1:1 1:2 1:3 1:4")
-- concatener le texte annote verset par verset dans le meme ordre, avec
verification stricte que la concatenation canonique correspond au champ
`text` du manifest source (comme le controle deja fait pour les clips
single-verset dans build_rules_manifests.py).

Sortie : nemo_manifests_rules/val_youtube_heldout.jsonl
"""
import json
import re
from pathlib import Path

BASE = Path(__file__).parent
RULES_DIR = BASE / "data" / "quran_tajweed_rules"
YT_MANIFEST = BASE / "data" / "manifest_youtube_clean.jsonl"
HDD_BASE = Path("/run/media/kafai/HDD/Coran Karim/benchmark")
OUT = BASE / "nemo_manifests_rules" / "val_youtube_heldout.jsonl"


def norm(s: str) -> str:
    return " ".join(s.replace("۞", " ").split())


def load_video_titles():
    """video_id -> titre, depuis tous les manifests youtube connus (metadata
    de telechargement, contient le titre original de la video)."""
    id2title = {}
    for fname in ["manifest_youtube.jsonl", "manifest_youtube_aligned.jsonl",
                  "manifest_youtube_bad.jsonl"]:
        p = BASE / "data" / fname
        if not p.exists():
            continue
        for l in open(p, encoding="utf-8"):
            r = json.loads(l)
            m = re.search(r"v=([\w-]{11})", r.get("source_url", ""))
            if m:
                id2title[m.group(1)] = r.get("title", "")
    return id2title


def has_reciter_attribution(title: str) -> bool:
    """False si le titre ne contient AUCUNE info exploitable (juste une
    reference de verset type 'Al-Maida: 05', ou titre vide)."""
    title = title.strip()
    if not title:
        return False
    if re.match(r"^[A-Za-z\-\.\s']+:\s*\d+$", title):
        return False
    return True


def main():
    id2title = load_video_titles()
    annotated = {}
    canonical = {}
    for l in open(RULES_DIR / "annotated.jsonl", encoding="utf-8"):
        r = json.loads(l)
        annotated[r["verse_key"]] = norm(r["text"])
    for l in open(RULES_DIR / "uthmani.jsonl", encoding="utf-8"):
        r = json.loads(l)
        canonical[r["verse_key"]] = norm(r["text"])

    rows_out = []
    stats = {"ok": 0, "mismatch": 0, "missing_audio": 0, "missing_verse": 0,
             "no_attribution": 0}
    for l in open(YT_MANIFEST, encoding="utf-8"):
        r = json.loads(l)
        m = re.search(r"/([\w-]{11})_\d+\.wav", r["wav"])
        video_id = m.group(1) if m else None
        title = id2title.get(video_id, "") if video_id else ""
        if not has_reciter_attribution(title):
            stats["no_attribution"] += 1
            continue
        keys = r["key"].split()
        if not all(k in canonical and k in annotated for k in keys):
            stats["missing_verse"] += 1
            continue
        canon_concat = " ".join(canonical[k] for k in keys)
        ann_concat = " ".join(annotated[k] for k in keys)
        text_manifest = norm(r["text"])
        if canon_concat != text_manifest:
            stats["mismatch"] += 1
            continue
        wav_path = HDD_BASE / r["wav"]
        if not wav_path.exists():
            stats["missing_audio"] += 1
            continue
        rows_out.append({
            "audio_filepath": str(wav_path),
            "text": ann_concat,
            "verse_keys": r["key"],
            "n_verses": len(keys),
            "source_title": title,
        })
        stats["ok"] += 1

    with open(OUT, "w", encoding="utf-8") as f:
        for r in rows_out:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"{OUT.name}: {len(rows_out)} clips -- {stats}")

    # couverture par regle
    rules = json.load(open(RULES_DIR / "rules_map.json", encoding="utf-8"))
    sym2name = {v: k for k, v in rules.items()}
    counts = {k: 0 for k in rules}
    for r in rows_out:
        for c in r["text"]:
            if c in sym2name:
                counts[sym2name[c]] += 1
    print("\ncouverture par regle (nb OCCURRENCES, pas nb clips) :")
    for k, v in counts.items():
        print(f"  {k:<24} {v}")
    n_with_any = sum(1 for r in rows_out if any(s in r["text"] for s in rules.values()))
    print(f"\nclips avec au moins 1 regle : {n_with_any}/{len(rows_out)}")


if __name__ == "__main__":
    main()
