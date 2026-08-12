# Basculer l'application en Warsh — sources trouvées et mesures

Branche : `chantier-warsh` (créée le 2026-08-12 depuis `prod`, commit `8c0c3ab`).
**Aucun code applicatif modifié — recherche de sources et mesures uniquement.**

Cadrage utilisateur (2026-08-12) :
- on cherche **de vraies sources** de texte ET d'audio Warsh, on ne se demande
  pas si l'app actuelle « pourrait » basculer ;
- la Bismillah comptée ou non comme verset **n'est pas un problème** : on
  l'exclut, on garde la même règle fonctionnelle qu'aujourd'hui ;
- **le modèle ASR n'est pas touché** : on l'utilise tel quel pour aligner du
  texte Warsh sur de l'audio Warsh, et on mesure ce qu'il détecte.

---

## 1. Ce qui a été trouvé (vérifié par appel réel, pas par lecture de doc)

### 1.1 AUDIO Warsh verset par verset — everyayah.com ✅

C'est la trouvaille qui débloque le chantier. `everyayah.com/data/recitations.js`
liste **3 récitateurs Warsh**, au format `SSSAAA.mp3` — **exactement la
convention de nommage que `reciter_download_service.dart` utilise déjà** :

| récitateur | dossier | couverture testée |
|---|---|---|
| **Ibrahim Al-Dosary (128 kbps)** | `warsh/warsh_ibrahim_aldosary_128kbps` | **9/9** ✅ complet |
| **Yassin Al-Jazaery (64 kbps)** | `warsh/warsh_yassin_al_jazaery_64kbps` | **9/9** ✅ complet |
| Abdul Basit Warsh (128 kbps) | `warsh/warsh_Abdul_Basit_128kbps` | 5/9 ⚠️ incomplet |

Test de couverture : requête HTTP sur le **dernier verset** des sourates
1, 2, 3, 18, 36, 55, 78, 110, 114. Fichiers réels vérifiés à `ffprobe`
(1:1 = 6,47 s / 1:7 = 17,70 s / 2:285 = 51,83 s / 2:286 = 75,80 s).

### 1.2 …et cet audio est indexé en numérotation **HAFS** ✅✅

Le point le plus important de toute cette analyse.

Le mushaf Warsh ne compte que **285 versets** à la sourate 2 (contre 286 en
Hafs). Or `002286.mp3` **existe** chez Al-Dosary et Al-Jazaery, et dure 75,8 s
— la durée du « lā yukallifu-llāhu nafsan » qui est bien le 286ᵉ verset de la
numérotation Hafs. Même contrôle sur Al-Fatiha : `001007.mp3` dure 17,70 s,
c'est-à-dire le verset **long** de Hafs (`ṣirāṭa … wa-lā ḍ-ḍāllīn`), pas le
verset court qu'aurait Warsh à ce rang.

⇒ **Les clés `(sourate, verset)` de l'app restent valables.** Il n'y a ni
renumérotation à faire, ni migration de base, ni décalage silencieux des
statistiques. C'est ce qui rend le chantier faisable sans toucher aux schémas
`portion_words` / `recitation_errors` / `session_words`.

### 1.3 AUDIO Warsh par sourate — mp3quran.net (241 récitateurs, 16 mus-hafs Warsh)

`https://mp3quran.net/api/v3/reciters?language=ar` — champ `moshaf[].name`
portant la riwāya. **16 mus-hafs Warsh**, dont **10 complets (114 sourates)** :

> Al-Husary · Abdul Basit · Omar Al-Kazabri · Ibrahim Al-Dosary ·
> Laayoun El Kouchi · Mohamed Sayed · Al-Qari Yassin · Abdelmoujib Benkirane ·
> Ahmed Diban · Rachid Belalia · Mohamed El Iraoui (111) · Hicham Al-Harraz (113) …

Format **par sourate** (un MP3 entier), donc pas directement utilisable pour la
correction mot à mot — mais précieux comme choix de récitateur pour l'écoute,
et comme matière première (découpe possible) si l'on veut d'autres voix que les
deux d'everyayah.

À noter : `OmarKazabri`, `LaayounKouchi`, `MohamedElIraoui`, `RachidBelalia`,
`AbdelmoujibBenkirane` sont **déjà dans `download_assajda.py`**, déjà tagués
`riwaya: "Warsh"`, et déjà téléchargés (~85 905 clips) — présence à
reconfirmer sur la machine Ubuntu, `benchmark/data/` étant gitignoré et vide
ici.

