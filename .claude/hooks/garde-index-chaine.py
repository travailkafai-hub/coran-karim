#!/usr/bin/env python3
"""Empêche de committer par accident les fichiers de la CHAÎNE de récitation.

POURQUOI CE HOOK EXISTE — un accident réel, le 2026-07-29.

`benchmark/balayage_versions.sh` greffe la version d'un autre commit avec
`git checkout <sha> -- <les 3 fichiers de chaîne>`. Or cette commande met à jour
**l'INDEX** en plus du répertoire de travail. Les fichiers greffés restaient donc
indexés après le balayage — et le commit suivant les emportait, même quand le
`git add` ne visait que deux scripts de banc.

Résultat : `a0c8935`, intitulé « Banc : le balayage installait en local puis
récitait sur le PC B », a commité **−452 lignes de BufferedTranscriber.kt** et
−22 de ForcedAligner.kt. La branche est revenue à v8 sans que personne le voie.
Toute la soirée de mesures a ensuite tourné sur v8 sous l'étiquette v23 — donc
avec le resync ACTIF, alors que v23 le coupe précisément. Neuf hypothèses ont
été explorées et réfutées pour chercher la cause d'un décrochage que v23 avait
déjà corrigé.

La cause est traitée dans le balayage lui-même (`git restore --staged` en fin de
course). Ce hook est le FILET : il rattrape le cas où l'index est sale pour une
autre raison — un checkout manuel, un balayage interrompu, un `git add -A`.

CE QU'IL FAIT : sur une commande `git commit`, si un fichier de chaîne est
indexé alors que le message ne parle QUE du banc ou de la documentation, il
refuse et explique. Il ne bloque JAMAIS un commit qui assume de toucher la
chaîne — le but est de rendre l'accident visible, pas d'interdire le travail.

Branché dans .claude/settings.json en PreToolUse sur Bash.
"""
import json
import re
import subprocess
import sys

# Les fichiers dont une modification silencieuse change ce qui est MESURÉ.
CHAINE = (
    "fastconformer/BufferedTranscriber.kt",
    "fastconformer/ForcedAligner.kt",
    "providers/recitation_provider.dart",
    "services/diagnostic_log.dart",
)

# Un message qui ne parle que de ça n'a aucune raison d'emporter la chaîne.
HORS_CHAINE = re.compile(
    r"\b(banc|bench|benchmark|script|doc|documentation|readme|skill|hook|"
    r"consigne|trace|note)\b",
    re.IGNORECASE,
)
# ... sauf s'il annonce explicitement qu'il touche la chaîne.
ANNONCE_CHAINE = re.compile(
    r"\b(chaine|chaîne|ancre|resync|aligneur|alignement|buffer|segmentation|"
    r"jugement|gel|v\d+)\b",
    re.IGNORECASE,
)


def indexes():
    """Fichiers de chaîne actuellement dans l'index (staged)."""
    try:
        out = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except Exception:
        return []
    return [l for l in out.splitlines() if any(c in l for c in CHAINE)]


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    cmd = (data.get("tool_input") or {}).get("command", "")
    if "git commit" not in cmd:
        return 0

    touches = indexes()
    if not touches:
        return 0

    # Le message annonce-t-il qu'on touche à la chaîne ? Alors c'est voulu.
    if ANNONCE_CHAINE.search(cmd):
        return 0
    # Un message purement banc/doc qui emporte la chaîne : c'est l'accident.
    if not HORS_CHAINE.search(cmd):
        return 0

    liste = "\n".join(f"    {f}" for f in touches)
    print(
        "⛔ COMMIT REFUSÉ — des fichiers de la CHAÎNE DE RÉCITATION sont indexés\n"
        "alors que le message ne parle que du banc ou de la documentation :\n\n"
        f"{liste}\n\n"
        "C'est exactement l'accident du 2026-07-29 (a0c8935) : un commit de banc\n"
        "a emporté -452 lignes de BufferedTranscriber.kt, ramenant la branche à v8\n"
        "sans que personne le voie. Toutes les mesures suivantes ont porté sur une\n"
        "version différente de celle annoncée par le tag de build.\n\n"
        "QUE FAIRE :\n"
        "  • si ces fichiers ne doivent PAS partir (cas le plus fréquent) :\n"
        "      git restore --staged <les fichiers ci-dessus>\n"
        "  • s'ils doivent partir, dites-le dans le message (« chaîne », « ancre »,\n"
        "    « resync », « v24 »…) — le hook laisse alors passer.\n\n"
        "Vérifiez AVANT : git diff --cached --stat",
        file=sys.stderr,
    )
    return 2  # bloque l'appel et renvoie le message à l'agent


if __name__ == "__main__":
    sys.exit(main())
