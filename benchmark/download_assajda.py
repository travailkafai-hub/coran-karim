"""
Télécharge les récitations du Coran depuis assajda.com (CDN media.assabile.com).

Fonctionnement :
1. Fetch page réciteur -> id_collection_default
2. Fetch /fr/ajax/loadplayer-{person_id}-{collection_id} -> JSON playlist (114 sourates)
3. Pour chaque sourate : /fr/ajax/getrcita-link-{rec_id} -> URL MP3 directe
4. Télécharge MP3 -> WAV 16kHz -> découpe verset par verset (division uniforme)
5. Génère JSONL NeMo-compatible

Usage :
    python download_assajda.py --list
    python download_assajda.py --reciter OmarKazabri
    python download_assajda.py --reciter all
    python download_assajda.py --reciter OmarKazabri,LaayounKouchi
"""

import os, sys, re, json, time, argparse
import urllib.request
from pathlib import Path
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
WAV_DIR  = DATA_DIR / "train_wav"
MP3_DIR  = DATA_DIR / "train"

def set_data_dir(data_dir_path: str):
    global DATA_DIR, WAV_DIR, MP3_DIR
    DATA_DIR = Path(data_dir_path)
    WAV_DIR  = DATA_DIR / "train_wav"
    MP3_DIR  = DATA_DIR / "train"
    DATA_DIR.mkdir(parents=True, exist_ok=True)

