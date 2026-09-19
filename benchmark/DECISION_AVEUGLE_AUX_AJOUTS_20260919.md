# La décision est aveugle aux ajouts — et le modèle, lui, les entend

19 septembre 2026. Document de passation : l'utilisateur a forcé des fautes que
l'application n'a pas signalées. Le diagnostic est fait, la cause est isolée, et
**une piste a déjà été mesurée puis rejetée** — elle est consignée ici pour
qu'elle ne soit pas retentée telle quelle.

Constat de l'utilisateur, qui est le point de départ : *« je ne suis pas
satisfait que le modèle réponde bien et que ce soit l'application qui génère mal
les décisions »*.

**Il a raison, et c'est mesuré.**

---

## 1. Ce qui s'est passé

Session du 2026-09-19 14:25, Al-Baqara 2:1-5, fautes insérées volontairement.
**33 mots jugés : 29 verts, 2 omis, 2 provisoires.** Aucune des fautes n'a été
signalée.

Or le modèle les a toutes entendues. Transcript libre, tel quel :

```
f=24   فَمَآ أُنزِلَ مِن قَبْلِكَ            ← فَ au lieu de وَ
f=25   ...إِلَيْكَ فَ وَمَآمَآ أُنزِلَ       ← فَ en trop + répétition
f=40   وَبِلَالْـَٔاخِرَةِ هُمْ يُوقِنُونَ     ← لَ en trop
f=42   فَأُو۟لَـٰٓئِكَ عَلَىٰ هُدًى          ← فَ ajouté
```

L'information est produite, complète, puis perdue en aval.

---

## 2. Pourquoi le `gop` ne peut pas les voir

`gop = forced − free`. C'est un **écart**, pas une qualité absolue. Quand le
décodage libre se dégrade en même temps que l'alignement forcé, l'écart se
referme et le mot passe.

Mot 29, `وَبِٱلْـَٔاخِرَةِ`, prononcé `وَبِلَٱلْـَٔاخِرَةِ` :

| obs | forced | free | gop | verdict |
|---:|---:|---:|---:|---|
| 1 | **−1,92** | −0,22 | −1,70 | **rouge** ✅ |
| 2 | −0,51 | −0,18 | −0,33 | vert |
| 3 | −0,48 | **−0,35** | **−0,14** | **vert définitif** ❌ |

**Le premier verdict était juste, les observations suivantes l'ont écrasé.** Ce
n'est donc pas un problème de seuil : c'est l'accumulation de preuves qui efface
un verdict correct.

Les trois observations de ce mot disent `لَلْـَٔاخِرَةِ`,
`وَبِلَالْـَٔاخِرَةِ`, `وَبِلَٱلْـَٔاخِرَةِ` — **aucune ne dit le mot attendu**.
Le texte trahit la faute ; le score ne la voit pas.

Mot 32, `أُو۟لَـٰٓئِكَ` prononcé `فَأُو۟لَـٰٓئِكَ` : `forced = −0,22`,
`free = −0,22`, donc **`gop = 0,00` exactement**. C'est le biais canonique que
le projet documente depuis juillet, dans sa forme pure — « quand le modèle est
convaincu du canonique, `forced == free`, donc `gop = 0`, donc vert à tort ».

⇒ **L'application vérifie que le mot attendu est présent, jamais qu'il n'y a
rien d'autre.** Toute faute par AJOUT passe structurellement au travers. Cela
recoupe la mesure du banc : *particule ajoutée 52 %* contre *100 %* sur les
flexions finales.

---

## 3. Le défaut d'attribution, qui aggrave tout

Une insertion **décale l'alignement**, et le décalage se propage aux voisins.

| mot | attendu | ce que l'aligneur lui a donné | verdict |
|---:|---|---|---|
| 25 | `وَمَآ` | `فَ` seul, **2 frames** (160 ms) | provisoire:vert |
| 28 | `قَبْلِكَ` | `وَبِ` — le **début du mot suivant** | **`omis`** |

Le mot 28 est déclaré **`omis`** — le verdict le plus grave de l'app, « vous
n'avez pas prononcé ce mot » — alors que `f=24` contient `أُنزِلَ مِن قَبْلِكَ`
en clair. C'est un faux `omis` causé par le décalage.

Et le mot 25 a été jugé sur **2 frames**. Un `gop` calculé sur 160 ms d'un mot
qui en dure trois fois plus ne mesure rien.

---

## 4. La piste testée, et REJETÉE par la mesure

