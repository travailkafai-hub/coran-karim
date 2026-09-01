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
  final VoidCallback onTap;
  const _PageMushaf(
      {required this.page,
      required this.variante,
      required this.tajwid,
      required this.sombre,
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
          return _pageMushaf(versets);
        },
      ),
    );
  }

  Widget _pageMushaf(List<Verse> versets) {
    final texte = versets
        .map((v) => '${v.textUthmani} ${_medaillon(v.ayahNumber)}')
        .join(' ');

    // COLORATION TAJWID (2026-09-01). Les données sont déjà en local : le
    // champ `text_uthmani_tajweed` est renseigné sur 6236/6236 versets en
    // Hafs. En Warsh il ne l'est que sur 1 verset (la Bismillah) -- d'où le
    // repli sur le texte nu, verset par verset, qui donne du texte noir
    // correct plutôt qu'une page à moitié colorée.
    //
    // Le style de base est VOLONTAIREMENT sans `fontSize` ni `color` : ces
    // deux propriétés sont portées par le TextSpan racine dans `_bloc`, et
    // les spans colorés n'y surchargent que la couleur. C'est ce qui permet
    // à l'auto-ajustement de faire varier la taille SANS re-parser le HTML à
    // chaque itération -- 9 analyses de page par rendu, ce serait ruineux.
    final spans = tajwid
        ? parseTajweedHtml(
            versets
                .map((v) =>
                    '${v.textUthmaniTajweed ?? v.textUthmani} ${_medaillon(v.ayahNumber)}')
                .join(' '),
            GoogleFonts.amiri(height: 2.0),
            // `tajweed_text.dart` porte une seconde palette, calculée pour un
            // fond noir (`_pourFondNoir`). Réutiliser la palette claire sur
            // fond sombre donnerait des rouges et des bleus qui vibrent et
            // deviennent illisibles -- le travail est déjà fait, il suffit de
            // le demander.
            sombre: sombre,
          )
        : null;
    final sourates = versets.map((v) => v.surahNumber).toSet().toList()..sort();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Container(
          decoration: BoxDecoration(
            color: sombre ? AppColors.sombreBgDeep : const Color(0xFFFBF5E6),
            border: Border.all(
                color: sombre
                    ? AppColors.brass.withValues(alpha: 0.65)
                    : AppColors.brass,
                width: 2.5),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(5),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: AppColors.brass.withValues(alpha: 0.55), width: 1),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                _enTete(sourates),
                const SizedBox(height: 6),
                Expanded(
                  child: _blocAjuste(texte, spans),
                ),
                Divider(
                    color: AppColors.brass.withValues(alpha: 0.4), height: 14),
                Text(_chiffresArabes(page),
                    style:
                        GoogleFonts.amiri(fontSize: 15, color: AppColors.brass)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enTete(List<int> sourates) {
    // Juz approximé sur la page (604 pages / 30 juz) : c'est une MAQUETTE
    // dont le sujet est le rendu, pas l'exactitude des métadonnées.
    final juz = ((page - 1) ~/ 20 + 1).clamp(1, 30);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('جزء ${_chiffresArabes(juz)}',
            style: GoogleFonts.amiri(
                fontSize: 13.5,
                color: AppColors.brass.withValues(alpha: 0.9))),
        Text(
          sourates.map((s) => 'سورة ${_chiffresArabes(s)}').join(' · '),
          style: GoogleFonts.amiri(
              fontSize: 13.5, color: AppColors.brass.withValues(alpha: 0.9)),
        ),
      ],
    );
  }

  Widget _bloc(String texte, double taille, List<TextSpan>? spans) {
    final style = GoogleFonts.amiri(
      fontSize: taille,
      height: 2.0,
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
  Widget _blocAjuste(String texte, List<TextSpan>? spans) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final style = GoogleFonts.amiri(height: 2.0);
        double basse = 12, haute = 46;
        for (var i = 0; i < 9; i++) {
          final milieu = (basse + haute) / 2;
          // La MESURE doit porter sur ce qui sera réellement peint : mesurer
          // le texte nu puis afficher les spans donnerait une taille fausse
          // dès que la coloration change le découpage des lignes.
          final peintre = TextPainter(
            text: spans == null
                ? TextSpan(text: texte, style: style.copyWith(fontSize: milieu))
                : TextSpan(
                    style: style.copyWith(fontSize: milieu), children: spans),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.justify,
          )..layout(maxWidth: contraintes.maxWidth);
          if (peintre.height <= contraintes.maxHeight) {
            basse = milieu;
          } else {
            haute = milieu;
          }
        }
        return _bloc(texte, basse, spans);
      },
    );
  }

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
