"""Recupere les slugs exacts (book name) par langue pour les 6 livres canoniques."""
import truststore; truststore.inject_into_ssl()
import json, urllib.request

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")

hed = json.loads(fetch("https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions.json"))
CANON = ["bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah"]
for c in CANON:
    print(f"\n{c}:")
    for book in hed[c]["collection"]:
        print(f'  lang={book.get("language"):12s} name={book.get("name")}  hasgrades?')
print("\nDONE")
