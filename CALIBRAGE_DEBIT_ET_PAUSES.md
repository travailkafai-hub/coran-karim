# Débit, pauses et découpage — ce que le modèle préfère, et comment calibrer

État au 2026-07-31. Toutes les valeurs de ce document sont **mesurées** ; celles
qui ne le sont pas sont signalées comme telles.

---

## 1. Trois grandeurs qu'on confond, et une quatrième qui décide

Quand on dit « il récite trop vite », on mélange trois choses **indépendantes** :

| grandeur | ce que c'est | mesurée par |
|---|---|---|
| **durée des pauses** | combien de temps dure chaque silence | p50, p75, p90 des silences |
| **fréquence des pauses** | combien de silences par seconde | nombre de silences ÷ durée |
| **débit** | vitesse d'articulation des mots eux-mêmes | *pas mesuré aujourd'hui* |

Ces trois-là ne bougent pas ensemble. La preuve est dans les deux calibrages
faits ce soir :

|  | référence | utilisateur |
|---|---|---|
| durée totale | 102,7 s | 46,6 s |
| silences | 35 | 44 |
| **fréquence** | **0,34 /s** | **0,94 /s** |
| p50 | 0,16 s | 0,08 s |
| p75 | 0,32 s | 0,16 s |
| **p90** | **0,80 s** | **0,48 s** |
| p95 | 0,88 s | 0,56 s |
| séparation p90/p25 | 10,0 | 6,0 |
| niveau de parole | 0,0761 | 0,1193 |

L'utilisateur fait **presque trois fois plus de pauses**, mais **deux fois plus
courtes**. Aucune des deux voix n'est « plus rapide » que l'autre au sens naïf :
elles phrasent différemment.

### La quatrième grandeur — celle qui décide vraiment

Ni la durée ni la fréquence ne pilotent la qualité. Ce qui la pilote, c'est ce
qu'elles produisent **ensemble** :

> **la durée des segments envoyés au modèle.**

C'était déjà écrit dans le balayage du code, sans qu'on en tire la conséquence :
*« ce qui pilote le taux n'est ni la pause ni le RMS pris isolément, c'est le
NOMBRE DE BLOCS qu'ils produisent ensemble »*.

```
segments = silences qui dépassent le seuil
durée de segment ≈ durée totale ÷ nombre de ces silences
```

Deux récitateurs très différents peuvent produire les mêmes segments — et c'est
tout ce que le modèle voit.

---

## 2. Ce que le modèle préfère

### Son domaine d'entraînement

- `max_duration: 20.0` — aucun clip d'entraînement ne dépasse **20 s** ;
- sur les 59 232 clips de Coran récité du manifeste : médiane **12,6 s**,
  q90 32,0 s, q99 53,9 s, max 60 s.

Au-delà, le modèle travaille dans un régime de longueur qu'il n'a jamais vu.

### La courbe mesurée — un plateau, pas un pic

Balayage sur le flux brut de référence, tout le reste identique :

| blocs produits | mots non verts |
|---|---|
| 39 | **73,56 %** |
| 49 | 65,76 % |
| 75 | 2,64 % |
| 91 | 2,72 % |
| 102 | **2,03 %** |
| 104 | 2,71 % |
| 127 | 4,41 % |
| 287 | 15,93 % |

**Trop peu de blocs** → ils sont trop longs, hors domaine, effondrement.
**Trop de blocs** → chaque frontière est une occasion de se tromper.
L'optimum est large : entre ~75 et ~104 blocs, tout tient entre 2,0 et 2,7 %.

C'est une bonne nouvelle : il n'y a pas de valeur magique à trouver, il y a une
**zone** à viser. Sur la récitation de référence (380 s), cette zone correspond
à des segments d'environ **8 à 13 secondes**.

### Le garde-fou, et pourquoi il ne doit jamais se déclencher

`maxBlocSecondes = 30 s` : si aucun silence ne se présente, la chaîne coupe au
RMS le plus bas disponible — donc potentiellement **en pleine parole**.

> MESURE : à 18 s ce garde-fou coupait en pleine parole et faisait passer le
> taux de **11,86 % à 51,53 %**.

Il a été porté à 30 s et, avec le réglage retenu, **il ne se déclenche jamais**.
S'il se déclenche, c'est un symptôme à instruire, pas un réglage à baisser.

---

