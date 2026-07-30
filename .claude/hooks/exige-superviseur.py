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
quitte) mais par une PREUVE datant d'APRES la derniere modification du chemin.
Pas de mesure, pas de commit.

DEUX NATURES DE PREUVE (revision du 2026-07-30, demande utilisateur : « c'etait
sur la boucle des modifications d'avant, quand ce n'etait que des correctifs
palliatifs »). Ce hook a ete ecrit pendant la phase ou l'on RETOUCHAIT sans fin
une chaine deja branchee a l'ecran : la seule preuve valable etait alors une
recette sur telephone, parce que chaque ligne modifiee peignait immediatement du
vert ou du rouge devant l'utilisateur. Exiger la meme chose d'un code qui n'est
BRANCHE SUR RIEN n'ajoute aucune securite : ca interdit seulement de committer,
donc ca pousse a accumuler du travail non commite -- exactement ce qui a fait
perdre NEUF versions mesurees, dont le meilleur resultat du projet
(`piege_9_versions_perdues`, mediane 0,57 %, code irrecuperable).

  chemin LIVE (la chaine qui peint l'ecran)  -> recette a deux telephones
  chemin HORS LIGNE (code non branche)       -> tests unitaires JVM au vert

Dans les deux cas c'est une preuve MECANIQUE, jamais une declaration de
l'agent. Et des qu'un fichier live est touche, meme en meme temps que du hors
ligne, c'est la recette qui est exigee -- le doute profite au socle.
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
# Racines a interroger dans `git status` -- les chemins complets sont ensuite
# filtres par `sur_le_chemin`.
CHEMIN_GLOBS = (
    "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/",
    "app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/",
    "app/android/app/src/test/kotlin/com/corankarim/coran_karim/recitation2/",
    "app/lib/providers/",
    "app/lib/services/",
    "app/lib/screens/karaoke_recitation_screen.dart",
)

# HORS LIGNE : du code de la chaine, mais qui n'est BRANCHE SUR RIEN. Il ne peut
# pas peindre une couleur fausse a l'ecran, donc une recette a deux telephones
# ne mesurerait rien de lui. Sa preuve est le banc JVM, qui appelle son vrai
# code (couches pures, cf. CONCEPTION_RECITATION_V2.md).
#
# ATTENTION EN LE FAISANT EVOLUER : le jour ou la v2 est branchee a l'ecran,
# `recitation2/` doit SORTIR de cette liste. Un code branche mesure par des
# tests unitaires seulement, c'est le retour au point de depart.
HORS_LIGNE = (
    "coran_karim/recitation2/",
    "services/recitation_v2_bench.dart",
)

RESULTATS_JVM = (
    RACINE / "app" / "build" / "app" / "test-results" / "testDebugUnitTest"
)

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


def hors_ligne(p: str) -> bool:
    """Fichier de la chaine, mais non branche : preuve = tests JVM."""
    p = p.replace("\\", "/")
    return any(c in p for c in HORS_LIGNE)


def sur_le_chemin(p: str) -> bool:
    """Fichier de la chaine LIVE : preuve = recette a deux telephones."""
    p = p.replace("\\", "/")
    if hors_ligne(p):
        return False
    return any(c in p for c in CHEMIN)


def sur_le_chemin_large(p: str) -> bool:
    return sur_le_chemin(p) or hors_ligne(p)


def instant_derniere_modif() -> float:
    """Date de la derniere modification du chemin, marqueur OU fichier source.

    Sans le repli sur la date des FICHIERS, une edition faite hors Edit/Write
    (sed, python via Bash, redirection) ne posait pas de marqueur, et l'absence
    de marqueur etait interpretee comme « rien a verifier » -- le garde-fou
    laissait alors passer le commit. Vu le 2026-07-30.
    """
    t = MARQUEUR.stat().st_mtime if MARQUEUR.exists() else 0.0
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain", "--"] + list(CHEMIN_GLOBS),
            capture_output=True, text=True, timeout=5, cwd=RACINE,
        ).stdout
    except Exception:
        out = ""
    for ligne in out.splitlines():
        chemin = ligne[3:].strip().strip('"')
        if not sur_le_chemin_large(chemin):
            continue
        f = RACINE / chemin
        if f.exists():
            t = max(t, f.stat().st_mtime)
    return t


def modifications_par_nature():
    """(fichiers live modifies, fichiers hors ligne modifies), indexes ou non."""
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain", "--"] + list(CHEMIN_GLOBS),
            capture_output=True, text=True, timeout=5, cwd=RACINE,
        ).stdout
    except Exception:
        return [], []
    live, offline = [], []
    for ligne in out.splitlines():
        chemin = ligne[3:].strip().strip('"')
        if sur_le_chemin(chemin):
            live.append(chemin)
        elif hors_ligne(chemin):
            offline.append(chemin)
    return live, offline


def tests_jvm_au_vert_posterieurs() -> bool:
    """Un run JUnit posterieur a la derniere modification, et SANS echec ?

    On lit les XML de resultats, pas une declaration : `failures` et `errors`
    doivent valoir 0 sur chaque classe, et le fichier doit etre plus recent que
    la modification. Un run qui n'a pas tourne depuis ne prouve rien.
    """
    t = instant_derniere_modif()
    if t == 0.0:
        return True
    if not RESULTATS_JVM.is_dir():
        return False
    vu = False
    for f in RESULTATS_JVM.glob("*.xml"):
        if f.stat().st_mtime <= t:
            continue
        texte = f.read_text(encoding="utf-8", errors="replace")
        entete = texte[:2000]
        if re.search(r'failures="([1-9]\d*)"', entete) or \
                re.search(r'errors="([1-9]\d*)"', entete):
            return False
        vu = True
    return vu