# ── Tous les réciteurs disponibles sur assajda.com pas encore dans le dataset ─
# person_id : visible dans l'URL /fr/{slug}-{person_id}.html
# collection_id : lu automatiquement depuis la page (id_collection_default)
# riwaya : "Warsh" pour Maghreb/Algérie, "Hafs" pour le reste
ASSAJDA_RECITERS = {
    # ── Réciteurs marocains (Warsh) ──────────────────────────────────────────
    "OmarKazabri": {
        "name_ar":     "عمر القزابري",
        "name_fr":     "Omar Al-Kazabri",
        "slug":        "omar-al-kazabri",
        "person_id":   "15",
        "out_name":    "OmarKazabri_assajda",
        "riwaya":      "Warsh",
    },
    "LaayounKouchi": {
        "name_ar":     "لعيون الكوشي",
        "name_fr":     "Laayoun El Kouchi",
        "slug":        "laayoun-el-kouchi",
        "person_id":   "22",
        "out_name":    "LaayounKouchi_assajda",
        "riwaya":      "Warsh",
    },
    "MustaphaGharbi": {
        "name_ar":     "مصطفى الغربي",
        "name_fr":     "Mustapha Gharbi",
        "slug":        "mustapha-gharbi",
        "person_id":   "101",
        "out_name":    "MustaphaGharbi_assajda",
        "riwaya":      "Warsh",
    },
    "MohamedKantaoui": {
        "name_ar":     "محمد الكنتاوي",
        "name_fr":     "Mohamed El Kantaoui",
        "slug":        "mohamed-el-kantaoui",
        "person_id":   "88",
        "out_name":    "MohamedKantaoui_assajda",
        "riwaya":      "Warsh",
    },
    "MohamedHamdan": {
        "name_ar":     "محمد الطيب حمدان",
        "name_fr":     "Mohamed Al Tayeb Hamdan",
        "slug":        "mohamed-al-tayeb-hamdan",
        "person_id":   "87",
        "out_name":    "MohamedHamdan_assajda",
        "riwaya":      "Warsh",
    },
    "YoussefEdghouch": {
        "name_ar":     "يوسف أدغوش",
        "name_fr":     "Youssef Edghouch",
        "slug":        "youssef-edghouch",
        "person_id":   "256",
        "out_name":    "YoussefEdghouch_assajda",
        "riwaya":      "Warsh",
    },
    "NurdinMaghriby": {
        "name_ar":     "نور الدين حمزة المغربي",
        "name_fr":     "NurDin Hamza Al Maghriby",
        "slug":        "nurdin-hamza-al-maghriby",
        "person_id":   "42",
        "out_name":    "NurdinMaghriby_assajda",
        "riwaya":      "Warsh",
    },
    "RachidIfrad": {
        "name_ar":     "رشيد إفراد",
        "name_fr":     "Rachid Ifrad",
        "slug":        "rachid-ifrad",
        "person_id":   "218",
        "out_name":    "RachidIfrad_assajda",
        "riwaya":      "Warsh",
    },
    "AbdelmoujibBenkirane": {
        "name_ar":     "عبد المجيب بنكيران",
        "name_fr":     "Abdelmoujib Benkirane",
        "slug":        "abdelmoujib-benkirane",
        "person_id":   "310",
        "out_name":    "AbdelmoujibBenkirane_assajda",
        "riwaya":      "Warsh",
    },
    "MohamedAlJabery": {
        "name_ar":     "محمد الجابري الحياني",
        "name_fr":     "Mohamed Aljabery Al Heyani",
        "slug":        "mohamed-aljabery-al-heyani",
        "person_id":   "89",
        "out_name":    "MohamedAlJabery_assajda",
        "riwaya":      "Warsh",
    },
    "AbdelhamidHssain": {
        "name_ar":     "عبد الحميد حسين",
        "name_fr":     "Abdelhamid Hssain",
        "slug":        "abdelhamid-hssain",
        "person_id":   "359",
        "out_name":    "AbdelhamidHssain_assajda",
        "riwaya":      "Warsh",
    },
    "AbdelKabirHadidi": {
        "name_ar":     "عبد الكبير الحديدي",
        "name_fr":     "Abdel-Kabir El Hadidi",
        "slug":        "abdel-kabir-el-hadidi",
        "person_id":   "361",
        "out_name":    "AbdelKabirHadidi_assajda",
        "riwaya":      "Warsh",
    },
    "SamirBelaachya": {
        "name_ar":     "سمير بلعشية",
        "name_fr":     "Samir Belaachya",
        "slug":        "samir-belaachya",
        "person_id":   "65",
        "out_name":    "SamirBelaachya_assajda",
        "riwaya":      "Warsh",
    },
    "MohamedElIraoui": {
        "name_ar":     "محمد العراوي",
        "name_fr":     "Mohamed El Iraoui",
        "slug":        "mohamed-el-iraoui",
        "person_id":   "240",
        "out_name":    "MohamedElIraoui_assajda",
        "riwaya":      "Warsh",
    },
    "MohamedChahboun": {
        "name_ar":     "محمد شهبون",
        "name_fr":     "Mohamed Chahboun",
        "slug":        "mohamed-chahboun",
        "person_id":   "376",
        "out_name":    "MohamedChahboun_assajda",
        "riwaya":      "Warsh",
    },
    "RachidBelaachya": {
        "name_ar":     "رشيد بلعشية",
        "name_fr":     "Rachid Belaachya",
        "slug":        "rachid-belaachya",
        "person_id":   "389",
        "out_name":    "RachidBelaachya_assajda",
        "riwaya":      "Warsh",
    },
    "FaysalWizar": {
        "name_ar":     "فيصل وزار",
        "name_fr":     "Faysal Wizar",
        "slug":        "faysal-wizar",
        "person_id":   "391",
        "out_name":    "FaysalWizar_assajda",
        "riwaya":      "Warsh",
    },
    "AbdurrahimNabulsi": {
        "name_ar":     "عبد الرحيم عبد السلام النابلسي",
        "name_fr":     "Abdurrahim Abdussalam An-Nabulsi",
        "slug":        "abdurrahim-abdussalam-an-nabulsi",
        "person_id":   "403",
        "out_name":    "AbdurrahimNabulsi_assajda",
        "riwaya":      "Warsh",
    },
    "HosseinBousseksso": {
        "name_ar":     "حسين بوسكسو",
        "name_fr":     "Hossein Bousseksso",
        "slug":        "hossein-bousseksso",
        "person_id":   "409",
        "out_name":    "HosseinBousseksso_assajda",
        "riwaya":      "Warsh",
    },
    # ── Réciteurs algériens (Warsh) ───────────────────────────────────────────
    "RachidBelalia": {
        "name_ar":     "رشيد بلالية",
        "name_fr":     "Rachid Belalia",
        "slug":        "rachid-belalia",
        "person_id":   "219",
        "out_name":    "RachidBelalia_assajda",
        "riwaya":      "Warsh",
    },
    "ZakariaHamama": {
        "name_ar":     "زكريا حمامة",
        "name_fr":     "Zakaria Hamama",
        "slug":        "zakaria-hamama",
        "person_id":   "222",
        "out_name":    "ZakariaHamama_assajda",
        "riwaya":      "Warsh",
    },
    "YassenAlJazairi": {
        "name_ar":     "ياسين الجزائري",
        "name_fr":     "Yassen Al Jazairi",
        "slug":        "yassen-al-jazairi",
        "person_id":   "37",
        "out_name":    "YassenJazairi_assajda",
        "riwaya":      "Warsh",
    },
    # ── Réciteurs non encore dans le dataset (Hafs) ───────────────────────────
    "AbdallahMatroud": {
        "name_ar":     "عبد الله ماطرود",
        "name_fr":     "Abdallah Matroud",
        "slug":        "abdallah-matroud",
        "person_id":   "5",
        "out_name":    "AbdallahMatroud_assajda",
        "riwaya":      "Hafs",
    },
    "AbdulRashidSufi": {
        "name_ar":     "عبد الرشيد علي صوفي",
        "name_fr":     "Abdul Rashid Ali Sufi",
        "slug":        "abdul-rashid-ali-sufi",
        "person_id":   "26",
        "out_name":    "AbdulRashidSufi_assajda",
        "riwaya":      "Hafs",
    },
    "AbdulWadudHaneef": {
        "name_ar":     "عبد الودود حنيف",
        "name_fr":     "Abdul Wadud Haneef",
        "slug":        "abdul-wadud-haneef",
        "person_id":   "30",
        "out_name":    "AbdulWadudHaneef_assajda",
        "riwaya":      "Hafs",
    },
    "AdelKalbani": {
        "name_ar":     "عادل الكلباني",
        "name_fr":     "Adel Al Kalbani",
        "slug":        "adel-al-kalbani",
        "person_id":   "44",
        "out_name":    "AdelKalbani_assajda",
        "riwaya":      "Hafs",
    },
    "IdrissAbkar": {
        "name_ar":     "إدريس أبكر",
        "name_fr":     "Idriss Abkar",
        "slug":        "idriss-abkar",
        "person_id":   "90",
        "out_name":    "IdrissAbkar_assajda",
        "riwaya":      "Hafs",
    },
    "AhmedSaoud": {
        "name_ar":     "أحمد سعود",
        "name_fr":     "Ahmed Saoud",
        "slug":        "ahmed-saoud",
        "person_id":   "55",
        "out_name":    "AhmedSaoud_assajda",
        "riwaya":      "Hafs",
    },
    "MohamedElBarak": {
        "name_ar":     "محمد البراك",
        "name_fr":     "Mohamed El Barak",
        "slug":        "mohamed-el-barak",
        "person_id":   "60",
        "out_name":    "MohamedElBarak_assajda",
        "riwaya":      "Hafs",
    },
    "MohamedAlMohisni": {
        "name_ar":     "محمد المحيسني",
        "name_fr":     "Mohamed Al Mohisni",
        "slug":        "mohamed-al-mohisni",
        "person_id":   "66",
        "out_name":    "MohamedMohisni_assajda",
        "riwaya":      "Hafs",
    },
    "AlzainMohamedAhmed": {
        "name_ar":     "الزين محمد أحمد",
        "name_fr":     "Alzain Mohamed Ahmed",
        "slug":        "alzain-mohamed-ahmed",
        "person_id":   "76",
        "out_name":    "AlzainMohamedAhmed_assajda",
        "riwaya":      "Hafs",
    },
    "MustaphaLahouni": {
        "name_ar":     "مصطفى اللاهوني",
        "name_fr":     "Mustapha Al Lahouni",
        "slug":        "mustapha-al-lahouni",
        "person_id":   "49",
        "out_name":    "MustaphaLahouni_assajda",
        "riwaya":      "Hafs",
    },
    "KhalidAlJalil": {
        "name_ar":     "خالد الجليل",
        "name_fr":     "Khalid Al Jalil",
        "slug":        "khalid-al-jalil",
        "person_id":   "307",
        "out_name":    "KhalidAlJalil_assajda",
        "riwaya":      "Hafs",
    },
    # ── Réciteurs égyptiens (Hafs) ────────────────────────────────────────────
    "AntarMuslim": {
        "name_ar":     "عنتر مسلم",
        "name_fr":     "Antar Muslim",
        "slug":        "antar-muslim",
        "person_id":   "10",
        "out_name":    "AntarMuslim_assajda",
        "riwaya":      "Hafs",
    },
    "SaberAbdulHakam": {
        "name_ar":     "صابر عبد الحكم",
        "name_fr":     "Saber Abdul Hakam",
        "slug":        "saber-abdul-hakam",
        "person_id":   "77",
        "out_name":    "SaberAbdulHakam_assajda",
        "riwaya":      "Hafs",
    },
    "HassanSaleh": {
        "name_ar":     "حسن صالح",
        "name_fr":     "Hassan Saleh",
        "slug":        "hassan-saleh",
        "person_id":   "111",
        "out_name":    "HassanSaleh_assajda",
        "riwaya":      "Hafs",
    },
    "AbdallahKamel": {
        "name_ar":     "عبد الله كامل",
        "name_fr":     "Abdallah Kamel",
        "slug":        "abdallah-kamel",
        "person_id":   "318",
        "out_name":    "AbdallahKamel_assajda",
        "riwaya":      "Hafs",
    },
}

