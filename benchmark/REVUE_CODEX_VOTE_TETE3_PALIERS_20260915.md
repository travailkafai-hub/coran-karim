# Revue des essais de Claude — vote et tête 3

État vérifié le 15 septembre 2026 après les trois campagnes Samsung.
Conclusion : **la version testée du vote dégrade trop les mots corrects ;
l'ajout de la tête 3 n'est pas justifié par les résultats en application.**
L'accord initial de Codex pour lui confier la couleur reposait trop sur le
rapport hors application. Cette mesure change la décision.

## Preuves relues et vérification reproductible

- `CAMPAGNE_PALIERS_20260915.md`, les trois manifestes, `executions.jsonl`,
  `environment.json`, les statuts `[CTL][V2]`, observations et avis tête 3.
- Code de `VoteFenetres`, `Decideur`, `JugementTete3` et chargement du plugin.
- Graphe : `piege_gop_vs_free`, `piege_verrou_sur_apercu`,
  `piege_attestation_normalisee_blanchit`, `mort_k1_a_la_fermeture`,
  `mesure_tete3_sans_gain_sur_modele_app`,
  `mesure_tete3_audio_reel_complete_le_tts_sans_le_remplacer`,
  `regle_le_plafond_de_tete3_est_en_amont_delle`.
- Test hors device `Tete3SansVoteContreFactuelTest` : +2 signalements de
  mutations, +18 signalements de corrects (57→59 et 40→58). Ce test rejoue
  un registre complet avec un décideur neuf : ce n'est pas une session en
  direct ni une preuve de parité des verrouillages.

Commande : `python -X utf8 benchmark/auditer_paliers_codex_20260915.py`.
Sortie : `AUDIT_PALIERS_CODEX_20260915.json` (preuves des changements incluses).
Le script vérifie que cibles, opérations et empreintes WAV correspondent
entre configurations. Il ne modifie ni les campagnes ni le téléphone.

## Résultat le plus probant : T805 seul

Les trois configurations jugent les **mêmes 222 indices**. Parmi eux :
200 mots sans mutation, 20 mots mutés comparables et 2 insertions dont le
verdict voisin reste un proxy. Les deux insertions sont exclues du tableau.

| Configuration | Mutations signalées / 20 | Corrects signalés / 200 | Corrects rouges définitifs / 200 |
|---|---:|---:|---:|
| Historique | 8/20 = 40 % | 7/200 = 3,5 % | 3/200 = 1,5 % |
| Vote seul | 11/20 = 55 % | 14/200 = 7 % | 7/200 = 3,5 % |
| Vote + tête 3 | 11/20 = 55 % | 18/200 = 9 % | 11/200 = 5,5 % |

« Signalé » inclut orange provisoire/définitif, rouge provisoire/définitif,
omis et déplacé. Ce n'est pas un taux de rouges définitifs : le JSON les
sépare. Un provisoire vert n'est pas présenté comme un correct définitivement
validé. Les mutations restent la vérité du montage, sans réécoute indépendante.

**Vote seul et vote + tête 3 portent exactement les mêmes 1 139 observations**
sur T805 : même ordre, fenêtre, tentative, texte libre, scores, frames,
intervalle, contexte, poids et exclusion. L'identité est vérifiée par SHA-256
du contenu normalisé (champs tête 3 exclus). Seuls quatre statuts changent,
tous vert définitif → rouge définitif sur des mots sans mutation :

| Index manifeste | Attendu | Logits de la candidate sur fenêtres retenues |
|---:|---|---|
| 68 | أُلْقُوا۟ | +10,900 ; +4,342 ; +8,164 |
| 131 | وَأَسِرُّوا۟ | +31,078 ; +33,048 ; +28,343 |
| 155 | مَنَاكِبِهَا | +3,901 ; +3,241 |
| 180 | حَاصِبًا | +0,826 ; +1,554 ; +1,380 |

Les `[t3-jugement]` portent `ECART`, `couleur_texte=VERT`, `couleur=ROUGE`,
`definitif=true`. Il ne s'agit donc pas d'une supposition fondée sur le
logit seul. Le seuil Hafs reçu ensuite (−2,222) ne résoudrait pas ces quatre
cas positifs : il est inférieur au seuil brut utilisé ici.

## Nuances nécessaires dans la conclusion de Claude

Les effectifs globaux 52/25, 68/73 et 69/76 (mutations signalées / corrects
signalés) sont reproduits. Ils portent toutefois sur des populations jugées
différentes après décrochage : le ratio global « trois accusations fausses
par détection gagnée » n'est pas une estimation causale appariée. Il inclut
également les doutes et les insertions prises comme proxies.

