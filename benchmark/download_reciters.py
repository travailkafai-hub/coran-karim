"""
Télécharge des réciteurs supplémentaires depuis EveryAyah.com et quranicaudio.com.
Convertit MP3 → WAV 16kHz mono et génère des entrées JSONL pour le dataset.

Usage :
    ../.venv/Scripts/python download_reciters.py --reciters all
    ../.venv/Scripts/python download_reciters.py --reciters Sudais,Husary
    ../.venv/Scripts/python download_reciters.py --list          # lister les réciteurs disponibles
"""
import os, sys, json, argparse, time, subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.request

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
MP3_DIR  = DATA_DIR / "train"
WAV_DIR  = DATA_DIR / "train_wav"

# ── Versets du Coran : sourates 1-114, versets selon la numérotation Hafs ──────
SURAH_VERSE_COUNT = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
    123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
    34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
    54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
    60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
    14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
    29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
    15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
    11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
    5, 4, 5, 6, 5, 9, 0
]
# (index 1-based : SURAH_VERSE_COUNT[1] = 7 versets pour Al-Fatiha)

# ── Réciteurs disponibles sur EveryAyah.com ─────────────────────────────────
# Format : { "id": (nom_dossier_everyayah, nom_affichage) }
# NOTE : les noms de dossier sont exacts tels qu'utilisés sur everyayah.com/data/
EVERYAYAH_RECITERS = {
    # ─── Déjà dans notre dataset (pour référence) ───────────────────────────
    # "Alafasy"         : "Alafasy_128kbps"
    # "AlSudais"        : "Abdurrahmaan_As-Sudais_192kbps"
    # "Maher"           : "Maher_AlMuaiqly_64kbps"
    # etc. (voir train_combined.jsonl)

    # ─── À télécharger — Moyen-Orient / Golfe ───────────────────────────────
    "AbdulBasitMurattal": ("Abdul_Basit_Murattal_192kbps",  "عبد الباسط — مرتّل"),
    "AbdulBasitMujawwad": ("Abdul_Basit_Mujawwad_128kbps",  "عبد الباسط — مجوّد"),
    "Husary":             ("Husary_128kbps",                 "محمود خليل الحصري"),
    "HusaryMujawwad":     ("Husary_Mujawwad_64kbps",         "الحصري — مجوّد"),
    "HusaryMuallim":      ("Husary_Muallim_128kbps",         "الحصري — معلّم"),
    "Shuraim":            ("Saood_ash-Shuraym_128kbps",      "سعود الشريم"),
    "HaniRifai":          ("Hani_Rifai_192kbps",             "هاني الرفاعي"),
    "SaadGhamdi":         ("Saad_Al-Ghamdi_128kbps",         "سعد الغامدي"),
    "KhalidQahtani":      ("Khaalid_Abdullaah_al-Qahtaanee_192kbps", "خالد القحطاني"),
    "WadiAlYamani":       ("Wadi_Al-Yamani_128kbps",         "وادي اليماني"),
    "AdilKalbani":        ("Adel_Kalbani_64kbps",            "عادل الكلباني"),
    "AhmedAjamy":         ("Ahmed_ibn_Ali_al-Ajamy_128kbps_ketaballah", "أحمد العجمي"),
    "YasserDossary":      ("Yasser_Ad-Dussary_128kbps",      "ياسر الدوسري"),
    "MaherMuaiqly128":    ("Maher_Al_Muaiqly_128kbps",       "ماهر المعيقلي — 128"),
    "MuhamadAbdulkareem": ("Muhammad_AbdulKareem_128kbps",   "محمد عبد الكريم"),
    "SalahBudair":        ("Salah_Al_Budair_128kbps",        "صلاح البدير"),
    "MuhsinQasim":        ("Muhsin_Al_Qasim_192kbps",        "محسن القاسم"),

    # ─── Réciteurs africains / marocains / maghrébins ───────────────────────
    # EveryAyah.com héberge ces réciteurs nord-africains confirmés :
    "IdrisAbkar":         ("Idrees_Abkar_192kbps",           "إدريس أبكر — سوداني"),
    "AzizAlili":          ("aziz_alili_128kbps",             "عزيز العيلي — مغاربي"),
    "MustafaIsmail":      ("Mustafa_Ismail_48kbps",          "مصطفى إسماعيل — مصري"),
    "MahmoudBanna":       ("mahmoud_ali_al_banna_32kbps",    "محمود علي البنا"),

    # Réciteurs marocains (sources alternatives — voir notes ci-dessous) :
    # ● Omar Al-Qazabri (عمر القزابري) — pas sur EveryAyah, mais disponible sur
    #   quranicaudio.com/quran/mp3/omar-al-qazabri
    # ● Mohamed Rachad Al-Ifrani (محمد رشاد الإفراني) — قناة YouTube officielle
    # ● Abderahman Amsili (عبد الرحمن أمسيلي) — vidéos YouTube
    # ● Larbi Bensari (العربي بنساري) — enregistrements anciens, archives
    # ● Abdessadak Benchi — disponible sur certains sites marocains
    # Pour ces réciteurs, utiliser download_youtube.py (voir plus bas)
}

