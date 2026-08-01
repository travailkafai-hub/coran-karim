#!/usr/bin/env python3
"""Telecharge les horodatages REELS (API quran.com) pour les 3 styles
Mujawwad/Muallim -- exclus de `collect_word_timings.py` (reference des
LETTRES, ou leur rythme non representatif aurait fausse la mediane) mais
utiles pour la tete TAJWID : ce style exagere/elabore les regles (madd
etendus, ghunnah appuyee), ce qui en fait de bons exemples positifs, et la
contrainte de rythme "representatif d'une recitation courante" ne s'applique
pas a un entrainement encodeur GELE (stage a).

Demande utilisateur (2026-08-01), suite a la verification : l'API donne de
VRAIS horodatages par mot (pas une estimation), confirme sur 6 recitateurs a
quelques dizaines/centaines de ms pres contre l'enveloppe RMS des fichiers
LOCAUX -- meme enregistrement. Reutilise cette fois pour construire les
labels tajwid SANS passer par l'alignement Viterbi fragile
(`build_frame_level_tajwid_labels.py`, meme piege que celui documente dans
PROBLEME_DECOUPE_CLIPS_COURTS.md).

Sortie : benchmark/.timings_cache_mujawwad/{rid}_{surah}.json (meme format
que .timings_cache/, cache separe pour ne jamais melanger avec la reference
murattal).
"""
import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = Path(__file__).parent
CACHE = BASE / ".timings_cache_mujawwad"
API = "https://api.quran.com/api/v4/recitations/{rid}/by_chapter/{s}?fields=segments&per_page=300"

# Les 3 styles exclus de la reference murattal -- mapping id -> dossier LOCAL
# verifie manuellement (2026-08-01).
RECITEURS = {
    1: ("AbdulBaset AbdulSamad (Mujawwad)", "Abdul_Basit_Mujawwad_128kbps"),
    8: ("Mohamed Siddiq al-Minshawi (Mujawwad)", "Minshawy_Mujawwad_192kbps"),
    12: ("Mahmoud Khalil Al-Husary (Muallim)", "Husary_Muallim_128kbps"),
}


def fetch_surah(rid: int, surah: int, retries: int = 4):
    cache = CACHE / f"{rid}_{surah}.json"
    if cache.exists():
        return json.loads(cache.read_text(encoding="utf-8"))
    url = API.format(rid=rid, s=surah)
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
            with urllib.request.urlopen(req, timeout=40) as r:
                data = json.load(r)
            out = {}
            for af in data.get("audio_files", []):
                key, seg = af.get("verse_key"), af.get("segments")
                if key and seg:
                    out[key] = [[int(x[0]), int(x[2]), int(x[3])]
                                for x in seg if len(x) >= 4]
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(out), encoding="utf-8")
            return out
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            if attempt == retries - 1:
                print(f"    ! echec r{rid} s{surah} : {e}")
                return {}
            time.sleep(2 ** attempt)
    return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--surahs", default=None)
    ap.add_argument("--pause", type=float, default=0.35)
    a = ap.parse_args()
    surahs = ([int(x) for x in a.surahs.split(",")] if a.surahs
              else list(range(1, 115)))

    total = 0
    for rid, (nom, dossier) in RECITEURS.items():
        print(f"── recitateur {rid} : {nom}  ({dossier})", flush=True)
        n_versets = 0
        for s in surahs:
            got = fetch_surah(rid, s)
            n_versets += len(got)
            if s % 20 == 0:
                print(f"    sourate {s:>3} ... {n_versets} versets", flush=True)
            time.sleep(a.pause)
        print(f"   total : {n_versets} versets\n")
        total += n_versets
    print(f"TERMINE : {total} versets telecharges sur les 3 recitateurs")


if __name__ == "__main__":
    main()
