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

### La courbe, inspirée des jeux — et ce qu'on en refuse

> « Inspire-toi des jeux, ce qui se fait, mais après transpose sur cette
> application sérieuse. » (utilisateur, 2026-08-13)

**Ce qui se transpose, parce que ça sert la mémorisation :**

| mécanique de jeu | transposition ici | pourquoi ça tient |
|---|---|---|
| XP proportionnels à l'effort | 1 point par mot repris | l'effort de révision est réel, il se compte |
| combo / enchaînement | multiplicateur quand les quarts s'enchaînent **dans la même session** | c'est exactement ce que la mémorisation exige : de la continuité, pas des bribes |
| paliers de progression | badges sur des jalons **réels** : un quart, un Hizb, un Juz, une sourate entière, les Mufassal | le jalon a déjà un sens pour le récitant — on ne l'invente pas |
| série quotidienne | jours où l'objectif est atteint (cf. §8) | l'assiduité est le premier facteur de mémorisation |

Barème proposé : **1 point par mot repris**, ×1,5 si la reprise part du **début
du quart** (le geste qu'on veut installer), puis un multiplicateur croissant
par quart enchaîné dans la même session — ×1, ×1,2, ×1,5, ×2 : quatre quarts
d'affilée, soit un Hizb, valent le double de quatre quarts séparés.

**Garde-fou obligatoire** : plafonner le nombre de fois qu'un même quart
rapporte dans une journée. Sans ce plafond, le barème rend rentable de rejouer
en boucle un passage facile — c'est le défaut classique, et il viderait les
points de leur sens.

**Ce qu'on REFUSE, et il faut l'écrire pour ne pas y revenir :**

- **Les classements entre utilisateurs, les ligues.** Mettre des récitants du
  Coran en compétition est déplacé. Accessoirement l'app n'a ni compte ni
  serveur (cf. la politique de confidentialité : « tout se passe sur votre
  téléphone ») — c'est donc aussi impossible, et tant mieux.
- **Les vies / cœurs qui bloquent l'accès** (modèle Duolingo). Empêcher
  quelqu'un de réciter le Coran parce qu'il a « épuisé ses vies » serait
  absurde. Rien, jamais, ne doit fermer l'accès au texte.
- **Les récompenses aléatoires, coffres, roues.** Mécanique de hasard, étrangère
  à ce que l'app est.
- **Les badges décoratifs (icônes à débloquer, animations, collection à
  exhiber).** ✅ Tranché le 2026-08-13 : « c'est une application islamique, pas
  un jeu ». Et il n'y a rien à construire de plus -- `PortionResume.badge`
  (un quart) et `_GroupePortions.badge` (une sourate entière) existent déjà :
  bordure dorée + icône vérifiée sur la carte, quand la portion est
  intégralement couverte et juste. C'est DÉJÀ le badge -- une information sur
  la progression, jamais une récompense qui scintille. Les points restent,
  mais comme un compteur DISCRET d'effort de révision, pas un score affiché
  en grand.
- **La culpabilisation.** Le §2 pose déjà l'inverse : quand l'objectif est trop
  haut, on **propose de le baisser**. Une notification qui fait honte pousse à
  désinstaller, pas à réciter.

Reste à définir : le palmarès exact des badges, et le plafond journalier.

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

5. **Noms des trois niveaux** → **« À mon rythme » / « Régulier » /
   « Exigeant »** (§3).
6. **La série** → **le nombre de jours où l'objectif a été atteint**. Pas un
   compteur séparé : deux compteurs finissent toujours par se contredire, et
   celui-ci se déduit de la table de jours actifs (§7).
7. **La courbe de points** → inspirée des jeux, avec ce qui est explicitement
   refusé (§6).

**Reste ouvert :** le palmarès des badges, le plafond journalier anti-boucle,
et la formule exacte des multiplicateurs.

---

*Rien de tout cela n'est commencé. Ce document sert de référence commune ; il
sera mis à jour au fil des arbitrages, et c'est lui qu'il faut relire avant de
toucher au Coach.*

## ✅ TRANCHÉ ET IMPLÉMENTÉ — l'objectif est une « durée pour tout le Coran » (2026-08-14)

Proposition utilisateur, préférée au modèle précédent (« N quarts par jour /
semaine / mois », jugé illisible : « je trouve que objectif par jour c'est
beaucoup ») :

> l'objectif devient **mémoriser tout le Coran**, l'utilisateur choisit en
> combien d'**années**, et l'app AFFICHE ce que ça donne en moyenne par jour,
> par semaine et par mois (arrondi).

Le Coran = **240 quarts de Hizb** (60 Hizb x 4).

| Durée | /jour | /semaine | /mois |
|---|---|---|---|
| 1 an | 0,7 | 4,6 | 20 (5 Hizb) |
| 2 ans | 0,33 | 2,3 | 10 |
| 3 ans | 0,22 | 1,5 | 7 |
| 5 ans | 0,13 | 0,9 | 4 (1 Hizb) |
| 10 ans | 0,07 | 0,5 | 2 |

(Le curseur livré s'arrête à **6 ans** : au-delà, le rythme quotidien devient
si faible qu'il ne guide plus rien — 10 ans, c'est un dixième de quart par
jour. Les deux dernières lignes restent ici pour mémoire. Un ancien objectif
qui se convertissait au-delà de 6 ans est ramené à 6, cf. la migration.)

### Les quatre arbitrages, et ce qui a été livré

| Question | Décision utilisateur | Où ça vit |
|---|---|---|
| L'échéance porte sur quoi ? | **Le reste à mémoriser** (240 − acquis), pas les 240 quarts | `ObjectifCoach.rythmePour`, `SessionArchiveService.motsAcquisTousCoran` |
| Comment se saisit la durée ? | **Curseur de 1 à 6 ans** | `_ReglageObjectifSheet` |
| Fenêtre de la barre de progression | **Le mois** | `_ObjectifSection` |
| Périmètre | La refonte de l'objectif **seule** | — |

**Pourquoi le mois, et pas la semaine** (horizon de rattrapage du §2) : c'est le
seul horizon où la cible tombe sur un entier lisible sur toute la plage du
curseur — 20 quarts à 1 an, 3 à 6 ans. Sur la semaine, 6 ans redonnerait
« 0,8 quart », c'est-à-dire exactement le défaut corrigé le matin même
(capture utilisateur : « 0 sur 0.2 quart(s) »). Le jour et la semaine restent
affichés, en texte, sans barre.

**Le reste à mémoriser est compté en mots DISTINCTS**, pas en portions : une
portion vaut selon les cas une sourate, un demi-Hizb ou un quart, et changer la
granularité laisse en base les anciennes portions dont les versets sont aussi
couverts par les nouvelles — additionner des portions compterait deux fois les
mêmes mots. D'où le `DISTINCT (sourate, verset, mot)`, converti en quarts par
la moyenne du Coran (~322,6 mots par quart).

**Effet de bord identifié AVANT d'implémenter, et traité** : le seuil quotidien
de la série est dérivé du rythme (`parJour × 322,6 mots`). À 6 ans il tombait à
~35 mots, soit An-Nasr plus une ligne — une série qui ne peut plus se rompre ne
mesure plus l'assiduité. D'où un **plancher à 50 mots**
(`RythmeCoach.plancherMotsParJour`), soit une courte sourate.

Ce que ça a changé dans le code : `ObjectifCoach` (années + `RythmeCoach`
dérivé, au lieu de quarts+période), la persistance (`coach_objectif_annees`,
avec migration une fois depuis l'ancien volume/période — l'ancien réglage n'est
pas effacé), `_ReglageObjectifSheet`, `_ObjectifSection`, le seuil de série
dans `karaoke_recitation_screen`, et une **migration v6 → v7** de
`session_archive.db` : colonne `jours_actifs.objectif_mots_du_jour` (l'ancienne
`objectif_du_jour` porte des QUARTS sur les jours antérieurs et n'est plus
alimentée — changer l'unité d'une colonne en place aurait rendu l'historique
faux en silence).
⚠️ La colonne `souffle` évoquée plus bas devient donc une migration **v7 → v8**.

Couvert par `app/test/objectif_coach_test.dart` (8 cas, au vert) : le tableau
ci-dessus, la détente du rythme à mesure qu'on avance, le plancher de série,
et les bornes (Coran acquis, dépassement).

**Baisser l'objectif** (§2) ne veut plus dire réduire un volume mais
**allonger l'échéance d'un an**, plafonnée à 6 — on ne descend jamais à
« aucun objectif », qui serait un abandon et non une baisse.

### La barre de progression comptait faux — troisième et dernière source

Constat fait en vérifiant la refonte sur le téléphone : la carte affichait
**« 100 % ce mois-ci »** juste sous **« il te reste 239 quarts sur 240 »**.

Cause, mesurée sur la base réelle : la barre sommait des **fractions de
portion** plafonnées à 1. Une portion « sourate entière » courte y valait donc
un quart PLEIN — Al-Kawthar (10 mots) comptait autant qu'un vrai quart
(~322 mots).

| ce que la barre comptait | ce que valent vraiment ces mots |
|---|---|
| 12,37 quarts | **0,84 quart** (272 mots ÷ 322,6) |

Corrigé le 2026-08-14 : l'avancement du mois lit la **même grandeur** que le
reste à mémoriser (mots acquis distincts ÷ 322,6,
`quartsAcquisDuMoisProvider`). Les deux chiffres de la carte ne peuvent plus se
contredire, ils sortent de la même requête. Effet assumé : la barre passe de
100 % à **17 %** sur ce téléphone — elle était flatteuse parce qu'elle était
fausse.

⛔ **Le plancher `jours_actifs.quarts_valides` a sauté avec** (`math.max(
quartsFaits, avancement)`) : ce compteur s'incrémente sur
`PortionResume.badge`, donc il portait exactement le même biais et l'aurait
réintroduit à lui seul. Il reste utilisé pour l'objectif du JOUR
(`quartsValides > 0` valide la journée), où le biais est bienveillant et
cohérent avec le §2 — mais il ne doit plus jamais servir de mesure d'avancement.

**Trois sources fausses en une journée pour cette seule barre**
(`mots_recites` cumulé → fractions de portions → mots distincts) : la leçon
tient en une ligne — *une mesure d'avancement ne peut pas mélanger deux unités,
et une portion n'est pas une unité de volume.*

### Ce qui est affiché où (demande utilisateur 2026-08-14)

> « je veux pas afficher le détail sur cet écran, il est quand on choisit
> l'objectif »

| écran | ce qu'il montre |
|---|---|
| Carte « MON OBJECTIF » | le but (« Tout le Coran en 4 ans »), les trois tuiles, les trois barres. **Pas** le détail du calcul |
| Feuille de réglage | le reste à mémoriser et le rythme jour/semaine/mois, mis à jour pendant qu'on déplace le curseur — là où ils servent à décider |

### Trois horizons, et une couleur qui veut dire quelque chose (2026-08-14)

> « il manque une progression annuelle et une pour le Coran entier [...] pas
> forcément affichée dès le départ mais on défile »
>
> « je veux que la couleur ait un sens : vert je suis dans le rythme, orange ça
> dérape un peu, rouge il faut que je progresse pour rattraper l'objectif du
> mois »

| barre | cible | état coloré |
|---|---|---|
| **ce mois-ci** (30 j glissants) | `parJour × 30` | oui — c'est celle qu'on peut encore rattraper |
| **cette année** (365 j glissants) | `parJour × 365` | oui |
| **tout le Coran** | 240 quarts | **non** : un cumul n'a pas d'échéance, personne n'est « en retard » sur le Coran |

Fenêtres **glissantes** et non civiles : sinon, chaque 1ᵉʳ janvier, une
progression durement acquise retomberait à zéro du jour au lendemain.

**L'état n'est PAS le pourcentage de la barre** (`EtatRythme.depuis`). Il
compare l'avancement à ce qui était attendu **compte tenu du temps déjà
suivi** : ≥ 100 % vert, ≥ 70 % ambre, en dessous brique. Sans cette
pondération, quelqu'un qui installe l'app ouvre son premier écran sur du rouge
— la culpabilisation que le §2 refuse. Mesuré sur le téléphone de test
(2 jours de suivi, 0,84 quart) : la barre affiche **17 %** et l'état est
**vert**, parce que le rythme quotidien, lui, est tenu.

Trois précautions tenues :
- **la couleur ne porte jamais l'information seule** — chaque état est doublé
  d'un libellé écrit (« Dans le rythme » / « Léger retard » / « À rattraper ») ;
- **contrastes vérifiés** sur le crème (#fbf7ee) : 7,00 / 4,67 / 5,99, tous
  ≥ 4,5 puisque la couleur porte aussi du texte ;
- **le rouge est une brique**, pas un rouge d'alerte, et aucun des trois hex
  n'est partagé avec les palettes tajwid, mindmap ou jeu.

Sous 10 %, le pourcentage garde une décimale : « 0,4 % du Coran » plutôt qu'un
« 0 % » qui effacerait un travail réel.

### Ce que la carte a perdu — trois retraits demandés le même jour

Les trois barres ont d'abord été empilées à plat, et la carte gardait ses trois
tuiles plus un bouton « Réciter ». Retour utilisateur immédiat, et il porte une
seule idée : **une carte de tableau de bord doit répondre à une question, pas
en poser trois.**

| retrait | ce que disait l'utilisateur | ce qui a été fait |
|---|---|---|
| année + Coran entier à plat | « pas affichées au premier coup, ça doit être caché, que la progression du mois » | repliés derrière « Voir l'année et le Coran entier ». Le mois est le seul horizon **sur lequel on peut encore agir aujourd'hui** ; les empiler le noyait |
| bouton « Réciter » | « enlève aussi Réciter, je ne l'utilise pas » | retiré (l'accès reste entier ailleurs dans le hub). Code gardé en commentaire, avec sa règle : l'objectif dit COMBIEN progresser, jamais PAR OÙ commencer |
| tuile « Aujourd'hui : en cours » | « à côté de série, je ne comprends pas l'utilité, il se peut à supprimer » | **fusionnée** dans la tuile Série plutôt que supprimée : elle ne répond qu'à « est-ce que ma journée comptera pour la série ? », donc c'est une information SUR la série. « 3 jours · aujourd'hui validé » se comprend seul, la tuile isolée non |

Le repli n'est **pas persisté** : il se referme à chaque ouverture de l'écran.
Rouvrir automatiquement ce que l'utilisateur a demandé de cacher remettrait au
premier plan ce qu'il vient d'en retirer.

### Deux autres points ouverts, même journée

1. **Historisation de l'objectif.** L'objectif n'a AUCUN historique (une seule
   valeur dans les préférences). Analyse faite avec l'utilisateur : le passé
   ne doit JAMAIS être recalculé -- sinon la série devient achetable (baisser
   la barre offrirait une série jamais gagnée) et l'historique devient
   instable. Manque : une table en AJOUT SEUL
   `objectifs_historique(depuis, quarts, periode, niveau)`, et un affichage
   segmenté par époque (« du 1er au 20 août : 3/semaine — 1 semaine sur 3 »).
   Corollaire retenu : l'objectif est une ALLURE, pas une note ; la mesure qui
   ne dépend d'aucun objectif (portions acquises) doit rester en tête.

2. **L'oubli n'a pas de marqueur propre.** `deja_rate` signifie « a déjà été
   faux une fois » (statuts `error`/`oubli`/`unclear`), PAS « le souffleur a
   dû lancer l'audio ». L'exclure de `words_green` a été tenté le 2026-08-14
   et ANNULÉ le jour même : Al-Masad et Al-Falaq sont tombées sous 100 %
   rétroactivement, sur des mots simplement corrigés autrefois, sans aucun
   oubli. Il faut une colonne dédiée `souffle` (migration v6 -> v7), posée au
   déclenchement du souffleur, monotone, et exclue du score. Le marquage GRIS
   à l'écran, lui, est en place et correct (`_motsOublies`, session en cours).
