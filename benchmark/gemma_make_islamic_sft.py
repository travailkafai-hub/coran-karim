"""
Construit le SFT islamique enrichi pour Gemma (FR + AR).

Sources :
  - TAFSIR  : data/tafsir/*.jsonl  (classiques: ibn-kathir, tabari, qurtubi,
              jalalayn, baghawi, saadi, muyassar + trad FR montada/hamidullah/rashid
              + fr-mokhtasar)
  - HADITH  : data/islamic_corpus/hadith/*.jsonl  (6 livres canoniques, FR+AR, grades)

Principe d'authenticite :
  - Chaque reponse CITE sa source (nom du tafsir / recueil + numero + grade).
  - Hadith : Bukhari & Muslim inclus d'office (sahih par consensus).
             Les 4 Sunan filtres sur grade Sahih/Hasan (daif exclus de l'entrainement).
  - Le modele apprend a ATTRIBUER, pas a inventer.

Sortie : data/gemma_islamic_sft.jsonl   format {"system","user","target"}
"""
import json, os, random, re, glob
random.seed(42)

ROOT       = os.path.dirname(os.path.abspath(__file__))
TAFSIR_DIR = os.path.join(ROOT, "data", "tafsir")
HADITH_DIR = os.path.join(ROOT, "data", "islamic_corpus", "hadith")
SCIENCES_DIR = os.path.join(ROOT, "data", "quran_sciences")
MANIFEST   = os.path.join(ROOT, "data", "manifest_full.jsonl")
OUT        = os.environ.get("GEMMA_SFT_OUT", os.path.join(ROOT, "data", "gemma_islamic_sft_v2.jsonl"))

MUFRADAT_ENTRIES = os.path.join(SCIENCES_DIR, "ar-mufradat_entries.jsonl")
NUZHAT_ENTRIES   = os.path.join(SCIENCES_DIR, "ar-nuzhat-ayun_entries.jsonl")

# Chapitres "wujuh wal-naza'ir" reperes par en-tete exacte dans les encyclopedies
# generalistes (le reste de ces livres traite d'autres sujets : asbab an-nuzul,
# i'rab, naskh... hors-sujet pour ce lot -> on isole strictement ce chapitre).
WUJUH_CHAPTERS = {
    "ar-itqan":  {"range": (526, 547), "name": "الإتقان في علوم القرآن", "author": "السيوطي"},
    "ar-burhan": {"range": (119, 128), "name": "البرهان في علوم القرآن", "author": "الزركشي"},
}

AR_LETTER_RE = re.compile(r"[ء-غف-ي]")
TASHKEEL_RE = re.compile(r"[ً-ْٰ]")

MIN_LEN    = 40
MAX_TARGET = 2200    # caractères (eviter les tafsirs ultra-longs type Tabari/Razi)

SYSTEM = ("Tu es un assistant specialise dans les sciences islamiques : Coran, "
          "tafsir (exegese), et hadith. Tu reponds en citant systematiquement tes "
          "sources authentiques (nom de l'exegete ou du recueil, numero, et grade "
          "d'authenticite pour les hadiths). Tu es precis, pedagogue et tu ne "
          "pretends jamais une information dont tu n'as pas la source.")

# Noms d'affichage des tafsirs (slug fichier -> (nom, langue))
TAFSIR_META = {
    "ar-ibn-kathir":   ("Tafsir Ibn Kathir", "ar"),
    "ar-tabari":       ("Tafsir at-Tabari", "ar"),
    "ar-qurtubi":      ("Tafsir al-Qurtubi", "ar"),
    "ar-jalalayn":     ("Tafsir al-Jalalayn", "ar"),
    "ar-baghawi":      ("Tafsir al-Baghawi", "ar"),
    "ar-saadi":        ("Tafsir as-Saadi", "ar"),
    "ar-muyassar":     ("Tafsir al-Muyassar", "ar"),
    "en-ibn-kathir":   ("Tafsir Ibn Kathir (EN)", "en"),
    "en-maarif":       ("Maarif-ul-Quran (EN)", "en"),
    "fr-hamidullah":   ("Traduction Hamidullah", "fr"),
    "fr-montada":      ("Tafsir Al-Montada (FR)", "fr"),
    "fr-rashid-maash": ("Traduction Rashid Maash", "fr"),
    "fr-mokhtasar":    ("Tafsir Al-Mukhtasar (FR)", "fr"),
    "ar-tahlil-kalimat":  ("Tahlil Kalimat al-Qur'an (analyse lexicale)", "ar"),
    "ar-kashshaf":        ("Al-Kashshaf (az-Zamakhshari)", "ar"),
    "ar-ibn-ashur":       ("At-Tahrir wa at-Tanwir (Ibn Ashur)", "ar"),
    "ar-siraj-gharib":    ("As-Siraj fi Bayan Gharib al-Qur'an", "ar"),
    "ar-muyassar-gharib": ("Al-Muyassar fi al-Gharib", "ar"),
}