## 3. Les seuils en vigueur

| paramètre | valeur | nature |
|---|---|---|
| `pauseMinSecondes` | **0,35 s** (0,40 validé) | **FIGÉ EN DUR** — le seul qui reste à calibrer |
| `seuilRmsSilence` | 0,344 × p75 des RMS, borné [0,004 ; 0,20] | **déjà adaptatif**, fenêtre glissante 30 s |
| `maxBlocSecondes` | 30 s | garde-fou |
| `minBlocSecondes` | 0,8 s | un énoncé plus court est une respiration, on l'agrège |
| cadence d'aperçu | ~3 s, fenêtre 9 s | **horloge absolue**, indépendante des coupes |

### Le seuil RMS est un précédent réussi — c'est le modèle à copier

Fixe, il s'effondrait dès qu'on changeait le gain :

| gain | blocs | non verts |
|---|---|---|
| ×0,4 | 287 | 15,93 % |
| ×1,0 | 102 | **2,03 %** |
| ×1,5 | 49 | **65,76 %** |
| ×2,5 | 39 | 73,22 % |

+50 % de volume et la chaîne s'écroule. Rendu adaptatif (rapport au niveau de
parole) : **2,03 % à tous les gains, 91 blocs à chaque fois**. La valeur 0,344
est **dérivée** — c'est le rapport qui reproduit le seuil validé — pas réglée.

C'est exactement ce qu'il reste à faire pour la pause.

---

## 4. La méthode de calibrage

### Ce qui est déjà en place

Écran `CalibrageScreen` + `recitation2/Calibrage.kt`. Le récitateur récite
≥ 45 s, l'app mesure :

1. le **niveau de parole** (p75 des RMS de bloc) → le seuil de silence ;
2. les **durées de silence** avec ce seuil → la distribution complète ;
3. la **séparation** p90/p25 → deux populations distinctes, ou non.

**Cumul sur plusieurs sessions** : on ne cumule PAS le signal brut, on cumule
les **silences**. Chaque session dérive son propre niveau de parole avant d'être
versée au total — deux sessions à des distances différentes du micro auraient
sinon un p75 commun à mi-chemin, trop haut pour l'une et trop bas pour l'autre.

Tout est journalisé (`[CALIB]` dans `recitation_diagnostic.log`), distribution
comprise : la valeur seule serait un chiffre incontestable, la distribution dit
si le réglage **tient**.

### La méthode que je proposais — et pourquoi elle est FAUSSE

`seuil = 0,50 × p90 des silences`, le rapport 0,50 étant dérivé de la récitation
de référence (p90 = 0,80 → 0,40 validé).

Elle reproduit bien 0,400 sur la référence. **Elle échoue sur la deuxième
voix** :

```
utilisateur : p90 = 0,48  →  0,50 × 0,48 = 0,24  →  borné à 0,25
```

Et 0,25 est une valeur déjà constatée comme un **échec**. La borne a rattrapé le
coup, mais elle a masqué une méthode fausse.

**Ce n'est pas une imprécision, c'est le mauvais sens.** L'utilisateur fait
beaucoup de petites pauses ; il faut **monter** la barre pour les enjamber, pas
la descendre. Le rapport au p90 transforme chacune de ses respirations en
frontière et le découperait en segments de 4 à 6 s — hors de la zone du modèle.

### La méthode correcte — viser la durée de segment

L'invariant entre récitateurs n'est pas le rapport à leurs pauses. C'est **la
durée des segments produits**, puisque c'est la seule chose que le modèle voit.

```
cible          : ~11 s par segment (centre de la zone 8-13 s mesurée)
frontières     = durée totale ÷ 11
seuil          = la durée de silence telle que ce nombre de silences la dépasse
```

Appliqué aux deux calibrages :

| | durée | silences | frontières visées | seuil obtenu |
|---|---|---|---|---|
| référence | 102,7 s | 35 | 9,3 (top 27 %) | **≈ 0,32 – 0,40 s** ✔ |
| utilisateur | 46,6 s | 44 | 4,2 (top 9,5 %) | **≈ 0,48 s** |

La référence retrouve sa valeur validée ; l'utilisateur obtient un seuil **plus
haut**, ce qui est bien le sens attendu.

**Aucun paramètre emprunté à un autre récitateur.** La seule constante est la
durée de segment cible, et elle vient du **domaine d'entraînement du modèle** —
donc d'une propriété du modèle, pas d'une voix.

