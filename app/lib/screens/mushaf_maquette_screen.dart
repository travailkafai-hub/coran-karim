import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/riwaya.dart';
import '../models/verse.dart';
import '../providers/player_provider.dart';
import '../providers/app_settings_provider.dart';
import '../services/mushaf_lignes_service.dart';
import '../services/mushaf_opening_position.dart';
import '../services/diagnostic_log.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../theme/app_theme.dart';
import '../widgets/mushaf_page_chrome.dart';
import '../widgets/mushaf_ornamental_frame.dart';
import '../widgets/choix_ecriture_sheet.dart';
import '../widgets/tajweed_text.dart';

/// Vue page « vrai mushaf », ouverte directement depuis l'icone de la lecture.
///
/// ── CE QUE CET ÉCRAN EST, ET N'EST PAS ────────────────────────────────────
/// C'est un BANC DE COMPARAISON, pas une fonctionnalité livrée. Il ne
/// remplace rien : l'affichage actuel (`mushaf_screen.dart`) n'est pas touché
/// d'une ligne. Accès par recette uniquement (`--es recette mushaf`), donc
/// invisible pour l'utilisateur final tant que rien n'est validé.
///
/// ── DEUX MANQUES CORRIGÉS APRÈS LE PREMIER ESSAI (2026-09-01) ─────────────
/// Retour utilisateur sur la v1 de cette maquette : « il se met pas en plein
/// écran, je n'arrive pas à passer à d'autres pages ». Les deux touchaient au
/// cœur du sujet, pas au détail :
///   1. PLEIN ÉCRAN — un mushaf qu'on regarde entre une barre d'état et des
///      boutons système ne donne pas l'impression d'une page imprimée. Mode
///      immersif, restauré à la sortie.
///   2. BALAYAGE — un mushaf se FEUILLETTE. Des flèches minuscules coincées
///      sous les boutons Android ne sont pas seulement peu pratiques, elles
///      sont le mauvais geste. `PageView` sur les 604 pages, dans le sens de
///      lecture arabe.
/// Les contrôles n'apparaissent qu'au toucher, puis s'effacent : hors
/// navigation, il ne reste que la page.
///
/// ── RÈGLE ABSOLUE RESPECTÉE ICI ───────────────────────────────────────────
/// Le texte coranique n'est JAMAIS modifié pour les besoins de la mise en
/// page. Aucun `tatweel` (ـ U+0640) n'est inséré pour étirer les mots, alors
/// que c'est la technique classique de justification arabe : ce serait
/// ajouter des caractères au texte révélé. La justification passe uniquement
/// par l'espacement natif, et l'ajustement par la taille de police.
class MushafMaquetteScreen extends ConsumerStatefulWidget {
  final int pageInitiale;
  final SystemUiMode modeSystemeAuRetour;

  const MushafMaquetteScreen({
    super.key,
    this.pageInitiale = 1,
    this.modeSystemeAuRetour = SystemUiMode.edgeToEdge,
  });

  @override
  ConsumerState<MushafMaquetteScreen> createState() =>
      _MushafMaquetteScreenState();
}

/// ── LE BALAYAGE DEMANDAIT UN GESTE TROP LONG (2026-09-04) ─────────────────
///
/// Constat utilisateur : « je scrolle pour le balayage mais il faut vraiment
/// que je fasse un long scroll ».
///
/// `PageView` tranche entre deux gestes. Un LANCER tourne la page quelle que
/// soit la distance parcourue -- mais seulement si la vitesse dépasse
/// `tolerance.velocity`. En dessous, le geste est lu comme un GLISSEMENT, et
/// la page ne bascule que si le doigt a franchi la MOITIÉ de l'écran.
///
/// PREMIÈRE TENTATIVE, INSUFFISANTE : diviser les deux seuils de VITESSE par
/// 3. Retour utilisateur : « le scroll ne marche pas aussi bien, il résiste
/// encore pour basculer ». Normal -- ça ne touchait que la porte d'entrée du
/// lancer, jamais le seuil de DISTANCE, qui est le vrai verrou. Un geste posé
/// restait sous la vitesse ET sous la demi-page : rien ne basculait.
///
/// CE QUI EST FAIT MAINTENANT : `createBallisticSimulation` est réécrit, avec
/// les trois cas explicites au lieu de l'arrondi unique de Flutter :
///   geste franc  -> la DIRECTION décide, la distance ne pèse plus ;
///   geste lent   -> bascule dès 28 % de la page franchie (au lieu de 50 %) ;
///   geste infime -> page la plus proche, comme avant.
///
/// POURQUOI 28 % ET PAS MOINS. Le faux positif est le risque symétrique, et
/// cet écran tourne DÉJÀ la page au simple tap : trop bas, un doigt qui hésite
/// ferait sauter deux pages. 28 % laisse passer le geste posé et rejette le
/// tremblement.
class _BalayagePage extends PageScrollPhysics {
  const _BalayagePage({super.parent});

  @override
  _BalayagePage applyTo(ScrollPhysics? ancestor) =>
      _BalayagePage(parent: buildParent(ancestor));

  /// Seuil du LANCER (défaut `kMinFlingVelocity` = 50 px/s).
  @override
  double get minFlingVelocity => 5.0;

  @override
  Tolerance toleranceFor(ScrollMetrics metrics) {
    final t = super.toleranceFor(metrics);
    return Tolerance(
      distance: t.distance,
      time: t.time,
      velocity: t.velocity / 10,
    );
  }

  /// Fraction de page à franchir pour que la bascule se fasse, quand le geste
  /// est trop lent pour compter comme un lancer. Flutter exige 0,5 -- la
  /// MOITIÉ de l'écran.
  static const double _fractionBascule = 0.28;

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // Bords de liste : on laisse le parent gérer le rebond.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tol = toleranceFor(position);
    final largeur = position.viewportDimension;
    if (largeur <= 0) return super.createBallisticSimulation(position, velocity);

    final page = position.pixels / largeur;
    final depart = page.floorToDouble();
    final avance = page - depart; // 0 -> page de départ, 1 -> page suivante

    double cible;
    if (velocity.abs() > tol.velocity) {
      // Geste franc : la DIRECTION décide, la distance n'a plus à peser.
      cible = velocity > 0 ? depart + 1 : depart;
    } else if (avance >= _fractionBascule && avance <= 1 - _fractionBascule) {
      // Geste lent mais net : on suit le sens dans lequel le doigt a poussé.
      cible = avance >= 0.5 ? depart + 1 : depart;
    } else {
      // Trop peu : on revient à la page la plus proche (comportement d'avant).
      cible = page.roundToDouble();
    }

    // ── UN GESTE NE TOURNE JAMAIS PLUS D'UNE PAGE (2026-09-04) ──────────
    //
    // DEFAUT QUE CE CORRECTIF A LUI-MEME INTRODUIT, vu au banc : deux
    // balayages faisaient passer de la page 79 a la page 89 -- CINQ pages par
    // geste. La cible calculee etait pourtant bonne ; c'est la simulation qui
    // emportait, lancee avec la vitesse brute du doigt.
    //
    // On borne donc la cible aux deux pages qui encadrent la position, et la
    // vitesse a une largeur d'ecran par seconde. Un balayage franc tourne une
    // page, un balayage tres franc tourne une page aussi -- c'est ce que fait
    // un mushaf de papier, et c'est ce qu'on attend d'une page qu'on lit.
    cible = cible.clamp(page.floorToDouble(), page.ceilToDouble());
    final pixels = (cible * largeur)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (pixels == position.pixels) return null;
    final vBornee = velocity.clamp(-largeur, largeur);
    return ScrollSpringSimulation(spring, position.pixels, pixels, vBornee,
        tolerance: tol);
  }
}

/// Interligne du texte de la page (2026-09-02).
///
/// 2,0 auparavant. Retour utilisateur, capture d'un mushaf de reference a
/// l'appui : « le rendu visuel est plus joli et plus lisible, on dirait les
/// lettres plus grandes ».
///
/// Le mecanisme en cause n'est PAS la taille de police -- elle est calculee
/// pour remplir la page -- mais l'INTERLIGNE, qui consomme la hauteur avant
/// elle. A 2,0, chaque ligne occupait le double de sa hauteur de glyphe : la
/// recherche binaire trouvait donc une police plus petite pour tenir. A 1,72,
/// la meme page rend des lettres nettement plus grandes, en gardant l'air
/// qu'exige un texte a diacritiques (les harakat montent et descendent hors
/// du corps de la lettre : trop serrer les ferait se toucher).
///
/// Le plafond de la recherche binaire passe de 46 a 72 dans la foulee : a
/// 46 il devenait atteignable sur les pages courtes, et bridait alors la
/// taille au lieu de laisser le remplissage decider.
/// 1,72 : les harakat arabes montent et descendent HORS du corps de la lettre.
/// A 1,42 (essai du 2026-09-03), avec une police plus grande, celles d'une
/// ligne touchaient celles de la suivante -- « tout est melange », « regression
/// sur le texte ». L'interligne d'un texte a diacritiques ne se regle pas comme
/// celui d'un texte latin : il lui faut l'air que les signes occupent.
/// Trace en ROUGE le contour de chaque zone de la page (en-tete, bloc de
/// texte, bandeau de sourate, pied). Outil de diagnostic d'affichage, jamais
/// destine a l'utilisateur final -- a remettre a `false` apres usage.
///
/// Pose le 2026-09-04 sur demande : « j'ai l'impression que tu superposes des
/// zones ; entoure les zones ou tu mets le texte avec du rouge ». Une capture
/// montre alors ce qu'aucune lecture de code ne montre : ou chaque bloc
/// commence, ou il finit, et ce qui deborde du sien.
const bool kZonesDebug = false;

const double _kInterligne = 1.72;

/// Entoure [enfant] d'un filet rouge quand [kZonesDebug] est actif.
Widget _zone(Widget enfant, Color couleur) => kZonesDebug
    ? DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: couleur, width: 1)),
        child: enfant,
      )
    : enfant;

/// Hauteur de la ligne de basmala, en multiples de la taille de police.
///
/// 1,30 : la place d'un glyphe et de ses diacritiques, pas davantage. Elle ne
/// suit PAS `_kInterligne` -- et surtout pas l'interligne élargi des pages peu
/// remplies, qui montait jusqu'à 2,45 et repoussait la basmala au milieu d'un
/// vide de 110 px (« le début commence trop bas », 2026-09-04). C'est une
/// ligne isolée, elle n'a pas à respirer comme un paragraphe.
const double _kBoiteBasmala = 1.30;

/// Réserve sous la dernière ligne, en fraction de la taille de police.
///
/// ── MESURÉE, PLUS DEVINÉE (2026-09-04) ───────────────────────────────────
///
/// `height: 1.72` est imposé à toutes les écritures : `TextPainter` mesure donc
/// 1,72 × taille par ligne pour chacune. Mais les glyphes sont peints selon les
/// métriques de LEUR police, et une police dont l'ascender+descender dépasse
/// 1,72 em déborde de la ligne qu'on lui alloue. Amiri, mesurée dans son
/// fichier : 1,76 em (hhea), jusqu'à 2,76 (OS/2) -- aucune marge. Bouazzi
/// Maghribi : 1,40 / 1,52 -- de la marge à revendre.
///
/// PREMIÈRE VERSION, ET SA CRITIQUE : une table écrite à la main, `Amiri` à
/// 1,05 et 0,5 pour le reste. L'utilisateur l'a refusée à raison -- « ton
/// programme est censé fonctionner sur différents modèles, j'ai un doute
/// là ». Les 22 autres écritures viennent de Google Fonts, ne sont pas sur le
/// disque, et n'ont jamais été mesurées : la table les couvrait par un chiffre
/// choisi pour d'autres. La première d'entre elles qui a des métriques
/// généreuses aurait coupé sa dernière ligne, sans que rien ne l'annonce.
///
/// CE QU'ON FAIT MAINTENANT : on demande à Flutter, pour l'écriture RÉELLEMENT
/// affichée, quelle hauteur une ligne prend SANS contrainte d'interligne
/// (`height: null`, donc les métriques propres de la police). L'écart avec la
/// ligne imposée est exactement ce qui déborde. Aucune police n'est nommée, et
/// une écriture ajoutée demain est couverte sans qu'on touche à ce code.
///
/// Le résultat est borné à [0,4 ; 1,6] : en dessous on n'absorbe plus rien, et
/// une valeur aberrante (police de secours pas encore chargée, métriques
/// exotiques) ne doit pas réduire la page à une ligne.
/// Mise en page MESUREE d'une page, retenue pour ne pas la recalculer.
/// Cf. le long commentaire dans `_blocAjuste`, qui porte le pourquoi et la
/// mesure. Clé : page, écriture, riwaya, tajwid, contraintes, nb de segments.
final _cacheMiseEnPage =
    <String, ({double taille, double interligne, List<double> hauteurs})>{};

/// Au-delà, la plus ancienne entrée est évincée. 200 pages couvrent largement
/// une session de lecture continue (on revient presque toujours sur ce qu'on
/// vient de quitter) sans laisser la carte grandir indéfiniment.
const int _kMaxPagesEnCache = 200;

final _cacheReserve = <String, double>{};

