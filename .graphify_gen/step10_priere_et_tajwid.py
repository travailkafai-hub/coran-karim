#!/usr/bin/env python3
"""Enrichit le graphe avec ce que les 2026-09-07 et 09-08 ont MESURE.

Trois chantiers, tous instruits par des chiffres releves sur device ou sur
corpus, jamais par l'intention :

  1. le mode PRIERE -- pourquoi le suivi s'arretait, pourquoi le souffleur se
     taisait, et pourquoi il a fini par souffler au mauvais endroit ;
  2. les MADD -- trois grandeurs candidates pour distinguer 2, 4 et 6 harakat,
     les trois refutees, chacune avec sa mesure ;
  3. les DEUX TETES tajwid (famille 11 / fine 76) -- ce que leur confrontation
     apporte reellement, sur corpus PUIS sur recitation reelle.

REGLE PROJET RESPECTEE : on n'ecrase rien, le graphe precedent est copie dans
graphify-out/graph_avant_priere.json avant ecriture.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

# ── Les noeuds ────────────────────────────────────────────────────────────
# `rationale` porte LA MESURE, jamais l'intention.

NOEUDS = [
    # ═══ MODE PRIERE ═════════════════════════════════════════════════════
    ("piege_minuteur_sur_signal_lent",
     "[PIEGE] Un minuteur cable sur un signal plus lent que son propre seuil",
     "TOMBE DEUX FOIS EN UN JOUR (2026-09-07). Le retour en attente du mode "
     "priere (8 s) etait nourri par le DECODAGE LIBRE, qui se tait des que la "
     "cible est posee : il expirait donc 8 s apres CHAQUE pose de cible, "
     "recitation en cours ou non -- Al-Fatiha revenait a l'ecran au bout de "
     "8 s. Recable sur les VERDICTS, il est reparti quand meme : mesure des "
     "trois signaux sur une session reelle -- verdict mediane 2,47 s / p90 "
     "8,19 s ; fenetre localisee 0,37 s / p90 4,17 s ; niveau micro < 0,1 s. "
     "Le p90 des verdicts EST le seuil. Preuve directe : les verdicts 318-320 "
     "sont tombes 6 ms APRES l'expiration, sur 9,71 s dont 8,00 s d'audio recu "
     "(18 % de silence, les respirations). REGLE : un minuteur se nourrit du "
     "signal le plus RAPIDE disponible, jamais d'un signal dont le pire cas "
     "normal atteint son seuil."),

    ("piege_minuteur_pendant_le_souffle",
     "[PIEGE] Tout minuteur nourri par le micro doit se taire quand le "
     "haut-parleur parle",
     "TOMBE TROIS FOIS (2026-09-07 et 09-08). `pauseCapture()` coupe le micro "
     "pendant la lecture du souffleur : le niveau tombe a zero, et TOUT "
     "minuteur nourri par lui expire mecaniquement. Constate successivement "
     "sur le retour en attente (30 s), le silence court (3 s) et le compteur "
     "« rien ne se place » (6 s). Le dernier cas est le plus net : 21:21:46,47 "
     "DECROCHAGE, 21:21:47,48 souffle du passage 35..35, 21:21:53,48 « 6s sans "
     "reussir a placer un seul mot -> ruku' » -- le message accusait le "
     "recitant alors que c'est le souffleur qui parlait. Un souffle de 49 mots "
     "a ete mesure a 16,4 s."),

    ("mesure_souffleur_fabrique_ses_decrochages",
     "[MESURE] Le souffleur fabriquait les decrochages suivants",
     "MESURE (session 17:43, build v376) : 16,4 s sans une seule fenetre "
     "pendant que le souffleur joue 49 mots, puis l'audio empile digere D'UN "
     "BLOC en fenetres de 7,92 / 8,88 / 10,64 s. Ces fenetres ENJAMBENT 25 puis "
     "78 mots, produisant deux « passages non entendus » qui n'etaient pas des "
     "sauts du recitant -- et donc deux souffles de plus, le troisieme refuse "
     "parce que le deuxieme jouait encore. Corrige en purgeant le flux de "
     "travail AVANT la reprise du micro (`repartirApresSouffle`)."),

    ("regle_le_trou_se_fonde_sur_l_exact",
     "[REGLE] Un trou est une ACCUSATION : il se fonde sur l'exact, pas sur le "
     "normalise",
     "MESURE (session 2026-09-08, 21:03) : l'utilisateur s'etait TU et "
     "attendait d'etre souffle. 21:03:53,85 mot 16 definitif:vert (son dernier "
     "mot) ; 21:03:54,92 f=4 bande=20..21 conf=0,50 interieurs=0/2 -> trou de "
     "4 mots MIS EN ATTENTE ; 21:03:59,60 souffleur sur les mots 17..20. Les "
     "blocs PCM montrent le portier jetant l'audio au meme instant : la bande "
     "etait posee SUR DU SILENCE. Le mot 48 a meme ete juge definitif:vert "
     "alors que rien n'etait prononce. Applique le principe deja ecrit dans "
     "`Localisateur.Bande` (2026-07-30) : « normaliser pour TROUVER, comparer "
     "exactement pour CONFIRMER » -- le mot qui fonde le trou doit etre dans "
     "`attestesExacts`. Mode priere seul (`sautLibre`)."),

    ("regle_aide_sur_silence_reel",
     "[REGLE] L'aide se declenche sur le SILENCE REEL, pas sur le pointeur",
     "MESURE (session 2026-09-08, 21:03) : le souffleur d'hesitation (4 s) se "
     "remet a zero a chaque avancee du POINTEUR. Un faux placement pose sur du "
     "silence l'a donc REARME, et il n'a jamais pu partir -- le mecanisme cense "
     "secourir le recitant a ete desarme par le defaut lui-meme. Le niveau "
     "micro, lui, se mesure EN AMONT de toute localisation : il ne peut pas "
     "etre efface par un placement errone. Rejoue sur la session, l'aide "
     "serait partie a 21:03:56,85 (3 s de silence) au lieu de 21:03:59,60, et "
     "sur le mot 16 au lieu des mots 17..20 fabriques."),

    ("mesure_point_daide_apres_le_trou",
     "[MESURE] Le souffleur soufflait le verset SUIVANT le passage oublie",
     "MESURE ChGPT (session 2026-09-08, An-Nisa, build v379) : trou 72..85 "
     "(les 14 mots de 4:4) mis en attente, mais `pointDeReprise()` rend "
     "`maxOf(dernierDefinitif=70, dernierAttesteVu=86)` = 86, et le pont Dart "
     "ajoute 1 -> 87, premier mot de 4:5. Le recitant n'avait pas dit 4:4 et on "
     "lui a joue 4:5. Une attestation AU-DELA d'un trou n'est pas une preuve "
     "que les mots precedents ont ete reconnus : 72 et 73 etaient restes "
     "provisoire:rouge, 74..85 sans aucun verdict. Corrige par un `pointDAide()` "
     "distinct, conditionne au mode priere -- `pointDeReprise()` est laisse "
     "intact, le remplacer globalement reintroduirait les retards d'aide de "
     "l'ete. 8 tests JUnit (`ChaineRecitationPriereTest`), Hafs et Warsh."),

    ("mort_reidentification_sur_decrochage",
     "[MORT] Relancer une identification complete sur decrochage persistant",
     "REFUSEE PAR L'UTILISATEUR LE JOUR MEME (2026-09-07), et il a raison sur "
     "le fond : EN PRIERE L'IMAM NE SAUTE PAS. Le mecanisme etait bati sur un "
     "cas que la salat ne produit pas. Le saut libre couvre un trou de CAPTURE "
     "(« c'est un micro, il se peut qu'il ne detecte pas la voix, ce sont des "
     "sauts VIRTUELS, il n'a pas saute »), pas un imam qui change de passage. "
     "Remplace par le repli sur les CANDIDATS GARDES : `locateTopMatches(k=20)` "
     "en ramenait vingt et n'en gardait qu'un ; les concurrents d'une autre "
     "sourate restent desormais a cote, sans relancer aucune recherche."),

    # ═══ LES MADD ════════════════════════════════════════════════════════
    ("mort_duree_du_pic_pour_les_madd",
     "[MORT] La duree du pic de detection pour distinguer les types de madd",
     "MESURE SUR 377 SESSIONS DEVICE dedoublonnees, maximum par (session, mot) "
     "-- donc deja le meilleur de toutes les coupes, comme `dureesParMot` : "
     "madda_necessary (6 harakat) n=104 mediane 160 ms, 47,1 % encore a 80 ms ; "
     "madda_obligatory (4-5) n=637 mediane 240 ms ; madda_permissible (4-6) "
     "n=600 mediane 240 ms. L'ORDRE EST INVERSE -- le madd le plus long est "
     "mesure le plus court -- et un tiers a la moitie des mots plafonnent a UNE "
     "SEULE FRAME. Cause : `DetectedRule.frames` compte les frames ou la TETE "
     "emet sa classe, c'est la largeur du PIC, pas la duree du son. Cout d'un "
     "seuil pose dessus, sur des madd CORRECTS : 240 ms en rejette 23 a 44 %, "
     "320 ms en rejette 48 a 61 %. Aucune fenetre utile."),

    ("mort_tenue_de_voyelle_pour_les_madd",
     "[MORT] La tenue de voyelle (`Decodage.tenueMax`) pour distinguer les madd",
     "MESURE PC A (2026-09-07), `tenue_max` sur une fenetre de +/-0,5 s centree "
     "sur l'ancre reelle, 70 exemples par type : madda_necessary mediane 1 "
     "(moyenne 1,16), madda_obligatory 1 (1,21), madda_permissible 2 (1,44). "
     "ORDRE INVERSE, comme la duree du pic. Et recentrer strictement sur "
     "l'ancre REND L'INVERSION PLUS NETTE, pas plus faible -- ce n'est donc pas "
     "un artefact de fenetrage. La grandeur est conservee en journal "
     "(`[tajwidTenue]`, observation seule) mais ne distingue pas les types."),

    ("mesure_tete3_insensible_au_madd_court",
     "[MESURE] La tete 3 ne voit pas un madd volontairement raccourci",
     "MESURE sur test delibere de l'utilisateur (2026-09-07, build v378) : il "
     "recite en raccourcissant les madd. Tete 3 : 217 evaluations, 74 "
     "abstentions, 200 « ok » contre 17 DEVIATION_SUSPECTEE. Sur les mots a "
     "madd : logit min median -10,67 quand le madd EST fait, -11,67 quand il ne "
     "l'est PAS -- donc legerement MOINS suspect, a l'envers. Deviations 3/26 "
     "contre 5/32, indiscernables. Ses madd raccourcis (لآ -6,90, يرهو -15,48) "
     "sont parmi les MOINS signales. Confirme sur un cas cible le noeud "
     "existant « la tete 3 n'apporte RIEN sur le modele de l'app » (21,5 % "
     "contre 24,2 % pour la regle ecrite a la main, z=0,55). n=6 par groupe."),

    ("mesure_madda_normal_violet_permanent",
     "[MESURE] `madda_normal` faisait 41 % des violets, sans preuve possible",
     "MESURE sur tous les journaux device, logique EXACTE de "
     "`unrealizedRulesFor` (regles portees par le texte ecartees, groupe des "
     "quatre madd applique) : madda_normal 163 violets sur 399 au total, soit "
     "41 %. Aucune des deux tetes ne peut fonder ce verdict -- FAMILLE : seuil "
     "1,1 dans seuils_tajwid.json (probabilite > 1, infranchissable) et canal "
     "ONNX CONSTANT (0 sur v7, -20 sur le paquet 5 tetes) ; FINE : classes "
     "eclatees par LETTRE (madd__ا, madd__و...), jamais par statut juridique. "
     "Le filet du 2026-09-05 (les quatre madd interchangeables) fonctionne et "
     "avait deja fait tomber le compte de 271 a 163. Remise dans "
     "`porteesParLeTexte` sur decision utilisateur. COUT ASSUME : un madd "
     "normal reellement raccourci n'est plus signale."),

    ("attente_corpus_de_fautes_tajwid",
     "[EN ATTENTE] Aucun corpus de fautes tajwid reellement prononcees",
     "Le rapport de validation des deux tetes le dit lui-meme : "
     "`not_measured: \"faute de tajwid reellement prononcee (aucun corpus "
     "d'erreurs acoustiques valide)\"`. TOUTES les mesures de rappel portent "
     "sur des regles CORRECTEMENT realisees. Sans un seul exemple de faute, "
     "aucun seuil ne peut etre pose sur aucune grandeur : on ne sait pas ou "
     "couper. Preliminaire PC A sur 6 exemples de madd raccourcis : la "
     "detection ne bouge quasiment jamais (donc l'issue « le probleme se "
     "resout tout seul » est ECARTEE), la tenue bouge 2 fois sur 6 -- rien ne "
     "tranche a ce n. Decision utilisateur 2026-09-07 : ne pas fabriquer le "
     "corpus, observer en phase recette (`[tajwidTenue]` s'ecrit deja)."),

    # ═══ LES DEUX TETES TAJWID ═══════════════════════════════════════════
    ("mesure_intersection_des_deux_tetes",
     "[MESURE] L'intersection des deux tetes divise l'invention par 6 a 8",
     "MESURE PC A (2026-09-07), 400 fenetres reelles, 4 voix d'evaluation "
     "disjointes, les DEUX tetes lues sur le MEME modele et les MEMES "
     "fenetres : madd rappel union 93,5 % / inter 81,2 %, invention union "
     "11,8 % / inter 1,9 % ; qalaqah 96,2/80,8 et 4,9/0,9 ; idgham_ghunnah "
     "88,1/81,4 et 2,3/0,3. ~12 points de rappel pour 6 a 8 fois moins "
     "d'invention. C'est le bon echange ICI : une regle INVENTEE accuse le "
     "recitateur d'une faute qu'il n'a pas faite, une regle manquee le laisse "
     "seulement sans retour."),

    ("mesure_fine_seule_moins_bonne_que_famille",
     "[MESURE] La tete fine SEULE est moins bonne que la tete famille",
     "MESURE sur le meme jeu (11 823 fenetres, 9 351 positives, 4 voix), "
     "rappel par famille au seuil brut 0,5, fine remontee a ses familles : "
     "famille meilleure sur 8 familles sur 11, egalite sur 3, la fine ne gagne "
     "franchement nulle part. Macro 79,9 % (fine) contre 86,4 % (famille). Les "
     "pires : idgham_wo_ghunnah -19,3 pts, qalaqah -14,7. Eclater 1 264 "
     "fenetres `idgham_ghunnah` sur 25 classes coute cher. Son SEUL avantage "
     "propre est l'invention, deux fois moindre (8,9 % contre 14,9 %) -- ce qui "
     "en fait une bonne CONFIRMATION et une mauvaise remplacante."),

    ("mesure_accord_des_tetes_sur_device",
     "[MESURE] Sur recitation reelle, les deux tetes s'accordent a 80,2 %",
     "MESURE sur device (2026-09-07, build v378), 61 mots portant des regles : "
     "accord 150, famille seule 37, fine seule 46 -> 80,2 % de ce que la "
     "famille detecte est confirme par la fine. Le PC A trouvait ~81 % de "
     "rappel d'intersection sur 400 fenetres de corpus et 4 voix "
     "professionnelles : DEUX PROTOCOLES INDEPENDANTS, meme resultat. Par "
     "famille : qalaqah 90,7 %, madd 77,8 %, ikhafa 61,9 %. RESERVE : croise "
     "avec les regles attendues par le texte, l'intersection ecarte 19 regles "
     "attendues pour 18 non attendues (49 %) -- sur device elle n'a donc pas "
     "montre le gain qu'elle donne sur corpus. Une seule session, seuils de la "
     "tete fine non calibres (ln 0,5 faute de mieux)."),

    ("mesure_quantification_int8_sure",
     "[MESURE] La quantification int8 ne change presque aucune decision",
     "MESURE PC A (2026-09-07) sur 400 fenetres de PAROLE REELLE, int8 contre "
     "FP32 : bascule de decision tajwid famille 0,138 %, tajwid fine 0,049 %. "
     "Une mesure prealable sur BRUIT GAUSSIEN donnait un ecart median de 3,55 "
     "en log-probabilite sur la tete fine (facteur ~35 en probabilite) -- "
     "majorant pessimiste, le modele etant hors distribution donc dans le pire "
     "regime pour int8. REGLE : une parite de quantification se mesure sur de "
     "la parole, et ce qui compte est le taux de BASCULE au seuil, pas l'ecart "
     "de log-prob."),

    ("piege_encodeur_partage_a_verifier",
     "[PIEGE] « Meme encodeur » ne se suppose pas, il se hache",
     "Le LISEZ_MOI du transfert l'exigeait explicitement (« a reverifier pour "
     "ces deux checkpoints, ne pas supposer »). Verifie par SHA-256 des 692 "
     "tenseurs de l'encodeur, DEUX methodes independantes : encodeur exporte, "
     "encodeur d'entrainement de la tete FAMILLE (v7) et de la tete FINE "
     "donnent le meme hash (900a142d2b585d3c ; f7e7669f02dc8191 par la seconde "
     "methode). Corollaire verifie aussi pour `encoder_state`, donc les "
     "calibrations tete 3 fournies sont valables pour ce pack. Au passage : le "
     "champ `description` des tete3_*.json annoncait a tort « conjoint12 », une "
     "chaine codee en dur depuis le 2026-08-21 -- metadonnee fausse corrigee, "
     "donnees toujours justes."),

    ("piege_deux_packs_incompatibles",
     "[PIEGE] Deux packs dans le meme dossier, et ils ne sont pas "
     "interchangeables",
     "VERIFIE canal par canal en remontant le `Concat` de sortie ONNX : "
     "`modele_production_maddunion_4tetes` a 11 canaux et les trois madd "
     "FUSIONNES (canal 0 duplique sur madda_necessary/obligatory/permissible) ; "
     "`modele_production_5tetes` a 13 canaux et les trois madd SEPARES (canaux "
     "0, 1, 2). Le pack 5 tetes n'embarque donc PAS la tete `madd-union` : sa "
     "tete famille est celle de v7. Consequence directe : le risque « un madd "
     "de 2 harakat valide la ou on en attend 6 » ne se pose pas avec ce pack. "
     "J'avais moi-meme ecrit l'inverse en verifiant le mauvais pack -- l'ordre "
     "interne et l'ordre `rules.json` NE COINCIDENT PAS, tout mapping doit "
     "passer par le NOM, jamais par l'index."),

    ("piege_stockage_interne_pour_les_modeles",
     "[PIEGE] Un modele pousse en storage EXTERNE n'est pas vu par l'app",
     "MESURE (2026-09-07) : les dix fichiers du pack pousses par `adb push` "
     "dans `/storage/emulated/0/Android/data/<pkg>/files/models/`, `ls` les "
     "montre -- et le journal dit `verif storage externe : ... existe=false`. "
     "Scoped storage : les fichiers ecrits par `adb shell` appartiennent a "
     "`shell`, l'app ne les voit pas meme en rw-rw-rw-. Le commentaire du code "
     "decrivait deja ce symptome. Solution : `run-as <pkg> cp` vers "
     "`files/models/`, les fichiers appartiennent alors a l'app."),

    ("piege_tag_de_build_remplace_par_motif",
     "[PIEGE] Remplacer le tag de build par motif echoue en silence",
     "TOMBE LE 2026-09-07 : trois `sed` successifs sur `_kBuildTag`, chacun "
     "cherchant le motif que le precedent avait deja remplace -- les deux "
     "derniers n'ont RIEN fait, sans erreur. L'APK installe portait "
     "`v377-oublier-apres-souffle` alors qu'il contenait le code des cinq "
     "tetes. C'est exactement le piege que le superviseur interdit (« v8 mesure "
     "sous l'etiquette v23, pendant des heures »). Rattrape avant toute mesure. "
     "REGLE : verifier le tag APRES l'avoir change, et le confirmer dans le "
     "journal du device apres installation."),
]

# ── Les liens ─────────────────────────────────────────────────────────────
LIENS = [
    ("piege_minuteur_sur_signal_lent", "couche_v2_g_decision", "nait_dans", None),
    ("piege_minuteur_pendant_le_souffle", "piege_minuteur_sur_signal_lent",
     "precise", "meme famille de defaut : le signal qui nourrit le minuteur "
     "disparait au moment ou il compte"),
    ("mesure_souffleur_fabrique_ses_decrochages", "couche_v2_b_fenetres",
     "nait_dans", None),
    ("regle_le_trou_se_fonde_sur_l_exact", "couche_v2_d_localisation",
     "nait_dans", None),
    ("regle_le_trou_se_fonde_sur_l_exact", "regle_pas_de_verdict_sur_entendu_vide",
     "reprend", "meme exigence de preuve, appliquee au trou plutot qu'au mot"),
    ("regle_aide_sur_silence_reel", "piege_minuteur_sur_signal_lent", "reprend",
     "meme lecon : choisir le signal le plus proche de la realite mesuree"),
    ("mesure_point_daide_apres_le_trou", "couche_v2_d_localisation", "mesure", None),
    ("mort_reidentification_sur_decrochage", "couche_v2_d_localisation",
     "nait_dans", None),
    ("mort_duree_du_pic_pour_les_madd", "couche_v2_g_decision", "nait_dans", None),
    ("mort_tenue_de_voyelle_pour_les_madd", "mort_duree_du_pic_pour_les_madd",
     "reprend", "seconde grandeur tentee pour le meme probleme, meme symptome : "
     "ordre inverse entre les types de madd"),
    ("mesure_tete3_insensible_au_madd_court", "mort_tenue_de_voyelle_pour_les_madd",
     "reprend", "troisieme grandeur tentee, meme conclusion"),
    ("mesure_madda_normal_violet_permanent", "couche_v2_g_decision", "mesure", None),
    ("attente_corpus_de_fautes_tajwid", "mort_duree_du_pic_pour_les_madd",
     "precise", "ce qui manque pour poser un seuil sur n'importe quelle grandeur"),
    ("mesure_intersection_des_deux_tetes", "couche_v2_g_decision", "mesure", None),
    ("mesure_fine_seule_moins_bonne_que_famille", "mesure_intersection_des_deux_tetes",
     "precise", "pourquoi la fine est une confirmation et non une remplacante"),
    ("mesure_accord_des_tetes_sur_device", "mesure_intersection_des_deux_tetes",
     "precise", "le meme resultat par un protocole independant, avec sa reserve"),
    ("piege_encodeur_partage_a_verifier", "couche_v2_c_front", "nait_dans", None),
    ("piege_deux_packs_incompatibles", "couche_v2_c_front", "nait_dans", None),
    ("piege_stockage_interne_pour_les_modeles", "couche_v2_c_front", "nait_dans", None),
]


def sha(ref="HEAD"):
    try:
        return subprocess.run(["git", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    existants = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid in existants:
            print(f"  = deja present : {nid}")
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "SUIVI_PRIERE.md", "source_location": None,
            "source_url": None, "captured_at": "2026-09-08", "author": None,
            "contributor": None, "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower(),
        })
        ajoutes += 1

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel, pourquoi in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            continue
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": pourquoi, "rationale": pourquoi,
        })
        aretes += 1

    shutil.copy2(GRAPHE, SORTIE / "graph_avant_priere.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