# ─── Source alternative : quranicaudio.com (MP3 par sourate entière) ─────────
# Ces URLs donnent des MP3 par sourate (pas par verset) — moins utiles pour nous
# mais utilisables avec un aligneur forcé (whisper-forced-aligner)
QURANICAUDIO_RECITERS = {
    "OmarQazabri":    ("omar-al-qazabri",   "عمر القزابري — مغربي"),
    "Rifai":          ("hani-rifai",         "هاني الرفاعي"),
    "AbdussalamShweel":("abdussalam-al-shweel", "عبدالسلام الشويل"),
    "TablawyMurattal":("muhammad-al-tablawi", "محمد الطبلاوي — مرتّل"),
}

EVERYAYAH_BASE    = "https://everyayah.com/data"
QURANICAUDIO_BASE = "https://download.quranicaudio.com/quran"

def list_reciters():
    print("Réciteurs déjà dans le dataset :")
    existing = {d.name for d in (MP3_DIR.iterdir() if MP3_DIR.exists() else [])}
    print(f"  {sorted(existing)}\n")
    print("Réciteurs disponibles au téléchargement :")
    for key, (folder, name_ar) in EVERYAYAH_RECITERS.items():
        tag = " ✓ déjà présent" if folder in existing else ""
        print(f"  {key:20s} → {folder} | {name_ar}{tag}")

def download_file(url: str, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 1000:
        return True
    try:
        urllib.request.urlretrieve(url, dest)
        return dest.stat().st_size > 1000
    except Exception:
        if dest.exists():
            dest.unlink(missing_ok=True)
        return False

def convert_to_wav(mp3_path: Path, wav_path: Path) -> bool:
    if wav_path.exists() and wav_path.stat().st_size > 1000:
        return True
    wav_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3_path),
         "-ar", "16000", "-ac", "1", "-f", "wav", str(wav_path)],
        capture_output=True
    )
    return result.returncode == 0 and wav_path.exists()

def download_reciter(reciter_key: str, surah_range=None, max_workers=8):
    folder, name_ar = EVERYAYAH_RECITERS[reciter_key]
    mp3_out = MP3_DIR / folder
    wav_out = WAV_DIR / folder
    mp3_out.mkdir(parents=True, exist_ok=True)
    wav_out.mkdir(parents=True, exist_ok=True)

    # Charger le texte Quran (depuis nos données existantes)
    quran_text = load_quran_text()

    tasks = []
    if surah_range is None:
        surah_range = range(1, 115)

    for s in surah_range:
        if s < 1 or s > 114:
            continue
        n_verses = SURAH_VERSE_COUNT[s - 1]
        for v in range(1, n_verses + 1):
            url  = f"{EVERYAYAH_BASE}/{folder}/{s:03d}{v:03d}.mp3"
            mp3p = mp3_out / f"{s}_{v}.mp3"
            wavp = wav_out / f"{s}_{v}.wav"
            key  = f"{s}:{v}"
            text = quran_text.get(key, "")
            tasks.append((url, mp3p, wavp, key, text, folder))

    print(f"\n[{reciter_key}] {len(tasks)} versets à télécharger...")
    results = []
    ok = 0
    failed = 0

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {pool.submit(process_verse, *t): t for t in tasks}
        for i, fut in enumerate(as_completed(futures), 1):
            entry = fut.result()
            if entry:
                results.append(entry)
                ok += 1
            else:
                failed += 1
            if i % 100 == 0:
                print(f"  [{reciter_key}] {i}/{len(tasks)} — OK:{ok} ERR:{failed}")

    print(f"  [{reciter_key}] Terminé — {ok} OK, {failed} échecs")

    # Écrire JSONL
    out_jsonl = DATA_DIR / f"train_{folder}.jsonl"
    with open(out_jsonl, "w", encoding="utf-8") as f:
        for e in results:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(f"  → {out_jsonl} ({len(results)} entrées)")
    return results

