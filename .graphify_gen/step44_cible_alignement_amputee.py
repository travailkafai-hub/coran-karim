#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""La cible d'alignement perdait des caracteres sur un mot sur sept."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_word_tokens_ampute_un_mot_sur_sept",
     "[MESURE] `word_tokens.json` perd des caracteres sur 2 806 mots (14,8 %) -- la cible d'alignement est amputee",
     "Cause de faux rouges sur des mots au TRANSCRIT PARFAIT, trouvee le "
     "2026-09-05 en remontant deux cas signales par l'utilisateur : `بِهِۦ` "
     "(un seul ecart, une maddah U+0653 que le modele AJOUTE) et `وَٱتَّقُوا۟` "
     "(zero ecart, onze codes Unicode identiques entre attendu et entendu). "
     "L'objection de l'utilisateur -- « il n'y avait pas de confusion dans le "
     "transcrit affiche » -- etait juste, et c'est elle qui a mene a la cause. "
     "MESURE sur le `word_tokens.json` du pack v7 : 2 806 mots sur 18 993 "
     "(14,8 %) ont une decomposition dont la concatenation NE REDONNE PAS le "
     "mot. Caracteres perdus : U+06DF (zero suscrit du `slnt`) sur 1 259 mots, "
     "U+0627 sur 948, U+0653 (maddah) sur 855, U+06E5/U+06E6 (petites waw et "
     "ya) sur 557, U+06E2 sur 101. Exemple exact : `بِهِۦ` -> cible `▁بِ + هِ`, "
     "la petite waw a disparu. Le chemin force doit alors produire un mot "
     "ampute la ou le modele ecrit le signe d'allongement : forced -8,54 "
     "pendant que le decodage libre est a -0,10."),

    ("regle_un_transcrit_identique_ne_prouve_pas_un_forced_correct",
     "[REGLE] Un transcrit identique a l'attendu ne prouve RIEN sur le score d'alignement force",
     "L'alignement force ne compare pas des TEXTES, il suit une DECOMPOSITION "
     "en pieces. Le decodage libre emet les pieces qu'il veut ; le force doit "
     "suivre celle que la cible impose. Deux decoupages du meme mot rendent le "
     "MEME texte affiche et des scores opposes -- chiffre deja note dans "
     "`AligneurForce` (mot `كَفَرُوا۟`) : modele emet la piece entiere + cible "
     "piece entiere -> 8 frames, gop 0,00 ; modele EPELLE + cible piece "
     "entiere -> 1 frame, gop -11,99. CONSEQUENCE POUR L'ANALYSE : devant un "
     "rouge dont `entendu` egale `attendu`, ne pas chercher une difference de "
     "texte (il n'y en a pas) mais regarder la decomposition imposee."),

    ("regle_ecarter_les_entrees_amputees_du_dictionnaire",
     "[REGLE] Ecarter une entree de dictionnaire amputee et laisser le greedy reprendre la main",
     "Correctif du 2026-09-05, dans `CtcTokenizer` -- point unique traverse "
     "par la v1 ET la v2. Au chargement, toute entree dont la recomposition ne "
     "redonne pas le mot est ECARTEE ; le repli glouton la retokenise. "
     "DEUX MESURES FAITES AVANT D'ECRIRE UNE LIGNE : (1) le greedy existant "
     "trouve une decomposition EXACTE pour 2 806 des 2 806 mots concernes -- "
     "100 %, aucun bloque par un vocabulaire insuffisant ; (2) le cout est "
     "NUL, le dictionnaire passe de 77 161 a 77 049 pieces au total, soit "
     "-0,1 % (la decomposition exacte est en moyenne plus courte). "
     "⚠️ A NE PAS CONFONDRE avec [MORT] « passer le texte a l'aligneur pour "
     "ouvrir toutes les ecritures » (2026-08-06, mesuree 0,68 % -> 7,46 % de "
     "mots non verts) : la-bas on LIBERAIT la DP, qui deplacait les frontieres "
     "de tous les mots ; ici on remplace UNE decomposition fausse par UNE "
     "decomposition exacte, la contrainte reste entiere."),

    ("mesure_la_marge_de_lettres_condamne_avant_le_gop",
     "[MESURE] La marge de lettres rend ROUGE avant tout examen du gop",
     "Releve dans `Decideur.couleur()` le 2026-09-05 : la premiere branche est "
     "`margeLettres < seuilMargeRouge -> ROUGE`, donc un mot peut etre "
     "condamne sans que son gop soit meme consulte. Cas mesure, mot 21 "
     "`وَٱتَّقُوا۟` : margeL = -0,91 (une confusion de LETTRE bat le mot "
     "attendu) tandis que margeH = +1,14 ; les seules confusions generees sur "
     "ce mot sont ت↔ط et ق↔ك, donc l'audio a prefere une variante qaf/kaf, "
     "paire notoirement proche. Ce n'est pas un bug : c'est le collateral deja "
     "chiffre dans la doc du Decideur (« les faux positifs des deux mecanismes "
     "s'additionnent, le collateral passe d'environ 2 % a ~4 % »), le prix de "
     "la detection que la marge apporte (30 % contre 9 % pour le gop, mesure "
     "du 2026-07-31). NON RESOLU, et a ne pas traiter en deplacant "
     "`seuilMargeRouge` -- ce serait deplacer un critere d'acceptation pour "
     "faire disparaitre un symptome."),
]

LIENS = [
    ("regle_ecarter_les_entrees_amputees_du_dictionnaire",
     "mesure_word_tokens_ampute_un_mot_sur_sept", "shares_data_with",
     "le correctif et la mesure qui l'a impose"),
    ("regle_un_transcrit_identique_ne_prouve_pas_un_forced_correct",
     "mesure_word_tokens_ampute_un_mot_sur_sept", "shares_data_with",
     "pourquoi le transcrit ne suffit pas a innocenter l'alignement"),
    ("mesure_la_marge_de_lettres_condamne_avant_le_gop",
     "mesure_word_tokens_ampute_un_mot_sur_sept", "shares_data_with",
     "deux causes distinctes derriere des rouges au transcrit parfait"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step44.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
