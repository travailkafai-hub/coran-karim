# Prompt de réécriture — chaîne de récitation *from scratch*

Copier tout le bloc ci-dessous comme premier message de la nouvelle session.

---

## MISSION

Tu réécris **entièrement** la chaîne de vérification de récitation coranique du
projet Coran Karim. Le code existant sera supprimé : ne cherche pas à le
préserver, à le refactorer, ni à t'y conformer. Tu repars d'une page blanche
sur ce périmètre précis.

**Ce que l'app doit faire, et rien d'autre** : le récitateur récite, l'app
écoute **en streaming**, suit le texte **mot par mot**, et dit **immédiatement**
si ce qui vient d'être dit est juste. Vert = correct, orange = douteux,
rouge = faux.

**Périmètre** : uniquement la chaîne micro → jugement du mot. Pas l'IHM, pas le
tuteur Gemma, pas la révision FSRS, pas l'entraînement de modèle.

## AVANT TOUTE CHOSE — LIS LE GRAPHE

Un graphe de connaissance a été construit sur **tout l'historique du projet** :
184 commits sur 6 branches, les diffs réels des 91 commits qui touchent cette
chaîne, 96 constantes, 95 fonctions, et surtout **toutes les pistes déjà
mesurées perdantes**.

**Ce graphe existe parce que ce chantier a échoué de façon répétée.** Neuf mois
de correctifs, treize versions dont aucune concluante, et le meilleur résultat
du projet a été perdu faute de commit. Chaque idée qui te paraîtra neuve a une
forte probabilité d'être déjà dans le graphe avec la mesure qui l'a tuée.

```bash
# Point d'entrée obligatoire — le mode d'emploi du graphe
cat "GRAPHE_RECITATION.md"

# Interroger
graphify query "<question>" --budget 3000
graphify path "<nœud A>" "<nœud B>"
```

⚠️ **La traversée apparie sur le vocabulaire des libellés.** Une question
formulée dans des mots absents du graphe remonte du bruit. Utilise les
préfixes : `[MORT]`, `[PIEGE]`, `[EN ATTENTE]`, `[SYMPTOME]`, `[REGLE]`,
`couche_1..6`, `fn_*`, `var_*`, `commit_*`.

Le rendu visuel est dans `graphify-out/graph.html`.

### Les quatre requêtes à passer avant d'écrire une ligne

```bash
graphify query "MORT <le mécanisme que tu envisages>"
graphify query "PIEGE <la couche que tu touches>"
graphify query "SYMPTOME <le défaut que tu veux corriger>"   # → la couche où il NAÎT
graphify path "<la variable que tu veux introduire>" "⑥ Jugement et affichage (Dart)"
```

Le champ `rationale` des nœuds `commit_*` contient **le corps de message
complet avec les mesures chiffrées** (63 commits en portent). C'est la source
la plus fiable du projet : elle dit ce qui a été mesuré, pas ce qui a été espéré.

## CONTRAINTES NON NÉGOCIABLES

1. **Modèle : causal v1.** `EXPECTED_SOURCE_NEMO = "causal-final.nemo"`,
   contexte d'attention `[70, 13]`, 121 frames d'entrée, 112 de décalage,
   14 de sortie valides, sous-échantillonnage 8, `window_stride` 10 ms.
   Ce contrat est vérifié au chargement — ne le contourne pas.

2. **L'export ONNX expose `audio_signal` (mel), JAMAIS `raw_audio`.**
   Le mel est calculé côté app. Piège tombé **deux fois** dans ce projet : un
   export E2E valide parfaitement PyTorch==ONNX, le modèle se charge (log
   rassurant et trompeur), et **chaque transcription échoue en silence**.
   Vérification obligatoire avant tout déploiement :
   ```bash
   python3 -c "import onnxruntime as ort; print([i.name for i in ort.InferenceSession('<model.onnx>').get_inputs()])"
   ```
   « Le modèle est chargé » ne prouve rien. Exige une vraie transcription.

