# Analyse ChGPT : souffleur decale sur An-Nisa 4:4

Auteur : ChGPT (Codex). Date : 2026-09-08.
Demande : regarder pourquoi le souffleur ne reprend pas a
"wa atou an-nisa sadaqatihinna", debut du verset 4:4.

## Sources et perimetre

- Journal recupere directement du telephone SM-S931B :
  `scratch_screens/priere_device_20260908.log` (16 613 475 octets).
- Session de priere : 2026-09-08, 19:33:26 a 19:35:38, build
  `v379-madd-normal-non-juge`. Riwaya native : HAFS. Mode : PRIERE.
- La relance a 19:37:38 ne contient pas de nouvelle session de priere.
- WAV brut recupere : `scratch_screens/stream_1788888808026.wav`,
  16 kHz, mono, PCM 16 bits, 122,32 secondes. En-tete verifie.
- Analyse des transitions et du choix de l'extrait audio. Aucune modification
  de l'application, aucun build ni deploiement durant cette analyse.
- Le WAV n'a pas ete ecoute ni redecode hors application. Cette analyse ne
  tranche donc pas entre oubli reel, hesitation, capture degradee et erreur
  ASR sur ce que l'utilisateur a effectivement prononce. Le journal suffit
  en revanche a etablir quel passage a ete demande au lecteur audio.

## Constat principal

Le moteur a bien detecte un trou commencant au mot 72, debut de 4:4.
Le souffleur a pourtant joue les premiers mots de 4:5, autour du mot 87.
La position proposee au lecteur est deja incorrecte avant la lecture :
le journal n'indique pas un echec du lecteur audio pour cette demande.

Les indices sont locaux a la cible installee (15 versets / 411 mots),
numerotes depuis zero. Le debut de 4:4 correspond aux indices 72, 73, 74.
Le trou 72..85 couvre les 14 mots de 4:4. Le mot 86 ouvre 4:5.

## Preuves chronologiques

Les numeros de ligne renvoient a la copie locale du journal ci-dessus.

| Heure | Ligne | Observation |
|---|---:|---|
| 19:33:51.218 | 195176 | Fin de Fatiha, identification commencee. |
| 19:34:00.573 | 195185 | An-Nisa 4:1 confirmee, environ 9,35 s apres le debut de cette phase. |
| 19:34:04.761 | 195850 | Ancre localisee sur la nouvelle cible, au mot 14. |
| 19:34:54.214 | 196702 | Mot 70 definitif vert ; mot 71 encore provisoire vert. |
| 19:34:56.031 | 196715 | Fenetre 34 : trou de 14 mots apres 71 MIS EN ATTENTE. |
| 19:34:56.044 | 196772 | Bande 68..86 ; le decodage libre finit par un "wala". |
| 19:34:56.354 | 196778 | Mot 72 provisoire rouge, puis mot 73 provisoire rouge. |
| 19:34:58.568 | 196794 | DECROCHAGE : dernier definitif=70, dernier atteste vu=86, reprise apres 86. |
| 19:34:58.740 | 196796 | Souffleur : passage 87..87, verset 4:5, mot local 1. |
| 19:35:01.333 | 196802 | Lecture demandee : 4:5, mots locaux 0..4, 137173..141819 ms dans le MP3. |
| 19:35:06.209 | 196804 | Lecteur : 4870 ms jouees, resultat ok. |
| 19:35:06.218 | 196805 | Reprise native au mot 87 ; preuves et verdicts posterieurs effaces. |
| 19:35:10.430 | 196810 | Nouvelle aide sur 87 refusee : deja souffle sur cette cible. |
| 19:35:12.455 | 196826 | Second DECROCHAGE, cette fois dernier definitif=86. |
| 19:35:12.980 | 196832 | Aide sur 87 refusee de nouveau : deja souffle. |

Le passage 72..85 n'est jamais confirme comme saut dans cette sequence.
Les mots 72 et 73 restent provisoires rouges ; aucun verdict V2 sur
74..85 n'apparait dans cette session. Il ne faut pas les compter comme
valides, ni transformer cette absence en preuve d'une faute du recitant.

## Mecanisme causal dans le code actuel

1. `ChaineRecitation.kt:1407` conserve les bornes du trou :
   `trouEnAttenteDe=71`, `trouEnAttenteA=86`. Les mots manquants se trouvent
   strictement entre ces bornes. Leur premier indice est donc 72.
2. `ChaineRecitation.kt:1556` avance `dernierAttesteVu` jusqu'a 86 a partir
   de la bande, meme si le trou 72..85 reste en attente. Une attestation
   au-dela du trou n'est pas une preuve que tous les mots precedents ont
   ete reconnus.
