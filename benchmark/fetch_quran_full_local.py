#!/usr/bin/env python3
"""Telecharge la totalite du texte coranique (chapitres + versets, uthmani +
tajweed + traduction fr + numero de page) depuis api.quran.com UNE FOIS,
pour le bundler en asset local Flutter -- remplace les appels Dio en direct
de `quran_api.dart` (cf. session 2026-07-19, decouverte "Connexion requise"
au lancement sans reseau : AUCUN cache local n'existait, la lecture du Coran
necessitait un appel reseau a chaque lancement, contrairement au reste du
pipeline ASR/ML qui est 100% on-device).

Sortie : app/assets/data/quran_chapters.json (114 sourates)
         app/assets/data/quran_verses.json (6236 versets, memes champs que
         Verse.fromJson cote Dart : text_uthmani, text_uthmani_tajweed,
         page_number, translations[0].text)

Reste EN LIGNE volontairement (streaming, pas raisonnable a embarquer) :
audio des recitations (fetchSurahAudioUrls), segments mot-par-mot
(fetchAyahSegments), info detaillee sourate (fetchSurahInfo) -- cf.
quran_api.dart, ces methodes ne changent pas.
"""
import json
import time
import urllib.request
from pathlib import Path

BASE = Path(__file__).parent.parent / "app" / "assets" / "data"
BASE.mkdir(parents=True, exist_ok=True)
API = "https://api.quran.com/api/v4"


def get(path, params):
    qs = "&".join(f"{k}={v}" for k, v in params.items())
    url = f"{API}{path}?{qs}"
    req = urllib.request.Request(url, headers={"User-Agent": "CoranKarim/1.0"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:
            wait = 2 ** attempt
            print(f"  retry {path} dans {wait}s ({e})", flush=True)
            time.sleep(wait)
    raise SystemExit(f"ECHEC definitif : {url}")


def main():
    print("Chapitres...", flush=True)
    chapters = get("/chapters", {"language": "fr"})["chapters"]
    assert len(chapters) == 114, f"{len(chapters)} chapitres != 114"
    (BASE / "quran_chapters.json").write_text(
        json.dumps(chapters, ensure_ascii=False), encoding="utf-8")
    print(f"  {len(chapters)} chapitres -> quran_chapters.json", flush=True)

    all_verses = []
    for ch in range(1, 115):
        data = get(f"/verses/by_chapter/{ch}", {
            "translations": "136",
            "fields": "text_uthmani,text_uthmani_tajweed,page_number",
            "per_page": "286",
        })
        verses = data["verses"]
        all_verses.extend(verses)
        print(f"  ch{ch:3d}/114 -- {len(verses)} versets, cumul {len(all_verses)}",
              flush=True)
        time.sleep(0.2)  # politesse API

    assert len(all_verses) == 6236, f"{len(all_verses)} versets != 6236"
    (BASE / "quran_verses.json").write_text(
        json.dumps(all_verses, ensure_ascii=False), encoding="utf-8")
    print(f"  {len(all_verses)} versets -> quran_verses.json", flush=True)

    total_bytes = (BASE / "quran_chapters.json").stat().st_size + \
        (BASE / "quran_verses.json").stat().st_size
    print(f"Total : {total_bytes / 1e6:.1f} Mo")


if __name__ == "__main__":
    main()
