#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Audit securite 2026-09-06 (perimetre APK) : ce qui a ete verifie par
execution, pas suppose sur la foi du rapport."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_quran_api_trois_courses_reproduites_et_fermees",
     "[MESURE] QuranApi : 3 courses de concurrence reproduites par execution (audit QUAL-01), dont une absente du rapport",
     "L'audit (Reproduit, deux scenarios) decrivait 2 bugs : (1) `_chapters != "
     "null` pris pour preuve de chargement COMPLET alors que `_versesBySurah` "
     "pouvait rester nul -- plantage ; (2) un chargement Hafs en vol pouvait "
     "publier APRES une bascule Warsh, ecrasant le texte actif. Correctif : "
     "compteur `_generation`, incremente au setter `riwaya`, capture au debut "
     "de `_ensureLoaded()` et revalide juste avant de publier. UN TROISIEME "
     "BUG a ete trouve en VERIFIANT ce correctif par execution, pas en le "
     "lisant : entre le retour du chemin rapide de `_ensureLoaded()` (cache "
     "deja rempli) et la relecture du cache par l'appelant, une bascule "
     "SYNCHRONE peut nuller ce cache dans l'intervalle -- `Null check operator "
     "used on a null value`. Corrige en remplacant les lectures directes de "
     "`_versesBySurah!`/`_chapters!` par des boucles `while(true) { await "
     "_ensureLoaded(); if (cache != null) return cache; }`. Preuve : "
     "`test/quran_api_concurrence_test.dart`, 3 scenarios, canal d'assets "
     "mocke avec delais controles, les 3 passent."),

    ("piege_test_dont_le_teardown_ne_reinitialise_rien",
     "[PIEGE] Un tearDown qui rappelle le setter n'a reinitialise rien si le setter a un garde d'egalite",
     "Trouve en ecrivant la preuve du bug ci-dessus, pas dans le code de "
     "production : la premiere version du test remettait `QuranApi.riwaya = "
     "Riwaya.hafs` en tearDown, mais le setter fait `if (value == _riwaya) "
     "return;` -- si le test precedent avait deja laisse la riwaya sur hafs, "
     "ce tearDown ne faisait RIEN, et le cache non-nulle du test precedent "
     "contaminait les hypotheses du suivant. Un plantage different (mais "
     "reel) en est sorti, menant a `mesure_quran_api_trois_courses_"
     "reproduites_et_fermees`. Fixe en forcant DEUX bascules (warsh puis "
     "hafs) en setUp/tearDown, quel que soit l'etat de depart -- la seule "
     "facon de garantir qu'un setter a garde d'egalite s'execute reellement."),

    ("regle_un_interrupteur_doit_fermer_tous_les_chemins_pas_juste_le_principal",
     "[REGLE] Un interrupteur de diagnostic doit fermer TOUS les points d'ecriture, verifies un par un -- pas seulement le chemin principal",
     "Audit SEC-01 (P1) : le diagnostic desactive laissait pourtant ecrire par "
     "3 chemins distincts, chacun avec sa propre cause -- (1) le natif Kotlin "
     "demarrait `enabled=true` et le restait jusqu'au premier `setLogFile`, "
     "fenetre ouverte entre lancement de l'app et premiere recitation ; (2) le "
     "SwitchListTile REELLEMENT affiche dans les Reglages ecrivait la "
     "preference et le champ Dart mais n'appelait jamais `setLogEnabled` -- "
     "l'ancien `_DiagnosticTile` qui le faisait a ete retire du parcours "
     "visible le 2026-08-09 sans que ce point soit repris ; (3) "
     "`quran_verse_locator_service.dart` appelait `debugPrint` en direct, "
     "sans lire `DiagnosticLog.enabled` du tout. Aucun des trois n'etait "
     "visible depuis les deux autres : fermer le premier n'aurait rien dit "
     "sur les deux suivants. Les 3 corriges independamment (natif ferme par "
     "defaut + `setFile` atomique avec l'etat, commutateur visible relie a "
     "`setLogEnabled`, `debugPrint` remplace par `DiagnosticLog.log`)."),

    ("mesure_purge_sautait_deux_operations_independantes",
     "[MESURE] session_archive_service : le retour premature de purgerAnciennes() sautait 2 nettoyages sans rapport avec sa condition",
     "Audit SEC-02 (P2, confirme par le code). `purgerAnciennes()` faisait "
     "`if (vieilles.isEmpty) return;` AVANT d'appeler `_purgerAudioPortions()` "
     "-- deux objets distincts (sessions vs portion_words) purges par la MEME "
     "condition de sortie. `demarrer()` appelle cette methode a CHAQUE "
     "session : « aucune vieille session, mais des portions expirees » est "
     "l'etat NORMAL d'un usage regulier, pas un cas limite. Le commentaire "
     "de la methode promettait aussi un « balayage du dossier » pour "
     "recuperer un fichier orphelin apres un echec de suppression avale -- "
     "grep sur balayage/reconcil/orphelin dans tout le fichier : 0 resultat, "
     "la promesse n'avait pas d'implementation. Corrige : les deux purges "
     "tournent independamment, plus une nouvelle `_reconcilierFichiersOrphelins"
     "()` qui balaie reellement le dossier contre les deux tables SQL."),

    ("piege_note_anti_double_tiret_xml_contredite_dans_le_meme_commentaire",
     "[PIEGE] Un commentaire XML peut porter sa propre regle (« pas de -- ici ») et la violer dans le paragraphe d'a cote -- seul un build le prouve",
     "En corrigeant SEC-04 (allowBackup ne couvre pas le transfert "
     "d'appareil a appareil), le commentaire ajoute a AndroidManifest.xml "
     "contenait litteralement la phrase « pas de double tiret dans ce "
     "commentaire, XML l'interdit » -- ET deux vraies occurrences de `--` "
     "quelques lignes plus haut dans CE MEME commentaire (utilisees comme "
     "tiret de style, pas comme code). Le nouveau `data_extraction_rules.xml` "
     "en portait un troisieme. Les trois avaient ete relus, jamais "
     "recompiles : `flutter build apk --debug` a echoue avec `[Fatal Error] "
     "La chaine \"--\" n'est pas autorisee dans les commentaires`, sur les "
     "DEUX fichiers, l'un apres l'autre. La note d'intention dans le texte "
     "ne remplace pas la verification -- seule l'execution du build l'a "
     "trouve, exactement la regle de methode du projet (executer, pas lire "
     "pour conclure)."),

    ("regle_politique_confidentialite_verifiee_hote_par_hote",
     "[REGLE] Une politique de confidentialite se verifie hote reseau par hote reseau dans le code, pas en la relisant",
     "Audit SEC-05 (P2, confirme par le code et le document). Le texte du 11 "
     "aout annoncait 2 fournisseurs audio (Quran.com, hisnmuslim.com) et les "
     "extraits vocaux comme « diagnostic desactive par defaut » uniquement. "
     "`grep -rEo 'https?://...' lib/` remonte 6 hotes distincts reellement "
     "contactes : quran.com/verses.quran.com (audio + minutage mot-a-mot), "
     "everyayah.com, mp3quran.net (+ miroir qurango.net), hisnmuslim.com -- "
     "plus Google Fonts (pubspec.yaml : 11 des 12 ecritures du selecteur se "
     "telechargent a la demande, seule Amiri est embarquee depuis le "
     "2026-09-03). L'archive de session (mots non-verts + extrait audio, 7 "
     "jours, `session_archive_service.dart`) est ACTIVE PAR DEFAUT hors "
     "session de reference/mode tajwid -- distincte du diagnostic, jamais "
     "mentionnee comme telle. Document reecrit apres verification de chaque "
     "affirmation contre le code (hotes, retention 7 jours mesuree dans "
     "`retentionJours`, ecran de suppression reellement existant "
     "`coach_sessions.dart`), pas sur la base de ce que l'app est supposee "
     "faire."),
]

LIENS = [
    ("piege_test_dont_le_teardown_ne_reinitialise_rien",
     "mesure_quran_api_trois_courses_reproduites_et_fermees", "shares_data_with",
     "le meme fichier de test, la meme session de correctifs"),
    ("regle_un_interrupteur_doit_fermer_tous_les_chemins_pas_juste_le_principal",
     "mesure_purge_sautait_deux_operations_independantes", "shares_data_with",
     "meme audit (2026-09-06), meme session de fermeture (2026-09-09)"),
    ("piege_note_anti_double_tiret_xml_contredite_dans_le_meme_commentaire",
     "regle_politique_confidentialite_verifiee_hote_par_hote", "shares_data_with",
     "deux corrections documentaires de la meme session, verifiees par execution"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step49.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
