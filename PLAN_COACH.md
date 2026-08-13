# Le Coach — de la mesure à l'accompagnement

Document de conception. **Rien n'est implémenté à ce jour.** Écrit le
2026-08-13 à partir du cadrage utilisateur, pour être arbitré avant tout code.

---

## 1. Le constat de départ (mots de l'utilisateur)

> « On ne fait que réciter [...] les sessions avec la mémorisation, avec les
> pourcentages, ça c'est bien, mais on n'est pas encore dans la phase coach. »

L'app sait aujourd'hui répondre à **« qu'est-ce que j'ai fait, et est-ce que
c'était juste ? »**. Elle ne sait pas répondre à **« où dois-je en être, et
qu'est-ce que je fais aujourd'hui ? »**. Tout ce qui suit vise cette seconde
question — sans rien retirer de la première, qui reste la base de mesure.

**Ce qui est déjà acquis et qu'on imbrique, jamais qu'on remplace :**
- la récitation vérifiée par le modèle — c'est **le moyen de contrôle**, et
  c'est ce qui distingue cette app d'un compteur déclaratif : un palier n'est
  validé que si le modèle a entendu une récitation juste ;
- le suivi permanent par **quart de Hizb** (`portions`/`portion_words`), avec
  ses pourcentages et son historique de mots ratés ;
- le journal cumulé d'erreurs par mot (`RecitationErrorLogService`), jamais
  purgé — c'est lui qui sait « les versets où il oublie souvent ».

## 2. Les objectifs, et leur cascade

L'utilisateur fixe un objectif dans les **Réglages → Coach** : un volume
(versets, pages, ou quart de Hizb) sur une **période** (jour, semaine, mois).

L'app en **dérive** les paliers plus courts :

> « Dans un mois je fais un Hizb, ça veut dire qu'on fait les opérations pour
> voir combien il doit faire par jour et par semaine. »

Donc un seul objectif saisi, trois horizons affichés : **jour → semaine →
mois**. Le jour est le palier d'action, la semaine le palier de rattrapage, le
mois l'horizon de sens.

### Le rattrapage, pas la punition

> « S'il rate une journée, qu'il puisse récupérer pour atteindre l'objectif de
> la semaine [...] pour qu'il continue pour atteindre son objectif final. »

