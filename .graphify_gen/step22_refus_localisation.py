#!/usr/bin/env python3
"""Pourquoi un tiers du calcul ne produit aucun verdict (piste A, 2026-08-02).

Instrumentation des refus du Localisateur + balayages pauseMin / maxBloc
sur le banc BancFluxBrut, modele final-v1, curseur 2/4.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_refus_localisation_fenetres_trop_pauvres",
     "[MESURE] 83 % des refus de localisation = fenetre trop pauvre, pas mauvais appariement",
     "Instrumentation ajoutee le 2026-08-02 (Localisateur.derniereRaison, "
     "observation seule, taux inchange a 1,55 % avant/apres). "
     "Banc BancFluxBrut, final-v1, curseur 2/4, pause 0,25, maxBloc 30 : "
     "30 fenetres refusees sur 236 = 12,7 %. Repartition : "
     "score-insuffisant 25 (83,3 %), decodage-vide 5 (16,7 %). "
     "LA CAUSE, lisible dans le detail : `entendus=1`, `entendus=2`, "
     "`entendus=3`. Ces fenetres n'ont decode QUE 1 a 3 mots, alors que "
     "minAppariements = 2. Une fenetre qui n'entend qu'UN mot ne peut "
     "mathematiquement jamais atteindre le seuil -- elle est refusee par "
     "construction, quel que soit le modele. "
     "CE NE SONT DONC PAS des echecs d'appariement mais des fenetres PAUVRES "
     "EN TEXTE (silence, ou debut de bloc). Exemples : f=38 score=0/2 "
     "entendus=2 region=29..121 ; f=62 score=1/2 entendus=1 region=50..142. "
     "CONSEQUENCE : chercher a ameliorer l'appariement ou le modele ne "
     "corrigerait rien ici. Le levier est en amont -- ne pas emettre de "
     "fenetre dont on sait deja qu'elle ne portera pas assez de texte."),

    ("mort_maxbloc_court_sur_architecture_curseur",
     "[MORT] Plafonner maxBloc a 6 s : 1,55 % -> 14,58 %",
     "Demande utilisateur du 2026-08-02, testee malgre la mesure ancienne "
     "(l'agent avait d'abord refuse en citant un commentaire mesure sur une "
     "AUTRE architecture -- incoherent, puisqu'il venait d'argumenter que la "
     "falaise de pauseMin ne se transportait pas. L'utilisateur a eu raison "
     "d'exiger la remesure). "
     "Banc, final-v1, pause 0,25, curseur 2/4, meme WAV : "
     "maxBloc 6 s -> 14,58 % (ancre 191) ; 8 s -> 8,25 % ; 12 s -> 2,06 % ; "
     "18 s -> 1,55 % ; 30 s -> 1,55 %. "
     "Le sens de l'ancienne mesure est confirme sur l'architecture ACTUELLE, "
     "avec une amplitude moindre (14,6 % contre 51,5 % a l'epoque, a 18 s) : "
     "le curseur glissant amortit une partie du degat. "
     "POURQUOI : un plafond coupe OU QU'ON EN SOIT, donc en pleine parole. "
     "A distinguer de pauseMin, qui est un CRITERE et coupe toujours a une "
     "frontiere de mot. Plafond et critere ne sont pas interchangeables."),

    ("mesure_pausemin_plateau_020_035",
     "[MESURE] pauseMin : plateau indiscernable de 0,20 a 0,35, chute a 0,15",
     "Banc, final-v1, curseur 2/4, maxBloc 30, meme WAV, ancre 193 partout "
     "(denominateur constant -- comparaison propre) : "
     "0,15 -> 3,09 % (6 mots, 319 blocs) ; 0,20 -> 1,55 % (3 mots, 272) ; "
     "0,25 -> 1,55 % (3 mots, 236) ; 0,30 -> 1,55 % (3 mots, 236) ; "
     "0,35 -> 1,03 % (2 mots, 209). "
     "LECTURE HONNETE : de 0,20 a 0,35 l'ecart vaut 1 mot sur 194, c'est "
     "INDISCERNABLE. Seul 0,15 est nettement moins bon. La tendance va vers "
     "MOINS de blocs, l'inverse de l'hypothese testee (« fractionner pour "
     "gagner en reactivite »). "
     "CALIBRATION QUI L'EXPLIQUE : sur cet audio, 251 silences, p25 = 0,080 s, "
     "mediane 0,160 s, p75 = 0,240 s, p90 = 0,640 s, separation p90/p25 = 8. "
     "Deux populations distinctes : micro-pauses de phrase (~0,08-0,24 s) et "
     "vraies respirations (>= 0,64 s). Descendre sous 0,20 fait couper DANS le "
     "souffle d'un mot au lieu d'entre deux mots."),

    ("mesure_latence_affichage_rafales",
     "[MESURE] L'affichage n'attend pas la fin du bloc : mediane 3,4 s, trous jusqu'a 9,9 s",
     "Session device du 2026-08-02 (v6-offline-final-v1, rejeu deterministe). "
     "Hypothese utilisateur : « le rendu ne se fait qu'en fin de bloc ». "
     "MESURE : 234 fenetres emises en 252 s, cadence mediane 0,8 s -- le "
     "curseur emet donc bien SANS attendre la fin du bloc. Mais les verdicts "
     "sortent en 74 instants distincts pour 200 verdicts : ecart median 3,4 s, "
     "p90 5,9 s, MAX 9,9 s, avec 4 rafales de 6-7 mots d'un coup. "
     "CAUSE : 23 % des mots vus sont « au bord » et ne votent pas "
     "(236 sur 1047), consequence du lookahead de 1,04 s ; et le Decideur "
     "exige k=2 observations concordantes. Plusieurs mots deviennent donc "
     "interieurs ET atteignent leur 2e observation en meme temps -> ils "
     "tombent ensemble. "
     "CE N'EST PAS un probleme de decoupage : ni maxBloc ni pauseMin ne "
     "l'ameliorent (les deux ont ete balayes)."),

    ("mesure_stream_v3_sans_gain_dans_la_chaine",
     "[MESURE] stream-v3 : meilleur val_wer_ctc, aucun gain dans la chaine",
     "Idee utilisateur : utiliser les POIDS entraines pour le streaming dans "
     "le front OFFLINE (les deux sont independants). Test propre a une seule "
     "variable -- export ONNX verifie (audio_signal/length, PyTorch == ONNX), "
     "vocab IDENTIQUE au bit pres (meme md5), meme WAV, meme config 2/4/0,25. "
     "val_wer_ctc : stream-v3 0,179 < v1-lr3e4 0,182 < stream-v2 0,183 < "
     "stream-v1 0,186. stream-v3 est donc le MEILLEUR sur la metrique interne. "
     "DANS LA CHAINE, sur le corps de la recitation (mots 0-191) : "
     "final-v1 3 non verts, stream-v3 4 non verts. EQUIVALENTS. "
     "Le chiffre agrege de stream-v3 (14/202 = 6,93 %) est trompeur : 10 des "
     "14 sont des mots 192-201 JAMAIS JUGES, une queue de fin de fichier -- "
     "stream-v3 pousse l'ancre a 201 contre 193, au-dela de ce qu'il sait "
     "juger. L'agent a d'abord annonce « 4,5x moins bon » sur ce chiffre "
     "agrege AVANT d'en regarder la composition, ce que la methode du projet "
     "interdit explicitement (tableau mot par mot AVANT interpretation). "
     "CONCLUSION : sans gain, donc pas de raison de deployer -- mais pas "
     "perdant non plus. Et 3e confirmation que val_wer_ctc ne predit pas le "
     "comportement en regime de deploiement."),
]

LIENS = [
    ("mesure_refus_localisation_fenetres_trop_pauvres",
     "mesure_latence_affichage_rafales", "explique",
     "les fenetres refusees coutent une inference pour zero verdict"),
    ("mort_maxbloc_court_sur_architecture_curseur",
     "mesure_pausemin_plateau_020_035", "oppose",
     "un plafond coupe n'importe ou, un critere coupe a une frontiere de mot"),
    ("mesure_stream_v3_sans_gain_dans_la_chaine",
     "piege_confondre_les_instruments_de_mesure", "illustre",
     "val_wer_ctc et taux de mots non verts sont deux instruments differents"),
    ("mesure_stream_v3_sans_gain_dans_la_chaine",
     "mort_front_streaming_branche_dans_v2", "distingue",
     "les POIDS streaming ne sont pas le FRONT streaming : seul le front est perdant"),
    ("mesure_latence_affichage_rafales",
     "mesure_pausemin_plateau_020_035", "delimite",
     "aucun reglage de decoupage n'agit sur la latence d'affichage"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step22.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
