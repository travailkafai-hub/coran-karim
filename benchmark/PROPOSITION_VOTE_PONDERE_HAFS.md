# Vote pondéré entre lectures d'un mot — proposition pour Hafs

Demande du 15 septembre 2026 : deux lectures A solides doivent pouvoir
l'emporter sur une lecture B isolée, même si B est le texte attendu. Une
lecture B fiable doit aussi pouvoir l'emporter sur des lectures A/C incertaines.

## Ce qui existe et ce qui manque

`Decideur.statuts` contient déjà un consensus : les `k` dernières observations
votantes, de fenêtres distinctes, doivent avoir la même couleur. C'est un
consensus de couleurs, pas un vote entre les textes entendus.

Trois chemins doivent être examinés ensemble :

- `nette` peut figer le vert avec une seule attestation et un GOP vert, sans
  tenir compte de la marge de confusion ni des votes contradictoires ;
- le secours avant `Omis` peut aussi figer un vert sur une attestation ;
- `meilleurProvisoire` conserve la meilleure couleur antérieure. Supprimer
  seulement `nette` laisserait donc possible un vert provisoire persistant.

Précision : un rouge **déjà définitif** n'est pas écrasé par `nette` : la boucle
traite les verdicts figés avant ce raccourci. Le problème décrit porte sur les
preuves contradictoires qui n'ont pas encore verrouillé un verdict négatif.

La correction précédente isole les tentatives après une reprise explicite.
Elle ne résout pas le désaccord de plusieurs découpages d'une même lecture.

## Exemple réel à reprendre

Dans [T005, journal avant fermeture](campagne_100x20_dense30/logs/T005-C100-ce9bd5464727407dafc9264f00af7ccb.before_close.log), mot 115 :

| Ligne | Attendu | Entendu associé à la trace | Statut de l'app | GOP | Nombre d'observations |
|---:|---|---|---|---:|---:|
| 6607 | أَصْحَـٰبِ | أَصْحَـٰبَ | provisoire:rouge | -2,09 | 1 |
| 6827 | أَصْحَـٰبِ | أَصْحَـٰبِ | definitif:vert | 0,00 | 3 |

La transition est vérifiée. Ces deux événements ne donnent pas le détail
des trois observations : ils ne prouvent pas « deux votes A contre un B ».
Le pont choisit une observation pour accompagner le statut ; ce n'est pas
nécessairement la preuve qui a déclenché le verdict. T013/mot 50 illustre
cette limite avec un vert accompagné d'un GOP négatif inchangé.

Ne pas annoncer un gain en simulant le décideur uniquement sur ces changements
de statut : il manque les observations sans changement et leur provenance.

## Proposition de décision

1. **Regrouper la même prononciation.** Même session, tentative, index de mot
   et occurrence audio. Une vraie répétition ne vote pas contre la précédente.
   Les bornes et le suivi doivent identifier l'occurrence, pas le seul texte.
2. **Écarter les preuves inexploitables.** Mot sur l'audio du voisin, silence,
   fragment de bord ou intervalle incompatible. Conserver le motif d'exclusion.
   Une frame CTC unique n'est pas automatiquement une preuve incomplète.
   « Complet » qualifie ici la capture du son et de son contexte, jamais
   l'obligation d'avoir prononcé toutes les lettres attendues : une vraie
   troncature prononcée avec un intervalle audio bien observé doit rester
   une candidate à la détection.
3. **Comparer les hypothèses entendues.** Garder lettres et harakat distinctes.
   Ne donner aucun bonus à une hypothèse parce qu'elle est le texte attendu.
4. **Pondérer par une fiabilité mesurée.** Additionner les poids de chaque
   hypothèse. Une seule fenêtre réanalysée n'obtient pas plusieurs voix.
   Les fenêtres distinctes qui se chevauchent restent corrélées : la part des
   poids gagnants n'est pas une probabilité de correction.
5. **Garder le résultat révisable pendant l'observation.** La meilleure lecture
   peut changer quand les fenêtres suivantes arrivent. Définir un critère de
   clôture lié à l'audio et au contexte droit disponible, avec délai maximal
   mesuré. Ne pas figer sur le premier vert ni attendre dix fenêtres par défaut.
6. **Séparer lecture retenue et jugement.** Une fois A/B départagés, appliquer
   les règles de prononciation/position. Si les preuves restent insuffisantes,
   garder le doute ou demander la reprise prévue par l'app. Une majorité seule
   ne démontre pas la justesse phonétique.

Le seuil de poids suffisant, la marge entre gagnant et opposition, le nombre
de confirmations et le délai de clôture doivent être choisis sur calibration,
puis évalués sur des passages distincts. Le prototype ne fixe pas ces seuils.