Une journée manquée ne casse rien : elle **reporte sa charge sur les jours
restants de la semaine**. C'est la semaine qui fait foi, le jour n'est qu'une
répartition. Conséquence de conception : l'écran doit montrer la dette
courante (« il te reste 2 pages sur 4 d'ici dimanche »), pas un échec.

### Et si l'objectif est trop haut : le baisser, pas insister

> « Mieux vaut des petits pas qu'on réussit que des grands pas qu'on rate. »

Quand la semaine est manquée — pas un jour, la **semaine** — l'app **propose
de réduire l'objectif**. C'est une règle rare et précieuse : elle protège
contre l'abandon, qui est le vrai risque, plutôt que de défendre un chiffre.
À faire par proposition explicite, jamais par ajustement silencieux : un
objectif qui baisse tout seul n'est plus un engagement.

## 3. Les trois niveaux d'accompagnement

L'utilisateur les a décrits ainsi : « niveau zéro, c'est toi qui décides, pas
de forcing », « modéré », « strict », et a demandé de proposer les noms.

**Proposition** — nommer ce que l'utilisateur **reçoit**, pas l'agressivité de
l'app :

| niveau | nom proposé | ce qui change |
|---|---|---|
| 0 | **À mon rythme** | aucun rappel, aucune relance. Les objectifs restent affichés, purement indicatifs |
| 1 | **Régulier** | un rappel par jour, un bilan hebdomadaire. Silence si l'objectif du jour est déjà atteint |
| 2 | **Exigeant** | relances multiples, rappel des versets souvent ratés, alerte quand la série ou la semaine est en danger |

(Les mots de l'utilisateur — libre / modéré / strict — fonctionnent aussi ;
« strict » décrit toutefois une sévérité de jugement, pas une fréquence de
rappel, d'où la proposition ci-dessus.)

## 4. Les notifications

> « Par exemple sur un rappel avec les versets où il oublie souvent [...] avec
> tout le verset. »

Trois familles, par ordre d'utilité :

1. **Le rappel du jour** — dit l'état, pas « reviens » : « il te reste 1 page
   pour ta semaine », « ta série de 12 jours s'arrête ce soir ».
2. **Le verset qui coince** — tiré du journal cumulé d'erreurs, avec **le
   texte du verset dans la notification**. C'est la seule qui apprend quelque
   chose en étant simplement lue.
3. **La proposition de baisse** — après une semaine manquée (cf. §2).

### ✅ Tranché (2026-08-13) — adossés aux horaires de prière, renforcés le soir et le week-end

Les rappels se calent sur les **horaires de prière**, que l'app calcule déjà :
ils suivent donc les saisons sans réglage, et tombent à des moments où
l'utilisateur est déjà tourné vers le Coran.

Deux pondérations demandées : **davantage le soir**, et **davantage le
week-end** — les moments où le temps existe réellement. Un rappel du matin en
semaine a peu de chances d'être suivi d'effet ; l'insistance doit se placer là
où l'action est possible.

L'infrastructure existe déjà : `flutter_local_notifications`, et le
`ScheduledNotificationBootReceiver` est déjà déclaré au manifeste — les
rappels survivent au redémarrage sans travail supplémentaire. Les horaires de
prière viennent de `PrayerTimesService`.

## 5. Valider un palier : la répétition depuis le début

C'est le point le plus original du cadrage, et il faut le lire deux fois :

> « C'est validé par des récitations par palier [...] si on écoute des grandes
> sourates, qu'il répète depuis le début jusqu'au palier. Donc comme ça, c'est
> de la répétition. »

Autrement dit : sur une sourate courte, le palier = la sourate. Sur une longue,
valider le palier N exige de réciter **de 1 à N**, pas seulement N. La
mémorisation se consolide par recouvrement, et le système le récompense au
lieu de le subir.

> « S'il est dans la page 2, s'il répète la page 1 et 2, il gagne plus de
> récompenses. »

### ✅ Tranché (2026-08-13) — le palier est le QUART de Hizb, et on le reprend entier

> « Pour valider les paliers, c'est le quart de Hizb. On ne peut pas partir sur
> le Hizb, il ne peut pas réciter d'un coup un Hizb entier [...] quand il est
> en train de réciter dans le quart de Hizb, c'est préférable qu'il répète
> depuis le début du quart de Hizb. »

La reprise est donc **bornée par construction** : jamais plus d'un quart de
Hizb, quelle que soit l'avancée. Le problème d'impraticabilité disparaît sans
mécanisme supplémentaire — pas de fenêtre glissante, pas de révision espacée à
inventer ici. Le quart est déjà l'unité de `portions` : aucune conversion.

**Valider un quart = le réciter depuis son début, jugé correct par le modèle.**

## 6. Points et badges — la répétition a une valeur en soi

> « S'il a déjà lu un Hizb, il veut le répéter, c'est bien, ça gagne des points.
> Indépendamment s'il fait des erreurs ou pas. Pour les points, c'est vraiment
> pour donner de la valeur à la répétition. »

**Deux monnaies distinctes, et c'est ce qui rend le système cohérent :**

| | ce qui la gouverne | ce qu'elle récompense |
|---|---|---|
| **Validation d'un palier** | le modèle : la récitation est-elle juste ? | la **qualité** |
| **Points / badges** | le volume répété, **sans regarder les erreurs** | la **répétition** |

Un utilisateur qui reprend un Hizb entier déjà su gagne des points même s'il
trébuche — parce que ce qu'on veut encourager là, c'est le geste de revenir en
arrière, que rien d'autre ne récompense. Et il ne peut pas pour autant valider
un palier mal récité : la qualité reste gardée par le modèle, ailleurs.

Cette séparation évite l'écueil classique d'un barème unique — soit il punit
la révision d'un passage fragile, soit il rend rentable de rejouer du facile.

Reste à définir : la courbe exacte (points par mot repris ? par quart ?) et le
palmarès des badges.

## 7. Ce qui manque techniquement (à faire en premier)

**Une table de jours actifs.** Les sessions sont purgées à **7 jours**
(`SessionArchiveService.retentionJours = 7`) : une série ou une courbe
mensuelle **ne peut pas** en être dérivée. Il faut une table durable, minuscule
— une ligne par jour (date, mots récités, paliers validés, objectif du jour) —
de l'ordre du kilo-octet par an. Sans elle, toute statistique au-delà d'une
semaine serait fausse **en silence**, ce qui est pire que de ne rien afficher.

C'est le seul ajout de schéma indispensable ; le reste s'appuie sur
`portions` (permanent) et le journal d'erreurs (jamais purgé).

## 8. Décisions

**Tranchées le 2026-08-13 :**

1. **Unité d'objectif et de palier** → le **quart de Hizb** (§5).
2. **Validation d'un palier** → le réciter **depuis son début**, jugé correct
   par le modèle. Borné par construction (§5).
3. **Points** → découplés de la justesse, ils récompensent la répétition (§6).
4. **Rappels** → adossés aux **horaires de prière**, renforcés le **soir** et
   le **week-end** (§4).

**Encore ouvertes :**

5. **Les noms des trois niveaux** : « À mon rythme / Régulier / Exigeant »
   (proposition du §3), ou les mots d'origine (libre / modéré / strict) ?
6. **La série** : mécanique à part, ou simplement « nombre de jours où
   l'objectif a été atteint » ? La seconde évite deux compteurs qui peuvent se
   contredire.
7. **La courbe de points** : par mot repris, ou par quart ? Et quels badges ?

---

*Rien de tout cela n'est commencé. Ce document sert de référence commune ; il
sera mis à jour au fil des arbitrages, et c'est lui qu'il faut relire avant de
toucher au Coach.*