3. Les fenetres suivantes ont une bande inconnue. Elles passent dans
   `if (bande == null)` (`ChaineRecitation.kt:1127`) et quittent la fonction
   avant le traitement du trou en attente (`ChaineRecitation.kt:1423`).
   L'attente de confirmation reste donc sans resolution jusqu'au decrochage.
4. Au decrochage, `pointDeReprise()` (`ChaineRecitation.kt:658`) choisit
   `maxOf(dernierDefinitif, dernierAttesteVu)`, soit `max(70,86)=86`.
   Il ignore le debut du trou pourtant deja memorise.
5. `_onDecrochageV2` (`recitation_provider.dart:289`) ajoute 1 et transmet
   87 au souffleur. Son parametre s'appelle `dernierDefinitif`, mais dans
   ce cas le pont lui transmet le point de reprise calcule, donc 86.
   Ce nom peut induire en erreur lors du diagnostic.
6. `_soufflerPassage` (`prayer_follow_screen.dart:174`) retrouve alors
   logiquement 4:5. Les deux mots de contexte avant sont bornes au debut
   de CE verset ; ils ne remontent pas au debut de 4:4.
7. `repartirApresSouffle` (`ChaineRecitation.kt:986`) reutilise ce meme
   indice 87 et affecte `dernierDefinitif = cible - 1`, soit 86. Le log
   suivant affiche donc 86 comme dernier definitif sans nouveau verdict
   acoustique correspondant. Le message "ancre reculee" est trompeur
   dans ce cas : la reference passe en fait de 70 a 86.
8. Le garde contre les repetitions (`prayer_follow_screen.dart:166`)
   bloque ensuite le meme indice 87. Il explique l'absence de nouvelle
   lecture, mais ne cause pas le premier choix errone de verset.

## Ce qui fonctionne et doit etre preserve

- La sourate 4 est identifiee puis suivie durant plusieurs versets.
- Deux trous anterieurs sont mis en attente puis combles (lignes 196397,
  196434, 196560, 196587). Supprimer l'attente de confirmation provoquerait
  des aides inutiles sur ces deux exemples.
- Le premier decrochage atteint bien Dart, le souffleur et le lecteur audio.
  Pour les deux decrochages de cette sequence : deux demandes d'aide,
  une lecture terminee, une demande bloquee comme deja jouee.
- La lecture utilise un MP3 local et se termine avec le resultat `ok`.
  Cela atteste la lecture cote logiciel, pas son audibilite physique.

## Correctif a preparer

En mode PRIERE, au moment d'un decrochage confirme, conserver comme point
d'aide le debut d'un trou encore non resolu. Ici, transmettre 71 au pont
historique "reprise apres", ou transmettre explicitement 72 dans un champ
"premier mot a souffler". Ne pas confondre le point atteint apres le trou
avec l'endroit ou proposer l'aide.

Le traitement doit aussi couvrir les fenetres non localisees : elles ne
doivent pas faire oublier un trou en attente. Garder l'attente qui permet
aux fenetres suivantes de combler un trou, sans la convertir en obligation
pour le recitant de repeter. Apres l'aide, le suivi doit pouvoir se replacer
sur ce qui est effectivement recite.

Ne pas remplacer globalement `maxOf` par `dernierDefinitif` : cela pourrait
reintroduire les anciens retards d'aide lorsque le jugement arrive apres la
localisation. Le choix du debut de trou doit etre conditionne au mode PRIERE
et a l'existence du trou non resolu. Le mode normal garde son comportement.
Verifier ce parcours pour HAFS et WARSH sans changer leurs normalisations,
vocabulaires, tokenisations ni seuils GOP.

Tests utiles avant de livrer : trou 72..85 suivi de fenetres inconnues =>
aide 4:4 ; trou comble a la fenetre suivante => aucune aide ; reprise apres
l'aide => relecture possible et realignement libre ; comportement hors
PRIERE preserve. La presente analyse ne valide aucun correctif nouveau.

## Limites complementaires

A 19:35:12, le journal annonce un essai du candidat de reserve 7:189.
Aucune nouvelle cible 7 n'est installee dans la suite observee : ne pas
presenter cette annonce comme un changement de sourate effectivement realise.
Le retour en attente intervient a 19:35:22, puis le micro est relache et le
WAV finalise a 19:35:38. Pas de ligne `session fermee` dans cette session ;
la finalisation de tous les verdicts V2 ne peut pas etre affirmee.

Le diagnostic precedent portait sur v372 et le 7 septembre. Il ne doit pas
etre reutilise pour attribuer automatiquement ce nouvel incident a la V1
ou au minuteur de silence : ici, le trou, son point de reprise incorrect
et la demande de lecture du verset 4:5 sont directement traces.
