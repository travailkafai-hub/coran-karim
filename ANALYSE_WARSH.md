# Basculer l'application en Warsh — analyse de ciblage

Branche : `chantier-warsh` (créée le 2026-08-12 depuis `prod`, commit `8c0c3ab`).
**Analyse seule — aucune ligne de code applicatif modifiée sur cette branche.**

Demande utilisateur : « quand on bascule Warsh, côté Mushaf, côté récitation,
côté jeu, côté audio, tout doit être traité avec Warsh [...] toutes les
fonctionnalités qui jusque-là sont traitées avec le Hafs doivent être
transposées ». Ce document dit **où**, précisément, et **ce qui manque**.

---

## 0. Le fait qui commande tout le reste (mesuré, pas supposé)

**`(sourate, verset)` n'est PAS une identité stable entre Hafs et Warsh.**

Mesure faite le 2026-08-12 en comparant `app/assets/data/quran_verses.json`
(Hafs, 6 236 versets) au jeu de données officiel KFGQPC Warsh
(`warshData_v10.json`, 6 214 versets) :

| mesure | valeur |
|---|---|
| versets au total | Hafs 6 236 / Warsh **6 214** |
| sourates dont le NOMBRE de versets diffère | **50 sur 114** |
| clés `s:a` communes aux deux | 6 188 |
| ...dont le **squelette consonantique** est identique | **1 245** |
| ...dont le squelette diffère (= ce n'est pas le même verset) | **4 943** |

Exemple vérifié à la main, décisif :

```
clé 2:132   Hafs  : وَوَصَّىٰ بِهَآ إِبْرَٰهِـۧمُ بَنِيهِ …
clé 2:132   Warsh : ۞ أَمْ كُنتُمْ شُهَدَآءَ … (= le 2:133 de Hafs)
```

Et sur Al-Fatiha, décalage d'un rang complet : la Bismillah n'est pas comptée
comme verset 1 en Warsh, donc `1:1` Warsh = `1:2` Hafs, et ainsi de suite.

**Conséquence directe :** toute donnée que l'app persiste sous la forme
`(surah, ayah, word_index)` devient FAUSSE au basculement — elle ne se
« décale » pas, elle désigne un autre mot d'un autre verset, en silence. C'est
le risque n°1 du chantier, avant même la question du texte affiché.

Second fait mesuré : le mushaf Warsh KFGQPC fait lui aussi 604 pages, mais ce
n'est **pas la même découpe** (numérotation propre au mushaf Warsh). Or
`QuranApi.fetchVersesByPage` pilote l'enchaînement continu de la récitation ET
la partie illimitée du jeu.

Troisième fait mesuré : le jeu KFGQPC Warsh fournit `jozz` (1-30) et `page`,
mais **ni `hizb_number` ni `rub_el_hizb_number`** — exactement les deux champs
sur lesquels repose le découpage en portions du Coach
(`portion_service.dart`).

---

## 1. Ce qui existe déjà, et qu'il ne faut pas refaire

- **Un corpus audio Warsh est déjà téléchargé** : `download_assajda.py` tague
  22 récitateurs marocains `riwaya: "Warsh"`, et
  `build_hafs_only_manifest.py` documente **~85 905 clips Warsh (21 % du
  dataset)** qui ont été délibérément EXCLUS des entraînements Hafs.
  ⚠️ Ces clips sont sur la machine Ubuntu (`benchmark/data/` est gitignoré et
  vide ici) — **présence à reconfirmer là-bas avant de planifier quoi que ce
  soit dessus**, je ne peux pas la vérifier depuis ce poste.
- **Le travail de vérification de riwaya par récitateur est déjà fait**, à la
  main, sur assabile.com + test audio sur verset discriminant (3:146
  qatala/qutila, 57:24 présence de « howa ») — cf. les commentaires de
  `build_hafs_only_manifest.py`. Deux récitateurs y sont notés comme tagués
  Hafs à tort. Ce travail est réutilisable tel quel, en inversant le filtre.
- **Une source de texte Warsh complète et officielle existe** : KFGQPC
  (Complexe du Roi Fahd), dépôt `thetruetruth/quran-data-kfgqpc`, dossier
  `warsh/data/` (JSON 2,7 Mo, + CSV/XML/SQL), version 0.10 de 2021. Colonnes :
  `jozz, page, sura_no, sura_name_en/ar, line_start, line_end, aya_no,
  aya_text`. Le même dépôt fournit aussi qaloon, doori, soosi, bazzi, qumbul,
  shouba — donc la même mécanique servirait d'autres riwayat plus tard.

## 2. Ce qui n'existe nulle part et devra être produit

| donnée | état Hafs | état Warsh |
|---|---|---|
| texte du verset | `quran_verses.json` (7,7 Mo) | **KFGQPC dispo** (à intégrer) |
| tajweed coloré (`text_uthmani_tajweed`) | fourni par quran.com | **inexistant** |
| annotations de règles (`quran_rules_annotated.json`, 6 236 versets) | dérivé Hafs | **à re-dériver** |
| signes de waqf (`quran_waqf.json`, 2 640 versets) | dérivé Hafs | partiellement dans le texte KFGQPC, **à extraire** |
| index de recherche (`quran_search_index.json`) | dérivé Hafs | **à re-générer** |
| timings mot-à-mot (`word_timings_ms.json`, 3 520 versets) | dérivé d'un récitateur Hafs | **à re-mesurer sur un récitateur Warsh** |
| baseline GOP (`gop_word_baseline.json`, 12 702 mots) | mots Hafs | **à re-mesurer** |
| hizb / rub'-el-hizb | dans `quran_verses.json` | **absent du jeu KFGQPC** |
| **modèle ASR** | 3 têtes, entraîné **Hafs-only volontairement** | **à entraîner** |
| lexique du modèle (`word_tokens.json`, 19 001 mots) | mots Hafs | **à régénérer** |
| audio récitateur (lecture, correction, coach) | 8 récitateurs quran.com | **aucun** côté API (cf. §4) |

## 3. Point de bascule n°1 — le TEXTE : un seul verrou, c'est la bonne nouvelle

Tout le texte affiché et jugé descend de `Verse.textUthmani`, alimenté par
`QuranApi._parseVerse` depuis les deux assets locaux. **Aucun écran ne lit
l'asset directement.** Le verrou unique est donc :

- [quran_api.dart:56-79](app/lib/services/quran_api.dart#L56-L79) `_ensureLoaded()`
  → charger `quran_verses_warsh.json` au lieu de `quran_verses.json` selon le
  réglage, et **invalider les caches statiques** (`_chapters`,
  `_versesBySurah`, `_versesByPage`, `_bismillahCache`) au changement.

Les 17 fichiers qui consomment `textUthmani` en aval (mushaf, karaoké,
tajweed, jeu, coach, portions, recette, mini-player, téléchargements) suivent
alors **sans modification** — vérifié fichier par fichier.

Deux exceptions à traiter à la main :
- [tajweed_text.dart](app/lib/widgets/tajweed_text.dart) et
  `tajweedSpansPerWord()` reposent sur `textUthmaniTajweed`, **absent en
  Warsh** → décider : pas de couleur tajweed en Warsh, ou re-dérivation.
- [portion_service.dart:96-114](app/lib/services/portion_service.dart#L96-L114)
  exclut la Bismillah du total via le cas particulier `(1,1)` — en Warsh, `1:1`
  **est** « الحمد لله » et non la Bismillah : ce cas particulier devient faux.

## 4. Point de bascule n°2 — l'AUDIO : c'est ici que ça bloque vraiment

**Vérifié en appel réel le 2026-08-12 : l'API quran.com ne sert QUE du Hafs.**

- `/resources/recitations` renvoie **12 récitateurs, tous Hafs**, aucun Warsh.
- `/quran/verses/{resource}` **ignore complètement** l'identifiant demandé :
  `uthmani`, `uthmani_warsh`, `warsh` et même un identifiant inventé
  (`totally_bogus_resource`) renvoient tous le **même texte Hafs**, HTTP 200.
  Il n'y a donc pas de « paramètre Warsh » caché à activer côté API.

Ce qui dépend de cet audio, et tombe donc entièrement :

| fonction | fichier | ce qui casse en Warsh |
|---|---|---|
| lecture du Mushaf | [audio_player_service.dart:26](app/lib/services/audio_player_service.dart#L26) | URLs Hafs |
| téléchargement hors-ligne | [reciter_download_service.dart:202](app/lib/services/reciter_download_service.dart#L202) | idem |
| **correction d'un mot raté** | [word_correction_audio.dart](app/lib/services/word_correction_audio.dart) | rejoue un mot Hafs sur une erreur Warsh |
| répétition incrémentale du Coach | [coach_incremental_repeat.dart](app/lib/screens/coach_incremental_repeat.dart) | idem (réutilise `playWordRange`) |
| découpe mot-à-mot | `QuranApi.fetchAyahSegments` | segments Hafs, indices de mots Warsh |
| aide tajweed « écouter » | [tajwid_help_sheet.dart](app/lib/widgets/tajwid_help_sheet.dart) | idem |

⇒ Un mode Warsh **sans source audio Warsh** donnerait une app qui affiche
Warsh et fait entendre Hafs sur la correction — c'est-à-dire qui **enseigne
l'erreur**. C'est le point à arbitrer en premier, avant tout code.

À noter au passage, **défaut préexistant trouvé pendant l'analyse** (sans
rapport avec Warsh, mais dans le fichier même que ce chantier va toucher) :
[reciter.dart:22-32](app/lib/models/reciter.dart#L22-L32) associe des noms à
des identifiants qui ne correspondent pas à ceux de l'API. Vérifié via l'URL
audio réelle renvoyée par l'API : `id=1` est Abdul Basit **Mujawwad** (l'app
dit Murattal), `id=2` Murattal (l'app dit Mujawwad), `id=5` est **Hani
ar-Rifai** (l'app dit Abu Bakr Ash-Shaatree), `id=9` **Minshawi** (l'app dit
Al-Husary), `id=10` **Shuraym** (l'app dit Al-Qatami), `id=11` **Al-Tablawi**
(l'app dit As-Sudais), `id=12` **Husary Muallim** (l'app dit Muhammad Ayyoub).
6 entrées sur 8 sont fausses. À traiter séparément, pas dans ce chantier.

## 5. Point de bascule n°3 — la chaîne ASR (le plus lourd)

Le modèle déployé est **volontairement Hafs-only** : c'était une correction
documentée (`ETAT_CTC_NEMO.md` §6) après qu'une contamination Warsh de 21 % ait
dégradé les runs précédents. Un mode Warsh demande donc un **second modèle**,
pas un réglage.

Trois artefacts du modèle sont indexés sur le texte Hafs :
- `vocab.json` — tokenizer BPE tajweed (1 024 tokens) appris sur du Hafs ;
  l'orthographe KFGQPC Warsh emploie des conventions différentes (`اِ۬لْحَمْدُ`
  contre `ٱلْحَمْدُ`), donc segmentation dégradée avant même l'acoustique ;
- `word_tokens.json` — 19 001 mots Hafs pré-tokenisés. Un mot absent **ne fait
  pas planter** (repli greedy, cf.
  [ForcedAligner.kt:1339-1358](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt#L1339-L1358))
  mais perd la qualité d'alignement ;
- `tete3.json` — l'écart au canonique, entraîné contre le canon **Hafs**.

Côté app, la cible de jugement se construit dans
[recitation_provider.dart](app/lib/providers/recitation_provider.dart) à partir
de `ArabicNormalizer.splitExpectedWords(v.textUthmani)` : elle suivra
automatiquement le texte Warsh — mais elle sera alors comparée à un modèle qui
n'a jamais entendu Warsh. **Le texte basculerait sans que le juge bascule.**

⚠️ Rappel des règles projet applicables ici : `solution-de-fond` (ne pas
déplacer un critère d'acceptation pour compenser un modèle inadapté) et
« pas de correctif palliatif ». Faire tolérer le Warsh à un modèle Hafs par
des seuils serait exactement le palliatif que le projet s'interdit.

## 6. Point de bascule n°4 — les données déjà enregistrées

Aucune table ne porte de colonne `riwaya`. Toutes indexent par
`(surah, ayah, word_index)` — la clé dont le §0 démontre qu'elle change de
sens :

| stockage | fichier | clé |
|---|---|---|
| journal d'erreurs cumulé (jamais purgé) | [recitation_error_log_service.dart:121](app/lib/services/recitation_error_log_service.dart#L121) | `surah_number, ayah_number, word_index` |
| sessions datées (7 j) | `session_archive_service.dart` — `session_words` | idem |
| **portions permanentes** | `session_archive_service.dart` — `portion_words` | `portion_id, ayah_number, word_in_ayah` |
| portions elles-mêmes | `portions.unit_key` = `s2h5`… | dérivé du **hizb**, absent du jeu Warsh |
| record du jeu Enchaînement | `memorization_game.best_words_by_portion` | clé `unit_key` |
| reprise Coach, signets | `last_coach_verse_provider.dart`, prefs | `(surah, ayah)` |

⇒ Il faut trancher, avant d'écrire une ligne : les statistiques sont-elles
**par riwaya** (une colonne/clé de plus partout, deux historiques séparés) ou
**partagées** (et alors une migration explicite, jamais un décalage
silencieux) ? Sans cette décision, un simple basculement de réglage
réattribuerait des erreurs d'un mot à un autre.

## 7. Ce qu'il reste à décider (à arbitrer, pas à supposer)

1. **L'audio Warsh** : accepte-t-on un mode Warsh sans correction sonore au
   départ, ou le chantier attend-il une source audio Warsh (les 22 récitateurs
   déjà téléchargés sont des sourates entières, pas des clips verset par
   verset alignés — à vérifier sur la machine Ubuntu) ?
2. **Le modèle ASR** : un second modèle Warsh est un entraînement complet.
   Tant qu'il n'existe pas, le mode Warsh doit-il **désactiver la
   vérification** (lecture/jeu seulement) plutôt que juger avec un modèle
   Hafs ?
3. **Les portions du Coach** : sans `hizb_number` en Warsh, on retombe sur le
   `jozz` (30 unités, plus grossier) ou on dérive les hizb nous-mêmes.
4. **Historique** : séparé par riwaya, ou partagé avec migration ?
5. **Tajweed coloré** : abandonné en Warsh, ou re-dérivé ?

## 8. Ordre de travail proposé (aucune étape ne démarre sans validation)

1. Intégrer le **texte** Warsh + une clé d'identité qui porte la riwaya
   (`w2:132` vs `h2:132`), et faire basculer `QuranApi` seul → l'app lit et
   affiche Warsh, tout le reste reste Hafs et **assumé désactivé**.
2. Ajouter la **riwaya dans les schémas** de stockage (avant toute écriture
   Warsh, sinon les données sont polluées dès la première session).
3. Décider du sort de la **vérification** (§7.2) et n'ouvrir la récitation en
   Warsh que quand le juge est le bon.
4. Audio, tajweed, timings, GOP : chacun est un chantier propre, mesurable
   séparément.

---

*Mesures de ce document faites le 2026-08-12 : comparaison Hafs/Warsh sur les
deux jeux de données complets, appels réels à `api.quran.com` (scripts et
sorties reproductibles), lecture des artefacts du modèle déployé. Ce qui n'a
pas pu être vérifié depuis ce poste est nommé comme tel (présence du corpus
audio Warsh sur la machine Ubuntu).*
