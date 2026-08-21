#!/usr/bin/env python3
"""Seuils tajwid par classe, controle jamais atteint, et le tajwid qui accusait.

Mesures du 2026-08-16/17 : audio reel Al-Afasy hors telephone pour les seuils,
journal de sessions live pour le reste (trois diagnostics poses couche par
couche -- V2tajwidWrite, RenderTajwid, MotsOubliesAdd -- puis retires).
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mort_seuil_plat_0_5_tete_tajwid",
     "[MORT] Seuil PLAT 0,5 sur la tete tajwid -- \"frontiere naturelle d'une sigmoide, pas un reglage a calibrer\"",
     "Le commentaire de `decodeTajwid` affirmait qu'un seuil a 0,5 n'etait pas "
     "un reglage. MESURE sur audio reel (Al-Afasy, modele trois-tetes deploye, "
     "comptage agrege toutes classes contre les reperes du texte annote) : "
     "fenetre de calibrage 2:6..2:62, 57 versets, verite 774 reperes -> 2 393 "
     "spans, soit +209,2 %. HORS fenetre (sourates 3, 18, 36, 67, 112, 84 "
     "versets), verite 813 -> 2 764 spans, +240,0 %. Une regle sur trois "
     "environ etait inventee. Les seuils PAR CLASSE de `seuils_tajwid.json` "
     "ramenent a 991 (+28,0 %) et 1 125 (+38,4 %) sur les memes deux "
     "echantillons -- et le gain TIENT hors de la fenetre de calibrage, donc "
     "ce n'est pas du surapprentissage local. Raison de fond : chaque classe a "
     "sa propre confiance naturelle (mesuree de 0,5 a 0,9633 selon la classe), "
     "pas une frontiere commune. LIMITE ASSUMEE de cette mesure : elle est "
     "class-blind (total de spans contre total de reperes), faute de "
     "`rules_map.json` (table symbole PUA -> classe) sur ce poste ; le residu "
     "de +28/+38 % peut donc cacher des classes compensees entre elles."),

    ("piege_tajwid_jamais_controle_sur_mot_verrouille_par_raccourci",
     "[PIEGE] Un mot verrouille par le raccourci \"nette\" (1 observation) ne voit JAMAIS son tajwid controle",
     "`tajwidFiable` exigeait 2 observations votantes, quand le Decideur peut "
     "figer un VERT sur UNE SEULE observation (regle `nette` : decodage libre "
     "et alignement force d'accord). Or un mot `dejaFige` n'est plus jamais "
     "reevalue et son audio sort du tampon : son tajwid n'etait donc controle "
     "NULLE PART, jamais -- pas en retard, jamais. MESURE sur 3 sessions "
     "reelles (2026-08-16) : 6 mots sur 28 portant une regle active, soit "
     "21 %, verrouilles definitif:vert sans que `tajwidFiable` soit devenu "
     "vrai une seule fois (An-Nas 2/9, Al-Balad 4/14). Correctif : au moment "
     "du verrouillage, se rabattre sur TOUTES les observations disponibles "
     "plutot que rien. Verifie apres correctif sur audio deterministe 2:6 : "
     "0 mot bloque sur 5 suivis, et `mot=0 إِنَّ` verrouille a obs=1 rend "
     "desormais `ghunnah` NON DETECTEE -- ligne impossible a produire avant."),

    ("piege_tajwid_comptait_comme_echec_et_marquait_oublie",
     "[PIEGE] Un mot PARFAITEMENT recite, degrade par le seul tajwid, comptait comme un echec -> souffleur -> gris \"oublie\" qui ECRASE le violet",
     "`_judge` recevait le meme statut pour la COULEUR et pour `isNegative`, "
     "qui alimente `newErrors` -> `wordFailed` -> `_motsOublies` -> gris. Un "
     "mot dont lettres et harakat sont justes, degrade a `unclear` au seul "
     "titre d'une regle manquante, comptait donc comme un demi-echec : deux de "
     "suite declenchaient le souffleur. MESURE en direct (2026-08-16, session "
     "PROPRE -- app relancee, portion remise a zero, donc aucun etat perime) : "
     "`[MotsOubliesAdd] wordIndex=4 raison=mot precedent egalement en echec "
     "(deux consecutifs)` et `wordIndex=16` -- puis `[RenderTajwid] mot=16 "
     "\"ٱلصَّلَوٰةَ\" classifyError=tajwid tajwidManquant=true estOubli=true` : "
     "la couleur violette etait calculee CORRECTEMENT puis ecrasee par le gris "
     "de `if (estOubli)`, place apres tout le reste. Consigne utilisateur qui "
     "fonde le correctif : « adulte et tajweed c'est pareil sans impact du "
     "tajweed, tajweed vient en fin pour trancher ». La prononciation se juge "
     "donc a l'identique dans les deux presets ; le tajwid n'agit qu'a la fin, "
     "sur la couleur seule (`newErrors: null` quand statutBase==correct)."),

    ("piege_coach_alimente_par_le_chemin_du_souffleur",
     "[PIEGE] `logError` (le Coach) vivait sur le chemin du SOUFFLEUR : couper le faux echec coupait le Coach du meme coup",
     "`RecitationErrorLogService.logError` -- seule source des ecarts de tajwid "
     "du Coach -- n'existait que dans `_onWordFailed`, c'est-a-dire sur la voie "
     "de la correction. Le Coach etait donc alimente PAR ACCIDENT : un mot "
     "degrade par le tajwid comptait comme un echec, ce qui declenchait le "
     "souffleur ET, au passage, ecrivait dans le Coach. Corriger le faux "
     "\"oublie\" (cf. noeud precedent) a donc supprime le violet du Coach dans "
     "le meme mouvement. CONSTAT UTILISATEUR qui l'a revele, et qui montre "
     "l'inversion exacte : « avant je constate du violet dans cet ecran "
     "[Coach] et non dans ecran recitation, maintenant c'est l'inverse ». "
     "Deplace sur `wordLockedNonGreen` (flux qui recoit TOUT mot verrouille "
     "non vert, sans condition de reglage, d'anti-rafale ni de mode, et qui "
     "servait deja a archiver pour le Coach). Lecon generale : deux "
     "fonctionnalites qui n'ont aucun rapport ne doivent pas partager un "
     "canal, sinon corriger l'une casse l'autre sans qu'aucun test ne le dise."),

    ("mort_juge_v1_on_aligned",
     "[MORT] `_onAligned` -- le juge v1, 941 lignes, ne s'executait plus depuis douze jours",
     "PREUVE PAR DEUX INSTRUMENTATIONS INDEPENDANTES, sur les 32 552 lignes du "
     "journal cumule (toutes sessions depuis le 2026-08-15) : la ligne Dart "
     "`_onAligned S'EXECUTE` (posee le 2026-08-06 exactement pour trancher) "
     "vaut 0 occurrence, et le drapeau natif dit `v1Coupee=true v2Actif=true "
     "bufferedExiste=false` sur CHAQUE session. Retire avec ce qui n'existait "
     "que pour lui : `_capByRuleReliability`, `_normalizedGop`, "
     "`_cappingRules`, `_gopWordBaseline`, `_v1AlignJournalise`, `_alignSub` "
     "-- 1 044 lignes au total. DEUX MECANISMES Y DORMAIENT sans que personne "
     "le sache : l'apprentissage des durees par mot (`WordDurationStore`, cf. "
     "[EN ATTENTE] durees de reference) et le plafond par fiabilite de regle. "
     "Inertes depuis le 2026-08-04, jour ou la v2 a pris l'affichage -- meme "
     "famille de mort silencieuse que le controle tajwid et la Bismillah. "
     "`flutter analyze` propre, rejeu deterministe 2:6 sans regression."),

    ("mort_rouge_attenue_sur_error_non_verrouille",
     "[MORT] Rouge attenue sur un `error` non verrouille -- ajoute le 2026-08-15, retire le lendemain",
     "Ajoute pour combler un defaut mesure : `provisoire:rouge` est le statut "
     "FINAL d'au moins un mot dans 13 sessions sur 19, soit 16 mots finissant "
     "sans la moindre couleur. Retire le 2026-08-16 sur demande utilisateur -- "
     "trop d'etats de couleur pendant la recitation (7 recenses : vert, "
     "violet, orange, rouge franc, rouge attenue, gris, invisible). Le defaut "
     "des 16 mots sans couleur REVIENT avec ce retrait, en connaissance de "
     "cause. Effet de bord connu du mecanisme lui-meme : clignotement "
     "rouge->vert, qui avait deja fait retirer cet affichage le 2026-07-09."),

    ("en_attente_tete_tajwid_n_a_jamais_vu_d_erreur",
     "[EN ATTENTE] La tete tajwid n'a JAMAIS vu d'erreur : elle reconnait un contexte, elle ne verifie pas une realisation",
     "Constat utilisateur (2026-08-17) sur le cas `أُنزِلَ` : « si ikhfa, le "
     "texte va pas detecter le noun [...] ikhfa c'est presque le son n'est pas "
     "dit, confirme par le texte » -- l'ikhfa est determine a 100 % par le "
     "texte (noun sakin + une des 15 lettres), donc le detecter n'apporte "
     "AUCUNE information. VERIFIE dans `build_frame_level_tajwid_labels.py`, "
     "deux faits : (1) la fenetre apprise est le MOT ENTIER (`f0 = "
     "first[wstart]`, `f1 = last[wend]`), pas le son de la regle ; (2) le "
     "script dit lui-meme « les recitateurs du corpus sont professionnels [...] "
     "apprises sur de la recitation CORRECTE sans etiquetage manuel "
     "correct/incorrect » -- zero contre-exemple, jamais. Donc « regle non "
     "detectee » signifie « le modele n'a pas reconnu son motif appris », PAS "
     "« le recitateur ne l'a pas faite ». Coherent avec le residu de +28/+38 % "
     "et avec le MEME mot `أُنزِلَ` non detecte au mot 23 puis detecte au mot "
     "26 dans la meme session. PISTE UTILISATEUR, chiffree : l'IZHAR halqi "
     "(noun sakin + lettre de gorge) fournit le negatif gratuitement -- le "
     "noun y est prononce CLAIREMENT, ce qui est exactement le son de « ikhfa "
     "non realise ». Compte sur le Coran complet : 2 481 occurrences d'izhar "
     "disponibles. PIEGE A TRAITER AVANT TOUT ENTRAINEMENT : la lettre "
     "suivante differe (gorge contre 15 autres), le modele peut donc apprendre "
     "le raccourci « lettre de gorge -> negatif » au lieu de « noun clair -> "
     "negatif », avec un excellent score d'entrainement et un echec total sur "
     "le cas visé. Detail et pistes : FONCTIONNALITES_FUTURES.md §12."),

    ("regle_trace_systematique_attendu_detecte_par_mot",
     "V2tajwidDetail : la trace attendu/detecte s'ecrit MEME quand tout est correct",
     "Avant, `V2tajwid` n'ecrivait qu'en cas d'ecart. Un mot dont toutes les "
     "regles attendues sont detectees ne laissait donc AUCUNE ligne, ce qui "
     "rend indiscernables deux situations opposees : « le controle n'a jamais "
     "tourne » (`tajwidFiable=false`) et « il a tourne et n'a rien trouve a "
     "redire ». C'est exactement ce qui a bloque le diagnostic pendant une "
     "journee : l'absence de violet ne pouvait pas etre interpretee. La ligne "
     "porte desormais mot, statut, `tajwidFiable`, attendues et detectees, et "
     "ne s'ecrit que pour les mots portant une regle ACTIVE du preset."),
]

LIENS = [
    ("mort_seuil_plat_0_5_tete_tajwid", "piege_decoder_une_tete_multilabel_comme_du_ctc",
     "shares_data_with",
     "le meme commentaire posait 0,5 comme non calibrable ; la mesure le refute"),
    ("mort_seuil_plat_0_5_tete_tajwid", "en_attente_tete_tajwid_n_a_jamais_vu_d_erreur",
     "shares_data_with",
     "aucun seuil ne corrige une tache mal posee : le residu +28/+38 % vient de la"),
    ("piege_tajwid_jamais_controle_sur_mot_verrouille_par_raccourci",
     "piege_tajwid_comptait_comme_echec_et_marquait_oublie",
     "shares_data_with",
     "deux defauts du MEME controle : l'un l'empechait de tourner, l'autre le faisait accuser"),
    ("piege_tajwid_comptait_comme_echec_et_marquait_oublie",
     "piege_coach_alimente_par_le_chemin_du_souffleur",
     "shares_data_with",
     "corriger le faux echec a coupe le Coach : les deux partageaient le canal wordFailed"),
    ("mort_juge_v1_on_aligned", "piege_tajwid_comptait_comme_echec_et_marquait_oublie",
     "shares_data_with",
     "meme famille : un mecanisme cesse d'agir ou d'etre isole sans que personne le decide"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step32.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
