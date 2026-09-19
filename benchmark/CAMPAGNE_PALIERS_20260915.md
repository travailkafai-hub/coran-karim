# Campagne en paliers du 2026-09-15 — ce que le vote et la tête 3 coûtent vraiment

Trois configurations, les **mêmes WAV**, le **même manifeste**, le **même
modèle**. Seul le code de l'app change. C'est la première mesure du projet qui
sépare le vote entre fenêtres de la tête 3 en décision — jusque-là les deux
étaient activés par le même marqueur, donc inséparables.

## La question, et pourquoi le banc a cette forme

Demande du 15/09 : « lancer les tests en mode réel avec les datasets qui
contiennent les erreurs », avec « plus de pourcentage de mots en erreur », sur
30 minutes. `campagne_100x20_dense30` n'injecte que **4,78 % des mots**
(600 opérations / 12 540 mots) : sur 30 minutes ça ne fait qu'une quarantaine
de fautes, trop peu pour juger.

Le taux demandé — 40 % — a été **mesuré inexploitable**, et c'est un résultat
en soi : à cette densité l'ancre décroche presque immédiatement (T801 décroche
au 3ᵉ mot, en 35 s sur 104). Un banc entièrement à 40 % aurait rendu huit fois
« décrochage », vrai et muet sur la détection. D'où les **paliers** : 40 %,
20 %, 10 % et des **témoins à 0 %**. Les témoins ne sont pas du remplissage —
sans mot correct, aucun faux signalement n'est mesurable.

`benchmark/campagne_paliers_20260915.py` — 8 cas, 31 min d'audio,
**195 erreurs sur 1 113 mots**, Hafs uniquement (il n'existe pas de source
Warsh dans ce banc).

| cas | palier | erreurs / mots |
|---|---|---|
| T801, T802 | 40 % | 27/68 · 63/159 |
| T803, T804 | 20 % | 32/159 · 44/222 |
| T805, T806 | 10 % | 22/222 · 7/105 |
| T807, T808 | 0 % témoin | 0 |

Familles : truncate 78, omission_word 31, insertion 31,
near_word_substitution 29, extra_letter 17, haraka_mutation 9. **Une seule
erreur par mot, jamais deux mots adjacents** — deux fautes collées rendraient
un rouge inattribuable.

⚠️ **Le repli « phonème dupliqué » de dense30 a été retiré ici.** À cette
densité il devenait la famille MAJORITAIRE (53 des 195 au premier tirage) :
on aurait mesuré la réaction à un **artefact de montage** et non à une faute.
Les cas sans mot voisin dans le corpus basculent sur une vraie troncature.

## Les trois configurations

| | vote | tête 3 en décision | APK SHA-256 |
|---|---|---|---|
| témoin `chantier-warsh` | non | non | `af305b40…` |
| vote seul | oui | non | `8d8755ef…` |
| vote + tête 3 | oui | oui | `ed0e46d8…` |

Séparer les deux a demandé un second marqueur de debug,
`files/tete3_decision_actif` (cf. `FastConformerCtcPlugin`) — sans lui, la tête
s'activait dès que le vote l'était. **Par défaut elle ne décide plus.**
Quand elle ne décide pas, le journal le dit avec la raison
(`active=false raison=marqueur_tete3_decision_actif_absent`) : sinon « elle n'a
pas jugé » et « elle n'était pas là » seraient indiscernables.

Le modèle est **identique** sur les deux branches : les seuls fichiers du pack
qui diffèrent entre `chantier-warsh` et `Astra` sont deux références
arithmétiques, de la documentation, pas des poids. La comparaison mesure donc
le code, et rien d'autre.

