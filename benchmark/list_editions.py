"""Liste les editions tafsir (AR/FR) et hadith (toutes langues) disponibles."""
import truststore; truststore.inject_into_ssl()
import json, urllib.request

def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")

print("########## TAFSIR editions (arabic + french) ##########")
eds = json.loads(fetch("https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/editions.json"))
for e in eds:
    if e["language_name"] in ("arabic", "french"):
        print(f'  [{e["language_name"][:2]}] {e["slug"]:45s} | {e["name"]} — {e["author_name"]}')

print("\n########## HADITH editions ##########")
hed = json.loads(fetch("https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions.json"))
for coll_key, coll in hed.items():
    langs = []
    for book in coll.get("collection", []):
        langs.append(book.get("language", "?"))
    print(f'  {coll_key:20s} | {coll.get("name","")} | langues: {langs}')

print("\nDONE")
