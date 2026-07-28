---
name: analyse-session-recitation
description: Analyser une session de récitation sur device (log + WAV) et en tirer un compte rendu causal complet. À invoquer dès que l'utilisateur dit « regarde la log », « analyse », « qu'est-ce qui cloche », ou fournit une session à examiner.
---

# Analyser une session de récitation

Ce skill existe parce que cette analyse a été refaite une dizaine de fois le
2026-07-27, **à la main, et qu'une omission ou une erreur de méthode s'est
glissée à chaque fois**. Les pièges ci-dessous sont tous des erreurs réellement
commises ce jour-là, pas des précautions théoriques.

## Règle n°1 — ne JAMAIS omettre les mots non jugés

L'utilisateur l'a redemandé deux fois : *« il y a aussi les non jugés à blanc,
il ne faut pas les exclure quand je te demande d'analyser »*.

Un mot peut ne pas être vert de **trois** façons, et un compte rendu qui n'en
présente qu'une est faux :

| état | visible à l'écran | où le lire |
|---|---|---|
| signalé (rouge/orange) | cadre coloré | `[GOP] … -> WordStatus.error/unclear (lock=true)` |
| **non jugé** | **aucun cadre** | absent des lignes `lock=true` |
| jamais atteint | gris | au-delà de l'ancre max |

Le total doit **toujours** boucler : `verrouillés + non jugés = ancre max`.
Annoncer « 2,8 % d'erreurs » alors que 7,4 % des mots ne sont pas verts, c'est
donner le chiffre flatteur.

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

## Étape 3 bis — Par quel CHEMIN le mot a-t-il été verrouillé ?

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

## Étape 3 ter — Le 2ᵉ buffer : TOUS les secours, un par ligne

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
| mot | attendu | entendu | état | forced | free | cause | chemin | dans le WAV ? | 2ᵉ buffer | mécanisme |
```

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
