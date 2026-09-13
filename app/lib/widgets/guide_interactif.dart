// Visite guidée : une main 👆 se promène sur l'écran, se pose sur un vrai
// bouton, et l'application navigue pour de bon.
//
// ── CE QUE L'UTILISATEUR A DEMANDÉ (2026-09-13) ──────────────────────────────
//
// D'abord : « un tutoriel interactif dans l'application, avec une main animée
// qui montre les appuis et les défilements ».
// Puis, devant la première version : « c'est moche, moi je veux vraiment un
// style, une emoji main qui se balade, navigue et fait découvrir
// l'application ».
//
// Les trois mots comptent, et chacun a une conséquence ici :
//
//   « emoji »    -> la main est un vrai emoji 👆, pas une icône Material.
//                   Rien à embarquer dans l'APK, et le rendu est celui du
//                   téléphone.
//   « se balade » -> elle GLISSE d'une cible à l'autre, en traversant l'écran,
//                   au lieu d'apparaître/disparaître. C'est ce déplacement
//                   continu qui donne l'impression d'une main, et c'est
//                   exactement ce qui manquait à la première version.
//   « navigue »  -> chaque étape porte une [EtapeGuide.action] : quand la main
//                   se pose, l'APPLICATION CHANGE VRAIMENT d'écran. Une main
//                   qui désigne sans que rien ne se passe ne fait pas
//                   découvrir l'application, elle la commente.
//
// ── LA LIMITE QUI NE BOUGE PAS ───────────────────────────────────────────────
//
// ⚠️ AUCUN ÉVÉNEMENT TACTILE N'EST SYNTHÉTISÉ. La main ne « clique » pas : à
// l'instant où elle se pose, on appelle [EtapeGuide.action], une fonction
// fournie par l'écran hôte, qui fait elle-même la navigation (changer
// d'onglet, ouvrir une page). Ce composant n'a aucun accès au
// `GestureBinding`, ne crée aucun `PointerEvent`.
//
// C'est la traduction technique d'une consigne explicite : « les autorisations
// du téléphone resteraient à accepter par l'utilisateur, jamais par la main
// simulée ». Un guide qui saurait produire un appui saurait aussi accepter une
// permission à la place de quelqu'un — et une boîte de dialogue système ne se
// distingue pas d'un bouton de l'app pour du code qui pousse des événements.
// La seule garantie solide est l'incapacité, pas la bonne volonté.
//
// ⚠️ Corollaire pour qui ajoutera des étapes : ne JAMAIS mettre dans `action`
// quelque chose qui déclenche une demande de permission (micro, position,
// notifications). La visite montre où ça se trouve ; c'est l'utilisateur qui
// appuie.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Le geste qu'une étape illustre.
enum GesteGuide {
  /// La main se pose et appuie (pulsation + onde).
  appui,

  /// La main traverse la zone, de [EtapeGuide.depart] vers
  /// [EtapeGuide.arrivee].
  balayage,

  /// On montre sans rien faire. Pas d'onde d'appui.
  regarder,
}

/// Une étape : une zone réelle, un mot, et ce que l'app fait à cet instant.
class EtapeGuide {
  /// Clé posée sur le VRAI widget à désigner.
  ///
  /// ⚠️ La position est lue à l'exécution sur le `RenderBox` de cette clé,
  /// jamais écrite en coordonnées. Des coordonnées en dur seraient fausses dès
  /// qu'on change de téléphone — et la règle du projet est que le travail doit
  /// être « fonctionnel sur n'importe quel téléphone ». Cible absente (écran
  /// pas encore construit, élément hors champ) : la main se pose au centre et
  /// aucun trou n'est percé, plutôt que d'éclairer le mauvais endroit.
  final GlobalKey? cible;

  final String titre;

  /// Une phrase. Deux au plus. On montre, on ne disserte pas — c'est ce qui
  /// distingue cette visite de `onboarding_screen.dart`, qui explique.
  final String texte;

  final GesteGuide geste;

  /// Ce que l'application fait quand la main se pose. Appelé UNE fois par
  /// étape. `null` = on désigne sans rien changer.
  ///
  /// Ne doit jamais déclencher une demande de permission (cf. l'en-tête).
  final Future<void> Function()? action;

  /// Pour [GesteGuide.balayage] : fractions de la zone (−1..1, comme
  /// `Alignment`), pas des pixels — même raison que [cible].
  final Alignment depart;
  final Alignment arrivee;

  final double rayon;
  final double marge;

  /// Temps de lecture après l'appui, avant de filer vers l'étape suivante.
  final Duration pause;

