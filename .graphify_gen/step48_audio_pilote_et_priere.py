#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""L'audio pilote la decoupe, et le mode priere cesse de tout charger."""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("regle_audio_pilote_la_decoupe_le_texte_suit",
     "[REGLE] L'audio pilote la decoupe, le texte en est deduit -- une seule mesure au lieu de trois",
     "Ecart signale depuis le 2026-08-27 et jamais resolu : « il y a toujours un "
     "ecart dans la memorisation par palier entre l'audio qui recite et le "
     "texte » ; le commentaire du code disait que « la cause restante n'est pas "
     "decidable depuis le code seul ». Elle l'etait. `playWordWindow` prend des "
     "INDEX de mots puis va rechercher les millisecondes AILLEURS -- segments "
     "d'Al-Afasy, ou estimation ponderee en Warsh. Le texte etait coupe d'apres "
     "une source, l'audio d'apres une autre. Diagnostic de l'utilisateur : "
     "« ta methode genere des ecarts entre texte et audio, oublie les 6 mots » "
     "-- repasser par l'index, c'est ressortir chercher le temps ailleurs. "
     "TROIS MECANIQUES SUPPRIMEES : `coupes_palier_afasy.json` (coupes mesurees "
     "sur la voix d'Al-Afasy seulement), les timings « ESTIMES (Warsh) -- "
     "decoupe ponderee, non mesuree », et la mise a l'echelle par le rapport "
     "des durees. CE QUI EXISTAIT DEJA ET QUE PERSONNE N'AVAIT CROISE : "
     "`RegistreDePreuves` enregistre `debutAbs`/`finAbs` par mot, en "
     "echantillons absolus, « pour reextraire l'audio d'un verdict apres "
     "coup » -- les frontieres etaient calculees a chaque passage, jamais "
     "remontees. Le critere de coupe est le SILENCE et rien d'autre : aucun "
     "waqf n'est lu, les coupes y tombent indirectement parce que le "
     "recitateur les respecte."),

    ("mesure_coupes_precalculees_sur_le_coran_entier",
     "[MESURE] Les coupes de palier precalculees hors app : 15 883 paliers, mediane 5 mots, 1,04 % au-dela de 10",
     "Decision de l'utilisateur (2026-09-06) : « analyse le texte nous-memes au "
     "lieu de laisser cette decision dans l'app ; travaille sur le texte "
     "entier ; tu peux deduire les vrais endroits pour s'arreter, avoir une "
     "coherence structurelle ». Le calcul a l'execution ne voyait qu'un verset "
     "a la fois ; hors app on lit les 6 236 d'un coup, ce qui ouvre la seule "
     "chose qui donne de la coherence : LE CORAN SE REPETE. 7 474 groupes de 2 "
     "a 5 mots reviennent au moins trois fois (`ٱلسموت وٱلأرض` 133 fois, "
     "`يأيها ٱلذين ءامنوا` 89, `على كل شىء قدير` 33). Ils sont traites comme des "
     "unites qu'on ne coupe jamais -- donc coupees de la MEME facon partout. "
     "CINQ SOURCES : waqf Hafs UNION Warsh (5 202 versets couverts contre "
     "2 637), les `mamnu` qui suppriment des coupes au lieu d'en creer, les "
     "liaisons, les groupes figes, la longueur. Asset de 84 ko couvrant les "
     "6 236 versets."),

    ("regle_liaison_ouvre_sauf_devant_l_article_defini",
     "[REGLE] `و`/`ف` ouvre une proposition SAUF devant l'article defini -- deux caracteres suffisent",
     "Le probleme etait de departager les deux emplois de `و` : sur 6:1, "
     "`وَجَعَلَ` (و + verbe) ouvre une proposition tandis que `وَٱلنُّورَ` "
     "(و + nom) prolonge la precedente. Couper avant chaque `و` donnait des "
     "coupes apres les mots 4, 5 et 7 au lieu des 5 et 8 que l'utilisateur fait "
     "a voix haute. LA REGLE N'EST PAS GRAMMATICALE, ELLE EST ORTHOGRAPHIQUE : "
     "`و`/`ف` suivi de l'ARTICLE DEFINI `ال` coordonne un NOM, donc prolonge la "
     "phrase ; sans article, la liaison ouvre. Aucune morphologie n'est "
     "necessaire. Verifie sur 6:1 : rend exactement `[5, 8]`. Ampleur : 15 080 "
     "mots du Coran commencent par `و`/`ف`, dont 13 636 (90 %) sans article. "
     "⚠️ PAS EXACT, SUFFISANT : un `و` + nom SANS article sera pris pour une "
     "ouverture -- prix a payer pour ne pas dependre d'un asset morphologique."),

    ("mesure_seuil_de_distance_fixe_par_les_arrets_reels",
     "[MESURE] Le seuil de distance entre coupes est 3, et c'est l'exemple de l'utilisateur qui le fixe",
     "La regle avait ete enoncee avec 4 (« si une autre coupe est a moins de 4 "
     "mots, on ne coupe pas »). Mesure sur les deux versets donnes : les arrets "
     "de 6:1 sont les mots 5 et 8, soit exactement 3 mots d'ecart -- un seuil "
     "de 4 supprimerait le second. seuil 2 : 6:1 juste mais 13:2 laisse un "
     "palier de 2 mots ; seuil 3 : 6:1 juste et 13:2 en 6/5/3/4/8 ; seuil 4 : "
     "6:1 casse. ET LA DISTANCE VAUT POUR TOUTES LES COUPES : les waqf en "
     "etaient exemptes au motif qu'« un waqf du texte est une autorite », ce "
     "que 13:2 a refute -- le Warsh y marque apres le mot 5 et le Hafs apres le "
     "6, a UN mot d'ecart, produisant un palier d'un seul mot. Deux autorites "
     "qui se suivent de trop pres ne font pas deux arrets, elles en font un."),

    ("mesure_priere_chargeait_la_sourate_entiere",
     "[MESURE] Le mode priere chargeait la sourate ENTIERE : 97 077 tokenisations, l'app gelait",
     "Defaut signale le 2026-09-07 (« suivre priere, l'app a bugue »). Le "
     "journal s'arrete NET sur `cible d'alignement : 3747 mots, ancre=0`, zero "
     "ligne apres, alors que la veille la meme session continuait 45 s de plus. "
     "CAUSE : apres identification, la sourate ENTIERE etait posee comme cible. "
     "Al-Fatiha fait 29 mots, An-Nisa 3 747. La pose de cible construit les "
     "variantes confusables de CHAQUE mot puis les tokenise -- 856 "
     "tokenisations pour Al-Fatiha, 97 077 pour An-Nisa, facteur 113. La "
     "quasi-totalite de ces variantes sont des mots volontairement hors-Coran, "
     "donc absents du dictionnaire : chacune part en repli glouton. "
     "DEUX HYPOTHESES ECARTEES PAR LA MESURE avant d'arriver la : (1) « le "
     "filtre du dictionnaire alourdit ce chemin » -- les 323 replis gloutons "
     "correspondent bien aux 323 entrees qu'il ecarte, mais ces replis donnent "
     "des decompositions 20 % PLUS COURTES (3,20 pieces contre 4,00) et exactes "
     "323 fois sur 323 : le filtre allege ; (2) « la DP explose » -- non, "
     "`maxAlignWords = 80` la borne deja. Le cout etait entierement dans la "
     "PREPARATION de la cible. Correction : charger 400 mots et etendre de 400 "
     "en 400 (`extendVerses`/`v2ExtendTarget`, ce que le karaoke fait depuis le "
     "2026-08-05), le localisateur ne cherchant de toute facon que dans "
     "`[ancre - 20, ancre + 80]`."),

    ("regle_pas_de_souffleur_avant_relocalisation",
     "[REGLE] Aucune correction avant que l'ancre ait retrouve sa place sur la nouvelle cible",
     "Defaut signale le 2026-09-07, juste apres la correction du gel : « une "
     "fois la sourate trouvee il faut d'abord reussir l'alignement, la "
     "relocalisation ; une fois OK on peut commencer a corriger, sans forcer la "
     "repetition -- l'ancre doit toujours chercher a se positionner. La il m'a "
     "corrige sur يَـٰٓأَيُّهَا ٱلنَّاسُ : c'est le debut de la sourate, mais ce "
     "n'etait plus le debut, j'avais avance. » Journal : `cible v2 posee : 411 "
     "mots` puis immediatement `[Souffleur] hesitation longue (4s)`. "
     "MEME CAUSE STRUCTURELLE que celle deja documentee dans "
     "`_beginIdentifiedTargetPhase` : on identifie un verset PARCE QU'IL VIENT "
     "D'ETRE DIT, et le temps de le reconnaitre le recitant est plus loin. Le "
     "correctif d'aout avait traite la POSITION de l'ancre ; son propre "
     "commentaire disait deja que « ce qui posait probleme n'etait pas la "
     "position mais le SOUFFLEUR ». `_prayerLocalisee` passe a faux a chaque "
     "pose de cible et a vrai des qu'un mot est juge dessus. L'ancre, elle, "
     "continue de chercher -- le localisateur n'est pas touche. Si la "
     "localisation n'aboutit jamais, le souffleur reste muet : souffler au "
     "mauvais endroit est pire que ne rien souffler."),

    ("piege_un_defaut_dormant_se_reveille_quand_on_elargit",
     "[PIEGE] Un defaut dormant se reveille des qu'on elargit -- le cache d'URL et les douze recitateurs",
     "Constat de l'audit (QUAL-04), verifie : `_urlCache` etait indexe par le "
     "seul numero de sourate alors qu'il est rempli par "
     "`fetchSurahAudioUrls(reciter.id, ...)`. Apres une correction avec le "
     "recitateur A, choisir B sur la meme sourate rejouait l'URL de A -- la "
     "mauvaise voix. CE QUE L'AUDIT NE DIT PAS : le defaut etait DORMANT et "
     "inoffensif tant qu'UN SEUL recitateur Hafs passait par quran.com. Les "
     "onze recitations ajoutees la veille l'ont rendu atteignable. "
     "REGLE GENERALE : elargir un ensemble (recitateurs, riwayat, sources) "
     "reveille les caches et les tests qui supposaient l'unicite. Chercher ces "
     "suppositions AVANT d'elargir, pas apres."),
]

