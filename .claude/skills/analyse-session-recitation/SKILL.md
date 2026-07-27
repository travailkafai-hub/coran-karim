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
| mot | attendu | entendu | état | forced | free | cause | dans le WAV ? | mécanisme |
```

- **mot** — index absolu.
- **attendu / entendu** — textes bruts du log. `(vide)` si `entendu=""`.
- **état** — 🔴 rouge / 🟠 orange / ⚪ non jugé. Les trois dans le MÊME tableau.
- **forced / free** — tels quels. `free` proche de 0 = le modèle est certain de
  ce qu'il a reçu, donc ce n'est PAS une faute de prononciation.
- **cause** — la ligne de log qui l'explique (cf. Étape 3). Jamais « divers » :
  un mot sans cause est un trou de diagnostic, à nommer comme tel.
- **dans le WAV ?** — OUI / non / *(non vérifié)*. Voir ci-dessous.
- **mécanisme** — A, B, C (cf. Étape 4), ou « faute réelle ».

**Puis, et seulement après le tableau :**

1. le bilan chiffré, avec le total qui boucle (`verrouillés + non jugés = ancre`)
   et le taux de mots **non verts** ;
2. le regroupement par mécanisme, avec ce que chacun implique ;
3. ce qui reste inexpliqué, nommé comme tel.

### La colonne « dans le WAV ? » n'est pas optionnelle

C'est elle qui distingue une analyse d'un simple relevé. Pour chaque mot du
tableau, décoder le flux brut et chercher le mot :

| brut | clips | conclusion à écrire dans la colonne « mécanisme » |
|---|---|---|
| OUI | OUI | l'audio était là : c'est l'ALIGNEMENT qui a échoué |
| OUI | non | perdu entre le micro et le clip |
| non | non | limite du modèle, ou mot réellement non prononcé — à écouter |

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
