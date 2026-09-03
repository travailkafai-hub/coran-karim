#!/usr/bin/env python3
"""Journee du 2026-09-03 : ecritures du mushaf, session media, CPU de l'ASR.

Toutes les valeurs ci-dessous sont MESUREES sur device ou dans les binaires
(fontTools), jamais estimees. Deux erreurs de mesure de la meme journee y
figurent aussi : une mesure fausse consignee vaut mieux qu'une mesure fausse
refaite six mois plus tard.
"""
import json, shutil, subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_cpu_recitation_deux_parallelismes",
     "[MESURE] Le CPU de la recitation vient de DEUX parallelismes empiles, pas d'un ASR gourmand -- 163 % -> 133 % en bornant les threads ONNX",
     "Constat utilisateur (« je sens le tel devenir chaud »), puis sa question "
     "qui a mene a la cause : « c'est un seul ASR qui fait tourner 3 coeurs ? ». "
     "Non. Releve des threads du processus pendant une recitation : CINQ "
     "threads `DefaultDispatch` actifs simultanement (649+244+242+239+176 ticks) "
     "-- le pool de coroutines Kotlin, dimensionne au nombre de coeurs (8), et "
     "AUCUN mutex ne serialise les inferences (les `synchronized` de "
     "BufferedTranscriber portent sur le tampon d'echantillons, pas sur l'appel "
     "ONNX). Par-dessus, `OrtSession.SessionOptions()` par defaut laissait ONNX "
     "Runtime paralleliser CHAQUE inference sur autant de threads qu'il voit de "
     "coeurs. Plus de threads que de coeurs = sur-souscription : le processeur "
     "arbitre entre des inferences qui se disputent les memes unites, il chauffe "
     "sans aller plus vite. CORRECTIF MESURE (meme WAV rejoue, meme riwaya, "
     "seul le reglage change) : intraOp=2 / interOp=1 donne CPU moyen 163 % -> "
     "133 % (-18 %), CPU max 358 % -> 227 % (-37 %), duree d'inference mediane "
     "352 -> 348 ms et p90 709 -> 722 ms, soit inchangee. Verdicts STRICTEMENT "
     "identiques au mot pres (36 definitif:vert, 32 provisoire:rouge, 31 "
     "definitif:rouge, 9 provisoire:orange, 6 provisoire:vert, 6 "
     "definitif:orange), meme ancre (mot 219), un seul decrochage de part et "
     "d'autre. RESTE : serialiser les inferences elles-memes toucherait la "
     "latence et le temps reel -- non tente."),

    ("piege_v2_ne_mesurait_pas_son_temps_de_calcul",
     "[PIEGE] La chaine v2 ne mesurait NULLE PART son temps d'inference -- les traces existent, mais dans la v1 morte",
     "Un premier banc a cherche `infDebut`/`infFin` sur une session v2 complete "
     "et n'a rien trouve : ces traces sont dans `BufferedTranscriber`, la chaine "
     "v1, qui ne tourne plus (le journal dit `[v2] f=78`). Sans duree "
     "d'inference on ne peut pas arbitrer un reglage de parallelisme : baisser "
     "le CPU en allongeant l'inference serait un echange perdant, et invisible "
     "en ne regardant que le CPU. `FrontOnnx.sorties` journalise desormais la "
     "duree, une ligne `[Inference] computeAll ech=… duree=…ms` par fenetre "
     "(~80 par session, negligeable). REGLE : avant de mesurer une chaine, "
     "verifier que l'instrument appartient au chemin qui tourne."),

    ("piege_banc_heritait_de_la_riwaya_de_l_app",
     "[PIEGE] Un banc de recitation heritait de la riwaya de l'utilisateur -- audio Hafs juge contre texte Warsh, tout rouge",
     "Le reglage persiste valait `flutter.riwaya=warsh` (mis pour la vue Page). "
     "Le banc rejouait `afasy_90.wav`, un enregistrement HAFS. Resultat : mots "
     "rouges en masse et 968 lignes `CtcTokenizer: caractere hors vocab ignore : "
     "'ٱ'` -- l'alef wasla du texte Hafs, absent du vocabulaire Warsh. La mesure "
     "de CPU restait bonne, le jugement des mots ne valait RIEN. Trouve parce "
     "que l'utilisateur a vu le rouge et a demande si le probleme ne venait pas "
     "de la tete Warsh ou Hafs -- il avait raison. Le banc accepte desormais "
     "`--es riwaya hafs|warsh`, applique AVANT tout chargement de texte. REGLE : "
     "un banc qui herite d'un reglage utilisateur ne mesure pas ce qu'on croit."),

    ("piege_dumpsys_battery_set_ac_fige_la_mesure",
     "[PIEGE] `dumpsys battery set ac 0` ne coupe pas la charge : il FIGE tout le rapport batterie, temperature comprise",
     "Premiere tentative de mesure de la chauffe : on coupait la charge par "
     "`dumpsys battery set ac 0` / `set usb 0` pour que le cable d'adb ne fausse "
     "pas le niveau. Les trois regimes (repos, ecoute, recitation) ont rendu "
     "37,6 °C et 100 % A L'IDENTIQUE, au dixieme, sur 3 minutes chacun -- on "
     "mesurait sa propre falsification. Cette commande est un OVERRIDE du "
     "rapport batterie, pas une coupure d'alimentation. Deuxieme erreur du meme "
     "jour : lire la temperature comme le maximum parmi toutes les "
     "`/sys/class/thermal/thermal_zone*`, ce qui change de zone d'un releve a "
     "l'autre et donne des ecarts absurdes (-5, +6,6, -12,7 °C). Ce qui a "
     "tranche, c'est la CHARGE CPU du processus par `top` : repos 0 %, ecoute "
     "40 %, recitation 226 % avec des pointes a 333 %."),

    ("mesure_texte_tajweed_altere_sur_tous_les_versets",
     "[MESURE] `text_uthmani_tajweed` differe du texte coranique sur 100 % des versets -- il ne doit JAMAIS fournir les caracteres",
     "Recensement sur les 6236 versets Hafs, champ depouille de ses balises : "
     "100 % different, 384 natures d'ecart. Les principales : le numero de "
     "verset deja ecrit en fin de texte (6208x, d'ou un doublon avec le "
     "medaillon), U+200C ajoute (3836x), le petit zero des lettres muettes "
     "U+06DF remplace par un sukun U+0652 (3676x -- ce n'est PAS le meme signe : "
     "l'un dit « ecrit, pas prononce », l'autre « prononce sans voyelle »), alif "
     "suscrit U+0670 -> alef a hamza ondulee U+0672 (1479x), tatweel U+0640 "
     "ajoute (495x -- les longs traits visibles au-dessus des mots), alef perdu "
     "(395x), tanwin degrades en voyelle simple (313x). En WARSH, 6235 versets "
     "sur 6236 n'ont AUCUNE version tajwid. Le remede existait depuis le "
     "2026-07-10 (`tajweedSpansPerWord` reconstruit chaque mot depuis "
     "`text_uthmani` et n'emprunte que la couleur) ; la vue Page ecrite le "
     "2026-09-01 etait le seul endroit de l'app a peindre les caracteres de "
     "l'annotation. Trouve a l'oeil nu par l'utilisateur."),

    ("mesure_4578_marques_du_mushaf_ecartees_par_le_filtre",
     "[MESURE] 4578 marques du mushaf sont ecartees par le filtre des mots RECITABLES -- il faut les rendre au rendu, pas au decoupage",
     "Recensement Hafs : 4578 tokens isoles sans lettre, 9 formes -- waqf jim "
     "U+06DA 1972x, sali U+06D6 1682x, qali U+06D7 603x, rub el hizb U+06DE "
     "199x, lam-alef U+06D9 68x, mim U+06D8 22x, trois points U+06DB 12x, seen "
     "U+06DC 5x, et les 15 sajdas U+06E9. `tajweedSpansPerWord` les ecarte a "
     "dessein : son filtre est celui de la chaine de jugement, et un token de "
     "plus decalerait tous les index (bug corrige le 2026-07-11). Mais ce qui ne "
     "se RECITE pas doit se VOIR. On les reintroduit AU RENDU, jamais dans le "
     "decoupage. En WARSH : 0 token isole -- les signes y sont deja colles au "
     "mot, ce qui est aussi la forme correcte a l'affichage (une marque HAUTE "
     "sans lettre porteuse flotte vers la ligne du dessus)."),

    ("mesure_aucune_police_n_englobe_le_medaillon",
     "[MESURE] AUCUNE police n'englobe le numero dans le medaillon U+06DD -- le rendre en Amiri quelle que soit l'ecriture",
     "Mesure fontTools sur 14 polices. U+06DD est de categorie Unicode `Cf` "
     "(format), pas `Me` (enclosing mark) : rien n'oblige un moteur a lui faire "
     "avaler les chiffres. Aucune police n'a de regle GSUB liant U+06DD aux "
     "chiffres arabes. Et leurs metriques disent toutes la meme chose -- avance "
     "d'environ un cadratin pour un dessin a peine plus etroit (Amiri 1279/1191, "
     "Scheherazade 1984/1809, Harmattan 2019/1912) : le signe se pose A COTE du "
     "numero. Quatre polices ne l'ont meme pas (Aref Ruqaa, Reem Kufi, Markazi "
     "Text, Bouazzi Maghribi). CORRIGE UNE NOTE ANTERIEURE qui affirmait "
     "qu'« Amiri compose U+06DD correctement, contrairement a scheherazadeNew » "
     "-- c'est faux, ce qui differe est le dessin et le calage. Le medaillon est "
     "donc rendu en Amiri quelle que soit l'ecriture de la page, comme le signe "
     "de sajda l'est en Scheherazade (Amiri le dessine en rosace florale au lieu "
     "de la forme en niche)."),

    ("piege_taille_mesuree_sur_la_police_de_secours",
     "[PIEGE] La recherche de taille mesurait le texte avec la police de SECOURS -- six ecritures rendaient la meme occupation au dixieme",
     "Balayage de 24 ecritures, occupation verticale de la page : Noto Sans "
     "Arabic, IBM Plex Arabic, Markazi Text, Bouazzi Maghribi et Harmattan "
     "rendaient 22,5 %, Alkalami 22,4 %. Une egalite au dixieme entre six "
     "dessins differents n'est pas possible, sauf si toutes ont ete mesurees "
     "avec la MEME police. `GoogleFonts.getFont` rend un `TextStyle` "
     "immediatement et telecharge la police en arriere-plan : la dichotomie "
     "travaillait sur le repli, choisissait une taille pour LUI, puis la vraie "
     "police remplacait le dessin sans que la taille soit recalculee -- d'ou le "
     "symptome utilisateur « la taille ne s'ajuste pas au changement d'ecriture ; "
     "apres balayage, elle s'ajuste ». CORRECTIF : ecouter "
     "`PaintingBinding.instance.systemFonts`, le notificateur que Flutter emet "
     "quand une police devient disponible. Prefere a "
     "`GoogleFonts.pendingFonts()` (absent de la version du cache) et a un delai "
     "fixe (le temps de telechargement depend du reseau)."),

    ("piege_clipRect_masque_un_debordement_il_ne_le_corrige_pas",
     "[PIEGE] Un `ClipRect` masque un debordement au lieu de le signaler -- la derniere ligne du Coran etait coupee en silence",
     "En supprimant les 11,4 % de vide de la page (reserve de securite rendue "
     "ABSOLUE au lieu de proportionnelle -- elle protege d'une diacritique "
     "haute, ce qui vaut une fraction du corps et non 7 % de la page --, puis "
     "reliquat de la dichotomie converti en interligne), la somme des hauteurs "
     "pouvait depasser la place disponible. Le `ClipRect` de la page, pose la "
     "contre les diacritiques, coupait alors la derniere ligne SANS RIEN DIRE : "
     "invisible au calcul, visible a l'oeil (constate page 4). CORRECTIF : la "
     "somme est REMESUREE apres chaque recul, et la page recule tant que ca ne "
     "rentre pas -- d'abord en rendant l'air ajoute, ensuite en descendant le "
     "corps. Mesure du gain conserve : vide haut+bas 11,4 % -> 0,1 % de la "
     "hauteur interieure du cadre."),

    ("mesure_aucune_police_n_etait_embarquee",
     "[MESURE] Aucune police n'etait dans l'APK -- la police du Coran dependait du reseau",
     "Inspection du cache de `google_fonts` sur l'appareil : TOUTES les polices "
     "y etaient telechargees, Amiri comprise (Amiri_regular 403 Ko, Amiri_700 "
     "379 Ko), aux cotes de Manrope, Fraunces et Baloo2. `pubspec.yaml` n'avait "
     "aucune section `fonts:`. Sur un telephone jamais connecte depuis "
     "l'installation, Flutter se rabattait donc sur la police systeme, qui ne "
     "dessine ni le medaillon de fin de verset ni les marques de waqf -- alors "
     "que le TEXTE est local depuis le commit « Coran 100 % local ». CORRIGE "
     "pour 825 Ko (Amiri-Regular 421 + Amiri-Bold 404 : le poids w600 du texte "
     "n'existe pas chez Amiri, qui n'a que 400 et 700). VERIFIE hors ligne, "
     "cache vide, wifi et donnees coupes : la page tient, et le cache reste a "
     "zero fichier Amiri. Les 11 autres ecritures du selecteur restent en "
     "telechargement a la demande (3,8 Mo au total, usage ponctuel). ⚠️ NE PAS "
     "RENOMMER les fichiers de `google_fonts/` : le package les reconnait par "
     "leur nom officiel, un nom modifie casse la reconnaissance EN SILENCE et la "
     "police repasse par le reseau."),

    ("piege_extra_absent_de_la_map_de_MainActivity",
     "[PIEGE] La map d'extras de MainActivity se construit cle par cle -- un extra absent n'atteint jamais Dart, en silence",
     "Un parametre de banc `--es ecriture <famille>` a ete ajoute cote Dart et "
     "cote recette_screen, et le balayage a rendu TREIZE captures identiques au "
     "MD5 pres. Cause : `MainActivity` construit la map remise a Dart cle par "
     "cle (`mapOf(\"mode\" to m, \"sourate\" to s, …)`) ; une cle absente de "
     "cette liste est simplement perdue, sans erreur ni journal. Meme piege "
     "ensuite pour `--es riwaya`. REGLE : tout nouvel extra de banc se declare "
     "aux TROIS etages -- MainActivity, main.dart, RecetteScreen."),

    ("mesure_session_media_liberer_sans_garder_l_app_vivante",
     "[MESURE] La lecture continue app reduite par une session media -- l'interface Flutter est suspendue, seul un service natif joue",
     "Demande utilisateur : pause/play depuis la notification pour « liberer, "
     "economiser la batterie », avec la bonne intuition -- « garder toute l'app "
     "en arriere-plan, c'est pas une bonne idee ». Verifie sur device, app "
     "reduite : le service `com.ryanheise.audioservice.AudioService` tourne en "
     "`isForeground=true`, la session est en `PLAYING` avec la position qui "
     "avance, la notification affiche sourate et reciteur avec "
     "stop/precedent/pause/suivant, le selecteur « Sortie media » propose les "
     "ecouteurs Bluetooth, et `MediaButtonReceiver` est branche. "
     "`AudioPlayerService` n'est PAS touche : il porte la logique MP3Quran "
     "(fichier de sourate entiere, minuteur de frontiere de verset), migrer vers "
     "just_audio l'aurait fait reecrire. PORTEE : regle le confort et la "
     "consommation pendant l'ECOUTE (40 % de CPU) ; la chauffe de la RECITATION "
     "(226 %) est un autre chantier. PIEGE PAYE : les commentaires XML "
     "n'admettent pas `--`, le manifeste ne parsait plus et le build echouait "
     "sur un message qui ne le disait pas."),

    ("mesure_micro_bluetooth_absent_de_l_app",
     "[MESURE] Le micro d'un casque Bluetooth n'etait pas utilise -- aucun code de routage, et le brancher degrade l'ASR",
     "Question utilisateur sur les micros de casque. Verifie dans le code : "
     "ECOUTER en Bluetooth ou en filaire marchait deja (route media A2DP) ; "
     "RECITER avec un casque FILAIRE marchait deja (Android route seul) ; "
     "RECITER avec un casque BLUETOOTH ne marchait pas -- l'app n'avait AUCUN "
     "code de routage (ni `startBluetoothSco`, ni `setCommunicationDevice`, ni "
     "`MODE_IN_COMMUNICATION`), et Android ne bascule pas seul. ⚠️ LE REGLAGE "
     "EST ETEINT PAR DEFAUT : le profil HFP/SCO compresse la voix en bande "
     "etroite alors que le modele est entraine sur du 16 kHz propre. Basculer "
     "des qu'un casque est connecte aurait degrade le jugement SANS QUE "
     "PERSONNE NE LE SACHE. RESTE A MESURER : le WER en SCO n'a jamais ete "
     "chiffre sur ce projet -- tant qu'il ne l'est pas, c'est une possibilite "
     "offerte, pas une recommandation. A ne pas confondre avec la suppression "
     "de bruit, retiree de l'IHM parce que la mesure la donnait perdante "
     "(70,2 % de WER activee contre 22,8 % eteinte) : ici il n'y a pas "
     "d'alternative."),

    ("attente_taux_du_banc_afasy_90_mauvais_en_soi",
     "[EN ATTENTE] Le banc `afasy_90` rend 36 verts pour 63 rouges sur un enregistrement PROFESSIONNEL -- preexistant, non instruit",
     "Mesure du 2026-09-03, riwaya Hafs imposee, WAV rejoue d'Al-Afasy sur la "
     "sourate 90 : 36 definitif:vert, 31 definitif:rouge, 32 provisoire:rouge, "
     "9 provisoire:orange, 6 provisoire:vert, 6 definitif:orange. Ancre au mot "
     "219, un decrochage. Le taux est IDENTIQUE avant et apres le bornage des "
     "threads ONNX, donc il ne vient pas de ce reglage : il est preexistant. "
     "Un recitateur professionnel juge a ce taux est un signal fort, mais il "
     "n'a PAS ete instruit -- il peut venir du banc (fenetre, sourate de "
     "depart, WAV tronque) autant que de la chaine. A reprendre avec le skill "
     "`analyse-session-recitation` avant toute conclusion."),
]

