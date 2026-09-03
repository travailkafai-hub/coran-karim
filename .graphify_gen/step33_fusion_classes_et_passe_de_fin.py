#!/usr/bin/env python3
"""Nuit du 2026-09-03 : le dernier mot condamne sans preuve, et les classes fusionnees.

Deux causes de faux violet, mesurees l'une apres l'autre sur l'audio de
l'utilisateur, apres celles deja consignees par step32.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_la_passe_de_fin_ne_remontait_aucune_regle",
     "[PIEGE] `v2Terminer` rendait `detectedRules` VIDE en dur -- le dernier mot de chaque palier etait condamne sans preuve",
     "Constat utilisateur, CINQ essais de suite sur `ٱلْخَنَّاسِ` : « toujours "
     "violet, meme en rabaissant la tolerance ». Ni le modele, ni les seuils, "
     "ni la recitation. LE BANC DIRECT sur le WAV de l'essai : transcription "
     "exacte (`مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ`, donc banc valide) et ghunna a "
     "0,993 en PLATEAU de 4,56 s a 5,36 s -- 0,8 seconde au-dessus du seuil "
     "strict 0,604. La regle etait parfaitement realisee. LA CHAINE : (1) "
     "`ٱلْخَنَّاسِ` est le DERNIER mot du palier, la fenetre ne va jamais assez "
     "loin au-dela de lui, donc `frames=0` et verrouillage « fermeture de "
     "session » sans ligne de preuve ; (2) il est finalise par `v2Terminer`, "
     "qui ne renvoyait que `i` et `statut` -- `detectedRules` arrivait VIDE EN "
     "DUR cote Dart ; (3) le palier leve la double observation, donc le mot est "
     "juge quand meme -> « regle attendue, aucune detectee » -> VIOLET GARANTI, "
     "quoi que fasse le recitateur et quel que soit le seuil. Ce n'etait pas un "
     "rejet par seuil : `decodeTajwid` n'etait meme pas appele "
     "(`if (m.frames > 0)`). Les regles EXISTAIENT pourtant -- `terminer()` "
     "appelle `traiter(fenetre)`, qui remplit le registre de preuves. CORRECTIF "
     "(2026-09-03) : le natif lit `chaine.preuves.observations()` et rend "
     "`rules` + `tajwidObserve` ; Dart exige `tajwidObserve` avant toute "
     "degradation. Le drapeau du Coach leve la DEUXIEME observation, jamais la "
     "premiere."),

    ("regle_aucun_verdict_tajwid_sans_observation",
     "[REGLE] `tajwidFiable` (deux fois) et `tajwidObserve` (au moins une fois) sont deux questions differentes",
     "Nee du piege ci-dessus. `tajwidFiable = votantes.size >= 2 || "
     "estDefinitif` repond a « ce mot a-t-il ete vu DEUX fois ? ». Il ne repond "
     "pas a « a-t-il ete vu TOUT COURT ? ». Le drapeau "
     "`tajwidSansDoubleObservation`, pose a l'entree du palier et du controle, "
     "levait les deux exigences d'un coup -- d'ou des verdicts rendus sur des "
     "mots que rien n'avait regarde, ce que la regle premiere du projet "
     "interdit (« aucun verdict sans preuve acoustique »). Le champ "
     "`tajwidObserve` separe les deux ; un drapeau de rigueur ne doit jamais "
     "pouvoir supprimer la preuve elle-meme."),

    ("mesure_les_trois_regles_du_noun_franchissent_le_seuil_ensemble",
     "[MESURE] ikhafa, idgham_ghunnah et iqlab franchissent le seuil EXACTEMENT ensemble -- preuve directe qu'elles sont une seule classe",
     "Constat utilisateur sur `مِّن جُوعٍ وَءَامَنَهُم` (Quraysh 106:4), trois "
     "essais : « ca passe pas, puis j'ai mis tolerant et ca passe ». Le journal "
     "donne la preuve experimentale de la fusion annoncee par "
     "`classes_10.json` : en STRICT `detectees = ikhafa` seule et le palier "
     "echoue sur `idgham_ghunnah` attendue ; en TOLERANT `detectees = ikhafa, "
     "idgham_ghunnah, iqlab` -- les trois d'un coup -- et le palier passe. "
     "Trois noms qui franchissent le seuil au meme instant quand il descend, "
     "c'est une valeur unique. Idem pour `ikhafa_shafawi`/`idgham_shafawi`, qui "
     "sortent toujours par paire sur `أَطْعَمَهُم`. CORRECTIF : "
     "`_groupesFusionnes` -- une regle attendue est satisfaite si le modele a "
     "detecte n'importe laquelle de son groupe. CE N'EST PAS DE LA TOLERANCE "
     "AJOUTEE : c'est cesser de sur-interpreter la sortie du modele. PRIX "
     "ASSUME : l'app validera un `iqlab` attendu meme si le recitant fait une "
     "`ikhafa`. Seul un reentrainement sur classes separees rendrait la "
     "finesse ; aucun seuil n'y arrivera."),

    ("piege_j_ai_condamne_les_madd_sur_un_seul_wav_de_3s",
     "[PIEGE] Les deux madd declares muets sur UN enregistrement de 3 s sortent a 0,943 sur un autre",
     "Decision prise en session : `madda_obligatory` et `madda_permissible` "
     "passent en observation seule, sur la foi d'un banc ou ils rendaient 0,033 "
     "et 0,001 alors qu'ils etaient attendus ET realises. Un second "
     "enregistrement, quelques minutes plus tard, donne `madda_permissible` a "
     "0,943 et `madda_obligatory` detecte sur `ٱلَّذِىٓ`. La premiere mesure "
     "portait sur UN SEUL WAV de 3,12 s : echantillon trop maigre pour "
     "condamner deux regles, et la conclusion « aucun seuil ne les rattrape » "
     "n'est pas etablie. Le retrait du jugement reste en place faute de mieux, "
     "mais LA MESURE QUI LE JUSTIFIE EST A REFAIRE sur plusieurs prises avant "
     "d'en tirer quoi que ce soit."),

    ("outil_banc_direct_wav_vers_modele",
     "[OUTIL] Banc direct WAV -> modele, valide par sa propre transcription -- ce qui manquait toute la soiree",
     "Ecrit sur demande de l'utilisateur (« vas-y utilise le meme WAV et teste "
     "le modele ! »). Rejoue n'importe quelle capture dans le modele deploye en "
     "quelques secondes, sans rebuild ni telephone : mel reimplemente a la main "
     "(pas de librosa sur la machine), inference ONNX, puis probabilites tajwid "
     "par classe et par trame. CONTROLE DE VALIDITE INTEGRE, et il a servi deux "
     "fois : on decode AUSSI la tete CTC ; si le texte arabe sort exact, le mel "
     "est juste et les sorties tajwid sont exploitables. Sur une capture le CTC "
     "est sorti VIDE -- le WAV etait quasi silencieux (RMS 0,005 contre 0,061 "
     "sur une capture normale, facteur 12) et aucune conclusion n'a ete tiree. "
     "Sans ce garde-fou, un mel errone aurait ete lu comme « la tete ne detecte "
     "rien ». AVANT ce banc, trois series de seuils ont ete calibrees a "
     "l'aveugle depuis les seuls journaux."),
]

LIENS = [
    ("piege_la_passe_de_fin_ne_remontait_aucune_regle",
     "regle_aucun_verdict_tajwid_sans_observation",
     "depends_on",
     "Le piege a impose la distinction entre observe et fiable"),
    ("piege_la_passe_de_fin_ne_remontait_aucune_regle",
     "mesure_le_palier_court_juge_tout_a_la_fermeture",
     "depends_on",
     "Le dernier mot passe toujours par la passe de fermeture"),
    ("mesure_les_trois_regles_du_noun_franchissent_le_seuil_ensemble",
     "piege_le_modele_a_10_classes_pas_17",
     "depends_on",
     "Preuve experimentale de la fusion annoncee par classes_10.json"),
    ("outil_banc_direct_wav_vers_modele",
     "mesure_tete_tajwid_voit_mais_le_seuil_rejette",
     "depends_on",
     "C'est ce banc qui a etabli que la tete voyait a 0,633"),
    ("outil_banc_direct_wav_vers_modele",
     "piege_j_ai_condamne_les_madd_sur_un_seul_wav_de_3s",
     "semantically_similar_to",
     "Le meme banc a produit la mesure fautive puis sa refutation"),
]


def sha():
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    a = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            print(f"  = deja present : {nid}")
            continue
        g["nodes"].append({
            "label": label, "rationale": rationale, "node_type": "concept",
            "id": nid, "community": 0, "norm_label": label.lower()})
        a += 1
    connus = {n["id"] for n in g["nodes"]}
    ar = 0
    for s, t, rel, pq in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}")
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pq, "rationale": pq})
        ar += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step33.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
