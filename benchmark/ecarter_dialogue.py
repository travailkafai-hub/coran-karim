#!/usr/bin/env python3
"""Écarte le dialogue système « Compatibilité des applis Android ».

POURQUOI CE SCRIPT EXISTE. Android affiche cet avertissement à chaque
installation d'un APK **débogable** (« application débogable actuellement
testée », plus la vérification d'alignement ELF 16 ko). Il se pose par-dessus
l'app et attend un tap.

Pourquoi ne pas simplement passer en release, ce qui le supprimerait à la
source : `run-as` — donc la récupération des WAV de session — ne fonctionne QUE
sur une app débogable. Vérifié le 2026-07-28 :

    run-as: package not debuggable: com.corankarim.coran_karim

Or l'analyse audio est le seul moyen de distinguer une faute de récitation d'un
défaut d'architecture. On garde donc le debug, et on écarte le dialogue.

Pourquoi pas des coordonnées en dur : elles changent avec la taille d'écran, la
densité et la langue. On lit l'arbre d'accessibilité et on vise le bouton par
son TEXTE — « Ne plus afficher » de préférence à « OK », pour ne pas avoir à
recommencer au lancement suivant.
"""
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

# Par ordre de préférence : le premier bouton trouvé est cliqué.
LIBELLES = ("ne plus afficher", "don't show again", "dont show again", "ok")


def sh(serial: str, cmd: str) -> str:
    r = subprocess.run(["adb", "-s", serial, "shell", cmd],
                       capture_output=True, text=True, timeout=60)
    return r.stdout


def centre(bounds: str):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds or "")
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def ecarter(serial: str) -> bool:
    sh(serial, "uiautomator dump /sdcard/ui_dlg.xml")
    xml = sh(serial, "cat /sdcard/ui_dlg.xml")
    if "<" not in xml:
        return False
    try:
        racine = ET.fromstring(xml[xml.index("<?xml"):] if "<?xml" in xml else xml)
    except ET.ParseError:
        return False
    trouves = {}
    for n in racine.iter("node"):
        t = (n.get("text") or "").strip().lower()
        if t in LIBELLES:
            trouves.setdefault(t, n.get("bounds"))
    for lib in LIBELLES:
        if lib in trouves:
            c = centre(trouves[lib])
            if c:
                sh(serial, f"input tap {c[0]} {c[1]}")
                print(f"{serial} : dialogue ecarte via « {lib} »")
                return True
    return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: ecarter_dialogue.py <serial> [<serial>...]")
    for s in sys.argv[1:]:
        if not ecarter(s):
            print(f"{s} : aucun dialogue a ecarter")