LIENS = [
    ("mesure_cpu_recitation_deux_parallelismes",
     "piege_v2_ne_mesurait_pas_son_temps_de_calcul",
     "depends_on",
     "Le bornage des threads ne pouvait pas etre arbitre sans duree d'inference"),
    ("mesure_cpu_recitation_deux_parallelismes",
     "piege_banc_heritait_de_la_riwaya_de_l_app",
     "depends_on",
     "La mesure n'est comparable qu'une fois la riwaya imposee au banc"),
    ("mesure_cpu_recitation_deux_parallelismes",
     "piege_dumpsys_battery_set_ac_fige_la_mesure",
     "semantically_similar_to",
     "Deux facons de mesurer la chauffe : la premiere s'est mesuree elle-meme"),
    ("mesure_4578_marques_du_mushaf_ecartees_par_le_filtre",
     "mesure_texte_tajweed_altere_sur_tous_les_versets",
     "depends_on",
     "Les marques ne manquaient qu'apres le passage au texte canonique"),
    ("piege_clipRect_masque_un_debordement_il_ne_le_corrige_pas",
     "piege_taille_mesuree_sur_la_police_de_secours",
     "semantically_similar_to",
     "Deux defauts de la meme dichotomie de taille, trouves le meme jour"),
    ("mesure_aucune_police_n_englobe_le_medaillon",
     "mesure_aucune_police_n_etait_embarquee",
     "depends_on",
     "Le repli en Amiri suppose qu'Amiri soit disponible hors ligne"),
    ("mesure_micro_bluetooth_absent_de_l_app",
     "mesure_session_media_liberer_sans_garder_l_app_vivante",
     "semantically_similar_to",
     "Deux volets de la meme demande sur les casques et l'arriere-plan"),
    ("attente_taux_du_banc_afasy_90_mauvais_en_soi",
     "mesure_cpu_recitation_deux_parallelismes",
     "depends_on",
     "Taux releve pendant cette mesure, identique avant et apres"),
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
    shutil.copy2(GRAPHE, SORTIE / "graph_avant_step31.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{a} noeuds, +{ar} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")


if __name__ == "__main__":
    main()
