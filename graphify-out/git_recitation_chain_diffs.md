=== COMMIT cde1472 | 2026-07-30 | On test-1-gop: v29-libre-conseil : presentDansLibre en CONSEIL (topologie mot + penalite silence) - NON MESURE ===
=== COMMIT db98d26 | 2026-07-30 | CHUNKWISE + rattrapage borne, sur branche d'experimentation (NON MESURE) ===
=== COMMIT e735f99 | 2026-07-30 | Le log du secours donne les TROIS scores, et le superviseur devient obligatoire ===
=== COMMIT bca8706 | 2026-07-29 | v24 : la chaine consolidee, et le decrochage disparait (mediane 25,34 % -> 11,78 %) ===
=== COMMIT 6dc9759 | 2026-07-29 | Consigne : l'app ne sait pas suivre un reciteur qui REPETE ===
=== COMMIT bb388c0 | 2026-07-29 | Le decrochage n'est pas dans le texte : il est dans un rattrapage qui echoue ===
=== COMMIT d709c7d | 2026-07-29 | Le decrochage tombe au MEME endroit sur six versions -- et l'anneau n'y est pour rien ===
=== COMMIT a0c8935 | 2026-07-29 | Banc : le balayage installait en local puis recitait sur le PC B, sans le dire ===
=== COMMIT 41df3e3 | 2026-07-29 | v23 : le resync est coupe, et la mesure lui donne tort (8,16 % -> 6,12 %) ===
=== COMMIT 69de15a | 2026-07-29 | Retour arriere : le resync sur apercu JETTE des mots corrects (mesure) ===
=== COMMIT 305db63 | 2026-07-29 | Le resync ne devine plus : il aligne aux deux ancres et garde la meilleure ===
=== COMMIT 6d99166 | 2026-07-29 | Sonde de 4 lettres rejetee, expansion mise en sommeil : le secours coute plus qu'il ne rapporte quand il se declenche trop ===
=== COMMIT 4606d64 | 2026-07-29 | Le resync comparait des identifiants de tokens : il compare desormais du TEXTE ===
=== COMMIT 6d07754 | 2026-07-29 | Secours etendu aux mots valides en amont -- et ce qu'il ne peut PAS reparer ===
=== COMMIT 36c03d0 | 2026-07-29 | Rayon de coupe elargi a 2 s : essaye, mesure, rejete ===
=== COMMIT f2d61bc | 2026-07-28 | La coupe ne depend plus de l'horloge -- mais le taux n'y gagne pas ===
=== COMMIT a786239 | 2026-07-28 | Couper la ou le MODELE ne dit rien, pas la ou le signal est faible ===
=== COMMIT 6ae0884 | 2026-07-28 | Le contexte droit va AUSSI a la DP : les mots de fin de segment n'avaient pas d'audio ===
=== COMMIT 363a3a1 | 2026-07-28 | Contexte des DEUX cotes pour l'encodeur, jugement seulement au centre ===
=== COMMIT 8507b0e | 2026-07-28 | Retire le palliatif : on ne deplace pas le critere d'acceptation ===
=== COMMIT a54cfe2 | 2026-07-28 | La regle de proportion cede devant une preuve d'alignement forte ===
=== COMMIT a97867f | 2026-07-28 | Le secours voit enfin les mots TRONQUES, pas seulement les mots absents ===
=== COMMIT 44305da | 2026-07-28 | Le secours aligne le mot AVEC SES VOISINS, plus jamais seul ===
=== COMMIT 8cd6a06 | 2026-07-28 | Chaque session dit desormais ce qu'elle teste, et vide sa trace fine ===
=== COMMIT 10dd819 | 2026-07-28 | Sort le gel a la borne dure du thread audio, et cesse d'ecrire l'audio deux fois ===
=== COMMIT c0935dd | 2026-07-27 | Le secours vise enfin les bons mots, et couvre le chemin de la recitation continue ===
=== COMMIT 84778b6 | 2026-07-27 | La fenetre de secours tombait 3 s avant le mot : origine absolue corrigee ===
=== COMMIT 5740cee | 2026-07-27 | Le secours produisait toujours une liste vide : forceJudgeIndex manquant ===
=== COMMIT f00f53c | 2026-07-27 | Regle "pas d'hypothese tant qu'une ligne de log peut trancher" + trace du declencheur ===
=== COMMIT 3f5fa4c | 2026-07-27 | Corrige deux bugs qui rendaient le secours muet et multipliaient les non juges ===
=== COMMIT 488d969 | 2026-07-27 | Buffer de secours en lecture seule : rejuge un mot non place, avec contexte ===
=== COMMIT eb231af | 2026-07-27 | L'ancre ne cale plus : resynchronisation par le decodage libre, et +1 en mode reference ===
=== COMMIT e5c8011 | 2026-07-27 | Les bornes de segment portent sur l'audio NOUVEAU, pas sur le contexte ===
=== COMMIT aba4feb | 2026-07-27 | Le contexte du chevauchement va a l'encodeur, jamais au juge ===
=== COMMIT e12cf33 | 2026-07-27 | Corrige la boucle de re-gel introduite par le chevauchement ===
=== COMMIT cd5c0f0 | 2026-07-27 | Segments chevauchants : 3 s de contexte pour ne plus commencer en plein mot ===
=== COMMIT 03f9a42 | 2026-07-27 | Enregistre le clip du gel a la borne dure : 35 % de l'audio n'existait dans aucun fichier ===
=== COMMIT ac4397f | 2026-07-27 | Groupe le transport PCM : supprime la file d'attente qui grossissait sans borne ===
=== COMMIT ec8ec43 | 2026-07-27 | Deduit les durees par mot sur le telephone, en fin de session de reference ===
=== COMMIT b3cf46b | 2026-07-27 | Corrige la regression du matin : l'ancre ne peut plus bloquer sur un mot non place ===
=== COMMIT 73325d8 | 2026-07-27 | Trace fine du pipeline audio, accumulee en memoire pour ne pas fausser la mesure ===
=== COMMIT f972a8a | 2026-07-27 | Journalise les bornes de frames : le compte de frames non-blank n'est pas une duree ===
=== COMMIT b68ef31 | 2026-07-27 | Apprend la duree des mots dans la voix du recitateur et s'en sert au lieu de quran.com ===
=== COMMIT 3f75b94 | 2026-07-27 | Journalise la duree reelle par mot, pour mesurer le gain d'un plancher "voix propre" ===
=== COMMIT f634f92 | 2026-07-27 | Cesse de condamner un mot quand c'est la DP qui a echoue ===
=== COMMIT 39a2b5d | 2026-07-27 | Distingue "la DP a echoue" de "mot saute" par la place reellement disponible ===
=== COMMIT 827be11 | 2026-07-27 | Mesure les mots en frontiere avant de decider d'un second decodage ===
=== COMMIT c2cc4de | 2026-07-26 | Ne juge plus un mot quand le modele est sur de ce qu'il entend (trou d'alignement) ===
=== COMMIT 028be10 | 2026-07-26 | Retire la validation groupee par GOP : mesuree sans aucun gain ===
=== COMMIT b9bf09d | 2026-07-26 | Fiabilise la capture WAV de diagnostic et cesse de juger la Bismillah sans preuve ===
=== COMMIT 5d70d32 | 2026-07-26 | fix: recalcule le score après un recul ===
=== COMMIT 52b03e0 | 2026-07-26 | fix: resynchronise la reprise après correction ===
=== COMMIT d535b1b | 2026-07-26 | feat: active le modèle causal dans le flux continu ===
=== COMMIT f74ded8 | 2026-07-26 | feat: porte le moteur Android sur le causal stateful ===
=== COMMIT 6a09ff8 | 2026-07-26 | feat: verrouille le contrat du modèle causal ===
=== COMMIT a293172 | 2026-07-26 | feat: maintient le décodage CTC entre les chunks ===
=== COMMIT 1accd18 | 2026-07-26 | fix: preserve les diagnostics de recitation ===
=== COMMIT c9b6aa7 | 2026-07-25 | Valide les mots par GROUPE quand le GOP est bon, au lieu de carver mot par mot ===
=== COMMIT 196bff1 | 2026-07-25 | Rend la correction immediate : 15,9 s -> 0,003 s avant le retour de l'ancre ===
=== COMMIT 08556f8 | 2026-07-25 | Corrige la chaine de recitation : course de gel, purge de l'audio consomme, verdicts sans preuve ===
=== COMMIT d06c6ee | 2026-07-24 | Corrige la perte d'audio dans BufferedTranscriber et le verrou premature des mots en recouvrement ===
=== COMMIT 58db2fa | 2026-07-23 | Branche de test 2-GOP : moteur ASR à l'état c9c531f (2 têtes + segmentation recouvrement 2s) ===
=== COMMIT 5ca97e9 | 2026-07-23 | Corrige un crash natif JNI (SIGABRT) sur le thread du pool de coroutines ===
=== COMMIT 8193111 | 2026-07-23 | Branche de test : moteur ASR à l'état 5d97e09 (1 GOP + tête tajwid séparée) ===
=== COMMIT 4b42b4a | 2026-07-23 | Revert ciblé du moteur ASR vers l'état avant les 2 GOP (a2d3054), test isolé ===
=== COMMIT 24d7521 | 2026-07-23 | Réorganise les mindmaps par langue (ar/en/fr) au lieu d'un dossier plat ===
=== COMMIT f94a890 | 2026-07-23 | Revert ASR+coach vers l'état avant les 2 GOP (a2d3054), pour test comparatif ===
=== COMMIT ed2ca8a | 2026-07-23 | Revert temporaire ASR vers l'état 2-GOP (5d97e09), pour test isolé avant segmentation ===
=== COMMIT d671c33 | 2026-07-23 | Diagnostique et corrige les blocages d'ancre sur récitation hésitante ===
=== COMMIT 5d97e09 | 2026-07-23 | Fiabilise le jugement tajwid : 2 têtes branchées, GOP dépiégé, stats honnêtes ===
=== COMMIT a2d3054 | 2026-07-20 | Renforce le correctif GOP : renormalisation pré-softmax + exclusion du chadda nu ===
=== COMMIT 64215d0 | 2026-07-20 | Corrige la pénalité systématique des symboles de règles dans le GOP (Kotlin) ===
=== COMMIT 746df89 | 2026-07-20 | Le mode tajwid vérifie enfin le tajwid (règle attendue vs règle réalisée) ===
=== COMMIT dd8f757 | 2026-07-20 | Sépare prononciation et tajwid : l'alignement forcé repasse sur le texte nu ===
=== COMMIT db43917 | 2026-07-20 | Traces de diagnostic récitation : mode, changements de mode, ancre ===
=== COMMIT cc94417 | 2026-07-20 | Cartes mentales des 114 sourates + erreurs catégorisées par type (+ refonte Invocations/Rites de l'agent parallèle) ===
=== COMMIT 8f8c00a | 2026-07-20 | Règles tajwid : le garde-fou passe d'un blocage à un plafond ===
=== COMMIT 08efcc9 | 2026-07-19 | Déploie le modèle stage1b-260h dans le cœur ASR + câble les modes de jugement ===
=== COMMIT f22ff35 | 2026-07-19 | Refonte IHM complète : jugement post-décodage + décentralisation des réglages ===
=== COMMIT 548fe14 | 2026-07-19 | Coran 100% local (fini le "Connexion requise" hors-ligne), rescoring NLL diagnostique, corrections "Suivre une prière" ===
=== COMMIT 3fb04c3 | 2026-07-16 | Corrige la troncature per-mot via validation globale (idée utilisateur) ===
=== COMMIT 3316e65 | 2026-07-16 | Corrige 8/10 findings de la revue de code (2 restants documentés délibérément) ===
=== COMMIT fc506f6 | 2026-07-16 | Corrige la cécité aux erreurs de prononciation (cause racine : token parasite) ===
=== COMMIT 9024fb6 | 2026-07-12 | Correctifs récitation (perf, sensibilité, référence globale), cascade offline, mini-LoRA v1 (PC-side) ===
=== COMMIT fc6d731 | 2026-07-12 | Refonte ASR (GOP forced-alignment), récitation continue, cascade d'explications offline ===
=== COMMIT e800305 | 2026-07-11 | Commit initial — Coran Karim ===
