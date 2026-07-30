# La chaîne de récitation, fonction par fonction

Du micro jusqu'à la couleur affichée. Écrit le 2026-07-30 **en lisant le code**,
pas de mémoire — chaque fonction citée existe, avec son fichier et sa ligne.

> **À quoi sert cette chaîne** : le récitateur récite, l'app écoute **en
> streaming**, suit le texte mot par mot, et dit **immédiatement** si ce qui
> vient d'être dit est juste. Vert = correct, orange = douteux, rouge = faux.

Le flux traverse **six couches**. Une erreur naît toujours dans une couche
précise et se *voit* souvent dans une couche plus basse — d'où l'importance de
cette carte avant tout correctif.

```
① MICRO (Dart)  →  ② TRANSPORT  →  ③ BUFFER (Kotlin)  →  ④ ASR
                                            ↓                ↓
                                    ⑥ AFFICHAGE  ←  ⑤ ALIGNEMENT + JUGEMENT
```

---

## ① Capture micro — `app/lib/services/recitation_verifier.dart`

| fonction | ligne | rôle |
|---|---|---|
| `start(expectedWords, …)` | 613 | point d'entrée d'une session. Sérialisé pour qu'on ne démarre jamais deux captures |
| `_startLocked(…)` | 619 | démarrage réel, sous verrou |
| `_startStreamingCapture(…)` | 681 | ouvre le micro et abonne le flux PCM. Écrit le marqueur `capture ouverte` que le banc attend |
| `_closeStaleContinuousCapture()` | 826 | ferme une capture précédente restée ouverte — sinon deux flux se superposent |
| `stop()` | 1082 | arrête et **vide la trace fine** (`_flushTraces`) : sans ce chemin, la trace en mémoire est perdue |
| `stopIfCurrentSession(gen)` | 1118 | n'arrête que si la session est bien celle attendue (protège des arrêts croisés) |
| `_cutAndRestart()` | 991 | coupe et relance la capture (changement de verset, correction) |

**Ce qui peut casser ici** : un micro qui ne s'ouvre pas (le banc meurt sur
`le micro ne s'est jamais ouvert`), ou une capture fantôme qui double le flux.

## ② Transport Dart → Kotlin

| fonction | fichier:ligne | rôle |
|---|---|---|
| `_pumpFeed()` | recitation_verifier.dart:908 | **sérialise** les envois : garde `_feedInFlight`, envoie tout le PCM en attente en UN appel, se rappelle à la fin. C'est ce qui garantit qu'il n'y a jamais deux `feed()` concurrents |
| `_processContinuousChunk(bytes, n)` | :923 | l'appel effectif, chronométré (`feedEntree`/`feedSortie` dans la trace) |
| `feedBufferedAudio(pcm16)` | fastconformer_verifier.dart:539 | passe le PCM au natif par MethodChannel |
| `"feedBufferedAudio"` | FastConformerCtcPlugin.kt:273 | côté Kotlin : **redécoupe en blocs de 80 ms** avant d'appeler `feed()`. Dart groupe pour réduire les allers-retours, mais le portier et la détection de pause décident **par bloc** — sans ce redécoupage, la segmentation changerait |

## ③ Buffer et segmentation — `BufferedTranscriber.kt`

Le cœur, et la couche où naissent la plupart des défauts mesurés.

### Entrée de l'audio

| fonction | ligne | rôle |
|---|---|---|
| `feed(newSamples, scope)` | 1646 | **le point d'entrée de tout**. Calcule le RMS du bloc, applique le portier de silence, accumule dans `samples`, décide s'il faut re-transcrire ou figer, lance l'inférence en coroutine |
| `rmsAt(buf, from, len)` | 1433 | énergie d'une tranche — sert au portier et à la recherche de coupe |
| `reset()` | 1617 | remet le buffer à zéro (nouvelle récitation) |

**Le portier RMS** (dans `feed`) : un bloc sous `SILENCE_RMS_THRESHOLD` (0,02)
est du silence. Il en garde au plus `MAX_SILENCE_SAMPLES` (0,3 s) par pause et
**jette le reste** — c'est pourquoi le flux brut et le flux de travail n'ont pas
la même échelle de temps. Confondre les deux a déjà faussé un banc entier.

### Décision de coupe

