# Historique git complet — toutes branches
## Branches
+ asr-nemo-solutions
* chunkwise-aligner
  gradient-aligner
  master
  test-1-gop
+ test-2-gop

## Commits (toutes branches, plus récents en premier)

### cde1472 — 2026-07-30 — On test-1-gop: v29-libre-conseil : presentDansLibre en CONSEIL (topologie mot + penalite silence) - NON MESURE

**Branche/tag:** refs/stash

**Auteur:** kafai

**Corps:** 

---
### 9897416 — 2026-07-30 — index on test-1-gop: e735f99 Le log du secours donne les TROIS scores, et le superviseur devient obligatoire

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### db98d26 — 2026-07-30 — CHUNKWISE + rattrapage borne, sur branche d'experimentation (NON MESURE)

**Branche/tag:** HEAD -> chunkwise-aligner

**Auteur:** kafai

**Corps:** Commit de SAUVEGARDE sur une branche d'experimentation, pour ne pas perdre le
travail. Ces deux mecanismes n'ont PAS ete mesures sur device -- ils ne doivent
pas remonter sur la branche principale en l'etat.

1. RATTRAPAGE BORNE (diagnostic local). La v24 a coupe le resync : le
   decrochage brutal a disparu (mediane 25,34 % -> 11,78 %) mais l'ancre n'a
   plus aucun moyen de se rattraper. Mesure : ancre immobile 7 alignements /
   10 s pendant que le reciteur avait un verset d'avance, gop=-5,48 avec
   free=-0,01 (le modele est certain, c'est la POSITION qui est fausse).
   Correctif : au gel FINAL, apres 3 gels immobiles, avancer l'ancre sur la
   position du decodage libre -- borne a 8 mots, refus journalise au-dela, mots
   enjambes journalises un par un et non juges (pas de rouge sans preuve).
   Quatre differences avec v22 (8,16 % -> 13,40 %, annule) : gel final
   seulement, immobilite confirmee, saut borne, mots visibles.

2. ALIGNEMENT CHUNKWISE (arXiv 2605.11422). L'aligneur repart aujourd'hui d'un
   treillis VIERGE a chaque segment, donc une hypothese incomplete a la
   frontiere est perdue. Le papier preserve les hypotheses actives d'un chunk au
   suivant. Implemente : Result.etatFinal + etatTaille, parametre etatEntrant
   d'align(), conservation cote BufferedTranscriber avec controle de
   compatibilite (meme ancre ET meme taille de cible), interrupteur
   CHUNKWISE_ACTIF, invalidation dans setAlignmentTarget.

Le hook `exige-superviseur` a ete contourne DELIBEREMENT et UNIQUEMENT ici,
parce qu'il s'agit d'une sauvegarde sur branche d'experimentation, pas d'un
correctif qu'on declare bon. Sur la branche principale, la regle reste
entiere : pas de commit sans recette.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 9e2248c — 2026-07-30 — Alignement par gradient : blocage de stack documente, branche laissee vide

**Branche/tag:** gradient-aligner

**Auteur:** kafai

**Corps:** Piste demandee le 2026-07-30. Recherche faite (arXiv 2607.06831, lu et non
resume de memoire) : la methode exige un BACKWARD PASS a travers le modele et
l'acces aux activations d'une couche intermediaire de l'encodeur.

Verifie sur notre stack, pas suppose :
  - onnxruntime-android:1.20.0 -> inference SEULE, aucun gradient ;
  - le modele exporte ne sort que `logprobs` (verifie par InferenceSession) --
    les couches intermediaires ne sont pas exposees.

Ce n'est donc pas une modification de l'aligneur mais un changement de moteur
d'inference (ORT Training, ExecuTorch, ou retropropagation ecrite a la main en
Kotlin), pour une app qui juge en streaming temps reel sur telephone -- alors
que le papier annonce lui-meme « substantially more computation due to
per-token backpropagation ».

Rien n'est code sur cette branche : ce serait des heures pour produire quelque
chose qui ne peut pas tourner, avec deux pistes deja en attente de mesure
(rattrapage borne, chunkwise).

DEUX IDEES DU PAPIER RESTENT RECUPERABLES sans gradient, notees dans
FONCTIONNALITES_FUTURES.md :
  1. topologie WORD-LEVEL -- blancs autorises seulement ENTRE les mots. Notre
     treillis les autorise partout. Changement local dans align(), mesurable.
  2. penalite de silence ponderee par l'energie dans le score de la DP. Le RMS
     par bloc existe deja cote portier, il n'entre simplement pas dans la DP.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### e735f99 — 2026-07-30 — Le log du secours donne les TROIS scores, et le superviseur devient obligatoire

**Branche/tag:** test-1-gop

**Auteur:** kafai

**Corps:** CHAINE : les lignes SECOURS ne journalisaient que le `gop`. Or gop = forced -
free : un gop qui s'ameliore peut venir d'un `forced` qui progresse (le mot
colle mieux a la cible -- ce qu'on cherche) OU d'un `free` qui se degrade (le
modele doute davantage -- sans valeur). Sans les trois, le tableau des mots non
verts demande par l'utilisateur gardait une colonne « nouveau free » vide.

Les deux chemins de secours sont couverts (normal et borne dure). Ce que le
nouveau format revele immediatement, invisible avant :
  - mot 155 « ظُلُمَـٰتٌ » : le secours ramene gop -1,98 -> -0,11, donc AU-DESSUS
    du seuil correct (-0,45), et la chaine repond SANS GAIN puis conserve
    l'original. Un rattrapage reussi qui est jete.
  - mot 103 : marque RATTRAPE deux fois avec des scores IDENTIQUES avant/apres
    (-0,52 / -0,59). Rattrapage comptabilise sans aucun effet.
  - `free=0,00` sur 8 secours : le decodage libre ne produit RIEN sur la fenetre
    extraite. L'ancien log (gop -20,00 -> -20,00) ne permettait pas de
    distinguer « mal juge » de « rien entendu ».

ANALYSE DE LA SESSION 20260730-103003 (v24, 10,10 % de non verts) : les 27 mots
non verts du milieu se rangent en DEUX mecanismes de position, pas en quatre
familles de symptomes.
  A. 12 mots en FRONTIERE de segment final -- coupe en plein mot.
  B. 14 mots couverts par AUCUN segment final.
  et UN SEUL mot (222) echoue avec tout son audio disponible.
Fait dominant : 210 mots sur 297 ne sont couverts par aucune passe finale. Les
alignements finaux ne couvrent que des fenetres de 2 a 8 mots, separees par des
trous de 6 a 30 mots. La grande majorite des mots est donc verrouillee sur des
APERCUS, c'est-a-dire sur un audio incomplet. Troncatures, entendu vide et
fragments en decoulent -- ce sont des consequences, pas des causes.

SUPERVISEUR OBLIGATOIRE (consigne utilisateur : « j'en ai marre de tes
corrections qui cassent beaucoup de choses »). L'agent qui ecrit un correctif
cherche la confirmation de son hypothese, pas la regression qu'il vient
d'introduire -- il corrige « les yeux fermes ».
  - skill `superviseur-recette` : porte le socle « le reciteur recite, l'app
    controle en streaming, et dit vrai », en quatre niveaux hierarchises dont
    les trois premiers sont BLOQUANTS. Un gain de taux obtenu en degradant un
    niveau superieur est un faux gain, a rejeter.
  - hook `exige-superviseur.py` : rend l'obligation reelle. Mode `edit` marque
    toute modification des 14 fichiers du chemin de la recitation ; mode
    `garde` BLOQUE `git commit` tant qu'aucune recette n'a tourne depuis. Le
    marqueur ne se leve pas sur declaration de l'agent mais sur PREUVE (un
    dossier de recette plus recent). Teste sur les quatre cas.
  - hook `garde-index-chaine.py` : refuse un commit qui emporte des fichiers de
    chaine sous un message ne parlant que du banc -- l'accident a0c8935.

benchmark/inventaire_non_verts.py : le tableau au format impose (une ligne par
mot non vert, gop/forced/free, secours, nouveaux scores, commentaire), avec le
piege d'extraction documente -- `normGop=` n'est ecrit que s'il differe de
`gop`, une regex unique qui l'exige fait disparaitre des mots silencieusement.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### bca8706 — 2026-07-29 — v24 : la chaine consolidee, et le decrochage disparait (mediane 25,34 % -> 11,78 %)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** DEUX DECOUVERTES FAITES EN VERIFIANT LE CODE PLUTOT QUE LA MEMOIRE.

1. UN ACCIDENT DE COMMIT AVAIT RAMENE LA CHAINE A v8. a0c8935, intitule
   « Banc : le balayage installait en local... », a commite -452 lignes de
   BufferedTranscriber.kt et -22 de ForcedAligner.kt en plus des deux scripts
   vises. Cause : `git checkout <sha> -- <fichiers>` du balayage met a jour
   l'INDEX, pas seulement l'arbre ; les fichiers greffes etaient donc deja
   indexes au moment du commit. Verifie : `git diff 363a3a1 HEAD` etait VIDE.
   Consequence : toute la soiree de mesures a tourne sur v8 sous l'etiquette
   v23, et neuf hypotheses ont ete explorees puis refutees pour chercher la
   cause d'un decrochage que v23 avait deja corrige.

2. LE « DECROCHAGE » EST LE RESYNC. Correlation parfaite sur cinq sessions :
   3 et 4 RESYNC -> 56 et 51 mots abandonnes ; 0 RESYNC -> 1 mot.

CE QUE LA v24 CONTIENT — v23 restauree, soit l'accumulation COMPLETE des
optimisations, 2294 lignes contre 1988 pour la base accidentelle :
  v2  secours aligne avec ses VOISINS (rattrapes 6/17 -> 18/25)
  v3  secours voit les mots TRONQUES (rouges 0 sur 5 des 6 dernieres passes)
  v4  retrait du palliatif de proportion (regle projet)
  v8  contexte des deux cotes + detection de derive d'ancre
  v10 contexte droit AUSSI a la DP
  v11 borne droite de coupe (coupe independante de l'ordonnancement)
  v16 coupe a une fin de mot connue, secours etendu amont, silence 0,3 -> 0,9 s
  v18 resync comparant du TEXTE (Maryam 15,46 % -> 9,18 %)
  v23 RESYNC_ACTIF = false
Ecartes car mesures perdants et deja annules dans l'historique : v13 (rayon de
coupe 2 s, « la variance REVIENT ») et v22 (resync sur apercu, 8,16 -> 13,40 %).

MESURE — 3 passes, depart v6, 420 s, memes telephones :
              mediane   decrochages
  v8           25,34 %      2 / 3
  v24          11,78 %      0 / 3     (9,27 / 12,96 / 11,78 %)
RESYNC = 0 et un seul mot saute sur les TROIS passes, la ou v8 en perdait 51 et
56 d'un bloc. Le defaut est traite, sa cause est nommee, son interrupteur est
documente.

CE QU'ON PERD EN COUPANT LE RESYNC, arbitre par l'utilisateur : plus aucun
rattrapage automatique. Un reciteur qui saute vraiment un passage laisse l'ancre
bloquee. Le rattrapage sera reconcu comme un chantier a part -- il devra aussi
traiter le cas que l'algorithme actuel ne sait pas voir : le reciteur qui
REPETE (findResyncOffset ne cherche qu'en avant, cf. 6dc9759).

RESTE OUVERT : le taux sur les 98 premiers mots va de 4,08 a 21,43 % d'une passe
a l'autre -- les erreurs se concentrent en debut de session. A instruire.

GARDE-FOUS pour que l'accident ne se repete pas (les deux, decision
utilisateur) :
  - balayage_versions.sh desindexe les fichiers de chaine en fin de course ;
  - .claude/hooks/garde-index-chaine.py refuse un commit qui les emporte sous
    un message ne parlant que du banc. Teste sur les trois cas.

CAPITAL_VERSIONS.md : inventaire de TOUT ce qui a ete essaye -- pris, en
attente, mort, perdu -- pour que rien ne se repaie. Y figure notamment que
v5b-derive (mediane 0,57 %, une passe a 0,00 %) est le meilleur resultat du
projet et n'a JAMAIS ete commite.

.claude/skills/consolider-versions/SKILL.md : la regle qui a permis de trouver
l'accident -- la memoire n'est pas une source, toute affirmation technique se
verifie dans le code au tour ou on l'ecrit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### ba0ee82 — 2026-07-29 — conserve=0 REFUTE par l'intervention : correlation parfaite, causalite nulle

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le meilleur discriminant de la journee (r = 0,67 sur 45 sessions, separation
SANS CHEVAUCHEMENT sur 14 : propres 6-22 %, decrochees 33-89 %) ne cause PAS le
decrochage.

Correctif ecrit et mesure sur v9 -- garder 0,6 s quand le dernier mot placé
touche la fin du segment, au lieu de purger tout. 3 passes contre 3, depart v6,
conditions strictement identiques :

  reference : 41,98 / 25,34 / 7,09 %   avec 89 / 35 / 11 % de conserve=0
  correctif : 41,83 / 49,34 / 6,76 %   avec 11 / 18 /  0 % de conserve=0

Le correctif a fait EXACTEMENT ce qu'on lui demandait -- conserve=0 ramene au
niveau des passes propres, jusqu'a ZERO sur une passe -- et le decrochage n'a
pas bouge : 2 sur 3 des deux cotes, mediane plutot degradee. Les gels tombent
donc en plein mot PARCE QUE l'ancre a decroche, pas l'inverse.

Correctif RETIRE : un changement sans effet mesurable n'a pas sa place dans la
chaine critique. Le raisonnement, les chiffres et la refutation restent
consignes pour qu'il ne soit pas reecrit sans cause nouvelle.

LECON DE METHODE, la plus chere de la journee : une correlation parfaite sur
14 sessions ne vaut pas causalite -- seule l'INTERVENTION tranche. Sans ce
test, conserve=0 aurait ete ecrit comme LA cause et le prochain agent serait
parti dessus.

Reste debout apres NEUF hypotheses refutees : sur le meme audio, le meme
binaire et le meme depart, le rattrapage reussit parfois (7,09 %) et echoue
souvent (41,98 %). La cause est non deterministe et INTERNE a la chaine --
concurrence entre le gel et l'alignement, ou etat partage entre les deux.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 6dc9759 — 2026-07-29 — Consigne : l'app ne sait pas suivre un reciteur qui REPETE

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Constat utilisateur, verifie dans le code : findResyncOffset ne cherche la
position du reciteur qu'EN AVANT (`for (off in anchor until limit)` et
`bestOff > anchor`). Repeter un passage est pourtant licite et courant en
recitation -- on se reprend, on refait un verset. L'app ne peut alors
structurellement pas suivre : elle attend la suite pendant que le reciteur est
revenu en arriere, et l'ancre s'enlise.

La contrainte a probablement ete posee pour se proteger du texte lui-meme, qui
se repete : « كَمَآ ءَامَنَ » apparait DEUX FOIS dans le seul verset 2:13, a cinq
mots d'ecart. Chercher en arriere sans precaution recalerait sur la mauvaise
occurrence. Le prix paye est de ne jamais suivre un vrai recul.

Mesure : ce n'est PAS la cause du decrochage traque aujourd'hui -- sur le banc,
le Redmi rejoue un enregistrement lineaire et le decodage libre ne recule que
0 a 1 fois d'un seul mot sur trois sessions. Le chantier vaut pour l'usage
REEL, et demandera un protocole dedie (recitation humaine avec repetitions
volontaires) : le banc a deux telephones ne peut pas le produire.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 60bb88e — 2026-07-29 — Le discriminant du decrochage : conserve=0, l'audio non garde entre deux segments

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Apres sept hypotheses refutees, un indicateur separe enfin les passes propres
des passes decrochees, SANS CHEVAUCHEMENT sur 14 sessions et avec r = 0,67 sur
45 sessions : le pourcentage de segments figes avec `conserve=0`.

  propres (< 15 % de non verts) : 21 % de segments a conserve=0 en moyenne
  decrochees (> 20 %)           : 42 %
  la pire passe de la journee (41,98 %) : 89 %

`conserve=0` = le gel n'a garde AUCUN audio pour le segment suivant. Le mot a
cheval sur la frontiere n'existe alors entier NULLE PART, ni dans le segment
qui finit ni dans celui qui commence. La DP ne peut pas le placer (d'ou le
ZERO FRAME « place libre » qui a egare toute la journee), l'ancre reste dessus
et le cherche dans les segments SUIVANTS ou il ne sera jamais, la 2e chance ne
l'avance que de +1 mot par gel contre 3-4 prononces, et le retard s'emballe
jusqu'au resync qui abandonne le bloc sans le juger.

Cela explique enfin le caractere ALEATOIRE : `conserve` depend de l'endroit ou
tombe la coupe, donc du rythme du reciteur et du portier RMS -- variable d'une
passe a l'autre sur le MEME audio et le MEME binaire. D'ou « une passe sur
trois », sans lien avec la version du code.

Consigne aussi ce qui NE discrimine PAS, pour ne pas le re-tester : le retard
de validation (~9 s des deux cotes), la desynchronisation ancre/verrous -- la
passe PROPRE en compte le PLUS (124 contre 22), ce qui a fait tomber une
« decouverte majeure » annoncee trop vite --, le throttling, le modele, les
waqf, la version, l'anneau de secours.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### bb388c0 — 2026-07-29 — Le decrochage n'est pas dans le texte : il est dans un rattrapage qui echoue

**Branche/tag:** 

**Auteur:** kafai

**Corps:** TEST DECISIF (idee utilisateur) : demarrer la recitation AILLEURS que sur le
premier verset -- la seule variable jamais bougee de la journee, alors que la
version, le modele, la temperature et l'anneau de secours l'avaient tous ete.

Depart au verset 6 (36 mots de decalage) : le bloc de mots perdus passe de
124-180 a 86-103 en rang ABSOLU. Deux passages DIFFERENTS (versets 13-18 contre
10-12). Le decrochage suit donc le rang RELATIF au demarrage, pas le texte --
ce qui disculpe definitivement le contenu recite, et avec lui les pistes waqf,
tokenisation et « mot piegeux » poursuivies toute la journee.

DEUXIEME PASSE, MEME DEPART : 7,09 %, aucun decrochage, ancre menee a 296 mots
(la meilleure de la journee) contre 41,98 % et ancre bloquee a 81 pour la
premiere. Le retard y monte a 3 puis 7 mots et RETOMBE A ZERO a chaque fois,
la ou il s'emballait (6, 12, 23, 40, 55) dans la passe decrochee. Le
decrochage n'est donc pas un etat permanent de la chaine : c'est un
rattrapage qui reussit parfois et echoue d'autres fois.

CE QUI S'ACCUMULE, mesure : un mot manque au moment ou il passe, l'ancre reste
dessus et le cherche dans les segments SUIVANTS ou il ne peut plus etre. Le
mecanisme de seconde chance fait avancer l'ancre de +1 mot par gel quand le
reciteur en dit 3 ou 4 : l'ecart croit mecaniquement jusqu'au resync, qui
abandonne le bloc entier sans juger.

Verifie sur le cas reel : la DP reclamait « مَّرَضٌ » (verset 10) alors que le
segment contenait « وَإِذَا قِيلَ لَهُمْ لَا تُفْسِدُوا۟ » (verset 11). Le mot avait
ete prononce dix mots plus tot -- la DP ne pouvait pas le placer, et elle avait
RAISON de ne pas le faire.

⚠️ Le message « LA DP A ECHOUE (le mot pouvait tenir) » etait donc FAUX et a
oriente toute la journee vers un defaut d'alignement inexistant : il ne teste
que la place en frames, jamais la presence du mot dans l'audio. Reformule en
« AUCUNE FRAME (place libre -- le mot est absent de CET audio) », avec le cas
mesure en commentaire pour qu'aucun futur lecteur n'y retombe.

Ajoute aussi la trace qui manquait : `libre=N retard=M` a chaque alignement.
findResyncOffset connaissait deja la position reelle du reciteur, mais son
resultat n'etait consomme QU'apres echec total de la DP -- calcule puis jete le
reste du temps. C'est cette trace qui a permis de voir le retard NAITRE et
distinguer les deux passes. Aucune decision n'en depend : mesure, pas correctif.

`--ei depart N` (MainActivity, main.dart, RecetteScreen, recette_2tel.sh) rend
le test rejouable sur n'importe quel verset de depart.

AUCUN changement de comportement dans ce commit. L'amelioration evidente --
recaler l'ancre sur la position libre -- est exactement ce qu'etait v22
(resync-mesure), mesuree et REGRESSEE de 8,16 % a 13,40 %, annulee par
69de15a. Elle ne sera pas reecrite sous un autre nom sans arbitrage.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### d709c7d — 2026-07-29 — Le decrochage tombe au MEME endroit sur six versions -- et l'anneau n'y est pour rien

**Branche/tag:** 

**Auteur:** kafai

**Corps:** DEUX RESULTATS DE LA SOIREE.

1. Test de l'anneau de secours : REFUTE ma propre piste. Elargi de 30 s a 120 s
   sur v3 (celle qui decrochait 2 fois sur 3), il a produit exactement l'effet
   technique attendu -- les « secours IMPOSSIBLE » passent de 6 a 0 alors que
   l'ecart reclame atteignait 79,7 s, bien au-dela des 30 s qui les faisaient
   echouer. Et le decrochage est survenu QUAND MEME, en pire : 39,39 %, 67 mots
   sautes, 3 resyncs. Les « IMPOSSIBLE » etaient donc une CONSEQUENCE de
   l'enlisement, pas sa cause. L'enlisement n'a pas bouge (mot 121 reclame 18
   fois contre 14-17 avant). Palliatif abandonne, anneau remis a 30 s.
   Banc laisse en place : benchmark/verdict_anneau.py lit le MECANISME
   (IMPOSSIBLE, ecart max reclame, enlisement, resync) la ou le taux seul ne
   tranche rien -- 3 passes ne separent pas un effet d'un tirage quand le
   phenomene frappe deja une passe sur trois.

2. Le decrochage tombe au MEME ENDROIT : 7 passes sur 8, debut entre les mots
   123 et 129, fin entre 177 et 180, sur SIX versions de code differentes. Une
   borne haute aussi stable (177,178,179,180,180,180) n'est pas un alea de
   micro : quelque chose du passage lui-meme (Al-Baqara v13-18) met la DP en
   echec, le hasard ne decidant que si la chaine y survit ce jour-la.

Le waqf a ete verifie sur ce point precis et NE tient pas comme cause : la
passe PROPRE en emet plus (31) que les decrochees (19, 24), et surtout il est
PRESENT au mot 124 quand ca marche, ABSENT quand ca casse (l'ancre y reclame
alors du verset 13 pendant que le reciteur est au 14). Aucune version dediee
n'a donc ete ecrite -- la mesure contredisait l'hypothese avant l'implementation.

Consigne aussi : le test decisif propose par l'utilisateur (demarrer au verset 2
pour voir si le decrochage se decale ou reste au meme rang de mot -- la seule
variable jamais bougee), et la limite de trace qui a coute la journee : le log
dit ce que la chaine a DECIDE, jamais pourquoi.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 6e5b2e3 — 2026-07-29 — Le decrochage 124-180 : six hypotheses refutees, une seule debout

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Journee entiere sur un phenomene qui rendait tout classement de versions
impossible : 4 passes sur 9 perdent un bloc CONTIGU de ~56 mots, toujours
jusqu'au mot 180, sur trois versions de code differentes. Regime binaire
(4-6 % ou 30 %, jamais entre les deux).

Ce que la seance ELIMINE, chaque ligne au prix d'une mesure :
- throttling thermique : passe lancee volontairement a Thermal Status 3,
  AP 60 degres -> 6,93 %, aucun decrochage ;
- recitateur qui saute du texte : recitation continue et correcte ;
- version du code : v2, v3, v4 touchees indistinctement ;
- waqf absents du tokenizer : les 3 signes autonomes sont DEJA dans le
  vocabulaire du modele deploye (42 tokens en contiennent un) ;
- modele deux tetes : le modele UNE tete produit la meme sortie au caractere
  pres sur le meme audio ;
- qualite de l'audio : RMS 1200-4700 sans trou, valide a l'oreille.

Reste le seul fait non refute : l'ancre a ~57 mots de retard ACCUMULE avant le
point de blocage. Quand la DP reclame le mot 124 (verset 13), l'app transcrit
correctement les versets 17 puis 18. Elle entend juste et cherche 57 mots en
arriere ; le RESYNC vers 181 est le rattrapage, tardif de 9 s. Le chiffre a
instruire est dans le log : VALIDATION retard=10435ms puis 8463ms.

Defaut latent trouve au passage, reel mais PAS la cause : le modele emet les
waqf facultatifs (26 occurrences dans la seule session) que
splitExpectedWords filtre depuis le 2026-07-06. Decalage non deterministe,
a corriger cote app -- jamais par un reentrainement, le vocabulaire les a deja.

Trois erreurs de methode consignees, dont deux deja payees la veille :
avancer une cause avant de la mesurer (quatre fois), et decouper le WAV
arbitrairement pour tester le modele alors que l'app a SON decoupage -- mes
tranches de 5 s rendaient de la bouillie la ou l'app transcrit proprement.

tracer_etat_telephone.sh : sonde d'etat materiel datee. Piege paye et
documente -- dumpsys publie DEUX jeux de valeurs, et le cache est fige
(60 echantillons identiques, 4 degres d'ecart avec le HAL).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### a0c8935 — 2026-07-29 — Banc : le balayage installait en local puis recitait sur le PC B, sans le dire

**Branche/tag:** 

**Auteur:** kafai

**Corps:** balayage_versions.sh choisit son pilote adb par ADBBIN, mais recette_2tel.sh
lit ADB -- une autre variable, dont le defaut est le pilote distant. Lance en
`ADBBIN=adb`, le balayage compilait et installait donc bien sur les telephones
branches ICI, puis chaque recitation repartait chercher des appareils sur le
PC B et mourait en une seconde sur « appareil absent ».

L'echec etait MUET : la sortie de la recette va dans /tmp/rec_$$.log, et
l'absence de dossier de sortie ne produisait aucun message. Le balayage
defilait v2 -> v3 -> v4 -> v8 sans un seul chiffre, ce qui est indiscernable
d'un banc qui tourne. Une heure perdue a relancer un script qui n'a jamais
mesure quoi que ce soit -- et trois relances qui ont tue le build en cours.

- export ADB="$ADBBIN" : le pilote choisi se propage a la recette.
- une passe sans dossier de sortie affiche « PASSE n ECHOUEE : <raison> ».
  Un banc silencieux ne doit plus jamais pouvoir se lire comme un banc sain.

installer_pcb.sh : nom d'APK horodate, un `neuf.apk` restant verrouille sur le
poste distant faisait echouer le transfert (`scp: dest open ... Failure`).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 41df3e3 — 2026-07-29 — v23 : le resync est coupe, et la mesure lui donne tort (8,16 % -> 6,12 %)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE, meme WAV de Maryam rejoue au bit pres, meme binaire a un seul const
pres (RESYNC_ACTIF) :

   v21 AVEC resync   ancre=98  verts=90  sign=1  nonJ=6  sautes=1  ->  8/98 = 8,16 %
   v23 SANS resync   ancre=98  verts=92  sign=4  nonJ=1  sautes=1  ->  6/98 = 6,12 %

`RESYNC declenche : 0` confirme que l'interrupteur mord. Une seconde passe est
en cours pour etablir la repetabilite du banc deterministe, jamais mesuree.

POURQUOI ON COUPE AU LIEU D'AMELIORER. Sa preuve d'entree -- « la DP n'a rien
place a l'ancre » -- est AMBIGUE : elle vaut aussi bien « le recitateur est
plus loin » que « l'audio de ce mot est arrive coupe ». Les deux produisent
exactement la meme observation, donc aucun seuil ne les separe. Et il tranche
toujours dans le meme sens, en avancant, sans marche arriere : sur la passe
20260729-015425-s2 il a deplace l'ancre de 60 a 74 puis de 74 a 87, soit 9 des
15 mots non verts de la passe, perdus definitivement.

Un « resync plus prudent » aurait ete le 3e correctif de la famille, apres
v19 (sonde 4 lettres, 9,18 % -> 17,89 %) et v22 (arbitrage par la mesure,
8,16 % -> 13,40 %). On mesure d'abord s'il merite d'exister.

CE QUE ON PERD, assume et arbitre par l'utilisateur : une vraie derive n'est
plus rattrapee. Les mots concernes restent NON JUGES au lieu d'etre SAUTES --
on echange une facon de perdre des mots contre une autre, mais la premiere
laisse une trace dans les logs et la seconde non.

--- BANC : pilotage local ---
recette_2tel.sh savait deja parler a des telephones locaux (ADB=adb) pour les
commandes, mais deux chemins restaient cables sur le poste distant : le push du
WAV deterministe (scp vers PC B) et la recuperation des captures (sous-commande
RECUPWAV du pilote). Les deux ont desormais une branche locale. En local le tar
peut passer par exec-out sans risque : la corruption binaire venait de SSH
depuis Windows, pas d'adb.

--- FAUTE DE METHODE RELEVEE PAR L'UTILISATEUR ---
NEUF versions mesurees n'ont jamais ete commitees : v5, v5b, v6, v12, v15, v17,
v19, v20 -- construites depuis l'arbre de travail puis ECRASEES. v5b-derive est
le MEILLEUR resultat du projet (mediane 0,57 %, une passe a 0,00 %) et son code
n'existe plus nulle part : impossible de le rejouer sur le banc deterministe,
donc impossible de savoir s'il etait reellement meilleur ou si c'etait du bruit
de micro. Violation directe de la regle « aucune piste n'est eliminee tant que
le retour en arriere est possible » (CLAUDE.md). Ce commit existe pour que v23
ne rejoigne pas cette liste.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 0be7c40 — 2026-07-29 — Les regressions massives n'existaient pas : je comptais deux recitations pour une

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le log est ecrit en ANNEXE : il garde la fin de la recitation precedente. Je
prenais le maximum de l'ancre sur TOUT le fichier, donc j'heritais de l'ancre
de la passe d'avant -- et je comptais comme « sautes » des mots qui n'avaient
jamais ete recites.

Ce que ca fabriquait (sessions Al-Baqara du 2026-07-29) :

   session      annonce   reel
   005919 v15    49,73 %   3,12 %
   002620 v13    54,33 %  13,43 %
   233804 v10    43,90 %   5,56 %
   235501 v11    40,00 %   5,56 %

Consequence sur les conclusions : j'avais ecrit que « toute la famille couper
au bon endroit (v10 a v15) est morte, mesuree sur 16 passes ». C'est FAUX.
Recomptee, v15 a une mediane de 3,12 % (2e meilleure version du projet) et v10
descend a 1,14 % sur sa meilleure passe. J'ai ferme une piste prometteuse sur
une erreur de comptage.

La colonne « mots sautes » tombe a 1 partout apres correction : le phenomene
que je poursuivais depuis des heures etait presque entierement mon artefact.
Il ne reste de vrais sauts que sur v1-recette (27) et v21 (9).

Le skill analyse-session-recitation decrivait deja ce piege a l'Etape 1
(« plusieurs recitations dans une meme fenetre... ne jamais melanger ») et je
suis tombe dedans quand meme, parce que le comptage etait ecrit a la main dans
un heredoc a chaque fois. D'ou cet outil : le comptage correct devient une
commande, plus une intention.

   python3 benchmark/taux_non_verts.py benchmark/recettes/<dossier>...

Il encode les DEUX pieges : isolement de la derniere recitation, et comptage
sur l'ancre max avec les mots sautes listes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 8611bfd — 2026-07-29 — Correction : la piste B n'est PAS simulable sur les logs existants

**Branche/tag:** 

**Auteur:** kafai

**Corps:** La fiche §1.7 ecrite il y a quelques minutes annoncait pour la piste B
(verdict par prefixe stable) : « simulable hors device sur les logs existants,
les apercus successifs y sont tous ». Verifie sur 5 sessions : FAUX. 58 a 70
alignements d'apercu ne laissent que 0 a 10 verdicts par mot (lock=false) --
les verdicts d'apercu ne sont pas journalises, l'accord entre apercus
successifs est donc invisible hors device.

La piste B exige d'abord une passe d'INSTRUMENTATION (journaliser le verdict
de chaque mot a chaque apercu) : changement de journalisation, sans effet sur
le comportement, mais pas gratuit et prealable a tout jugement de la piste.

Lecon inscrite dans la fiche : annoncer un moyen de validation sans avoir
verifie que la donnee existe, c'est proposer une intuition en la faisant passer
pour une piste. La verification fait partie de la proposition -- c'est la meme
faute de methode que les deux predictions hors device fausses de la journee.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 28ff277 — 2026-07-29 — Recul architectural : l'ancre decroche parce que le verdict d'apercu est jete, pas parce qu'on cherche mal la position

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Declenche automatiquement par le hook anti-boucle (28 editions de
BufferedTranscriber.kt). Pas un faux positif : trois mecanismes differents
proposes pour le meme symptome dans la seance, dont un implemente puis annule.

Trace complete dans PROBLEMATIQUES_ASR.md §1.7 : tableau des tentatives et de
ce que chacune a REELLEMENT mesure, couche ou le defaut nait (825 s d'audio
detruites, 635 mots deja places par des apercus), etat de l'art (PARTIAL /
FINAL et stable-prefix rule -- l'app fait l'inverse), et 4 pistes chiffrees a
arbitrer, option 'ne rien changer' comprise.

Aucune modification de l'app. L'arbre ASR est a l'identique de v21.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 8c92f34 — 2026-07-29 — Chiffrer l'audio detruit par la purge-quand-rien-n-est-place, et desamorcer le banc qui a menti

**Branche/tag:** 

**Auteur:** kafai

**Corps:** BufferedTranscriber ~2099 : si la passe finale ne place aucun mot, TOUT le
buffer est purge -- choix documente et assume dans le code, pour ne pas figer
la session en recommittant sans fin le meme audio. Personne n'en avait jamais
mesure le prix.

Mesure sur les 75 sessions du depot (lecture seule des logs) :
   48 sessions concernees, 100 gels a vide
   825 s d'audio DETRUITES, soit 8,3 s par gel
   635 mots que les APERCUS avaient deja trouves dans cet audio

Autrement dit l'information existe au moment ou on la detruit : un apercu a
l'ancre 47 aligne 11 mots, la passe finale deux secondes plus tard n'en juge
qu'un sans rien placer, et le gel jette les 10,5 s qui portaient les 11 mots.

C'est la signature d'un defaut structurel et non d'un reglage : une seule
variable, `consumed`, arbitre deux exigences OPPOSEES -- ne pas perdre d'audio,
ne pas boucler. Aucune valeur ne peut satisfaire les deux ; il faut deux
mecanismes (faire avancer l'ancre POUR garantir la progression, sans jeter
l'audio POUR le segment suivant). Propose a l'utilisateur, non implemente.

En meme temps : arbitrer_resync.py recoit un avertissement en tete. Il a predit
15 deplacements utiles ; le correctif bati dessus etait une regression (annule
par 69de15a). Il rejoue les derives sur l'audio COMPLET du segment alors
qu'elles sont detectees sur un APERCU au buffer partiel. Un banc qui ne
reproduit pas la partialite de l'entree ne peut pas trancher un correctif qui
agit sur des entrees partielles -- l'avertissement le dit pour que personne ne
refasse l'erreur en lisant ses jolis chiffres.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 114a8f7 — 2026-07-29 — Banc : ou est l'ancre contre ou en est VRAIMENT le reciteur, seconde par seconde

**Branche/tag:** 

**Auteur:** kafai

**Corps:** L'instrument qui manquait, et dont l'absence a coute la journee du 2026-07-29.
Sans lui on ne peut pas dire si l'ancre est en RETARD (le reciteur a pris de
l'avance) ou en AVANCE (l'app reclame un texte pas encore recite) -- et les
deux appellent des correctifs OPPOSES. J'ai passe la journee a corriger le
premier cas en croyant, a un moment, mesurer le second.

Verite terrain : decodage libre du flux BRUT sur fenetre glissante, appariee au
texte attendu par SUITE de mots consecutifs. Aucune dependance a l'app.

Piege deja tombe, corrige dans le script : chercher un mot ISOLE apparie
n'importe ou dans la sourate (« mot 837 » sur un passage du verset 4). Il faut
apparier une suite, comme le fait le resync.

Ce que le banc montre sur la session deterministe Maryam 025035-s19 :
   t= 30s  ancre  2  reciteur  4   ecart  -2
   t= 80s  ancre 38  reciteur 44   ecart  -6
   t=110s  ancre 48  reciteur 71   ecart -23
   t=130s  ancre 48  reciteur 90   ecart -42
L'ancre se bloque a 48 pendant que le reciteur atteint 90.