double _reserveBasMesuree(String ecriture) {
  final connu = _cacheReserve[ecriture];
  if (connu != null) return connu;
  const taille = 40.0;
  // Un échantillon qui empile ce qui monte et ce qui descend : madd, shadda,
  // hamza portée, kasra, et le médaillon de fin de verset.
  const echantillon = 'لَّآ أُو۟لَـٰٓئِكَ ﴿١﴾ بِسْمِ';
  final base = ecriturePour(ecriture);
  double hauteur(double? interligne) {
    final p = TextPainter(
      text: TextSpan(
        text: echantillon,
        style: styleEcriture(base,
            taille: taille, interligne: interligne, graisse: FontWeight.w600),
      ),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    final hauteur = p.height;
    p.dispose();
    return hauteur;
  }

  // `height: null` -> la police décide ; l'écart avec la ligne imposée est ce
  // qui dépasse du cadre alloué.
  final naturelle = hauteur(null) / taille;
  // 0,65 et non 0,35 (2026-09-04) : à 0,35 la page 562 (Al-Mulk) rognait
  // encore le bas des jambages de sa dernière ligne -- vérifié à l'écran, pas
  // déduit. La hauteur naturelle rendue par `TextPainter` couvre l'ascender et
  // le descender DÉCLARÉS ; les diacritiques coraniques empilées descendent
  // au-delà, et cette marge-là ne se lit dans aucune métrique.
  final reserve = (naturelle - _kInterligne + 0.65).clamp(0.4, 1.6);
  _cacheReserve[ecriture] = reserve;
  return reserve;
}

/// Charte du mushaf de reference, RELEVEE sur sa capture (2026-09-02) et non
/// choisie a l'oeil : extraction des couleurs par saturation, mesure des
/// bordures en pixels. Cf. le script `charte_reference.py` du scratchpad.
class _Charte {
  /// Filet fonce qui souligne le cadre.
  static const filet = Color(0xFF1A5B56);

}

/// Police de la page. MESURE du 2026-09-02, capture contre capture :
/// la reference (scan d'un mushaf imprime) couvre 15,1 % de pixels sombres,
/// notre rendu Amiri en poids normal seulement 5,0 % -- trois fois moins
/// d'encre, d'ou « les lettres ne sont pas aussi grasses et visibles ».
///
/// `scheherazadeNew` est plus pleine qu'Amiri a taille egale, et w600 epaissit
/// encore le trait. C'est la meme famille que le reste de l'app pour l'arabe
/// (cf. `main.dart`), donc aucune police supplementaire a embarquer.
/// ⚠️ `amiriQuran` ET NON `scheherazadeNew` (2026-09-03).
///
/// Defaut signale : « les chiffres ne sont plus dans le dessin ». Le medaillon
/// de fin de verset est le caractere U+06DD, qui doit ENGLOBER les chiffres
/// qui le suivent -- c'est une propriete de la POLICE, pas du texte. Avec
/// scheherazadeNew, le medaillon se dessinait vide et le numero s'imprimait a
/// cote : « ۝ ١٠٥ » au lieu du numero encercle.
///
/// `amiri` (standard) : elle compose U+06DD correctement, contrairement a
/// `scheherazadeNew`.
///
/// ⚠️ CETTE PHRASE EST INEXACTE, mesuree telle le 2026-09-03 et conservee pour
/// la trace : AUCUNE police ne « compose » U+06DD. Le caractere est de
/// categorie Unicode `Cf`, aucune des 14 polices essayees n'a de regle GSUB le
/// liant aux chiffres, et toutes ont une avance d'environ un cadratin -- le
/// signe se pose donc A COTE du numero. Ce qui differe, c'est le dessin et le
/// calage du glyphe. Le medaillon est desormais rendu en Amiri quelle que soit
/// l'ecriture de la page (cf. `_spansCanoniques`), ce qui rend le point sans
/// objet pour le choix de police.
///
/// ⚠️ NE PAS remettre `amiriQuran` : essayee le 2026-09-03, elle rend les
/// HARAKAT EN ROUGE -- c'est une police a glyphes colores (COLR/CPAL), pensee
/// pour un mushaf ou les signes sont teintes. Sur une page qui porte deja la
/// coloration TAJWID, deux systemes de couleur se superposent et plus rien
/// n'est lisible : le rouge d'une fatha devient indistinguable du rouge d'un
/// madd obligatoire.
///
/// L'Amiri standard etait deja la au depart, avec 5,0 % d'encre seulement --
/// mais la cause etait l'INTERLIGNE (2,0) et le poids (normal), pas la
/// famille. A 1,42 et w600 elle rend bien plus dense, medaillons compris.
/// `interligne` : par defaut la valeur de reference, mais la vue Page le
/// RELEVE pour consommer le reliquat de sa dichotomie (cf. `_blocAjuste`).
/// Toujours vers le haut -- le baisser rapprocherait les harakat de la ligne
/// suivante, defaut mesure et rejete le 2026-09-03.
///
/// `famille` : nom Google Fonts de l'ecriture choisie (cf.
/// `policeMushafPageProvider` et `kEcrituresMushaf`). Defaut `Amiri` -- le
/// rendu d'origine, que la consigne du 2026-09-03 demandait de ne pas changer
/// tant qu'aucun autre choix n'est fait.
///
/// `getFont` et non `GoogleFonts.amiri(...)` : le nom vient d'un reglage, il
/// ne peut donc pas etre un appel de methode ecrit en dur. Une famille inconnue
/// ferait lever `getFont`, d'ou la liste FERMEE de `kEcrituresMushaf` -- on n'y
/// ajoute une police qu'apres avoir verifie sa couverture des caracteres
/// coraniques.
TextStyle _policePage({
  double? taille,
  Color? couleur,
  double interligne = _kInterligne,
  String famille = 'Amiri',
}) => styleEcriture(
  ecriturePour(famille),
  taille: taille,
  interligne: interligne,
  graisse: FontWeight.w600,
  couleur: couleur,
);

class _MushafMaquetteScreenState extends ConsumerState<MushafMaquetteScreen> {
  static const _kPages = 604;

  late final PageController _ctrl = PageController(
    initialPage: widget.pageInitiale.clamp(1, _kPages) - 1,
  );

  /// ── LE LIEN ENTRE LES DEUX MUSHAF N'ALLAIT QUE DANS UN SENS (2026-09-04) ─
  ///
  /// Demande utilisateur : « il faut garder le lien entre le mushaf papier et
  /// le mushaf, comme on peut faire du marquage de page ; il n'y a qu'un seul
  /// sens actuellement ».
  ///
  /// L'écran de lecture passait bien sa page au papier (`pageInitiale`), mais
  /// rien ne revenait : on pouvait tourner vingt pages ici, le retour rendait
  /// la liste exactement où on l'avait laissée. Les deux vues du MÊME texte
  /// divergeaient dès qu'on en utilisait une.
  ///
  /// On mémorise donc la page réellement lue, et on la rend au `pop`. La page
  /// de départ compte : quelqu'un qui entre puis ressort sans feuilleter doit
  /// retrouver sa place, pas être renvoyé ailleurs.
  late int _pageLue = widget.pageInitiale.clamp(1, _kPages);

  /// Premier verset de la page affichee -- la cible du signet (2026-09-12).
  ///
  /// La vue papier navigue par PAGE, le signet du projet se pose sur un
  /// VERSET (`MarquePagesNotifier.cle(sourate, verset)`). Marquer le premier
  /// verset de la page est ce qui permet d'y revenir : c'est la page qu'on
  /// veut retrouver, pas une ligne precise.
  ///
  /// Charge a l'ouverture puis a chaque changement de page. `fetchVersesByPage`
  /// sert deja la page affichee juste a cote, donc cet appel retombe sur le
  /// meme cache -- pas de second acces reseau.
  Verse? _premierVersetPage;

  Future<void> _chargerPremierVerset() async {
    final page = _pageLue;
    final warsh = ref.read(riwayaProvider) == Riwaya.warsh;
    try {
      final v = warsh
          ? await QuranApi.fetchWarshMushafVersesByPage(page)
          : await QuranApi.fetchVersesByPage(page);
      // La page a pu changer pendant le chargement : ne pas ecraser la cible
      // d'une page qu'on ne regarde plus.
      if (!mounted || page != _pageLue) return;
      setState(() => _premierVersetPage = v.isEmpty ? null : v.first);
      if (v.isNotEmpty) {
        // ChGPT: persist the actual paper page without changing verse IDs,
        // manual bookmarks, or the ASR's Hafs/Warsh numbering.
        final position = await lireDernierePositionLecture();
        if (!mounted || page != _pageLue ||
            warsh != (ref.read(riwayaProvider) == Riwaya.warsh)) {
          return;
        }
        await MushafOpeningPosition.save(
          warsh ? Riwaya.warsh : Riwaya.hafs, page, position,
        );
      }
    } catch (e) {
      DiagnosticLog.log('Lecture', 'memorisation page mushaf impossible : $e');
      // Le signet est un confort : s'il ne peut pas cibler, il se desactive,
      // il ne fait pas echouer l'affichage de la page.
    }
  }

  /// ── LE DECALAGE A L'OUVERTURE (2026-09-05) ────────────────────────────
  ///
  /// Constat utilisateur : « a l'ouverture, avant le plein ecran, il y a un
  /// probleme d'affichage, il y a un overlay de pixels ». Capture prise en
  /// rafale pendant la transition : la page apparait DECALEE vers la droite,
  /// le cadre deporte et le texte debordant a gauche.
  ///
  /// CAUSE. `SystemChrome.setEnabledSystemUIMode(immersiveSticky)` est demande
  /// des `initState`, mais le systeme met quelques images a retirer ses barres.
  /// Le premier rendu se fait donc a l'ANCIENNE taille : la dichotomie calcule
  /// une police et des hauteurs pour un ecran plus petit, puis l'ecran
  /// s'agrandit et tout se recale sous les yeux.
  ///
  /// On laisse passer deux images avant de peindre. `addPostFrameCallback`
  /// imbrique plutot qu'un delai fixe : le nombre d'images est ce qui compte,
  /// et il ne depend pas de la vitesse de l'appareil comme le ferait un
  /// `Future.delayed(80ms)` -- trop court sur un telephone lent, du retard
  /// gratuit sur un rapide.
  bool _tailleStable = false;

  /// Une police vient d'arriver : la page doit se remesurer.
  ///
  /// Sans cela, la taille reste celle calculee sur la police de SECOURS --
  /// defaut constate le 2026-09-03 (« la taille ne s'ajuste pas au changement
  /// d'ecriture ; apres balayage, elle s'ajuste »), et confirme par six
  /// ecritures differentes qui rendaient la meme occupation au dixieme.
  void _policeChargee() {
    _cacheReserve.clear();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // `systemFonts` est notifie par Flutter des qu'une police devient
    // disponible. On s'y abonne plutot que d'attendre un delai fixe : le temps
    // de telechargement depend du reseau, un delai serait tantot trop court,
    // tantot du retard gratuit a chaque ouverture.
    PaintingBinding.instance.systemFonts.addListener(_policeChargee);
    // Cible du signet pour la page d'ouverture (cf. `_premierVersetPage`).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _chargerPremierVerset());
    // Plein écran : ni barre d'état ni boutons système. `immersiveSticky` les
    // ramène brièvement sur un balayage depuis le bord puis les re-masque --
    // le geste de feuilletage n'est donc jamais confisqué par le système.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Deux images : la premiere porte encore l'ancienne taille, la seconde la
    // nouvelle. On peint a partir de la.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tailleStable = true);
      });
    });
    // La page de mushaf reste rotative sans changer le verrou global de l'app.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_policeChargee);
    // Sans cette restauration, TOUT le reste de l'app resterait sans barres
    // système après un passage par la maquette.
    // ChGPT: the normal reader is also immersive. Restoring edgeToEdge
    // unconditionally changed its insets underneath the return animation.
    SystemChrome.setEnabledSystemUIMode(widget.modeSystemeAuRetour);
    // Remettre le verrou de `main.dart`, sinon tout le reste de l'app
    // devient rotatif après un simple passage par cet écran -- exactement le
    // même piège que les barres système ci-dessus.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // THÈME DE LECTURE (2026-09-01, « est-ce qu'ajusté peut suivre le thème
    // de lecture ? »). Le mode sombre est celui des réglages de lecture, le
    // même que le Mushaf d'origine -- passer de l'un à l'autre ne doit pas
    // faire clignoter l'écran du clair au sombre.
    //
    final sombre = ref.watch(modeSombreProvider);
    final sepia = ref.watch(kindleModeProvider);
    final warsh = ref.watch(riwayaProvider) == Riwaya.warsh;
    // ECRITURE DU TEXTE CORANIQUE (2026-09-03) : reglage local a cette vue,
    // defaut `Amiri` -- le rendu d'origine, inchange tant qu'aucun autre choix
    // n'est fait.
    final ecriture = ref.watch(policeMushafPageProvider);
    final tajwid = ref.watch(tajwidMushafPageProvider);
    // ── LE SURLIGNEMENT SUIT LA LECTURE (2026-09-12) ────────────────────
    //
    // Meme calcul que la vue liste (`playingVerseKey` dans
    // mushaf_screen.dart), recopie a l'identique -- y compris le test sur
    // `isActive` et non `isPlaying` : au moment ou `currentVerse` change, le
    // statut vaut encore « loading », et filtrer sur `isPlaying` ferait
    // clignoter le surlignement a chaque changement de verset.
    final etatLecteur = ref.watch(playerProvider);
    final cleVersetJoue =
        etatLecteur.isActive ? etatLecteur.currentVerse?.key : null;
    // ── RETOUR ET SIGNET, ICI AUSSI (2026-09-12) ─────────────────────────
    //
    // Demande utilisateur : « je veux egalement les marquer dans mushaf
    // papier ». Cette vue n'avait aucun chrome -- on en sortait par le geste
    // systeme, et le signet n'y etait pas posable du tout, alors que c'est la
    // vue ou l'on LIT longtemps, donc celle ou l'on s'arrete.
    //
    // Memes couleurs que dans le Mushaf normal, et pour la meme raison : le
    // rond n'est qu'un voile de la couleur du fond, c'est l'icone accordee au
    // theme qui porte le contraste. Sur une page de mushaf, le texte prime sur
    // le chrome.
    // Alpha 76 : mi-chemin entre les 110 d'avant (le texte etait masque) et
    // les 42 d'un premier essai (le bouton s'effacait) -- retour utilisateur
    // du 2026-09-12, meme reglage que dans le Mushaf plein ecran.
    final fondRond =
        (sombre ? AppColors.sombreBgDeep : const Color(0xFFF3EAD6))
            .withAlpha(76);
    // ── LA MARGE HAUTE TIENT COMPTE DE CHAQUE TELEPHONE (2026-09-12) ─────
    //
    // Ni une valeur fixe, ni la marge systeme entiere. Une constante en dur
    // passerait sous l'encoche des uns et flotterait au milieu de l'ecran des
    // autres ; `SafeArea` entier posait les boutons trop bas sur la page
    // (« est-ce qu'il y a moyen de les faire encore remonter »).
    //
    // On prend donc une PART de ce que l'appareil declare, bornee des deux
    // cotes : 45 % de `padding.top`, au moins 4 (ecrans qui ne declarent
    // rien -- cette vue tourne en `immersiveSticky`, la barre d'etat y est
    // masquee), au plus 64 (tablettes et encoches profondes, ou 45 % ferait
    // redescendre le bouton trop bas). Les deux boutons sont aux BORDS
    // gauche et droit, la ou aucune encoche ni aucun poincon ne se place --
    // le risque de recouvrement est donc structurellement faible.
    final margeHauteRond = margeHauteBoutonsMushaf(context);
    final encreRond = sombre ? AppColors.cream : AppColors.ink;
    final cleSignet = _premierVersetPage == null
        ? null
        : MarquePagesNotifier.cle(_premierVersetPage!.surahNumber,
            _premierVersetPage!.ayahNumber);
    final estMarquee =
        cleSignet != null && ref.watch(marquePagesProvider) == cleSignet;
    return PopScope(
      // Le retour rend la page LUE, pas celle d'entrée : c'est ce qui rend le
      // lien bidirectionnel (cf. la doc de `_pageLue`). `PopScope` plutôt
      // qu'un bouton dédié -- le geste de retour d'Android et la flèche de la
      // barre passent tous les deux par ici, donc aucun chemin de sortie
      // n'oublie de rapporter la position.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) Navigator.of(context).pop(_pageLue);
      },
      child: Opacity(
      // Le fond du Scaffold reste peint : on ne voit pas un ecran noir, mais la
      // couleur du parchemin, puis la page dessus.
      opacity: _tailleStable ? 1 : 0,
      child: Scaffold(
      backgroundColor: sombre ? AppColors.sombreBg : const Color(0xFFF3EAD6),
      // CHGPT : la page reste toujours en plein ecran. Un toucher avance
      // directement, sans faire apparaitre de barre qui decale le Mushaf.
      body: Stack(
        children: [
          PageView.builder(
        controller: _ctrl,
        // ── LE SENS DE LA TOURNE NE DEPEND PAS DE LA LANGUE (2026-09-13) ──
        //
        // C'etait `reverse: true` en dur. Constat utilisateur : « je viens de
        // remarquer que tourner les pages ressemble a tourner en francais ».
        // VERIFIE par la mesure, pas deduit : interface en arabe, un balayage
        // droite -> gauche faisait passer de la page 16 a la page 23, c'est le
        // sens d'un livre latin. Un mushaf se tourne dans l'autre sens.
        //
        // La cause est un DOUBLE RETOURNEMENT. Un `PageView` horizontal tire
        // deja son sens de la `Directionality` ambiante :
        //
        //   LTR  + reverse:false -> avance en balayant droite -> gauche (latin)
        //   LTR  + reverse:true  -> avance en balayant gauche -> droite (arabe)
        //   RTL  + reverse:false -> avance en balayant gauche -> droite (arabe)
        //   RTL  + reverse:true  -> avance en balayant droite -> gauche (LATIN)
        //                                                        ^^^^^^^^^^^^
        // `reverse: true` etait donc JUSTE tant que l'application etait en
        // francais, et FAUX des qu'elle passe en arabe -- la locale arabe
        // bascule toute la `Directionality` (cf. `MaterialApp(locale:)`), ce
        // qui annulait le retournement au lieu de s'y ajouter. Le defaut
        // n'apparait que dans une langue, ce qui explique qu'il ait survecu.
        //
        // En le derivant de la direction ambiante, les quatre cas se reduisent
        // aux deux lignes « arabe » ci-dessus : le mushaf se tourne toujours
        // comme un mushaf, quelle que soit la langue de l'interface. C'est un
        // livre, pas un ecran -- son sens ne se negocie pas avec la locale.
        reverse: Directionality.of(context) == TextDirection.ltr,
        physics: const _BalayagePage(),
        itemCount: _kPages,
        onPageChanged: (i) {
          _pageLue = i + 1;
          _chargerPremierVerset();
        },
        // ── LE ZOOM SYSTEME CASSAIT LE CALCUL DE PAGE (2026-09-04) ───────
        //
        // Question de l'utilisateur : « l'affichage du mushaf papier tient-il
        // de la dimension du téléphone ? ». De l'écran, oui -- la taille de
        // police est MESUREE par dichotomie pour remplir exactement la hauteur
        // disponible (`_tailleQuiTient`). Du réglage système « taille de
        // police », non, et les deux divergeaient :
        //
        //   la MESURE passe par `TextPainter`, qui n'applique aucun zoom ;
        //   le RENDU passe par `Text`, qui applique celui du `MediaQuery`.
        //
        // Une page calculée pour 100 % et peinte à 130 % déborde -- la
        // dernière ligne sort du cadre. Le public d'un mushaf comprend
        // beaucoup de lecteurs qui augmentent cette taille : le défaut n'a
        // rien d'exotique. Il explique peut-être aussi la « dernière ligne pas
        // visible » signalée le 2026-09-03, attribuée alors à la seule hauteur
        // d'écran -- non vérifié, l'appareil de test est peut-être à 100 %.
        //
        // L'ENVELOPPE PLUTÔT QUE CINQ `textScaler` : le corps n'est pas seul en
        // cause. L'en-tête, le pied, les médaillons et surtout le bandeau de
        // sourate -- dont la hauteur `compactHeight` est une CONSTANTE entrant
        // dans le calcul de la place disponible -- grossiraient aussi, et la
        // réservation deviendrait fausse. Un seul point couvre la page entière,
        // y compris ce qu'on y ajoutera demain.
        //
        // CE N'EST PAS UN DÉNI D'ACCESSIBILITÉ : la page remplit déjà l'écran
        // par construction, la police est prise AU MAXIMUM de ce qui tient. Le
        // zoom système ne peut rien y ajouter, seulement casser le calcul. Qui
        // veut un texte plus grand a le sélecteur d'écriture (appui long) et le
        // format lui-même, qui répond en tournant moins de lignes par page.
        itemBuilder: (context, i) => MediaQuery.withNoTextScaling(
          child: _PageMushaf(
          page: i + 1,
          sombre: sombre,
          sepia: sepia,
          warsh: warsh,
          ecriture: ecriture,
          tajwid: tajwid,
          cleVersetJoue: cleVersetJoue,
          onTap: () => _ctrl.nextPage(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          ),
          // Raccourci : la meme feuille que dans les Reglages, pour
          // comparer deux ecritures sans quitter la page.
          onLongPress: () =>
              ouvrirChoixEcriture(context, ref, sombre: sombre),
        ),
        ),
      ),
          // Poses APRES la page dans le Stack : ils flottent au-dessus d'elle,
          // sans jamais entrer dans le calcul de mise en page du mushaf (la
          // taille de police est mesuree par dichotomie sur la hauteur
          // disponible -- un bouton dans le flux la ferait retrecir).
          Positioned(
            top: margeHauteRond,
            left: 8,
            child: Material(
                color: fondRond,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: encreRond),
                  onPressed: () => Navigator.of(context).pop(_pageLue),
                ),
            ),
          ),
          Positioned(
            top: margeHauteRond,
            right: 8,
            child: Material(
                color: fondRond,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: estMarquee
                      ? AppLocalizations.of(context)!.mushafBookmarkRemove
                      : AppLocalizations.of(context)!.mushafBookmarkHere,
                  icon: Icon(
                      estMarquee
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: estMarquee ? AppColors.brass : encreRond),
                  // Desactive tant que la page n'a pas dit quel verset elle
                  // commence : mieux vaut un bouton inerte qu'un signet pose
                  // au mauvais endroit.
                  onPressed: _premierVersetPage == null
                      ? null
                      : () async {
                          final v = _premierVersetPage!;
                          final pose = await ref
                              .read(marquePagesProvider.notifier)
                              .basculer(v.surahNumber, v.ayahNumber);
                          if (!context.mounted) return;
                          final t = AppLocalizations.of(context)!;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                              duration: const Duration(seconds: 2),
                              backgroundColor: AppColors.green900,
                              content: Text(
                                '${pose ? t.mushafBookmarkAdded : t.mushafBookmarkRemoved}'
                                '  ${v.surahNumber}:${v.ayahNumber}',
                                style: GoogleFonts.manrope(
                                    fontSize: 13, color: AppColors.cream),
                              ),
                            ));
                        },
                ),
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}