| fonction | ligne | rôle |
|---|---|---|
| `findCutOffset(buf, target, minKeep)` | 1484 | **où couper**. Cherche un micro-silence près de la cible ; borné par `CUT_SEARCH_RADIUS_SECONDS` (0,8 s) pour ne pas dépendre de l'ordonnancement |
| `targetSeconds()` | 1614 | la cible courante (aujourd'hui = la borne dure, 12 s) |
| `setCommitSilenceMs(ms)` | 1423 | seuil de pause franche qui déclenche un gel |

Trois façons de figer un segment : **pause franche** (≥ 450 ms de silence),
**borne dure** (`MAX_SEGMENT_SECONDS` = 12 s, même sans pause), ou **coupe sur
micro-silence**. La borne dure est le mécanisme qui coupe en plein mot — mais
sans elle, le buffer grossit sans fin et la normalisation `per_feature` dérive.

### Cible d'alignement

| fonction | ligne | rôle |
|---|---|---|
| `setAlignmentTarget(tokens, anchor, …)` | 422 | reçoit de Dart le texte attendu, tokenisé par mot. **Remet à zéro** tous les états (ancre, différé, horodatages, état chunkwise) |
| `extendAlignmentTarget(…)` | 467 | allonge la cible sans tout réinitialiser (verset suivant) |
| `setAlignmentAnchor(anchor)` | 454 | déplacement explicite de l'ancre, demandé par Dart (correction) |
| `setNeverBlockAnchor(v)` | 449 | mode référence : l'ancre ne cale jamais, elle avance de +1 sur échec |

### Le second buffer (secours)

| fonction | fichier:ligne | rôle |
|---|---|---|
| `RescueBuffer.append(samples)` | RescueBuffer.kt:51 | anneau **en lecture seule** de `RESCUE_RING_SECONDS`. Reçoit une copie de tout l'audio, jamais purgé par le jugement |
| `RescueBuffer.extract(from, to)` | :81 | extrait une fenêtre en indices absolus, ou `null` si elle est sortie de l'anneau. **Refuse une fenêtre tronquée** : un secours sur audio partiel reproduirait le défaut qu'il corrige |
| `horodater(words, origin, spf)` | BufferedTranscriber:533 | note la position absolue des mots **sûrs**. C'est ce registre qui borne les fenêtres de secours |
| `fenetreDeRecherche(wordIndex)` | :556 | où chercher un mot : bornée par ses **voisins sûrs**, pas par son propre placement (qui vient d'échouer) |
| `cibleAvecVoisins(zone, idx, toks)` | :617 | la cible du secours = tous les mots que la fenêtre couvre. Aligner un mot **seul** produisait 7 faux positifs sur 33 |
| `cibleEtendue(idx, toks, n)` | :599 | variante repartant de N mots validés en amont (en sommeil) |
| `rescueWord(idx, tokens, from, to, …)` | :658 | **le secours lui-même** : extrait l'audio, rejoue le vrai aligneur, rend un verdict |
| `secoursMeilleur(orig, rj)` | :629 | accepte le verdict de secours **seulement s'il améliore**. Un mot déjà vert ne peut pas devenir rouge |

**Quatre verdicts possibles**, et il faut les distinguer : `RATTRAPE`,
`SANS GAIN` (a produit, pas mieux), `SANS RESULTAT` (n'a rien produit),
`IMPOSSIBLE` (fenêtre hors anneau).

### Rattrapage d'ancre

| fonction | ligne | rôle |
|---|---|---|
| `findResyncOffset(logprobs, tokens, anchor)` | 763 | **où en est vraiment le récitateur** : apparie le décodage libre au texte attendu. Ne cherche qu'**en avant** (`bestOff > anchor`) — un récitateur qui *répète* ne peut donc pas être suivi |
| `indexOfSub(list, sub, from)` | 858 | recherche de sous-séquence, utilitaire du précédent |

## ④ Inférence ASR — `FastConformerCtc.kt` + `MelSpectrogram.kt`

| fonction | fichier:ligne | rôle |
|---|---|---|
| `MelSpectrogram.compute(pcm)` | :187 | PCM → mel-spectrogramme (80 bandes). **C'est l'app qui calcule le mel**, pas le modèle : l'export ONNX doit donc exposer `audio_signal`, jamais `raw_audio` |
| `frameLogMel(padded, start)` | :154 | une frame de mel |
| `fft(input)` | :107 | FFT maison |
| `buildMelFilterbank()` | :77 | banc de filtres mel (slaney) |
| `computeAll(pcm)` | FastConformerCtc:125 | **l'inférence ONNX** : mel → `logprobs` (+ tête tajwid si présente) |
| `computeLogProbs(pcm)` | :115 | idem, lettres seulement |
| `greedyDecode(logprobs, …)` | :172 | décodage **libre** : ce que le modèle entend, sans contrainte de cible |
| `decodeTajwid(tajwid)` | :91 | règles tajwid détectées (2ᵉ tête) |
| `loadVocab(path)` | :72 | vocabulaire (1024 tokens) |

## ⑤ Alignement forcé — `ForcedAligner.kt`

C'est ici que le texte attendu rencontre l'audio.

| fonction | ligne | rôle |
|---|---|---|
| `align(logprobs, wordTokens, anchor, …)` | 491 | **le cœur**. Construit le treillis CTC, fait tourner le Viterbi, attribue chaque frame à un token, en déduit les bornes de chaque mot et ses scores |
| `stripRuleSymbolMass(logprobs)` | 113 | retire la masse des symboles de règles avant scoring |
| `ctcMinFrames(toks)` | 466 | minimum **physique** de frames pour un mot (n tokens ⇒ ≥ n frames). Sert à **condamner** |
| `plausibleMinFrames(wi, toks, ref)` | 478 | minimum **typique**, référence quran.com incluse. Sert à **excuser** — ne jamais les interchanger |
| `greedyDecodeRange(logprobs, from, to)` | 1338 | texte réellement entendu **sur les frames du mot** → c'est le champ `entendu` |
| `tokenizeWord(word)` | 1383 | mot → tokens, via le dictionnaire précalculé |
| `tokenizeWordGreedy(word)` | 1411 | repli glouton pour les mots hors dictionnaire |
| `tokensToText(t)` | 1319 | tokens → texte (sert à détecter les troncatures) |
| `coveredWordsFromFree(free, tokens)` | 1263 | combien de mots attendus le décodage libre confirme, dans l'ordre |
| `wordSpansFromFree(free, tokens)` | 1292 | leurs plages de frames |
| `decodeFreeSpan(free, span)` | 1327 | texte d'une plage du décodage libre |
| `ctcForwardNll(…)` | 1187 | rescoring NLL d'une variante (diagnostic, second treillis — **ne pas confondre** avec celui d'`align`) |

### Les trois scores — ils répondent à trois questions différentes

| score | question | lecture |
|---|---|---|
| `free` | le modèle est-il **sûr de ce qu'il entend** ? | proche de 0 = certain |
| `forced` | ce qu'il entend **colle-t-il à la cible** ? | très négatif = ne colle pas |
| `gop` = `forced − free` | **l'écart** entre les deux | c'est lui qui décide de la couleur |

**Un `gop` effondré avec un `free` proche de 0 signifie *mauvaise position*, pas
*mauvaise prononciation*.** Confondre les deux fait chercher au mauvais endroit —
erreur commise plusieurs fois.

### Le pont Kotlin → Dart

| fonction | ligne | rôle |
|---|---|---|
| `runAlignment(logprobs, isFinal, …)` | BufferedTranscriber:900 | orchestre : appelle `align`, déclenche le secours, gère l'ancre, construit le message pour Dart |
| `energieParFrame(audio, nFrames)` | :885 | énergie RMS par frame, pour la pénalité de silence de l'aligneur |
| `alignmentPayload()` | :868 | le dernier résultat, lu par Dart |

## ⑥ Jugement et affichage — `recitation_provider.dart`

| fonction | ligne | rôle |
|---|---|---|
| `_onAligned(payload)` | 2758 | **reçoit l'alignement et décide de la couleur**. Applique les seuils, écrit les lignes `[GOP]`, verrouille ou non |
| `_judge(words, i, status, …)` | 2213 | pose le verdict d'un mot |
| `applyJudgementOptions(opts)` | 238 | seuils du préréglage actif (`correct` = −0,45, `unclear` = −1,60…) |
| `applyGopWordBaseline(baseline)` | 304 | référence GOP par mot, propre à la voix de l'utilisateur |
| `applyRuleReliability(…)` | 292 | fiabilité par règle tajwid |
| `classifyError(wordIndex)` | 469 | nature de l'erreur, pour la révision |
| `_applyDiagnosticCapture()` | 2006 | capture des WAV de diagnostic |

**Le verrou** (`lock`) est la règle la plus importante de cette couche :

```dart
final lock = p.isFinal || (judged == WordStatus.correct && !deferredTajwid);
```

Un mot est verrouillé si la passe est **finale**, ou s'il est **correct**. Donc
un mot jugé correct sur un simple **aperçu** est figé immédiatement — voulu, pour
qu'un mot juste ne reste pas orange. Conséquence mesurée : la majorité des mots
sont verrouillés sur des aperçus, donc sur un audio incomplet.

---

## Où naissent les défauts — table de correspondance

| symptôme observé | couche où il NAÎT |
|---|---|
| mot tronqué (`صَـٰ` pour `صَـٰدِقِينَ`) | ③ coupe de segment, ou verrou sur aperçu ⑥ |
| `entendu` vide, `gop` effondré, `free` normal | ⑤ position de l'ancre, pas la prononciation |
| mot jamais placé | ③ son audio n'est pas dans le segment |
| bloc de mots abandonnés | ③ rattrapage d'ancre (`findResyncOffset`) |
| texte charabia sur segment long | ④ dérive de normalisation `per_feature` |
| audio capté mais jamais consommé | ③ portier RMS ou purge |

**Règle qui découle de cette carte** : ne jamais corriger un symptôme dans une
couche plus basse que celle où il naît. Une tolérance ajoutée au jugement ⑥ pour
compenser une perte d'information en ③ dégrade la fonction première de l'app et
rend le vrai défaut invisible dans les logs suivants.