def mesure_posterieure_au_marqueur() -> bool:
    """Une recette a-t-elle tourne APRES la derniere modification du chemin ?"""
    t = instant_derniere_modif()
    if t == 0.0:
        return True          # rien de modifie : rien a verifier
    if not RECETTES.is_dir():
        return False
    for d in RECETTES.iterdir():
        if d.is_dir() and d.stat().st_mtime > t:
            return True
    return False


def mode_edit(data) -> int:
    chemin = (data.get("tool_input") or {}).get("file_path", "")
    if not chemin or not sur_le_chemin_large(chemin):
        return 0
    MARQUEUR.parent.mkdir(parents=True, exist_ok=True)
    MARQUEUR.write_text(f"{time.time()}\n{chemin}\n", encoding="utf-8")
    if hors_ligne(chemin):
        # Code non branche : pas de recette a exiger, mais pas de passe-droit
        # non plus. Le banc JVM appelle le VRAI code de ces couches ; c'est lui
        # qui a trouve, en quelques secondes, les trois defauts de socle que la
        # conception n'avait pas vus (premier mot declare omis, derniers mots
        # jamais verrouilles, mot saute juge ROUGE).
        print(
            "🧪 CHAÎNE v2 (hors ligne) MODIFIÉE — les tests JVM doivent repasser\n"
            f"   {Path(chemin).name}\n\n"
            "   cd app/android && ./gradlew --offline :app:testDebugUnitTest \\\n"
            '       --tests "com.corankarim.coran_karim.recitation2.*"\n\n'
            "Le gel de version restera BLOQUÉ tant qu'un run JUnit postérieur à\n"
            "cette modification n'est pas AU VERT. Le jour où la v2 est branchée\n"
            "à l'écran, elle sort de HORS_LIGNE et repasse à la recette.",
            file=sys.stderr,
        )
        return 0
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


def chaine_modifiee_dans_larbre() -> bool:
    """Le chemin de la recitation differe-t-il de HEAD, indexe ou non ?

    TROU BOUCHE (2026-07-30, trouve par l'utilisateur) : la version precedente
    ne reposait que sur le MARQUEUR, pose par le mode `edit` sur PostToolUse
    Edit|Write|MultiEdit. Or une modification faite par `sed`, un script python
    lance via Bash, ou une simple redirection shell ne passe par AUCUN de ces
    outils -- le marqueur n'etait donc pas pose, et `git commit` passait sans
    controle. C'est arrive pour de vrai : ForcedAligner.kt et
    BufferedTranscriber.kt ont ete modifies par heredoc python, le hook est
    reste muet, et le garde-fou n'aurait rien bloque.

    On interroge donc directement git : c'est l'ETAT DU FICHIER qui compte, pas
    l'outil qui l'a produit.
    """
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain", "--"] + list(CHEMIN_GLOBS),
            capture_output=True, text=True, timeout=5, cwd=RACINE,
        ).stdout
    except Exception:
        return False
    return any(sur_le_chemin_large(l) for l in out.splitlines())


def mode_garde(data) -> int:
    cmd = (data.get("tool_input") or {}).get("command", "")
    if "git commit" not in cmd:
        return 0
    # Le marqueur ne suffit pas : une edition hors Edit/Write ne le pose pas.
    if not MARQUEUR.exists() and not chaine_modifiee_dans_larbre():
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
    if not any(sur_le_chemin(l) for l in indexe.splitlines()) \
            and not chaine_modifiee_dans_larbre():
        MARQUEUR.unlink(missing_ok=True)
        return 0
    live, offline = modifications_par_nature()

    # Rien de LIVE : la preuve attendue est le banc JVM, pas une recette.
    # Le doute profite au socle -- des qu'un fichier live est touche, meme en
    # meme temps que du hors ligne, on repasse a l'exigence de recette.
    if not live and offline:
        if tests_jvm_au_vert_posterieurs():
            MARQUEUR.unlink(missing_ok=True)
            return 0
        print(
            "⛔ BLOQUÉ — la chaîne v2 (hors ligne) a été modifiée et AUCUN run\n"
            "de tests JVM au vert ne date d'après.\n\n"
            f"   fichiers : {', '.join(Path(f).name for f in offline)}\n\n"
            "Ce code n'est branché sur rien : une recette à deux téléphones ne\n"
            "mesurerait pas une ligne de lui. Sa preuve, c'est le banc — qui\n"
            "appelle son vrai code, et non une réimplémentation (deux prédictions\n"
            "hors device confiantes et fausses ont déjà été payées pour ça).\n\n"
            "CE QU'IL FAUT FAIRE :\n"
            "  cd app/android && ./gradlew --offline :app:testDebugUnitTest \\\n"
            '      --tests "com.corankarim.coran_karim.recitation2.*"\n\n'
            "Un run avec ne serait-ce qu'un échec ne lève pas le garde-fou.",
            file=sys.stderr,
        )
        return 2

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
