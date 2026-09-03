import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/app_settings_provider.dart';
import '../models/riwaya.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/tajweed_text.dart';
import '../widgets/tajwid_help_sheet.dart' show kTajwidRuleInfo;
import '../l10n/app_localizations.dart';

/// MAQUETTE COMPARATIVE « vrai mushaf » (demande utilisateur 2026-09-01 :
/// « on dirait pas un mushaf [...] je demande pas d'enlever ce qu'on a mais
/// une possibilité en plus »).
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
/// Les contrôles (choix de variante, numéro de page) n'apparaissent qu'au
/// TOUCHER, puis s'effacent : hors comparaison, il ne reste que la page.
///
/// ── RÈGLE ABSOLUE RESPECTÉE ICI ───────────────────────────────────────────
/// Le texte coranique n'est JAMAIS modifié pour les besoins de la mise en
/// page. Aucun `tatweel` (ـ U+0640) n'est inséré pour étirer les mots, alors
/// que c'est la technique classique de justification arabe : ce serait
/// ajouter des caractères au texte révélé. La justification passe uniquement
/// par l'espacement natif, et l'ajustement par la taille de police.
enum VarianteMushaf {
  /// Page de mushaf dont la taille de texte s'AJUSTE pour remplir la page
  /// d'un bord à l'autre. C'est le rendu retenu.
  ///
  /// Les variantes « Actuel » (fond sombre au fil de l'eau) et « Mushaf »
  /// (page à taille de texte FIXE) ont été retirées le 2026-09-01 sur
  /// décision utilisateur : « enlève actuel, le mushaf, laisse que ajusté et
  /// photo ». Elles avaient rempli leur rôle -- servir de points de
  /// comparaison pour choisir -- et le choix est fait. Les garder aurait
  /// laissé deux onglets que personne n'ouvre devant deux qui comptent.
  /// L'affichage d'origine, lui, n'a pas bougé : il vit toujours dans
  /// `mushaf_screen.dart`, cet écran ne fait que s'ajouter à côté.
  mushafAjuste,

  /// PAGES PHOTO : l'image scannée d'un vrai mushaf Warsh (604 pages), au
  /// lieu d'un texte recomposé. C'est le seul rendu qui donne la mise en page
  /// AUTHENTIQUE -- y compris la pagination Warsh, que nos données JSON n'ont
  /// pas (elles portent la structure Hafs, cf. le constat du 2026-09-01).
  ///
  /// Contrepartie : une image est MORTE. Pas de coloration tajwid, pas de
  /// suivi de récitation, pas de sélection de mot. Sort possible à terme
  /// (« on verra après si on supprime également photo »).
  ///
  /// ⚠️ Les images ne sont PAS dans les assets : 604 pages pèsent ~118 Mo en
  /// WebP 1080 px (et 372 Mo dans leur JPEG d'origine -- les mettre en PDF ne
  /// changerait rien, un PDF est un conteneur, pas un compresseur). On les lit
  /// donc depuis le dossier de l'app sur l'appareil :
  ///   `<externe>/mushaf_warsh/page_001.webp` … page_604.webp
  /// Le jour où c'est livré, ce sera un téléchargement au premier usage, pas
  /// un embarquement dans l'APK -- Play plafonne l'install initial à 200 Mo.
  photo,
}

class MushafMaquetteScreen extends ConsumerStatefulWidget {
  final int pageInitiale;

  /// Riwaya de la lecture d'où l'on vient, quand cet écran est ouvert depuis
  /// le Mushaf. `null` = banc de recette, aucune lecture en cours.
  ///
  /// Sert UNIQUEMENT à ne pas mentir sur les pages photo : ce sont des scans
  /// Warsh. Les montrer sans rien dire à quelqu'un qui lit en Hafs afficherait
  /// un texte qui n'est pas le sien, avec une pagination qui n'est pas la
  /// sienne, et rien à l'écran ne le signalerait.
  final Riwaya? riwaya;

  const MushafMaquetteScreen(
      {super.key, this.pageInitiale = 1, this.riwaya});

