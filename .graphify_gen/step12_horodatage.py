#!/usr/bin/env python3
"""Consigne les mesures du 2026-08-06 (horodatage, maxBloc/maxFusion) ET
corrige un noeud dont la mesure etait invalide.

Meme principe que step10_decrochage.py : on enrichit, on n'ecrase pas, et
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
    ("piege_parametre_lu_mais_jamais_applique",
     "[PIEGE] Un parametre de banc LU mais jamais passe au constructeur",
     "MESURE (2026-08-06) : `maxFusion` et `apercu2` etaient lus par "
     "BancFluxBrut (`System.getProperty`) et relayes par build.gradle.kts, "
     "mais l'edition qui devait les passer a `ConstructeurDeFenetres` avait une "
     "indentation fausse -- elle n'a rien remplace, en silence. SEPT "
     "configurations (maxFusion 30/20/18/16/15/12/10) ont rendu 302 blocs et "
     "41/295 = 13,90 % A L'IDENTIQUE. Le signal qui l'a trahi : un parametre "
     "qui ne change RIEN DU TOUT, pas meme le nombre de blocs. Une fois "
     "corrige, 10/15 rend 296 blocs et 15,93 %. CONSEQUENCE GRAVE : la mesure "
     "des « deux grilles de periodes premieres » etait vide de sens, la "
     "seconde grille n'ayant jamais existe -- conclusion juste par accident, "
     "ce qui ne vaut rien. PARADE : la ligne de parametres du banc imprime "
     "desormais TOUS les parametres sans exception ; c'est la seule chose qui "
     "rend cette panne visible. Meme famille que le relais manquant de "
     "`apercu`/`largeurApercu` dans build.gradle.kts."),

    ("mesure_maxbloc_10_maxfusion_18",
     "[MESURE] Blocs plafonnes a 10 s, fusion a 18 s -- le plus serre sans cout",
     "Banc JVM (Al-Baqara 433 s, meme audio, apercus 4/4, k=2), maxBloc/"
     "maxFusion -> non verts : 30/30 13,90 % (265 blocs), 15/30 13,90 % (273), "
     "10/18 13,90 % (302), 12/24 14,24 % (286), 10/16 15,59 % (299), "
     "10/15 15,93 % (296). FALAISE entre maxFusion 18 et 16. Recette REELLE, "
     "rejeu deterministe du meme WAV sur DEUX telephones : 30/30 -> 210 "
     "fenetres, plus longue 26,0 s, 38 au-dela de 12 s, 1,02 % ; 15/30 -> 221, "
     "21,8 s, 39, 1,02 % ; 10/18 -> 240, 16,9 s, 19, 1,02 %. Memes trois mots "
     "non verts (172, 228, 285) partout, resultat IDENTIQUE sur le Redmi. "
     "Motivation utilisateur : a 30 s une fenetre portait jusqu'a 58 mots."),

    ("mort_plafonner_les_fenetres_sous_18s",
     "[MORT] Plafonner les fenetres en dessous de 18 s",
     "MESURE QUI LA TUE (recette reelle, meme WAV) : 6/12 -> 2,37 %, "
     "4/8 -> 4,07 %, 8/8 -> 9,15 %. Degradation MONOTONE. L'hypothese testee "
     "etait « le modele s'effondre au-dela de 12 s » : elle est REFUTEE sur ce "
     "modele et cet audio. Le 8/8 illustre en plus le piege du plafond "
     "partage : maxFusion = maxBloc rend la fusion impossible, elle disparait, "
     "et on obtient MOINS de fenetres (206) qu'a 30/30 (210) tout en ayant "
     "raccourci. La mesure ancienne « عظيم parfait a 3 s, introuvable a 12 s » "
     "portait sur le sondage d'un mot ISOLE et sur un autre modele : elle ne "
     "dit rien du fenetrage de la chaine."),

    ("mesure_les_fenetres_longues_sont_le_rattrapage",
     "[MESURE] Les fenetres longues NE SONT PAS du gaspillage : ce sont elles "
     "le rattrapage",
     "MESURE decisive, mot 67 `أَلَآ`, MEME audio, deux configurations. A "
     "30/30 : declare `omis` a 14:41:17 (gop=-2,96, bord, entendu=\"\", obs=2) "
     "puis REPECHE a 14:41:21 en `provisoire:vert` (gop=0,00, INT, obs=4, "
     "entendu=`أَلَآ`). Les fenetres qui le couvrent : 4,1 s, 4,0 s, puis "
     "9,6 s, 11,8 s, 11,4 s -- ce sont les trois longues qui le remettent au "
     "centre. A 6/12 : SEULES deux fenetres le couvrent (4,0 et 6,0 s), obs=1, "
     "il reste `omis` et aucun rattrapage n'arrive jamais. COROLLAIRE : `omis` "
     "n'est pas un verdict final, il peut etre renverse -- et c'est la duree "
     "des fenetres qui decide s'il le sera."),

    ("piege_horodatage_ambiguite_passage_repete",
     "[PIEGE] Deux alignements a EGALITE, et la LCS prend le plus ancien",
     "MESURE (2026-08-06, Al-Ma'un 107, session NORMALE, trois recitations "
     "consecutives). Le recitateur dit `ٱلَّذِينَ هُمْ يُرَآءُونَ` (mots 24-26) ; "
     "`ٱلَّذِينَ هُمْ` figure AUSSI aux mots 19-20. DP rejouee sur les vrais "
     "mots : depart=19 -> LCS=5 retenu [19,20,26,27,28] (trou de 5 mots) ; "
     "depart=24 -> LCS=5 retenu [24,25,26,27,28] (contigu). A egalite la "
     "marche arriere prenait l'index le PLUS PETIT. Log : `f=20/21/25 RECUL "
     "vers le mot 19` puis `f=22/24/32 SAUT REFUSE : trou de 3 mots apres le "
     "mot 23 (attestes=[27, 28])`. Ancre figee a 23, CINQ derniers mots jamais "
     "juges, alors que le balayage du flux brut les lit nettement "
     "(26-30 s et 30-34 s)."),

    ("regle_contrainte_temporelle_appariement",
     "[REGLE] Un saut d'index doit etre PAYE en frames, sinon il est impossible",
     "Sauter de l'index a a l'index b laisse les mots a+1..b-1 non entendus ; "
     "leur prononciation exige un minimum PHYSIQUE de frames "
     "(`framesMinParMot`, deja fourni par ChaineRecitation et jusqu'ici "
     "utilise pour la seule tete de bloc). Si l'audio entre les deux mots "
     "ENTENDUS n'en porte pas autant, l'alignement n'est pas moins probable : "
     "il est IMPOSSIBLE. CONTRAINTE DURE, pas departage -- decision "
     "utilisateur : « le saut n'est pas autorise, en plus c'est ce que je veux "
     "detecter pour arreter la recitation et qu'il recite les mots reellement "
     "attendus ». Un saut ne doit pas faire avancer l'ancre en silence, il "
     "tombe dans le decrochage. La DP porte desormais sur les CANDIDATS "
     "d'appariement, la contrainte liant deux appariements consecutifs -- ce "
     "qu'une LCS classique ne sait pas exprimer. PREUVE : LocalisateurTest, "
     "3 tests, ECHOUENT sans le correctif (2 sur 3)."),

    ("piege_session_jamais_fermee_fin_de_recitation",
     "[PIEGE] La session v2 n'est jamais fermee quand on enchaine sans STOP",
     "MESURE (2026-08-06, trois recitations reelles) : `capture ouverte` = 3, "
     "toute trace de fermeture = 0, et `session fermee` (la ligne que produit "
     "`v2Terminer`) = 0 OCCURRENCE SUR 152 349 LIGNES de journal. Cause : le "
     "`dispose()` de l'ecran karaoke ne fait que `setClipCapture(null)` ; seul "
     "le bouton STOP appelle `stopContinuous()`, donc `v2Terminer()`. "
     "L'utilisateur enchaine les sourates sans passer par lui. Consequence : "
     "la derniere fenetre HORS GRILLE n'est jamais emise, et les derniers mots "
     "restent au bord droit de la derniere fenetre -- `f=26 bande=33..34 "
     "interieurs=0/2`, `f=29 bande=36..41 interieurs=4/6`. Mots de fin jamais "
     "atteints : 5, 3 et 5 sur les trois recitations. NON CORRIGE a ce jour. "
     "PIEGE DE METHODE ASSOCIE : chercher `v2Terminer` ou `terminer` dans le "
     "log ne trouve RIEN alors que le mecanisme journalise bien -- la ligne "
     "s'appelle `session fermee`. Verifier le TEXTE que le code ecrit, pas le "
     "nom de la fonction."),
]

LIENS = [
    ("piege_parametre_lu_mais_jamais_applique",
     "mort_deux_grilles_periodes_premieres", "a_invalide"),
    ("mesure_maxbloc_10_maxfusion_18",
     "mort_plafonner_les_fenetres_sous_18s", "borne_par"),
    ("mort_plafonner_les_fenetres_sous_18s",
     "mesure_les_fenetres_longues_sont_le_rattrapage", "explique_par"),
    ("piege_horodatage_ambiguite_passage_repete",
     "regle_contrainte_temporelle_appariement", "corrige_par"),
    ("piege_session_jamais_fermee_fin_de_recitation",
     "piege_horodatage_ambiguite_passage_repete", "meme_symptome"),
    ("mesure_maxbloc_10_maxfusion_18",
     "piege_maxbloc_partage_avec_le_plafond_de_fusion", "rendu_possible_par"),
]

# CORRECTION d'un noeud existant : sa mesure etait invalide (cf.
# piege_parametre_lu_mais_jamais_applique). On ne supprime pas, on REECRIT le
# rationale avec les chiffres refaits -- et on dit que les premiers etaient faux.
CORRECTIONS = {
 "mort_deux_grilles_periodes_premieres":
  "IDEE UTILISATEUR (2026-08-06) : deux grilles de periodes 3 et 5 ne "
  "realignent leurs frontieres que toutes les 15 s. Raisonnement JUSTE, gain "
  "NUL. ATTENTION -- LA PREMIERE MESURE ETAIT INVALIDE : `apercu2` n'etait pas "
  "passe au constructeur du banc, la seconde grille n'a jamais existe, et je "
  "comparais en realite A(3/3) seule a A(4/4) seule (cf. "
  "piege_parametre_lu_mais_jamais_applique). MESURE REFAITE, relais verifie, "
  "banc JVM meme audio, ligne B active : A(4/4) seule -> 265 blocs, 1162 obs, "
  "13,90 % ; A(3/3)+A2(5/5) -> 378 blocs, 1322 obs, 13,90 % ; temoin NON "
  "premier A(4/4)+A2(6/6) -> 334 blocs, 1316 obs, 14,24 %. Deux grilles "
  "n'ameliorent donc pas le taux, ici pour 43 % de fenetres en plus, et la "
  "primalite ne degrade pas non plus. POURQUOI l'argument ne mord pas : il "
  "suppose que la seconde ligne est une GRILLE dont les frontieres pourraient "
  "coincider. La ligne B ne coupe pas sur une horloge, elle coupe aux SILENCES "
  "REELS -- instants sans periodicite, jamais synchronisables avec une grille. "
  "Code conserve et desactive (apercu2Secondes = 0).",
}


def noeud(nid, label, rationale):
    return {"id": nid, "label": label, "rationale": rationale,
            "node_type": "concept", "community": "recitation"}


def sha() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


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

    corriges = 0
    for n in g["nodes"]:
        if n["id"] in CORRECTIONS:
            n["rationale"] = CORRECTIONS[n["id"]]
            corriges += 1
            print(f"  ~ rationale CORRIGE (mesure invalide) : {n['id']}")
    print(f"  {corriges} noeud(s) corrige(s)")

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
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_horodatage.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_horodatage.json")


if __name__ == "__main__":
    main()
