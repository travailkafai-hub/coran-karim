#!/usr/bin/env python3
"""Rend le skill `superviseur-recette` OBLIGATOIRE, pas facultatif.

POURQUOI CE HOOK EXISTE (2026-07-30). Consigne utilisateur : « il doit se
declencher absolument a chaque modification de code sur le chemin de cette
fonctionnalite ». Une consigne dans CLAUDE.md depend de la bonne volonte de
l'agent -- or c'est precisement l'agent qui corrige « les yeux fermes » qu'il
faut contraindre. Un agent qui casse ne se voit pas casser.

DEUX MODES, branches dans .claude/settings.json :

  edit    PostToolUse sur Edit|Write|MultiEdit
          -> si le fichier touche est sur le chemin de la RECITATION, pose un
             marqueur et rappelle le superviseur.

  garde   PreToolUse sur Bash
          -> BLOQUE `git commit` tant que le superviseur n'a pas tourne depuis
             la derniere modification. C'est ce qui rend l'obligation reelle :
             on ne peut plus figer un correctif non supervise.

COMMENT LE MARQUEUR SE LEVE. Pas par declaration de l'agent (il se croirait
quitte) mais par une PREUVE : une session de recette datant d'APRES la derniere
modification du chemin. Concretement, un dossier sous benchmark/recettes/ plus
recent que le marqueur. Pas de mesure, pas de commit.
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

RACINE = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")).resolve()
MARQUEUR = RACINE / ".claude" / ".superviseur-requis"
RECETTES = RACINE / "benchmark" / "recettes"

# Le CHEMIN de la fonctionnalite : capture -> segmentation -> ASR -> alignement
# -> jugement -> affichage. Une modification de l'un de ces fichiers peut
# fissurer le socle « le reciteur recite, l'app controle en streaming, dit vrai ».
CHEMIN = (
    # segmentation / buffer / secours
    "fastconformer/BufferedTranscriber.kt",
    "fastconformer/RescueBuffer.kt",
    # alignement force et scores
    "fastconformer/ForcedAligner.kt",
    "fastconformer/CausalAlignmentSession.kt",
    # moteur ASR et son entree
    "fastconformer/FastConformerCtc.kt",
    "fastconformer/FastConformerCtcPlugin.kt",
    "fastconformer/MelSpectrogram.kt",
    "fastconformer/CtcTokenizer.kt",
    # jugement et etat cote Dart
    "providers/recitation_provider.dart",
    "providers/judgement_provider.dart",
    "providers/gop_baseline_provider.dart",
    # contrats partages (decoupage des mots, verificateur)
    "services/recitation_verifier.dart",
    "services/fastconformer_verifier.dart",
    # ecran qui consomme la chaine
    "screens/karaoke_recitation_screen.dart",
)


def sur_le_chemin(p: str) -> bool:
    p = p.replace("\\", "/")
    return any(c in p for c in CHEMIN)


def mesure_posterieure_au_marqueur() -> bool:
    """Une recette a-t-elle tourne APRES la derniere modification ?"""
    if not MARQUEUR.exists():
        return True
    t = MARQUEUR.stat().st_mtime
    if not RECETTES.is_dir():
        return False
    for d in RECETTES.iterdir():
        if d.is_dir() and d.stat().st_mtime > t:
            return True
    return False


def mode_edit(data) -> int:
    chemin = (data.get("tool_input") or {}).get("file_path", "")
    if not chemin or not sur_le_chemin(chemin):
        return 0
    MARQUEUR.parent.mkdir(parents=True, exist_ok=True)
    MARQUEUR.write_text(f"{time.time()}\n{chemin}\n", encoding="utf-8")
    print(
        "🔎 CHEMIN DE LA RÉCITATION MODIFIÉ — le superviseur est OBLIGATOIRE\n"
        f"   {Path(chemin).name}\n\n"
        "Avant tout build et tout commit, invoque le skill `superviseur-recette`\n"
        "et passe ses contrôles. Rappel de sa hiérarchie — les trois premiers\n"
        "sont bloquants, le taux ne compte qu'après :\n"
        "   1. DIRE VRAI     aucun verdict sans preuve acoustique\n"
        "   2. SUIVRE        ancre jusqu'au bout, aucun bloc > 5 mots sans jugement\n"
        "   3. STREAMING     retard borné, pas de cascade de gels\n"
        "   4. le taux       seulement si 1-2-3 tiennent\n\n"
        "Un gain de taux obtenu en dégradant 1-2-3 est un faux gain, à rejeter.\n"
        "`git commit` restera BLOQUÉ jusqu'à ce qu'une recette ait tourné.",
        file=sys.stderr,
    )
    return 0  # informatif : on n'empeche pas d'editer


def mode_garde(data) -> int:
    cmd = (data.get("tool_input") or {}).get("command", "")
    if "git commit" not in cmd:
        return 0
    if not MARQUEUR.exists():
        return 0
    # Le chemin a-t-il vraiment quelque chose d'indexe ? Sinon le marqueur est
    # un residu (modification annulee entre-temps) : on le leve sans bloquer.
    try:
        indexe = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True, text=True, timeout=5, cwd=RACINE,
        ).stdout
    except Exception:
        indexe = ""
    if not any(sur_le_chemin(l) for l in indexe.splitlines()):
        MARQUEUR.unlink(missing_ok=True)
        return 0
    if mesure_posterieure_au_marqueur():
        MARQUEUR.unlink(missing_ok=True)
        return 0

    fichier = ""
    try:
        fichier = MARQUEUR.read_text(encoding="utf-8").splitlines()[1]
    except Exception:
        pass
    print(
        "⛔ COMMIT BLOQUÉ — le chemin de la récitation a été modifié et AUCUNE\n"
        "recette n'a tourné depuis.\n\n"
        f"   dernière modification : {fichier}\n\n"
        "Le socle n'a donc pas été vérifié : « le récitateur récite, l'app\n"
        "contrôle en streaming, et dit vrai ». Figer un correctif non mesuré,\n"
        "c'est exactement ce qui a fait perdre une journée le 2026-07-29 (v8\n"
        "mesuré sous l'étiquette v23, neuf hypothèses réfutées pour rien).\n\n"
        "CE QU'IL FAUT FAIRE :\n"
        "  1. invoquer le skill `superviseur-recette`\n"
        "  2. DEPART=6 ADB=adb bash benchmark/recette_2tel.sh 2 420\n"
        "  3. python3 benchmark/taux_non_verts.py <dossier>/\n"
        "  4. passer les contrôles, dont le BLOQUANT :\n"
        "       grep -c 'entendu=\"\".*WordStatus\\.error (lock=true' <session.log>\n"
        "       → doit valoir 0\n\n"
        "Si la modification ne touche PAS le comportement (commentaire seul,\n"
        "renommage), dis-le explicitement à l'utilisateur et demande-lui de\n"
        "lever le garde-fou — ne le contourne pas de ta propre initiative.",
        file=sys.stderr,
    )
    return 2  # bloque l'appel


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "edit"
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    return mode_edit(data) if mode == "edit" else mode_garde(data)


if __name__ == "__main__":
    sys.exit(main())
