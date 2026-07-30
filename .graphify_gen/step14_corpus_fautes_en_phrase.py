#!/usr/bin/env python3
"""Le corpus de fautes : ce qu'il vaut, et comment lui donner du contexte.

Journee du 2026-07-31. Meme principe que les etapes precedentes : on enrichit,
on n'ecrase pas, et le `rationale` porte le chiffre.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_audibilite_corpus_fautes",
     "[MESURE] 93,9 % des fautes du corpus s'entendent vraiment",
     "PREMIERE verification d'audibilite du corpus de fautes, par le rapport de "
     "vraisemblance CTC : on garde le clip si logP(texte etiquette | audio) > "
     "logP(texte canonique | audio). L'alignement force n'a rien a reecrire, "
     "contrairement au decodage libre : c'est ce qui le rend insensible au biais "
     "canonique du modele. Resultat sur les 18 195 clips `tts_augmentation` "
     "(ceux reellement utilises a l'entrainement) : 17 078 audibles = 93,9 %, "
     "1 117 dont l'audio dit le mot CORRECT. Par substitution : ت->ط 99 %, "
     "د->ض 99 %, ك->ق 98 %, س->ص 96 %, harakat 84 a 93 %. Le lot `tts_paired` "
     "(5 339 clips, autre script) est nettement moins bon : 76,4 %. "
     "ATTENTION -- j'ai d'abord annonce 70 % pour l'ensemble du corpus : "
     "c'etait le chiffre de `tts_paired` mesure avec un critere a deux faces, "
     "extrapole a tort au corpus d'entrainement."),
    ("piege_qa_cer_ne_mesure_pas_audibilite",
     "[PIEGE] Un QA au CER ne peut pas voir si la faute s'entend",
     "`qa_tts_paired.py` accepte jusqu'a CER_REJECT = 0,5 entre la "
     "transcription libre et le texte DEMANDE. Un mot dont une lettre change "
     "sur six a un CER de 0,17 : il passe, que le TTS ait prononce la faute ou "
     "le mot canonique. Le critere ne separe donc pas les deux cas -- il n'a "
     "jamais mesure l'audibilite, et personne ne s'en est rendu compte parce "
     "qu'il rendait des taux flatteurs (94 % de clips « OK »). Sa branche "
     "`OK_BIAIS_CANONIQUE` va plus loin : quand l'ASR entend le canonique, elle "
     "SUPPOSE le biais de l'ASR et garde le clip. Effet borne (77 cas), mais "
     "c'est une supposition non verifiee inscrite dans un outil de qualite."),
    ("mesure_rendement_tts_par_longueur",
     "[MESURE] XTTS ne rend la faute que s'il n'a pas de contexte a corriger",
     "Rendement de fautes AUDIBLES selon ce qu'on demande a XTTS : 1 mot isole "
     "93,9 % | phrase 2-3 mots 29 % | phrase 3-6 mots 10 % | assemblage de mots "
     "synthetises seuls (4-8 mots) 42 %, et 57 % au critere a deux faces. Le "
     "TTS a le MEME reflexe canonique que l'ASR : plus il a de contexte, plus "
     "il corrige le texte qu'on lui donne. La substitution atteint pourtant "
     "bien le modele -- verifie, 10 sequences de tokens sur 10 different apres "
     "le tokenizer XTTS, et le nettoyeur conserve les harakat. C'est donc le "
     "modele acoustique qui corrige, pas la chaine de texte."),
    ("solution_assemblage_mots_pour_contexte",
     "[SOLUTION] Fabriquer le contexte par assemblage, pas par synthese",
     "Chaque mot est synthetise SEUL (regime ou XTTS est fidele), le clip du mot "
     "faute est CONTROLE, puis les mots sont assembles en phrase. La version "
     "correcte est assemblee par le MEME chemin a partir des MEMES clips, a un "
     "mot pres : memes coutures, meme prosodie hachee. Sans cette symetrie on "
     "entrainerait un detecteur de montage. CE N'EST PAS le montage audio mort "
     "(qui remplacait une frame de 80 ms a l'interieur d'un mot) : l'unite est "
     "le MOT ENTIER, ce que la note de deces autorisait explicitement. Cout "
     "assume et a verifier a la fin : une phrase assemblee n'a pas la "
     "coarticulation d'une recitation continue."),
    ("mort_gop_fenetre_etroite",
     "[MORT] Juger le mot sur un gop recalcule en fenetre etroite",
     "Hypothese : le modele etant fidele sans contexte, recalculer gop = forced "
     "- free sur un extrait court restaurerait la detection. REFUTE : pouvoir "
     "de separation (correct - faute) de +0,682 en fenetre etroite contre "
     "+3,595 en fenetre large, l'etroite fait moins bien sur 4 paires sur 4. "
     "Raison lisible : prive de contexte, `free` s'effondre autant que "
     "`forced`, et l'ecart se referme. Ce n'est PAS la meme chose que l'idee "
     "des deux passes, qui compare des TEXTES."),
    ("mort_deux_passes_texte",
     "[MORT] Deux passes : localiser avec contexte, entendre sans contexte",
     "Idee de l'utilisateur, seduisante et correctement fondee sur les regimes "
     "mesures. Deux mesures l'ecartent. (1) DECISION : la regle « texte entendu "
     "!= mot attendu » detecte 100 % des fautes mais signale 97-99 % des mots "
     "CORRECTS ; aucun seuil sur le CER ne separe (median 1,000 des deux "
     "cotes). (2) EXTRACTION : sur des mots CORRECTS, le decodage libre de "
     "l'extrait ne rend le mot attendu que dans 20 % des cas au mieux (CER "
     "median 0,50), apres calibration du decalage (-4 frames) et de l'etendue "
     "(mi-chemin entre voisins) -- le plafond ne bouge pas quand on elargit la "
     "marge. Raison structurelle : le modele deploye est CAUSAL avec 70 frames "
     "de contexte gauche (5,6 s) ; un extrait decoupe en plein flux ne les a "
     "pas. A rouvrir avec un modele non causal, ou si l'extrait est reconstruit "
     "avec son historique."),
    ("mesure_cout_device_tetes_vs_passes",
     "[MESURE] Sur le telephone, 3 tetes coute < 1 %, deux passes coute ~3x",
     "La question posee par l'utilisateur porte sur l'EXECUTION, pas sur "
     "l'entrainement. Trois tetes : l'encodeur porte 94,9 % des parametres et la "
     "totalite du calcul, il tourne UNE fois, et chaque tete est une couche "
     "lineaire (512 -> 19 classes pour le tajwid, ~10 k parametres ; 512 -> 3 "
     "classes pour l'ecart au canonique, ~2 k). Surcout < 1 %. Deux passes : un "
     "bloc de 10 s contient ~25 mots, chaque extrait fait 0,8-1,0 s avec ses "
     "marges, soit 20-25 s d'audio EN PLUS des 10 s de la passe 1, plus 25 "
     "invocations ONNX et 25 calculs de mel par bloc. ~3x le calcul ASR, sur un "
     "budget temps reel qui vient tout juste de liberer un moteur en coupant la "
     "v1."),
    ("regle_controle_audibilite_obligatoire",
     "[REGLE] Aucun corpus de fautes ne part a l'entrainement sans controle d'audibilite",
     "Le controle est le rapport de vraisemblance CTC entre le texte de "
     "l'etiquette et le texte canonique, sur l'audio du clip. Il a tue le "
     "montage audio en cinq minutes, il a chiffre le rendement de XTTS par "
     "longueur de phrase, et il a montre qu'un QA au CER ne mesure pas ce "
     "qu'on croit. Un corpus de fautes dont la faute ne s'entend pas apprend "
     "l'INVERSE de la cible : c'est le seul defaut de donnees qui rend le "
     "modele activement nuisible plutot que simplement moins bon."),
]

LIENS = [
    ("mesure_audibilite_corpus_fautes", "piege_qa_cer_ne_mesure_pas_audibilite",
     "revele", "le QA d'origine laissait passer 6 % de clips mal etiquetes"),
    ("mesure_rendement_tts_par_longueur", "attente_tts_phrases_fautees", "mesure",
     "la piste etait non mesuree : voici son rendement"),
    ("solution_assemblage_mots_pour_contexte", "mesure_rendement_tts_par_longueur",
     "contourne", "on prend le regime a 94 % et on fabrique le contexte apres"),
    ("solution_assemblage_mots_pour_contexte", "piege_contre_exemples_mots_isoles",
     "traite", "donne enfin un CONTEXTE aux contre-exemples a fautes"),
    ("solution_assemblage_mots_pour_contexte", "mort_montage_audio_splice", "distincte_de",
     "unite = le MOT ENTIER, ce que la note de deces autorisait explicitement"),
    ("mort_gop_fenetre_etroite", "piege_biais_canonique_contexte", "ne_corrige_pas", None),
    ("mort_deux_passes_texte", "piege_biais_canonique_contexte", "ne_corrige_pas", None),
    ("mort_deux_passes_texte", "mort_gop_fenetre_etroite", "distincte_de",
     "compare des TEXTES, pas des scores -- il fallait la mesurer a part"),
    ("mesure_cout_device_tetes_vs_passes", "regle_cahier_des_charges_deux_tetes",
     "conforte", "l'architecture a tetes est aussi la moins chere a l'execution"),
    ("regle_controle_audibilite_obligatoire", "mort_montage_audio_splice", "issue_de", None),
    ("regle_controle_audibilite_obligatoire", "mesure_audibilite_corpus_fautes",
     "s_applique_a", None),
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
            "source_url": None, "captured_at": "2026-07-31", "author": None,
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step14.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
