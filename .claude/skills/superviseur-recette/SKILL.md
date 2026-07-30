---
name: superviseur-recette
description: Superviseur de développement — passe DERRIÈRE l'agent après toute modification de la chaîne de récitation pour vérifier que le socle tient : le récitateur récite, l'app contrôle en streaming et dit vrai. Interroge d'abord le GRAPHE (pistes [MORT], [PIEGE], couche où le symptôme naît, couplage invisible entre commits) avant de lire le diff. Porte la vision globale que l'agent perd quand il corrige un défaut précis. À relancer systématiquement après chaque correctif, sans attendre qu'on le demande.
---

# Superviseur — le socle, c'est réciter et contrôler

Ce skill existe parce que l'agent, quand il corrige un défaut, **corrige les
yeux fermés** : il regarde le symptôme qu'on lui a signalé, pas l'ensemble qu'il
traverse. Il perd la vision globale, et il casse.

Consigne utilisateur, 2026-07-30 : *« à chaque fois je te demande de trouver un
problème, tu corriges un peu les yeux fermés. Tu n'as pas une vision globale et
du coup tu fais beaucoup de casse. »*

Il ne mesure pas un taux. Il répond à une question : **le socle tient-il
encore ?**

---

## LE SOCLE

**Le récitateur récite. L'app contrôle, en streaming, et dit vrai.**

Tout le reste de l'application est construit là-dessus. Si ce socle se fissure,
le taux de mots verts n'a aucune importance.

Décomposé, ce socle impose quatre choses — et elles sont hiérarchisées :

```
        1. DIRE VRAI          ← si ça tombe, l'app est nuisible
              ↑
        2. SUIVRE             ← si ça tombe, l'app est inutilisable
              ↑
        3. EN STREAMING       ← si ça tombe, ce n'est plus la même app
              ↑
        4. bien juger (taux)  ← seulement si 1-2-3 tiennent
```

### 1. DIRE VRAI — le plus grave

L'app existe pour dire à quelqu'un si sa récitation est juste. Un verdict faux
est pire que pas de verdict.

- **Aucun verdict sans preuve acoustique.** Un mot verrouillé `error` avec
  `entendu=""` condamne l'utilisateur sur du vide. Règle projet : *pas de rouge
  sans preuve*.
  ```bash
  grep -c 'entendu="".*WordStatus\.error (lock=true' $S     # DOIT valoir 0
  ```
- **Aucun mot à moitié prononcé ne passe vert.** C'est la fonction même de
  l'app. Un palliatif allant dans ce sens a déjà été refusé (2026-07-25) :
  *« un récitateur qui ne dit que la moitié d'un mot était alors validé —
  précisément ce que l'app existe pour détecter »*.
- **Un verdict affiché ne se contredit pas** : un mot verrouillé ne se rejuge
  pas.

### 2. SUIVRE — le récitateur ne doit jamais être perdu de vue

- l'ancre progresse jusqu'au bout de ce qui a été récité
  (référence : ~295-302 mots sur `DEPART=6`, 420 s) ;
- **aucun bloc de plus de 5 mots contigus sans jugement** — un bloc, c'est
  l'utilisateur qui récite dans le vide sans retour ;
- chaque `RESYNC` abandonne des mots sans les juger : les compter, ils sont
  invisibles autrement ;
- l'audio n'est ni détruit ni dupliqué : somme des clips ≈ flux brut (±10 %).
  Un mot dont l'audio est jeté ne pourra JAMAIS être jugé, à aucune couche.

### 3. EN STREAMING — juger pendant, pas après

