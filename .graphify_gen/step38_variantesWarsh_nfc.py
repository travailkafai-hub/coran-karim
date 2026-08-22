#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Correctif d'un agent tiers, valide par superviseur : variante NFC pour Warsh.

Contexte 2026-08-22 : un test Warsh sous v181 (cablage riwaya fonctionnel)
montrait 6 mots sur 7 non-verts avec un TEXTE RECONNU IDENTIQUE a l'attendu
mais un gop tres negatif -- signature d'un ecart de tokenisation, pas de
perception. Un correctif est arrive independamment pendant l'analyse.
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_warsh_mots_texte_identique_mais_rouges",
     "[MESURE] Sous v181 (riwaya cablee), 6/7 mots non-verts Warsh ont un texte reconnu IDENTIQUE a l'attendu",
     "Session Warsh reelle apres le cablage riwaya (mots 6, 9, 12, 13, 15, 18 "
     "d'Al-Fatiha) : le texte `entendu` egale exactement `attendu` "
     "(اِ۬لرَّحِيمِ==اِ۬لرَّحِيمِ, اِ۬لدِّينِۖ==اِ۬لدِّينِۖ, etc.) et pourtant le "
     "verdict reste rouge avec un gop tres negatif (-2,8 a -22,6). `frames` "
     "n'est PAS discriminant (mot 10, vert, et mot 9/12/18, rouges, ont tous "
     "frames=6) -- le score `forced` est faux malgre un texte juste, ce qui "
     "ecarte une cause de perception/segmentation et pointe vers un ecart de "
     "TOKENISATION CIBLE (la sequence de tokens du lookup Warsh ne "
     "correspond pas exactement a ce que le modele emet pour ce mot)."),

    ("mesure_correctif_variantesWarsh_nfc_valide_par_superviseur",
     "[MESURE] Correctif variantesWarsh (NFC) valide : compile, 20/20 tests JVM verts, coherent avec le graphe",
     "Un agent tiers a ajoute `Orthographe.variantesWarsh()` (variante en "
     "forme Unicode NFC, ordre canonique des diacritiques -- distinct de la "
     "canonicalisation shadda deja faite cote Dart par "
     "`normalizeTraining`, qui est une regex textuelle et non un "
     "reordonnancement Unicode) et cable `ChaineRecitation.variantesOrthographe` "
     "pour la choisir quand `moteur.riwayaWarsh == true`. Revue superviseur "
     "avant integration : (1) graphe interroge, aucun [MORT] sur ce point ; "
     "(2) plafond `Orthographe.MAX=10` (deja releve par le piege MAX=7 du "
     "2026-08-14) non depasse, +1 entree au pire ; (3) BUILD SUCCESSFUL ; "
     "(4) 20/20 tests JVM verts (ChaineRecitationTest x10, OrthographeTest "
     "x9, Tete3PariteTest x1), 0 echec, 0 erreur -- non-regression Hafs "
     "prouvee. RESERVE EXPLICITE : aucun test ne couvre `variantesWarsh` "
     "elle-meme, les 20 tests verts prouvent la non-regression, pas le gain "
     "Warsh -- a mesurer sur device avant de considerer le defaut resolu. "
     "Corrige AU PASSAGE un bug reel laisse par le cablage riwaya du meme "
     "jour : `tokenizer` (singleton lazy) n'etait jamais reinitialise par "
     "`setRiwaya()`, restant fige sur l'ancien vocabulaire apres une "
     "bascule."),
]

LIENS = [
    ("mesure_correctif_variantesWarsh_nfc_valide_par_superviseur",
     "mesure_warsh_mots_texte_identique_mais_rouges", "shares_data_with",
     "le correctif cible precisement le symptome mesure juste avant"),
    ("mesure_correctif_variantesWarsh_nfc_valide_par_superviseur",
     "mesure_wiring_natif_warsh_deux_vocabs_en_memoire_permanente", "shares_data_with",
     "construit sur le meme cablage riwayaWarsh du 2026-08-22"),
    ("mesure_warsh_mots_texte_identique_mais_rouges",
     "mesure_deux_moutures_du_22_seule_la_tete_tajwid_change", "shares_data_with",
     "meme modele, meme journee, deux facettes de la tete Warsh"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step38.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
