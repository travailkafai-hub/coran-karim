"""Le Python rouvre-t-il ce que le Dart a scelle ?

Se lance APRES `flutter test test/collecte_chiffrement_test.dart`, qui depose
`app/build/collecte_interop/paquet_dart.bin` et le clair attendu a cote.

── POURQUOI CE SCRIPT EXISTE ──────────────────────────────────────────────

Deux implementations d'un meme format peuvent etre parfaitement coherentes
CHACUNE AVEC ELLE-MEME et incompatibles entre elles : un ordre d'octets dans
`info`, un `aad` oublie, un nonce de 16 octets d'un cote et 12 de l'autre.
Rien ne le signale -- l'application chiffre sans erreur, l'envoi part, et le
defaut se decouvre le jour ou l'on veut entrainer, sur un corpus devenu
illisible que personne ne peut plus recuperer.

C'est le seul test qui protege de cela, et il doit tourner AVANT le premier
envoi reel.

Les cles utilisees ici sont celles du DEPOT, sans valeur : elles ne servent
qu'a ce controle. La cle de production se genere avec `collecte_cles.py
generer` et sa partie privee ne figure evidemment nulle part dans le depot.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from collecte_cles import dechiffrer  # noqa: E402

RACINE = Path(__file__).resolve().parent.parent
INTEROP = RACINE / "app" / "build" / "collecte_interop"
CLES = RACINE / "benchmark" / "cles_test_collecte"


def main() -> int:
    paquet_f = INTEROP / "paquet_dart.bin"
    clair_f = INTEROP / "clair_attendu.bin"
    priv_f = CLES / "collecte_privee.bin"

    manquants = [f for f in (paquet_f, clair_f, priv_f) if not f.is_file()]
    if manquants:
        for f in manquants:
            print(f"ABSENT : {f}")
        print()
        print("Lancer d'abord, depuis app/ :")
        print("    flutter test test/collecte_chiffrement_test.dart")
        return 2

    paquet = paquet_f.read_bytes()
    attendu = clair_f.read_bytes()

    if paquet[:4] != b"CKR1":
        print(f"ECHEC : magique {paquet[:4]!r}, attendu b'CKR1'")
        return 1
    if len(paquet) != len(attendu) + 64:
        print(f"ECHEC : {len(paquet)} octets pour {len(attendu)} de clair, "
              f"attendu {len(attendu) + 64} (4 magique + 32 ephemere + "
              "12 nonce + 16 tag)")
        return 1

    try:
        ouvert = dechiffrer(paquet, priv_f.read_bytes())
    except Exception as e:  # noqa: BLE001 -- on veut TOUTE erreur, nommee
        print(f"ECHEC : le Python ne peut pas ouvrir le paquet Dart -> "
              f"{type(e).__name__}: {e}")
        print()
        print("Les deux cotes ont diverge. Verifier, dans cet ordre :")
        print("  - `info` de HKDF : contexte || cle ephemere || cle destinataire")
        print("  - l'AAD : le magique, et lui seul")
        print("  - la longueur du nonce : 12 octets")
        return 1

    if ouvert != attendu:
        print(f"ECHEC : dechiffre {len(ouvert)} octets, attendu {len(attendu)} "
              "-- le format s'ouvre mais ne rend pas le meme contenu")
        return 1

    print(f"OK  le Python rouvre le paquet Dart ({len(attendu)} octets de "
          f"clair, {len(paquet)} scelles)")
    print("    magique, longueurs, et contenu identiques des deux cotes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
