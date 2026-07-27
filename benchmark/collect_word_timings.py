"""Collecte les timings mot-a-mot de plusieurs recitateurs depuis quran.com et
produit un asset COMPACT et LOCAL des durees de reference par mot.

POURQUOI (2026-07-27, demande utilisateur) : la DP d'alignement donne parfois
ZERO frame a un mot pourtant bien prononce (mesure : 4 mots sans aucune couleur
sur une session de 142). Le discriminant installe le meme jour utilise le compte
de tokens CTC comme plancher -- exact, mais FAIBLE : il dit qu'un mot de 6 tokens
tient dans 480 ms, alors qu'en recitation reelle il en prend ~870. Il laisse donc
passer de vrais sauts.

Une duree de reference REALISTE corrige ca. Et la garder EN LOCAL supprime toute
dependance reseau a l'usage : 82 011 mots, en uint16 (millisecondes), tiennent en
160 Ko -- negligeable a cote des 8 Mo de quran_verses.json deja embarque.

POURQUOI PLUSIEURS RECITATEURS, pas un seul : la valeur brute d'un recitateur
inclut ses pauses de waqf, qui lui sont propres. Mesure qui l'a montre : chez
al-`Afasy le mot "هُمُ" (2:13) dure 3030 ms -- aberrant pour un mot de 3 lettres,
c'est la pause qui est comptee dedans. La MEDIANE sur plusieurs recitateurs lisse
ces idiosyncrasies sans se laisser tirer par un cas extreme (la moyenne, elle, le
serait).

POURQUOI DES PROPORTIONS et pas des millisecondes brutes : le tempo varie d'un
recitateur a l'autre et du tien. On stocke donc AUSSI le rapport de chaque mot a
la mediane de son verset -- une grandeur sans dimension, directement utilisable
quel que soit ton debit, sans avoir a estimer un rapport de tempo (estimation qui
a deja fait diverger la cible dynamique `secPerWord`, cf. BufferedTranscriber).

Recitateurs retenus : uniquement du MURATTAL (rythme de lecture normal). Les
versions Mujawwad (ids 1 et 8) sont ecartees volontairement -- tres lentes et
melodiques, leur duree n'a rien a voir avec une recitation d'apprentissage.

SORTIE : benchmark/word_timings_ref.json
    {"2:13": {"ms": [650, 740, ...], "rel": [0.76, 0.87, ...]}, ...}
  ms  : duree mediane inter-recitateurs, en millisecondes
  rel : duree rapportee a la mediane du verset (sans dimension)

USAGE
    python3 benchmark/collect_word_timings.py            # tout le Coran
    python3 benchmark/collect_word_timings.py --surahs 1,2,112
  Reprend ou il s'est arrete (cache par sourate/recitateur dans .timings_cache/).
"""
import argparse
import json
import statistics
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = Path(__file__).parent
CACHE = BASE / ".timings_cache"
OUT = BASE / "word_timings_ref.json"
API = "https://api.quran.com/api/v4/recitations/{rid}/by_chapter/{s}?fields=segments&per_page=300"

# Murattal uniquement (cf. en-tete). L'app utilise aujourd'hui l'id 7.
# 9 des 12 recitateurs de l'API (exclus : id 1 et 8 = Mujawwad, id 12 =
# Muallim/pedagogique -- rythmes non representatifs d'une recitation courante).
# Verifie (2026-07-27) : les 9 rendent TOUS 7 segments sur 2:2 (attendu 9 mots
# canoniques) -- le decalage de comptage vient du REFERENTIEL quran.com
# lui-meme, pas d'un recitateur en particulier. Plus de recitateurs affine la
# mediane de duree, mais ne comble PAS les versets a decalage (cf. le mapping
# a construire separement si on veut les recuperer).
RECITERS = {
    2: "AbdulBaset AbdulSamad (Murattal)",
    3: "as-Sudais",
    4: "Abu Bakr al-Shatri",
    5: "Hani ar-Rifai",
    6: "Al-Husary",
    7: "al-`Afasy",
    9: "al-Minshawi (Murattal)",
    10: "ash-Shuraym",
    11: "al-Tablawi",
}


