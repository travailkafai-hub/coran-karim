# Le plafond de la chaîne est dans l'ALIGNEMENT, pas dans la décision

Objectif posé par l'utilisateur : **80 % de détection, moins de 5 % de faux
signalements**. État mesuré ce soir : **67 % / 9,2 %**. Ce document dit où j'ai
cherché, ce que j'ai éliminé avec des chiffres, et pourquoi la suite n'est pas
un réglage.

Banc : `campagne_paliers_20260915`, 10 cas rejoués hors device
(`BancChaineOnnxJvmTest`, étendu de 5 à 8 cas + T023/T005), PCM réel → mel
Kotlin → ONNX du pack → chaîne entière, verrouillages pendant le flux.
**103 mutations, 534 mots corrects** au dénominateur commun.

## Le fait qui commande tout

Sur les **57 fautes ratées**, les bornes attribuées au mot ont été comparées à
la zone réellement éditée par le générateur (`output_edit_start_ms` +
`replacement_samples`) :

| recouvrement avec la zone fautée | mots |
|---|---:|
| < 25 % — **aligné à côté** | **37** |
| 25 à 75 % | 20 |
| > 75 % — bien aligné | **0** |

**Aucune faute ratée n'était correctement alignée sur l'audio modifié.** Elles
ne sont donc pas « inaudibles » : la chaîne lisait l'audio du voisin, intact,
et le déclarait conforme. Ces mots avaient d'abord été classés « acoustiques »
(43 d'entre eux) — c'était faux, et cette correction est le résultat principal
de la soirée.

Le rappel par famille confirme la mécanique :

| famille | détectée | ratée | rappel |
|---|---:|---:|---:|
| near_word_substitution | 18 | 3 | **86 %** |
| extra_letter | 12 | 2 | **86 %** |
| truncate | 42 | 24 | 64 % |
| omission_word | 14 | 8 | 64 % |
| haraka_mutation | 3 | 2 | 60 % |
| insertion | 6 | 18 | 25 % (non mesurable) |

`insertion` n'est pas mesurable ainsi : le manifeste le dit lui-même
(« nearby verdicts are proxy only »), un mot inséré n'a pas de mot attendu en
face. Hors insertions, le rappel monte à 70 %.

**Les substitutions atteignent 86 % : quand le son fautif est au bon endroit,
la chaîne le voit.** Tout le déficit est sur troncature et omission — là,
précisément, où l'aligneur n'a plus l'audio du mot et va le chercher ailleurs.

## ORIGINE MESUREE : le delai d'emission du CTC n'est jamais compense

Les bornes attribuees par l'aligneur ont ete comparees aux bornes REELLES des
mots (horodatage API quran.com, `campagne_100x20/sources/*.json`), sur 98 mots
situes AVANT toute edition du montage (au-dela, les positions glissent) :

| decalage debut aligneur moins debut reel | frames de 80 ms |
|---|---:|
| mediane | **+12,15** |
| moyenne | +12,38 |
| q10 -> q90 | +8,5 -> +17,2 |
| **signe positif** | **100 % des 98 mots** |

**L'aligneur est systematiquement EN RETARD d'environ 12 frames, soit ~970 ms.
Jamais en avance, pas une seule fois.** Et `Horloge.LOOKAHEAD_FRAMES` vaut
**13 frames = 1,04 s**.

Le decalage est donc egal au lookahead du modele causal. C'est le **delai
d'emission** bien connu du CTC : la loss CTC est invariante a l'alignement,
rien n'oblige le modele a emettre le token au moment du son, et il le fait
apres. `LOOKAHEAD_FRAMES` est utilise comme **marge droite d'interiorite**
(`AligneurForce.margeDroiteFrames`) mais **n'est jamais retranche des bornes**.

### Pourquoi cela produit exactement les symptomes observes

Les bornes du mot i couvrent alors l'audio `[debut_i +12, fin_i +12]`, qui
contient la FIN du mot i puis le DEBUT du mot i+1. Consequences mecaniques :

- l'alignement force ne retrouve que la fin de i -> **lecture en suffixe**
  (`فَهُمْ` lu `هُمْ`) ;
- le decodage libre du mot i-1 attrape le debut de i -> **le voisin prononce le
  debut du suivant** (`مَّآ` lu `أُن`), ce qui est exactement le compte de 19
  cas releve plus bas ;
- un mot tronque ou omis n'a plus rien a son emplacement decale : l'aligneur va
  le chercher ailleurs -> **0 faute ratee sur 57 alignee sur la zone fautee**.

Une seule cause explique donc les faux signalements, les fautes ratees ET le
decrochage sur audio correct.

### CORRECTION TESTEE -- ET REFUTEE (a ne pas refaire)

Implementee puis mesuree le soir meme : `AligneurForce.framesAvanceeDebut`
rend au mot les frames de debut que le CTC n'a pas emises (extension de
`premiere[w]` vers la gauche, bornee a `derniere[w-1]+1`, la fin intacte,
`nb`/`sommeForced`/`sommeFree` non recalcules). Parametre laisse en place,
**defaut 0 = chaine inchangee**, balayable par `-DavanceeDebut=N` sur le banc.

