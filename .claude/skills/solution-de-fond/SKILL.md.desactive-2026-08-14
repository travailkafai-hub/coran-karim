---
name: solution-de-fond
description: Trouver la solution qui SUPPRIME une classe de défauts au lieu de la contenir. À invoquer avant d'écrire un correctif sur la chaîne de récitation, dès qu'on s'apprête à toucher un seuil, une tolérance, un critère de jugement, ou à ajouter un mécanisme de rattrapage.
---

# Chercher la solution de fond

Ce skill existe parce que le 2026-07-28, en une seule séance, j'ai écrit trois
correctifs qui « marchaient » et dont **deux étaient des palliatifs** — repérés
par l'utilisateur, pas par moi. Il l'a dit ainsi : *« au lieu de chercher des
solutions dans l'architecture, les couches, des solutions pour que le modèle
soit dans les mêmes conditions pour mieux juger, tu es en train de modifier les
critères d'acceptance »*.

`recul-architectural` sert à **sortir d'une boucle** déjà installée. Celui-ci
sert **avant d'écrire la première ligne** : il donne les questions qui séparent
une solution de fond d'un pansement bien commenté.

## Le test des trois questions

Avant tout correctif, y répondre par écrit. Une seule réponse fausse disqualifie.

**1. Est-ce que je déplace un critère d'acceptation ?**

Si le correctif change *ce qui est considéré comme correct* — un seuil, une
tolérance, une règle de fragment, une exemption — ce n'est pas une correction,
c'est un déménagement du problème. Le défaut reste, il devient seulement
invisible dans les logs suivants.

Cas réel : j'ai fait céder la règle de proportion (« entendu × 3 ≥ attendu »)
quand le `normGop` était bon. Ça faisait passer au vert `يُخَـٰدِعُونَ` entendu
`يُ`. Le mot était bien prononcé — mais c'est le juge que j'avais assoupli, pas
la cause traitée.

**2. Est-ce que je mets le modèle dans les conditions où il RÉUSSIT ?**

C'est la question la plus productive du projet. Elle suppose de savoir, par la
mesure, dans quelles conditions le modèle réussit. Sur ce projet, la réponse est
documentée : **hors device, le modèle lit correctement chaque mot dès qu'on lui
donne une fenêtre de 2 à 4 s où le mot n'est pas au bord.**

D'où la question qui suit : *qu'est-ce qui, sur l'appareil, diffère de ces
conditions ?* Elle a directement produit le correctif du contexte droit — le
segment recevait 3 s de contexte à gauche et **rien** à droite, donc le dernier
mot de chaque segment était systématiquement au bord.

**3. Quelle classe de correctifs je n'aurai plus jamais à écrire ?**

Une solution de fond rend une famille entière de bugs impossible. Si la réponse
est « ce cas-ci ne se reproduira plus », c'est un pansement. Si c'est « on n'aura
plus jamais à régler la fenêtre du secours », c'en est une.

## Le préalable : la mesure doit être plus fine que l'effet

**Ne jamais optimiser contre une mesure plus bruitée que le gain cherché.** On y
ajuste alors le bruit, on annonce des gains qui n'existent pas, et on ne sait
même pas dire si l'objectif est atteint.

Mesure du 2026-07-28 : le **même binaire** sur la **même sourate** donnait 1,4 %
puis 4,3 % de mots non verts, les passes allant de 0,0 % à 10,9 %. Toute
conclusion tirée d'une passe unique était donc du hasard.

Avant d'optimiser :

| question | ce qu'on fait si la réponse est non |
|---|---|
| Ai-je répété la mesure au moins 3 fois ? | la répéter |
| L'écart cherché dépasse-t-il l'écart entre deux passes identiques ? | rendre le banc déterministe AVANT tout correctif |
| Le protocole est-il strictement le même d'une passe à l'autre ? | l'automatiser (cf. `benchmark/recette_2tel.sh`) |

Rendre déterministe, ici, veut dire : rejouer un **fichier** au lieu de passer
par haut-parleur → micro — même chemin de code, mêmes blocs de 80 ms, même
cadence temps réel, mais entrée identique au bit près.

## Le juge de paix : confronter au modèle sur l'audio brut

Un mot signalé par l'app n'est une **vraie** erreur que si le modèle échoue lui
aussi quand on lui donne l'audio dans de bonnes conditions. Sinon c'est un faux
positif, et le défaut est dans la chaîne.

    python3 benchmark/verifier_erreurs.py benchmark/recettes/<dossier>...

Résultat du 2026-07-28, sur 125 mots jugés : **8 non verts, 0 vraie erreur**.
Autrement dit, 100 % du taux d'erreur affiché était de l'architecture. Ce chiffre
change la nature du travail : il n'y a rien à préserver dans ces signalements,
tout est à faire disparaître.

Deux pièges de méthode sur cette vérification :

- **balayer plusieurs largeurs de fenêtre.** Une seule ne prouve rien : `عظيم`
  est parfait à 3 s et introuvable à 12 s. Conclure « le modèle n'y arrive pas »
  sur une largeur unique est une faute ;
- **ne jamais écrire « absent » sur un test de sous-chaîne.** Le modèle décode
  souvent une quasi-homophone ou perd une lettre (`قاموا` → `قالوا`,
  `لذهب` → `لهب`). Lire le texte réellement décodé de la zone.

## Les signatures d'architecture, et ce qu'elles imposent

| ce qu'on observe | ce que ça dit | ce qu'il faut faire |
|---|---|---|
| on ajoute un énième seuil | une couche devine une information qu'elle n'a pas | lui **donner** l'information |
| un réglage doit satisfaire deux exigences opposées | objectifs contradictoires sur une même variable | **deux mécanismes**, jamais un meilleur seuil |
| `free ≈ 0` et `forced` effondré | le modèle est sûr de ce qu'il entend, et ce n'est pas ce qu'on aligne | c'est une erreur de **position**, pas de prononciation |
| un mécanisme ne laisse aucune trace | il n'a pas « rarement tourné » : il n'a pas tourné | vérifier dans le CODE que son garde peut être vrai |
| le correctif vit dans une couche plus basse que le défaut | palliatif | remonter à la couche où l'information est détruite |

## Varier le matériau, sinon on ajuste sur un texte

Mesurer toujours sur le même passage revient à corriger **ce** passage. Le
2026-07-28, Al-Baqara donnait 1-4 % et masquait tout ; **Ar-Rahman a
immédiatement fait ressortir 9,4 %** — son refrain revient 31 fois, c'est le
pire cas pour un aligneur. La faiblesse structurelle n'était visible que là.

Prendre au moins un passage à **répétitions** (55), un **long** (2), un
**court** (67, 36).

## Rationalisations à refuser

| ce qu'on se dit | la réalité |
|---|---|
| « le gop est bon, je peux relâcher la règle de texte » | c'est le critère d'acceptation qu'on déplace. Le projet l'interdit |
| « ça marche sur ma session de test » | une passe n'est pas une mesure. Trois, sur trois passages différents |
| « j'ajoute un rattrapage pour ce cas » | un rattrapage répare en aval ce qui casse en amont. Quelle information a été détruite, et où ? |
| « le modèle a du mal sur ce mot » | à vérifier sur l'audio brut avec plusieurs largeurs. Le 2026-07-28, 0 cas sur 8 était réel |
| « j'ajuste le seuil, c'est vite fait » | un seuil réglé à la main est le symptôme n°1 d'une information manquante à cette couche |
| « le banc est bruité mais la tendance est bonne » | si le bruit dépasse l'effet, il n'y a pas de tendance, il y a du hasard |
