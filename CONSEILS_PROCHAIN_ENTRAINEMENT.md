# Conseils pour le prochain entraînement — ce que les sessions réelles ont appris

Fichier initialisé le **2026-08-14** à la demande de l'utilisateur, après
l'analyse de la récitation d'Al-Fil : *« faut créer un fichier s'il y a des
remarques, conseils pour un nouvel entraînement pour éviter ce type de
problème »*.

**Ce document ne rassemble QUE des défauts constatés sur une session réelle,
avec leur preuve chiffrée.** Pas d'idée générale d'amélioration : celles-là
vivent dans `FONCTIONNALITES_FUTURES.md` et `PLAN_ENTRAINEMENT_HYBRIDE.md`.
Chaque entrée doit dire : le symptôme vu à l'écran, la mesure qui l'établit, et
ce qu'il faut changer **dans le dataset ou l'entraînement** (pas dans un seuil).

Avant tout entraînement : invoquer le skill `model-training` (règle
`CLAUDE.md`).

---

## 1. Désaccord d'orthographe entre la CIBLE et ce que le modèle ÉMET

**C'est le défaut n°1 de la session du 2026-08-14 : deux des quatre mots non
verts ne sont pas des fautes de récitation, mais des désaccords de graphie.**

### Le symptôme

| mot | cible (texte de l'app) | ce que le modèle émet | gop | verdict |
|---|---|---|---|---|
| `تَرْمِيهِم` | م final **nu** | `تَرْمِيهِمْ` (م + soukoun U+0652) | **−0,46** | 🟠 orange |
| `مَّأْكُولٍۭ` | tanwin + **petit meem** U+06ED | `مَّأْكُولٍ` (sans le signe) | **−0,69** | 🟠 orange |

Seuil de vert : **−0,45**. Le premier échoue **à 0,01 près**.

### La mesure qui l'établit

- Balayage du flux brut (`benchmark/balayer_flux_brut.py`, largeurs 4 s et 6 s)
  sur `stream_1786732781103.wav` : `تَرْمِيهِمْ` est décodé **avec** le soukoun
  dans **toutes** les fenêtres où il apparaît (16-20 s, 18-22 s, 15-21 s,
  18-24 s). Le modèle n'hésite pas : `free = −0,07`, il est certain de ce qu'il
  entend. Le coût est **entièrement** dans l'alignement forcé sur une cible
  qu'il juge improbable.
- Vocabulaire du modèle déployé (`trois-tetes-2026-08-04-combine`, 1024 tokens) :
  - U+0652 (soukoun) apparaît dans **242** tokens — dont `هُمْ`, `ُمْ`, `مْ` ;
  - U+06ED (petit meem d'iqlab) n'existe que dans **1** token isolé (`ۭ`).

Autrement dit : la forme **avec** soukoun est massivement représentée, la forme
**sans** ne l'est presque pas, et le signe d'iqlab est à la limite du hapax. La
cible demande au modèle exactement ce qu'il n'a pas appris.

### Pourquoi ces signes existent dans la cible

Ce ne sont pas des erreurs du texte : ce sont des **marques contextuelles de
tajwid** du Mushaf. Le م de `تَرْمِيهِم` est nu parce qu'il est suivi de
`بِحِجَارَةٍ` (ikhfa' shafawi) ; le petit meem de `مَّأْكُولٍۭ` annonce l'iqlab
du tanwin. Elles dépendent du **mot suivant**, donc un même mot s'écrit
différemment selon son voisin.

### 🛑 AUCUN RÉENTRAÎNEMENT N'EST NÉCESSAIRE — ET LE MÉCANISME EXISTE DÉJÀ

Question utilisateur, 2026-08-14 : *« du coup pour gérer l'équivalence on n'a
pas besoin d'un nouvel entraînement, il faut gérer le forced non ? »* — **oui,
exactement**, et c'est vérifié dans le code :

| ce qu'on croyait devoir faire | ce qu'il faut réellement faire |
|---|---|
| réentraîner sur un corpus normalisé | **rien côté modèle** — il sait déjà émettre les deux formes, ses tokens existent |
| inventer un mécanisme de variantes | **il tourne déjà** : `recitation2/Orthographe.kt`, branché dans `ChaineRecitation.ajouterMots` (`variantesAttendues`), l'aligneur retient le **meilleur** score |

L'en-tête d'`Orthographe.kt` pose déjà, mot pour mot, le principe formulé par
l'utilisateur : *« Ici on ne touche pas au critère : on corrige la CIBLE. Deux
graphies du même son sont la même cible acoustique »*, et *« une variante ne
rentre ici que si elle se prononce STRICTEMENT pareil »*.

**Ce qu'il couvre aujourd'hui** : alif suscrit (U+0670), alif wasla, madda,
waw/ya suscrits, madd tenu (lettre d'allongement doublée).

**Ce qu'il ne couvre pas — et ce sont exactement nos trois cas** :

| famille manquante | mot de la session | à ajouter |
|---|---|---|
| soukoun final présent / absent (U+0652) | `تَرْمِيهِم` | la forme avec ET sans |
| petit meem d'iqlab (U+06ED), et sa famille de signes de tajwid | `مَّأْكُولٍۭ` | la forme sans le signe |
| **waqf** : finale voyellée / finale en soukoun | tout mot en fin de verset | la forme en pause |

⚠️ **Point de vigilance avant d'y toucher** : `Orthographe.MAX = 7` et le
`out.take(MAX)` final. Ajouter des familles sans relever ce plafond ferait
**évincer silencieusement** des variantes déjà utiles (le madd tenu est généré
en dernier). Le coût d'une variante est un treillis minuscule sur les seules
frames du mot — **aucune passe d'encodeur supplémentaire** —, donc relever MAX
est peu coûteux, mais ça se mesure, ça ne se suppose pas.

⇒ **Le §1 n'est donc PAS un chantier d'entraînement.** Ce qui suit reste vrai
pour le dataset, mais en second rang : le défaut se ferme dans `Orthographe.kt`.

### ✅ LE PRINCIPE — DEUX VARIANTES EN PARALLÈLE (décision utilisateur 2026-08-14)

> « pour moi en mode Adulte il doit nettoyer l'attendu et mettre les deux
> options en parallèle, avec et sans. Si le modèle le détecte tant mieux, sinon
> on a le mot nettoyé qui ne va pas impacter le forced. Exactement la gestion
> du soukoun à la fin du mot : on doit avoir les deux options, avec soukoun
> présent et absent, car les deux c'est la même chose. »

**Le principe, et il faut le lire deux fois : ce n'est pas de la tolérance,
c'est de l'ÉQUIVALENCE.** Les deux graphies notent la même récitation. Aucune
des deux n'est une faute ; il n'y a donc rien à « pardonner ».

Concrètement, à l'alignement forcé : construire pour chaque mot **l'ensemble de
ses graphies canoniquement équivalentes**, aligner sur chacune, et **retenir le
meilleur score**. Le mot nettoyé sert de plancher — il garantit que le `forced`
ne peut plus être pénalisé par un signe que le modèle n'émet pas ; et si le
modèle produit la forme marquée, elle gagne d'elle-même.

| famille | exemple de cette session | pourquoi les deux formes sont justes |
|---|---|---|
| soukoun final de liaison | `تَرْمِيهِم` / `تَرْمِيهِمْ` | le م est nu à cause du mot suivant ; prononcé, c'est le même son |
| signes d'iqlab / ikhfa' | `مَّأْكُولٍۭ` / `مَّأْكُولٍ` | le petit meem note une règle de tajwid, pas un phonème de plus |
| **waqf en fin de verset** | tout mot final voyellé | **règle d'arabe** : on peut s'arrêter en soukoun sur la finale. Ce n'est pas une erreur, c'est la lecture en pause |

> « également ça peut arriver en fin de verset : on a bien une haraka, mais il
> est permis en arabe de prononcer le soukoun en fin, c'est la règle, et ça ne
> demande pas de souplesse parce qu'on n'est pas dans l'erreur. »

⇒ Le waqf doit donc être traité par le **même mécanisme** : la finale voyellée
et la finale en soukoun sont deux variantes du même mot, sur **tout mot en fin
de verset** — pas seulement là où le Mushaf porte un signe.

### ⛔ CE N'EST PAS « HARAKAT SOUPLE », ET LES CONFONDRE SERAIT UNE FAUTE

Distinction posée par l'utilisateur, et elle est structurante :

| | ce que ça couvre | statut de la récitation |
|---|---|---|
| **harakat souples** (`strictHarakat=false`) | une **vraie erreur** de voyelle — damma prononcée à la place d'une kasra — qu'on choisit de laisser passer en mode débutant | **fautive**, mais tolérée |
| **variantes équivalentes** (ce qui précède) | deux notations du **même son**, toutes deux correctes | **juste**, rien à tolérer |

Ranger le soukoun de liaison ou le waqf dans « harakat souples » aurait deux
conséquences inacceptables : ces cas deviendraient dépendants d'un réglage
d'indulgence (donc faux en mode strict, où ils sont pourtant justes), et ils
disparaîtraient de l'écran comme une erreur pardonnée alors qu'il n'y a jamais
eu d'erreur.

### Le lien avec la TÊTE TAJWEED — c'est elle qui devrait porter ces signes

Remarque utilisateur : *« tous ces signes, c'est en lien avec la tête
tajweed »*. C'est exact, et ça donne le partage des rôles :

- la tête **texte** (CTC) répond à « le bon mot a-t-il été dit ? » — elle ne
  doit pas être pénalisée par une marque de tajwid contextuelle ;
- la tête **tajweed** (tête 3) répond à « la règle a-t-elle été réalisée ? » —
  ikhfa', iqlab, madd. C'est là que ces signes ont un sens, et c'est là qu'ils
  doivent être jugés, avec leur propre verdict.

Faire porter à la tête texte un signe qui relève de la tête tajweed, c'est
mélanger deux questions et rendre orange un mot correctement prononcé — ce que
fait la chaîne aujourd'hui.

### Ce qui reste à faire au prochain entraînement (SECOND rang — le défaut se ferme sans lui)

1. **Aligner la normalisation du corpus sur celle du texte de l'app.** Vérifier,
   avant de lancer, que les transcriptions portent les mêmes marques
   contextuelles que `assets/data/quran_verses.json` — pas la forme « pleine »
   systématique. Un `diff` sur quelques centaines de mots suffit.
2. **Mesurer la couverture des signes rares avant de lancer.** Un signe présent
   dans la cible mais dans ≤ 2 tokens du vocabulaire est une pénalité garantie
   à l'alignement forcé. Sortir la table `signe → nb de tokens → nb
   d'occurrences dans le corpus` et traiter tout ce qui est sous le millier.
3. **Entraîner en connaissant les variantes** : si le corpus contient les deux
   graphies d'un même mot, le modèle apprend qu'elles sont interchangeables au
   lieu d'en privilégier une. C'est le pendant, côté données, du mécanisme de
   variantes à l'alignement.

### ⚠️ Ce qu'il ne faut PAS faire

**Ne pas toucher `seuilCorrect` (−0,45).** Les quatre non-verts de la session
sont entre −0,46 et −0,69 : un seuil à −0,70 les rendrait tous verts, y compris
celui qui correspond à un vrai écart de prononciation. On ne corrige pas un
désaccord de graphie par une tolérance de jugement (cf. skill
`solution-de-fond`) : les variantes équivalentes suppriment la classe entière
de défauts, un seuil déplacé ne fait que la cacher en ouvrant la porte aux
vraies fautes.

### ⚠️ Ce qu'il ne faut PAS faire

**Ne pas toucher `seuilCorrect` (−0,45).** Les quatre non-verts de la session
sont entre −0,46 et −0,69 : un seuil à −0,70 les rendrait tous verts, y compris
celui qui correspond à un vrai écart de prononciation. On ne corrige pas un
défaut de dataset par une tolérance de jugement.

---

## 2. Le م de `هُمْ` disparaît selon la fenêtre — instabilité, pas faute

| mot | cible | décodé selon la fenêtre |
|---|---|---|
| `كَيْدَهُمْ` | `هُمْ` | `كَيْدَهُمْ` à 10-14 s (complet) mais `كَيْدَهُ` à 12-16 s, 9-15 s, 12-18 s |
| `فَجَعَلَهُمْ` | `هُمْ` | `فَجَعَلَهُۥ` dans toutes les fenêtres (21-27 s, 22-26 s) |

Le premier cas prouve que **le م est bien prononcé** : il est décodé
correctement dès que le mot tombe au milieu de la fenêtre. Ce n'est donc pas le
récitateur, et ce n'est pas non plus le modèle « en général » — c'est la
POSITION du mot dans la fenêtre qui décide. Défaut de chaîne (fenêtrage), à
traiter côté v2, pas au réentraînement.

Le second cas, lui, est stable : le modèle rend `هُۥ` partout. Deux lectures
restent ouvertes, et il faut **écouter le WAV** pour trancher — la
confusion `هُمْ` / `هُۥ` est un candidat sérieux pour un renfort ciblé du
dataset (paires minimales sur les suffixes pronominaux).

**Piste concrète** : compter dans le corpus d'entraînement les occurrences de
`هُمْ` en fin de mot suivies d'une consonne, et vérifier que le modèle ne les
apprend pas majoritairement dans un seul contexte prosodique (fin de verset,
avec pause), ce qui expliquerait qu'il les rate en liaison.

---

## 3. Défaut hors entraînement, à ne pas oublier (2026-08-14)

Le preset affiche `strictHarakat=false` (« harakat souples »), et le code de
relâchement existe bien (`_relaxJudged`, `recitation_provider.dart`) : il rend
`correct` tout mot dont le **squelette de lettres** est identique.

**Mais il n'est jamais appelé sur la chaîne qui peint l'écran.** Depuis
`_v2PiloteAffichage = true`, le verdict vient du `Decideur` Kotlin et est
converti directement en `WordStatus` — le relâchement reste sur le chemin v1.
Le réglage est donc **inopérant** sur ce que voit l'utilisateur.

⚠️ **Ce défaut est réel, mais il ne doit PAS servir à régler le §1.** Réparer
`_relaxJudged` en v2 rendrait certes `تَرْمِيهِم` vert — au prix d'un
contresens : un mot juste serait alors validé par un mécanisme de PARDON, donc
uniquement quand l'utilisateur a choisi d'être indulgent, et resterait orange en
mode strict où il est pourtant parfaitement correct. Les deux sujets se règlent
séparément :
- graphies équivalentes → variantes à l'alignement (§1), **quel que soit le
  preset** ;
- vraie erreur de voyelle → `_relaxJudged`, à porter en v2 ou à retirer du
  réglage. Ne pas laisser un réglage visible qui ne fait rien.

À trancher avec l'utilisateur avant tout correctif (règle « proposer et faire
valider »).

---

*Chaque nouvelle session qui révèle un défaut imputable au dataset ou à
l'entraînement s'ajoute ici, avec sa mesure. Une entrée sans chiffre n'a rien à
y faire.*