HADITH_DISPLAY = {
    "bukhari": "Sahih al-Bukhari", "muslim": "Sahih Muslim",
    "abudawud": "Sunan Abu Dawud", "tirmidhi": "Jami at-Tirmidhi",
    "nasai": "Sunan an-Nasa'i", "ibnmajah": "Sunan Ibn Majah",
}
SAHIH_BY_CONSENSUS = {"bukhari", "muslim"}


# ── Chargement versets canoniques ──────────────────────────────────────────────

def load_verses():
    arabic = {}
    if os.path.exists(MANIFEST):
        for l in open(MANIFEST, encoding="utf-8"):
            v = json.loads(l)
            arabic.setdefault(v["key"], v["text"])
    return arabic


def load_tafsir(slug):
    path = os.path.join(TAFSIR_DIR, slug + ".jsonl")
    if not os.path.exists(path):
        return {}
    return {o["verse_key"]: o["text"]
            for l in open(path, encoding="utf-8")
            for o in [json.loads(l)]
            if len(o.get("text", "")) >= MIN_LEN}


def clip(txt):
    txt = txt.strip()
    if len(txt) > MAX_TARGET:
        # coupe a la derniere phrase avant la limite
        cut = txt[:MAX_TARGET]
        last = max(cut.rfind("."), cut.rfind("۔"), cut.rfind("\n"))
        txt = cut[:last + 1] if last > MAX_TARGET // 2 else cut
    return txt.strip()


# ── Authenticite hadith ────────────────────────────────────────────────────────

def is_authentic(entry):
    """Bukhari/Muslim -> True. Sunan -> True si un grade Sahih/Hasan."""
    if entry["collection"] in SAHIH_BY_CONSENSUS:
        return True
    for g in entry.get("grades", []):
        grade = (g.get("grade") or "").lower()
        if "sahih" in grade or "hasan" in grade or "صحيح" in grade or "حسن" in grade:
            return True
    return False


def grade_label(entry):
    if entry["collection"] in SAHIH_BY_CONSENSUS:
        return "Sahih (authentique par consensus)"
    grades = entry.get("grades", [])
    for g in grades:
        gr = (g.get("grade") or "")
        if "sahih" in gr.lower() or "صحيح" in gr:
            return f"Sahih (selon {g.get('name','')})"
    for g in grades:
        gr = (g.get("grade") or "")
        if "hasan" in gr.lower() or "حسن" in gr:
            return f"Hasan (selon {g.get('name','')})"
    return grades[0]["grade"] if grades else "non grade"


# ── Generation des exemples ────────────────────────────────────────────────────

def build_tafsir_examples(arabic):
    tafsirs = {slug: load_tafsir(slug) for slug in TAFSIR_META}
    loaded = {s: len(d) for s, d in tafsirs.items() if d}
    print(f"  Tafsirs charges: {loaded}", flush=True)

    examples = []
    keys = sorted(arabic.keys(), key=lambda k: (int(k.split(":")[0]), int(k.split(":")[1])))
    for key in keys:
        ar = arabic.get(key, "")
        if not ar:
            continue
        # FR : traduction / explication
        for slug in ("fr-montada", "fr-rashid-maash", "fr-mokhtasar", "fr-hamidullah"):
            txt = tafsirs.get(slug, {}).get(key, "")
            if len(txt) >= MIN_LEN:
                name = TAFSIR_META[slug][0]
                examples.append({
                    "system": SYSTEM,
                    "user": f"Explique le sens du verset {key} du Coran :\n{ar}",
                    "target": f"{clip(txt)}\n\n(Source : {name})",
                })
                break  # une explication FR par verset suffit
        # AR : tafsir classique attribue (jusqu'a 2 par verset, varie)
        ar_slugs = [s for s in ("ar-ibn-kathir", "ar-saadi", "ar-tabari",
                                "ar-qurtubi", "ar-jalalayn", "ar-baghawi", "ar-muyassar",
                                "ar-kashshaf", "ar-ibn-ashur")
                    if tafsirs.get(s, {}).get(key)]
        random.shuffle(ar_slugs)
        for slug in ar_slugs[:2]:
            txt = tafsirs[slug][key]
            if len(txt) >= MIN_LEN:
                name = TAFSIR_META[slug][0]
                examples.append({
                    "system": SYSTEM,
                    "user": f"بحسب {name}، ما تفسير الآية {key} من القرآن الكريم؟\n{ar}",
                    "target": f"{clip(txt)}\n\n(المصدر: {name})",
                })
        # AR : analyse lexicale / mots rares (prompt dedie, distinct du tafsir general,
        # pour ne pas melanger "sens du verset" et "sens precis d'un mot")
        gharib_slugs = [s for s in ("ar-tahlil-kalimat", "ar-siraj-gharib", "ar-muyassar-gharib")
                        if tafsirs.get(s, {}).get(key)]
        if gharib_slugs:
            slug = random.choice(gharib_slugs)
            txt = tafsirs[slug][key]
            if len(txt) >= MIN_LEN:
                name = TAFSIR_META[slug][0]
                examples.append({
                    "system": SYSTEM,
                    "user": f"اشرح مفردات وغريب الآية {key} من القرآن الكريم؟\n{ar}",
                    "target": f"{clip(txt)}\n\n(المصدر: {name})",
                })
    return examples