SURAH_VERSE_COUNT = [
    7,286,200,176,120,165,206,75,129,109,
    123,111,43,52,99,128,111,110,98,135,
    112,78,118,64,77,227,93,88,69,60,
    34,30,73,54,45,83,182,88,75,85,
    54,53,89,59,37,35,38,29,18,45,
    60,49,62,55,78,96,29,22,24,13,
    14,11,11,18,12,12,30,52,52,44,
    28,28,20,56,40,31,50,40,46,42,
    29,19,36,25,22,17,19,26,30,20,
    15,21,11,8,8,19,5,8,8,11,
    11,8,3,9,5,4,7,3,6,3,
    5,4,5,6,5,9,0
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "Accept": "*/*",
    "X-Requested-With": "XMLHttpRequest",
}

def fetch(url, referer=None, retries=3):
    h = dict(HEADERS)
    if referer:
        h["Referer"] = referer
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=h)
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.read().decode("utf-8", errors="ignore")
        except Exception as e:
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)

def get_collection_id(person_id: str, slug: str) -> str:
    """Récupère id_collection_default depuis la page du réciteur."""
    page_url = f"https://www.assajda.com/fr/{slug}-{person_id}.html"
    h = dict(HEADERS); h["Accept"] = "text/html,*/*"
    req = urllib.request.Request(page_url, headers=h)
    with urllib.request.urlopen(req, timeout=15) as r:
        html = r.read().decode("utf-8", errors="ignore")
    m = re.search(r"var id_collection_default\s*=\s*['\"]?(\d+)['\"]?", html)
    if m:
        return m.group(1)
    # Cherche dans les options
    m = re.search(r'value="/fr/ajax/loadplayer-\d+-(\d+)"[^>]*class="current_filtre"', html)
    if m:
        return m.group(1)
    raise ValueError(f"id_collection_default non trouvé pour {slug}-{person_id}")