  @override
  ConsumerState<MushafMaquetteScreen> createState() =>
      _MushafMaquetteScreenState();
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
const double _kInterligne = 1.72;

/// Charte du mushaf de reference, RELEVEE sur sa capture (2026-09-02) et non
/// choisie a l'oeil : extraction des couleurs par saturation, mesure des
/// bordures en pixels. Cf. le script `charte_reference.py` du scratchpad.
class _Charte {
  /// Papier : #FDFDF3, plus blanc que le creme qu'on utilisait (#FBF5E6).
  static const papier = Color(0xFFFDFDF3);
  /// Bande exterieure du cadre, 25 px sur 1080 dans la reference.
  static const cadreClair = Color(0xFFBAE7D2);
  /// Bande mediane.
  static const cadreMedian = Color(0xFF92CAB9);
  /// Filet fonce qui souligne le cadre.
  static const filet = Color(0xFF1A5B56);
  /// Vert des cartouches de legende.
  static const legende = Color(0xFF69BA9A);
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
TextStyle _policePage({double? taille, Color? couleur}) =>
    GoogleFonts.amiri(
      fontSize: taille,
      height: _kInterligne,
      fontWeight: FontWeight.w600,
      color: couleur,
    );

class _MushafMaquetteScreenState extends ConsumerState<MushafMaquetteScreen> {
  static const _kPages = 604;

  late int _page = widget.pageInitiale.clamp(1, _kPages);
  late final PageController _ctrl =
      PageController(initialPage: _page - 1);
  VarianteMushaf _variante = VarianteMushaf.mushafAjuste;
  bool _controles = true;

  /// Coloration tajwid sur les rendus TEXTE (pas sur les photos : une image
  /// est figée, ses couleurs sont celles de l'imprimeur).
  ///
  /// Activée par défaut -- c'est ce qui a été demandé, et c'est le principal
  /// avantage d'un texte recomposé sur un scan. L'interrupteur existe quand
  /// même : la couleur aide à apprendre les règles, elle gêne pour lire d'une
  /// traite, et les deux usages sont légitimes sur le même écran.
  bool _tajwid = true;

  @override
  void initState() {
    super.initState();
    // Plein écran : ni barre d'état ni boutons système. `immersiveSticky` les
    // ramène brièvement sur un balayage depuis le bord puis les re-masque --
    // le geste de feuilletage n'est donc jamais confisqué par le système.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // ROTATION (2026-09-01, demande utilisateur « pour les photos est-ce
    // qu'on peut gérer pivoter l'écran »). `main.dart` verrouille TOUTE
    // l'app en `portraitUp` : sans cette levée locale, tourner le téléphone
    // ne fait rien du tout ici non plus.
    //
    // On ne touche pas au réglage global : le verrou portrait a du sens pour
    // des écrans de liste et de réglages. C'est la page de mushaf qui est le
    // cas particulier -- une page scannée est un objet physique, on veut
    // pouvoir la tenir comme du papier, et en paysage deux pages tiennent
    // côte à côte comme un mushaf ouvert.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Sans cette restauration, TOUT le reste de l'app resterait sans barres
    // système après un passage par la maquette.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    // Les pages PHOTO n'y sont pas soumises : un scan a son propre papier,
    // l'assombrir donnerait une image grise, pas un mode nuit.
    final sombre = ref.watch(modeSombreProvider) &&
        _variante != VarianteMushaf.photo;
    return Scaffold(
      backgroundColor:
          sombre ? AppColors.sombreBg : const Color(0xFFF3EAD6),
      body: Stack(
        children: [
          // `reverse: true` : en lecture arabe on tourne les pages dans
          // l'autre sens qu'un livre latin. Balayer vers la DROITE avance
          // dans le mushaf, comme sur le papier.
          //
          // En PAYSAGE sur les pages photo, on passe à la double page : c'est
          // la forme réelle d'un mushaf ouvert, et c'est le seul cas où la
          // rotation apporte autre chose qu'une page plus petite. Les rendus
          // recomposés gardent une page unique -- leur texte se remet en page
          // tout seul et remplit déjà la largeur, les doubler ne montrerait
          // rien de plus.
          PageView.builder(
            controller: _ctrl,
            reverse: true,
            itemCount: _kPages,
            onPageChanged: (i) => setState(() => _page = i + 1),
            itemBuilder: (context, i) => _PageMushaf(
              page: i + 1,
              variante: _variante,
              tajwid: _tajwid,
              sombre: sombre,
              controlesVisibles: _controles,
              onTap: () => setState(() => _controles = !_controles),
            ),
          ),
          // Avertissement de RIWAYA, volontairement indépendant de
          // `_controles` : un bandeau qu'un tap fait disparaître laisserait
          // l'utilisateur devant un texte Warsh en croyant lire du Hafs. Il
          // reste tant que la contradiction est là.
          if (_variante == VarianteMushaf.photo &&
              widget.riwaya == Riwaya.hafs)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5A00).withValues(alpha: .93),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.cream, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ces pages sont un mushaf Warsh — vous lisez en '
                          'Hafs. Texte et pagination diffèrent.',
                          style: GoogleFonts.manrope(
                              color: AppColors.cream,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_controles) ...[
            Positioned(top: 0, left: 0, right: 0, child: _barreHaut()),
            Positioned(bottom: 0, left: 0, right: 0, child: _barreBas()),
          ],
        ],
      ),
    );
  }

