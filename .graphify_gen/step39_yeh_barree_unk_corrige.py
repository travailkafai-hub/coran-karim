#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le yeh barree tokenisait en <unk> dans word_tokens_warsh.json -- corrige localement."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_yeh_barree_tokenisait_en_unk",
     "[MESURE] `word_tokens_warsh.json` tokenisait le yeh barree en <unk> -- 525/540 mots touches",
     "Trouve par confrontation donnee/comportement : un test reel montrait "
     "`اُ۬لذِے`/`اَ۬لذِے` systematiquement rouge a travers 6 tours successifs, "
     "texte reconnu quasi identique a l'attendu. Decodage des tokens du "
     "dictionnaire livre : word_tokens_warsh.json['اُ۬لذِے'] = [49, 317, 0], "
     "et vocab_warsh.json[0] = '<unk>'. Cause : le dictionnaire a ete "
     "construit par tokenisation SentencePiece BRUTE du texte source, sans "
     "la normalisation yeh barree (U+06D2 -> ي) deja en place cote Dart "
     "pour l'affichage depuis le 2026-08-12. L'alignement force condamne "
     "alors tout mot avec ce caractere, independamment de la prononciation. "
     "Ampleur : 540/22928 mots contiennent la lettre, 525 (97,2 %) avaient "
     "un <unk> dans leur sequence de tokens."),

    ("mesure_correctif_yeh_barree_regenere_local",
     "[MESURE] Correctif applique localement : <unk> tombe de 525/540 a 5/540",
     "Fidelite verifiee AVANT toute modification : le tokenizer SentencePiece "
     "local (tokenizers/warsh.model, meme fichier que le paquet livre) "
     "reproduit exactement 200/200 entrees existantes sans yeh barree. "
     "Correctif : chaque cle contenant 'ے' est retokenisee via ce meme "
     "tokenizer apres avoir applique 'ے'->'ي' -- la cle elle-meme (ce que le "
     "natif cherche) reste inchangee, seule la sequence de tokens change. "
     "Cause traitee a sa source (le dictionnaire), pas de tolerance ajoutee "
     "en aval. Les 5 mots restants avec <unk> le sont pour une AUTRE lettre "
     "(hamza suscrite combinante U+0655, absente des 1024 pieces du "
     "vocabulaire) -- hors perimetre, 5/22928 mots, necessiterait que le "
     "vocabulaire lui-meme apprenne ce caractere (expertise machine "
     "d'entrainement), pas une simple retokenisation."),

    ("mesure_coupes_palier_ecart_mots_hafs_warsh_marginal",
     "[MESURE] L'ecart de nombre de mots Hafs/Warsh par verset est marginal (6/6236), pas les 44% que le comptage brut suggerait",
     "Verification avant de coder un correctif pour CoupesPalierService "
     "(asset indexe par surah:ayah, mesure sur Al-Afasy en Hafs, sans garde "
     "de longueur contrairement a RuleAnnotationService) : un premier "
     "comptage brut (`.split()`) donnait 2723/6236 versets differents en "
     "nombre de mots entre les deux textes -- alarmant. Refait avec un "
     "filtre approchant `ArabicNormalizer.splitExpectedWords` (retrait des "
     "marques de waqf isolees, sans lettre) : seulement 6/6236 versets "
     "(0,1 %) different reellement. L'ecart brut venait presque entierement "
     "du comptage different des marques de waqf, pas de vrais mots en plus "
     "ou en moins. DECISION : ne pas modifier le format de "
     "coupes_palier_afasy.json pour un risque aussi marginal -- le garde de "
     "bornes deja present (`i < dernier`) suffit en pratique."),
]

LIENS = [
    ("mesure_correctif_yeh_barree_regenere_local",
     "mesure_yeh_barree_tokenisait_en_unk", "shares_data_with",
     "le diagnostic et son correctif, meme fichier"),
    ("mesure_yeh_barree_tokenisait_en_unk",
     "piege_yeh_barree_lettre_pas_diacritique", "shares_data_with",
     "meme lettre, meme piege, deux couches differentes (affichage Dart vs tokens natifs)"),
    ("mesure_coupes_palier_ecart_mots_hafs_warsh_marginal",
     "mesure_warsh_mots_texte_identique_mais_rouges", "shares_data_with",
     "meme session de test, deux constats distincts"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step39.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
