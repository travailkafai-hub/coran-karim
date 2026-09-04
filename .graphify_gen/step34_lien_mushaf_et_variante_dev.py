#!/usr/bin/env python3
"""2026-09-04 : lien entre les deux mushaf, variante DEV, zoom systeme, balayage.

Valeurs mesurees sur device (captures) ou dans les binaires (metriques de
police lues par struct). Aucune n'est estimee.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_le_lien_entre_les_deux_mushaf_n_allait_que_dans_un_sens",
     "[PIEGE] L'aller partait du DEBUT de la sourate et le retour ne rapportait rien -- deux vues du meme texte qui divergent",
     "Deux defauts distincts sur le meme lien, trouves l'un apres l'autre par "
     "l'utilisateur. (1) LE RETOUR : `MushafMaquetteScreen(pageInitiale:)` "
     "recevait bien la page, mais rien ne revenait -- on pouvait feuilleter "
     "vingt pages au papier, le retour rendait la liste ou on l'avait laissee. "
     "(2) L'ALLER, signale ensuite (« la recherche ne se fait pas bien meme le "
     "premier sens, surtout si on scrolle puis on veut passer a mushaf "
     "papier ») : `_ouvrirVuePage` prenait `_verses.first.pageNumber`, donc la "
     "page ou COMMENCE la sourate, jamais celle qu'on regarde -- ouvrir le "
     "papier depuis Yusuf 25 renvoyait page 235 au lieu de 238. Le defaut etait "
     "connu et ECRIT dans le code (« a reprendre le jour ou l'ecran expose un "
     "verset visible »), jamais traite. CORRECTIF : `_versetVisible()` parcourt "
     "`_verseKeys` -- un `ListView.builder` ne construit que le voisinage de "
     "l'ecran, donc les versets ayant un `currentContext` SONT les candidats -- "
     "et garde le premier dont le bas depasse le haut de la fenetre. Aucune "
     "estimation d'offset : la hauteur d'un verset varie du simple au decuple. "
     "TEST DEVICE COMPLET (Yusuf) : Mushaf v.25-28 -> papier page 238 ; 3 pages "
     "-> 241 ; retour -> verset 44 (1er de la page 241) ; scroll -> v.64-67 ; "
     "bascule -> page 243. Les deux sens verifies."),

    ("regle_se_tromper_vers_le_debut_de_page_plutot_que_vers_la_fin",
     "[REGLE] Au retour du papier, viser le PREMIER verset de la page : se tromper fait relire, jamais sauter",
     "Arbitre en deux temps par l'utilisateur le 2026-09-04. D'abord la fin de "
     "page (« il doit prendre la situation de fin de verset qui existe dans la "
     "page »), puis revirement : « attends, je pense que c'est mieux debut de "
     "page, c'est plus logique ». Le raisonnement qui le justifie : viser la fin "
     "SUPPOSE que la page a ete lue jusqu'au bout, ce que rien ne garantit -- on "
     "peut l'avoir ouverte, parcourue a moitie, ou traversee en feuilletant. Se "
     "tromper vers le debut fait relire quelques versets ; se tromper vers la "
     "fin en fait SAUTER. Sur un texte qu'on memorise, les deux erreurs ne se "
     "valent pas. Vaut pour tout mecanisme de reprise de position."),

    ("mesure_amiri_n_a_aucune_marge_verticale",
     "[MESURE] Amiri occupe 1,76 a 2,76 em pour une boite de ligne de 1,72 -- marge nulle, elle casse la premiere",
     "Question de l'utilisateur : « pourquoi ce probleme apparemment que pour "
     "Amiri ? Les autres styles passent ». Metriques lues dans les fichiers de "
     "police (struct sur head/hhea/OS-2) : AMIRI ascender 1124 + descender -634 "
     "sur 1000 upem = 1,76 em en hhea, et winAscent 1850 + winDescent 910 = "
     "2,76 em en OS/2 ; BOUAZZI MAGHRIBI 1,40 em (hhea) et 1,52 em (OS/2). Or "
     "`height: 1.72` est IMPOSE a toutes les ecritures : `TextPainter` mesure "
     "donc 1,72 x taille pour chacune, mais les glyphes sont peints selon les "
     "metriques de LEUR police. Amiri n'a aucune marge -- elle passe tout juste "
     "sans zoom (verifie par capture sur S25 : page 6 complete) et deborde des "
     "que quoi que ce soit s'ajoute ; les autres ont 0,20 a 0,32 em de reserve "
     "et encaissent. Ce n'est donc pas Amiri qui est cassee : c'est la premiere "
     "a tomber. RESERVE ACTUELLE du code : 0,5 x taille, contre un depassement "
     "possible de 1,04 -- deux fois trop peu. Piste ouverte : une reserve PAR "
     "police, mesuree, au lieu d'une constante unique."),

    ("piege_la_page_mesuree_a_100_pourcent_peinte_au_zoom_systeme",
     "[PIEGE] La page est mesuree par TextPainter (sans zoom) et peinte par Text (avec le zoom systeme)",
     "Capture d'un testeur sur Galaxy S10+ : derniere ligne tranchee "
     "horizontalement ET fragments de texte hors du cadre a gauche et a droite. "
     "La MEME page (Al-Baqara p.6) rendue sans defaut sur le S25 de "
     "l'utilisateur. La taille de police de cette vue n'est pas choisie, elle "
     "est MESUREE par dichotomie pour remplir la hauteur -- mais la mesure passe "
     "par `TextPainter`, qui n'applique aucun facteur de zoom, tandis que le "
     "rendu passe par `Text`, qui applique celui du `MediaQuery`. Une page "
     "calculee pour 100 % et peinte a 130 % deborde en largeur ET en hauteur, "
     "les deux symptomes observes. Indice releve au passage : l'appareil de "
     "l'utilisateur lui-meme tourne avec `Physical density 480 / Override 510`, "
     "soit +6 % -- ce reglage est courant. CORRECTIF : "
     "`MediaQuery.withNoTextScaling` sur la page ENTIERE et non sur le seul "
     "corps, car le bandeau de sourate a une hauteur CONSTANTE "
     "(`compactHeight`) qui entre dans le calcul de la place disponible : s'il "
     "grossit, la reservation devient fausse. NON VERIFIE sur l'appareil du "
     "testeur -- lien tres coherent, pas une mesure."),

    ("piege_baisser_le_seuil_de_vitesse_ne_debloque_pas_le_balayage",
     "[PIEGE] Diviser les seuils de VITESSE ne rend pas le balayage plus sensible : le verrou est la DISTANCE",
     "« Je scrolle pour le balayage mais il faut vraiment que je fasse un long "
     "scroll. » Premiere tentative : `minFlingVelocity` et `tolerance.velocity` "
     "divises par 3. Retour : « le scroll ne marche pas aussi bien, il resiste "
     "encore pour basculer ». C'etait mal cible. `PageView` tranche entre un "
     "LANCER (tourne quelle que soit la distance, si la vitesse depasse le "
     "seuil) et un GLISSEMENT (tourne seulement au-dela de la MOITIE de "
     "l'ecran) : agir sur la vitesse n'ouvre que la premiere porte, un geste "
     "pose reste sous les DEUX seuils. CORRECTIF : `createBallisticSimulation` "
     "reecrit avec trois cas explicites -- geste franc, la direction decide ; "
     "geste lent, bascule des 28 % de page ; geste infime, page la plus proche. "
     "28 % et pas moins : cet ecran tourne DEJA la page au simple tap, trop bas "
     "un doigt qui hesite ferait sauter deux pages."),

    ("outil_variante_dev_applicationid_suffixe",
     "[OUTIL] La variante DEV (`applicationIdSuffix .dev`) coexiste avec la version du Play Store",
     "Demande utilisateur : « quand tu veux installer, installe en version DEV, "
     "comme ca je peux telecharger l'app du Play Store ». Resout deux blocages "
     "d'un coup. (1) Un APK debug ne s'installe pas sur un APK release : adb "
     "rend INSTALL_FAILED_UPDATE_INCOMPATIBLE (signatures differentes), et la "
     "seule issue etait de DESINSTALLER, donc de perdre preferences, journal et "
     "captures WAV -- ce qui a bloque plusieurs installations le 2026-09-04. "
     "(2) Meme signature, la version testee ECRASAIT celle du Store. Deux "
     "applicationId font deux applications : icones, donnees et mises a jour "
     "separees. MISE EN OEUVRE : `applicationIdSuffix = \".dev\"`, "
     "`versionNameSuffix = \"-dev\"`, `resValue(\"string\", \"app_name\", "
     "\"Coran Karim DEV\")` -- ce dernier exige `buildFeatures { resValues = "
     "true }` (ferme par defaut depuis AGP 8 : « Build Type debug contains "
     "custom resource values, but the feature is disabled ») et que le manifeste "
     "porte `@string/app_name` au lieu du nom en dur. ⚠️ PIEGE DE DIAGNOSTIC : "
     "journaux et captures vivent desormais sous "
     "`com.corankarim.coran_karim.dev/` -- une analyse faite sur le journal de "
     "l'autre application ne se voit pas."),
]

LIENS = [
    ("piege_le_lien_entre_les_deux_mushaf_n_allait_que_dans_un_sens",
     "regle_se_tromper_vers_le_debut_de_page_plutot_que_vers_la_fin",
     "depends_on",
     "La cible du retour a ete arbitree dans ce chantier"),
    ("mesure_amiri_n_a_aucune_marge_verticale",
     "piege_la_page_mesuree_a_100_pourcent_peinte_au_zoom_systeme",
     "depends_on",
     "La marge nulle d'Amiri explique pourquoi elle seule casse sous le zoom"),
    ("outil_variante_dev_applicationid_suffixe",
     "piege_le_lien_entre_les_deux_mushaf_n_allait_que_dans_un_sens",
     "depends_on",
     "Sans la variante DEV, le correctif ne pouvait pas etre installe pour test"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step34.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
