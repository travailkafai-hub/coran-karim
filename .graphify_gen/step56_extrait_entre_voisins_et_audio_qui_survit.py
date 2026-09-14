#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""2026-09-11 au 2026-09-14 : madda_normal enfin detectee, l'extrait deduit de
deux voisins surs, et l'audio qui ne s'arretait jamais parce que `dispose()`
n'arrivait jamais."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_madda_normal_detecteur_reel_pack_production_v2",
     "[MESURE] madda_normal a un VRAI detecteur pour la premiere fois : 83,2 % de rappel, 13,1 % de fausses detections -- 14 canaux app alimentes sur 17, contre 13",
     "Pack `transfert_2026-09-11_production_v2` recu de PC A (commit 5b63fdb). "
     "La tete famille passe a `madd-union-plus-normal-v1`, 12 classes ; "
     "jusque-la `madda_normal` etait une CONSTANTE a -20 en permanence, donc "
     "un canal mort qui ne pouvait rien porter. Mesure annoncee au seuil brut : "
     "83,2 % de rappel pour 13,1 % de fausses detections. La tete fine passe a "
     "80 classes, cablee a AUCUN verdict (observation seule, 5e sortie). "
     "Encodeur, Hafs et Warsh inchanges. "
     "CE QUI DISTINGUE CE PACK DE CELUI DU 2026-09-08, dont l'integration avait "
     "du etre annulee le matin meme : celui-la portait dans son LISEZ_MOI « pas "
     "encore autorise a l'export applicatif » et etait HAFS SEUL. Verifications "
     "faites avant integration, pas seulement lues : entree `audio_signal` "
     "confirmee par onnxruntime (piege du projet, tombe deux fois), cinq sorties "
     "conformes, `seuils_tajwid.json` coherent (madda_normal a 0,5 et non 1,1), "
     "puis sur device `modele charge=true`, `tete tajwid : OUI (17 classes)` et "
     "`regles=14(...,madda_normal,...)` au journal."),

    ("piege_deux_packs_de_modeles_dans_le_meme_aab",
     "[PIEGE] Laisser l'ancien pack de modeles dans le model_pack : 354 Mo d'AAB au lieu de 221, sans qu'aucune ligne de code ne le dise",
     "Constate au 2026-09-11 en integrant `production_v2` : le pack "
     "`cinq-tetes-2026-09-07` etait encore present. Rien ne le signale -- le "
     "code charge un sous-dossier NOMME, les autres dorment et sont quand meme "
     "empaquetes. Ecart mesure : 354 Mo contre 221, soit +60 %, pour un modele "
     "que plus personne ne charge. Meme gras que les deux modeles vestiges "
     "nettoyes le meme jour. "
     "L'ancien pack est DEPLACE hors du projet, jamais supprime (regle : aucune "
     "piste eliminee tant que le retour arriere est possible) et le .onnx "
     "d'origine reste dans son dossier de transfert. "
     "A VERIFIER A CHAQUE ENVOI DE PC A : le poids de l'AAB dit s'il reste un "
     "pack orphelin, plus surement qu'une relecture du code."),

    ("regle_extrait_deduit_de_deux_voisins_juxtaposes",
     "[REGLE] Un mot sans position fiable MAIS encadre de deux voisins JUXTAPOSES surs rend quand meme un extrait : l'intervalle entre eux",
     "Decision utilisateur (2026-09-12) : « si position non fiable, les deux "
     "mots juxtaposes sont fiables, donc le son entre ces deux mots c'est le "
     "son du mot ». `ChaineRecitation.entreLesVoisins`, repli de `voixSurPlage`. "
     "CE QUE LE JOURNAL MONTRAIT (An-Nasr, build v425) : mot 4 definitif:vert/INT, "
     "mot 5 OMIS bord/sansCreneau, mot 6 definitif:vert/INT. Le mot muet etait "
     "encadre de deux positions sures -- et c'est justement le mot qu'on veut "
     "entendre. "
     "POURQUOI CELA NE REOUVRE PAS LE DEFAUT DU 2026-08-14 (extraits de 12,10 s "
     "et 15,62 s tombant sur un AUTRE passage) : ce defaut venait de l'UNION "
     "d'observations ELOIGNEES pour un mot bel et bien prononce. Ici aucune "
     "union : deux mots adjacents ne peuvent enfermer qu'un seul mot. Le refus "
     "sec reste entier pour tous les autres cas. "
     "TROIS REFUS, silencieux (l'appelant journalise) : un voisin sans position "
     "fiable, un intervalle au-dela de PLAGE_MAX_ECH (8 s -- une pause ou un "
     "decrochage s'est glisse la), et on rend `null` PLUTOT QUE DE ROGNER, "
     "parce que rogner reviendrait a deviner de quel cote du trou le mot se "
     "trouve. Marge de 0,4 s de chaque cote, et non les 0,25 s de `voixSurPlage` : "
     "ici la marge n'est pas un rattrapage du piquage CTC, elle est le SEUL "
     "contenu audible quand le trou est court."),

    ("regle_le_silence_entre_deux_voisins_est_la_reponse_pas_une_panne",
     "[REGLE] Quand les deux voisins se touchent, on rend la jonction et non `null` : le vide EST le resultat cherche, pas un defaut de l'application",
     "Demande utilisateur (2026-09-12) : « peut-etre c'est vraiment omis et du "
     "coup il n'y aura rien [...] si le decoupage montre qu'il y avait rien, ca "
     "veut dire qu'il y avait rien ». "
     "Rendre `null` sur un intervalle vide ou negatif afficherait « Audio plus "
     "disponible » -- un message de PANNE la ou l'absence est la reponse. "
     "`entreLesVoisins` rend donc le point de jonction elargi de la marge : le "
     "recitateur ENTEND qu'il est passe d'un mot a l'autre sans rien entre les "
     "deux, ce qui confirme l'omission au lieu de laisser croire a un bug. "
     "Portee generale : une absence mesuree et une panne ne doivent jamais "
     "produire le meme message a l'ecran -- sinon toute omission correctement "
     "detectee est lue comme un defaut du produit."),

    ("piege_un_ecran_dans_un_indexedstack_ne_recoit_jamais_dispose",
     "[PIEGE] L'audio d'entrainement continuait apres changement d'onglet : l'ecran coupe bien son audio dans `dispose()`, mais `dispose()` N'ARRIVE JAMAIS",
     "Bug signale par l'utilisateur le 2026-09-14 : « au lancement de l'audio, "
     "si je bascule sur autre chose, l'audio continue, il doit s'arreter ». "
     "LA CAUSE N'EST PAS DANS L'ECRAN. `coach_incremental_repeat.dart` coupait "
     "deja `WordCorrectionAudio` dans son `dispose()` -- correct et inutile : "
     "les CINQ onglets vivent dans un `IndexedStack` (`main.dart`), choix "
     "voulu pour retrouver chaque onglet ou on l'a laisse. Un `IndexedStack` "
     "garde tous ses enfants MONTES : changer d'onglet ne detruit rien, donc "
     "ne declenche aucun `dispose()`. "
     "Deux facons de quitter l'ecran, aucune ne passait par la : changer "
     "d'onglet, et quitter l'application. D'ou deux gardes : `TickerMode` pose "
     "sur l'onglet Coach, lu dans `didChangeDependencies` comme signal de "
     "VISIBILITE, et `WidgetsBindingObserver` pour le cycle de vie. Seule la "
     "LECTURE est coupee, jamais le tour en cours. "
     "REGLE GENERALE QUI EN DECOULE : dans cette application, `dispose()` ne "
     "peut PAS servir de garantie de liberation pour ce qui vit dans un onglet. "
     "Tout ecran a etat continu (audio, enregistreur, minuteur) doit avoir un "
     "signal de visibilite explicite."),

    ("regle_une_seule_session_media_par_application_android",
     "[REGLE] Android n'accepte QU'UNE session media par application : la radio emprunte le handler du Coran, en sauvegardant ses rappels et en les RENDANT",
     "Demande utilisateur (2026-09-14) : « invocation radio, quand c'est play, "
     "garder le controle sur la notification ». "
     "Deux contraintes se sont ajoutees. (1) Le lecteur etait un `AudioPlayer` "
     "cree DANS le widget et detruit par son `dispose()` : une notification "
     "n'aurait pilote qu'un lecteur deja mort. Sortir le lecteur du widget "
     "(`RadioDhikrService`, singleton) est la CONDITION de la demande, pas un "
     "raffinement. (2) Ouvrir une seconde session `audio_service` ferait "
     "disparaitre la premiere -- celle du lecteur du Coran, initialisee avant "
     "`runApp`. "
     "PIEGE QUI EN DECOULE, et qui est traite : les rappels `auPlay`/`auPause`/"
     "`auStop` sont branches par `PlayerNotifier` UNE SEULE FOIS au demarrage. "
     "Les ecraser sans les rendre ferait piloter la radio par les boutons de la "
     "notification PENDANT une lecture du Coran -- un bouton qui commande autre "
     "chose que ce qu'il affiche. `_prendreLaMain()` les sauvegarde, "
     "`_rendreLaMain()` les remet a l'arret comme a l'echec. "
     "Le flux ICY n'a pas de fin mais le lecteur croit que si : reconnexion "
     "tant que l'arret n'est pas demande, abandon annonce apres 3 echecs de "
     "moins de 5 s d'ecoute utile."),

    ("piege_mailto_perd_la_piece_jointe_et_le_partage_perd_le_destinataire",
     "[PIEGE] Aucun chemin Dart ne porte A LA FOIS un destinataire et une piece jointe : `mailto:` perd le fichier, le partage perd l'adresse",
     "Demande utilisateur (2026-09-14) sur l'envoi des verdicts : « il faut "
     "mettre la meme adresse mail que Nous contacter, pre-saisie ». "
     "Les deux chemins existants echouent chacun sur une moitie : `url_launcher` "
     "avec `mailto:?to=` remplit le champ « A » mais ne peut porter aucun "
     "fichier ; `share_plus` porte le .zip mais ignore le destinataire. "
     "D'ou un `Intent ACTION_SEND` natif (canal `coran_karim/envoi`, "
     "`MainActivity.kt`) qui porte `EXTRA_EMAIL` ET `EXTRA_STREAM`. "
     "DEUX PRECAUTIONS QUI COMPTENT : (1) notre PROPRE `FileProvider` "
     "(`<paquet>.fichiers`, `res/xml/chemins_partage.xml`) -- celui de "
     "`share_plus` lui appartient, s'y greffer casserait a sa prochaine "
     "version ; (2) ce provider n'expose QUE `<cache-path>`, jamais "
     "`files-path` ni `external-path` : les dossiers qui contiennent la VOIX de "
     "l'utilisateur ne doivent pas devenir lisibles par l'application choisie "
     "dans le selecteur. Repli conserve sur le partage ordinaire si l'Intent "
     "echoue."),

    ("piege_rotation_de_page_a_90_degres_montre_la_tranche",
     "[PIEGE] Le « flash » de la page qui se tourne venait de la rotation atteignant exactement 90 degres -- l'angle ou une surface est vue par la tranche",
     "Signale par l'utilisateur le 2026-09-14 : « je vois le changement comme "
     "tourner la page, deja ca se fait rapidement [...] en plus ca fait un "
     "flash ». "
     "Deux defauts distincts, une seule plainte. (1) Le `PageView` faisait "
     "GLISSER la page ; une feuille PIVOTE. D'ou `_FeuilleQuiTourne` "
     "(`Matrix4` avec perspective `setEntry(3,2,...)`). (2) La premiere version "
     "allait jusqu'a pi/2 : a cet angle exact la feuille n'a plus d'epaisseur a "
     "l'ecran, elle DISPARAIT puis reapparait de dos -- ce que l'oeil lit comme "
     "un flash, pas comme une page qui se tourne. "
     "CHIFFRES RETENUS : angle plafonne a 78 degres (`_kAngleMax`), fondu a "
     "partir de 55 % de la course (`_kDebutFondu`), translation compensee pour "
     "que la feuille reste sur la reliure, et duree portee de 260 ms a 820 ms "
     "en `easeInOut` -- a 260 ms le geste etait fini avant d'etre lu."),

    ("piege_une_consigne_derive_quand_le_comportement_change_a_cote",
     "[PIEGE] Deux consignes d'ecran etaient devenues FAUSSES sans que rien ne le signale -- une consigne fausse apprend le mauvais geste",
     "Trouvees en relisant l'ecran d'essai le 2026-09-14, NON signalees par "
     "l'utilisateur : "
     "(1) « Un mauvais choix fait seulement trembler : AUCUNE PENALITE » alors "
     "que le jeu d'enchainement applique « -5 et retour au verset precedent » "
     "depuis le 2026-08-10 -- la consigne datait d'avant la penalite ; "
     "(2) « Sur Al-Ikhlas -- quatre versets », devenue fausse le jour meme ou "
     "la tuile d'entrainement est partie sur An-Nisa' 4:1. "
     "MECANISME COMMUN : la consigne vit dans un fichier ARB, le comportement "
     "dans un provider ; rien ne les relie, aucun test ne les confronte, et le "
     "compilateur est muet. Elles derivent a chaque fois que le comportement "
     "change A COTE. "
     "Ce qui rend le defaut grave et pas cosmetique : une consigne fausse est "
     "PIRE que pas de consigne, elle apprend le mauvais geste. A relire "
     "systematiquement quand une regle de jeu ou une cible d'ecran change."),

    ("attente_page_tournee_radio_et_verdicts_non_verifies_sur_device",
     "[EN ATTENTE] Animation de page, notification radio, envoi des verdicts et arret de l'audio : rien n'est verifie sur telephone, seulement par analyse statique",
     "Etat au 2026-09-14, commit 81992dd. Ce qui EST verifie : "
     "`flutter analyze lib/` a 0 erreur, et les tests d'ouverture du mushaf a "
     "4/4 apres mise a jour (ils exigeaient « la couverture ouvre le papier », "
     "ce qui n'est plus le contrat ; ce qu'ils verrouillent encore -- "
     "prechargement de la riwaya et de la position -- est conserve tel quel). "
     "Ce qui N'EST PAS verifie, faute de telephone connecte (`adb devices` "
     "vide en fin de session) : l'animation de page tournee, la notification de "
     "la radio et le passage de main des rappels media, l'envoi d'un verdict "
     "avec destinataire pre-saisi via l'Intent natif, et l'arret effectif de "
     "l'audio au changement d'onglet. "
     "A REPRENDRE PAR LA : ces quatre points d'abord, avant toute nouvelle "
     "modification de ces ecrans."),
]