### 1.4 TEXTE Warsh — deux sources, complètes et officielles

| source | contenu | numérotation | accès |
|---|---|---|---|
| **KFGQPC** (`thetruetruth/quran-data-kfgqpc`, `warsh/data/`) | 6 214 versets, JSON/CSV/XML/SQL, + `jozz`, `page`, `line_start/end` | **Warsh** (6 214) | libre, **téléchargé et analysé ici** |
| **QUL** (Tarteel, `qul.tarteel.ai`) | « Quran Script(Warsh) — Ayah by Ayah » **et — Word by Word** | à confirmer | **compte requis** pour le téléchargement |

La version QUL *word-by-word* est celle qui intéresserait le plus l'app (elle
donnerait la découpe en mots sans avoir à la dériver), mais elle est derrière
une authentification. La version KFGQPC est libre et suffit pour démarrer.

L'API quran.com, elle, est un cul-de-sac, **vérifié** : `/quran/verses/{id}`
ignore complètement l'identifiant demandé (`uthmani`, `uthmani_warsh`, `warsh`
et même un identifiant inventé renvoient le **même texte Hafs**, HTTP 200), et
ses 12 récitateurs sont tous Hafs.

---

## 2. Les mesures qui décident du travail à faire

Comparaison exhaustive du texte KFGQPC Warsh (6 214 versets) au
`quran_verses.json` Hafs de l'app (6 236 versets), Bismillah 1:1 exclue du
comptage conformément à la règle retenue.

### 2.1 Les mots sont les mêmes — le flux ne bouge quasiment pas

| mesure | Hafs | Warsh |
|---|---|---|
| mots sur tout le Coran (hors Bismillah 1:1) | 77 429 | **77 427** |

Deux mots d'écart **sur tout le Coran**. Et sourate par sourate, les longueurs
coïncident presque toujours (Al-Baqara : 6 117 mots des deux côtés).

### 2.2 Squelette consonantique : 99,16 % identique

Après normalisation correcte (cf. §3), alignement par `SequenceMatcher` :

| | mots | part |
|---|---|---|
| identiques | 76 780 | **99,16 %** |
| réellement différents | **649** | **0,84 %** |
| sourates sans **aucune** divergence | 38 / 114 | |

Les 649 divergences réelles sont surtout des notations de hamza et quelques
variantes lexicales bien connues :
`اسرءىل → اسراءىل` (42×) · `النبى → النبىء` (30×) · `ءامن → امن` (20×) ·
`ابرهم → ابرهىم` (15×) · `ارءىتم → ارىتم` (14×).

### 2.3 …mais avec les harakat, 37,88 % des mots diffèrent

C'est le chiffre honnête, et **c'est celui qui prédit le comportement du
modèle** : son tokenizer est un BPE « tajweed » qui **conserve** les
diacritiques.

| comparaison | mots identiques |
|---|---|
| squelette consonantique seul | **99,16 %** |
| **avec les harakat** (ce que le tokenizer voit) | **62,12 %** |

Autrement dit, en Warsh : **le modèle devrait retrouver les bons mots**
(99 % de squelette commun → l'ancrage et l'alignement ont toutes leurs chances)
mais **il risque de signaler beaucoup de mots comme mal prononcés**, puisque
c'est précisément la vocalisation qui change d'une riwāya à l'autre. C'est
exactement l'expérience que tu veux faire — elle est maintenant outillée
(§4).

### 2.4 Le décalage de numérotation existe, mais ne nous concerne plus

Pour mémoire, puisque la question a été posée : 50 sourates sur 114 n'ont pas
le même nombre de versets, et sur les 6 188 clés communes, 4 943 désignent un
autre verset (`2:132` Warsh = `2:133` Hafs). **Sans objet ici** : l'audio
everyayah étant en numérotation Hafs (§1.2), on garde les clés Hafs de bout en
bout et l'on recoupe le texte Warsh sur les frontières Hafs — opération sûre
puisque le flux de mots est le même (§2.1).

---

## 3. Spécification exacte du normaliseur (inventaire Unicode mesuré)

`ArabicNormalizer` devra traiter ces caractères, relevés par comparaison des
inventaires complets des deux textes :

**Présents en Warsh, absents du Hafs :**