LIENS = [
    ("mesure_coupes_precalculees_sur_le_coran_entier",
     "regle_audio_pilote_la_decoupe_le_texte_suit", "shares_data_with",
     "les deux moities de la decoupe : la voix et le texte"),
    ("regle_liaison_ouvre_sauf_devant_l_article_defini",
     "mesure_coupes_precalculees_sur_le_coran_entier", "shares_data_with",
     "une des cinq sources de l'asset"),
    ("mesure_seuil_de_distance_fixe_par_les_arrets_reels",
     "mesure_coupes_precalculees_sur_le_coran_entier", "shares_data_with",
     "le reglage de longueur de l'asset"),
    ("regle_pas_de_souffleur_avant_relocalisation",
     "mesure_priere_chargeait_la_sourate_entiere", "shares_data_with",
     "deux defauts du mode priere trouves le meme jour"),
    ("piege_un_defaut_dormant_se_reveille_quand_on_elargit",
     "mesure_way2quran_sans_minutage_mp3quran_en_a_115", "shares_data_with",
     "l'elargissement qui a reveille le cache"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step48.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print("+{} noeuds, +{} aretes -> {} noeuds, {} aretes".format(
        a, ar, len(g["nodes"]), len(g["links"])))


if __name__ == "__main__":
    main()