Rejeu complet des 10 cas avec `-DavanceeDebut=13` :

| configuration | sans avancee | avec 13 frames |
|---|---|---|
| historique | 57/103 - 5,2 % | 56/103 - 4,9 % |
| vote | 69/103 - 9,0 % | 69/103 - **8,6 %** |
| vote + tete BPE | 69/103 - 9,2 % | 69/103 - **9,6 %** (pire) |

**Gain marginal, negatif sur une configuration. L'hypothese ne tient pas.**

POURQUOI, et c'est le vrai enseignement : `entendu` est bien calcule depuis
`premiere[w]` (`Decodage.texte(logprobs, pieces, blank, premiere[w],
derniere[w])`), la correction atteignait donc le bon endroit. Mais etendre la
fenetre de lecture vers la gauche n'ajoute que des frames **blanches** : le CTC
n'y a rien emis. Le debut du mot n'etait pas « dans des frames non lues » --
**le modele ne l'a jamais emis**.

⇒ Quand `فَهُمْ` est lu `هُمْ`, la particule `فَ` n'a pas ete rognee par
l'alignement : elle n'a jamais ete produite. Le defaut n'est donc PAS dans
l'aligneur mais dans l'EMISSION du modele, qui avale les particules initiales
courtes -- exactement la piste que Codex avait ouverte (T805/94 perte de `وَ`,
211 perte de `ن`). Cela se traite a l'entrainement ou au decodage, pas dans la
chaine de decision.

La mesure de decalage plus haut reste valable comme CONSTAT (debut +13,4, fin
+3,1, duree -13,9, 100 % de signe positif) ; c'est son interpretation
« frames mal attribuees » qui est fausse. La bonne lecture : le modele emet
tard ET n'emet pas les debuts faibles.

### Le motif des debuts manquants -- et pourquoi il ne se corrige pas en aval

Les 87 lectures en suffixe ont ete triees par ce qui MANQUE au debut :

| debut manquant | occurrences |
|---|---:|
| `وَ` | 14 |
| `فَ` | 10 |
| `بِ` | 6 |
| `أَ` / `إِ` / `ثَ` / `تُ` | 3 / 2 / 3 / 2 |

Ce sont les **proclitiques** arabes : une consonne + une voyelle breve, les
segments les plus courts et les moins energetiques de la langue. Repartition :
**72 sur des mots CORRECTS contre 15 sur de vraies fautes**. Le modele les
avale ; le recitateur ne les oublie pas.

Regle ciblee testee -- ne pas condamner un mot dont la SEULE divergence est la
perte d'un proclitique d'une lettre : **3 faux evites pour 2 fautes perdues**.
Non exploitable. Raison : ces 72 observations portent sur des mots que la regle
de la lecture entiere sauve DEJA. Le gisement etait deja capte.

⇒ Septieme hypothese ecartee. **Les leviers de DECISION sont epuises** : sept
testees, six mortes, une retenue pour 8 faux. Le defaut est dans l'emission du
modele, et aucune regle en aval ne le rattrape sans couter autant qu'elle
rapporte.

### Piste restante, non testee

Le decodage libre est **glouton** (argmax par frame). Un CTC qui hesite sur un
proclitique bref peut le perdre en glouton et le retrouver en **beam search**.
A mesurer sur ce banc avant toute implementation -- c'est la seule piste
identifiee qui ne demande pas de reentrainer.

