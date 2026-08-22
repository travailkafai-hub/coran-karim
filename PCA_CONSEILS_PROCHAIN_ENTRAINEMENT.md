# PC A — ce qu'il faut corriger au prochain entraînement / export Warsh

**Écrit le 2026-08-22, après intégration du paquet `deux-geles-int8-2026-08-22-tajwid2`
sur device et six sessions de récitation Warsh réelles.**

Ce document ne demande **pas** de réentraîner le modèle acoustique.

Les points 1 et 2 ont été **contournés localement** pour débloquer les tests en
cours — ces contournements seront écrasés à votre prochaine livraison. Le
point 2 garde en plus une **cause de fond non tranchée**, qui est de votre
ressort.

---

## ⚠️ À lire en premier : un correctif local a été appliqué, il sera ÉCRASÉ

`word_tokens_warsh.json` a été **réparé à la main sur le PC de dev** le
2026-08-22 : 525 mots (yeh barree, point 1) + 26 mots (hamza, point 2). Ce fichier étant un livrable de PC A, **la prochaine
livraison écrasera cette réparation** et le défaut reviendra tel quel.

C'est la raison d'être de ce document : la correction doit remonter dans le
script de génération, pas rester sur le poste de test.

---

## Le constat qui cadre tout : le Hafs est propre, le Warsh non

Même contrôle, mêmes outils, sur les deux dictionnaires livrés dans le paquet :

| dictionnaire | entrées | entrées contenant `<unk>` (token 0) |
|---|---|---|
| `word_tokens.json` (Hafs) | 19 001 | **0** |
| `word_tokens_warsh.json` (Warsh) | 22 928 | **311** |

Le zéro du Hafs prouve que ce n'est pas une fatalité du pipeline : c'est un
écart de traitement entre les deux riwayāt.

**Pourquoi un `<unk>` dans ce fichier est grave.** Ce dictionnaire est la cible
de l'alignement forcé. Un `<unk>` demande au décodeur d'« expliquer » avec
l'audio un token que le modèle ne peut structurellement jamais produire avec
confiance : le score s'effondre **quelle que soit la prononciation réelle**.
Constaté sur device, six tours successifs, le même mot toujours en rouge alors
que le texte reconnu était correct.

---

## 1. Yeh barree `ے` (U+06D2) — 525 mots, correction dans le script

**Ce qui se passait :** le dictionnaire était construit par tokenisation
SentencePiece **brute** du texte source, sans appliquer la normalisation
`ے` → `ي` que l'application applique pourtant déjà à l'affichage depuis le
2026-08-12.

```
word_tokens_warsh.json["اُ۬لذِے"]  =  [49, 317, 0]
vocab_warsh.json[0]                =  "<unk>"
```

**Mesure :** 540 mots contiennent ce caractère, **525 (97,2 %)** avaient un
`<unk>`.

