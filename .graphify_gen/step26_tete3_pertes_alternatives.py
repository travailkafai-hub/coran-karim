#!/usr/bin/env python3
"""Deux pertes alternatives pour la tete 3, mesurees et refutees (2026-08-05)."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mort_tete3_perte_de_rang_par_paires",
     "[MORT] Tete 3 entrainee PAR PAIRES (rang intra-paire) : 43 % contre 47 %",
     "Idee : le corpus TTS est APPARIE (meme mot, meme voix, meme phrase -- "
     "seule la faute differe), et `det@collateral` est une metrique de "
     "CLASSEMENT alors que la BCE optimise la CALIBRATION. Comparer un mot a "
     "LUI-MEME devait supprimer toute la variation de nuisance (timbre, "
     "identite du mot, position) et ne laisser que la deviation. "
     "MESURE, 18 configurations, meme test et meme graine que la reference : "
     "rang SEUL 13-16 % (AUC 0,78) ; rang + ancrage BCE 0,2 -> 37-40 % ; "
     "rang + ancrage BCE 1,0 -> 42-43 %. MEILLEUR 43 %, contre 47 % pour la "
     "BCE seule. "
     "POURQUOI CA ECHOUE, et c'est le vrai enseignement : contraindre `faute_i` "
     "face a SON PROPRE correct est une contrainte LOCALE, alors que la mesure "
     "exige que chaque faute passe devant TOUS les mots corrects du corpus. "
     "Ordonner deux versions d'un meme mot n'y contribue presque pas, et peut "
     "contrarier l'ordre global. Le pairage, si seduisant soit-il, n'attaque "
     "pas la bonne quantite."),

    ("mort_tete3_perte_ciblee_sur_la_region_de_collateral",
     "[MORT] Perte ciblee sur les 2 % de collateral : s'effondre sur une solution constante",
     "Suite logique du diagnostic precedent : puisque `det@2 %` ne regarde que "
     "les fautes situees au-dessus du 98e centile des scores des CORRECTS, et "
     "que 98 % des exemples -- invisibles a la mesure -- accaparent le gradient "
     "d'une BCE, on optimisait massivement ce qu'on ne mesure pas. Perte "
     "ecrite : seuil `tau` = quantile (1-alpha) des corrects recalcule a chaque "
     "pas, charniere sur les fautes SOUS `tau`, charniere sur les corrects "
     "AU-DESSUS. "
     "MESURE, 12 configurations : effondrement systematique des que la BCE ne "
     "domine pas -- AUC 0,496 a 0,546 et 0 a 1 % de detection, c'est-a-dire le "
     "hasard. Avec `w_bce = 2,0` (la BCE domine) on remonte a 44-45 %, donc "
     "SOUS les 47 % de la BCE seule : le terme cible ne fait que degrader ce "
     "qui marchait. MEILLEUR 45 %. "
     "CAUSE, previsible avec le recul : la perte a une SOLUTION DEGENEREE. Si "
     "tous les scores sont egaux, `tau` suit, les deux charnieres valent la "
     "marge et le gradient ne pointe plus nulle part. Un quantile detache ne "
     "peut pas ancrer une echelle. "
     "A NE PAS REESSAYER sous cette forme. Une optimisation de pAUC demanderait "
     "un estimateur qui ne s'effondre pas (bornes fixes, ou pAUC par "
     "sous-echantillonnage), pas un quantile mobile."),
]

LIENS = [
    ("mort_tete3_perte_de_rang_par_paires",
     "regle_le_plafond_de_tete3_est_en_amont_delle", "confirme",
     "changer l'objectif ne franchit pas le plafond non plus"),
    ("mort_tete3_perte_ciblee_sur_la_region_de_collateral",
     "mort_tete3_perte_de_rang_par_paires", "suit",
     "seconde tentative sur l'objectif, apres l'echec de la contrainte locale"),
    ("mort_tete3_perte_ciblee_sur_la_region_de_collateral",
     "regle_le_plafond_de_tete3_est_en_amont_delle", "confirme",
     "ni la capacite, ni les donnees, ni l'objectif ne debloquent 47 %"),
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
    a = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "benchmark/NOTE_TETE3_OBJECTIF_80.md",
            "source_location": None, "source_url": None,
            "captured_at": "2026-08-05", "author": None, "contributor": None,
            "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}"); continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step26.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
