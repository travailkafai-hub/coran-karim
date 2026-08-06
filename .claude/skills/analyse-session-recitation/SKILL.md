---
name: analyse-session-recitation
description: Analyser une session de récitation sur device (log + WAV) et en tirer un compte rendu causal complet. À invoquer dès que l'utilisateur dit « regarde la log », « analyse », « qu'est-ce qui cloche », ou fournit une session à examiner.
---

# Analyser une session de récitation

Ce skill existe parce que cette analyse a été refaite une dizaine de fois le
2026-07-27, **à la main, et qu'une omission ou une erreur de méthode s'est
glissée à chaque fois**. Les pièges ci-dessous sont tous des erreurs réellement
commises ce jour-là, pas des précautions théoriques.

---

## ⚠️ LIRE EN PREMIER — LA CHAÎNE A CHANGÉ (mise à jour 2026-08-06)

Ce skill a été écrit pour la **v1**. La chaîne qui peint l'écran est aujourd'hui
la **v2** (`recitation2/`, ligne `[CTL][V2]`). Une grande partie des lignes de
log citées plus bas **n'existe plus** — chercher un mécanisme mort, c'est
conclure « il n'a pas tourné » sur un code qui a été supprimé.

**Vérifié par comptage sur une session v2 réelle (build `v56`, 2026-08-06,
9 670 lignes) :**

| marqueur cité dans ce skill | occurrences | statut |
|---|---|---|
| `[GOP] … lock=true` | **0** | mort — remplacé par `[CTL][V2] mot=` |
| `segment FIGE` / `apercu reutilise` | **0** | mort — **plus de gel, plus de « borne dure »** |
| `ZERO FRAME` | **0** | mort |
| `secours mot=` | **0** | mort — **il n'y a plus de 2ᵉ buffer** |
| `AVANCE SANS JUGER` | **0** | mort |
| `RESYNC` | **0** | mort |
| `VALIDATION retard=` | **0** | mort |
| `ETRANGLE PAR LA REFERENCE` | **0** | mort |

⇒ **Les étapes 3 bis (chemin de gel) et 3 ter (2ᵉ buffer) ne s'appliquent plus.**
Elles sont conservées telles quelles plus bas — règle projet : on n'efface pas
la trace de ce qui a été tenté — mais elles ne concernent que les logs v1
d'avant le 2026-08. Sur une session v2, la colonne « 2ᵉ buffer » vaut
systématiquement `sans objet (supprimé par conception)`, et la colonne
« chemin » vaut `v2`.

### Les marqueurs v2, ceux qu'il faut réellement chercher

| ligne | ce qu'elle dit |
|---|---|
| `[CTL][V2] mot=N "x" -> statut \| gop= forced= free= frames= INT margeL= margeH= obs= entendu=""` | le verdict d'un mot, avec toutes ses preuves |
| `[v2] f=N bande=i0..i1 conf=… interieurs=k/n` | la fenêtre s'est localisée |
| `[v2] f=N bande=inconnue entendu="…"` | la fenêtre n'a rien pu positionner |
| `[v2] f=N SAUT REFUSE : trou de T mots apres le mot P (attestes=[…])` | trou > `sautMaxMots` → **toute la fenêtre est jetée** |
| `[v2] f=N RECUL vers le mot i0` | le récitateur répète |
| `[v2] f=N horsTexte (saut)? : fenetresHorsTexte=… fenetresAvantDecrochage=…` | compteur avant décrochage |
| `[v2] f=N DECROCHAGE (saut)? : … dernier atteste vu=… reprise apres le mot R` | le natif signale |
| `[v2] cible etendue : +k mots -> N mots (chaine active=…)` | enchaînement de page **répercuté au natif** |
| `[t3] mot=N logit=… ` / `[tajwidDuree] mot=N …` | têtes 2/3, **observation seule, aucun verdict** |

**Statuts possibles** (à lire tels quels, ne pas les traduire) :
`definitif:vert` `definitif:orange` `definitif:rouge` `provisoire:vert`
`provisoire:orange` `provisoire:rouge` `omis`.

⚠️ **`provisoire:*` en fin de session = mot JAMAIS VERROUILLÉ.** C'est un
non-vert, au même titre qu'un rouge — le compter, ne jamais le lire comme
« vert » sous prétexte que le mot est `provisoire:vert`.

⚠️ **`omis` = « le récitateur n'a pas dit ce mot »**, le verdict le plus grave
de l'app. Mesuré le 2026-08-06 : deux `omis` (mots 44-45, Bismillah d'une
nouvelle sourate) alors que le flux brut la contient clairement. **Tout `omis`
doit être confronté au WAV, sans exception.**

## Étape 0 (v2) — LA CHAÎNE DU DÉCROCHAGE, ET SES CINQ MORTS SILENCIEUSES

Ajoutée le 2026-08-06 après une soirée entière passée à corriger le mauvais
maillon. Un décrochage doit traverser **quatre étages** ; il peut mourir à
chacun, et il est longtemps mort **sans laisser une seule ligne**.

