#!/usr/bin/env python3
"""Fin de sourate : cadrage de la fenetre finale, cloture de session, Coach.

Mesures du 2026-08-14 (session live An-Nasr + rejeu hors device du WAV capte
par l'app sur le modele DEPLOYE trois-tetes-2026-08-04-combine).
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("symptome_dernier_mot_de_sourate_jamais_fige",
     "[SYMPTOME] Le dernier mot d'une sourate reste `provisoire` a jamais -- nait dans le CADRAGE de la fenetre finale, se voit dans le Decideur",
     "Session live An-Nasr : `mot=22 \"تَوَّابًۢا\" -> provisoire:orange | "
     "gop=-0.74 forced=-0.85 free=-0.11 obs=1 entendu=\"تَوَّابًا\"`. Le mot "
     "etait bien recite. Le WAV brut capte par l'app, rejoue hors device sur "
     "le modele DEPLOYE, seule la largeur de fenetre changeant : 4,00 s -> "
     "\"تَوَّابًا\" (le `ۢ` U+06E2 manque, un seul codepoint d'ecart) ; "
     "6,72 s -> \"تَوَّابًۢا\" EXACT ; 8 s et 10 s -> EXACT. La fenetre "
     "reellement emise par `ConstructeurDeFenetres.terminer()` faisait 4,00 s. "
     "Le defaut ne nait donc NI dans le modele NI dans la recitation : c'est "
     "un cadrage. Deux causes se cumulaient -- (1) fenetre trop courte, d'ou "
     "le gop -0,74 sous le seuil vert -0,45 ; (2) `obs=1`, une seule fenetre "
     "couvrant ce mot, alors que le Decideur exige k=2 fenetres distinctes."),

    ("var_min_fenetre_finale_8s",
     "var_minFenetreFinaleEch = 8,0 s -- longueur minimale de la fenetre de fin de session (ConstructeurDeFenetres)",
     "Mesure ci-dessus : 4,00 s rend le mot FAUX, 6,72 s le rend EXACT. 8 s "
     "garde une marge sans depasser `maxEch`. Implementation : `terminer()` "
     "repart du bord gauche de la coupe PRECEDENTE (`avantDerniereCoupe`) "
     "quand le bloc final est plus court -- l'audio est deja dans le tampon, "
     "`compacter()` le conserve toujours. Aucun seuil nouveau invente : la "
     "borne haute reste `maxEch`, deja en place. Le silence de lookahead "
     "(`lookaheadEch`, 1,04 s) est ajoute au meme endroit : a la fin d'une "
     "sourate le micro s'arrete avec le recitateur, ce silence n'arrive "
     "jamais de lui-meme, et sans lui le dernier mot n'est jamais interieur."),

    ("piege_fenetre_finale_dupliquee_vaut_deux_preuves",
     "[PIEGE] Elargir la fenetre finale faisait emettre sa JUMELLE de fusion sur le MEME audio -- deux ids distincts, une seule mesure",
     "Defaut introduit ET corrige le 2026-08-14, dans la meme heure. En "
     "posant `derniereCoupe = avantDerniereCoupe` pour elargir la fenetre de "
     "fin, `couper()` remplissait aussi sa condition de fusion et emettait "
     "`bloquer(avantDerniereCoupe, position)` -- desormais STRICTEMENT le "
     "meme audio que la fenetre primaire, avec un `id` different. Le Decideur "
     "y aurait vu `idsDistincts == true` sur k=2 et fige un verdict sur UNE "
     "SEULE mesure deguisee en deux, c'est-a-dire exactement la fraude que "
     "k=2 existe pour empecher. Correctif : `avantDerniereCoupe = -1` dans le "
     "meme bloc. Regle a retenir : deux ids ne valent une preuve que s'ils "
     "portent deux CONTEXTES differents."),

    ("mort_k1_a_la_fermeture",
     "[MORT] k=1 pour la passe de fermeture (Decideur.statuts(fermeture=true)) -- ecrit puis retire le meme jour",
     "Le probleme vise est reel : a la fermeture, `k=2` (2e observation) et "
     "`recitateurPasse` (un mot POSTERIEUR observe) sont structurellement "
     "insatisfiables -- aucune fenetre future, aucun mot posterieur. Les "
     "derniers mots restaient `provisoire` pour toujours. `k=1` a la "
     "fermeture a ete implemente, puis RETIRE sur arbitrage utilisateur : "
     "« on peut garder k=2 mais rajouter a la fin de chaque sourate صدق الله "
     "العظيم si on a un audio ». Raisonnement retenu comme meilleur : reciter "
     "une phrase APRES la sourate rend le dernier mot non-dernier, il obtient "
     "sa 2e observation et son contexte droit NATURELLEMENT, sans qu'aucune "
     "regle de preuve ne cede. Ne pas reintroduire k=1 sans cause nouvelle : "
     "ce serait figer un verdict sur une seule mesure. Le cas « la phrase "
     "n'est pas dite » se resout en laissant le mot NON JUGE, ce qui ne "
     "penalise pas (regle `nonJuges` de `_compterMots`)."),

    ("piege_enchainement_de_page_franchit_les_sourates",
     "[PIEGE] L'enchainement suivait la PAGE du Mushaf, pas la sourate -- cible x4, et le dernier mot recite n'etait plus le dernier de la cible",
     "Regle utilisateur ancienne (« le controle se fait par sourate, jamais "
     "plusieurs sourates en meme temps ») non respectee par "
     "`_maybeExtendNextPage`, qui chargeait la page suivante du Mushaf sans "
     "regarder les frontieres de sourate. Mesure sur device : session "
     "demarree sur An-Nasr, `[CTL][PARAMS] cible=23 mots`, puis `[COUTURE] "
     "mots=93` -- quatre sourates dans la cible. DEUX consequences : l'ecran "
     "montrait la suite d'une autre sourate ; et surtout le dernier mot "
     "RECITE (22) etait tres loin de la fin de la cible (93), donc aucune "
     "mecanique de fin de session ne pouvait le traiter comme un dernier mot. "
     "C'est ce qui rendait aussi inoperante l'idee de la phrase de fin : "
     "placee en queue de cible, elle serait tombee au mot 93. Correctif : "
     "l'extension filtre sur `surahNumber` et pose `_noMorePages` des que la "
     "page deborde sur une autre sourate."),

    ("symptome_session_ouverte_jamais_fermee",
     "[SYMPTOME] Session archivee ouverte et JAMAIS fermee sur la fleche retour -- nait dans le garde d'entree de stopContinuous()",
     "Journal device : `[Archive] session 103 ouverte (sourate=110 1-3)` a "
     "10:25:30, et AUCUN `session fermee` ensuite -- ni erreur. La liste du "
     "Coach ne montrant que les sessions avec `ended_at`, la recitation "
     "n'apparaissait nulle part. Cause : `stopContinuous()` sort des sa "
     "premiere ligne (`if (!state.isActive || !state.continuous) return;`) et "
     "c'est LUI qui porte `v2Terminer()` ; tout ce qui suivait dans le bloc "
     "de sortie (cloture d'archive, comptabilisation Coach, relache du micro) "
     "etait mort. Correctifs : attente BORNEE a 5 s sur `stopContinuous()`, "
     "puis `finaliserPourPause()` appele SANS CONDITION (attente de la file "
     "PCM puis `v2Terminer`), puis cloture de l'archive sur l'etat A JOUR "
     "(`notifier.etatCourant`, pas `_dernierEtatConnu` fige au dernier build)."),

    ("piege_deja_rate_confondu_avec_oubli",
     "[PIEGE] Exclure `deja_rate` de `words_green` fait chuter des scores RETROACTIVEMENT, sans aucun oubli",
     "Tente puis ANNULE le 2026-08-14, dans l'heure. Objectif vise : compter "
     "l'oubli (souffleur declenche) comme une erreur, pour qu'une session "
     "avec oubli ne puisse plus afficher 100 %. Filtre pose : `AND "
     "w.deja_rate = 0` dans le sous-select `words_green`. Constat utilisateur "
     "immediat : Al-Masad et Al-Falaq, a 100 %, sont tombees SOUS 100 % « "
     "pourtant y avait pas d'oubli ». Cause : `deja_rate` signifie « a deja "
     "ete faux au moins une fois » (statuts `error`/`oubli`/`unclear`) et est "
     "MONOTONE -- des mots simplement corriges lors de sessions ANTERIEURES "
     "le portaient encore. Le filtre penalisait donc du passe deja repare. "
     "Deux notions distinctes a ne plus confondre : `deja_rate` = a deja ete "
     "faux ; OUBLI = le souffleur a du lancer l'audio. Ce dernier n'a aucune "
     "colonne : il en faut une (`souffle`, migration v6 -> v7, monotone, "
     "exclue du score). Le marquage GRIS a l'ecran, lui, est correct : il "
     "s'appuie sur `_motsOublies`, alimente a l'instant ou le souffleur part."),

    ("piege_progression_coach_sur_compteur_cumulatif",
     "[PIEGE] Barre de progression du Coach calculee sur `jours_actifs.mots_recites` -- elle montait en REPETANT le meme passage",
     "Premiere version du tableau de bord (2026-08-14) : avancement = "
     "`motsPeriode / 322,6` (77 430 mots de Coran / 240 quarts). Defaut : "
     "`mots_recites` est ADDITIF a chaque session, donc quinze recitations "
     "d'An-Nasr (23 mots) valaient 345 mots, soit « plus d'un quart » -- "
     "100 % affiche sans un seul mot NOUVEAU memorise. Un pourcentage "
     "d'avancement qui monte en repetant le meme passage ne mesure rien. "
     "Source corrigee : `portions`, dedupliquee par construction "
     "(`UNIQUE(portion_id, ayah_number, word_in_ayah)`), ou la part acquise "
     "d'un quart vaut `wordsGreen / wordsTotal`, plafonnee a 1 par portion. "
     "Ne pas reintroduire de conversion mots -> quart sur un compteur "
     "cumulatif."),

    ("piege_invalidation_riverpod_gardee_par_mounted",
     "[PIEGE] `if (mounted)` sautait l'invalidation du Coach sur le SEUL chemin ou elle comptait",
     "Constat utilisateur : « il manque le rafraichissement du tableau de "
     "bord ». Le bloc `ref.invalidate(...)` de `_cloturerArchive` etait garde "
     "par `if (mounted)`. Or le chemin le plus frequent -- la fleche retour "
     "-- appelle cette methode DEPUIS `dispose()`, apres `stopContinuous()` : "
     "`mounted` y vaut toujours `false`. L'invalidation etait donc "
     "systematiquement sautee, et le Coach affichait l'etat d'AVANT la "
     "recitation qu'on venait de terminer. Correctif : capturer le "
     "`ProviderContainer` (`ProviderScope.containerOf(context, listen: "
     "false)`) au premier build -- il appartient au ProviderScope de l'app et "
     "survit a n'importe quel ecran, contrairement a `ref`. Meme famille que "
     "le defaut `ref` dans `dispose()` deja documente sur `_dernierEtatConnu`."),

    ("regle_seuil_journalier_derive_de_l_objectif",
     "[REGLE] Le seuil quotidien de la serie derive de l'objectif, jamais une constante en dur",
     "`atteint: quartsValides > 0 || motsDuJour >= 150` -- 150 etait ecrit en "
     "dur, identique que l'objectif soit « 1 quart par mois » ou « 5 quarts "
     "par semaine ». La serie exigeait donc la meme chose de tout le monde, "
     "sans rapport avec l'engagement pris : avec un objectif mensuel elle "
     "etait cassee en permanence tout en etant parfaitement tenu. Decision "
     "utilisateur : « on reste sur les jours, mais le seuil sera le seuil "
     "minimum quotidien pour respecter ton objectif ; une fois qu'on rate un "
     "jour ca se remet a zero ». Seuil = `objectif.parJour * 322,6`, plancher "
     "a 1. Donne ~11 mots/jour pour 1 quart/mois, ~139 pour 3 quarts/semaine, "
     "~323 pour 1 quart/jour. Corollaire tranche le meme jour : le passe ne "
     "se recalcule JAMAIS quand l'objectif change, sinon la serie devient "
     "achetable (baisser la barre offrirait une serie jamais gagnee)."),
]

LIENS = [
    ("symptome_dernier_mot_de_sourate_jamais_fige", "var_min_fenetre_finale_8s",
     "shares_data_with", "le cadrage est la cause, la fenetre elargie est le correctif"),
    ("var_min_fenetre_finale_8s", "piege_fenetre_finale_dupliquee_vaut_deux_preuves",
     "shares_data_with", "l'elargissement a introduit la fenetre jumelle, corrigee dans le meme bloc"),
    ("symptome_dernier_mot_de_sourate_jamais_fige", "mort_k1_a_la_fermeture",
     "shares_data_with", "k=1 etait la reponse envisagee au meme symptome, ecartee"),
    ("piege_enchainement_de_page_franchit_les_sourates", "symptome_dernier_mot_de_sourate_jamais_fige",
     "shares_data_with", "cible 23 -> 93 mots : le dernier mot recite n'etait plus le dernier de la cible"),
    ("symptome_session_ouverte_jamais_fermee", "symptome_dernier_mot_de_sourate_jamais_fige",
     "shares_data_with", "stopContinuous() porte v2Terminer() : son garde d'entree tuait aussi la finalisation"),
    ("piege_deja_rate_confondu_avec_oubli", "piege_progression_coach_sur_compteur_cumulatif",
     "shares_data_with", "deux compteurs du Coach fausses le meme jour, tous deux annules sur constat utilisateur"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step30.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