### Une piste alternative : la vallée

Les percentiles montrent un creux net entre les deux populations (référence :
p75 = 0,32 puis p90 = 0,80, rien entre les deux). On peut poser le seuil dans ce
creux — le plus grand écart entre deux durées consécutives — sans aucun
paramètre. À comparer avec la méthode par durée de segment : **non mesuré à ce
jour**.

---

## 5. Seuil calibré OU jauge ? — les deux, mais pas pour la même chose

C'est la question centrale, et il ne faut pas les confondre.

### Le moule existe — la question est QUI fait l'effort d'y entrer

La plage 8-13 s n'est pas négociable : c'est le domaine du modèle, tout le monde
doit y atterrir. Le sujet n'est donc pas *s'il faut* un moule, mais qui s'adapte.

**La méthode par durée de segment NORMALISE tout le monde vers cette plage** —
le récitateur garde son phrasé naturel, c'est le seuil qui change :

```
référence   0,34 pause/s, longues   →  seuil 0,40  →  ~11 s
utilisateur 0,94 pause/s, courtes   →  seuil 0,48  →  ~11 s
```

Deux voix opposées, **même sortie**. C'est exactement pourquoi le rapport
0,50 × p90 était mauvais : il CONSERVAIT la différence entre les voix au lieu de
l'absorber.

### DÉCISION : seuil GÉNÉRAL, calibrage comme test d'admission

**Décision utilisateur, 2026-07-31.** J'avais proposé un seuil par récitateur ;
la mesure ne le justifie pas, et le seuil général est retenu.

L'argument est le **plateau** : 75 blocs → 2,64 %, 91 → 2,72 %, 102 → 2,03 %,
104 → 2,71 %. Une plage large de 30 % en nombre de blocs pour moins de 0,7 point
d'écart. Ce jeu suffit à absorber la différence entre récitateurs — avec un seuil
général de **0,40** :

| | frontières | segment | dans la plage ? |
|---|---|---|---|
| référence | ~9 sur 35 silences | ~11 s | oui |
| utilisateur | ~5-8 sur 44 silences | ~6-9 s | **oui** |

Mon 0,48 aurait centré l'utilisateur à 11 s, pour un gain que le plateau rend
probablement indétectable.

**Ce que le général gagne :** un seul comportement à raisonner, une seule recette
à interpréter, **aucun état par utilisateur** à stocker, versionner, invalider.
Et surtout aucun risque qu'un calibrage raté dégrade quelqu'un en silence —
exactement ce qui a failli arriver avec le 0,24 dérivé sur l'utilisateur, que
seule la borne a arrêté.

**Le calibrage ne RÈGLE donc plus le seuil, il VÉRIFIE** que le récitateur entre
dans la plage avec le seuil général. C'est un test d'admission :

- entre dans la plage → rien à faire, seuil général ;
- ne s'arrête presque jamais > 0,40 → 2-3 frontières, segments de 20 s et plus,
  le garde-fou finira par couper en pleine parole ;
- marque une pause franche à chaque mot → trop de blocs, retour vers les 4,41 %
  de la ligne « 127 blocs ».

Pour ces deux derniers cas **seulement, et une fois détectés**, on adapte. Le
per-utilisateur devient une exception justifiée par une mesure, au lieu d'être la
règle par défaut.

**Ce qui falsifierait cette décision** : un récitateur dont le calibrage sort de
la plage avec 0,40. Tant qu'on n'en a pas rencontré un, le seuil général tient.

⚠️ **La plage reste une plage, pas un point.** Si le cas se présente, on peut
choisir où placer quelqu'un dedans selon sa marge : un récitateur à marge nulle
(cf. plus bas) gagnerait à viser le bord bas (7-8 s) plutôt que le centre.
*Non mesuré sur device.*

**Réponse directe : oui, le 0,40 changera** — il deviendra une valeur par
récitateur. Pour l'utilisateur calibré ce soir, ce serait ~0,48. Le 0,40 restera
la valeur de départ tant qu'aucun calibrage n'existe.

### La jauge surveille la DÉRIVE (dynamique, pendant une session)

Elle ne sert pas à choisir le seuil — **elle ne le peut pas** : ses paliers sont
gradués par le seuil (1,5 × seuil, 1 × seuil), donc changer le seuil déplace la
jauge sans que rien n'ait changé dans la récitation. C'est circulaire.

