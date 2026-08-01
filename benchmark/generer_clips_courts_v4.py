#!/usr/bin/env python3
"""GENERE des fragments COURTS a partir d'HORODATAGES REELS (API quran.com).

v4 -- corrige v1 (proportions empruntees, 37,2 % WER) et v2 (Viterbi CTC brut,
43,3 %, pointu) et v3 (probabilite de blanc, 33,9 %/48,5 %, encore trop
imprecis). Ici il n'y a plus d'ESTIMATION du tout : l'API quran.com donne un
horodatage par mot, MESURE au moment de l'enregistrement.

Verifie le 2026-08-01 : sur 6 recitateurs murattal, l'enveloppe RMS des
fichiers LOCAUX (train_wav_local) colle a quelques dizaines/centaines de ms
pres a ce que rend l'API -- c'est le MEME enregistrement, pas une estimation
empruntee ailleurs.

── LES 10 RECITATEURS COUVERTS (sur 54) ────────────────────────────────────
9 murattal (API reciters 2,3,4,5,6,7,9,10,11) + Husary_Muallim (id 12, verifie
separement). Les 44 autres recitateurs locaux n'ont AUCUN horodatage reel
disponible -- pas traites ici, cf. PROBLEME_DECOUPE_CLIPS_COURTS.md pour la
suite si besoin.

Les 2 Mujawwad (Abdul_Basit, Minshawy) sont EXCLUS ici (decision utilisateur
2026-08-01) : verification par decodage reel non concluante (beaucoup de '??'
sur mots decodes vs attendus), cause non isolee (mauvais alignement, ou
modele qui decode mal le style Mujawwad independamment de l'alignement). Ils
continuent d'etre utilises pour la tete TAJWID (deja dans train_manifest.jsonl,
mecanisme different -- pas de decoupe audio la-bas), juste pas ici.

Coupe en plein mot pour une partie des fragments (decision utilisateur du
2026-07-31) : la cible texte EXCLUT TOUJOURS le mot tronque.
"""
import json
import random
import re
from pathlib import Path

import numpy as np
import soundfile as sf

BASE = Path(__file__).parent
TRAIN_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"
CACHE_MURATTAL = BASE / ".timings_cache"
CACHE_MUALLIM = BASE / ".timings_cache_mujawwad"
OUT_DIR = BASE / "data" / "clips_courts_v4"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"

# dossier local -> (id API, cache)
RECITATEURS = {
    "Abdul_Basit_Murattal_192kbps":  (2, CACHE_MURATTAL),
    "Abdurrahmaan_As-Sudais_192kbps": (3, CACHE_MURATTAL),
    "Abu_Bakr_Ash-Shaatree_128kbps": (4, CACHE_MURATTAL),
    "Hani_Rifai_192kbps":            (5, CACHE_MURATTAL),
    "Husary_128kbps":                (6, CACHE_MURATTAL),
    "Alafasy_128kbps":               (7, CACHE_MURATTAL),
    "Minshawy_Murattal_128kbps":     (9, CACHE_MURATTAL),
    "Saood_ash-Shuraym_128kbps":     (10, CACHE_MURATTAL),
    "Mohammad_al_Tablaway_128kbps":  (11, CACHE_MURATTAL),
    "Husary_Muallim_128kbps":        (12, CACHE_MUALLIM),
}

_LETTRE_AR = re.compile(r"[ء-يٮ-ۓ]")


def est_un_mot(tok: str) -> bool:
    return bool(_LETTRE_AR.search(tok))


def lire_wav16(p):
    x, sr = sf.read(str(p), dtype="float32")
    if x.ndim > 1:
        x = x.mean(axis=1)
    assert sr == 16000, f"{p} pas a 16kHz ({sr})"
    return x


def charger_segments(cache_dir, rid, surah, ayah, cache_mem):
    key = (rid, surah)
    if key not in cache_mem:
        f = cache_dir / f"{rid}_{surah}.json"
        cache_mem[key] = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}
    return cache_mem[key].get(f"{surah}:{ayah}")


def bornes_depuis_segments(seg, n_mots):
    """L'API donne [idx, debut_ms, fin_ms] par mot COURT ; le manifeste local
    peut avoir un decompte legerement different (ponctuation waqf, etc). On
    n'utilise QUE les cas ou les comptes correspondent exactement -- pas
    d'interpolation bricolee ici, il y a assez de recitateurs/versets pour se
    permettre d'etre strict."""
    if seg is None or len(seg) != n_mots:
        return None
    bornes = [seg[0][1] / 1000.0]
    for _, _, fin_ms in seg:
        bornes.append(fin_ms / 1000.0)
    return bornes


