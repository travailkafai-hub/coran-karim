# Feuilletage du Mushaf papier - ChGPT - 2026-09-14

## Demande et perimetre

Reproduire le rythme de lecture arabe : page de droite, page de gauche,
puis un feuillet tourne de gauche vers la droite. Une page reste lisible
en plein ecran portrait. Le verrouillage de rotation existant est conserve.
La double page simultanee en paysage n'est pas implementee.

Point Git avant intervention : `9bf5c0b`.
Ce commit sauvegarde l'etat preexistant de `mushaf_maquette_screen.dart`,
y compris les changements precedents ; il n'attribue pas leur auteur a ChGPT.
Les autres fichiers modifies/stages dans le depot n'ont pas ete inclus.

Fichiers de cette intervention :

- `app/lib/widgets/mushaf_leaf_transition.dart` : nouveau rendu du pli.
- `app/lib/screens/mushaf_maquette_screen.dart` : branchement et navigation.
- Le present document.

## Comportement

La paire d'ouverture retenue est 1 a droite / 2 a gauche, conformement au
parcours demande. Ensuite 3/4, 5/6, etc. Cette convention concerne les pages
numerotees du lecteur, pas la couverture externe de demarrage.

| Passage | Mouvement |
| --- | --- |
| 1 -> 2 | Translation douce vers la page de gauche |
| 2 -> 3 | Pli courbe vers la droite, prochaine page decouverte dessous |
| 3 -> 4 | Translation douce |
| 4 -> 5 | Nouveau feuillet |
| 3 -> 2 | Meme pli parcouru a rebours |
| 2 -> 1 | Translation de retour |

Le choix depend des numeros de page, jamais d'un compteur de clics : une
ouverture directe a une page intermediaire conserve la bonne alternance.
Une autre edition qui decalerait les pages en regard devrait adapter cette
convention explicitement ; ce n'est pas une regle universelle deduite du texte.

Au toucher : 340 ms dans une paire, 720 ms entre deux paires. Le balayage
continue d'utiliser le PageView et sa physique existante : ces durees ne
forcent pas la vitesse du doigt. La hauteur initiale du toucher incline le pli.
Un toucher pendant le defilement ne programme pas une seconde avance.
La derniere page n'avance pas vers une page vide et ne reboucle pas sur 1.

L'option systeme de reduction des animations desactive le pli ; le toucher
change alors directement de page. Le balayage reste une navigation native.

## Rendu et sens

L'ancienne rotation plane avec disparition par opacite est retiree.
Le nouveau composant peint un pli stylise en 2D, avec deux bords courbes,
un dos de papier et une ombre legere. Ce n'est pas une simulation physique
3D d'un feuillet complet. Le texte n'est jamais retourne en miroir.

Le PageView conserve `reverse: Directionality.of(context) == TextDirection.ltr`.
Cela donne un axe physique `AxisDirection.left` dans les interfaces francaise
et arabe. La compensation de translation utilise cet axe physique, pas un
second test de langue comme le faisait l'ancienne animation.

Pendant un pli, les deux pages restent stationnaires : leurs masques courbes
complementaires revelent la suivante. Le dos occupe l'espace entre les deux
masques. Le mouvement inverse reutilise exactement la meme geometrie.

References Flutter utilisees : [sens du PageView](https://api.flutter.dev/flutter/widgets/PageView/reverse.html),
[decoupage du rendu](https://api.flutter.dev/flutter/rendering/CustomClipper-class.html).

## Poids, performance et protections

- Aucun asset, photo, police, son, shader externe ou paquet supplementaire.
- Aucune capture bitmap temporaire des 604 pages.
- PageView.builder et preparation des voisines conserves.
- Le controleur invalide la peinture, pas la construction des paragraphes
  a chaque frame ; le contenu possede un RepaintBoundary.
- Les couches de clip sont reutilisees et leurs references liberees a la sortie.
- Aucun changement de texte, harakat, waqf, ligne, borne de page ou source Hafs/Warsh.
- Aucun changement de modele, ASR, alignement, score ou historique de recitation.
- Les cles de cible du tutoriel restent presentes. Ses changements de page
  voisins utilisent cette animation ; un saut lointain est direct pour eviter
  de parcourir et charger toutes les pages intermediaires.
- Les protections du mode apercu contre l'enregistrement de position restent
  en place. Le catalogue du tutoriel de Claude n'est pas modifie ici.

## Verification

Analyse statique des deux fichiers : aucune erreur, deux avertissements
preexistants (`_kBoiteBasmala`, `_pageLignes` inutilises). `git diff --check` OK.
`flutter build apk --debug` : reussi (assembleDebug : 125,1 secondes).
Installation `adb -s R3CY20XW7TD install -r` : `Success`, sur le Samsung
SM-S931B autorise par l'utilisateur, package `com.corankarim.coran_karim.dev`.
Mise a jour sans desinstallation ni effacement des donnees. Application non
ouverte par ChGPT apres installation.

Aucun test automatise, aucune ouverture de l'application et aucune capture
du telephone : l'utilisateur souhaite effectuer lui-meme la verification.
La fluidite et la fidelite visuelle ne sont donc pas annoncees comme mesurees.

Recette manuelle a effectuer : 1/2/3/4/5 puis retour, ouverture directe en page
paire et impaire, interface francaise puis arabe, gestes lents annules et
rapides, derniere page, themes clair/sepia/sombre, option reduction des
animations, sortie pendant le mouvement et navigation depuis le tutoriel.
