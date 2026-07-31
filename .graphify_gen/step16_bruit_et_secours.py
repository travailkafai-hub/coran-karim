#!/usr/bin/env python3
"""Le banc ne distingue plus un effet d'un hasard — et deux mecanismes non juges.

Fin de journee du 2026-07-31. Le noeud le plus important est le PIEGE sur le
bruit du banc : il invalide la lecture de plusieurs mesures de l'apres-midi.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_banc_bruit_depasse_effet_cherche",
     "[PIEGE] Une passe ne distingue plus un effet d'un hasard",
     "ARGUMENT DECISIF DE L'UTILISATEUR (2026-07-31) : « on rajoute une "
     "condition FAVORABLE et on a un resultat catastrophique, ce n'est pas "
     "logique -- au pire ca doit etre pareil ». Deux changements strictement "
     "favorables ne peuvent pas degrader. Verifications faites : le code est "
     "correct, l'APK le contient (source 15:53, build 15:57, recette 16:05), et "
     "le TEMPS REEL est tenu (derive horloge/audio 0,0 s sur 270 blocs PCM). "
     "DONC L'ECART EST DU BRUIT. Consequence : les comparaisons 2,37 % / 3,05 % "
     "/ 4,41 % de l'apres-midi tiennent toutes dans l'intervalle documente du "
     "banc (deux passes identiques varient de 0 a 10,9 %) et NE PROUVENT RIEN. "
     "Du code a ete retire sur cette base."),
    ("mesure_cause_variabilite_segmentation",
     "[MESURE] La variabilite vient de la SEGMENTATION, pas du micro",
     "Trouvee en cherchant une file d'attente qui n'existait pas : 159 fenetres "
     "contre 170 pour le MEME audio et la MEME duree. La cadence du curseur "
     "depend des silences rencontres -- chaque coupe reinitialise le compteur "
     "d'apercu -- donc deux passes ne decoupent pas aux memes endroits et les "
     "mots ne tombent pas au meme endroit dans leur fenetre. Un mot au CENTRE "
     "est bien juge, le meme au BORD ne l'est pas. "
     "CONSEQUENCE PRATIQUE : le rejeu deterministe d'un WAV (b72b05b) ne "
     "suffirait PAS a rendre le banc reproductible, puisque la segmentation "
     "resterait sensible. Il faut soit plusieurs passes et la mediane, soit une "
     "cadence d'apercu INDEPENDANTE des coupes."),
    ("attente_secours_sur_omission",
     "[EN ATTENTE] Secours : regarder l'audio avant de dire « pas prononce »",
     "CONSTAT VERIFIE SUR LE WAV (verifier_non_verts_v2.py, deux recettes) : des "
     "mots declares `Omis` sont bel et bien dans l'audio -- mot 228 « وَإِن » "
     "(le WAV dit « وَإِن كُنتُمْ فِى رَ »), 205 « ٱلَّذِى », 220 « رِزْقًا », 67 "
     "« أَلَآ » avec gop 0,00 et texte EXACT. Le critere d'omission etait "
     "purement POSITIONNEL -- trois mots plus loin sont juges, donc celui-ci est "
     "perdu -- sans jamais regarder l'audio du mot lui-meme. Or `Omis` est le "
     "verdict le plus grave que l'app puisse rendre. "
     "IMPLEMENTE : attestation EXACTE -> VERT, sans repasser par le gop. "
     "NON JUGE : il n'a pas declenche lors de la recette (le mot 67 avait "
     "free = -0,16 au lieu de -0,01, donc pas d'attestation exacte) -- il est "
     "peut-etre trop restrictif. Et il NE JOURNALISE RIEN : le tracer avant de "
     "le rejuger."),
    ("attente_sens_unique_provisoire",
     "[EN ATTENTE] Un provisoire ne se degrade jamais",
     "DECISION UTILISATEUR : « je veux implementer un seul sens, meme sur les "
     "jugements partiels avant le definitif ». Le code portait deja le constat "
     "avec les numeros : les mots 170, 171, 174, 205, 67 etaient lus "
     "PARFAITEMENT dans leur propre enonce (gop 0,00, texte exact, atteste) puis "
     "DEGRADES par une fenetre qui les tronquait (ٱلْبَرْ pour ٱلْبَرْقُ). Le mot "
     "170 est ressorti orange le 2026-07-31 avec la MEME troncature, sept jours "
     "plus tard. Le curseur glissant aggrave le probleme : une fenetre toutes "
     "les 3 s au lieu d'une par silence, donc bien plus d'occasions qu'une "
     "fenetre defavorable arrive APRES une bonne. Ne touche QUE l'affichage "
     "provisoire -- le verrouillage exige toujours deux fenetres concordantes. "
     "NON JUGE : mesure noyee dans le bruit du banc."),
    ("piege_commentaire_maxbloc_30s_faux",
     "[PIEGE] Le commentaire de maxBloc = 30 s affirme un fait FAUX",
     "Il dit « jamais de bloc plus long que les clips d'entrainement ». MESURE "
     "sur les 59 232 clips de Coran recite du manifeste : mediane 12,6 s, q90 "
     "32,0 s, q99 53,9 s, MAX 60,0 s -- et 11,9 % des clips depassent 30 s. La "
     "borne ne colle donc pas au domaine d'entrainement ; c'est une valeur ronde "
     "justifiee apres coup. Si l'on voulait vraiment coller au domaine elle "
     "serait vers 50 s. Un futur agent croira ce commentaire sur parole. "
     "Remarque : cette borne ne gouverne presque plus rien -- le bloc median "
     "mesure fait 16,5 s, c'est le SEUIL DE PAUSE (0,40 s) qui commande."),
    ("mesure_modele_deploye_une_seule_tete",
     "[MESURE] Le modele deploye n'a QU'UNE tete utilisable",
     "Verifie sur les parametres du checkpoint : 0 parametre tajwid. Blocs = "
     "preprocessor, encoder (692), decoder (5) et joint (6) = tete RNNT "
     "neutralisee dans tous les runs du projet, ctc_decoder (2) = 1025 classes. "
     "L'export ONNX n'a donc qu'UNE sortie : les logprobs des lettres. "
     "Les 3 tetes sont le PLAN, pas l'etat : la tete tajwid existe dans un autre "
     "run (`causal-stageb`) et est devenue incompatible depuis que l'encodeur a "
     "bouge ; la tete « ecart au canonique » a ete entrainee hors device le "
     "2026-07-31 (16 833 parametres, 31 % de detection) et n'est pas branchee. "
     "CONSEQUENCE : tout ce qui ameliore la detection aujourd'hui (regle C, "
     "marge de confusion) se calcule A LA MAIN a partir des logprobs -- on "
     "fabrique ce qu'une tete dediee ferait mieux, puisqu'elle lirait les 512 "
     "dimensions de l'encodeur et non leur projection sur 1025 classes."),
]

LIENS = [
    ("piege_banc_bruit_depasse_effet_cherche", "mesure_cause_variabilite_segmentation",
     "explique_par", None),
    ("attente_secours_sur_omission", "piege_banc_bruit_depasse_effet_cherche",
     "non_jugeable_a_cause_de", None),
    ("attente_sens_unique_provisoire", "piege_banc_bruit_depasse_effet_cherche",
     "non_jugeable_a_cause_de", None),
    ("attente_secours_sur_omission", "couche_v2_g_decision", "modifie", None),
    ("attente_sens_unique_provisoire", "couche_v2_g_decision", "modifie", None),
    ("mesure_cause_variabilite_segmentation", "solution_curseur_glissant", "limite",
     "la cadence depend des coupes, donc le decoupage n'est pas reproductible"),
    ("mesure_modele_deploye_une_seule_tete", "regle_cahier_des_charges_deux_tetes",
     "etat_reel_de", None),
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
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pourquoi, "rationale": pourquoi})
        aretes += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step16.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
