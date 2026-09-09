#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Suivre une priere : le minuteur de 6s retire, la resynchronisation sur
'deplace' ajoutee -- deux mesures sur de vraies sessions."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mort_minuteur_6s_sans_alignement_priere",
     "[MORT] Minuteur de 6s « sans alignement -> ruku' » : se declenche a tort pendant que le souffleur joue un audio",
     "Ajoute le 2026-09-08 matin sur demande utilisateur (« rajoute un "
     "compteur de 6 s de ne pas pouvoir aligner un mot [...] c'est que "
     "l'imam est en ruku' »), retire le soir meme par la meme personne "
     "(« le minuteur de 6 s, plus d'interet »). MESURE sur session reelle "
     "(21:21) qui motive le retrait : 21:21:46,47 DECROCHAGE -- reprise "
     "apres le mot 34 ; 21:21:47,48 souffle du passage 35..35 (le micro est "
     "COUPE pendant la lecture) ; 21:21:53,48, soit 6 s apres le decrochage "
     "qui avait arme le minuteur, « ruku' » declare a tort alors que c'est "
     "l'application elle-meme qui parlait. Le desarmement pendant le "
     "souffle corrigeait ce cas precis, mais le mecanisme restait fragile : "
     "six secondes sans placement de mot sont ordinaires des que la "
     "transcription se degrade, et le cout d'une sortie a tort est eleve -- "
     "rendre la main en pleine sourate. Les trois sorties qui restent "
     "(takbir entendu, debut d'Al-Fatiha par faisceau, silence REEL de "
     "30 s) reposent toutes sur ce qui est ENTENDU plutot que sur un "
     "chronometre nourri par un signal (le decrochage) qui peut rester "
     "actif pendant une lecture audio -- meme famille de piege que le "
     "minuteur de silence 30 s et le silence court 3 s, deja documentes."),

    ("mesure_decrochage_natif_57s_avant_declenchement",
     "[MESURE] Le decrochage natif (3 fenetres hors texte) a mis 57 s a se declencher alors que la chaine jugeait deja juste 12 s apres le saut",
     "Session reelle : Al-Baqara, versets 1-3 recites puis saut de verset "
     "(verset 6 au lieu du 4). A 21:00:58 l'ancre se pose au mot 11 ; des "
     "21:01:10 (12 s plus tard), la chaine v2 juge DEJA correctement -- "
     "statut `deplace`, GOP quasi parfait -- des mots correspondant aux "
     "versets 2:5 a 2:7 (mots 28 a 55), donc BIEN APRES le saut. `deplace` "
     "signifie « bien prononce, mais hors de la zone attendue » : le natif "
     "(Decideur.OrdreTemporel) a deja ecarte les inversions/repetitions "
     "locales legitimes avant d'emettre ce statut, donc une SERIE qui "
     "s'accumule loin devant le pointeur est une vraie preuve de position, "
     "pas un mot isole mal place. Le decrochage NATIF (3 fenetres "
     "consecutives hors texte, seuil deja en place) ne s'est declenche "
     "qu'a 21:01:55 -- 57 s apres le debut du suivi, 2 s avant la fermeture "
     "de la session -- alors que `state.pointer` cote Dart, LUI, etait "
     "reste fige a 1 pendant tout ce temps : le souffleur de silence "
     "(qui lit ce pointeur) a propose de l'aide au mauvais endroit (mot 1 "
     "au lieu de ~55) quatre fois de suite, toutes ignorees par le garde "
     "anti-repetition."),

    ("regle_resync_priere_sur_serie_deplace_coherente",
     "[REGLE] Une serie de 3+ mots \"deplace\" coherents, loin devant le pointeur, resynchronise sans attendre le decrochage natif",
     "Correctif du defaut mesure ci-dessus (mesure_decrochage_natif_57s_"
     "avant_declenchement), valide par l'utilisateur avant implementation : "
     "« il faut proposer l'audio [...] et apres oublier tout ce qui etait "
     "deja aligne et chercher a relocaliser ». Dans `_onV2` "
     "(recitation_provider.dart), une serie d'au moins 3 mots `deplace` "
     "distincts, groupes (etalement <= 60 mots) et significativement "
     "au-dela du pointeur (marge > 10 mots, pour ne pas confondre avec une "
     "simple inversion locale deja geree par le statut `deplace` lui-meme), "
     "declenche desormais la MEME resynchronisation que le decrochage "
     "natif classique en phase target (canal `_sautPresumeCtrl`, deja "
     "cable a `soufflerPriere` cote ecran) -- mais au PREMIER mot de la "
     "serie detectee, sans attendre le seuil natif des 3 fenetres. "
     "Isolation verifiee dans le code (pas supposee) : garde par "
     "`_dynamicTargetDiscovery && state.prayerPhase == PrayerPhase.target` "
     "-- `_dynamicTargetDiscovery` est `false` par defaut et n'est mis a "
     "`true` que dans `startPrayerFollow()`, jamais dans le chemin de la "
     "recitation standard (`startContinuous`), qui le remet meme "
     "explicitement a `false`. Verifie par execution : "
     "`test/prayer_deplace_resync_test.dart`, 4 scenarios (serie coherente "
     "qui declenche au bon mot, inversion locale qui ne declenche rien, "
     "deux signaux disperses qui ne se combinent pas a tort, accumulation "
     "qui traverse plusieurs appels a `_onV2`), tous passent. Suite "
     "complete (244 tests) : memes 9 echecs pre-existants, aucune "
     "regression."),
]

LIENS = [
    ("mesure_decrochage_natif_57s_avant_declenchement",
     "mort_minuteur_6s_sans_alignement_priere", "shares_data_with",
     "meme mecanisme (decrochage en phase target), meme session de travail"),
    ("regle_resync_priere_sur_serie_deplace_coherente",
     "mesure_decrochage_natif_57s_avant_declenchement", "shares_data_with",
     "le correctif ferme directement la mesure"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step51.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
