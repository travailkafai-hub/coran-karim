#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le madd raccourci : capte par le gop, etiquete faute de lettres."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_le_gop_capte_le_madd_raccourci_et_l_etiquette_faux",
     "[MESURE] Le gop capte bien le madd raccourci -- il l'etiquetait « faute de prononciation »",
     "Deux mots d'Al-Masad DELIBEREMENT mal recites par l'utilisateur "
     "(2026-09-05, « je n'ai pas applique le madd en vrai ») : "
     "mot 5 `يَدَآ` definitif:rouge gop=-2,92 margeL=+2,57 entendu=\"يَدَآ\" ; "
     "mot 9 `مَآ` definitif:rouge gop=-2,84 margeL=+9,97 entendu=\"مَآ\". "
     "Transcrit PARFAIT dans les deux cas, et marge de lettres franchement "
     "POSITIVE -- l'audio prefere ce mot-ci a chacune de ses confusions. Le gop "
     "bas ne vient donc pas des lettres : le chemin contraint doit etaler une "
     "cible qui porte l'allongement sur un audio qui ne le tient pas. "
     "CE QUE CA ETABLIT, et qui n'etait pas su : le gop DETECTE le madd "
     "raccourci, correctement ; il le range simplement sous la mauvaise "
     "etiquette. Le controle tajwid, lui, ne les voyait pas -- il n'entre que "
     "si `statutBase == correct`, et un mot deja rouge n'y passe jamais."),

    ("regle_requalifier_un_madd_raccourci_en_faute_de_tajwid",
     "[REGLE] Un madd raccourci se requalifie en faute de TAJWID (violet), sous trois conditions",
     "Demande utilisateur du 2026-09-05 : « je veux que tu bascules la "
     "detection de ce madd dans regle de tajwid, ce qui va renforcer la regle "
     "de tajwid ». CE N'EST PAS UNE TOLERANCE : le mot reste non-vert, il "
     "change d'ETIQUETTE et de couleur -- violet dit « ton allongement n'a pas "
     "ete tenu », vrai et actionnable ; rouge disait « ce mot est faux », ce "
     "qui ne l'etait pas. TROIS CONDITIONS, toutes necessaires : (1) le "
     "transcrit du mot est identique au mot attendu ; (2) `margeLettres >= 0` "
     "-- sans elle on requalifierait aussi les mots ou le modele ECRIT le "
     "canonique par biais de langage alors qu'autre chose a ete dit, le defaut "
     "meme que la marge existe pour attraper ; (3) le mot attend au moins une "
     "regle de MADD -- seule regle dont le raccourcissement degrade "
     "mecaniquement le chemin contraint."),

    ("regle_un_madd_non_juge_par_le_preset_ne_doit_pas_rougir",
     "[REGLE] En mode adulte, un madd raccourci devient VERT -- promotion bornee par cinq conditions",
     "Deduction de l'utilisateur, juste : « si je suis en mode adulte et que le "
     "madd est absent, ca devrait etre vert ». En adulte `_activeRules` est "
     "vide, donc la requalification en violet ne se declenche pas et le mot "
     "restait ROUGE : le meme audio donnait violet en tajwid et rouge en "
     "adulte -- le recitateur puni, dans le mode le plus permissif, pour une "
     "regle que ce mode ne juge pas. Cela contredisait mot pour mot la "
     "decision du 2026-08-16 (« le jugement de prononciation doit etre "
     "identique entre les presets ; le tajwid n'intervient qu'apres ») : "
     "`statutBase` etait contamine par le tajwid sans que rien ne le dise. "
     "⚠️ C'EST UNE PROMOTION AU VERT, et ce n'est PAS celle que le graphe "
     "porte en [EN ATTENTE] (promotion sur transcrit parfait) -- celle-la "
     "validait 22 mots `deplace` mesures. Les conditions 4 et 5 sont "
     "exactement ce qui l'en separe : (1) transcrit identique ; (2) "
     "margeLettres >= 0 ; (3) le mot porte un madd DANS LE TEXTE "
     "(`expectedRules`, sans filtre de preset -- propriete du Coran, pas d'un "
     "reglage) ; (4) AUCUN de ces madd n'est juge par le preset courant, ce "
     "qui borne la promotion a adulte/enfant ; (5) le statut n'est ni `omis` "
     "ni `deplace`. Journalisee systematiquement (`V2maddHorsPreset`) : une "
     "promotion muette rendrait invisible le defaut d'alignement qui l'a "
     "rendue necessaire."),

    ("mesure_madda_normal_manquait_au_groupe_des_madd",
     "[MESURE] `madda_normal` etait exclue du groupe des madd interchangeables -- un allongement FAIT ressortait en faute",
     "Cas releve par l'utilisateur le 2026-09-05, Al-Masad mot 12 `مَالُهُۥ` : "
     "attendues=madda_normal, detectees=madda_permissible,madda_obligatory. "
     "L'allongement A ETE FAIT -- deux detections franches -- et le mot "
     "ressortait quand meme en faute (« ta solution ne marche pas a 100 % »). "
     "`madda_normal` avait ete laissee hors du groupe au motif que le madd "
     "naturel fait 2 harakat contre 4 a 6 pour les trois autres, distinction "
     "donc supposee audible. C'EST FAUX, et pour une raison deja ecrite dans "
     "ce projet : `madda_permissible` se lit « 2 OU 4 OU 6 harakat, au choix "
     "du recitant » -- elle RECOUVRE entierement la duree du madd naturel. "
     "Exiger que la tete les separe, c'est lui demander de deviner une "
     "categorie grammaticale, pas d'entendre une duree. Les quatre `madda_*` "
     "sont donc desormais interchangeables. Ce que le groupe ne fait PAS : "
     "blanchir un allongement OMIS -- si aucune regle de madd n'est detectee, "
     "la regle reste manquante (cf. les mots 5 et 9 de la meme session)."),
]

LIENS = [
    ("regle_requalifier_un_madd_raccourci_en_faute_de_tajwid",
     "mesure_le_gop_capte_le_madd_raccourci_et_l_etiquette_faux",
     "shares_data_with", "la regle et la mesure qui l'a imposee"),
    ("regle_un_madd_non_juge_par_le_preset_ne_doit_pas_rougir",
     "regle_requalifier_un_madd_raccourci_en_faute_de_tajwid",
     "shares_data_with", "les deux moities du meme defaut, selon le preset"),
    ("regle_un_madd_non_juge_par_le_preset_ne_doit_pas_rougir",
     "en_attente_promotion_au_vert_bornee_par_la_marge",
     "shares_data_with",
     "une promotion au vert bornee, a ne pas confondre avec la generale"),
    ("mesure_madda_normal_manquait_au_groupe_des_madd",
     "mesure_le_gop_capte_le_madd_raccourci_et_l_etiquette_faux",
     "shares_data_with", "deux defauts de la meme session sur les madd"),
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
            print("  = deja present : " + nid)
            continue
        g["nodes"].append({
            "label": label, "rationale": rationale, "node_type": "concept",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print("  ! cible absente : " + s + " -> " + t)
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step46.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