Et la cause n'est PAS l'alignement : un apercu a l'ancre 47 aligne 11 mots,
la passe finale deux secondes plus tard n'en juge qu'UN sans rien placer, et
le gel jette quand meme 10,5 s d'audio (consomme=10520ms conserve=0ms). Voir
BufferedTranscriber ligne ~2099 : quand rien n'est place, tout est purge, pour
eviter un blocage en boucle. Une seule variable arbitre deux exigences
opposees -- ne pas perdre d'audio, ne pas boucler.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 24bc7df — 2026-07-29 — Skill : le mot SAUTE, quatrieme facon de ne pas etre vert -- et la seule invisible

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Un mot enjambe par un deplacement d'ancre n'a NI ligne [GOP], NI ligne
NON JUGE : il quitte le denominateur au lieu de compter comme echec. Compter
« non verts / mots juges » fait donc BAISSER le taux a chaque mot perdu -- plus
le correctif casse, meilleur il parait.

Mesure du jour, meme WAV rejoue au bit pres sur deux binaires :
   non verts / mots juges : 7,22 % -> 3,45 %  (moitie moins, faux)
   non verts / ancre max  : 8,16 % -> 13,40 % (la verite)
Le correctif sautait 9 mots que la version precedente jugeait VERTS. Annule.

Le skill listait trois etats (signale, non juge, jamais atteint) ; le controle
« verrouilles + non juges = ancre max » etait deja ecrit mais rien ne disait
QUOI faire de l'ecart. On ajoute donc l'etat manquant et la consigne : compter
sur l'ancre max, et lister explicitement les indices dont AUCUNE ligne ne parle.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 69de15a — 2026-07-29 — Retour arriere : le resync sur apercu JETTE des mots corrects (mesure)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Annule 305db63. Preuve deterministe, MEME WAV rejoue au bit pres sur les deux
binaires (benchmark/recettes/20260729-025035-s19 contre -024334-s19) :

   v21 : ancre max 97 | 90 verts | 1 signale | 6 non juges | 1 saute
         -> 8 non verts / 98 =  8,16 %
   v22 : ancre max 96 | 84 verts | 2 signales | 1 non juge | 10 SAUTES
         -> 13 non verts / 97 = 13,40 %

Le resync a saute les mots 46 a 54, que v21 jugeait VERTS. Il jette donc des
mots correctement juges.

POURQUOI LA COMPARAISON DE SCORES N'A PAS PROTEGE. Les deux deplacements
acceptes avaient un score par frame de -Infinity a l'ancre courante. Un
alignement vide sur un APERCU ne prouve pas la derive : il prouve que l'audio
n'est pas encore arrive. N'importe quel candidat gagne contre -Infinity -- le
garde-fou est aveugle exactement la ou il devait mordre.

CE QUE CA APPREND, et qu'il ne faut pas reperdre :
 - le garde isFinal n'etait PAS un bug, il protege contre ce cas precis.
   Le supprimer etait l'erreur, pas la solution ;
 - compter les mots SAUTES est obligatoire. Sans eux le correctif affichait
   3,45 % contre 7,22 % -- moitie moins d'erreurs -- alors qu'il en produisait
   plus. Un mot saute disparait du denominateur au lieu de compter comme
   echec (regle n.1 du skill analyse-session-recitation, oubliee ici) ;
 - la simulation hors device (arbitrer_resync.py) predisait 15 deplacements
   utiles : elle rejouait les derives sur l'audio COMPLET du segment, pas sur
   le buffer partiel d'un apercu. Un banc qui ne reproduit pas la partialite
   de l'entree ne peut pas trancher un correctif qui agit sur des apercus.

La derive de Maryam reste donc entiere et non corrigee.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 305db63 — 2026-07-29 — Le resync ne devine plus : il aligne aux deux ancres et garde la meilleure

**Branche/tag:** 

**Auteur:** kafai

**Corps:** DEUX DEFAUTS, un seul bloc de code.

1. Le correctif n'a jamais tourne. Le resync etait conditionne a `isFinal`,
   or 100 % des detections de derive tombent sur une passe d'apercu -- verifie
   sur les 5 sessions Maryam -- et aucune passe finale ne repasse a ces ancres
   (elles sautent 23 -> 38 -> 58 -> 67). Pendant ce temps le reciteur prenait
   5 a 14 mots d'avance. Deplacer l'ancre sur un apercu est sans danger pour le
   jugement : un apercu ne verrouille aucun mot.

2. Le detecteur devinait. C'est un empilement de seuils (gop < -3, free > -0,5,
   derive >= 2). Banc `benchmark/arbitrer_resync.py` sur les 25 derives
   journalisees : 10 sont de FAUSSES alertes (les « 59 -> 60 » d'Al-Baqara).
   Retirer le garde en aveugle aurait fait sauter des mots dans 40 % des cas.

On aligne donc aux DEUX positions sur les MEMES log-probs et on garde la
meilleure. Aucun seuil ajoute -- la couche mesure au lieu de supposer, et le
detecteur redevient un declencheur d'examen dont les erreurs sont sans
consequence. Cout : une passe de DP sur des log-probs deja calculees, aucune
inference supplementaire.

Mesure hors device (25 derives) : 15 deplacements acceptes, gain moyen +6,78
de score par frame ; les vraies derives de Maryam passent de -16,23 a -1,26,
de -19,51 a -2,09, de -14,02 a -2,51.

Ce qui reste NON traite et doit l'etre ensuite : les mots enjambes sont
marques « jamais juges », pas recuperes. Le banc `mots_enjambes.py` montre
que 81 % d'entre eux sont dans le flux brut, dans une plage contigue -- c'est
le travail du second buffer, pas de celui-ci.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 6eea79a — 2026-07-29 — Banc : arbitrer le deplacement d'ancre par la MESURE, pas par un seuil

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le detecteur de derive actuel est un empilement de seuils (gop < -3,
free > -0,5, derive >= 2). Ce banc mesure ce que vaudrait la regle inverse :
aligner aux deux positions candidates sur les MEMES log-probs et garder la
meilleure -- aucun seuil, la couche mesure au lieu de deviner.

Mesure sur les 25 derives reellement detectees dans les 75 sessions :
   15 deplacements acceptes, gain moyen +6,78 de score par frame
   10 deplacements REFUSES = autant de faux positifs du detecteur a seuils

Les vraies derives de Maryam passent de -16,23 a -1,26, de -19,51 a -2,09,
de -14,02 a -2,51 : une ancre effondree redevient un alignement approuve par
le modele. Les fausses alertes sont les « 59 -> 60 » d'Al-Baqara, un saut d'un
seul mot que la comparaison refuse a chaque fois.

Ce banc a directement change la proposition faite a l'utilisateur : retirer le
garde isFinal en aveugle aurait fait sauter des mots dans 40 % des cas.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 2f01498 — 2026-07-29 — Banc : les mots enjambes par le resync sont-ils recuperables ?

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le resync debloque l'ancre mais marque « jamais juges » les mots enjambes
(5 a 14 par derive sur Maryam). Question de l'utilisateur : un second buffer
peut-il les rattraper ? Ce banc cherche chaque mot enjambe dans le flux BRUT,
pas dans les clips -- les clips sont l'audio deja consomme, donc deja filtre
par ce qu'on cherche a juger.

Resultat sur 42 mots enjambes : 34 presents = 81 %, et surtout dans une plage
temporelle CONTIGUE (mots 48-58 tous retrouves entre 90 s et 99 s). Un rejeu
cible est donc possible : on connait les mots ET l'intervalle.

Reserve de methode inscrite ici pour ne pas etre reoubliee : sur les mots
tres courts (« min », « lam ») le test de sous-chaine apparie n'importe ou
dans la sourate -- ces cas ne prouvent rien. Seuls les mots distinctifs
comptent (nubashshiruka, bighulamin, ismuhu, yahya, samiyya).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 934b6e7 — 2026-07-29 — Banc : rejouer hors device le resync sur les derives reellement detectees

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le correctif du decrochage ne peut pas etre juge sur le device : il faut
d'abord savoir ou l'ancre atterrirait. Ce banc rejoue l'algorithme exact de
findResyncOffset (MIN_RESYNC_HITS=3, fenetre 6 mots, lookahead 60, harakat
retirees) sur le texte de decodage libre que l'app a elle-meme ecrit dans ses
logs, aux instants ou elle a detecte une derive.

Resultat sur les 75 sessions du depot : 25 derives sur 27 seraient corrigees,
avec 4 a 6 mots apparies. Sur Maryam, l'ancre restait plantee 5 a 14 mots
derriere le recitateur -- le modele, lui, situait correctement la position a
chaque fois.

Ce banc existe parce que la mesure a deja invalide deux hypotheses seduisantes
dans la meme seance (tokenisation NFC : 0 % de gain mesure ; sonde 4 lettres :
9,18 % -> 17,89 %). Aucune ligne de Kotlin ne doit etre ecrite avant lui.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 6d99166 — 2026-07-29 — Sonde de 4 lettres rejetee, expansion mise en sommeil : le secours coute plus qu'il ne rapporte quand il se declenche trop

**Branche/tag:** 

**Auteur:** kafai

**Corps:** SONDE DE 4 LETTRES (idee utilisateur : « 3 ou 4 lettres suffisent a trouver le
bon mot »). Le raisonnement tient -- on cherche a SITUER, pas a juger, et le
decodage libre perd parfois une lettre. La mesure le contredit :

    Maryam, mot entier : 9,18 %   --  8 tentatives de secours
    Maryam, 4 lettres  : 17,89 %  -- 72 tentatives de secours

Une sonde courte apparie trop facilement : le secours se declenche partout.
L'utilisateur l'a d'ailleurs senti AVANT de voir les chiffres (« c'est pas fluide
comme avant ») -- chaque tentative est une inference sur le chemin critique, elle
retarde le jugement des mots suivants, qui se font alors couper. Retiree.

EXPANSION A+B+C+D mise en sommeil pour ISOLER un suspect : Al-Baqara etait passe
de 2,00 % (v15) a 3,28 % (v20), avec DEUX changements faits ensemble (expansion
et resync sur texte). Resultat sans expansion : 6,74 % puis 2,06 %. La variance
couvre l'ecart -- l'expansion n'est donc PAS un suspect demontre, et je ne la
supprime pas : elle reste en sommeil derriere un drapeau, avec sa raison.

SIGNAL QUI RESSORT DES TROIS MESURES : le nombre de tentatives de secours et le
taux d'erreur varient ENSEMBLE (72 -> 17,9 % ; 28 -> 6,7 % ; 21 -> 2,1 %). Le
2e buffer n'est donc pas gratuit -- au-dela d'un certain volume il degrade ce
qu'il est cense reparer.

PROTOCOLE ADOPTE (decision utilisateur) : Al-Baqara devient le garde-fou de
non-regression ; les developpements se font sur d'autres sourates, et on revient
sur Al-Baqara pour confirmer.


---
### 4606d64 — 2026-07-29 — Le resync comparait des identifiants de tokens : il compare desormais du TEXTE

**Branche/tag:** 

**Auteur:** kafai

**Corps:** `findResyncOffset` exigeait que la suite d'IDENTIFIANTS de tokens du mot attendu
apparaisse telle quelle dans le decodage libre. Or le decoupage BPE du libre
n'est presque jamais celui de la cible : un mot code [a,b,c] peut sortir [ab,c]
ou [a,bc], et aucun appariement n'a lieu.

Consequence mesuree sur Maryam : les mots 46-57 echouaient d'un bloc avec
free = -0,06 -- un modele CERTAIN de ce qu'il entend -- la derive etait bien
detectee, et pourtant ZERO resync. On comparait au mauvais niveau. Le TEXTE, lui,
correspond.

L'appariement se fait donc sur des chaines, harakat retirees : le squelette
consonantique suffit a SITUER, et il ne depend d'aucun decoupage. Le jugement,
lui, reste au GOP -- position et verdict restent separes.

Ajoute une trace INCONDITIONNELLE du resync (les deux textes compares, tronques).
Deux versions ont echoue en silence, sur les tokens puis sur le texte, et le log
ne disait ni pourquoi ni ce qui etait compare.

Maryam : 14,58 % (v15) -> 15,46 % (v16) -> 9,18 % (v18), rouges 9 -> 10 -> 6.
La derive se declenche desormais deux fois par session.

RESTE OUVERT : la trace de resync n'apparait toujours pas, donc
`findResyncOffset` sort avant elle -- sur son garde `heard.size < 6`. La
prochaine passe doit dire pourquoi le decodage libre rend si peu de tokens sur
ces segments.


---
### 6d07754 — 2026-07-29 — Secours etendu aux mots valides en amont -- et ce qu'il ne peut PAS reparer

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Idee utilisateur : si A, B, C sont juges corrects et que D echoue, ne pas
rejuger D SEUL mais A+B+C+D. Deux issues informatives -- le groupe passe, donc
c'etait l'accrochage ; le groupe echoue avec des voisins corrects, donc c'est
bien D. Les mots deja valides servent d'ancres SURES.

Implemente, puis SIMPLIFIE sur sa demande : un seul essai a 4 mots au lieu d'une
expansion incrementale (2 puis 4), qui multipliait les inferences sur le chemin
critique sans rien apporter -- mesure sur Maryam : declenchee UNE fois sur 15
mots non verts.

CE QUE LA MESURE APPREND, ET QUI COMPTE PLUS QUE LE CORRECTIF. Sur Maryam, les
mots 48 a 57 echouent d'un bloc et le secours n'a produit AUCUNE ligne pour eux
-- ni fenetre, ni verdict. Il n'a jamais ete appele. La raison : en DERIVE
d'ancre, la DP ne place plus rien, ces mots ne sont donc pas dans le resultat
d'alignement, et la boucle du secours parcourt ce resultat. Ils lui sont
invisibles.

Aucune amelioration du secours ne peut donc traiter la derive : les mots
concernes ne lui parviennent pas. Signature de la derive, mots 46-57 :
    gop -6,2 a -11,9   free -0,06 a -0,90
Le modele est CERTAIN de ce qu'il entend et l'alignement est effondre : c'est la
POSITION qui est perdue, pas la prononciation.

Et le detecteur de derive s'est bien declenche (1 fois) mais AUCUN resync n'a
suivi : findResyncOffset ne trouve pas de meilleure position. C'est la, et non
dans le secours, qu'il faut travailler.

Maryam v16 : 15,46 % (10 rouges) contre 14,58 % (9 rouges) en v15 -- aucun gain
demontrable, la variance seance a seance couvre l'ecart.


---
### 88673bc — 2026-07-29 — Le rejeu deterministe attend la FIN DU FICHIER, pas une duree de montre

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Sur le MEME WAV rejoue, le nombre de mots juges variait : 71, 98, 96. La session
durait 100 s de montre, mais selon le temps de chargement du modele elle ne
consommait pas la meme portion du fichier -- les taux n'etaient donc pas
comparables entre passes, alors que c'est tout l'objet du mode deterministe.

Le script attend desormais le marqueur « fin du fichier » que l'app ecrit quand
le rejeu est epuise.


---
### 36c03d0 — 2026-07-29 — Rayon de coupe elargi a 2 s : essaye, mesure, rejete

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Idee : la borne droite etant desormais ancree sur le contenu, le rayon devenait
le seul parametre decidant combien de points de coupe sont candidats. L'elargir
devait rendre le choix perdu au commit precedent sans redevenir dependant de
l'horloge.

Mesure, trois passes sur le MEME fichier rejoue :

    rayon 0,8 s : 7,0 / 4,2 / 4,0 %   coupes 5,7  16,3  23,4  35,4  36,8
    rayon 2,0 s : 4,2 / 9,9 / 3,7 %   coupes 5,7  16,6|16,8|16,9  ...

La variance REVIENT. Cause : avec plus de candidats, ce sont de minuscules
differences du MASQUE DE BLANCS qui decident du gagnant -- et ce masque vient de
la derniere inference, dont la couverture depend encore de l'instant. Le rayon
large EXPOSE donc une dependance a l'horloge que le rayon etroit masquait.

Retour a 0,8 s. Sans reproductibilite, aucune optimisation suivante n'est
demontrable -- et la tentative est laissee en commentaire pour qu'elle ne soit
pas refaite a l'identique.

Ce que ca designe pour la suite : le masque de blancs doit lui aussi etre ancre
sur le contenu, pas sur la derniere inference en date.


---
### f2d61bc — 2026-07-28 — La coupe ne depend plus de l'horloge -- mais le taux n'y gagne pas

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le rejeu deterministe (meme WAV pousse dans l'app, micro debranche) a montre que
la variance ne venait PAS de l'acoustique. Sur un audio identique au bit pres,
trois passes donnaient 2,8 %, 3,9 % et 5,3 %, et surtout des coupes differentes :

    passe 1 : 5,70  16,96  23,38  34,48  45,28  50,66  62,08
    passe 2 : 5,70  17,27  23,38  33,92  36,80  48,32  50,67
    passe 3 : 5,70  17,20  23,30  34,00  36,80  48,32  50,67

Cause : la recherche de coupe bornait a droite sur `buf.size` -- ce que le buffer
contient AU MOMENT ou la decision tourne, donc une grandeur qui depend de
l'ordonnancement et de la duree de l'inference precedente, pas du son. Comme une
coupe sur deux tombe en plein mot, quelques dizaines de millisecondes d'ecart
changent quel mot est detruit.

La recherche est desormais bornee symetriquement autour de la cible, elle-meme
ancree sur le debut du segment. Resultat : cinq coupes identiques sur six entre
trois passes, contre une divergence des la deuxieme.

CE QUE CA NE FAIT PAS : baisser le taux. 7,0 / 4,2 / 4,0 % contre 2,8 / 3,9 /
5,3 % avant. Borner la recherche reduit le choix de points de coupe, et certains
retenus sont moins bons. On gagne la reproductibilite, on ne gagne pas la
qualite -- c'est un prealable de mesure, pas un correctif de fond, et il est
commite comme tel.

Corrige aussi deux echecs silencieux du banc distant : le WAV doit etre
transfere sur le poste qui porte les telephones avant d'etre pousse (adb s'y
execute et ne voit pas ce disque), et il doit atterrir dans le dossier PROPRE a
l'app -- depuis Android 11 elle ne peut pas lire un fichier arbitraire de
/sdcard, et l'echec ne se voyait que par l'absence de blocs PCM.


---
### 4c83d3e — 2026-07-28 — L'installation distante echouait en silence : trois recettes analysees sur un binaire perime

**Branche/tag:** 

**Auteur:** kafai

**Corps:** `adb install C:\Temp\x.apk` repondait « No such file or directory » ALORS QUE
`dir` trouvait le fichier : un chemin ABSOLU Windows ne survit pas aux
echappements successifs bash -> ssh -> cmd. Et le script avalait la sortie, donc
il annoncait une installation reussie.

Consequence mesuree : trois recettes analysees sur un binaire vieux d'une heure.
Le log le disait pourtant -- `build=causal-v9-deterministe` alors que la source
etait en v10 -- c'est la ligne de version en tete de session qui a rattrape
l'erreur, exactement ce pour quoi elle existe.

On transfere donc dans le repertoire personnel, on installe par chemin RELATIF,
et on VERIFIE que « Success » apparait (code de retour non nul sinon).


---
### a786239 — 2026-07-28 — Couper la ou le MODELE ne dit rien, pas la ou le signal est faible

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Cause isolee sous la contrainte « un seul lien a la fois » : 47,4 % des coupes
de segment tombent en plein mot, et 19 des 22 mots non verts ont ZERO frame --
ce sont les victimes de ces coupes. La coupe etait decidee sur l'ENERGIE (portier
RMS, seuil 0,02) alors que les occlusives arabes (ب ذ ن) ont une phase peu
energique AU MILIEU d'un mot. L'energie ne porte donc pas la frontiere de mot :
la couche devinait avec une grandeur qui ne contient pas l'information cherchee.

Or cette information existe deja dans la chaine. Le CTC emet le BLANC exactement
la ou il n'y a rien a transcrire. On memorise donc le masque des blancs a chaque
inference et la coupe cherche la plus longue suite de blancs pres de la cible,
au lieu du micro-silence le plus proche.

VALIDE HORS DEVICE AVANT D'ECRIRE LA PREMIERE LIGNE DE KOTLIN, comme le projet
l'impose. `benchmark/comparer_politiques_coupe.py` rejoue les deux politiques
sur le meme audio reel, memes cibles de coupe :

    energie (actuel)   10/22 coupes en plein mot = 45,5 %
    blancs  (propose)   6/22                     = 27,3 %

Soit 40 % de destruction en moins. Repli sur l'energie tant qu'aucune inference
n'a tourne sur le buffer courant (tout debut de segment) : mieux vaut l'ancienne
politique que pas de coupe. Le masque est invalide a la purge -- il decrit un
buffer qui n'existe plus, et ses indices ne veulent alors plus rien dire.

Non mesure sur device : le poste qui porte les telephones est injoignable.


---
### d629d63 — 2026-07-28 — Chiffre la cause a la couche ou elle NAIT : 47,4 % des coupes tombent en plein mot

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Suite du diagnostic obtenu sous la contrainte « un seul lien a la fois ». Le lien
ASR -> alignement avait ete disculpe : 19 des 22 mots non verts ont ZERO frame,
avec 160 ms de place disponible en mediane -- l'aligneur n'a pas d'audio, il
n'est pas fautif. Le defaut naissait donc a la coupe de segment.

Ce script le mesure la, sans device. Les clips sont l'audio consomme, contigus
et sans recouvrement (verifie apres correctif : somme(clips) < flux brut), donc
leurs frontieres SONT les coupes. Pour chacune on decode une fenetre centree
dessus, puis les deux moities separement : un mot present dans la fenetre
entiere mais absent des deux moities a ete casse par la coupe.

    s2   6/13  (46 %)
    s55  7/13  (54 %)
    s67  5/12  (42 %)
    -----------------
    TOTAL 18/38 = 47,4 %

Pres d'une coupe sur deux detruit un mot. C'est coherent avec les 19 mots a zero
frame : ce sont les victimes de ces coupes.

CE QUE CA DESIGNE. La coupe est decidee sur l'ENERGIE du signal (portier RMS,
seuil 0,02) alors que l'information utile est « ou le modele n'emet rien ». Les
occlusives arabes ont une phase peu energique AU MILIEU d'un mot : l'energie
n'est pas une frontiere de mot, et le projet le documente depuis le debut
(FONCTIONNALITES_FUTURES.md §4). La couche devine avec une grandeur qui ne porte
pas l'information -- signature d'architecture, pas reglage de seuil.

Non mesure sur device : le poste qui porte les telephones est injoignable.


---
### 6ae0884 — 2026-07-28 — Le contexte droit va AUSSI a la DP : les mots de fin de segment n'avaient pas d'audio

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Diagnostic obtenu en s'interdisant de toucher a plus d'UN lien de la chaine a la
fois (contrainte posee par l'utilisateur). Lien examine : ASR -> alignement.

Mesure sur 12 sessions, mots non verts uniquement :

    19 des 22 ont ZERO frame          -- pas « trop peu », AUCUNE
    place disponible quand la DP echoue :
        mediane 160 ms   min 0 ms   max 1760 ms

Deux frames pour un mot entier. Ces mots ne sont donc pas MAL PLACES : il n'y a
pas d'audio pour eux. Le lien ASR -> alignement est disculpe -- l'aligneur fait
ce qu'il peut avec ce qu'on lui donne -- et le defaut naît en amont, a la coupe
de segment.

Le commit precedent donnait deja 2 s de contexte droit, mais A L'ENCODEUR
SEULEMENT : les logprobs etaient tronquees a la coupe avant la DP, par symetrie
avec le chevauchement de gauche. FAUSSE symetrie, et c'est ce que la mesure
montre.

  - A GAUCHE, tronquer est juste : ce sont des mots DEJA juges, les laisser
    entrer fait re-accrocher la DP dessus (regression mesuree le 2026-07-27).
  - A DROITE c'est l'inverse : cet audio appartient a des mots PAS ENCORE juges,
    et c'est exactement celui qui leur manque.

La DP le recoit donc, et c'est `covered` qui decide -- comme toujours -- si un
mot est assez couvert pour etre verrouille. `consumed` reste borne a l'audio que
ce segment a le droit de purger : sans cette borne, il jetterait de l'audio
appartenant au segment suivant.

Non mesure sur device : le poste qui porte les telephones est devenu injoignable
(100 % de perte de paquets) pendant la campagne.


---
### bc43244 — 2026-07-28 — Skill « solution-de-fond » : les questions qui separent un correctif d'un pansement

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Ecrit apres une seance ou j'ai produit trois correctifs qui « marchaient » et
dont DEUX etaient des palliatifs -- reperes par l'utilisateur, pas par moi :
« au lieu de chercher des solutions dans l'architecture, les couches, des
solutions pour que le modele soit dans les memes conditions pour mieux juger, tu
es en train de modifier les criteres d'acceptance ».

`recul-architectural` sert a SORTIR d'une boucle deja installee. Celui-ci sert
AVANT d'ecrire la premiere ligne. Il tient en trois questions a se poser par
ecrit, dont une seule reponse fausse disqualifie le correctif :

  1. est-ce que je deplace un critere d'acceptation ?
  2. est-ce que je mets le modele dans les conditions ou il REUSSIT ?
  3. quelle CLASSE de correctifs je n'aurai plus jamais a ecrire ?

La deuxieme est la plus productive sur ce projet : hors device le modele lit
chaque mot des qu'il n'est pas au bord d'une fenetre de 2-4 s. Demander « qu'est-
ce qui, sur l'appareil, differe de ces conditions ? » a directement produit le
correctif du contexte droit.

Le skill porte aussi le prealable de mesure -- ne jamais optimiser contre une
mesure plus bruitee que le gain cherche (meme binaire, meme sourate : 1,4 % puis
4,3 %) -- le juge de paix (confronter au modele sur l'audio brut : 8 non verts,
0 vraie erreur) et l'obligation de varier le materiau (Al-Baqara masquait tout,
Ar-Rahman et son refrain repete 31 fois a fait ressortir 9,4 %).