3. **Aucun verdict sans preuve acoustique.** Un mot ne peut être jugé que sur
   de l'audio réellement analysé. Pas de verdict par défaut, pas de verdict sur
   absence de donnée.

4. **Aucun audio détruit.** Tout ce qui entre par le micro doit rester
   atteignable pour analyse. 35 % de l'audio n'existait dans aucun fichier à un
   moment de ce projet — ça a invalidé des journées de mesure.

5. **Temps réel tenu.** Le retard entre la parole et le verdict est une
   propriété de conception, pas une conséquence à constater.

## MÉTHODE IMPOSÉE

Ces règles viennent de consignes utilisateur explicites, motivées par des
échecs réels. Elles ne sont pas négociables.

- **PROPOSER ET FAIRE VALIDER AVANT DE DÉVELOPPER.** Expose la cause, le
  correctif envisagé, **et les effets de bord attendus** — puis ATTENDS la
  validation. Ne code pas, ne build pas, n'installe pas avant.
  **Si tu identifies toi-même un effet de bord pendant l'analyse, cet effet
  interdit l'implémentation directe** : il doit être arbitré par l'utilisateur.

- **PAS DE CORRECTIF PALLIATIF.** Ne compense jamais une perte d'information
  d'une couche basse par une tolérance ajoutée dans une couche haute. Identifie
  la couche où le défaut **naît**, pas celle où il se **voit**.
  Cas réel : requalifier « correct » tout fragment cohérent validait un
  récitateur ne disant que **la moitié d'un mot** — exactement ce que l'app
  existe pour détecter.

- **UN SEUL CHANGEMENT PAR VERSION AVANT DE MESURER.** Empiler deux changements
  rend le résultat ininterprétable — c'est ce qui a produit treize versions dont
  aucune n'est concluante.

- **MESURE HORS DEVICE AVANT DE TOUCHER AU MOTEUR.** Quatre correctifs
  « évidents » ont été testés en une journée, **tous rejetés par la mesure**.
  Bancs disponibles : `benchmark/simulate_sliding_window.py`,
  `benchmark/analyze_device_log.py`, `benchmark/comparer_politiques_coupe.py`,
  `benchmark/verifier_erreurs.py`, `benchmark/ancre_vs_realite.py`.

- **UNE CORRÉLATION NE PROUVE RIEN.** `conserve=0` avait r = 0,67 sur 45
  sessions avec séparation sans chevauchement — et l'intervention l'a réfutée.
  Interviens sur la variable avant de conclure à une cause.

- **COMMITE AVANT CHAQUE CHANGEMENT IMPORTANT.** Neuf versions mesurées de ce
  projet n'ont jamais été commitées, dont `v5b-derive` — **le meilleur résultat
  jamais obtenu (médiane 0,57 %, une passe à 0,00 %)**, code irrécupérable.
  Ne fais jamais `git add -A` : l'arbre porte un gros état non commité
  préexistant. Committe fichier par fichier.

- **Ne supprime jamais un commentaire qui documente une tentative passée.**
  Ajoute une note à côté. C'est la seule trace de ce qui a déjà été essayé.

### Skills à invoquer

- `solution-de-fond` — **avant** de toucher à un seuil, une tolérance, un
  critère de jugement, ou d'ajouter un rattrapage.
- `superviseur-recette` — **après chaque modification**, sans attendre qu'on le
  demande. Il vérifie que l'app fait toujours ce pour quoi elle existe.
- `analyse-session-recitation` — dès qu'il faut analyser une session réelle.
- `recul-architectural` — si un bout de code en est à sa 4ᵉ version, ou si un
  symptôme déjà corrigé réapparaît.

## CE QUE LE GRAPHE DIT ET QUI DOIT CADRER TA CONCEPTION

Six constats issus de la mesure, pas d'une opinion. Ils expliquent pourquoi
l'ancienne architecture ne pouvait pas converger.

1. **La normalisation `per_feature` a dicté toute l'architecture aval.**
   Elle interdit la transcription incrémentale → d'où le « tout re-transcrire
   toutes les 1,5 s ». Elle dérive sur les longs buffers → d'où le gel et la
   borne 12 s. **Le gel est un contournement, jamais une fonctionnalité voulue.**
   → *Décision de conception à prendre explicitement, en premier.*

