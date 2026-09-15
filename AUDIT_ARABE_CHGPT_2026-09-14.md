# Audit du texte arabe et de sa lisibilite

Auteur : ChGPT (Codex), 14 septembre 2026.

## Demande et methode

Revoir l'arabe a partir de l'utilite des fonctions, et non traduire mot a mot
le francais. Agrandir le texte la ou l'interface arabe dispose de plus de place,
sans changer la pagination du Mushaf papier ni le moteur de recitation.

Point de sauvegarde avant cette passe : `0a6b0bd`.
La correction initiale du titre « اتلُ وكن مصححاً » est deja dans ce point.
Le chantier contient aussi des modifications simultanees de Claude : ce rapport
decrit uniquement les interventions linguistiques et typographiques de ChGPT.

## Perimetre relu

- Les 852 messages de `app/lib/l10n/app_ar.arb`, y compris les anciens ecrans.
- Les titres et explications arabes des parcours de `guides_catalogue.dart`.
- Les libelles arabes integres a Decouvrir et au panneau du guide interactif.
- Les categories, sous-categories et suggestions horaires de `models/dua.dart`.
- Les titres arabes des cinq catalogues `duas_*.dart`, les titres des etapes
  Hajj/Umra, les noms de recitateurs et les libelles arabes presents dans les widgets.

Les citations coraniques et les invocations ne sont pas du texte d'interface a
reecrire. Leur contenu, leurs signes et leurs sources ont ete preserves. Cet audit
n'est ni une verification religieuse des contenus ni une nouvelle expertise ASR.

Le fichier [avant/apres complet](AUDIT_ARABE_CHGPT_2026-09-14.csv) inventorie les
852 messages ARB : cle, statut, arabe precedent, arabe actuel et reference francaise.
213 messages existants sont reformules par rapport au point de sauvegarde ;
6 cles ajoutees pendant le travail concurrent (horaires et pierres de progression)
ont egalement ete relues et conservees. Elles ne sont pas attribuees a ChGPT.
Les textes deja
appropries ne sont pas reecrits artificiellement. Les textes integres directement
au Dart sont visibles dans le diff : 41 lignes du catalogue de guide et 7 libelles
de categories/suggestions, ainsi que les formulations de Decouvrir.

## Principales corrections

| Probleme | Formulation retenue / intention |
| --- | --- |
| « Reciter et devenir correcteur » | `تلاوة مع التصحيح` : l'utilisateur recite, l'application fournit une aide. |
| Confusion entre entrainement et jeu | `التدرّب على الحفظ` pour ecouter/repeter ; `لعبة تسلسل الكلمات` pour choisir le mot suivant. |
| Controle traduit par surveillance | `اختبار الحفظ`, et non `المراقبة`. |
| Imitation decrite comme une conversation | `ردّد مع القارئ` : repeter avec la voix du recitateur. |
| Verdicts contestes confondus avec les regles religieuses | `التقييمات المعترض عليها`, reserve aux evaluations de l'application. |
| « Mot couvert », « section acquise » | Mots recites, progression du passage, mots a revoir. |
| « Sans blocage » traduit comme une interdiction | `المتابعة دون إلزام بالإعادة` : pas d'obligation de repeter. |
| Alif mal orthographie dans le reglage Bluetooth | Phrase explicite sur l'utilisation du microphone du telephone. |
| Meme forme pour 1, 2, 3 et 11 | Formes ICU arabes pour jours, mois, annees, erreurs, enregistrements et compteurs. |
| Certitudes excessives sur la prononciation | Resultats presentes comme des evaluations automatiques, susceptibles d'erreur. |
| Mode enfant decrit mot par mot | Description des groupes de deux mots, et du dernier mot isole en cas de nombre impair. |
| Introduction du tajwid Warsh contradictoire | Indication de l'indisponibilite du controle tajwid Warsh dans cet ecran, sans annoncer une substitution par Hafs. |
| Reseau decrit comme exclusivement audio | Mention du chargement de contenus, des recitations et des radios. |
| Reperes fragiles du tutoriel | Noms des outils plutot que « bouton a droite » ou nombre de polices fige. |

### Sens confronte au code

- `coach_incremental_repeat.dart`, `_finsUnite` : groupes de deux mots pour enfant.
- Meme fichier, `_currentWindow` : repetition cumulative depuis le debut de l'ayah.
- `judgement_options.dart`, presets : le mode enfant assouplit l'evaluation ; cela
  ne signifie pas qu'une confusion de lettres est religieusement correcte.
- `preparation_screen.dart` : entrees distinctes vers recitation, memorisation,
  jeu et lecture papier ; instructions dans une fenetre fermable.
