# Graphe de la chaîne de récitation — mode d'emploi pour l'agent

**Ce document n'est pas destiné à être lu par l'utilisateur.** C'est le point
d'entrée de l'agent qui va redévelopper la chaîne de récitation *from scratch*.

Le graphe encode **ce qui a déjà été essayé et ce que la mesure en a dit**.
Avant d'écrire une ligne de code sur cette chaîne, l'interroger. Une idée qui
paraît neuve a de fortes chances d'être un nœud `[MORT]` avec sa mesure.

## Interroger

```bash
graphify query "<question>"                 # traversée BFS, contexte large
graphify query "<question>" --budget 3000   # remonter le plafond de tokens
graphify path "<nœud A>" "<nœud B>"         # chemin le plus court entre deux concepts
graphify explain "<nœud>"                   # explication d'un nœud
```

Rendu interactif : `graphify-out/graph.html` (aucun serveur requis).

⚠️ La traversée apparie sur le **vocabulaire des libellés**. Une question dans
des mots absents du graphe remonte du bruit. Utiliser les préfixes ci-dessous.

## Ce que contient le graphe

**1436 nœuds, 2394 arêtes, 96 communautés.** Deux couches superposées :

| Couche | Contenu |
|---|---|
| **AST** (989 nœuds) | fonctions, classes, symboles réels de 69 fichiers Kotlin/Dart/Python |
| **Sémantique** (514 nœuds) | ce que l'AST ne peut pas voir — voir ci-dessous |

### Ce qui a été réellement lu (périmètre du contrôle)

- **184 commits** sur toutes les branches : sujet indexé.
- **91 commits** touchent la chaîne de récitation. Pour ceux-là :
  **le diff réel a été lu** (`git show --unified=0`) et **le corps de message
  injecté** — 85 ont un corps, **63 portent des mesures chiffrées** (taux avant/après,
  nombre de mots sautés, durées). Le `rationale` du nœud commit les contient.
- **96 constantes** et **95 fonctions** réellement touchées, extraites des diffs.
- **6 documents** lus intégralement : `CHAINE_RECITATION.md`,
  `ARCHITECTURE_RECITATION.md`, `CAPITAL_VERSIONS.md`,
  `REVUE_ARCHITECTURE_KARAOKE.md`, plus `CLAUDE.md` et le git.

⚠️ **Les 93 commits hors chaîne (UI, mindmaps, tuteur, entraînement) n'ont que
leur sujet indexé** — leur diff n'a pas été lu. Et **26 des 30 `.md` du projet
ne sont pas dans la couche sémantique** (notamment `PROBLEMATIQUES_ASR.md` et
`FONCTIONNALITES_FUTURES.md`, ~1000 lignes chacun). À lire directement si le
sujet les concerne.

### Les préfixes qui font le garde-fou

| Préfixe | Nb | Ce que c'est |
|---|---|---|
| `[MORT]` | 14 | **Piste mesurée perdante.** Le `rationale` porte la mesure qui la tue. Ne pas réintroduire sans cause nouvelle. |
| `[PIEGE]` | 15 | Erreur déjà commise, souvent plusieurs fois. |
| `[EN ATTENTE]` | 10 | Non mesuré ou non gagnant **aujourd'hui**, récupérable par `git show`. |
| `[SYMPTOME]` | 10 | Défaut observé, avec la couche où il **naît** vs celle où il se **voit**. |
| `[REGLE]` | 7 | Règle de méthode (process), pas de code. |
| `couche_1..6` | 6 | Les six couches, du micro à la couleur affichée. |
| `fn_*` | 62 | Fonction réelle, avec `fichier:ligne` et son rôle. |
| `var_*` | 86 | **Constante réelle lue dans le code**, avec sa valeur et ce qu'elle pilote. |
| `commit_*` | 184 | Tous les commits, **toutes branches** (y compris les branches de test). |
| `branche_*` | 6 | `master`, `asr-nemo-solutions`, `chunkwise-aligner`, `gradient-aligner`, `test-1-gop`, `test-2-gop`. |

### Les arêtes qui répondent à la vraie question

Le problème identifié par l'utilisateur : *« entre plusieurs commits il y a
parfois le même fonctionnement, et une petite fonctionnalité ou variable qui
touche à plusieurs couches »*. Trois familles d'arêtes l'encodent :

- **`commit → symbole`** (`shares_data_with`, 296 arêtes) — quel commit a touché
  quel symbole, **avec le sens** (`AJOUTE` / `SUPPRIME` dans `source_location`).
  Dérivé des **diffs réels**, pas des messages.
- **`commit ↔ commit`** (`semantically_similar_to`, **843 arêtes**) — **deux
  commits qui touchent le même symbole sont couplés, même si rien ne le dit.**
  `source_location` nomme le symbole partagé. C'est ce couplage invisible qui
  produit les régressions.
- **`couche → couche`** (`shares_data_with`) — les couplages structurels, avec
  l'effet ballon dans le champ `source_location`.

### Points chauds mesurés (symboles les plus retouchés)

Ce sont les endroits où le code n'a jamais convergé — à traiter en priorité
dans la réécriture :

