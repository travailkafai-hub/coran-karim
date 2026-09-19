#!/usr/bin/env python3
"""Consigne les mesures du 15 au 19 septembre 2026.

Quatre sujets, et chacun a produit un resultat NEGATIF qui vaut autant que les
positifs -- c'est precisement ce que le graphe existe pour retenir :
  - la graphie de LIAISON (shadda initiale) : seul vrai levier trouve ;
  - les PARTICULES : le deficit de detection est acoustique, pas decisionnel ;
  - le DEBIT : la degradation va dans le sens INVERSE de l'hypothese ;
  - la TOKENISATION : un mot lu parfaitement, rouge 14 fois sur 14.

`rationale` porte LA MESURE, jamais l'intention.
"""
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "graphify-out"
GRAPH = OUT / "graph.json"

NODES = [
    ("regle_shadda_initiale_liaison_20260917",
     "[REGLE] Shadda initiale = liaison, pas propriete du mot",
     "Un mot a shadda initiale etait faussement signale dans 28,6 % des cas "
     "(10/35) contre 7,0 % ailleurs (48/682) -- quatre fois plus. La shadda "
     "sur la PREMIERE lettre note un idgham avec le mot precedent ; le mot "
     "seul ne la porte pas. Variante sans shadda ajoutee : faux 8,1 % -> "
     "7,4 % au vote, detection inchangee a 68 %, et les 682 autres mots "
     "STRICTEMENT inchanges. Premiere lettre seulement : les shaddas internes "
     "sont des proprietes du mot, les retirer blanchirait la gemination."),

    ("mesure_variantes_liaison_finale_20260917",
     "[MESURE] Finale assimilee (idgham/ikhfa) : effet marginal",
     "Contexte d'idgham : 10,8 % de faux (18/166) contre 7,0 % sans regle. "
     "Correlation REELLE, mais la correction ne supprime qu'UN seul faux "
     "(7,4 % -> 7,3 %). Relecture des cas restants : ce n'est pas la finale, "
     "c'est la particule INITIALE qui manque (`لِلْمُتَّقِينَ` lu "
     "`ٱلْمُتَّقِينَ`). Les mots en contexte d'idgham sont longs et precedes "
     "d'une particule -- deux proprietes deja connues comme fautives."),

    ("piege_correlation_observations_vs_verdicts_20260917",
     "[PIEGE] Une correlation sur les OBSERVATIONS n'est pas un gain sur les VERDICTS",
     "Paye DEUX FOIS le meme jour. Idgham 10,8 % et conditions d'ecoute 69 % : "
     "deux correlations reelles, toutes deux deja neutralisees en aval par les "
     "exclusions du vote (fragment_alignement, lecture_non_complete). Seule la "
     "shadda initiale etait un levier -- parce que rien en aval ne la traitait. "
     "Verifier ce que les couches suivantes font DEJA avant d'implementer."),

    ("mort_marge_gauche_25_frames_20260917",
     "[MORT] Elargir la marge gauche a 25 frames (2 s de contexte)",
     "Sur 2 139 observations de mots CORRECTS, le taux de lecture erronee "
     "passe de 69,1 % (moins de 0,5 s de contexte a gauche) a 3,6 % (au-dela "
     "de 3 s) : le meme encodeur causal devine quand il n'a rien entendu "
     "avant. Mais a 25 frames : +2 detections (68 % -> 70 %) et +4 faux "
     "(7,3 % -> 7,8 %). Pas de gain net -- le vote FILTRAIT deja ces lectures. "
     "margeGaucheFrames reste a 2, balayable par -DmargeGauche=N."),

    ("regle_lecture_entiere_prime_20260916",
     "[REGLE] Une lecture entiere prime sur un mot ampute",
     "8 faux evites, 0 detection perdue. Ecarter TOUS les fragments donnait "
     "21 evites pour 16 detections perdues ; n'ecarter que les suffixes quand "
     "une lecture entiere existe donne 38 pour 9. Conditionne a l'existence "
     "de cette lecture entiere : sans elle le suffixe est la seule preuve."),

    ("mort_banc_coupures_insertions_20260916",
     "[MORT] Mesurer la chaine sur des mots coupes/inseres/omis",
     "L'ancien banc etait fait a 72 % de coupures, insertions et omissions. "
     "Critique utilisateur du 16/09 : aucun recitateur ne coupe un mot en "
     "plein milieu. Mesure qui lui donne raison : sur les seules "
     "substitutions, la detection passe de 66 % a 82 %. Le chiffre bas venait "
     "de la FABRICATION du test, pas de l'application."),

    ("mort_biais_canonique_sur_flexions_20260916",
     "[MORT] Craindre que le modele 'corrige' vers la forme canonique",
     "Sur les substitutions de flexion (`ٱلضَّالِّينَ` -> `ٱلضَّالُّونَ`), le "
     "modele entend la faute 100 % du temps (7/7). Le biais canonique "
     "documente depuis juillet ne joue PAS sur les flexions. Flexion interne "
     "83 % (15/18). Tout le deficit tient dans les particules."),

    ("mesure_deficit_particules_20260916",
     "[MESURE] Le deficit de detection est acoustique, pas decisionnel",
     "Particule ajoutee 52 % (16/31), particule retiree 67 % (16/24), contre "
     "100 % sur les flexions finales. Sur 87 lectures amputees de leur debut : "
     "`وَ` 14 fois, `فَ` 10, `بِ` 6 -- et 72 de ces 87 cas portent sur des "
     "mots CORRECTS. Ce n'est pas le recitateur qui les oublie, c'est le "
     "modele qui ne les produit pas. Verifie dans les logprobs : le `ث` de "
     "`ثَجَّاجًا` est au rang 24. Se traite a l'entrainement."),

    ("piege_tokenisation_fragmentee_20260918",
     "[PIEGE] Un mot parfaitement lu, rouge 14 fois sur 14",
     "`تُحِلُّوا۟` (5:2) juge rouge a CHAQUE tentative d'un entrainement par "
     "paliers, dont 13 fois avec entendu == attendu. Signature : free=-0,01 "
     "(decodage libre certain) mais forced=-4,32 sur le MEME texte. Cause : "
     "absent de word_tokens.json, donc repli glouton en 6 pieces dont une "
     "SHADDA ISOLEE, quand `ءَامَنُوا۟` tient en UNE piece et passe vert a "
     "gop=0,00. Aucun caractere perdu (0 ligne 'hors vocab'). Le dictionnaire "
     "ne couvre que 18 993 des 37 565 mots du Coran (49 % absents) et 14,8 % "
     "de ses entrees ne redonnent pas le mot."),

    ("mort_voyant_debit_eleve_20260919",
     "[MORT] Un voyant qui passe au rouge quand le debit MONTE",
     "Mesure sur 659 mots juges, debit local calcule sur les segments alignes "
     "(fenetre de 5 mots) : faux signalements 11,7 % sous 0,58 mots/s contre "
     "2,5 % au-dessus de 1,02 -- degradation MONOTONE mais dans le sens "
     "INVERSE de l'hypothese. Debit median des faux 0,64 mots/s contre 0,77 ; "
     "duree du mot 1,87 s contre 1,31 s. Controle du facteur confondu : hors "
     "fin de verset l'ecart tient (12,2 % contre 2,6 %). Aucun seuil de debit "
     "eleve n'existe dans les donnees."),

    ("mesure_duree_fenetres_reelles_20260919",
     "[MESURE] Les blocs envoyes au modele ne sont pas longs",
     "311 fenetres sur 27 sessions device : mediane 7,68 s, max 17,24 s, ZERO "
     "au-dela de 20 s -- l'app tourne avec maxBloc=10 s et maxFusion=18 s, pas "
     "les 30 s du document de calibrage. Ce qui est long est l'ATTENTE entre "
     "deux fenetres : mediane 1,46 s, p90 6,96 s, jusqu'a 20,5 s a l'interieur "
     "d'une meme recitation, puis les verdicts tombent par paquets (mediane 4 "
     "mots dans la meme seconde, jusqu'a 14)."),
]

