#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le chiffre du banc v180 avec le modele du 22 aout, et ce qu il ne dit pas."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_banc_v180_non_verts_1_7pct",
     "[MESURE] Modele du 22 : 1,7 % de non-verts au banc, contre 23,7 % la veille",
     "Banc a un telephone, Al-Baqara 1-20, Al-Afasy studio rejoue en WAV (pas "
     "de micro, donc tout non-vert est un faux positif). 227 mots juges, ancre "
     "max 229, 2 non juges. Non-verts a la regle du banc (identique a la mesure "
     "du 21) : 4/229 = 1,7 %, contre 23,7 % (45/190) avec le modele du 21. A la "
     "regle stricte du skill d'analyse (tout `provisoire` = jamais verrouille) : "
     "11/229 = 4,8 %. Statuts : definitif:vert 218, provisoire:vert 7, "
     "provisoire:orange 2. RESERVE QUI INTERDIT D'ATTRIBUER TOUT LE GAIN AU "
     "MODELE : trois variables ont change en meme temps -- le modele (21 -> 22), "
     "le code (v178 -> v180) et l'APPAREIL (Samsung -> Xiaomi). Sur un WAV "
     "rejoue sans micro l'appareil ne devrait pas peser, mais ce n'est pas "
     "mesure."),

    ("mesure_v180_les_fragments_ont_quasi_disparu",
     "[MESURE] Les FRAGMENTS, premier poste de faux positifs du modele du 21, ont quasi disparu",
     "Le 21 aout, la decomposition des 509 non-verts donnait 22,4 % de "
     "FRAGMENTS (un mot ne recevant qu'une ou deux trames) et concluait que "
     "c'etait le plus gros levier, insensible a tout recalibrage de seuil. Sur "
     "le banc v180 avec le modele du 22 : 210 des 218 mots verts (96,3 %) ont un "
     "squelette entendu EXACTEMENT egal a l'attendu, et il ne reste que 2 "
     "fragments valides verts (0,9 %). Le gain de taux n'est donc PAS obtenu en "
     "relachant les criteres -- controle fait avant d'annoncer le chiffre, "
     "conformement au superviseur."),

    ("piege_vert_accorde_a_un_fragment_malgre_un_gop_tres_negatif",
     "[PIEGE] Un mot valide vert avec gop=-10,66, tres au-dela du seuil correct=-0,45",
     "Banc v180 : mot 166, attendu `istawqada`, entendu `qad` (4 trames), "
     "gop=-10,66 -- et statut `definitif:vert`. Le seuil `correct` vaut -0,45 : "
     "la decision ne vient donc PAS du seul gop, d'autres criteres (margeL, "
     "margeH, obs) l'emportent. C'est exactement ce que l'application existe "
     "pour detecter : un recitateur qui ne dit qu'un tiers du mot est valide. "
     "Deuxieme cas plus benin le meme jour : mot 24, `qablika` -> `qabli` "
     "(gop=-0,49), le pronom manquant passe. A INSTRUIRE avant de considerer le "
     "socle \"dire vrai\" comme intact -- deux cas sur 218 verts, mais sur la "
     "fonction premiere de l'app."),
]

LIENS = [
    ("mesure_banc_v180_non_verts_1_7pct",
     "mesure_modele_22aout_change_l_encodeur", "shares_data_with",
     "le meme modele, mesure hors telephone puis sur l appareil"),
    ("mesure_v180_les_fragments_ont_quasi_disparu",
     "mesure_46pct_des_non_verts_ne_sont_pas_des_fautes", "shares_data_with",
     "la categorie designee comme premier levier le 21, remesuree le 22"),
    ("piege_vert_accorde_a_un_fragment_malgre_un_gop_tres_negatif",
     "mesure_banc_v180_non_verts_1_7pct", "shares_data_with",
     "la reserve qui accompagne le chiffre : un taux bas ne prouve pas dire-vrai"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step36.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