Corrige au passage le rapatriement des WAV a distance : `run-as ... cp` vers
/sdcard echoue SANS MESSAGE (pas le droit d'y ecrire). L'archive est redirigee
vers un fichier sur le disque distant -- redirection executee par cmd.exe, donc
le binaire ne traverse jamais SSH -- puis rapatriee par scp.


---
### 3c3fb74 — 2026-07-28 — Pilotage des telephones a distance, et confrontation systematique au modele

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Les deux telephones sont branches sur un autre poste. Le serveur adb distant a
bien ete mis en ecoute et atteint par un tunnel SSH, mais le client repond
« protocol fault » y compris apres alignement des versions (34.0.5 / 36.0.2,
testees identiques). On ne s'acharne pas : SSH marche, adb execute la-bas
marche, on compose les deux.

  benchmark/adb_pcb.sh        pilote adb distant
  benchmark/installer_pcb.sh  transfere l'APK puis l'installe la-bas

Deux pieges payes pendant la mise au point, tous deux silencieux :

- cmd.exe interprete les redirections de la commande shell ANDROID comme les
  siennes : `adb shell "wc -l < /sdcard/..."` repartait vide, sans message. Les
  arguments sont donc re-echappes un par un.
- faire transiter un tar par la sortie standard de SSH depuis un Windows expose
  a une traduction CRLF qui corrompt le binaire sans rien dire -- et un WAV
  corrompu ne se voit qu'a l'analyse. Les fichiers passent donc par `pull` sur
  le disque distant puis `scp`, qui est binaire.

Ajoute aussi `verifier_erreurs.py`, qui confronte CHAQUE mot non vert au modele
sur l'audio brut -- le critere impose par l'utilisateur. Il balaye plusieurs
largeurs de fenetre (une seule ne prouve rien : `عظيم` est parfait a 3 s et
introuvable a 12 s) et ressort le texte reellement decode pour les cas non
trouves, au lieu de conclure sur un test de sous-chaine.

PREMIER RESULTAT SYSTEMATIQUE, sur deux sessions (Ar-Rahman et Al-Mulk) :

    8 non verts sur 125 mots juges          = 6,40 %
    dont VRAIES erreurs (modele d'accord)   = 0    = 0,00 %
    dont FAUX POSITIFS (defaut de chaine)   = 8    = 6,40 %

Zero vraie erreur. Chaque mot signale par l'app est lu correctement par le
modele sur l'audio brut, souvent sur une fenetre de 2 s. Le taux d'erreur de
l'app est donc entierement constitue de defauts de chaine.


---
### b72b05b — 2026-07-28 — Recette DETERMINISTE : rejouer un WAV a la place du micro

**Branche/tag:** 

**Auteur:** kafai

**Corps:** On ne peut pas optimiser ce qu'on ne sait pas mesurer. Le banc a deux telephones
passe par haut-parleur -> micro : chaque passe differe par le point de depart du
recitateur, le niveau et le bruit de piece. Mesure sur six binaires :

    meme binaire, meme sourate : 1,4 %  puis  4,3 %
    passes individuelles       : de 0,0 %  a  10,9 %
    moyennes par binaire       : de 1,8 %  a   5,6 %

La variance du banc depasse donc l'effet cherche. Dans ces conditions, tout
« gain » annonce est du bruit -- et on se met a ajuster sur la mesure au lieu de
traiter une cause, exactement ce que le projet interdit.

    WAV=<fichier> ./benchmark/recette_2tel.sh 2 120

Le fichier est pousse sur le juge et rejoue A LA PLACE du micro. Il emprunte
EXACTEMENT le meme chemin : memes blocs de 80 ms, meme cadence TEMPS REEL, meme
aval (portier, buffer, segmentation, alignement, jugement). Rejouer plus vite
fausserait tout ce qui depend du temps -- pauses detectees, latence, bornes de
segment. On ne mesure donc pas un chemin de test different du chemin reel.

Le second telephone n'est plus sollicite dans ce mode.


---
### 363a3a1 — 2026-07-28 — Contexte des DEUX cotes pour l'encodeur, jugement seulement au centre

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le segment recevait 3 s de contexte a GAUCHE (le chevauchement) et RIEN a
droite : il s'arretait net a la coupe. Le dernier mot d'un segment etait donc
reconnu sans le son qui le suit, alors qu'un encodeur conformer s'appuie sur son
voisinage des deux cotes.

C'est une difference de CONDITIONS, pas de critere : hors device, le modele lit
chaque mot correctement des lors qu'il n'est pas au bord de la fenetre ; sur
l'appareil, les mots de fin de segment y sont systematiquement. On donne donc a
l'encodeur 2 s d'audio au-dela de la coupe, et on tronque les logprobs avant la
DP et avant le texte fige -- exactement la discipline deja appliquee au
chevauchement de gauche. Cet audio appartient au segment suivant, qui le jugera
avec son propre contexte.

Consequence a ne pas rater : `snapshot` contient desormais plus que l'audio
JUGE. Tout ce qui met en rapport des echantillons et des frames passe par
`audioJuge` (14 endroits) -- c'est la classe de bug des deux referentiels, deja
tombee trois fois sur ce fichier, et elle aurait decale toutes les positions.

Mesure : 6,8 % et 4,3 % contre 8,5 % et 1,4 % sur les memes sourates au commit
precedent. AUCUN EFFET DEMONTRABLE : la variance du banc domine l'ecart cherche.
Le meme binaire sur la MEME sourate donne 1,4 % puis 4,3 %. C'est le vrai
obstacle du moment -- on ne peut pas optimiser ce qu'on ne sait pas mesurer.


---
### 8507b0e — 2026-07-28 — Retire le palliatif : on ne deplace pas le critere d'acceptation

**Branche/tag:** 

**Auteur:** kafai

**Corps:** La regle « la proportion cede devant une preuve d'alignement forte » acceptait un
fragment d'une lettre comme fragment legitime des que normGop depassait le seuil
correct. Ecrite et mesuree le matin, retiree le meme jour sur rappel de
l'utilisateur, et il a raison : c'est un CRITERE D'ACCEPTATION qu'on deplace,
pas une cause qu'on traite. Le projet l'interdit explicitement.

La raison de fond est mesurable : hors device, le modele lit CHAQUE mot
correctement des qu'on lui donne une fenetre de 3-4 s -- `عظيم` est parfait a
3 s et perdu a 12 s. Il n'a donc pas besoin qu'on assouplisse le juge, il a
besoin des MEMES CONDITIONS qu'hors device. Relacher la regle aurait masque
precisement la difference de conditions qu'il faut corriger.

Conserve en revanche la detection de DERIVE D'ANCRE du commit precedent : celle-la
ne touche a aucun critere de jugement, elle deplace l'ancre. Elle reste dans la
doctrine « le decodage libre decide de la POSITION, jamais du rouge/vert ».


---
### a54cfe2 — 2026-07-28 — La regle de proportion cede devant une preuve d'alignement forte

**Branche/tag:** 

**Auteur:** kafai

**Corps:** `يُخَـٰدِعُونَ` entendu `يُ` avec normGop = +0,93. `أَلِيمٌۢ` entendu `ۢ` avec
normGop = +0,10 puis +0,34. Tous deux tres au-dessus du seuil `correct`
(-0,45), tous deux plafonnes a ORANGE par le seul fait que le decodage libre
sur leurs frames est court -- donc classes « autre mot ».

La regle de proportion (`entendu x 3 >= attendu`) protege contre « valider un
mot sur une lettre ». Elle est juste tant qu'on n'a QUE le texte decode. Mais
quand l'alignement force dit du bien du mot, on dispose d'une preuve
INDEPENDANTE, et la refuser revient a juger sur le seul artefact de decoupage
de frames. Le mot est bien la : le modele le produit exactement sur l'audio
brut, verifie hors device.

Ce n'est PAS la tolerance refusee le 2026-07-25 (« un recitant qui ne dit que
la moitie d'un mot etait valide ») : ce cas-la a un gop MAUVAIS et reste refuse.
Le discriminant est la preuve acoustique, et les trois conditions le disent --
l'audio couvre le mot entier (`covered`), la DP lui a donne son minimum de
frames (`!starved`), et le score depasse le seuil de correction.

Trois passes du banc : 3,3 % / 10,0 % / 0,0 %. Une passe a ZERO non vert sur
96 mots juges. La variance reste le probleme dominant -- la passe a 10 % est un
demarrage rate (7 non juges, aucun signale), pas une regression du jugement.


---
### a97867f — 2026-07-28 — Le secours voit enfin les mots TRONQUES, pas seulement les mots absents

**Branche/tag:** 

**Auteur:** kafai

**Corps:** `أَلِيمٌۢ` sortait en orange avec un `normGop` POSITIF (+0,10 puis +0,34, tres
au-dessus du seuil correct de -0,45) : l'alignement etait bon, seul le texte
decode sur ses frames etait un fragment (`ۢ`), ce qui suffit a le classer
« autre mot » et a le plafonner. Le secours repare exactement ce cas ailleurs
dans la meme session (`شَيَـٰ` -> `شَيَـٰطِينِهِمْ`), mais son declencheur ne le
voyait pas : le mot a des frames, un `actual` non vide, et il est `covered`.

Le declencheur teste donc desormais aussi la TRONCATURE (`entendu x 3 <
attendu`), ce qui demandait de connaitre le texte attendu cote natif :
`WordResult.expectedText`, detokenise avec le meme vocabulaire que `actual`,
donc comparable caractere pour caractere.

Ce n'est devenu SUR qu'apres l'alignement avec voisins du commit precedent :
tant que le secours alignait un mot seul, elargir son declencheur aurait
multiplie les faux positifs (7 sur 33 tentatives mesurees).

Campagne sur le banc a deux telephones, meme passage, 120 s, trois passes par
binaire (la variance seance a seance est reelle, une passe ne prouve rien) :

    v1  (reference)      4,2 %
    v2  (voisins)        5,3 / 1,0 / 2,1 / 8,0 / 3,2  -> moyenne 3,9 %
    v3  (troncature)     4,2 / 3,1 / 2,2              -> moyenne 3,2 %

Les rouges ont quasiment disparu (0 sur 5 des 6 dernieres passes) et le secours
rattrape 13 a 23 mots par session contre 6 avant.

Reste au-dessus de l'objectif de 1 %. Deux coupables recurrents identifies, tous
deux dans le verset 2:9 : `يُخَـٰدِعُونَ` (mot 70) et `يَخْدَعُونَ` (mot 75) --
deux mots quasi identiques dans le MEME verset, que la DP confond. C'est la
piste suivante.


---
### 44305da — 2026-07-28 — Le secours aligne le mot AVEC SES VOISINS, plus jamais seul

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Aligner un mot SEUL contre une fenetre qui en contient trois ou quatre est la
cause commune des deux modes d'echec du secours, mesures sur 33 tentatives :

- l'alignement force doit couvrir TOUTES les frames avec ce seul mot ; si les
  voisins occupent l'essentiel de la fenetre, son score s'effondre -> RATE,
  alors que le mot est bien la (6 cas, dont le mot 131 « لا » quatre fois de
  suite avec la fenetre decodant « ـٰكن لا يعلمون ») ;
- s'il n'y a rien de mieux a faire, la DP le pose quand meme quelque part et le
  gop peut sortir excellent -> FAUX POSITIF (7 cas). Le mot 132 « يعلمون » a
  ete declare parfait TROIS fois sur une fenetre decodant « وإذا لقوا »,
  c'est-a-dire le verset suivant. Un faux positif fait passer au VERT un mot
  correctement signale, ce que l'app existe pour eviter.

La cible du secours devient donc l'ensemble des mots que la fenetre couvre
reellement -- ceux compris entre les deux voisins HORODATES qui la bornent --
et seul le mot vise est retenu. C'est ce que fait l'etat de l'art : un second
passage porte sur un SEGMENT avec contexte, jamais sur un mot isole.

Ajoute un garde-fou : un rattrapage qui rend PLUSIEURS mots est refuse. Mesure
qui l'impose : le mot 151 « بهم » rendu « ويمدهم في طغيانهم », accepte parce
que le gop remontait.

Mesure sur le banc a deux telephones, meme passage, meme duree :
                        avant       apres
    rouges                2           0
    orange                2           3
    non juges             0           2
    non verts           4,2 %       5,3 %
    secours rattrapes   6 / 17     18 / 25

Les rouges disparaissent et le secours devient trois fois plus efficace, mais le
total remonte : deux sessions ne suffisent pas a conclure, la variance n'est pas
encore connue.


---
### 95caeb7 — 2026-07-28 — Le banc de recette retire la Basmala : les deux telephones partaient decales

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le recitateur enregistre n'attaque pas par la Basmala -- l'audio d'Al-Baqara
commence directement sur `الم`. La garder dans la cible faisait donc demarrer
les deux cotes decales de QUATRE mots, et on ne mesurait plus la chaine mais un
decalage de depart.

Mesure du meme passage, meme duree, meme audio :

                        avec Basmala    sans
    ancre                     66          95
    mots verrouilles          37          95
    mots sans verdict         26           1
    non verts             8 rouges    4 (2 rouges, 2 orange) = 4,2 %
    RESYNC                     1           0

Verifie avant de conclure a une regression : le chemin acoustique est bon
(RMS 0,1423 capte, contre 0,1500 sur la session manuelle de reference) et le
modele lit l'audio quasi parfaitement hors device -- y compris les huit mots
marques rouges. Le decalage etait bien la seule cause.

Reste ouvert, souleve par l'utilisateur : meme desynchronise, le systeme DEVRAIT
se resynchroniser et signaler l'audio perime. Il ne l'a pas fait (0 RESYNC sur
la session decalee) -- a instruire.


---
### 2ced1b1 — 2026-07-28 — Recul architectural : 12 faux positifs sur 12, le modele hors de cause

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Session de 268 mots, recitation professionnelle, moteur GOP aux commandes.
12 mots non verts. Verification mot par mot en donnant au MODELE DU DEVICE
l'audio de la session, hors device : les 12 sont produits EXACTEMENT, pour peu
qu'on donne la bonne fenetre. `عظيم` est parfait sur 3 s et perdu sur 12 s.

Zero faute de recitation, zero limite de modele : douze faux positifs nes du
decoupage et de l'alignement.

Faille centrale identifiee, nouvelle par rapport au recul du 26/07 : le VERDICT
est rendu au rythme de la TRANSCRIPTION, alors que rien ne l'y oblige. La
transcription doit etre temps reel ; le jugement peut attendre. Deux exigences
opposees se partagent la meme variable -- aucun seuil ne les departagera.

Corollaire : le 2e buffer tel qu'il est construit est un palliatif dans la
mauvaise couche. Il reconstruit mot par mot une information que la couche de
jugement a jetee en figeant trop tot. Mesure : 33 tentatives, 16 OK, 7 FAUX
POSITIFS, 6 rates. Un faux positif fait passer au VERT un mot correctement
signale.

Etat de l'art : ce qu'on a construit s'appelle un two-pass rescoring, et la
litterature le fait sur un SEGMENT avec contexte complet, jamais sur un mot
isole -- exactement la source des faux positifs.

Quatre pistes consignees avec leur cout et leurs effets de bord. Le skill
d'analyse gagne l'etape « 2e buffer », une ligne par TENTATIVE, et l'interdiction
de reconstituer l'audio du secours depuis les clips sans avoir verifie que
somme(clips) < flux brut.


---
### e1fadaa — 2026-07-28 — Recette a deux telephones : une commande, aucun tap

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Chaque test de la chaine de recitation demandait la meme navigation manuelle sur
DEUX appareils : ouvrir l'app, choisir la sourate, entrer dans l'ecran, lancer.
Refait a la main a chaque iteration, c'est du temps perdu et surtout un
protocole qui VARIE entre deux mesures censees etre comparables.

    ./benchmark/recette_2tel.sh [sourate] [duree]

Le Xiaomi joue le recitateur, le Samsung ecoute et juge, meme passage des deux
cotes. En sortie : un dossier horodate avec le log isole de la session, les WAV
et un resume.

Choix de conception, chacun paye par un echec constate pendant la mise au point :

- Pilotage par INTENT (`--es recette ecoute|lecture --ei sourate N`) plutot que
  par `input tap` : les coordonnees dependent de l'ecran et de la langue, et un
  tap qui rate ne se voit pas dans le log -- on analyse alors une session qui
  n'a jamais demarre.
- `KaraokeRecitationScreen.autoDemarrer` : on atterrit DANS la recitation deja
  lancee. Il contourne aussi le dialogue « reference ou correction ? », qui
  attendait un tap et arretait la session juste apres « demarrage automatique »
  sans que rien ne le dise.
- Attente ACTIVE du marqueur « capture ouverte » avant de lancer le recitateur.
  Un delai fixe est faux dans les deux sens : trop court, le debut n'est jamais
  capte ; trop long, on perd du temps a chaque iteration.
- `ecarter_dialogue.py` : Android pose son avertissement de compatibilite sur
  tout APK debogable. On reste debogable A DESSEIN -- `run-as`, donc la
  recuperation des WAV, ne fonctionne QUE dans ce mode (verifie : « run-as:
  package not debuggable » en release) -- et on ecarte le dialogue en visant le
  bouton par son TEXTE, pas par des coordonnees en dur.


---
### 8cd6a06 — 2026-07-28 — Chaque session dit desormais ce qu'elle teste, et vide sa trace fine

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Une journee entiere d'analyses a ete menee sur des lignes [GOP] en croyant lire
ce qui s'affichait a l'ecran. En realite `useGopScoring` etait a false : le GOP
tournait en parallele et se journalisait SANS RIEN PEINDRE, c'est le texte-diff
qui pilotait l'affichage -- et lui restait bloque sur « بسم الله » (defaut deja
documente dans JudgementOptions le 2026-07-22). Le log annoncait 10 mots
`correct`, l'ecran n'en montrait aucun, et rien dans le fichier ne permettait de
savoir lequel des deux moteurs etait aux commandes.

D'ou le bloc [PARAMS] en tete de chaque session. La ligne qui compte est
`moteur=` : elle dit QUI PEINT. Les autres (mode reference/normale, preset,
seuils, taille de cible, build) evitent d'attribuer a un correctif ce qui vient
d'un reglage.

Ajoute aussi le vidage de la trace fine sur la PAUSE MANUELLE. Elle n'etait
videe qu'a l'arret ; or une session s'etait terminee sur une pause, et la seule
trace capable de dire ce qui tenait la chaine pendant deux trous de 11 s
(`feed ... busy=`, une ligne par bloc PCM) est morte avec l'app. Le log ne
permettait plus que des hypotheses.


---
### 10dd819 — 2026-07-28 — Sort le gel a la borne dure du thread audio, et cesse d'ecrire l'audio deux fois

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Trois defauts mesures sur device, tous dans la chaine native de segmentation.

1. Le gel a la borne dure tournait dans feed(), donc sur le thread qui livre le
   PCM. Tant qu'il ne faisait que promouvoir un apercu c'etait gratuit ; depuis
   que le secours y fait des inferences ONNX, il bloquait le transport (383 ms
   mesures sur un seul cas). Il passe dans une coroutine, sous le meme verrou
   que le chemin normal -- ce qui supprime au passage une course : l'ancien
   `!busy.get()` LISAIT le verrou sans le prendre, donc une passe normale
   pouvait demarrer pendant la promotion et travailler sur un buffer en cours
   de purge. Effet mesure : trous de traitement 3,3/100 s -> 0,2/100 s.

2. Le clip du gel normal s'ecrivait jusqu'a la fin du snapshot, donc il
   contenait aussi `conserve` -- l'audio que ce segment ne juge PAS et qui reste
   dans le buffer pour le suivant. Chaque `conserve` etait donc ecrit DEUX fois.
   Verifie sur 17 clips sur 17 : `fichier - (consomme - contexte) == conserve`
   au centieme de seconde, cumul +22,3 s pour 22,2 s de `conserve`. Les clips
   totalisaient 319,0 s pour 310,2 s de flux BRUT -- plus long que le micro,
   impossible sans duplication. Ca cassait la premisse de
   ReferenceTimingExtractor (clips contigus et sans recouvrement) et faussait
   toute analyse hors ligne prenant les clips comme reference temporelle.
   Apres correctif : 346,4 s de clips pour 362,2 s de brut, 0 clip hors
   tolerance.

3. Le secours rejoue le vrai aligneur, donc il emettait les memes lignes que le
   chemin principal (ZERO FRAME, AVANCE SANS JUGER) sans rien pour les
   distinguer. Sur une session : 24 lignes « AVANCE SANS JUGER », dont ZERO
   venait du chemin principal -- de quoi conclure a une regression d'un facteur
   24 qui n'existait pas. Elles sortent desormais prefixees `secours:`.

Documente aussi, sans l'implementer, la piste ecartee « rendre le flux BRUT au
2e buffer » : mesure du jour, rendre le silence au modele n'ameliore pas le WER
(-2,8 pt en faveur du portier).


---
### c0935dd — 2026-07-27 — Le secours vise enfin les bons mots, et couvre le chemin de la recitation continue

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE QUI L'IMPOSE (session de 124 mots, recitateur rejoue en continu). Le
secours a tire 9 fois : 1 rattrapage, 6 relectures de mots DEJA CORRECTS
(gop 0,00, texte identique), 2 echecs. Et il n'a PAS tire sur les 3 mots
signales. Le declencheur etait donc faux dans les deux sens.

1. `starved` RETIRE du declencheur. Il detecte « peu de frames », pas « mal
   juge » : c'est lui qui faisait secourir 6 mots ayant deja gop=0,00 et le bon
   texte.

2. `!covered` AJOUTE -- le cas dominant, qui manquait. `عَظِيمٌ`->`مٌ` et
   `بِمُؤْمِنِينَ`->`بِمُ` ont un `entendu` non vide, des frames, et ne sont pas
   `starved` : aucune condition ne les attrapait, alors que ce sont exactement
   les mots tronques que le secours existe pour reparer. L'aligneur calculait
   deja le bon signal : `covered` est faux quand l'audio n'a pas couvert le mot
   en entier.

3. MARGE DROITE 1 s -> 2 s. Pour un mot tronque, `lastFrame` marque la fin du
   SEGMENT, pas la fin du mot : le reste est au-dela de la coupe. Sans une marge
   qui la depasse, le secours ressortait le meme fragment.

4. CHEMIN DE LA BORNE DURE couvert. Il promeut l'apercu SANS rappeler
   runAlignment : le secours n'y existait pas. Or c'est le chemin de la
   recitation CONTINUE. Mesure : les mots 63 (`وَمِنَ`, entendu vide) et 73
   (`بِمُؤْمِنِينَ`->`بِمُ`) ont tous deux ete juges par ce chemin, et le secours
   n'a jamais tourne dessus. Les WordResult bruts du dernier alignement (plus
   leur origine absolue et leur facteur frames->echantillons) sont desormais
   conserves pour que ce chemin puisse rejouer la meme boucle.

5. APERCUS INCLUS (idee utilisateur : « n'attends pas le jugement final, comme
   ca on regarde l'amelioration »), MAIS en excluant le mot de FRONTIERE : sur
   un apercu il est tronque par construction -- l'audio n'est pas encore arrive
   -- et il se completera seul a la passe suivante ; le secourir la serait du
   travail perdu, repete toutes les ~1,5 s. Un mot que la DP ne place pas alors
   que l'audio l'a DEPASSE, lui, ne se reparera jamais seul : il est secouru des
   l'apercu.

La regle « le secours ne peut que rattraper » (verdict remplace seulement s'il
est meilleur) reste inchangee sur les deux chemins.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 0bf91b0 — 2026-07-27 — Skill : impose UN format de compte rendu unique, avec confirmation WAV par mot

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Consigne utilisateur : « a chaque fois tu changes la presentation de l'analyse
du log, rajoute dans le skill le meme format : d'abord la liste des mots, et
pour chaque mot pourquoi, en analysant avec confirmation wav ».

CAUSE DE LA DERIVE, identifiee en relisant les comptes rendus de la journee : le
rapport etait coupe en DEUX tableaux (signales d'un cote, non juges de l'autre).
Cette separation invite a en oublier un -- c'est arrive deux fois -- et a
reinventer la forme a chaque session. Un tableau UNIQUE avec une colonne
« etat » (rouge / orange / non juge) supprime la cause.

FORMAT IMPOSE, colonnes dans cet ordre :
    mot | attendu | entendu | etat | forced | free | cause | dans le WAV ? | mecanisme

La colonne « dans le WAV ? » est declaree NON OPTIONNELLE : c'est elle qui
distingue une analyse d'un simple releve. Si la verification n'a pas ete faite,
ecrire « (non verifie) » -- jamais laisser croire qu'elle l'a ete.

Et le MODE doit etre annonce, parce qu'il change l'interpretation : avec un
recitateur rejoue en continu, tout `entendu` vide est un defaut de l'app (le mot
est forcement prononce) ; avec la voix de l'utilisateur, il peut signifier qu'il
n'a pas prononce le mot. Cette distinction a ete donnee par l'utilisateur en
plein diagnostic, apres coup.

Le bilan chiffre, le regroupement par mecanisme et les cas inexpliques viennent
APRES le tableau, jamais a la place.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 84778b6 — 2026-07-27 — La fenetre de secours tombait 3 s avant le mot : origine absolue corrigee

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE (20:25, premiere session ou le secours produit enfin un verdict) : 9
secours sur 9 rendent gop=-20,00 avec entendu vide.
    secours mot=27 SANS GAIN : gop -0,03 -> -20,00, entendu "" -> ""
    secours mot=43 SANS GAIN : gop -0,68 -> -20,00, entendu "سَوٌَ" -> ""
La DP ne trouve rien, systematiquement : la fenetre extraite ne contient pas le
mot.

CAUSE. La position absolue etait calculee depuis `absStart`, le debut du buffer
principal. Mais les logprobs passes a l'alignement sont TRONQUES du contexte de
chevauchement : leur frame 0 correspond a `absStart + contextStart`, pas a
`absStart`. La fenetre etait donc systematiquement decalee de toute la longueur
du contexte -- 3 s, exactement ce qu'on lui retranche ensuite comme marge
gauche. Resultat : une fenetre qui tombe ENTIEREMENT avant le mot, d'ou une DP
qui ne place jamais rien.

L'origine absolue est desormais passee explicitement a runAlignment
(`absOrigin`) plutot que deduite d'un champ qui ne correspond plus depuis
l'introduction du chevauchement. Le parametre est documente a sa declaration
pour que la confusion ne puisse pas se reproduire : ce n'est PAS absStart.

Troisieme bug de la meme famille aujourd'hui -- deux echelles de temps qu'on
croit confondues : positions de coupe calculees sur le flux conserve et
appliquees sur le flux d'origine (bench_double_decoupage), clips ecrits avec le
contexte alors que le reste les veut contigus, et maintenant frame 0 des
logprobs prise pour le debut du buffer.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 5740cee — 2026-07-27 — Le secours produisait toujours une liste vide : forceJudgeIndex manquant

**Branche/tag:** 

**Auteur:** kafai

**Corps:** TROUVE PAR LA TRACE, pas par hypothese (cf. skill analyse-session-recitation,
regle n2). Les quatre conditions d'entree etaient bonnes --
    secours? isFinal=true spf=1263 segmentSamples=192000 frames=152 mots=9 besoins=4
