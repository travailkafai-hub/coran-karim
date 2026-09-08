# Suivre une priere : correction ChGPT du 7 septembre 2026

Auteur : **ChGPT (ChatGPT / Codex)**. Reference avant modification : `6eb88b7`.
Les fichiers applicatifs suivis etaient propres et deja commites. Aucun modele,
poids, vocabulaire, normaliseur arabe, seuil GOP ou fichier Kotlin n'a ete modifie.

## Besoin retenu

Apres Al-Fatiha, reconnaitre et confirmer la sourate suivante sans demander a
l'imam de recommencer. Apres confirmation, pouvoir souffler le debut du passage
non entendu, meme si le modele a manque les premiers mots. Cette aide n'est pas
un verdict de faute. Elle ne fait pas reculer le curseur et n'oblige pas a
repeter : le localisateur natif continue de rechercher la position a la reprise.

## Causes trouvees dans le code

1. `_identifierParCaptureDediee` arretait le flux continu puis enchainait
   `start(continuous: false)`, trois secondes d'enregistrement et `stop()`.
   La transcription s'effectuait micro arrete. Les textes des prises etaient
   ensuite concatenes ; leur contexte acoustique, lui, n'etait pas reconstitue.
   L'oreille utilise une prise de sept secondes. Les deux parcours n'etaient
   donc pas equivalents, meme s'ils utilisaient le meme modele et le meme index.
2. Un ancien chemin secondaire ignorait les propositions pendant sept secondes
   supplementaires. Il n'est plus utilise pour l'identification dediee.
3. `_onDecrochageV2` retournait a cause de `_confidentMode` dans la sourate cible
   du mode PRIERE : le signal de decrochage n'atteignait pas le souffleur.
4. Le minuteur du souffleur exigeait au moins un mot deja juge. Si le modele
   manquait le debut, l'aide pouvait ne jamais etre armee.
5. Le souffle de passage ne respectait pas l'interrupteur du souffleur et pouvait
   lire un long trou entier. Les fins asynchrones de capture/lecture pouvaient
   aussi relancer une ecoute qui avait ete arretee entre-temps.
6. `startPrayerFollow` remplacait l'etat par une valeur qui reprenait la riwaya
   par defaut. Le test Warsh a egalement reproduit la course de cache QuranApi
   deja decrite par l'audit, provoquee ici par le chargement Fatiha non attendu.

## Changements

### Identification audio continue

- [PrayerIdentificationAudio](app/lib/services/prayer_identification_audio.dart)
  conserve un anneau PCM16 mono 16 kHz, limite a sept secondes. La premiere
  tentative part apres trois secondes d'audio ; la suivante requiert trois
  secondes supplementaires. Ce sont des bornes en octets PCM, pas un minuteur
  qui arreterait le micro.
- Une seule transcription est en vol. L'audio continue d'arriver pendant le
  calcul ; la prochaine tentative prend la fenetre recente complete, sans
  concatener des transcriptions chevauchantes.
- Le verifier expose deux methodes propres a la priere. Pendant cette phase,
  il ne lance pas en parallele l'alignement sur l'ancienne Fatiha. La capture
  continue et son eventuel WAV diagnostic restent actifs. Le suivi ordinaire
  est inchange lorsque cette branche n'est pas active.
- Le WAV temporaire de chaque tentative est supprime en `finally`. Une fermeture
  de l'application pendant l'ecriture peut encore laisser un temporaire, comme
  pour d'autres captures du projet ; ce correctif n'est pas une purge globale.
- Le tampon contient au plus 224 000 octets, plus un instantane independant de
  meme taille maximale. Les copies de travail et le WAV ajoutent leur propre
  cout. Aucun nouveau modele, asset lourd ou paquet n'est ajoute.

### Confirmation, pas choix arbitraire

[confirmedPrayerTarget](app/lib/services/prayer_target_match.dart) distingue
recherche et confirmation : score au moins 0,45, au moins cinq votes de paires,
et avance de 1,3 sur un candidat d'une autre sourate. Plusieurs versets de la
meme sourate ne constituent pas une ambiguite entre sourates. Un meilleur
candidat Al-Fatiha ne devient pas une sourate suivante.

Ces criteres de votes/avance avaient existe dans le projet, puis avaient ete
retires de la capture fixe pour imiter l'oreille. Leur raison ici est explicite :
les premiers instantanes peuvent etre courts et l'utilisateur exige maintenant
une confirmation. Une paire commune peut obtenir un score parfait sans rien
identifier. Aucun seuil de prononciation/GOP n'est assoupli. Un passage ambigu
reste en recherche ; l'ordre suppose des sourates entre rak'ah ne tranche plus
contre l'evidence dans ce nouveau parcours.

