# Architecture de la chaîne de récitation — document de référence

**Pourquoi ce document existe.** Le 2026-07-30, l'utilisateur a relevé un défaut
de méthode réel : *« à chaque fois que je te pousse en question, tu me dis une
réponse, puis quand tu cherches tu me modifies la réponse »*. C'était exact — six
diagnostics contradictoires en une journée, parce qu'aucun modèle stable du
système n'était écrit nulle part. Chaque question déclenchait une redécouverte.

**Comment l'utiliser.** Avant de répondre à une question sur le comportement de
la chaîne, ou avant d'écrire un correctif : **lire ce document d'abord**. Il ne
contient que des faits vérifiés dans le code ou mesurés, avec leur preuve. S'il
est contredit par une mesure, c'est LUI qu'il faut corriger — pas improviser une
nouvelle explication à côté.

Complément : `CHAINE_RECITATION.md` liste chaque fonction du micro à la
validation. Ce document-ci porte les **invariants** et le **modèle causal**.

---

## 1. Ce que fait l'application

Le récitateur récite. L'app écoute **en streaming**, suit le texte mot par mot,
et dit **immédiatement** si ce qui vient d'être dit est juste — vert, orange,
rouge. Elle doit dire vrai : un faux rouge décourage, un faux vert trahit sa
raison d'être.

Contrainte structurante : **juger sur un audio incomplet, sans revenir sur un
verdict déjà affiché.**

---

## 2. Les invariants — vrais par construction du code

Chacun est vérifié à la ligne indiquée. Ce sont les règles du système, pas des
observations.

| # | invariant | où c'est écrit |
|---|---|---|
| I1 | **L'ancre avance de `res.words.size`** — du nombre de mots que la DP a placés, jamais plus | `BufferedTranscriber.kt:1308` |
| I2 | **`frontiere = endState / 2`** — l'état où le Viterbi termine son meilleur chemin détermine le dernier mot jugeable | `ForcedAligner.kt:732` |
| I3 | **`covered = wi < frontierWordRel`** — un mot au-delà de la frontière n'est pas jugé fiable | `ForcedAligner.kt:946` |
| I4 | **Un mot est verrouillé si la passe est FINALE, ou s'il est CORRECT** | `recitation_provider.dart:3367` |
| I5 | **Borne dure de segment : 12 s** — un gel est forcé même sans pause | `BufferedTranscriber.kt:96` |
| I6 | **Portier RMS : 0,02** — sous ce seuil c'est du silence, au plus 0,3 s conservé par pause | `BufferedTranscriber.kt:70` |
| I7 | **Le Viterbi est monotone** — trois transitions, toutes vers l'avant. Il ne peut pas revenir sur une occurrence antérieure | `ForcedAligner.kt`, boucle DP |
| I8 | **Le `RescueBuffer` est en lecture seule** — il ne touche jamais à la purge du buffer principal | `RescueBuffer.kt` en-tête |
| I9 | **Le flux de travail ≠ le flux brut** — le portier retire des silences, les deux échelles de temps divergent | `RescueBuffer.kt` en-tête |

### Conséquence directe de I2 + I3, à connaître par cœur

`frontiere == ancre` signifie `endState ∈ {0,1}` : **le meilleur chemin du
Viterbi finit sur le premier état du treillis**. Le Viterbi a donc conclu que
« rester au blanc initial » explique mieux l'audio que « avancer dans la cible ».

Cela n'arrive que dans **un** cas : **l'audio du segment ne contient pas le mot
que l'ancre réclame.**

---

## 3. Les trois scores — ne jamais les confondre

| score | question à laquelle il répond | lecture |
|---|---|---|
| `free` | le modèle est-il **sûr de ce qu'il entend** ? | proche de 0 = certain |
| `forced` | ce qu'il entend **colle-t-il à la cible** ? | très négatif = ne colle pas |
| `gop` = `forced − free` | l'**écart** entre les deux | décide de la couleur |