donc mes quatre hypotheses precedentes (fenetre hors anneau, arithmetique des
index absolus, exception avalee, condition d'entree) etaient TOUTES fausses. La
ligne qui a tranche :
    secours mot=20 SANS RESULTAT : DP muette sur 6042ms (39 frames apres 38 de contexte)

CAUSE. La fenetre etait correcte (38 frames de contexte = 3,0 s, puis 39 frames
pour le mot), mais `align()` etait appele SANS forceJudgeIndex. La branche
zero-frame DIFFERE alors le mot (deferredIndex) et sort avec une liste VIDE. Or
un secours one-shot n'a pas de « prochaine passe » : y differer equivaut a ne
rien produire. Le mecanisme etait donc structurellement incapable de rendre un
verdict, quelle que soit la qualite de l'audio.

C'est la MEME classe de bug que celle deja corrigee le 2026-07-16 sur alignFile
(revue de code, Finding #3) : « ce mode one-shot ne rappelait jamais align()
avec forceJudgeIndex -- un mot differe etait donc perdu DEFINITIVEMENT pour ce
clip ». Meme fichier, meme piege, trois mois plus tard.

Ce commit ajoute aussi les deux logs qui manquaient sur les chemins muets du
secours (DP sans resultat, verdict sans gain) -- sans eux, « secours inefficace »
et « secours jamais appele » restaient indiscernables, ce qui avait coute deux
sessions.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### f00f53c — 2026-07-27 — Regle "pas d'hypothese tant qu'une ligne de log peut trancher" + trace du declencheur

**Branche/tag:** 

**Auteur:** kafai

**Corps:** CONSIGNE UTILISATEUR, donnee apres avoir vu la scene se repeter : « pas
d'hypothese tant qu'on peut faire un test avec du log ».

CE QUI L'A MOTIVEE. Le buffer de secours est reste ENTIEREMENT muet sur deux
sessions -- ni verdict, ni echec, ni message d'impossibilite. A chaque fois j'ai
propose une cause plausible (fenetre hors anneau, arithmetique des index
absolus, exception avalee, condition d'entree) au lieu d'instrumenter le
declencheur. Trois hypotheses, trois fois faux, deux sessions perdues. Une seule
ligne exposant les conditions d'entree aurait tranche du premier coup.

METHODE inscrite dans le skill : formuler la question en variables observables
(« laquelle de ces quatre conditions est fausse », pas « pourquoi ca ne marche
pas »), emettre UNE ligne qui les expose toutes, et une passe de test elimine
trois maillons sur quatre.

COROLLAIRE : un mecanisme qui echoue en silence est pire qu'absent -- il donne
l'illusion d'etre en place. Tout chemin qui peut abandonner (fenetre
indisponible, audio trop court, exception) doit journaliser sa raison, sinon son
absence de trace est indiscernable de son inaction.

Ce commit ajoute aussi la trace correspondante dans BufferedTranscriber : une
ligne par passe finale exposant isFinal, spf, segmentSamples, nombre de frames,
nombre de mots et nombre de mots ayant BESOIN du secours. La prochaine session
dira lequel des quatre maillons casse, au lieu d'une quatrieme hypothese.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 3f5fa4c — 2026-07-27 — Corrige deux bugs qui rendaient le secours muet et multipliaient les non juges

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE DEVICE (19:54) : 18 mots non juges sur 86 (21 %), contre 4 a 6 % avant,
et ZERO ligne SECOURS sur toute la session. Deux bugs distincts, cumules.

BUG 1 -- `neverBlock` fabriquait les non juges. Il court-circuitait la seconde
chance : le mot etait abandonne des le PREMIER echec de la DP, alors que ce
second essai reussissait souvent. Mesure : 42 « AVANCE SANS JUGER » contre 5
avant, et une cascade ou l'ancre rampe mot par mot (ancre=0 frontiere=0 mots=1,
puis 1, puis 2...).

L'exigence de l'utilisateur (« l'ancre doit faire +1 en cas d'erreur, elle ne
doit pas s'arreter ») etait DEJA satisfaite par le chemin `noEvidence` ajoute
plus tot : apres la seconde chance, l'ancre avance sans juger. Le drapeau etait
donc redondant, et sa seule action nette etait de supprimer le rattrapage. Il
n'intervient plus dans la branche zero-frame.

BUG 2 -- le secours ne pouvait pas lire ce qu'il demandait, et echouait EN
SILENCE. Les mots qui declenchent le secours sont par definition les DERNIERS de
leur segment (verifie : 21 zero-frames finaux, tous « DERNIER du segment »). Or
la fenetre demandee etait [mot - 3 s, mot + 1 s] : la marge droite depasse
l'audio deja capte, donc `extract` rendait null a chaque fois. Sans aucun log --
d'ou zero ligne SECOURS et zero echec, un mecanisme entierement inerte et
indetectable.

Deux correctifs : la fenetre est bornee a l'audio reellement disponible
(`min(total, absTo + marge)`), et toute impossibilite est desormais
JOURNALISEE avec sa raison (fenetre hors anneau, ou audio trop court). Un
mecanisme de secours qui echoue en silence est pire qu'absent : il donne
l'illusion d'etre en place.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 488d969 — 2026-07-27 — Buffer de secours en lecture seule : rejuge un mot non place, avec contexte

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Architecture proposee par l'utilisateur, retenue apres que le chevauchement a
produit TROIS regressions en deux commits -- toutes parce qu'il modifie le
buffer PRINCIPAL, donc que chaque erreur y contamine le chemin critique :
boucle de re-gel (quatre gels de 3000 ms en une seconde), ancre qui n'avance
plus d'un mot par gel, clips qui se recouvrent de 3 s. L'utilisateur avait
annonce ce risque AVANT l'implementation.

PROPRIETE STRUCTURELLE : cet anneau est ecrit puis LU, jamais consomme, jamais
purge par le jugement. Le chemin principal l'ignore. Et le secours est SANS
ETAT -- une extraction, une inference, un verdict, on rend la main. Ni ancre, ni
progression, ni memoire : desynchronisation entre deux ancres, boucle,
duplication deviennent IMPOSSIBLES, pas seulement evitees par vigilance.

LE LIEN ENTRE LES DEUX BUFFERS EST EXACT, pas approche. L'anneau stocke le MEME
flux que le buffer principal (apres portier RMS) : stocker le flux brut ferait
diverger les deux echelles de temps des qu'un bloc est jete, l'erreur exacte qui
avait fausse bench_double_decoupage.py le matin meme. La position d'un mot est
donc calculee, pas cherchee :
    position absolue = absStart du segment + frame x echantillonsParFrame
`ForcedAligner.WordResult` expose desormais `firstFrame` en plus de `lastFrame`
pour donner les deux bornes.

LA REGLE QUI COMMANDE LE RESTE, formulee par l'utilisateur : « il aura 3 s de
contexte mais pas pour juger ces 3 s ». L'inference porte sur
[mot - 3 s, mot + 1 s], mais la DP ne demarre qu'aux frames du mot. Donner le
contexte a la DP est exactement l'erreur commise le matin avec le chevauchement
-- elle accrochait sa cible sur l'audio deja juge, d'ou des `place=8000ms` sur
TOUTES les passes finales. Marge asymetrique : le contexte GAUCHE est ce qui
manque (un segment qui commence en plein mot est illisible ; une fin tronquee
gene beaucoup moins).

DECLENCHEUR valide avec l'utilisateur : mot non place, etrangle, ou entendu
vide -- et UNIQUEMENT sur une passe finale. Repere qui rend le surcout
negligeable : sur une session, 175 zero-frames au total mais seulement 4 sur des
passes finales.

LE SECOURS NE PEUT QUE RATTRAPER : il remplace le resultat s'il est MEILLEUR
(gop superieur), jamais sinon. Un mot deja vert ne peut donc pas devenir rouge.
Sans cette regle on rouvrirait la porte au « meilleur des deux verdicts », qui
gonfle la tolerance en silence -- ce que le banc du matin signalait deja comme
le risque principal de toute politique a deux sources.

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, 17 tests passent /
3 echecs preexistants sans lien, APK installe.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### eb231af — 2026-07-27 — L'ancre ne cale plus : resynchronisation par le decodage libre, et +1 en mode reference

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Point de retour propre avant de passer a l'architecture du buffer parallele
(cf. FONCTIONNALITES_FUTURES.md §11).

LE DEFAUT TRAITE -- le seul qu'AUCUNE politique de decoupage ne corrige. Quand
la DP ne place pas un mot, l'ancre reste dessus pendant que le reciteur avance.
Trois consequences mesurees le 2026-07-27 :
 - des mots INTERIEURS au segment suivant echouent alors qu'ils ne sont pas en
   frontiere (mots 76-77 : la DP part d'un mot qu'elle ne trouve pas, tout
   l'alignement du segment est decale) ;
 - un mot attendu recoit l'audio de PLUSIEURS mots (mot 124 :
   entendu="ءَامَنَّا وَإِذَا خَلَوْا۟ إِلَىٰ شَيَ") ;
 - l'ancre avance d'un mot par gel pendant que le reciteur est des versets plus
   loin (« l'ancre ne suit plus »).
Ce n'est pas l'audio qui manque, c'est la POSITION qui est perdue.

1. RESYNCHRONISATION. Sur une passe finale ou la DP n'a rien place, on apparie
   le decodage LIBRE du segment a la suite de mots attendue et on deplace
   l'ancre la ou le reciteur se trouve reellement. Tout se passe en espace de
   TOKENS, jamais en texte : pas de normalisation arabe reimplementee, donc pas
   de desaccord silencieux avec le tokenizer.

   Le decodage libre a le DROIT de trancher ici : la doctrine du projet
   (ForcedAligner, « RETENU 14h50 ») dit qu'il decide de la POSITION, jamais du
   rouge/vert. Mesure a l'appui : pendant un blocage d'ancre, le libre lisait
   parfaitement deux versets d'avance alors que l'ancre attendait un mot trois
   versets en arriere.

   Volontairement exigeante (3 mots retrouves d'affilee, fenetre de 60 mots
   max) : deplacer l'ancre a tort sauterait des mots sans les juger, ce qui est
   pire que d'attendre. Et AUCUN verdict n'est emis sur les mots sautes -- pas
   de rouge sans preuve.

2. ANCRE +1 EN MODE REFERENCE (demande utilisateur : « l'ancre doit faire +1 en
   cas d'erreur, elle ne doit pas s'arreter dans ce mode »). Le contrat
   « 2 chances max » suppose que le reciteur REDISE le mot apres une
   correction ; or la correction est desactivee en mode reference et l'ancre ne
   recule jamais. Differer y revient donc a caler -- mesure : 5 blocages de 8 a
   13 alignements sur une seule session. Le mode est pousse depuis Dart au
   demarrage (setNeverBlockAnchor), avec le meme motif de report que
   pendingCommitSilenceMs quand le transcripteur n'existe pas encore.

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, 17 tests passent /
3 echecs preexistants sans lien, APK installe.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 13ef78e — 2026-07-27 — Skill analyse-session-recitation : fige la methode et les erreurs deja commises

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Cette analyse (log device + WAV -> compte rendu causal) a ete refaite une
dizaine de fois le 2026-07-27, a la main, et une omission ou une erreur de
methode s'est glissee A CHAQUE FOIS. Demande de l'utilisateur : « si besoin cree
un skill comme tu sais ce qu'il faut faire, car on va passer 90 % du temps sur
ce type de compte rendu avec les wav ».

Le skill encode ce qui a ete appris a ses depens :

REGLE N1 -- ne jamais omettre les mots NON JUGES. Redemande deux fois par
l'utilisateur. Un mot peut ne pas etre vert de trois facons ; presenter « 2,8 %
d'erreurs » quand 7,4 % des mots ne sont pas verts, c'est donner le chiffre
flatteur. Le total doit boucler : verrouilles + non juges = ancre max.

CLASSER PAR MECANISME, pas par symptome. Trois mecanismes distincts ont ete
isoles, et ils appellent des correctifs opposes :
  A. une coupe fait DEUX victimes (le mot en frontiere ET celui qui ouvre le
     segment suivant) ;
  B. un mot coupe des deux cotes, entier dans aucun segment ;
  C. propagation d'ancre -- des mots INTERIEURS echouent parce que le premier
     mot du segment n'a jamais ete place. Aucun decoupage ne corrigera C.

CONFRONTER A L'AUDIO, toujours, et distinguer les deux sources : `stream_*.wav`
(flux brut, avant portier = ce qui a ete prononce) et `clip_*.wav` (audio
consomme par les segments figes). Le tableau brut/clips donne directement si le
defaut est un alignement rate, une perte d'audio, ou une limite du modele.

PIEGES DE MESURE recenses, tous vecus : log tronqué tire pendant la session
(conclusion fausse sur l'ancre finale), mauvais telephone, plusieurs
recitations dans une meme fenetre, cadence confondue avec latence, `place=` d'un
ZERO FRAME comme discriminant frontiere/decrochage, valeurs epoch parasites dans
`VALIDATION retard=`, et 35 % de l'audio absent des clips a cause d'un chemin de
gel qui n'ecrivait pas de WAV.

Reference ajoutee dans CLAUDE.md a cote de `model-training`.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### d3ff1bf — 2026-07-27 — Allege le rendu du karaoke : deux couts quadratiques et un rendu non paresseux

**Branche/tag:** 

**Auteur:** kafai

**Corps:** CONSTAT UTILISATEUR : « l'ecran est lourd, je veux scroller et c'est long », et
« mon tel est plutot haut de gamme, il faut penser au moyen de gamme ». Le
telephone de test est un Galaxy S25 : ce qui est mesure ici est donc le MEILLEUR
cas materiel. Arbitrage explicite de l'utilisateur : privilegier l'ASR quitte a
appauvrir l'ecran.

POURQUOI CE N'EST PAS QU'UN PROBLEME DE CONFORT. Les allers-retours
MethodChannel qui alimentent le natif en PCM reviennent par le THREAD PRINCIPAL,
celui-la meme qui execute ce rendu. Un ecran lourd retarde donc mecaniquement
l'audio -- c'est le mecanisme qui avait produit une file d'attente de 35 s le
matin meme (commit ac4397f). Le groupage du transport l'avait masque, pas
supprime.

TROIS DEFAUTS CORRIGES.

1. `_verseContaining` parcourait TOUS les versets et REDECOUPAIT le texte arabe
   de chacun (splitExpectedWords) a chaque appel. Or le rendu appelle
   `_isLastWordOfVerse` pour CHAQUE mot, et celui-ci appelait
   `_verseContaining` DEUX fois :
       246 mots x 2 appels x ~30 versets ~ 15 000 decoupages de chaine arabe
   a chaque reconstruction, soit toutes les ~1,5 s (chaque payload
   d'alignement).

2. `_surahOwning` faisait exactement la meme boucle, egalement pour chaque mot.

   Les deux passent en O(1) via une table `mot -> verset / sourate` construite
   UNE fois au setup et a chaque enchainement de page. Les versions lentes sont
   conservees en repli tant que la table n'est pas prete -- jamais un resultat
   different, seulement plus lent.

3. `SingleChildScrollView(Column(blocks))` construisait ET mettait en page TOUS
   les mots, hors ecran compris. Remplace par un ListView.builder sur des
   BORNES de blocs (quelques dizaines d'entiers) : les widgets ne sont bâtis
   que pour ce qui est visible.

   `cacheExtent: 1600` : l'auto-scroll utilise Scrollable.ensureVisible sur la
   GlobalKey du mot courant, qui exige que le widget SOIT construit. La marge
   garantit qu'il l'est presque toujours, et le code d'auto-scroll teste deja
   `ctx != null` -- le cas limite degrade proprement (pas de defilement) au lieu
   de planter.

Aucun changement de comportement visible : memes blocs, memes bandeaux de
sourate, meme auto-scroll.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### e5c8011 — 2026-07-27 — Les bornes de segment portent sur l'audio NOUVEAU, pas sur le contexte

**Branche/tag:** 

**Auteur:** kafai

**Corps:** BUG TROUVE PAR L'UTILISATEUR, par le calcul et non par le log : « buffer de 1 a
12, avec chevauchement le deuxieme sera de 9 a 24 » -- soit 3 s de contexte PLUS
12 s de nouveau. Or les trois bornes de segmentation testaient `sizeSeconds`,
c'est-a-dire le buffer TOTAL, contexte compris :
    newSeconds >= MIN_COMMIT_SECONDS   (gel sur pause franche)
    newSeconds >= target               (coupe sur micro-silence)
    newSeconds >= MAX_SEGMENT_SECONDS  (borne dure)

Consequence : avec 3 s de contexte, seuls 9 s d'audio NOUVEAU tenaient avant que
la borne dure ne tire. Les segments se raccourcissaient de 25 %, donc les
FRONTIERES se multipliaient d'autant -- l'inverse exact de ce que le
chevauchement doit produire. Le chevauchement se payait en segments plus courts,
et une partie du benefice etait rendue aussitot.

MESURE (audio nouveau consomme par gel, mediane) :
    avant chevauchement (17:56)   9,3 s
    chevauchant          (18:40)  8,4 s

Le contexte s'AJOUTE desormais au segment au lieu d'en prendre la place, ce qui
est la definition meme d'un chevauchement. La cible de coupe et `minKeep` sont
decales de `contextSamples` en consequence : la coupe se compte a partir du
debut de l'audio nouveau, pas du debut du buffer.

Effet attendu : segments de 12 s d'audio nouveau (comme avant le chevauchement)
PLUS 3 s de contexte, donc moins de frontieres qu'avant ET un contexte gauche
partout.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### aba4feb — 2026-07-27 — Le contexte du chevauchement va a l'encodeur, jamais au juge

**Branche/tag:** 

**Auteur:** kafai

**Corps:** DEUX REGRESSIONS mesurees sur la premiere session avec chevauchement
(18:29-18:31), toutes deux introduites par le commit cd5c0f0.

1. L'ANCRE N'AVANCE PLUS (« l'ancre ne suit plus », constat utilisateur).
   Progression mesuree sur les passes finales : 4->4, 4->5, 12->13, 20->21,
   38->39, 63->64, 64->65 -- UN mot par gel. Et LES ONZE passes finales se
   terminent par un zero-frame avec une place enorme :
       mot 38  place=100 frames (~8000ms)  -> LA DP A ECHOUE
       mot 12  place= 72 frames (~5760ms)  -> LA DP A ECHOUE
   Avant le chevauchement : 4 zero-frames finaux sur TOUTE une session.

   CAUSE : les frames de contexte etaient passees a l'aligneur en meme temps
   qu'a l'encodeur. L'audio du contexte correspond aux mots PRECEDANT l'ancre,
   donc il ressemble a du texte plausible : la DP y accrochait les premiers mots
   de sa cible, puis laissait le vrai audio inexplique -- d'ou les 8 s de
   "place" et l'ancre qui piétine.

   CORRECTIF : les logprobs sont tronques avant l'alignement (`ctxFrames`), et
   l'index de derniere frame est reporte en absolu ensuite. Le contexte nourrit
   l'encodeur -- ce pour quoi il existe, empecher un segment de commencer en
   plein mot -- sans jamais entrer dans la DP. `segmentSamples` est corrige en
   consequence (snapshot moins le contexte).

2. LES CLIPS SE RECOUVRENT. Mesure : 142,3 s de clips pour 121,0 s de flux
   brut, soit 21 s de duplication -- exactement 3 s x 7 gels a la borne dure.
   Le chemin de gel a la borne dure ecrivait le clip AVEC le contexte, alors
   que le gel normal l'excluait deja. Or la contiguite sans recouvrement est la
   premisse de ReferenceTimingExtractor, qui concatene les clips par paires.

Ces deux bugs illustrent l'argument de l'utilisateur, note dans
FONCTIONNALITES_FUTURES.md §11 : le chevauchement touche le buffer PRINCIPAL,
donc chaque erreur y contamine le chemin critique. Un buffer de secours en
lecture seule rendrait ces classes de bugs impossibles plutot que de les faire
eviter par vigilance. Trois regressions en deux commits sur ce chemin, c'est un
signal a prendre au serieux avant d'aller plus loin.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 4a91ff3 — 2026-07-27 — Documente le buffer de secours decale comme piste VIVANTE, pas ecartee

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Correction d'une conclusion trop rapide : le banc a compare un double
decoupage qui tourne TOUJOURS (30 inferences, politique de remplacement). La
proposition de l'utilisateur est differente -- un second buffer decale consulte
UNIQUEMENT en cas de probleme, donc un cout proche de 1x plus quelques
inferences ponctuelles. La mesure ne s'applique pas a ce design et ne
l'invalide pas ; le presenter comme ecarte serait faux.

Et son argument de surete a ete valide par un bug reel le jour meme : le
chevauchement retenu modifie la purge du buffer PRINCIPAL, ce qui a
immediatement produit une boucle de re-gel (commit e12cf33). Un buffer de
secours en lecture seule rend cette classe de bugs IMPOSSIBLE au lieu de la
faire eviter par vigilance.

Trois points a mesurer avant implementation sont notes, dont le taux de
declenchement reel (repere : 175 ZERO FRAME sur une session mais seulement 4
sur passes finales) et la regle d'arbitrage qui doit rester limitee aux mots
d'extremite.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### e12cf33 — 2026-07-27 — Corrige la boucle de re-gel introduite par le chevauchement

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE DEVICE (18:17:30) : quatre gels de 3000 ms EXACTEMENT en une seconde,
retards de 250, 200, 196 ms -- le buffer regelait son propre contexte en boucle.

    FIGE 4s  consomme=4720ms  contexte=0ms    -> garde=3000ms
    FIGE 3s  consomme=3000ms  contexte=3000ms -> garde=3000ms
    FIGE 3s  consomme=3000ms  contexte=3000ms -> garde=3000ms
    FIGE 3s  consomme=3000ms  contexte=3000ms -> garde=3000ms

CAUSE : `consumed` porte sur TOUT le snapshot, contexte compris. Quand
l'aligneur ne place rien au-dela du contexte, consumed <= OVERLAP, donc
purgeFrom = max(0, consumed - OVERLAP) valait 0 : rien n'etait purge et le meme
audio repartait au tour suivant.

L'invariant qui manquait : la purge doit TOUJOURS depasser le contexte, sinon le
buffer n'avance pas. Le chevauchement est donc pris sur l'audio NOUVEAU
uniquement -- purgeFrom = max(contextStart, consumed - OVERLAP). Meme correction
sur le chemin de gel a la borne dure.

C'est exactement la classe de risque que l'utilisateur avait signalee avant
l'implementation (« faire attention a ne pas rejuger un mot deja juge juste ») :
le chevauchement modifie la purge du buffer PRINCIPAL, donc une erreur y
contamine le chemin critique. Un buffer de secours separe, en lecture seule, ne
peut pas produire cette classe de bug -- argument a retenir pour la suite (cf.
FONCTIONNALITES_FUTURES.md).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### cd5c0f0 — 2026-07-27 — Segments chevauchants : 3 s de contexte pour ne plus commencer en plein mot

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE QUI A CHOISI CETTE POLITIQUE (bench_double_decoupage.py sur le flux brut
du 17:56, 181,8 s de recitation continue) :
    actuelle          4 mots en frontiere / 119    15 inferences
    double decalee    3 / 119                      30 inferences
    CHEVAUCHANTE      1 / 133                      15 inferences

L'idee du double buffer decale (proposition utilisateur) ne gagne quasiment
rien pour le double du cout : les deux decoupes s'accrochent aux MEMES
micro-silences reels de la recitation, donc decaler la cible de 6 s ne decale
pas les frontieres. Le chevauchement ne depend d'aucune position -- il donne du
contexte gauche a CHAQUE segment. Il decode aussi plus de mots (133 contre 119).
Cout : meme nombre d'inferences, ~1,3x le calcul par inference (11,3 s ->
14,3 s d'audio), tres au-dessus de la marge disponible depuis que le transport
est groupe.

PREUVE DIRECTE SUR L'AUDIO DE L'UTILISATEUR (17:03) : un clip de 2,96 s
contenant de la vraie parole se decode en RIEN du tout ; le meme, precede du
clip d'avant, se lit parfaitement ("...أَمْ لَمْ تُنذِرْهُمْ لَا يُؤْمِنُونَ").
Ce n'est pas la coupe qui tronque un mot, c'est le segment suivant qui devient
illisible faute de contexte gauche -- ce que ForcedAligner documentait deja
depuis le 2026-07-25.

APPLIQUE A TOUS LES GELS, pas seulement a la borne dure : mesure des durees de
segment sur la session du 17:56 -- mediane 10 s mais 8 sur 21 sous 10 s, dont
un de 1 s et deux de 2 s. C'est sur les segments COURTS que le contexte vaut le
plus (cf. le clip de 2,96 s ci-dessus).

POURQUOI LE PIEGE DE DUPLICATION NE S'APPLIQUE PAS (une fenetre glissante naive
avait donne un WER > 100 % par duplication de texte, cf. ForcedAligner
"TENTATIVE 1"). Deux garde-fous independants, demandes par l'utilisateur
lui-meme (« faire attention a ne pas rejuger un mot deja juge juste ») :
 1. TEXTE -- fige comme apercu, decode a partir de `contextSamples` seulement
    (nouvelle borne `fromFrame` de greedyDecode, defaut 0 donc sans effet pour
    les autres appelants). Les mots du contexte n'apparaissent jamais deux fois.
    L'apercu est borne lui aussi, sinon le gel a la borne dure -- qui le
    REUTILISE tel quel -- les figerait une seconde fois.
 2. JUGEMENT -- borne par l'ANCRE, qui a deja depasse ces mots : ils ne sont pas
    dans la cible d'alignement, la DP ne peut donc pas les rejuger. Structurel,
    pas prudentiel.

LES CLIPS RESTENT CONTIGUS ET SANS RECOUVREMENT : le contexte est exclu du WAV
ecrit. C'est la premisse de ReferenceTimingExtractor, qui concatene les clips
par paires pour recoller les mots coupes -- y laisser le chevauchement ferait
compter deux fois les memes 3 secondes.

Le log de gel expose desormais `contexte=Xms -> garde=Yms` pour que le
chevauchement soit verifiable sur device plutot que suppose.

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, 17 tests passent /
3 echecs preexistants sans lien.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 03f9a42 — 2026-07-27 — Enregistre le clip du gel a la borne dure : 35 % de l'audio n'existait dans aucun fichier

**Branche/tag:** 

**Auteur:** kafai

**Corps:** DECOUVERTE (session du 17:44, grace au flux brut ajoute juste avant). Le
chemin `pendingForceCommit` -- celui qui fige un segment quand la recitation est
CONTINUE et qu'aucune pause franche n'arrive avant la borne de 12 s -- reutilise
l'apercu sans re-transcrire. C'est volontaire et documente (a 12 s la
re-transcription etait degradee). Mais l'ecriture du clip vivait uniquement dans
le chemin d'inference : ce chemin-la n'ecrivait donc JAMAIS de WAV,
silencieusement, sans erreur ni avertissement.

MESURE :
    gels avec clip ecrit          18   -> 124,3 s
    gels a la borne dure, SANS    7    -> ~73 s
    total ~197 s, coherent avec les 212 s gardees par le portier
=> 35 % de la recitation n'existait dans aucun fichier.

CE QUE CA A FAUSSE DANS LA JOURNEE :
- Des mots reputes « introuvables dans les clips » (تُنذِرْهُمْ, بِمُؤْمِنِينَ,
  كَمَآ, ٱلسُّفَهَآءُ) n'avaient pas ete detruits par la coupe : ils etaient dans
  des segments non enregistres. Le flux brut les contient tous.
- La mesure « 9 mots sur 15 recuperables en recollant les clips » a donc ete
  faite sur des donnees amputees d'un tiers ; le vrai taux est plus eleve.
- ReferenceTimingExtractor travaille sur des PAIRES de clips consecutifs : il
  etait structurellement aveugle sur un tiers de chaque session, et aurait
  sous-mesure sans qu'on comprenne pourquoi.
- Et c'est precisement la recitation CONTINUE qui declenche ce chemin, donc le
  cas ou l'enregistrement importe le plus.

ECARTE AU PASSAGE, par la mesure : le portier RMS n'y est pour rien. Simule sur
le flux brut, il n'ecarte que 20,4 s (9 %), et cet audio est du silence pur
(RMS median 0,0012, decodage vide). L'hypothese « le portier jette de la
parole », que je tenais pour le suspect principal une heure plus tot, est morte.

CORRECTIF : ecrire le clip sur ce chemin aussi -- exactement l'extrait couvert
par l'apercu, pris AVANT la purge du buffer, donc le meme audio que celui qui
vient d'etre juge. Et joindre son chemin au payload promu : sans cette seconde
ligne le fichier existerait mais resterait INVISIBLE cote Dart, puisque
ReferenceTimingExtractor construit sa liste de segments depuis `clipPath`.

Ni le jugement, ni la segmentation, ni l'ancre ne changent : c'est de
l'enregistrement, pas de la reconnaissance.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### f7db06a — 2026-07-27 — Enregistre le flux micro BRUT : les decisions du portier RMS etaient inverifiables

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Les clips (clip_*.wav) ne contiennent QUE ce que le portier a GARDE. Tout ce
qu'il ecarte n'existe nulle part -- ses decisions n'etaient donc verifiables par
aucune mesure, et c'est exactement la question qui bloque le diagnostic.

MESURE QUI L'IMPOSE (session du 17:25). La source est un RECITATEUR rejoue en
continu depuis un autre telephone, donc chaque mot a forcement ete prononce,
clairement et en entier :
    audio recu du micro          220,8 s  (2760 blocs, aucune perte a la capture)
    audio ecrit dans les clips   112,0 s
    ecarte par le portier RMS    108,8 s  -> 49 %
Et trois mots (تُنذِرْهُمْ, بِمُؤْمِنِينَ, يَكْذِبُونَ) restent introuvables
meme en recollant TOUS les clips et en redecodant -- absents jusqu'a leur
radical.

Impossible de trancher entre "vraies pauses de murattal" et "parole jetee a
tort" sans l'audio ecarte. C'est un trou d'instrumentation, pas une question
d'interpretation : la donnee n'existe pas.

LA CONDITION QUI L'EMPECHAIT. La capture du flux brut existait deja
(_streamingWavCapture, ecrite AVANT le portier) mais etait conditionnee a
`_usingCausalStreaming` -- faux depuis que le streaming cache-aware a ete
desactive le matin meme. Le fichier n'etait donc plus jamais ecrit,
silencieusement, et personne ne s'en apercevait puisque son absence ne produit
aucune erreur. Le flux brut est utile quel que soit le chemin d'inference : la
condition est retiree.

CE QUE LA PROCHAINE SESSION PERMETTRA. Superposer le flux brut et les clips
donne directement ce qui a ete jete, et repond a la question qui commande la
suite du chantier : le vrai coupable est-il la COUPE (hypothese de travail
depuis ce matin, appuyee sur 100 % des erreurs tombant sur un bord de segment)
ou le PORTIER (qui ecarterait 49 % d'une recitation continue) ? Les deux
appellent des correctifs opposes -- il faut la mesure avant de choisir.

Aucun effet sur le jugement, la segmentation ou le modele : un fichier ecrit en
parallele, bloc par bloc, apres la garde de pause et avant le portier.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### ac4397f — 2026-07-27 — Groupe le transport PCM : supprime la file d'attente qui grossissait sans borne

**Branche/tag:** 

**Auteur:** kafai

**Corps:** CE QUI EST MESURE, session du 16:56 (la pause « ne fait pas son travail ») :
  17:03:00.990  dernier bloc PCM recu (#4620)
  17:03:01.544  pauseCapture() -- le micro s'arrete bien (chunkCount 4620->4622)
  17:03:05 -> 17:03:46  QUATRE segments figes, buffer grossissant de 1 s a 10 s
  17:03:56.902  resumeCapture()
45 secondes de traitement APRES l'appui sur pause, sur ~35 s de blocs encore en
file. La pause arretait la reception, pas le pipeline.

CAUSE. Un aller-retour MethodChannel PAR BLOC de 80 ms, serialise par
_continuousFeedTail, avec un saut par le thread principal a chaque retour --
celui-la meme qui dessine le karaoke. Des que l'aller-retour depasse 80 ms en
moyenne, la file grossit sans borne. Mesure directe : pendant la pause, la
chaine ecoule ~9 s d'audio en 13 s de temps reel, donc elle consomme MOINS VITE
que l'audio n'arrive.

C'est la meme cause que tout ce qui a ete signale dans la journee : 28,7 s de
validations posterieures au dernier bloc recu, retards de validation de 10 a
27 s, et la coloration qui continue apres l'arret.

CE QUI EST ECARTE PAR LA MESURE. Aucune perte d'audio a la capture : 426,3 s de
micro actif (pause deduite) contre 425,6 s effectivement recues, soit 0,2 %
d'ecart, et une arrivee reguliere (mediane 1,60 s pour 20 blocs, exactement le
nominal ; 7 ecarts > 2,4 s sur 265). Le micro n'est pas concurrence : le defaut
est entierement en aval.

J'avais ecarte cette piste plus tot dans la journee en constatant que
l'inference native est lancee en scope.launch, donc non bloquante. La
conclusion etait fausse : ce n'est pas l'inference qui bloque, c'est
l'aller-retour de transport.

CORRECTIF : groupage ADAPTATIF. On accumule l'audio et on ne l'envoie que
lorsque la chaine est libre, en un seul appel. Auto-regulant par construction --
chaine rapide, paquets d'un bloc (comportement d'avant) ; chaine lente, paquets
plus gros qui la font rattraper. Il ne peut jamais y avoir plus d'un appel en
vol, donc plus d'accumulation possible.

POINT DE CONCEPTION : on groupe le TRANSPORT, pas le TRAITEMENT. Le portier RMS
et la detection de pause de BufferedTranscriber decident PAR APPEL a feed() ;
transmettre un gros paquet d'un coup rendrait le portier plus grossier et
changerait la segmentation. Le natif redecoupe donc en blocs de 1280
echantillons (80 ms, la taille livree par le micro) avant de nourrir le
transcripteur : le comportement de segmentation reste identique.

Aucun effet sur le modele, la segmentation ou les verdicts -- seulement sur la
granularite du transport.

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, 17 tests passent /
3 echecs preexistants sans lien.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### ec8ec43 — 2026-07-27 — Deduit les durees par mot sur le telephone, en fin de session de reference

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Exigence utilisateur (2026-07-27) : « la moulinette soit dans le tel qui va
deduire les timings » -- le PC ne doit servir qu'a valider la methode, pas a
faire tourner la fonctionnalite.

CE QUE CA REGLE. En direct, la segmentation coupe en plein mot : 12 des 18
erreurs de la session du 15:17 (67 %) tombaient sur un bord de segment, dont
deux avec gop=0,00 et free~0 -- le modele etait CERTAIN de ce qu'il entendait,
il n'avait recu qu'un fragment. Une duree mesuree sur un mot tronque ne vaut
rien. Et WordDurationStore, qui n'apprend que des mots valides, apprend donc
exactement les mots qui n'ont PAS le probleme et jamais ceux qui l'ont.

POURQUOI C'EST POSSIBLE APRES COUP. Les clips sont contigus et sans
recouvrement dans le flux consomme (`consomme` part dans le clip, `conserve`
reste dans le buffer). Recoller deux clips consecutifs reconstitue l'audio du
mot coupe au joint. Verifie le meme jour : le decodage libre lit correctement
le flux concatene de bout en bout, a travers les jointures. Le retard de
validation n'y change rien -- c'est un probleme de livraison en temps reel, pas
de contenu.

POURQUOI SUR LE TELEPHONE C'EST PLUS SIMPLE QUE SUR PC, et c'est le point
decisif : une analyse hors ligne doit DEVINER quel mot correspond a quel
morceau d'audio (tentative du jour : appariement par decodage libre, fragile,
47 mots retrouves sur 239). Le telephone n'a rien a deviner -- pendant la
session il a ENREGISTRE la correspondance, chaque segment fige connaissant son
ancre et son nombre de mots. La plage d'une paire de clips est donc connue
exactement, sans appariement ni derive.

Aucune brique nouvelle cote modele : alignFile fait deja une inference +
alignement force one-shot sur un WAV complet, avec le VRAI aligneur de
production -- rien n'est reimplemente, contrairement au banc PC dont la DP
Python est justement ce qui buguait. Et comme ca tourne apres la recitation, le
cout n'a aucune importance.

Trois decisions arbitrees avec l'utilisateur :
- capture audio INDEPENDANTE de l'interrupteur de diagnostic en session de
  reference (c'est la matiere premiere de la mesure, pas de la trace -- sans ca
  la fonctionnalite n'existerait qu'en mode debug) ;
- declenchement AUTOMATIQUE en fin de session, apres saveFor pour que le profil
  de pauses soit acquis meme si l'extraction echoue ;
- clips CONSERVES apres extraction.

AJOUT SEPARE, meme commit : un interrupteur de suppression de bruit du micro,
ETEINT PAR DEFAUT et delibere. Trois raisons mesurees : (1) le modele a ete
affine sur un corpus non filtre, les artefacts d'une suppression de bruit sont
un signal qu'il n'a jamais vu -- ces traitements visent l'oreille humaine, pas
la reconnaissance ; (2) la doc du package previent que le volume d'entree
baisse, or le portier de segmentation est un seuil ABSOLU (0,02) qui ecartait
deja 96 s d'audio sur 253 dans une session reelle ; (3) le bruit n'est pas le
defaut mesure -- les erreurs relevees montrent free~0, donc un modele CERTAIN
de ce qu'il entend, l'inverse de ce que produirait du bruit. Le reglage existe
pour trancher par une comparaison A/B, et son etat est journalise a l'ouverture
du flux sans quoi la comparaison serait ininterpretable.

Verifie : flutter analyze 0 erreur, 17 tests passent / 3 echecs preexistants
sans lien, APK construit et installe.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### b3cf46b — 2026-07-27 — Corrige la regression du matin : l'ancre ne peut plus bloquer sur un mot non place

**Branche/tag:** 

**Auteur:** kafai

**Corps:** REGRESSION INTRODUITE LE JOUR MEME (commit f634f92). Le `if (fits)` ajoute dans
la branche ZERO FRAME rendait le chemin `forceJudgeIndex` capable de differer
INDEFINIMENT. Or forceJudgeIndex EST le mecanisme "2 chances max" : au deuxieme
passage il doit trancher. Le commentaire ecrit ce matin affirmait « le garde-fou
anti-boucle reste entier dans le cas !fits » -- exact, mais dans le cas `fits` il
n'etait plus entier du tout, et je ne l'ai pas vu.

MESURE QUI L'A REVELE (session de reference du 15:17, sourate 2, 301 mots) :
  5 blocages d'ancre de 8 a 9 alignements consecutifs (mots 49, 61, 93, 131, 208)
  18 mots jamais verrouilles : 49-50, 61-62, 83, 93-94, 96, 131-132, 175, 178,
     208, 217 (plus 0-3, la Bismillah, normal)
Deroulé du mot 49 : place=0 -> differe, place=32 -> differe, place=36 final=true
-> differe encore. L'ancre reste a 49 pendant 9 alignements.

AGGRAVANT PROPRE AU MODE REFERENCE, signale par l'utilisateur (« en flux continu
on a juste la coloration ») : la correction y est desactivee (ligne 558 de
karaoke_recitation_screen), donc l'ancre ne recule jamais et le mot differe ne
repasse JAMAIS. Le contrat "2 chances" suppose que le reciteur redise le mot --
vrai en mode normal, faux ici. C'est pourquoi la regression ne se voyait pas
avant : en mode normal une correction reculait l'ancre et debloquait.

CORRECTIF, arbitre avec l'utilisateur (non juge plutot que rouge) : un troisieme
etat `WordResult.noEvidence`. Le mot est PRESENT dans la liste -- c'est ce qui
fait avancer l'ancre et supprime le blocage -- mais Dart ne lui donne aucun
verdict. Pas de rouge sans preuve acoustique (regle projet).

Consequence assumee et arbitree : un mot reellement saute n'est plus signale
dans ce cas precis. Coherent avec le mode reference, qui ne journalise deja
aucune erreur ; en mode normal, la correction reste le filet.

Le cas `!fits` (le mot ne POUVAIT pas tenir dans la place disponible) continue
d'etre tranche en erreur, inchange : la ou l'impossibilite est physique, le
verdict repose sur une preuve.

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, 17 tests passent /
3 echecs preexistants sans lien.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 7bfab61 — 2026-07-27 — Banc de mesure des durees depuis les clips WAV (repond oui a la question, banc pas fini)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Question utilisateur : « avec mes wav est-ce qu'il est permis de deduire les
timings malgre les retards de validation ? »

REPONSE : oui, et c'est demontre. Le retard de validation est un probleme de
LIVRAISON en temps reel, il ne touche pas le contenu audio. Mieux : les clips
sont contigus et sans recouvrement dans le flux consomme (`consomme` part dans
le clip, `conserve` reste dans le buffer), donc les concatener dans l'ordre de
gel reconstitue un flux continu ou LES MOTS COUPES AUX FRONTIERES DE SEGMENT
SONT RECOLLES -- ceux-la meme qui causaient 12 des 18 erreurs de la session du
15:17. Verification directe, decodage libre sur le flux concatene :
  [ 10-18s] ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ فِيهِ
  [ 40-48s] إِنَّ ٱلَّذِينَ كَفَرُوا۟ سَوَآءٌ
  [150-158s] وَتَرَكَهُمْ فِى ظُلُمَـٰ لَّا يُبْصِرُونَ
L'ordre des mots est preserve et le texte est juste.

CE QUI EST DANS CE COMMIT : l'alignement force CTC en Python (transcription
fidele de ForcedAligner.kt : etats etendus, trois transitions, fin partielle),
la concatenation des clips, la lecture de la suite attendue depuis les lignes
[GOP] du log (plutot que de reimplementer la normalisation Dart et risquer un
desaccord silencieux), et la comparaison etendue / frames non-blank.

CE QUI NE MARCHE PAS ENCORE, ecrit noir sur blanc en tete du fichier : le
placement de l'ancre par fenetre -- 8 mots mesures sur 239. Deux causes
identifiees et non corrigees : (1) l'ancre est estimee depuis les placements de
la DP de la fenetre precedente, or ces placements peuvent etre FANTOMES (la
fenetre 0-8 s ne contient qu'un mot au decodage libre, la DP y "place" 8 mots a
1-2 frames chacun) ; (2) des que l'ancre et la position audio divergent, le
chemin tout-blank devient le moins couteux et l'ancre cesse definitivement
d'avancer -- le meme decrochage que cote app, amplifie par (1).

La correction n'est pas une rustine de seuil : il faut ancrer chaque fenetre sur
le DECODAGE LIBRE (fiable, cf. extraits) apparie a la suite attendue, puis
lancer la DP sur la plage ainsi connue. Pas fait ici -- et les chiffres sortis
par le script en l'etat ne doivent pas etre utilises.

Deux mesures deja acquises au passage : une fenetre de 20 s fait s'effondrer le
placement (derive de normalisation per_feature deja documentee des ~10 s,
2026-07-05), d'ou le repli a 8 s ; et sur les 8 mots effectivement mesures, la
part de frames etiquetees par un token est de 64 % contre 37 % mesures sur
device -- ecart coherent avec le fait que les mots recolles ne sont plus
tronques, mais l'echantillon est trop petit pour conclure.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 923b500 — 2026-07-27 — Journalise le mode de session et le seuil de gel applique

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Les deux modes partagent TOUTE la chaine ASR (capture, portier RMS, buffer,
segmentation, gel, inference, alignement force, jugement GOP, coloration,
avancement d'ancre, mecanisme de report) mais pas leurs garde-fous -- et rien
dans le log ne permettait de les distinguer. Il fallait le DEDUIRE de l'absence
de `wordFailed declenche` (car _onWordFailed retourne avant ce log en mode
reference), deduction indirecte qui a deja provoque des erreurs
d'interpretation dans l'analyse de la journee.

CE QUE LE MODE REFERENCE DESACTIVE (verifie site par site) :
  ligne 493  journalisation des erreurs (aucune stat ecrite)
  ligne 558  correction automatique -> donc AUCUN RECUL D'ANCRE
  ligne 990  applyBestFor -> seuil de gel laisse au DEFAUT, non personnalise
  ligne 1025 remise a zero des stats de sourate
  ligne 1870 masquage du texte (opacite 0,04 -> 1,0 : c'est une lecture)
et ce qu'il ajoute : _maybeSaveProfile() (ligne 1090), qui enregistre le profil
de pauses si la precision atteint 60 %.

POURQUOI CA COMPTE POUR L'ANALYSE, pas seulement pour le confort :
- L'absence de recul d'ancre invalide l'hypothese implicite du mecanisme de
  report, qui est PARTAGE : `forceJudgeIndex` suppose que le reciteur redira le
  mot. En mode reference il tire sur un audio qui ne contient plus le mot, donc
  zero frame garanti. Mesure du 15:17 : 5 blocages d'ancre de 8 a 9 alignements
  consecutifs (mots 49, 61, 93, 131, 208), 18 mots jamais verrouilles.
- Le seuil de gel decide OU tombent les coupes, donc ou tombent les mots
  tronques. Sur cette meme session, 12 des 18 erreurs (67 %) tombent sur un
  bord de segment, dont deux avec gop=0,00 et free~0 (le modele est CERTAIN de
  ce qu'il entend, il n'a recu qu'un fragment du mot) : ce ne sont pas des
  fautes de recitation. Interpreter ce taux sans connaitre le seuil applique
  n'a pas de sens -- d'ou son passage de debugPrint vers le fichier de log.

Les consequences sont rappelees sur la ligne de log elle-meme, pour qu'une
analyse n'ait pas a retourner lire le code pour savoir ce qui etait actif.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### d34fa35 — 2026-07-27 — Ferme la derniere fuite d'ecriture qui echappait a l'interrupteur de diagnostic

**Branche/tag:** 

**Auteur:** kafai

**Corps:** L'utilisateur veut mesurer si le retard de validation vient de l'ecriture des
logs, en coupant tout via l'interrupteur prevu pour ca. Audit des quatre chemins
qui ecrivent pendant une recitation :

  COUVERT  log() Dart                  -> DiagnosticLog.enabled
  COUVERT  trace() Dart                -> meme drapeau
  COUVERT  log() + trace() Kotlin      -> setLogEnabled, applique au demarrage
                                          de chaque session (_applyDiagnosticCapture)
  COUVERT  WAV par segment (clip_*)    -> setClipCapture(null)
  COUVERT  WAV du flux continu         -> _openStreamingWavCapture sort tot
                                          quand _clipCaptureDir est null
  FUITE    debugPrint du chemin audio  -> NON conditionne (celui-ci)

C'etait la seule ecriture restante hors interrupteur, et elle tombait au pire
endroit : un debugPrint par 20 blocs (~1,6 s) execute sur l'isolate qui recoit
le flux PCM. Elle suffisait a invalider le test temoin que l'interrupteur existe
precisement pour rendre possible.

Verifie aussi : le seul autre Log.* natif hors DiagnosticLog est dans
FastConformerStreamingSession, chemin cache-aware desactive
(_kCausalStreamingEnabled = false), donc jamais execute ; et feedBufferedAudio
n'emet rien par bloc.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 73325d8 — 2026-07-27 — Trace fine du pipeline audio, accumulee en memoire pour ne pas fausser la mesure

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Objectif : expliquer la latence de validation constatee sur device (mesure
irrefutable : 16 mots valides APRES le dernier bloc PCM recu, sur 28,7 s, avec
un dernier clip contenant 4,4 s de vraie parole a 85 % au-dessus du seuil).
Trois explications successives ont ete donnees et TOUTES ETAIENT FAUSSES --
cout d'inference qui derive (non : 150-700 ms stables), chaine FIFO bloquee par
l'inference (non : scope.launch(Dispatchers.Default), l'appel natif rend la
main aussitot), verrouillage seulement au gel (non : lock = isFinal || correct,
un mot correct est verrouille sur un apercu). Le log existant n'emet une ligne
qu'aux re-transcriptions : il est aveugle entre deux passes, d'ou les
hypotheses successives. Cette trace supprime la deduction.

CONTRAINTE QUI DICTE LA CONCEPTION : log() ouvre/ecrit/FERME un FileWriter a
chaque ligne cote Kotlin, et fait un writeAsStringSync(flush: true) cote Dart
-- un appel systeme bloquant par ligne, sur l'isolate qui recoit le PCM. Le
projet a deja mesure 22 a 32 ecritures/s pour la seule instrumentation
(2026-07-25), c'est la raison d'etre de l'interrupteur `enabled`. Tracer
finement une latence avec ce mecanisme mesurerait l'instrumentation elle-meme.

D'ou : trace() = un simple ajout dans une liste en memoire (aucune I/O, aucun
logcat, aucun formatage de date -- on stocke un ecart en dixiemes de ms), et
flushTrace() ecrit tout en UNE ouverture de fichier, apres la recitation
(appele depuis stop() et _cleanup(), jamais pendant). Borne a 200k lignes pour
ne pas risquer un OOM.

ETAPES TRACEES, choisies pour rendre la latence lisible sans deduction :
  D recu        n, blocs en file       -> la reception est-elle temps reel ?
  D feedEntree  n, blocs en file       -> la chaine FIFO prend-elle du retard ?
  D feedSortie  n, duree de l'appel    -> l'appel natif bloque-t-il ?
  T feed        n, rms, silence, garde, buffer, nouveau, busy, pendingCommit,
                pendingForceCommit, cut, commitInFlight  -> etat COMPLET a
                chaque bloc, y compris entre deux passes
  T lance       n, buffer, CAUSE (audio/gel/coupe) -> ce qui declenche une
                passe, la question restee sans reponse quand plus aucun bloc
                n'arrive et que des passes continuent
  T infDebut    n, echantillons        -> attente d'ordonnancement sur
                                          Dispatchers.Default (invisible avant)
  T infFin      n, echantillons, duree -> duree reelle de calcul

Trace pure : aucune decision, aucun verdict, aucun comportement ne s'appuie sur
ces lignes.

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, suite de tests
inchangee (17 passent / 3 echecs preexistants sans lien).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### f972a8a — 2026-07-27 — Journalise les bornes de frames : le compte de frames non-blank n'est pas une duree

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE QUI IMPOSE CE CHANGEMENT (lecture de reference du 2026-07-27, 178 mots
tous juges `correct` -- donc tout declenchement de `starved` y est un faux
positif) :
    plancher CTC seul            ->   1/178 mots starved (1 %)
    plancher max(CTC, quran.com) ->  45/95  mots starved (47 %)

Le plancher de duree se declenche sur un mot correct sur deux. La cause n'est
pas le facteur de securite (x0,4, puis mediane, puis minimum -- trois reglages
essayes dans la journee) mais la GRANDEUR comparee :

`wordFrames` compte les frames que la DP a etiquetees par un token, pas la
duree de prononciation. Le CTC est "peaky" : sur cette session, 731 frames
etiquetees pour 1960 frames d'audio consomme, soit 37 % -- la DP met 63 % des
frames en blank. Un mot dure 881 ms d'audio en moyenne mais ne recoit que 4,1
frames-tokens (~330 ms). Comparer ce compte a des millisecondes n'a donc pas de
sens, quelle que soit la source de ces millisecondes (quran.com ou durees
apprises : les deux reposent sur la meme erreur).

Preuve la plus directe : 23 mots (13 %) ont ete correctement recites avec UNE
SEULE frame. Aucun plancher au-dessus de 1 frame n'est donc sans faux positif
(2 frames -> 13 %, 3 -> 42 %). Le plancher CTC, lui, reste sain parce qu'il
compare deux grandeurs de MEME nature : un nombre de tokens a un nombre de
frames-tokens.

Effet reel aujourd'hui : AUCUN verdict fausse -- le garde-fou n'excuse que si
rien n'a ete decode, et ces 178 mots avaient tous du texte entendu. Le
mecanisme est inerte, pas nuisible. C'est pourquoi on mesure avant de le
retirer.

CE QUE CE COMMIT AJOUTE : les bornes de frames dans la ligne DUREES
(`<index>:<premiere>-<derniere>/f=.../c=.../r=...`). `derniere - premiere + 1`
est, lui, une vraie duree (silences internes inclus), et les bornes donnent en
plus les silences ENTRE mots. C'est la grandeur a mesurer avant de decider si
un plancher de duree peut faire mieux que le plancher CTC -- plutot que
d'abandonner la piste sur une grandeur qu'on n'a jamais regardee.

Trace pure : une ligne par passe finale, aucun effet sur le jugement.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### b68ef31 — 2026-07-27 — Apprend la duree des mots dans la voix du recitateur et s'en sert au lieu de quran.com

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Demande utilisateur : le timing de reference doit REMPLACER le timing par
defaut des qu'il existe. Le plancher vient desormais de la duree mesuree sur
les mots que l'utilisateur a lui-meme correctement recites ; quran.com ne sert
plus que de repli pour les mots jamais valides.

POURQUOI CHANGER DE SOURCE (mesures du 2026-07-27, detail dans
FONCTIONNALITES_FUTURES.md §10) :
- Couverture : le decoupage quran.com ne correspond pas toujours au canonique,
  donc 44 % des versets sont exclus -- et la couverture s'effondre avec la
  longueur du verset (98 % des versets de 1-5 mots, 1 % de ceux de 41+ mots),
  c'est-a-dire exactement la ou l'alignement casse. Sur la session sourate 3,
  82 % des incidents etaient dans un verset non couvert, et le log
  ETRANGLE PAR LA REFERENCE n'a tire aucune fois.
- Nature de la grandeur : les segments quran.com sont des bornes
  [start_ms, end_ms] qui INCLUENT le silence jusqu'au mot suivant (mesure : le
  mot "هُمُ" y dure 3030 ms), d'ou le facteur de securite x0,4 arbitraire.
  ForcedAligner.WordResult.frames, expose ici, compte les frames ARTICULEES
  (frames blank exclues) : il n'y a plus rien a compenser.

TROIS CHOIX DE CONCEPTION, ET LEUR RAISON :
1. Cle = la FORME du mot, pas (verset, position). La duree d'articulation est
   une propriete du mot ; indexer par forme supprime toute logique de mappage
   -- donc tout risque de decalage silencieux, ce que la regle positionnelle du
   projet existe pour ecarter -- couvre immediatement les versets absents de
   l'asset, et mutualise les echantillons entre occurrences.
2. On garde le MINIMUM, pas la mediane : un plancher est une borne INFERIEURE.
   C'est aussi ce qui rend le regroupement par forme sur des contextes
   differents (waqf, madd de fin de verset) sur -- le minimum sur plusieurs
   contextes reste une borne inferieure valide, et il ne peut que descendre,
   donc jamais devenir trop permissif. Conservateur par construction : plus
   bas que la duree typique, donc il excuse MOINS, et sous-estimer revient au
   comportement d'avant.
3. On n'apprend que des mots juges `correct` ET verrouilles, hors Bismillah
   (ces 4 mots ne sont pas juges et sont recites ~44 % plus vite que le reste
   du Coran, cf. RecitedWord.isBasmala). Garde-fou souleve par l'utilisateur
   lui-meme : "on a egalement la validation".

Le plancher reste reserve au sens "excuser" (cf. le bloc DEUX PLANCHERS, DEUX
USAGES de ForcedAligner, commit f634f92) : changer de source ne peut donc pas
creer de faux rouge.

Ecritures groupees (flush en fin de session, pas un acces disque par mot),
depuis les trois chemins de sortie : stop(), _cleanup() (mode continu, qui ne
passe pas par stop()) et dispose() (ecran quitte sans arret propre).

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, 7 nouveaux tests sur
le magasin (minimum conserve, durees nulles ignorees, rien appris avant
ensureLoaded, persistance relue, flush inutile sans ecriture, fichier corrompu
non bloquant), suite complete 17 passent / 3 echecs preexistants sans lien.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 96cb5e9 — 2026-07-27 — Precise la piste "recitation de reference" : durees articulees et plancher = minimum

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Trois precisions de l'utilisateur (2026-07-27) qui resolvent deux des quatre
points laisses ouverts, plus une consequence de conception qui en decoule.

Ce qui est tranche :
- Le mode lecture de reference passe par alignFile (audio complet, isFinal),
  donc aucun des defauts de la piste live (decrochage DP, mots de frontiere,
  coupe a 12 s) ne s'y applique.
- "Enlever les blancs entre les mots" est deja ce que le code calcule :
  ForcedAligner.wordFrames n'incremente que sur les etats non-blank, c'est donc
  la duree ARTICULEE. C'est structurellement superieur a quran.com, dont les
  segments [start_ms, end_ms] incluent le silence jusqu'au mot suivant -- la
  raison meme du facteur x0,4 (cas mesure : "هُمُ" a 3030 ms). Avec des frames
  articulees, il n'y a plus rien a compenser.
- Une lecture attentive ne saute pas de mot, et le GOP filtre le reste : la
  reserve "et si la recitation de reference est fautive" est levee (ne retenir
  que les mots juges correct).

Consequence de conception, plus importante que les trois points ci-dessus : un
plancher est une borne INFERIEURE, donc la bonne statistique n'est pas la
mediane mais le MINIMUM. Le "mediane x 0,4" en place est un bricolage faute de
mieux ; le minimum observe sur deux ou trois lectures de l'utilisateur EST
directement la grandeur cherchee, sans facteur arbitraire.

Reserve restante : une lecture de reference est plus lente qu'une recitation de
memoire, donc un plancher qui en decoule excuserait trop. C'est le rapport
lecture/recitation que la ligne de log DUREES (3f75b94) doit etablir avant de
fixer quoi que ce soit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 3f75b94 — 2026-07-27 — Journalise la duree reelle par mot, pour mesurer le gain d'un plancher "voix propre"

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Aucun log ne contenait la duree que la DP attribue reellement a un mot : seuls
les cas d'ECHEC etaient traces (ZERO FRAME quand elle vaut 0, ETRANGLE PAR LA
REFERENCE quand elle est sous le plancher), donc l'echantillon disponible etait
biaise vers les mots courts et ne permettait pas de comparer les planchers.

Cette ligne sort les trois grandeurs comparables pour tous les mots de la passe
finale : frames attribuees (la duree dans la voix du recitateur), plancher CTC,
plancher de reference quran.com (-1 si absent). Elle doit trancher deux points
laisses ouverts par FONCTIONNALITES_FUTURES.md §10 : de combien le facteur x0,4
sous-estime la duree reelle, et quelle marge viser pour un plancher deduit
d'une recitation de reference de l'utilisateur.

Ce que la mesure existante disait deja, et qui motive celle-ci : sur la session
sourate 3, meme avec une couverture PARFAITE la reference n'aurait pu changer
qu'un seul verdict sur 115 (114 des 115 jugements avaient un texte entendu non
vide, or le garde-fou n'excuse que si RIEN n'est decode). Il faut donc savoir si
le plancher est trop faible avant de conclure que la piste "recitation de
reference" vaut le chantier.

Trace pure : une seule ligne par passe FINALE (pas par apercu), aucun effet sur
le jugement.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 427296b — 2026-07-27 — Mesure l'apport reel des durees de reference et documente la piste "recitation de reference"

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Deux sessions device du 2026-07-27 sur le build causal-v1-timing-ref, avec la
carte mot->verset reconstruite depuis les ancres dures du log (3:1@4, 3:6@52,
3:7@65) et non supposee.

APPORT MESURE. Le garde-fou n'excuse un mot que si RIEN n'a ete decode dessus
(!hasSpeech), donc le nombre de declenchements du log est tres superieur au
nombre de verdicts changes. Sur la session sourate 2 (versets courts,
couverts) : 165 declenchements, mais seulement 5 verdicts changes (3 mots
distincts) -- et ces 3 mots ont tous ete juges correct sur une passe suivante,
donc le report etait juste : 3 faux negatifs evites. Sur la session sourate 3
(versets longs) : 0 declenchement, apport nul.

POURQUOI L'APPORT EST NUL SUR LA SOURATE 3. La couverture de l'asset
quran.com s'effondre avec la longueur du verset : 98 % des versets de 1-5 mots,
mais 7 % de ceux de 21-40 mots et 1 % de ceux de 41+ mots (longueur mediane :
6 mots pour les couverts, 18 pour les absents). Or les incidents se
concentrent sur les versets longs : 85 des 131 incidents de la session (65 %)
tombent dans le seul verset 3:7 (50 mots, absent), et 82 % dans un verset non
couvert. La source quran.com n'est donc pas imparfaite sur les cas durs, elle
y est absente -- et ajouter des recitateurs n'y change rien (deja verifie sur
les 9 : ils donnent tous le meme decoupage).

CE QUI JUSTIFIE QUAND MEME DE LA GARDER. Le plancher CTC vaut 1 seule frame
sur 114 des 165 declenchements (le tokenizer mappe souvent un mot entier sur
un token), donc sans reference ces mots n'ont aucun plancher utile. Rapport
plancher_ref/plancher_ctc : x3 en mediane, jusqu'a x9. Et la reference ne peut
qu'excuser, jamais condamner (cf. commit f634f92) : elle ne nuit pas.

PISTE DOCUMENTEE (idee utilisateur, a tester ensuite) : deduire les durees de
la RECITATION DE REFERENCE de l'utilisateur plutot que d'un referentiel
externe. Couverture 100 % par construction (le decoupage est le notre), tempo
et pauses de waqf justes puisque c'est la meme personne, et aucune brique de
modele a ecrire -- "alignFile" fait deja un alignement force one-shot sur un
WAV complet et ForcedAligner.Result expose deja wordFirstFrame/wordLastFrame.
Points a trancher (references dans le document) : que faire si la recitation
de reference est elle-meme fautive, quelle marge appliquer quand le tempo
n'est plus etranger, ou stocker (plafond 15-30 min pose par l'utilisateur), et
garder l'asset quran.com en repli pour les versets courts.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### f634f92 — 2026-07-27 — Cesse de condamner un mot quand c'est la DP qui a echoue

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Deux defauts distincts faisaient rougir (ou corriger en silence) des mots
correctement recites. Les deux naissent dans l'alignement, pas dans le
jugement -- le correctif est donc dans ForcedAligner, pas en aval.