Elle sert à l'unique cas que le calibrage ne peut pas couvrir : **le récitateur
s'écarte de son propre comportement habituel** en cours de session.

### La formule

Observable : **le temps écoulé depuis la dernière frontière** — c'est-à-dire
depuis le dernier silence qui a franchi le seuil.

```
T       = temps depuis la derniere frontiere (s)
T_hab   = intervalle habituel entre frontieres de CE recitateur (calibrage)
        = duree totale / nombre de silences >= seuil
          defaut 11 s si aucun calibrage

T_rouge = min( 2 x T_hab , 0,6 x maxBloc )      -> plafonne a 18 s
T_jaune = max( T_hab , 0,5 x T_rouge )

VERT   T < T_jaune
JAUNE  T_jaune <= T < T_rouge
ROUGE  T >= T_rouge
```

| | T_hab | vert | jaune | rouge |
|---|---|---|---|---|
| référence | 11,4 s | < 11,4 | 11,4 – 18 | ≥ 18 s |
| utilisateur | ~7,8 s | < 7,8 | 7,8 – 15,6 | ≥ 15,6 s |

**Pourquoi cette forme :**

- **Le sens unique est gratuit.** T se remet à zéro à chaque frontière.
  Ralentir → frontières plus fréquentes → T ne monte jamais → vert. Ce n'est pas
  une règle ajoutée qu'on pourrait oublier de maintenir, c'est la nature de la
  grandeur mesurée.
