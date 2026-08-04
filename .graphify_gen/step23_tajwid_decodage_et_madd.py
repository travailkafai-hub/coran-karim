#!/usr/bin/env python3
"""Le tajwid decode comme il a ete entraine, et la famille madd devient binaire.

Consigne la soiree du 2026-08-04 : quatre defauts remontes un a un, deux
hypotheses de l'agent REFUTEES par la mesure, une erreur de methode (comparer
deux branches sans le voir), et la limite structurelle que l'utilisateur a
nommee avant l'agent (la sous-famille du madd n'est pas acoustique).
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("piege_decoder_une_tete_multilabel_comme_du_ctc",
     "[PIEGE] Decoder une tete SIGMOIDE avec un argmax CTC : une regle sur deux est inventee",
     "La tete 2 est multi-label a sigmoide depuis le 2026-07-24 (BCE par "
     "classe, `-softplus(-x)` a l'export, apprise sur des SPANS DENSES pour "
     "que deux regles coexistent sur les memes frames). `decodeTajwid` faisait "
     "pourtant un argmax ENTRE CLASSES + collapse CTC -- le decodage de "
     "l'ANCIENNE architecture. Le decodeur n'avait pas suivi le changement de "
     "tete. MESURE sur 20 s de recitation reelle, modele deploye : "
     "(1) `tajwidBlank` = tajwidNames.size = 19 alors que la sortie n'a QUE 19 "
     "classes (0..18) -- indice HORS PLAGE, garde toujours vrai, donc 100 % "
     "des frames emettaient une regle, et sur 49,8 % d'entre elles le "
     "« gagnant » etait SOUS 0,5 de probabilite : une regle sur deux etait "
     "INVENTEE. (2) 13,9 % des frames portent REELLEMENT deux regles au-dessus "
     "du seuil -- exactement ce que les spans avaient ete construits pour "
     "permettre, et qu'un argmax ne peut pas rendre. (3) Les spans denses "
     "ressortaient haches en pics d'UNE frame, ce qui a fait conclure a tort a "
     "la peakiness du CTC en analysant les durees (p25 = 1 frame sur "
     "madda_obligatory). Corrige par un seuil PAR CLASSE a 0,5 -- frontiere "
     "naturelle d'une sigmoide, pas un reglage a calibrer. "
     "COROLLAIRE : le blanc n'a pas ete « oublie » dans rules.json. Il "
     "n'existe pas pour une tete multi-label -- « aucune regle » se dit "
     "« toutes les probabilites basses », vrai sur 49,8 % des frames."),

    ("piege_frames_du_mot_mesurent_des_pics_pas_une_duree",
     "[PIEGE] `frames` compte les pics d'emission du CTC, jamais la duree du son",
     "AligneurForce ecarte explicitement les blancs (« le blanc n'appartient a "
     "aucun mot ») pour calculer frames/premiereFrame/derniereFrame. Le CTC "
     "etant peaky, `إِنَّمَا` (quatre syllabes) ressort avec frames=1 et `إِلَّآ` "
     "avec frames=2, tous deux PARFAITEMENT reconnus (gop=0,00, entendu "
     "exact). Un mot correctement reconnu peut donc avoir frames=1 : ce n'est "
     "PAS un signe de defaut. CONSEQUENCE MESUREE : on cherchait les regles "
     "tajwid dans [premiereFrame, derniereFrame], soit 80 a 160 ms, alors que "
     "la tete 2 emet sur la duree REELLE -- le madd tombait en dehors et l'app "
     "accusait `إِلَّآ` et `إِنَّمَا` de « regle attendue NON DETECTEE ». Corrige "
     "en bornant chaque mot par ses VOISINS (du dernier pic du precedent au "
     "premier pic du suivant), blancs compris. La ghunna de `إِنَّمَا` passe "
     "d'introuvable a 880 ms, stable sur trois observations (11f/10f/11f). "
     "Cette etendue ne sert QU'A CHERCHER LES REGLES : les scores des lettres "
     "restent calcules sur les seules frames emises, et le taux ne bouge pas "
     "(1,67 % avant comme apres)."),

    ("mesure_omis_verrouille_jetait_les_corrections_de_la_v2",
     "[MESURE] Verrouiller `omis` jetait en silence les corrections de la v2",
     "TROUVE PAR L'UTILISATEUR, capture d'ecran a l'appui : des mots "
     "s'affichaient SANS AUCUNE COULEUR (rendu de `skipped` : soulignement, "
     "aucun fond) alors que la v2 les avait finalement juges VERTS. Log de la "
     "session : mot=76 `إِلَّآ` omis -> provisoire:vert -> definitif:vert ; "
     "mot=18 `بِمَآ` idem ; mot=17 `يُؤْمِنُونَ` omis -> definitif:vert. Quatre a "
     "huit mots par session suivent ce trajet. MECANISME : `omis` appelait "
     "`_judge(lock: true)`, et la correction emise deux fenetres plus tard "
     "tombait sur `if (words[i].locked) return;`. L'app continuait donc "
     "d'afficher une ACCUSATION (« tu n'as pas dit ce mot ») que sa propre "
     "couche de decision avait dementie -- le contraire du socle « dire vrai ». "
     "POURQUOI NE PLUS VERROUILLER N'EST PAS UN ASSOUPLISSEMENT : "
     "`Statut.Omis` n'est JAMAIS memorise dans `Decideur.definitifs[]` (seules "
     "les COULEURS y entrent), donc la v2 le recalcule a chaque fenetre -- il "
     "est revisable PAR CONCEPTION. C'etait Dart qui le figeait, contre le "
     "dessin de la couche qui le produit."),

    ("regle_sous_famille_du_madd_est_grammaticale_pas_acoustique",
     "[REGLE] La sous-famille d'un madd est GRAMMATICALE : ne jamais la demander a l'acoustique",
     "RAISONNEMENT DE L'UTILISATEUR (2026-08-04), confirme par la mesure : "
     "« ils peuvent avoir la meme longueur sauf que un est obligatoire, et "
     "l'obligation c'est pas la couleur ». `madda_obligatory` (wajib muttasil) "
     "et `madda_permissible` (jaiz munfasil) durent tous deux 4 a 5 harakat ; "
     "ce qui les separe est la nature de ce qui SUIT la voyelle longue -- une "
     "hamza dans le meme mot ou dans le suivant. Le TEXTE le sait de facon "
     "deterministe (RecitedWord.expectedRules) ; le son, non. "
     "CONSTAT DEVICE : sur une recitation PROFESSIONNELLE rejouee, le mot 76 "
     "`إِلَّآ` est signale « madda_obligatory NON DETECTEE » alors que la tete "
     "detecte `madda_permissible` au meme endroit -- le madd EST fait, il est "
     "range dans la sous-famille voisine. Aucune amelioration de la tete ne "
     "reglera ca : la question n'est pas de son ressort. "
     "DECOUPAGE CORRECT : le TYPE vient du texte ; l'acoustique ne repond "
     "qu'a « y a-t-il eu un allongement, et de quelle duree »."),

    ("mort_juger_le_madd_par_la_duree_des_runs_ctc",
     "[MORT] Seuil de duree sur les runs de la tete tajwid : 26 a 74 % de faux positifs",
     "Piste proposee par l'agent apres le constat sur la sous-famille : puisque "
     "le texte donne le type, mesurer la DUREE pour verifier que l'allongement "
     "a ete tenu. REFUTE par la mesure, sur une recitation PROFESSIONNELLE ou "
     "toutes les regles sont censees etre faites -- un seuil correct devrait "
     "donc quasiment tout laisser passer : "
     "seuil 2f -> 26 % des madda_obligatory rejetes a tort ; 4f -> 64 % ; "
     "6f -> 74 %. Les percentiles p5, p10 ET p25 de madda_obligatory valent "
     "TOUS 1 frame : au moins un quart des madds obligatoires d'un "
     "professionnel ne produisent qu'un pic de 80 ms. "
     "⚠️ CE CHIFFRE A ETE OBTENU AVANT la correction du decodage "
     "(cf. piege_decoder_une_tete_multilabel_comme_du_ctc) : la peakiness "
     "venait de l'argmax, pas du CTC. Apres correction les durees redeviennent "
     "realistes (ghunnah 880 ms), mais la separation long/court ne monte qu'a "
     "AUC 0,653 -- toujours insuffisant pour un critere opposable. A rouvrir "
     "seulement avec une duree issue de l'alignement force de la voyelle, pas "
     "des runs de la tete 2."),

    ("mesure_fusion_madd_binaire_divise_la_loss_par_deux",
     "[MESURE] Fusionner la famille madd (17 classes) : val_tajwid 0,283 -> 0,126",
     "Idee de l'utilisateur : « le mieux c'etait de distinguer madd long et "
     "madd court au lieu de toute cette typologie ». Fondee sur deux mesures : "
     "(1) la sous-famille n'est pas acoustique (cf. la regle dediee) ; (2) la "
     "distinction qui compte -- long (4-6 harakat) contre court (2) -- ne se "
     "separe qu'a AUC 0,653 par la duree (410 detections d'une session reelle, "
     "mediane 3 frames contre 2, moyenne 5,95 contre 2,73) : la tete diluait "
     "sa capacite sur quatre classes dont trois se recouvrent. "
     "RESULTAT (stage a, encodeur et tete lettres GELES, donc val_wer_ctc "
     "protege par construction) : tete 19 classes 0,283 a l'epoch 1 ; tete 17 "
     "classes 0,126 a l'epoch 1, soit -55 %. "
     "RESERVE : val_tajwid est une BCE moyennee SUR LES CLASSES, passer de 19 "
     "a 17 change un peu l'echelle -- l'ecart est trop grand pour venir de la "
     "seule arithmetique, mais le juge definitif reste l'AUC long/court et le "
     "comportement sur device. "
     "LA FUSION EST FAITE DANS LES LABELS, jamais au decodage : fusionner au "
     "decodage reviendrait a accepter n'importe quel madd pour un madd "
     "obligatoire, donc a valider un allongement COURT la ou il en faut un "
     "long -- le « demi-mot valide » que le projet interdit."),

    ("piege_banc_marqueur_de_fin_de_la_session_precedente",
     "[PIEGE] Le banc lisait le marqueur de fin de la session PRECEDENTE",
     "`recette_2tel.sh` cherchait « capture ouverte » et « fin du fichier » "
     "dans les 400 DERNIERES lignes du journal. Ce journal est APPEND-ONLY et "
     "PARTAGE entre sessions : le marqueur de la passe precedente y trainait "
     "encore, et le banc concluait que le rejeu etait termine au bout de vingt "
     "secondes. MESURE : trois recettes ont rendu 0 mot juge (20260804-213658, "
     "-215405, -221130) quand les autres en rendaient 120 a 133, sur le MEME "
     "wav et le MEME binaire. "
     "ELARGIR LA FENETRE NE CORRIGE RIEN -- c'est ce qui avait deja ete fait "
     "pour l'autre marqueur (60 -> 400 lignes le 2026-07-30) et le defaut est "
     "revenu ailleurs. On borne desormais par la POSITION (`wc -l` releve "
     "AVANT le lancement, puis `tail -n +$DEPUIS`), independamment du debit du "
     "journal. "
     "CONSEQUENCE A ASSUMER : les taux mesures avant ce correctif sont "
     "fragiles -- les ancres allaient de 103 a 133 mots pour le meme WAV."),

    ("piege_compter_les_non_verts_sans_les_mots_jamais_juges",
     "[PIEGE] Un taux de non-verts qui oublie les mots JAMAIS juges se flatte tout seul",
     "RAPPEL DE L'UTILISATEUR le 2026-08-04, apres trois taux annonces trop "
     "bas. Le script comptait les mots SIGNALES au numerateur et l'ancre max au "
     "denominateur : un mot jamais juge disparaissait donc du numerateur tout "
     "en restant au denominateur. Corrections : v6-sans-tete3 8,47 % -> 9,32 % ; "
     "v7-minAppariements1 8,47 % -> 9,32 % ; v8-wordtokens 2,54 % -> 3,39 %. "
     "CE QUE CA CHANGE AUX CONCLUSIONS : `minAppariements` 2 -> 1 ne gagne RIEN "
     "sur le taux (9,32 % avant comme apres) ; le gain annonce ce soir-la "
     "n'existait pas. Son seul effet reel, mesure, est sur les refus de "
     "fenetres (26,0 % -> 8,9 %). Le vrai correctif du taux etait le "
     "`word_tokens.json` (9,32 % -> 3,39 %). "
     "LE MOT SAUTE EST LE PLUS DANGEREUX : il ne laisse AUCUNE ligne dans le "
     "log. Exemple trouve ainsi : le mot 115 `ءَامَنَ` etait enjambe dans trois "
     "sessions alors que 113, 114, 116 et 117 etaient juges -- il tombe dans "
     "`ءَامِنُوا۟ كَمَآ ءَامَنَ ٱلنَّاسُ` (2:13), la repetition deja documentee."),

    ("piege_comparer_deux_branches_en_croyant_mesurer_un_correctif",
     "[PIEGE] Comparer deux BRANCHES en croyant mesurer son propre correctif",
     "Erreur de methode de l'agent, 2026-08-04. Une « regression » de 1,68 % a "
     "9,24 % a ete attribuee au travail du jour, puis confirmee sur trois "
     "passes -- alors que la reference 1,68 % venait d'un APK construit depuis "
     "le worktree `streaming`, une base de code DIFFERENTE. Il n'y avait jamais "
     "eu de reference sur la branche courante. "
     "LES DEUX VRAIES CAUSES ETAIENT PREEXISTANTES : `minAppariements` a 2 "
     "(26 % de fenetres refusees contre 4,5 %) et le mauvais "
     "`word_tokens.json` (celui du modele tajwid : meme vocab.json au bit pres, "
     "mais seulement 13 282 cles communes sur 19 001 -- deux JEUX DE MOTS "
     "differents). Avec lui, des mots dont `entendu` etait EXACTEMENT "
     "l'attendu (`وَمَآ`, `إِلَّآ`, `كَمَآ`) sortaient rouges. "
     "DEUX HYPOTHESES DE L'AGENT REFUTEES AU PASSAGE : la tete 3 (coupee, taux "
     "inchange 9,32/9,24/10,00) et le modele 3 tetes (logprobs BIT-IDENTIQUES "
     "a final-v1, ecart max 0,0000 sur 20 s, argmax identique sur 100 % des "
     "frames)."),

    ("mesure_tete3_audio_reel_complete_le_tts_sans_le_remplacer",
     "[MESURE] Audio reel re-etiquete : 37 % combine, 10 % seul, 33 % en TTS seul",
     "Idee de l'utilisateur : le mecanisme d'entrainement de la tete 3 ne "
     "regarde JAMAIS ce que l'audio dit -- il score contre le texte canonique "
     "DECLARE. Rien n'exige donc que l'audio soit synthetique : on prend un "
     "clip REEL du corpus (201 956 clips de recitateurs professionnels) et on "
     "declare pour un mot un canonique FAUX. "
     "MESURE, detection a 2 % de collateral sur le test TTS tenu a l'ecart : "
     "TTS seul 33 % ; audio reel seul 10 % ; TTS + reel 37 %. "
     "L'audio reel seul est PIRE : trop « propre » (son net contre etiquette "
     "fausse), il n'apprend jamais l'ambiguite qu'on cherche a detecter. Il "
     "COMPLETE le TTS, il ne le remplace pas. "
     "Elargir a 30 000 clips reels DEGRADE (32 %/57 % contre 37 %/61 %) : "
     "question de dosage, pas de volume. "
     "Regles imposees par l'utilisateur pour la generation : substitutions "
     "proches ET eloignees, omission, insertion -- et JAMAIS la derniere "
     "harakat d'un mot, un waqf en fin de mot etant licite et non une faute."),

    ("mesure_xtts_ne_rend_pas_les_emphatiques_dad_dha",
     "[MESURE] XTTS ne rend quasiment pas ض/ظ : 2 a 13 % de rendement",
     "Confusions ajoutees le 2026-08-04 apres recherche web (plusieurs sources "
     "FR/EN/AR citent ض/ظ comme l'une des plus frequentes, meme chez des "
     "natifs). Rendement au controle d'audibilite de la passe 2, 63 cas par "
     "paire : ث->س 51 % ; س->ث 14 % ; ظ->ض 13 % ; ض->ظ 2 %. "
     "Une premiere generation aleatoire de 400 phrases n'avait produit que 13 "
     "occurrences de ces lettres (rares en arabe) -- il a fallu FILTRER les "
     "phrases sources sur la lettre cible pour obtenir un echantillon "
     "exploitable. "
     "CONCLUSION : pour ض/ظ la voie n'est pas la synthese mais l'enregistrement "
     "HUMAIN. Les paires lues par un humain le 2026-08-04 sortaient nettes au "
     "decodage la ou XTTS echoue."),
]

LIENS = [
    ("piege_decoder_une_tete_multilabel_comme_du_ctc",
     "piege_frames_du_mot_mesurent_des_pics_pas_une_duree", "masquait",
     "la peakiness attribuee au CTC venait de l'argmax, pas du modele"),
    ("regle_sous_famille_du_madd_est_grammaticale_pas_acoustique",
     "mort_juger_le_madd_par_la_duree_des_runs_ctc", "a_motive",
     "puisque le type vient du texte, on a cherche a mesurer la duree -- refute"),
    ("regle_sous_famille_du_madd_est_grammaticale_pas_acoustique",
     "mesure_fusion_madd_binaire_divise_la_loss_par_deux", "a_motive",
     "cesser de demander a l'acoustique une categorie grammaticale"),
    ("piege_banc_marqueur_de_fin_de_la_session_precedente",
     "piege_confondre_les_instruments_de_mesure", "illustre",
     "un banc defectueux fabrique des ecarts qu'on attribue au code"),
    ("piege_comparer_deux_branches_en_croyant_mesurer_un_correctif",
     "piege_confondre_les_instruments_de_mesure", "illustre",
     "la reference et la mesure ne venaient pas de la meme base de code"),
    ("piege_compter_les_non_verts_sans_les_mots_jamais_juges",
     "piege_comparer_deux_branches_en_croyant_mesurer_un_correctif", "aggrave",
     "un taux flatteur rend une fausse attribution plus credible encore"),
    ("mesure_omis_verrouille_jetait_les_corrections_de_la_v2",
     "piege_frames_du_mot_mesurent_des_pics_pas_une_duree", "distinct_de",
     "l'un est un verrou cote Dart, l'autre une fenetre de recherche cote Kotlin"),
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
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid in connus:
            continue
        g["nodes"].append({
            "label": label, "file_type": "concept",
            "source_file": "SOLUTIONS_RECITATION_V2.md", "source_location": None,
            "source_url": None, "captured_at": "2026-08-04", "author": None,
            "contributor": None, "rationale": rationale, "_origin": "semantic",
            "id": nid, "community": 0, "norm_label": label.lower(),
        })
        ajoutes += 1
    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel, pourquoi in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente : {s} -> {t}")
            continue
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": pourquoi, "rationale": pourquoi})
        aretes += 1
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step23.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