  Widget _barreHaut() {
    const libelles = {
      VarianteMushaf.mushafAjuste: 'Ajusté',
      VarianteMushaf.photo: 'Photo',
    };
    return Container(
      color: AppColors.green900.withValues(alpha: 0.94),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.cream),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              for (final v in VarianteMushaf.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: () => setState(() => _variante = v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _variante == v
                              ? AppColors.brassLight
                              : Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          libelles[v]!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _variante == v
                                ? AppColors.green900
                                : AppColors.cream,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barreBas() {
    return Container(
      color: AppColors.green900.withValues(alpha: 0.94),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text('page $_page / $_kPages',
                    style: GoogleFonts.manrope(
                        color: AppColors.cream.withValues(alpha: 0.85),
                        fontSize: 12)),
              ),
              // Interrupteur tajwid : sans objet sur les pages photo, dont
              // les couleurs sont imprimées dans l'image. On le MASQUE plutôt
              // que de le griser -- un bouton grisé invite à chercher
              // pourquoi il ne répond pas.
              if (_variante != VarianteMushaf.photo)
                GestureDetector(
                  onTap: () => setState(() => _tajwid = !_tajwid),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _tajwid
                          ? AppColors.brassLight
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            _tajwid
                                ? Icons.palette_rounded
                                : Icons.palette_outlined,
                            size: 15,
                            color: _tajwid
                                ? AppColors.green900
                                : AppColors.cream),
                        const SizedBox(width: 6),
                        Text('Tajwid',
                            style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _tajwid
                                    ? AppColors.green900
                                    : AppColors.cream)),
                      ],
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
  final VarianteMushaf variante;
  final bool tajwid;
  final bool sombre;

  /// Les barres de controle sont-elles affichees ? Elles sont en overlay
  /// AU-DESSUS de la page : sans cette information, l'en-tete et le pied
  /// existent mais restent caches dessous.
  final bool controlesVisibles;

  final VoidCallback onTap;
  const _PageMushaf(
      {required this.page,
      required this.variante,
      required this.tajwid,
      required this.sombre,
      required this.controlesVisibles,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (variante == VarianteMushaf.photo) {
      // Pas de FutureBuilder sur QuranApi ici : l'image scannée porte déjà le
      // texte, aucune donnée verset n'est nécessaire pour la peindre.
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: _PagePhoto(page: page),
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: FutureBuilder<List<Verse>>(
        future: QuranApi.fetchVersesByPage(page),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Erreur : ${snap.error}',
                    style: GoogleFonts.manrope(color: Colors.redAccent)));
          }
          final versets = snap.data;
          if (versets == null) {
            return const Center(
                child:
                    CircularProgressIndicator(color: AppColors.brassLight));
          }
          if (versets.isEmpty) {
            return Center(
                child: Text('page $page vide',
                    style: GoogleFonts.manrope(color: AppColors.inkLight)));
          }
          return _pageMushaf(context, versets);
        },
      ),
    );
  }