2. **La moitié de la logique de jugement existait pour compenser la
   segmentation.** `MIN_FRAMES_FOR_JUDGMENT`, `deferredOnceIndex`, tolérance aux
   fragments, tolérance au bleed préfixe, filet décodage-libre. Chaque rustine
   était justifiée ; leur accumulation était le signal que la cause était en amont.
   → *Si tu réintroduis une de ces rustines, c'est que la segmentation te pose
   le même problème. Traite la segmentation.*

3. **`gop = forced − free` est relatif — il manque un signal absolu.**
   Mesuré : attendu `صِرَٰطَ`, entendu `سَرَٰطَ`, gop = −0,35 → **vert**, parce que
   le modèle hésitait sur tout. « Pas beaucoup pire que le meilleur chemin »
   n'est pas « correct ».
   → Piste mesurée **GO** : rescoring de variantes sur les **lettres**
   (80,8 % sur 854 clips, marge médiane +3,80).
   → Piste mesurée **NO-GO** : la même chose sur les **harakat** (49,6 %, soit
   le hasard). Ne verrouille **jamais** un verdict harakat là-dessus.

4. **La majorité des mots étaient verrouillés sur des aperçus**, donc sur un
   audio incomplet — `lock = p.isFinal || judged == correct`.
   → *Le moment du verrouillage est une décision de conception centrale.*

5. **`findResyncOffset` ne cherchait qu'en avant** : un récitateur qui répète ne
   pouvait structurellement pas être suivi. Et le banc, qui rejoue un audio
   linéaire, **ne peut pas produire ce cas** — le défaut était donc invisible en
   mesure.

6. **`runAlignment` a été réécrit 7 fois, `OVERLAP_SECONDS` 6 fois.**
   Ce sont les points où le code n'a **jamais** convergé. Ils marquent la
   frontière mal découpée entre alignement, secours et gestion d'ancre.
   → *C'est la première interface à redessiner.*

## CE QUE J'ATTENDS DE TOI EN PREMIER

**N'écris aucun code.** Rends d'abord :

1. **Ce que tu as tiré du graphe** : les pistes mortes que ta conception évite,
   et celles en attente que tu comptes reprendre (avec leur commit).
2. **L'architecture proposée** : les couches, et surtout **le contrat exact
   entre chaque couche** — c'est l'absence de contrat clair qui a produit les
   régressions en cascade.
3. **Comment tu traites le constat n°1** (normalisation / segmentation), qui
   conditionne tout le reste.
4. **À quel moment un mot est jugé, et à quel moment son verdict devient
   définitif** — avec le retard attendu, chiffré.
5. **Comment tu mesures** que ça marche, avant tout déploiement sur device.
6. **Les effets de bord que tu as identifiés** — leur existence interdit
   l'implémentation directe, ils doivent être arbitrés.

Puis **attends la validation**.

---

## Documents à lire si le sujet les concerne

Ils ne sont **pas** dans le graphe (26 des 30 `.md` du projet n'y sont pas) :

| Document | Contenu |
|---|---|
| `PROBLEMATIQUES_ASR.md` (983 l.) | énoncé des problèmes + état de l'art externe (forums, papers) |
| `FONCTIONNALITES_FUTURES.md` (989 l.) | idées validées non implémentées, 3 hypothèses de segmentation mortes |
| `CHAINE_RECITATION.md` | la chaîne fonction par fonction — **la carte de l'ancien code** |
| `CAPITAL_VERSIONS.md` | inventaire v1→v24 : pris / en attente / mort / perdu |
| `ARCHITECTURE_RECITATION.md` | paramètres chiffrés et limites structurelles de l'ancien code |
| `REVUE_ARCHITECTURE_KARAOKE.md` | revue critique + plan P0/P1/P2 et sa contre-revue |
| `ETAT_CTC_NEMO.md` | état des modèles, WER, déploiement |