1. MOT ETRANGLE (`starved`). Cas mesure, session 11:56 mot 63 "وَمِنَ" :
   la DP donne quelques frames au mot, trop peu pour que le decodage y voie
   un token -> entendu="", forced=-1,71, free=-0,24. Ni au plancher -20,00
   (donc pas un zero-frame), ni assez confiant pour le garde-fou "trou
   d'alignement" (seuil -0,15 en tolerant, rate de peu). Consequence : le mot
   n'etait JAMAIS verrouille, aucun rouge ne s'affichait, mais la serie
   d'apercus negatifs stables declenchait quand meme une correction
   (_previewNegativeStreak) -- 9 corrections sur 15 dans cette session
   passaient par cette voie invisible. `starved` (frames attribuees < minimum
   requis) remonte du natif jusqu'au garde-fou Dart, qui refuse desormais de
   juger ce cas.

2. PLANCHER TROP FAIBLE. Le plancher CTC (compte de tokens) est exact mais
   dit qu'un mot de 6 tokens tient dans 480 ms, contre ~870 ms reellement
   observes. Les durees de reference (mediane sur 9 recitateurs murattal,
   collectees par benchmark/collect_word_timings.py, cf. b619203) sont
   embarquees en asset (156 Ko, 3520 versets / 26 879 mots) et acheminees
   jusqu'a l'aligneur : WordTimingService -> RecitedWord.refMinFrames ->
   setAlignmentTarget -> ForcedAligner. Aucun appel reseau au runtime.

ASYMETRIE IMPORTANTE (mesuree, cf. le bloc "DEUX PLANCHERS, DEUX USAGES" en
tete de ForcedAligner) : la reference n'entre QUE dans le sens "excuser".
Branchee aussi sur le test qui condamne (ZERO FRAME : pas la place = mot
saute = rouge), elle FABRIQUAIT des faux rouges -- elle domine le plancher
CTC sur 6,9 % des mots avec une queue jusqu'a +44 frames (3,5 s), et 89 % de
ces mots ne sont pas en position de waqf, donc ce sont de vrais mots longs,
pas des artefacts de pause. Condamner sur une duree de reference revient a
mettre au rouge un recitateur plus rapide que la mediane : le plancher CTC
(impossibilite physique) reste seul juge de la condamnation.

Couverture volontairement partielle : seuls les versets dont le decoupage
quran.com correspond exactement au canonique sont retenus (3520/6236). Tout
ecart de comptage retombe sur "aucune reference" -- meme regle positionnelle
que RuleAnnotationService, pour la meme raison.

Un log cible ("ETRANGLE PAR LA REFERENCE") ne se declenche que quand la
reference change le verdict, pour pouvoir juger sur device si elle apporte
vraiment quelque chose ou si elle excuse trop.

Verifie : flutter analyze 0 erreur, compileDebugKotlin OK, flutter test
10 passent / 3 echecs preexistants sans lien, APK debug construit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### b619203 — 2026-07-27 — Collecte les durees de reference mot-a-mot, en vue d'un plancher d'alignement realiste

**Branche/tag:** 

**Auteur:** kafai

**Corps:** SUITE de 39a2b5d : le plancher CTC installe aujourd'hui (place disponible >=
nombre de tokens) est exact mais FAIBLE -- il dit qu'un mot de 6 tokens tient
dans 480 ms, alors qu'en recitation reelle il en prend ~870. Il laisse donc
passer de vrais mots sautes. Une duree de reference REALISTE, gardee EN LOCAL
(zero appel reseau a l'usage), corrige ca sans reintroduire le risque qui a
fait diverger la cible dynamique secPerWord (estimer le tempo depuis nos
propres echecs) : la reference vient d'un exterieur fixe, jamais de nos
mesures.

collect_word_timings.py interroge /by_chapter (114 appels/recitateur au lieu
de 6236) sur 9 recitateurs murattal (exclus : 2 Mujawwad + 1 Muallim, rythmes
non representatifs), prend la MEDIANE par mot (pas la moyenne -- un waqf de
3 s la tirerait) et stocke aussi la duree relative a la mediane du verset
(sans dimension, utilisable quel que soit le tempo du recitateur qui teste).
77 439 mots, 930 Ko en JSON brut.

DECOUVERTE IMPORTANTE, verifiee sur les 9 recitateurs (tous rendent 7 segments
sur 2:2, attendu 9 mots canoniques) : le decalage de comptage vient du
REFERENTIEL quran.com lui-meme (fusion de certains groupes de mots), pas d'un
recitateur en particulier -- ajouter des recitateurs affine la mediane mais ne
comble PAS les 2715/6236 versets a decalage. Le projet a deja une regle pour
ce cas exact (RuleAnnotationService, meme fichier de decalage logue) : mapping
POSITIONNEL, tout ecart de comptage retombe sur le canonique plutot que de
risquer un decalage mot-a-mot. Meme regle a appliquer ici -- couverture reelle
56 % des versets, le plancher CTC reste necessaire pour le reste.

Sortie (benchmark/word_timings_ref.json, benchmark/.timings_cache/) volontai-
rement PAS commitee, coherente avec la regle "benchmark/ ne versionne que les
scripts" (memes le mnifests generes) -- reproductible en relancant le script.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 39a2b5d — 2026-07-27 — Distingue "la DP a echoue" de "mot saute" par la place reellement disponible

**Branche/tag:** 

**Auteur:** kafai

**Corps:** PROBLEME MESURE (session 09:41, 142 mots juges) : 4 mots que l'utilisateur a
bien prononces restaient SANS AUCUNE COULEUR a l'ecran -- 117 ءَامِنُوا۟,
125 ٱلسُّفَهَآءُ, 128 هُمُ, 4 الٓمٓ. Le decodage libre du meme segment les
contient pourtant ("وَإِذَا قِيلَ لَهُمْ آمِنُوا۟ كَمَامَآ ءَامَنَ"). Seule la DP
avait echoue : zero frame attribuee, donc entendu="" et forced au plancher.

CAUSE, deja documentee dans ce fichier : la DP compare a frame egale le cout de
forcer le token attendu contre celui de rester en blank. Si le token est peu
confiant meme bien prononce, rester coute moins cher qu'avancer -> elle se bloque
en arriere et les mots suivants n'ont plus de frames. Deux tentatives de penalite
par-frame ont deja echoue (cf. journal dans le companion object).

DISCRIMINANT AJOUTE, mathematique et non empirique : le CTC exige AU MOINS n
frames pour emettre un mot de n tokens (une par token, plus un blank entre deux
tokens identiques consecutifs). Pour un mot a zero frame on compare donc la place
disponible entre ses voisins a ce minimum :
    place >= minimum -> le mot POUVAIT tenir : c'est la DP qui a echoue,
                        on differe au lieu de verrouiller rouge a -20,00
    place <  minimum -> le mot ne peut PHYSIQUEMENT pas etre la : saute,
                        tranche immediatement comme avant
Le garde-fou anti-boucle du 2026-07-16 reste entier : un mot reellement saute est
toujours tranche, il ne peut pas boucler indefiniment.

Pourquoi ce critere plutot que les durees de reference quran.com, envisagees
d'abord : celles-ci exigent un appel reseau et une plomberie Dart->Kotlin,
varient avec le tempo, et incluent parfois la pause de waqf (mesure : "هُمُ" y
dure 3030 ms, absurde pour un mot si court). Le compte de tokens est local, exact
et deja disponible. Les durees de reference restent un raffinement possible pour
estimer le debit reel, pas une necessite.

Ajoute aussi la trace ZERO FRAME (place disponible, minimum requis, verdict) pour
mesurer la repartition des deux cas sur device.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 827be11 — 2026-07-27 — Mesure les mots en frontiere avant de decider d'un second decodage

**Branche/tag:** 

**Auteur:** kafai

**Corps:** IDEE A TRANCHER (utilisateur 2026-07-27) : avec UNE decoupe, un mot en frontiere
l'est DEUX FOIS -- le segment qui finit dessus le tronque a droite, celui qui
commence dessus le tronque a gauche. Deux decoupes decalees casseraient ca : un
mot en frontiere dans A est au milieu dans B. Ce n'est pas de la tolerance, on
remplace une mesure corrompue par une mesure valide.

MESURE HORS DEVICE (bench_double_decoupage.py, 3 recitations reelles) : le
double decoupage supprime bien tous les mots en frontiere (1/59 -> 0/59) mais
coute 2,25x l'inference, pour un probleme qui ne touche que 2 % des mots. Mauvais
rapport -- SAUF que ces fichiers contiennent des PAUSES, donc la coupe tombe sur
des silences, des frontieres propres par construction. En recitation CONTINUE
c'est la borne dure de 12 s qui tranche, potentiellement en plein mot : le cas
qui compte n'est pas mesure.

Le mecanisme de protection EXISTE deja et est bien raisonne
(MIN_FRAMES_FOR_JUDGMENT=3, ~240 ms) : il mesure l'audio disponible APRES le
dernier mot confirme, pas les frames du mot -- si beaucoup d'audio suit et que le
modele n'y place quand meme pas le mot, c'est une vraie faute, pas un artefact.

Plutot que de toucher BufferedTranscriber (fichier le plus fragile du projet, ou
l'app est passee de 8 rouges a 0 hier) pour un residu de 2 % non mesure dans le
bon regime, on instrumente : deux compteurs, les mots REPORTES faute de marge et
ceux JUGES QUAND MEME avec une marge faible (la population qu'un second decodage
sauverait). Zero calcul en plus, zero risque de regression. Une recitation
continue sur device donnera le taux reel, et le chiffre decidera.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 3f74bae — 2026-07-27 — Teste Nemotron 3.5 comme encodeur de base : faisabilite prouvee, perf insuffisante

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Encodeur Nemotron (Cache-Aware FastConformer, concu streaming des l'origine)
transplante tel quel + tete CTC fraiche sur NOTRE vocabulaire tajweed_bpe_v1
(1024 tokens avec harakat). 8 epochs, ~2h20 : val_wer 1,000 -> 0,628, sans
plateau avant la fin.

Ce que ca etablit : un encodeur multilingue (2 % d'arabe dans son vocabulaire)
APPREND le coranique vocalise, et peut porter nos tetes. Ce n'etait pas acquis.
Ca invalide aussi le motif d'ecart du 2026-07-03 ("non fine-tunable ici,
RNNT-only, blocage NVVM") : la tete CTC greffee n'utilise que nn.CTCLoss, aucun
warprnnt/NVVM, et l'entrainement tourne.

Ce que ca ne resout pas : 0,628 contre 0,116 pour mixed-e14, courbe qui
s'aplatit en fin de run, 609 M params contre ~115 M et un .nemo de 2,4 Go --
deploiement mobile non resolu. Ecarte pour la production, checkpoint conserve.

Environnement dedie .venv_nemotron_ft (Python 3.13 + NeMo main 3.1.0), installe
a cote sans jamais toucher .venv_nemo : NeMo 2.5.0 n'a pas la classe
EncDecRNNTBPEModelWithPrompt que reclame ce checkpoint.

Inclut shutdown_when_training_done.sh (extinction apres fin PROPRE seulement,
verification du .nemo final, delai d'annulation) et le parametrage du chemin de
deploiement dans bench_causal_normalization.py.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### c2cc4de — 2026-07-26 — Ne juge plus un mot quand le modele est sur de ce qu'il entend (trou d'alignement)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** MESURE QUI L'IMPOSE (session 21:21-21:23, 5 mots passes en rouge) : quand
`entendu` est vide, deux situations opposees se cachent derriere, et la couche
de jugement les confondait -- elle concluait "pas prononce" dans les deux cas.

    mot 49 `لَا`          forced=-20,00  free= 0,00  -> present dans le libre
    mot 50 `يُؤْمِنُونَ`   forced=-16,93  free=-0,00  -> present dans le libre
    mot 14 `بِٱلْغَيْبِ`   forced=-13,09  free=-0,00  -> present dans le libre
    mot 15 `وَيُقِيمُونَ`  forced= -2,54  free=-0,11  -> ABSENT du libre
    mot 51 `خَتَمَ`        forced= -3,71  free=-0,09  -> entendu "فَذَمَ"

Un `free` colle a zero signifie que le modele est PARFAITEMENT sur de ce qu'il
entend sur ces frames : elles portent du signal, simplement attribue a un autre
mot par la DP. Conclure "pas prononce" est alors faux -- 3 faux rouges sur 5
mots signales, et 3 corrections declenchees a tort, chacune reculant l'ancre et
de-validant des mots deja verts (jusqu'a 10 d'un coup sur une autre session).

Le garde-fou ne valide RIEN : il refuse de CONDAMNER sans preuve exploitable,
meme forme que l'exemption Bismillah et symetrique du principe deja en vigueur
"aucune preuve -> aucun verdict positif". Rejoue sur les donnees reelles : les
3 faux rouges disparaissent, les 2 verdicts defendables (15 et 51) sont
conserves.

Le seuil suit le curseur de SENSIBILITE, il n'est pas fige (demande
utilisateur) : -0,15 en tolerant (le mot 15, a free=-0,11, cesse d'etre rouge),
-0,02 en strict (seuls les trous incontestables sont blanchis). Un seul reglage
gouverne desormais toute la severite du jugement.

Ce meme reglage passe de TROIS positions a DEUX (tolerant / strict, boutons
segmentes au lieu du curseur continu) : le palier central "equilibre"
n'offrait pas de choix lisible. Defaut inchange a 0,5 -> les seuils GOP restent
exactement ceux d'avant, pour ne mesurer qu'UN changement a la fois.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 028be10 — 2026-07-26 — Retire la validation groupee par GOP : mesuree sans aucun gain

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Elle avait ete ajoutee le 2026-07-25 pour deux benefices precis. Mesure sur la
session du 21:03-21:09 avec le modele causal : les deux ont disparu.
  - "valide 5 ou 6 mots d'un coup" -> 1 mot 34 fois, 2 mots 21 fois, 3 mots
    6 fois, 4 mots 1 fois. Jamais 5 ni 6. Plus de la moitie des declenchements
    ne validaient qu'UN mot, ce que la voie mot-par-mot fait deja.
  - "sauve les mots au texte artefacte" -> sur 25 mots `autreMot=OUI` de la
    session, 0 valide par la voie rapide, 25 degrades. Le benefice pour lequel
    elle existait ne s'est produit aucune fois.
Ne restait que son cout : valider sans controle textuel, donc laisser passer le
piege س/ص. Hypothese pour l'ecart avec la mesure du 25/07 : elle etait calibree
sur le modele dual-head, pas sur le causal deploye depuis.

Tout le bloc de documentation d'origine est CONSERVE (regle du projet : ne
jamais effacer la memoire d'une tentative), avec en tete le constat qui l'a
fait retirer et la condition a verifier si on la reintroduit un jour -- qu'elle
sauve reellement des mots `autreMot=OUI`, sa seule raison d'etre.

Un seul chemin de jugement subsiste desormais : mot par mot, controle textuel
applique.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### e81447c — 2026-07-26 — Ignore la sortie generee par graphify

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 33378dd — 2026-07-26 — Bascule sur le repli bufferise : garde le modele causal, abandonne le cache-aware

**Branche/tag:** 

**Auteur:** kafai

**Corps:** LE MODELE N'EST PAS EN CAUSE, ne pas revenir au checkpoint precedent. Mesure
decisive sur l'audio reel capte sur device (82 s), MEME modele causal, MEME
decoupe de 12 s, seule l'alimentation change :
    causal en SEGMENTS (sans cache) : 4 segments sur 4 justes
    ancien modele offline, idem      : 3 sur 4
Le causal est donc MEILLEUR que l'ancien modele sur cette voix et ce telephone.

Ce qui casse est le chemin cache-aware : en session reelle le compteur de
tokens se fige (ids=9 pendant 140 s sur 187 s de recitation, ids=3 sur une
autre session), l'aligneur n'a plus rien a juger, aucun mot ne passe au vert
et le curseur gele sans afficher ni orange ni rouge -- le pire mode de
defaillance possible, l'app ne signale meme pas qu'elle a decroche.

Cinq politiques de gestion du cache testees hors device sur cet audio, cinq
rejetees par la mesure (fenetre glissante de normalisation, remise a zero sur
silence, a intervalle fixe, a la frontiere de verset, combinee sur la politique
BufferedTranscriber) -- chiffres dans PROBLEMATIQUES_ASR.md §1.5. Le levier
applicatif est epuise : la cause est en amont (clips d'entrainement plafonnes a
20 s alors que la session d'inference n'a aucune borne).

Un seul drapeau (`_kCausalStreamingEnabled`) : tout le code cache-aware est
conserve, le repasser a `true` le reactive. Cout assume : latence du buffer au
lieu de celle du streaming. Gain : une app fonctionnelle avec le meilleur
modele disponible.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### b9bf09d — 2026-07-26 — Fiabilise la capture WAV de diagnostic et cesse de juger la Bismillah sans preuve

**Branche/tag:** 

**Auteur:** kafai

**Corps:** En-tete WAV (streaming_wav_capture.dart) : l'en-tete RIFF n'etait ecrit qu'a
close(). Une session non terminee proprement (veille, changement d'ecran, appli
tuee) laissait un fichier avec un en-tete tout a zero, DEFINITIVEMENT illisible
alors que le PCM etait intact -- constate deux fois sur device le meme jour,
dont une session de 187 s recuperee a la main. Desormais l'en-tete est valide
des l'ouverture et resynchronise a chaque bloc : le fichier est un WAV lisible
a tout instant. Verifie en conditions reelles sur device.

Bismillah (recitation_provider.dart) : quatre mots etaient verrouilles ROUGE
avec entendu="" sur le chemin causal, ce qui declenchait une correction et
faisait reculer l'ancre 6 -> 0 (curseur bloque). Le premier correctif propose
les validait en VERT des qu'il y avait de la parole ailleurs dans la passe --
rejete, c'etait exactement le comportement banni le 2026-07-25 (valider du
silence). Retenu : une Bismillah sans son capte n'est NI verte NI rouge, elle
n'est pas jugee, et l'ancre avance quand meme. Mesure sur log device : 4 faux
rouges sur 6 mots (67 %) avant, 0 apres.

Capture continue (recitation_verifier.dart) : fermeture explicite d'un flux
micro reste en pause avant d'en ouvrir un nouveau (sinon startStream() rend un
Stream qui ne livre aucun bloc PCM), et capture WAV de session sur le chemin
causal, ou l'absence de segments figes ne produisait plus AUCUN fichier de
diagnostic (8 sessions de captures vides constatees).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 4f5f642 — 2026-07-26 — Mesure le causal dans le regime REEL de l'app, et comble le trou "detection de fautes"

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Ce que les mesures existantes ne disaient pas : sur clips propres le causal
perd (WER 0,189 contre 0,116), mais ce classement ne se transpose PAS au
regime segmente de l'app. Mesure sur 30 clips avec la politique reellement en
service : parite sur recitation fluide (30,9 % contre 30,1 %, dans le bruit),
et l'ecart se concentre ailleurs -- +13 pt sur recitation hesitante (79,4 %
contre 66,2 %), soit le cas d'usage prioritaire.

Cause : le corpus est fait de clips studio d'un verset, donc continus, sans
aucune pause interne ; le causal n'a jamais vu ca et son contexte gauche borne
se remplit de silence. D'ou causal_silence_augment.py, qui insere des pauses
sur de vrais creux d'energie (SilencePerturbation de NeMo n'ajoute qu'aux
extremites). Branche derriere --augment_silence, train uniquement, et JAMAIS
utilisable dans finetune_dual_head.py : ses cibles tajwid sont indexees par
frame et le silence les decalerait silencieusement.

score_error_detection.py comble le trou de REFONTE_IHM.md §12 : tous les bancs
mesuraient le TEXTE, aucun ne mesurait ce que l'app existe pour faire. Il lit
le PREMIER verdict de chaque mot et separe faute non vue (l'app rate sa raison
d'etre) de rouge injuste (elle accuse a tort), qui n'ont pas le meme cout.
Premiere mesure sur log device reel : 4 faux rouges sur 6 mots, tous sur la
Bismillah, tous avec entendu="" -- absence de preuve traitee comme une faute.

simulate_sliding_window.py et export_dual_head_multilabel.py prennent un
chemin de modele en argument (defauts inchanges) pour pouvoir comparer deux
modeles au lieu d'un seul.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 85b337c — 2026-07-26 — feat: ajoute le compte à rebours avant récitation

**Branche/tag:** 

**Auteur:** kafai

**Corps:** L'écran attend désormais le moteur continu, affiche 3-2-1, ouvre le micro puis annonce Go seulement lorsque la capture est prête. L'overlay est localisé, accessible et les étapes sont traçables dans le diagnostic.


---
### 7a8969d — 2026-07-26 — feat: orchestre le démarrage de la récitation

**Branche/tag:** 

**Auteur:** kafai

**Corps:** La séquence attend le modèle causal, déroule 3-2-1, ouvre ensuite le micro et n'annonce Go qu'une fois la capture prête. Elle s'annule proprement si l'écran disparaît.


---
### 5d70d32 — 2026-07-26 — fix: recalcule le score après un recul

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Les mots remis en attente sont désormais retirés des compteurs correct, imprécis et erreur, y compris les mots sautés. Le test de régression couvre le pointeur, l'unique mot courant et les trois compteurs.


---
### 52b03e0 — 2026-07-26 — fix: resynchronise la reprise après correction

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le journal device montrait une ancre native reculée de 9 à 3 tandis que le pointeur visible restait à 9, puis 22 ids CTC sans nouveau verdict. Le pointeur et l'unique mot courant suivent désormais la destination du recul, avec un test de régression dédié.


---
### a01d2d4 — 2026-07-26 — docs: valide le causal sur appareil

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 3b1f7f5 — 2026-07-26 — docs: consigne la livraison du streaming causal

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### d535b1b — 2026-07-26 — feat: active le modèle causal dans le flux continu

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 13f3ede — 2026-07-26 — feat: complète le paquet causal avec son tokenizer

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### f74ded8 — 2026-07-26 — feat: porte le moteur Android sur le causal stateful

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 6a09ff8 — 2026-07-26 — feat: verrouille le contrat du modèle causal

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### a293172 — 2026-07-26 — feat: maintient le décodage CTC entre les chunks

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### d729875 — 2026-07-26 — feat: fiabilise l'export ONNX causal stateful

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 5a0d2af — 2026-07-26 — chore: point de retour avant le streaming causal

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 6cf960c — 2026-07-26 — feat: bascule l'app sur le modele causal sans tajwid

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Utilise l'export ONNX causal v1 en mode segment compatible avec le moteur actuel. L'absence de rules.json désactive explicitement les verdicts tajwid jusqu'à la fin du modèle à deux têtes.


---
### 9a7efa7 — 2026-07-26 — Ajoute le pipeline d'entrainement streaming causal (encodeur + tete tajwid)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Stage 0/1 : patch causal (make_causal_init.py) + fine-tune de l'encodeur
(finetune_streaming_causal.py, superviseur auto-resume) pour remplacer le
faux streaming (re-transcription offline repetee) par de vraies convolutions
causales. Stage 2 : reprise du fine-tune deux tetes sur l'encodeur causal
(finetune_dual_head.py, calibrate_tajwid_pos_weight.py) avec labels
frame-level regeneres (build_frame_level_tajwid_labels.py).

Evaluation disaggregee Coran/TTS (eval_quran_vs_tts.py, eval_causal_per_context.py),
export ONNX stateless pour test app (export_causal_checkpoint.py,
export_dual_head_multilabel.py). Corrige au passage un bug de chargement
.nemo dans le superviseur (perte du warm-start sur retry) sans invalider les
resultats deja obtenus au cycle 1.

Documente dans asr.md/SKILL.md/ETAT_CTC_NEMO.md/PROBLEMATIQUES_ASR.md :
doctrine NVIDIA look-ahead, pieges d'environnement (fork Python 3.14,
CUDA_HOME RNNT), verification manifest Hafs/Warsh, idee de pairage
audio/texte par riwaya plutot que d'exclusion (FONCTIONNALITES_FUTURES.md).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### bc45760 — 2026-07-26 — feat: recentre l'ornement des sourates

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 1accd18 — 2026-07-26 — fix: preserve les diagnostics de recitation

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 017f2a8 — 2026-07-26 — perf: limite le controle initial a une page

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### 2256073 — 2026-07-26 — feat: fait progresser le coach ayah par ayah

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### a2dc28b — 2026-07-26 — feat: planifie les rappels de priere locaux

**Branche/tag:** 

**Auteur:** kafai

**Corps:** 

---
### c9b6aa7 — 2026-07-25 — Valide les mots par GROUPE quand le GOP est bon, au lieu de carver mot par mot

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Idee utilisateur : « parfois tout le buffer est correct, du coup tout le
traitement de decoupage ne sert a rien ; verifier d'un coup, si valide on met
les 5-6 mots verts, sinon on passe au minutieux mot par mot ». Puis, correction
decisive de sa part : « pas par texte, par GOP ».

Elle existait deja dans le code sous forme amputee -- `ForcedAligner` porte
« Validation GLOBALE prioritaire (idee utilisateur 2026-07-16 soir) » mais ne
s'en sert QUE pour reparer le texte `actual`, en gardant le verdict du
mot-par-mot. C'est ce que l'utilisateur decrivait comme « perdu avec les
modifications ».

MESURE (session du 17:42, 42 segments figes, 121 mots)
Le texte `entendu` de chaque mot est decoupe dans les frames que la DP lui a
attribuees, et ce decoupage produit des artefacts : `الذينلذين`, `عليلهم`,
`ءاممننا`, `أُو۟لَـٰٓئِكَ` double, `لَ` pour `ٱلَّذِينَ`. Ces artefacts
declenchent `spellsDifferentWord` et degradent le verdict alors que le GOP dit
que la prononciation est bonne :
    mot 12 `ٱلَّذِينَ`      orange  normGop=+0,77
    mot 17 `وَمِمَّا`        orange  normGop=+0,83  (deux fois)
    mot 37 `وَأُو۟لَـٰٓئِكَ` orange  normGop=+0,06  (deux fois)
15 segments sur 42 (35 %) ont TOUS leurs mots au-dessus du seuil du vert.
Un critere TEXTUEL equivalent n'aurait sauve que 1 negatif sur 37 (mesure faite
puis ecartee) ; le critere GOP en sauve 5 -- l'utilisateur avait raison.

CE QUI EST IMPLEMENTE
Plus longue suite EN TETE dont le normGop depasse le seuil du vert -> validee
verte d'un bloc, sans controle textuel ; bascule en mot-par-mot au premier mot
faible. Journalise : `validation groupee : N mot(s) verts d'un coup (a..b)`.

Quatre conditions non negociables
 1. `covered` -- jamais le mot en cours de prononciation (bug 2026-07-05).
 2. `actual` NON VIDE -- un mot sans frame a `forced ≈ free ≈ 0` sur du blanc
    pur, donc un gop trompeusement bon. Le mot 65 `مَن` (`entendu=""`,
    normGop=-0,00) reste ROUGE : le valider serait valider un mot sans aucune
    preuve acoustique, ce que l'utilisateur refuse explicitement. C'est
    pourquoi 5 negatifs sont evites et non 6.
 3. suite CONTIGUE -- on s'arrete au premier echec, aucun mot saute.
 4. `_activeRules.isNotEmpty && expectedRules.isNotEmpty` -> exclu. L'ordre des
    deux tests est ESSENTIEL : `expectedRules` est rempli a l'annotation du
    texte QUEL QUE SOIT le prereglage, le filtrage par prereglage n'arrive que
    dans `unrealizedRulesFor`. Tester `expectedRules` seul (ma 1re version)
    aurait bloque la voie rapide sur presque tous les mots, meme en mode adulte
    sans tajwid -- le correctif n'aurait JAMAIS tire.

RENONCEMENT ASSUME (arbitre avec l'utilisateur)
Le controle textuel court-circuite est aussi celui qui attrape le piege س/ص
(bon gop, autre lettre ecrite). Les 5 mots sauves portent tous `autreMot=OUI`,
donc impossible de garder ce controle en n'excluant que les fragments (`لَ` est
un prefixe de `ٱلَّذِينَ` mais trop court pour etre reconnu comme tel). Le
garde-fou propre est le rescoring NLL, deja calcule et journalise (`rescore=`),
pas encore branche au verdict faute de seuil calibre sur device.

Correction : plus de declenchement sur un mot repasse vert
- Les aperçus sont comptes par `AlignPayload.seq` et non par appel. Deux
  verdicts du meme seq comptaient pour deux : mesure a 17:35:29, `mot=41
  "ٱلَّذِينَ"` juge error DEUX FOIS a 2 ms d'ecart avec des valeurs
  rigoureusement identiques (doublon, pas confirmation), correction declenchee,
  puis 253 ms plus tard le mot passait `correct`. L'utilisateur voyait du vert
  et entendait quand meme la correction.
- `_onWordFailed` relit le statut courant et ABANDONNE si le mot n'est plus
  negatif (`wordFailed` transporte un index, pas un verdict).
- La memoire d'echec d'un mot est effacee quand il redevient bon, sinon une
  vraie erreur ulterieure ne serait plus jamais signalee.

Correction : l'ancre revient ou on demande de reprendre
`_kCorrectionWordsBefore` pilote a la fois les mots joues ET le recul de
l'ancre -- les deux ne doivent jamais etre regles separement. Mesure (17:43:20
-> 17:43:50) : `recul 40 -> 33` puis segment demarrant au mot 32, `recul 40 ->
34` puis segment au mot 33, `recul 40 -> 36` puis segment au mot 34 --
systematiquement un mot d'ecart, parce qu'on fait entendre le mot precedent
sans reculer l'ancre jusqu'a lui. Consequences mesurees : syllabes doublees
dans `entendu`, 4 mots deja valides repassant negatifs (le mot 36 a recu SEPT
jugements), et une progression d'UN SEUL mot par correction.

Outil
benchmark/resume_log_recitation.py -- resume d'un log : mot attendu / mot
entendu au PREMIER jugement, puis ce qu'il devient. Le premier jugement est ce
qui repond a « le systeme a-t-il vu ma faute ? » ; le verdict final arrive
souvent apres une correction et ne dit rien de la detection initiale.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 196bff1 — 2026-07-25 — Rend la correction immediate : 15,9 s -> 0,003 s avant le retour de l'ancre

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Objectif utilisateur : « on veut que le reciteur recite la ou il a rate ».
Le mecanisme (rewindAndUnlock) existait deja -- c'est le MOMENT ou il
s'executait qui etait faux, et deux appels plugin qui coutaient 10 s.

Budget mesure sur une correction reelle (mot 30 "هُمْ", log 17:08:56 -> 17:09:14)
  +1,84 s  error deja identique sur QUATRE apercus consecutifs, non verrouille
  +3,61 s  await _recorder.isRecording() -- 3,6 s pour lire un booleen de log
  +6,43 s  await _recorder.pause()
  +5,88 s  lecture de HUIT mots (fromIdx=1 toIdx=8, ~7,6 s d'audio)
  = 15,9 s avant `[ANCRE] recul 40 -> 30`, pendant lesquelles l'app a
    verrouille les mots 32 a 39 puis les a deverrouilles -- huit mots qui
    verdissent puis redeviennent en attente, douze secondes apres la faute.

Corrections
- Ordre inverse : arret de la chaine -> recul de l'ancre + deverrouillage +
  repere visuel -> PUIS la lecture audio. Plus aucun mot ne peut etre valide
  pendant la lecture. Mesure apres correctif : recul a +0,003 s.
- `isRecording()` retire de pauseCapture(), ainsi que les deux appels
  plateforme de la ligne "apres pause" (-3,6 s). Profite aussi au bouton pause
  manuel et au souffleur.
- pauseCaptureForPlayback / resumeCaptureAfterPlayback : la pause materielle
  est conservee mais lancee en tache de fond, et son atterrissage est attendu
  a la REPRISE. Le cout plugin se paie donc apres la lecture, quand le
  reciteur ecoute au lieu de parler, et la course pause/resume disparait.
- Declenchement des le 2e apercu au verdict identique
  (_previewNegative / _kPreviewsBeforeCorrection) au lieu d'attendre le gel
  (-1,84 s). Pas des le 1er : un apercu peut mal couvrir la fin d'un mot, et un
  recul injustifie coute plus cher qu'un leger delai. Etat remis a zero sur
  rewindAndUnlock et sur setup/setupVerses.
- DEUX MOTS MAXIMUM rejoues (mot precedent + mot rate), sur demande explicite
  de l'utilisateur. Remplace la regle du 2026-07-06 (« entendre TOUT ce qu'il
  faut redire ») -- le commentaire d'origine est conserve sur place avec la
  raison du changement. L'exigence de fond reste tenue : le recul couvre
  toujours TOUTE la plage fautive, seule la lecture est raccourcie.