def get_playlist(person_id: str, collection_id: str) -> list[dict]:
    """Retourne la liste des sourates avec leur rec_id."""
    url = f"https://www.assajda.com/fr/ajax/loadplayer-{person_id}-{collection_id}"
    referer = f"https://www.assajda.com/fr/"
    raw = fetch(url, referer=referer)
    data = json.loads(raw)
    result = []
    for r in data.get("Recitation", []):
        sura_id = int(r["sura_id"])
        rec_id  = r["href"].lstrip("#")
        result.append({
            "sura_id": sura_id,
            "rec_id": rec_id,
            "name": r.get("span_name", f"Surah {sura_id}"),
            "duration": r.get("duration", ""),
        })
    return sorted(result, key=lambda x: x["sura_id"])

def get_mp3_url(rec_id: str, referer: str) -> str:
    """Appelle getrcita-link pour obtenir l'URL MP3 directe."""
    url = f"https://www.assajda.com/fr/ajax/getrcita-link-{rec_id}"
    result = fetch(url, referer=referer).strip()
    if not result.startswith("http"):
        raise ValueError(f"URL invalide pour rec_id={rec_id}: {result}")
    return result

def download_mp3(url: str, out_path: Path) -> bool:
    """Télécharge un MP3 depuis media.assabile.com."""
    if out_path.exists() and out_path.stat().st_size > 50000:
        return True
    out_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": HEADERS["User-Agent"],
            "Referer": "https://www.assajda.com/",
        })
        with urllib.request.urlopen(req, timeout=300) as r:
            data = r.read()
        if len(data) < 50000:
            return False
        out_path.write_bytes(data)
        return True
    except Exception as e:
        print(f"    Erreur download: {e}")
        return False

