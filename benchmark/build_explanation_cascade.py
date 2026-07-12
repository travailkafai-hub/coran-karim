"""
Construit l'index d'explication en cascade (paliers synthetique -> detail ->
erudit) pour la fonctionnalite "tap sur un verset ou un mot" — cf.
WORD_AYAH_EXPLANATION_PLAN.md. Recherche directe, PAS de LLM : le modele ne
sert jamais a generer ce contenu, seulement a repondre aux questions libres
qui ne correspondent pas a un simple lookup.

Deux sorties :
  - data/quran_sciences/ayah_explanations.jsonl : par verset, paliers 1/2/3
    en arabe/francais/anglais (tafsirs classes par verset).
  - data/quran_sciences/word_explanations.jsonl : par mot (position dans le
    verset), paliers 1/2/3 en arabe (Mufradat -> Nuzhat al-Ayun -> analyse
    grammaticale), + repli explicite sur le tafsir de verset pour FR/EN
    (aucune ressource mot-a-mot dediee trouvee dans ces langues).

Usage : python build_explanation_cascade.py [surah_debut] [surah_fin]
  Sans argument : les 114 sourates. Avec 2 arguments : juste cette plage
  (ex. "1 1" pour prototyper sur Al-Fatiha avant de generaliser).
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).parent
TAFSIR_DIR = ROOT / "data" / "tafsir"
SCIENCES_DIR = ROOT / "data" / "quran_sciences"
WORD_ROOT_INDEX = SCIENCES_DIR / "word_root_index.jsonl"
MUFRADAT_ENTRIES = SCIENCES_DIR / "ar-mufradat_entries.jsonl"
NUZHAT_ENTRIES = SCIENCES_DIR / "ar-nuzhat-ayun_entries.jsonl"

SURAH_LO = int(sys.argv[1]) if len(sys.argv) > 1 else 1
SURAH_HI = int(sys.argv[2]) if len(sys.argv) > 2 else 114

# ── Cascade ayah : quelle source pour quel palier, par langue ─────────────
AYAH_TIERS = {
    "ar": {
        1: ["ar-muyassar", "ar-jalalayn"],
        2: ["ar-saadi", "ar-ibn-kathir", "ar-baghawi"],
        # Reduit a 3 (au lieu de 10) : le palier 3 est recupere a la demande en
        # ligne (pas embarque dans l'app, cf. WORD_AYAH_EXPLANATION_PLAN.md),
        # 3 angles deliberement distincts plutot que redondants : Tabari
        # (riwaya/fondateur), Razi (rationnel/theologique), Ibn Ashur
        # (linguistique/rhetorique moderne).
        3: ["ar-tabari", "ar-razi", "ar-ibn-ashur"],
    },
    "fr": {
        1: ["fr-mokhtasar"],
        2: ["fr-montada"],
        3: [],  # rien de plus riche disponible en FR (constate lors de l'enrichissement)
    },
    "en": {
        1: ["en-mukhtasar"],
        2: ["en-ibn-kathir", "en-maarif"],
        3: ["en-tazkirul", "en-jalalayn", "en-ibn-abbas"],
    },
}

TAFSIR_DISPLAY = {
    "ar-muyassar": "Tafsir al-Muyassar", "ar-jalalayn": "Tafsir al-Jalalayn",
    "ar-saadi": "Tafsir as-Saadi", "ar-ibn-kathir": "Tafsir Ibn Kathir",
    "ar-baghawi": "Tafsir al-Baghawi", "ar-tabari": "Tafsir at-Tabari",
    "ar-qurtubi": "Tafsir al-Qurtubi", "ar-kashshaf": "Al-Kashshaf (az-Zamakhshari)",
    "ar-ibn-ashur": "At-Tahrir wa at-Tanwir (Ibn Ashur)", "ar-razi": "Mafatih al-Ghayb (ar-Razi)",
    "ar-alusi": "Ruh al-Ma'ani (al-Alusi)", "ar-bahr-muhit": "Al-Bahr al-Muhit (Abu Hayyan)",
    "ar-baydawi": "Anwar at-Tanzil (al-Baydawi)", "ar-shawkani": "Fath al-Qadir (ash-Shawkani)",
    "ar-durr-manthur": "ad-Durr al-Manthur (as-Suyuti)",
    "fr-mokhtasar": "Tafsir Al-Mukhtasar (FR)", "fr-montada": "Tafsir Al-Montada (FR)",
    "en-mukhtasar": "Tafsir Al-Mukhtasar (EN)", "en-ibn-kathir": "Tafsir Ibn Kathir (EN)",
    "en-maarif": "Maarif-ul-Quran (EN)", "en-tazkirul": "Tazkirul Qur'an (EN)",
    "en-jalalayn": "Tafsir al-Jalalayn (EN)", "en-ibn-abbas": "Tanwir al-Miqbas (EN)",
}

MIN_LEN = 15


def in_range(verse_key):
    s = int(verse_key.split(":")[0])
    return SURAH_LO <= s <= SURAH_HI


def load_tafsir(slug):
    path = TAFSIR_DIR / f"{slug}.jsonl"
    if not path.exists():
        return {}
    out = {}
    with open(path, encoding="utf-8") as f:
        for l in f:
            o = json.loads(l)
            if in_range(o["verse_key"]) and len(o.get("text", "")) >= MIN_LEN:
                out[o["verse_key"]] = o["text"]
    return out


def build_ayah_explanations():
    all_tafsirs = {}
    for lang_tiers in AYAH_TIERS.values():
        for slugs in lang_tiers.values():
            for slug in slugs:
                if slug not in all_tafsirs:
                    all_tafsirs[slug] = load_tafsir(slug)

    verse_keys = set()
    for tafsirs in all_tafsirs.values():
        verse_keys.update(tafsirs.keys())

    # Palier 3 : PAS embarque dans l'app (817 Mo pour 10 sources ; meme reduit a
    # 3 sources, ca reste trop lourd a bundler) -> un fichier JSON par verset
    # dans tier3/{surah}/{ayah}.json, recupere a la demande uniquement si
    # l'utilisateur clique "approfondir davantage" (cf. WORD_AYAH_EXPLANATION_PLAN.md).
    # Paliers 1+2 (toutes langues) : embarques offline dans ayah_explanations.jsonl.
    tier3_dir = SCIENCES_DIR / "tier3"
    tier3_dir.mkdir(exist_ok=True)

    n = 0
    n_tier3 = 0
    with open(SCIENCES_DIR / "ayah_explanations.jsonl", "w", encoding="utf-8") as out:
        for vk in sorted(verse_keys, key=lambda k: (int(k.split(":")[0]), int(k.split(":")[1]))):
            entry = {"verse_key": vk}
            tier3_by_lang = {}  # accumule TOUTES les langues avant d'ecrire (bug corrige :
            # AR et EN ont chacun un palier 3, ecrire au fil de la boucle langue par langue
            # sur le MEME fichier {surah}/{ayah}.json ecrasait l'AR par l'EN)
            for lang, tiers in AYAH_TIERS.items():
                lang_entry = {}
                for tier, slugs in tiers.items():
                    found = []
                    for slug in slugs:
                        txt = all_tafsirs.get(slug, {}).get(vk)
                        if txt:
                            found.append({"source": TAFSIR_DISPLAY[slug], "text": txt})
                    if not found:
                        continue
                    if tier == 3:
                        tier3_by_lang[lang] = found
                    else:
                        lang_entry[str(tier)] = found
                if lang_entry:
                    entry[lang] = lang_entry
            if tier3_by_lang:
                surah, ayah = vk.split(":")
                d = tier3_dir / surah
                d.mkdir(exist_ok=True)
                with open(d / f"{ayah}.json", "w", encoding="utf-8") as t3:
                    json.dump({"verse_key": vk, **tier3_by_lang}, t3, ensure_ascii=False)
                n_tier3 += 1
            out.write(json.dumps(entry, ensure_ascii=False) + "\n")
            n += 1
    print(f"{n} versets -> ayah_explanations.jsonl (paliers 1+2, offline)", flush=True)
    print(f"{n_tier3} fichiers palier 3 -> {tier3_dir}/ (a heberger, recupere a la demande)", flush=True)


# ── Cascade mot : Mufradat -> Nuzhat al-Ayun -> analyse grammaticale (AR) ──

TASHKEEL_RE = re.compile(r"[ً-ْٰ]")


def norm_root(r):
    """Normalisation minimale pour reconcilier la racine triliterale complete
    (donnee par tahlil-kalimat, ex. 'ربب') avec la forme d'entree Mufradat
    (souvent contractee pour les racines a lettre doublee, ex. 'رب')."""
    r = TASHKEEL_RE.sub("", r or "").strip()
    variants = [r]
    if len(r) == 3 and r[1] == r[2]:
        variants.append(r[:2])  # ربب -> رب
    return variants


def load_entries(path):
    if not path.exists():
        return {}
    out = {}
    with open(path, encoding="utf-8") as f:
        for l in f:
            o = json.loads(l)
            out.setdefault(o["heading"].strip(), []).append(o["text"])
    return out


def build_word_explanations():
    mufradat = load_entries(MUFRADAT_ENTRIES)
    nuzhat_raw = load_entries(NUZHAT_ENTRIES)
    nuzhat = {re.sub(r"^\s*باب\s+", "", k).strip(): v for k, v in nuzhat_raw.items()}

    n = 0
    matched_root = 0
    total_words = 0
    with open(WORD_ROOT_INDEX, encoding="utf-8") as f, \
         open(SCIENCES_DIR / "word_explanations.jsonl", "w", encoding="utf-8") as out:
        for l in f:
            o = json.loads(l)
            if not in_range(o["verse_key"]):
                continue
            words_out = []
            for pos, w in enumerate(o["words"]):
                total_words += 1
                entry = {"surface": w["surface"], "position": pos}
                root = w.get("root")
                if root:
                    tiers = {}
                    for variant in norm_root(root):
                        if variant in mufradat and "1" not in tiers:
                            tiers["1"] = [{"source": "Al-Mufradat fi Gharib al-Qur'an (ar-Raghib al-Isfahani)",
                                           "text": "\n".join(mufradat[variant])}]
                        if variant in nuzhat and "2" not in tiers:
                            tiers["2"] = [{"source": "Nuzhat al-A'yun (Ibn al-Jawzi) - al-wujuh wal-naza'ir",
                                           "text": "\n".join(nuzhat[variant])}]
                    if tiers:
                        matched_root += 1
                        entry["root"] = root
                        entry["ar"] = tiers
                words_out.append(entry)
            out.write(json.dumps({"verse_key": o["verse_key"], "words": words_out}, ensure_ascii=False) + "\n")
            n += 1
    print(f"{n} versets -> word_explanations.jsonl", flush=True)
    print(f"  mots avec au moins 1 palier trouve : {matched_root}/{total_words} "
          f"({100*matched_root/total_words:.1f}%)" if total_words else "  aucun mot", flush=True)


def main():
    print(f"Plage : sourates {SURAH_LO}-{SURAH_HI}", flush=True)
    build_ayah_explanations()
    build_word_explanations()
    print("CASCADE BUILD DONE", flush=True)


if __name__ == "__main__":
    main()