```
[v2] DECROCHAGE (natif Kotlin)
   ↓
[CTL][Decrochage] signalé par la v2 -- reprise=R      (pont natif → Dart)
   ↓
[CTL][Correction] wordFailed déclenché : raison=…     (_onWordFailed)
   ↓
[CTL][Correction-Audio] verset=… fromIdx=… toIdx=…    (audio réellement joué)
```

**Compter les quatre, et comparer.** `DECROCHAGE=25` mais
`Decrochage signalé=14` et `wordFailed=8` : ce sont **deux fuites**, pas un
détail. Les causes connues, dans l'ordre où on les rencontre :

| étage perdu | cause | journalisé ? |
|---|---|---|
| natif → Dart | `if (_confidentMode) return;` (mode prière) | **non** — trou de diagnostic |
| natif → Dart | `if (state.status != RecitationStatus.listening) return;` | **non** — trou de diagnostic |
| `_onWordFailed` | réglage correction désactivé | oui (`IGNORÉ … désactivée`) |
| `_onWordFailed` | anti-rafale (cooldown 4 s) | oui (`IGNORÉ … anti-rafale`) |
| `_onWordFailed` | `verset=null` → **Bismillah / hors versets chargés** | oui (`IGNORÉ … position introuvable`) |

**Le piège de la jonction de sourates (mesuré 2026-08-06).** À l'enchaînement
de page, la reprise tombe sur la Bismillah insérée ; `_verseContaining` y rend
`null`, donc **la correction ne peut jamais partir** — deux fois de suite dans
la même session. Vérifier systématiquement :

```bash
grep -c "IGNORÉ.*position introuvable" $S   # >0 => decrochage impuissant
```

**Vérifier aussi le mode AVANT de conclure quoi que ce soit :**

```
[CTL][PARAMS] session=NORMALE correction=active ancreSansBlocage=false modeConfiant=false
```

`modeConfiant=true` **coupe le décrochage à la source**. Une session en mode
confiant ne valide AUCUN correctif de décrochage — le dire, et ne pas la
compter. Erreur commise le 2026-08-06 : deux sessions sur quatre étaient en
mode confiant, avec 53 et 25 `SAUT REFUSE`, chiffres qui ne prouvaient rien.

## Étape 0 bis (v2) — LA CIBLE A-T-ELLE SUIVI L'ÉCRAN ?

Défaut trouvé le 2026-08-05, resté invisible des semaines : l'enchaînement de
page mettait à jour l'écran **et l'ancien aligneur v1**, jamais la cible
**v2** — celle qui juge réellement. La cible restait figée à sa taille de
départ, et tout mot au-delà était structurellement hors de portée
(localisateur et décrochage sont bornés par `motsAttendus.size`).

```bash
grep -m1 "PARAMS] cible=" $S          # cible au DEMARRAGE
grep    "cible etendue"    $S          # doit apparaitre a chaque page enchainee
grep -oE 'nouvelle position max|mot=[0-9]+' $S | ...   # ancre max atteinte
```

**Si `ancre max` dépasse la cible initiale sans aucune ligne `cible etendue`,
l'analyse est faussée** : les mots au-delà ne pouvaient pas être jugés, et tout
« taux » calculé dessus est faux.

---

## Règle n°1 — ne JAMAIS omettre les mots non jugés

L'utilisateur l'a redemandé deux fois : *« il y a aussi les non jugés à blanc,
il ne faut pas les exclure quand je te demande d'analyser »*.

Un mot peut ne pas être vert de **quatre** façons, et un compte rendu qui n'en
présente qu'une est faux :

| état | visible à l'écran | où le lire |
|---|---|---|
| signalé (rouge/orange) | cadre coloré | `[GOP] … -> WordStatus.error/unclear (lock=true)` |
| **non jugé** | **aucun cadre** | absent des lignes `lock=true` |
| **sauté par un déplacement d'ancre** | **aucun cadre** | **AUCUNE ligne du tout** |
| jamais atteint | gris | au-delà de l'ancre max |

Le total doit **toujours** boucler : `verrouillés + non jugés = ancre max`.
Annoncer « 2,8 % d'erreurs » alors que 7,4 % des mots ne sont pas verts, c'est
donner le chiffre flatteur.

**Le mot SAUTÉ est le plus dangereux des quatre, parce qu'il ne laisse aucune
trace.** Quand l'ancre saute (resync, `AVANCE SANS JUGER`, recul annulé), les
mots enjambés n'ont ni ligne `[GOP]`, ni ligne `NON JUGÉ` : ils sortent du
**dénominateur** au lieu de compter comme échec. Compter « non verts / mots
jugés » fait alors *baisser* le taux à chaque mot perdu — plus le correctif
casse, meilleur il paraît.

Cas réel (2026-07-29). Un correctif de resync mesuré sur le même WAV rejoué au
bit près :

| compte | v21 (avant) | v22 (correctif) |
|---|---|---|
| non verts / mots **jugés** | 7,22 % | **3,45 %** ← moitié moins, faux |
| non verts / **ancre max** | 8,16 % | **13,40 %** ← la vérité |