  Widget _pageMushaf(BuildContext context, List<Verse> versets) {
    // ── UN SEGMENT PAR SOURATE (2026-09-03) ────────────────────────────
    // La page etait un seul flux de texte : deux sourates s'y suivaient sans
    // rien entre elles. On regroupe donc les versets par sourate, pour
    // pouvoir intercaler un bandeau de titre a chaque changement.
    final segments = <({int sourate, String texte, String annote})>[];
    for (final v in versets) {
      final mot = '${v.textUthmani} ${_medaillon(v.ayahNumber)}';
      final annote =
          '${v.textUthmaniTajweed ?? v.textUthmani} ${_medaillon(v.ayahNumber)}';
      if (segments.isNotEmpty && segments.last.sourate == v.surahNumber) {
        final d = segments.removeLast();
        segments.add((
          sourate: d.sourate,
          texte: '${d.texte} $mot',
          annote: '${d.annote} $annote',
        ));
      } else {
        segments.add((sourate: v.surahNumber, texte: mot, annote: annote));
      }
    }

    // COLORATION TAJWID : un jeu de spans PAR SEGMENT, meme raison que
    // ci-dessus (cf. 2026-09-01 pour le pourquoi de l'analyse unique et du
    // style de base sans taille ni couleur).
    final spansParSegment = tajwid
        ? [
            for (final s in segments)
              parseTajweedHtml(s.annote, _policePage(), sombre: sombre)
          ]
        : null;
    final sourates = versets.map((v) => v.surahNumber).toSet().toList()..sort();
    // Le juz et le hizb VIENNENT DES DONNEES (2026-09-02) : ils etaient
    // estimes a partir du numero de page, ce qui se trompe des qu'une page
    // enjambe une frontiere. `juz_number` et `hizb_number` sont dans
    // `quran_verses.json` depuis le debut.
    final juz = versets.map((v) => v.juzNumber).whereType<int>().toSet();
    final hizb = versets.map((v) => v.hizbNumber).whereType<int>().toSet();

    return SafeArea(
      child: Padding(
        // Marges resserrees : la page doit occuper l'ecran (demande
        // utilisateur), le decor remplace ce que les marges laissaient vide.
        // Haut et bas dégagés : les barres de contrôle sont en overlay
        // AU-DESSUS de la page ; sans cette réserve elles recouvraient
        // l'en-tête (sourate/hizb/juz) et le pied, qui existaient donc sans
        // jamais se voir.
        // Bande de 2,3 % de la largeur : sur 1080 px cela fait 25 px, la
        // mesure exacte de la reference.
        padding: EdgeInsets.fromLTRB(
            0, controlesVisibles ? 68 : 0, 0, controlesVisibles ? 56 : 0),
        child: Container(
          // ── CADRE ORNEMENTAL, EXTRAIT D'UN MUSHAF SCANNE (2026-09-03) ──
          //
          // Demande utilisateur : « peut-etre tu peux recuperer un peu de
          // graphisme qui se trouve dans photo pour ameliorer le rendu ».
          //
          // Il ne s'agit pas d'une imitation dessinee : c'est le cadre REEL
          // de la page 2 du mushaf scanne, decoupe avec son centre rendu
          // transparent (motifs floraux, coins, filets). 207 Ko en WebP a
          // 900 px de large -- aucune tentative de le redessiner en Flutter
          // n'aurait approche ce niveau de detail.
          //
          // `BoxFit.fill` et non `contain` : le cadre doit epouser la page,
          // quelle que soit la proportion de l'ecran. La deformation reste
          // faible (le cadre est en 1080x1543, la page en ~1080x1900) et
          // porte sur des motifs repetitifs, ou elle ne se voit pas.
          // BANDE DELIMITEUR FINE, calee sur la reference : 2,3 % de la
          // largeur pour la bande coloree, puis un filet. Tout le reste est
          // rendu au texte.
          decoration: BoxDecoration(
            color: sombre ? AppColors.sombreBgDeep : _Charte.cadreMedian,
          ),
          padding: const EdgeInsets.all(2),
          child: Stack(
            children: [
              Container(
            decoration: BoxDecoration(
              color: sombre ? AppColors.sombreBgDeep : _Charte.papier,
              border: Border.all(
                  color: sombre
                      ? AppColors.brass.withValues(alpha: 0.55)
                      : _Charte.filet,
                  width: 1.2),
            ),
            // ── RESERVE PROPORTIONNELLE AU CADRE (2026-09-03) ───────────
            // MESURE sur le scan d'origine : la fenetre interieure du cadre
            // va de x=238 a x=842 sur 1080, soit 22 % de reserve de chaque
            // cote ; et de y=340 a y=1403 sur 1543, soit 22 % en haut et
            // 9 % en bas.
            //
            // Une valeur FIXE (46 px, premier essai) ne pouvait pas marcher :
            // le cadre est etire a la taille de la page, sa bordure grandit
            // donc avec elle. Le texte passait dessous des que l'ecran
            // s'elargissait -- constate a l'ecran, moitie des lignes coupees.
            padding: EdgeInsets.zero,
            child: LayoutBuilder(builder: (context, cts) {
              // 4 % au lieu de 21,5 % : la bande fine ne mange plus la
              // page, donc la quasi-totalite de l'ecran revient au texte --
              // « tu occupes l'ecran pour que le texte soit visible ».
              // Au plus juste : la bande fine encadre deja, inutile d'y
              // ajouter du vide. Tout ce qui n'est pas cadre est du texte.
              final rx = cts.maxWidth * 0.028;
              final ryHaut = cts.maxHeight * 0.008;
              final ryBas = cts.maxHeight * 0.008;
              return Padding(
                padding: EdgeInsets.fromLTRB(rx, ryHaut, rx, ryBas),
                child: Column(
              children: [
                // ── TOUT POUR LA LECTURE (2026-09-03) ────────────────
                // Un seul bandeau en haut, un seul en bas, l'en-tete sur une
                // ligne, le pied reduit au numero de page. La legende tajwid
                // est retiree : elle prenait 5 lignes, soit ~12 % de la
                // hauteur, pour une information que la fiche d'un mot donne
                // en mieux (nom ET explication).
                _enTete(sourates, juz, hizb),
                _bandeauOrne(),
                const SizedBox(height: 2),
                // `ClipRect` : une diacritique haute de la derniere ligne
                // pouvait deborder du cadre (medaillon coupe, vu a l'ecran).
                Expanded(
                  child: ClipRect(
                      child: _blocAjuste(segments, spansParSegment)),
                ),
                _bandeauOrne(),
                _pied(sourates, juz),
              ],
                ),
              );
            }),
          ),
              // ── CADRE ORNEMENTAL RETIRE (2026-09-03) ────────────────
              // Il occupait 21,5 % de chaque cote, la ou la bande du mushaf
              // de reference en mesure 2,3 % (25 px sur 1080). Il ne
              // delimitait pas la page, il la mangeait -- « tu n'as que
              // superpose la photo avec ton texte ».
              // L'ASSET A ETE SUPPRIME AVEC LUI (207 Ko) : « pas de photo,
              // sinon ca va alourdir la taille de l'app pour rien ». Un asset
              // qu'aucun code ne charge pese quand meme dans l'APK. La
              // methode d'extraction reste consignee au graphe
              // (`mesure_cadre_se_decoupe_pas_se_redessine`) si le besoin
              // revient pour une page de titre de sourate.
            ],
          ),
        ),
      ),
    );
  }