- **Pas de scintillement.** T croît linéairement puis retombe à zéro. Aucune
  hystérésis nécessaire — contrairement à un maximum glissant sur 20 s, qui
  chuterait par marches quand la dernière longue pause sort de la fenêtre.
  *(C'était la première version proposée ; abandonnée pour cette raison.)*
- **Le plafond à 18 s n'est pas choisi**, c'est la valeur mesurée où le
  garde-fou détruisait le taux (11,86 % → 51,53 %). Le rouge s'allume donc
  exactement au point mesuré comme catastrophique, jamais après.
- **Les deux règles du `min` ont chacune leur raison** : `2 × T_hab` dit « vous
  vous écartez de vous-même », `0,6 × maxBloc` dit « la casse dure approche ».
  Deux modes de défaillance distincts, on prend celui qui arrive en premier.
- **Aucun état par utilisateur n'est requis** : sans calibrage, T_hab = 11 s et
  la jauge fonctionne. Le calibrage ne fait que l'affiner.

### Coût de calcul : nul

Rien de neuf à calculer. Le RMS par bloc et la longueur du silence courant sont
**déjà** calculés par `ConstructeurDeFenetres` pour détecter les frontières
(`runSilence`, `noterNiveau`). La jauge s'y branche : une comparaison et une
soustraction toutes les 80 ms, aucune allocation, aucun appel au modèle.

Pour comparer, chaque aperçu est une passe complète de l'encodeur toutes les
3 s. Ce n'est pas un arbitrage à faire.

### Ce qu'il faut ajouter au calibrage

`T_hab` demande le **nombre de silences ≥ seuil**, que le journal ne garde pas
(il n'a que les percentiles). Deux lignes dans `Calibrage.kt` : compter, et
exposer `intervalleHabituel`. Ça enrichit aussi l'écran — « une frontière toutes
les 7,8 s » est plus parlant qu'un percentile.

#### Les paliers sont PAR RÉCITATEUR, un multiplicateur général ne transfère pas

Première version de ce document : vert ≥ 1,5 × seuil. **Faux**, et les deux
calibrages le prouvent — ça suppose que le seuil se place toujours au même
endroit dans la distribution du récitateur :

| | seuil calibré | p90 (sa pause longue habituelle) | marge |
|---|---|---|---|
| référence | 0,40 | 0,80 | **×2,0** |
| utilisateur | 0,48 | 0,48 | **×1,0** |

Chez la référence le seuil est bien en dessous des vraies pauses. **Chez
l'utilisateur il tombe exactement sur son p90** : un palier vert à 1,5 × seuil
l'aurait mis au jaune-rouge en permanence alors qu'il récite normalement.

**Deux ancrages, tous deux issus du calibrage :**

| | ancrage | nature |
|---|---|---|
| 🔴 | < **seuil** | universel dans sa FORME — en dessous, aucune pause ne peut produire de frontière ; ce n'est pas un avertissement mais un constat |
| 🟢 | ≥ **son p90 calibré** | propre au récitateur — son rythme habituel, mesuré |
| 🟡 | entre les deux | ses pauses se resserrent par rapport à lui-même |

#### La marge est elle-même une information, disponible AVANT de réciter

Chez l'utilisateur, vert et rouge se confondent : marge **nulle**. Seuls ~10 %
de ses silences franchissent le seuil, contre ~27 % pour la référence. Il est
structurellement plus près du point de rupture — non parce qu'il récite mal,
mais parce qu'il phrase en pauses courtes et fréquentes.

⇒ Le calibrage peut annoncer cette marge d'avance. C'est plus utile que le seuil
lui-même : « ce récitateur a un facteur 2 de sécurité » contre « celui-ci n'en a
aucun ».

⇒ **Et ça interroge la cible de 11 s pour lui.** Viser 7-8 s lui rendrait de la
marge, au prix de plus de blocs — le plateau mesuré va de 75 à 104 blocs pour
2,0-2,7 %, il y a donc de la place. Pour un récitateur à faible marge, la cible
devrait peut-être être le **bord bas** de la zone, pas son centre. *Non mesuré.*

**À sens unique, et gratuitement** : ralentir allonge les pauses, donc pousse la
valeur vers le haut, donc vers le vert. Ralentir ne peut jamais déclencher
d'alerte — ce n'est pas une règle ajoutée, c'est une propriété de la grandeur
mesurée.

### Deux règles de formulation, non négociables

**Le message ne dit jamais « ralentissez » ni « faites une pause ».** Les pauses
dans le Coran sont régies par le **waqf** — `waqf_lazim` et `waqf_awla` sont
deux des 19 classes de la tête tajwid. Pousser à s'arrêter peut pousser à
s'arrêter à un endroit interdit. Le libellé doit être **« je n'arrive plus à
suivre »** : c'est l'app qui a une limite, pas le récitateur.

**Certains passages n'offrent aucun arrêt licite pendant longtemps.** Le rouge
peut alors s'allumer alors que le récitateur fait exactement ce qu'il doit. Une
raison de plus pour que le message porte sur l'app.

---

## 6. Ce qui n'est pas mesuré, et qu'il ne faut pas croire su parole

- **La méthode par durée de segment n'a pas été essayée sur device.** Les
  seuils du §4 sont calculés depuis les percentiles, pas constatés.
- **Le débit d'articulation n'est mesuré nulle part.** Tout ce document parle de
  pauses. Un récitateur qui articule vite mais respire bien ne pose aucun
  problème ; l'inverse en pose un.
- **La résolution des silences est de 80 ms** (pas de l'encodeur). La moitié des
  silences tombe dans le premier casier — la population basse est écrasée. Passer
  au pas du mel (10 ms) donnerait 8× plus de finesse pour un coût négligeable.
- **Un seul calibrage utilisateur, 46,6 s, 44 silences, séparation 6,0.** Moins
  franc que la référence (10,0). Une deuxième session confirmerait.
- **La jauge n'existe pas** : elle est spécifiée ici, pas codée.

---

## 7. Ordre de travail

Révisé après la décision « seuil général » (§5) : l'étape la plus lourde —
appliquer un seuil par récitateur — **disparaît**.

1. **Ramener la pause à 0,40** — une ligne, la mesure le demande déjà
   (device : 3,05 % à 0,35 contre 2,03 / 2,37 / 2,71 % à 0,40).
2. **Ajouter `intervalleHabituel` au calibrage** (compter les silences ≥ seuil).
   Deux lignes, et c'est ce dont la jauge a besoin.
3. **Le test d'admission** : le calibrage annonce si le récitateur entre dans la
   plage avec 0,40. Purement informatif au début — on collecte des cas avant de
   décider quoi faire des exclus.
4. **La jauge**, formule du §5. Reste à arbitrer : voyant permanent, ou
   affichage seulement à partir du jaune ?

Ce qui reste **non mesuré** et ne doit pas être présenté comme acquis : la
méthode par durée de segment n'a jamais tourné sur device, et aucun récitateur
hors plage n'a encore été rencontré — donc la branche « on adapte » du test
d'admission n'a jamais servi.