def to_wav_16k(mp3: Path, wav: Path) -> bool:
    if wav.exists() and wav.stat().st_size > 1000:
        return True
    r = subprocess.run(
        ["ffmpeg", "-y", "-i", str(mp3), "-ar", "16000", "-ac", "1", str(wav)],
        capture_output=True
    )
    return r.returncode == 0 and wav.exists()

def load_quran_text() -> dict:
    quran = {}
    candidates = [
        DATA_DIR / "manifest_full_wav.jsonl",
        DATA_DIR / "train_combined.jsonl",
        # Fallback quand DATA_DIR est sur un autre disque (ex: E:\Coran_data)
        BASE_DIR / "data" / "manifest_full_wav.jsonl",
        BASE_DIR / "data" / "train_combined.jsonl",
    ]
    for src in candidates:
        if src.exists():
            with open(src, encoding="utf-8") as f:
                for line in f:
                    try:
                        e = json.loads(line)
                        if e.get("text"):
                            quran[e.get("key", "")] = e["text"]
                    except Exception:
                        pass
            if quran:
                print(f"  Texte Coran: {len(quran)} versets chargés depuis {src}")
                break
    return quran

def split_by_verse_uniform(wav_path: Path, surah: int, wav_out_dir: Path,
                            out_name: str, quran_text: dict) -> list[dict]:
    """Découpe le WAV surah en versets par division uniforme."""
    try:
        import soundfile as sf
        import numpy as np
    except ImportError:
        print("  Installe soundfile : pip install soundfile")
        return []

    audio, sr = sf.read(str(wav_path))
    if sr != 16000:
        raise ValueError(f"Échantillonnage inattendu: {sr}")

    n_verses = SURAH_VERSE_COUNT[surah - 1]
    if n_verses == 0:
        return []

    total = len(audio)
    per_v = total // n_verses
    results = []
    for v in range(1, n_verses + 1):
        key  = f"{surah}:{v}"
        text = quran_text.get(key, "")
        if not text:
            continue
        s   = (v - 1) * per_v
        e   = v * per_v if v < n_verses else total
        seg = audio[s:e]
        if len(seg) < 1600:  # moins de 0.1s
            continue
        wav_out = wav_out_dir / f"{surah}_{v}.wav"
        sf.write(str(wav_out), seg, 16000, subtype="PCM_16")
        try:
            wav_rel = str(wav_out.relative_to(BASE_DIR)).replace("\\", "/")
        except ValueError:
            wav_rel = str(wav_out.absolute()).replace("\\", "/")
        results.append({
            "key":     key,
            "reciter": out_name,
            "text":    text,
            "wav":     wav_rel,
            "duration": round(len(seg) / 16000, 3),
        })
    return results

