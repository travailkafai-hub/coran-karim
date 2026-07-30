#!/usr/bin/env python3
"""La v2 sur DEVICE : la premiere prediction hors device de ce projet qui tient.

Meme principe que les steps precedents : on enrichit, on n'ecrase pas, et le
`rationale` porte le chiffre.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_v2_sur_device",
     "[MESURE] v2 sur device : 2,37 %, et LES MEMES MOTS que le banc",
     "Recette deterministe sur telephone (build v2-branchee-parallele, WAV "
     "rejoue a la place du micro, sourate 2 depart v6, 295 mots) : 287 "
     "definitif:vert, 1 provisoire:vert, 3 omis (67, 181, 228), 2 "
     "provisoire:rouge (169, 172), 2 provisoire:orange (282, 285) = 7 non verts "
     "= 2,37 %. Le banc hors telephone predisait 2,03 % sur le meme flux brut, "
     "et surtout LES MEMES MOTS. Reference v1 seule, meme protocole : 10,10 %. "
     "C'est la premiere prediction hors device de ce projet qui se verifie sur "
     "device -- elle tient parce que le banc APPELLE le code de l'app au lieu "
     "de le reimplementer."),
    ("piege_cout_du_mode_parallele",
     "[PIEGE] Faire tourner v1 et v2 ensemble degrade la v1",
     "MESURE : dans la session parallele, l'ancre de la v1 s'est arretee au mot "
     "106 sur 295 et ses passes montent a 1389 ms, alors qu'elle atteint 297 en "
     "solo. Doubler la charge d'inference n'est pas gratuit. Deux consequences : "
     "(1) le chiffre de la v1 dans une session parallele est BIAISE CONTRE ELLE "
     "et ne doit pas etre compare a son chiffre solo ; (2) le mode parallele est "
     "un outil de comparaison, pas un etat de deploiement -- le jour ou la v2 "
     "est validee, la v1 doit etre COUPEE, pas laissee tourner."),
    ("piege_session_qui_ne_mesure_pas_ce_qu_elle_annonce",
     "[PIEGE] Une session peut porter le bon tag et mesurer autre chose",
     "MESURE : la premiere session etiquetee `v2-branchee-parallele` contenait "
     "ZERO ligne [V2]. `v2Activer` n'etait appele que sur deux des trois chemins "
     "de demarrage du provider, et pas sur celui qu'emprunte la recette. Le tag "
     "de build etait pourtant correct. ⇒ Verifier la PRESENCE DES TRACES du "
     "composant teste, pas seulement le tag. C'est le meme piege que « v8 mesure "
     "sous l'etiquette v23 » (2026-07-29), sous une autre forme."),
    ("piege_banc_dependant_du_debit_du_journal",
     "[PIEGE] Une detection de demarrage ne doit pas dependre du DEBIT du journal",
     "MESURE : `recette_2tel.sh` cherchait « capture ouverte » dans les 60 "
     "dernieres lignes du log. Depuis que la v2 journalise ses blocs, le "
     "marqueur en sort en une fraction de seconde : le banc a conclu « le micro "
     "ne s'est jamais ouvert » ALORS QUE LA SESSION TOURNAIT (verifie dans le "
     "log du telephone). Fenetre portee a 400 lignes. Un banc dont le verdict "
     "depend de la verbosite du composant mesure n'est pas un banc."),
]

LIENS = [
    ("mesure_v2_sur_device", "regle_banc_appelle_le_code", "confirme",
     "la prediction hors device se verifie, sur les memes mots"),
    ("mesure_v2_sur_device", "mesure_decoupage_silences", "confirme",
     "le gain du decoupage aux silences tient sur device"),
    ("piege_cout_du_mode_parallele", "couche_v2_c_front", "nait_dans", None),
    ("piege_session_qui_ne_mesure_pas_ce_qu_elle_annonce", "regle_mesure_avant_kotlin",
     "precise", "le tag ne suffit pas, il faut les traces du composant"),
    ("piege_banc_dependant_du_debit_du_journal", "regle_banc_appelle_le_code",
     "precise", "un banc ne doit pas dependre de la verbosite du mesure"),
]


def sha(ref="HEAD"):
    try:
        return subprocess.run(["git", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "SOLUTIONS_RECITATION_V2.md", "source_location": None,
            "source_url": None, "captured_at": "2026-07-30", "author": None,
            "contributor": None, "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower(),
        })
        ajoutes += 1

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel, pourquoi in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}")
            continue
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": pourquoi, "rationale": pourquoi,
        })
        aretes += 1

    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step11.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
