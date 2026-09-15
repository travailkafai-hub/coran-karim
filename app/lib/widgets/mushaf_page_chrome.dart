import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/verse.dart';
import 'mushaf_ornamental_frame.dart';

/// Structure graphique d'une page de mushaf, dessinee uniquement par Flutter.
///
/// Les scans Warsh servent de reference de proportions et de vocabulaire
/// visuel. Aucun pixel de ces pages n'est embarque dans l'application.
/// Marge haute des deux ronds flottants du Mushaf (retour, signet).
///
/// ── UNE SEULE FORMULE, POUR TOUS LES TELEPHONES (2026-09-12) ─────────────
///
/// Demande utilisateur, apres les avoir vus poses trop bas : « est-ce qu'il y
/// a moyen de les faire encore remonter » -- puis, dans la foulee : « faut
/// gerer ca pour tenir compte des plusieurs telephones qui vont telecharger
/// l'app ».
///
/// Les deux naïvetes possibles sont ecartees :
///   * une VALEUR FIXE passerait sous l'encoche des uns et flotterait au
///     milieu de l'ecran des autres ;
///   * `SafeArea` ENTIER reserve toute la marge declaree -- c'est ce qui les
///     posait trop bas, et c'est ce qu'on corrige.
///
/// On prend donc une PART de ce que l'appareil declare, bornee des deux cotes.
/// Les deux boutons vivent aux BORDS gauche et droit, la ou ni encoche ni
/// poincon ne se placent (ils sont centres) : la marge haute n'a donc pas a
/// couvrir toute la hauteur d'une encoche, seulement a eviter la barre d'etat
/// quand elle est visible.
///
/// Bornes : au moins [_margeMin] pour les ecrans qui ne declarent aucune marge
/// (mode immersif, ou la barre d'etat est masquee) -- sans ce plancher le rond
/// collerait au pixel du bord ; au plus [_margeMax] pour les tablettes et les
/// encoches profondes, ou 45 % ferait redescendre le bouton sur le texte.
///
/// Testee sur les configurations reelles dans
/// `test/mushaf_marge_boutons_test.dart`.
double margeHauteBoutonsMushaf(BuildContext context) =>
    (MediaQuery.paddingOf(context).top * _partDeLaMarge).clamp(
      _margeMin,
      _margeMax,
    );

const double _partDeLaMarge = 0.45;
const double _margeMin = 4;
const double _margeMax = 64;

enum MushafFrameStyle { opening, regular }

class MushafPageChrome extends StatelessWidget {
  final MushafFrameStyle style;
  final bool dark;
  final bool sepia;
  final double verticalReserve;
  final Widget child;

  // ChGPT->ici : meme "3" que celui deja utilise plus bas pour `band.left`/
  // `band.right` (le filet du cadre est peint 3 px plus pres du bord que le
  // padding de contenu standard). Expose ici pour que l'en-tete
  // (`_PageMushaf._enTete`, mushaf_maquette_screen.dart) puisse annuler EXACTEMENT
  // ce meme ecart sur les cartouches, sans dupliquer le nombre a la main.
  static const double headerBleed = 3;

