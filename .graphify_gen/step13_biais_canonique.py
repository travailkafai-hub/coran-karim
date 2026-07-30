#!/usr/bin/env python3
"""Le biais canonique : sa cause dans les donnees, et ce qui ne le corrige pas.

Meme principe : on enrichit, on n'ecrase pas, le `rationale` porte le chiffre.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_biais_canonique_contexte",
     "[PIEGE] Le modele CORRIGE la faute des qu'il a le contexte de la phrase",
     "MESURE sur la voix de l'utilisateur, qui a prononce ZAZAQNAHOUM au lieu de "
     "RAZAQNAHOUM : fenetre etroite (2 s) -> le modele ecrit le ZA reellement "
     "dit ; fenetre large (7,5 s) -> il ecrit la forme CANONIQUE. Verifie "
     "ensuite sur 12 modeles sur 12 : en fenetre large, TOUS ecrivent le "
     "canonique. Ce n'est pas un defaut du modele deploye, c'est une propriete "
     "de leur entrainement commun. Consequence directe pour la chaine v2, qui "
     "juge sur des blocs de 5 a 15 s : elle juge en plein dans le regime "
     "biaise, et une vraie faute y passe au VERT."),
    ("piege_contre_exemples_mots_isoles",
     "[PIEGE] Les contre-exemples a fautes sont TOUS des mots isoles",
     "CAUSE RACINE du biais canonique, trouvee dans le manifeste "
     "`nemo_manifests_dual` (156 892 exemples). Les 81 380 clips a fautes "
     "deliberees sont correctement etiquetes (texte PRONONCE, jamais le "
     "canonique -- verifie 81 380 sur 81 380). Mais : duree mediane 1,71 s et "
     "**1 mot par clip, maximum 1**, contre 10,40 s et 9 mots pour le Coran "
     "recite. Le modele n'a donc JAMAIS vu une PHRASE contenant une faute. Il a "
     "appris deux regimes disjoints : court = fidele, long = corrige. "
     "Ce qui manque n'est pas la faute, c'est son CONTEXTE."),
    ("mort_montage_audio_splice",
     "[MORT] Montage audio d'une lettre confusable (splice)",
     "MESURE QUI LA TUE (2026-07-30, premiere execution de "
     "build_confusable_splice_augmentation.py, ecrit le 2026-07-14 et jamais "
     "lance) : le segment remplace fait UNE SEULE FRAME (80 ms), parce que "
     "l'alignement CTC est peaky -- il marque la frame ou la lettre culmine, pas "
     "l'ETENDUE acoustique du phoneme. Sur le fichier monte (س -> ص), le modele "
     "lit la lettre D'ORIGINE en fenetre etroite comme en fenetre large. "
     "L'outil etiquetterait donc ص un son qui reste س : entrainer la-dessus "
     "apprendrait l'INVERSE de ce qu'on veut. A rouvrir seulement s'il remplace "
     "l'etendue reelle du phoneme, pas la frame de pic."),
    ("mesure_modeles_detection_vs_faux_positifs",
     "[MESURE] Le meilleur transcripteur est le pire juge",
     "A decoupage identique, flux brut de reference. Faux positifs / detection "
     "(fautes injectees 1 mot sur 5) / collateral : causal-v1 DEPLOYE 2,03 % / "
     "100 % / 2,44 % | tajweed-v2_059 12,93 % / 100 % / 12,65 % | pcd_ACTUEL_v1 "
     "12,59 % / 95,9 % / 11,43 % | mixed-e02 9,18 % / 100 % / 13,06 %. Les "
     "concurrents transcrivent mieux (4,05 % d'erreur mot contre 7,77 %) mais "
     "signalent 12 a 13 % de mots CORRECTS. Le modele deploye reste le bon choix "
     "pour JUGER -- c'est la mesure, pas une preference."),
    ("mesure_trois_familles_architecture",
     "[MESURE] Le nom d'un modele ne dit pas son architecture",
     "Verifie en listant les parametres des CHECKPOINTS, pas en lisant les "
     "exports. Trois familles : (1) tete tajwid separee, 19 classes -- les 5 "
     "`deploy/*dual-head*` et `causal-stageb` ; (2) regles en SYMBOLES dans le "
     "vocabulaire, 40 pieces en zone privee Unicode -- `rules-260h_stage1b` et "
     "`rules-260h_piste3`, qui sont les PIRES de tous (67 % d'erreur mot, ce que "
     "la mesure d'origine annoncait : « les regles volaient ~20 % de masse aux "
     "lettres ») ; (3) aucune -- pcd, mixed-e02, tajweed-augmented, "
     "tajweed-epoch09, tajweed-v2, causal-v1. `tajweed-epoch09` et `tajweed-v2` "
     "s'appellent ainsi parce qu'ils ont ete entraines sur du texte ANNOTE, pas "
     "parce qu'ils ont une tete : leur ctc_decoder sort 1025 classes et aucun "
     "parametre ne contient `tajwid`."),
    ("attente_causal_v3_silence",
     "[EN ATTENTE] causal-v3, abandonne alors qu'il etait MEILLEUR",
     "val_wer_ctc 0,180 des l'epoch 0, contre 0,183 apres 18 epochs pour le run "
     "deploye (causal-v1-lr3e4). Abandonne le 2026-07-26 pour « silence hors "
     "distribution » -- un probleme de donnees, pas de qualite (le dossier "
     "s'appelle fastconformer-streaming-causal-v3-ABANDONNE-silence-hors-"
     "distribution). A rouvrir si l'on relance un cycle d'entrainement."),
    ("regle_cahier_des_charges_deux_tetes",
     "[REGLE] Deux tetes, deux roles : juger sans biais, signaler le tajwid absent",
     "Cahier des charges fixe par l'utilisateur le 2026-07-30 : « le modele doit "
     "etre juste pour transcrire et valider SANS ETRE BIAISE ; quand il y a une "
     "faute il la fait savoir, sinon pas d'utilite. Et la tete tajwid c'est "
     "OPTIONNEL, quand c'est active, juste pour preciser les mots ou le tajwid "
     "est absent. » Corollaire : la tete tajwid ne verra JAMAIS un ز a la place "
     "d'un ر -- c'est une lettre, pas une regle. Trois erreurs, trois "
     "mecanismes : lettre -> fenetre etroite et modele non biaise ; harakat -> "
     "GOP, faiblement ; regle -> tete tajwid."),
    ("attente_tts_phrases_fautees",
     "[EN ATTENTE] Regenerer les contre-exemples en PHRASES, par TTS",
     "La voie praticable pour corriger le biais canonique, puisque le montage "
     "audio est mort (cf. mort_montage_audio_splice). Les 18 195 fautes "
     "existent deja et sont bien etiquetees (9 723 harakat, 8 472 lettres, avec "
     "`kind` et `detail` du type « ه->ح ») ; il manque leur CONTEXTE. L'outil qui "
     "les a produites, `generate_tts_augmentation.py`, fait du XTTS-v2 avec "
     "CLONAGE VOCAL sur de vrais recitateurs du corpus : il peut donc "
     "synthetiser des versets entiers dont un mot est faute. Non mesure -- le "
     "cout de generation reste a estimer."),
]

LIENS = [
    ("piege_contre_exemples_mots_isoles", "piege_biais_canonique_contexte",
     "cause", "c'est POURQUOI le modele corrige en contexte long"),
    ("piege_biais_canonique_contexte", "couche_v2_b_fenetres", "limite",
     "la v2 juge sur des blocs longs, donc en plein dans le regime biaise"),
    ("piege_biais_canonique_contexte", "piege_gop_relatif", "aggrave",
     "le gop est calcule sur des logprobs deja corriges"),
    ("mort_montage_audio_splice", "piege_contre_exemples_mots_isoles", "ne_corrige_pas",
     "la piste evidente pour donner du contexte aux fautes, et elle est morte"),
    ("attente_tts_phrases_fautees", "piege_contre_exemples_mots_isoles", "traite",
     "la seule voie restante identifiee"),
    ("mesure_modeles_detection_vs_faux_positifs", "mesure_detection_fautes_v2",
     "complete", "la meme mesure, etendue a tous les modeles"),
    ("regle_cahier_des_charges_deux_tetes", "couche_v2_g_decision", "s_applique_a", None),
    ("attente_causal_v3_silence", "regle_cahier_des_charges_deux_tetes", "point_de_depart",
     "meilleur checkpoint disponible pour repartir"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step13.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
