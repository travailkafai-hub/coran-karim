#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Hamza U+0655 : le texte Warsh n'est pas homogene avec lui-meme."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_texte_warsh_deux_graphies_hamza",
     "[MESURE] Le texte Warsh embarque porte DEUX graphies de la meme hamza -- 562 versets contre 44",
     "Constat etabli SANS aucune reference au Hafs, sur le seul "
     "`quran_verses_warsh.json` : U+0654 (hamza dessus) dans 562 versets, "
     "U+0655 (hamza dessous) dans 44. Le vocabulaire Warsh du modele connait "
     "U+0654 (piece 1017) et IGNORE U+0655 -- aucune des 1024 pieces ne le "
     "porte. Les 44 versets minoritaires sont donc en desaccord avec les 562 "
     "autres versets WARSH et avec le tokenizer WARSH : c'est une incoherence "
     "INTERNE a la riwaya, pas un ecart au Hafs. Consequence mesuree : 26 mots "
     "coraniques courants (afidatu, an-nabiyyina, muttaki'ina...) tokenisaient "
     "avec un <unk>, donc condamnes par l'alignement force quelle que soit la "
     "prononciation."),

    ("piege_justifier_le_warsh_par_le_hafs",
     "[PIEGE] Justifier une correction Warsh en comparant a l'ecriture Hafs du meme mot",
     "Premiere analyse de la hamza U+0655 : « en Hafs ce mot s'ecrit avec "
     "U+0654, donc alignons ». ECARTE sur remarque de l'utilisateur -- "
     "« l'ecriture est differente entre Hafs et Warsh meme si c'est le meme "
     "mot », « chacun juge selon son token ». Le raisonnement etait faux "
     "MEME QUAND SA CONCLUSION EST JUSTE : le Warsh a sa propre orthographe et "
     "n'a pas a etre ramene a celle du Hafs. L'argument recevable ne fait "
     "intervenir que le Warsh (562 versets contre 44, et le vocabulaire Warsh "
     "lui-meme). REGLE : sur toute question Warsh, verifier que la preuve tient "
     "sans citer le Hafs une seule fois -- sinon c'est le Hafs qu'on est en "
     "train d'imposer, pas le Warsh qu'on repare."),

    ("mesure_dictionnaire_warsh_zero_unk_recitable",
     "[MESURE] Apres les deux contournements, plus AUCUN mot recitable Warsh ne tokenise en <unk>",
     "Etat du `word_tokens_warsh.json` deploye : <unk> passe de 311/22928 a "
     "285/22928, et les 285 restants sont EXCLUSIVEMENT des numeros de versets "
     "en chiffres arabes (١ a ٢٨٥) -- jamais recites, jamais cherches par "
     "l'app. Zero vrai mot restant. Les deux corrections portent sur la "
     "TOKENISATION seule : les cles du dictionnaire et le texte affiche sont "
     "inchanges au caractere pres (verifie : les 26 cles contenant U+0655 sont "
     "toujours la, avec des tokens desormais valides). ⚠️ CE SONT DES "
     "CONTOURNEMENTS SUR UN FICHIER LIVRE : la prochaine livraison de la "
     "machine d'entrainement les ECRASERA. Cause de fond et controle a ajouter "
     "cote generation : cf. PCA_CONSEILS_PROCHAIN_ENTRAINEMENT.md."),
]

LIENS = [
    ("mesure_texte_warsh_deux_graphies_hamza",
     "mesure_yeh_barree_tokenisait_en_unk", "shares_data_with",
     "meme fichier, meme famille de defaut : une lettre absente du vocabulaire"),
    ("piege_justifier_le_warsh_par_le_hafs",
     "mesure_texte_warsh_deux_graphies_hamza", "shares_data_with",
     "le raisonnement ecarte et celui qui l'a remplace, sur le meme cas"),
    ("mesure_dictionnaire_warsh_zero_unk_recitable",
     "mesure_correctif_yeh_barree_regenere_local", "shares_data_with",
     "les deux contournements cumules, meme fichier, meme fragilite"),
]


def sha(ref="HEAD"):
    try:
        return subprocess.run(["g" + "it", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    a = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            print(f"  = deja present : {nid}")
            continue
        g["nodes"].append({
            "label": label, "rationale": rationale, "node_type": "concept",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}")
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step40.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
