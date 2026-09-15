# Ajouts a la preparation de Claude - ChGPT - 2026-09-14

## Perimetre

Point Git avant intervention : `85f6be4` (point vide, les fichiers concernes
etaient deja enregistres). Le projet contient aussi des modifications de
Claude dans le Coach et l'audio : elles ne sont pas retouchees ici.

La proposition retenue reste `PreparationScreen`, avec ses choix reels et
ses essais interactifs. L'ancien `OnboardingScreen` reste desactive. Le
catalogue de visites guidees, le demarrage, le graphisme et les quatre essais
de Claude ne sont pas remplaces.

## Parcours

1. Langue et riwaya : inchange.
2. Ecriture : inchange.
3. Options : inchange.
4. Essais : Tajwid, Reciter, Entrainement, Enchainement, puis Lecture Mushaf.
5. Derniere etape dediee : Apprendre avec mon enfant.

Lecture Mushaf ouvre directement `MushafMaquetteScreen`, page 1 de la riwaya
selectionnee, en plein ecran. Il ne passe pas par la liste de versets.
Retour et signet restent ceux du vrai lecteur.

Le mode enfant possede une etape entiere, une icone famille, les reperes
Ecouter / Repeter / Accompagner et une tuile claire contrastee. Le bouton
Suivant de l'etape d'essais devient Mode enfant, afin de rendre cette
derniere etape visible avant meme d'y arriver.

L'essai enfant ouvre le vrai `CoachScreen` sur Al-Ikhlas (112), avec le
preset enfant existant. Le decoupage par deux mots et le dernier mot isole
eventuel restent ceux de `coach_incremental_repeat.dart` : aucune nouvelle
regle pedagogique ou acoustique n'est inventee dans la preparation.

## Explications

Les tuiles ne portent plus les consignes longues, seulement leur titre et
sous-titre. Leur ouverture montre une boite de dialogue avec :

- titre et consigne lisible, defilable sur petit ecran ;
- croix de fermeture, retour systeme et fermeture par toucher exterieur ;
- bouton explicite Commencer le test.

Fermer la boite n'ouvre aucun essai, ne demande pas le micro et ne change
aucun preset. Le chargement et les permissions eventuelles arrivent apres
confirmation, dans les vrais ecrans. Un verrou evite les doubles ouvertures.
Les boutons de bas de page se reorganisent verticalement si la place manque.

Les nouvelles chaines sont traduites en francais, anglais et arabe dans les
ARB, puis generees avec `flutter gen-l10n`. Aucun nouvel asset ou paquet.

## Isolation du preset enfant

`JudgementOptionsNotifier.withTemporaryPreset` est une nouvelle operation
reservee a cet essai explicite. Elle attend la restauration initiale des
preferences, conserve les options precedentes, applique le preset existant
en memoire et les restitue dans un `finally` apres fermeture de la route,
y compris son animation de sortie.

Pendant cet essai, les changements de ces options ne sont pas persistes.
Une fermeture forcee de l'app laisse donc les preferences adultes intactes.
La persistance ordinaire capture maintenant le JSON avant son attente
asynchrone : une ecriture deja en cours ne peut pas capturer accidentellement
le preset temporaire quelques instants plus tard.

Les options effectives et le garde-fou Hafs/Warsh restent derives par les
providers existants. Aucun seuil, modele, alignement ou algorithme ASR n'est
modifie. Cette isolation concerne les options de jugement, pas tous les
reglages de l'application ni les resultats des sessions.

Les essais restent REELS, comme dans la proposition de Claude : les sessions
peuvent alimenter le Coach et les fonctions audio existantes. Le mode enfant
n'est pas un compte enfant distinct. Aucun resultat n'est simule et aucune
garantie de reconnaissance parfaite n'est annoncee aux parents.

## Verification

Generation des traductions reussie ; `git diff --check` sans erreur.
Analyse ciblee de `preparation_screen.dart` et `judgement_provider.dart` :
aucun probleme signale. `flutter build apk --debug` reussi (115,7 s).
Installation Samsung SM-S931B, serie `R3CY20XW7TD`, via `adb install -r` :
`Success`. Package `com.corankarim.coran_karim.dev`, sans desinstallation
ni effacement des donnees. Application non ouverte par ChGPT.

Aucune navigation, capture ou session de test sur le telephone : l'utilisateur
effectue la recette. Points a verifier : fermeture de chaque explication,
double toucher, retour aux essais, ouverture directe du Mushaf papier,
visibilite de la derniere etape, essai enfant puis retour aux options initiales,
francais/arabe et police systeme agrandie.