LIENS = [
    ("regle_le_silence_entre_deux_voisins_est_la_reponse_pas_une_panne",
     "regle_extrait_deduit_de_deux_voisins_juxtaposes", "shares_data_with",
     "meme fonction `entreLesVoisins` : l'une dit quand elle repond, l'autre ce qu'elle repond sur un trou vide"),
    ("piege_deux_packs_de_modeles_dans_le_meme_aab",
     "mesure_madda_normal_detecteur_reel_pack_production_v2", "shares_data_with",
     "le gras a ete vu en integrant ce pack : le nouveau arrive, l'ancien reste"),
    ("attente_page_tournee_radio_et_verdicts_non_verifies_sur_device",
     "piege_un_ecran_dans_un_indexedstack_ne_recoit_jamais_dispose", "shares_data_with",
     "le correctif d'arret de l'audio fait partie de ce qui reste a verifier sur telephone"),
    ("attente_page_tournee_radio_et_verdicts_non_verifies_sur_device",
     "regle_une_seule_session_media_par_application_android", "shares_data_with",
     "le passage de main des rappels media ne se prouve qu'avec une vraie notification"),
    ("piege_rotation_de_page_a_90_degres_montre_la_tranche",
     "attente_page_tournee_radio_et_verdicts_non_verifies_sur_device", "shares_data_with",
     "l'angle et la duree sont choisis sur analyse, pas encore vus a l'ecran d'un telephone"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step56.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
