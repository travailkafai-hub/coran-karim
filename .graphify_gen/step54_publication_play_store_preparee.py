#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Preparation de la premiere publication Play Store : maj forcee, diagnostic
retire, et un modele de test jamais valide qui avait glisse vers la release."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_pack_de_test_avait_glisse_vers_la_release",
     "[MESURE] Un modele tajwid explicitement \"pas autorise a l'export applicatif\" pointait dans le code au moment de preparer la premiere release publique",
     "En construisant le premier APK/AAB de publication (2026-09-11), "
     "`_kModelSubdir` (fastconformer_verifier.dart) pointait encore sur "
     "`models/madd-normal-test-2026-09-08` -- le pack de test demande le "
     "2026-09-08 par l'utilisateur (« non, applique le madd aussi, je veux "
     "tester ») sur SON telephone de dev. Le LISEZ_MOI.md du transfert PC A "
     "est explicite : « pas encore autorise a l'export applicatif [...] "
     "validation diagnostique (pilote 1500 fenetres), pas une selection "
     "produit » -- 13,1 % de faux positifs au seuil brut, et HAFS SEUL (le "
     "modele diagnostique n'a pas de sortie warsh_logprobs). Un test valide "
     "sur un telephone de dev, avec l'utilisateur presente pour l'interpreter, "
     "n'est pas la meme decision qu'exposer ce taux de faux positifs a de "
     "vrais utilisateurs publics -- la distinction n'avait jamais ete "
     "reexaminee au moment de construire une release. Le \"REVENIR EN "
     "ARRIERE\" etait deja documente dans judgement_options.dart, jamais "
     "execute avant ce jour : rollback fait vers models/cinq-tetes-2026-09-07 "
     "(encodeur identique, verifie par hash SHA-256 des 692 tenseurs -- "
     "CONFIRMATION_ENCODEUR.md -- donc aucune perte sur le CTC/jugement de "
     "base, seule la tete madd_normal redevient inactive)."),

    ("mesure_deux_modeles_vestiges_dans_lasset_pack",
     "[MESURE] Deux modeles jamais references par le code gonflaient l'AAB de 264 Mo",
     "Question utilisateur : « prk apk est plus grand que d'habitude, est-ce "
     "qu'il y a deux modeles ? ». Verifie : `model_pack/src/main/assets/"
     "models/` contenait `quatre-tetes-v7-2026-09-05` et "
     "`quatre-tetes-warsh-v5-2026-08-31` (132 Mo chacun), TOUS DEUX a zero "
     "occurrence dans lib/ (grep exhaustif) -- le code ne pointe QUE sur une "
     "constante unique `_kModelSubdir` (un seul modele fusionne Hafs+Warsh, "
     "pas de selection par riwaya), donc ces deux dossiers separes par "
     "riwaya sont un schema anterieur jamais nettoye. Deplaces (pas "
     "supprimes) hors du projet. AAB : 319,4 Mo -> 221,2 Mo apres le "
     "remplacement par le bon modele (135 Mo, un seul dossier)."),

    ("piege_asset_pack_absent_dun_apk_simple",
     "[PIEGE] Le module model_pack (Play Asset Delivery) n'est jamais inclus dans un APK construit hors du Play Store",
     "Verifie par `unzip -l` sur deux APK de release consecutifs : aucune "
     "occurrence de `model.onnx` ni du nom du dossier modele, quel que soit "
     "son contenu -- alors que le MEME contenu est bien present dans l'AAB "
     "correspondant (verifie par `jarsigner -verify -verbose`, la ligne "
     "`model_pack/assets/models/.../model.onnx` y apparait avec la bonne "
     "taille). Le module `model_pack` utilise le plugin "
     "`com.android.asset-pack` (Play Asset Delivery, install-time) : seul le "
     "Play Store sait assembler le module de base avec un asset pack separe "
     "au moment de l'installation -- un `flutter build apk`/`adb install` "
     "direct ne le fait jamais, meme si le pack est present dans le projet "
     "et dans l'AAB. Consequence pratique : un APK universel construit par "
     "ce projet n'a jamais eu de modele ASR fonctionnel s'il est installe "
     "directement (sideload/adb) -- seul un canal Play Store reel (ou le "
     "canal de test interne de Play Console) livre l'app avec son modele. "
     "Ce n'est pas un defaut introduit par le rollback du 2026-09-11 : c'est "
     "vrai depuis la creation du module le 2026-08-11, jamais verifie par "
     "execution avant cette session."),

    ("regle_maj_forcee_fail_safe_verifiee_par_execution",
     "[REGLE] La mise a jour forcee (upgrader) doit rester silencieuse sur toute erreur, verifie par lecture du code ET par execution",
     "Demande utilisateur : forcer la mise a jour si une nouvelle version "
     "Play Store existe, avec une reserve explicite (« ca risque d'embeter "
     "s'il y a un probleme, quand afficher quand ne pas afficher »). Verifie "
     "dans le code source du package upgrader (pas suppose) : "
     "`play_store_search_api.dart.lookupById` catche toute Exception et tout "
     "code HTTP hors 2xx -> retourne null ; `Upgrader.isUpdateAvailable()` "
     "catche l'exception de parsing de version -> false. A chaque etage, une "
     "erreur reseau/parsing degrade vers \"pas de mise a jour detectee\", "
     "jamais vers un dialog affiche a tort. Le child (HomeScreen) s'affiche "
     "immediatement dans le StreamBuilder, la verification est asynchrone -- "
     "aucun retard au demarrage. Verifie ensuite PAR EXECUTION sur device "
     "(Upgrader(debugDisplayAlways: true) temporaire) : dialog bloquant "
     "confirme (seul bouton \"MAINTENANT\", bouton retour Android sans "
     "effet, capture d'ecran a l'appui), flag de test retire avant tout "
     "commit -- il aurait affiche ce dialog en permanence en production."),
]

LIENS = [
    ("mesure_deux_modeles_vestiges_dans_lasset_pack",
     "mesure_pack_de_test_avait_glisse_vers_la_release", "shares_data_with",
     "meme investigation, meme session : pourquoi l'APK est gros, quel modele y est vraiment"),
    ("piege_asset_pack_absent_dun_apk_simple",
     "mesure_deux_modeles_vestiges_dans_lasset_pack", "shares_data_with",
     "decouvert en verifiant le contenu reel de l'APK juste apres le nettoyage des vestiges"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step54.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
