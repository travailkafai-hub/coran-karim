#!/usr/bin/env python3
"""Consigne les mesures des 2026-08-05 / 2026-08-06 (chaine du DECROCHAGE).

Meme principe que step8_v2.py / step9_v21.py : on enrichit, on n'ecrase pas, et
le `rationale` porte LE CHIFFRE ou LA LIGNE DE LOG -- jamais l'intention.

Contexte : une soiree entiere de correctifs sur le decrochage / SAUT REFUSE,
dont la moitie visaient le mauvais maillon. Ce fichier existe pour qu'on ne
repaye pas ces heures -- chaque noeud dit ce qui a ETE MESURE, pas ce qui a ete
espere.

Protocole des mesures : sessions reelles sur device (Samsung R3CY20XW7TD),
builds v49 a v57, sourates 90/93/95, mode NORMALE sauf mention, journal
`recitation_diagnostic.log` + flux brut `stream_*.wav` confronte au modele.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    # ── LA CAUSE RACINE DE LA SOIREE ────────────────────────────────────────
    ("piege_cible_v2_jamais_etendue",
     "[PIEGE] L'enchainement de page ne mettait PAS a jour la cible v2",
     "MESURE (2026-08-05, device) : `extendAlignmentTarget` ne touchait que "
     "l'aligneur v1. La cible v2 -- celle qui juge REELLEMENT, cf. PARAMS "
     "« CELUI QUI PEINT L'ECRAN » -- restait figee a sa taille de DEPART toute "
     "la session. Log : `cible=40 mots` au demarrage, puis cote Dart "
     "`Enchaînement page 3 : +11 versets, +127 mots` (167 mots a l'ecran) et "
     "cote Kotlin TOUJOURS 40. Tout mot au-dela du 40e etait STRUCTURELLEMENT "
     "hors de portee : localisateur et decrochage sont bornes par "
     "`motsAttendus.size`. Symptome trompeur : « il decroche toujours sur "
     "إِنَّ » -- ce mot etait simplement le 40e. CINQ correctifs ont ete tentes "
     "sur le SEUIL de decrochage avant de trouver que la cible etait trop "
     "courte. Corrige par `ChaineRecitation.etendreTexte` + `v2ExtendTarget` "
     "(v49) : verifie ensuite `cible etendue : +114 mots -> 158`, ancre 81 sur "
     "une cible initiale de 44."),

    ("regle_verifier_cible_avant_taux",
     "[REGLE] Verifier que la CIBLE a suivi l'ecran avant tout taux",
     "Si `ancre max` depasse la cible initiale sans aucune ligne "
     "`cible etendue`, les mots au-dela ne POUVAIENT pas etre juges et tout "
     "taux calcule dessus est faux. Controle : `grep -m1 'PARAMS] cible=' $S` "
     "puis `grep 'cible etendue' $S`. Defaut reste invisible des semaines "
     "(2026-08-05)."),

    # ── LES QUATRE ETAGES, ET LES MORTS SILENCIEUSES ────────────────────────
    ("piege_decrochage_quatre_etages",
     "[PIEGE] Un decrochage traverse QUATRE etages et meurt en silence",
     "MESURE (2026-08-06, 4 sessions) : `DECROCHAGE`=25 mais "
     "`Decrochage signalé`=14 et `wordFailed déclenché`=8. Deux fuites, pas un "
     "detail. Les etages : [v2] DECROCHAGE (natif) -> [Decrochage] signalé "
     "(pont) -> [Correction] wordFailed (_onWordFailed) -> [Correction-Audio] "
     "(audio joue). Compter les QUATRE et comparer, sinon on corrige le mauvais "
     "maillon -- ce qui a ete fait pendant des heures le 2026-08-05."),

    ("piege_retours_silencieux_onWordFailed",
     "[PIEGE] `_onWordFailed` avalait un decrochage sans AUCUNE ligne",
     "MESURE (2026-08-05) : 1re correction complete, 2e decrochage signale puis "
     "PLUS RIEN -- ni `wordFailed`, ni `Correction-Audio`. Quatre `return` "
     "muets pouvaient tuer le signal (action en cours / anti-rafale / position "
     "introuvable / reglage desactive) et un cinquieme cote provider "
     "(`state.status != listening`). Instrumentes le 2026-08-05 : le log a "
     "immediatement nomme la cause reelle (`IGNORÉ ... correction automatique "
     "désactivée`). REGLE : un `return` sur le chemin d'un signal DOIT se "
     "journaliser -- zero trace est indiscernable de zero execution."),

    ("piege_reglage_persiste_et_course_init",
     "[PIEGE] Reglage persiste a false + course d'init = « 1re OK, 2e KO »",
     "MESURE (2026-08-05, device) : `auto_correction_enabled=false` en base "
     "(desactive lors d'un test du souffleur, jamais reactive). Le provider "
     "demarre a `true` EN DUR puis lit la valeur persistee en ASYNCHRONE, et "
     "n'est cree qu'au PREMIER `ref.read` -- qui etait celui de la 1re "
     "correction. Log : 22:46:43 1re correction jouee, 22:46:50 et 22:47:09 "
     "« IGNORÉ : correction automatique désactivée ». Motif SYSTEMATIQUE, pris "
     "a tort pour un defaut d'algorithme. Corrige en prechargeant le provider a "
     "l'ouverture de l'ecran (v54). LECON : avant de toucher un seuil, lire les "
     "`IGNORÉ` et verifier l'etat PERSISTE sur le device."),

    ("piege_bismillah_correction_impossible",
     "[PIEGE] A la jonction de sourates, la correction ne peut PAS partir",
     "MESURE (2026-08-06, session 06:54) : `DECROCHAGE (saut) ... reprise apres "
     "le mot 81` -> `reprise=82 بِسْمِ` -> `IGNORÉ mot 82 : position "
     "introuvable (verset=null local=null)`, DEUX FOIS. `_verseContaining` rend "
     "`null` sur la Bismillah inseree, donc le decrochage est structurellement "
     "impuissant a chaque enchainement de sourate. Le commentaire de "
     "`_onDecrochageV2` nommait deja ce piege pour le mot 0 -- il revient a "
     "chaque jonction. NON CORRIGE au 2026-08-06."),

    ("mesure_omis_a_tort_sur_bismillah",
     "[MESURE] Deux `omis` sur une Bismillah PARFAITEMENT audible",
     "MESURE (2026-08-06, session 06:54, sourate 95) : mots 44-45 declares "
     "`omis` -- le verdict le plus grave de l'app (« vous n'avez pas dit ce "
     "mot ») -- alors que le flux brut decode `ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ` a "
     "61-67 s. Meme zone que piege_bismillah_correction_impossible : la "
     "jonction de sourates cumule DEUX defauts (verdict faux + correction "
     "impuissante). REGLE : tout `omis` se confronte au WAV, sans exception."),

    # ── SAUT REFUSE : CE QUI A ETE CORRIGE, ET CE QUI RESTE ─────────────────
    ("piege_saut_blanchi_par_fenetre_refusee",
     "[PIEGE] Une fenetre REFUSEE ne doit pas faire avancer la reference",
     "MESURE (2026-08-05, saut delibere du mot 14 au mot 27) : "
     "`dernierAttesteVu` etait mis a jour AVANT le controle de saut, donc une "
     "fenetre REFUSEE posait quand meme son point d'arrivee (27) comme nouvelle "
     "reference. La fenetre suivante ne voyait plus aucun trou, l'ancre montait "
     "a 27, et l'audio de correction repartait du mot 28 -- APRES le saut -- au "
     "lieu du mot 15 ou le recitateur avait quitte le texte. Le saut etait "
     "refuse pour le JUGEMENT et blanchi pour la POSITION. Corrige (v52) : la "
     "reference n'avance que sur une fenetre ACCEPTEE."),

    ("piege_trou_derriere_lancre",
     "[PIEGE] Un trou entre mots DEJA VALIDES n'est pas un saut",
     "MESURE (2026-08-05, log 23:14:46, verset 2:13) : `SAUT REFUSE : trou de 5 "
     "mots apres le mot 97 (attestes=[97,103,104,105,106,107]), dernier "
     "definitif=108`. Le trou 97->103 est ENTIEREMENT derriere l'ancre (108) : "
     "ces mots etaient tous deja valides, le modele les reentend simplement "
     "(repetition, recouvrement de fenetres). Deux fenetres comme celle-ci de "
     "suite coupaient une recitation JUSTE -- plainte utilisateur « il m'a coupe "
     "alors que je recite ». Corrige (v56) : on ne cherche le trou que parmi "
     "les mots >= ancre."),

    ("regle_reprise_au_dernier_mot_DIT",
     "[REGLE] Reprendre au dernier mot REELLEMENT DIT, pas au dernier verrouille",
     "MESURE (2026-08-05, log 22:55:26) : reprise annoncee au mot 13 avec "
     "`dernier definitif=12`, alors que le recitateur etait alle plus loin -- "
     "les mots suivants etaient ENTENDUS et ATTESTES mais pas encore "
     "VERROUILLES (le Decideur exige deux fenetres concordantes). Symptome : "
     "« quand il y a decrochage il repete des mots que j'ai dit ». Corrige "
     "(v55) par `pointDeReprise() = max(dernierDefinitif, dernierAttesteVu)` -- "
     "verifie ensuite dans le log : `dernier definitif=45, dernier atteste "
     "vu=46, reprise apres le mot 46`."),

    ("mort_encoreEnCours_sur_avancee",
     "[MORT] « la chaine progresse encore » ne protege PAS d'un saut",
     "TENTE puis RETIRE le 2026-08-05. L'idee : ne pas compter une fenetre vers "
     "le decrochage si `dernierAttesteVu` a avance (la chaine resout encore le "
     "trou). REFUTE deux fois par des sauts DELIBERES : (1) un saut de 39 mots "
     "comptait comme « encore en cours » -- log `f=61 SAUT REFUSE : trou de 30 "
     "mots apres le mot 89 (attestes=[120,124,126,128]) -- encore en cours "
     "(attesteVu 89 -> 128), decrochage NON compte` ; (2) le mecanisme exigeait "
     "de mettre la reference a jour AVANT le controle, ce qui blanchissait le "
     "saut (cf. piege_saut_blanchi_par_fenetre_refusee). Retire : la reference "
     "n'avance plus que sur fenetre acceptee, ce garde devient sans objet."),

    ("attente_ambiguite_mot_repete_sans_horodatage",
     "[EN ATTENTE] Mot frequent -> bande posee au hasard, ancre figee",
     "MESURE (2026-08-06, session 07:28, v57) : NEUF fenetres consecutives "
     "refusees en 30 s, `SAUT REFUSE : trou de 27 mots apres le mot 22 "
     "(attestes=[22, 50])`, ancre bloquee a 21. Le decodage libre atteste les "
     "mots 22 ET 50 dans la MEME fenetre : un mot frequent accroche une "
     "occurrence 27 positions plus loin. Meme famille que les blocages "
     "constates sur `إِنَّ` et `أُو۟لَـٰٓئِكَ`. Le commentaire de "
     "`Localisateur.minAppariements` nommait deja le risque : « un mot tres "
     "frequent (مِن, إِن) qui place la bande au hasard dans une region de 92 "
     "mots ». PISTE NON IMPLEMENTEE : les frames de chaque mot atteste sont "
     "DEJA disponibles (`bande.attestes` = index -> IntRange de frames, "
     "`Fenetre.absoluDeFrame`) mais AUCUN controle ne les lit -- tout raisonne "
     "sur les index. Deux mots attestes dont les index bondissent alors que le "
     "temps avance sont incompatibles avec une lecture lineaire."),

    ("piege_sentinelle_divisee_aligneur",
     "[PIEGE] La sentinelle divisee cesse d'etre reconnaissable (AligneurForce)",
     "MESURE (2026-08-06, device) : `margeL=3.333333383491554e+29` dans le log. "
     "`forwardMoyen` rendait `fin / n` sans filtrer la sentinelle : -1e30 / 3 = "
     "-3,33e29, et tous les gardes testent `<= -1e30` -- la sentinelle passait. "
     "Impact CONSTATE nul sur les verdicts (le Decideur ne condamne que sur "
     "marge NEGATIVE, et `f` vient du Viterbi, pas de cette fonction), mais la "
     "faille etait ouverte : une marge massivement negative aurait verrouille "
     "un ROUGE sans preuve acoustique. MEME BUG DEJA PAYE dans `Tete3Traits` "
     "(« au-dela de 2 frames il ne filtrait plus rien -- alt2 a -2,5e29 et un "
     "logit a 3,7e29 »), corrige la-bas le 2026-08-05 et JAMAIS ici. Corrige "
     "(v57) en filtrant AVANT la division : verifie, 0 occurrence de `e+29` "
     "sur la session suivante."),

    ("regle_mode_change_l_analyse",
     "[REGLE] `modeConfiant` coupe le decrochage -- la session ne valide RIEN",
     "MESURE (2026-08-06) : 2 sessions sur 4 en `modeConfiant=true`, avec 53 et "
     "25 `SAUT REFUSE`. Or `_onDecrochageV2` commence par "
     "`if (_confidentMode) return;` : ces chiffres ne prouvent rien sur le "
     "decrochage. Lire `[CTL][PARAMS] session=... modeConfiant=...` AVANT "
     "d'interpreter, et le dire dans le compte rendu."),

    ("mesure_faux_positifs_dominent_le_taux",
     "[MESURE] 11 des 15 non-verts sont AUDIBLES et CORRECTS dans le brut",
     "MESURE (2026-08-06, session 06:54, sourates 93->95, 82 mots juges) : "
     "18,3 % de mots non verts, dont 11 sur 15 confirmes presents et corrects "
     "dans le flux brut. Les rouges viennent de decodages approximatifs du "
     "modele acoustique (ض->ت sur وَٱلضُّحَىٰ, د->ض sur بَعْدُ, ع avale sur "
     "وَدَّعَكَ), pas de la recitation. Confirme la mesure du 2026-07-28 (8 non "
     "verts, 0 vraie erreur) sur un modele plus recent : le taux affiche mesure "
     "d'abord la chaine, pas le recitateur."),
]

# (source, cible, relation)
LIENS = [
    ("piege_cible_v2_jamais_etendue", "regle_verifier_cible_avant_taux", "impose"),
    ("piege_decrochage_quatre_etages", "piege_retours_silencieux_onWordFailed", "explique"),
    ("piege_retours_silencieux_onWordFailed", "piege_reglage_persiste_et_course_init", "a_masque"),
    ("piege_bismillah_correction_impossible", "mesure_omis_a_tort_sur_bismillah", "meme_zone"),
    ("piege_saut_blanchi_par_fenetre_refusee", "mort_encoreEnCours_sur_avancee", "a_cause_de"),
    ("attente_ambiguite_mot_repete_sans_horodatage", "piege_trou_derriere_lancre", "voisin_de"),
    ("piege_sentinelle_divisee_aligneur", "regle_mode_change_l_analyse", "meme_session"),
]


def sha() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


def noeud(nid, label, rationale):
    return {"id": nid, "label": label, "rationale": rationale,
            "node_type": "concept", "community": "recitation"}


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid not in connus:
            g["nodes"].append(noeud(nid, label, rationale))
            ajoutes += 1
        else:
            # On ENRICHIT sans ecraser : si le noeud existe deja, on ne touche
            # a rien (regle projet -- aucune piste n'est jamais ecrasee).
            print(f"  = deja present, inchange : {nid}")

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            continue
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": None, "rationale": None,
        })
        aretes += 1

    if GRAPHE.exists():
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_decrochage.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_decrochage.json")


if __name__ == "__main__":
    main()