Au-dela : exposer les scores **par TOKEN** et non par mot. Aujourd'hui `forced`
et `free` sont agreges sur le mot, si bien qu'un debut manquant est invisible
dans les chiffres -- on voit que le texte differe, jamais que le modele etait
muet sur les deux premieres frames. Sans cette instrumentation, les pistes
suivantes se jugeront a l'aveugle.





Retrancher le delai d'emission des bornes remontees par le Viterbi
(`premiere[w]` / `derniere[w]` dans `AligneurForce.aligner`, autour de la
ligne 403) avant de produire `debutAbs`/`finAbs` et de calculer forced/free.
Le decalage mesure ici est de 12 frames ; **a balayer**, ne pas coder 12 en dur
sans balayage (8, 10, 12, 13, 14) sur ce banc.

⚠️ RESERVES A LEVER AVANT D'Y TOUCHER :
- Les segments API sont annonces fiables « a quelques dizaines/centaines de ms
  pres » (`SUITE_TETE3.md` §0). L'ecart mesure ici est de ~970 ms, soit 3 a 10
  fois plus : l'ecart est donc bien reel, mais la mesure merite d'etre refaite
  sur un second corpus avant d'etre traitee comme une constante.
- La mesure porte sur 98 mots d'un seul banc, tous avant la premiere edition.
- Un decalage uniforme ne casse PAS l'ordre des mots : la structure relative est
  preservee. Ce qui casse, c'est la lecture de l'audio A l'interieur des bornes.
  Un correctif qui deplacerait les bornes doit donc etre juge sur le TEXTE LU,
  pas sur l'ordre.

## Cause structurelle nommée

**L'alignement forcé n'a pas d'option « absent ».** Il doit placer tous les
mots de la fenêtre ; quand un mot est tronqué ou omis, il redistribue les
frames et pose le mot sur l'audio du voisin. Le mot est alors lu correctement
— donc déclaré correct.

Le même défaut, vu de l'autre côté, produit les faux signalements. Sur 121
mots amputés de leur début :

| où est passé le début | cas |
|---|---:|
| **absorbé par la lecture du mot précédent** | **19** |
| bornes collées au voisin, aucune marge à gauche | 47 |
| perdu sans trace | 49 |

Trois exemples réels (sortie de `diagnostiquer_aligneur_debut_20260915.py`) :
le voisin de gauche prononce le début du mot suivant — `أُنذِرَ` lu `ذِرَ`
pendant que `مَّآ` est lu `أُن` ; `بِثَالِثٍ` lu `ثَالِثٍ` pendant que
`فَعَزَّزْنَا` est lu `فَعَزْبِ` ; `لِتُنذِرَ` lu `تُنذِرَ` pendant que
`ٱلرَّحِيمِ` est lu `لِ`.

C'est l'origine de **60 des 78 faux signalements (77 %)**, et c'est la même
cause que le décrochage sur audio correct (`PROBLEMATIQUES_ASR.md` : 18 des 30
décrochages `horsTexte` de dense30) et que les faux positifs de la tête 3.
**Un seul défaut, trois symptômes.**

⚠️ `margeGaucheFrames` (AligneurForce) ne corrige pas cela — vérifié : il ne
sert qu'au critère `interieur`, il n'élargit aucune borne. L'amputation vient
du treillis Viterbi lui-même.

## Six pistes testées, cinq mortes — ne pas les refaire

| piste | résultat mesuré |
|---|---|
| marge de confusion sur les lettres | **non** : 10 rattrapées / **139 faux ajoutés** |
| champ `couvert` comme signal de troncature | **non** : vaut `true` sur 100 % des observations |
| écarter tous les fragments du mot attendu | **non** : 21 faux évités / **16 détections perdues** |
| **écarter les suffixes SI une lecture entière existe** | **oui** : 8 faux, **0 perte** — implémenté |
| gop | **non** : médiane **0,000** pour les fautes ratées **comme** pour les corrects |
| durée attribuée (frames/lettre) | **non** : médianes 0,57 vs 0,62, distributions superposées |

