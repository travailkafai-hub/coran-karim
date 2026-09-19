"""Rapatrie, dechiffre et ouvre les envois de collecte (cf. COLLECTE_RECITATIONS.md).

    python benchmark/collecte_rapatrier.py --sortie <dossier>

Chaque envoi devient un dossier contenant `session.json`, le ou les WAV et le
journal. Un envoi deja rapatrie n'est pas retelecharge.

── CE QU'IL FAUT AVOIR SOUS LA MAIN ───────────────────────────────────────

    benchmark/cles_collecte/collecte_privee.bin   la cle privee
    benchmark/cles_collecte/inventaire.txt        le secret de l'inventaire

Ce dossier est ignore par git (cf. .gitignore) : ces deux fichiers ne doivent
JAMAIS entrer dans le depot. La cle privee ouvre tout le corpus ; le secret
d'inventaire permet de le lister et de le telecharger.

── POURQUOI PASSER PAR LE WORKER PLUTOT QUE PAR `wrangler` ────────────────

`wrangler` ne sait pas LISTER un bucket -- il faudrait des cles d'acces S3,
c'est-a-dire reintroduire le secret que le binding R2 permet d'eviter. Et son
`r2 object get` interroge par defaut un stockage LOCAL simule : il repond
« The specified key does not exist » sur un objet pourtant bien present, ce qui
a coute une fausse piste le 2026-09-19. Le Worker, lui, ne peut se tromper de
depot.

⚠️ CE SCRIPT NE SUPPRIME RIEN cote R2. Effacer est un geste separe, volontaire,
et qui doit suivre une regle de conservation (12 mois annonces dans l'ecran de
consentement) ou une demande de suppression. Un rapatriement qui effacerait au
passage rendrait toute erreur de manipulation definitive.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
import zipfile
from io import BytesIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from collecte_cles import dechiffrer  # noqa: E402

RACINE = Path(__file__).resolve().parent.parent
CLES = RACINE / "benchmark" / "cles_collecte"
BASE = "https://coran-karim-collecte.travail-kafai.workers.dev"


def _appel(chemin: str, secret: str) -> bytes:
    req = urllib.request.Request(
        BASE + chemin,
        headers={"x-cle": secret, "User-Agent": "coran-karim-rapatriement/1.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def inventaire(secret: str) -> list[dict]:
    """Toutes les entrees, en suivant les curseurs.

    Sans la reprise par curseur, un rapatriement s'arreterait au milleme objet
    SANS RIEN DIRE -- on croirait avoir tout recupere."""
    objets, curseur = [], None
    while True:
        chemin = "/inventaire?limite=1000" + (f"&curseur={curseur}" if curseur else "")
        rep = json.loads(_appel(chemin, secret))
        objets.extend(rep["objets"])
        curseur = rep.get("suite")
        if not curseur:
            return objets


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--sortie", type=Path, required=True)
    p.add_argument("--limite", type=int, default=0,
                   help="s'arreter apres N envois (0 = tous)")
    args = p.parse_args()

    fpriv, fsecret = CLES / "collecte_privee.bin", CLES / "inventaire.txt"
    for f in (fpriv, fsecret):
        if not f.is_file():
            return _absent(f)
    priv = fpriv.read_bytes()
    secret = fsecret.read_text(encoding="utf-8").strip()

    args.sortie.mkdir(parents=True, exist_ok=True)
    try:
        objets = inventaire(secret)
    except urllib.error.HTTPError as e:
        print(f"inventaire refuse : HTTP {e.code}. Le secret est-il celui pose "
              "par `wrangler secret put CLE_INVENTAIRE` ?")
        return 1

    print(f"{len(objets)} envoi(s) dans le depot")
    faits = illisibles = deja = 0
    for objet in objets:
        cle = objet["cle"]
        # L'arborescence reprend celle du depot : <appareil>/<instant>. C'est ce
        # qui permet, plus tard, de retrouver TOUT ce qu'un appareil a envoye si
        # quelqu'un demande la suppression de ses donnees.
        dest = args.sortie / cle.replace(".bin", "")
        if dest.is_dir():
            deja += 1
            continue
        try:
            ouvert = dechiffrer(_appel("/objet/" + cle, secret), priv)
        except Exception as e:  # noqa: BLE001
            # Un envoi illisible n'arrete pas le rapatriement, mais il est
            # COMPTE et nomme : c'est le signal d'une divergence de format ou
            # d'une cle qui n'est pas la bonne.
            print(f"  ILLISIBLE {cle} -> {type(e).__name__}: {e}")
            illisibles += 1
            continue
        dest.mkdir(parents=True, exist_ok=True)
        try:
            with zipfile.ZipFile(BytesIO(ouvert)) as z:
                z.extractall(dest)
        except zipfile.BadZipFile:
            # Dechiffre mais pas une archive : on garde le contenu brut plutot
            # que de le perdre, et on le dit.
            (dest / "contenu.bin").write_bytes(ouvert)
            print(f"  {cle} dechiffre mais n'est pas une archive")
        faits += 1
        if args.limite and faits >= args.limite:
            break

    print(f"\n{faits} rapatrie(s), {deja} deja present(s), "
          f"{illisibles} illisible(s) -> {args.sortie}")
    return 1 if illisibles else 0


def _absent(f: Path) -> int:
    print(f"ABSENT : {f}")
    print()
    print("La cle privee se genere avec :")
    print("    python benchmark/collecte_cles.py generer --dossier benchmark/cles_collecte")
    print("Le secret d'inventaire est celui pose sur le Worker :")
    print("    cd collecte_worker && npx wrangler secret put CLE_INVENTAIRE")
    print("et il se recopie dans benchmark/cles_collecte/inventaire.txt")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
