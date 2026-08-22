#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ordre de la shadda en Warsh, et ids de la tete tajwid traduits par position."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_shadda_ordre_oppose_hafs_warsh",
     "[MESURE] Les deux riwayat ordonnent la shadda A L'OPPOSE -- un mot Warsh sur quatre en payait le prix",
     "`normalizeTraining` force shadda+voyelle, regle calibree sur le HAFS le "
     "2026-07-16 (« verifie 100 % shadda-premier sur les manifests reels ») puis "
     "appliquee au Warsh sans y etre remesuree. Mesure du 2026-08-22 sur les "
     "fichiers eux-memes : le TEXTE Warsh porte shadda+voyelle, mais le "
     "VOCABULAIRE Warsh du modele a ete appris en voyelle+shadda (`ِّ` piece 23, "
     "`َّ` 46, `ُّ` 55). La piece fusionnee ne pouvait donc JAMAIS etre choisie, "
     "et la shadda partait en jeton ISOLE coince entre deux morceaux de mot -- "
     "micro-jeton qu'un CTC « pique » n'emet pas a un instant precis. Score "
     "effondre sur un mot parfaitement prononce, `free` proche de 0 a l'appui. "
     "CHIFFRES sur 22 643 mots distincts : shadda isolee 5 940 (26,2 %) dans "
     "l'ordre du texte, 173 (0,8 %) dans l'ordre du vocabulaire -- 5 767 mots "
     "reparees, 25,5 % du texte. CE N'EST PAS DE L'ENTRAINEMENT : model.onnx, "
     "vocab_warsh.json et warsh.model sont inchanges."),

    ("piege_changer_la_normalisation_sans_les_cles_du_dictionnaire",
     "[PIEGE] Changer la normalisation SANS regenerer les cles du dictionnaire : 100 % -> 74 % de cles trouvees",
     "En corrigeant l'ordre de la shadda, la premiere version de "
     "`normalizeTrainingWarsh` ne reordonnait RIEN -- hypothese que le texte "
     "Warsh etait deja dans l'ordre du vocabulaire. FAUX, et c'est le controle "
     "avant/apres qui l'a montre : le taux de cles trouvees dans "
     "`word_tokens_warsh.json` tombait de 100,00 % a 74,09 % (20 059 mots "
     "introuvables). La normalisation et les cles du dictionnaire vont "
     "ENSEMBLE : changer l'une sans l'autre casse le lookup en silence (l'app "
     "retombe sur la tokenisation greedy, aucune erreur levee). Apres "
     "correction (inversion exacte) : 77 428 / 77 431 = 100,00 %. REGLE : "
     "toute modification de `normalizeTraining*` exige de remesurer le taux de "
     "cles trouvees AVANT de deployer -- appliquer la regle du Hafs au Warsh ET "
     "ne rien appliquer du tout etaient TOUS DEUX faux."),

    ("piege_ids_tete_tajwid_traduits_par_position",
     "[PIEGE] Les ids de la tete tajwid traduits par POSITION -- decalage de 2, inerte donc invisible",
     "`FastConformerVerifier` traduisait les ids de regles par "
     "`TajwidRule.values[id]`. Le commentaire posait pourtant la condition noir "
     "sur blanc (« TajwidRule.values[i] doit rester le meme ordre que "
     "rules.json ») mais rien ne la verifiait, et elle a cesse d'etre vraie "
     "avec le modele a 17 classes : le modele a DEUX madd (madd_long, "
     "madd_court) la ou l'enum en a QUATRE, donc tout est decale de 2 a partir "
     "de l'index 2. id 2 = ghunnah lu `madda_permissible` ; id 3 = ikhafa lu "
     "`madda_normal` ; id 11 = laam_shamsiyah lu `idgham_mutajanisayn` ; id 12 "
     "= ham_wasl lu `idgham_mutaqaribayn` ; id 14 = qalaqah lu `ham_wasl`. "
     "INERTE tant que le preset n'est pas `tajwid` (`_activeRules` vide), ce "
     "qui le rendait DANGEREUX : au rebranchement, le journal natif "
     "`[tajwidDuree]` (qui passe par `front.nomsRegles`) serait reste JUSTE "
     "pendant que les verdicts Dart auraient ete faux. CORRIGE : traduction par "
     "le NOM lu dans rules.json, jamais par la position ; un nom inconnu de "
     "l'enum est IGNORE. Ne pas confondre avec `RuleSymbols` (texte annote, "
     "U+E000+i), dont la correspondance reste valide."),

    ("mesure_seuils_tajwid_livres_sont_ceux_du_f1",
     "[MESURE] Les seuils tajwid livres sont ceux du F1, pas ceux de la discrimination",
     "Lu dans la documentation du modele elle-meme "
     "(`modele_4tetes_2026-08-21/docs/DECOUVERTES_ENTRAINEMENT_2026-08-20.md` "
     "§15) : « Calibrer sur le F1 ne calibre pas la discrimination. Ecarts "
     "entre les deux optima : 0,10 contre 0,95 (idgham_mutaqaribayn), 0,40 "
     "contre 0,80 (idgham_mutajanisayn), 0,60 contre 0,95 (idgham_shafawi). » "
     "Or `seuils_tajwid.json` livre porte bien 0,95 pour idgham_mutaqaribayn -- "
     "le seuil que ce document qualifie d'absurde, qui donne 0 % de rappel "
     "alors que la classe remonte a 80 % de rappel pour 2,7 % d'invention a "
     "0,10. NON CORRIGE VOLONTAIREMENT : le meme document pose la reserve qui "
     "l'interdit (« potentiellement sur-ajustes au jeu de jugement, a verifier "
     "sur une part tenue a l'ecart avant de les livrer »). C'est cette "
     "verification qui manque, et elle est du cote de la machine "
     "d'entrainement."),

    ("mesure_madd_long_invente_une_fois_sur_deux",
     "[MESURE] `madd_long` invente une fois sur deux -- le pont des madd reste impossible",
     "Documentation du modele : madd_long a 94,5 % de rappel mais **50,4 % "
     "d'invention**, contre 0,0 % (qalaqah, idgham_wo_ghunnah, "
     "idgham_mutajanisayn), 7-11 % (laam_shamsiyah, ham_wasl, iqlab, "
     "idgham_shafawi, ghunnah, madd_court, ikhafa_shafawi) et 17-22 % (slnt, "
     "idgham_ghunnah, ikhafa). Raison donnee par l'entrainement : « c'est une "
     "regle de DUREE, pas de timbre -- distinguer un madd de 2 temps d'un madd "
     "de 4-6 temps demande de mesurer une longueur, la ou une ghunnah ou une "
     "qalqala laissent une signature spectrale nette ». CONSEQUENCE : le pont "
     "entre les 4 noms de madd du texte annote "
     "(madda_necessary/obligatory/permissible/normal) et les 2 du modele n'est "
     "PAS pose et ne doit pas l'etre tant que ce chiffre tient -- il produirait "
     "un faux positif sur un madd long correct une fois sur deux. madd_court "
     "(10-11 %) est, lui, exploitable."),
]

LIENS = [
    ("piege_changer_la_normalisation_sans_les_cles_du_dictionnaire",
     "mesure_shadda_ordre_oppose_hafs_warsh", "shares_data_with",
     "le correctif et le piege rencontre en l'appliquant"),
    ("mesure_shadda_ordre_oppose_hafs_warsh",
     "piege_justifier_le_warsh_par_le_hafs", "shares_data_with",
     "meme racine : une regle calibree sur une riwaya appliquee a l'autre"),
    ("mesure_seuils_tajwid_livres_sont_ceux_du_f1",
     "piege_fichier_de_seuils_dans_une_forme_non_lue", "shares_data_with",
     "meme fichier de seuils, deux defauts distincts (forme, puis valeurs)"),
    ("mesure_madd_long_invente_une_fois_sur_deux",
     "piege_ids_tete_tajwid_traduits_par_position", "shares_data_with",
     "les deux prerequis qui bloquent le rebranchement du tajwid"),
    ("piege_ids_tete_tajwid_traduits_par_position",
     "regle_madd_long_et_madd_court_par_comparaison", "shares_data_with",
     "meme table de classes, meme decalage de deux entre modele et enum"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step41.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