  /// Bandeau decoratif : losanges et traits alternes, facon encadrement de
  /// mushaf imprime. Dessine et non image -- il suit la largeur reelle, prend
  /// la couleur du theme, et ne coute aucun asset a embarquer.
  Widget _bandeauOrne({bool epais = false}) {
    final c = sombre
        ? AppColors.brass.withValues(alpha: 0.6)
        : _Charte.cadreMedian;
    return SizedBox(
      height: epais ? 12 : 7,
      child: LayoutBuilder(builder: (context, cts) {
        final n = (cts.maxWidth / 16).floor().clamp(3, 60);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < n; i++)
              i.isEven
                  ? Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                          width: epais ? 5 : 3.6,
                          height: epais ? 5 : 3.6,
                          color: c))
                  : Container(
                      width: epais ? 7 : 5,
                      height: 1.2,
                      color: c.withValues(alpha: 0.55)),
          ],
        );
      }),
    );
  }

  /// Legende des couleurs tajwid, en pied de page.
  ///
  /// Ne liste QUE les regles reellement presentes dans la palette de
  /// `tajweed_text.dart` et nommees : une legende qui annonce une couleur
  /// absente de la page apprend une fausse correspondance. Deux colonnes,
  /// comme sur un mushaf imprime, pour tenir en trois lignes.
  Widget _legendeTajwid(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final entrees = [
      for (final e in kTajwidRuleInfo.entries)
        if (e.value.color != const Color(0xFF9E9E9E))
          (e.value.color, e.value.name(t)),
    ];
    // Doublons de couleur : deux classes peuvent partager une teinte (les
    // shafawi, par exemple). Une seule pastille par couleur, sinon la
    // legende repete la meme information.
    final vues = <int>{};
    final uniques = [
      for (final (c, nom) in entrees)
        if (vues.add(c.toARGB32())) (c, nom),
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        // Bloc pose sur le papier, pas des pastilles flottantes : la legende
        // doit se lire comme un cartouche, separee du texte coranique.
        color: sombre
            ? Colors.white.withValues(alpha: 0.04)
            : _Charte.legende.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _Charte.legende.withValues(alpha: 0.55)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 9,
        runSpacing: 1,
        children: [
          for (final (c, nom) in uniques)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 3),
                Text(nom,
                    style: GoogleFonts.manrope(
                        fontSize: 8,
                        color: sombre
                            ? AppColors.cream.withValues(alpha: 0.75)
                            : _Charte.filet)),
              ],
            ),
        ],
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
              color: sombre ? AppColors.brass : _Charte.filet),
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
  Widget _enTete(List<int> sourates, Set<int> juz, Set<int> hizb) {
    final style = GoogleFonts.amiri(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: sombre ? AppColors.brass : _Charte.filet);
    final gauche = [
      if (hizb.isNotEmpty) 'حزب ${_chiffresArabes(hizb.first)}',
      if (juz.isNotEmpty) 'جزء ${_chiffresArabes(juz.first)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(gauche, style: style),
          Flexible(
            child: Text(
              sourates.map((s) => 'سورة ${_nomSourate(s)}').join(' · '),
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloc(String texte, double taille, List<TextSpan>? spans) {
    final style = GoogleFonts.amiri(
      fontSize: taille,
      height: _kInterligne,
      // Blanc pur sur fond sombre fatigue sur une page pleine de texte : on
      // reprend l'encre crème du reste de l'app plutôt que `sombreInk`.
      color: sombre ? AppColors.cream : const Color(0xFF1A1208),
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: spans == null
          ? Text(texte, textAlign: TextAlign.justify, style: style)
          : Text.rich(
              TextSpan(style: style, children: spans),
              textAlign: TextAlign.justify,
            ),
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
  Widget _blocAjuste(
      List<({int sourate, String texte, String annote})> segments,
      List<List<TextSpan>>? spansParSegment) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final style = _policePage();
        // 58 et non 46 : en dessous, le libelle des medaillons
        // (`آياتها`, `ترتيبها`) devient illisible.
        const hauteurBandeau = 58.0;
        final nBandeaux = segments.length - 1;
        final dispo =
            contraintes.maxHeight - nBandeaux * hauteurBandeau;
        double basse = 12, haute = 52;
        for (var i = 0; i < 9; i++) {
          final milieu = (basse + haute) / 2;
          var total = 0.0;
          for (var s = 0; s < segments.length; s++) {
            final sp = spansParSegment?[s];
            final peintre = TextPainter(
              text: sp == null
                  ? TextSpan(
                      text: segments[s].texte,
                      style: style.copyWith(fontSize: milieu))
                  : TextSpan(
                      style: style.copyWith(fontSize: milieu), children: sp),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.justify,
            )..layout(maxWidth: contraintes.maxWidth);
            total += peintre.height;
          }
          // Marge de securite : une diacritique haute de la derniere ligne
          // depasse ce que TextPainter annonce.
          if (total <= dispo * 0.93) {
            basse = milieu;
          } else {
            haute = milieu;
          }
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var s = 0; s < segments.length; s++) ...[
              if (s > 0) _bandeauSourate(segments[s].sourate, hauteurBandeau),
              _bloc(segments[s].texte, basse, spansParSegment?[s]),
            ],
          ],
        );
      },
    );
  }

  /// Bandeau de titre de sourate, entre deux sourates d'une meme page.
  ///
  /// Le fond est le MOTIF REEL du mushaf scanne (90x115 px, 4,6 Ko), repete
  /// horizontalement ; le cartouche et les medaillons sont dessines par-dessus
  /// pour porter les donnees de CHAQUE sourate. Copier le bandeau entier
  /// n'aurait servi qu'a une sourate : son nom y est peint.
  ///
  /// Les deux medaillons reprennent ceux du mushaf : `آياتها` (nombre de
  /// versets) et `ترتيبها` (rang de la sourate).
  Widget _bandeauSourate(int numero, double hauteur) {
    const vert = Color(0xFF1A7A3C);
    final s = QuranApi.chapitresCharges
        ?.where((c) => c.number == numero)
        .firstOrNull;
    return Container(
      height: hauteur,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black87, width: 1.6),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fond : le motif du scan, repete. `repeat` et non `fill` -- un
          // etirement deformerait les entrelacs, qui sont faits pour se
          // repeter.
          Image.asset('assets/images/motif_bandeau.webp',
              repeat: ImageRepeat.repeatX,
              alignment: Alignment.centerLeft,
              fit: BoxFit.fitHeight),
          Row(
            children: [
              _medaillonSourate('آياتها', s?.versesCount ?? 0, vert),
              // Cartouche central : bords coupes comme sur le scan, pas un
              // rectangle arrondi.
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black87, width: 1.4),
                    borderRadius: BorderRadius.circular(hauteur * 0.28),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text('سورة ${_nomSourate(numero)}',
                          style: GoogleFonts.amiri(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: Colors.black)),
                    ),
                  ),
                ),
              ),
              _medaillonSourate('ترتيبها', numero, vert),
            ],
          ),
        ],
      ),
    );
  }

  /// Un des deux medaillons ronds du bandeau : le libelle au-dessus, le
  /// chiffre dedans -- disposition du mushaf.
  /// ⚠️ `LayoutBuilder` et non `AspectRatio` : dans une `Row` de hauteur
  /// contrainte, `AspectRatio` reclame une largeur egale a la hauteur SANS
  /// tenir compte du padding vertical -- d'ou un « BOTTOM OVERFLOWED » visible
  /// a l'ecran (2026-09-03). On calcule donc le diametre depuis la hauteur
  /// reellement disponible.
  Widget _medaillonSourate(String libelle, int valeur, Color vert) =>
      LayoutBuilder(builder: (context, cts) {
        final d = cts.maxHeight - 6;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: SizedBox(
            width: d,
            height: d,
            child: Container(
            decoration: BoxDecoration(
              color: vert,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(libelle,
                      style: GoogleFonts.amiri(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('$valeur',
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
            ),
          ),
        );
      });

  /// Fin de verset : le signe ۝ suivi du numéro en chiffres arabes orientaux.
  String _medaillon(int ayah) => '۝${_chiffresArabes(ayah)}';

  String _chiffresArabes(int n) {
    const chiffres = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => chiffres[int.parse(c)]).join();
  }
}

/// Une page PHOTO du mushaf Warsh scanné, lue depuis le stockage de l'app.
///
/// Pourquoi un fichier et pas un asset : cf. la doc de [VarianteMushaf.photo]
/// -- 604 pages ne rentrent pas dans un APK. Ce banc lit ce qui a été poussé
/// sur l'appareil, exactement comme le ferait un téléchargement à la demande.
class _PagePhoto extends StatefulWidget {
  final int page;
  const _PagePhoto({required this.page});

  @override
  State<_PagePhoto> createState() => _PagePhotoState();
}

class _PagePhotoState extends State<_PagePhoto> {
  /// Résolu une seule fois pour tout l'écran : `getExternalStorageDirectory`
  /// fait un aller-retour vers le natif, inutile de le payer à chaque page
  /// balayée.
  static Future<String?>? _racine;

  static Future<String?> _dossier() {
    return _racine ??= () async {
      final d = await getExternalStorageDirectory();
      return d == null ? null : '${d.path}/mushaf_warsh';
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _dossier(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.brassLight));
        }
        final numero = widget.page.toString().padLeft(3, '0');
        final fichier = File('${snap.data}/page_$numero.webp');
        if (!fichier.existsSync()) {
          return _absente(fichier.path);
        }
        // PLEINE LARGEUR + DÉFILEMENT VERTICAL (2026-09-01).
        //
        // Avant : `BoxFit.contain`, qui fait tenir la page ENTIÈRE dans
        // l'écran. En portrait c'est presque la même chose (l'écran est plus
        // étroit que la page, donc c'est la largeur qui contraint) -- mais en
        // paysage la hauteur devient la contrainte et la page se réduit à un
        // timbre au milieu de l'écran, avec deux grosses bandes vides sur les
        // côtés. C'est précisément ce qui a fait dire à l'utilisateur, en
        // pivotant : « c'est pour ajuster la largeur sur la largeur de
        // l'écran, et du coup la page s'affiche en scrollant en bas ».
        //
        // Donc : la page occupe TOUJOURS toute la largeur, et ce qui dépasse
        // se lit en défilant. C'est le comportement d'un lecteur de scan, et
        // il vaut dans les deux orientations -- inutile de le conditionner à
        // `Orientation.landscape`, en portrait le défilement est simplement
        // très court.
        //
        // Le défilement est VERTICAL et le `PageView` qui tourne les pages
        // est HORIZONTAL : les deux gestes ne se disputent rien.
        //
        // ⚠️ Le zoom par pincement (`InteractiveViewer`) a été RETIRÉ ici, et
        // ce n'est pas un oubli : superposé au défilement vertical et au
        // balayage de page, cela faisait trois gestes concurrents sur la même
        // surface, où le pincement volait régulièrement le défilement. La
        // pleine largeur couvre le besoin de lisibilité qui motivait le zoom.
        // À rétablir seulement si l'usage montre qu'il manque -- et alors sur
        // un geste qui ne rentre pas en conflit (double-tap, par exemple).
        return SingleChildScrollView(
          child: Image.file(
            fichier,
            fit: BoxFit.fitWidth,
            width: double.infinity,
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
  }

  /// Ne PAS masquer l'absence par une page blanche : sur un banc, un fichier
  /// manquant et une image illisible se ressemblent à l'écran, et on conclut
  /// sur le mauvais des deux.
  Widget _absente(String chemin) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                color: AppColors.inkLight, size: 40),
            const SizedBox(height: 12),
            Text('Page ${widget.page} absente',
                style: GoogleFonts.manrope(
                    color: AppColors.inkLight,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 6),
            Text(chemin,
                textAlign: TextAlign.center,
                style: GoogleFonts.robotoMono(
                    color: AppColors.inkLight.withValues(alpha: .6),
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
