"""
Construit la base de connaissance RAG (anti-hallucination) — CPU uniquement.

Decoupe en passages recuperables, avec metadonnees completes pour citation :
  - TAFSIR  : 1 passage par (verset x tafsir)   -> source, verset, langue
  - HADITH  : 1 passage par hadith authentique  -> recueil, numero, grade

Sortie : data/rag_corpus/passages.jsonl
  { "id", "type", "source", "ref", "lang", "text", "meta": {...} }

Cette base servira a 2 choses :
  1. Recherche RAG on-device (le modele lit le passage reel + cite la source)
  2. Verification factuelle (jamais de hadith/tafsir invente)
"""
import json, os, glob, re

ROOT       = os.path.dirname(os.path.abspath(__file__))
TAFSIR_DIR = os.path.join(ROOT, "data", "tafsir")
HADITH_DIR = os.path.join(ROOT, "data", "islamic_corpus", "hadith")
OUT_DIR    = os.path.join(ROOT, "data", "rag_corpus")
os.makedirs(OUT_DIR, exist_ok=True)
OUT        = os.path.join(OUT_DIR, "passages.jsonl")

MIN_LEN    = 30
MAX_CHARS  = 1500   # passages pas trop longs pour le retrieval

TAFSIR_META = {
    "ar-ibn-kathir": ("Tafsir Ibn Kathir", "ar"),
    "ar-tabari": ("Tafsir at-Tabari", "ar"),
    "ar-qurtubi": ("Tafsir al-Qurtubi", "ar"),
    "ar-jalalayn": ("Tafsir al-Jalalayn", "ar"),
    "ar-baghawi": ("Tafsir al-Baghawi", "ar"),
    "ar-saadi": ("Tafsir as-Saadi", "ar"),
    "ar-muyassar": ("Tafsir al-Muyassar", "ar"),
    "en-ibn-kathir": ("Tafsir Ibn Kathir (EN)", "en"),
    "en-maarif": ("Maarif-ul-Quran (EN)", "en"),
    "fr-hamidullah": ("Traduction Hamidullah", "fr"),
    "fr-montada": ("Tafsir Al-Montada (FR)", "fr"),
    "fr-rashid-maash": ("Traduction Rashid Maash", "fr"),
    "fr-mokhtasar": ("Tafsir Al-Mukhtasar (FR)", "fr"),
}
HADITH_DISPLAY = {
    "bukhari": "Sahih al-Bukhari", "muslim": "Sahih Muslim",
    "abudawud": "Sunan Abu Dawud", "tirmidhi": "Jami at-Tirmidhi",
    "nasai": "Sunan an-Nasa'i", "ibnmajah": "Sunan Ibn Majah",
}
SAHIH_CONSENSUS = {"bukhari", "muslim"}


def chunk(text):
    text = text.strip()
    if len(text) <= MAX_CHARS:
        return [text]
    # decoupe sur les fins de phrase
    parts, cur = [], ""
    for sent in re.split(r'(?<=[.۔\n])\s+', text):
        if len(cur) + len(sent) > MAX_CHARS and cur:
            parts.append(cur.strip()); cur = sent
        else:
            cur += " " + sent
    if cur.strip():
        parts.append(cur.strip())
    return parts


def is_authentic(e):
    if e["collection"] in SAHIH_CONSENSUS:
        return True
    for g in e.get("grades", []):
        gr = (g.get("grade") or "").lower()
        if "sahih" in gr or "hasan" in gr or "صحيح" in gr or "حسن" in gr:
            return True
    return False


def grade_label(e):
    if e["collection"] in SAHIH_CONSENSUS:
        return "Sahih (consensus)"
    for g in e.get("grades", []):
        gr = g.get("grade") or ""
        if "sahih" in gr.lower() or "صحيح" in gr:
            return f"Sahih ({g.get('name','')})"
    for g in e.get("grades", []):
        gr = g.get("grade") or ""
        if "hasan" in gr.lower() or "حسن" in gr:
            return f"Hasan ({g.get('name','')})"
    return "n/a"


def main():
    n_taf = n_had = 0
    with open(OUT, "w", encoding="utf-8") as out:
        # ── Tafsir ──
        for slug, (name, lang) in TAFSIR_META.items():
            path = os.path.join(TAFSIR_DIR, slug + ".jsonl")
            if not os.path.exists(path):
                continue
            for l in open(path, encoding="utf-8"):
                o = json.loads(l)
                txt = o.get("text", "")
                if len(txt) < MIN_LEN:
                    continue
                vk = o["verse_key"]
                for j, c in enumerate(chunk(txt)):
                    out.write(json.dumps({
                        "id": f"taf:{slug}:{vk}:{j}",
                        "type": "tafsir",
                        "source": name,
                        "ref": f"Verset {vk}",
                        "lang": lang,
                        "text": c,
                        "meta": {"slug": slug, "verse_key": vk},
                    }, ensure_ascii=False) + "\n")
                    n_taf += 1
        # ── Hadith ──
        for path in glob.glob(os.path.join(HADITH_DIR, "*.jsonl")):
            coll = os.path.splitext(os.path.basename(path))[0]
            display = HADITH_DISPLAY.get(coll, coll)
            for l in open(path, encoding="utf-8"):
                e = json.loads(l)
                if not is_authentic(e):
                    continue
                ar = e.get("ar", "").strip()
                fr = e.get("fr", "").strip()
                if len(ar) < MIN_LEN:
                    continue
                grade = grade_label(e)
                body = ar + (("\n\n" + fr) if fr else "")
                out.write(json.dumps({
                    "id": f"had:{coll}:{e['number']}",
                    "type": "hadith",
                    "source": display,
                    "ref": f"{display} n°{e['number']}",
                    "lang": "ar+fr" if fr else "ar",
                    "text": body[:MAX_CHARS],
                    "meta": {"collection": coll, "number": e["number"],
                             "grade": grade},
                }, ensure_ascii=False) + "\n")
                n_had += 1

    print(f"Passages tafsir: {n_taf:,}", flush=True)
    print(f"Passages hadith: {n_had:,}", flush=True)
    print(f"TOTAL: {n_taf + n_had:,} passages -> {OUT}", flush=True)
    print("RAG CORPUS DONE", flush=True)


if __name__ == "__main__":
    main()