def process_reciter(key: str, surahs: list[int] | None = None, keep_surah_wav: bool = False):
    cfg = ASSAJDA_RECITERS.get(key)
    if cfg is None:
        print(f"Réciteur inconnu : {key}")
        return 0

    person_id = cfg["person_id"]
    out_name  = cfg["out_name"]
    slug      = cfg["slug"]
    referer   = f"https://www.assajda.com/fr/{slug}-{person_id}.html"

    mp3_dir = MP3_DIR / out_name
    wav_dir = WAV_DIR / out_name
    mp3_dir.mkdir(parents=True, exist_ok=True)
    wav_dir.mkdir(parents=True, exist_ok=True)

    quran_text = load_quran_text()

    print(f"\n[{key}] {cfg['name_fr']} ({cfg['riwaya']})")

    # Collection ID
    print(f"  Récupération collection ID...")
    try:
        coll_id = get_collection_id(person_id, slug)
        print(f"  collection_id = {coll_id}")
    except Exception as e:
        print(f"  ERREUR collection_id: {e}")
        return 0

    # Playlist
    print(f"  Chargement playlist (loadplayer-{person_id}-{coll_id})...")
    try:
        playlist = get_playlist(person_id, coll_id)
        print(f"  {len(playlist)} sourates dans la playlist")
    except Exception as e:
        print(f"  ERREUR playlist: {e}")
        return 0

    if surahs:
        playlist = [p for p in playlist if p["sura_id"] in surahs]

    all_results = []

    # Phase 1 : collecter toutes les URLs MP3 (API séquentielle)
    print(f"  Récupération des {len(playlist)} URLs MP3...")
    surah_jobs = []
    for item in playlist:
        surah  = item["sura_id"]
        rec_id = item["rec_id"]
        mp3_out = mp3_dir / f"{surah:03d}.mp3"
        wav_out = mp3_dir / f"{surah:03d}.wav"
        if mp3_out.exists() and mp3_out.stat().st_size > 50000:
            mp3_url = None  # déjà téléchargé
        else:
            try:
                mp3_url = get_mp3_url(rec_id, referer)
                time.sleep(0.2)
            except Exception as e:
                print(f"  Sourate {surah:3d}: ERREUR URL - {e}")
                continue
        surah_jobs.append({**item, "mp3_url": mp3_url, "mp3_out": mp3_out, "wav_out": wav_out})

    # Phase 2 : télécharger les MP3 en parallèle
    def download_and_split(job):
        surah   = job["sura_id"]
        name    = job["name"]
        mp3_out = job["mp3_out"]
        wav_out = job["wav_out"]
        mp3_url = job["mp3_url"]

        if mp3_url and not download_mp3(mp3_url, mp3_out):
            return surah, name, []
        if not to_wav_16k(mp3_out, wav_out):
            return surah, name, []
        results = split_by_verse_uniform(wav_out, surah, wav_dir, out_name, quran_text)
        # Supprime le WAV sourate après découpage (économise ~2x l'espace disque)
        if not keep_surah_wav and wav_out.exists():
            wav_out.unlink()
        return surah, name, results

    workers = min(6, len(surah_jobs))
    print(f"  Téléchargement + découpage ({workers} workers)...")
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(download_and_split, j): j for j in surah_jobs}
        done = 0
        for fut in as_completed(futures):
            try:
                surah, name, results = fut.result()
                all_results.extend(results)
                done += 1
                sz = os.path.getsize(futures[fut]["mp3_out"]) // 1024 if futures[fut]["mp3_out"].exists() else 0
                print(f"  [{done:3d}/{len(surah_jobs)}] Sourate {surah:3d} ({name:20s}): "
                      f"{len(results):3d} versets ({sz}KB)")
            except Exception as e:
                print(f"  ERREUR: {e}")

    # Sauvegarde JSONL
    if all_results:
        out_jsonl = DATA_DIR / f"train_{out_name}.jsonl"
        with open(out_jsonl, "w", encoding="utf-8") as f:
            for e in sorted(all_results, key=lambda x: (int(x["key"].split(":")[0]),
                                                         int(x["key"].split(":")[1]))):
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        print(f"\n  [{key}] {len(all_results)} versets -> {out_jsonl.name}")

    return len(all_results)

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--list",    action="store_true", help="Lister les réciteurs disponibles")
    p.add_argument("--reciter", default=None,
                   help="ID du réciteur (voir --list), 'all' pour tous, ou liste séparée par virgule")
    p.add_argument("--surahs",  default=None,
                   help="Sourates à télécharger ex: 1-10 ou 1,2,36,112")
    p.add_argument("--keep-surah-wav", action="store_true",
                   help="Conserver les WAVs sourate après découpage (par défaut : supprimés)")
    p.add_argument("--data-dir", default=None,
                   help="Répertoire de données alternatif (ex: E:\\Coran_data)")
    args = p.parse_args()

    if args.list or not args.reciter:
        print("\nRéciteurs disponibles sur assajda.com:\n")
        for k, v in ASSAJDA_RECITERS.items():
            print(f"  {k:25s}  {v['name_fr']:30s}  ({v['riwaya']})")
        print("\nUsage: python download_assajda.py --reciter OmarKazabri")
        print("       python download_assajda.py --reciter all")
        return

    # Parse surahs
    surah_filter = None
    if args.surahs:
        surah_filter = []
        for seg in args.surahs.split(","):
            if "-" in seg:
                a, b = seg.split("-")
                surah_filter.extend(range(int(a), int(b) + 1))
            else:
                surah_filter.append(int(seg))

    # Sélection des réciteurs
    if args.reciter == "all":
        keys = list(ASSAJDA_RECITERS.keys())
    else:
        keys = [k.strip() for k in args.reciter.split(",")]

    if args.data_dir:
        set_data_dir(args.data_dir)
        print(f"Data dir: {DATA_DIR}")

    keep_wav = args.keep_surah_wav if hasattr(args, "keep_surah_wav") else False
    total = 0
    for key in keys:
        n = process_reciter(key, surah_filter, keep_surah_wav=keep_wav)
        total += n

    print(f"\n=== Total : {total} versets téléchargés ===")

if __name__ == "__main__":
    main()
