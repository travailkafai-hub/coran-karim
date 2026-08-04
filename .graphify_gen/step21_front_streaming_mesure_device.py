#!/usr/bin/env python3
"""Le front streaming branche dans la v2 : mesure DEVICE, meme WAV au bit pres.

2026-08-02. Rejeu deterministe du WAV brut de la session de 13:54 sur le build
offline restaure. Curseur identique des deux cotes (verifie), donc la seule
variable est le front acoustique.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mort_front_streaming_branche_dans_v2",
     "[MORT] Front streaming par bloc branche dans la v2 : 34 % de mots non verts",
     "Rejeu DETERMINISTE du meme WAV au bit pres (sourate 18, depart v1, 252 s), "
     "curseur IDENTIQUE des deux cotes (fenetre dominante 4,0 s -- verifie, ce "
     "n'etait pas la variable). Compte sur ANCRE MAX, pas sur mots juges. "
     "  front STREAMING (build v17-sans-plafond) : ancre 191, vert 127, "
     "OMIS 57, rouge 7, orange 1 -> 34,03 % de mots non verts. "
     "  front OFFLINE (build v6-offline-final-v1) : ancre 189, vert 188, "
     "omis 0, rouge 1, orange 1 -> 1,06 %. "
     "RECOUPEMENT INDEPENDANT : le banc de l'autre session donnait 33,56 % pour "
     "le streaming a cache continu -- deux instruments differents, meme verdict. "
     "Le symptome dominant est l'OMIS (57 -> 0) : le front streaming ne situe "
     "pas le recitateur (125 fenetres `bande=inconnue` contre 67 en offline), "
     "donc la bande n'est pas identifiee et les mots tombent en omis alors "
     "qu'ils sont prononces. "
     "A NE PAS confondre avec le contexte causal : ce n'est pas le lookahead "
     "qui est en cause, c'est la propagation du cache d'un bloc au suivant."),

    ("piege_confondre_les_instruments_de_mesure",
     "[PIEGE] Comparer des taux venant de bancs differents",
     "Erreur commise le 2026-08-02 et relevee par l'utilisateur : j'ai presente "
     "3,73 % comme la reference de l'offline, alors que ce chiffre vient du "
     "banc de comparaison des trois modes de cache de l'autre session. "
     "Les references reelles du projet sont : 1,69 % au banc JVM BancFluxBrut "
     "(2/4 + 0,25, final-v1), 2,37 % sur device au commit « v2 branchee a "
     "l'ecran », et 1,06 % sur device au rejeu deterministe du 2026-08-02. "
     "L'utilisateur se souvenait de « moins de 2 %, 1,6... » -- sa memoire "
     "etait juste, le chiffre repris sans en verifier l'origine ne l'etait pas. "
     "REGLE : un taux ne se compare qu'a un taux produit par le MEME "
     "instrument, sur le MEME materiau. Citer un chiffre sans nommer son banc "
     "est une faute de methode, pas un raccourci."),

    ("mesure_v2_inchangee_sauf_les_trois_valeurs",
     "[MESURE] Entre le commit 3/9 et le commit 2/4, la v2 QUI TOURNE ne change pas",
     "Verifie sur le diff e9d7612 -> 775539e. Le package `recitation2/` gagne "
     "206 lignes dont un fichier NEUF `FrontStreamingParBloc.kt` (96 lignes), "
     "mais ce front n'est JAMAIS instancie dans 775539e : le plugin construit "
     "`FrontOnnx` aux deux points de construction. C'est du code pose dans le "
     "package, pas branche. "
     "Donc structurellement la v2 a bouge, FONCTIONNELLEMENT la chaine qui "
     "s'execute est inchangee a part apercuSecondes 3->2, "
     "fenetreApercuSecondes 9->4, pauseMinSecondes 0,40->0,25. "
     "L'utilisateur l'avait dit avant la verification : « sur v2 c'est plutot "
     "stable depuis hier, juste les valeurs 2 4 0,25 qui ont change ». "
     "COROLLAIRE : le build v17-sans-plafond qui tournait sur le telephone "
     "branchait ce front par du code NON COMMITE -- sa ligne "
     "`front = STREAMING incremental` n'existe dans aucun commit du depot."),
]

LIENS = [
    ("mort_front_streaming_branche_dans_v2",
     "mesure_gain_streaming_reduit_depuis_2s_4s", "refute",
     "le gain de latence calcule supposait une qualite equivalente : elle ne l'est pas"),
    ("mort_front_streaming_branche_dans_v2",
     "mesure_v2_inchangee_sauf_les_trois_valeurs", "isole",
     "le curseur etant identique, la seule variable restante est le front"),
    ("piege_confondre_les_instruments_de_mesure",
     "mesure_curseur_2s_4s_gagne", "protege",
     "1,69 % est un chiffre de banc JVM, pas un taux device"),
    ("mesure_v2_inchangee_sauf_les_trois_valeurs",
     "piege_deux_agents_un_seul_telephone", "decoule_de",
     "un build non commite tournait sur les telephones"),
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
            "source_url": None, "captured_at": "2026-08-02", "author": None,
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
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pourquoi, "rationale": pourquoi})
        aretes += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step21.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
