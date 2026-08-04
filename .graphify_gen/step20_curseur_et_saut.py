#!/usr/bin/env python3
"""Calibrage du curseur v2, regression du refus de saut, et lignee streaming.

Consigne les mesures des deux commits de retard (2026-08-01/02) :
balayage (pas, largeur), taux de rejugement, inversion de la pause 0,25,
la regression du refus de saut, et l'etat de la lignee streaming.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_curseur_2s_4s_gagne",
     "[MESURE] Curseur 2 s / 4 s : 2,03 % -> 1,69 % de mots non verts",
     "Balayage JVM de 13 configurations (pas, largeur) sur le banc BancFluxBrut, "
     "modele final-v1. La configuration historique 3 s / 9 s donnait 2,03 % de "
     "mots non verts ; 2 s / 4 s donne 1,69 %. La latence jusqu'au verdict "
     "DEFINITIF passe de ~9,3 s a ~4,3 s. "
     "Contre-intuitif et c'est le point : RETRECIR la fenetre (9 s -> 4 s) "
     "AMELIORE le taux au lieu de le degrader. Une fenetre large noie le mot "
     "cherche -- deja vu au 2e buffer, ou les fenetres de 9-15 s echouaient "
     "toutes (15/15 SANS GAIN) quand les etroites de 5,8-8,4 s rattrapaient "
     "tout (15/15). Meme cause, deux couches differentes. "
     "DEPLOYE dans FastConformerCtcPlugin.kt : apercuSecondes = 2.0, "
     "fenetreApercuSecondes = 4.0."),

    ("mesure_rejugement_59pct_inutile",
     "[MESURE] 58,9 % des observations ne changent aucun verdict",
     "Instrumentation du rejugement dans BancFluxBrut (compteurs RECOUVREMENT / "
     "REJUGEMENT). Avec un pas de 2 s et une fenetre de 6 s, chaque instant "
     "d'audio est retranscrit 3 fois ; 58,9 % des observations portent sur des "
     "mots DEJA definitifs et ne peuvent donc rien changer (contrat de "
     "monotonie : un verdict Definitif ne se rejuge jamais). "
     "C'est du calcul pur perdu, et c'est l'argument chiffre en faveur du "
     "streaming a etat : le cache-aware supprime ce recouvrement par "
     "construction. Passer a 2 s / 4 s ramene deja le rejugement a 2 passes."),

    ("mesure_pause_025_gagne_avec_final_v1",
     "[MESURE] Pause mini 0,25 s : -0,67 pt -- l'ancien verdict est INVERSE",
     "Le code portait un commentaire « NE PAS RETENTER 0,25 » herite d'une "
     "mesure sur un modele anterieur. Remesure sur DEUX modeles : "
     "v4-phrases 5,08 % -> 4,41 % (-0,67 pt), final-v1 3,05 % -> 2,37 % "
     "(-0,68 pt). 0,25 GAGNE dans les deux cas. "
     "Le commentaire d'origine est CONSERVE (regle projet) avec une note "
     "expliquant l'inversion. Lecon de methode : une mesure « ne pas "
     "retenter » est liee au modele sur lequel elle a ete faite -- exactement "
     "l'avertissement des mesures pre-causal. Erreur reelle : l'agent a cite "
     "le commentaire comme s'il faisait autorite, c'est l'utilisateur qui a "
     "produit la remesure."),

    ("piege_refus_de_saut_jette_les_mots_attestes",
     "[PIEGE] Refuser un saut d'ancre jette des mots ATTESTES",
     "Regression introduite puis corrigee le 2026-08-01. Un garde refusait de "
     "juger une bande quand l'ecart entre le dernier mot definitif et les mots "
     "attestes depassait sautMaxMots. Mesure sur session device : 26 "
     "SAUT REFUSE, ancre bloquee (17->21->25->36->48 avec 16 refus "
     "consecutifs), 40 mots attestes jetes, et des verdicts « omis » sur des "
     "mots REELLEMENT prononces -- l'utilisateur l'a signale sur "
     "fasatubsiru/fayubsiruna, attendu jaune, obtenu omis. "
     "CAUSE : le graphe portait deja l'information -- un mot non atteste peut "
     "avoir son audio dans le bloc. Refuser la bande entiere pour proteger "
     "l'ancre detruit la preuve au lieu de la questionner. "
     "CORRECTIF : le signal de decrochage remonte, mais la bande est JUGEE "
     "quand meme (suppression du `return`). Banc revalide a 1,69 %, "
     "inchange."),

    ("regle_signaler_sans_jeter_la_preuve",
     "[REGLE] Un signal ne doit jamais consommer la preuve qu'il signale",
     "Generalisation du piege du refus de saut. Quand une couche detecte une "
     "anomalie (decrochage, saut, incoherence), elle doit REMONTER le signal "
     "et laisser la couche de jugement faire son travail sur les donnees "
     "disponibles. Interrompre le traitement (`return`) fait disparaitre des "
     "preuves acoustiques qui existaient -- et un mot dont l'audio est jete ne "
     "pourra JAMAIS etre juge, a aucune couche (socle du superviseur, "
     "niveau 2 SUIVRE). "
     "Classe de bugs supprimee : tous les « l'ancre s'est bloquee et des mots "
     "sont passes en omis sans avoir ete ecoutes »."),

    ("mesure_lignee_streaming_v1_v2",
     "[MESURE] Fine-tunes streaming : val_wer_ctc 0,186 (v1) et 0,183 (v2)",
     "Trois runs de fine-tune pour le regime streaming, distincts de l'export "
     "cache-aware de final-v1 (qui n'est que le MEME modele exporte autrement, "
     "lookahead inchange a 1,04 s). "
     "stream-v1 : 0,186 (13 checkpoints). stream-v2 : 0,183 (68 checkpoints). "
     "stream-v3 : entraine sur TROIS contextes simultanes 70,13 / 70,6 / 70,1, "
     "repart des poids de v2. "
     "L'enjeu est le contexte 70,1 : il ferait tomber le lookahead de 1,04 s a "
     "0,08 s. Mais 0,183 est une moyenne SUR LES TROIS CONTEXTES MELANGES -- "
     "le WER du contexte court seul n'est pas mesure, et c'est lui qui decide "
     "de tout. A evaluer par contexte avant tout portage Kotlin."),

    ("mesure_gain_streaming_reduit_depuis_2s_4s",
     "[MESURE] Le streaming a etat ne vaut plus que ~1,3 s depuis 2 s / 4 s",
     "Decomposition de l'attente jusqu'au verdict definitif. "
     "AUJOURD'HUI (2 s / 4 s, lookahead 1,04 s) : 1,04 + ~1,0 (attente "
     "fenetre) + ~0,3 (inference) + 2,0 (2e observation, k=2) = ~4,3 s. "
     "STREAMING A ETAT SEUL (shift 1,12 s, lookahead INCHANGE) : 1,04 + 0,56 + "
     "0,3 + 1,12 = ~3,0 s, soit ~1,3 s de gain. "
     "STREAMING + CONTEXTE 70,1 : 0,08 + 0,56 + 0,3 + 1,12 = ~2,1 s. "
     "CONSEQUENCE : ~1 s des ~2,2 s de gain total vient du FINE-TUNE (contexte "
     "reduit), pas du streaming a etat. Deux leviers distincts a ne pas "
     "confondre. La piste streaming avait ete prise quand on etait a 3 s / 9 s "
     "et que l'attente valait ~9,3 s ; le passage a 2 s / 4 s a deja pris la "
     "moitie du chemin, gratuitement. Le k=2 du Decideur reste incompressible "
     "dans tous les scenarios."),

    ("piege_deux_agents_un_seul_telephone",
     "[PIEGE] Deux agents deployant sur le meme device s'ecrasent en silence",
     "Constate le 2026-08-02. Le dossier device "
     "files/models/fastconformer-ctc-causal-v1/ ne contient plus que "
     "model_streaming.onnx : le `model.onnx` du chemin bufferise a DISPARU, "
     "alors que fastconformer_verifier.dart tourne avec "
     "_kCausalStreamingEnabled = false et cherche donc model.onnx. "
     "Le binaire installe porte le tag v17-sans-plafond, qui n'est pas celui "
     "de la branche tete3-ecart-canonique. Le log de diagnostic a ete remis a "
     "zero, effacant la session du matin. "
     "Le nom de dossier est IDENTIQUE pour les deux exports -- rien dans le "
     "chemin ne dit lequel est en place. C'est la meme classe de piege que "
     "`models/fastconformer-ctc-mixed-e02` contenant en realite l'epoch 14. "
     "CONSEQUENCE : toute mesure prise sur un telephone partage est "
     "inattribuable sans verifier, AVANT la passe, le tag de build ET la liste "
     "des fichiers du dossier modele."),
]

LIENS = [
    ("mesure_curseur_2s_4s_gagne", "mesure_rejugement_59pct_inutile",
     "explique", "moins de recouvrement = moins de calcul perdu"),
    ("mesure_gain_streaming_reduit_depuis_2s_4s", "mesure_curseur_2s_4s_gagne",
     "decoule_de", "le gain deja pris par le curseur reduit celui du streaming"),
    ("mesure_gain_streaming_reduit_depuis_2s_4s", "mesure_lignee_streaming_v1_v2",
     "conditionne", "le gain reel depend du WER du contexte court, non mesure"),
    ("regle_signaler_sans_jeter_la_preuve",
     "piege_refus_de_saut_jette_les_mots_attestes", "decoule_de", None),
    ("piege_deux_agents_un_seul_telephone", "mesure_curseur_2s_4s_gagne",
     "menace", "une mesure device n'est plus attribuable a une configuration"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step20.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