  const MushafPageChrome({
    super.key,
    required this.style,
    required this.dark,
    this.sepia = false,
    this.verticalReserve = 0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final opening = style == MushafFrameStyle.opening;
        // ── LE CADRE NE DOIT PAS CHANGER DE LARGEUR SELON LA PAGE (2026-09-13) ──
        //
        // Constat utilisateur, capture a l'appui : « le cadre qui entoure
        // l'ecran, a la difference des autres pages il est maintenant trop
        // large ». Mesure sur les deux pages : 72 px de bordure visible sur
        // une page d'OUVERTURE contre 26 px sur une page NORMALE -- pres de
        // 3x plus large.
        //
        // CAUSE : `horizontal` avait une formule differente pour les pages
        // d'ouverture (0,075 x largeur, jusqu'a 42 px) que pour les pages
        // normales (0,032 x largeur, jusqu'a 16 px) -- ecart introduit pour
        // « donner de l'air » au bandeau de titre (2026-09-04), a une epoque
        // ou le cadre actuel n'existait pas encore. `horizontal` pilote a la
        // fois le padding du CONTENU et la position du FILET (`band`) : les
        // elargir ensemble a fini par rendre le filet lui-meme visiblement
        // plus large que sur les autres pages, precisement ce que
        // l'utilisateur vient de signaler.
        //
        // Une seule formule desormais, quel que soit le style : le cadre
        // (et le padding qui l'accompagne) reste identique sur TOUTE page.
        final horizontal = (constraints.maxWidth * 0.032).clamp(10.0, 16.0);
        // ── LE CADRE REND DE LA HAUTEUR AU TEXTE (2026-09-04) ────────────
        //
        // Demande utilisateur : « revois le haut de la page, retravaille le
        // cadre de la page pour chercher de la hauteur ».
        //
        // Une page courante réservait jusqu'à 19 px en haut ET en bas -- 38 px
        // de bande vide, presque une ligne de texte, pour écarter le contenu
        // d'un simple filet ornemental. Le plafond descend à 13 px : le filet
        // respire encore, et la dichotomie récupère de quoi grandir la police
        // ou loger une ligne de plus.
        //
        // La page d'OUVERTURE gardait des proportions differentes (jusqu'a
        // 48 px contre 13 px) pour donner de l'air a son bandeau de titre.
        // ⚠️ REDUIT LE 2026-09-13, meme cause que pour `horizontal` juste
        // au-dessus -- constat utilisateur, capture a l'appui, « haut et le
        // bas c'est trop large » sur la page d'ouverture par rapport aux
        // autres : le FILET du cadre (`band`, plus bas) se trouvait repousse
        // loin du bord, sur cet axe comme sur l'horizontal, pour une raison
        // qui n'a rien a voir avec la hauteur FIXE du bandeau lui-meme
        // (`_bandeauSourate`, 76 px, cf. `MushafSurahBanner.openingHeight`).
        //
        // ⚠️ CORRECTION DU CORRECTIF (meme session) : j'avais d'abord ecrit
        // ici que la marge etait inutile au bandeau et je l'avais unifiee
        // partout, y compris pour le PADDING DU CONTENU. Constat immediat sur
        // capture : la fleche retour et le signet (`Positioned(top:
        // margeHauteBoutonsMushaf(context), ...)`, plus bas dans l'ecran
        // appelant) flottent a une position FIXE, independante de ce widget --
        // ils comptaient sur cette marge pour rester sous les medaillons du
        // bandeau. Sans elle, ils se dessinent DESSUS, medaillon a moitie
        // cache. La marge etait donc bien necessaire, mais pour une raison
        // STRUCTURELLE (degager des boutons flottants d'un autre widget),
        // jamais documentee comme telle -- pas pour le confort du bandeau.
        // Le FILET du cadre, lui, n'a aucune raison de la porter : seul le
        // PADDING DU CONTENU la reprend desormais, cf. [_margeHauteMinOuverture]
        // plus bas.
        // ChGPT: absorb the former outer whitespace into the painted frame,
        // while computing the text layout from exactly its previous height.
        final contentHeight = constraints.maxHeight - 2 * verticalReserve;
        final vertical = (contentHeight * 0.013).clamp(8.0, 13.0);
        // ── DEGAGER LES BOUTONS FLOTTANTS, PAGE D'OUVERTURE SEULEMENT ────
        //
        // 48 : diametre par defaut d'un `IconButton` (celui des boutons
        // retour/signet, non redefini a l'appel). `margeHauteBoutonsMushaf`
        // est la MEME fonction qui positionne ces boutons (cf. sa doc et
        // `test/mushaf_marge_boutons_test.dart`) -- aucune valeur inventee
        // ici, seulement la reutilisation de ce qui les place deja.
        // ── LE TEXTE S'ÉCARTE DU SIGNET (2026-09-14, demande utilisateur) ───
        //
        // Constat, capture à l'appui (page 3, Al-Baqara) : le signet et la
        // flèche de retour, qui flottent en haut à gauche, se posaient SUR la
        // première ligne. « Y a moyen de descendre un peu le texte pour
        // s'éloigner du signe signet, juste un peu ».
        //
        // CAUSE : ce dégagement existait déjà, mais `opening ? … : 0.0` le
        // réservait à la page d'ouverture. Les pages courantes, elles, faisaient
        // commencer le texte juste sous le filet -- alors qu'elles portent
        // exactement les mêmes boutons flottants.
        //
        // ⚠️ 12 px et non le dégagement complet (~44, la hauteur d'un bouton) :
        // les boutons occupent le seul coin haut-gauche, le texte est justifié
        // sur toute la largeur, et libérer leur hauteur entière coûterait une
        // ligne de texte SUR CHAQUE PAGE. On écarte, on ne dégage pas.
        //
        // ⚠️ ET CELA ANNULE EN PARTIE LE GAIN DU 2026-09-04 (« gagne un peu
        // d'espace en haut », ~6 px repris au profit du texte) : c'est voulu et
        // arbitré par la même personne, deux constats différents à dix jours
        // d'écart. Ne pas « re-optimiser » cette marge sans le lui redemander.
        final margeHauteMinOuverture =
            opening ? margeHauteBoutonsMushaf(context) + 48 : 12.0;

        return ColoredBox(
          color: dark ? const Color(0xFF111B19) : const Color(0xFFFFFEF6),
          child: CustomPaint(
            painter: MushafOrnamentalFramePainter(
              tone: dark
                  ? MushafFrameTone.dark
                  : sepia
                  ? MushafFrameTone.sepia
                  : MushafFrameTone.light,
              opening: opening,
              band: EdgeInsets.fromLTRB(
                horizontal - headerBleed,
                vertical * 0.40 - 1 + verticalReserve,
                horizontal - headerBleed,
                vertical - 2 + verticalReserve,
              ),
            ),
            child: Padding(
              // ── UN PEU D'ESPACE REPRIS EN HAUT (2026-09-04) ──────────────
              //
              // Demande utilisateur, après le constat de la dernière ligne
              // coupée : « sinon gagne un peu d'espace en haut ».
              //
              // La marge haute d'une page courante valait 19 px (le plafond de
              // `maxHeight * 0.018`) alors qu'elle ne sépare le texte QUE du
              // filet ornemental -- rien ne s'y écrit. Le bas, lui, porte le
              // numéro de page : le serrer rapprocherait deux choses lisibles.
              // On reprend donc un tiers en haut seulement, ~6 px rendus au
              // texte, et la page d'ouverture garde ses proportions (son
              // bandeau de titre a besoin d'air).
              padding: EdgeInsets.fromLTRB(
                horizontal,
                // 0,40 et non 0,66 (2026-09-04) : « remonte le texte ».
                // Cette marge ne separe le texte que du filet ornemental --
                // rien ne s'y ecrit, et chaque pixel rendu est du texte.
                // `max` avec `margeHauteMinOuverture` UNIQUEMENT en haut : le
                // bas ne porte aucun bouton flottant, rien a y degager.
                (vertical * 0.40 + verticalReserve)
                    .clamp(margeHauteMinOuverture, double.infinity),
                horizontal,
                vertical + verticalReserve,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Cartouche de debut/separation de sourate inspire des deux pages d'ouverture.
class MushafSurahBanner extends StatelessWidget {
  static const double openingHeight = 76;

  /// ── LE SÉPARATEUR RENDU PLUS DISCRET (2026-09-04) ────────────────────────
  ///
  /// Demande utilisateur : « diminue peut-être le dessin de séparation de
  /// sourate ». 62 px pour un cartouche intercalé DANS la page, c'était une
  /// ligne de texte entière consommée à chaque changement de sourate -- et une
  /// page peut en porter deux.
  ///
  /// Le gain est direct et non pas cosmétique : cette constante entre dans le
  /// calcul de la place disponible (`dispo = maxHeight - nBandeaux ×
  /// compactHeight`). Chaque pixel repris ici est rendu à la dichotomie, donc
  /// au texte.
  ///
  /// 48 et pas moins : le cartouche porte deux médaillons (nombre de versets,
  /// ordre de révélation) dont la taille suit cette hauteur. En dessous, leurs
  /// libellés `آياتها` et `ترتيبها` deviennent illisibles -- limite déjà
  /// constatée le 2026-09-03 sur le bandeau d'ouverture.
  static const double compactHeight = 48;

  final Surah surah;
  final bool compact;
  final bool dark;

  const MushafSurahBanner({
    super.key,
    required this.surah,
    required this.dark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? compactHeight : openingHeight;
    final ink = dark ? const Color(0xFFF3E7C3) : const Color(0xFF18140F);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Les médaillons suivent la hauteur du cartouche : 28 pour 48 px
          // garde la même proportion qu'avant (34 pour 62).
          final sealSize = compact ? 28.0 : 42.0;
          final sideInset = (constraints.maxWidth * 0.105).clamp(25.0, 52.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SurahBannerPainter(dark: dark)),
              ),
              Positioned(
                left: sideInset - sealSize / 2,
                child: _Seal(
                  size: sealSize,
                  label: 'آياتها',
                  value: _arabicDigits(surah.versesCount),
                  dark: dark,
                ),
              ),
              Positioned(
                right: sideInset - sealSize / 2,
                child: _Seal(
                  size: sealSize,
                  label: 'ترتيبها',
                  value: _arabicDigits(surah.number),
                  dark: dark,
                ),
              ),
              Positioned(
                left: constraints.maxWidth * 0.22,
                right: constraints.maxWidth * 0.22,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'سُورَةُ ${surah.nameArabic}',
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    style: GoogleFonts.amiri(
                      fontSize: compact ? 23 : 28,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Seal extends StatelessWidget {
  final double size;
  final String label;
  final String value;
  final bool dark;

  const _Seal({
    required this.size,
    required this.label,
    required this.value,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? const Color(0xFF294B42) : const Color(0xFF416F5E),
        border: Border.all(color: const Color(0xFFB59A5A), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 1,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textDirection: TextDirection.rtl,
              style: GoogleFonts.amiri(
                color: const Color(0xFFFFF9E9),
                fontSize: 9,
                height: 0.95,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.amiri(
                color: Colors.white,
                fontSize: 13,
                height: 0.9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahBannerPainter extends CustomPainter {
  final bool dark;

  const _SurahBannerPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Rect.fromLTWH(
      0,
      size.height * 0.18,
      size.width,
      size.height * 0.64,
    );
    final green = dark ? const Color(0xFF263D37) : const Color(0xFFDCE8DF);
    final deepGreen = dark ? const Color(0xFF89A99C) : const Color(0xFF416F5E);
    final gold = dark ? const Color(0xFF9B8551) : const Color(0xFFB59A5A);
    final paper = dark ? const Color(0xFF172421) : const Color(0xFFFFFEF6);

    canvas.drawRect(bar, Paint()..color = green);
    canvas.drawRect(
      bar.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = gold,
    );

    final motifPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = gold.withValues(alpha: 0.9);
    for (double x = 8; x < size.width; x += 18) {
      final center = Offset(x, size.height / 2);
      final diamond = Path()
        ..moveTo(center.dx, center.dy - 8)
        ..lineTo(center.dx + 6, center.dy)
        ..lineTo(center.dx, center.dy + 8)
        ..lineTo(center.dx - 6, center.dy)
        ..close();
      canvas.drawPath(diamond, motifPaint);
      canvas.drawCircle(center, 1.7, Paint()..color = deepGreen);
    }

    final left = size.width * 0.18;
    final right = size.width * 0.82;
    final top = size.height * 0.08;
    final bottom = size.height * 0.92;
    final notch = size.height * 0.14;
    final panel = Path()
      ..moveTo(left + notch, top)
      ..lineTo(right - notch, top)
      ..quadraticBezierTo(right, top, right, top + notch)
      ..lineTo(right + notch, size.height / 2)
      ..lineTo(right, bottom - notch)
      ..quadraticBezierTo(right, bottom, right - notch, bottom)
      ..lineTo(left + notch, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - notch)
      ..lineTo(left - notch, size.height / 2)
      ..lineTo(left, top + notch)
      ..quadraticBezierTo(left, top, left + notch, top)
      ..close();
    canvas.drawPath(panel, Paint()..color = paper);
    canvas.drawPath(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = deepGreen,
    );
  }

  @override
  bool shouldRepaint(covariant _SurahBannerPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

String _arabicDigits(int value) {
  const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return value.toString().split('').map((c) => digits[int.parse(c)]).join();
}