- `prayer_follow_screen.dart` : texte de reprise distinct de l'etat d'ecoute.
- `quran_api.dart`, `mp3quran_api.dart` et les radios : certains contenus
  necessitent Internet. Le texte ne doit pas promettre une application sans reseau.
- `dua_card.dart` : source, traduction et merite en francais sont caches en arabe.

## Lisibilite

Pas de grossissement global de MediaQuery et pas de remplacement des polices.
Les reglages d'accessibilite du systeme restent en vigueur.

| Surface | Modification en arabe seulement |
| --- | --- |
| Lecture continue, `VerseTile` | Base 26 -> 30, toujours multipliee par le reglage utilisateur. |
| Versets explicitement scindes | Base conservee ; pas de changement de decoupage. |
| Mushaf papier | Aucun changement de taille, de cadre ou de pagination par cette passe. |
| Carte d'invocation | Titre 16 -> 20 ; texte 22 -> 26, sans traduction/translitteration affichee. |
| Preparation | Titres, sous-titres et consignes plus grands ; cartes extensibles et listes defilantes. |
| Guide interactif | Texte 13 -> 15 ; panneau deja defilant et boutons disposes en Wrap. |
| Decouvrir | Texte principal 14 -> 16. |
| Tuiles de reglages | Titres 13 -> 15 ; sous-titres 11 -> 14. |

`AppTheme.readableUi` applique +2 points, un minimum de 14 et un interligne
minimal de 1,55 sur les surfaces qui l'utilisent. La taille ne depend pas de la
largeur de l'ecran. L'espacement des lettres arabes est nul pour ne pas perturber
la lecture. Les boutons compacts et les indicateurs ne sont pas tous agrandis.

Les listes/colonnes peuvent accueillir des lignes supplementaires. Cela ne
constitue pas une validation visuelle sur tous les appareils : verifier notamment
les petits ecrans et les grandes tailles d'accessibilite pendant la recette manuelle.

## Problemes identifies, non masques

1. **Reglage sans effet** : `repeatWindowSizeProvider` est encore expose dans
   `tajwid_rules_screen.dart`, mais le moteur cumulatif ne le lit plus. Le texte
   arabe l'identifie comme ancien et sans effet sur l'entrainement actuel.
   La suppression du controle ou son retrait dans toutes les langues est une
   decision fonctionnelle distincte, non effectuee ici.
2. **Ancien nombre de mots adulte** : provider conserve mais non utilise par le
   decoupage actuel. Son message conserve ne prouve pas une fonction active.
3. **Contenu religieux non localise** : le modele `Rite` ne possede que des titres
   arabes, pas des champs arabes pour toutes ses instructions. Les sources/merites
   d'invocations sont egalement encore francais. Ils demandent une localisation
   editoriale distincte avec validation des sources, pas une reformulation improvisee.
4. **Textes dynamiques** : noms ou contenus provenant d'API et explications generees
   ne peuvent pas tous etre audites a l'avance a partir des chaines du depot.
5. **Francais/anglais** : hormis le titre et la consigne de recitation corriges avant
   cette passe, cette revision porte sur l'arabe. Les formulations historiques
   d'autres langues peuvent encore comporter les memes approximations fonctionnelles.
6. **Travail concurrent** : des changements d'onboarding et de lecteur ont ete
   observes pendant la passe. Ils sont conserves, sans etre attribues a ChGPT.

## Controles

- `flutter gen-l10n` : generation reussie apres les reformulations et les pluriels.
- `dart run tool/audit_arabic_copy.dart` : 852 cles, arguments attendus et citations
  protegees controles ; generation du CSV complet. Ce controle structurel ne
  remplace pas la relecture linguistique ni le parseur ICU de Flutter.
- `flutter analyze` cible : aucune erreur, cinq diagnostics restants : trois
  usages existants de `activeColor` deprecie, `_NoiseSuppressTile` inutilise et
  un import `foundation.dart` devenu inutilise dans le travail concurrent sur
  Preparation. Ces points sans rapport avec la traduction ne sont pas nettoyes ici.
- `git diff --check` : aucun probleme d'espacement detecte.
- Aucun test audio, parcours automatique ni changement de configuration sur le
  telephone. Pas de modification ChGPT des poids, seuils, confusions de lettres,
  normalisation Hafs/Warsh ou logique de validation pendant cet audit.

Compilation `flutter build apk --debug --no-pub` reussie en 106,4 secondes.
Installation `adb install -r` reussie sur le Samsung SM-S931B (`R3CY20XW7TD`),
package DEV `com.corankarim.coran_karim.dev`. Application non ouverte par ChGPT
apres installation. La validation visuelle et les parcours sont laisses a l'utilisateur.

Le CSV et l'outil d'audit restent des fichiers de developpement, hors assets de
l'application : aucun paquet de polices, image ou modele n'a ete ajoute pour cette passe.