- `VALIDATION retard=` borné (référence ~9-11 s) et ne croît pas sans fin ;
- pas de cascade de gels (plusieurs en moins d'une seconde) ;
- le modèle chargé est bien celui attendu (`subdir=models/...`) — « modèle
  chargé » ne prouve rien sur son utilisabilité, vérifier une vraie
  transcription.

### 4. BIEN JUGER — le taux

**Seulement si 1, 2 et 3 tiennent.** Un gain de taux obtenu en dégradant un
niveau supérieur est un faux gain, à rejeter sans discussion.

---

## CE QUI REND CE SOCLE DIFFICILE — à avoir en tête avant de juger un correctif

- **C'est du streaming** : juger sur un audio incomplet, sans jamais revenir sur
  un verdict affiché. Un correctif qui « attend d'en savoir plus » casse le
  streaming.
- **Le texte coranique se répète** : `كَمَآ ءَامَنَ` deux fois dans le seul verset
  2:13, `يُخَـٰدِعُونَ`/`يَخْدَعُونَ` à cinq mots d'écart au verset 9. L'appariement
  est ambigu **par nature**, pas par défaut d'implémentation.
- **Le récitateur peut répéter** un passage — c'est licite, et l'algorithme
  actuel ne sait pas le suivre (`findResyncOffset` ne cherche qu'en avant).
- **Trois scores, trois questions différentes** : `free` (le modèle est-il sûr de
  ce qu'il entend ?), `forced` (colle-t-il à la cible ?), `gop` = forced − free
  (l'écart). Un `gop` effondré avec un `free` normal signifie *mauvaise
  position*, pas *mauvaise prononciation*. Confondre les deux fait chercher au
  mauvais endroit.
- **Le 2ᵉ buffer rejoue le MÊME aligneur sur le MÊME audio de segment.** Quand
  le segment est le problème (trop long, mot coupé à la frontière), le secours
  est impuissant par construction — pas aveugle, impuissant.

---

## COMMENT SUPERVISER

### a0) INTERROGER LE GRAPHE — le tout premier geste, avant de lire le diff

*Ajouté le 2026-07-30 : ce skill a été écrit AVANT que le graphe existe. Sans
cette étape, le superviseur ne pouvait vérifier qu'une chose — que le correctif
ne casse rien **aujourd'hui**. Il ne pouvait pas voir qu'il avait déjà été
mesuré perdant **hier**.*

Le graphe (`GRAPHE_RECITATION.md`, `graphify-out/graph.json`) encode
**184 commits, les diffs réels des 91 qui touchent cette chaîne, et 63 corps de
message portant des mesures chiffrées**. C'est la seule source du projet qui
dise ce qui a été *mesuré*, pas ce qui a été *espéré*.

**Trois questions, dans cet ordre, sur CHAQUE mécanisme introduit ou retiré :**

```bash
graphify query "MORT <le mécanisme introduit>"      # a-t-il déjà été mesuré perdant ?
graphify query "PIEGE <la couche touchée>"          # erreur déjà commise ici ?
graphify query "SYMPTOME <le défaut corrigé>"       # dans quelle couche NAÎT-il ?
graphify path "<la variable touchée>" "⑥ Jugement et affichage (Dart)"
```

⚠️ **La traversée apparie sur le vocabulaire des libellés** : une question posée
avec des mots absents du graphe remonte du bruit, ce qui se lit à tort comme
« rien de connu là-dessus ». Quand le sujet est un mécanisme et non une phrase,
la lecture **exhaustive** est plus sûre et coûte deux secondes :

```bash
python3 - <<'EOF'
import json
g = json.load(open('graphify-out/graph.json'))
for n in g['nodes']:
    if n['label'].startswith(('[MORT]', '[PIEGE]', '[SYMPTOME]', '[EN ATTENTE]')):
        print(n['label'], '\n   ', n.get('rationale'), '\n')
EOF
```

**Ce que le superviseur en fait — trois verdicts possibles :**

| ce que le graphe dit | verdict |
|---|---|
| le mécanisme est un nœud `[MORT]` | **BLOQUANT.** Le correctif est refusé, sauf si l'agent produit une **cause nouvelle** (autre modèle, autre régime) et la nomme. « Cette fois c'est différent » n'est pas une cause nouvelle. |
| le symptôme corrigé NAÎT dans une couche plus haute que celle modifiée | **BLOQUANT** — c'est la définition d'un palliatif (règle projet). |
| le mécanisme est `[EN ATTENTE]` | recevable : citer le commit et ce que sa mesure disait, et dire ce qui a changé depuis. |

**Vérifier aussi le couplage invisible**, la question qui a motivé la
construction du graphe (*« entre plusieurs commits il y a parfois le même
fonctionnement, et une petite fonctionnalité ou variable qui touche à plusieurs
couches »*) : les arêtes `commit ↔ commit` (`semantically_similar_to`, 843
arêtes) relient **deux commits qui touchent le même symbole même si rien ne le
dit**. C'est ce couplage-là qui produit les régressions en cascade.

```bash
python3 - <<'EOF'
import json
SYMB = "runAlignment"          # <- le symbole touché par le correctif
g = json.load(open('graphify-out/graph.json'))
lab = {n['id']: n['label'] for n in g['nodes']}
for e in g['links']:
    if SYMB in (e.get('source_location') or ''):
        print(lab.get(e['source'], e['source']), '<->', lab.get(e['target'], e['target']))
EOF
```

Les points chauds connus, à traiter comme des zones à risque **même si le diff
paraît anodin** : `runAlignment` (réécrit **7×**), `OVERLAP_SECONDS` (**6×**),
`computeLogProbs` (6×), `appendMergingOverlap` (5×), `MAX_SILENCE_SAMPLES` (4×),
`RESYNC_ACTIF` (3×), `RIGHT_CONTEXT_SECONDS` (3×). Un code qui n'a jamais
convergé en sept tentatives ne converge pas à la huitième par chance : exiger
que le correctif dise **quelle classe de défauts il supprime**, pas quel cas il
règle.

**Après une mesure, le graphe se met à jour.** Une piste nouvellement réfutée
qui ne devient pas un nœud `[MORT]` avec son chiffre sera repayée — c'est
exactement ce qui est arrivé neuf fois (`piege_9_versions_perdues`).

### a) Revue du code — avant toute mesure

1. **Relire le diff en entier**, pas seulement les lignes ajoutées.
2. **Qui d'autre lit ou écrit ce que j'ai touché ?** `grep` sur chaque variable
   et fonction — jamais de mémoire.
3. **Est-ce un contrat partagé ?** `splitExpectedWords`, `RecitedWord`,
   `setup()`/`start()`, les timings mot-à-mot sont utilisés **hors récitation**
   (coach, jeux de mémorisation, coloration tajwid). Y toucher casse plusieurs
   domaines d'un coup — étendre le contrôle.
4. Aucun commentaire existant supprimé (règle projet : c'est la seule trace de
   ce qui a déjà été tenté).
5. Tag de build changé **avant** le build, sinon la mesure sera attribuée à la
   mauvaise version.
6. `git status` : aucun fichier de chaîne indexé par accident
   (cf. `.claude/hooks/garde-index-chaine.py`).

### b) Une passe, puis analyse

```bash
DEPART=6 ADB=adb bash benchmark/recette_2tel.sh 2 420
python3 benchmark/taux_non_verts.py <dossier>/
```

Puis le **tableau non-verts**, qui vient AVANT toute interprétation : une ligne
par mot non vert, avec `attendu`, `entendu`, `gop`, `forced`, `free`, les
`ZERO FRAME` (chemin principal ET secours, séparés) et la colonne **2ᵉ buffer**
(`RATTRAPÉ a→b` / `SANS GAIN` / `SANS RÉSULTAT` / `IMPOSSIBLE` / jamais appelé).

### c) Les contrôles

```bash
S=<dossier>/session.log
grep -m1 'BUILD code=' $S                                    # bon binaire ?
grep -m1 'modele charge=' $S                                 # bon modèle ?
grep -oE 'nouvelle_ancre=[0-9]+' $S|sed 's/.*=//'|sort -n|tail -1
grep -c 'RESYNC' $S
grep -c 'entendu="".*WordStatus\.error (lock=true' $S        # BLOQUANT : 0
grep 'segment FIGE' $S | cut -c1-23 | uniq -d                # cascade de gels
grep -oE 'VALIDATION retard=[0-9]+' $S|sed 's/.*=//'|sort -n|tail -1
```

### d) Le tableau avant/après — obligatoire

Un correctif ne se juge jamais seul.

| contrôle | avant | après | verdict |
|---|---|---|---|
| **verdicts sans preuve** (bloquant) | | | |
| ancre finale | | | |
| blocs abandonnés / RESYNC | | | |
| écart clips / brut | | | |
| retard max | | | |
| `flutter analyze` | | | |
| taux non verts | | | |

**Toute case qui se dégrade doit être expliquée, ou le correctif est annulé.**

---

## CE QUE LE SUPERVISEUR REFUSE

- **un mécanisme que le graphe porte déjà en `[MORT]`, réintroduit sans cause
  nouvelle nommée** — c'est le refus n°1 depuis le 2026-07-30 ;
- **un correctif dont le graphe dit que le symptôme naît dans une couche plus
  haute** que celle touchée (palliatif) ;
- un effet indistinguable de l'étendue du banc (±4 points) présenté comme un
  gain ;
- un gain de taux accompagné d'une dégradation d'un niveau 1-2-3 ;
- de la tolérance ajoutée en aval d'une perte d'information en amont (règle
  projet « pas de correctif palliatif ») ;
- un correctif dont on ne sait pas dire **quelle classe de bugs il supprime** ;
- une mesure sur un binaire dont le tag ne correspond pas au code (piège payé :
  v8 mesuré sous l'étiquette v23 pendant des heures) ;
- une modification d'un contrat partagé sans vérifier ce qui en dépend.

## RATIONALISATIONS À REFUSER

| ce qu'on se dit | la réalité |
|---|---|
| « le graphe ne dit rien là-dessus » | la traversée apparie sur le VOCABULAIRE des libellés : une question mal formulée remonte du bruit, jamais « rien ». Relire les nœuds à préfixe en entier avant de conclure |
| « c'était mesuré sur l'ancien modèle, donc ça ne compte pas » | vrai parfois (avertissement §1.5 : les mesures pré-causal ne se transportent pas), mais c'est une CAUSE NOUVELLE à écrire, pas un droit de passage |
| « le taux a baissé, c'est bon » | vérifier 1-2-3 d'abord : un taux qui baisse parce que des mots ont quitté le dénominateur est un faux gain |
| « je n'ai touché qu'à l'aligneur » | le coach, les jeux et le tajwid partagent le découpage des mots |
| « c'est un petit changement » | le plus gros dégât de la journée est venu d'un commit intitulé « Banc : … » |
| « je vérifierai après » | l'agent qui écrit ne voit pas ce qu'il casse — c'est la raison d'être de ce skill |
| « une passe suffit » | pour montrer un gain peut-être ; pour prouver une non-régression, tous les contrôles |