# ── al-wujuh wal-naza'ir : mots aux sens multiples / nuances lexicales ─────────

def clean_word(h):
    h = (h or "").strip()
    h = TASHKEEL_RE.sub("", h)
    h = h.strip(" ()[]»«.:—-")
    return h.strip()


MAX_WORD_LEN = 40  # une vraie en-tete "mot"/"baab X" est courte ; au-dela, c'est
                    # du texte de paragraphe mal englobe dans la balise <title>
                    # par la source (defaut constate sur ~11% des entrees Ibn al-Jawzi :
                    # le titre capture aussi le premier paragraphe -> "mot" = une phrase
                    # entiere hors-sujet si on ne le detecte pas).


def repair_heading(raw_heading):
    """Renvoie (mot_propre_ou_None, texte_supplementaire_a_preferer_au_debut_du_corps).
    Si le titre brut contient un saut de ligne et commence par 'باب <mot court>',
    on isole le vrai mot et on recupere le reste comme debut du corps de CETTE
    entree (pas de la precedente). Sinon, si le titre est trop long pour etre un
    mot, on le traite comme invalide (fragment de continuation ou intercalaire
    d'edition type "(ابواب الثلاثة)")."""
    h = (raw_heading or "").strip()
    if "\n" in h:
        first, rest = h.split("\n", 1)
        first_clean = clean_word(first)
        if first_clean.startswith("باب"):
            word = re.sub(r"^\s*باب\s+", "", first_clean).strip()
            if 2 <= len(AR_LETTER_RE.findall(word)) and len(word) <= MAX_WORD_LEN:
                return word, rest
        return None, h
    word = clean_word(h)
    if 2 <= len(AR_LETTER_RE.findall(word)) and len(word) <= MAX_WORD_LEN:
        return word, ""
    return None, h


def load_entries_merged(path):
    """Charge un fichier d'entrees {heading,text,...} et recolle au precedent
    tout fragment dont l'en-tete n'est pas un vrai mot (titre tronque, intercalaire
    d'edition type '(ابواب الثلاثة)', ou paragraphe englobe par erreur dans la
    balise <title>) plutot que de le jeter : ca evite de perdre du contenu ET de
    fabriquer une fausse entree dont le "mot" serait en realite une phrase entiere."""
    with open(path, encoding="utf-8") as f:
        rows = [json.loads(l) for l in f]
    merged = []
    for r in rows:
        word, extra = repair_heading(r["heading"])
        text = (extra + "\n" + r["text"]) if extra else r["text"]
        if word and len(text) >= 30:
            merged.append({"word": word, "text": text})
        elif merged:
            merged[-1]["text"] += "\n" + text
    return merged


def build_mufradat_examples():
    if not os.path.exists(MUFRADAT_ENTRIES):
        return []
    examples = []
    for e in load_entries_merged(MUFRADAT_ENTRIES):
        txt = e["text"].strip()
        if len(txt) < MIN_LEN:
            continue
        examples.append({
            "system": SYSTEM,
            "user": f"ما معنى كلمة «{e['word']}» في القرآن الكريم؟ اذكر دقائق معناها وما يميزها عن الكلمات القريبة منها في المعنى.",
            "target": f"{clip(txt)}\n\n(المصدر: المفردات في غريب القرآن، الراغب الأصفهاني)",
        })
    return examples


def build_nuzhat_examples():
    if not os.path.exists(NUZHAT_ENTRIES):
        return []
    examples = []
    for e in load_entries_merged(NUZHAT_ENTRIES):
        word = re.sub(r"^\s*باب\s+", "", e["word"]).strip()
        txt = e["text"].strip()
        if len(txt) < MIN_LEN or not word:
            continue
        examples.append({
            "system": SYSTEM,
            "user": f"اذكر الوجوه والمعاني المختلفة لكلمة «{word}» كما وردت في القرآن الكريم (علم الوجوه والنظائر).",
            "target": f"{clip(txt)}\n\n(المصدر: نزهة الأعين النواظر في علم الوجوه والنظائر، ابن الجوزي)",
        })
    return examples


