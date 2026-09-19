# DEMANDE PC A — régénérer `word_tokens.json` avec le tokeniseur d'entraînement

**Date** : 2026-09-18
**Origine** : faux rouges répétés en session réelle sur l'entraînement par
paliers (Al-Māʾida 5:2), analysés le soir même.
**Ce qui est demandé** : un `word_tokens.json` couvrant **tous** les mots du
Coran, produit par le **tokeniseur SentencePiece du modèle**, pas par un
repli glouton.

---

## 1. Le défaut observé sur l'appareil

Session d'entraînement par paliers, 13 tentatives entre 22:31 et 22:44, Samsung
SM-S931B, build `v467`, paquet `models/cinq-tetes-2026-09-11-madd-normal`.

Le mot **`تُحِلُّوا۟`** (5:2, mot 4) a été jugé **rouge 14 fois sur 14**. Il n'a
jamais été validé, et c'est lui qui a fait reprendre le palier `0..9` puis
`0..13` six fois de suite : la progression était bloquée par ce seul mot.

**Dans 13 de ces 14 verdicts, le modèle a transcrit exactement le mot attendu.**
Ligne de journal typique :

```
[CTL][V2] mot=4 "تُحِلُّوا۟" -> definitif:rouge |
    gop=-4.31 forced=-4.32 free=-0.01 frames=7 obs=3 entendu="تُحِلُّوا۟"
```

`free = -0,01` : le décodage libre est certain, et il rend le bon mot.
`forced = -4,32` sur le **même texte** : l'alignement forcé s'effondre.

C'est la signature déjà décrite dans `ForcedAligner.kt` (doc de `wordLookup`,
2026-09-05) : *« deux découpages du même mot rendent le même texte et des
scores opposés — même mot, même texte, gop 0,00 avec la bonne décomposition,
−11,99 avec l'autre »*.

## 2. La cause, mesurée

Le mot est **absent** du dictionnaire `word_tokens.json`, donc décomposé par le
repli glouton de `CtcTokenizer.tokenizeWordGreedy`. Décompositions effectives,
reproduites hors app à partir de `vocab.json` (1 024 pièces) :

| mot | décomposition réellement utilisée | pièces | verdict sur l'appareil |
|---|---|---:|---|
| `ءَامَنُوا۟` | `▁ءَامَنُوا۟` | **1** | **vert**, `gop = 0,00` (23 fois sur 25) |
| `فَٱصْطَادُوا۟` | `▁فَٱ` `صْ` `طَ` `ا` `دُوا۟` | 5 | rouge (2 sur 2) |
| `تُحِلُّوا۟` | `▁تُ` `حِ` `لُ` `ّ` `و` `ا۟` | **6** | **rouge (14 sur 14)** |

Aucun caractère n'est perdu : la recomposition redonne le mot exactement, et le
journal ne contient **aucune** ligne `caractere hors vocab ignore` (0 occurrence
sur 6,5 Mo). Ce n'est donc pas le défaut d'amputation corrigé le 2026-09-05.

Le problème est la **granularité** : le chemin forcé doit traverser six tokens,
dont une **shadda isolée** (`ّ`) comme pièce autonome — une unité que le modèle
n'émet pratiquement jamais seule, puisqu'elle n'apparaît ainsi dans aucune
segmentation apprise. Le décodage libre, lui, choisit ses propres pièces et ne
paie pas ce chemin.

⚠️ **Ce qui n'est PAS démontré** : que la fragmentation soit une cause
suffisante. 6 297 mots (16,8 %) sont décomposés en 5 pièces ou plus et tous ne
produisent pas de faux rouge. Ce qui est démontré, c'est que le mot vert de
référence tient en **une** pièce et les deux mots rouges en cinq et six. La
demande ci-dessous supprime la question plutôt que de la trancher : avec le
tokeniseur d'origine, la décomposition n'est plus une approximation.

## 3. L'état du dictionnaire livré

Mesuré sur le paquet déployé :

```
app/android/model_pack/src/main/assets/models/cinq-tetes-2026-09-11-madd-normal/
  word_tokens.json   847 852 o   sha256 c1219a6e869c4fbd044a1121bdf04c26f8a44b39eea2b75b1aae70ae8f27b024
  vocab.json          13 245 o   sha256 94efdc0e3db0d123c7cf1086d9b92a3b50674c95b7caad148962717060a7960c
```