**Règle de lecture** : `gop` effondré **avec** `free` proche de 0 signifie
**mauvaise POSITION**, jamais mauvaise prononciation. Cette confusion a été
commise plusieurs fois et fait chercher au mauvais endroit.

---

## 4. LE MODÈLE CAUSAL — la boucle de retard d'ancre

C'est le mécanisme central. Presque tous les symptômes observés en découlent.

```
       ┌──────────────────────────────────────────┐
       │                                          │
       ▼                                          │
  l'ancre est en retard sur l'audio               │
       │                                          │
       ▼                                          │
  le Viterbi ne trouve pas le mot réclamé          │
  → endState ≈ 0  →  frontiere == ancre   (I2)     │
       │                                          │
       ▼                                          │
  le gel final ne juge qu'UN mot           (I3)    │
       │                                          │
       ▼                                          │
  l'ancre avance de +1                    (I1)     │
  pendant que le récitateur dit 3-4 mots           │
       │                                          │
       ▼                                          │
  LE RETARD AUGMENTE  ─────────────────────────────┘
```

**Preuve mesurée** (session `v28-wordlevel-energie`, 2026-07-30) :

```
gels finaux : ancre=73 frontiere=73 mots=1
              ancre=74 frontiere=74 mots=1
              ancre=75 frontiere=75 mots=1   (× 6 de suite)

l'ancre réclamait : يَشْعُرُونَ        (mot 73, verset 12)
l'audio contenait : ٱللَّهُ يَسْتَهْزِئُ بِهِمْ وَيَمُدُّهُمْ فِى   (verset 15)
```

Trois versets d'avance. **12 gels finaux pour 79 mots parcourus — 21 mots
seulement jugés définitivement.**

### Ce que la boucle explique, sans hypothèse supplémentaire

| symptôme | explication par la boucle |
|---|---|
| `entendu=""` avec `gop` effondré et `free` normal | le mot n'est pas dans le segment ; la DP place des frames sur autre chose |
| mots verrouillés sur des **aperçus** | aucun gel final ne les couvre jamais (I4 : `lock = isFinal`) |
| troncatures (`صَـٰ` pour `صَـٰدِقِينَ`) | jugé sur aperçu, avant que la fin du mot n'arrive |
| secours impuissant (19 échecs sur 22) | il rejoue le **même** aligneur sur le **même** segment où le mot n'est pas |
| taux dispersé selon les passes | la boucle s'amorce ou non selon un aléa initial |

---

## 5. Faits établis, avec leur preuve

À ne pas re-mesurer sans raison.

| fait | preuve | date |
|---|---|---|
| Le décrochage brutal (bloc de ~57 mots abandonnés) **était** le resync | corrélation parfaite sur 5 sessions : 3-4 RESYNC → 51-56 mots perdus ; 0 RESYNC → 1 mot | 07-29 |
| `RESYNC_ACTIF = false` supprime ce décrochage | médiane 25,34 % → 11,78 %, 3 passes | 07-29 |
| Le contenu du texte n'est **pas** en cause | départ décalé de 36 mots : le bloc perdu suit le rang RELATIF, pas le passage | 07-29 |
| Le modèle `causal-v1` est le meilleur des 7 testés | 5/5 tranches correctes hors ligne | 07-29 |
| Le modèle **sait** lire les passages qui échouent | décodage hors ligne, fenêtre courte : texte exact | 07-29/30 |
| L'audio capté est bon | RMS 1500-3100 sans trou + validé à l'oreille | 07-29 |
| ~15 s d'audio capté ne sont jamais consommées | somme des clips 377,6 s contre 392,8 s de flux brut | 07-29 |
| Le secours ne rattrape presque jamais | 1 rattrapage sur 22 non-verts ; 10 `SANS RÉSULTAT`, 8 `SANS GAIN` | 07-30 |
| La majorité des mots n'est couverte par **aucun** gel final | 210 mots sur 297 dans une session | 07-30 |

---

## 6. RÉFUTÉ — ne pas y revenir sans cause nouvelle

