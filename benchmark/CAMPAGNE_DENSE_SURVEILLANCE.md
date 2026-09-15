# Relais de surveillance — campagne dense 100 × 20

> Mise à jour après audit PCM : les étiquettes du manifeste ne décrivent pas
> toutes le montage joué. Les 70 `omission_word` sont des troncatures ; le
> repli synthétique conserve le mot original. Consulter en priorité
> [l'extraction corrigée](campagne_100x20_dense30/MOTS_MAL_JUGES_CAMPAGNE_DENSE30_POUR_CODEX.md)
> et [le correctif des répétitions](CORRECTION_REPETITIONS_DENSE30.md).

Ce document est le point de reprise pour Claude ou un autre agent. Il fixe le
protocole, l'état réel de la dernière exécution et les contrôles à conserver.

## Objectif

La campagne vérifie le jugement V2 de l'application Android sur 100 relectures
déterministes de 20 versets. Chaque cas contient exactement six opérations
placées aux positions de verset `[2, 3, 6, 9, 10, 15]`, soit 30 % des unités de
verset. Les montages sont volontairement difficiles :

- `haraka_mutation` : mot d'un autre verset avec les mêmes lettres et des
  harakât différentes, quand le corpus disponible le permet ;
- `extra_letter` : mot coranique à distance d'une lettre de base ;
- `near_word_substitution` : remplacement par un mot coranique très proche ;
- `omission_word`, `omission_span` (deux mots contigus) et `omission_2words`
  (saut long de deux mots après l'ancre, trois index audio concernés) ;
- insertion, permutation, troncature et mélange dense.

Les groupes de positions rapprochées servent à exercer le décrochage. Dans
l'application, trois fenêtres `horsTexte` et un saut maximal de deux mots
déclenchent le chemin de correction et la demande de répétition. Le WAV
déterministe ne peut pas répondre à cette demande ; le runner capture alors le
journal, ferme proprement la session et classe le cas
`REQUIRES_HUMAN_REPETITION`.

## État de l'exécution terminée

- Campagne : `benchmark/campagne_100x20_dense30.py`.
- Résultat : 100/100 cas exécutés, 600 transformations enregistrées.
- Fin audio : 49 cas `AUDIO_FINISHED`.
- Répétition : 51 cas `REQUIRES_HUMAN_REPETITION`.
- Signaux natifs `DECROCHAGE` : 63 événements ; marqueurs de reprise/correction : 495.
- Clôture confirmée : 100/100 ; incohérence d'index ou de texte : 0.
- Extension de page : aucun marqueur `Enchaînement page` ou `Enchainement page`.
- Mode et APK : `valid_mode=true` partout, même APK SHA-256
  `a5ca72055dc0f72736ca0c990d3a3c285684eccd7f4abd761a733468ab3d6738`.
- Appareil : `R3CY20XW7TD`, package
  `com.corankarim.coran_karim.dev`.
- Manifest et WAV actifs : `benchmark/campagne_100x20_dense30/manifest.json` et
  `benchmark/campagne_100x20_dense30/wav/`.

Le journal final est parfois tronqué après le bouton retour. L'analyseur prend
donc `*.before_close.log` comme source de session lorsqu'il contient
`versets=20/` et `borner=true`. Cette règle est nécessaire pour ne pas perdre
les recettes absentes du journal final.

## Lancer ou reprendre

Depuis la racine du dépôt :

```powershell
python benchmark/campagne_100x20_dense30.py run --serial R3CY20XW7TD
```

Le runner utilise le mode recette `ecoute`, `normal=true`, `versets=20` et
`borner=true`. Le paramètre `borner=true` est obligatoire : il empêche
l'enchaînement automatique vers la page suivante. Le runner considère
`AUDIO_FINISHED` et `REQUIRES_HUMAN_REPETITION` comme terminaux et ne relance
pas le second lors d'une reprise.

Pendant l'exécution, laisser le processus actif. Pour surveiller depuis une
autre console :

```powershell
Get-Content benchmark/campagne_100x20_dense30/executions.jsonl -Tail 5
Get-ChildItem benchmark/campagne_100x20_dense30/logs | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

Un cas `REQUIRES_HUMAN_REPETITION` est un résultat attendu du protocole, pas un
plantage. Ne pas injecter un second WAV dans la même session et ne pas compter
les verdicts qui suivent la première ligne `DECROCHAGE` comme une nouvelle
décision sur l'erreur initiale.

## Analyse après la série

L'analyseur historique pointe par défaut vers l'ancien dossier. Pour analyser
la campagne dense, lancer temporairement l'analyseur avec son dossier de sortie
redirigé, ou copier son code en remplaçant `OUT` par
`benchmark/campagne_100x20_dense30`. La sortie attendue est :

- `analysis_details.json` : événements V2, ligne du premier décrochage,
  états avant/après demande de répétition ;
- `error_outcomes.csv` : une ligne par transformation ;
- `RESULTATS.md` : synthèse par famille.

Vérifications minimales avant de conclure :

1. chaque cas a `valid_mode=true`, `session_closed=true` et le même hash APK ;
2. aucune session ne contient `Enchaînement page` ou `Enchainement page` ;
3. les statuts sont uniquement `AUDIO_FINISHED` ou
   `REQUIRES_HUMAN_REPETITION` ;
4. les journaux sont lus avant et après la fermeture, mais les verdicts après
   le premier décrochage sont isolés ;
5. les insertions sont évaluées comme proxys, car elles n'ont pas de mot
   attendu unique ;
6. les résultats sont rapportés par famille et par distance : mot isolé,
   deux mots, haraka, lettre ajoutée, substitution proche et décrochage.

## Pistes à surveiller

Le point critique est la différence entre une faute réellement classée
(`omis`, `rouge`, `orange`, `deplace`) et une demande de répétition sans verdict
sur le mot ciblé. Une omission de verset ou de deux mots peut donc produire
`no_verdict` après `DECROCHAGE` : ce cas doit être compté comme « reprise
demandée avant classification », pas comme un mot correctement reconnu.

Les transformations synthétiques utilisent des frontières de segments de
l'API Quran Foundation. Elles servent à éprouver la logique de détection et ne
remplacent pas une validation phonétique humaine du tajwîd.
