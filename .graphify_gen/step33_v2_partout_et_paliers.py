#!/usr/bin/env python3
"""La v2 ne tournait pas ou on la croyait, et les paliers se validaient a vide.

Mesures du 2026-08-18/19, journal de sessions live sur device (builds v146 a
v167) : comptages de lignes natives et Dart, horodatages a la milliseconde.
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_v2_activee_mais_jamais_alimentee_en_pcm",
     "[PIEGE] La v2 s'active et ne recoit AUCUN audio : `chaine parallele ACTIVE` ne prouve rien",
     "L'alimentation de la chaine v2 en PCM passe UNIQUEMENT par "
     "`_processContinuousChunk`, donc par le mode CONTINU. Tout appelant qui "
     "demarre par `start()` (non continu) obtient une v2 ACTIVEE mais affamee. "
     "MESURE sur le controle final du Coach (2026-08-18 21:10, verset 4:1) : "
     "`chaine parallele ACTIVE`=1, fenetres `[v2] f=`=0, verdicts `[V2] mot=`"
     "=0, `micro continu=false`=1, pendant que 17 verdicts `[TEXTDIFF]` et 2 "
     "`ZERO FRAME` venaient de la v1 -- dont le mot 17, jamais juge. Troisieme "
     "occurrence de la meme famille apres le palier de memorisation "
     "(2026-08-17) et le controle tajwid : un chemin ecrit pour la v1, reste "
     "en place, qui a cesse d'agir le jour ou la v2 a pris l'affichage sans "
     "que personne le decide. SIGNATURE A CHERCHER : compter `[v2] f=` et "
     "`[V2] mot=` -- une v2 activee qui n'a produit aucune fenetre est une v2 "
     "qui n'a pas tourne."),

    ("piege_v2activer_avant_chargement_du_modele",
     "[PIEGE] `v2Activer` appele avant le chargement du modele = appel sans effet, et la v1 reprend la main",
     "`v2Activer(true, cible)` etait emis avant que le modele existe cote "
     "natif : il n'y avait aucune chaine a configurer, l'appel ne faisait "
     "rien. MESURE (2026-08-19 06:15, verset 4:1, PREMIERE recitation apres le "
     "lancement de l'app) : le modele se charge PENDANT `start()` "
     "(06:15:50,13 -> 06:15:51,35), et au premier bloc PCM le natif ecrit "
     "`v2Actif=false v2Mots=0` puis `INSTANCIATION de BufferedTranscriber -- "
     "la v1 VA tourner`. Toute la session est tombee sur la v1 ; l'ecran est "
     "reste sans couleur et le score a 0 %, alors que l'audio etait "
     "parfaitement entendu (les transcriptions brutes de la v1 contiennent la "
     "recitation). INVISIBLE jusqu'ici parce que le modele reste charge d'une "
     "session a l'autre : SEULE la premiere recitation apres le lancement est "
     "touchee -- d'ou un defaut qui ne se reproduit pas quand on le cherche. "
     "Correctif : `ensureModelLoaded()` (idempotent) avant `v2Activer`."),

    ("piege_verdicts_de_cloture_postes_dans_un_flux_donc_apres_finished",
     "[PIEGE] `v2Terminer` POSTAIT ses verdicts dans un flux : livres APRES le passage a `finished`",
     "Un `add()` sur un flux est livre au tour de boucle suivant, tandis que "
     "le passage de la session a `finished` est synchrone. Tout ecran qui "
     "decide sur `finished` lisait donc l'etat d'AVANT la cloture. MESURE "
     "(2026-08-18, palier sur 80:1, deux mots) : 34,152 `[v2] session fermee : "
     "2 mot(s) finalise(s)` ; 34,157 `[Palier] fin de tour : juges=0 "
     "statuts=[current,pending]` ; 34,159 et 34,160 les deux verdicts "
     "`definitif:vert` et `provisoire:vert`. Les deux mots etaient VERTS et le "
     "palier a conclu a l'echec SEPT MILLISECONDES trop tot -- donc jamais "
     "validable, quelle que soit la recitation. Correctif : `v2Terminer` REND "
     "les verdicts, le provider les applique par le meme `_onV2` avant de "
     "clore."),

    ("piege_un_ecran_decide_sur_la_session_d_un_autre",
     "[PIEGE] `recitationProvider` est PARTAGE : un ecran qui se monte herite de la session du precedent",
     "Le controle du Coach se monte juste apres un palier reussi et y trouve "
     "encore sa session : `finished` vrai, tous les mots verts. Sa condition "
     "`controleParfait` etait donc vraie AVANT tout controle, et le passage "
     "automatique partait sur l'etat d'un autre ecran. MESURE (2026-08-18 "
     "22:13, cumul active) : 22:13:39,46 palier 1:4 -> 3 mots "
     "`definitif:vert` ; 22:13:42,13 audio du palier de 1:5 -- soit 2,67 s "
     "d'ecart, exactement le `Future.delayed(2600)` du passage automatique. "
     "L'utilisateur passait au verset suivant sans avoir rien recite. "
     "`setup()` ne protege PAS : il repasse les mots a `pending` mais dans un "
     "post-frame, donc APRES le build qui decide. Correctif : un drapeau pose "
     "au demarrage du micro -- un ecran ne decide que sur SA session."),

    ("mort_seuil_de_reussite_calcule_sur_la_fenetre_cumulative",
     "[MORT] Seuil de reussite du palier calcule sur la fenetre CUMULATIVE -- moyennable, donc contournable",
     "La fenetre d'un palier est cumulative depuis le premier mot du verset "
     "(decision 2026-08-09). Y calculer un seuil global laisse la partie DEJA "
     "ACQUISE payer pour la partie manquante, et cette partie grossit a chaque "
     "palier : le defaut s'aggrave tout seul. MESURE sur 5:1 "
     "(`finsUnite=[4,11,16,22]`) : unite 3, 10 mots juges sur 17, seuil a la "
     "moitie -> REUSSI avec ZERO mot neuf recite (les 5 mots de P3 tous "
     "`pending`). Seuil remonte aux trois quarts : sur 4:1 le 2026-08-18 "
     "19:58, `juges=13/17` donne `13x4=52 >= 51`, franchi D'UN POINT avec 2 "
     "mots neufs sur 6. Les DEUX seuils globaux echouent pour la meme raison. "
     "Retenu : evaluation UNITE PAR UNITE, couverture (3/4) et qualite (une "
     "faute sur trois) -- memes seuils qu'avant, mais plus moyennables entre "
     "paliers."),

    ("piege_plafond_d_attente_fixe_plus_court_que_l_audio_demande",
     "[PIEGE] Plafond d'attente FIXE (15 s) plus court que la lecture demandee : coupe sans un mot",
     "Le garde-fou anti-blocage des trois points de lecture de "
     "`word_correction_audio` etait borne a 15 s en dur -- juste tant que ce "
     "fichier ne servait qu'a faire reentendre UN mot (~2 s). Le palier rejoue "
     "la fenetre cumulative, qui depasse 15 s des le deuxieme palier. MESURE "
     "sur 4:1 (Al-Afasy) : P1 6,6 s demandes -> 6,6 s joues ; P2 17,1 -> 15 ; "
     "P3 26,5 -> 15 ; P4 36,0 -> 15. A partir de P2, TOUS les paliers "
     "faisaient entendre les memes 15 premieres secondes, coupees au milieu du "
     "mot 8 -- constat utilisateur : « on dirait P2 rejoue ». La troncature "
     "etait ENTIEREMENT SILENCIEUSE : ni l'asset, ni les index, ni "
     "`ayatTiming` n'etaient en cause, tout etait juste jusqu'au lecteur. "
     "Correctif : plafond proportionnel, plus une trace de ce qui a REELLEMENT "
     "ete joue a chaque tour."),

    ("piege_position_perimee_du_lecteur_prise_pour_la_nouvelle",
     "[PIEGE] Position PERIMEE du lecteur prise pour la nouvelle : la lecture se coupe avant de commencer",
     "`audioplayers` continue d'emettre la derniere position connue pendant "
     "l'instant ou un repositionnement n'a pas encore pris effet. Le test de "
     "fin `pos >= endMs` etait donc vrai immediatement au rejeu. MESURE "
     "(2026-08-18) : `joue verset=4:1 mots=0..23 demande=37040 ms reel=2 ms` "
     "-- le rejeu apres echec ne faisait entendre STRICTEMENT RIEN. Le defaut "
     "existait depuis toujours et n'a ete vu que le jour ou une trace a "
     "compare le reel au demande. Correctif : n'autoriser le test de fin "
     "qu'apres avoir OBSERVE une position tombee dans la fenetre demandee."),

    ("piege_ensure_loaded_rend_la_main_sans_attendre_le_chargement_en_cours",
     "[PIEGE] `ensureLoaded()` en `if (_x != null || _chargement) return;` : le second appelant lit du vide",
     "Cette forme rend la main IMMEDIATEMENT au second appelant pendant que le "
     "premier charge encore -- il lit alors une donnee vide sans le savoir. "
     "MESURE : `ABANDON (MP3Quran) verset=80:1 : minutage local absent "
     "(segments=null)` alors que 80:1 EST dans l'asset ; `prefetch()` amorcait "
     "le chargement et `_startRound` rappelait 100 ms plus tard sans rien "
     "attendre -- le palier demarrait son ecoute sans que l'utilisateur ait "
     "entendu le recitateur. Present a l'identique dans "
     "`Mp3QuranWordSegments` ET `CoupesPalierService` (celui-ci decide du "
     "DECOUPAGE des paliers : sans chargement, un verset entier en une seule "
     "unite). Correctif : memoriser le Future en cours, tout le monde attend "
     "le meme."),

    ("piege_compteurs_de_score_tenus_par_le_seul_chemin_v1",
     "[PIEGE] `accuracy` et `score` lisent des compteurs que SEUL le chemin v1 tenait a jour",
     "`_onV2` n'ecrivait que `words`. Or `accuracy`/`score` ne se derivent pas "
     "de `words` : ils lisent `correctCount`/`unclearCount`/`errorCount`, "
     "alimentes par `_onStructured` (v1) uniquement. Toute session jugee par "
     "la v2 affichait donc 0 % -- y compris le bilan de fin de l'ecran de "
     "recitation, bien avant que le controle du Coach ne le rende visible. "
     "VERIFIE apres correctif sur 2:2 : 6 verts + 1 orange sur 7 mots -> "
     "(6 + 0,5)/7 = 92,86 % affiche 93 %. Recalcul complet a chaque passe et "
     "non increment : un verdict v2 peut CORRIGER un mot deja juge, un "
     "compteur incremente ne saurait pas defaire l'ancien."),

    ("piege_ref_apres_demontage_dans_les_methodes_d_archivage",
     "[PIEGE] `ref` lu apres demontage dans l'archivage : le dernier mot est vert a l'ecran et absent du Coach",
     "`_container` avait ete introduit le 2026-08-14 pour que la cloture "
     "d'archive n'ait « plus jamais besoin de `ref.read` », mais n'avait ete "
     "branche que sur `_comptabiliserPourCoach` ; les QUATRE methodes "
     "d'archivage lisaient encore `ref`. MESURE (session 62 du 2026-08-18, "
     "Al-Fatiha complete) : le mot 28 (le dernier) est `provisoire:vert` puis "
     "`archivage mot non juge impossible mot=28 : Bad state: Cannot use ref "
     "after the widget was disposed`. Ce n'est PAS un hasard que ce soit le "
     "DERNIER mot : c'est celui qui a le plus de chances d'etre encore "
     "`provisoire` (aucune observation suivante) donc de passer par le scanner "
     "de fin, et c'est aussi le moment ou l'ecran se demonte -- les deux "
     "conditions se concentrent sur lui, d'ou le « toujours » du constat."),

    ("piege_enchainement_saute_la_fin_de_la_page_courante",
     "[PIEGE] L'enchainement va a `page + 1` sans finir la page courante : les sourates du milieu sont enjambees",
     "MESURE (2026-08-18, session 75) : depart `sourate=106 1-4` (Quraysh, "
     "cible 21 mots), puis `enchainement vers la/les sourate(s) 109,110,111 "
     "(page 603)`. Quraysh occupe le MILIEU de la page 602 ; Al-Ma'un (107) et "
     "Al-Kawthar (108) sont sur cette meme page, APRES elle, et etaient "
     "enjambees -- la premiere sourate enchainee devenait Al-Kafirun. Frappe "
     "TOUTE sourate qui n'est pas la derniere de sa page. Deux pieges dans le "
     "correctif : filtrer sur « non deja charge » NE SUFFIT PAS (une page "
     "contient aussi les sourates qui PRECEDENT le depart -- regression "
     "introduite et corrigee le meme jour : Al-'Asr apparaissait apres "
     "Al-Fil), il faut ne garder que l'AVAL et re-trier."),

    ("piege_fin_de_playlist_change_l_etat_sans_arreter_le_son",
     "[PIEGE] Fin de playlist : le statut passe a `idle` mais le lecteur continue de jouer",
     "Avec MP3Quran la source est le fichier de la SOURATE ENTIERE, et le "
     "minuteur de frontiere ne fait qu'EMETTRE un signal de fin -- il ne "
     "touche pas au lecteur. En fin de playlist, `_advance()` se contentait de "
     "`state.copyWith(status: idle)` : le son enchainait sur le verset suivant "
     "pendant que l'app se croyait a l'arret. INVISIBLE dans le Mushaf, ou la "
     "playlist a toujours un verset apres ; visible des qu'elle n'en contient "
     "QU'UN -- l'etape Lecture du Coach. `pause()` et non `stop()` : `stop()` "
     "ferme le flux et obligerait a rouvrir le gros fichier au verset "
     "suivant."),
]

LIENS = [
    ("piege_v2_activee_mais_jamais_alimentee_en_pcm",
     "piege_v2activer_avant_chargement_du_modele", "shares_data_with",
     "deux facons d'obtenir une v2 activee qui ne juge rien : pas de PCM, ou pas de modele"),
    ("piege_v2activer_avant_chargement_du_modele",
     "piege_compteurs_de_score_tenus_par_le_seul_chemin_v1", "shares_data_with",
     "la v1 reprend la main, mais son chemin de peinture n'existe plus : ecran vide et 0 %"),
    ("piege_verdicts_de_cloture_postes_dans_un_flux_donc_apres_finished",
     "piege_un_ecran_decide_sur_la_session_d_un_autre", "shares_data_with",
     "meme famille : decider sur un etat qui n'est pas encore, ou n'est deja plus, le sien"),
    ("mort_seuil_de_reussite_calcule_sur_la_fenetre_cumulative",
     "piege_verdicts_de_cloture_postes_dans_un_flux_donc_apres_finished",
     "shares_data_with",
     "les deux faisaient echouer le palier sur une recitation juste, par des voies opposees"),
    ("piege_plafond_d_attente_fixe_plus_court_que_l_audio_demande",
     "piege_position_perimee_du_lecteur_prise_pour_la_nouvelle", "shares_data_with",
     "deux troncatures muettes du meme lecteur, revelees par la meme trace reel/demande"),
    ("piege_ensure_loaded_rend_la_main_sans_attendre_le_chargement_en_cours",
     "piege_v2activer_avant_chargement_du_modele", "shares_data_with",
     "meme forme : agir avant qu'une ressource asynchrone soit prete, sans l'attendre"),
    ("piege_v2_activee_mais_jamais_alimentee_en_pcm",
     "mort_juge_v1_on_aligned", "shares_data_with",
     "un chemin ecrit pour la v1 reste en place et cesse d'agir sans que personne le decide"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step33.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