## Comment définir « le modèle est sûr »

`gop` compare l'attendu à un score libre : il ne mesure pas directement la
fiabilité du texte A/B reconnu. `free` moyenne des maxima par frame, et peut
être proche de zéro sur des blancs CTC ou une mauvaise position. `atteste`
constate un accord avec l'attendu ; ce n'est pas une confiance calibrée.

Évaluer une confiance sur les tokens réellement émis : distribution des
probabilités, entropie, écart aux alternatives et qualité de l'intervalle.
Traiter explicitement les blancs CTC et agréger au niveau du mot. NVIDIA
documente ces méthodes ainsi que la surconfiance des probabilités brutes :
[confiance ASR par entropie](https://developer.nvidia.com/blog/entropy-based-methods-for-word-level-asr-confidence-estimation/).
Cela fournit des candidats à mesurer, pas des seuils déjà valides sur ce Hafs.

Pour A contre B, comparer également leurs scores CTC sur les **mêmes frames**.
Un score élevé de l'attendu, calculé sur un autre découpage, ne départage pas
à lui seul les hypothèses. Les lectures produites par le même encodeur ne sont
pas plusieurs modèles indépendants.

La tête 3 pose une autre question : écart acoustique à l'attendu. Elle pourra
apporter un signal supplémentaire après vérification des caractéristiques,
parité et calibration avec le paquet courant. Ne pas transformer son logit
non calibré en poids de fiabilité d'une transcription.

## Prototype fourni

[vote_hypotheses_hafs.py](vote_hypotheses_hafs.py) implémente la somme des poids,
la séparation des occurrences/tentatives, les exclusions et la déduplication
des fenêtres. Il ne lit pas le texte attendu pour décider du gagnant.

Il retourne une hypothèse provisoire ou à évaluer, jamais un statut V2. La
majorité exigée est supérieure au poids de **toute** l'opposition ; une simple
première place sans majorité reste indécise. Un poids absent reste explicite.
Cette règle est une proposition du prototype, pas un optimum mesuré.

Exemples avec **poids fictifs**, destinés à expliquer le mécanisme :

| Lectures | Sommes | Résultat du vote |
|---|---|---|
| A:0,8 ; A:0,8 ; B:0,8 | A:1,6 ; B:0,8 | A |
| A:0,2 ; B:0,9 ; C:0,1 | A:0,2 ; B:0,9 ; C:0,1 | B |
| A:0,8 ; B:0,8 | égalité | indécis |
| B:0,9, fenêtres encore attendues | B en tête | provisoire |

```powershell
python -X utf8 benchmark/vote_hypotheses_hafs.py --demo
python -X utf8 -m unittest discover -s benchmark -p test_vote_hypotheses_hafs.py -v
```

Avec `--entree fichier.json`, fournir `riwaya: "hafs"`, `cible` contenant
`tentative`, `mot`, `prononciation`, puis `lecture_terminee` et `observations`
au format de la dataclass `Observation`. Le banc fournit les identifiants
d'occurrence et les poids ; le prototype ne les extrait pas de l'audio.
Le champ `intervalle_complet` concerne la couverture audio, pas la conformité
au texte attendu.

## Travail pour Claude et critères d'acceptation

Avant toute activation dans l'app, collecter chaque observation, même sans
changement de statut : identifiants, bornes, transcription, preuves de qualité,
scores de confiance, motif de décision, votes inclus/exclus et source de la
calibration. Ne pas reconstruire les voix à partir des seules couleurs finales.

Comparer sur Hafs, à WAV identiques, trois variantes : décision actuelle ;
vote sans pondération après exclusions ; vote pondéré. Le protocole précédent
reste applicable : [campagne, témoins et reprises](TACHE_CLAUDE_CALIBRATION_TETE3_ET_REPETITIONS.md).

Les tests doivent couvrir les deux exemples utilisateur, leur ordre inversé,
une première fenêtre verte suivie d'erreurs solides, les fragments trompeurs,
les doublons de fenêtres, la fin de verset avec peu d'observations, les vraies
reprises, les permutations et les harakat. Vérifier séparément le secours
d'omission et la couleur provisoire pour empêcher un contournement du vote.

Mesurer rappel des erreurs, faux signalements sur récitations correctes,
indécisions/reprises, couverture et délai. Les régressions possibles sont une
majorité de fragments trompeurs, un modèle sûr de sa mauvaise lecture, davantage
d'attente ou de reprises et une mauvaise séparation des répétitions. Les
témoins propres sont indispensables pour voir ces coûts.

Le prototype démontre le comportement de l'agrégation sur les exemples. Il
ne démontre aucun gain de détection et ne modifie pas les couleurs de l'app.
