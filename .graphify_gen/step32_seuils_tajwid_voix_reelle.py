#!/usr/bin/env python3
"""Soiree du 2026-09-03 : la tete tajwid voyait, le seuil rejetait.

Toutes les valeurs viennent du banc direct (WAV de session passe au modele
deploye hors app, mel revalide par la transcription CTC qui sort exacte) ou du
journal de session. Aucune n'est estimee. Trois erreurs de methode de la meme
soiree y figurent : une mesure fausse consignee vaut mieux qu'une mesure fausse
refaite six mois plus tard.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_tete_tajwid_voit_mais_le_seuil_rejette",
     "[MESURE] La tete tajwid VOIT la ghunna a 0,633 -- le seuil strict lui en demandait 0,777",
     "Question de l'utilisateur qui a debloque la soiree : « pourquoi elle ne "
     "voit rien, vas-y utilise le meme WAV et teste le modele ! ». Banc direct, "
     "hors app : le WAV de la session An-Nas 114:1 (3,12 s) passe au modele "
     "deploye `quatre-tetes-warsh-v5-2026-08-31`. CONTROLE DE VALIDITE d'abord, "
     "sans lequel le banc ne prouve rien : le mel est reimplemente a la main "
     "(pas de librosa sur la machine), donc une erreur de preprocessing "
     "produirait un silence de la tete qu'on lirait a tort comme un defaut de "
     "modele -- on decode donc AUSSI la tete CTC, qui rend le texte exact, "
     "harakat comprises. Le mel est juste, les sorties tajwid sont "
     "exploitables. RESULTAT sur le mot final : ghunnah 0,633 (seuil effectif "
     "strict 0,863 x 0,90 = 0,777) -> REJETEE ; qalaqah 0,661 -> rejetee ; "
     "madda_obligatory 0,033 ; madda_permissible 0,001. La tete n'est donc PAS "
     "aveugle sur ghunnah et qalaqah : le seuil les jette. Facteur requis par "
     "cette voix : 0,73 (ghunnah), 0,71 (qalaqah). CORRECTIF applique : "
     "facteurs de rigueur 0,90/0,70 -> 0,70/0,50, verifie sur le meme audio -- "
     "le mot passe au VERT dans les deux modes, AUCUNE sur-detection a 0,50."),

    ("mesure_les_deux_madd_ne_sortent_pas_du_modele",
     "[MESURE] Les madd sont ATTENDUS, REALISES, et la tete rend 0,033 et 0,001 -- aucun seuil ne les rattrape",
     "Meme banc, meme mot, ou `madda_permissible` est attendue par le texte "
     "annote ET realisee par le recitateur. La tete rend 0,001 ; "
     "`madda_obligatory` rend 0,033 ailleurs dans la meme prise. Ce ne sont pas "
     "des valeurs « sous le seuil » : ce sont des canaux muets. Les faire passer "
     "demanderait un facteur de 0,04, soit un seuil de 0,037, ou n'importe quel "
     "bruit declenche la regle et l'app valide tout le monde -- le code porte "
     "deja la mesure qui l'interdit : un seuil plat a 0,5 sur-detecte de +209 % "
     "a +240 %. DECISION : les deux madd rejoignent `_signalNonFiable` "
     "(observation seule, plus de violet). Ce n'est PAS un abandon -- le madd "
     "est la regle la plus audible et la plus importante pedagogiquement -- mais "
     "un retrait du jugement tant que la taxonomie n'est pas instruite. PISTE "
     "NOMMEE : `classes_10.json` nomme les madd par leur DUREE (madd_long / "
     "madd_court) et non par leur statut juridique, et `FastConformerCtc` les "
     "decide par comparaison entre les deux canaux -- c'est la qu'il faut "
     "chercher."),

    ("piege_le_modele_a_10_classes_pas_17",
     "[PIEGE] La taxonomie d'entrainement compte 10 classes, pas 17 : ikhafa, idgham_ghunnah et iqlab n'en font qu'UNE",
     "Observation repetee TROIS sessions de suite avant d'en trouver la cause : "
     "`ikhafa`, `idgham_ghunnah` et `iqlab` sortaient avec des effectifs, des "
     "probabilites et des durees RIGOUREUSEMENT identiques. Lu comme une "
     "confusion du modele pendant trois analyses. C'est en fait une FUSION "
     "documentee : `classes_10.json`, livre avec le modele, porte "
     "`ikhfa_idgham_noun` = ikhafa 3088 + idgham_ghunnah 2275 + iqlab 314, et "
     "`shafawi` = idgham_shafawi 506 + ikhafa_shafawi 288. Le modele ne SAIT PAS "
     "les distinguer, et l'app validera un iqlab attendu si le recitant fait une "
     "ikhafa. Consequence assumee, arbitrage ouvert. NE PAS relire une identite "
     "parfaite entre trois classes comme un defaut de detection : verifier "
     "d'abord la taxonomie d'entrainement."),

    ("piege_l_app_lit_les_regles_par_INDICE",
     "[PIEGE] L'app lit les regles PAR INDICE (`TajwidRule.values[id]`) -- un modele mal ordonne donne VIOLET PARTOUT",
     "Consigne dans DECOUVERTES_2026-08-31.md §3 comme « la decouverte la plus "
     "couteuse », re-verifiee ici. `fastconformer_verifier.dart` fait "
     "`TajwidRule.values[id]` : `rules.json` ne sert qu'a COMPTER les classes, "
     "jamais a les nommer. Un modele dont les canaux ne suivent pas l'ordre de "
     "l'enum est mal interprete des le premier decalage -- mesure a l'epoque : "
     "canal 3 (`ghunnah`) lu `madda_normal`, canal 9 (`qalaqah`) lu `iqlab`, "
     "donc AUCUNE regle attendue jamais reconnue comme realisee, donc violet "
     "partout, y compris sur un recitateur d'enseignement qui les applique "
     "toutes. VERIFICATION FAITE le 2026-09-03 sur le modele reellement "
     "installe : son `rules.json` est bien dans l'ordre exact de l'enum (export "
     "`--ordre_app`), et `tajwid_logprobs` sort 17 canaux. Ce piege-la n'est "
     "donc PAS actif aujourd'hui -- mais il se reactive au moindre reexport."),

    ("piege_seuils_calibres_sur_cinq_professionnels",
     "[PIEGE] Calibrer les seuils sur cinq recitateurs professionnels rend le mode strict inatteignable",
     "Les seuils du 2026-09-03 viennent de "
     "`seuils_tajwid_5reciteurs_jvm.json` (Ayman Sowaid, Husary, Abdul Basit, "
     "Minshawy, As-Sudais), ou la ghunna moyenne sort a 0,959 et les huit seuils "
     "calibres valent tous entre 0,976 et 0,999. En prendre 90 % donnait 0,88 a "
     "0,90 pour TOUTES les regles. Mesure sur la voix de l'utilisateur : sa "
     "ghunna sort a 0,633, sa qalqala a 0,661 -- correctement realisees, et "
     "rejetees. Symptome vecu : « c'est pas normal qu'un reciteur tajwid signale "
     "erreur ». REGLE : un seuil calibre sur des voix professionnelles mesure la "
     "distance a ces voix, pas la realisation de la regle. Calibrer sur la voix "
     "CIBLE, ou accepter un facteur de rigueur qui absorbe l'ecart."),

    ("piege_quatre_ecrans_devinaient_la_cause_du_violet",
     "[PIEGE] Redeviner une cause deja connue : `classifyError` sortait sur `harakat` avant d'atteindre `tajwid`",
     "Constat utilisateur sur l'entrainement par palier : « je ne vois aucun "
     "violet alors que je fais expres de ne pas faire de regle », alors que le "
     "journal portait bien les lignes `[V2tajwid]` et que le mot passait a "
     "`unclear`. Le provider connait la cause avec CERTITUDE a l'instant ou il "
     "degrade le mot -- il vient de constater la regle manquante -- et la jetait "
     "aussitot. Quatre ecrans (palier, coach, reciter, fiche du mot) la "
     "redemandaient a `classifyError`, qui la REDEVINE en recomparant attendu et "
     "entendu, et qui teste les harakat AVANT le tajwid (a juste titre : une "
     "regle ne se juge que si les lettres sont bonnes). Une diacritique de plus "
     "dans la transcription suffisait a le faire sortir sur `harakat` : la "
     "branche `tajwid` n'etait jamais atteinte, et le mot se peignait ORANGE au "
     "lieu de VIOLET -- deux gestes differents pour le recitateur. CORRECTIF : "
     "registre `_motsDegradesTajwid` pose a la degradation, lu par les quatre "
     "ecrans. Un seul endroit SAIT au lieu de quatre qui devinent."),

    ("mesure_le_palier_court_juge_tout_a_la_fermeture",
     "[MESURE] Sur un palier de 4 mots, AUCUN mot n'est juge pendant la recitation -- tout tombe a la fermeture, et l'ecran bascule 10 ms apres",
     "Chronologie relevee sur le palier An-Nas 114:1 : les quatre mots sont "
     "verrouilles entre 22:52:16.367 et 22:52:16.372, tous avec le declencheur "
     "`fermeture de session`. La degradation tajwid du mot 3 arrive a .374, la "
     "fin de tour a .381, et `verset termine -> CONTROLE` a .382 -- l'ecran "
     "bascule 10 ms apres le verdict. La couleur est calculee correctement et "
     "n'est JAMAIS peinte. CAUSE : en v2 un mot ne devient definitif que lorsque "
     "la fenetre a avance au-dela de lui ; sur quatre mots elle n'avance jamais "
     "assez (obs=1 partout, d'ou `tajwidFiable=false` systematique). Sur les "
     "passages longs de la meme session, 91 verdicts sur 163 tombent bien "
     "pendant la recitation. C'est la BRIEVETE du palier qui produit l'effet, "
     "pas un defaut de la chaine. NON CORRIGE : la pause d'affichage avant "
     "bascule n'a pas ete faite."),

    ("piege_confondre_tajwidFiable_avec_le_seuil",
     "[PIEGE] `tajwidFiable=false` ne vient PAS du seuil : c'est le nombre d'observations",
     "Hypothese formulee en session : « tajwidFiable false est du parce qu'elle "
     "ne depasse pas le seuil, il faut un seuil a 0,2 ou 0,1 pour qu'il passe a "
     "true ». Faux, et la distinction commande le correctif. `tajwidFiable` vaut "
     "`votantes.size >= 2 || estDefinitif` cote natif : c'est le nombre "
     "d'OBSERVATIONS completes du mot, jamais une probabilite. Preuve dans le "
     "journal de la session : le mot 3 a bien ete degrade MALGRE "
     "`tajwidFiable=false`, parce que `tajwidSansDoubleObservation` (pose a "
     "l'entree du palier) leve cette exigence. Ce qui depend du seuil, c'est "
     "`detectees=` vide. Baisser un seuil ne fera jamais passer `tajwidFiable` a "
     "true."),

    ("mesure_le_terrain_de_test_conditionne_ce_qu_on_peut_voir",
     "[MESURE] Sur Al-Balad, 26 % des mots seulement portent une regle jugeable -- tester le tajwid la-dessus ne montre rien",
     "Mesure sur `assets/data/quran_rules_annotated.json` (texte complet, pas "
     "les journaux) apres le constat « je ne vois aucun violet ». Part des mots "
     "portant AU MOINS UNE regle jugeable (hors les 4 portees par le texte et "
     "hors qalaqah) : Al-Balad 26 %, Al-Fatiha 24 %, An-Naba 1-20 26 %, "
     "Al-Baqara 1-20 36 %, Al-Ikhlas 6 %. Al-Balad est une sourate a QALQALA "
     "(18 % de ses mots n'ont qu'elle), or qalaqah est retiree du jugement : on "
     "peut y ecraser toutes ses qalqalas sans que l'app dise rien. An-Nas est un "
     "bon terrain (40 % jugeables, 0 % de qalaqah pure). Al-Ikhlas est le pire "
     "terrain possible : UN seul mot jugeable. AVANT de conclure qu'un mecanisme "
     "de tajwid ne marche pas, verifier que le passage teste porte des regles "
     "que l'app peut juger."),

    ("piege_j_ai_donne_72_pourcent_pour_15_pourcent",
     "[PIEGE] Un taux calcule sur les mots d'UN journal court n'est pas le taux du corpus -- 72 % annonce pour 15 % reel",
     "Affirme en session : « 72 % des mots du palier ont tajwidFiable=false ». "
     "Le chiffre venait d'un seul journal de 14 mots (`p2.log`, 71 %). Mesure "
     "sur les 17 journaux disponibles : 14 a 15 % en recitation continue (s3 a "
     "s8, 506 a 937 mots), 41 a 71 % sur les seules sessions tres courtes. La "
     "conclusion CHANGE : le controle n'est pas aveugle au tajwid, il l'est sur "
     "environ un mot sur sept. Meme erreur repetee le meme soir sur « 33 a 45 % "
     "des mots d'Al-Balad ne portent que qalaqah » (mesure sur les journaux) "
     "contre 18 % sur le texte complet. REGLE : un taux issu d'un journal porte "
     "sur les mots ATTEINTS ET JUGES, jamais sur le corpus -- le dire, ou "
     "mesurer sur l'asset."),
]

LIENS = [
    ("mesure_tete_tajwid_voit_mais_le_seuil_rejette",
     "piege_seuils_calibres_sur_cinq_professionnels",
     "depends_on",
     "Le seuil qui rejette vient du calibrage sur les cinq professionnels"),
    ("mesure_tete_tajwid_voit_mais_le_seuil_rejette",
     "mesure_les_deux_madd_ne_sortent_pas_du_modele",
     "semantically_similar_to",
     "Meme banc, meme mot : deux causes opposees separees par la meme mesure"),
    ("mesure_les_deux_madd_ne_sortent_pas_du_modele",
     "piege_le_modele_a_10_classes_pas_17",
     "depends_on",
     "Les madd sont nommes par leur DUREE dans la taxonomie a 10 classes"),
    ("piege_le_modele_a_10_classes_pas_17",
     "piege_l_app_lit_les_regles_par_INDICE",
     "semantically_similar_to",
     "Deux facons distinctes dont la nomenclature du modele trahit l'app"),
    ("piege_quatre_ecrans_devinaient_la_cause_du_violet",
     "mesure_le_palier_court_juge_tout_a_la_fermeture",
     "depends_on",
     "Corriger la couleur ne suffit pas si l'ecran bascule avant de la peindre"),
    ("piege_confondre_tajwidFiable_avec_le_seuil",
     "mesure_le_palier_court_juge_tout_a_la_fermeture",
     "depends_on",
     "obs=1 sur un palier court est la vraie cause de tajwidFiable=false"),
    ("piege_j_ai_donne_72_pourcent_pour_15_pourcent",
     "mesure_le_terrain_de_test_conditionne_ce_qu_on_peut_voir",
     "semantically_similar_to",
     "Deux erreurs de denominateur commises la meme soiree"),
]


def sha():
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


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
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