Le gop mérite un mot : il est cassé pour la raison déjà écrite dans
`Decideur.kt` — `free` est un maximum sur les 1025 classes, borne si lâche que
tout s'y écrase à zéro. Ce n'est pas un seuil à déplacer, c'est la grandeur
qui n'informe pas.

## Ce qui a été changé dans le code

`Decideur.statutsVote` — une lecture ENTIÈRE et conforme écarte, pour ce mot,
les lectures qui n'en montrent qu'un **suffixe** (début mangé). Justification
physique : un récitateur qui tronque un mot en dit le début puis s'arrête, il
ne peut pas en prononcer la fin sans le début ; un suffixe n'est donc jamais
une troncature prononcée. Les **préfixes restent jugés** — ce sont les vraies
troncatures. Conditionné à l'existence d'une lecture entière : sans elle, les
cas sont trop ambigus (11 mots corrects contre 7 fautes réelles).

Aucun seuil déplacé. C'est un choix de preuve entre deux lectures du même son,
pas une tolérance. Effet mesuré au rejeu complet : **vote 55 → 48 faux**,
**vote + tête BPE 57 → 49**, détection **inchangée à 69/103**.

⚠️ L'estimation préalable annonçait 38 faux évités pour 9 détections perdues.
Le rejeu réel donne **8 pour 0**. L'estimation supposait qu'écarter une lecture
suffisait à faire tomber le verdict, alors que le vote recalcule et retombe
souvent dessus autrement. Ne pas conclure sur estimation.

## La piste proposée, et pourquoi

**Resserrer la borne du gop.** Aujourd'hui `free` demande « ce mot plutôt que
n'importe laquelle des 1025 classes », question à laquelle tout audio répond
oui. La question utile est « ce mot est-il ici, **plutôt que ses voisins
immédiats dans le texte** ? » — un chemin CTC contraint aux mots adjacents, pas
à tout le vocabulaire. C'est exactement ce qui manque pour qu'un mot absent ou
tronqué se signale : son voisin expliquerait mieux l'audio que lui.

**Non mesuré.** C'est une hypothèse ; elle doit passer par ce banc avant toute
implémentation dans la chaîne.

Autre voie, plus lourde : donner au Viterbi une option de **saut** (un mot peut
n'avoir aucune frame), au lieu de l'obliger à tout placer.

## Reproduire

Depuis `app/android` :

```
gradlew.bat -DasrBanc=true :app:testDebugUnitTest --tests *BancChaineOnnxJvmTest
```

Puis depuis la racine :

```
python benchmark/analyser_replay_chaine_jvm_20260915.py
python benchmark/analyser_causes_echecs_20260915.py
python benchmark/diagnostiquer_aligneur_debut_20260915.py
python benchmark/verifier_alignement_sur_zone_fautee_20260915.py
python benchmark/potentiel_marge_lettres_20260915.py
python benchmark/mesurer_regle_lecture_entiere_20260915.py
```

Deux gardes figées ont été corrigées pour permettre l'extension du banc : le
test et son script d'analyse comptaient « 20 résultats » en dur (5 cas × 4
configurations) et refusaient les 40 résultats corrects. Elles comptent
désormais les cas réellement rejoués. Les `assert` de non-régression entre
`legacy` et `bpe` sont devenus une **collecte** (`anomalies` dans
`analyse.json`) : sur T803 la tête BPE signale 14 mutations contre 15, et
s'arrêter là masquait les sept autres cas.

Le C2 du JDK Microsoft 21.0.10 a planté une seconde fois, sur
`CollectionsKt::maxOrThrow` (`hs_err_pid30276`). Exclure méthode par méthode ne
tient pas : le banc tourne désormais en `-XX:TieredStopAtLevel=1`. Sans effet
sur le runtime Android, ni sur les verdicts mesurés.

## Ce que ce banc ne dit pas

- Montage synthétique aux frontières de l'API, pas de la récitation humaine.
- Rien sur Warsh : aucune source Warsh dans ce banc.
- Les chiffres JVM ne sont pas bit à bit ceux d'Android (ORT desktop, C1 seul).
  Les comparaisons **internes** au banc valent ; les valeurs absolues non.
- **La suite de tests complète n'a pas été relancée** après le changement du
  `Decideur`. À faire avant tout commit.
