# PC A — ce qu'il faut corriger au prochain entraînement / export Warsh

**Écrit le 2026-08-22, après intégration du paquet `deux-geles-int8-2026-08-22-tajwid2`
sur device et six sessions de récitation Warsh réelles.**

Ce document ne demande **pas** de réentraîner le modèle acoustique. Les trois
points ci-dessous se corrigent dans les scripts qui **génèrent les fichiers
livrés** — sauf le point 2, qui touche le vocabulaire SentencePiece.

---

## ⚠️ À lire en premier : un correctif local a été appliqué, il sera ÉCRASÉ

`word_tokens_warsh.json` a été **réparé à la main sur le PC de dev** le
2026-08-22 (525 mots). Ce fichier étant un livrable de PC A, **la prochaine
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

## 2. Hamza suscrite `ٕ` (U+0655) — 26 mots, correction dans le VOCABULAIRE

C'est le seul point qui **ne peut pas** se corriger côté script.

**Vérifié :** ce caractère n'apparaît dans **aucune** des 1024 pièces de
`vocab_warsh.json`. Aucune tokenisation ne peut donc l'encoder — c'est le
vocabulaire lui-même qui doit l'apprendre, ou une équivalence explicite qui
doit être décidée.

**Les 26 mots concernés** (tous coraniques et courants) :

```
أَفْـِٕدَةُ          أَفْـِٕدَتَهُمْ        أَفْـِٕدَتُهُم        اَفْـِٕدَةٗ
اَ۬لسَّيِّےِٕۖ       اَ۬لنَّبِيٓـِٕۧنَ      اَ۬لنَّبِيٓـِٕۧنَۖ     اَ۬لَافْـِٕدَةِۖ
اَ۬لْخَاطِـِٕينَۖ     اُ۪مْرِےِٕۢ          اُ۪مْرِےٕٖ           اُ۬لنَّبِيٓـِٕۧنَ
اِ۪مْرِےٕٖ           اِ۬للُّؤْلُوِٕ         بِالنَّبِيٓـِٕۧنَ      خَٰسِـِٕينَۖ
خَٰطِـِٕينَۖ         شَٰطِےِٕ            لَخَٰطِـِٕينَۖ        مُتَّكِـِٕينَ
مُّتَّكِـِٕينَ        وَأَفْـِٕدَةٗۖ        وَأَفْـِٕدَتُهُمْ      وَالنَّبِيٓـِٕۧنَ
وَالَافْـِٕدَةَ       وَالَافْـِٕدَةَۖ
```

**Deux voies possibles, à trancher côté entraînement** — je ne tranche pas,
c'est un choix qui engage la fidélité au texte :

- faire couvrir U+0655 par le vocabulaire SentencePiece (corpus d'entraînement
  du tokenizer contenant ces formes) ;
- ou décider d'une normalisation explicite vers une forme déjà couverte, **si
  et seulement si** elle est phonétiquement neutre. À ne pas décider à la
  légère : l'app affiche le texte tel quel.

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

Un point distinct a été observé et **volontairement écarté** : le tokenizer
Warsh découpe certains mots plus finement que le Hafs (`وَبَثَّ` → 4 tokens en
Warsh contre 3 en Hafs, la pièce fusionnée `fatha+shadda` existant côté Hafs
seulement). Cela abaisse le score de ces mots même bien prononcés. Corriger
cela demanderait de reconstruire le tokenizer **et** de réentraîner la tête
acoustique sur le nouveau vocabulaire — décision prise le 2026-08-22 de ne pas
l'engager pour le moment.
