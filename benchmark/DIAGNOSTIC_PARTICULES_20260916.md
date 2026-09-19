# Le défaut des particules — pourquoi la détection plafonnait

Nuit du 15 au 16 septembre 2026. Objectif posé : **80 % de détection, moins de
5 % de faux signalements**. Ce document dit ce qui a été mesuré, ce qui a été
réfuté, et où est réellement le défaut.

---

## 1. Le chiffre a changé de sens

| | valeur | ce que c'est |
|---|---:|---|
| ancien banc, toutes familles | **66 %** | détection, `campagne_paliers_20260915` |
| substitutions seules | **82 %** | les erreurs réellement commises |
| chaîne historique, erreurs réelles | **2,0 %** | faux signalements |

L'ancien banc était composé à **72 % de coupures, insertions et omissions** :
un mot tranché en plein milieu, un mot supprimé, un mot inséré.

**Aucun récitateur ne fait cela.** Il dit `ٱلضَّالُّونَ` au lieu de
`ٱلضَّالِّينَ`, ou `وَ` au lieu de `ثُمَّ`. La critique est de l'utilisateur, le
16/09, et la mesure lui donne raison : en ne gardant que les substitutions, la
détection passe de 66 % à 82 %. **Le chiffre bas venait de la fabrication du
test, pas de l'application.**

---

## 2. Le banc d'erreurs réelles

`benchmark/campagne_erreurs_reelles_20260916.py` — 10 cas, **118 erreurs sur
1 254 mots**, uniquement des substitutions par une forme voisine **réellement
prononcée ailleurs** dans le corpus. Aucun mot coupé, aucun son fabriqué.

| famille | exemple | principe |
|---|---|---|
| `particule_ajoutee` | `ٱرْجِعِ` → `فَٱرْجِعِ` | une conjonction en trop |
| `particule_retiree` | `وَٱلْجِبَالَ` → `ٱلْجِبَالُ` | une conjonction absente |
| `flexion_finale` | `ٱلضَّالِّينَ` → `ٱلضَّالُّونَ` | même racine, autre cas |
| `flexion_interne` | même racine, voyelle longue différente | |

⚠️ Filtre indispensable : à distance d'édition 1, `إِذْ` et `أَمْ` ressortent
comme « voisins » alors que ce sont deux mots sans rapport. Le générateur exige
donc une **vraie parenté** — particule ajoutée/retirée devant le même mot, ou
racine commune avec désinence différente. Sans ce filtre, on fabrique du bruit,
pas des erreurs de récitateur.

---

## 3. Où l'application rate

Résultats sur le banc d'erreurs réelles, configuration `vote + tête 3 (BPE)` :

| famille | rappel |
|---|---:|
| **flexion finale** | **100 %** (7/7) |
| flexion interne | **83 %** (15/18) |
| particule retirée | 67 % (16/24) |
| **particule ajoutée** | **52 %** (16/31) |

### Le modèle n'est PAS biaisé par le contexte

C'était la crainte de l'utilisateur, et elle est levée : entendant
`ٱلضَّالُّونَ` là où le verset attend `ٱلضَّالِّينَ`, le modèle va-t-il
« corriger » vers la forme canonique parce qu'il connaît le passage ?

**Non — il l'entend, 100 % du temps.** Le biais canonique documenté depuis
juillet (« quand le modèle est convaincu du canonique, `forced == free`, donc
`gop = 0`, donc vert à tort ») ne joue pas sur les flexions.

**Tout le déficit tient dans les particules.**

---

## 4. Pourquoi les particules

Sur 87 lectures amputées de leur début, ce qui manque :

| début manquant | occurrences |
|---|---:|
| `وَ` | 14 |
| `فَ` | 10 |
| `بِ` | 6 |
| `أَ` / `إِ` / `ثَ` / `تُ` | 3 / 2 / 3 / 2 |

**72 de ces 87 cas portent sur des mots CORRECTS**, 15 seulement sur de vraies
fautes. Ce n'est pas le récitateur qui les oublie : **c'est le modèle qui ne
les produit pas**.

Vérification directe dans les logprobs (`BancProclitiquePerduJvmTest`) :

```
T802  فَهُمْ lu هُمْ    : le 'ف' est le PREMIER choix, logprob -0,075 (93 %)
T802  وَخَشِىَ lu خَشِىَ : le 'و' est au rang 4, logprob -7,556
T801  ثَجَّاجًا lu جَّاجًا : le 'ث' est au rang 24 — le modèle est muet dessus
```

Le modèle **produit parfois** le proclitique et **parfois pas du tout**. Ce
sont une consonne et une voyelle brève : les segments les plus courts et les
moins énergétiques de la langue.

⇒ Le défaut n'est **ni dans l'alignement, ni dans la décision, ni dans la
tête 3** : c'est un segment phonétique précis que le modèle acoustique ne
produit pas de façon fiable. **Cela se traite à l'entraînement.**

