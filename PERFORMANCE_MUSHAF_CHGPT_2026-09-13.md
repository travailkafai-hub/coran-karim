# Performance Mushaf - ChGPT

## Demande et reference

L'utilisateur demande de laisser l'IHM de cote et de corriger la performance.
Reference du code : `8c4e596` (cache de mise en page et sens de tourne,
travail preexistant conserve). Point avant intervention : `30fc708`.
Les modifications graphiques deja presentes dans le workspace ne sont pas
annulees ni poursuivies dans ce correctif.

Les 347/399/456 ms rapportes a la premiere visite sont des mesures fournies
par l'utilisateur, pas des mesures refaites ici. L'ancien cache supprimait
le calcul au retour seulement. Un cache vide executait 12 recherches de
taille, une mesure initiale d'interligne puis 8 recherches d'interligne,
soit 21 evaluations completes sur le thread UI dans un LayoutBuilder.

## Correctifs

### Mesure cooperative, pas de nouvelle typographie

- `mushaf_layout_scheduler.dart` : file commune aux pages. Une seule mesure
  de paragraphe apres chaque frame, priorite a la page visible. Les travaux
  obsoletes sont retires avant execution. Chaque TextPainter est libere.
- `_hauteursSegments` conserve les memes spans, tailles, hauteurs, basmala,
  reserve de diacritiques, largeur exacte et somme de hauteurs. La basmala
  est mesuree dans sa propre tranche quand elle existe.
- Les deux recherches conservent leurs 12/8 iterations, bornes et conditions.
  Aucun changement des textes, du tajwid, des signes waqf ou des pages Hafs/Warsh.
- `MushafMeasuredBlock` maintient le resultat hors du LayoutBuilder. Une
  generation invalide les travaux lors du changement d'entree ou de la
  destruction du widget. Une route masquee ou une app en arriere-plan suspend
  le calcul ; au retour un calcul incomplet peut reprendre depuis le debut.
- Un resultat obsolete ne peut pas remplir le cache ni remplacer le contenu
  d'une autre page. En cas d'erreur, une action Reessayer remplace le chargement.
- Le cache conserve au plus 200 resultats termines ; cle incluant page,
  ecriture, riwaya, tajwid, dimensions exactes et contenu des segments.
  L'arrondi des dimensions a l'entier est retire : une largeur sous-pixel
  peut affecter les retours a la ligne. Couleur du cadre et surlignement audio
  ne modifient pas les metriques et ne declenchent pas de nouveau calcul.

### Anticipation et donnees stables

- `PageView.allowImplicitScrolling` prepare un viewport voisin de chaque cote,
  via le comportement natif de Flutter (cache par defaut d'un viewport).
  La file de mesure donne toujours priorite a la page courante.
  Le sens conditionne a Directionality est conserve.
  Cette option permet aussi les demandes implicites de defilement pour
  l'accessibilite ; ce comportement doit etre inclus dans une future recette.
- `_MushafPageData` conserve le meme Future tant que page et riwaya ne changent
  pas. Une mise a jour du lecteur audio ou du theme ne recharge plus les donnees.
  La cle du FutureBuilder empeche de conserver l'ancien texte lors d'un
  changement de page/riwaya.

### Chemin Warsh isole

- Le decodage et l'indexation de `quran_mushaf_warsh.json` passent dans `compute`
  sur Android. Un decodeur dedie conserve exactement le parsing existant.
- Un seul Future de chargement sert la page, la basmala et les voisins ;
  leurs demandes simultanees ne decodent plus plusieurs fois le meme asset.
- Seuls les index papier Warsh sont publies. Le parsing commun, le chargement
  Hafs, les indexes de recitation et le choix de modele ne sont pas modifies.
- L'index Warsh reste propre a son asset fixe ; il ne remplace jamais un index
  Hafs, meme si la riwaya active change pendant son chargement.

## Graphe

`PageView (courante + voisins) -> Future stable par page/riwaya -> segments`

`contraintes exactes + contenu -> MushafMeasuredBlock -> cache ou recherches`

`recherches -> file prioritaire -> un TextPainter/frame -> resultat complet`

`nouvelle configuration / route cachee / dispose -> invalidation generation`

`asset papier Warsh -> Future partage -> compute -> index papier Warsh`

## Limites et verification

Pas de test execute, pas de navigation ni de capture telephone, conformement
a la demande de l'utilisateur. Analyse statique : aucune nouvelle erreur,
deux avertissements preexistants (_kBoiteBasmala et _pageLignes non utilises).
Compilation debug reussie. Installation de `com.corankarim.coran_karim.dev`
sur le Redmi Note 9 Pro connecte (`f70fd53c`) confirmee par adb (Success).
Application non lancee apres installation ; validation laissee a l'utilisateur.

Cette correction vise d'abord le gel continu et anticipe les pages voisines.
Elle ne supprime pas le cout CPU de la premiere mise en page : le temps total
d'attente d'une page non preparee peut augmenter, puisque les calculs sont
repartis entre les frames. Un TextPainter individuel reste synchrone et peut
encore depasser le budget d'une frame sur un appareil lent. Aucun gain chiffre
ou garantie de fluidite parfaite n'est annonce sans mesure sur appareil.

Les traces `Perf / ChGPT page=... mesure cooperative` indiquent :

- attente : temps ecoule, y compris attente des frames et de la file ;
- calcul : somme du temps des mesures de paragraphes ;
- trancheMax : plus longue mesure individuelle ;
- paragraphes : nombre reel de mesures, basmalas comprises ;
- premierPlan et taille du cache.

Les traces ne contiennent ni audio ni texte recite. Validation ulterieure :
balayages rapides, premiere ouverture, retour, changement de police/riwaya,
rotation, arriere-plan, pages denses et pages a plusieurs sourates, verification
du meme rendu et mesures sur le meme appareil en profile/release.