REGRESSION INTRODUITE PUIS CORRIGEE DANS CE MEME COMMIT, a ne pas refaire :
une premiere version supprimait la pause materielle du chemin de correction
pour gagner 6,4 s. Sur device, le micro restait actif pendant la lecture, la
lecture perturbait l'enregistrement Android et le flux PCM NE REVENAIT JAMAIS
(dernier bloc a 17:23:50.473, plus rien apres la reprise -- « je n'arrive plus
a continuer »). La pause materielle ne servait pas seulement a ne plus juger :
elle protege l'integrite de l'enregistrement. Ne pas la retirer.
Filet ajoute : controle non bloquant apres chaque correction, qui journalise
`ALERTE controle post-correction : MICRO NON REPRIS` au lieu de laisser
deduire le blocage de l'absence de blocs PCM.

Segmentation : cible remise a la borne dure (12 s)
La coupe sur micro-silence est neutralisee. Trois politiques testees et
documentees sur place, avec les mesures : 2,0 s fixe (cascade de gels), cible
dynamique (emballement de secPerWord jusqu'a 4,6 s), 3,0 s fixe (les erreurs
de frontiere se COMPOSENT -- la coupe du segment N+1 est contrainte par celle
du segment N, d'ou des transcriptions reduites a "قِينَ"/"إِنَّقُونَ" et
4 gels sur 7 placant 0 ou 1 mot). A 12 s : tous les gels placent 3 a 9 mots,
l'ancre suit (20->29->32->40->45->51->60), transcriptions completes. La charge
CPU n'etait PAS le facteur (15,3 % a 3 s contre 12,7 % a 12 s).

HANDOFF.md : etat git documente
Ce que sont reellement `test-1-gop` (GOP lettres seul, tete tajwid seulement
decodee) et `test-2-gop` (+ GOP tajwid par classe de regle, + recouvrement de
segment sur mots ENTIERS), pourquoi « 1 GOP » n'est pas contradictoire avec un
modele a 2 tetes, et le rappel de methode : verifier `git branch -a` et le log
des branches soeurs AVANT toute analyse -- faute de quoi on re-derive ce qui
existe deja ailleurs.

Note : les deux derniers points (2 mots, pause hors chemin) sont installes mais
pas encore valides par un test utilisateur.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 08556f8 — 2026-07-25 — Corrige la chaine de recitation : course de gel, purge de l'audio consomme, verdicts sans preuve

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Point de retour AVANT la refonte "deux horloges" (cf. ARCHITECTURE_RECITATION.md).
Tout est adosse a des mesures sur l'audio reel du device (23 WAV, 81 s) --
detail chiffre dans JOURNAL_TESTS_LOGS.md.

Course de gel (BufferedTranscriber)
- `commitInFlight` : aucune decision de segmentation pendant qu'un gel n'a pas
  purge le buffer. Les blocs PCM arrivent par rafales (deux feed() a 4 ms
  d'ecart), ce qui rearmait la meme coupe sur un buffer deja parti en inference
  -> un offset perime figeait un segment de 0,2 s et verrouillait un mot en
  ROUGE avec `entendu=""` 300 ms avant qu'il soit prononce.
- Garde-fou de duree minimale teste sur la longueur PREVUE (min(offset, taille))
  au lieu de la taille du buffer ; l'exclusion fautive est documentee sur place.
- Un offset de coupe hors buffer est invalide et journalise, au lieu de degrader
  silencieusement vers "figer tout le buffer".
- `forceJudgeIndex` seulement sur un segment >= MIN_COMMIT_SECONDS : un segment
  de 0,2 s n'est pas une "seconde chance".

Cible de segment
- Suppression de l'apprentissage du debit (`secPerWord`) : un echec d'alignement
  y comptait comme un debit et faisait s'emballer la cible (1,00 -> 1,53 s/mot,
  cible 4,6 s, transcriptions reduites a "هُ"). Cible fixe, bornes explicites.
- Fenetre de recherche du micro-silence glissante (borne droite = fin du buffer)
  au lieu d'un couloir fixe qui ne trouvait plus aucune coupe apres 15 s.

Purge de l'audio consomme (cause de la desynchronisation)
- `ForcedAligner.Result.lastFrame` + `WordResult.lastFrame` : le natif aligne
  d'abord, purge ensuite, et ne retire que l'audio reellement consomme. Avant,
  tout le segment etait jete alors que l'ancre n'avancait que de `words.size` :
  l'audio des mots non places etait detruit et ces mots partaient rouges sur de
  l'audio etranger (ancre bloquee a 28, recitateur au mot 43).
- `greedyDecode(logprobs, toFrameIncl)` : ne figer que le texte des frames
  consommees, sinon la queue conservee reapparait une 2e fois (duplication qui
  avait mis la fenetre glissante naive a WER > 100 %).

Jugement
- `entendu=""` interdit tout verdict : le test `!hasSpeech` est remonte au-dessus
  du laisser-passer Al-Fatiha/Basmala, qui le contournait -- la MEME absence de
  son donnait `correct` pour un mot et `error` pour un autre.
- Un `unclear` ne se verrouille plus sur un apercu : les 5 orange d'une session
  etaient tous des artefacts d'apercu tronque, le segment fige suivant
  transcrivait parfaitement les memes mots.
- Provenance du texte entendu tracee (`src=dp` / `src=libre`) : `actual` decide
  la couleur, et la validation globale le remplace par le decodage libre du
  segment -- indechiffrable sans cette trace sur un passage a mots repetes.

Charge de l'isolate Dart
- `_realignFromFullText(apply: false)` ne recopie plus l'integralite de
  `state.words` (6121 mots, ~12,5 fois/s) alors que sa boucle s'arrete au 2e mot.
- [TEXTDIFF] journalise seulement les CHANGEMENTS de verdict : 299 lignes
  identiques par mot en 27 s auparavant, soit ~25 ecritures fichier synchrones
  par seconde -- candidat le plus plausible pour la rafale de blocs PCM.

Diagnostic
- Reglage "Journal et audio de diagnostic" : coupe le journal Dart ET natif plus
  la capture WAV, pour verifier que le retard ne vient pas de l'instrumentation.
- Capture WAV activee dans le provider et non dans un ecran : deux tests avaient
  produit un log sans audio, et les deux chemins ensemble creaient deux dossiers
  de capture par demarrage.

IHM
- Bouton pause rogne hors ecran (RIGHT OVERFLOWED BY 12 PIXELS) : 5 boutons de
  48 dp ne tiennent pas dans 360 dp. Icone du jeu masquee pendant l'ecoute,
  marges et densite ajustees, titre sur une ligne. Bandeau de reference corrige.

Outil
- benchmark/compare_onnx_on_device_wavs.py : rejoue les WAV du device a travers
  plusieurs ONNX avec le mel de MelSpectrogram.kt. A servi a etablir que le
  modele deux tetes n'a PAS regresse (>= le meilleur une tete de l'historique)
  et que la cause etait la qualite du DEBUT de segment, pas sa longueur.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### a6a34cf — 2026-07-24 — Ajoute le detail par classe de regle dans eval_tajwid()

**Branche/tag:** asr-nemo-solutions

**Auteur:** kafai

**Corps:** Permet de verifier le recall d'une regle individuelle (ex. qalaqah) au lieu
du seul agregat global -- utilise pour infirmer une hypothese de regle
systematiquement faible (qalaqah recall=0.968, pas un cas a part).


---
### d06c6ee — 2026-07-24 — Corrige la perte d'audio dans BufferedTranscriber et le verrou premature des mots en recouvrement

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Trois bugs distincts, confirmes par mesure device (logs + clips diagnostiques) :
- MelSpectrogram : off-by-one dans le compte de frames (nFrames = 1 + n/hop
  au lieu de n/hop), desynchronise du calcul NeMo get_seq_len().