Le total du palier 10 % est identique pour vote et vote+tête3, mais cela ne
signifie pas absence d'effet : T805 prend **quatre faux rouges de plus**,
T806 perd quatre signalements de corrects. T806 n'a pas les mêmes
observations (73 contre 62). La seconde différence ne peut donc pas être
attribuée à un pouvoir de la tête 3 de blanchir des mots : le code de fusion
ne lui donne justement pas ce pouvoir. La cause de cette divergence de flux
reste à examiner. T807 a également 71 contre 60 observations.

Ces nuances renforcent le besoin d'un examen par mot. Elles ne rendent pas
la version acceptable.

## Mécanisme effectivement visible dans le vote

T805 / index 94, mot sans mutation `وَقُلْنَا` :

| Fenêtre | Texte libre | Poids brut | Exclusion |
|---:|---|---:|---|
| 80 | قُلْنَا | 0,997736 | aucune |
| 81 | وَقُلْنَا | 0,997712 | aucune |
| 84 | قُلْنَا | 0,993717 | aucune |

Les trois lectures appartiennent à la composante temporelle retenue.
Les deux lectures inexactes l'emportent, le mot devient rouge définitif.
Même signature de deux lectures inexactes contre une exacte sur
`رِّزْقِهِۦ` (158), `ٱلرَّحْمَـٰنُ` (202) et `جُندٌ` (211).

Le calcul d'addition respecte la demande A+A contre B. Le défaut est que
les poids tirés des pics CTC sont presque saturés, y compris quand la lecture
est fausse. Ils ne sont pas une estimation validée de la justesse du mot.
Plusieurs fenêtres du même son peuvent reproduire le même défaut du modèle.
Le contrôle `lecture_non_complete` compare le texte au décodage libre de
la fenêtre : si ce décodage est lui-même incomplet, le fragment peut être
admis comme complet. La responsabilité exacte du cadrage, du décodage et
des frontières reste à confronter au WAV ; elle n'est pas prouvée par une
ressemblance de chaînes de caractères.

**Ne pas corriger en excluant tout sous-mot de l'attendu** : `قُلْنَا` peut
être une vraie omission de `وَ`. Cela masquerait précisément une famille de
fautes demandée par l'utilisateur. Même réserve sur `estFragment` ajouté
dans le banc `evaluerSansVote` : son test de sous-chaîne ne prouve pas une
troncature par la fenêtre.

## Travail précis à poursuivre avec Claude

1. Confronter les quatre faux rouges propres à la tête 3 et les exemples
   de vote ci-dessus au PCM original, aux frames réellement utilisées et
   aux entrées de la tête. Vérifier aussi les équivalences orthographiques
   côté caractéristiques : le vote et la tête peuvent scorer deux formes
   de référence différentes. Ne pas conclure sans cette vérification.
2. Comparer chaque fragment observé sur plusieurs contextes du **même son**,
   avec ses bords audio et son décodage complet. Déterminer pourquoi une
   fenêtre mal lue obtient presque le même poids qu'une fenêtre juste.
3. Conserver les vrais gains (dont T023 et T005) comme contre-exemples :
   rétablir le raccourci « une attestation verte suffit » ne résout pas le
   problème initial. Aucune reprise humaine ne doit être ajoutée au vote
   des fenêtres d'une occurrence.
4. Tester les variantes hors device sur les mêmes observations, avec les
   événements de clôture quand disponibles. Mesurer gain/perte **appariés**,
   rouges, doutes, non jugés et latence séparément. Une variante ne passe
   sur Samsung qu'avec une hypothèse étayée et un témoin identique.
5. Le décrochage sur fragment de bord et la fiche de correction décalée de
   quatre mots sont des défauts distincts : suivre les tâches de Claude
   dans `CAMPAGNE_PALIERS_20260915.md`, sans les confondre avec le score tête 3.

État du téléphone lors de cette revue : `vote_fenetres_actif` présent,
`tete3_decision_actif` absent. Donc le vote expérimental reste demandé ;
la tête 3 est désactivée par son marqueur. Aucun marqueur, APK ni fichier
de décision n'a été modifié pendant cette revue. La nouvelle Warsh a été
récupérée et vérifiée séparément par Claude, sans mesure device Warsh dans
ces campagnes Hafs ; leur résultat ne prouve rien sur sa valeur propre.
