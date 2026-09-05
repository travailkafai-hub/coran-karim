#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Le tajwid v7 : ce que la mesure a dit le 2026-09-05."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_waqf_isole_eteint_le_tajwid_sur_42pc_des_versets",
     "[MESURE] Les marques de waqf isolees eteignaient le tajwid sur 42,5 % des versets et 64,3 % des mots",
     "Cause d'une lecture entiere d'An-Nisa sans un seul violet (2026-09-05). "
     "L'asset `quran_rules_annotated.json` garde les marques de waqf isolees "
     "(06D6, 06DA, 06D7...) comme des MOTS a part entiere ; "
     "`ArabicNormalizer.splitExpectedWords` les elimine (leur normalisation est "
     "vide). Des qu'un verset en porte une, les deux decoupages divergent et "
     "`RecitationNotifier._wordsFromSegments` retombe « sur le canonique » -- "
     "repli volontaire et sain (ne jamais attribuer une regle au mauvais mot) "
     "qui eteint TOUT le tajwid du verset, en silence, avec pour seule trace "
     "une ligne `[Rules] decalage annot s:a (N vs M mots) -> canonique`. "
     "MESURE sur les assets embarques : 2 652 versets sur 6 236 (42,5 %) dans "
     "ce cas, 49 791 mots sur 77 433 (64,3 %) sans aucune regle attendue. "
     "Al-Baqara 210 versets, An-Nisa 132, Al-An'am 129, Al-Imran 123. Sur la "
     "session du diagnostic, 8 des 11 versets traverses etaient decales et les "
     "3 alignes n'ont jamais ete atteints (ancre max = mot 88, le premier "
     "verset aligne commence au mot 90) : zero ligne `V2tajwidDetail` sur "
     "5 674 lignes de session, alors que la tete tajwid detectait bien "
     "(`[tajwidDuree] ikhafa=4f(320ms) p=1,000`)."),

    ("regle_recoller_le_waqf_au_mot_precedent",
     "[REGLE] Le recollage des marques de waqf realigne 6 236/6 236 versets -- et le filtre doit s'appliquer APRES retrait des symboles",
     "Correctif retenu (2026-09-05, arbitrage utilisateur) : filtrer les tokens "
     "annotes avec le meme critere que `splitExpectedWords`, applique APRES "
     "`RuleSymbols.strip`. CE DETAIL DECIDE DU RESULTAT : filtrer sans retirer "
     "les symboles PUA d'abord ne realigne que 5 338 versets (85,6 %) -- une "
     "marque de waqf PORTANT un symbole de regle (ex. 06D6+E007) passe alors "
     "pour un mot. Avec le retrait prealable : 6 236 / 6 236 (100 %), chaque "
     "mot annote egal a son canonique une fois les symboles retires. Les mots "
     "porteurs d'une regle attendue passent de 15 974 a 44 331 (x2,8). "
     "Les 1 048 symboles annotes SUR une marque (405 idgham_ghunnah, 256 "
     "ikhafa, 181 madda_obligatory, 114 slnt, 35 idgham_wo_ghunnah, 19 iqlab, "
     "15 madda_normal, 13 ikhafa_shafawi, 10 idgham_shafawi) sont rattaches au "
     "mot PRECEDENT : un idgham sur un signe d'arret est la jonction avec le "
     "mot d'avant, celui qui porte le noun ou le tanwin -- la logique deja "
     "portee par `isBoundaryWord`. Les index de "
     "`quran_rules_boundary.json` sont remappes dans la meme passe : sans "
     "cela chaque marque retiree decalerait d'un cran toutes les paires "
     "suivantes du verset."),

    ("piege_deux_decoupages_du_meme_texte",
     "[PIEGE] Deux decoupages du meme texte qui ne s'accordent pas sur ce qui compte comme un mot",
     "Troisieme occurrence de la MEME classe de bug dans ce projet : le rub el "
     "hizb decalait toute la coloration tajwid (corrige le 2026-07-11 dans "
     "`tajweedSpansPerWord`), le layout QPC le compte comme un mot la ou "
     "`tajweedSpansPerWord` le filtre (note dans `mushaf_maquette_screen`), et "
     "les marques de waqf font tomber les regles attendues (2026-09-05). "
     "Le generateur `build_app_rules_assets.py` ne retire que le rub el hizb, "
     "et il verifie son comptage contre SON PROPRE `uthmani.jsonl` -- jamais "
     "contre le texte que l'app decoupe. Sa garantie « meme nombre de mots que "
     "le texte canonique », ecrite en tete du fichier et verifiee par assert, "
     "est donc VRAIE chez lui et FAUSSE dans l'app. REGLE : tout asset indexe "
     "positionnellement sur les mots doit etre verifie contre "
     "`splitExpectedWords`, pas contre le decoupage de son propre generateur."),

    ("mesure_verdict_tajwid_rendu_avant_la_detection",
     "[MESURE] La regle arrive jusqu'a 4,6 s APRES le verdict qu'elle contredit",
     "Mot 39 (session Al-Balad du 2026-09-05) : verdict VIOLET "
     "« idgham_ghunnah manquante » a 17:01:23.168, puis idgham_ghunnah p=1,000 "
     "sur 400 ms a 17:01:27.769 et p=1,000 sur 480 ms a 17:01:28.458. La chaine "
     "verrouille le mot des que la fenetre avance, alors que la tete tajwid "
     "continue de l'observer dans les fenetres suivantes. Sur cette session, "
     "4 des 10 violets etaient contredits par le journal lui-meme (iqlab a "
     "0,99 sur un mot, idgham a 1,00 sur 560 ms sur deux autres). Prendre le "
     "maximum des observations ne suffit donc PAS : au moment de trancher, la "
     "detection n'existe pas encore. Correctif : le mot est re-emis vers Dart "
     "quand ses regles s'enrichissent, et le violet retire -- sens autorise de "
     "« jamais un vert ne passe rouge » (on n'aggrave jamais, on repare)."),

    ("mort_seuils_de_duree_par_regle_tajwid",
     "[MORT] Filtrer les detections tajwid par une duree minimale par regle",
     "Seuils `SEUILS_MS` poses dans `ChaineRecitation` puis NEUTRALISES le "
     "2026-09-05 : ils rejetaient 86 detections a p=1,000 sur une seule "
     "session. Deux defauts, et le second est structurel : ils etaient batis "
     "sur `det.frames`, un compte dont l'utilisateur avait deja montre qu'il "
     "ne dit rien d'utilisable ; et une fenetre qui coupe la fin d'un mot rend "
     "une duree trop courte SANS abimer la probabilite. La duree reste "
     "journalisee et affichee -- elle ne tranche plus aucun verdict."),

    ("piege_mesurer_la_tete_tajwid_sur_un_bloc_long",
     "[PIEGE] Mesurer la tete tajwid sur un bloc de 20 s donne des probabilites fausses",
     "Erreur commise puis corrigee le 2026-09-05. J'ai conclu « le madd n'est "
     "pas reconnu » apres avoir passe un WAV entier au modele par blocs de "
     "20 s : `ghunnah` y tombait a 0,064 alors que la MEME session en app "
     "donnait 1,000. Cause : la normalisation du mel est PER-FEATURE, donc "
     "dependante de la longueur du bloc -- un bloc long ecrase les pics. "
     "Re-mesure en fenetres de 2,5 s (celles que l'app utilise reellement) : "
     "`madda_obligatory` = 0,987. REGLE : toute mesure hors device de la tete "
     "tajwid doit reproduire la LONGUEUR DE FENETRE de l'app, sinon elle ne "
     "mesure que l'effet de la normalisation."),

    ("mesure_la_lecture_tajwid_ecrivait_dans_les_statistiques",
     "[MESURE] Le mode lecture tajwid ecrivait partout dans les statistiques",
     "Signale par l'utilisateur le 2026-09-05 (« la lecture et verification de "
     "tajwid n'impacte pas les pourcentages, ce n'est pas de la recitation, "
     "c'est de la lecture ») et confirme dans le code : le mode ouvre "
     "`KaraokeRecitationScreen` avec `forcerModeNormal: true`, donc "
     "`_isReferenceSession` valait `false` et TOUTES les ecritures d'une vraie "
     "recitation partaient -- `RecitationErrorLogService.clearSurah` (une "
     "LECTURE effacait les stats d'erreur de la sourate), une session archivee "
     "de plus avec son taux de verts, les portions suivies, l'activite du "
     "jour, la serie, l'objectif et les mots acquis. Correctif : un garde "
     "`_sansStatistiques = _isReferenceSession || modeTajwid` sur les cinq "
     "points d'archivage et sur l'ouverture de session -- meme chemin que la "
     "session de reference, pour la meme raison (« ce n'est pas une vraie "
     "recitation notee »)."),

    ("piege_le_fond_du_karaoke_n_est_pas_celui_du_scaffold",
     "[PIEGE] Le fond de l'ecran de recitation est peint par `_ambientBackground`, pas par le `Scaffold`",
     "Constat 2026-09-05 : j'ai mis le fond du mode tajwid sur le "
     "`backgroundColor` du `Scaffold` et l'ecran est reste vert. Un `Container` "
     "plein ecran (`_ambientBackground`, degrade radial + trame) le recouvre "
     "integralement. La trace `[KaraokeOuverture] modeTajwid=true` a montre que "
     "le mode etait bien actif, ce que la couleur dementait. COROLLAIRE de la "
     "meme journee : changer le fond ne suffit pas non plus -- le texte tenait "
     "sa couleur de `_buildChunk` (`AppColors.cream`), parfait sur le vert et "
     "invisible sur parchemin ; seules ressortaient les lettres PORTANT une "
     "regle, qui tiennent leur couleur de `tajweedSpansPerWord`."),
]

LIENS = [
    ("regle_recoller_le_waqf_au_mot_precedent",
     "mesure_waqf_isole_eteint_le_tajwid_sur_42pc_des_versets", "shares_data_with",
     "le correctif et la mesure qui l'a impose"),
    ("piege_deux_decoupages_du_meme_texte",
     "mesure_waqf_isole_eteint_le_tajwid_sur_42pc_des_versets", "shares_data_with",
     "troisieme occurrence de la meme classe de bug"),
    ("mort_seuils_de_duree_par_regle_tajwid",
     "mesure_verdict_tajwid_rendu_avant_la_detection", "shares_data_with",
     "deux facons de perdre une detection franche sur le meme mot"),
    ("piege_mesurer_la_tete_tajwid_sur_un_bloc_long",
     "mesure_verdict_tajwid_rendu_avant_la_detection", "shares_data_with",
     "deux mesures de la tete tajwid faussees par le fenetrage"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step43.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