La cible n'est affichee comme suivie qu'apres son installation native. Les
identifications tardives sont rejetees si la session, la phase ou la riwaya a
change. Le secours par continuite ne remplace pas une identification active par
la sourate precedente sur la seule base d'un delai.

### Souffleur non contraignant

- Decrochage dans une cible confirmee : emission d'une proposition d'aide, meme
  si aucun premier mot n'a pu etre juge. Pas d'erreur fabriquee et pas de recul.
- Minuteur de confort conserve a quatre secondes, arme des l'arrivee sur la
  cible confirmee. Le texte deja valide n'est pas requis pour proposer l'aide.
- Un meme debut de passage n'est souffle qu'une fois par cycle ; le reglage
  du souffleur est respecte pour le minuteur ET pour les trous signales.
- Contexte court : deux mots avant et trois apres, borne par le verset et par
  les segments disponibles. La longueur totale du trou ne rallonge plus l'aide.
- `soufflerPriere` conserve cible et historique natifs : ni `resetBuffer`, ni
  `v2ReculerAncre`, ni nouvelle cible, ni attente d'une repetition.
- L'ecoute reprend aussi si la lecture echoue, mais pas si l'utilisateur a
  arrete la session ou si une autre session a pris le micro.

**Limite acoustique importante :** le micro reste suspendu pendant la lecture
du haut-parleur, pour ne pas juger la voix du recitateur audio comme celle de
l'imam. Il reprend ensuite avec le localisateur existant. Ce correctif ne
pretend pas separer simultanement les deux voix ni implementer une annulation
d'echo. L'imam n'est pas oblige de repeter, mais ce qu'il dit pendant cette
lecture peut ne pas etre entendu ; le recalage reel doit etre verifie sur appareil.

### Isolation Hafs / Warsh

La riwaya de session est conservee au demarrage, transmise au moteur et utilisee
pour choisir l'audio de correction. Le chargement initial de Fatiha est attendu
avant l'ecoute, ce qui evite la course reproduite dans ce parcours. Les gardes
rejettent un resultat d'identification devenu obsolete apres changement de
riwaya. Les normalisations Hafs et Warsh existantes restent distinctes et intactes.
La course generale de QuranApi dans d'autres parcours reste un sujet de l'audit.

## Verification et supervision

- **143 tests passent** sur les huit fichiers listes ci-dessous. Les nouveaux
  tests exercent le code de production ; les anciens bancs gardent leurs propres
  limites, notamment leurs copies historiques de la decision d'identification.
- Nouveaux cas : fenetre croissante/bornee, reutilisation du buffer source,
  collecte pendant une inference, annulation, erreur puis nouvelle tentative,
  ambiguite, confirmation sans delai additionnel, faible nombre de votes.
- Integration du notifier sur les vrais assets Hafs puis Warsh : identification,
  installation PRIERE, absence de faux verdict au verrouillage, aide sans
  premier mot juge, pas de recul/reset, reprise apres echec de lecture,
  absence de reprise apres stop et rejet d'une identification tardive.
- Test du verifier avec enregistreur simule : meme micro et meme generation
  pendant l'identification. Les tests de garde du micro et de reprise du flux
  restent verts.
- Graphe et consignes `superviseur-recette` consultes : pas de retour au resync
  qui abandonne des mots, pas de texte d'apercu fusionne pour fabriquer des
  preuves, pas de changement de segmentation/jugement du mode CTL.
- Aucun telephone connecte a `adb devices -l`. Pas de recette acoustique live,
  pas de mesure d'un gain x2, pas de verification de l'echo ou de l'endurance.
  La suite complete du projet n'est pas declaree verte par ces tests cibles.

Commande des tests, depuis `app` :

```text
flutter test --no-pub test/prayer_identification_audio_test.dart test/prayer_target_match_test.dart test/prayer_follow_flow_test.dart test/recitation_capture_restart_test.dart test/garde_micro_test.dart test/identification_priere_deterministe_test.dart test/simulation_priere_complete_test.dart test/simulation_priere_limites_test.dart --reporter expanded
```

## Recette appareil restante

Comparer le meme WAV dans l'oreille et dans le suivi de priere, dans la meme
riwaya, en relevant debut de parole, premiere tentative, confirmation et premier
recalage. Tester la Fatiha suivie d'une courte sourate, un depart au milieu d'une
sourate, une pause avant le debut, un debut mal transcrit, un takbir, un long
decrochage, une reprise volontaire et la sortie d'ecran pendant le souffle.
Verifier notamment que l'imam peut continuer apres l'aide sans redire les mots
manques et que le micro ne se rouvre pas apres un arret.

Historique du code remplace : `git show 6eb88b7:app/lib/providers/recitation_provider.dart`.
Le detail historique est aussi conserve dans `SUIVI_PRIERE.md` ; il ne faut pas
confondre ses descriptions de juillet/aout avec le parcours corrige ci-dessus.
