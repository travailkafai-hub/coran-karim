"""Cles et dechiffrement de la collecte de recitations (cf. COLLECTE_RECITATIONS.md).

Cote PC A. L'application ne porte QUE la cle publique ; la privee ne quitte
jamais cette machine.

    python benchmark/collecte_cles.py generer   --dossier <dir>
    python benchmark/collecte_cles.py dechiffrer --cle <priv.bin> --entree <f.bin> --sortie <f.zip>
    python benchmark/collecte_cles.py autotest  --dossier <dir>

── POURQUOI CE FORMAT, ET PAS UNE « SEALED BOX » ──────────────────────────

L'idee de depart etait la sealed box de libsodium. Elle est excellente, mais
elle n'existe pas telle quelle du cote Dart : il aurait fallu reimplementer son
nonce (`blake2b(eph_pk || dest_pk)`) a la main dans l'application. C'est
precisement le genre de detail ou une erreur silencieuse produit des fichiers
que PLUS PERSONNE ne peut dechiffrer -- et on ne s'en apercoit qu'apres avoir
collecte des milliers de sessions.

On prend donc des primitives que les DEUX cotes fournissent en standard, sans
rien reimplementer :

    X25519            accord de cle avec une paire ephemere par envoi
    HKDF-SHA256       derivation de la cle de session
    AES-256-GCM       chiffrement authentifie

Chaque envoi tire une paire ephemere : deux sessions du meme appareil n'ont
aucune cle en commun, et la compromission d'un envoi n'ouvre pas les autres.

── LE PAQUET ──────────────────────────────────────────────────────────────

    0..3     "CKR1"            magique + version de format
    4..35    cle publique ephemere X25519 (32 octets)
    36..47   nonce AES-GCM (12 octets, aleatoire)
    48..     chiffre + tag GCM (16 octets)

`info` de HKDF contient les DEUX cles publiques : sans cela, un envoi chiffre
pour un destinataire pourrait etre rejoue vers un autre. Le magique est
authentifie comme donnee additionnelle (AAD) : un octet modifie dans l'en-tete
fait echouer le dechiffrement au lieu de rendre des octets faux.

⚠️ LA CLE PRIVEE EST LE CORPUS. Perdue, tout ce qui a ete collecte est
definitivement illisible -- il n'existe aucune recuperation. La sauvegarder
HORS de cette machine avant le premier envoi.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey, X25519PublicKey)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import (
    Encoding, NoEncryption, PrivateFormat, PublicFormat)

MAGIQUE = b"CKR1"
INFO = b"coran-karim-collecte-v1"


def _cle_de_session(partage: bytes, eph_pub: bytes, dest_pub: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=None,
                info=INFO + eph_pub + dest_pub).derive(partage)


def chiffrer(clair: bytes, dest_pub_brut: bytes) -> bytes:
    """Chiffre pour le porteur de la cle privee. Sert a l'autotest ; en
    production c'est l'application qui fait ceci, en Dart."""
    dest = X25519PublicKey.from_public_bytes(dest_pub_brut)
    eph = X25519PrivateKey.generate()
    eph_pub = eph.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    cle = _cle_de_session(eph.exchange(dest), eph_pub, dest_pub_brut)
    nonce = os.urandom(12)
    chiffre = AESGCM(cle).encrypt(nonce, clair, MAGIQUE)
    return MAGIQUE + eph_pub + nonce + chiffre


def dechiffrer(paquet: bytes, priv_brut: bytes) -> bytes:
    if len(paquet) < 48 or paquet[:4] != MAGIQUE:
        raise ValueError(
            f"ce n'est pas un paquet de collecte (en-tete {paquet[:4]!r})")
    eph_pub, nonce, chiffre = paquet[4:36], paquet[36:48], paquet[48:]
    priv = X25519PrivateKey.from_private_bytes(priv_brut)
    dest_pub = priv.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    cle = _cle_de_session(priv.exchange(X25519PublicKey.from_public_bytes(eph_pub)),
                          eph_pub, dest_pub)
    return AESGCM(cle).decrypt(nonce, chiffre, MAGIQUE)


def generer(dossier: Path) -> None:
    dossier.mkdir(parents=True, exist_ok=True)
    fpriv, fpub = dossier / "collecte_privee.bin", dossier / "collecte_publique.bin"
    if fpriv.exists():
        sys.exit(f"REFUS : {fpriv} existe deja. Ecraser une cle privee rend "
                 "illisible tout ce qui a ete collecte avec. La deplacer "
                 "d'abord, en connaissance de cause.")
    priv = X25519PrivateKey.generate()
    brut_priv = priv.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
    brut_pub = priv.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    fpriv.write_bytes(brut_priv)
    fpub.write_bytes(brut_pub)
    try:
        os.chmod(fpriv, 0o600)
    except OSError:
        pass  # NTFS : pas de permissions POSIX, cf. CLAUDE.md
    print(f"cle privee  : {fpriv}   ⚠️  A SAUVEGARDER HORS DE CETTE MACHINE")
    print(f"cle publique: {fpub}")
    print()
    print("A copier dans l'application (constante `kCollecteClePublique`) :")
    print("  " + brut_pub.hex())


def autotest(dossier: Path) -> None:
    """Verifie l'aller-retour ET les refus attendus.

    Un chiffrement qui « marche » n'est pas une preuve : il faut aussi qu'un
    paquet abime soit REFUSE, sinon on croirait avoir de l'authentification
    alors qu'on n'en a pas."""
    pub = (dossier / "collecte_publique.bin").read_bytes()
    priv = (dossier / "collecte_privee.bin").read_bytes()
    clair = b"session de test " + os.urandom(4096)

    paquet = chiffrer(clair, pub)
    assert dechiffrer(paquet, priv) == clair, "aller-retour casse"
    print(f"OK  aller-retour           ({len(clair)} -> {len(paquet)} octets, "
          f"+{len(paquet) - len(clair)} d'en-tete et de tag)")

    # Deux paquets du meme message ne doivent jamais se ressembler : sinon la
    # paire ephemere ne serait pas retiree a chaque envoi.
    assert chiffrer(clair, pub) != paquet, "paire ephemere non renouvelee"
    print("OK  paire ephemere par envoi")

    for nom, abime in (
        ("octet du chiffre modifie", paquet[:60] + bytes([paquet[60] ^ 1]) + paquet[61:]),
        ("nonce modifie", paquet[:40] + bytes([paquet[40] ^ 1]) + paquet[41:]),
        ("magique modifie", b"CKR2" + paquet[4:]),
    ):
        try:
            dechiffrer(abime, priv)
        except Exception:
            print(f"OK  refuse : {nom}")
        else:
            sys.exit(f"ECHEC : un paquet avec {nom} a ete accepte")

    autre = X25519PrivateKey.generate().private_bytes(
        Encoding.Raw, PrivateFormat.Raw, NoEncryption())
    try:
        dechiffrer(paquet, autre)
    except Exception:
        print("OK  refuse : une autre cle privee")
    else:
        sys.exit("ECHEC : une autre cle privee a dechiffre le paquet")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sous = p.add_subparsers(dest="action", required=True)
    g = sous.add_parser("generer"); g.add_argument("--dossier", type=Path, required=True)
    a = sous.add_parser("autotest"); a.add_argument("--dossier", type=Path, required=True)
    d = sous.add_parser("dechiffrer")
    d.add_argument("--cle", type=Path, required=True)
    d.add_argument("--entree", type=Path, required=True)
    d.add_argument("--sortie", type=Path, required=True)
    args = p.parse_args()

    if args.action == "generer":
        generer(args.dossier)
    elif args.action == "autotest":
        autotest(args.dossier)
    else:
        args.sortie.write_bytes(dechiffrer(args.entree.read_bytes(),
                                           args.cle.read_bytes()))
        print(f"{args.entree} -> {args.sortie} ({args.sortie.stat().st_size} octets)")


if __name__ == "__main__":
    main()