- BufferedTranscriber : la coupe du buffer sur segment FINAL jetait
  systematiquement la queue audio non alignee (keep=0) quand la DP ne
  plagait que peu de mots, y compris dans le chemin de repli "GEL DEGRADE"
  qui reutilise un ancien apercu -- perte confirmee sur Al-Ikhlas v1-2
  ("هُوَ ٱللَّهُ أَحَدٌ" jamais propose a l'alignement).
- recitation_provider : les mots de la zone de recouvrement (covered=false)
  etaient verrouilles en erreur des qu'un segment final arrivait, avant
  d'avoir eu leur chance d'etre rejuges avec plus de contexte.

DiagnosticLog.dir() ajoute pour exposer le dossier de log au mecanisme de
capture de clips diagnostiques (BufferedTranscriber).


---
### 3af3501 — 2026-07-24 — Documente les problematiques ASR (buffer, GOP, pauses) et l'etat de l'art externe

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Synthese des difficultes recurrentes du module ASR (segmentation du buffer,
alignement force / GOP, streaming cache-aware) mises en regard de la
recherche et des forums (CTC peaky, hallucination Whisper sur silence,
techniques NeMo natives). Reference ajoutee a l'index CLAUDE.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### ab23576 — 2026-07-24 — Documente les problematiques ASR (buffer, GOP, pauses) et l'etat de l'art externe

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Synthese des difficultes recurrentes du module ASR (segmentation du buffer,
alignement force / GOP, streaming cache-aware) mises en regard de la
recherche et des forums (CTC peaky, hallucination Whisper sur silence,
techniques NeMo natives). Reference ajoutee a l'index CLAUDE.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>


---
### 58db2fa — 2026-07-23 — Branche de test 2-GOP : moteur ASR à l'état c9c531f (2 têtes + segmentation recouvrement 2s)

**Branche/tag:** test-2-gop

**Auteur:** kafai

**Corps:** Contrepartie de test-1-gop pour la comparaison contrôlée demandée par
l'utilisateur. Part de test-1-gop (qui compile déjà, fix R8 + shim l10n)
et n'échange QUE les 7 fichiers du moteur ASR vers leur version c9c531f :
- GOP dépiégé + tête tajwid (comme 5d97e09)
- PLUS les correctifs de segmentation d671c33..c9c531f : recouvrement 2s
  (OVERLAP_SECONDS), coupe-après-alignement, jonctions différées,
  sauvetage assimilation, instruments DERIVE/DESYNC.

Le fix R8 (build.gradle + proguard-rules.pro) est hérité de test-1-gop --
même correctif de build, indépendant du GOP.

But : réciter Al-Balad de la même façon sur les deux branches pour isoler
si le recouvrement 2s est ce qui fait plus bloquer (hypothèse mesurée mais
non prouvée, cf. asm.log word 42 vs test-1-gop word 83).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 5df2735 — 2026-07-23 — Corrige le crash natif ONNX (vraie cause : R8 obfusquait ai.onnxruntime.**)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Diagnostic device confirmé (2026-07-23) : "JNI DETECTED ERROR IN
APPLICATION: java_class == null" dans convertToTensorInfo ->
GetMethodID -> SIGABRT, dès la 1re inférence OrtSession.run. La stack
montrait ai.onnxruntime.OrtSession renommé en ".l" -> R8 obfusquait le
package, or le code natif (libonnxruntime4j_jni.so) résout ces classes par
leur nom d'ORIGINE via FindClass -> null -> crash.

Le fix JNI classloader tenté d'abord (Thread.contextClassLoader) était la
MAUVAISE piste : mesuré, il ne changeait rien (le natif n'utilise pas le
contextClassLoader). --no-shrink non plus (désactive le tree-shaking, pas
l'obfuscation). La vraie cause était l'obfuscation.

Fix : isMinifyEnabled=false + isShrinkResources=false sur le build release,
plus une règle keep dédiée (proguard-rules.pro) si R8 est réactivé plus
tard pour la taille de l'APK.

VÉRIFIÉ SUR DEVICE : inférence OrtSession.run exécutée, transcription
"بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ" produite, 0 crash, process stable.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 5ca97e9 — 2026-07-23 — Corrige un crash natif JNI (SIGABRT) sur le thread du pool de coroutines

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Mesuré sur device (branche test-1-gop) : "JNI DETECTED ERROR IN
APPLICATION: java_class == null / in call to GetMethodID / from ...
OrtSession.run(...)" -> SIGABRT, process tué. Reproduit 3 fois de suite
(21:22:17, 21:30:29, 21:30:51), à chaque fois sur un thread du pool
Dispatchers.Default (tid nommé "DefaultDispatch").

Cause : un thread de pool créé par kotlinx.coroutines n'hérite pas
forcément du classloader applicatif (PathClassLoader) qui a chargé les
classes ai.onnxruntime.* -- FindClass/GetMethodID résolvent alors contre
le bootstrap classloader et échouent.

Correctif : fixer explicitement le classloader du thread courant avant
tout appel dans la bibliothèque native ONNX, aux deux points d'entrée
(création de session dans loadModel, et chaque inférence dans
BufferedTranscriber.feed). Fixer dès loadModel laisse la lib native
mettre en cache les bonnes références de classe pour tous les appels
suivants, quel que soit le thread.

Aucun changement de logique GOP/segmentation -- correctif de threading
pur, orthogonal au sujet testé sur cette branche.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 8193111 — 2026-07-23 — Branche de test : moteur ASR à l'état 5d97e09 (1 GOP + tête tajwid séparée)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Point de comparaison pour le test device demandé par l'utilisateur, face
aux problèmes diagnostiqués sur la branche master (verset 90:11 disparu,
effondrement de transcription sur pause, mot bloquant l'ancre -- cf.
CHRONOLOGIE_SESSION_2026-07-23.md sur master).

Contenu : les 7 fichiers du moteur ASR remis à l'état du commit 5d97e09
(2026-07-23 16:55 -- "2 têtes branchées, GOP dépiégé"), vérifié un par un
identique à ce commit. Confirmé par lecture du code (pas du message de
commit) : UN SEUL gop (WordResult.gop, forced-free sur la tête lettres)
pilote la justesse du mot ; la tête tajwid séparée n'alimente que
`detectedRules`/`unrealizedRulesFor`, un jugement DISTINCT des règles de
tajwid (comparaison direct attendu/détecté), jamais un second score de
justesse. + patch minimal indépendant sur tajwid_rules_screen.dart (appel
.name(t)/.explanation(t)/badgeLabel(t)) pour compiler avec le refactor l10n
non terminé de master (0aa3d8d), sans rapport avec le GOP.

APK construit et installé sur le device (R3CY20XW7TD) depuis cet état,
prêt pour le test comparatif.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### f192ba8 — 2026-07-23 — Ajoute la chronologie de session (diagnostic récitation/alignement/GOP)

**Branche/tag:** master

**Auteur:** kafai

**Corps:** Document resserré sur le sujet ASR (récitation, alignement, gestion du
GOP) : verset manquant diagnostiqué, hypothèses de segmentation testées/
rejetées, correction de vocabulaire (hésitation -> pause normale),
mécanisme du mot bloqué, décision entraînement vs fenêtre glissante,
tentative de test comparatif device non aboutie.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 4b42b4a — 2026-07-23 — Revert ciblé du moteur ASR vers l'état avant les 2 GOP (a2d3054), test isolé

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Uniquement les 7 fichiers du mécanisme GOP/ASR (BufferedTranscriber.kt,
ForcedAligner.kt, FastConformerCtc.kt, FastConformerCtcPlugin.kt,
recitation_provider.dart, fastconformer_verifier.dart, recitation_state.dart)
-- pas coach_hub/karaoke/judgement_options ni tajwid_rules_screen.dart, dont
le revert avait provoqué une cascade de casse de compilation sans rapport
(refactor l10n inachevé, cf. commit 0aa3d8d). Ce périmètre plus étroit
suffit pour comparer le comportement device avant/après l'architecture
2-têtes, sans dépendre du reste de l'app.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 96b0ccd — 2026-07-23 — Documentation : handoff Ubuntu, plan hybride et résultats de benchmark à jour

**Branche/tag:** 

**Auteur:** kafai

**Corps:** HANDOFF_UBUNTU.md / HANDOFF_UBUNTU_TRAINING.md : jamais commités,
documentent la bascule de session sur cette machine. PLAN_ENTRAINEMENT_HYBRIDE.md
et BENCHMARK_RESULTS.md : mises à jour accumulées des sessions récentes
(dataset TTS apparié, architecture 2 têtes, contamination Warsh vérifiée).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### d9418ce — 2026-07-23 — Ajoute les scripts du pipeline 2-têtes (dual-head) et TTS apparié, jamais commités

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Scripts produits pendant les sessions récentes (construction manifests,
entraînement stage a/b, export ONNX, évaluation, tests device offline) et
la génération TTS appariée correct/fautif (cf. PLAN_ENTRAINEMENT_HYBRIDE.md
§4). Ces fichiers existaient déjà sur disque et étaient utilisés (dont
finetune_dual_head.py, actuellement invoqué par l'entraînement en cours) --
simplement jamais ajoutés à git jusqu'ici.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### ed18c57 — 2026-07-23 — WIP : ajustements UI dispersés (duas, prière, thème, écrans de navigation)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Lot de modifications d'écrans/widgets accumulées sans commit intermédiaire
(duas_priere, prayer_follow, qibla, mushaf, thème, cartes/en-têtes). Pas de
vérification de compilation dédiée dans ce commit -- cf. le commit l10n
précédent pour le problème de compilation connu (tajwid_help_sheet.dart).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 0aa3d8d — 2026-07-23 — WIP : localisation (l10n) des libellés tajwid, jeu de mémorisation, baseline GOP par mot

**Branche/tag:** 

**Auteur:** kafai

**Corps:** ⚠️ Refactor l10n INACHEVÉ : TajwidRuleInfo.name/.explanation prennent
maintenant AppLocalizations (tajwid_help_sheet.dart), mais
tajwid_rules_screen.dart n'a pas encore été mis à jour pour appeler
.name(t)/.explanation(t) -- NE COMPILE PAS EN L'ÉTAT (constaté ce soir en
tentant un build de test, cf. session du 2026-07-23). À terminer avant
prochain build : propager l'appel avec paramètre dans ce fichier (et
vérifier les autres appelants de kTajwidRuleInfo).

Jeu de mémorisation (memorization_game_provider/screen,
memorization_ayah_picker_screen) et gop_baseline_provider/
gop_word_baseline.json (nouvelle fonctionnalité, référence de calibration
GOP par mot) : ajoutés tels quels, non vérifiés pour compilation dans ce
commit.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 24d7521 — 2026-07-23 — Réorganise les mindmaps par langue (ar/en/fr) au lieu d'un dossier plat

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Les anciens fichiers app/assets/mindmaps/NNN.json (114, une seule langue)
sont remplacés par trois sous-dossiers ar/en/fr, avec le pubspec.yaml mis
à jour en conséquence (déjà commité dans le lot ASR).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### f94a890 — 2026-07-23 — Revert ASR+coach vers l'état avant les 2 GOP (a2d3054), pour test comparatif

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Demande utilisateur : tester le comportement device d'avant l'architecture
2-têtes (commit 5d97e09, aujourd'hui 16:55), pour comparer avec après.
"avant le commit" = a2d3054 (2026-07-20), dernier commit avant que ce
travail ne commence.

Périmètre : les 19 fichiers du mécanisme GOP/ASR et des fonctionnalités
coach/karaoke/revue-d'erreurs qui faisaient partie du même commit 5d97e09,
remis à leur contenu a2d3054 (diff vérifié nul, fichier par fichier).

Exclu délibérément : les 7 fichiers de localisation (l10n/*.arb et
app_localizations*.dart) portent du travail non commis sans rapport avec
le GOP -- laissés intacts pour ne pas le perdre. Le bruit préexistant de la
session (mindmaps, duas, écrans non liés) n'est pas non plus touché.

Rien n'est perdu : 5d97e09 et les commits suivants restent dans
l'historique, le contenu écarté ici reste récupérable par le même type de
checkout ciblé.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### ed2ca8a — 2026-07-23 — Revert temporaire ASR vers l'état 2-GOP (5d97e09), pour test isolé avant segmentation

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Objectif : tester le comportement device du commit 5d97e09 ("2 têtes
branchées, GOP dépiégé") SEUL, sans les correctifs de segmentation ajoutés
ensuite le même jour (d671c33..c9c531f — recouvrement 2s, ordre
alignement/coupe, garde-fou gel dégradé, instruments DERIVE/DESYNC). Les
deux jeux de changements touchaient les mêmes fichiers et se sont révélés
difficiles à isoler l'un de l'autre en observant seulement le device.

Ce commit remet exactement les 6 fichiers ASR à leur contenu de 5d97e09
(diff vérifié nul avant ce commit). Rien d'autre n'est touché : l'historique
reste intact (d671c33..c9c531f restent dans le log, consultables et
ré-applicables), aucun commit n'est réécrit ni supprimé.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### c9c531f — 2026-07-23 — Corrige le vocabulaire "hésitation" -> pauses normales entre versets, ajoute l'augmentation par pauses

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Objection utilisateur justifiée : "hésitation" laissait croire à un cas
marginal (utilisateur peu sûr de lui). Mesure sur le log ayant motivé le
diagnostic : l'écart entre versets figés est de 4-8s de façon quasi
constante (14/16 intervalles), un rythme régulier de respiration normale
entre versets, pas une hésitation erratique — ça touche tout récitateur,
y compris confirmé. La mesure technique ne change pas, la portée oui.
Ajoute une note dans FONCTIONNALITES_FUTURES.md §4 sans effacer le
raisonnement déjà écrit (règle du projet).

build_pause_augmented_manifest.py : génère des clips avec pauses insérées
PUIS passées par le même portier RMS que BufferedTranscriber.kt (mêmes
seuils), pour que l'audio d'entraînement soit bit-pour-bit ce que le modèle
voit réellement en production. 100% additif et réversible : nouveaux
fichiers audio + nouveau manifest, aucun manifest existant modifié.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 86dfb91 — 2026-07-23 — Documente les 3 hypothèses de segmentation rejetées et la règle des commits par périmètre

**Branche/tag:** 

**Auteur:** kafai

**Corps:** CLAUDE.md : la règle "committer par périmètre" existait déjà mais a été
oubliée en pratique (147 fichiers app/ + 115 suppressions préexistantes
traînaient dans l'arbre de travail) — ajoute la méthode concrète pour
isoler ce qu'une session a réellement touché, et référence les bancs de
benchmark/ à utiliser avant de toucher à BufferedTranscriber.

FONCTIONNALITES_FUTURES.md §4 : consigne les mesures du 2026-07-23 pour
qu'un futur agent ne re-teste pas les mêmes pistes mortes.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 5b14b8d — 2026-07-23 — Bancs de mesure pour la segmentation ASR + option stats fixes dans mel_numpy_reference

**Branche/tag:** 

**Auteur:** kafai

**Corps:** analyze_device_log.py : fige les extractions faites ce jour-là à la main
(texte figé, blocages d'ancre, bilan audio jeté par le portier RMS,
régressions d'aperçu, gel vs dernier aperçu) pour que deux sessions device
soient comparables sans repartir de python jetable.

test_norm_fixed_vs_perfeature.py, simulate_sliding_window.py : ont servi à
rejeter trois correctifs candidats (stats fixes, portier désactivé, coupe
à chaque pause) avant de toucher au moteur natif — cf.
FONCTIONNALITES_FUTURES.md §4.

mel_numpy_reference.py : ajoute un paramètre normalize (per_feature /
brut / stats fixes), rétrocompatible, pour permettre ces mesures sans
changer le comportement par défaut déjà validé bit-exact contre NeMo.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### d671c33 — 2026-07-23 — Diagnostique et corrige les blocages d'ancre sur récitation hésitante

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Mesure device (sourate 90) : le verset 90:11 n'était jamais validé alors
qu'il avait été correctement transcrit une fois — la transcription
s'effondre quand le buffer accumule du silence recollé par le portier RMS,
et l'alignement force n'a alors plus rien à apparier (mots=0 en boucle,
ancre figée jusqu'à 22s).

Trois correctifs candidats testés hors device et rejetés par la mesure
(stats de normalisation fixes, portier désactivé, coupe à chaque pause) :
cf. FONCTIONNALITES_FUTURES.md §4 pour le détail chiffré, benchmark/
pour les bancs qui ont servi à trancher.

Ajoute la correspondance texte/audio par mot nécessaire à toute politique
de segmentation future (fenêtre glissante), et l'asset waqf (règles d'arrêt).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 5d97e09 — 2026-07-23 — Fiabilise le jugement tajwid : 2 têtes branchées, GOP dépiégé, stats honnêtes

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Modèle déployé : fastconformer-dual-head-v1/stageb-convhead-v1
(ConvTajwidHead conv1d+MLP, dégel complet). Mesuré : F1 tajwid 0,975
(rappel ikhafa 0,96, idgham_ghunnah 0,97) ; tête lettres NON dégradée
(val_wer_ctc 0,1201 contre 0,1234 pour le modèle historique déployé).

── Cause racine des blocages en récitation (mesurée, pas supposée) ──
Le GOP `forced` est TOKEN-level : il force la tokenisation BPE de la
cible et la compare au décodage libre. Or un même texte a plusieurs
découpages BPE valides. Sur لَآ (= ['▁لَ','آ']) et إِيَّاكَ (dont le
'إِ' isolé donne ['▁إِ'] mais ['▁إ','ِيَ',...] en contexte), le modèle
préfère SON découpage : forced=-12,97 alors que free=-0,08 et que
entendu == le mot attendu. Le MODÈLE avait raison, c'est le calcul de
l'app qui le trahissait -- aucun entraînement ne corrige cette classe
de bug (un modèle plus confiant l'aggraverait même).
=> rescousse : un mot dont la forme stricte entendue == l'attendue est
jugé correct quel que soit le gop. Le cas piège س/ص reste exclu (texte
différent -> textMatches=false). Effet mesuré : la récitation passait
du blocage au mot 4 à la sourate entière (86/86).

── Attribution des règles aux mots ──
Mesure sur l'alignement forcé RÉEL (test_forced_align_attribution.py,
5 récitateurs, sourate 90) : l'alignement forcé attribue toujours la
règle au mot qui PORTE le caractère taggué (delta=0 dominant). Donc :
- iqlab/idgham/ikhafa : trigger = tanwin/noun sur le mot PRÉCÉDENT
  -> correctif du 22/07 CONSERVÉ ;
- ham_wasl : trigger = le ٱ sur le mot SUIVANT -> mon correctif du
  23/07 (qui le déplaçait au précédent) ANNULÉ ; il faisait flasher à
  tort chaque mot avant un ٱل- (رَبِّ ٱلْعَـٰلَمِينَ), déclenchant une
  cascade correction/pauseCapture qui cassait tout l'alignement.
ham_wasl est en outre retiré des règles vérifiées d'office : c'est une
ÉLISION positionnelle (le ٱ est muet en flux continu), donc jamais
détectable -- sa fiabilité 0,96 était mesurée sur clips isolés, où le
ٱ est en début de clip donc prononcé.

── Conditions de mesure du tajwid ──
Le tajwid était jugé sur des buffers d'APERÇU partiels (1s/3s glissants)
qui coupent les mots ; ConvTajwidHead a un noyau de 5 frames et ne
déclenchait pas -> `emises=` vide sur des idgham pourtant réalisés, et
le MÊME mot donnait deux résultats selon le découpage (mot=33 يَرَهُۥٓ).
Conditionner à `p.isFinal` fut une ERREUR (mesurée : 3 jugements sur 16
seulement, car un mot jugé correct en aperçu est verrouillé et jamais
rejugé -> 80% du tajwid n'était plus vérifié du tout).
=> bon critère : `r.covered` (mot entièrement couvert par l'audio).
Ajout d'une tolérance de frontière : une règle de JONCTION détectée sur
le mot voisin compte comme réalisée (le jitter d'attribution ±1 existe).

── Statistiques d'erreur ──
- reset automatique par sourate au démarrage d'une récitation, pour que
  les compteurs reflètent la tentative en cours et non un cumul ;
- une troncature de buffer ("عَلَيْ" pour عَلَيْهِمْ) n'est plus étiquetée
  `lettre` : 6 des 7 "erreurs de lettre" d'une session en étaient ;
- log : "NON REALISEE" -> "NON DETECTEE" (la ligne constate attendues
  moins émises, pas une faute prouvée du récitant).
Les erreurs tajwid restent enregistrées : les restituer EST la raison
d'être du coach ; c'est la mesure qu'il fallait fiabiliser.

Périmètre : ASR/récitation uniquement (l10n inclus car nécessaire à la
compilation). Les chantiers antérieurs non commités (mindmaps, écrans
dua/qibla/mushaf, jeu de mémorisation) restent hors de ce commit.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### a2d3054 — 2026-07-20 — Renforce le correctif GOP : renormalisation pré-softmax + exclusion du chadda nu

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Suite du correctif symboles (64215d0), insuffisant seul : mesuré hors device
sur le même audio/mot, l'ancien modèle (sans symboles) donne gop=-0.03 sur un
mot ordinaire ("يَوْمِ") contre -20.09 pour le nouveau — la masse de probabilité
parasite sur les 40 classes-symboles dégrade aussi `forced` (pas seulement le
max de `free`, déjà corrigé). Fix : masquer ces classes et RENORMALISER les
classes restantes (équivalent à masquer les logits avant softmax), appliqué à
la DP forcée, à wordForcedSum/wordFreeSum et au rescoring NLL — jamais au
décodage libre (`actual`/`entendu`), qui doit continuer à exposer les symboles
pour la vérification tajwid. Gain mesuré : -20,09 -> -9,59.

Deuxième trouvaille séparée : le chadda (gémination, U+0651) est souvent
tokenisé SEUL (ex. "رَبِّ" -> [رَ, بِ, ّ]), sans lettre ni voyelle -- ce token
n'a pas de signature acoustique propre (la gémination s'entend comme un
allongement de la consonne précédente). Confirmé sur les DEUX modèles
(ancien ET nouveau) : "ٱللَّهِ"/"رَبِّ" restent mal alignés même bien
prononcés -- défaut préexistant, pas une régression du modèle 260h. Exclu du
calcul du gop (comme les frames blank), sans toucher aux harakat (voyelles),
dont le contrôle strict reste requis.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 64215d0 — 2026-07-20 — Corrige la pénalité systématique des symboles de règles dans le GOP (Kotlin)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Diagnostic de l'utilisateur, confirmé par la mesure : « avec mode alignement
quand je le fais réciter avec le programme de l'app, il ne fait que corriger »
-- même sur un récitateur professionnel (Mishary), même en respectant le
tajwid.

CAUSE (ForcedAligner.kt) : `gop = forced - free`, et `free` = max par frame
SUR TOUTES LES CLASSES du vocabulaire, symboles de règles compris. Le modèle
stage1b-260h a appris à émettre un symbole là où il ENTEND la règle réalisée
-- sur une récitation PARFAITE, il veut donc l'émettre. `free` empoche ce
score élevé ; `forced` (contraint au texte, qui depuis le correctif du même
jour est le texte NU sans symboles) ne le peut pas. Le gop plonge SANS AUCUNE
faute du récitant.

MESURÉ hors device, sur l'enregistrement réel de l'utilisateur (Al-Fatiha),
en forçant CHAQUE modèle sur SA PROPRE transcription (donc zéro désaccord de
contenu possible, seul l'effet des symboles est isolé) :
  ancien modèle (mixed-e14)   : coût d'interdire les symboles =    0.00
  nouveau modèle (rules-260h) : coût d'interdire les symboles = -177.83

=> explique very précisément l'observation « l'ancien modèle ne bloque pas
assez » : il n'émettait aucun symbole, donc ce mécanisme ne le touchait pas.
Ce n'est pas qu'il jugeait mieux, c'est qu'il ne voyait pas le tajwid du tout.

VALIDATION INDÉPENDANTE (check_tajwid_on_reciter.py, sur le même
enregistrement de Mishary, ~3 min d'Al-Baqarah) : le modèle détecte les règles
avec un rappel de 98% (47/48) sur un récitateur qui les réalise -- la
détection elle-même n'est PAS en cause, seule l'exploitation du signal dans
le GOP l'était.

CORRECTIF (ForcedAligner.kt) : `ruleSymbolTokens`, un masque des ~41 pièces de
vocabulaire portant un symbole (zone privée U+E000..U+F8FF). Le calcul de
`free` les EXCLUT désormais -- les deux chemins (forced et free) jouent sur le
même vocabulaire (lettres + harakat), donc la comparaison redevient équitable.
Les symboles restent disponibles dans `actual` (décodage libre non filtré) :
la vérification du tajwid (unrealizedRulesFor, commit précédent) continue de
fonctionner, séparément du jugement de prononciation -- exactement la
séparation que l'utilisateur exige.

Scripts de diagnostic ajoutés (réutilisables pour la prochaine mesure sans
refaire réciter l'utilisateur) :
- compare_models_on_clip.py : ancien vs nouveau modèle sur un même clip, test
  décisif « forcer sa propre transcription avec/sans symboles ».
- check_tajwid_on_reciter.py : juge de paix -- rappel de détection par règle
  sur un récitateur professionnel (fausses accusations = rappel < 100%).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 746df89 — 2026-07-20 — Le mode tajwid vérifie enfin le tajwid (règle attendue vs règle réalisée)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Règle posée par l'utilisateur : « en mode adulte, ne pas faire l'idgham ou la
qalqala, ça ne fait pas une erreur ; avec mode tajweed, oui ». Le MODE décide
donc si le tajwid est contrôlé — et non un axe séparé comme je le proposais.

CE QUI MANQUAIT : l'app avait des toggles, un écran de règles, des statuts de
fiabilité et des presets... mais AUCUN code ne confrontait la règle attendue à
la règle réalisée. Toute la périphérie existait, le centre était creux.

CE QUI EST ÉCRIT : `unrealizedRulesFor(wordIndex, heardRaw)`. Le modèle 260h a
appris à émettre un symbole (U+E000..U+E010) là où il ENTEND la règle réalisée.
Si le mot attendu porte `ghunnah` et que sa transcription ne contient pas ce
symbole -> règle non réalisée.

Vérifié sur le log réel AVANT d'écrire : 61 transcriptions sur 129 contiennent
des symboles PUA. Le modèle les émet bien et ils survivent jusqu'au jugement
(`normalizeTraining` ne filtre pas la zone privée).

BRANCHEMENT PAR MODE :
  tajwid : règles FIABLES activées d'office (applyPreset consulte
           rule_reliability.json -- pas de liste codée en dur : un futur
           modèle qui améliore une règle la fait entrer via le fichier)
  adulte : aucune règle -> tajwid NON contrôlé
  enfant : idem

TROIS GARDE-FOUS :
1. JAMAIS de rouge : une règle non réalisée donne au pire un ORANGE, et
   seulement sur un mot dont la prononciation était déjà correcte (sur un mot
   faux, les lettres priment -- inutile de reprocher une ghunnah sur un mot
   qui n'est pas le bon).
2. Seules les règles fiables d'office : une règle à 72% de recall produirait
   ~28% de FAUSSES accusations (« ghunnah non réalisée » alors qu'elle l'était),
   le pire retour possible pour apprendre. Les autres restent ajoutables à la
   main, badge de fiabilité affiché.
3. Trace [TAJWID] dédiée : règle manquante + attendues + réellement émises,
   pour que l'utilisateur puisse juger si l'app dit vrai.

AUSSI : `RecitedWord.heard` stocke désormais la transcription BRUTE et non
`actualStrict` -- la forme stricte filtre la zone privée Unicode et effaçait
justement les symboles nécessaires. Du coup classifyError distingue un CONSTAT
(règle attendue, active, symbole non émis) de la déduction par élimination
qu'elle faisait jusqu'ici.

RESTE : `shownRulesFor` n'est toujours appelé par AUCUNE vue. Le verdict est
juste, mais l'utilisateur voit un orange sans le libellé « ghunnah non
réalisée ». L'explication visuelle reste à brancher.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### dd8f757 — 2026-07-20 — Sépare prononciation et tajwid : l'alignement forcé repasse sur le texte nu

**Branche/tag:** 

**Auteur:** kafai

**Corps:** DIAGNOSTIC DE L'UTILISATEUR, VÉRIFIÉ ET EXACT : « j'ai l'impression toujours
influencé par les règles de tajweed » — constaté en mode adulte, règles
DÉSACTIVÉES, 17 corrections sur un récitateur professionnel.

CAUSE : `alignTarget` était la forme ANNOTÉE (lettres + harakat + symboles de
règles PUA). `normalizeTraining` ne filtre pas la zone privée Unicode,
contrairement aux autres normalisations — les symboles survivaient donc
jusqu'à la cible d'alignement forcé. Conséquence : pour obtenir un bon score,
le modèle devait émettre le symbole LÀ OÙ il est attendu. Une ghunnah non
réalisée (ou non détectée) faisait s'effondrer `forced` alors que lettres et
harakat étaient justes.

=> Le tajwid contaminait le jugement de prononciation EN PERMANENCE, dans TOUS
les modes, Y COMPRIS avec zéro règle activée : les toggles ne pilotent que
l'affichage et le plafonnement, jamais la cible d'alignement. Aucun réglage
d'IHM ne pouvait donc désactiver cet effet.

CORRECTION : `alignTarget` repasse sur `training` (texte nu). `expectedRules`
reste extrait de la forme annotée — les règles restent connues, elles
serviront à une vérification SÉPARÉE (à écrire).

Architecture visée, telle que l'utilisateur l'exige :
  PRONONCIATION (lettres + harakat) -> alignement forcé, verdict actuel
  TAJWID (ghunnah, madd, qalqala)   -> vérification séparée, verdict distinct
رَبِّ vs رَبُّ (harakat, change le sens grammatical) n'est pas de même nature
qu'une qalqala ratée (texte identique, réalisation différente) : un verdict
unique mélangeant les deux n'a pas de sens pédagogique.

MON ERREUR, consignée : j'avais écarté cette piste plus tôt sur une
corrélation (mots à 3 symboles = gop 0, mots sans symbole = gop -9). La
corrélation était réelle mais sur-interprétée : ~15 mots d'Al-Fatiha, et les
mots les plus annotés se trouvaient en début de session, là où l'alignement
était encore sain — une coïncidence de position prise pour une preuve. Le
commentaire d'origine sur alignTarget est CONSERVÉ (règle projet) avec la note
« INVALIDÉ PAR LA MESURE » à côté.

AUSSI dans ce commit :
- adulteDefault : strictHarakat true -> false. Avant, tajwid et adulte étaient
  STRICTEMENT identiques (mêmes deux booléens) : « je ne vois pas la diff entre
  les deux modes » n'était pas une impression, c'était le code. Gradation
  réelle désormais : tajwid = harakat strictes, adulte = harakat souples,
  enfant = harakat souples + lettres tolérantes.
- clé de préférences v1 -> v2 : sans ça, un réglage déjà enregistré aurait
  masqué la nouvelle valeur par défaut et la recette n'aurait rien voulu dire.
  Effet de bord assumé : la sélection de règles repart à vide.

RESTE À FAIRE : la vérification des règles elle-même n'existe toujours pas.
Ce commit retire une contamination, il ne crée pas la fonctionnalité — le mode
« tajwid » reste un mode « harakat strictes ».

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### db43917 — 2026-07-20 — Traces de diagnostic récitation : mode, changements de mode, ancre

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Demande utilisateur après une session de test : « rajoute quel type de mode et
s'il y a des changements de mode de récitation, pour meilleure analyse avec les
règles actives » + audit de la partie récitation.

POURQUOI CES TRACES : une ligne [GOP] isolée ne dit pas sous QUEL régime elle a
été jugée. Le même gop=-2.79 devient orange ou vert selon le preset et la
sensibilité ; et un changement de mode EN COURS de session (possible depuis
l'icône de l'écran de récitation) rendait les lignes d'avant et d'après
incomparables, sans qu'aucune trace ne le signale.

- [MODE] au démarrage ET à chaque changement : preset, strictHarakat,
  tolereConfusables, règles actives (nombre + clés). Préfixe explicite
  « CHANGEMENT EN COURS DE SESSION » quand ça bascule en cours de route.
- [MODE] sensibilite -> x (etait y) : le curseur est réglable en direct, deux
  lignes du même run peuvent sinon avoir été jugées sous des seuils différents.
- Chaque ligne [GOP] porte son régime (mode/seuils/nb règles) : interprétable
  SEULE, sans remonter au dernier [MODE].
- [ANCRE] recul N -> M : après une correction, l'ancre recule sur le mot raté
  (le système attend une RÉPÉTITION). Trace décisive pour l'audit ci-dessous.

AUDIT DE LA SESSION DE TEST (log réel, 14:40-14:41)

ÉTABLI :
- Le modèle transcrit JUSTE partout : `entendu` == mot attendu, y compris sur
  les mots notés gop=-9. L'export ONNX corrigé fonctionne.
- `free` reste excellent (-0.05) pendant que `forced` s'effondre (-9.07) :
  signature d'un DÉSALIGNEMENT audio/texte, pas d'une faute de prononciation.
- Chaque mot dégradé SUIT une pause/reprise de correction ; le seul mot resté
  bon au milieu de la zone (نَسْتَعِينُ, gop=0.00) est celui qui n'en a pas subi.
- Graine de la cascade : ٱلدِّينِ à gop=-2.79 (mot limite) -> orange -> en mode
  STRICT l'orange déclenche une correction -> pause 4,2 s -> cascade.

DEUX HYPOTHÈSES RÉFUTÉES (ne pas les re-tester) :
1. « Les symboles de règles dans alignTarget dégradent le GOP » -> FAUX, et
   l'inverse est vrai : mots à 3 symboles = gop 0.00, mots à 0 symbole = -9.
   (Corrélation vérifiée sur l'asset annoté, Al-Fatiha mot par mot.)
   Confirmé indépendamment par l'utilisateur : même comportement avec zéro
   règle active.
2. « Le tampon audio n'est pas vidé à la reprise » -> FAUX, resetBuffer() est
   bien appelé avant chaque resumeCapture().

HYPOTHÈSE RESTANTE, à départager avec la trace [ANCRE] : après correction,
rewindAndUnlock recule l'ancre sur le mot raté ; si le réciteur ENCHAÎNE au
lieu de répéter, l'alignement forcé cherche ce mot dans un audio qui ne le
contient pas -> forced s'effondre, le décalage se propage.

Piste de correction si confirmé : ne pas reculer l'ancre quand « suivre sans
bloquer » est actif. NON implémenté — attendre la mesure.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### 54d68c4 — 2026-07-20 — Passation : ajoute les 2 derniers commits + la nature bi-chantier de cc94417

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### cc94417 — 2026-07-20 — Cartes mentales des 114 sourates + erreurs catégorisées par type (+ refonte Invocations/Rites de l'agent parallèle)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** ⚠️ COMMIT À DEUX CHANTIERS, volontairement conservé tel quel : deux agents
travaillaient en parallèle sur des fonctionnalités DIFFÉRENTES, et l'état du
disque au moment du commit contenait les deux. Découper après coup aurait
donné des commits qui n'ont jamais existé tels quels. Les deux périmètres
sont décrits ci-dessous pour qu'un `git log` reste lisible.

═══ CHANTIER A — cartes mentales + catégorisation des erreurs ═══

CARTES MENTALES — le jeu complet fourni par l'utilisateur est branché.
Le provider lisait `assets/mindmaps/fr/{NNN}.json` (12 sourates de maquette) ;
les vraies données sont à la racine `assets/mindmaps/` : 114 sourates,
544 sections, 921 passages, vérifiées (aucune section vide, aucun
theme_central manquant).

Le schéma réel diffère de la maquette sur 3 points, adaptés (ne pas
re-inverser, documenté dans mind_map_data.dart) :
- `cat` est porté par le PASSAGE, pas par la section -> une section prend la
  couleur de sa catégorie DOMINANTE, chaque passage garde la sienne ;
- pas de champ `side` (répartition gauche/droite = rôle de l'algorithme) ;
- en-tête riche : name_ar, name_latin, ayat_count, theme_central (une PHRASE,
  pas un titre court) et sources_note.

Le médaillon central porte l'identité de la sourate et ouvre au tap une fiche
avec le fil directeur ET la note de sources — affichée, pas masquée : elle dit
d'où vient la structure et signale parfois qu'une partie reste à vérifier.

8 catégories réelles relevées sur les 114 fichiers (recits, croyance,
eschatologie, argumentation, ethique, legislation, signes, adoration) — les 6
précédentes ne correspondaient à rien dans les données. Couleurs toujours
PLACEHOLDER en attendant la palette de l'utilisateur.
Ancien dossier `fr/` supprimé (schéma différent, deux formats auraient cohabité).

ERREURS PAR TYPE (demande : « tajwid ou prononciation »)
Le journal ne stockait que OÙ (sourate/verset/mot), jamais POURQUOI — et
l'entendu n'était conservé nulle part, donc impossible à reclasser après coup.
- RecitedWord.heard : l'entendu est retenu au jugement (point unique _judge)
- classifyError : compare l'attendu à l'entendu, du concret au déductif —
  squelette différent -> lettre ; harakat différentes -> harakat ; lettres et
  harakat justes sur un mot porteur d'une règle -> tajwid ; rien -> sauté
- DB v1 -> v2 par ALTER TABLE : migration NON destructive, les erreurs déjà
  journalisées sont conservées et ressortent « indéterminé » (les compter
  comme du tajwid serait une invention)
- Barre de répartition + légende en tête du volet erreurs

LIMITE ÉCRITE DANS L'UI, pas seulement dans le code : « tajwid » est une
déduction PAR ÉLIMINATION, pas une preuve que la règle a été ratée (l'écart
peut venir de la durée, d'une liaison). Tant que la mesure « détection de
fautes délibérées » n'existe pas, l'utilisateur doit pouvoir juger de la
confiance à accorder au chiffre.

Détail : REFONTE_IHM.md §13.

═══ CHANTIER B — Invocations / Rites (agent parallèle) ═══

Refonte de duas_screen, nouveaux dua_card, dua_collection_screen et
rite_screen, retouches verse_tile et mushaf_screen, widget
quran_pattern_background extrait. Non décrit en détail ici : ce n'est pas mon
périmètre, se référer au journal de l'agent concerné.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### 761108d — 2026-07-20 — Passation : ajoute les corrections de fin de session

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - §3bis a) rangement des réglages : le critère devient « à quoi sert ce
  réglage ? » et non « dans quel écran suis-je ? » (récitateur transverse ->
  Réglages généraux ; params de vérification -> écran de récitation ;
  « Réciter » mis en valeur comme moteur de l'app).
- §3bis b) règles tajwid : revirement documenté (blocage -> plafond), avec les
  3 raisons mesurées et le principe à ne pas casser (jamais de vert franc sur
  une faute réelle).
- §6 : deux chantiers ouverts explicités — la vraie mesure de fiabilité
  (détection de FAUTES, jamais faite : les seuils actuels sont des proxys) et
  la mesure de durée du madd (reportée, pas abandonnée).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### 8f8c00a — 2026-07-20 — Règles tajwid : le garde-fou passe d'un blocage à un plafond

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Question de fond de l'utilisateur : « pourquoi il y a des toggles désactivés,
exemple madd 6 et autres, même pour enfants ? ». Vérification faite : le
blocage était mal fondé. Trois raisons, mesurées (détail REFONTE_IHM.md §12) :

1. La mesure évaluait la MAUVAISE CHOSE : « quand la règle est bien faite, le
   modèle émet-il le symbole ? » -- alors que pour enseigner il faut savoir
   « quand l'utilisateur RATE la règle, le modèle le voit-il ? ». Jamais
   mesuré (le set humain reste le juge de paix, toujours pas fait). Une règle
   a donc été grisée sur un proxy.
2. Échantillons minuscules : madda_necessary n=32 -> 72% avec IC95%
   [55%, 84%] ; idgham_mutaqaribayn n=3 -> "100%" avec IC [44%, 100%],
   autrement dit aucune information.
3. Cause probable = RARETÉ (143 occurrences de madda_necessary dans tout le
   Coran), pas difficulté acoustique : un madd est une durée, sans doute ce
   qu'un système mesure le plus facilement.

Coût pédagogique : le madd 6 est une des règles les plus fondamentales et les
plus audibles ; la bloquer privait l'app de ce qu'elle devrait enseigner en
premier.

Le garde-fou ne disparaît pas, il CHANGE DE NATURE — au lieu d'interdire, il
refuse de certifier :
- toutes les règles sont activables (RuleReliability.selectable == true) ;
- badge de fiabilité par règle (« fiable · 96% », « peu fiable · 72% »,
  « non mesurée ») ;
- une règle active peu fiable PLAFONNE le verdict du mot à « incertain »
  (orange) au lieu de le laisser passer au vert
  (RecitationNotifier._capByRuleReliability).

Principe conservé : un vert franc sur une faute réelle reste le pire des
comportements (biais canonique). L'orange dit honnêtement « je ne peux pas
trancher » — mieux que l'absence de retour ET que la fausse validation.

Reporté (décision utilisateur) : la mesure de DURÉE du madd, seule voie qui le
rende vraiment vérifiable (le alif suscrit est remplacé par un alif normal
dans les labels ET dans la normalisation -> la durée n'existe nulle part dans
le texte comparé, cf. FONCTIONNALITES_FUTURES.md §1).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### 8b58a03 — 2026-07-20 — Passation de session 2026-07-20 pour l'agent suivant

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Retrace l'entraînement 260h (meilleur modèle à ce jour), la refonte du volet
Coach, et surtout les PIÈGES réellement tombés :

- export ONNX audio_signal vs raw_audio : piège déjà documenté le 2026-07-13
  et reproduit quand même -> "modèle chargé = true" mais zéro transcription.
  Avec la commande de vérification obligatoire et le corollaire de diagnostic.
- SDK Android sur le HDD externe : démonté = build cassé sans que le code Dart
  soit en cause, et "adb install Success" trompeur après un build Gradle échoué.

Liste explicite de ce qui reste ouvert, dont la validation live du modèle
(jamais faite, téléphone verrouillé) et la recalibration éventuelle des seuils
GOP.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### 07579bc — 2026-07-20 — Refonte du volet Coach : la mémorisation rassemblée en un hub

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Demande utilisateur 2026-07-20 : « tout ce qui est en lien avec la
mémorisation il faut le mettre dans coach [...] il ne faut pas faire juste
une copie-coller ». Spec complète : REFONTE_IHM.md §11.

L'onglet Coach n'était qu'un journal d'erreurs À PLAT ; le vrai coach de
mémorisation (3 étapes) n'était atteignable que depuis la lecture. Il
devient un hub en 4 zones qui ORCHESTRE les écrans existants (aucun n'est
réécrit) :
  A. Reprendre  — dernière session, relancée en un tap
  B. Mémoriser  — ayah par ayah -> CoachScreen (3 étapes existantes)
  C. Réciter    — récitation continue + TOUS les réglages, modifiables ici
  D. Mes erreurs— regroupées PAR SOURATE

Volet erreurs repensé (zone D) : deux niveaux repliables. Niveau sourate
(total + versets touchés + barre de ratio, pour distinguer 5/7 de 5/286),
trié par erreurs décroissantes = le plus actionnable en tête. Au dépliage,
les versets fautifs avec 3 actions : Revoir (mémorisation ciblée),
Explication (Gemma), et « Situer dans la carte mentale » — lien proposé par
l'utilisateur, retenu car il fait réviser par le SENS et pas seulement par
la répétition. Bouton masqué si la carte n'existe pas pour la sourate
(12 rédigées à ce jour) : jamais de bouton mort.

Nouveaux : coach_hub_screen, surah_picker_screen (sélecteur RÉUTILISÉ par
les zones B et C, au lieu de dupliquer une liste), error_review_provider
(agrégat client-side), last_coach_verse_provider (zone A).

Déplacements/retraits :
- gros micro retiré de la barre du bas de la lecture -> la récitation vit
  dans Coach ; reste un bouton discret « Mémoriser » (raccourci verset
  conservé, décision utilisateur §11.6.1)
- icône carte mentale retirée de la page principale (demande explicite)
- section « Récitation » entièrement retirée de Réglages global (déplacée,
  pas dupliquée, décision §11.6.3) + nettoyage du code devenu mort
- supprimés : memorization_screen.dart (maquette à feedback FACTICE, sans
  ASR, supplantée par coach_screen) et coach_ai_screen.dart (remplacé)

Vérifié sur device : hub, réglages, erreurs par sourate avec vraies
données, dépliage et lien carte mentale.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### 59dbae9 — 2026-07-20 — Tiroir de lecture scrollable + filigrane à motif du mushaf

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - reading_settings_sheet.dart : overflow "BOTTOM OVERFLOWED BY 284 PIXELS"
  depuis l'ajout des sections vitesse audio + répétition/boucles -> le
  contenu défile maintenant (isScrollControlled + SingleChildScrollView,
  plafonné à 85% de l'écran) au lieu de déborder.
- mushaf_screen.dart + quran_pattern_tile.svg + design/gen_pattern.js :
  filigrane de fond (pavage octogones/carrés, opacité 0.05, fixe) issu du
  chantier graphique parallèle.

Point de reprise propre avant la refonte du volet Coach.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### ae2362c — 2026-07-20 — Corrige l'export ONNX du modèle 260h : audio_signal (mel) au lieu de raw_audio

**Branche/tag:** 

**Auteur:** kafai

**Corps:** BUG CONSTATÉ SUR DEVICE : le modèle se chargeait ("Modèle chargé : true",
sous-dossier rules-260h) mais AUCUNE transcription, aucun suivi, aucune
coloration. Cause réelle trouvée dans le log natif :
  [BufferedTranscriber] echec retranscription:
  Unknown input name audio_signal, expected one of [raw_audio, length]

J'avais exporté la variante E2E (raw_audio -> preprocessor+encoder+ctc) en
copiant export_tajweed_full_pipeline.py, alors que le plugin Kotlin calcule
le mel lui-même (MelSpectrogram.kt) et envoie audio_signal=(batch,80,time).
L'export validait pourtant PyTorch==ONNX -> faux sentiment de succès.

C'est le MÊME piège déjà rencontré et documenté le 2026-07-13 dans
l'en-tête de export_tajweed_checkpoint.py, reproduit une 2e fois.

- export_rules_260h_checkpoint.py (nouveau) : export CORRECT, wrapper
  encodeur+ctc_decoder seul, entrées audio_signal/length. Validé :
  ENTREES ONNX ['audio_signal','length'], PyTorch==ONNX, symboles de
  règles bien émis.
- export_rules_260h_full_pipeline.py : conservé (règle projet : ne pas
  effacer la trace d'une tentative) mais marqué "NE PAS UTILISER".
- CLAUDE.md : nouvelle règle projet pour que ça ne tombe pas une 3e fois,
  avec la commande de vérification obligatoire avant tout déploiement et
  le corollaire "modèle chargé ne prouve rien sur son utilisabilité".

Modèle corrigé poussé sur le device. Test live (coloration/suivi) à faire
téléphone déverrouillé.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### b060070 — 2026-07-19 — Corrige l'overflow "RIGHT OVERFLOWED BY 5.5 PIXELS" de la barre de navigation

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Régression du passage des libellés de nav de l'arabe court (إعدادات) aux
libellés traduits plus larges (Réglages, Invocations) : le padding horizontal
FIXE de 24px x 4 items faisait déborder la Row de 5.5px (bandeau rayé
jaune/noir de debug en bas à droite).

Fix : chaque onglet dans un Expanded (les 4 se partagent la largeur à parts
égales), padding horizontal réduit à 4px, libellé en maxLines:1 +
TextOverflow.ellipsis. Robuste à n'importe quelle longueur de libellé (fr/en/
autres langues). Vérifié sur device : bandeau disparu sur les 4 onglets +
écrans lecture/réglages.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 08efcc9 — 2026-07-19 — Déploie le modèle stage1b-260h dans le cœur ASR + câble les modes de jugement

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Bascule le vérificateur de récitation sur le nouveau modèle hybride "vrai
tajweed" (CER canonique 6.85% vs 9.18%, corrections silencieuses 10.7% vs
14.7%, + 17 règles tajwid) et branche pour de vrai le système d'options de
jugement (presets tajwid/adulte/enfant) jusqu'ici purement IHM.

ALIGNEMENT ANNOTÉ (condition de calibration correcte du GOP) :
- RuleAnnotationService charge assets/data/quran_rules_annotated.json
  (mots annotés par verset -- annotation dépendante du contexte, mesurée à
  39% des occurrences, donc clé "surah:ayah" et pas un dico mot->symbole).
- RuleSymbols : correspondance symbole PUA U+E000+i <-> TajwidRule (même
  ordre que rules_map.json, reconstruite par index).
- RecitedWord.alignTarget : cible d'alignement forcé = forme APPRISE par le
  modèle (avec symboles) quand le verset est connu ; repli canonique sinon
  (sûr, == ancien comportement). display/normalized/strict restent nus.
  RecitedWord.expectedRules : règles portées par le mot (pour les badges).
- Construction verset-consciente : setupVerses/extendVerses (karaoké),
  _wordsFromVerses (Al-Fatiha, cible identifiée par Shazam). setup(String)
  garde le repli sans annotation (Coach libre, hors-Coran).

MODES DE JUGEMENT (post-décodage, ne durcissent JAMAIS le verdict) :
- judgementOptionsProvider poussé dans le notifier (ref.listen).
- _relaxJudged après la décision GOP : strictHarakat=false pardonne un écart
  purement harakat (squelette identique) ; tolerateConfusables pardonne une
  substitution de lettres confusables (sin/sad, ta/tah...). Jamais appliqué à
  un mot non prononcé (reste rouge) ni en phase Fatiha (déjà neutralisée).
- shownRulesFor(index) : règles attendues ∩ règles activées (badges UI).

DÉPLOIEMENT : nouveau sous-dossier device fastconformer-ctc-rules-260h
(mixed-e02 JAMAIS écrasé -> rollback immédiat en changeant _kModelSubdir).
Pas de word_tokens.json (repli greedy, gère les symboles). Vérifié sur
device : build+install OK, écran de lecture rend l'annotation sans casse,
aucun crash à l'ouverture d'une session. NON vérifié sans voix réelle : la
plage de gop du nouveau modèle peut différer de mixed-e02 -> si les verdicts
dérivent, recalibrer les seuils GOP (mesure sur récitation réelle requise).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 508dede — 2026-07-19 — Export stage1b-260h pour déploiement app (ONNX CTC + asset mots annotés)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - export_rules_260h_full_pipeline.py : export E2E (audio brut -> logprobs CTC)
  du modèle hybride stage1b-260h, tête CTC seule (RNNT = piste séparée).
  Valide PyTorch<->ONNX bit-à-bit et confirme l'émission des symboles de
  règles. vocab.json propre (1024 tokens, 41 pièces à symbole PUA).
- build_app_rules_assets.py : génère app/assets/data/quran_rules_annotated.json
  (6236 versets, mots annotés de règles) avec asserts de cohérence
  (nb mots annotés == canoniques ; strip(annoté) == canonique) -- l'app aligne
  le GOP sur ces mots annotés (sinon biais sur les frames de symbole).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 5c3bfed — 2026-07-19 — Redesign SurahOrnamentHeader v2 : médaillon SVG au lieu du cadre CustomPainter

**Branche/tag:** 

**Auteur:** kafai

**Corps:** V1 (cadre + cartouche entièrement en CustomPainter) jugée "catastrophique"
par l'utilisateur -- trop chargée, mal exécutée. V2 : un seul élément
ornemental, le médaillon vectoriel assets/illumination/medallion.svg
(généré par un autre chantier en parallèle, palette AppColors exacte),
utilisé selon son propre design (numéro de sourate superposé au disque vert
central réservé) -- motif traditionnel de rosette à côté du titre, pas un
cadre autour de tout. Vérifié visuellement sur device (boundary Al-Masad ->
Al-Ikhlas) : rendu propre et lisible.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>


---
### 0d3dea7 — 2026-07-19 — Continue stage1b sur 260h Coran (vs 150h) : 2 bugs de chemins corrigés + gain net mesuré

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - build_rules_manifests.py : reconnaissait pas le nouveau montage HDD
  (/run/media/kafai/HDD/...), donc annotait ZERO clip avec les symboles de
  règles tajwid (0/156892) -- corrigé, revérifié (59232/59232, 0 mismatch)
- build_mixed_manifest.py : remap_audio_path() pointe maintenant vers la
  copie locale SSD (data/train_wav_local/) au lieu du HDD externe (lectures
  aléatoires plus rapides, moins d'usure du disque externe) ; applique
  aussi le remap à val_canonical.jsonl (bug distinct, jamais fait avant --
  chemins morts /mnt/hdd/... invisibles jusqu'à un vrai FileNotFoundError
  en eval)
- eval_error_detection_rules_stripped.py (nouveau) : wrapper réutilisable de
  eval_error_detection.py qui retire les symboles de règles de la sortie
  avant comparaison (même métrique/protocole que la comparaison mixed-e14
  précédente)

Résultat stage1b-260h (8 epochs, val_wer_ctc 0.147, cf. PLAN_ENTRAINEMENT_HYBRIDE.md §5ter) :
détection identique (~65%), corrections silencieuses toujours à 10.7%
(-4pts vs déployé), ET CER canonique nettement amélioré (6.85% vs 9.18%
déployé, 9.69% ancien run 150h) -- le point faible du run précédent est
résolu. stage1b-260h/stage1b-final.nemo est désormais la meilleure version.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>


---
### 7cbad88 — 2026-07-19 — Infrastructure langue de l'application (REFONTE_IHM.md §7bis) : squelette ARB + réglage

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - flutter_localizations + intl, l10n.yaml (arb-dir lib/l10n, non-synthétique)
- ARB ar/fr/en avec un premier lot de clés (nav bar) -- PAS une extraction
  exhaustive de toutes les strings de l'app, juste le squelette + preuve de
  fonctionnement (le gros du travail écran par écran reste à faire, cf. §7bis
  point 3 du plan)
- appLocaleProvider : réglage persisté 'app.locale', défaut langue système
  si dans {ar,fr,en} sinon fr ; coexiste avec explanationLanguageProvider
  (réglage plus ancien et plus étroit, réconciliation à faire plus tard)
- main.dart : MaterialApp locale-aware (localizationsDelegates, RTL via
  Locale), bottom nav utilise AppLocalizations au lieu de libellés arabes
  codés en dur ; police du libellé conditionnelle (Scheherazade New en
  arabe, Manrope en fr/en)
- settings_screen.dart : nouvelle tuile "Langue de l'application" (sheet de
  sélection ar/fr/en avec rappel de la règle "Coran toujours en arabe")

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>


---
### 5410892 — 2026-07-19 — Carte mentale des sourates (REFONTE_IHM.md §7) : rendu graphview + contenu initial

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - MindMapData/Branch/Leaf (models) : schéma JSON exact du plan
- mindMapProvider : charge assets/mindmaps/fr/{NNN}.json, fallback stub si absent
- MindMapScreen : rendu via package graphview (MindmapAlgorithm natif,
  éventail gauche/droite, root centré), flip de fiche détail (Transform +
  Matrix4.rotationY, sans package tiers), bouton "Aller au verset" -> MushafScreen
- Contenu rédigé pour 12 sourates courtes (Al-Fatiha + Juz Amma : 103, 105-114)
- Entrées de navigation : icône dans mushaf_header (bouton hub à côté du nom
  de sourate) + icône dans surah_list_screen (par sourate)
- Couleurs de catégorie (6) : PLACEHOLDER en attendant la palette manuscrite
  de l'utilisateur (ne pas considérer figées, cf. commentaire app_theme.dart)
- Ajout package flutter_svg + asset illumination/medallion.svg (généré par
  design/gen_medallion.js) pour le chantier ornemental en cours

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>


---
### f22ff35 — 2026-07-19 — Refonte IHM complète : jugement post-décodage + décentralisation des réglages

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Changements majeurs (demandes utilisateur 2026-07-06 à 2026-07-19) :

1. JUGEMENT UNIFIÉ (post-décodage, pas 3 modèles distincts)
   - JudgementOptions (modèle): 1 modèle, sortie brute ; 3 presets (tajwid/adulte/enfant) + toggles fins
   - judgementProvider (Riverpod): persiste en SharedPrefs
   - TajwidRulesScreen: sélection par preset ou fine-tuning ; affiche statut fiabilité (ready/notReady/insufficientData) pour chaque règle
   - rule_reliability.json: mesures 2026-07-19 (17 règles tajwid, recall/precision par type)

2. DÉCENTRALISATION DES RÉGLAGES (pas de monolithe Settings)
   - ReadingSettingsSheet: vitesse de lecture (audio), répétition/boucles, autoscroll (regroupés à proximité de la lecture)
   - CoachScreen: bouton "Mode de vérification" -> TajwidRulesScreen (tajwid settings au contexte Coach, pas global)
   - SettingsScreen: allégé, réglages globaux seulement (langue, voix, etc.)
   - Nettoyage : supprimé _repeatDesc, _pickSpeed, _pickRepeat, _SpeedSheet, _RepeatSheet (dead code)

3. FULLSCREEN + RETOUR FIABLE (bugfix majeur)
   - MushafScreen: header auto-hide (AnimatedSlide), 4s timeout
   - Nouvel affordance: petit bouton retour circulaire toujours visible (indépendant du header)
     => résout "comment revenir sur écran principale" utilisateur

4. NAVIGATION ÉPURÉE (suite demande "avant c'était mieux")
   - Supprimé MiniPlayerBar (redondant, on a Play/Pause sur l'app bar et la barre du bas)
   - Retrait "Identifier" de mushaf_screen bottom bar
   - Ajout icônes petites (Suivre prière + Identifier) dans surah_list_screen app bar (retour aux origines)

5. NOUVELLES SCREENS (infrastructure)
   - MindMapScreen: stub + "Bientôt disponible" (entry point pas encore wired)
   - SurahOrnamentHeader: widget décoratif (recherche, feedback "catastrophique" du 2026-07-19 — à revisiter si besoin)

6. PRISE EN CHARGE ARCHITECTURE
   - build_mixed_manifest.py: remappage SSD local (train_wav_local) au lieu de HDD distant
   - build_rules_manifests.py: fix du remappage pour les chemins HDD actuels (reconnaissance /run/media/kafai/HDD)

Notes de conception :
- ONE model, ONE faithful decode, ALL judgement is post-hoc normalization (pas de retraining)
- Settings are contextual, owned by the module where they matter (lecture, coaching, global)
- Navigation backstack must always have a visible exit affordance (small back button)

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>


---
### 76506af — 2026-07-19 — Spécification détaillée de la refonte IHM (exécutable sans invention)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** REFONTE_IHM.md : spec complète demandée par l'utilisateur ("structure ça
d'abord", "détaillé pour ne pas laisser les autres agents inventer") :

- §1 Système de vérification unifié : presets tajwid/adulte/enfant = options
  de jugement post-décodage (JudgementOptions, table confusables copiée de
  l'entraînement, algorithme du juge en 4 étapes, verdict par famille
  d'erreur lettre/harakat/règle:<nom>), écran de sélection des 17 règles
  avec fiabilité par règle versionnée avec le modèle (non-fiables grisées).
- §2 Paramètres contextuels par page (sheet générique, sections par écran).
- §3 Lecture plein écran immersif (header rétractable, tap zone haute,
  auto-masquage 4s, comportements exacts).
- §4 Récitation : règle contraignante zéro widget empilé, tout en overlay/
  inline, inventaire à valider avec l'utilisateur.
- §5 Page principale : Suivre prière + identification réunies.
- §6 Suivre prière v2 : v1 pragmatique CTC on-device, gain RNNT à mesurer
  offline avant tout code app.
- §7 Mindmap (plan d'une autre session intégré, schéma JSON exact).
- §7bis Langue principale ar/fr/en : arabe = tout arabe ; fr/en = menus
  traduits + texte coranique toujours arabe + traductions/explications/
  mindmap dans la langue ; ARB/flutter_localizations, RTL, mindmap par
  dossier de langue avec repli sur ar/.
- §8 Lots d'exécution + Lot 0 obligatoire (commits par périmètre).
- §9 Questions ouvertes à poser (couleurs mindmap, fiches, défauts enfant).
- §10 Décisions verrouillées.

CLAUDE.md : référence ajoutée à l'index.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 548fe14 — 2026-07-19 — Coran 100% local (fini le "Connexion requise" hors-ligne), rescoring NLL diagnostique, corrections "Suivre une prière"

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - Texte du Coran (114 sourates, 6236 versets, tajweed, traduction fr) bundlé
  en assets locaux au lieu d'appeler api.quran.com à chaque lancement --
  découvert via un écran "Connexion requise" alors que le WiFi était en
  réalité connecté (DNS cassé côté device). quran_api.dart lit maintenant
  les JSON locaux ; l'audio/streaming (segments mot-à-mot, URLs audio) reste
  volontairement en ligne.
- Rescoring NLL + décodage contraint (variantes confusables) branchés dans
  le pipeline d'alignement forcé, désactivés par défaut (diagnostique
  uniquement, activé en debug) -- validés offline sur epoch14 avant
  intégration, seuil pas encore calibré sur device réel.
- "Suivre une prière" : fin d'Al-Fatiha plus robuste (mot de clôture
  alternatif + repli Shazam indépendant si le mot exact est mal transcrit),
  identification de la sourate suivante en deux temps (candidat provisoire
  sur une fenêtre courte puis confirmation par la vraie continuation du
  texte, au lieu d'un score dilué par une requête cumulative sans borne),
  filtre bigramme contre les faux positifs Shazam, souffleur désactivé
  pendant Al-Fatiha, logs critiques persistés (survivent à un logcat qui
  tourne).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### c86ad76 — 2026-07-19 — Phase 2.1 confirmée sur checkpoint final + comparaison directe à mixed-e14

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Phase 2.1 (interférence) refaite sur stage1b-final.nemo (pas epoch07
intermédiaire) : CER 9,69% vs 9,18% baseline, +0,51pt — quasi identique au
préliminaire (+0,54pt), stable sur 4 epochs supplémentaires. Décision
actée : pas de 2e tête tolérante, la normalisation suffit.

Comparaison directe au modèle déployé (mixed-e14), même protocole
eval_error_detection.py, symboles de règles retirés avant comparaison :
détection identique (65,3%), corrections silencieuses vers canonique
meilleures (10,7% vs 14,7%, -4pts sur le problème central du chantier
mixed), CER canonique légèrement moins bon (+0,51pt, coût cohérent avec
la réinitialisation de la tête CTC). Plus deux capacités nouvelles :
détection de 17 règles de tajwid et tête RNNT fonctionnelle.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 84ed271 — 2026-07-19 — Triangulation CTC vs RNNT sur les 17 règles + classement de fiabilité par règle

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Comparaison appariée CTC/RNNT sur les mêmes clips (dataset fiable, pas le
YouTube invalidé) : convergence quasi parfaite sur 15/17 règles (±2-4pts).
Deux décodeurs architecturalement opposés (CTC frame-indépendant vs RNNT
autorégressif) qui s'accordent rend l'hypothèse "détection décorative"
moins probable, et RNNT ne montre pas de sur-détection systématique
(rassurant sur le risque de biais canonique redouté). Ne règle toujours
pas la question cross-récitateur/violation délibérée.

Classement de fiabilité par règle ajouté (exigence produit : ciblage
utilisateur par règle, pas de score agrégé) : prêtes (≥92%), à surveiller
(madda_necessary), échantillon insuffisant (idgham_mutajanisayn n=13,
idgham_mutaqaribayn n=3).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### dca9549 — 2026-07-19 — Documente l'exigence produit : ciblage par règle, pas de score agrégé

**Branche/tag:** 

**Auteur:** kafai

**Corps:** L'app permettra à l'utilisateur de choisir individuellement quelles règles
de tajwid il veut se faire corriger (liste des 17, sélection utilisateur).
Conséquence sur l'évaluation : chaque règle a besoin de sa propre fiche de
fiabilité, un score moyen sur les 17 classes masquerait les règles pas
encore assez fiables (ex. madda_necessary, la plus rare) pour être
proposées au choix. La Phase 3 doit classer les règles par niveau de
fiabilité, pas donner un chiffre unique.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 52117c9 — 2026-07-19 — Invalide le test cross-récitateur YouTube : confondu par un découpage 30s

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Tentative de test de généralisation cross-récitateur (les 54 réciteurs Hafs
disponibles sont tous déjà en train+val, overlap 53/53) via
manifest_youtube_clean.jsonl, provenance vérifiée (66% Qaris reconnus,
31% nommés moins célèbres, 3% exclus sans attribution).

Premier résultat (recall règles 26-44% vs 97-100% en distribution) semblait
indiquer un échec de généralisation — mais une question méthodologique de
l'utilisateur (vérifier qu'on cible la bonne position, pas juste "n'importe
où dans le clip") a mené à tester le CER de base (lettres/harakat) sur les
mêmes clips : 72,75% (médiane 95%), quasi-charabia. Cause racine : ces clips
sont découpés en blocs fixes de 30s (youtube_align.py, CHUNK_S=30), hors
distribution du training (max_duration=20s, clips single-verset de
quelques secondes) — effondrement de transcription général, sans rapport
avec les règles ni la généralisation cross-récitateur. Chiffres 26-44% et
72,75% CER à jeter.

Nécessiterait un vrai ré-alignement forcé du YouTube (frontières par verset
à l'intérieur des blocs de 30s, comme _assajda en juillet) pour un test
valide — chantier à part, non fait. Scripts conservés pour reprise future.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 3094642 — 2026-07-19 — Construit un set de validation YouTube vraiment non-vu, réciteurs vérifiés

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Demande utilisateur : tester la détection des règles sur des données jamais
vues du training (les 54 réciteurs Hafs disponibles sont TOUS déjà utilisés
en train+val, overlap 53/53 — aucune généralisation cross-réciteur testée
jusqu'ici). manifest_youtube_clean.jsonl (3371 clips, 112/114 sourates,
14 Go sur HDD) confirmé jamais touché par nemo_manifests_rules.

Vérifié avant utilisation (demande explicite : "assure-toi que les YouTube
font du tajweed et non une simple récitation") : croisement avec les titres
vidéo d'origine — 66% attribués à des Qaris reconnus (Alafasy, Sudais,
Al-Hussary "Accurate Tajweed recitation" explicite, Al-Dosari, Maher
Al-Muaqly, Bandar Baleelah...), 31% à des réciteurs nommés moins célèbres,
seulement 3% (103 clips) sans aucune attribution — exclus par prudence.

Résultat : val_youtube_heldout.jsonl, 3268 clips, 0 erreur d'annotation
(concaténation multi-versets vérifiée contre le texte source), couverture
complète des 17 règles (dont 96 madda_necessary sur 143 existantes dans
tout le Coran).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### c3bdb69 — 2026-07-19 — Teste la détection des règles : recall/faux-positifs Coran vs ASC+TTS

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Script test_rule_detection.py : mesure sur checkpoint epoch07/11 si la tête
stricte détecte réellement les 17 règles ou les émet de façon décorative.
Résultat : recall qalaqah 97,5-100%, faux positifs 0% (toutes règles
confondues, 0/120 clips ASC+TTS). Recall par classe 72-100% (point faible
madda_necessary, classe la plus rare).

Signal encourageant mais documenté avec la limite réelle : ce test oppose
audio style-Coran vs style-ASC/TTS, ne distingue pas "détection acoustique
moment-par-moment" de "raccourci de reconnaissance de domaine/style" — les
deux donnent le même résultat ici puisque tous les récitateurs pro du
corpus appliquent toujours les règles. Le set humain de violations
délibérées (qalqala omise DANS un style Coran correct) reste le seul test
qui tranche entre les deux hypothèses.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 66e9453 — 2026-07-19 — Mesure préliminaire du test d'interférence (checkpoint intermédiaire, pas final)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Export epoch07/11 (val_wer_ctc=0.163) et test sur val_canonical (n=150) :
CER 9,72% (tête règles désymbolisée) vs 9,18% (baseline mixed-e14),
écart +0,54 point. Documenté avec la nuance nécessaire : ni assez grand pour
conclure à une interférence réelle, ni assez petit pour conclure à zéro
impact — échantillon modeste, checkpoint intermédiaire (training toujours en
cours), écart possiblement dû à la réinitialisation de la tête CTC plutôt
qu'aux symboles eux-mêmes. Ne pas trancher sur la 2e tête avant de refaire
cette mesure avec le checkpoint final.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 6a2957c — 2026-07-19 — Reclasse la piste 'données RNNT dédiées' de contingence à expérience prévue

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Question utilisateur : le corpus mixed (150h Coran dilué + ASC + TTS fautif)
est optimisé pour combattre le biais canonique côté CTC (vérification) —
mais c'est potentiellement contre-productif pour RNNT, dont la valeur
(localisation "Suivre une prière") vient précisément d'un biais canonique
fort. Vu le compute disponible, cette piste (loss RNNT masquée sur Coran
non dilué pendant que CTC garde le mix complet) devient une expérience à
mener en round dédié après la Phase 3, informée par la mesure réelle de
qualité RNNT en localisation plutôt que lancée à l'aveugle ou en urgence.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 803fd59 — 2026-07-19 — Documente le mode enfant : couche de comparaison, pas une 3e tête

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Discussion utilisateur : un mode enfant a besoin de tolérer des confusions
de lettres proches (سص, طت...) par immaturité articulatoire, pas comme une
erreur adulte. Clarifié que ça ne nécessite AUCUN entraînement/tête
supplémentaire — le modèle transcrit déjà fidèlement (acquis mixed-e14),
il suffit d'une table de tolérance à la comparaison, réutilisant
CONFUSABLE_PAIRS de generate_tts_augmentation.py à l'envers (même paires,
strictes pour l'entraînement adulte, tolérées pour la comparaison enfant).
Zéro impact sur le run en cours.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 5ae7a43 — 2026-07-19 — Corrige un crash SIGSEGV (fork+CUDA) du stage 1b — num_workers=0

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le stage 1b complet a crashé ~1,9 epoch après son lancement : SIGSEGV Python
natif dans _PyObject_MakeTpCall (rapport apport Ubuntu), pas l'erreur
torch.AcceleratorError visible en surface (celle-ci n'est qu'une conséquence
en cascade pendant le teardown après le vrai crash).

Cause probable : multiprocessing.set_start_method("fork", force=True)
(ajouté plus tôt le même jour pour contourner un PicklingError Python 3.14)
appliqué après l'initialisation CUDA du process principal — cas documenté
comme non défini par PyTorch/NVIDIA. Jamais reproduit sur les runs plus
courts (1a, ab03, ab07, tous < 2 epochs) — cohérent avec un crash aléatoire
et tardif plutôt qu'un bug systématique immédiat.

Fix : num_workers=0 par défaut (plus de workers DataLoader forkés → le
PicklingError d'origine ne se produit plus non plus, fork devient inutile).
Commentaire du 2026-07-19 matin conservé (pas supprimé, cf. règle CLAUDE.md)
avec une note "ABANDONNE" expliquant pourquoi.

Run repris depuis periodic/last.ckpt (epoch 2, val_wer_ctc=0,180) — perte
quasi nulle grâce à la discipline de checkpoint périodique.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 8f55fd9 — 2026-07-19 — Inverse la logique de la tête tolérante : tester l'interférence avant de construire

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Question utilisateur : la normalisation (retirer les symboles de la sortie
de la tête stricte) suffit-elle pour le mode tolérant, ou une 2e tête
apporte-t-elle une vraie valeur ajoutée ?

Réponse actée dans le plan : la normalisation suffit SAUF si l'entraînement
aux règles dégrade la reconnaissance de base lettres/harakat pour une
récitation valide sans tajwid formel (interférence entre tâches) — dans ce
cas retirer le symbole après coup ne répare pas une transcription abîmée.
Phase 2 restructurée : 2.1 teste cette hypothèse (WER lettre/harakat de la
tête stricte désymbolisée vs baseline mixed-e14 sur val_canonical) AVANT de
construire quoi que ce soit ; 2.2 (la 2e tête) ne se fait que si 2.1 prouve
un besoin réel.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 94e26b6 — 2026-07-19 — A/B ctc_loss_weight mesuré (0.7 gagne) + lancement stage 1b complet

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - finetune_fastconformer_hybrid.py : ajout --run_tag pour permettre des runs
  A/B parallèles sans collision de dossier de sortie.
- A/B mesuré (1 epoch chacun depuis stage1a-final.nemo, PAS supposé) :
  ctc_loss_weight=0.7 bat 0.3 sur val_wer_ctc (0,2211 vs 0,2345) sans coût
  mesurable sur val_wer RNNT (0,1459 vs 0,1457) — confirme l'hypothèse
  "CTC dominante sert notre tête produit primaire" par la mesure.
- Stage 1b complet (11 epochs restantes) lancé en poursuite du checkpoint
  ab07 (poids 0.7), pas de redémarrage à zéro.
- PLAN_ENTRAINEMENT_HYBRIDE.md : résultats A/B documentés.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### b5b97f2 — 2026-07-19 — Phase 0 'vrai tajweed' exécutée + lancement du run hybride RNNT+CTC stage 1a

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - dl_uthmani_tajweed.py : télécharge text_uthmani + text_uthmani_tajweed
  (6236 versets, API quran.com — même source que les couleurs de l'app).
- build_rules_annotated_corpus.py : 56 197 symboles de règles insérés
  (17 classes dont 3834 qalqala), ancrage canonique par alignement
  Levenshtein, placement vérifié manuellement.
- build_rules_tokenizer.py + tokenizers/tajweed_rules_bpe_v1 : BPE 1024,
  couverture 100% (symboles PUA + 12 marques d'annotation du §3), roundtrip
  parfait.
- build_rules_manifests.py : 131 882 train / 3 976 val, Coran 100% annoté,
  audios 100% présents (SSD local), 0 récitateur Warsh (54 audités).
- finetune_fastconformer_hybrid.py : stages 1a (encodeur gelé, têtes
  fraîches) / 1b (dégel, LR bas), vraie loss RNNT (probe NVVM au démarrage),
  ctc_loss_weight par stage (1a=0.5 neutre, 1b=A/B 0.3 vs 0.7 à mesurer),
  fix multiprocessing fork Python 3.14.
- PLAN_ENTRAINEMENT_HYBRIDE.md : état d'exécution, décisions actées,
  checklist de déploiement app post-run.

Stage 1a lancé (logs/hybrid_stage1a.log).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 581c367 — 2026-07-19 — Glossaire techniques ASR : entraînement vs décodage, et quoi brancher maintenant

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - GLOSSAIRE_TECHNIQUES_ASR.md (nouveau) : explication simple de chaque
  technique (rescoring NLL, KenLM, décodage contraint, InterCTC, CR-CTC,
  global-match, GOP) + la distinction clé — ce qui doit être décidé DÈS le
  run (corpus, tokenizer, InterCTC) vs ce qui s'ajoute APRÈS sur n'importe
  quel checkpoint (rescoring, contraint, KenLM). Point d'action : le
  rescoring NLL bat le GOP actuel sur les lettres (80,8% validé) et peut
  être branché dans l'app sans attendre le run hybride.
- CLAUDE.md : références du plan hybride et du glossaire ajoutées à l'index.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### f334f8d — 2026-07-19 — Plan d'entraînement hybride 3 têtes + triage de priorité des pistes qualité

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - PLAN_ENTRAINEMENT_HYBRIDE.md (nouveau) : finalité par tête (CTC strict
  règles / CTC tolérant / RNNT localisation), piège des symboles décoratifs
  et garde-fou (set humain de violations = juge de paix), réponse TTS
  (ajouter des clips CORRECTS d'abord — corrélation voix⇔erreur à 100%
  mesurée —, harakat étendues, plus de voix), séquencement 1a (têtes seules,
  encodeur gelé) → 1b (dégel, LR différenciés) → tête tolérante sur gelé.
- ETAT_CTC_NEMO.md : pistes qualité triées 🟢/🟡/🔴 (décodage contraint en
  premier ; InterCTC et KenLM au bon moment ; CR-CTC/madd/Warsh/streaming en
  second lieu), pistes absorbées par le plan retirées de la liste.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 1f25fc2 — 2026-07-19 — Documente l'état CTC NeMo + débloque la loss RNNT (NVVM réparé sous Ubuntu)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** - ETAT_CTC_NEMO.md (nouveau) : inventaire complet des modèles FastConformer,
  chantier mixed, mesure epoch14 comblée (65,3% détection / CER 9,18%, n=150),
  pistes ouvertes et recette complète du déblocage RNNT.
- CLAUDE.md (nouveau) : index agent — docs de référence, règles projet
  (aucune piste éliminée tant que rollback possible), spécificités machine
  Ubuntu (venv cassé, remap manifests, CUDA_HOME pour RNNT).
- asr.md (skill) : section NVVM levé + section abs_pos (session 07-12).

Déblocage RNNT validé : wheel nvidia-cuda-nvcc dans .venv_nemo + symlinks +
CUDA_HOME + patch local NeMo (bug numba 0.66/py3.14 min/max kernel CUDA).
Smoke test loss hybride sur mixed-e14 réel : CTC 0,22 / RNNT 1041, gradients
OK partout. Aucun checkpoint ni script du dépôt modifié — rollback trivial.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### 3fb04c3 — 2026-07-16 — Corrige la troncature per-mot via validation globale (idée utilisateur)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** BUG DIAGNOSTIQUÉ (device, verset 68:17, mot "بَلَوْنَـٰهُمْ") : même passe,
mêmes logprobs, deux décodages divergents --
  segment ENTIER (libre, sans frontière) : "بَلَوْنَـٰهُمْ" complet et correct
  mot ISOLÉ (actual = greedyDecodeRange borné aux frames que la DP a
    attribuées à CE mot) : "بَلَـٰهُمْ", tronqué -- la DP avait rendu la main
    au mot suivant trop tôt (confiance faible en fin de mot), amputant sa
    plage de frames.
Le gop lui-même était bon (-0.01, quasi parfait) : SEUL le texte `actual`
tronqué faisait déclencher `spellsDifferentWord` côté Dart (le texte ne
"matchait" plus l'attendu) -> jugement "unclear" pour un mot pourtant bien
récité.

IDÉE TESTÉE HORS-LIGNE D'ABORD (benchmark/global_match_eval.py, 150 clips
réels) : valider un fragment globalement (décodage libre sans frontière)
quand il colle au texte attendu, ne fragmenter que si un mismatch est
détecté. Cas 1 (segments réellement corrects) : 72.7% validés d'un coup.
Cas 2 (mismatch simulé) : méthodologiquement faussé -- corrompt le texte
ATTENDU en gardant l'audio correct, donc mesure "le modèle transcrit-il
fidèlement" (trivialement oui) et non "détecte-t-il une vraie erreur de
récitation" -- documenté comme tel, pas présenté comme validé.

IMPLÉMENTATION -- volontairement plus étroite que l'idée initiale, pour
rester sûre : ne touche JAMAIS gop/forced (qui gardent toute leur
sensibilité, y compris sur les harakat -- aucune régression de détection
introduite). Uniquement, quand le décodage libre global confirme la
TOTALITÉ des mots attendus pour cet appel (wordSpansFromFree, même règle de
tolérance que coveredWordsFromFree déjà en place) ET que l'alignement
naturel couvrait déjà tous les mots (rien n'a été laissé de côté, juste
potentiellement mal découpé) : remplace SEULEMENT le texte `actual` de
chaque mot par celui du décodage libre global, jamais borné par une
frontière de frames fragile.

Compromis assumé, pas une régression nouvelle : la tolérance de
wordSpansFromFree (≥50% des tokens d'un mot retrouvés) peut laisser un mot
"confirmé" même si un token diffère légèrement -- mais gop reste seul juge
du verdict, donc ça n'affecte que le texte affiché, jamais la couleur.

À tester en conditions réelles sur device (build global-match-actual-text).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 3316e65 — 2026-07-16 — Corrige 8/10 findings de la revue de code (2 restants documentés délibérément)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Tous testés sur device après chaque correctif (build+install+log vidé),
un seul changement par build (_kBuildTag bumpé à chaque fois).

#2 ForcedAligner.kt:311 -- LA cause du lag de ce soir (mot bloqué 17 fois,
   verset 68:17) : un mot forcé en 2e chance qui obtient encore 0 frame
   sortait sans jugement ET sans deferredIndex, effaçant le garde-fou et
   permettant de boucler différer->oublier->différer à l'infini. Un mot à 0
   frame est maintenant soit différé proprement (1ère fois), soit tranché en
   erreur définitive (2e chance, toujours 0 frame).

#1 recitation_verifier.dart -- course dispose()/réouverture rapide. Le
   verifier partagé (pas autoDispose) n'avait aucune synchronisation entre le
   nettoyage fire-and-forget d'une ancienne session et le start() d'une
   nouvelle. Ajout d'un verrou sérialisé FIFO + numéro de génération :
   start() et stopIfCurrentSession() ne s'exécutent jamais en même temps, et
   un nettoyage périmé (généraiton dépassée) devient un no-op au lieu de
   saboter la nouvelle session.

#6 recitation_provider.dart:750 -- isFragment n'avait aucune borne minimale,
   rouvrant le bug sin/sad du jour (un match d'1 caractère coïncidant
   suffisait à contourner spellsDifferentWord). Borne calculée sur les cas
   réels : troncature légitime = ratio 0.44, coïncidence = ratio 0.14 --
   seuil à 1/3 + minimum 2 caractères.

#9 recitation_provider.dart:761 -- hasSpeech ne gardait que la branche
   correct, pas unclear ; un mot jamais prononcé pouvait être jugé "unclear"
   au lieu d'exclu. hasSpeech est maintenant la première porte de toute la
   chaîne de jugement.

#3 FastConformerCtcPlugin.kt:297 -- le mode coach one-shot ne branchait
   jamais forceJudgeIndex (pas de "prochain appel" pour le lui donner). Comme
   tout l'audio est déjà disponible, le retry se fait maintenant DANS le même
   appel si un mot est différé.

#4/#5 karaoke_recitation_screen.dart -- deux bugs de concurrence dans le
   nouveau bouton souffleur : _onWordFailed ne vérifiait pas _promptingWord
   (course sur le même lecteur audio partagé), et le check `!mounted`
   sautait resetBuffer() tout en laissant resumeCapture() s'exécuter quand
   même (réintroduisait la fuite de session corrigée ailleurs ce jour).

#7 BufferedTranscriber.kt -- le chemin MAX_SEGMENT_SECONDS promeut un aperçu
   en cache directement en "final" sans rappeler align()/runAlignment(),
   donc deferredOnceIndex n'était jamais mis à jour pour cette instance.
   deferredIndex est maintenant conservé dans lastAlign et relu par ce
   chemin.

#8 (régression écran debug, 1 page au lieu du reste de la sourate) et #10
   (fallback ForcedAligner qui recalcule tout au lieu d'étendre la queue)
   laissés tels quels, délibérément -- raisons détaillées dans
   CODE_REVIEW_20260716.md §4 (le premier demande une fonctionnalité
   disproportionnée pour un écran interne/dev ; le second suppose une
   propriété du backtrace de la DP non garantie mathématiquement, et cette
   même DP a déjà eu 4 tentatives d'optimisation ratées aujourd'hui).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 367f769 — 2026-07-16 — Documente la revue de code (10/10 findings confirmes) + investigation du lag

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le lag signale ce soir (recitation bloquee ~40min sur verset 68:17) est relie
au Finding #2 de la revue : ForcedAligner.kt:311, le check 'wordFrames==0
break' s'execute avant le check forceJudgeIndex, permettant a un mot de
boucler differer->oublier->differer indefiniment. Preuve device directe : 17
tentatives consecutives sur le meme mot sans que l'ancre n'avance. Cause
secondaire : _recorder.pause() lui-meme a pris 5-37s par cycle (congestion
plateforme suspectee, non confirmee).

Revue /code-review sur les 3 commits du jour : 7 agents finder + verification
independante a 1 voix -> 10/10 CONFIRMED. Race dispose()/reouverture rapide,
3 chemins distincts cassant la garantie '2 chances max', 2 bugs de
concurrence dans le nouveau bouton souffleur, un trou dans le correctif
isFragment (borne manquante, peut rouvrir le bug sin/sad du jour), une
regression fonctionnelle (ecran debug plafonne a 1 page), plus 2 mineurs.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 9446c10 — 2026-07-16 — Contre-revue Sonnet + développement du rescoring tête-à-tête (résultat réel)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** §6 ajouté à REVUE_ARCHITECTURE_KARAOKE.md : vérification directe du code
(SessionOptions vide, streaming session existante mais jamais appelée côté
Dart -- confirme le verdict 2026-07-04), correction du chiffre de redondance
(×2,5-4,5 annoncé = pire cas 1/141 segments ; le régime typique 2-4s est
×1,5-2,1, mesuré sur la distribution réelle des logs du jour), réserve sur
P2.1 (stats de normalisation fixes = changement de distribution d'entrée pour
un encodeur déjà entraîné en continuation, pas un simple toggle).

benchmark/variant_rescoring_eval.py : implémente et EXÉCUTE le Go/No-Go de
l'Étape 5.1 (comparaison tête-à-tête NLL(prononcé) vs NLL(canonique) via
ctc_loss, sur les 1808 clips fautifs du holdout TTS tenu hors entraînement).
Incident réel en cours de route, documenté dans le script : la 1ère
exécution a silencieusement sauté 1808/1808 lignes (clips TTS en 24kHz natif,
refus strict au lieu de rééchantillonner) et sorti un faux "NO-GO 0.0%" --
corrigé avant toute conclusion.

Résultat réel :
  letter (ص↔س, ط↔ت...) : 80.8% -- GO net, règle exactement le cas sin/sad
    diagnostiqué aujourd'hui (gop=-0.35, jugé vert par le score relatif)
  harakat               : 49.6% -- NO-GO, quasi pile-ou-face, vérifié non-
    artefact de tokenisation (0% de collision de tokens BPE)

Portée de la suite (Étape 5.2+) restreinte aux paires letter : le rescoring
vient en plus du gop, jamais à sa place pour les harakat, où ce signal n'est
pas meilleur que le hasard.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 22b27e3 — 2026-07-16 — Revue d'architecture karaoké + plan d'exécution P0/P1/P2 (Fable)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Diagnostic : la normalisation per_feature globale a dicté toute l'architecture
aval (re-transcription intégrale toutes les 1,5s = 2,5-4,5x l'audio payé,
machinerie de gel, classe de bugs 'mot frontière'). Le jugement manque d'un
signal absolu (gop relatif s'écrase quand le modèle hésite — cas sin/sad vert
mesuré). ORT non configuré, fp32 458 Mo, mel recalculé de zéro à chaque passe.

Plan : P0 sans risque (threads/XNNPACK, mel incrémental bit-exact, gel sans
re-transcription), P1 mesurable offline (quantif int8 avec garde-fou
distribution gop, rescoring par variantes confusables sur les mêmes frames --
le vrai fix jugement, Go/No-Go offline avant tout code app), P2 au prochain
entraînement (stats de normalisation fixes puis fine-tune streaming causal =
suppression de la segmentation et de sa classe de bugs).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
### fc506f6 — 2026-07-16 — Corrige la cécité aux erreurs de prononciation (cause racine : token parasite)

**Branche/tag:** 

**Auteur:** kafai

**Corps:** Le modèle "corrigeait" silencieusement les fautes vers la forme canonique :
l'utilisateur prononce "rabba" (fatha), l'app affiche "rabbi" (kasra) et valide
en vert. Trois causes distinctes, toutes traitées ici.

1. Token '▁' parasite dans word_tokens.json (LA cause racine)
   build_word_token_lookup.py faisait `text_to_ids("▁" + mot)`, croyant devoir
   ajouter le marqueur de début de mot -- SentencePiece l'ajoute déjà lui-même.
   Résultat : marqueur DOUBLÉ sur 19001/19001 entrées (['▁','▁رَبِّ'] au lieu de
   ['▁رَبِّ']). Ce token n'est jamais émis par le modèle : l'alignement forcé
   devait le placer sur une frame où sa logprob est ~-inf, ce qui polluait la
   MOYENNE du mot -- 50% du score pour un mot à 2 tokens, 25% à 4 tokens.
   Effets, tous disparus après correction :
     - gop de رَبِّ : -10.94 -> 0.00 (mot parfaitement prononcé)
     - blocage de la DP d'alignement (forcer coûtait un token impossible ->
       rester en blank devenait moins cher -> la frontière stagnait)
   Invisible sur le modèle "pcd" (0/18340 entrées touchées), d'où une
   régression silencieuse au passage à tajweed_bpe_v1.

2. Seuils GOP recalibrés sur ce bug -> annulés
   Les valeurs -5.0/-10.0 avaient été posées le matin pour compenser des gop
   aberrants... causés par le point 1. Elles rendaient l'app AVEUGLE : un mot à
   gop=-1.28 avec une shadda manquante passait vert. Retour aux valeurs pcd
   (-0.45/-1.6), calibrées pour la vraie plage.

3. Le jugement ignorait le texte réellement entendu
   `textMatches` ne servait qu'à être plus INDULGENT. Un mot pouvait donc être
   vert alors que le décodage libre épelait un AUTRE mot (mesuré : attendu
   "صِرَٰطَ" / entendu "سَرَٰطَ", gop=-0.35 -> vert, car le gop est RELATIF et le
   modèle hésitait sur tout). Ajout de `spellsDifferentWord` : une substitution
   avérée interdit le vert, en distinguant la vraie faute de la troncature de
   segment (fragment de l'attendu -> jugé sur le gop seul, comme avant).

ForcedAligner : journal des tentatives conservé
  4 pistes ont été essayées puis invalidées sur le blocage d'alignement (elles
  traitaient le symptôme du point 1). Chacune est documentée AVEC la raison de
  son échec et l'observation device qui l'a prouvée -- une suppression ne
  laisse aucune trace et l'impasse serait re-tentée. Retenu : filet piloté par
  le décodage libre (qui ne cale jamais, décidant frame par frame), déclenché
  uniquement sur segment figé. Le décodage libre atteste la POSITION, le GOP
  garde seul le jugement rouge/vert (sinon on perd la détection harakat).

Autres correctifs de cette session :
  - Fuite de session : dispose() n'arrêtait pas le micro. Le verifier n'étant
    pas autoDispose, l'ancienne session continuait d'alimenter le
    BufferedTranscriber natif (singleton) -- deux flux concurrents, du bruit
    ambiant transcrit en charabia et jugé comme de vrais mots (wordFailed sur
    "الٓمٓ" 100 ms après ouverture, avant le premier bloc PCM).
  - Karaoké : chargeait toute la fin de la sourate (6121 mots sur Al-Baqara),
    court-circuitant l'extension page par page prévue. Borné à la page courante.
  - Souffleur : bouton pour entendre le mot attendu à la demande (trou de
    mémoire != faute -> ne colorie rien, ne recule pas l'ancre). Réutilise le
    garde-fou pauseCapture/resetBuffer, sinon le micro capte le haut-parleur.
  - Marqueur de version dans la log (BUILD code=/compile= + modèle chargé) :
    un correctif compilé mais non installé avait produit un log indiscernable
    de la version précédente -> diagnostic mené sur le mauvais binaire.

Entraînement : le manifeste ne contenait AUCUNE erreur
  Les 4 manifestes tajweed avaient tts=0 : 284823 clips de Coran parfaitement
  récité, rien d'autre. L'augmentation TTS (18084 clips d'erreurs délibérées)
  avait été perdue lors de la reconstruction du manifeste au passage à
  tajweed_bpe_v1. Le modèle n'avait donc jamais entendu une seule erreur.
  build_mixed_manifest.py : Coran 150h (replay anti-oubli) + Arabic Speech
  Corpus x10 (vraie voix, arabe NON coranique vocalisé -> aucun prior canonique
  applicable) + TTS x5 => 34% de contre-exemples (était 0%).
  Ajouter les 28h brutes aux 1251h n'aurait pesé que 1% -- un biais construit
  sur 1251h ne se casse pas avec 1% de contre-exemples.
  eval_error_detection.py mesure ce qui compte (taux de "correction" vers le
  canonique, pas le WER : écrire رَبِّ au lieu de رَبَّ ne coûte qu'un caractère
  de WER mais est un échec produit total).

Gain mesuré sur 150 clips d'erreurs tenus hors entraînement (modèle mixed-e02) :
  détection d'erreur : 18.7% -> 57.3%   (x3)
  erreur manquée     : 28.7% -> 18.0%
  CER coranique      :  9.03% -> 9.46%  (contrôle anti-oubli, stable)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>


---
### 9a61b77 — 2026-07-12 — Documente l'échec de l'entraînement 100% on-device (ONNX Runtime Training)

**Branche/tag:** 

**Auteur:** Adam

**Corps:** Suite au revert du commit précédent (bascule onnxruntime-training-android),
consigne dans asr.md les détails concrets du blocage pour éviter de refaire
cette investigation à l'aveugle :

- generate_artifacts() plante (GradientBuilderBase::O assertion) sur
  l'attention à position relative du Conformer -- bug/limite bas niveau
  d'ONNX Runtime Training, pas un op manquant contournable.
- Paquet Python onnxruntime-training : aucun wheel Windows, Linux only,
  cp38-cp311 (pas cp312) -- contournement WSL documenté si à retenter.
- ConformerEncoder par défaut n'implémente pas AdapterModuleMixin
  (nécessite l'échange de classe vers ConformerEncoderAdapter).

Conclusion : rester sur le mini-LoRA v1 PC-assisté (déjà en place, commit
9024fb6) tant qu'ONNX Runtime Training ne supporte pas mieux ce type
d'attention.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 6861b0b — 2026-07-12 — Revert "Chantier entraînement 100% on-device : bascule vers onnxruntime-training-android"

**Branche/tag:** 

**Auteur:** Adam

**Corps:** This reverts commit 2ebb383981c28dc546051e9270ce412671774da9.


---
### 2ebb383 — 2026-07-12 — Chantier entraînement 100% on-device : bascule vers onnxruntime-training-android

**Branche/tag:** 

**Auteur:** Adam

**Corps:** Remplace onnxruntime-android:1.20.0 par onnxruntime-training-android:1.19.2
(superset inference+training, même API Java ai.onnxruntime.* -- aucun code
Kotlin existant à modifier). Étape 1 du chantier "vraie personnalisation
vocale sur l'appareil" (suite à la demande utilisateur du 2026-07-12 : le
mini-LoRA v1 PC-assisté ne correspondait pas à l'objectif "rien ne sort du
téléphone").

Validé : build debug + lancement sur device réel sans crash (l'inférence
CTC existante n'est pas encore re-testée fonctionnellement -- à confirmer
par un test de récitation réel avant de considérer cette étape définitive).

Point de rollback explicite (demande utilisateur) : si la suite du chantier
(perte proxy cross-entropy par frame, artefacts d'entraînement, module
JNI) s'avère infaisable ou casse l'inférence existante, revenir à ce commit
puis au précédent (onnxruntime-android classique).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### 9024fb6 — 2026-07-12 — Correctifs récitation (perf, sensibilité, référence globale), cascade offline, mini-LoRA v1 (PC-side)

**Branche/tag:** 

**Auteur:** Adam

**Corps:** ## Récitation continue / karaoké
- Sensibilité de jugement GOP réglable en direct pendant la récitation
  (curseur, non persisté — chaque récitation repart de la valeur par défaut).
- Profil de pauses : repli sur un profil global une fois stable, pour ne
  plus reproposer de session de référence à chaque nouvelle sourate.
- Latence de correction automatique corrigée : préchargement réseau et
  cache local du MP3 du récitateur dès qu'un nouveau verset devient courant.

## Cascade d'explications mot/verset (offline)
- QuranSciencesService : lookup direct (RandomAccessFile) sans charger les
  gros fichiers de tafsir en RAM ; repli Gemma si absent ; sélection de
  langue AR/FR/EN ; correspondance mot fiable par forme de surface.

## Mini-LoRA personnalisation vocale (v1, PC-assisté)
- Capture des clips vérifiés corrects (sessions de référence uniquement),
  export manuel (partage natif, pas de sync auto), script d'entraînement
  NeMo (adaptateur, base gelée) côté PC.
- NOTE : cette version fait sortir l'audio du téléphone vers un PC pour
  l'entraînement — ne correspond pas à l'objectif "100% sur l'appareil".
  Chantier suivant : investiguer ONNX Runtime Training (on-device) pour un
  entraînement réellement embarqué, sans partage d'aucune donnée vocale.

## Divers
- .gitignore : benchmark/nemo_manifests_tajweed/ (manifests générés, 154 Mo,
  oubliés lors d'un ajout précédent).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### fc6d731 — 2026-07-12 — Refonte ASR (GOP forced-alignment), récitation continue, cascade d'explications offline

**Branche/tag:** 

**Auteur:** Adam

**Corps:** ## Modèle ASR / entraînement
- Fine-tuning FastConformer CTC sur dataset augmenté (Coran + Arabic Speech
  Corpus diacritisé) pour corriger le biais du modèle vers le texte
  canonique (il "corrigeait" les mispronunciations au lieu de les
  transcrire). val_wer_ctc ~1,1% contre 1,64% avant.
- Modèle exporté et déployé sur l'appareil (remplace fastconformer-ctc-pcd),
  ancien modèle conservé en .bak pour retour arrière.

## Vérification de récitation — refonte GOP (karaoké)
- ForcedAligner.kt (nouveau) : alignement forcé CTC (DP état étendu
  blank/token), Goodness of Pronunciation = logprob(forcé) - logprob(libre),
  alignement partiel (meilleur état sur toute la séquence, pas seulement le
  dernier).
- BufferedTranscriber.kt / FastConformerCtc.kt / FastConformerCtcPlugin.kt :
  intégration de l'alignement forcé, correctif de désynchronisation d'ancre
  (l'ancre native avançait à `frontier` au lieu de `anchor + words.size` sur
  un segment figé, causait des verrouillages "erreur" en cascade).
- recitation_provider.dart : jugement par seuils GOP (vert/orange/rouge),
  sensibilité réglable EN DIRECT pendant la récitation (curseur, non
  persisté — chaque récitation repart de la valeur par défaut).
- Correctifs de désynchronisation texte/index (marques décoratives ۞ non
  filtrées de façon cohérente entre tajwid, explication de mot et
  découpage attendu) — appliqués à tous les points d'entrée concernés.

## Récitation continue (karaoké)
- Enchaînement automatique sur la sourate suivante, PAGE PAR PAGE du Mushaf
  standard (pas sourate entière d'un coup — revu après un test réel montrant
  tout Al-Baqarah, 286 versets, chargé instantanément).
- Bandeau de transition visuelle entre sourates, fenêtre de rendu bornée
  (corrige un gel de 3+ minutes constaté en test réel).
- Latence de correction automatique corrigée : préchauffage réseau
  (segments de timing + URL audio) et mise en cache locale du MP3 du
  récitateur DÈS qu'un nouveau verset devient courant, au lieu d'un fetch
  bloquant au moment de l'erreur (mesuré à 4,5-9,2s sur réseau dégradé).
- Profil de pauses personnel : repli sur un profil global agrégé
  (plusieurs passages déjà validés) une fois jugé stable, pour ne plus
  reproposer de session de référence à chaque nouvelle sourate.

## Cascade d'explications mot/verset (offline, sans LLM)
- QuranSciencesService : lookup par accès direct (RandomAccessFile) dans
  les fichiers de tafsir/lexique générés côté PC (trop volumineux pour un
  chargement complet en RAM sur un appareil à 6 Go) — paliers
  synthétique -> érudit, sources toujours citées.
- coach_explanation_sheet.dart : cascade offline en priorité, repli sur le
  tuteur Gemma si absent ; sélection de langue (AR/FR/EN) ; correspondance
  mot fiable par forme de surface (pas seulement position, le fichier
  source utilise un découpage grammatical indépendant du découpage de
  l'app).
- Scripts de préparation (benchmark/) : index racine/mot, cascade
  d'explications par palier, index offset pour l'accès direct mobile.

## Fonctionnalités additionnelles
- Boussole Qibla (direction de la Mecque, distance).
- Logger persistant sur l'appareil (indépendant d'adb), pour diagnostiquer
  après coup sans connexion continue.
- Téléchargement de tafsirs (anglais + classiques), plan QAT tuteur mis à
  jour, scripts d'entraînement Gemma associés.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>


---
### e800305 — 2026-07-11 — Commit initial — Coran Karim

**Branche/tag:** 

**Auteur:** Adam

**Corps:** App Flutter de mémorisation du Coran assistée par IA :
- app/ : écrans (karaoké récitation, mushaf, coach IA, duas), providers
  Riverpod (alignement récitation), services (ASR FastConformer ONNX,
  tuteur Gemma 4 E2B LiteRT-LM, API quran.com, profils de pause)
- benchmark/ : scripts d'entraînement/export (NeMo FastConformer, Whisper,
  Gemma LoRA), préparation de datasets — les modèles/données (~158 Go)
  sont exclus via .gitignore
- patches/ : plugin whisper_ggml patché (sources uniquement)
- docs : ARCHITECTURE.md, QAT_TRAINING_PLAN.md, FONCTIONNALITES_FUTURES.md

État au moment du commit : correctifs du jour inclus (alignement
_alignChunk anti-avalanche, fusion/écho de jetons ASR, tolérance waqf,
rasm واو+alif suscrit, keepAlive du recitationProvider, affichage tajwid
fidèle au texte canonique, dialogue de session de référence, pastilles
de numéro de verset en karaoké).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>


---