def build_ulum_chapter_examples():
    examples = []
    for slug, meta in WUJUH_CHAPTERS.items():
        path = os.path.join(SCIENCES_DIR, slug + ".jsonl")
        if not os.path.exists(path):
            continue
        lo, hi = meta["range"]
        pages = []
        for l in open(path, encoding="utf-8"):
            o = json.loads(l)
            if lo <= o["page_id"] <= hi:
                pages.append(o["text"])
        full = "\n".join(pages)
        citation = f"{meta['name']}, {meta['author']} (فصل الوجوه والنظائر)"
        chunks = []
        while full:
            if len(full) <= 1800:
                chunks.append(full)
                break
            cut = full.rfind(".", 0, 1800)
            if cut < 900:
                cut = 1800
            chunks.append(full[:cut + 1])
            full = full[cut + 1:]
        for i, chunk in enumerate(chunks):
            chunk = chunk.strip()
            if len(chunk) < 100:
                continue
            q = ("ما هو علم الوجوه والنظائر في القرآن الكريم؟"
                 if i == 0 else f"تابع الشرح عن علم الوجوه والنظائر في القرآن (الجزء {i + 1}).")
            examples.append({
                "system": SYSTEM,
                "user": q,
                "target": f"{clip(chunk)}\n\n(المصدر: {citation})",
            })
    return examples


def build_hadith_examples():
    examples = []
    stats = {}
    for path in glob.glob(os.path.join(HADITH_DIR, "*.jsonl")):
        coll = os.path.splitext(os.path.basename(path))[0]
        display = HADITH_DISPLAY.get(coll, coll)
        kept = 0
        for l in open(path, encoding="utf-8"):
            e = json.loads(l)
            if not is_authentic(e):
                continue
            ar = e.get("ar", "").strip()
            fr = e.get("fr", "").strip()
            if len(ar) < MIN_LEN:
                continue
            src   = e["source"]
            grade = grade_label(e)

            # 1) Demander le texte + traduction d'un hadith reference
            if fr:
                examples.append({
                    "system": SYSTEM,
                    "user": f"Rapporte et traduis le hadith {src}.",
                    "target": f"Texte arabe :\n{ar}\n\nTraduction :\n{fr}\n\n"
                              f"(Source : {display}, n°{e['number']} — {grade})",
                })
            # 2) Traduire/expliquer un hadith donne en arabe
            if fr:
                examples.append({
                    "system": SYSTEM,
                    "user": f"Traduis ce hadith en francais :\n{ar}",
                    "target": f"{fr}\n\n(Source : {display}, n°{e['number']} — {grade})",
                })
            kept += 1
        stats[coll] = kept
    print(f"  Hadiths authentiques retenus: {stats}", flush=True)
    return examples


def main():
    print("Chargement versets...", flush=True)
    arabic = load_verses()
    print(f"  {len(arabic)} versets", flush=True)

    print("Construction exemples tafsir...", flush=True)
    tafsir_ex = build_tafsir_examples(arabic)
    print(f"  {len(tafsir_ex)} exemples tafsir", flush=True)

    print("Construction exemples hadith...", flush=True)
    hadith_ex = build_hadith_examples()
    print(f"  {len(hadith_ex)} exemples hadith", flush=True)

    print("Construction exemples wujuh wal-naza'ir / mufradat...", flush=True)
    mufradat_ex = build_mufradat_examples()
    nuzhat_ex = build_nuzhat_examples()
    ulum_ex = build_ulum_chapter_examples()
    print(f"  {len(mufradat_ex)} mufradat, {len(nuzhat_ex)} nuzhat al-ayun, {len(ulum_ex)} chapitres ulum", flush=True)

    examples = tafsir_ex + hadith_ex + mufradat_ex + nuzhat_ex + ulum_ex
    random.shuffle(examples)

    with open(OUT, "w", encoding="utf-8") as f:
        for ex in examples:
            f.write(json.dumps(ex, ensure_ascii=False) + "\n")

    print(f"\nTOTAL: {len(examples)} exemples -> {OUT}", flush=True)
    print(f"  tafsir: {len(tafsir_ex)}  hadith: {len(hadith_ex)}  "
          f"mufradat: {len(mufradat_ex)}  nuzhat: {len(nuzhat_ex)}  ulum: {len(ulum_ex)}", flush=True)
    print("ISLAMIC SFT DONE", flush=True)


if __name__ == "__main__":
    main()