| | |
|---|---:|
| mots distincts dans `app/assets/data/quran_verses.json` | **37 565** |
| entrées dans `word_tokens.json` | 18 993 |
| **mots du Coran ABSENTS du dictionnaire** | **18 572 — 49 %** |
| entrées présentes dont la décomposition ne redonne pas le mot | 2 806 — 14,8 % |
| mots décomposés en ≥ 5 pièces (dictionnaire ou repli) | 6 297 — 16,8 % |

Un mot sur deux du Coran n'a donc **aucune** décomposition de référence et passe
par le glouton. L'app le journalise à chaque démarrage :

```
[CtcTokenizer] dictionnaire mot->tokens charge : 17005 mots
   (1988 ecarte(s) : leur decomposition ne redonnait pas le mot -- repli greedy)
```

## 4. Ce qui manque sur ce PC, et pourquoi la demande part chez vous

La décomposition juste est celle que **le tokeniseur SentencePiece du modèle**
produit — le même que celui utilisé pendant l'entraînement. Ce PC (portable
Windows) n'a ni le `.nemo` du run, ni le `tokenizer.model`, ni le venv NeMo.
Reproduire le tokeniseur à partir du seul `vocab.json` donnerait encore une
approximation gloutonne, c'est-à-dire exactement ce qu'on cherche à remplacer.

## 5. Ce qui est demandé, précisément

1. Charger le tokeniseur du modèle **effectivement déployé** — le run dont est
   issu `cinq-tetes-2026-09-11-madd-normal`. Vérifier avant tout que son
   vocabulaire correspond : les 1 024 pièces doivent être **identiques et dans
   le même ordre** que `vocab.json` ci-dessus (sha256
   `94efdc0e…7960c`). Si l'ordre diffère, les identifiants produits seront faux
   en silence — l'app indexe `vocab[id]`, elle ne cherche pas la pièce par son
   texte. Le dire dans la réponse plutôt que de livrer.

2. Extraire la liste des mots distincts du texte coranique **tel que l'app le
   porte** : `app/assets/data/quran_verses.json` (champ `text_uthmani`), plus
   `app/assets/data/quran_mushaf_warsh.json` pour la riwāya Warsh. Ce sont ces
   graphies-là qui sont comparées à l'exécution, pas celles du manifeste
   d'entraînement.

3. Pour chaque mot, produire la décomposition du tokeniseur et **vérifier
   qu'elle restitue le mot** : `''.join(pieces).replace('▁','') == mot`, en
   comparant aussi en NFC (le texte coranique écrit le madd en décomposé,
   `0627 0653`, quand le vocabulaire porte la forme précomposée `0622` — c'est
   le piège documenté le 2026-09-05 qui avait fait écarter 818 entrées à tort).
   Tout mot dont la décomposition ne restitue pas le texte doit être **listé
   dans la réponse**, jamais livré silencieusement.

4. Écrire `word_tokens.json` au même format que l'existant : objet plat
   `{"mot": [ids…]}`, UTF-8 sans BOM.

## 6. Où écrire, et ce que la réponse doit contenir

- Le fichier : `benchmark/tunnel_pc_a/reponses/word_tokens_2026-09-18.json`
- Une note : `benchmark/tunnel_pc_a/reponses/REPONSE_2026-09-18_word_tokens.md`
  portant :
  - le **sha256** du fichier produit et son nombre d'entrées ;
  - le run et le chemin du tokeniseur utilisés, avec le sha256 du
    `tokenizer.model` ;
  - le résultat du contrôle de vocabulaire du point 5.1 (identique / différent) ;
  - le nombre de mots dont la décomposition ne restitue pas le texte, avec la
    liste complète si elle tient, un échantillon de 50 sinon ;
  - la décomposition obtenue pour les trois mots témoins ci-dessous.

**Témoins à reporter tels quels dans la réponse** — ils permettent de vérifier
ici, sans relancer l'appareil, que le fichier corrige bien le défaut :

| mot | décomposition actuelle (glouton) |
|---|---|
| `تُحِلُّوا۟` | `▁تُ` `حِ` `لُ` `ّ` `و` `ا۟` (6 pièces) |
| `فَٱصْطَادُوا۟` | `▁فَٱ` `صْ` `طَ` `ا` `دُوا۟` (5 pièces) |
| `ءَامَنُوا۟` | `▁ءَامَنُوا۟` (1 pièce) — celui qui passe vert |

## 7. Ce qui sera fait ici à réception

Le fichier ne sera pas déployé sur la foi de sa provenance. Il passera d'abord
par le banc JVM (`BancChaineOnnxJvmTest`), qui rejoue l'audio réel à travers le
modèle embarqué et la chaîne entière sans téléphone :