Le correctif sautait 9 mots que la version précédente jugeait **verts**. Lu sur
le premier compte il divisait les erreurs par deux ; lu correctement il les
multipliait par 1,6. Il a été annulé.

⇒ Toujours compter sur `ancre max`, jamais sur le nombre de mots jugés. Et
lister explicitement les indices manquants (`[k for k in range(ancre_max) if k
not in vus]`) — c'est la seule façon de VOIR un mot dont rien ne parle.

## Étape 1 — Récupérer et ISOLER la bonne session

```bash
adb shell "cat /sdcard/Android/data/com.corankarim.coran_karim/files/recitation_diagnostic.log" > full.log
```

Puis découper sur la **dernière** ligne `=== BUILD code=… ===`, et vérifier que
le tag correspond au binaire qu'on croit tester.

**Pièges vécus :**
- *Log tronqué* : le log a été tiré pendant que la session tournait encore, et
  l'analyse a conclu « l'ancre finit à 130 » alors qu'elle est allée à 268. **Se
  fier à l'heure de la dernière ligne**, la comparer à l'heure des WAV.
- *Mauvais téléphone* : deux appareils sont utilisés. `adb devices -l` d'abord,
  et `-s <serial>` ensuite.
- *Plusieurs récitations dans une même fenêtre* : une remise à zéro de l'ancre
  (`nouvelle_ancre=0`) marque une nouvelle récitation. Ne jamais mélanger.

Travailler **à l'horodatage**, jamais en octets (demande explicite de
l'utilisateur).

## Étape 2 — Le mode et les réglages, avant tout le reste

```
[MODE] session de REFERENCE : correction DESACTIVEE…   ← ou « session NORMALE »
[PauseProfile] seuil de gel …
[ASR] capture ouverte | suppression de bruit = …
seuils -> correct=… unclear=… trouAlignement(free)=…
```

En **mode référence** : pas de correction, donc **aucun recul d'ancre**, et le
seuil de gel reste au défaut. Un mot différé n'y repassera jamais — les
conclusions valables en mode normal n'y tiennent pas.

## Étape 3 — L'inventaire complet, en un seul tableau

Pour chaque mot qui n'est pas vert : index, texte attendu, texte entendu,
`forced`, `free`, et **la cause**. Les causes possibles sont journalisées :

| ligne de log | cause |
|---|---|
| `2e chance epuisee … AVANCE SANS JUGER` | la DP ne l'a jamais placé, report épuisé |
| `trou d'alignement (free=… starved=…)` | pas de preuve exploitable |
| `ZERO FRAME … place=N frames` | aucune frame ; `place` dit si le mot POUVAIT tenir |
| `ETRANGLE PAR LA REFERENCE` | plancher de durée déclenché |
| Bismillah (index 0-3) | jamais jugée, décision 2026-07-20 |

Un mot sans cause identifiée est un **trou de diagnostic** : le dire, ne pas le
ranger dans « divers ».

## Étape 3 bis — Par quel CHEMIN le mot a-t-il été verrouillé ? [v1 SEULEMENT]

