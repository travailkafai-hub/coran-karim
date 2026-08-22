#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cloisonnement Hafs/Warsh : normalisation scindee, moteur natif bascule.

Chantier du 2026-08-22, demande utilisateur explicite : "garder cette
separation... je veux un cloisonnement" -- puis confirmation que la bascule
Hafs<->Warsh en pleine recitation doit etre interdite (figee au demarrage).
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_moteur_asr_jamais_bascule_warsh_avant_ce_jour",
     "[MESURE] Avant le 2026-08-22, basculer l'app sur Warsh ne changeait JAMAIS le moteur ASR",
     "Verifie dans le code, pas suppose : `riwaya.dart` disait noir sur blanc "
     "(decision utilisateur 2026-08-12) que le modele ASR restait celui "
     "entraine sur Hafs, \"observe a l'oeuvre sur du Warsh\". Confirme cote "
     "plugin : `FastConformerCtcPlugin.loadModel` construisait "
     "`FastConformerCtc(modelPath, vocabPath, rulesPath, seuilsPath)` -- SANS "
     "vocabWarshPath (pourtant deja un parametre du constructeur Kotlin), et "
     "`riwayaWarsh` n'etait mis a true NULLE PART dans tout le plugin (0 "
     "occurrence de \"warsh\" dans FastConformerCtcPlugin.kt). Le "
     "`word_tokens_warsh.json` deploye sur le telephone etait un fichier mort "
     "cote Dart (0 occurrence)."),

    ("mesure_normalisation_fusionnee_hafs_warsh_avant_ce_jour",
     "[MESURE] La normalisation Hafs/Warsh vivait dans UNE SEULE fonction avant le cloisonnement",
     "`ArabicNormalizer._collapseVariants` portait la regle Warsh (yeh barree "
     "e -> a, 2026-08-12) au milieu du pipeline Hafs. Verifiee sans collision "
     "a l'epoque (0/1024 tokens vocab Hafs, 0/19001 mots) -- mais rien dans la "
     "structure n'empechait une future regle Warsh de percuter Hafs. Scinde en "
     "`_collapseVariantsHafs`/`_collapseVariantsWarsh` sur un tronc commun ; "
     "`normalizeWarsh`/`normalizeStrictWarsh` ajoutes a cote de `normalize`/"
     "`normalizeStrict` (conserves tels quels, ~50 sites d'appel existants "
     "inchanges)."),

    ("mesure_seule_frontiere_construction_recitedword_compte",
     "[MESURE] Un seul point de fusion reel identifie parmi ~90 sites d'appel de normalisation",
     "~50 appels a `normalize`/`normalizeStrict`, ~30 a `splitExpectedWords`, "
     "6 a `similarity`, 2 a `matchesTolerant` trouves dans le code. Analyse : "
     "seuls les 4 points qui construisent `RecitedWord.normalized/.strict` "
     "DEPUIS LE TEXTE BRUT (`_wordsFromText`, `_wordsFromSegments` dans "
     "RecitationNotifier, plus 2 sites d'affichage coach/karaoke) ont besoin "
     "de choisir Hafs vs Warsh -- tout le reste (`similarity`, "
     "`splitExpectedWords`, `matchesTolerant`) recoit des chaines DEJA "
     "normalisees en amont, donc un `normalize()` Hafs applique dessus est un "
     "no-op idempotent (verifie : le vocabulaire Warsh du modele ne produit "
     "JAMAIS de yeh barree en sortie -- 0/1024 pieces -- donc le cote "
     "RECONNU/ASR n'a jamais besoin de la regle Warsh, seul le texte ATTENDU "
     "en a besoin). Corriger 4 sites au lieu de ~90 -- migrer les ~90 aurait "
     "ete un risque de casse sans aucun gain fonctionnel."),

    ("piege_rule_annotation_service_hafs_only_pollue_warsh_en_silence",
     "[PIEGE] RuleAnnotationService n'a aucune notion de riwaya -- expectedRules pollue en Warsh, sans le montrer",
     "`quran_rules_annotated.json` est un asset HAFS UNIQUEMENT, indexe par "
     "surah/ayah sans distinction de riwaya. En session Warsh, "
     "`RuleAnnotationService.annotatedWords(surah, ayah)` rend quand meme les "
     "mots annotes HAFS pour cette cle -- et le garde de longueur "
     "(`annotated.length != canonWords.length`) ne le detecte PAS puisque "
     "Hafs et Warsh ont generalement le meme nombre de mots par verset. "
     "N'EST PAS BLOQUANT AUJOURD'HUI seulement parce que "
     "`judgementOptionsEffectivesProvider` retombe deja sur adulte/enfant en "
     "Warsh (aucun preset n'exploite `expectedRules` dans ce cas, decision "
     "utilisateur \"oublie le tajwid pour le Warsh, adulte et enfant\"). Le "
     "jour ou le tajwid Warsh est cable, ce point DOIT etre traite avant --"
     "asset annote Warsh dedie, ou garde etendu ici."),

    ("mesure_wiring_natif_warsh_deux_vocabs_en_memoire_permanente",
     "[MESURE/DECISION] Cablage natif Warsh : les deux vocabulaires en memoire en permanence, bascule = un bool",
     "Decision utilisateur validee (AskUserQuestion) : pas de bascule a chaud "
     "pendant une recitation active -- \"interdire, forcer un nouveau "
     "demarrage\". Implementation : `loadModel` charge vocabHafs ET vocabWarsh "
     "(+ les deux dictionnaires word_tokens) UNE SEULE FOIS, sans recharger le "
     "modele ONNX (couteux). Une methode SEPAREE `setRiwaya(warsh: Boolean)` "
     "bascule seulement `engine.riwayaWarsh`, appelee UNE FOIS par "
     "`RecitationNotifier._startInterne` juste apres `ensureModelLoaded()` et "
     "avant tout `setAlignmentTarget`. `CtcTokenizer` (4 points de "
     "construction dans le plugin) choisit le dictionnaire mot->tokens "
     "correspondant a la riwaya ACTIVE du moteur, jamais un dictionnaire fixe -- "
     "chercher un mot dans le mauvais dictionnaire aurait rendu des IDs de "
     "tokens VALIDES mais FAUX, silencieusement (aucune exception, les deux "
     "vocabulaires se recoupent partiellement en IDs)."),
]

LIENS = [
    ("mesure_moteur_asr_jamais_bascule_warsh_avant_ce_jour",
     "mesure_deux_moutures_du_22_seule_la_tete_tajwid_change", "shares_data_with",
     "meme modele deux-geles-int8-2026-08-22, deux facettes mesurees le meme jour"),
    ("mesure_normalisation_fusionnee_hafs_warsh_avant_ce_jour",
     "mesure_seule_frontiere_construction_recitedword_compte", "shares_data_with",
     "le diagnostic (fusion) et le perimetre reel du correctif (4 points)"),
    ("piege_rule_annotation_service_hafs_only_pollue_warsh_en_silence",
     "regle_madd_long_et_madd_court_par_comparaison", "shares_data_with",
     "meme racine : le vocabulaire de regles Warsh n'est pas encore raccorde"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step37.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, {len(g['links'])} aretes")


if __name__ == "__main__":
    main()
