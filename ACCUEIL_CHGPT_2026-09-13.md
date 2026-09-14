# Accueil et miniature Qibla - ChGPT

## Perimetre

Demande : conserver les elements de l'accueil, proposer un agencement plus
soigne, rendre les cinq horaires visibles et ajouter une miniature Qibla utile.
Capture avant : `screenshots/chgpt_accueil_avant_agencement.png`.
Sauvegarde ciblee avant modification : `2aabf9d`. Elle contient l'etat
preexistant des fichiers d'accueil, pas un nouveau correctif ASR.

## Modifications

- `surah_list_screen.dart` : en-tete compact, image du Coran deja presente
  dans les assets, titre arabe contraint pour ne plus sortir de l'ecran.
  Papier blanc, separateurs fins, numerotation discrete et noms arabes conserves.
  Identification, signet unique et acces conditionnel au suivi de priere conserves.
  Chargement asynchrone protege par `mounted`, erreur remise a zero au nouvel essai.
- `home_prayer_panel.dart` : bande pleine largeur pour les horaires, prochaine
  priere mise en evidence, cinq horaires regroupes, acces aux reglages.
  Les heures sont celles du provider existant, pas des donnees de demonstration.
  Les horaires d'une ancienne date ne sont pas presentes comme ceux du jour.
  Au retour visible ou au changement de jour, le panneau utilise le rafraichissement
  existant si la date est perimee. Aucun changement de formule de calcul.
- Compte a rebours : le code genere expose
  `prayerInHoursMinutes(int minutes, int heures)`. L'ancien accueil passait
  `(heures, minutes)`, produisant notamment `dans 33 h 1` au lieu de `dans 1 h 33`.
  Appel corrige, sans modification des traductions generees.
- Miniature : direction calculee par `QiblaService`, orientation issue de
  `flutter_compass`, ouverture de `QiblaScreen` au toucher. Pas d'aiguille
  inventee lorsque position ou cap sont absents. Precision inconnue, negative
  ou superieure a 25 : avertissement, jamais d'etat "aligne" valide.
- `main.dart` : TickerMode uniquement autour de l'accueil dans l'IndexedStack.
  La miniature se desabonne lorsque l'onglet est cache, qu'une route le recouvre
  ou que l'application passe en arriere-plan. Le minuteur suit la meme visibilite.
  Les cinq onglets, leurs libelles et leurs actions restent inchanges.

## Graphe

`HomeScreen -> SurahListScreen -> HomePrayerPanel -> PrayerOverview`

`prayerSettingsProvider -> horaires + position -> PrayerOverview`

`position -> QiblaService + FlutterCompass -> QiblaMiniature -> QiblaScreen`

`TickerMode + ModalRoute + cycle de vie -> abonnement boussole / minuteur`

Pas de connexion nouvelle avec l'encodeur, le forced alignment, le GOP,
les regles de jugement, les textes ou la pagination Hafs/Warsh.

## Verification

- 24 tests dans `app/test/home_prayer_panel_test.dart` : trois langues,
  largeurs 320/390/768, texte x1/x1.8, actions, compte a rebours,
  precision de boussole absente/faible et absence de localisation.
- Analyse statique ciblee : aucun signalement.
- Skill `scenarios-utilisateur` mentionne par CLAUDE.md absent du poste :
  verification manuelle des axes interruption, navigation et indisponibilite.
- Build debug reussi et installe dans `com.corankarim.coran_karim.dev`.
  Capture reelle : `screenshots/chgpt_accueil_apres_agencement.png`.
  Titre complet, cinq horaires, compte a rebours et cadran capteur visibles.
  Un toucher sur la miniature ouvre bien la route Qibla (chargement GPS observe).
  L'utilisateur a ensuite navigue dans le lecteur : recette interrompue pour
  ne pas interferer. Retour depuis la grande boussole et rotation physique
  ne sont donc pas valides par cette session.

## Poids et limites

Aucune nouvelle dependance ni image ajoutee a l'application. Le cadran est
dessine en Flutter, l'icone utilise un asset existant. Ne pas assimiler cela
a une mesure de variation de taille APK, qui reste a mesurer sur builds comparables.
La precision physique de la Qibla depend du magnetometre et de sa calibration ;
les tests de widget ne prouvent pas l'exactitude sur le terrain. Les valeurs
des capteurs, le retour depuis la grande boussole et le changement d'onglet
necessitent aussi une recette reelle.

## Integration de la couverture vert/or (suite)

Apres retour utilisateur, l'image approuvee est maintenant branchee dans
`assets/illumination/mushaf_cover.webp`. Sauvegarde de l'ancienne : `a860160`.
WebP qualite 86, resolution 1024x1536 conservee : 212 638 octets contre
79 854 auparavant (+132 784 octets hors compression APK).
`MushafClosedCover` utilise le vert #0C3B2C et `BoxFit.contain` pour ne pas
etirer le medaillon ni couper le cadre. Le titre Flutter superpose est retire :
la calligraphie est deja dans l'image. Son libelle semantique reste disponible.
Animation, navigation et lecteur sous-jacent inchanges. L'icone Android et
son splash systeme ne sont pas remplaces par cette couverture de lecture.
34 tests couverture/accueil passent ; analyse ciblee sans signalement.
Les 4 tests d'ouverture Hafs/Warsh etaient deja termines lorsque l'utilisateur
a demande d'arreter les tests. Aucun test supplementaire ni manipulation
du telephone pour une recette : l'utilisateur assure la validation visuelle.
Compilation reussie ; installation DEV confirmee par adb (Success).
Application non lancee apres installation, conformement a la demande.

### Cadre plein ecran

Suite au retour utilisateur, passage de `BoxFit.contain` a `BoxFit.fill` :
la couverture occupe toute la surface, sans bandes ajoutees et sans recadrage
des quatre bordures. Ce choix etire aussi le medaillon au ratio de l'ecran.
Les petites marges vertes contenues dans l'image elle-meme restent presentes.
Sauvegarde avant changement : `501f099`. Asset et poids inchanges.
Assertion de test mise a jour, tests non executes a la demande utilisateur.
Compilation reussie, installation DEV confirmee (adb Success).
Application non lancee ; verification visuelle laissee a l'utilisateur.
