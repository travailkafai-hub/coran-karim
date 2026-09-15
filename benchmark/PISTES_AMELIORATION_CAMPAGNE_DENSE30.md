# Pistes d'amélioration déduites de la campagne dense 30 %

> Analyse historique, rectifiée depuis par la comparaison des 100 WAV aux
> sources. Les taux ci-dessous utilisent les anciennes étiquettes : les 70
> `omission_word` sont des troncatures, et 21 replis contiennent le mot original
> intégral. Un `no_verdict` peut concerner un montage non encore lu au moment
> de l'arrêt pour reprise ; il ne prouve pas une faute non détectée. Voir
> [le rapport vérifié](campagne_100x20_dense30/MOTS_MAL_JUGES_CAMPAGNE_DENSE30_POUR_CODEX.md)
> et [la correction des répétitions](CORRECTION_REPETITIONS_DENSE30.md)
> avant d'utiliser ces pistes pour régler le détecteur.

Cette note sépare les observations mesurées des décisions de produit à tester.
Les chiffres viennent de [RESULTATS.md](campagne_100x20_dense30/RESULTATS.md),
des 600 lignes de [error_outcomes.csv](campagne_100x20_dense30/error_outcomes.csv)
et des journaux détaillés dans [analysis_details.json](campagne_100x20_dense30/analysis_details.json).

## Ce que la campagne montre

- 100/100 sessions sont fermées proprement ; 49 arrivent à la fin audio et 51
  demandent une répétition humaine.
- 63 signaux natifs `DECROCHAGE` et 495 marqueurs de correction/reprise ont été
  journalisés. Aucun enchaînement vers une page suivante n'a été observé.
- Sur les 600 transformations, 232 ont au moins un état négatif, 154 sont
  entièrement verts définitifs et 194 contiennent au moins un `no_verdict`.
  Ces trois colonnes décrivent le comportement observé ; elles ne constituent
  pas une précision statistique indépendante, car une erreur peut désaligner
  les mots suivants.

## Priorité 1 — rendre l'omission visible avant la répétition

Les omissions longues sont le point le plus faible :

| Famille | Transformations | Avec `no_verdict` | Au moins un négatif |
|---|---:|---:|---:|
| `omission_2words` | 60 | 58 (96,7 %) | 2 (3,3 %) |
| `omission_span` | 68 | 37 (54,4 %) | 31 (45,6 %) |
| `omission_word` | 70 | 12 (17,1 %) | 28 (40,0 %) |

Quand le décrochage arrive, l'interface demande bien la reprise, mais la faute
initiale reste souvent sans verdict. Ajouter un événement intermédiaire tel que
`OMISSION_PROBABLE` ou `REPRISE_REQUISE` permettrait de colorer les mots sautés
en attente, d'afficher l'ancre de reprise et de distinguer clairement :

1. faute classée (`omis`, `rouge`, `orange`, `deplace`) ;
2. omission probable en attente de répétition ;
3. mot non encore jugé.

Le second essai devrait remplacer l'état d'attente par un verdict confirmé,
sans compter les événements arrivés après la première demande comme une nouvelle
décision sur l'audio original.

## Priorité 2 — ne plus transformer une confusion proche en vert définitif

Les erreurs proches sont précisément celles demandées pour challenger le
programme :

| Famille | Transformations | Négatif | Tout vert définitif | `no_verdict` |
|---|---:|---:|---:|---:|
| `haraka_mutation` | 49 | 19 (38,8 %) | 16 (32,7 %) | 10 (20,4 %) |
| `near_word_substitution` | 66 | 32 (48,5 %) | 11 (16,7 %) | 21 (31,8 %) |
| `extra_letter` | 65 | 37 (56,9 %) | 12 (18,5 %) | 14 (21,5 %) |

La localisation normalisée reste utile pour retrouver la position, mais elle ne
doit pas verrouiller un mot comme juste : le commentaire du code indique déjà
« normaliser pour trouver, exact pour confirmer ». Conserver séparément le
texte exact, la base de lettres et les harakât, puis exposer une confiance
`provisoire` tant que l'alignement exact n'est pas confirmé, réduirait les verts
silencieux. Références :
[Decodage.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/Decodage.kt:189),
[Localisateur.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/Localisateur.kt:107),
[ConfusableVariants.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ConfusableVariants.kt:1).

Les mutations de harakât restent particulièrement ambiguës : une acceptation
verte ne doit pas être présentée comme une preuve que la haraka a été détectée.

## Priorité 3 — conserver la preuve du décrochage et régler sa fenêtre

Le moteur utilise actuellement trois fenêtres `horsTexte` et un saut maximal de
deux mots ([ChaineRecitation.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/ChaineRecitation.kt:742)).
La campagne produit des reprises sur 51 cas, alors que plusieurs cas longs
atteignent la fin audio sans demande. Cela indique une forte dépendance au
contexte et à la durée du passage.

Avant de modifier les seuils, journaliser pour chaque fenêtre : nombre de mots
attendus, index de l'ancre, durée de silence, distance du saut et confiance du
modèle. Tester ensuite une fenêtre adaptative, avec une borne stricte de deux
mots pour le message utilisateur. Le seuil d'omission postérieur est de trois
mots ([Decideur.kt](../app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/Decideur.kt:97)) : il doit être mesuré séparément du seuil de
décrochage afin de ne pas les confondre dans l'IHM.

## Priorité 4 — utiliser la permutation comme signal d'ordre

La permutation est la famille la mieux signalée : 51/64 transformations ont un
état négatif et seulement 2/64 sont entièrement vertes. Garder l'information
de séquence dans le verdict (« mot attendu déplacé ») aidera davantage que de
la réduire à un simple rouge. Il faut toutefois vérifier les reprises légitimes
et les mots répétés avant de verrouiller `deplace`.

## Priorité 5 — traiter l'insertion comme désalignement, pas comme réussite

Les insertions donnent 3/70 signaux négatifs, 40/70 transformations entièrement
vertes et 19/70 sans verdict. Ce résultat ne mesure pas la détection de
l'insertion : il n'existe pas de mot attendu correspondant au mot ajouté. Le
runner les marque donc explicitement comme `insertion_proxy_only`. Dans l'app,
afficher « texte supplémentaire / alignement perturbé » avec une confiance
provisoire serait plus honnête qu'un vert définitif sur le mot voisin.

## Robustesse de la surveillance

- Utiliser le snapshot `before_close.log` quand il contient la recette
  `versets=20/` et `borner=true` ; la fermeture peut tronquer ou rebaser le
  journal final.
- Considérer `AUDIO_FINISHED` et `REQUIRES_HUMAN_REPETITION` comme deux statuts
  terminaux ; le runner ne doit pas relancer le second lors d'une reprise.
- Vérifier à chaque série le hash APK, le manifeste, `valid_mode`, la clôture
  et l'absence de marqueur d'enchaînement de page.
- Conserver les captures et les lignes après reprise, mais les exclure des
  taux de détection de l'erreur originale.

## Limites

Les erreurs sont des montages déterministes aux frontières des segments API,
avec des voix Hafs et deux récitants. Elles contournent le microphone réel et
ne mesurent pas la phonétique humaine, le bruit ambiant ni la qualité du
tajwîd. Une prochaine série doit compléter ces contrôles avec des erreurs
enregistrées par un récitant et une validation à l'écoute.