- contrôle que `تُحِلُّوا۟` redevient vert sur la capture de la session du
  2026-09-18 (l'audio est conservé sur l'appareil, dans
  `app_flutter/recitation_captures/`) ;
- contrôle que **les autres mots ne bougent pas** — c'est le test qui a validé
  la règle de shadda initiale le 2026-09-17 (« les 682 autres mots sont
  strictement inchangés ») et qui aurait fait rejeter la correction sinon ;
- détection et faux signalements comparés avant/après sur le banc d'erreurs
  réelles (`campagne_erreurs_reelles_20260916`, 118 erreurs / 1 254 mots).

Un gain sur le mot témoin obtenu en dégradant le reste serait un faux gain, et
le fichier serait refusé.


---

# RELANCE DU 2026-09-19 — ce n'est plus un chiffre de banc, ça interrompt l'utilisateur

Cette demande était étayée par le banc. Depuis, une **session réelle** l'a
confirmée de façon beaucoup plus nette. Priorité relevée.

## Ce qui s'est passé

Session du 2026-09-19 18:51, préréglage **tajwid**, Al-Ḥujurāt 49:1-9, 143 mots
jugés. **Six décrochages en sept minutes**, sept déclenchements du souffleur.
L'utilisateur : *« il bloque alors que je pensais avoir bien dit »*.

**Tous les mots qui l'ont bloqué sont écartés du dictionnaire.** Décomposition
réellement utilisée (repli glouton, reproduite hors app depuis `vocab.json`) :

```
وَٱعْلَمُوٓا۟   ▁وَٱ  عْ  لَمُ  و  ٓ  ا۟        6 pieces   -> definitif:ROUGE
تَرْفَعُوٓا۟    ▁تَ  رْ  فَ  عُو  ٓ  ا۟         6 pieces   -> definitif:ROUGE
فَتُصْبِحُوا۟   ▁فَ  تُ  صْ  بِ  حُ  و  ا۟      7 pieces   -> definitif:ROUGE
فَاسِقٌۢ       ▁فَ  ا  سِ  ق  ٌ  ۢ            6 pieces   -> definitif:ORANGE
```

Des pièces isolées — une **maddah seule** (`ٓ`), un `و` seul — que le modèle
n'émet pratiquement jamais ainsi.

## Le cas qui ne laisse aucune place au doute

Mot 96, `وَٱعْلَمُوٓا۟` :

```
[CTL][V2] mot=96 "وَٱعْلَمُوٓا۟" -> definitif:rouge
          gop=-4.73 forced=-4.75 free=-0.03  entendu="وَٱعْلَمُوٓا۟"
```

**`entendu` est identique à l'attendu.** Le modèle a lu le mot exactement, avec
`free = -0,03` (il est certain). Et le verdict est ROUGE, parce que
l'alignement forcé doit traverser les six pièces ci-dessus.

Mot 84, `فَاسِقٌۢ`, même famille, avec en plus la preuve que le tajwid n'y est
pour rien :

```
[CTL][V2tajwidDetail] mot=84 statut=unclear tajwidFiable=true
          attendues=iqlab(p=1.000/0.800,480ms)  detectees=iqlab(p=1.000/0.800,480ms)
```

La règle attendue est **détectée à 100 %**. Le mot est orange à cause du `gop`
seul (−1,44, entre les seuils −1,60 et −0,45).

## L'effet en cascade, qui est le vrai coût

1. le mot est rouge alors qu'il a été bien prononcé ;
2. l'alignement se décale : le mot 81 `ءَامَنُوٓا۟` reçoit `إِن` — la lecture du
   mot **82** — et sort en **`omis`**, le verdict le plus grave de l'app ;
3. le décrochage part sur ce faux `omis` ;
4. le souffleur interrompt l'utilisateur et lui redonne un mot qu'il venait de
   dire correctement. Chaque souffle dure 2,5 à 6,3 s.

⇒ Ce n'est plus « 49 % de couverture » dans un tableau : c'est **six
interruptions en sept minutes** sur une récitation correcte.

## Ce que cela ne demande pas

Aucune refonte de la chaîne. Le modèle acoustique fait son travail — il lit le
mot juste, et la tête tajwid détecte la règle attendue à 100 %. **Un seul
fichier est en cause.** La demande ci-dessus est inchangée : régénérer
`word_tokens.json` avec le tokeniseur du modèle, sur tout le texte porté par
l'application.

Les trois mots ci-dessus sont des **témoins supplémentaires** à reporter dans la
réponse, à côté de `تُحِلُّوا۟` : leur décomposition doit tenir en une ou deux
pièces, pas en six.
