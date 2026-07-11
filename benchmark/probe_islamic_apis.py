"""Probe des APIs islamiques (tafsir + hadith) : reachabilite + structure.
Teste a travers le proxy Norton via truststore."""
import truststore; truststore.inject_into_ssl()
import json, urllib.request

def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8")

def probe(label, url, show=600):
    print(f"\n{'='*60}\n{label}\n{url}")
    try:
        data = fetch(url)
        print(f"  OK ({len(data)} bytes)")
        print(f"  {data[:show]}")
        return data
    except Exception as e:
        print(f"  ECHEC: {e}")
        return None

# ── TAFSIR : spa5k/tafsir_api ──────────────────────────────────────────
print("########## TAFSIR API (spa5k) ##########")
ed = probe("Editions tafsir", "https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/editions.json", 1500)
# Test un ayah (Ibn Kathir AR) - tester 2 patterns d'URL
probe("Tafsir ayah pattern A (1/1.json)",
      "https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/ar-tafsir-ibn-kathir/1/1.json", 400)

# ── HADITH : fawazahmed0/hadith-api ────────────────────────────────────
print("\n\n########## HADITH API (fawazahmed0) ##########")
probe("Editions hadith", "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions.json", 2000)
# Test une section de Bukhari AR
probe("Bukhari AR section 1",
      "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions/ara-bukhari/sections/1.json", 600)
# Test 1 hadith specifique
probe("Bukhari AR hadith 1",
      "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions/ara-bukhari/1.json", 800)

print("\n\nPROBE DONE")