> ### ⚠️ CORRECTIF DU 15/09 AU SOIR — CES CHIFFRES SUR LA TÊTE 3 SONT CADUQUES
>
> Codex a trouvé, le même jour, que la tête 3 ne recevait **pas les bons
> jetons** : l'aligneur utilise un dictionnaire + découpage glouton, son
> entraînement utilisait SentencePiece BPE (`وَإِنْ` → `[393, 959]` attendu
> contre `[4, 615, 959]` fourni). Les 12 caractéristiques étaient donc
> calculées sur une segmentation fausse — cf.
> `CORRECTION_TOKENISATION_TETE3_JVM_20260915.md`.
>
> Tout ce qui suit concernant la **tête 3** a été mesuré avec ces entrées
> fausses, et notamment les quatre faux positifs cités en exemple, qui
> disparaissent une fois corrigés. Rejeu avec les bonnes entrées, sur 10 cas
> (103 mutations, 534 mots corrects) : la tête 3 détecte **autant** que le vote
> seul (69/103 dans les deux cas) et n'ajoute plus que 2 faux — elle est
> **neutre**, ni utile ni nuisible.
>
> Ce qui reste valable, parce que cela ne dépend pas d'elle : le coût du vote,
> le décrochage sur audio correct, et le décalage d'index de la fiche.
>
> Diagnostic complet et suite : `TACHE_CODEX_ALIGNEMENT_PLAFOND_20260915.md`.

## Résultats

rappel · faux signalements, dernier statut de chaque mot :

| palier | témoin | vote seul | vote + tête 3 |
|---|---|---|---|
| 40 % | 51 % · 13,2 % | 68 % · 27,7 % | 68 % · 29,2 % |
| 20 % | 51 % · 5,8 % | 55 % · 11,3 % | 57 % · 13,8 % |
| **10 %** | **39 % · 3,3 %** | **57 % · 9,3 %** | **57 % · 9,3 %** |
| 0 % témoin | — · 0,0 % | — · 15,5 % | — · 11,9 % |

| | fautes détectées | ratées | faux signalements | corrects OK |
|---|---|---|---|---|
| témoin | 52 | 55 | 25 | 434 |
| vote seul | 68 | 45 | 73 | 485 |
| vote + tête 3 | 69 | 44 | 76 | 482 |

### La tête 3 n'apporte rien

**+1 détection, +3 faux signalements.** Et au palier 10 % — le seul où les
trois configurations jugent exactement le même nombre de mots (237), donc le
seul strictement comparable — elle ne change **rien du tout** : 57 % · 9,3 %
avec et sans elle.

Une hypothèse intermédiaire a été **réfutée** par cette mesure, et il faut
qu'elle reste écrite : on l'avait d'abord accusée de porter les faux
signalements, parce que 18 de ses 21 interventions portent sur un mot correct.
C'est vrai mais sans effet : ces interventions tombent sur des mots que le
vote signalait **déjà**. Elle ne fait presque que confirmer, dans un sens comme
dans l'autre.

⇒ La tête 3 en décision ne se justifie pas. Elle reste `NON_CALIBREE`,
derrière son marqueur, éteinte par défaut.

### Le vote porte le gain ET le coût

+18 points de détection à 10 %, mais les faux signalements passent de 3,3 % à
9,3 %. Au total **16 fautes de plus détectées pour 48 faux signalements de
plus — une détection gagnée coûte trois accusations fausses.**

Il apporte en revanche une vraie robustesse : T803 (20 %) et T808 (0 %) vont
au bout avec le vote et **décrochent** sur le témoin.

⇒ Non activable tel quel. Le travail utile est de regarder QUELS mots corrects
il fait basculer, pas de régler un seuil à l'aveugle.

## Deux défauts trouvés, indépendants de tout ce qui précède

### 1. Un témoin SANS AUCUNE ERREUR décroche