**Correctif à porter dans le script de génération :** appliquer `ے` → `ي` à la
forme **avant de tokeniser**, en gardant la clé du dictionnaire **inchangée**
(c'est elle que le natif cherche). Autrement dit, seule la séquence de tokens
change, jamais la clé.

Vérifié sur le poste de dev avant application : le tokenizer livré
(`tokenizers/warsh.model`) reproduit **200/200** entrées existantes sans yeh
barree — la retokenisation ne dérive donc pas du fichier d'origine.

Après correction : `<unk>` tombe de 525/540 à **0/540** sur ces mots.

---

## 2. Hamza `ٕ` (U+0655) — 26 mots — CONTOURNÉ localement, cause de fond à trancher

**Contourné sur le poste de dev le 2026-08-22** (comme le point 1, et comme
lui **il sera écrasé à la prochaine livraison**). Mais la cause de fond reste
entière et vous seuls pouvez la trancher — d'où ce qui suit.

### Le constat, établi SANS aucune référence au Hafs

Le texte Warsh embarqué n'est pas homogène avec lui-même :

| dans `quran_verses_warsh.json` | versets |
|---|---|
| U+0654 (hamza dessus) | **562** |
| U+0655 (hamza dessous) | **44** |

Et le vocabulaire Warsh **connaît U+0654** (pièce 1017) mais **ignore
U+0655**. Les 44 versets minoritaires sont donc en désaccord avec les 562
autres versets Warsh **et** avec le tokenizer Warsh.

### Le contournement appliqué, et ses limites

`ٕ` → `ٔ` **à la tokenisation uniquement** : la clé du dictionnaire et le texte
affiché restent **intacts au caractère près** (le mushaf continue d'afficher
`اَ۬لنَّبِيٓـِٕۧنَ` tel que le KFGQPC l'écrit). 26/26 mots réparés, vérifié.

⚠️ **C'est un contournement, pas la solution.** Il traite le symptôme dans le
dictionnaire livré ; il ne dit pas *pourquoi* deux graphies coexistent.

### Ce qui reste à trancher — la solution de fond

Trois hypothèses possibles, que je ne peux pas départager d'ici :

1. **le texte source Warsh est hétérogène** (deux graphies pour le même son
   selon les passages) — auquel cas c'est l'asset qu'il faut homogénéiser ;
2. **le corpus du tokenizer différait du texte livré** — le tokenizer n'a
   jamais vu U+0655 parce qu'il a été entraîné sur une autre édition ;
3. **la distinction est voulue et porte du sens** — auquel cas c'est le
   VOCABULAIRE qui doit apprendre U+0655, et surtout pas le texte qu'il faut
   changer.

L'hypothèse 3 interdirait le contournement ci-dessus. **Vous êtes les seuls à
pouvoir le dire** : ça dépend de l'édition source et de ce que le tokenizer a
réellement vu à l'entraînement.

### Note de méthode

Une première analyse justifiait cette substitution en comparant à l'écriture
Hafs du même mot. **Écarté** sur remarque de l'utilisateur : l'écriture diffère
entre Hafs et Warsh même pour un mot identique, et « chacun jugé selon son
token ». L'argument retenu ne fait donc intervenir que le Warsh — c'est le
Warsh qui doit être cohérent avec le Warsh.

### Les 26 mots concernés

```
أَفْـِٕدَةُ          أَفْـِٕدَتَهُمْ        أَفْـِٕدَتُهُم        اَفْـِٕدَةٗ
اَ۬لسَّيِّےِٕۖ       اَ۬لنَّبِيٓـِٕۧنَ      اَ۬لنَّبِيٓـِٕۧنَۖ     اَ۬لَافْـِٕدَةِۖ
اَ۬لْخَاطِـِٕينَۖ     اُ۪مْرِےِٕۢ          اُ۪مْرِےٕٖ           اُ۬لنَّبِيٓـِٕۧنَ
اِ۪مْرِےٕٖ           اِ۬للُّؤْلُوِٕ         بِالنَّبِيٓـِٕۧنَ      خَٰسِـِٕينَۖ
خَٰطِـِٕينَۖ         شَٰطِےِٕ            لَخَٰطِـِٕينَۖ        مُتَّكِـِٕينَ
مُّتَّكِـِٕينَ        وَأَفْـِٕدَةٗۖ        وَأَفْـِٕدَتُهُمْ      وَالنَّبِيٓـِٕۧنَ
وَالَافْـِٕدَةَ       وَالَافْـِٕدَةَۖ
```

---

## 3. Numéros de versets — 285 entrées, à sortir du corpus

Les entrées `١`, `٢`, … `٢٨٥` (chiffres arabes) sont dans le dictionnaire et
comptent toutes un `<unk>`. Ce ne sont pas des mots à réciter : ce sont les
**numéros de versets** du texte source, jamais nettoyés avant construction.

Sans conséquence fonctionnelle aujourd'hui (l'app ne les cherche jamais), mais
ils révèlent que le corpus de génération n'est pas filtré — et ils faussent
tout comptage de qualité sur ce fichier.

---

## 4. Le contrôle qui aurait tout attrapé, à ajouter à la génération

Un seul contrôle, trois lignes, aurait bloqué les 525 **et** les 26 **et** les
285 avant qu'ils n'atteignent le téléphone :

```python
inconnus = [mot for mot, ids in dictionnaire.items() if 0 in ids]
assert not inconnus, f"{len(inconnus)} entrées tokenisent en <unk> : {inconnus[:10]}"
```

Le Hafs passe ce contrôle à **0**. Ce n'est donc pas un idéal théorique, c'est
un seuil déjà atteint par l'autre riwāya du même paquet.

---

## Ce qui n'est PAS demandé ici

**Aucun réentraînement acoustique n'est nécessaire pour les trois points
ci-dessus** (sauf reconstruction du tokenizer pour le point 2).

## 5. LE DEFAUT QUI RESTE — la shadda decoupee en micro-jetons

**Ecarte par decision utilisateur le 2026-08-22** (« oublie l'entrainement sur
le PC A »). Documente ici parce que c'est desormais le SEUL defaut Warsh
identifie apres correction des points 1 a 3, et qu'il est chiffre.

### Mesure

Session Warsh reelle du 2026-08-22 21:14, Al-Fatiha, 29 mots, apres les deux
correctifs de dictionnaire : **22 verts**. Les trois mots non verts ont tous la
meme signature :

| mot | `entendu` | `gop` | `free` |
|---|---|---|---|
| `اَ۬لرَّحْمَٰنِ` | **identique a l'attendu** | −3,27 | −0,20 |
| `اَ۬لصِّرَٰطَ` | **identique a l'attendu** | −3,72 | −0,07 |
| `وَإِيَّاكَ` | `وَإِيَّكَ` | −2,41 | −0,08 |

`free` proche de 0 = le modele est CERTAIN de ce qu'il entend, et il entend le
bon mot. Ce n'est donc pas de la prononciation.

### La cause, lue dans le dictionnaire

Les trois portent une shadda, et le tokenizer Warsh l'isole en micro-jetons :

```
اَ۬لرَّحْمَٰنِ  →  ▁اَ۬ل · ر · ّ · َ · حْ · مَٰنِ
اَ۬لصِّرَٰطَ   →  ▁اَ۬ل · ص · ّ · ِ · رَٰ · طَ
وَإِيَّاكَ    →  ▁وَ · إِي · ّ · َا · كَ
```

La shadda `ّ` et sa voyelle sont des tokens SEPARES, coinces entre deux
morceaux de mot. L'alignement force exige que le modele emette chacun a un
instant precis, alors que le CTC est « pique » sur ce genre de micro-jeton.

Meme racine que le cas `وَبَثَّ` observe plus tot dans la journee.

### Ce que ca demanderait

Reconstruire le tokenizer Warsh pour qu'il fusionne shadda + voyelle en une
piece (comportement qu'il a deja pour d'autres sequences), **et** reentrainer
la tete acoustique sur le nouveau vocabulaire — les IDs changeant, le modele
actuel ne les reconnaitrait plus.

C'est le seul point de ce document qui exige un vrai run. Rien ne presse : 22
mots sur 29 passent deja, et les trois restants ne sont pas des fautes de
recitation.

---

## 6. TAJWID — deux prérequis avant de pouvoir le rebrancher

Trouvés le 2026-08-22 en lisant `modele_4tetes_2026-08-21/docs/` (votre propre
documentation) et en analysant une session Hafs réelle. Le tajwid est
aujourd'hui **désactivé** (preset `adulte`) ; ces deux points doivent être
levés avant de le réactiver, sinon il produira des verdicts faux.

### 6a. Les seuils livrés sont ceux du F1, pas ceux de la discrimination

`DECOUVERTES_ENTRAINEMENT_2026-08-20.md` §15 le dit explicitement :

> « Calibrer sur le F1 ne calibre pas la discrimination. Écarts entre les deux
> optima : **0,10 contre 0,95** (`idgham_mutaqaribayn`), 0,40 contre 0,80
> (`idgham_mutajanisayn`), 0,60 contre 0,95 (`idgham_shafawi`). »

Or `seuils_tajwid.json` livré porte bien **0,95** pour `idgham_mutaqaribayn` —
le seuil que votre propre document qualifie d'absurde, celui qui donne **0 % de
rappel** alors que la classe remonte à **80 % de rappel pour 2,7 % d'invention**
à 0,10.

**NON CORRIGÉ ICI, VOLONTAIREMENT** : le même document pose la réserve qui
l'interdit —

> « Ces seuils-ci sont optimisés SUR le jeu de jugement : ils sont
> potentiellement sur-ajustés à lui. Avant de les livrer, il faut les vérifier
> sur une part tenue à l'écart. »

C'est exactement cette vérification qui manque, et elle est de votre côté.
Livrer les seuils de discrimination validés hors calibrage remplacerait
`seuils_tajwid.json` **sans aucune modification de code** (le parseur lit déjà
les trois formes).

### 6b. `madd_long` invente une fois sur deux

| règle | rappel | invention |
|---|---|---|
| `qalaqah`, `idgham_wo_ghunnah`, `idgham_mutajanisayn` | 64-99 % | **0,0 %** |
| `ghunnah`, `madd_court`, `ikhafa_shafawi` | 77-99 % | 10-11 % |
| **`madd_long`** | 94,5 % | **50,4 %** |

Votre analyse en donne la raison : « c'est une règle de DURÉE, pas de timbre ».

**Conséquence côté app** : le pont entre les 4 noms de madd du texte annoté
(`madda_necessary/obligatory/permissible/normal`) et les 2 du modèle
(`madd_long`/`madd_court`) **n'a pas été posé**, et ne le sera pas tant que ce
chiffre tient — il produirait un faux positif sur un madd long correct une fois
sur deux. `madd_court` (10-11 %) est, lui, exploitable.

### Ce qui A été corrigé côté app

Le décalage d'index : les ids de la tête étaient traduits par POSITION dans
l'enum Dart, or le modèle a 2 madd là où l'enum en a 4 — décalage de 2 à partir
de l'index 2 (`ghunnah` lu `madda_permissible`, `qalaqah` lu `ham_wasl`…).
Corrigé : traduction par le NOM lu dans `rules.json`.

⚠️ Ce défaut était INERTE (tajwid désactivé) et serait resté très difficile à
voir au rebranchement : le journal natif `[tajwidDuree]` serait resté JUSTE
pendant que les verdicts Dart auraient été faux.

L'app suit désormais l'ordre du modèle toute seule — mais **un nom que l'enum
ne connaît pas est ignoré**. Prévenez-nous si vous ajoutez une classe destinée
à être jugée.
