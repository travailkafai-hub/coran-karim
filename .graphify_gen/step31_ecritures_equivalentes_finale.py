#!/usr/bin/env python3
"""Ecritures equivalentes en FINALE de mot, et refonte de l'objectif du Coach.

Mesures du 2026-08-14 (session live Al-Fil, puis rejeu du MEME flux brut sur le
banc hors telephone : memes blocs, memes logprobs des deux cotes, seul le code
change).
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("symptome_soukoun_final_condamne_un_mot_juste",
     "[SYMPTOME] Un mot JUSTE sort orange parce que la CIBLE porte une marque contextuelle que le modele n'emet jamais -- nait dans la cible, se voit dans le Decideur",
     "Session live Al-Fil : `mot=20 \"تَرْمِيهِم\" -> definitif:orange | "
     "gop=-0.46 forced=-0.53 free=-0.07` pour un seuil de vert a -0,45 -- il "
     "echoue a 0,01 pres. Et `mot=26 \"مَّأْكُولٍۭ\" -> provisoire:orange | "
     "gop=-0.69 margeH=-0.14`. Balayage du flux brut capte par l'app (largeurs "
     "4 s ET 6 s) : le modele decode `تَرْمِيهِمْ` AVEC le soukoun dans TOUTES "
     "les fenetres, et `مَّأْكُولٍ` SANS le petit meem, sans hesiter "
     "(free=-0,07 : il est certain de ce qu'il entend). Tout le cout est donc "
     "dans le `forced`, sur une graphie qu'il n'emet pas. Vocabulaire du "
     "modele deploye (1024 tokens) : U+0652 present dans 242 tokens, U+06ED "
     "dans UN SEUL. Ces marques dependent du mot SUIVANT (ikhfa' shafawi, "
     "iqlab) : elles annoncent une REGLE DE TAJWID, pas un phoneme -- leur "
     "realisation est l'affaire de la tete 3, pas du forced de la tete texte."),

    ("var_orthographe_soukoun_final_et_signes_tajwid",
     "Orthographe.variantes : soukoun FINAL present/absent + signes de tajwid contextuels retires (familles 8 et 9)",
     "Correctif du 2026-08-14. MESURE, banc hors telephone sur le flux brut de "
     "la session (memes 28 blocs, memes logprobs, seul le code change) : non "
     "verts 8/27 = 29,63 % -> 6/27 = 22,22 %. `تَرْمِيهِم` ORANGE -> VERT, "
     "`مَّأْكُولٍۭ` ORANGE -> VERT, et les gop des mots 13 et 24 INCHANGES a la "
     "decimale pres -- la variante ne deborde pas. Decision utilisateur qui "
     "fonde le correctif : « on doit avoir les deux options, avec soukoun "
     "present et absent, car les deux c'est la meme chose ». CE N'EST PAS UNE "
     "TOLERANCE MAIS UNE EQUIVALENCE : les deux graphies notent le meme son, "
     "aucune n'est fautive, donc rien n'est pardonne et aucun critere ne "
     "bouge. STRICTEMENT BORNE A LA FINALE : a l'interieur d'un mot, ajouter "
     "ou retirer un soukoun CHANGE le son (consonne vocalisee ou non) et "
     "blanchirait une vraie faute -- meme piege que la variante « alif suscrit "
     "supprime », retiree le 2026-07-30."),

    ("piege_orthographe_max_evincait_en_silence",
     "[PIEGE] Orthographe.MAX=7 avec `out.take(MAX)` EVINCAIT deja des variantes utiles, sans une ligne de trace",
     "Trouve le 2026-08-14 en preparant l'ajout des familles 8 et 9. Un mot "
     "cumulant alif suscrit + wasla + madda + waw suscrit + ya suscrit produit "
     "6 variantes plus la combinaison plus le madd tenu, soit 8 entrees avec "
     "le canonique -- au-dessus du plafond de 7. `out.take(MAX)` coupe la FIN "
     "de la liste : le madd tenu, genere en dernier depuis le 2026-08-06, "
     "tombait donc silencieusement sur ces mots-la, et toute famille ajoutee "
     "apres lui serait la premiere perdue. Porte a 10. Regle a retenir : un "
     "plafond qui tronque une liste ORDONNEE fait disparaitre le dernier "
     "mecanisme ajoute, c'est-a-dire toujours le plus recent et le moins "
     "surveille. Cout d'une variante : un treillis minuscule sur les SEULES "
     "frames du mot (forwardMoyenGraphe), aucune passe d'encodeur en plus."),

    ("en_attente_waqf_variante_fin_de_verset",
     "[EN ATTENTE] Waqf : finale voyellee / finale en soukoun -- demande une information que la couche n'a PAS",
     "Demande utilisateur du 2026-08-14 : « en fin de verset on a bien une "
     "haraka, mais il est permis en arabe de prononcer le soukoun en fin, "
     "c'est la regle, et ca ne demande pas de souplesse parce qu'on n'est pas "
     "dans l'erreur ». VOLONTAIREMENT NON IMPLEMENTE avec les familles 8 et 9 "
     "le meme jour : le waqf n'est licite qu'en FIN DE VERSET, or "
     "`Orthographe.variantes(mot)` ne recoit qu'un mot, sans sa position. "
     "Applique a l'aveugle a tous les mots, il blanchirait une faute d'i'rab "
     "en plein verset (finale mal vocalisee validee par la forme en soukoun). "
     "Signature connue : « une couche devine une information qu'elle n'a pas "
     "-> il faut la lui DONNER » (drapeau finDeVerset transmis depuis Dart). "
     "Un test verrouille le refus actuel : `رَبُّكَ` ne doit produire AUCUNE "
     "forme en soukoun tant que l'information manque."),

    ("piege_harakat_souples_inoperant_sur_la_v2",
     "[PIEGE] Le preset `strictHarakat=false` est affiche mais INOPERANT : `_relaxJudged` n'est pas sur le chemin qui peint l'ecran",
     "Constate le 2026-08-14 en cherchant pourquoi les mots ci-dessus "
     "sortaient orange malgre le preset adulte. `_relaxJudged` "
     "(recitation_provider.dart) rend `correct` tout mot dont le SQUELETTE de "
     "lettres est identique -- il aurait donc « sauve » ces mots. Mais depuis "
     "`_v2PiloteAffichage = true`, le verdict vient du `Decideur` Kotlin et "
     "est converti DIRECTEMENT en `WordStatus` : le relachement reste sur le "
     "chemin v1, mort. Le journal affiche pourtant `strictHarakat=false` a "
     "chaque session, ce qui fait croire l'inverse. DEUX SUJETS A NE PAS "
     "CONFONDRE (distinction posee par l'utilisateur) : harakat souples = "
     "tolerer une VRAIE erreur (damma au lieu de kasra) ; ecritures "
     "equivalentes = deux notations du MEME son, aucune erreur. Reparer "
     "`_relaxJudged` pour regler le soukoun serait un contresens : un mot "
     "juste serait valide par un mecanisme de PARDON, donc uniquement quand "
     "l'utilisateur choisit d'etre indulgent, et resterait orange en mode "
     "strict ou il est pourtant correct."),

    ("regle_objectif_coach_duree_pour_tout_le_coran",
     "[REGLE] L'objectif du Coach est une DUREE pour tout le Coran, et son rythme porte sur le RESTE a memoriser",
     "Refonte du 2026-08-14 (l'objectif se saisissait en « N quarts par "
     "jour/semaine/mois », juge illisible : un volume ne dit pas vers quoi il "
     "mene). L'utilisateur choisit en combien d'ANNEES (curseur 1 a 6) ; l'app "
     "derive le rythme par jour, semaine et mois sur `240 - quarts acquis`. "
     "Les quarts acquis se comptent en MOTS DISTINCTS (`DISTINCT surah, ayah, "
     "word` sur portion_words) : la granularite des portions est un REGLAGE, "
     "donc additionner des portions compterait deux fois les memes mots quand "
     "elle change. Effet de bord identifie AVANT d'implementer et traite : le "
     "seuil quotidien de la serie, derive du rythme, tombait a ~35 mots a "
     "6 ans -- An-Nasr plus une ligne, une serie qui ne peut plus se rompre. "
     "D'ou un plancher de 50 mots. Migration base v6 -> v7 "
     "(`jours_actifs.objectif_mots_du_jour`) : l'ancienne colonne porte des "
     "QUARTS sur les jours anterieurs, changer son unite en place aurait rendu "
     "l'historique faux EN SILENCE."),

    ("piege_avancement_coach_somme_de_fractions_de_portions",
     "[PIEGE] La barre du Coach sommait des FRACTIONS DE PORTION : une sourate courte complete valait un quart PLEIN",
     "Deuxieme source fausse de la meme barre, le meme jour que la premiere "
     "(cf. piege_progression_coach_sur_compteur_cumulatif). Apres correction "
     "du compteur cumulatif, l'avancement sommait `wordsGreen / wordsTotal` "
     "plafonne a 1 PAR PORTION -- or une portion « sourate entiere » courte "
     "vaut 1 quart plein : Al-Kawthar (10 mots) comptait autant qu'un vrai "
     "quart de Hizb (~322 mots). MESURE sur la base reelle du telephone : la "
     "barre totalisait 12,37 quarts pour 272 mots acquis, qui en valent 0,84 "
     "-- « 100 % ce mois-ci » s'affichait sous « il te reste 239 quarts sur "
     "240 », deux chiffres contradictoires sur la meme carte. Corrige en "
     "lisant la MEME grandeur que le reste a memoriser (mots distincts / "
     "322,6). Le plancher `jours_actifs.quarts_valides` a saute avec : il "
     "s'incremente sur `PortionResume.badge`, donc il portait exactement le "
     "meme biais et l'aurait reintroduit a lui seul. TROIS sources fausses en "
     "une journee pour cette seule barre : une mesure d'avancement ne peut pas "
     "melanger deux unites, et une portion n'est pas une unite de volume."),
]

LIENS = [
    ("symptome_soukoun_final_condamne_un_mot_juste", "var_orthographe_soukoun_final_et_signes_tajwid",
     "shares_data_with", "la cible est la cause, les variantes en finale sont le correctif mesure"),
    ("var_orthographe_soukoun_final_et_signes_tajwid", "piege_orthographe_max_evincait_en_silence",
     "shares_data_with", "l'ajout des familles 8 et 9 a revele que le plafond tronquait deja"),
    ("var_orthographe_soukoun_final_et_signes_tajwid", "en_attente_waqf_variante_fin_de_verset",
     "shares_data_with", "meme mecanisme, mais le waqf exige la position dans le verset"),
    ("symptome_soukoun_final_condamne_un_mot_juste", "piege_harakat_souples_inoperant_sur_la_v2",
     "shares_data_with", "le preset semblait devoir sauver ces mots ; il ne tourne plus sur le chemin v2"),
    ("regle_objectif_coach_duree_pour_tout_le_coran", "piege_avancement_coach_somme_de_fractions_de_portions",
     "shares_data_with", "afficher le reste a memoriser a rendu visible la contradiction de la barre"),
    ("piege_progression_coach_sur_compteur_cumulatif", "piege_avancement_coach_somme_de_fractions_de_portions",
     "shares_data_with", "premiere et deuxieme source fausses de la MEME barre, le meme jour"),
    ("regle_seuil_journalier_derive_de_l_objectif", "regle_objectif_coach_duree_pour_tout_le_coran",
     "shares_data_with", "le seuil derive desormais d'une duree, avec un plancher de 50 mots"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step31.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
