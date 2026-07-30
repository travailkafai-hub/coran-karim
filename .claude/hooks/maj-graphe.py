#!/usr/bin/env python3
"""Empeche le graphe de decrocher du code qu'il est cense decrire.

POURQUOI CE HOOK EXISTE (2026-07-30, demande utilisateur : « rajoute ce hook,
apres dev mise a jour du graph »).

Le graphe est LA seule source du projet qui dise ce qui a ete *mesure*, pas ce
qui a ete *espere*. Sa valeur ne tient qu'a une chose : etre a jour. Un graphe
en retard est pire qu'aucun graphe -- il donne la confiance d'avoir verifie
« est-ce que ca a deja ete essaye ? » alors que la reponse manque. Et le cout
du retard est connu et chiffre : NEUF versions mesurees n'ont jamais ete
consignees, dont `v5b-derive`, le meilleur resultat du projet (mediane 0,57 %,
une passe a 0,00 %), code irrecuperable. Sa mesure survit UNIQUEMENT parce que
quelqu'un l'a ecrite quelque part.

CE QU'IL FAUT ECRIRE DANS LE GRAPHE. Pas ce qu'on a code : ce que la mesure a
DIT. Un noeud sans chiffre ne sert a rien. Les prefixes qui font le garde-fou :
[MORT] (mesure perdante), [PIEGE] (erreur deja commise), [EN ATTENTE] (non
mesure ou non gagnant aujourd'hui), [SYMPTOME] (avec la couche ou il NAIT),
[REGLE], [MESURE].

DEUX MODES, branches dans .claude/settings.json :

  rappel   PostToolUse sur Bash
           -> apres un commit qui touche la chaine, rappelle ce qu'il reste a
              consigner. Informatif.

  garde    PreToolUse sur Bash
           -> BLOQUE le gel de version quand le graphe a DEUX commits de chaine
              de retard ou plus. Un commit de retard est tolere (on code puis on
              consigne) ; deux, c'est une derive qui ne se rattrape jamais.
              Ne peut pas se bloquer lui-meme : mettre a jour le graphe fait
              avancer `built_at_commit`, donc lever le compteur.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

RACINE = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")).resolve()
GRAPHE = RACINE / "graphify-out" / "graph.json"

# Les memes racines que le superviseur : ce qui compte est « le graphe
# decrit-il encore la chaine de recitation telle qu'elle est ? ».
CHEMIN_GLOBS = (
    "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/",
    "app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/",
    "app/lib/providers/recitation_provider.dart",
    "app/lib/services/recitation_verifier.dart",
    "app/lib/services/fastconformer_verifier.dart",
)

TOLERANCE = 2  # commits de chaine de retard avant blocage


def git(*args, defaut=""):
    try:
        r = subprocess.run(["git", *args], capture_output=True, text=True,
                           timeout=8, cwd=RACINE)
        return r.stdout.strip() if r.returncode == 0 else defaut
    except Exception:
        return defaut


def commit_du_graphe() -> str:
    if not GRAPHE.exists():
        return ""
    try:
        # Lecture ciblee : le graphe fait plusieurs Mo, on ne le parse pas en
        # entier a chaque appel de hook.
        texte = GRAPHE.read_text(encoding="utf-8")
        return json.loads(texte).get("built_at_commit") or ""
    except Exception:
        return ""


def retard() -> tuple:
    """(nb de commits de chaine depuis le graphe, liste des sujets)."""
    base = commit_du_graphe()
    if not base:
        return 0, []
    if not git("cat-file", "-e", f"{base}^{{commit}}", defaut="ABSENT") == "":
        # Le commit du graphe n'existe pas ici (autre branche, historique
        # reecrit) : on ne bloque pas sur une comparaison impossible.
        if git("rev-parse", "--verify", "--quiet", base) == "":
            return 0, []
    sortie = git("log", "--oneline", f"{base}..HEAD", "--", *CHEMIN_GLOBS)
    lignes = [l for l in sortie.splitlines() if l.strip()]
    return len(lignes), lignes


def mode_rappel(data) -> int:
    cmd = (data.get("tool_input") or {}).get("command", "")
    if "commit" not in cmd or "git" not in cmd:
        return 0
    n, sujets = retard()
    if n == 0:
        return 0
    print(
        f"🕸️  GRAPHE À METTRE À JOUR — {n} commit(s) de chaîne depuis sa dernière\n"
        "construction :\n" + "".join(f"   {s}\n" for s in sujets[:5]) + "\n"
        "Consigne ce que la MESURE a dit, pas ce que le code fait : un nœud sans\n"
        "chiffre ne sert à rien. Préfixes : [MORT] / [PIEGE] / [EN ATTENTE] /\n"
        "[SYMPTOME] (avec la couche où il NAÎT) / [REGLE] / [MESURE].\n\n"
        "   python3 .graphify_gen/step8_v2.py     (ou un step9_… sur son modèle)\n\n"
        "Neuf versions mesurées ont déjà été perdues faute d'être consignées,\n"
        "dont le meilleur résultat du projet.",
        file=sys.stderr,
    )
    return 0


def mode_garde(data) -> int:
    cmd = (data.get("tool_input") or {}).get("command", "")
    if "commit" not in cmd or "git" not in cmd:
        return 0
    n, sujets = retard()
    if n < TOLERANCE:
        return 0
    print(
        f"⛔ BLOQUÉ — le graphe a {n} commits de chaîne de retard.\n\n"
        + "".join(f"   {s}\n" for s in sujets[:8]) +
        "\nUn graphe en retard est pire qu'aucun graphe : il donne la confiance\n"
        "d'avoir vérifié « est-ce que ça a déjà été essayé ? » alors que la\n"
        "réponse manque. Un commit de retard est toléré — on code puis on\n"
        "consigne. Deux, c'est une dérive qui ne se rattrape jamais.\n\n"
        "CE QU'IL FAUT FAIRE : ajouter les nœuds de ce qui vient d'être mesuré\n"
        "(prendre .graphify_gen/step8_v2.py comme modèle), avec dans `rationale`\n"
        "LE CHIFFRE et non l'intention, puis relancer le script. Il sauvegarde\n"
        "l'état précédent — aucune piste n'est jamais écrasée.\n\n"
        "Si le commit en cours EST la mise à jour du graphe, elle fait avancer\n"
        "`built_at_commit` : relance le script avant de committer.",
        file=sys.stderr,
    )
    return 2


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "rappel"
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    return mode_garde(data) if mode == "garde" else mode_rappel(data)


if __name__ == "__main__":
    sys.exit(main())