| Symbole | Retouché | Commits |
|---|---|---|
| `runAlignment` | **7×** | 8193111 4b42b4a 24d7521 f94a890 5d97e09 9024fb6 fc6d731 |
| `OVERLAP_SECONDS` | **6×** | cd5c0f0 58db2fa 4b42b4a 24d7521 ed2ca8a d671c33 |
| `computeLogProbs` | 6× | 8193111 4b42b4a 24d7521 f94a890 5d97e09 fc6d731 |
| `appendMergingOverlap` | 5× | 58db2fa 4b42b4a 24d7521 ed2ca8a d671c33 |
| `computeAll` / `decodeTajwid` | 5× | 8193111 4b42b4a 24d7521 f94a890 5d97e09 |
| `MAX_SILENCE_SAMPLES` | 4× | bca8706 a0c8935 6d07754 e800305 |
| `greedyDecode` / `reset` | 4× | — |
| `RESYNC_ACTIF` | 3× | bca8706 a0c8935 41df3e3 |
| `RIGHT_CONTEXT_SECONDS` | 3× | d709c7d a0c8935 363a3a1 |

## Les questions à poser avant de coder

```bash
graphify path "<la variable que je veux toucher>" "⑥ Jugement et affichage (Dart)"
graphify query "MORT <le mécanisme que j'envisage>"
graphify query "PIEGE <la couche que je touche>"
graphify query "SYMPTOME <ce que j'observe>"     # → la couche où il NAÎT
```

## Ce que le graphe dit et qui doit cadrer la réécriture

Ces constats sortent du graphe lui-même, pas d'une opinion :

1. **La normalisation `per_feature` a dicté toute l'architecture aval.**
   Elle interdit l'incrémental → d'où le « tout re-transcrire toutes les 1,5 s ».
   Elle dérive sur les longs buffers → d'où le gel et la borne 12 s.
   Le gel est un **contournement**, jamais une fonctionnalité voulue.
   (`piege_normalisation_dicte_archi`)

2. **La moitié de la logique de jugement existe pour compenser la segmentation.**
   `MIN_FRAMES_FOR_JUDGMENT`, `deferredOnceIndex`, tolérance aux fragments,
   tolérance au bleed préfixe, filet décodage-libre. Chaque rustine est
   individuellement justifiée ; leur accumulation est le signal que la cause est
   en amont. (`piege_moitie_logique_compense`)

3. **`gop = forced − free` est relatif, il manque un signal absolu.**
   Mesuré : attendu `صِرَٰطَ`, entendu `سَرَٰطَ`, gop = −0,35 → **vert**, parce que
   le modèle hésitait sur tout. « Pas beaucoup pire que le meilleur chemin »
   n'est pas « correct ». (`piege_gop_relatif`)

4. **La majorité des mots sont verrouillés sur des aperçus**, donc sur un audio
   incomplet — `lock = p.isFinal || judged == correct`. (`piege_verrou_sur_apercu`)

5. **Neuf versions mesurées n'ont jamais été commitées.** `v5b-derive` est le
   meilleur résultat du projet (médiane **0,57 %**, une passe à **0,00 %**) et son
   code est irrécupérable. Cela prouve qu'un taux sous 1 % est atteignable et
   qu'**aucune version commitée n'y est parvenue**. (`piege_9_versions_perdues`)

6. **`findResyncOffset` ne cherche qu'en avant** : un récitateur qui répète ne
   peut structurellement pas être suivi, et le banc — qui rejoue un audio
   linéaire — ne peut pas produire ce cas. (`piege_resync_avant_seulement`)

## À faire, inscrit dans le graphe (2026-08-06)

**`[EN ATTENTE] Recouvrement PARTIEL des fenêtres d'aperçu`** — demande
explicite de l'utilisateur : « garde-la dans le graphe comme à faire ».

Deux mesures encadrent la piste, et c'est ce qui la rend intéressante :

- le recouvrement **50 %** (`pas=2` / `largeur=4`) a été retiré au profit de
  `pas=4` / `largeur=4` : **même taux** (1,02 % de non-verts sur Al-Baqara,
  rejeu déterministe) pour **22 % de fenêtres en moins**. Une fois la SECONDE
  ligne de jugement en place, le recouvrement total ne payait plus sa charge ;
- le **mot 11** reste mal cadré. Balayé hors device, il est lu parfaitement dès
  qu'il n'est **pas au bord** de la fenêtre : c'est un défaut de CADRAGE, pas
  une limite du modèle.

D'où l'hypothèse à mesurer : un recouvrement **intermédiaire** (`pas=3` /
`largeur=4`), qui évite de remettre un mot au bord sans revenir au coût du
50 %.

⚠️ Ne pas confondre avec la **grille coprime 3/5** (deux lignes de périodes
premières entre elles) : celle-là a été mesurée et reste **derrière le 4/4**.
C'est une piste distincte, déjà tranchée.

## Contrat du modèle (à ne pas re-dériver)

Cible de la réécriture : **causal v1**, verrouillé par `StreamingModelConfig.kt` —
`EXPECTED_SOURCE_NEMO = "causal-final.nemo"`, contexte d'attention `[70, 13]`,
121 frames d'entrée, 112 de décalage, 14 de sortie valides, sous-échantillonnage 8.

L'export ONNX doit exposer **`audio_signal`** (mel), jamais `raw_audio` : le mel
est calculé côté app par `MelSpectrogram.kt`. Piège tombé deux fois.
(`piege_audio_signal`)

## Régénérer

Les scripts de génération sont dans `/tmp/gen/` (non pérenne). Le graphe se
reconstruit depuis le dépôt ; l'ancien graphe couvrant toute l'app est conservé
dans `graphify-out/graph_ancien_tout_app.json` — jamais écrasé (règle projet).