| point de code | occurrences | nom | traitement |
|---|---|---|---|
| `U+06D2` | 2 996 | YEH BARREE | → `ى` — **indispensable** : sans lui, `فى` devient `ف` (1 185 faux écarts à lui seul) |
| `U+0657` | 2 916 | INVERTED DAMMA | diacritique Warsh |
| `U+0656` | 1 935 | SUBSCRIPT ALEF | diacritique Warsh |
| `U+065E` | 1 815 | FATHA WITH TWO DOTS | diacritique Warsh (imāla) |
| `U+0655` | 45 | HAMZA BELOW | |
| `U+0660`–`U+0669` | 12 419 | chiffres arabo-indiens | **le numéro de verset est collé au texte** → à retirer |
| `U+200F` | 14 | marque RTL | à retirer |

**Présents en Hafs, absents du Warsh :** `U+0671` ALEF WASLA (13 483 !) → `ا`,
et les signes de waqf `U+06D7`–`U+06ED` (le jeu de signes de pause du mushaf
Warsh est différent).

C'est cette table qui fait passer la mesure de « 6,25 % de divergence » à
« 0,84 % » : sans elle, on mesure son propre normaliseur, pas les deux textes.

---

## 4. L'expérience à mener maintenant (tout est disponible)

Objectif : *le modèle actuel, inchangé, aligne-t-il du texte Warsh sur de
l'audio Warsh ?*

Tous les ingrédients sont réunis et vérifiés :
1. **audio** — `everyayah.com/data/warsh/warsh_ibrahim_aldosary_128kbps/SSSAAA.mp3`,
   complet, clés Hafs ;
2. **texte** — KFGQPC Warsh, recoupé sur les frontières Hafs (§2.4) ;
3. **modèle** — `benchmark/models_deployes/trois-tetes-2026-08-04-combine/`,
   tel quel.

