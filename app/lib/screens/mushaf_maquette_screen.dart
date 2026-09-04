import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/riwaya.dart';
import '../models/verse.dart';
import '../providers/app_settings_provider.dart';
import '../services/quran_api.dart';
import '../services/recitation_verifier.dart' show ArabicNormalizer;
import '../theme/app_theme.dart';
import '../widgets/mushaf_page_chrome.dart';
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

  const MushafMaquetteScreen({super.key, this.pageInitiale = 1});

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

  /// Une police vient d'arriver : la page doit se remesurer.
  ///
  /// Sans cela, la taille reste celle calculee sur la police de SECOURS --
  /// defaut constate le 2026-09-03 (« la taille ne s'ajuste pas au changement
  /// d'ecriture ; apres balayage, elle s'ajuste »), et confirme par six
  /// ecritures differentes qui rendaient la meme occupation au dixieme.
  void _policeChargee() {
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
    // Plein écran : ni barre d'état ni boutons système. `immersiveSticky` les
    // ramène brièvement sur un balayage depuis le bord puis les re-masque --
    // le geste de feuilletage n'est donc jamais confisqué par le système.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    final sombre = ref.watch(modeSombreProvider);
    final warsh = ref.watch(riwayaProvider) == Riwaya.warsh;
    // ECRITURE DU TEXTE CORANIQUE (2026-09-03) : reglage local a cette vue,
    // defaut `Amiri` -- le rendu d'origine, inchange tant qu'aucun autre choix
    // n'est fait.
    final ecriture = ref.watch(policeMushafPageProvider);
    final tajwid = ref.watch(tajwidMushafPageProvider);
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
      child: Scaffold(
      backgroundColor: sombre ? AppColors.sombreBg : const Color(0xFFF3EAD6),
      // CHGPT : la page reste toujours en plein ecran. Un toucher avance
      // directement, sans faire apparaitre de barre qui decale le Mushaf.
      body: PageView.builder(
        controller: _ctrl,
        reverse: true,
        itemCount: _kPages,
        onPageChanged: (i) => _pageLue = i + 1,
        itemBuilder: (context, i) => _PageMushaf(
          page: i + 1,
          sombre: sombre,
          warsh: warsh,
          ecriture: ecriture,
          tajwid: tajwid,
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
    );
  }
}

/// Une page, chargée à la demande (le cache de `QuranApi` rend les retours
/// en arrière gratuits).
class _PageMushaf extends StatelessWidget {
  final int page;
  final bool sombre;
  final bool warsh;

  /// Colorer le texte selon les regles de tajwid (cf.
  /// `tajwidMushafPageProvider`). Eteint, la page se peint en une seule encre.
  final bool tajwid;

  /// Nom Google Fonts de l'ecriture du TEXTE CORANIQUE (cf.
  /// `policeMushafPageProvider`). L'en-tete et le pied gardent Amiri : ce sont
  /// des reperes de navigation, les faire varier brouillerait la comparaison
  /// entre deux ecritures.
  final String ecriture;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _PageMushaf({
    required this.page,
    required this.sombre,
    required this.warsh,
    required this.ecriture,
    required this.tajwid,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: FutureBuilder<List<Verse>>(
        future: warsh
            ? QuranApi.fetchWarshMushafVersesByPage(page)
            : QuranApi.fetchVersesByPage(page),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Erreur : ${snap.error}',
                style: GoogleFonts.manrope(color: Colors.redAccent),
              ),
            );
          }
          final versets = snap.data;
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
    final segments = <({int sourate, String texte, List<Verse> versets})>[];
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
        ));
      } else {
        segments.add((sourate: v.surahNumber, texte: mot, versets: [v]));
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
      minimum: const EdgeInsets.symmetric(vertical: 6),
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
          style: pageOuverture
              ? MushafFrameStyle.opening
              : MushafFrameStyle.regular,
          dark: sombre,
          child: Column(
            children: [
              if (pageOuverture)
                _bandeauSourate(
                  segments.first.sourate,
                  MushafSurahBanner.openingHeight,
                  compact: false,
                )
              else
                _enTete(sourates, juz, hizb),
              const SizedBox(height: 3),
              Expanded(
                child: ClipRect(child: _blocAjuste(segments, spansParSegment)),
              ),
              _pied(sourates, juz),
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
  Widget _enTete(List<int> sourates, Set<int> juz, Set<int> hizb) {
    final style = GoogleFonts.amiri(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: sombre ? AppColors.brass : _Charte.filet,
    );
    final gauche = [
      if (hizb.isNotEmpty) 'حزب ${_chiffresArabes(hizb.first)}',
      if (juz.isNotEmpty) 'جزء ${_chiffresArabes(juz.first)}',
    ].join(' · ');
    Widget onglet(String texte) => Expanded(
      child: Container(
        height: 30,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: sombre ? const Color(0xFF172421) : const Color(0xFFFFFEF6),
          border: Border.all(
            color: sombre
                ? AppColors.brass.withValues(alpha: 0.75)
                : _Charte.legende,
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

    return Transform.translate(
      offset: const Offset(0, -7),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            onglet(gauche),
            const SizedBox(width: 8),
            onglet(
              sourates
                  .map((s) => 'سورة ${_nomSourate(s)} ${_chiffresArabes(s)}')
                  .join(' · '),
            ),
          ],
        ),
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
  List<TextSpan> _spansCanoniques(List<Verse> versets, {bool couleur = true}) {
    final base = _policePage(famille: ecriture);
    final out = <TextSpan>[];
    for (final v in versets) {
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
    }
    return out;
  }

  Widget _bloc(
    String texte,
    double taille,
    List<TextSpan>? spans, {
    double interligne = _kInterligne,
  }) {
    final style = styleEcriture(
      ecriturePour(ecriture),
      taille: taille,
      interligne: interligne,
      graisse: FontWeight.w600,
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
      child: Text.rich(
        TextSpan(
          style: style,
          children: _waqfSurLaLigne(
            spans ?? [TextSpan(text: texte, style: style)],
            style,
            taille,
          ),
        ),
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
  /// Hauteur reelle de chaque segment, pour une taille et un interligne donnes.
  ///
  /// Extraite pour pouvoir etre RAPPELEE : la garde de debordement doit
  /// remesurer apres chaque recul, sinon elle valide une hauteur qui n'est
  /// plus celle qui sera peinte.
  List<double> _hauteursSegments(
    List<({int sourate, String texte, List<Verse> versets})> segments,
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
      out.add(peintre.height);
    }
    return out;
  }

  Widget _blocAjuste(
    List<({int sourate, String texte, List<Verse> versets})> segments,
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
        final dispo = contraintes.maxHeight - nBandeaux * hauteurBandeau;
        double basse = 12, haute = 52;
        for (var i = 0; i < 9; i++) {
          final milieu = (basse + haute) / 2;
          var total = 0.0;
          for (var s = 0; s < segments.length; s++) {
            final sp = spansParSegment?[s];
            final st = style.copyWith(fontSize: milieu);
            final peintre = TextPainter(
              text: _spanMesure(segments[s].texte, sp, st, milieu),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.justify,
            )..layout(maxWidth: contraintes.maxWidth);
            total += peintre.height;
          }
          // Reserve de securite ABSOLUE et non proportionnelle : ce qu'elle
          // protege, c'est une diacritique haute de la DERNIERE ligne qui
          // depasse la hauteur annoncee par TextPainter. Ce depassement vaut
          // une fraction du corps -- il ne grandit pas avec la page. En
          // pourcentage (0,93 avant le 2026-09-03) il reservait ~125 px sur
          // une page de 1800 pour un besoin d'une quinzaine, et c'est ce vide
          // que l'utilisateur voyait en haut et en bas.
          if (total <= dispo - milieu * 0.5) {
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
        var hauteurTexte = 0.0;
        var lignes = 0;
        for (var s = 0; s < segments.length; s++) {
          final sp = spansParSegment?[s];
          final st = style.copyWith(fontSize: basse);
          final peintre = TextPainter(
            text: _spanMesure(segments[s].texte, sp, st, basse),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.justify,
          )..layout(maxWidth: contraintes.maxWidth);
          hauteurTexte += peintre.height;
          lignes += peintre.computeLineMetrics().length;
        }
        final residu = dispo - basse * 0.5 - hauteurTexte;
        // Plafond : sur une page peu remplie la police bute deja sur son
        // maximum et sans borne les quelques lignes s'etaleraient comme un
        // poeme. Au-dela, le reste redevient du vide centre -- le bon rendu
        // dans ce cas precis.
        final interligne = lignes == 0 || residu <= 0
            ? _kInterligne
            : (_kInterligne + residu / lignes / basse).clamp(
                _kInterligne,
                2.45,
              );

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
        var interligneRetenu = interligne;
        var tailleRetenue = basse;
        var hauteurs = _hauteursSegments(segments, spansParSegment, style,
            tailleRetenue, interligneRetenu, contraintes.maxWidth);
        for (var essai = 0; essai < 24; essai++) {
          if (hauteurs.fold<double>(0, (a, b) => a + b) <= dispo) break;
          if (interligneRetenu > _kInterligne) {
            interligneRetenu = _kInterligne;
          } else {
            if (tailleRetenue <= 12) break;
            tailleRetenue -= 1;
          }
          hauteurs = _hauteursSegments(segments, spansParSegment, style,
              tailleRetenue, interligneRetenu, contraintes.maxWidth);
        }
        basse = tailleRetenue;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var s = 0; s < segments.length; s++) ...[
              if (s > 0) _bandeauSourate(segments[s].sourate, hauteurBandeau),
              ClipRect(
                child: SizedBox(
                  height: hauteurs[s],
                  child: _bloc(
                    segments[s].texte,
                    basse,
                    spansParSegment?[s],
                    interligne: interligneRetenu,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  TextSpan _spanMesure(
    String texte,
    List<TextSpan>? spans,
    TextStyle style,
    double taille,
  ) => TextSpan(
    style: style,
    children: _waqfSurLaLigne(
      spans ?? [TextSpan(text: texte, style: style)],
      style,
      taille,
    ),
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