  const EtapeGuide({
    required this.titre,
    required this.texte,
    this.cible,
    this.geste = GesteGuide.appui,
    this.action,
    this.depart = Alignment.centerRight,
    this.arrivee = Alignment.centerLeft,
    this.rayon = 16,
    this.marge = 10,
    this.pause = const Duration(milliseconds: 2600),
  });
}

/// Pose la visite par-dessus l'écran courant.
///
/// À placer dans un `Stack`, au-dessus du contenu réel — et non dans un
/// `OverlayEntry` : la visite doit mourir avec l'écran qu'elle commente. Un
/// `OverlayEntry` oublié survit à la navigation et laisse un calque figé
/// au-dessus d'un autre écran (défaut classique, pénible à diagnostiquer).
class VisiteGuidee extends StatefulWidget {
  final List<EtapeGuide> etapes;
  final VoidCallback onTermine;

  /// Libellés déjà traduits, fournis par l'appelant.
  final String libellePasser;
  final String libelleSuivant;
  final String libelleFin;

  const VisiteGuidee({
    super.key,
    required this.etapes,
    required this.onTermine,
    required this.libellePasser,
    required this.libelleSuivant,
    required this.libelleFin,
  });

  @override
  State<VisiteGuidee> createState() => _VisiteGuideeState();
}

/// Les phases d'une étape. Nommées plutôt que numérotées : la séquence est la
/// chorégraphie, et elle doit se lire.
enum _Phase { glisse, appuie, agit, lit }

