# Cadre de lecture - ChGPT

## Demande et sauvegarde

Continuer le style de la couverture sur le cadre du lecteur uniquement,
en tenant compte des themes clair, sepia/Kindle et sombre.
Sauvegarde ciblee avant modification : `9406f92` (etat preexistant des trois
fichiers concernes). Aucun changement de modele ou de chaine ASR.

## Rendu

`mushaf_ornamental_frame.dart` contient un peintre Flutter partage : fond de
bordure, double filet, rinceaux a feuilles symetriques, petits motifs aux coins.
Il s'inspire des ornements de la couverture, sans reproduire sa calligraphie
centrale dans la page de lecture. Aucun asset ni dependance supplementaire.

Trois palettes, priorite sombre > sepia > clair :

- Clair : vert profond, or patine et petits accents or clair.
- Sepia : vert olive attenue et laiton doux, pour rester proche du papier chaud.
- Sombre : vert presque noir et or attenue, sans blanc brillant.

## Branchement et invariants

- Papier : `MushafPageChrome` remplace uniquement son ancien peintre.
  Les formules de padding sont conservees exactement. Le nouveau dessin est
  borne a une bande plus petite que ces reserves, avec centre evide et clip.
  Les pages d'ouverture conservent leurs marges plus larges ; les pages denses
  ont un cadre fin. Une reserve haute etroite ne devient pas une frise epaisse.
- Le choix sepia traverse `_PageMushaf` jusqu'au peintre ; il ne modifie pas
  le fond de page papier, les couleurs du texte ou ses mesures.
- Lecture defilante : couche decorative derriere le contenu et les commandes,
  sans padding nouveau, dans `IgnorePointer` et `RepaintBoundary`.
- Ni pagination, ni polices, ni signes waqf, ni geometrie des bandeaux,
  ni gestes de navigation, ni lecture audio ne sont modifies.
- Le meme cadre est utilisable en Hafs et Warsh : aucune branche de traitement
  linguistique n'est touchee.

## Graphe

`modeSombreProvider / kindleModeProvider -> palette du cadre`

`MushafScreen -> couche decorative -> MushafOrnamentalFramePainter`

`MushafMaquetteScreen -> _PageMushaf -> MushafPageChrome -> meme peintre`

## Verification et limites

Conformement a la demande utilisateur, aucun test, lancement ou screenshot
telephone n'est execute. Compilation Android et installation DEV seulement.
Compilation reussie ; installation dans `com.corankarim.coran_karim.dev`
confirmee par adb (Success). Application non lancee apres installation.

La validation visuelle est a faire par l'utilisateur : trois themes, pages
1/2 puis page dense, menu visible/masque, passage portrait/paysage du papier.
Il s'agit de points a regarder, pas de validations deja effectuees.
Le poids du code compile n'a pas ete mesure par comparaison APK ; seul
l'absence d'asset et de dependance nouveaux est etablie.

## Raccord bandeau / bords (suite)

Capture demandee par l'utilisateur : `screenshots/chgpt_bandeau_actuel.png`,
page 584. Elle montre les cartouches blancs au-dessus du filet et une marge
claire exterieure. Sauvegarde avant correction : `f962ef9`.

- Suppression du `Transform.translate(0, -7)` de l'en-tete : ses cartouches
  reviennent dans la zone qui leur etait deja reservee. Le texte des versets
  et les dimensions de la ligne d'en-tete ne changent pas.
- Les cartouches reprennent fond, filet et encre de la palette du cadre.
  La palette est exposee par le peintre pour eviter trois copies divergentes.
- Les 6 px exterieurs haut/bas passent a l'interieur de `MushafPageChrome`
  via `verticalReserve`. Les anciennes formules calculent toujours sur
  `hauteur - 12`, puis le padding restitue ces 6 px de chaque cote : la zone
  de texte garde la meme taille et la meme position, mais le decor peint
  desormais jusqu'au bord. Le retrait exterieur de 1 px du peintre est supprime.

Capture avant uniquement, sans navigation. Aucun test lance.
Compilation reussie. Installation du raccord NON effectuee : adb retourne
`device R3CY20XW7TD not found`. L'APK compile reste disponible dans
`app/build/app/outputs/flutter-apk/app-debug.apk`.

## Signalement performance : analyse du code, sans nouvelle mesure

L'utilisateur rapporte 347 a 456 ms a la premiere visite d'une page, caches
efficaces uniquement au retour. Ces valeurs ne sont pas une mesure effectuee
par ChGPT dans cette session.

Le cache de `_blocAjuste` conserve les resultats de mesure. Sur un manque :
12 evaluations de taille + 1 evaluation initiale d'interligne + 8 evaluations
d'interligne = 21 appels de `_hauteursSegments`. Chaque appel construit et
met en page un TextPainter par segment, plus la basmala eventuelle, dans un
LayoutBuilder donc sur le thread UI. Le log dit 20 mais omet l'evaluation
initiale d'interligne. Cette instrumentation exclut le dessin du cadre et
l'acces initial aux donnees : elle ne permet pas d'attribuer tout le temps
d'une transition a une seule phase, mais identifie un blocage synchrone.

Autres points releves, non corriges dans le changement graphique :

- Le Future.wait des donnees est recree a chaque build de `_PageMushaf`.
  Cela peut produire des reconstructions supplementaires, meme avec les
  index de donnees deja charges. A stabiliser par page/riwaya.
- Le decodage initial de l'asset papier Warsh reste synchrone apres loadString.
  Il concerne le premier chargement de cet asset, pas 400 ms a chaque page.
- La cle du cache arrondit largeur et hauteur : une difference sous-pixel
  peut changer les retours a la ligne. Une cle exacte serait plus rigoureuse,
  mais sa modification ne resout pas le cout de la premiere mesure.

Piste prioritaire : preparer la page suivante et fractionner les mesures
entre les frames, avec annulation quand la page, la riwaya, les dimensions
ou la police changent, tout en conservant exactement les deux recherches
et les gardes actuelles. Un simple Future ou microtask ne deplace PAS
TextPainter hors du thread UI. Un precalcul synchrone ne ferait que deplacer
le gel. Ne pas reduire arbitrairement les recherches ni supprimer la garde
de hauteur pour gagner du temps au prix de texte coupe.

Aucune correction de performance appliquee ou gain annonce ici. Une mesure
en profile/release sur le meme appareil reste necessaire pour quantifier le
cout reel (les commentaires existants citent un Redmi en debug). Les tests
et manipulations de recette restent suspendus a la demande utilisateur.
