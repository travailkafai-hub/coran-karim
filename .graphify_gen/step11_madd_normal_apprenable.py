#!/usr/bin/env python3
"""`madd_normal` est apprenable : la condition de reouverture se realise.

Complete le noeud `mesure_madda_normal_violet_permanent` (2026-09-08, matin)
par ce que le checkpoint `madd-union-plus-normal-v1` a mesure le soir meme.

REGLE PROJET RESPECTEE : on n'ecrase rien, sauvegarde dans
graphify-out/graph_avant_madd_normal.json.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("attente_madd_normal_apprenable",
     "[EN ATTENTE] `madd_normal` EST apprenable -- reste a l'exporter",
     "MESURE (checkpoint `madd-union-plus-normal-v1`, entraine et valide le "
     "2026-09-08, voix disjointes, pilote 1500 fenetres) : 12 classes -- les 11 "
     "de madd-union plus `madd_normal` en ID 11, sans decaler les IDs "
     "existants. Rappel brut 83,15 % pour 13,11 % de faux positifs fenetre ; "
     "calibre a 1 % de FP, 39,56 % pour 0,90 %. Comparee a `madd` (les 3 "
     "autres) sur le MEME run : 89,89 %/11,64 % et 64,42 %/1,47 %. Elle est "
     "donc un peu en dessous mais DU MEME ORDRE, sur un premier essai -- alors "
     "que le modele deploye n'a pour elle qu'un canal CONSTANT, donc un rappel "
     "structurellement nul. Parite PyTorch/ONNX verifiee, ecart max 3,4e-5. "
     "PAS ENCORE EXPORTABLE : validation diagnostique sur pilote, pas les "
     "11 823 fenetres du banc complet, et le LISEZ_MOI du transfert l'ecrit. "
     "Quatre conditions pour rouvrir, dans l'ordre : gate >= 90 % sur le banc "
     "complet ; export avec un canal REEL (verifier qu'il n'y a plus de "
     "`ConstantOfShape` a la position 3 du Concat de sortie) ; un seuil qui ne "
     "soit plus 1,1 dans seuils_tajwid.json ; alors seulement la sortir de "
     "`porteesParLeTexte`."),

    ("mort_compteur_six_secondes_sans_placer",
     "[MORT] Compteur de 6 s « rien ne se place » pour sortir du suivi",
     "AJOUTE PUIS RETIRE LE MEME JOUR (2026-09-08), sur demande utilisateur "
     "dans les deux sens (« rajoute un compteur de 6 s » le matin, « le "
     "minuteur de 6 s, plus d'interet » le soir). MESURE QUI LUI DONNE TORT, "
     "session de 21:21 : 21:21:46,47 DECROCHAGE, 21:21:47,48 souffle du "
     "passage 35..35, 21:21:53,48 « 6s sans reussir a placer un seul mot -> "
     "ruku' ». Le micro etait coupe PAR LE SOUFFLEUR : le compteur ne pouvait "
     "qu'expirer, et son message accusait le recitant d'etre passe au ruku' "
     "alors que c'est l'application qui parlait. Le desarmement pendant le "
     "souffle corrigeait ce cas, mais six secondes sans placement restent "
     "ordinaires des que la transcription se degrade, et le prix d'une sortie "
     "a tort est eleve : on rend la main en pleine sourate. Les trois sorties "
     "restantes suffisent, dont deux reposent sur ce qui est ENTENDU et non "
     "sur un chronometre -- takbir, debut d'Al-Fatiha, silence reel de 30 s."),

    ("mort_rejouer_le_meme_passage",
     "[MORT] Rejouer un passage deja souffle apres un delai",
     "REFUSE PAR L'UTILISATEUR (2026-09-08) : « je ne comprends pas, je n'ai "
     "jamais demande de rejouer le meme audio ». J'avais rendu un passage "
     "redisible au bout de 10 s en lisant la session de 21:21, ou le recitant "
     "restait bloque au mot 20 et ou les deux mecanismes d'aide etaient refuses "
     "par le garde -- j'y avais vu une demande de reentendre. Sa consigne "
     "portait en fait sur le minuteur qui courait pendant le souffle : j'ai "
     "etendu sa demande au-dela de ce qu'elle disait. Le garde redevient "
     "strict, un passage souffle une fois ne l'est plus sur la meme cible. "
     "L'horodatage est conserve pour que le journal dise DEPUIS QUAND -- c'est "
     "ce qui manquait pour comprendre la session de 21:21."),
]

LIENS = [
    ("attente_madd_normal_apprenable", "mesure_madda_normal_violet_permanent",
     "reprend", "la condition de reouverture que ce noeud posait"),
    ("mort_compteur_six_secondes_sans_placer", "piege_minuteur_pendant_le_souffle",
     "reprend", "le piege qui l'a condamne : le micro coupe pendant la lecture"),
    ("mort_rejouer_le_meme_passage", "regle_aide_sur_silence_reel", "precise",
     "ce que l'aide ne doit PAS faire, meme quand le recitant reste arrete"),
]


def sha(ref="HEAD"):
    try:
        return subprocess.run(["git", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    existants = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid in existants:
            print(f"  = deja present : {nid}")
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "SUIVI_PRIERE.md", "source_location": None,
            "source_url": None, "captured_at": "2026-09-08", "author": None,
            "contributor": None, "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower(),
        })
        ajoutes += 1

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel, pourquoi in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            continue
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": pourquoi, "rationale": pourquoi,
        })
        aretes += 1

    shutil.copy2(GRAPHE, SORTIE / "graph_avant_madd_normal.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