class _VisiteGuideeState extends State<VisiteGuidee>
    with TickerProviderStateMixin {
  int _index = 0;
  _Phase _phase = _Phase.glisse;
  bool _fini = false;

  /// Où la main se trouve, et où elle va. En coordonnées écran.
  Offset _mainDe = Offset.zero;
  Offset _mainVers = Offset.zero;
  Rect? _zone;

  /// Glissement de la main d'une cible à l'autre.
  late final AnimationController _glisse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Battement continu : appui, onde, respiration du halo.
  late final AnimationController _battement = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void initState() {
    super.initState();
    final taille =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    final ratio =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    // La main entre par le bas de l'écran, comme une vraie main. Partir du
    // centre donnerait une apparition, pas une arrivée.
    _mainDe = Offset(taille.width / ratio / 2, taille.height / ratio + 80);
    _mainVers = _mainDe;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jouerEtape());
  }

  @override
  void dispose() {
    _glisse.dispose();
    _battement.dispose();
    super.dispose();
  }

  Rect? _mesurer(EtapeGuide etape) {
    final ctx = etape.cible?.currentContext;
    if (ctx == null) return null;
    final rendu = ctx.findRenderObject();
    if (rendu is! RenderBox || !rendu.hasSize) return null;
    return (rendu.localToGlobal(Offset.zero) & rendu.size)
        .inflate(etape.marge);
  }

  /// La chorégraphie d'une étape, de bout en bout.
  ///
  /// Écrite en une seule fonction `async` plutôt qu'en rappels chaînés : la
  /// séquence EST le comportement, et elle doit se lire dans l'ordre où elle
  /// se produit. Chaque `await` est suivi d'un `if (!mounted) return` — sans
  /// quoi un « Passer » pendant une animation ferait continuer la visite sur
  /// un widget démonté.
  Future<void> _jouerEtape() async {
    if (!mounted || _fini) return;
    final etape = widget.etapes[_index];

    // 1. Repérer la cible et glisser jusqu'à elle.
    final zone = _mesurer(etape);
    final cible = zone?.center ??
        Offset(MediaQuery.sizeOf(context).width / 2,
            MediaQuery.sizeOf(context).height / 2);
    setState(() {
      _zone = zone;
      _phase = _Phase.glisse;
      _mainDe = _mainVers;
      _mainVers = etape.geste == GesteGuide.balayage && zone != null
          ? _pointDe(zone, etape.depart)
          : cible;
    });
    _glisse.forward(from: 0);
    await _glisse.forward().orCancel.catchError((_) {});
    if (!mounted || _fini) return;

    // 2. Le geste : appui sur place, ou traversée.
    setState(() => _phase = _Phase.appuie);
    if (etape.geste == GesteGuide.balayage && zone != null) {
      setState(() {
        _mainDe = _pointDe(zone, etape.depart);
        _mainVers = _pointDe(zone, etape.arrivee);
      });
      await _glisse.forward(from: 0).orCancel.catchError((_) {});
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (!mounted || _fini) return;

    // 3. L'application agit VRAIMENT. Aucun événement tactile n'est
    //    synthétisé : c'est l'écran hôte qui exécute sa propre navigation.
    setState(() => _phase = _Phase.agit);
    if (etape.action != null) {
      await etape.action!();
      if (!mounted || _fini) return;
      // Laisser la nouvelle page se construire avant de mesurer la cible
      // suivante : mesurer trop tôt rendrait `null` et la main se poserait au
      // centre, sur rien.
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted || _fini) return;
    }

    // 4. Temps de lecture, puis on enchaîne.
    setState(() => _phase = _Phase.lit);
    await Future<void>.delayed(etape.pause);
    if (!mounted || _fini) return;
    _suivant();
  }

  Offset _pointDe(Rect r, Alignment a) => Offset(
        r.left + (a.x + 1) / 2 * r.width,
        r.top + (a.y + 1) / 2 * r.height,
      );

  void _suivant() {
    if (_index + 1 >= widget.etapes.length) {
      _terminer();
      return;
    }
    setState(() => _index++);
    _jouerEtape();
  }

  void _terminer() {
    if (_fini) return;
    _fini = true;
    widget.onTermine();
  }

  @override
  Widget build(BuildContext context) {
    final etape = widget.etapes[_index];
    final taille = MediaQuery.sizeOf(context);
    final dernier = _index == widget.etapes.length - 1;

    return Stack(
      children: [
        // Le voile. `IgnorePointer` : il ne doit rien intercepter, pour que
        // l'utilisateur puisse appuyer POUR DE VRAI sur l'élément éclairé s'il
        // préfère faire le geste lui-même.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _battement,
              builder: (_, _) => CustomPaint(
                painter: _Voile(
                  zone: _zone,
                  rayon: etape.rayon,
                  battement: _battement.value,
                  actif: _phase != _Phase.glisse,
                ),
              ),
            ),
          ),
        ),
        _ruban(context, etape, taille, dernier),
        _main(etape),
      ],
    );
  }

  /// La main. Un emoji, comme demandé.
  Widget _main(EtapeGuide etape) {
    return AnimatedBuilder(
      animation: Listenable.merge([_glisse, _battement]),
      builder: (context, _) {
        final avance = Curves.easeInOutCubic.transform(_glisse.value);
        final p = Offset.lerp(_mainDe, _mainVers, avance)!;

        // Pendant le glissement, la main s'incline vers l'avant et s'éloigne un
        // peu — comme une main qui se soulève pour changer de place. C'est ce
        // détail qui fait la différence entre « un emoji téléporté » et « une
        // main qui se balade ».
        final enVol = _phase == _Phase.glisse && _glisse.isAnimating;
        final hauteur = enVol ? Curves.easeInOut.transform(
            (1 - (avance - 0.5).abs() * 2).clamp(0.0, 1.0)) : 0.0;
        final inclinaison =
            enVol ? (_mainVers.dx - _mainDe.dx).sign * 0.18 * hauteur : 0.0;

        // L'appui : la main descend brièvement, deux fois par cycle.
        final appuie = _phase == _Phase.appuie || _phase == _Phase.agit;
        final enfonce = appuie
            ? 6 * Curves.easeOut.transform(
                (1 - (_battement.value * 2 % 1 - 0.5).abs() * 2))
            : 0.0;

        // ── LA MAIN NE DOIT JAMAIS SORTIR DE L'ÉCRAN (2026-09-13) ──────────
        //
        // Vu à l'écran dès le premier essai : sur l'onglet du bas, l'emoji
        // était posé SOUS la barre de navigation et se retrouvait à moitié
        // coupé par le bord. La cause est structurelle et reviendra pour toute
        // cible basse : 👆 pointe vers le haut, donc on le place *en dessous*
        // du point visé -- ce qui, pour une cible déjà en bas d'écran, tombe
        // hors du cadre.
        //
        // On borne donc la position. Quand la cible est trop basse, la main
        // remonte et se pose SUR elle plutôt qu'en dessous : le doigt couvre
        // un peu le bouton, ce qui est infiniment préférable à une main
        // tronquée -- le halo doré désigne déjà la zone sans ambiguïté.
        final ecran = MediaQuery.sizeOf(context);
        const hauteurEmoji = 56.0;
        final y = (p.dy + 2 + enfonce - hauteur * 16)
            .clamp(0.0, ecran.height - hauteurEmoji);
        final x = (p.dx - 16).clamp(0.0, ecran.width - 46);

        return Positioned(
          // L'index de 👆 pointe vers le HAUT : on place donc l'emoji sous le
          // point visé, décalé pour que le bout du doigt tombe dessus. Centrer
          // l'emoji ferait pointer le doigt au-dessus de la cible.
          left: x,
          top: y,
          child: IgnorePointer(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (appuie)
                  Positioned(
                    top: -34,
                    child: _Onde(battement: _battement.value),
                  ),
                Transform.rotate(
                  angle: inclinaison,
                  child: Transform.scale(
                    scale: 1 + hauteur * 0.18,
                    child: const Text(
                      '👆',
                      style: TextStyle(
                        fontSize: 46,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Le bandeau de texte, posé en bas — toujours au même endroit.
  ///
  /// Une bulle qui saute d'un bord à l'autre selon la cible oblige l'œil à la
  /// chercher à chaque étape, et c'est précisément ce qui rendait la première
  /// version désagréable. Ici le texte ne bouge pas : seule la main voyage.
  /// En bas plutôt qu'en haut, parce que c'est là que les pouces reposent et
  /// que le haut porte souvent le titre de l'écran visité.
  Widget _ruban(
      BuildContext context, EtapeGuide etape, Size taille, bool dernier) {
    // Si la zone éclairée est elle-même tout en bas (la barre d'onglets), le
    // ruban remonte : sinon il la recouvrirait, et on masquerait ce qu'on
    // désigne.
    final zoneEnBas = _zone != null && _zone!.bottom > taille.height - 180;
    return Positioned(
      left: 14,
      right: 14,
      bottom: zoneEnBas ? taille.height - _zone!.top + 16 : 28,
      child: Material(
        color: Colors.transparent,
        child: Builder(
          builder: (context) {
            // ── LE FONDU PORTE SUR LE TEXTE, PAS SUR LE RUBAN (2026-09-13) ─
            //
            // Première version : un `AnimatedSwitcher` enveloppait le
            // conteneur ENTIER. Défaut vu à l'écran, capture à l'appui, et
            // qui touchait deux choses à la fois pendant les 260 ms de
            // transition :
            //   1. le fond devenait semi-transparent (deux conteneurs à
            //      opacité partielle, jamais 1 à eux deux), et la liste des
            //      sourates se lisait AU TRAVERS du ruban ;
            //   2. l'ancien titre et le nouveau se superposaient —
            //      « Coran » par-dessus « Invocations », illisible.
            //
            // Le conteneur reste donc opaque en permanence, et seul son
            // contenu change. Voir `_TexteEnchaine` juste en dessous pour le
            // point important : un fondu CROISÉ ne suffisait pas.
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
            decoration: BoxDecoration(
              color: AppColors.green900,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.brass, width: 1.4),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 2),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Le fil doré : autant de traits que d'étapes. Dit où on en
                    // est sans une ligne de texte à traduire.
                    for (var i = 0; i < widget.etapes.length; i++) ...[
                      Container(
                        width: i == _index ? 18 : 7,
                        height: 3,
                        decoration: BoxDecoration(
                          color: i <= _index
                              ? AppColors.brass
                              : AppColors.cream.withAlpha(60),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // ── FONDU ENCHAINE, ET NON CROISE ────────────────────
                //
                // `AnimatedSwitcher` superpose par defaut l'ancien et le
                // nouvel enfant pendant toute la transition : deux titres se
                // lisaient l'un par-dessus l'autre (« Coran » sur
                // « Invocations »), vu a l'ecran. Les deux `Interval` ci-
                // dessous decoupent la duree en deux moities : l'ancien texte
                // a DISPARU avant que le nouveau commence a apparaitre.
                //
                // `layoutBuilder` qui empile sans centrer : le defaut centre
                // les enfants, ce qui ferait glisser le texte horizontalement
                // pendant la transition dans un ruban aligne a gauche.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchOutCurve: const Interval(0.0, 0.5),
                  switchInCurve: const Interval(0.5, 1.0),
                  layoutBuilder: (courant, precedents) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...precedents, ?courant],
                  ),
                  child: Column(
                    key: ValueKey(_index),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        etape.titre,
                        style: const TextStyle(
                          color: AppColors.brassLight,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        etape.texte,
                        style: TextStyle(
                          color: AppColors.cream.withAlpha(225),
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: _terminer,
                      child: Text(
                        widget.libellePasser,
                        style: TextStyle(
                            color: AppColors.cream.withAlpha(150),
                            fontSize: 12.5),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      // « Suivant » n'attend pas la fin de la pause : on peut
                      // presser le pas sans casser la visite.
                      onPressed: dernier ? _terminer : _suivant,
                      child: Text(
                        dernier ? widget.libelleFin : widget.libelleSuivant,
                        style: const TextStyle(
                          color: AppColors.brass,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            );
          },
        ),
      ),
    );
  }
}

/// Voile sombre percé sur la zone désignée, avec un liseré doré qui respire.
///
/// `PathFillType.evenOdd` plutôt qu'un `saveLayer` + `BlendMode.clear` : le
/// second compose une couche hors écran de la taille de l'écran à chaque
/// frame. La rastérisation de cette application est déjà juste sur un
/// téléphone milieu de gamme — 17 à 27 ms par frame pour un budget de 16,7 ms,
/// mesuré (cf. `PERFORMANCE.md` §8). Un chemin à deux sous-contours ne coûte
/// rien.
class _Voile extends CustomPainter {
  final Rect? zone;
  final double rayon;
  final double battement;
  final bool actif;

  const _Voile({
    required this.zone,
    required this.rayon,
    required this.battement,
    required this.actif,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chemin = Path()..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (zone != null) {
      chemin.addRRect(RRect.fromRectAndRadius(zone!, Radius.circular(rayon)));
    }
    canvas.drawPath(chemin, Paint()..color = Colors.black.withAlpha(175));
    if (zone == null || !actif) return;
    for (final decalage in [0.0, 0.5]) {
      final t = (battement + decalage) % 1.0;
      final r = zone!.inflate(t * 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(rayon + t * 12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = AppColors.brass.withAlpha(((1 - t) * 200).round()),
      );
    }
  }

  @override
  bool shouldRepaint(_Voile o) =>
      o.zone != zone || o.battement != battement || o.actif != actif;
}

/// L'onde de l'appui, sous le bout du doigt.
class _Onde extends StatelessWidget {
  final double battement;
  const _Onde({required this.battement});

  @override
  Widget build(BuildContext context) {
    final t = battement * 2 % 1;
    return IgnorePointer(
      child: Container(
        width: 34 + t * 30,
        height: 34 + t * 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.brassLight.withAlpha(((1 - t) * 210).round()),
            width: 2.4,
          ),
        ),
      ),
    );
  }
}

// ── HÉBERGEMENT : LA VISITE DOIT SURVIVRE À LA NAVIGATION (2026-09-13) ───────
//
// Demande utilisateur : « je veux un globale et de taillé même sous détaillé ».
// Une visite qui ne couvre que les onglets ne peut pas tenir cette promesse :
// dès qu'un chapitre ouvre un vrai écran (Mushaf papier, Qibla, réglages des
// prières…), la page poussée se dessine AU-DESSUS de tout ce qui vit dans le
// `Stack` de l'accueil — donc au-dessus du guide, qui disparaît.
//
// L'`Overlay` racine est la seule couche qui reste au-dessus des routes
// poussées. C'est pour ça qu'on l'utilise ICI, alors que l'en-tête de ce
// fichier déconseillait un `OverlayEntry` : ce conseil visait une visite liée à
// UN écran, où l'entrée oubliée survit à la navigation et laisse un calque
// figé. Le danger est réel et n'a pas disparu ; on le neutralise autrement.
//
// ⚠️ LES TROIS GARDE-FOUS, à ne pas retirer :
//   1. UNE SEULE entrée à la fois (`_entree` statique) : `lancer` ferme
//      toujours la précédente. Deux visites superposées seraient
//      indébouclables pour l'utilisateur.
//   2. `fermer()` est IDEMPOTENT et remet `_entree` à null : appelé deux fois
//      (bouton « Passer » puis fin de la dernière étape), il ne lève pas.
//   3. La visite se ferme elle-même via `onTermine`. Aucun chemin ne laisse
//      l'entrée en place.
class GuideHote {
  GuideHote._();

  static OverlayEntry? _entree;

  /// Vrai si une visite est en cours. Permet à un écran de ne pas en lancer
  /// une seconde par-dessus (bouton pressé deux fois).
  static bool get enCours => _entree != null;

  /// Affiche [etapes] au-dessus de TOUTE l'application, routes comprises.
  static void lancer(
    BuildContext context, {
    required List<EtapeGuide> etapes,
    required String libellePasser,
    required String libelleSuivant,
    required String libelleFin,
    VoidCallback? auRetour,
  }) {
    if (etapes.isEmpty) return;
    fermer();
    final calque = Overlay.of(context, rootOverlay: true);
    final entree = OverlayEntry(
      builder: (_) => VisiteGuidee(
        etapes: etapes,
        libellePasser: libellePasser,
        libelleSuivant: libelleSuivant,
        libelleFin: libelleFin,
        onTermine: () {
          fermer();
          auRetour?.call();
        },
      ),
    );
    _entree = entree;
    calque.insert(entree);
  }

  /// Retire la visite. Sans effet si aucune n'est affichée.
  static void fermer() {
    _entree?.remove();
    _entree = null;
  }
}