LINKS = [
    ("regle_shadda_initiale_liaison_20260917",
     "piege_correlation_observations_vs_verdicts_20260917",
     "contraste_avec",
     "la shadda etait causale (seule difference dans les cas), l'idgham ne l'etait qu'en partie"),
    ("mesure_variantes_liaison_finale_20260917",
     "piege_correlation_observations_vs_verdicts_20260917",
     "illustre",
     "10,8 % de correlation pour UN seul faux supprime"),
    ("mort_marge_gauche_25_frames_20260917",
     "piege_correlation_observations_vs_verdicts_20260917",
     "illustre",
     "69 % d'erreurs de lecture sans contexte, et pourtant aucun gain net sur les verdicts"),
    ("mort_banc_coupures_insertions_20260916",
     "mesure_deficit_particules_20260916",
     "aboutit_a",
     "une fois les fautes artificielles retirees, le deficit restant est celui des particules"),
    ("mort_biais_canonique_sur_flexions_20260916",
     "mesure_deficit_particules_20260916",
     "confirme",
     "100 % sur les flexions : ce qui manque n'est pas la decision mais l'emission"),
    ("piege_tokenisation_fragmentee_20260918",
     "regle_lecture_entiere_prime_20260916",
     "distinct_de",
     "ici le texte entendu est COMPLET et exact ; c'est la decomposition qui echoue"),
    ("mort_voyant_debit_eleve_20260919",
     "mesure_duree_fenetres_reelles_20260919",
     "controle_par",
     "ni le debit ni la duree des blocs ne sortent le modele de sa zone mesuree"),
]


def git_head():
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                              capture_output=True, text=True,
                              timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    graph = json.loads(GRAPH.read_text(encoding="utf-8"))
    known = {node["id"] for node in graph["nodes"]}
    added_nodes = 0
    for node_id, label, rationale in NODES:
        if node_id in known:
            continue
        graph["nodes"].append({
            "label": label,
            "rationale": rationale,
            "node_type": "concept",
            "id": node_id,
            "community": 0,
            "norm_label": label.lower(),
        })
        known.add(node_id)
        added_nodes += 1

    existing = {(l.get("source"), l.get("target"), l.get("relation_type"))
                for l in graph["links"]}
    added_links = 0
    for source, target, relation, rationale in LINKS:
        key = (source, target, relation)
        if source not in known or target not in known or key in existing:
            continue
        graph["links"].append({
            "source": source,
            "target": target,
            "relation_type": relation,
            "source_location": "benchmark/FAUX_SIGNALEMENTS_GRAPHIE_DE_LIAISON_20260917.md",
            "rationale": rationale,
        })
        existing.add(key)
        added_links += 1

    shutil.copy2(GRAPH, OUT / "graph_avant_step58_liaison_tokenisation.json")
    graph["built_at_commit"] = git_head()
    GRAPH.write_text(json.dumps(graph, ensure_ascii=False), encoding="utf-8")
    print(f"+{added_nodes} noeuds, +{added_links} aretes -> "
          f"{len(graph['nodes'])} noeuds, {len(graph['links'])} aretes")


if __name__ == "__main__":
    main()