---

## 5. Huit pistes testées dans la chaîne — une seule retenue

Banc JVM rejouant l'audio réel, le modèle embarqué et la chaîne entière, sans
téléphone. **Ne pas les refaire.**

| piste | résultat mesuré | verdict |
|---|---|---|
| **une lecture entière prime sur un mot amputé** | **8 faux évités, 0 perte** | **retenue** |
| marge de confusion sur les lettres | 10 rattrapées / **139 faux** | morte |
| champ `couvert` comme signal de troncature | vaut `true` sur 100 % des observations | morte |
| écarter tous les fragments | 21 évités / **16 détections perdues** | morte |
| `gop` | médiane **0,000** des deux côtés | morte |
| durée attribuée par lettre | 0,57 contre 0,62, distributions superposées | morte |
| rendre au mot son début rogné (`framesAvanceeDebut`) | 48 → 46 faux | morte |
| reprendre les frames prises par le voisin | taux inchangés | morte |

### L'erreur de méthode, et elle compte

Ces huit tests ont été menés **sans jamais confronter l'audio au modèle seul**,
alors que la règle du projet l'impose en premier (`verifier_erreurs.py` : « un
mot que le modèle lit correctement sur l'audio brut est un faux positif de la
chaîne, pas une faute de récitation »).

Une fois fait (`BancFautesAudiblesJvmTest`), le partage est apparu : sur 58
fautes laissées passer, **34 sont inaudibles pour le modèle** et **24 sont
perçues mais perdues par la chaîne**. Sans cette vérification, les huit
réglages cherchaient au mauvais endroit.

---

## 6. Le vote coûte plus qu'il ne rapporte

Sur le banc d'erreurs réelles :

| configuration | erreurs détectées | faux signalements |
|---|---:|---:|
| **chaîne historique** | 58 % | **2,0 %** |
| vote entre fenêtres | 68 % | 8,1 % |
| vote + tête 3 | 68 % | 8,1 % |

Le vote gagne dix points de détection et **quadruple** les fausses accusations.
Pour une application qui reprend un récitateur, c'est un mauvais échange : **la
chaîne historique tient déjà l'objectif de moins de 5 % de faux**.

La tête 3, une fois ses entrées corrigées par Codex (tokenisation
SentencePiece, cf. `CORRECTION_TOKENISATION_TETE3_JVM_20260915.md`), ne change
plus rien — ni en bien ni en mal. Elle reste éteinte par défaut, derrière son
marqueur `files/tete3_decision_actif`.

---

## 7. Ce qui suit

| piste | pourquoi |
|---|---|
| **décodage par faisceau** | Le décodage libre est glouton (argmax par frame). Une particule brève se perd ainsi alors que le modèle lui donne de la masse (rang 0 à 93 % sur un cas mesuré). Mesurable sur ce banc, **sans réentraîner**. |
| **scores par jeton, pas par mot** | `forced`/`free` sont agrégés sur le mot : on voit que le texte diffère, jamais que le modèle était muet sur les deux premières frames. Sans cette instrumentation, les pistes suivantes se jugent à l'aveugle. |
| **entraînement sur les segments brefs** | La seule voie qui attaque la cause. Les proclitiques sont sous-représentés dans ce que le modèle apprend à émettre. |

---

## Reproduire

```powershell
python benchmark/campagne_erreurs_reelles_20260916.py prepare
cd app/android
.\gradlew.bat '-DasrBanc=true' :app:testDebugUnitTest --tests '*BancChaineOnnxJvmTest'
.\gradlew.bat '-DasrBanc=true' :app:testDebugUnitTest --tests '*BancFautesAudiblesJvmTest'
.\gradlew.bat '-DasrBanc=true' :app:testDebugUnitTest --tests '*BancProclitiquePerduJvmTest'
```

Clips audio des fautes laissées passer, pour écoute humaine :
`benchmark/clips_fautes_ratees_20260916/` (58 clips + `LISEZ_MOI.md`).

---

## Ce que ce banc ne dit pas

- Le mot remplaçant vient d'un autre passage : **sa prosodie diffère** (débit,
  intonation, position dans la phrase). Une part des détections peut venir de
  cette rupture plutôt que du mot lui-même. Limite inhérente au montage.
- Hafs uniquement — aucune source Warsh dans ce banc.
- Les chiffres JVM ne sont pas bit à bit ceux d'Android (ORT desktop, C1 seul).
  Les comparaisons **internes** au banc valent ; les valeurs absolues non.
- **La suite de tests complète n'a pas été relancée** après les changements du
  `Decideur` et de `AligneurForce`. Rien n'est commité.

---

Version illustrée du même diagnostic (tableaux, barres par famille) :
https://claude.ai/artifact/53iMbwzHpbVf8CJTbvv36M