> **⚠️ OBSOLÈTE SUR LA CHAÎNE v2 (constaté 2026-08-06).** `segment FIGE` et
> `apercu reutilise` valent **0 occurrence** sur une session v2 : il n'y a plus
> de gel, donc plus de « chemin borne dure ». Section conservée pour lire les
> logs v1 d'archive et parce qu'elle porte une leçon de méthode qui reste vraie
> (« comparer les taux, pas les effectifs » ; « zéro trace = zéro exécution,
> vérifier dans le CODE que le garde peut être vrai » — c'est exactement ce qui
> a permis de trouver les morts silencieuses de l'Étape 0).
> Sur une session v2, la colonne « chemin » du tableau vaut `v2`.

Ajoutée le 2026-07-27 après une erreur d'analyse coûteuse : j'ai écrit que les
mots non secourus avaient « `covered = true`, donc mon signal est le mauvais »
— une **supposition**, jamais vérifiée, et **fausse**. La vraie cause était
qu'un garde du code rendait le mécanisme mort sur le chemin majoritaire.

Un mot n'est pas verrouillé par « l'app » : il l'est par **un chemin de code
précis**, et deux chemins n'exécutent pas le même code.

| chemin | ligne de log | ce qui s'y passe |
|---|---|---|
| gel normal | `segment FIGE … consomme=…` | `runAlignment(isFinal=true)` complet |
| **borne dure** | `segment FIGE (borne 12s, apercu reutilise, …)` | l'**aperçu** est promu final **sans re-transcription** |

**Toujours mesurer la part de trafic de chaque chemin avant d'interpréter quoi
que ce soit.** Mesuré ce jour-là : 25 gels sur 44 à la borne dure, portant
**218 des 245 mots (89 %)**. Un mécanisme absent du chemin borne dure ne couvre
donc que 11 % de la récitation — indépendamment de sa qualité.

```bash
# chemin de gel qui precede le verrouillage de chaque mot
python3 - <<'EOF'
import re
S=open('sess.log',encoding='utf-8',errors='replace').read().splitlines()
for k in MOTS:
    j=max((i for i,l in enumerate(S) if f'mot={k} ' in l),default=None)
    g=[x for x in S[:j] if 'segment FIGE' in x][-1]
    print(k, 'BORNE DURE' if 'apercu reutilise' in g else 'gel normal')
EOF
```

**Comparer les taux d'échec, pas les effectifs.** Le même jour : 16 des 18 mots
non verts venaient d'un gel à la borne dure — chiffre qui semble accablant, mais
rapporté au trafic les deux chemins échouent à l'identique (7,3 % contre 7,4 %).
La borne dure n'était donc **pas** la cause des erreurs ; elle était la raison
pour laquelle le **secours** ne se déclenchait jamais. Deux conclusions
opposées à partir du même constat brut : seul le taux tranche.

**Un mécanisme qui ne laisse aucune trace n'a pas « rarement tourné » : il n'a
pas tourné.** Avant d'expliquer pourquoi il se déclenche mal, vérifier dans le
CODE que son garde peut être vrai. Cas réel : le secours du chemin borne dure
était gardé par `lastAlignSpf > 0`, or `lastAlignSpf` vient d'un appel aperçu
qui ne passe pas `segmentSamples` (valeur par défaut 0) — garde toujours faux,
zéro exécution, et **aucune ligne de log** pour le dire. Chercher `grep -c` sur
la ligne que le mécanisme DEVRAIT produire est le premier réflexe, avant toute
hypothèse sur son déclencheur.

## Étape 3 ter — Le 2ᵉ buffer : TOUS les secours, un par ligne [v1 SEULEMENT]

> **⚠️ OBSOLÈTE SUR LA CHAÎNE v2 (constaté 2026-08-06).** `secours mot=` vaut
> **0 occurrence** : le 2ᵉ buffer a été **supprimé par conception** en v2 (le
> recouvrement des fenêtres fait le travail en amont, cf. l'en-tête de
> `ChaineRecitation`). Sur une session v2 la colonne « 2ᵉ buffer » vaut
> `sans objet (supprimé par conception)` — ce n'est **pas** un mécanisme mort à
> instruire, c'est une absence voulue. Section conservée pour les logs v1.

Demande explicite de l'utilisateur (2026-07-28) : *« sur tous les rattrapages tu
dois inclure ça dans ta méthode d'analyse »*. Donner « 15 rattrapages sur 35 »
ne suffit pas — c'est un chiffre, pas un diagnostic. Chaque tentative se lit.

**Tableau imposé, une ligne par TENTATIVE (pas par mot) :**

```
| mot | attendu | fenêtre mot (ms) | fenêtre extraite (ms) | largeur | n° tentative | résultat | audio de la fenêtre |
```

Les lignes viennent de deux traces jumelles, à croiser :

```
secours mot=N fenetre mot=[a,b)ms extraite=[c,d)ms dispo=Xms   ← ce qu'il a visé
secours mot=N SANS GAIN : gop … -> …   |   SECOURS mot=N : …   ← ce qu'il a rendu
```

### La signature qui discrimine : la largeur et la RÉPÉTITION

Mesure du 2026-07-28 (235 mots, moteur GOP), séparation parfaite :

| forme de la fenêtre | tentatives | résultat |
|---|---|---|
| étroite (5,8-8,4 s), une seule tentative | 15 | **toutes rattrapées** |
| large (9-15 s), répétée 3 à 5 fois | 15 | **toutes SANS GAIN** |

**Toujours regrouper les tentatives par mot et comparer leurs bornes.** Une
borne GAUCHE identique d'une tentative à l'autre est le symptôme central :

```
109 → [131015, 140560)  puis [131015, 141015)  puis [131015, 141015)
132 → [165195, …) cinq fois       167 → [208438, …) quatre fois
```

Cause : un mot en échec ne s'horodate pas (cf. `wordStamps`), donc la borne
gauche reste collée au dernier mot SÛR et seule la droite avance. La fenêtre
grossit au lieu de glisser, et on demande à la DP de placer un mot de 0,3 s dans
10 à 15 s d'audio. Le plafond (`RESCUE_MAX_SEARCH_SECONDS`) masque le symptôme
sans le traiter — compter aussi les `fenetre PLAFONNEE`.

### NE JAMAIS reconstituer l'audio du secours depuis les clips

Erreur commise le 2026-07-28 : les clips concaténés ont été pris pour le flux
qu'adresse le `RescueBuffer`, et les fenêtres décodées « tombaient trop tôt ».
Conclusion invalidée par un contre-exemple du log lui-même — le mot 19, **bel et
bien rattrapé** par l'app (`يُن → يُنفِقُونَ`), alors que la fenêtre reconstituée
décodait des mots antérieurs. Cause : `somme(clips) = 319,0 s` pour un flux brut
de `310,2 s`, soit ~9 s d'audio dupliqué ; la dérive s'accumule et fausse toute
position absolue.

⇒ Contrôle obligatoire AVANT d'utiliser les clips comme référence temporelle :
`somme(clips)` doit être **inférieure** au flux brut (le portier retire du
silence). Si elle le dépasse, il y a duplication : les positions absolues
tirées des clips ne valent rien, et la colonne « audio de la fenêtre » s'écrit
**(non vérifiable)** — jamais une conclusion.

⇒ Le seul instrument fiable est un WAV écrit par le secours lui-même au moment
de l'extraction. S'il n'existe pas encore, le dire comme trou de diagnostic et
le proposer : sans lui, « pourquoi le secours échoue » restera indécidable.

### Ce qu'il faut conclure, et ce qu'il ne faut pas

- Un `SANS GAIN : gop -20,00 -> -20,00, entendu "" -> ""` **ne dit pas** que le
  mot est absent de l'audio. Il dit que la DP n'a rien placé dans la fenêtre —
  ce qui arrive aussi quand la fenêtre est mal posée ou trop large.
- Un secours **répété sur le même mot avec le même résultat** (mesuré : mot 200
  rattrapé cinq fois à l'identique) est du calcul perdu, à compter et à signaler.
- Les rattrapages doivent être **listés avec leur texte** : c'est là qu'on voit
  ce que le mécanisme sait faire (`بِ → بِمُؤْمِنِينَ`, `ص → صُمٌّ`,
  `"" → ظُلُمَـٰتٌ`). Un compte seul ne le montre pas.
- Compter séparément les rattrapages dus à la règle « texte complet à gop égal »
  (`gop 0,00 -> 0,00`) : ils seraient tous perdus sans elle — 11 sur 15 le
  2026-07-28.

## Étape 4 — Classer par MÉCANISME, pas par symptôme

C'est ici que l'analyse commence. Le constat ne suffit pas : il faut la chaîne
causale. Trois mécanismes distincts ont été isolés, ils appellent des correctifs
opposés.

**A. Une coupe fait DEUX victimes.** Le mot en frontière est tronqué, et son
successeur ouvre le segment suivant sans contexte. Signature :

```
mot N   frontiere du segment      → fragment ou entendu vide
mot N+1 premier du segment suivant → jamais placé
```

Vérifier avec `alignement seq=… ancre=A frontiere=F` : le mot est en frontière
si `mot >= F-1`, il ouvre le segment si `mot == A`.

**B. Un mot coupé des deux côtés.** Il est à la fois dernier d'un segment et
premier du suivant — il n'existe entier nulle part. Signature : plusieurs
`ZERO FRAME` avec une **place énorme** (plusieurs secondes) et un `forced` très
négatif.

**C. Propagation d'ancre.** Des mots **intérieurs** au segment (donc pas en
frontière) échouent quand même, parce que le PREMIER mot du segment n'a jamais
été placé : tout l'alignement du segment est décalé. Signature : mots non jugés
en `interieur (+3, +4…)` d'un segment dont l'ancre est bloquée.

Le mécanisme C **ne sera corrigé par aucun découpage** — c'est l'ancre.

Vérifier aussi les **rattrapages** (`unclear` puis `correct` sur une passe
suivante) : ils prouvent que le premier verdict était un artefact.

## Étape 4 bis (v2) — LE BALAYAGE TEMPOREL DU FLUX BRUT, À FOURNIR TOUJOURS

Demande explicite de l'utilisateur (2026-08-06) : *« ça m'intéresse, avec les
temps 3-6, 6-9… ce que le modèle reçoit, ça m'aide à analyser »*. Ce balayage
n'est pas une vérification ponctuelle réservée aux mots douteux : c'est une
**sortie standard de l'analyse**, à donner en entier.

**Pourquoi il tranche là où le log ne peut pas.** Le log dit ce que la chaîne a
*conclu* ; le balayage dit ce que le modèle *reçoit*, seconde par seconde, hors
de toute politique de fenêtrage. Les deux se lisent l'un contre l'autre :

| ce qu'on voit | ce que ça prouve |
|---|---|
| le mot est décodé net dans le brut, mais absent des `attestes` | défaut de la CHAÎNE (fenêtre mal posée), pas du récitateur |
| le mot est instable d'une fenêtre à l'autre (`ووجسك`/`ووجتك`/`ووجزسك`) | limite du MODÈLE sur ce son |
| le brut ne contient rien d'exploitable sur la plage | le récitateur s'est arrêté / audio trop pauvre |
| le même passage revient à deux instants éloignés | RÉPÉTITION — cause n°1 des faux `SAUT REFUSE` |

```bash
# recuperer le WAV de la session (l'horodatage du dossier == debut de session)
adb -s <serial> shell "run-as com.corankarim.coran_karim ls -t app_flutter/recitation_captures/ | head -3"
adb -s <serial> shell "run-as com.corankarim.coran_karim tar cf - -C app_flutter/recitation_captures/<session> ." > s.tar && tar xf s.tar
# balayer : largeurs 4 s ET 6 s, pas = largeur/2, sur TOUTE la duree
PYTHONPATH="benchmark/.venv_nemo/lib/python3.14/site-packages" \
  /usr/bin/python3.14 benchmark/balayer_flux_brut.py <stream_*.wav> 0 <duree>
```

⚠️ Le venv `.venv_nemo` est **obligatoire** (`onnxruntime` n'est pas dans le
python système), et son `bin/python3.14` est un symlink cassé : passer par
`PYTHONPATH` + `/usr/bin/python3.14`, comme ci-dessus. Le HDD porte le SDK
Android — si Gradle échoue soudain sur « SDK location not found », c'est le
disque qui s'est démonté, pas le code.

⚠️ **Deux largeurs au minimum, jamais une seule.** Mesure du 2026-07-28 : `عظيم`
est parfait à 3 s et introuvable à 12 s. Une largeur unique fait conclure
« absent » sur un mot présent.

**Ce que ce balayage a permis de trancher le 2026-08-06**, et qu'aucune lecture
de log n'aurait donné : l'utilisateur signalait « il se mêle avec cette
sourate ». Le balayage a montré Al-Kâfirûn récitée en entier et correctement
(0-30 s), PUIS répétée (36-48 s). La cible chargée était bien Al-Kâfirûn --
donc **aucun mélange de sourate** : le vrai mécanisme était la RÉPÉTITION d'un
passage qui figure deux fois dans la sourate (`وَلَآ أَنتُمْ عَـٰبِدُونَ مَآ
أَعْبُدُ`). Sans le balayage, l'hypothèse « mauvaise sourate chargée » aurait
été retenue -- elle avait d'ailleurs été affirmée à tort avant vérification.

## Étape 5 — Confronter à l'AUDIO, toujours

Un verdict n'est établi qu'après vérification sur le son. Le log seul dit ce que
l'app a cru, pas ce qui a été prononcé.

```bash
SESS=$(adb shell "run-as com.corankarim.coran_karim ls -t app_flutter/recitation_captures/ | head -1" | tr -d '\r')
adb shell "run-as com.corankarim.coran_karim tar cf - -C app_flutter/recitation_captures/$SESS ." > s.tar && tar xf s.tar
```

Deux sources, et elles ne disent pas la même chose :

- **`stream_*.wav`** — le flux micro BRUT, avant le portier RMS. C'est la
  vérité de ce qui a été prononcé.
- **`clip_*.wav`** — uniquement l'audio CONSOMMÉ par les segments figés,
  contigus et sans recouvrement.

**Le test décisif** : décoder le flux brut (fenêtres de 8 s, saut de 5 s) et
vérifier si le mot litigieux s'y trouve.

| brut | clips | conclusion |
|---|---|---|
| OUI | OUI | l'audio était là, c'est l'ALIGNEMENT qui a échoué |
| OUI | non | perdu entre le micro et le clip (portier, ou segment non enregistré) |
| non | non | à écouter : limite du modèle, ou mot réellement non prononcé |

Comparer aussi le **total** : `somme(clips)` contre `stream`. Un écart signale
de l'audio perdu (ou dupliqué, si les clips dépassent).

Le banc `benchmark/bench_double_decoupage.py` prend le `stream_*.wav` et compare
les politiques de découpage sur le taux de mots en frontière.

## Étape 6 — Les métriques, et lesquelles ne veulent rien dire

| métrique | où | piège |
|---|---|---|
| `VALIDATION retard=` | ligne `segment FIGE` | **c'est la latence**, pas la cadence. Une valeur epoch (>10⁶ ms) = `segmentStartWallMs` à 0, à ignorer |
| audio neuf par gel | `consomme=` + `apercu reutilise, Ns couverts` | les gels à la borne dure n'ont pas de `consomme=` — les compter à part |
| `place=` d'un ZERO FRAME | ligne `ZERO FRAME` | **le discriminant** : quelques frames = frontière normale ; plusieurs secondes = la DP a décroché |
| avancée de l'ancre | `final=true … nouvelle_ancre=` | ne compter que les passes **finales** ; les aperçus n'avancent rien |

**Erreur de méthode déjà commise** : conclure « pas de retard » parce que la
*cadence* de coloration était régulière à 1,6 s. Une cadence régulière avec une
file qui grossit, c'est précisément un arriéré. Mesurer la **latence**.

**Contrôle décisif de l'arriéré** : comparer l'heure du dernier bloc PCM reçu à
celle de la dernière validation. Des validations postérieures à l'arrêt du micro
= file d'attente, quel qu'en soit le motif.

## Étape 7 — Le compte rendu : UN SEUL FORMAT, TOUJOURS LE MÊME

Consigne explicite de l'utilisateur : *« à chaque fois tu changes la
présentation, ajoute dans le skill le même format »*. La dérive venait de ce que
le compte rendu était coupé en DEUX tableaux (signalés d'un côté, non jugés de
l'autre) : cette séparation invite à en oublier un, et à réinventer la forme à
chaque session.

**Un seul tableau, une ligne par mot non vert, colonnes dans cet ordre, sans
exception :**

```
| mot | attendu | entendu | état | gop | forced | free | frames | marge | cause | dans le WAV ? | mécanisme |
```

> **FORMAT v2 (2026-08-06).** Les colonnes `chemin` et `2ᵉ buffer` sont
> retirées : les deux mécanismes qu'elles décrivaient n'existent plus (cf. le
> bandeau en tête). Trois colonnes les remplacent, toutes disponibles telles
> quelles dans la ligne `[CTL][V2] mot=` :
> - **gop** — `forced − free`. Le discriminant principal.
> - **frames** — nombre de frames émises. `frames=1` sur un mot long est un
>   signal de troncature/pic d'émission, pas une durée.
> - **marge** — `margeL` / `margeH` (lettres / harakat). ⚠️ Une valeur en
>   `e+29` est une **SENTINELLE QUI FUIT**, pas une marge : la lire comme un
>   score est une faute. Signaler l'anomalie, ne jamais la moyenner.
>   Observée le 2026-08-06 (`margeL=3.33e+29`) — même famille de défaut que la
>   sentinelle divisée avant filtrage déjà corrigée dans `Tete3Traits`.
>
> Le tableau v1 d'origine reste valable pour relire un log d'archive.

- **mot** — index absolu.
- **attendu / entendu** — textes bruts du log. `(vide)` si `entendu=""`.
- **état** — 🔴 rouge / 🟠 orange / ⚪ non jugé. Les trois dans le MÊME tableau.
- **forced / free** — tels quels. `free` proche de 0 = le modèle est certain de
  ce qu'il a reçu, donc ce n'est PAS une faute de prononciation.
- **cause** — la ligne de log qui l'explique (cf. Étape 3). Jamais « divers » :
  un mot sans cause est un trou de diagnostic, à nommer comme tel.
- **chemin** — `gel normal` ou `borne dure` (cf. Étape 3 bis). Sans cette
  colonne on attribue à l'algorithme ce qui appartient au chemin de code.
- **dans le WAV ?** — `brut / clips`, chacun OUI / non / *(non vérifié)*, et le
  texte réellement décodé quand il diffère de l'attendu. Voir ci-dessous.
- **2ᵉ buffer** — ce qu'a fait le secours : `SECOURS` (rattrapé), `SANS GAIN`,
  `IMPOSSIBLE`/`IGNORE`, ou **`non tenté`** avec la raison. « non tenté » est un
  résultat à part entière, et le plus fréquent quand un garde est mort.
- **mécanisme** — A, B, C (cf. Étape 4), ou « faute réelle ».

**Puis, et seulement après le tableau :**

1. le bilan chiffré, avec le total qui boucle (`verrouillés + non jugés = ancre`)
   et le taux de mots **non verts** ;
2. **le tableau du 2ᵉ buffer, une ligne par TENTATIVE de secours** (cf. Étape
   3 ter) — jamais un simple compte, et jamais seulement les échecs : les
   rattrapages avec leur texte montrent ce que le mécanisme sait faire ;
3. le regroupement par mécanisme, avec ce que chacun implique ;
4. ce qui reste inexpliqué, nommé comme tel.

### La colonne « dans le WAV ? » n'est pas optionnelle

C'est elle qui distingue une analyse d'un simple relevé. Pour chaque mot du
tableau, décoder le flux brut et chercher le mot :

| brut | clips | conclusion à écrire dans la colonne « mécanisme » |
|---|---|---|
| OUI | OUI | l'audio était là : c'est l'ALIGNEMENT qui a échoué |
| OUI | non | perdu entre le micro et le clip |
| non | non | limite du modèle, ou mot réellement non prononcé — à écouter |

**Une recherche de sous-chaîne ne suffit PAS à écrire « non ».** Erreur commise
le 2026-07-27 : un test `mot_normalisé in transcription` a rendu trois « non »
dont **aucun n'était vrai**. Le modèle décode souvent le mot avec une lettre
en moins ou une quasi-homophone :

| attendu | réellement décodé | ce qu'un test naïf conclut |
|---|---|---|
| `قَامُوا۟` | `قَالُوا۟` (م → ل) | « absent » — faux, il est là |
| `لَذَهَبَ` | `لَهَبَ` (ذ tombé) | « absent » — faux |
| `ٱلْبَرْقُ` | `ٱلْبَرُْ` (ق tombé) | « absent » — faux |

⇒ Dès qu'un mot ressort « non », **imprimer les fenêtres décodées de la zone**
(repérer la zone par ses mots voisins, pas par le mot cherché) et lire le texte
réel. Ce n'est qu'après cette lecture qu'on peut écrire « non ».

⇒ Le modèle exact compte : tirer `model.onnx` **du téléphone** et vérifier que
sa taille correspond à celle du device. Un export frère du même jour n'est pas
le même binaire (constaté : 461 433 499 octets sur le PC contre 458 789 544 sur
l'appareil).

**Le mode change l'interprétation, le dire explicitement :**

- récitation d'un **récitateur rejoué en continu** : chaque mot est forcément
  prononcé, donc tout `entendu` vide est un defaut de l'app ;
- **voix de l'utilisateur** : un `entendu` vide peut signifier qu'il n'a
  réellement pas prononcé le mot. Ne jamais conclure sans le WAV.

Si la vérification audio n'a pas été faite, écrire *(non vérifié)* dans la
colonne — jamais laisser croire qu'elle l'a été.

## Rationalisations à refuser

| ce qu'on se dit | la réalité |
|---|---|
| « les non jugés, c'est du détail » | ils peuvent être plus nombreux que les erreurs ; l'utilisateur l'a redemandé deux fois |
| « le log suffit » | le log dit ce que l'app a cru. Le flux brut dit ce qui a été prononcé |
| « la cadence est régulière, donc pas de retard » | cadence ≠ latence. Erreur commise le 2026-07-27 |
| « ce mot est absent des clips, donc perdu » | vérifier le flux brut d'abord : 35 % de l'audio n'était pas enregistré à cause d'un chemin de gel oublié |
| « ces confusions de lettres sont de vraies fautes » | trois d'entre elles ont disparu une fois le contexte rétabli : c'étaient des troncatures |
| « je donne le taux d'erreurs » | donner le taux de mots **non verts**, qui inclut les non jugés |
| « la cause est probablement X » | si une ligne de log peut trancher, l'ajouter et refaire une passe. Trois hypotheses fausses ont coûté deux sessions le 2026-07-27 |
| « le mecanisme est en place, il ne doit pas se declencher souvent » | zero trace = indiscernable de zero execution. Instrumenter le declencheur, pas seulement le resultat |
| « le secours a fait 15 rattrapages sur 35, je donne le taux » | un taux n'est pas un diagnostic. Une ligne par TENTATIVE : c'est la largeur et la repetition des fenetres qui separent les 15 reussites des 15 echecs (Etape 3 ter) |
| « je reconstitue l'audio du secours en concatenant les clips » | verifie d'abord que somme(clips) < flux brut. Le 2026-07-28 les clips faisaient 319,0 s pour 310,2 s de brut : dupliques, donc toute position absolue en est faussee |
| « SANS GAIN avec entendu vide, donc le mot n'est pas dans l'audio » | ca dit que la DP n'a rien place dans LA FENETRE. Une fenetre mal posee ou trop large donne exactement la meme ligne |
| « mon signal de declenchement est le mauvais » | avant d'accuser le signal, verifier que le CODE peut l'atteindre. Le 2026-07-27 le garde `lastAlignSpf > 0` etait toujours faux : le signal n'a jamais ete lu |
| « le mot n'est pas dans la transcription, donc absent du WAV » | trois « non » sur trois etaient faux : lettre tombee ou quasi-homophone. Lire les fenetres decodees de la zone |
| « 16 echecs sur 18 viennent de ce chemin, c'est lui le coupable » | rapporter au trafic : ce chemin portait 89 % des mots et echouait au meme taux. Un effectif n'est pas un taux |
| « j'ai le fichier du modele sur le PC, c'est le meme » | comparer la taille avec celle du device. Deux exports du meme jour different |
| « le mecanisme n'a pas tourne, il n'y a aucune ligne » | verifier D'ABORD qu'il existe encore. Sur v2, `secours mot=`/`segment FIGE`/`ZERO FRAME` valent 0 parce que le CODE a ete supprime, pas parce qu'un garde est faux (2026-08-06) |
| « le decrochage n'est pas detecte » | compter les QUATRE etages (natif / signal / wordFailed / audio). Le 2026-08-06 il etait detecte 25 fois, transmis 14, execute 8 — le defaut etait en aval, pas dans la detection |
| « la correction ne part pas, donc le seuil est mauvais » | avant de toucher un seuil : lire les `IGNORÉ`. Une soiree entiere de correctifs sur le seuil, alors que la cause etait un REGLAGE persiste a `false` et une course d'initialisation (2026-08-05) |
| « ce mot est `provisoire:vert`, donc il est vert » | `provisoire` = JAMAIS VERROUILLE = non vert. Le compter comme tel |
| « l'app dit `omis`, le recitateur a saute ce mot » | `omis` est le verdict le plus grave : le confronter au WAV. Le 2026-08-06, deux `omis` portaient sur une Bismillah parfaitement audible |
| « l'ancre monte au-dela de la cible, tant mieux » | verifier `cible etendue` : sans elle les mots au-dela ne pouvaient PAS etre juges, et le taux calcule dessus est faux (defaut trouve le 2026-08-05) |
| « margeL vaut 3e+29, c'est une marge enorme » | c'est une SENTINELLE qui fuit — une valeur inatteignable utilisee comme « pas de candidat ». La lire comme un score fausse toute moyenne |
| « la session est en mode confiant mais ca teste quand meme » | `modeConfiant=true` coupe le decrochage a la source (`if (_confidentMode) return`). Cette session ne valide RIEN sur le decrochage |