T807 (0 % d'erreur) demande une répétition. Cause, dans le journal :

```
f=10 verif encoreEnCours : prochains=[كانت, مرصادا, للطغين, مابا, لبثين, فيها]
     entenduNorm="لب" -> false
f=10 DECROCHAGE : 3 fenetres hors texte, dernier entendu="لَّـٰبِ"
```

Le récitateur est dans le texte. La fenêtre a capté `لَّـٰبِ`, le **début** de
`لَّـٰبِثِينَ` (78:23) coupé au bord, et ce mot est dans les attendus. Le test
de `ChaineRecitation` exige que le mot attendu tienne **entier** dans
l'entendu ; un fragment de bord compte donc hors texte, et trois de suite
déclenchent la demande de répétition.

**Défaut ANTÉRIEUR au vote**, vérifié : dans `campagne_100x20_dense30` du
14/09, sans vote, **18 des 30 décrochages `horsTexte`** ont la même signature
— dont deux (T007, T017) au même mot avec exactement le même `لب`. Tous ne
sont pas des débuts : `ساء` contre `والسماء` est une **fin** de mot. La règle à
corriger est donc « accepter le fragment », pas « accepter le préfixe ».

Ce que le banc a apporté ici, c'est le **témoin à 0 %**. Sans lui, ce
décrochage se serait rangé sous « normal, il y avait des erreurs » — comme les
18 de la veille, passés inaperçus dans une campagne où chaque cas portait des
fautes.

### 2. La fiche « Réessayer ce mot » désigne le mauvais mot

Sur trois captures d'affilée, l'app fait redire un mot qui n'est pas celui
signalé : `أَحْسَنُ` à la place de `ٱلْمَوْتَ` (67:2), `خَاسِئًا` à la place de
`كَرَّتَيْنِ` (67:4), et sur 67:5 un mot **du verset suivant**. Converti en
index global, l'écart vaut **exactement 4 à chaque fois** — la longueur de la
basmala.

`tajwid_help_sheet.dart` compose la phrase comme
`[...contexte, focusWord, apres]`, où le contexte et le mot suivant sont lus
autour de `localWordIndex` alors que `focusWord` vient de `st.words[wordIndex]`.
Les deux divergent.

**Le jugement n'est PAS touché, et c'est vérifié** : pour chaque verdict des
campagnes, le mot écrit dans le journal a été comparé à celui attendu au même
index du manifeste — **2 282 jugements, 0 discordance**. Les chiffres de ce
document tiennent.

Restent suspects, non vérifiés : le souffleur (`_promptCurrentWord`) et
l'archivage des mots non verts (`_archiverMotNonVert`), qui utilisent les mêmes
helpers. La relecture Coach lit avec la fonction qui a écrit, le décalage s'y
compense probablement.

## Ce que ce banc ne peut pas dire

- **Montage synthétique** aux frontières de l'API. À 40 % c'est un collage tous
  les deux mots et demi, la prosodie n'existe plus : un signalement peut venir
  de l'artefact, pas de la faute. Les paliers bas sont les seuls interprétables.
- **Le palier 0 % du témoin porte sur 21 mots jugés** contre 84 pour les deux
  autres — il avait décroché tôt. Son 0,0 % n'est pas un chiffre solide.
- **Hafs uniquement.** La tête 3 Warsh est branchée et vérifiée (empreinte,
  logit de référence, parité sur vraie récitation) mais **jamais mesurée sur
  téléphone** : aucune source Warsh dans ce banc.
- Aucun seuil calibré n'a été activé. Les seuils reçus de PC A le 15/09
  (Hafs −2,222, Warsh +3,099) sont calibrés sur des **mots isolés** d'un cache
  d'entraînement, pas sur la règle multi-fenêtres qui décide réellement.

## Rejouer

```powershell
python -X utf8 benchmark/campagne_paliers_20260915.py prepare   # WAV + manifeste
python -X utf8 benchmark/campagne_paliers_20260915.py run --serial <serie>
python -X utf8 benchmark/run_vote_seul_paliers.py --serial <serie>
python -X utf8 benchmark/run_temoin_paliers_chantier_warsh.py --serial <serie>
```

Marqueurs, via `adb shell run-as com.corankarim.coran_karim.dev` :
`files/vote_fenetres_actif` active le vote, `files/tete3_decision_actif` la
tête 3. **Aucun script du dépôt ne les pose** — c'est manuel, et c'est
précisément pourquoi c'est écrit ici.

Chaque configuration exige un dossier de sortie **neuf** : le runner refuse de
mélanger deux empreintes d'APK dans un même `environment.json`, et ce refus est
voulu.

Preuves : `campagne_paliers_20260915/`,
`campagne_paliers_vote_seul_20260915/`, `campagne_paliers_temoin_20260915/`
(manifeste, `executions.jsonl`, `environment.json`, logs). Les WAV sont
régénérables par `prepare` depuis le cache de `campagne_100x20`.
