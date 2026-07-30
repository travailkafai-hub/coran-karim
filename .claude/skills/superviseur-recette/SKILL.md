---
name: superviseur-recette
description: Superviseur de développement — passe DERRIÈRE l'agent après toute modification de la chaîne de récitation pour vérifier que le socle tient : le récitateur récite, l'app contrôle en streaming et dit vrai. Porte la vision globale que l'agent perd quand il corrige un défaut précis. À relancer systématiquement après chaque correctif, sans attendre qu'on le demande.
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
| « le taux a baissé, c'est bon » | vérifier 1-2-3 d'abord : un taux qui baisse parce que des mots ont quitté le dénominateur est un faux gain |
| « je n'ai touché qu'à l'aligneur » | le coach, les jeux et le tajwid partagent le découpage des mots |
| « c'est un petit changement » | le plus gros dégât de la journée est venu d'un commit intitulé « Banc : … » |
| « je vérifierai après » | l'agent qui écrit ne voit pas ce qu'il casse — c'est la raison d'être de ce skill |
| « une passe suffit » | pour montrer un gain peut-être ; pour prouver une non-régression, tous les contrôles |
