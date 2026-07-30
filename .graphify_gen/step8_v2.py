#!/usr/bin/env python3
"""Enrichit le graphe EXISTANT avec la chaine v2 et ce que sa construction a mesure.

POURQUOI PAS UN SECOND GRAPHE (question utilisateur, 2026-07-30). Toute la
valeur du graphe tient a une propriete : il est LE seul endroit ou vit la
reponse a « est-ce que ca a deja ete essaye, et qu'est-ce que la mesure en a
dit ». Deux graphes, c'est deux sources ; un agent en lit une, la moitie des
mesures redevient invisible, et on repaye. C'est exactement le probleme que le
graphe existe pour supprimer.

La v2 n'annule pas l'historique de la v1 : elle en DECOULE. Un noeud [MORT] de
la v1 est ce qui interdit une piste a la v2 ; un noeud [EN ATTENTE] est ce
qu'elle reprend. Ces liens n'existeraient pas entre deux fichiers separes.

REGLE PROJET RESPECTEE : on n'ecrase rien. Le graphe d'avant la v2 est copie
dans graphify-out/graph_avant_v2.json avant ecriture.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"


def sha(ref="HEAD"):
    try:
        return subprocess.run(["git", "rev-parse", ref], capture_output=True,
                              text=True, cwd=RACINE, timeout=5).stdout.strip()
    except Exception:
        return ""


# ── Les noeuds ajoutes ────────────────────────────────────────────────────
# `rationale` porte LA MESURE, jamais l'intention : c'est ce qui rend le graphe
# plus fiable que les messages de commit.

COUCHES = [
    ("couche_v2_a_capture", "Ⓐ v2 — Capture (FluxBrut)",
     "Append-only, contigu, jamais purge par une decision de jugement. "
     "L'indice absolu d'un echantillon est LA reference de temps de toute la "
     "chaine. Rend impossible [PIEGE] 35 % de l'audio absent de tout fichier."),
    ("couche_v2_b_fenetres", "Ⓑ v2 — Fenetres (ConstructeurDeFenetres)",
     "Duree CONSTANTE W=6 s, pas 1,5 s, fenetres qui SE RECOUVRENT. Publie la "
     "table de correspondance travail<->brut. Supprime : gel, borne dure 12 s, "
     "findCutOffset, targetSeconds, conserve=0, coupe en plein mot."),
    ("couche_v2_c_front", "Ⓒ v2 — Front acoustique (FrontAcoustique)",
     "Fonction PURE de la fenetre, sans etat. Checkpoint causal v1 alimente SANS "
     "CACHE. Export ONNX audio_signal. Sans etat => plus de politique de remise "
     "a zero a deviner ([MORT] cache-aware, 5 politiques rejetees)."),
    ("couche_v2_d_localisation", "Ⓓ v2 — Localisation (Localisateur)",
     "Ou en est le recitateur, cherche DANS LES DEUX SENS, sur du TEXTE. Aucun "
     "effet de bord : deplacer la bande n'abandonne aucun mot. Repond `inconnu` "
     "quand elle ne sait pas. Rend attestes = index -> frames du decodage LIBRE."),
    ("couche_v2_e_alignement", "Ⓔ v2 — Alignement force (AligneurForce)",
     "Viterbi CTC pur. Ne juge pas, ne verrouille pas, ne connait aucun seuil. "
     "Produit `interieur` (le mot ne touche aucun bord, marge droite = lookahead "
     "13 frames) et `sansCreneau` (la DP a du le poser sur l'audio d'un voisin)."),
    ("couche_v2_f_preuves", "Ⓕ v2 — Registre de preuves (RegistreDePreuves)",
     "APPEND-ONLY. Aucune observation n'est jamais ecrasee. Remede direct a la "
     "mesure audio_detruit.py : 100 gels sans aucun mot place, 825 s d'audio "
     "detruites, 635 mots que les apercus avaient deja places dedans."),
    ("couche_v2_g_decision", "Ⓖ v2 — Decision (Decideur)",
     "SEUL endroit ou vit un seuil. Provisoire des la 1re preuve interieure, "
     "DEFINITIF quand K=2 fenetres DISTINCTES concordent (stable-prefix rule). "
     "Monotone : un definitif ne change plus jamais. Statut `Omis` distinct."),
    ("couche_v2_h_affichage", "Ⓗ v2 — Affichage",
     "Distingue provisoire et definitif. Le statut `Omis` demande un rendu qui "
     "n'est ni vert, ni orange, ni rouge — sinon un mot saute redevient "
     "invisible, le vrai defaut de v22."),
]

DEFAUTS = [
    ("piege_v2_marge_vs_bord",
     "[PIEGE] Marge gauche d'interiorite != bord de session",
     "MESURE (banc JVM, 2026-07-30) : le TOUT PREMIER mot d'une session n'etait "
     "jamais interieur, donc jamais verrouille, donc declare `Omis` — alors "
     "qu'il etait aligne a gop 0,00 sur TROIS fenetres. La marge gauche ecarte "
     "une TRONCATURE, pas un BORD : au debut de session il n'y a rien a "
     "tronquer. Corrige par bordGaucheEstDebutDeSession.",
     "couche_v2_e_alignement"),
    ("piege_v2_portier_gele_la_grille",
     "[PIEGE] Le portier de silence gele la grille de fenetres",
     "MESURE (banc JVM, 2026-07-30) : les 2-3 DERNIERS mots n'obtenaient jamais "
     "leur 2e preuve. La grille est pilotee par la CROISSANCE du flux de "
     "travail ; un portier qui garde 0,3 s apres le dernier mot gele ce flux, "
     "donc la validation. Le silence a conserver n'est pas un reglage : c'est "
     "lookahead + pas = 2,6 s, DERIVE. Complement : terminer() emet une "
     "derniere fenetre hors grille. Relie a [EN ATTENTE] MAX_SILENCE 0,3->0,9 s "
     "(6d07754), qui allait dans le bon sens sans pouvoir dire pourquoi 0,9.",
     "couche_v2_b_fenetres"),
    ("piege_v2_mot_saute_juge_rouge",
     "[PIEGE] Un mot SAUTE juge ROUGE : la DP le pose sur l'audio du voisin",
     "MESURE (banc JVM, 2026-07-30) : un mot que le recitateur saute ressortait "
     "Definitif(ROUGE) avec gop=-11,99 et free=-0,01 — le modele CERTAIN de ce "
     "qu'il entend, le mot simplement absent. La DP est obligee de placer tous "
     "les mots qu'on lui donne : elle avait vole 3 frames au voisin. C'est le "
     "socle n°1 (dire vrai) qui tombe. Discriminant retenu : GEOMETRIE, pas "
     "seuil — la plage alignee est-elle contenue dans l'audio laisse LIBRE par "
     "les voisins attestes ? Un mot saute n'a pas de creneau, un mot SUBSTITUE "
     "en a un. Aucune duree de reference, aucune tolerance.",
     "couche_v2_e_alignement"),
    ("piege_v2_relecture_du_registre",
     "[PIEGE] Relire le registre avec un Decideur neuf ne reproduit pas la session",
     "MESURE (dans le banc lui-meme, 2026-07-30) : un mot verrouille VERT "
     "ressortait « rouge provisoire » a la relecture, parce que la relecture ne "
     "voyait que les 2 dernieres preuves. La couche G est STATEFUL par contrat "
     "(un definitif ne bouge plus). Un banc qui rejoue la decision en bloc "
     "mesure autre chose que ce qu'a vu l'utilisateur.",
     "couche_v2_g_decision"),
]

MESURES = [
    ("mesure_v2_non_regression",
     "[MESURE] v2 compilee mais non branchee : la v1 ne bouge pas",
     "Recette 2 telephones, sourate 2 depart v6, 420 s, 2026-07-30 17:30. "
     "AVANT (v24-log-trio-secours, 10:30) : ancre 297, 267 verts, 30 non verts "
     "= 10,10 %. APRES (v24-base-v2-non-branchee) : ancre 297, 267 verts, 30 non "
     "verts = 10,10 %. Les agregats coincident au chiffre pres (coincidence : le "
     "detail par mot differe, cf. mot 0). A comparer a la famille v24 mesuree "
     "sur le meme protocole : 9,27 / 9,27 / 10,10 / 11,78 / 12,96 %. "
     "CONCLUSION : ajouter le paquet recitation2 + une methode de plugin non "
     "appelee ne deplace pas la chaine live."),
    ("mesure_v1_rouges_sans_preuve",
     "[MESURE] La v1 LIVE condamne 5-6 mots par session sur transcript VIDE",
     "Controle BLOQUANT du superviseur (doit valoir 0) : 6 le 2026-07-30 17:30, "
     "5 sur la reference 10:30. Signature relevee : mots 69/70/73 a gop -12,74 / "
     "-10,38 / -8,45 avec free -0,09 / -0,10 / -0,09 — le modele est CERTAIN de "
     "ce qu'il entend. C'est exactement [SYMPTOME] entendu vide, gop effondre, "
     "free NORMAL : le defaut NAIT dans la position, pas dans la prononciation. "
     "Defaut PREEXISTANT (present dans la reference), pas introduit. C'est ce "
     "que la v2 supprime par construction via `sansCreneau`."),
]

REGLES = [
    ("regle_preuve_selon_nature_du_code",
     "[REGLE] La preuve exigee depend de ce que le code PEUT casser",
     "Revision du hook exige-superviseur.py le 2026-07-30. Chaine LIVE (celle "
     "qui peint l'ecran) -> recette a deux telephones. Code NON BRANCHE -> tests "
     "JVM au vert. Exiger une recette d'un code que rien n'appelle n'ajoute "
     "aucune securite et pousse a accumuler du travail non commite — ce qui a "
     "deja fait perdre NEUF versions mesurees, dont la meilleure du projet. Des "
     "qu'un fichier live est touche, meme avec du hors ligne, c'est la recette : "
     "le doute profite au socle."),
    ("regle_banc_appelle_le_code",
     "[REGLE] Le banc doit APPELER le code de l'app, jamais le reimplementer",
     "Deux predictions hors device confiantes et fausses en une journee "
     "(ancre_vs_realite, arbitrer_resync), et « le banc mesurait mon decoupage, "
     "pas l'app » deux jours de suite. Cause commune : chaque banc etait une "
     "reimplementation Python de la logique Kotlin. En v2 les couches B/D/E/F/G "
     "sont pures et sans dependance Android : le banc est un test JVM qui "
     "appelle le vrai code. C'est ce qui a permis de trouver TROIS defauts de "
     "socle en quelques secondes, avant tout deploiement."),
]

# (source, cible, relation, ce que l'arete signifie)
LIENS = [
    ("couche_v2_a_capture", "couche_v2_b_fenetres", "flux"),
    ("couche_v2_b_fenetres", "couche_v2_c_front", "flux"),
    ("couche_v2_c_front", "couche_v2_d_localisation", "flux"),
    ("couche_v2_d_localisation", "couche_v2_e_alignement", "flux"),
    ("couche_v2_e_alignement", "couche_v2_f_preuves", "flux"),
    ("couche_v2_f_preuves", "couche_v2_g_decision", "flux"),
    ("couche_v2_g_decision", "couche_v2_h_affichage", "flux"),
]

# Ce que la v2 NEUTRALISE : l'arete dit « ce noeud mort ne peut plus se
# reproduire ici, et voici par quelle propriete ».
NEUTRALISE = [
    ("couche_v2_c_front", "mort_cache_aware",
     "sans etat : plus de cache a vider, donc plus de politique a deviner"),
    ("couche_v2_b_fenetres", "mort_fenetre_glissante_naive",
     "aucun texte n'est cousu : le texte attendu est connu, on ALIGNE dessus"),
    ("couche_v2_b_fenetres", "mort_coupe_chaque_pause",
     "il n'y a plus de coupe du tout"),
    ("couche_v2_b_fenetres", "mort_conserve_zero",
     "plus de frontiere de segment, donc plus de `conserve`"),
    ("couche_v2_b_fenetres", "mort_rayon_coupe_2s",
     "plus de recherche de point de coupe"),
    ("couche_v2_e_alignement", "mort_relachement_proportion",
     "un fragment touche forcement un bord : jamais interieur, jamais vert"),
    ("couche_v2_d_localisation", "mort_resync_sur_apercu",
     "deplacer la bande n'abandonne aucun mot : les deux operations sont decorrelees"),
    ("couche_v2_g_decision", "piege_verrou_sur_apercu",
     "aucun chemin ne verrouille sur une seule observation ni sur un bord"),
    ("couche_v2_d_localisation", "piege_resync_avant_seulement",
     "recherche bornee DANS LES DEUX SENS : un recitateur qui repete est suivi"),
    ("couche_v2_b_fenetres", "piege_normalisation_dicte_archi",
     "duree d'analyse CONSTANTE : la normalisation ne derive plus avec la longueur"),
    ("couche_v2_e_alignement", "piege_moitie_logique_compense",
     "`interieur` remplace MIN_FRAMES_FOR_JUDGMENT, deferredOnceIndex, "
     "tolerance aux fragments, bleed prefixe, filet decodage-libre"),
    ("couche_v2_a_capture", "piege_35pct_audio_absent",
     "tout audio entre par ajouter() et reste extractible ou a ete ecrit avant"),
    ("piege_v2_mot_saute_juge_rouge", "piege_gop_vs_free",
     "meme signature : gop effondre avec free proche de 0 = mauvaise POSITION"),
    ("mesure_v1_rouges_sans_preuve", "sympt_entendu_vide",
     "mesure fraiche du meme symptome, sur la chaine LIVE, 2026-07-30"),
    ("couche_v2_e_alignement", "sympt_entendu_vide",
     "`sansCreneau` supprime ce symptome par construction"),
]

# Ce que la v2 REPREND (pistes en attente) : l'arete porte la mesure d'origine.
REPREND = [
    ("couche_v2_d_localisation", "attente_resync_texte",
     "comparaison sur du TEXTE (Maryam 15,46 -> 9,18 %, rouges 10 -> 6)"),
    ("couche_v2_b_fenetres", "attente_buffer_decale",
     "generalise : toutes les fenetres se recouvrent d'un pas"),
    ("couche_v2_b_fenetres", "attente_mel_incremental",
     "colonnes log-mel cachables : c'est ce qui rend le cout de fenetre constant"),
    ("couche_v2_e_alignement", "attente_contexte_droit_dp",
     "plus aucune troncature de logprobs : contexte des deux cotes ou pas de jugement"),
    ("piege_v2_portier_gele_la_grille", "attente_max_silence_09",
     "meme direction, mais la valeur est DERIVEE (lookahead + pas) et non reglee"),
    ("couche_v2_b_fenetres", "attente_coupe_fin_de_mot",
     "rendue SANS OBJET : il n'y a plus de coupe (piste conservee, pas supprimee)"),
]


def noeud(nid, label, rationale, fichier="CONCEPTION_RECITATION_V2.md"):
    return {
        "label": label, "file_type": "concept", "source_file": fichier,
        "source_location": None, "source_url": None, "captured_at": None,
        "author": None, "contributor": None, "rationale": rationale,
        "_origin": "semantic", "id": nid, "community": 0,
        "norm_label": label.lower(),
    }


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = 0

    for nid, label, rationale in COUCHES:
        if nid not in connus:
            g["nodes"].append(noeud(nid, label, rationale)); ajoutes += 1
    for nid, label, rationale, _ in DEFAUTS:
        if nid not in connus:
            g["nodes"].append(noeud(nid, label, rationale)); ajoutes += 1
    for nid, label, rationale in MESURES + REGLES:
        if nid not in connus:
            g["nodes"].append(noeud(nid, label, rationale)); ajoutes += 1

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0

    def lien(s, t, rel, pourquoi=None):
        nonlocal aretes
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            return
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": pourquoi, "rationale": pourquoi,
        })
        aretes += 1

    for s, t, rel in LIENS:
        lien(s, t, rel)
    for nid, _, _, couche in DEFAUTS:
        lien(nid, couche, "nait_dans", "la couche ou le defaut NAIT")
    for s, t, pourquoi in NEUTRALISE:
        lien(s, t, "neutralise", pourquoi)
    for s, t, pourquoi in REPREND:
        lien(s, t, "reprend", pourquoi)

    if GRAPHE.exists():
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_v2.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_v2.json")


if __name__ == "__main__":
    main()
