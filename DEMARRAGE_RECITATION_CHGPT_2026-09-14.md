# Demarrage sans second toucher - ChGPT - 2026-09-14

## Demande

Une fois une fonction de recitation ouverte, ne plus attendre un toucher
sur le texte pour lancer l'ecoute. Cela inclut les essais de la preparation.
Point Git avant intervention : `6b502b8`, incluant les changements anterieurs
de Claude dans le Coach, sans les annuler.

## Cause

Les essais de PreparationScreen ouvraient KaraokeRecitationScreen sans le
parametre autoDemarrer. Celui-ci etait false par defaut. Les acces Mushaf et
Coach, eux, passaient deja true et forcerModeNormal=true.

Passer simplement le defaut a true aurait ete incorrect : ce drapeau sert
AUSSI a choisir la session de reference du banc, sans les corrections normales.
Le choix du mode ne doit pas changer quand on retire un geste d'interface.

## Modifications

- KaraokeRecitationScreen : demarrage commun et automatique de toute nouvelle
  session en direct, independamment du drapeau historique. Il attend la FIN
  de setupVerses pour sa propre cible. L'ancienne boucle de 250 ms, limitee
  a 15 s, pouvait lire les mots laisses par la session precedente ; elle est
  retiree. La relecture archivee garde son chemin texte-seul et ne demarre pas.
- Protection contre les doubles lancements pendant les attentes asynchrones.
  Les textes demandant un premier toucher ne sont plus affiches au demarrage.
- Verification de la route courante et du premier plan avant le depart et
  pendant la sequence de preparation. Si les donnees finissent de charger
  en arriere-plan, le premier retour au premier plan peut terminer l'ouverture.
  Cela ne redemarre pas une session arretee ou mise en pause volontairement.
- Coach, mode Controle : chaque entree demarre, y compris depuis l'onglet,
  pas seulement apres les paliers. Demarrage et reessai utilisent le meme
  helper. La capture precedente est arretee avant de poser la nouvelle cible.
  Les gardes _controleLance et _aParle sont conserves.
- Ancien RecitationScreen de diagnostic : demarre apres son setup, protege
  les doubles appuis et demande l'arret de la capture a la sortie.

## Parcours deja automatiques

Lecture des paliers de memorisation/enfant : _startRound apres preparation.
Suivre la priere : startPrayerFollow au premier frame.
Recherche vocale : ecoute a l'ouverture de QuranShazamSheet.
Ces trois chemins n'ont pas ete reecrits.

## Limites volontaires

- Le bouton Commencer le test de la fenetre explicative reste present :
  il constitue le choix de lancer la fonction. Aucun second toucher ensuite.
- Autorisations Android, chargement du modele et compte a rebours existant
  restent en place. Automatique ne signifie pas micro pret instantanement.
- Les boutons pause, arret, reprise et reessai restent disponibles. Aucune
  boucle de nouvelle tentative automatique apres un refus de permission.
- Ouvrir un Mushaf pour lire, une archive ou l'accueil ne lance pas de micro.
- Aucun changement des modeles, seuils, alignements ou regles Hafs/Warsh.
- Aucune modification des travaux audio/paliers de Claude en cours.

## Verification

Analyse ciblee : aucune erreur, 36 avertissements/informations preexistants
(deprecations, declarations inutilisees, annotation override deja mal placee).
`flutter build apk --debug` reussi (assembleDebug : 75,7 s).
Installation `adb -s R3CY20XW7TD install -r` : Success, Samsung SM-S931B,
package `com.corankarim.coran_karim.dev`, sans effacement des donnees.
Application non relancee apres installation ; aucune ecoute de test.

Une capture de l'ecran courant du Samsung a ete demandee et effectuee :
`screenshots/chgpt_capture_demarrage_20260914.png`. Elle montre la page
Invocation et partage, pas la recitation. Elle ne prouve donc pas le
fonctionnement du demarrage. Aucune navigation ni recitation de test effectuee.

Recette utilisateur restante : essais Reciter/Tajwid, entree Mushaf/Coach,
controle direct et apres paliers, autorisation refusee puis accordee,
retour pendant chargement, passage en arriere-plan, pause manuelle et archive.