def decouper_un_clip(pcm, sr, mots, bornes, dmin, dmax, rng,
                     p_troncature=0.6, max_essais=6):
    n = len(mots)
    if n < 1:
        return None
    for _ in range(max_essais):
        cible = rng.uniform(dmin, dmax)
        i = rng.randrange(n)
        j = i
        while j < n and bornes[j + 1] - bornes[i] <= cible:
            j += 1
        d = bornes[j] - bornes[i]
        if not (dmin <= d <= dmax and j > i):
            continue
        a = int(bornes[i] * sr)
        b_propre = min(int(bornes[j] * sr), len(pcm))
        tronque = False
        b = b_propre
        if j < n and rng.random() < p_troncature:
            duree_mot_suivant = bornes[j + 1] - bornes[j]
            fraction = rng.uniform(0.15, 0.85)
            b_essai = b_propre + int(duree_mot_suivant * fraction * sr)
            b_essai = min(b_essai, len(pcm))
            if b_essai > b_propre and (b_essai - a) / sr <= dmax + 2.0:
                b = b_essai
                tronque = True
        if b - a < int(0.5 * sr):
            continue
        return pcm[a:b], " ".join(mots[i:j]), tronque
    return None


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--dmin", type=float, default=3.0)
    ap.add_argument("--dmax", type=float, default=8.0)
    ap.add_argument("--par_clip", type=int, default=2)
    ap.add_argument("--p_troncature", type=float, default=0.6)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--limite", type=int, default=None)
    a = ap.parse_args()

    lignes = [json.loads(l) for l in open(TRAIN_MANIFEST, encoding="utf-8")]
    longs = [l for l in lignes
             if any(f"train_wav_local/{r}/" in l.get("audio_filepath", "")
                    for r in RECITATEURS)]
    if a.limite:
        longs = longs[:a.limite]
    print(f"{len(longs)} clips sur les {len(RECITATEURS)} recitateurs fiables", flush=True)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rng = random.Random(a.seed)
    cache_mem = {}
    ecrits = tronques = decompte_diff = trop_courts = 0

    with open(OUT_MANIFEST, "w", encoding="utf-8") as fout:
        for k, l in enumerate(longs):
            p = Path(l["audio_filepath"])
            m = re.match(r"^(\d+)_(\d+)$", p.stem)
            if not m:
                continue
            surah, ayah = int(m.group(1)), int(m.group(2))
            reci = p.parent.name
            rid, cache_dir = RECITATEURS[reci]

            mots = [w for w in l["text"].split() if est_un_mot(w)]
            if not mots:
                continue
            seg = charger_segments(cache_dir, rid, surah, ayah, cache_mem)
            bornes = bornes_depuis_segments(seg, len(mots))
            if bornes is None:
                decompte_diff += 1
                continue

            pcm = lire_wav16(l["audio_filepath"])
            for _ in range(a.par_clip):
                r = decouper_un_clip(pcm, 16000, mots, bornes, a.dmin, a.dmax, rng,
                                     p_troncature=a.p_troncature)
                if r is None:
                    trop_courts += 1
                    continue
                audio, texte, tronque = r
                if not texte:
                    trop_courts += 1
                    continue
                nom = f"court_{ecrits:06d}.wav"
                sf.write(str(OUT_DIR / nom), audio, 16000)
                fout.write(json.dumps({
                    "audio_filepath": str(OUT_DIR / nom),
                    "duration": round(len(audio) / 16000, 3),
                    "text": texte, "tronque": tronque,
                    "source": l["audio_filepath"], "recitateur": reci,
                }, ensure_ascii=False) + "\n")
                ecrits += 1
                if tronque:
                    tronques += 1

            if (k + 1) % 2000 == 0:
                print(f"  {k+1}/{len(longs)}  ecrits={ecrits}", flush=True)

    print(f"\n{ecrits} fragments ecrits -> {OUT_MANIFEST}")
    print(f"  dont tronques : {tronques} ({100*tronques/max(1,ecrits):.0f} %)")
    print(f"decompte de mots API != manifeste (ecarte) : {decompte_diff}")
    print(f"aucune fenetre trouvee : {trop_courts}")


if __name__ == "__main__":
    main()
