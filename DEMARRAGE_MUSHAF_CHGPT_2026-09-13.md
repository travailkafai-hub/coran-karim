# Demarrage Mushaf - ChGPT - 2026-09-13

## Demande et cause

Supprimer l'icone centree qui precede la couverture du Mushaf.
Point de retour cible avant modification : `b74d24b`.

- Android 12+ : les themes `values-v31` et `values-night-v31`
  demandaient explicitement `@mipmap/ic_launcher` comme splash.
- Android anterieur : `launch_background.xml` affichait `launch_book`
  au centre, au lieu de la couverture approuvee.
- Flutter attendait les trois initialisations avant `runApp`, ce qui
  prolongeait l'ecran natif. Son premier ecran etait deja une couverture.

## Modification

1. Splash Android 12+ : drawable transparent explicite, pas une valeur nulle
   pouvant laisser Android choisir l'icone du lanceur. Fond `#0C3B2C`,
   identique a celui de la couverture Flutter, en clair comme en sombre.
2. Fond natif avant Android 12 et fond de transition de la fenetre :
   couverture plein cadre, `gravity=fill`, comme le `BoxFit.fill` existant.
   La ressource `drawable-nodpi/launch_cover.webp` est une copie binaire
   de `assets/illumination/mushaf_cover.webp`, sans regeneration d'image.
   Empreinte SHA-256 commune :
   `8f8ededd9b6db73a1b8ee9e69736ee94034834716c5e90488ec8aedda01398a0`.
   Cout source additionnel : 212638 octets, pas de bibliotheque ajoutee.
   Toute future couverture doit actualiser ces deux fichiers ensemble.
3. `main.dart` monte immediatement un sas Flutter avec la couverture seule.
   `CoranKarimApp` et son `ProviderScope` ne sont montes qu'apres la fin
   des memes initialisations : journal, racine audio locale, session media.
   Aucun lecteur ni provider ASR n'est cree pendant cette attente.
4. La session media reste facultative en cas d'echec, comme auparavant.
   Une panne bloquante des autres services laisse une action de nouvelle
   tentative sur la couverture. Une session media deja creee n'est pas
   reinitialisee pendant cette tentative.
5. Le branchement du reglage tajwid natif precede toujours les providers.
   Aucun changement de modele, verdict, alignement, Hafs/Warsh, ni pagination.
   Aucun retard artificiel ou animation supplementaire ajoute.

## Limite de plateforme

Android 12 impose son ecran systeme lors des demarrages a froid/tiedes.
Il n'accepte pas une couverture plein ecran comme fond de ce splash :
un bref fond vert uni sans icone peut donc preceder le premier rendu Flutter.
Le correctif retire l'icone et commence le rendu Flutter sans attendre les
services, mais ne promet ni suppression du temps de demarrage du moteur,
ni disparition de l'animation du lanceur propre au fabricant.

Reference officielle :
https://developer.android.com/develop/ui/views/launch/splash-screen

## Verification

- Identite SHA-256 des deux couvertures verifiee.
- `flutter analyze lib/main.dart` : aucun probleme signale.
- `flutter build apk --debug` : reussi, environ 131 secondes. Avertissement
  existant de migration future Kotlin pour trois plugins ; compilation OK.
- `adb -s f70fd53c install -r .../app-debug.apk` : Success sur Redmi Note 9 Pro,
  Android API 31, package `com.corankarim.coran_karim.dev`. Aucune release
  construite ou installee, aucune desinstallation ni suppression de donnees.
- Aucun test automatise, lancement, navigation ou capture sur telephone :
  l'utilisateur souhaite faire la recette lui-meme.
- A verifier manuellement : lancement a froid et reprise, mode systeme
  clair/sombre, ouverture papier puis retour, lecture d'un audio local.
- Aucun gain de temps chiffre revendique sans mesure.