**Proposition de l'utilisateur** : que le modèle « revienne et fasse un grand
bout d'un coup pour contrôler après ».

L'idée est juste, et mieux : **cette passe longue existe déjà**. `f=25` fait
11,84 s et contient le `فَ` inséré. Il suffirait de comparer le TEXTE ENTIER
d'une fenêtre longue au texte attendu de sa bande, et de signaler les mots
décodés qui n'y ont rien à faire (« intrus »).

Mesuré sur le banc des erreurs réelles (118 fautes / 1 254 mots),
`benchmark/simuler_controle_texte_20260919.py` :

**Par fenêtre** — le chiffre flatteur :

| | sans filtre | avec filtres (bords + fragments) |
|---|---:|---:|
| alertes sur une vraie faute | 185 | 96 |
| alertes sur du correct | 106 | 30 |
| précision | 64 % | **76 %** |

**Par mot** — le chiffre qui décide :

| | |
|---|---:|
| fautes déjà détectées par la chaîne | 54 |
| fautes rattrapées **en plus** | **19** |
| mots corrects accusés **à tort** | **387** |

⛔ **19 détections gagnées pour 387 faux signalements** — vingt fausses
accusations par faute rattrapée. Inutilisable en l'état.

**Pourquoi l'écart entre les deux tableaux** : une fenêtre qui porte un intrus
accuse **toute sa bande**. Un seul intrus dans une fenêtre de huit mots en salit
huit. La règle sait dire « il y a une faute ici », pas « c'est ce mot-là ».

⚠️ **Leçon de méthode, et c'est la troisième fois ce mois-ci** : la première
mesure (par fenêtre, 76 % de précision) aurait justifié d'implémenter. La
seconde (par mot, contre ce que la chaîne détecte déjà) l'interdit. Toujours
mesurer le GAIN NET par rapport à l'existant, jamais la qualité d'un signal pris
isolément.

---

## 5. Ce qui reste ouvert

**A. Localiser l'intrus au lieu d'accuser la bande.** Le signal existe (toutes
les fautes de la session y sont) ; ce qui manque est l'attribution. Un
alignement de séquences (Levenshtein sur les mots, décodé contre attendu)
dirait *où* tombe l'insertion. C'est la suite naturelle du §4 et elle se mesure
avec le même script, sans toucher à l'application.

**B. Le décalage d'alignement sur insertion** (§3). C'est la cause amont : tant
qu'un mot reçoit le début du suivant, aucune règle aval ne peut viser juste. Le
`omis` du mot 28 en est la preuve la plus nette.

**C. Un verdict juste ne devrait pas être écrasé par des observations
ultérieures** (§2, mot 29 : rouge à la première observation, vert à la
troisième). À instruire : que fait l'accumulation de preuves d'un premier
verdict très négatif ?

**D. Le vote entre fenêtres a été ACTIVÉ sur l'appareil de test** le 19/09
(marqueur `files/vote_fenetres_actif`). Il compare les textes mot par mot, donc
sans le défaut d'attribution du §4. Mesure connue au banc : détection 58 % →
68 %, mais faux signalements 2,0 % → 8,1 %. **Résultat sur les fautes par ajout
non encore mesuré** — c'est le prochain test utilisateur.

---

## Reproduire

```powershell
# la simulation de la regle d'intrus (par fenetre, puis par mot)
python benchmark/simuler_controle_texte_20260919.py

# les captures de la session ou les fautes ont ete forcees
#   benchmark/captures_erreurs_20260919/session_1789820592923/  (283 Ko)
#   benchmark/captures_erreurs_20260919/session_1789820712116/  (4,3 Mo, 137 s)
```

Journal de la session : lignes 54882 et suivantes de
`recitation_diagnostic.log` (appareil `R3CY20XW7TD`, build
`v467-consignes-essais-tajwid-dabord`, `decision=HISTORIQUE`).

---

## Ce que ce document ne dit pas

- Les chiffres du §4 viennent du banc d'erreurs réelles, dont les familles sont
  *particule* et *flexion* — pas de gémination, pas de coupure.
- La session du §1 est **une seule** récitation, avec des fautes volontaires :
  elle montre le mécanisme, elle ne mesure pas un taux.
- Rien n'a été modifié dans la chaîne de décision. Les trois ajouts du jour
  (`firstFrame`, `lastFrame`, `samplesParFrame`) sont purement additifs et
  servent la collecte, pas le jugement.