/// Une page, chargée à la demande (le cache de `QuranApi` rend les retours
/// en arrière gratuits).
class _PageMushaf extends StatelessWidget {
  final int page;
  final bool sombre;
  final bool sepia;
  final bool warsh;

  /// Colorer le texte selon les regles de tajwid (cf.
  /// `tajwidMushafPageProvider`). Eteint, la page se peint en une seule encre.
  final bool tajwid;

  /// Nom Google Fonts de l'ecriture du TEXTE CORANIQUE (cf.
  /// `policeMushafPageProvider`). L'en-tete et le pied gardent Amiri : ce sont
  /// des reperes de navigation, les faire varier brouillerait la comparaison
  /// entre deux ecritures.
  final String ecriture;

  /// Cle « sourate:verset » du verset en cours de LECTURE, ou `null` si le
  /// lecteur est arrete (2026-09-12).
  ///
  /// Demande utilisateur : « lors de la lecture on a un surlignement sur la
  /// page par verset, est-ce qu'on peut avoir le meme rendu dans le mushaf
  /// papier, quelque chose qui suit la lecture ». La vue liste le fait depuis
  /// longtemps (`isPlayingCursor` dans verse_tile.dart) ; cette page-ci ne
  /// lisait tout simplement pas le lecteur -- rien ne s'y opposait, personne
  /// ne le lui avait branche.
  ///
  /// Meme source que la vue liste, au calcul pres qui est recopie tel quel
  /// (cf. `playingVerseKey` dans mushaf_screen.dart, et la note qui explique
  /// pourquoi on teste `isActive` et non `isPlaying`).
  final String? cleVersetJoue;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _PageMushaf({
    required this.page,
    required this.sombre,
    required this.sepia,
    required this.warsh,
    required this.ecriture,
    required this.tajwid,
    required this.cleVersetJoue,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      // ── LA BISMILLAH MANQUAIT EN TETE DE SOURATE (2026-09-04) ──────────
      //
      // Constat utilisateur : « dans mushaf papier, absence de bismillah dans
      // les sourates -- attention sourate Tawba sans bismillah ».
      //
      // La page est construite a partir des VERSETS, et la Bismillah n'en est
      // un que dans Al-Fatiha (1:1). Partout ailleurs elle precede le verset 1
      // sans etre numerotee : aucune API qui rend « les versets de la page »
      // ne la contient, elle etait donc simplement absente.
      //
      // ⚠️ SON TEXTE N'EST PAS ECRIT ICI. Regle du projet -- « faut pas
      // inventer et modifier le texte sacre » : on le LIT a la source, dans la
      // riwaya courante (le premier verset d'Al-Fatiha), au lieu de le saisir
      // a la main. Les deux lectures n'ecrivent pas la basmala identiquement.
      child: FutureBuilder<List<List<Verse>>>(
        future: Future.wait([
          warsh
              ? QuranApi.fetchWarshMushafVersesByPage(page)
              : QuranApi.fetchVersesByPage(page),
          warsh
              ? QuranApi.fetchWarshMushafVersesByPage(1)
              : QuranApi.fetchVersesByPage(1),
          // Le découpage en lignes du mushaf imprimé. Chargé ici plutôt qu'au
          // démarrage de l'app : il ne sert qu'à cette vue, et `ensureLoaded`
          // ne relit l'asset qu'une fois.
          MushafLignesService.instance
              .ensureLoaded()
              .then((_) => <Verse>[]),
        ]),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Erreur : ${snap.error}',
                style: GoogleFonts.manrope(color: Colors.redAccent),
              ),
            );
          }
          final versets = snap.data?.first;
          final bismillah = snap.data == null || snap.data!.length < 2
              ? null
              : (snap.data![1].isEmpty ? null : snap.data![1].first.textUthmani);
          if (versets == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brassLight),
            );
          }
          if (versets.isEmpty) {
            return Center(
              child: Text(
                'page $page vide',
                style: GoogleFonts.manrope(color: AppColors.inkLight),
              ),
            );
          }
          return _pageMushaf(context, versets, bismillah);
        },
      ),
    );
  }

  /// Les deux sourates qui n'ouvrent PAS sur une basmala rapportee.
  ///
  /// Al-Fatiha (1) : la basmala y EST le verset 1, elle est donc deja dans le
  /// flux -- l'ajouter la ferait apparaitre deux fois.
  /// At-Tawba (9) : elle n'en a pas, et c'est l'utilisateur qui l'a rappele en
  /// signalant le defaut (« attention sourate Tawba sans bismillah »). En
  /// ajouter une serait ajouter au texte, pas le corriger.
  static const _sansBasmala = {1, 9};

  /// ── LA PAGE EST FAITE DE LIGNES FIXES, PAS D'UN TEXTE QUI COULE ────────
  ///
  /// Constat utilisateur (2026-09-04) : « tu ne respectes pas le Coran papier.
  /// Ce n'est pas juste un nombre de pages : chaque page a un nombre précis de
  /// lignes, chaque ligne commence et finit avec les mêmes mots, quel que soit
  /// le type d'écriture. »
  ///
  /// C'était un défaut d'architecture, et il explique toute la série de
  /// correctifs qui a précédé -- réserve sous la dernière ligne, tolérance du
  /// clip, interligne élargi, marges du cadre : autant de rustines sur une mise
  /// en page qui n'était pas celle d'un mushaf. L'ancienne version versait le
  /// texte d'une page dans UN paragraphe justifié et laissait Flutter décider
  /// où couper ; le découpage suivait donc la police et la largeur d'écran.
  ///
  /// Ici chaque ligne est rendue POUR ELLE-MÊME, avec les mots que le mushaf
  /// imprimé y met (`MushafLignesService`). Changer d'écriture ne déplace plus
  /// un seul mot : seule la taille des glyphes change.
  ///
  /// ⚠️ RIEN NE SUPPOSE UN NOMBRE DE LIGNES. Ce sont les BORNES de chaque ligne
  /// qui font foi -- l'utilisateur a dû le rappeler (« j'ai pas dit 15 lignes
  /// fixes, c'est toi qui l'as dit ; respecte à la lettre le début et la fin de
  /// chaque ligne »). Quatre pages n'en ont pas 15, et une mise en page bâtie
  /// sur ce nombre y serait fausse. On parcourt la liste reçue, point.
  ///
  /// JUSTIFICATION PAR `Row` ET NON `TextAlign.justify` : Flutter ne justifie
  /// jamais la DERNIÈRE ligne d'un paragraphe, et ici chaque ligne est un
  /// paragraphe à elle seule -- elles se seraient toutes collées à droite. Un
  /// `Row` en `spaceBetween` répartit l'espace entre les mots, ce que fait le
  /// mushaf imprimé (qui, lui, étire aussi les lettres).
  ///
  /// TAILLE DE POLICE : la plus grande qui satisfait DEUX contraintes -- les
  /// lignes tiennent en hauteur, et la plus longue tient en largeur. La seconde
  /// est nouvelle : avec un découpage libre une ligne trop longue se coupait
  /// toute seule ; avec un découpage imposé, elle déborderait.
  Widget _pageLignes(
    BuildContext context,
    List<Verse> versets,
    List<LigneMushaf> lignes,
    String? bismillah,
  ) {
    final parCle = <String, Verse>{
      for (final v in versets) '${v.surahNumber}:${v.ayahNumber}': v,
    };

    /// Les mots d'une ligne, chacun avec ses spans de coloration.
    List<List<InlineSpan>> motsDe(LigneMushaf l, TextStyle style) {
      final out = <List<InlineSpan>>[];
      final d = l.debut!;
      final f = l.fin!;
      for (var a = d.verset; a <= f.verset; a++) {
        final v = parCle['${d.sourate}:$a'];
        if (v == null) continue;
        final bruts = v.textUthmani.split(RegExp(r'\s+'))
          ..removeWhere((m) => m.isEmpty);
        // ⚠️ `tajweedSpansPerWord` FILTRE les marques décoratives isolées (rub
        // el hizb « ۞ »), alors que le layout QPC les compte comme des mots.
        // Les deux index divergent donc dès qu'un verset en porte une : on
        // n'avance dans les spans que sur les mots que ce filtre garde, sinon
        // toute la coloration se décale d'un cran jusqu'à la fin du passage.
        final spans = tajwid
            ? tajweedSpansPerWord(v.textUthmani, v.textUthmaniTajweed, style,
                sombre: sombre)
            : null;
        var iSpan = 0;
        final premier = (a == d.verset) ? d.mot : 1;
        final dernier = (a == f.verset) ? f.mot : bruts.length;
        for (var i = 1; i <= bruts.length; i++) {
          final mot = bruts[i - 1];
          final compte = ArabicNormalizer.normalize(mot).isNotEmpty;
          final sp = (spans != null && compte && iSpan < spans.length)
              ? spans[iSpan]
              : null;
          if (compte) iSpan++;
          if (i < premier || i > dernier) continue;
          // ── LE MEDAILLON ET LA SAJDA EMPRUNTENT LEUR GLYPHE (2026-09-04) ─
          //
          // Constat utilisateur sur le rendu ligne par ligne : « les numéros
          // des versets ne sont pas dans leur zone ». C'est un correctif qui
          // EXISTAIT dans l'ancien rendu (`_spansCanoniques`) et que celui-ci
          // avait perdu -- il peignait tout avec la police de la page.
          //
          // Mesure fontTools des 14 écritures (2026-09-03) : U+06DD est de
          // catégorie Unicode `Cf`, AUCUNE police ne le lie aux chiffres par
          // une règle GSUB, et quatre ne le dessinent pas du tout (Aref Ruqaa,
          // Reem Kufi, Markazi Text, Bouazzi Maghribi). Amiri est celle dont le
          // glyphe et le calage rendent le numéro encerclé ; elle est embarquée
          // dans l'APK, donc ce repli tient hors ligne même si l'écriture
          // choisie doit encore se télécharger. Même montage pour `۩`, dont
          // Amiri dessine une forme « en porte » -- scheherazadeNew fait la
          // bonne (« le signe de sajda ressemble plutôt à une porte »).
          if (!compte) {
            out.add(<InlineSpan>[
              TextSpan(
                text: mot,
                style: mot == '\u06E9'
                    ? style.copyWith(
                        fontFamily: GoogleFonts.scheherazadeNew().fontFamily)
                    : style,
              ),
            ]);
            continue;
          }
          out.add(sp ?? <InlineSpan>[TextSpan(text: mot, style: style)]);
        }
        // Le médaillon de fin de verset suit le dernier mot de CE verset.
        if (a < f.verset || f.mot >= bruts.length) {
          out.add(<InlineSpan>[
            TextSpan(
              text: _medaillon(v.ayahNumber),
              style: style.copyWith(fontFamily: GoogleFonts.amiri().fontFamily),
            ),
          ]);
        }
      }
      return out;
    }

    return LayoutBuilder(
      builder: (context, c) {
        final n = lignes.length;
        if (n == 0) return const SizedBox.shrink();

        // Hauteur d'une ligne : l'espace disponible réparti à parts égales,
        // comme les lignes régulières d'un mushaf imprimé.
        final hLigne = c.maxHeight / n;

        // La plus grande taille qui tient EN LARGEUR sur toutes les lignes --
        // la hauteur, elle, est déjà imposée par `hLigne`.
        double basse = 8, haute = hLigne / 1.05;
        for (var essai = 0; essai < 10; essai++) {
          final m = (basse + haute) / 2;
          final st =
              _policePage(taille: m, famille: ecriture, interligne: 1.0);
          var tient = true;
          for (final l in lignes) {
            if (l.type != LigneType.texte) continue;
            final mots = motsDe(l, st);
            var largeur = 0.0;
            for (final mot in mots) {
              final p = TextPainter(
                text: TextSpan(style: st, children: mot),
                textDirection: TextDirection.rtl,
              )..layout();
              largeur += p.width;
            }
            // Un blanc minimal entre les mots : sans lui la ligne « tient » au
            // calcul et se touche à l'écran.
            largeur += (mots.length - 1) * m * 0.12;
            if (largeur > c.maxWidth) {
              tient = false;
              break;
            }
          }
          if (tient) {
            basse = m;
          } else {
            haute = m;
          }
        }
        final taille = basse;
        final style =
            _policePage(taille: taille, famille: ecriture, interligne: 1.0);

        return Column(
          children: [
            for (final l in lignes)
              SizedBox(
                height: hLigne,
                width: double.infinity,
                child: switch (l.type) {
                  LigneType.titreSourate =>
                    Center(child: _bandeauSourate(l.sourate!, hLigne)),
                  LigneType.basmala => bismillah == null
                      ? const SizedBox.shrink()
                      : Center(
                          child: Text(
                            bismillah,
                            style: style,
                            textAlign: TextAlign.center,
                            textHeightBehavior: const TextHeightBehavior(
                                applyHeightToFirstAscent: false),
                          ),
                        ),
                  LigneType.texte => Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final mot in motsDe(l, style))
                            Text.rich(
                              TextSpan(style: style, children: mot),
                              textHeightBehavior: const TextHeightBehavior(
                                  applyHeightToFirstAscent: false),
                            ),
                        ],
                      ),
                    ),
                },
              ),
          ],
        );
      },
    );
  }

  Widget _pageMushaf(
      BuildContext context, List<Verse> versets, String? bismillah) {
    // ── UN SEGMENT PAR SOURATE (2026-09-03) ────────────────────────────
    // La page etait un seul flux de texte : deux sourates s'y suivaient sans
    // rien entre elles. On regroupe donc les versets par sourate, pour
    // pouvoir intercaler un bandeau de titre a chaque changement.
    final segments =
        <({int sourate, String texte, List<Verse> versets, String? basmala})>[];
    for (final v in versets) {
      // Meme rattachement que pour la version coloree (cf. _spansCanoniques) :
      // une marque de waqf isolee, sans lettre porteuse, flotte vers la ligne
      // du dessus. Le rub el hizb est exclu, il s imprime seul.
      final texte = warsh ? _waqfRattache(v.textUthmani) : v.textUthmani;
      final medaillon = v.ayahNumber > 0 ? ' ${_medaillon(v.ayahNumber)}' : '';
      final mot = '$texte$medaillon';
      if (segments.isNotEmpty && segments.last.sourate == v.surahNumber) {
        final d = segments.removeLast();
        segments.add((
          sourate: d.sourate,
          texte: '${d.texte} $mot',
          versets: [...d.versets, v],
          basmala: d.basmala,
        ));
      } else {
        // Un segment qui commence au verset 1 OUVRE la sourate : c'est la, et
        // seulement la, que la basmala se pose. Une sourate qui se poursuit
        // d'une page sur l'autre n'en reprend pas.
        final ouvre = v.ayahNumber == 1 &&
            !_sansBasmala.contains(v.surahNumber) &&
            bismillah != null;
        segments.add((
          sourate: v.surahNumber,
          texte: ouvre ? '$bismillah\n$mot' : mot,
          versets: [v],
          basmala: ouvre ? bismillah : null,
        ));
      }
    }

    // ── LE TEXTE PEINT EST LE TEXTE CANONIQUE, PAS CELUI DE L'ANNOTATION ──
    //
    // Corrige le 2026-09-03 apres un constat utilisateur a l'oeil nu (« tu
    // n'as pas les vrais signes »), confirme par un recensement sur les 6236
    // versets : depouille de ses balises, `text_uthmani_tajweed` differe du
    // texte de reference sur 100 % des versets -- petit zero rond des lettres
    // muettes remplace par un sukun (3676x), alif suscrit devenu alef a hamza
    // ondulee (1479x), tanwin degrades en voyelle simple (313x), alefs perdus
    // (395x), et le numero de verset deja present en fin de texte (6208x),
    // qui faisait double emploi avec le medaillon ajoute ici.
    //
    // `tajweedSpansPerWord` existe depuis le 2026-07-10 pour exactement cela :
    // elle reconstruit chaque mot depuis `text_uthmani` et n'emprunte a
    // l'annotation QUE la couleur. L'ecran de lecture, le karaoke et la fiche
    // tajwid l'utilisent deja ; cette vue etait le seul endroit de l'app a
    // peindre les caracteres de l'annotation. NE PAS revenir a
    // `parseTajweedHtml` sur `text_uthmani_tajweed` : c'est ce defaut-la.
    // ── LA COULEUR TAJWID REDEVIENT UN CHOIX (2026-09-03) ────────────────
    // « tu peux laisser option couleur tajwid ou pas ». La vue l'appliquait en
    // permanence depuis que la barre du bas a disparu. La bascule vit dans la
    // feuille d'appui long, avec les ecritures -- pas en bouton permanent, qui
    // reprendrait la place rendue au texte.
    //
    // ⚠️ Couper la couleur ne change RIEN aux caracteres : ils viennent
    // toujours de `text_uthmani`, l'annotation ne fournit que la teinte.
    // ⚠️ LES SPANS SONT CONSTRUITS DANS LES DEUX CAS (2026-09-03).
    //
    // Premiere version : `null` quand la couleur etait eteinte, donc `_bloc`
    // peignait le texte d'un seul bloc avec la police de la page. Defaut
    // constate a l'ecran : les medaillons de fin de verset sortaient en CARRES
    // NOIRS avec le chiffre rejete a cote -- « si j'enleve couleur tajwid les
    // chiffres sortent du signe du verset ». Cause : le correctif qui force le
    // medaillon en Amiri vit dans `_spansCanoniques`, et n'etait donc applique
    // qu'avec la couleur. Or les ecritures sans U+06DD (Maghribi, Aref Ruqaa,
    // Reem Kufi, Markazi Text) ne savent pas le dessiner.
    //
    // On construit donc toujours les spans ; `couleur` ne commande QUE la
    // teinte des regles, jamais la structure du texte.
    final spansParSegment = [
      for (final s in segments) _spansCanoniques(s.versets, couleur: tajwid),
    ];
    final sourates = versets.map((v) => v.surahNumber).toSet().toList()..sort();
    // Le juz et le hizb VIENNENT DES DONNEES (2026-09-02) : ils etaient
    // estimes a partir du numero de page, ce qui se trompe des qu'une page
    // enjambe une frontiere. `juz_number` et `hizb_number` sont dans
    // `quran_verses.json` depuis le debut.
    final juz = versets.map((v) => v.juzNumber).whereType<int>().toSet();
    final hizb = versets.map((v) => v.hizbNumber).whereType<int>().toSet();
    final pageOuverture = page == 1 || page == 2;

    return SafeArea(
      // ── LE CADRE VA JUSQU'AU BORD (2026-09-03) ───────────────────────
      // « tu peux profiter du max de l'ecran du tel ». L'ecran est deja en
      // `immersiveSticky` (barre d'etat cachee) ; ce qui restait etait la
      // reserve d'encoche du SafeArea -- une bande beige d'environ 90 px
      // au-dessus du cadre, entouree en rouge sur sa capture. On la rend au
      // texte, en gardant 6 px pour que le filet ne colle pas au bord.
      top: false,
      bottom: false,
      // ChGPT: the same 6 px now live inside the painted chrome.
      minimum: EdgeInsets.zero,
      child: Padding(
        // Marges resserrees : la page doit occuper l'ecran (demande
        // utilisateur), le decor remplace ce que les marges laissaient vide.
        // Le plein ecran est immediat. Seul le bouton retour revele au toucher
        // demande temporairement une reserve en haut.
        // Bande de 2,3 % de la largeur : sur 1080 px cela fait 25 px, la
        // mesure exacte de la reference.
        // ⚠️ `padding.top` EXPLICITE (2026-09-03). Les 68 px compensaient la
        // barre de controle, qui est un OVERLAY pose au-dessus de la page ;
        // ils s'ajoutaient alors a la reserve d'encoche du SafeArea. Depuis
        // que celle-ci est retiree (« profiter du max de l'ecran »), il faut
        // la nommer ici, sinon la barre recouvre l'en-tete -- constate a
        // l'ecran, sourate/hizb/juz a moitie caches derriere le bandeau vert.
        padding: EdgeInsets.zero,
        // CHGPT : les pages d'ouverture et les pages courantes partagent le
        // meme contenu ; seul leur habillage graphique change. Les trois JPEG
        // de reference ne sont jamais charges par ce rendu.
        child: MushafPageChrome(
          verticalReserve: 6,
          style: pageOuverture
              ? MushafFrameStyle.opening
              : MushafFrameStyle.regular,
          dark: sombre,
          sepia: sepia,
          child: Column(
            children: [
              if (pageOuverture)
                _bandeauSourate(
                  segments.first.sourate,
                  MushafSurahBanner.openingHeight,
                  compact: false,
                )
              else
                _zone(_enTete(sourates, juz, hizb), Colors.red),
              // 1 et non 3 : l'en-tete et le texte se touchent presque, et
              // chaque pixel rendu ici est du texte en plus (cf. la marge du
              // cadre, reduite le meme jour).
              const SizedBox(height: 1),
              // ── LE DÉCOUPAGE DU MUSHAF IMPRIMÉ D'ABORD (2026-09-04) ──
              //
              // `_pageLignes` respecte les bornes de chaque ligne du mushaf.
              // L'ancien `_blocAjuste` (texte coulé dans un paragraphe
              // justifié, découpe laissée à Flutter) reste en repli si l'asset
              // manque : un asset absent doit afficher le Coran, pas une page
              // blanche. Conservé aussi parce que la règle du projet l'exige --
              // on n'efface pas un mécanisme remplacé.
              //
              // ⚠️ ICI ET PAS À LA PLACE DE `_pageMushaf` : le premier essai
              // remplaçait la page ENTIÈRE, et emportait avec elle le cadre,
              // l'en-tête (sourate/hizb/juz) et le numéro de page -- vus
              // disparaître à l'écran. Le chrome appartient à cette méthode ;
              // seul le contenu change.
              // ── RENDU LIGNE PAR LIGNE DEBRANCHE (2026-09-04) ─────────
              //
              // `_pageLignes` respectait bien les bornes du mushaf imprime
              // (asset `mushaf_lignes.json`, 17 640 bornes verifiees sans
              // ecart), mais son RENDU n'a pas convenu : « c'est quoi cette
              // connerie, reviens a la situation avant ma demande de faire
              // comme le papier, t'as vraiment rate ».
              //
              // Ce qui n'allait pas, et qui reste a resoudre avant tout
              // nouvel essai : la justification par repartition entre les mots
              // (`Row` en `spaceBetween`) ne ressemble pas a un mushaf. Un
              // mushaf imprime ETIRE les lettres (kashida) pour remplir la
              // ligne ; a defaut, la ligne la plus dense d'une page fixe la
              // taille de police pour toutes les autres, qui se retrouvent
              // trouees de grands blancs. Le probleme n'est donc PAS la donnee
              // -- elle est juste -- mais le fait que Flutter ne sache pas
              // etirer les glyphes.
              //
              // Le code et l'asset sont CONSERVES (regle du projet : on
              // n'efface pas un mecanisme, on laisse la trace de pourquoi il
              // ne tourne pas). Le rebrancher tient a cette seule condition.
              Expanded(
                key: ValueKey('mushaf-body-$page'),
                child: _zone(
                  ClipRect(child: _blocAjuste(segments, spansParSegment)),
                  Colors.blue,
                ),
              ),
              _zone(_pied(sourates, juz), Colors.green),
            ],
          ),
        ),
      ),
    );
  }

  /// Pied de page : le NUMERO DE PAGE, seul et centre.
  ///
  /// La sourate et le juz etaient repetes ici alors qu'ils figurent deja en
  /// en-tete -- « le nom de la sourate en haut et en bas, c'est perte
  /// d'espace ». Un mushaf imprime ne les repete pas non plus : l'en-tete
  /// situe, le pied numerote.
  Widget _pied(List<int> sourates, Set<int> juz) => Padding(
    padding: const EdgeInsets.only(top: 1),
    child: Text(
      _chiffresArabes(page),
      style: GoogleFonts.amiri(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: sombre ? AppColors.brass : _Charte.filet,
      ),
    ),
  );

  /// Nom arabe de la sourate, depuis le catalogue deja charge par `QuranApi`.
  /// Repli sur le numero si le catalogue n'est pas encore la : mieux vaut
  /// « ٢ » qu'un vide, et il se remplira au prochain rendu.
  String _nomSourate(int numero) {
    final s = QuranApi.chapitresCharges;
    if (s == null) return _chiffresArabes(numero);
    for (final c in s) {
      if (c.number == numero) return c.nameArabic;
    }
    return _chiffresArabes(numero);
  }

  /// En-tete : sourate(s) a droite, hizb et juz a gauche -- les trois
  /// reperes qu'un lecteur cherche pour se situer. Le juz etait ESTIME
  /// jusqu'au 2026-09-02 (cf. `_pageMushaf`), il vient maintenant des donnees.
  /// Hauteur de chaque onglet de l'en-tete -- partagee entre `onglet()` (le
  /// `Container` qui la fixe) et l'`OverflowBox` qui borne l'ensemble, pour ne
  /// jamais ecrire "26" deux fois et risquer que les deux divergent.
  static const double _kHauteurOnglet = 26;

  Widget _enTete(List<int> sourates, Set<int> juz, Set<int> hizb) {
    final (fondCadre, filetCadre, encreCadre) =
        MushafOrnamentalFramePainter.colorsFor(sombre
            ? MushafFrameTone.dark
            : sepia ? MushafFrameTone.sepia : MushafFrameTone.light);
    final style = GoogleFonts.amiri(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: encreCadre,
    );
    final gauche = [
      if (hizb.isNotEmpty) 'حزب ${_chiffresArabes(hizb.first)}',
      if (juz.isNotEmpty) 'جزء ${_chiffresArabes(juz.first)}',
    ].join(' · ');
    Widget onglet(String texte) => Expanded(
      child: Container(
        // 26 et non 30 (2026-09-04, « cherche de la hauteur ») : le libelle
        // fait 13 px, l'onglet en reservait plus du double. Quatre pixels
        // rendus au texte sur chacune des 604 pages.
        height: _kHauteurOnglet,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: fondCadre,
          border: Border.all(
            color: filetCadre,
            width: 1.1,
          ),
        ),
        child: Text(
          texte,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.rtl,
          style: style,
        ),
      ),
    );

    // ChGPT->ici : la ligne d'en-tete vit dans le meme padding de contenu
    // que le texte des versets (`horizontal`, cf. MushafPageChrome), alors
    // que le filet du cadre est peint 3 px plus au bord (`horizontal - 3`,
    // meme fichier). Ecart mesure sur capture : ~8 px physiques de page nue
    // visible entre le filet et chaque cartouche. On l'annule ICI seulement
    // -- les marges du texte, elles, restent exactement les memes.
    //
    // ⚠️ `Padding` negatif fait planter Flutter (`padding.isNonNegative`,
    // shifted_box.dart) -- contrairement a un margin CSS, ce n'est PAS
    // autorise. `OverflowBox` est l'outil prevu pour laisser un enfant
    // deborder des contraintes du parent sans le decouper : on l'elargit
    // de `2 * headerBleed` (la moitie de chaque cote) et il se centre tout
    // seul, ce qui deborde bien de `headerBleed` a gauche ET a droite.
    // ⚠️ HAUTEUR EXPLICITE OBLIGATOIRE (corrige un plantage) : dans un
    // `Column`, un enfant non `Expanded` recoit une hauteur LACHE (0..infini).
    // `OverflowBox` sans `minHeight`/`maxHeight` la propage telle quelle a
    // l'enfant ET la reprend pour SA PROPRE taille -- « BOTTOM OVERFLOWED BY
    // Infinity PIXELS » constate a l'ecran. La largeur, elle, doit rester
    // elargie (c'est tout l'objet du correctif) ; seule la hauteur doit donc
    // etre fixee, a la valeur reelle et unique de la ligne : `_kHauteurOnglet`.
    return SizedBox(
      height: _kHauteurOnglet,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeurElargie =
              constraints.maxWidth + 2 * MushafPageChrome.headerBleed;
          return OverflowBox(
            minWidth: largeurElargie,
            maxWidth: largeurElargie,
            minHeight: _kHauteurOnglet,
            maxHeight: _kHauteurOnglet,
            child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                onglet(gauche),
            // ChGPT->ici: 8 -> 0 (demande utilisateur : « faut vraiment
            // juxtapose les creneaux » -- l'espace de page visible entre les
            // deux cartouches doit disparaitre, elles se touchent).
            onglet(
              sourates
                  .map((s) => 'سورة ${_nomSourate(s)} ${_chiffresArabes(s)}')
                  .join(' · '),
              ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Colle au mot precedent les marques de waqf encodees isolement.
  ///
  /// Le texte Warsh les encode deja collees au mot. Ce traitement reste donc
  /// reserve a Warsh ; le texte et le rendu historique Hafs sont preserves.
  /// U+06DE (rub el hizb) est HORS de la plage : ornement autonome, il
  /// s imprime seul entre deux mots, le coller a un mot serait une faute.
  static final _waqfIsole = RegExp(r'\s+([ۖ-ۜ۩])');
  static final _waqfVisible = RegExp(r'[\u06D6-\u06DC]');
  String _waqfRattache(String texte) =>
      texte.replaceAllMapped(_waqfIsole, (m) => m[1]!);

  /// Les signes Unicode de waqf sont des glyphes "SMALL HIGH". Amiri les
  /// place tres haut au-dessus de la ligne ; dans une page dense ils semblent
  /// alors colles a la ligne precedente. On ne change aucun caractere : le
  /// signe garde la meme ligne de base, mais son corps plus petit rapproche sa
  /// forme visible du mot auquel il appartient.
  List<TextSpan> _waqfSurLaLigne(
    List<TextSpan> sources,
    TextStyle parent,
    double taille,
  ) => warsh
      ? _waqfSurLaLigneWarsh(sources, parent, taille)
      : _waqfSurLaLigneHafs(sources, parent, taille);

  // CHGPT : deux fonctions distinctes evitent qu'une correction Warsh change
  // de nouveau le rendu Hafs. Les deux abaissent les glyphes SMALL HIGH ; seul
  // Warsh ajoute une espace fine car ses waqf sont colles au mot dans l'asset.
  List<TextSpan> _waqfSurLaLigneHafs(
    List<TextSpan> sources,
    TextStyle parent,
    double taille,
  ) => _waqfAjustes(sources, parent, taille, separerDuSoukoun: false);

  List<TextSpan> _waqfSurLaLigneWarsh(
    List<TextSpan> sources,
    TextStyle parent,
    double taille,
  ) => _waqfAjustes(sources, parent, taille, separerDuSoukoun: true);

  List<TextSpan> _waqfAjustes(
    List<TextSpan> sources,
    TextStyle parent,
    double taille, {
    required bool separerDuSoukoun,
  }) {
    final resultat = <TextSpan>[];

    void ajouter(TextSpan source, TextStyle heritee) {
      final style = heritee.merge(source.style);
      final texte = source.text;
      if (texte != null && texte.isNotEmpty) {
        var debut = 0;
        for (final match in _waqfVisible.allMatches(texte)) {
          if (match.start > debut) {
            resultat.add(
              TextSpan(text: texte.substring(debut, match.start), style: style),
            );
          }
          if (separerDuSoukoun) {
            // Le signe suit parfois un mim portant deja un soukoun. Cette
            // espace fine evite leur superposition sans detacher le waqf.
            resultat.add(TextSpan(text: '\u2009', style: style));
          }
          resultat.add(
            TextSpan(
              text: match.group(0)!,
              // CHGPT : un corps reduit partage la ligne de base du mot. Il
              // abaisse donc le glyphe SMALL HIGH sans introduire de widget
              // dont TextPainter ne connaitrait pas la hauteur.
              style: style.copyWith(fontSize: taille * 0.75, height: 1),
            ),
          );
          debut = match.end;
        }
        if (debut < texte.length) {
          resultat.add(TextSpan(text: texte.substring(debut), style: style));
        }
      }
      for (final enfant in source.children ?? const <InlineSpan>[]) {
        if (enfant is TextSpan) {
          ajouter(enfant, style);
        }
      }
    }

    for (final source in sources) {
      ajouter(source, parent);
    }
    return resultat;
  }

  // ── ESPACEMENT DES LETTRES INAUGURALES : RETIRE (2026-09-03) ──────────
  //
  // Un mecanisme `_espacerHurufMuqattaat` inserait un U+202F (NARROW NO-BREAK
  // SPACE) entre chaque lettre des huruf muqatta'at en Warsh -- `أَلَٓمِّٓ`
  // devenait `أَ⁠ لَّ⁠ مۡ` a l'ecran -- pour empecher Amiri de les ligaturer.
  // Il portait aussi la liste des 29 versets concernes (2:1, 3:1, 7:1, 10:1...).
  //
  // REFUS UTILISATEUR, immediat et sans appel : « faut pas inventer et
  // modifier le texte sacre ! », puis « il a rajoute des espaces, c'est pas
  // tolere ». La regle du projet le disait deja pour la Bismillah : le texte
  // coranique ne se compose jamais a la main. Inserer un caractere absent de
  // la source -- meme invisible, meme typographique -- c'est ecrire dans le
  // texte revele.
  //
  // ⚠️ NE PAS LE REINTRODUIRE sous une autre forme (ZWNJ U+200C, tatweel
  // U+0640, letterSpacing applique a ces seuls versets) : le probleme de
  // depart -- ces lettres paraissent trop serrees -- se traite dans la POLICE
  // ou la taille, jamais dans la chaine de caracteres.

  /// Spans colores d'un segment, batis sur le TEXTE CANONIQUE.
  ///
  /// Chaque mot vient de `text_uthmani` ; l'annotation tajwid ne fournit que
  /// la couleur (cf. `tajweedSpansPerWord` et le commentaire de
  /// `_pageMushaf`). Le medaillon de fin de verset est ajoute ici, une seule
  /// fois -- l'annotation en portait deja un en clair, d'ou le doublon.
  /// @param couleur applique la coloration tajwid. A `false`, les memes spans
  /// sont produits dans l'encre de base -- c'est ce qui garde le medaillon de
  /// fin de verset en Amiri quelle que soit l'ecriture choisie.
  /// ── LE SURLIGNEMENT SUIT LA LECTURE (2026-09-12) ──────────────────────
  ///
  /// Demande utilisateur : « lors de la lecture on a un surlignement sur la
  /// page par verset, est-ce qu'on peut avoir le meme rendu dans le mushaf
  /// papier ». La vue liste le fait depuis longtemps (`isPlayingCursor`) ;
  /// cette page-ci ne lisait tout simplement pas le lecteur.
  ///
  /// Une TEINTE de fond, pas un cadre : sur une page justifiee a la maniere
  /// d'un mushaf, un verset court sur plusieurs lignes -- un cadre devrait se
  /// refermer au bout de chacune et on verrait des boites empilees. Le fond
  /// suit le texte ligne par ligne, comme un surligneur passe sur une page.
  ///
  /// RECURSIF et par `copyWith` : les spans du tajwid portent deja leur encre
  /// et leurs enfants ; les ecraser eteindrait la coloration des regles sur le
  /// verset qu'on ecoute -- precisement celui qu'on regarde.
  TextSpan _surligner(TextSpan sp, Color teinte) => TextSpan(
        text: sp.text,
        style: (sp.style ?? const TextStyle())
            .copyWith(background: Paint()..color = teinte),
        children: sp.children
            ?.map((e) => e is TextSpan ? _surligner(e, teinte) : e)
            .toList(),
      );

  List<TextSpan> _spansCanoniques(List<Verse> versets, {bool couleur = true}) {
    final base = _policePage(famille: ecriture);
    final out = <TextSpan>[];
    // ── LES DEUX TEINTES SE VALENT A L'OEIL (2026-09-12) ────────────────
    //
    // Premiere version posee a vue : 0,13 sur parchemin et 0,20 sur fond
    // sombre, en se disant qu'une teinte « disparaitrait » sur du noir.
    // Constat utilisateur : « faut tenir du style, quand c'est noir c'est
    // plus visible ». Verifie par le calcul, et il avait raison -- le meme
    // alpha ne donne pas le meme ecart selon le fond :
    //
    //   parchemin #F3EAD6 (luminance 0,92) + vert700  a 0,13 -> saut  7,9 pts
    //   sombre    #0B0B0B (luminance 0,04) + dore     a 0,20 -> saut 15,4 pts
    //
    // Deux fois plus marque sur fond sombre, parce que l'ecart entre la
    // teinte et le fond y est bien plus grand : sur du noir, la moindre
    // couche claire saute aux yeux.
    //
    // On egalise donc sur le SAUT DE LUMINANCE, pas sur l'alpha : 0,103
    // rend exactement les memes 7,9 points que le mode clair. Le
    // surlignement se remarque autant dans les deux themes -- et jamais plus
    // que le texte qu'il accompagne.
    final teinte = sombre
        ? AppColors.brassLight.withValues(alpha: 0.10)
        : AppColors.green700.withValues(alpha: 0.13);
    for (final v in versets) {
      // Index de depart : tout ce que CE verset ajoute sera surligne d'un
      // bloc en fin de tour -- medaillon et marques de waqf compris, qui lui
      // appartiennent visuellement.
      final debutDuVerset = out.length;
      final estJoue = cleVersetJoue != null && v.key == cleVersetJoue;
      final mots = tajweedSpansPerWord(
        v.textUthmani,
        // `null` = aucune couleur empruntee a l'annotation : les mots sortent
        // dans l'encre de base, mais toujours decoupes de la meme facon.
        couleur ? v.textUthmaniTajweed : null,
        base,
        sombre: sombre,
      );
      // ⚠️ `tajweedSpansPerWord` ne rend que les mots RECITABLES : son filtre
      // est celui de la chaine de jugement, qui ecarte a dessein `۩` (sajda)
      // et `۞` (rub el hizb) -- un recitateur ne les prononce pas. Mais un
      // mushaf les IMPRIME. On reparcourt donc le verset et on remet en place
      // celles qui manquent. Constate a l'ecran le 2026-09-03 : sans cela, la
      // sajda d'Al-Isra 17:109 disparaissait de la page.
      var k = 0;
      for (final token in v.textUthmani.split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        if (ArabicNormalizer.normalize(token).isNotEmpty) {
          if (k < mots.length) {
            out.addAll(mots[k]);
          } else {
            out.add(TextSpan(text: token, style: base));
          }
          k++;
          out.add(TextSpan(text: ' ', style: base));
        } else {
          // ── LA MARQUE DE WAQF SE POSE SUR LE MOT, PAS ENTRE DEUX LIGNES ──
          //
          // Ces signes sont des marques HAUTES (leur nom Unicode le dit :
          // SMALL HIGH JEEM, SMALL HIGH LIGATURE SAD...), faites pour
          // surmonter une lettre. Le texte Hafs les encode isolees, entourees
          // d'espaces : sans lettre porteuse, elles flottent a leur hauteur
          // nominale au-dessus du vide et paraissent appartenir a la ligne du
          // dessus -- defaut signale a l'ecran le 2026-09-03.
          //
          // On retire donc l'espace qui les precede : la marque se rattache au
          // mot qu'elle concerne. C'est la forme que le texte WARSH du projet
          // utilise deja nativement (0 marque isolee sur 6236 versets) et
          // celle qu'un mushaf imprime.
          //
          // EXCEPTION : le rub el hizb `۞` n'est pas une marque de pause posee
          // sur un mot, c'est un ornement autonome qui s'imprime SEUL entre
          // deux mots. On le laisse detache.
          const rubElHizb = '\u06DE';
          if (warsh &&
              token != rubElHizb &&
              out.isNotEmpty &&
              out.last.text == ' ') {
            out.removeLast();
          }
          // ── LE SIGNE DE SAJDA EMPRUNTE SON DESSIN A UNE AUTRE POLICE ───
          //
          // « le signe de sajda ressemble plutot a une porte que le signe que
          // tu m'as fait » (2026-09-03). Le CARACTERE est le bon -- verifie
          // dans l'asset : U+06E9 ARABIC PLACE OF SAJDAH. C'est Amiri qui le
          // dessine en rosace florale, la ou un mushaf imprime une forme en
          // niche, rectangulaire.
          //
          // On ne change pas la police de la PAGE pour autant : des trois
          // essayees le 2026-09-03, Amiri est la seule a composer U+06DD (le
          // medaillon de fin de verset englobant son numero) ET a laisser les
          // harakat noires -- amiriQuran les rend ROUGES, scheherazadeNew ne
          // compose pas U+06DD. On emprunte donc le glyphe pour ce SEUL
          // caractere : aucun des deux defauts n'est reintroduit.
          out.add(
            TextSpan(
              text: token,
              style: token == '۩'
                  ? base.copyWith(
                      fontFamily: GoogleFonts.scheherazadeNew().fontFamily,
                    )
                  : base,
            ),
          );
          out.add(TextSpan(text: ' ', style: base));
        }
      }
      if (v.ayahNumber > 0) {
        // ── LE MEDAILLON GARDE TOUJOURS LE MEME DESSIN ──────────────────
        //
        // « si les chiffres des versets ne sont pas la ou il y a le signe,
        // parfois c'est noir » (2026-09-03), a verifier sur TOUS les styles.
        //
        // Mesure fontTools sur les 14 polices : U+06DD est de categorie
        // Unicode `Cf`, aucune police n'a de regle GSUB le liant aux chiffres,
        // et toutes ont une avance d'environ un cadratin -- le signe se pose
        // A COTE du numero. Quatre polices ne l'ont meme pas (Aref Ruqaa,
        // Reem Kufi, Markazi Text, Bouazzi Maghribi) : chez elles le medaillon
        // ne se dessine pas du tout.
        //
        // On rend donc CE fragment en Amiri quelle que soit l'ecriture du
        // texte -- meme montage que le signe de sajda. Amiri est embarquee
        // dans l'APK, ce repli tient donc hors ligne meme si l'ecriture
        // choisie, elle, doit encore se telecharger.
        out.add(
          TextSpan(
            text: '${_medaillon(v.ayahNumber)} ',
            style: base.copyWith(fontFamily: GoogleFonts.amiri().fontFamily),
          ),
        );
      }
      // Le verset est complet : on repasse dessus pour poser la teinte, d'un
      // seul geste. En fin de tour plutot qu'a chaque ajout -- les mots, les
      // marques de waqf, la sajda et le medaillon entrent par quatre chemins
      // differents plus haut, et en oublier un laisserait un trou blanc au
      // milieu du surlignement.
      if (estJoue) {
        for (var i = debutDuVerset; i < out.length; i++) {
          out[i] = _surligner(out[i], teinte);
        }
      }
    }
    return out;
  }

  /// [basmala] : posée en tête, sur sa propre ligne, quand le segment ouvre
  /// une sourate.
  ///
  /// ⚠️ ELLE DOIT ETRE ICI ET PAS SEULEMENT DANS `_spanMesure` : celle-là ne
  /// sert qu'à MESURER la hauteur. C'est `_bloc` qui PEINT. Premier essai du
  /// 2026-09-04 : la basmala n'avait été ajoutée qu'à la mesure, et elle
  /// n'apparaissait donc nulle part -- la page réservait la place d'une ligne
  /// qu'elle ne dessinait pas. Constat utilisateur : « je ne vois pas les
  /// bismillah dans le mushaf papier », vérifié page 77 (début d'An-Nisa).
  Widget _bloc(
    String texte,
    double taille,
    List<TextSpan>? spans, {
    double interligne = _kInterligne,
    String? basmala,
  }) {
    final style = _policePage(
      famille: ecriture,
      taille: taille,
      interligne: interligne,
      // Blanc pur sur fond sombre fatigue sur une page pleine de texte : on
      // reprend l'encre crème du reste de l'app plutôt que `sombreInk`.
      couleur: sombre ? AppColors.cream : const Color(0xFF1A1208),
    );
    // ── LA DERNIERE LIGNE N'EST PAS JUSTIFIEE, ET FLUTTER NE SAIT PAS ───
    //
    // Demande utilisateur 2026-09-03, deux rectangles rouges sur sa capture :
    // le blanc laisse par la derniere ligne d'Al-Isra et par celle d'Al-Kahf.
    // `TextAlign.justify` ne touche jamais la derniere ligne d'un paragraphe
    // -- regle typographique par defaut, celle de Word comme celle du web --
    // et Flutter n'expose aucun equivalent de `text-align-last: justify`.
    //
    // ⚠️ TENTATIVE MESUREE INEFFICACE, NE PAS LA REFAIRE : terminer le texte
    // par un saut de ligne (`'\$texte\n'`, et un `TextSpan(text: '\n')` en
    // queue pour la version coloree) devait faire que la ligne portant du
    // texte ne soit plus « la derniere », donc justifiable. Essaye le
    // 2026-09-03, build v256 : AUCUN effet, blanc identique sur la capture.
    // Le moteur traite une ligne terminee par un saut DUR comme une fin de
    // paragraphe et refuse de l'etirer, exactement comme la vraie derniere.
    //
    // La seule voie qui reste est de composer la derniere ligne soi-meme
    // (la decouper via `computeLineMetrics` et repartir ses mots), avec deux
    // couts a arbitrer : une ligne de deux ou trois mots etiree sur toute la
    // largeur donne des espaces enormes, et il faut redecouper les spans de
    // coloration tajwid au meme offset.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _avecBasmala(
        // `spans == null` : la basmala est déjà dans `texte`, la sortir ici la
        // doublerait. Sinon elle n'est PAS dans le flux et se peint à part.
        basmala: spans == null ? null : basmala,
        style: style,
        taille: taille,
        interligne: interligne,
        // ChGPT: RichText uses exactly the measured span, without inheriting
        // Material's letter spacing or paragraph defaults through Text.rich.
        corps: RichText(
          text: _spanMesure(texte, spans, style, taille),
          textAlign: TextAlign.justify,
          // ── `applyHeightToFirstAscent: false` RETIRE (2026-09-04) ────────
          //
          // Il avait ete pose le meme jour pour remonter le texte (« apres le
          // trait du haut, laisse juste un peu d'espace et commence
          // l'ecriture ») : l'interligne, qui monte jusqu'a 2,45 sur une page
          // peu remplie, gonfle aussi l'ascender de la PREMIERE ligne et la
          // faisait descendre d'une demi-ligne.
          //
          // Il marchait, mais au prix d'un defaut pire : sans cet ascender, les
          // diacritiques hautes de la premiere ligne sortent de la boite, et le
          // `ClipRect` de la page les COUPE. Constate a l'ecran page 2 -- la
          // basmala d'Al-Baqara rognee sur toute sa hauteur superieure.
          //
          // On le retire donc. Le texte redescend un peu ; c'est le bon cote de
          // l'erreur -- mieux vaut du blanc en haut qu'une ligne tronquee.
          // Pour gagner de la hauteur sans ce risque, ce sont les marges du
          // cadre et l'en-tete qu'il faut reprendre (deja fait le meme jour :
          // 19 -> 5 px en haut, en-tete 30 -> 26 px, separateur 62 -> 48 px).
        ),
      ),
    );
  }

  /// La basmala CENTRÉE sur sa propre ligne, au-dessus du corps du segment.
  ///
  /// ── POURQUOI UN WIDGET SÉPARÉ ET PAS UN `TextSpan` (2026-09-04) ─────────
  ///
  /// Demande utilisateur : « mets la bismillah au milieu, centrée ». Dans le
  /// flux c'était impossible : le corps de page est en `TextAlign.justify`, et
  /// un paragraphe justifié n'aligne pas une de ses lignes autrement que les
  /// autres -- la basmala se collait au bord droit comme n'importe quelle ligne
  /// de texte. Il faut qu'elle sorte du paragraphe pour avoir son propre
  /// alignement, ce qui est aussi sa place typographique dans un mushaf.
  ///
  /// La hauteur ne bouge pas : la ligne est déjà comptée par la mesure
  /// (`_spanMesure`), elle est simplement peinte ailleurs.
  Widget _avecBasmala({
    required String? basmala,
    required TextStyle style,
    required Widget corps,
    required double taille,
    required double interligne,
  }) {
    if (basmala == null) return corps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // HAUTEUR IMPOSÉE, et c'est tout l'enjeu : la mesure compte la basmala
        // comme UNE ligne du paragraphe. Un `Text` libre en prendrait un peu
        // plus (métriques de bloc), et ce surplus était volé au corps, dont la
        // dernière ligne se faisait couper. En l'enfermant dans exactement
        // `interligne × taille`, ce que la mesure prévoit est ce que le rendu
        // consomme -- il n'y a plus d'écart à rattraper ailleurs.
        // ── LA BASMALA COMMENÇAIT TROP BAS (2026-09-04) ──────────────────
        //
        // Constat utilisateur : « le début du Bismillah commence trop bas, il y
        // a de l'espace qu'on peut utiliser en haut ».
        //
        // DEUX CAUSES EMPILÉES, et `Align(topCenter)` n'en réglait aucune :
        //
        // 1. La boîte faisait `interligne × taille`, or l'interligne monte
        //    jusqu'à 2,45 quand la page est peu remplie (le reliquat devient de
        //    l'air, cf. « LE RELIQUAT DEVIENT DE L'INTERLIGNE »). À 45 pt, cela
        //    réservait 110 px pour une ligne qui en demande 55.
        // 2. Le style porte `height: interligne` : le glyphe est alors CENTRÉ
        //    dans sa propre boîte de ligne. Caler la boîte en haut ne servait à
        //    rien -- le texte, lui, restait au milieu de sa ligne.
        //
        // On lui donne donc sa hauteur propre (`_kBoiteBasmala`, serré autour
        // du glyphe) et un `height` de ligne resserré. La page démarre où elle
        // doit, et ce qui n'est plus réservé ici revient au corps du texte.
        // ── LA BASMALA DOIT TENIR DANS SA ZONE (2026-09-04) ──────────────
        //
        // Version precedente : boite serree (`_kBoiteBasmala`), texte cale en
        // haut (`Align.topCenter`) et `applyHeightToFirstAscent: false`. Le but
        // etait de remonter la page (« le debut commence trop bas »), et il
        // etait atteint -- mais la moitie SUPERIEURE du glyphe sortait alors de
        // la zone, et le `ClipRect` du segment la coupait net.
        //
        // Vu a l'ecran une fois les zones tracees en couleur (demande
        // utilisateur : « entoure les zones ou tu mets le texte avec du rouge,
        // comme ca je vois comment tu disposes la page ») : la basmala d'Al-
        // Baqara chevauchait le bord haut de son cadre. Aucune lecture de code
        // ne montrait ca ; le trace, si.
        //
        // On lui rend donc une ligne pleine et un centrage vertical. Elle
        // redescend de quelques pixels -- c'est le bon cote de l'erreur : mieux
        // vaut du blanc au-dessus qu'un texte tronque.
        // ChGPT 2026-09-09: its real height is measured alongside the body.
        // A taller font must not steal space from the final Quran line.
        RichText(
          text: _spanBasmala(basmala, style),
          textAlign: TextAlign.center,
        ),
        corps,
      ],
    );
  }

  /// ── LE CŒUR DE LA DEMANDE ────────────────────────────────────────────
  /// Cherche la plus GRANDE taille de police pour laquelle la page tient
  /// entièrement dans la hauteur disponible : le texte remplit alors le
  /// cadre d'un bord à l'autre, et une page dense (Al-Baqara) comme une page
  /// aérée occupent toutes deux la page complète -- au lieu d'un bloc qui
  /// flotte. Dichotomie : 9 mesures suffisent entre 12 et 46 pt.
  /// Ajuste la taille pour que TOUS les segments plus les bandeaux de
  /// separation tiennent dans la hauteur disponible.
  ///
  /// La mesure porte sur la SOMME des segments et sur la hauteur des bandeaux
  /// (2026-09-03) : mesurer un seul bloc, comme avant, ferait deborder la page
  /// des qu'un bandeau s'intercale entre deux sourates.
  /// Hauteur reelle de chaque segment, pour une taille et un interligne donnes.
  ///
  /// Extraite pour pouvoir etre RAPPELEE : la garde de debordement doit
  /// remesurer apres chaque recul, sinon elle valide une hauteur qui n'est
  /// plus celle qui sera peinte.
  List<double> _hauteursSegments(
    List<({int sourate, String texte, List<Verse> versets, String? basmala})>
        segments,
    List<List<TextSpan>>? spansParSegment,
    TextStyle style,
    double taille,
    double interligne,
    double largeur,
  ) {
    final out = <double>[];
    for (var s = 0; s < segments.length; s++) {
      final st = style.copyWith(fontSize: taille, height: interligne);
      final peintre = TextPainter(
        text: _spanMesure(segments[s].texte, spansParSegment?[s], st, taille),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.justify,
      )..layout(maxWidth: largeur);
      // ── LA BASMALA COMPTE COMME UNE LIGNE, A PART (2026-09-04) ────────
      //
      // Elle n'est plus dans le paragraphe mesure : le rendu la peint dans une
      // `SizedBox` a lui (elle doit etre CENTREE, ce qu'un paragraphe justifie
      // ne permet pas). Tant qu'elle etait comptee ici ET peinte la-bas, les
      // deux hauteurs ne coincidaient pas exactement et le corps perdait la
      // difference -- le `ClipRect` tranchait alors sa derniere ligne. On
      // ajoute donc EXACTEMENT ce que la boite consomme, ni plus ni moins.
      var hauteur = peintre.height;
      peintre.dispose();
      final basmala = spansParSegment == null ? null : segments[s].basmala;
      if (basmala != null) {
        final p = TextPainter(
          text: _spanBasmala(basmala, st),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
        )..layout(maxWidth: largeur);
        hauteur += p.height;
        p.dispose();
      }
      // ChGPT: this reserve is part of the fit AND of the rendered box.
      // Adding it only after fitting caused the yellow/black overflow stripe.
      out.add(hauteur + taille * _reserveBasMesuree(ecriture));
    }
    return out;
  }

  Widget _blocAjuste(
    List<({int sourate, String texte, List<Verse> versets, String? basmala})>
        segments,
    List<List<TextSpan>>? spansParSegment,
  ) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final style = _policePage(famille: ecriture);
        // 58 et non 46 : en dessous, le libelle des medaillons
        // (`آياتها`, `ترتيبها`) devient illisible.
        // La hauteur vient du widget lui-meme (`hauteurCompacte`), elle
        // n'est plus une valeur devinee ici : le bandeau la GARANTIT par
        // un `SizedBox`, donc la reservation ne peut pas etre fausse.
        const hauteurBandeau = MushafSurahBanner.compactHeight;
        final nBandeaux = segments.length - 1;
        // ── LA BASMALA COÛTE EXACTEMENT UNE LIGNE (2026-09-04) ───────────
        //
        // Elle est MESURÉE dans le paragraphe (`_spanMesure` la compte avec son
        // saut de ligne) mais PEINTE hors de lui, dans une `Column` -- ce
        // qu'exigeait le centrage. Un `Text` isolé porte ses propres métriques
        // de bloc, plus hautes qu'une ligne partageant l'interligne de ses
        // voisines : le corps recevait donc moins que ce qu'il avait demandé et
        // `Flexible` le comprimait. Dernière ligne tranchée, vu page 562.
        //
        // PREMIÈRE TENTATIVE, FAUSSE : réserver « un tiers de ligne » dans
        // `dispo`. Elle utilisait une taille de police SUPPOSÉE (40) alors que
        // la vraie n'est connue qu'à la fin de la dichotomie -- la réserve ne
        // correspondait donc à rien, et la ligne coupait toujours.
        //
        // CE QU'ON FAIT : la basmala est enfermée dans une hauteur EXACTE d'une
        // ligne (cf. `_avecBasmala`). Mesure et rendu coïncident alors par
        // construction, et il n'y a plus rien à compenser ici.
        final dispo = contraintes.maxHeight - nBandeaux * hauteurBandeau;

        // ── LA MISE EN PAGE MESUREE EST MISE EN CACHE (2026-09-13) ────────
        //
        // Ce qui suit est le point le plus couteux de l'application, mesure :
        // deux dichotomies de 12 et 8 tours, chacune appelant
        // `_hauteursSegments`, qui met en page le texte COMPLET de la page via
        // `TextPainter`. Soit une VINGTAINE de mises en page d'un texte
        // coranique entier, avec ses diacritiques et ses spans de tajwid, sur
        // l'isolate qui dessine -- et le tout dans un `LayoutBuilder`, donc
        // rejoue a chaque reconstruction, pour la page courante ET pour les
        // pages voisines que `PageView.builder` prepare.
        //
        // Ce que l'instrument a relevé (Redmi Note 9 Pro, build debug) :
        //     [Fluidite] construction p90=473ms p99=718..882ms
        // alors qu'une tranche sans construction de page donne p50=2,7 ms.
        // C'est ce qui fait perdre des gestes : pendant qu'une page se mesure,
        // la file d'evenements tactiles n'est pas servie -- 12 balayages
        // n'avaient fait tourner que 7 pages.
        //
        // ⚠️ CE CACHE NE CHANGE AUCUN RENDU, et c'est sa raison d'etre : pour
        // des entrees identiques, la dichotomie redonne EXACTEMENT le meme
        // resultat (elle est deterministe et ne lit aucun etat exterieur). On
        // ne modifie donc ni la taille de police, ni l'interligne, ni les
        // hauteurs -- on evite seulement de les recalculer. C'etait la
        // condition pour toucher a ce code : la mise en page du mushaf a
        // demande beaucoup d'allers-retours avec l'utilisateur, et un
        // correctif de performance n'a pas le droit d'en deplacer un pixel.
        //
        // La cle porte TOUT ce qui entre dans la mesure. Un oubli ici ne
        // produirait pas une erreur visible tout de suite, mais une page
        // rendue avec la mise en page d'une AUTRE configuration -- le genre de
        // defaut qui ne se voit qu'en changeant d'ecriture. Les dimensions
        // sont arrondies au pixel : `LayoutBuilder` peut rendre des
        // contraintes differant d'une fraction, ce qui ferait manquer le cache
        // a chaque frame sans rien changer au resultat.
        final cleMesure = '$page|$ecriture|$warsh|$tajwid|'
            '${contraintes.maxWidth.round()}x${contraintes.maxHeight.round()}|'
            '${segments.length}|${spansParSegment == null}';
        final dejaMesure = _cacheMiseEnPage[cleMesure];

        double basse = 0, haute = 52;
        double interligneRetenu;
        List<double> hauteurs;

        if (dejaMesure != null) {
          basse = dejaMesure.taille;
          interligneRetenu = dejaMesure.interligne;
          hauteurs = dejaMesure.hauteurs;
        } else {
        final tMesure = Stopwatch()..start();
        for (var i = 0; i < 12; i++) {
          final milieu = (basse + haute) / 2;
          final total = _hauteursSegments(segments, spansParSegment, style,
              milieu, _kInterligne, contraintes.maxWidth)
              .fold<double>(0, (a, b) => a + b);
          // Reserve de securite ABSOLUE et non proportionnelle : ce qu'elle
          // protege, c'est une diacritique haute de la DERNIERE ligne qui
          // depasse la hauteur annoncee par TextPainter. Ce depassement vaut
          // une fraction du corps -- il ne grandit pas avec la page. En
          // pourcentage (0,93 avant le 2026-09-03) il reservait ~125 px sur
          // une page de 1800 pour un besoin d'une quinzaine, et c'est ce vide
          // que l'utilisateur voyait en haut et en bas.
          if (total <= dispo) {
            basse = milieu;
          } else {
            haute = milieu;
          }
        }

        // ── LE RELIQUAT DEVIENT DE L'INTERLIGNE (2026-09-03) ──────────────
        //
        // « il y a de l'espace en hauteur, tu peux occuper tout l'ecran ». La
        // dichotomie s'arrete sur la plus grande taille qui TIENT : il reste
        // donc toujours jusqu'a une ligne entiere de rab. On le rend au texte
        // en ecartant les lignes, au lieu de le laisser en marges.
        // Plafond : sur une page peu remplie la police bute deja sur son
        // maximum et sans borne les quelques lignes s'etaleraient comme un
        // poeme. Au-dela, le reste redevient du vide centre -- le bon rendu
        // dans ce cas precis.

        // ── LA SOMME EST MESUREE, PAS SUPPOSEE (2026-09-03) ───────────────
        //
        // Defaut constate a l'ecran, page 4 : « la derniere ligne n'est pas
        // visible ». L'interligne definitif est DEDUIT d'une mesure faite a
        // l'interligne de reference ; rien ne garantissait que la hauteur
        // reelle, une fois l'interligne releve, tienne encore dans `dispo`.
        // Quand elle debordait, le `ClipRect` de la page -- pose la pour
        // empecher une diacritique de mordre le cadre -- coupait la derniere
        // ligne SANS RIEN DIRE. Un `ClipRect` masque un debordement, il ne le
        // corrige pas : c'est ce qui rendait le defaut invisible au calcul.
        //
        // On remesure donc apres chaque recul, et on recule tant que ca ne
        // rentre pas : d'abord en rendant l'air ajoute, ensuite en descendant
        // le corps. Certaines pages seront un peu moins pleines -- c'est le
        // bon cote de l'erreur : mieux vaut du blanc qu'une ligne coupee.
        // ChGPT: use the same complete measurement for both searches.
        // No minimum font size or capped recovery loop may hide page content.
        interligneRetenu = _kInterligne;
        var interligneMax = 2.45;
        hauteurs = _hauteursSegments(segments, spansParSegment, style,
            basse, interligneRetenu, contraintes.maxWidth);
        for (var essai = 0; essai < 8; essai++) {
          final milieu = (interligneRetenu + interligneMax) / 2;
          final mesure = _hauteursSegments(segments, spansParSegment, style,
              basse, milieu, contraintes.maxWidth);
          if (mesure.fold<double>(0, (a, b) => a + b) <= dispo) {
            interligneRetenu = milieu;
            hauteurs = mesure;
          } else {
            interligneMax = milieu;
          }
        }
        tMesure.stop();
        _cacheMiseEnPage[cleMesure] = (
          taille: basse,
          interligne: interligneRetenu,
          hauteurs: hauteurs,
        );
        // Borne memoire : chaque entree ne pese que quelques `double`, mais
        // rien n'empeche de parcourir les 604 pages dans plusieurs ecritures.
        // Eviction du plus ancien insere (les `Map` Dart conservent l'ordre
        // d'insertion) -- suffisant ici, ou ce qu'on relit est ce qu'on vient
        // de quitter.
        if (_cacheMiseEnPage.length > _kMaxPagesEnCache) {
          _cacheMiseEnPage.remove(_cacheMiseEnPage.keys.first);
        }
        DiagnosticLog.log(
            'Perf',
            'mise en page mesuree page=$page ecriture=$ecriture '
                '${tMesure.elapsedMilliseconds}ms '
                '(20 mises en page TextPainter, thread UI) — '
                'en cache : ${_cacheMiseEnPage.length} page(s)');
        }

        // ── LE TEXTE COMMENCE EN HAUT DE SON BLOC (2026-09-04) ───────────
        //
        // C'etait `MainAxisAlignment.center` : le reliquat de la dichotomie se
        // repartissait moitie au-dessus du texte, moitie en dessous. Sur une
        // page pleine ca ne se voyait pas ; sur les autres, une bande vide
        // s'installait entre l'en-tete et la premiere ligne.
        //
        // Vu par l'utilisateur une fois les zones tracees en couleur, et
        // formule exactement : « le bloc bleu doit commencer juste apres le
        // rouge, et le segment orange c'est le debut du texte -- pourquoi
        // doit-il commencer depuis la ligne bleue ? ». Mesure sur la capture
        // page 78 : environ 80 px de vide en haut, autant en bas.
        //
        // `start` : le texte demarre sous l'en-tete, et ce qui reste tombe en
        // bas, au-dessus du numero de page -- la ou un mushaf imprime le met.
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (var s = 0; s < segments.length; s++) ...[
              if (s > 0) _bandeauSourate(segments[s].sourate, hauteurBandeau),
              // ── LE CLIPRECT EST « LE TRUC QUI CACHE » (2026-09-04) ────
              //
              // Intuition de l'utilisateur, exacte : « il y a des coupures, je
              // pense que c'est un calque ou un truc qui cache ». C'en est un :
              // ce `ClipRect` découpe net tout ce qui dépasse de `hauteurs[s]`.
              // La ligne n'est pas mal dessinée, elle est TRANCHÉE -- d'où
              // cette moitié de lettres, qu'aucune taille de police n'explique.
              //
              // Il protège le pied de page d'un texte qui déborderait, donc on
              // le garde. Mais `TextPainter` rend une hauteur en flottant, et
              // le rendu réel peut demander une fraction de pixel de plus :
              // arrondi vers le bas, c'est la dernière ligne qui paie. Deux
              // pixels de tolérance absorbent l'arrondi sans rien laisser
              // déborder de visible.
              _zone(ClipRect(
                child: SizedBox(
                  // Tolérance PROPORTIONNELLE et non 2 px fixes : ce qui
                  // déborde, ce sont des jambages et des kasra, dont la taille
                  // suit la police. Deux pixels suffisaient à 20 pt, pas à 45.
                  // ChGPT: already includes the reserve used by the search.
                  height: hauteurs[s],
                  child: _bloc(
                    segments[s].texte,
                    basse,
                    spansParSegment?[s],
                    interligne: interligneRetenu,
                    basmala: segments[s].basmala,
                  ),
                ),
              ), Colors.orange),
            ],
          ],
        );
      },
    );
  }

  /// [basmala] : posée en tête, sur sa propre ligne, quand le segment ouvre
  /// une sourate.
  ///
  /// ⚠️ ELLE DOIT ÊTRE AJOUTÉE ICI ET PAS SEULEMENT DANS `texte` : dès que la
  /// coloration tajwid est active, `spans` est fourni et le paramètre `texte`
  /// n'est plus lu du tout (`spans ?? [...]`). La basmala aurait donc disparu
  /// exactement dans le mode où l'on regarde le plus la page.
  TextSpan _spanMesure(
    String texte,
    List<TextSpan>? spans,
    TextStyle style,
    double taille, {
    String? basmala,
  }) => TextSpan(
    style: style,
    children: [
      if (basmala != null && spans != null)
        TextSpan(text: '$basmala\n', style: style),
      ..._waqfSurLaLigne(
        spans ?? [TextSpan(text: texte, style: style)],
        style,
        taille,
      ),
    ],
  );

  TextSpan _spanBasmala(String texte, TextStyle style) => TextSpan(
    text: texte,
    style: style.copyWith(height: _kInterligne),
  );

  /// Separateur de sourate : L'ORNEMENT DE L'ECRAN DE LECTURE, en compact.
  ///
  /// Demande utilisateur 2026-09-03, capture de l'ecran de lecture a l'appui :
  /// « le signe que tu as cree ici c'est plutot joli, mieux que ce que tu me
  /// proposais tout a l'heure ». Les deux ecrans montrent donc desormais le
  /// MEME dessin -- medaillon vectoriel numerote, nom de la sourate flanque de
  /// ses filets a losange, lieu et nombre de versets en dessous.
  ///
  /// ── CE QU'IL REMPLACE, ET POURQUOI ON GARDE LA TRACE ──────────────────
  /// Version precedente (meme jour, retiree) : le MOTIF REEL du mushaf scanne
  /// (`assets/images/motif_bandeau.webp`, 90x115 px, 4,6 Ko) repete en fond,
  /// avec un cartouche blanc central et deux medaillons ronds dessines par
  /// dessus -- `آياتها` (nombre de versets) et `ترتيبها` (rang de la sourate),
  /// disposition relevee sur le scan de la page 293. Elle fonctionnait ; elle
  /// a simplement moins plu que celle-ci. L'asset n'est plus declare dans
  /// `pubspec.yaml` (poids inutile dans l'APK) mais le fichier reste sur le
  /// disque : le rebrancher tient a une ligne.
  ///
  /// ⚠️ PIEGE PAYE PAR CETTE VERSION RETIREE, qui reste vrai partout :
  /// `AspectRatio` dans une `Row` de hauteur contrainte reclame une largeur
  /// egale a la hauteur SANS tenir compte du padding vertical -- d'ou un
  /// « BOTTOM OVERFLOWED » a l'ecran. Calculer le diametre depuis la hauteur
  /// reellement disponible (`LayoutBuilder`), jamais via `AspectRatio`.
  ///
  /// Le voile sombre est le meme traitement que dans l'ecran de lecture
  /// (`_SurahBanner`) : l'ornement est un decor CLAIR, laisse tel quel il
  /// forme un pave blanc au milieu d'une page nocturne.
  Widget _bandeauSourate(int numero, double hauteur, {bool compact = true}) {
    var s = QuranApi.chapitresCharges
        ?.where((c) => c.number == numero)
        .firstOrNull;
    if (s == null) return SizedBox(height: hauteur);
    final compteWarsh = warsh ? QuranApi.warshMushafVerseCount(numero) : null;
    if (compteWarsh != null && compteWarsh != s.versesCount) {
      s = Surah(
        number: s.number,
        nameArabic: s.nameArabic,
        nameSimple: s.nameSimple,
        nameTranslationFr: s.nameTranslationFr,
        versesCount: compteWarsh,
        revelationPlace: s.revelationPlace,
      );
    }
    return SizedBox(
      height: hauteur,
      child: MushafSurahBanner(surah: s, compact: compact, dark: sombre),
    );
  }

  /// Fin de verset : le signe ۝ suivi du numéro en chiffres arabes orientaux.
  String _medaillon(int ayah) => '۝${_chiffresArabes(ayah)}';

  String _chiffresArabes(int n) {
    const chiffres = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => chiffres[int.parse(c)]).join();
  }
}
