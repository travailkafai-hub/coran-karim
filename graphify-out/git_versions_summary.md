cde1472 (refs/stash) On test-1-gop: v29-libre-conseil : presentDansLibre en CONSEIL (topologie mot + penalite silence) - NON MESURE
9897416 index on test-1-gop: e735f99 Le log du secours donne les TROIS scores, et le superviseur devient obligatoire
db98d26 (HEAD -> chunkwise-aligner) CHUNKWISE + rattrapage borne, sur branche d'experimentation (NON MESURE)
9e2248c (gradient-aligner) Alignement par gradient : blocage de stack documente, branche laissee vide
e735f99 (test-1-gop) Le log du secours donne les TROIS scores, et le superviseur devient obligatoire
bca8706 v24 : la chaine consolidee, et le decrochage disparait (mediane 25,34 % -> 11,78 %)
ba0ee82 conserve=0 REFUTE par l'intervention : correlation parfaite, causalite nulle
6dc9759 Consigne : l'app ne sait pas suivre un reciteur qui REPETE
60bb88e Le discriminant du decrochage : conserve=0, l'audio non garde entre deux segments
bb388c0 Le decrochage n'est pas dans le texte : il est dans un rattrapage qui echoue
d709c7d Le decrochage tombe au MEME endroit sur six versions -- et l'anneau n'y est pour rien
6e5b2e3 Le decrochage 124-180 : six hypotheses refutees, une seule debout
a0c8935 Banc : le balayage installait en local puis recitait sur le PC B, sans le dire
41df3e3 v23 : le resync est coupe, et la mesure lui donne tort (8,16 % -> 6,12 %)
0be7c40 Les regressions massives n'existaient pas : je comptais deux recitations pour une
8611bfd Correction : la piste B n'est PAS simulable sur les logs existants
28ff277 Recul architectural : l'ancre decroche parce que le verdict d'apercu est jete, pas parce qu'on cherche mal la position
8c92f34 Chiffrer l'audio detruit par la purge-quand-rien-n-est-place, et desamorcer le banc qui a menti
114a8f7 Banc : ou est l'ancre contre ou en est VRAIMENT le reciteur, seconde par seconde
24bc7df Skill : le mot SAUTE, quatrieme facon de ne pas etre vert -- et la seule invisible
69de15a Retour arriere : le resync sur apercu JETTE des mots corrects (mesure)
305db63 Le resync ne devine plus : il aligne aux deux ancres et garde la meilleure
6eea79a Banc : arbitrer le deplacement d'ancre par la MESURE, pas par un seuil
2f01498 Banc : les mots enjambes par le resync sont-ils recuperables ?
934b6e7 Banc : rejouer hors device le resync sur les derives reellement detectees
6d99166 Sonde de 4 lettres rejetee, expansion mise en sommeil : le secours coute plus qu'il ne rapporte quand il se declenche trop
4606d64 Le resync comparait des identifiants de tokens : il compare desormais du TEXTE
6d07754 Secours etendu aux mots valides en amont -- et ce qu'il ne peut PAS reparer
88673bc Le rejeu deterministe attend la FIN DU FICHIER, pas une duree de montre
36c03d0 Rayon de coupe elargi a 2 s : essaye, mesure, rejete
f2d61bc La coupe ne depend plus de l'horloge -- mais le taux n'y gagne pas
4c83d3e L'installation distante echouait en silence : trois recettes analysees sur un binaire perime
a786239 Couper la ou le MODELE ne dit rien, pas la ou le signal est faible
d629d63 Chiffre la cause a la couche ou elle NAIT : 47,4 % des coupes tombent en plein mot
6ae0884 Le contexte droit va AUSSI a la DP : les mots de fin de segment n'avaient pas d'audio
bc43244 Skill « solution-de-fond » : les questions qui separent un correctif d'un pansement
3c3fb74 Pilotage des telephones a distance, et confrontation systematique au modele
b72b05b Recette DETERMINISTE : rejouer un WAV a la place du micro
363a3a1 Contexte des DEUX cotes pour l'encodeur, jugement seulement au centre
8507b0e Retire le palliatif : on ne deplace pas le critere d'acceptation
a54cfe2 La regle de proportion cede devant une preuve d'alignement forte
a97867f Le secours voit enfin les mots TRONQUES, pas seulement les mots absents
44305da Le secours aligne le mot AVEC SES VOISINS, plus jamais seul
95caeb7 Le banc de recette retire la Basmala : les deux telephones partaient decales
2ced1b1 Recul architectural : 12 faux positifs sur 12, le modele hors de cause
e1fadaa Recette a deux telephones : une commande, aucun tap
8cd6a06 Chaque session dit desormais ce qu'elle teste, et vide sa trace fine
10dd819 Sort le gel a la borne dure du thread audio, et cesse d'ecrire l'audio deux fois
c0935dd Le secours vise enfin les bons mots, et couvre le chemin de la recitation continue
0bf91b0 Skill : impose UN format de compte rendu unique, avec confirmation WAV par mot
84778b6 La fenetre de secours tombait 3 s avant le mot : origine absolue corrigee
5740cee Le secours produisait toujours une liste vide : forceJudgeIndex manquant
f00f53c Regle "pas d'hypothese tant qu'une ligne de log peut trancher" + trace du declencheur
3f5fa4c Corrige deux bugs qui rendaient le secours muet et multipliaient les non juges
488d969 Buffer de secours en lecture seule : rejuge un mot non place, avec contexte
eb231af L'ancre ne cale plus : resynchronisation par le decodage libre, et +1 en mode reference
13ef78e Skill analyse-session-recitation : fige la methode et les erreurs deja commises
d3ff1bf Allege le rendu du karaoke : deux couts quadratiques et un rendu non paresseux
e5c8011 Les bornes de segment portent sur l'audio NOUVEAU, pas sur le contexte
aba4feb Le contexte du chevauchement va a l'encodeur, jamais au juge
4a91ff3 Documente le buffer de secours decale comme piste VIVANTE, pas ecartee
e12cf33 Corrige la boucle de re-gel introduite par le chevauchement
cd5c0f0 Segments chevauchants : 3 s de contexte pour ne plus commencer en plein mot
03f9a42 Enregistre le clip du gel a la borne dure : 35 % de l'audio n'existait dans aucun fichier
f7db06a Enregistre le flux micro BRUT : les decisions du portier RMS etaient inverifiables
ac4397f Groupe le transport PCM : supprime la file d'attente qui grossissait sans borne
ec8ec43 Deduit les durees par mot sur le telephone, en fin de session de reference
b3cf46b Corrige la regression du matin : l'ancre ne peut plus bloquer sur un mot non place
7bfab61 Banc de mesure des durees depuis les clips WAV (repond oui a la question, banc pas fini)
923b500 Journalise le mode de session et le seuil de gel applique
d34fa35 Ferme la derniere fuite d'ecriture qui echappait a l'interrupteur de diagnostic
73325d8 Trace fine du pipeline audio, accumulee en memoire pour ne pas fausser la mesure
f972a8a Journalise les bornes de frames : le compte de frames non-blank n'est pas une duree
b68ef31 Apprend la duree des mots dans la voix du recitateur et s'en sert au lieu de quran.com
96cb5e9 Precise la piste "recitation de reference" : durees articulees et plancher = minimum
3f75b94 Journalise la duree reelle par mot, pour mesurer le gain d'un plancher "voix propre"
427296b Mesure l'apport reel des durees de reference et documente la piste "recitation de reference"
f634f92 Cesse de condamner un mot quand c'est la DP qui a echoue
b619203 Collecte les durees de reference mot-a-mot, en vue d'un plancher d'alignement realiste
39a2b5d Distingue "la DP a echoue" de "mot saute" par la place reellement disponible
827be11 Mesure les mots en frontiere avant de decider d'un second decodage
3f74bae Teste Nemotron 3.5 comme encodeur de base : faisabilite prouvee, perf insuffisante
c2cc4de Ne juge plus un mot quand le modele est sur de ce qu'il entend (trou d'alignement)
028be10 Retire la validation groupee par GOP : mesuree sans aucun gain
e81447c Ignore la sortie generee par graphify
33378dd Bascule sur le repli bufferise : garde le modele causal, abandonne le cache-aware
b9bf09d Fiabilise la capture WAV de diagnostic et cesse de juger la Bismillah sans preuve
4f5f642 Mesure le causal dans le regime REEL de l'app, et comble le trou "detection de fautes"
85b337c feat: ajoute le compte à rebours avant récitation
7a8969d feat: orchestre le démarrage de la récitation
5d70d32 fix: recalcule le score après un recul
52b03e0 fix: resynchronise la reprise après correction
a01d2d4 docs: valide le causal sur appareil
3b1f7f5 docs: consigne la livraison du streaming causal
d535b1b feat: active le modèle causal dans le flux continu
13f3ede feat: complète le paquet causal avec son tokenizer
f74ded8 feat: porte le moteur Android sur le causal stateful
6a09ff8 feat: verrouille le contrat du modèle causal
a293172 feat: maintient le décodage CTC entre les chunks
d729875 feat: fiabilise l'export ONNX causal stateful
5a0d2af chore: point de retour avant le streaming causal
6cf960c feat: bascule l'app sur le modele causal sans tajwid
9a7efa7 Ajoute le pipeline d'entrainement streaming causal (encodeur + tete tajwid)
bc45760 feat: recentre l'ornement des sourates
1accd18 fix: preserve les diagnostics de recitation
017f2a8 perf: limite le controle initial a une page
2256073 feat: fait progresser le coach ayah par ayah
a2dc28b feat: planifie les rappels de priere locaux
c9b6aa7 Valide les mots par GROUPE quand le GOP est bon, au lieu de carver mot par mot
196bff1 Rend la correction immediate : 15,9 s -> 0,003 s avant le retour de l'ancre
08556f8 Corrige la chaine de recitation : course de gel, purge de l'audio consomme, verdicts sans preuve
a6a34cf (asr-nemo-solutions) Ajoute le detail par classe de regle dans eval_tajwid()
d06c6ee Corrige la perte d'audio dans BufferedTranscriber et le verrou premature des mots en recouvrement
3af3501 Documente les problematiques ASR (buffer, GOP, pauses) et l'etat de l'art externe
ab23576 Documente les problematiques ASR (buffer, GOP, pauses) et l'etat de l'art externe
58db2fa (test-2-gop) Branche de test 2-GOP : moteur ASR à l'état c9c531f (2 têtes + segmentation recouvrement 2s)
5df2735 Corrige le crash natif ONNX (vraie cause : R8 obfusquait ai.onnxruntime.**)
5ca97e9 Corrige un crash natif JNI (SIGABRT) sur le thread du pool de coroutines
8193111 Branche de test : moteur ASR à l'état 5d97e09 (1 GOP + tête tajwid séparée)
f192ba8 (master) Ajoute la chronologie de session (diagnostic récitation/alignement/GOP)
4b42b4a Revert ciblé du moteur ASR vers l'état avant les 2 GOP (a2d3054), test isolé
96b0ccd Documentation : handoff Ubuntu, plan hybride et résultats de benchmark à jour
d9418ce Ajoute les scripts du pipeline 2-têtes (dual-head) et TTS apparié, jamais commités
ed18c57 WIP : ajustements UI dispersés (duas, prière, thème, écrans de navigation)
0aa3d8d WIP : localisation (l10n) des libellés tajwid, jeu de mémorisation, baseline GOP par mot
24d7521 Réorganise les mindmaps par langue (ar/en/fr) au lieu d'un dossier plat
f94a890 Revert ASR+coach vers l'état avant les 2 GOP (a2d3054), pour test comparatif
ed2ca8a Revert temporaire ASR vers l'état 2-GOP (5d97e09), pour test isolé avant segmentation
c9c531f Corrige le vocabulaire "hésitation" -> pauses normales entre versets, ajoute l'augmentation par pauses
86dfb91 Documente les 3 hypothèses de segmentation rejetées et la règle des commits par périmètre
5b14b8d Bancs de mesure pour la segmentation ASR + option stats fixes dans mel_numpy_reference
d671c33 Diagnostique et corrige les blocages d'ancre sur récitation hésitante
5d97e09 Fiabilise le jugement tajwid : 2 têtes branchées, GOP dépiégé, stats honnêtes
a2d3054 Renforce le correctif GOP : renormalisation pré-softmax + exclusion du chadda nu
64215d0 Corrige la pénalité systématique des symboles de règles dans le GOP (Kotlin)
746df89 Le mode tajwid vérifie enfin le tajwid (règle attendue vs règle réalisée)
dd8f757 Sépare prononciation et tajwid : l'alignement forcé repasse sur le texte nu
db43917 Traces de diagnostic récitation : mode, changements de mode, ancre
54d68c4 Passation : ajoute les 2 derniers commits + la nature bi-chantier de cc94417
cc94417 Cartes mentales des 114 sourates + erreurs catégorisées par type (+ refonte Invocations/Rites de l'agent parallèle)
761108d Passation : ajoute les corrections de fin de session
8f8c00a Règles tajwid : le garde-fou passe d'un blocage à un plafond
8b58a03 Passation de session 2026-07-20 pour l'agent suivant
07579bc Refonte du volet Coach : la mémorisation rassemblée en un hub
59dbae9 Tiroir de lecture scrollable + filigrane à motif du mushaf
ae2362c Corrige l'export ONNX du modèle 260h : audio_signal (mel) au lieu de raw_audio
b060070 Corrige l'overflow "RIGHT OVERFLOWED BY 5.5 PIXELS" de la barre de navigation
08efcc9 Déploie le modèle stage1b-260h dans le cœur ASR + câble les modes de jugement
508dede Export stage1b-260h pour déploiement app (ONNX CTC + asset mots annotés)
5c3bfed Redesign SurahOrnamentHeader v2 : médaillon SVG au lieu du cadre CustomPainter
0d3dea7 Continue stage1b sur 260h Coran (vs 150h) : 2 bugs de chemins corrigés + gain net mesuré
7cbad88 Infrastructure langue de l'application (REFONTE_IHM.md §7bis) : squelette ARB + réglage
5410892 Carte mentale des sourates (REFONTE_IHM.md §7) : rendu graphview + contenu initial
f22ff35 Refonte IHM complète : jugement post-décodage + décentralisation des réglages
76506af Spécification détaillée de la refonte IHM (exécutable sans invention)
548fe14 Coran 100% local (fini le "Connexion requise" hors-ligne), rescoring NLL diagnostique, corrections "Suivre une prière"
c86ad76 Phase 2.1 confirmée sur checkpoint final + comparaison directe à mixed-e14
84ed271 Triangulation CTC vs RNNT sur les 17 règles + classement de fiabilité par règle
dca9549 Documente l'exigence produit : ciblage par règle, pas de score agrégé
52117c9 Invalide le test cross-récitateur YouTube : confondu par un découpage 30s
3094642 Construit un set de validation YouTube vraiment non-vu, réciteurs vérifiés
c3bdb69 Teste la détection des règles : recall/faux-positifs Coran vs ASC+TTS
66e9453 Mesure préliminaire du test d'interférence (checkpoint intermédiaire, pas final)
6a2957c Reclasse la piste 'données RNNT dédiées' de contingence à expérience prévue
803fd59 Documente le mode enfant : couche de comparaison, pas une 3e tête
5ae7a43 Corrige un crash SIGSEGV (fork+CUDA) du stage 1b — num_workers=0
8f55fd9 Inverse la logique de la tête tolérante : tester l'interférence avant de construire
94e26b6 A/B ctc_loss_weight mesuré (0.7 gagne) + lancement stage 1b complet
b5b97f2 Phase 0 'vrai tajweed' exécutée + lancement du run hybride RNNT+CTC stage 1a
581c367 Glossaire techniques ASR : entraînement vs décodage, et quoi brancher maintenant
f334f8d Plan d'entraînement hybride 3 têtes + triage de priorité des pistes qualité
1f25fc2 Documente l'état CTC NeMo + débloque la loss RNNT (NVVM réparé sous Ubuntu)
3fb04c3 Corrige la troncature per-mot via validation globale (idée utilisateur)
3316e65 Corrige 8/10 findings de la revue de code (2 restants documentés délibérément)
367f769 Documente la revue de code (10/10 findings confirmes) + investigation du lag
9446c10 Contre-revue Sonnet + développement du rescoring tête-à-tête (résultat réel)
22b27e3 Revue d'architecture karaoké + plan d'exécution P0/P1/P2 (Fable)
fc506f6 Corrige la cécité aux erreurs de prononciation (cause racine : token parasite)
9a61b77 Documente l'échec de l'entraînement 100% on-device (ONNX Runtime Training)
6861b0b Revert "Chantier entraînement 100% on-device : bascule vers onnxruntime-training-android"
2ebb383 Chantier entraînement 100% on-device : bascule vers onnxruntime-training-android
9024fb6 Correctifs récitation (perf, sensibilité, référence globale), cascade offline, mini-LoRA v1 (PC-side)
fc6d731 Refonte ASR (GOP forced-alignment), récitation continue, cascade d'explications offline
e800305 Commit initial — Coran Karim