Protocole, en réutilisant les bancs existants (cf. `solution-de-fond` : la
mesure d'abord, et sur plusieurs passages) :
- prendre **trois passages de nature différente** — un court (67 ou 36), un à
  fortes répétitions (55), un long (2) ;
- passer l'audio Warsh au modèle avec le texte **Hafs** puis avec le texte
  **Warsh**, et comparer les deux taux de non-verts ;
- ce que ça répond : si le taux Warsh/Warsh s'approche du taux Hafs/Hafs
  habituel, la vérification est utilisable telle quelle. S'il explose, on saura
  **sur quels mots** (les 37,88 % vocalisés différemment sont identifiés
  nominativement), et l'on décidera à ce moment-là — pas avant.

⚠️ Rappel projet : ne pas « faire passer » le Warsh en déplaçant un seuil.
Le résultat de cette mesure est une donnée d'entrée pour décider, pas un
objectif à atteindre.

---

## 4 bis. Ce que voit chaque étage sur du Warsh (mesuré le 2026-08-12)

Simulation d'un récitateur qui dit du Warsh **parfait** : on compare, mot à mot
sur tout le Coran, ce que le modèle peut écrire (orthographe Hafs) à ce que
chaque étage de la chaîne attend.

| étage | ce qu'il compare | résultat |
|---|---|---|
| **ancrage / alignement** | le squelette, sans voyelles (`normalize`) | **97,5 %** des mots reconnus |
| **jugement** | le texte strict, avec voyelles (`normalizeStrict`) | **62,1 %** jugés corrects |

⇒ **37,9 % des mots seraient signalés alors qu'ils sont parfaitement récités.**
Le modèle entend bien et l'alignement suit : c'est le **juge** qui produit le
rouge, pas l'acoustique.

**Et ce n'est pas réglable par un seuil.** Le vocabulaire déployé (1 024 tokens)
ne contient **aucun** des signes de vocalisation Warsh — 0 occurrence pour
U+0655, U+0656, U+0657, U+065E, et 0 pour le yeh barree U+06D2. Le modèle est
structurellement incapable d'écrire du Warsh, alors que **8,7 %** des mots
Warsh portent au moins un de ces signes. On lui demande une chose absente de
son alphabet, puis on le sanctionne de ne pas l'avoir produite — même défaut
que le yeh barree (§3), un cran plus haut.

⚠️ Piège de mesure rencontré et corrigé : une première passe donnait 62,2 %
d'ancrage. C'était un artefact — le texte Hafs porte 4 578 signes de waqf
**isolés** comptés comme jetons, le Warsh n'en a aucun, donc la comparaison
mot à mot se décalait. Il faut découper comme `splitExpectedWords` (jeter les
jetons dont la normalisation est vide) avant toute comparaison.

### Question ouverte, à trancher PAR LA MESURE sur GPU — pas par le raisonnement

Deux voies pour rendre le jugement possible en Warsh, **aucune des deux n'est
mesurée à ce jour** :

- **4ᵉ tête** `Conv1d 512 → vocab_warsh` sur encodeur **gelé** — recette déjà
  éprouvée ici (la tête tolérante a été faite ainsi, cf.
  `PLAN_ENTRAINEMENT_HYBRIDE.md` §249-252, hors NeMo qui ne supporte pas deux
  têtes CTC). Zéro risque Hafs par construction. Répond à la vraie question :
  *les features de l'encodeur gelé distinguent-elles déjà l'imāla et les madd
  Warsh ?*
- **Réentraînement de l'encodeur** sur Hafs + Warsh **avec les bonnes
  étiquettes** (remarque utilisateur 2026-08-12, juste : l'échec passé venait
  du Warsh étiqueté en texte **Hafs**, pas de sa présence). Coût réel à ne pas
  sous-estimer : la tête 3 mange directement l'état encodeur (512 dims, cf.
  l'en-tête de `tete3.json`), la tête tolérante aussi, et
  `gop_word_baseline.json` (12 702 mots) en dérive — changer l'encodeur les
  périme toutes les trois.

Argument de conception à vérifier lui aussi, pas à croire : sur les 99 % de
rasme commun, le choix d'écriture (`ٱ` ou `ا۬`) est une convention, pas un son
— un modèle non conditionné devrait le deviner. L'app connaissant déjà la
riwāya, une tête par riwāya *est* ce conditionnement. **À confirmer par la
mesure.**

## 5. Ce qui manque encore, et où le prendre

| donnée | source identifiée | reste à faire |
|---|---|---|
| texte Warsh | KFGQPC ✅ | recouper sur frontières Hafs |
| audio par verset | everyayah ✅ (2 récitateurs complets) | — |
| audio par sourate | mp3quran.net ✅ (10 complets) | — |
| découpe mot à mot | QUL *word-by-word* (compte requis) | ou dériver du texte |
| **timings mot à mot** | ❌ aucune source | à produire — l'alignement forcé du modèle est précisément l'outil pour ça |
| tajweed coloré | ❌ aucune source Warsh | à décider : sans couleur en Warsh, ou re-dérivation |
| hizb / rub'-el-hizb | ❌ absent du jeu KFGQPC (`jozz` seulement) | dériver, ou portions sur le `jozz` |
| annotations de règles, waqf, index de recherche, baseline GOP | dérivés Hafs | à re-générer depuis le texte Warsh |

---

## 6. Défaut préexistant relevé au passage (hors chantier Warsh)

[reciter.dart:22-32](app/lib/models/reciter.dart#L22-L32) associe des noms à
des identifiants d'API qui ne correspondent pas. Vérifié via l'URL audio
réellement renvoyée par l'API pour chaque `id` : `id=1` est Abdul Basit
**Mujawwad** (l'app dit Murattal), `id=2` **Murattal** (l'app dit Mujawwad),
`id=5` **Hani ar-Rifai** (l'app dit Abu Bakr Ash-Shaatree), `id=9`
**Minshawi** (l'app dit Al-Husary), `id=10` **Shuraym** (l'app dit
Al-Qatami), `id=11` **Al-Tablawi** (l'app dit As-Sudais), `id=12` **Husary
Muallim** (l'app dit Muhammad Ayyoub). **6 entrées sur 8 sont fausses.**
À corriger séparément.

---

*Toutes les mesures de ce document datent du 2026-08-12 : comparaison des deux
jeux de données complets, requêtes réelles sur everyayah / mp3quran / quran.com
/ QUL, fichiers audio Warsh téléchargés et mesurés à `ffprobe`. Ce qui n'a pas
pu être vérifié depuis ce poste est nommé comme tel (corpus Warsh déjà
téléchargé sur la machine Ubuntu, contenu QUL derrière authentification).*

Sources : [everyayah.com](https://everyayah.com/data/recitations.js) ·
[mp3quran.net API](https://mp3quran.net/api/v3/reciters) ·
[KFGQPC quran-data](https://github.com/thetruetruth/quran-data-kfgqpc) ·
[QUL — Quranic Universal Library](https://qul.tarteel.ai/resources/quran-script) ·
[api.quran.com v4](https://api.quran.com/api/v4)
