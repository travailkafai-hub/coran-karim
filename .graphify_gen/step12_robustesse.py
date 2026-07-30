#!/usr/bin/env python3
"""Robustesse au niveau de voix, detection des fautes, et un banc qui diverge.

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
    ("mesure_seuil_adaptatif",
     "[MESURE] Un seuil de silence ABSOLU ne peut pas marcher",
     "Meme recitation, seul le GAIN change (ce que fait une voix plus douce ou "
     "un micro plus loin). AVANT (seuil fixe 0,03) : x0,4 -> 15,93 % de mots "
     "non verts | x0,7 -> 5,08 % | x1,0 -> 2,03 % | x1,5 -> 65,76 % | x2,5 -> "
     "73,22 %. +50 % de volume et la chaine s'effondre. APRES (seuil = 0,344 x "
     "percentile 75 des RMS de bloc, fenetre glissante de 30 s) : 2,03 % A TOUS "
     "LES GAINS, 91 blocs a chaque fois. La valeur 0,344 est DERIVEE (c'est le "
     "rapport qui reproduit le seuil valide), pas reglee. Un percentile fixe "
     "supposerait que la PROPORTION de silence est la meme chez tous les "
     "recitateurs ; le contraste parole/silence, lui, est une propriete de la "
     "voix et du micro."),
    ("mesure_micro_redmi_4x_plus_bas",
     "[MESURE] Deux telephones ne captent pas au meme niveau (4,6x)",
     "Roles permutes, meme recitation : p75 des RMS de bloc = 0,0871 sur le "
     "micro du Samsung, 0,0189 sur celui du Redmi -- 4,6x plus bas. Avec un "
     "seuil fixe a 0,03, 95,7 % des blocs du Redmi comptaient comme du SILENCE "
     "(contre 18,4 % cote Samsung). Un reglage de seuil valide sur un telephone "
     "n'a aucune raison de tenir sur un autre."),
    ("mesure_detection_fautes_v2",
     "[MESURE] La v2 detecte 100 % des fautes injectees, sans collateral",
     "Banc de detection (on fausse un mot ATTENDU sur N, sur le meme audio) : "
     "lettres confusables 1 sur 5 -> 49/49 = 100 %, collateral 2,44 % ; HARAKAT "
     "1 sur 5 -> 58/58 = 100 %, collateral 1,69 % ; 1 mot sur 3 -> 80/80 = "
     "100 %, collateral 5,14 % (73,27 % avant le seuil adaptatif). Les deux "
     "chiffres se lisent ENSEMBLE : une detection de 100 % obtenue en signalant "
     "tout le monde ne vaudrait rien."),
    ("piege_attestation_normalisee_blanchit",
     "[PIEGE] L'appariement normalise ne vaut pas preuve de justesse",
     "TROUVE PAR L'UTILISATEUR EN SE SERVANT DE L'APP : « j'ai fait des fautes "
     "deliberees, il les colorie [vert] alors que le texte entendu en bas "
     "montre bien que j'ai mal dit le mot ». Pour LOCALISER on compare les mots "
     "sans harakat (peu fiables pour retrouver une position) -- mais ce meme "
     "appariement servait de PREUVE que le mot est juste. Deux mots ne "
     "differant que par une harakat s'y confondaient, et la regle « atteste + "
     "vert => definitif » verrouillait un vert sur UNE observation. "
     "Normaliser pour TROUVER, comparer exactement pour CONFIRMER. "
     "Cout du durcissement : nul (2,03 % avant comme apres)."),
    ("sympt_blocs_de_mots_omis",
     "[SYMPTOME] Blocs de mots CONSECUTIFS declares omis",
     "Se VOIT comme des trous dans la coloration (150-156 et 201-205 sur le "
     "Redmi, 68-75 sur Yusuf). NAIT dans la couche de LOCALISATION : la bande "
     "va du PREMIER au DERNIER mot atteste, donc un mot que le decodage libre "
     "ne nomme pas n'entre pas dans la bande MEME SI SON AUDIO EST DANS LE "
     "BLOC. Signature : `bord/sansCreneau`, `entendu=\"\"`, `free` entre -0,01 "
     "et -0,22 -- le modele est CERTAIN, le mot n'etait juste pas demande. "
     "Correctif tente (extension de la bande vers l'arriere sur les frames "
     "libres) : NE TRANCHE PAS, 12,88 % contre 8,14 % avec des blocs qui se "
     "DEPLACENT, sur un protocole dont la variance est de 0 a 10,9 %."),
    ("piege_banc_diverge_du_device",
     "[PIEGE] Le banc a cesse de reproduire le device, et on ne sait pas pourquoi",
     "Sur le flux brut capte par le Redmi, le BANC donne 32-37 % de mots non "
     "verts la ou le DEVICE en donne 8-13 % -- sur le meme audio et le meme "
     "code. Verifie et ECARTE : en-tete WAV (44 octets des deux cotes), cible "
     "(295/295 mots presents dans le dictionnaire mot->tokens), niveau du "
     "signal (mesure, 4,6x plus bas mais coherent). Cause inconnue au "
     "2026-07-30. TANT QUE CE N'EST PAS RESOLU, optimiser sur ce banc revient a "
     "optimiser un banc qui ment -- c'est la lecon deja payee deux jours de "
     "suite sur ce projet."),
    ("piege_clips_perdus_avec_v1",
     "[PIEGE] Couper la v1 fait disparaitre la capture des clips",
     "La capture des clips audio par mot etait portee par BufferedTranscriber. "
     "Une session ou la v2 pilote ecrit donc 0 clip. Le flux BRUT reste ecrit "
     "(c'est lui qui sert de banc), mais la correspondance clip<->mots est "
     "perdue -- or c'est elle qui permettait de reecouter un mot signale. "
     "A reimplementer cote v2 avant de considerer la v1 retirable."),
]

LIENS = [
    ("mesure_seuil_adaptatif", "couche_v2_b_fenetres", "mesure", None),
    ("mesure_micro_redmi_4x_plus_bas", "mesure_seuil_adaptatif", "motive",
     "c'est ce qui a rendu le seuil adaptatif urgent"),
    ("piege_attestation_normalisee_blanchit", "regle_deux_mesures_independantes",
     "corrige", "l'attestation qui verrouille doit etre EXACTE"),
    ("piege_attestation_normalisee_blanchit", "couche_v2_g_decision", "nait_dans", None),
    ("mesure_detection_fautes_v2", "couche_v2_g_decision", "mesure", None),
    ("sympt_blocs_de_mots_omis", "couche_v2_d_localisation", "nait_dans", None),
    ("piege_banc_diverge_du_device", "regle_banc_appelle_le_code", "limite",
     "la regle ne suffit pas si le banc et le device divergent sans explication"),
    ("piege_clips_perdus_avec_v1", "piege_35pct_audio_absent", "rappelle",
     "meme famille : une preuve acoustique qui cesse d'etre ecrite"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step12.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
