#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Soiree du 2026-09-11 : le pic du CTC pris pour une duree, une troisieme
fois -- et les seuils tajwid reposes sur une mesure a cinq recitateurs."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_bornes_de_mots_sont_des_pics_ctc",
     "[MESURE] Les bornes de mots de l'aligneur sont des PICS d'emission CTC, pas l'etendue du son -- 51 a 74 % d'un verset compte a tort comme du silence",
     "Verset 2:6, cache de decoupe du device (files/decoupes/7-2-6.json), "
     "duree = fin - debut de chaque mot telle que l'aligneur la rend : "
     "mot 0 « إن » 80 ms, mot 1 « الذين » 0 ms, mot 2 80 ms, mot 4 80 ms, "
     "mot 9 80 ms. Un mot recite ne dure jamais 80 ms et encore moins 0 : "
     "le CTC est peaky, il marque le token sur une ou deux frames puis emet "
     "du blank. Les seuls mots « longs » (1680 ms) sont ceux a plusieurs "
     "pieces, donc a plusieurs pics espaces. "
     "CONSEQUENCE CHIFFREE : somme des durees de mots = 5 200 ms sur "
     "10 560 ms de verset, soit 51 % du temps attribue a des mots et 49 % "
     "compte comme du silence. Sur 2:4 c'est pire : 3 520 ms sur 13 280, "
     "soit 74 % de faux silence, et 10 coupes sur 11 trous possibles. "
     "C'est la TROISIEME fois que cette grandeur est prise pour une duree : "
     "2026-09-03 sur les seuils tajwid (« impossible un madd obligatoire en "
     "80 ms !! »), 2026-09-05 sur leur neutralisation, 2026-09-11 ici sur "
     "les paliers. Le chiffre 80 ms revient a chaque fois -- c'est une "
     "frame, pas une duree."),

    ("regle_les_coupes_de_palier_viennent_du_texte",
     "[REGLE] Les coupes de palier viennent du TEXTE ; la voix ne cree aucune coupe, elle dit seulement OU tombe le mot dans l'audio",
     "Directive utilisateur (2026-09-11) : « les paliers c'est exactement ce "
     "qu'on a prevu, il faut juste decouper l'audio selon ce texte ». "
     "PREUVE PAR CONTRASTE, dans un seul journal : 3:4 (18 mots) donnait "
     "3 paliers corrects de 4/10/4 -- et c'est precisement le verset ou la "
     "decoupe audio avait ECHOUE (NOT_LOADED), donc ou le texte avait pris "
     "le relais. 2:6 (11 mots) donnait 9 paliers d'un mot -- c'est celui ou "
     "elle avait REUSSI. Le verset qui marche est celui ou l'audio ne decide "
     "rien. "
     "Les deux sources precalculees sont d'accord sur 2:6 : coupes_paliers."
     "json (waqf, 6 236 versets) et coupes_palier_afasy.json (energie "
     "mesuree hors ligne) donnent [5] toutes les deux ; seule la mesure en "
     "direct divergeait avec 8 coupes. "
     "Les bornes en ms restent utilisees pour JOUER le bon extrait -- ce qui "
     "disparait est leur droit de creer une coupe. `_coupesMesurees` est "
     "conserve et journalise, a rebrancher le jour ou l'aligneur rendra une "
     "etendue."),

    ("piege_forcer_un_preset_par_sa_constante_nue",
     "[PIEGE] Forcer JudgementOptions.tajwidDefault vide les regles au lieu de les imposer -- preset=tajwid, regles=aucune",
     "Introduit puis corrige le 2026-09-11. Le mode tajwid dedie force son "
     "preset par un provider derive ; la premiere version passait la "
     "constante `tajwidDefault` NUE, dont `activeRules` est vide par "
     "construction -- les regles sont remplies par `applyPreset` depuis la "
     "fiabilite mesuree, jamais par la constante. "
     "Resultat exactement inverse du but : plus aucune coloration verte ni "
     "violette dans l'ecran qui existe pour verifier le tajwid. Signale par "
     "l'utilisateur (« j'ai plus les coloration vert et violet »), confirme "
     "au journal par correlation exacte TROIS fois de suite : "
     "`KaraokeOuverture modeTajwid=true` a 19:57:55, puis `regles=aucune` a "
     "19:57:58 ; idem a 19:58:47/51 et 19:58:58/19:59:01. Avant l'ouverture "
     "de cet ecran, le meme journal affichait `regles=14(...)`. "
     "Correctif : le calcul des regles fiables extrait en fonction partagee "
     "(une source, deux appelants), et on ne force QUE si le preset persiste "
     "n'est pas deja tajwid -- sinon on ecrasait les regles ajoutees a la "
     "main. Lecon generale : une constante de preset n'est pas l'etat du "
     "preset ; ce qui la complete vit dans le notifier."),

    ("mesure_filtre_de_duree_lisait_une_seule_observation",
     "[MESURE] Le filtre de duree tajwid lisait UNE observation quand les seuils sont calibres sur le MAX de quatre decoupes",
     "Remarque utilisateur (2026-09-11) : « comme le mot est juge plusieurs "
     "fois, je ne sais pas si tu gardes le max de duree pour une meilleure "
     "decision ». Verifie : `dureesParMot` accumulait deja le maximum par "
     "(mot, regle), mais le filtre lisait `d.frames` -- la seule observation "
     "courante. Une fenetre qui attrape le mot par le bord n'en voit qu'un "
     "fragment et rejetait une regle que la fenetre suivante voyait entiere. "
     "L'INCOHERENCE EST DOUBLE : le protocole de PC A qui produit ces seuils "
     "prend explicitement le MAX sur 4 decoupes par ancre (20/40/60/80 % "
     "dans une fenetre de 2,5 s), correction demandee par l'utilisateur le "
     "meme jour parce qu'« une fenetre unique peut couper la voyelle a son "
     "bord ». Calibrer sur un maximum et appliquer sur une observation "
     "unique rend les seuils trop severes par construction -- c'est le "
     "regime qui avait produit 86 rejets de regles a p=1,000 le 2026-09-05, "
     "dont des idgham_ghunnah a 480 et 560 ms refuses par un seuil a "
     "648 ms."),

    ("attente_ordre_des_madd_non_respecte_par_la_mesure",
     "[EN ATTENTE] La duree mesuree ne classe toujours pas les madd dans le bon ordre -- le lazim (6 harakat) y ressort plus court que le permissible",
     "Rapport livre par PC A le 2026-09-11 (rapport_tenue_max_madd_v2_"
     "maxfenetres), qui corrige pourtant le biais signale le jour meme par "
     "l'utilisateur en prenant le MAX sur quatre decoupes par ancre. "
     "Medianes obtenues : madda_necessary 2 frames (144 ms de moyenne), "
     "madda_obligatory 1 frame (104 ms), madda_permissible 3 frames "
     "(200 ms). Le fichier conclut lui-meme "
     "\"ordre_attendu_respecte_sur_mediane\": false. "
     "Or le madd lazim tient 6 harakat et le permissible 4 a 5 : si cette "
     "grandeur mesurait la tenue, l'ordre serait respecte PAR DEFINITION de "
     "ces categories. Elle ne la mesure donc pas. "
     "Les seuils de duree ont ete remis malgre cela, sur decision "
     "utilisateur (moyennes x 0,90 strict / x 0,70 tolerant, cf. "
     "SeuilsDureeTajwid). CE QU'IL FAUT SURVEILLER EN PREMIER : le retour "
     "des lignes `[tajwidDuree] ... REJETEE` sur une recitation dont on sait "
     "que la regle est appliquee. Si elles reviennent, c'est la table qu'il "
     "faut revider -- pas un seuil a deplacer. La question ouverte reste "
     "entiere : mesurer la TENUE d'un allongement demande autre chose que "
     "le compte de frames au-dessus d'un seuil."),
]

LIENS = [
    ("regle_les_coupes_de_palier_viennent_du_texte",
     "mesure_bornes_de_mots_sont_des_pics_ctc", "shares_data_with",
     "la regle decoule directement de la mesure : ce que la voix rend n'est pas un silence"),
    ("attente_ordre_des_madd_non_respecte_par_la_mesure",
     "mesure_bornes_de_mots_sont_des_pics_ctc", "shares_data_with",
     "meme grandeur suspecte (frames au-dessus du seuil), deux chemins de code differents"),
    ("mesure_filtre_de_duree_lisait_une_seule_observation",
     "attente_ordre_des_madd_non_respecte_par_la_mesure", "shares_data_with",
     "les seuils concernes viennent du meme envoi, calibres avec un MAX que le filtre n'appliquait pas"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step55.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