def process_verse(url, mp3p, wavp, key, text, folder):
    if not text:
        return None
    if not download_file(url, mp3p):
        return None
    if not convert_to_wav(mp3p, wavp):
        return None
    return {
        "key":     key,
        "reciter": folder,
        "mp3":     str(mp3p.relative_to(BASE_DIR)).replace("\\", "/"),
        "text":    text,
        "wav":     str(wavp.relative_to(BASE_DIR)).replace("\\", "/"),
    }

def load_quran_text() -> dict:
    """Charge le mapping {surah:verse → texte Uthmani} depuis nos données existantes."""
    quran = {}
    src = DATA_DIR / "train_combined.jsonl"
    if not src.exists():
        src = DATA_DIR / "manifest_wav.jsonl"
    if not src.exists():
        return quran
    with open(src, encoding="utf-8") as f:
        for line in f:
            e = json.loads(line)
            quran[e["key"]] = e["text"]
    return quran

def merge_all_jsonl():
    """Fusionne tous les train_*.jsonl dans train_combined.jsonl."""
    all_entries = []
    seen = set()
    for jf in sorted(DATA_DIR.glob("train_*.jsonl")):
        with open(jf, encoding="utf-8") as f:
            for line in f:
                e = json.loads(line)
                uid = f"{e['key']}_{e['reciter']}"
                if uid not in seen:
                    seen.add(uid)
                    all_entries.append(e)
    out = DATA_DIR / "train_combined.jsonl"
    with open(out, "w", encoding="utf-8") as f:
        for e in all_entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(f"\nFusion : {len(all_entries)} entrées → {out}")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--list",     action="store_true", help="Lister les réciteurs")
    p.add_argument("--reciters", default="all",
                   help="Réciteurs à télécharger (séparés par virgule, ou 'all')")
    p.add_argument("--surahs",   default=None,
                   help="Sourates (ex: '1-10' ou '36,112')")
    p.add_argument("--workers",  type=int, default=8)
    p.add_argument("--merge",    action="store_true",
                   help="Fusionner tous les JSONL après téléchargement")
    args = p.parse_args()

    if args.list:
        list_reciters()
        return

    # Parser sourates
    surah_range = None
    if args.surahs:
        parts = []
        for seg in args.surahs.split(","):
            if "-" in seg:
                a, b = seg.split("-")
                parts.extend(range(int(a), int(b)+1))
            else:
                parts.append(int(seg))
        surah_range = parts

    # Parser réciteurs
    if args.reciters == "all":
        keys = list(EVERYAYAH_RECITERS.keys())
    else:
        keys = [k.strip() for k in args.reciters.split(",")]
        for k in keys:
            if k not in EVERYAYAH_RECITERS:
                print(f"Réciteur inconnu : {k}")
                list_reciters()
                sys.exit(1)

    print(f"Téléchargement de {len(keys)} réciteur(s) : {keys}")
    for key in keys:
        download_reciter(key, surah_range=surah_range, max_workers=args.workers)

    if args.merge or args.reciters == "all":
        merge_all_jsonl()

if __name__ == "__main__":
    main()