def fetch_surah(rid: int, surah: int, retries: int = 4):
    """Segments d'une sourate entiere pour un recitateur. 114 appels par
    recitateur au lieu de 6236 -- le point d'entree /by_chapter rend bien les
    segments (verifie)."""
    cache = CACHE / f"{rid}_{surah}.json"
    if cache.exists():
        return json.loads(cache.read_text(encoding="utf-8"))
    url = API.format(rid=rid, s=surah)
    for attempt in range(retries):
        try:
            # User-Agent OBLIGATOIRE : l'API rend 403 Forbidden sur l'UA par
            # defaut d'urllib (`Python-urllib/3.x`). Constate a la premiere
            # execution -- les memes URLs passaient en curl, qui envoie le sien.
            req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
            with urllib.request.urlopen(req, timeout=40) as r:
                data = json.load(r)
            out = {}
            for af in data.get("audio_files", []):
                key, seg = af.get("verse_key"), af.get("segments")
                if key and seg:
                    # segment = [index_mot, ?, debut_ms, fin_ms]
                    out[key] = [[int(x[0]), int(x[2]), int(x[3])]
                                for x in seg if len(x) >= 4]
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(out), encoding="utf-8")
            return out
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            # Recul exponentiel : l'API refuse les rafales (constate en
            # collectant 3 versets d'affilee sans pause).
            if attempt == retries - 1:
                print(f"    ! echec r{rid} s{surah} : {e}")
                return {}
            time.sleep(2 ** attempt)
    return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--surahs", default=None, help="ex. 1,2,112 (defaut : 1-114)")
    ap.add_argument("--pause", type=float, default=0.35,
                    help="pause entre appels, pour ne pas se faire limiter")
    a = ap.parse_args()

    surahs = ([int(x) for x in a.surahs.split(",")] if a.surahs
              else list(range(1, 115)))

    # par verset -> par mot -> liste des durees observees chez les recitateurs
    durees: dict[str, dict[int, list[int]]] = {}
    for rid, nom in RECITERS.items():
        print(f"\n── recitateur {rid} : {nom}")
        for s in surahs:
            got = fetch_surah(rid, s)
            for key, segs in got.items():
                d = durees.setdefault(key, {})
                for widx, st, en in segs:
                    dur = en - st
                    if 0 < dur < 65000:  # borne uint16, et exclut les aberrations
                        d.setdefault(widx, []).append(dur)
            if s % 20 == 0:
                print(f"    sourate {s:>3} ... {len(durees)} versets connus")
            time.sleep(a.pause)

    # Agregation : MEDIANE (pas moyenne -- un waqf de 3 s tirerait la moyenne)
    resultat = {}
    for key, parmot in durees.items():
        if not parmot:
            continue
        n = max(parmot) + 1
        ms = []
        for i in range(n):
            vals = parmot.get(i)
            ms.append(int(statistics.median(vals)) if vals else 0)
        connus = [v for v in ms if v > 0]
        if not connus:
            continue
        med = statistics.median(connus)
        rel = [round(v / med, 3) if v > 0 else 0.0 for v in ms]
        resultat[key] = {"ms": ms, "rel": rel}

    OUT.write_text(json.dumps(resultat, separators=(",", ":")), encoding="utf-8")
    total_mots = sum(len(v["ms"]) for v in resultat.values())
    print(f"\n{'=' * 60}")
    print(f"versets couverts : {len(resultat)}")
    print(f"mots             : {total_mots}")
    print(f"ecrit            : {OUT}  ({OUT.stat().st_size / 1024:.0f} Ko)")
    if resultat:
        ech = next(iter(resultat.items()))
        print(f"exemple {ech[0]} : ms={ech[1]['ms'][:6]} rel={ech[1]['rel'][:6]}")


if __name__ == "__main__":
    main()