Chacune de ces pistes a été explorée **et tranchée par la mesure**. Les
reprendre coûterait le même temps pour le même résultat.

| hypothèse | comment elle est tombée |
|---|---|
| Throttling thermique | passe à 6,93 % en `Thermal Status 3`, AP 60 °C |
| Qualité de l'audio | RMS constant + validation à l'oreille |
| Le modèle deux têtes / le tokenizer | le modèle une tête échoue identiquement ; `causal-v1` est le meilleur |
| Waqf absents du vocabulaire | les 3 signes autonomes y sont déjà (42 tokens en contiennent un) |
| Retard de validation comme cause | ~9 s identique sur passes propres ET décrochées |
| Anneau de secours trop petit (30 s) | élargi à 120 s : `IMPOSSIBLE` → 0, **décrochage inchangé** |
| Désynchronisation ancre/verrous | la passe **propre** en compte le PLUS (124 contre 22) |
| `conserve=0` (audio non gardé entre segments) | r = 0,67 sur 45 sessions, séparation nette — **et l'intervention l'a réfuté** : ramené de 89 % à 11 %, décrochage inchangé |
| Mots identiques dans le texte (`كَمَآ ءَامَنَ`) | le Viterbi est monotone (I7) et le resync donne priorité au premier ; et les mots concernés n'étaient pas dans la transcription du tout |
| GC / croissance du buffer d'affichage | ~90 ms/s de traitement, stable du début à la fin, 0-1 pic par session |
| Concurrence `feed()` | trois garde-fous en place : `_feedInFlight` (Dart), `busy` AtomicBoolean, `synchronized(lock)` |
| Alignement par gradient (arXiv 2607.06831) | exige un backward pass ; `onnxruntime-android` est en inférence seule, le modèle ne sort que `logprobs` |
| Chunkwise aligner comme cause du cas mesuré | le mot n'était pas scindé entre deux blocs, l'ancre était 60 mots en arrière |

**Leçon de méthode la plus chère** : `conserve=0` avait une corrélation parfaite
sur 14 sessions et un mécanisme plausible. **Seule l'intervention l'a réfuté.**
Une corrélation, même sans exception, ne vaut pas causalité.

---

## 7. Questions ouvertes

| question | ce qu'on sait déjà |
|---|---|
| **Pourquoi l'ancre prend-elle du retard au départ ?** | la boucle explique son *entretien*, pas son *amorçage* |
| Comment rattraper sans jeter de mots ? | v22 (recalage sur aperçu) a régressé 8,16 → 13,40 % ; le **rattrapage borné** est codé mais non mesuré |
| Suivre un récitateur qui **répète** | `findResyncOffset` ne cherche qu'en avant ; demande un protocole de test dédié (le banc rejoue un audio linéaire) |
| Verdicts sans preuve acoustique | 5 à 21 par session ; le garde-fou existe mais exige `free ≥ −0,08`, or les cas ont `free` entre −0,13 et −0,53 |
| Le désaccord waqf | le modèle émet `▁ۖ ▁ۗ ▁ۚ`, `splitExpectedWords` les filtre. Latent, sans effet démontré |

---

## 8. Règles de travail qui découlent de tout ceci

1. **Ne jamais corriger un symptôme dans une couche plus basse que son origine.**
   Une tolérance ajoutée au jugement pour compenser une perte en segmentation
   dégrade la fonction première et rend le vrai défaut invisible.
2. **Une corrélation ne prouve rien** — seule l'intervention tranche.
3. **Un gain de taux obtenu en dégradant « dire vrai », « suivre » ou
   « streaming » est un faux gain.** Hiérarchie dans
   `.claude/skills/superviseur-recette/SKILL.md`.
4. **Vérifier dans le code, jamais de mémoire** — le balayage greffe des versions
   différentes en permanence.
5. **Une passe, puis analyse.** Les 3 passes ne servent qu'à comparer des
   versions, pas à chercher un mécanisme.
6. **Le tableau mot par mot avant toute interprétation** :
   `python3 benchmark/tableau_session.py <dossier>/`.
