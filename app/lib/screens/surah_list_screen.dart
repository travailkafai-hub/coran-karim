import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/home_prayer_panel.dart';
import '../widgets/quran_shazam_sheet.dart';
import '../widgets/quran_pattern_background.dart';
import 'mushaf_screen.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import 'prayer_follow_screen.dart';
import '../data/guides_catalogue.dart';

class SurahListScreen extends ConsumerStatefulWidget {
  const SurahListScreen({super.key});

  @override
  ConsumerState<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends ConsumerState<SurahListScreen> {
  List<Surah> _surahs = [];
  bool _loading = true;
  String? _error;

  // ── CIBLES DE LA VISITE GUIDÉE (2026-09-13) ──────────────────────────────
  //
  // Posées sur de VRAIS éléments de cet écran, et publiées dans
  // `data/guides_catalogue.dart` pour que la main puisse les mettre en
  // lumière. Sans elles, les étapes qui parlent de la carte de prière ou du
  // bouton d'écoute ne faisaient que les décrire.
  final GlobalKey _cleCartePriere = GlobalKey();
  final GlobalKey _cleBoutonEcoute = GlobalKey();
  final GlobalKey _cleSignet = GlobalKey();

  @override
  void initState() {
    super.initState();
    cleCartePriere = _cleCartePriere;
    cleBoutonEcoute = _cleBoutonEcoute;
    cleSignet = _cleSignet;
    _load();
  }

  @override
  void dispose() {
    // Une clé publiée qui survit à son widget ferait pointer la main sur une
    // position périmée -- pire qu'aucune cible, parce que ça DÉSIGNE quelque
    // chose et enseigne donc un mensonge.
    if (cleCartePriere == _cleCartePriere) cleCartePriere = null;
    if (cleBoutonEcoute == _cleBoutonEcoute) cleBoutonEcoute = null;
    if (cleSignet == _cleSignet) cleSignet = null;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final surahs = await QuranApi.fetchSurahs();
      setState(() { _surahs = surahs; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // Identification (Shazam coranique) déclenchée depuis la page principale --
  // REFONTE_IHM.md §5. Ouvre directement le Mushaf au passage identifié (même
  // logique que mushaf_screen.dart::_openShazam, mais on part toujours d'un
  // écran neuf ici puisqu'aucune sourate n'est encore chargée en scroll continu).
  Future<void> _openShazamFromHome() async {
    final match = await showQuranShazamSheet(context, ref);
    if (match == null || !mounted) return;
    _openMushafAt(match.surahNumber, match.ayahNumber);
  }

  Future<void> _openMushafAt(int surahNumber, int ayahNumber) async {
    final surahs = _surahs.isNotEmpty ? _surahs : await QuranApi.fetchSurahs();
    final target = surahs.firstWhere((s) => s.number == surahNumber,
        orElse: () => surahs.first);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MushafScreen(surah: target, initialAyahNumber: ayahNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: AppColors.green900,
            // "Suivre une prière" + "Identifier" (Shazam coranique) cote a
            // cote -- retour utilisateur 2026-07-19 : la version en grandes
            // cartes (§5 du plan) etait moins bien que les simples icones
            // d'origine, garder ce style, juste ajouter Identifier a cote de
            // Suivre une priere plutot que de le laisser seul dans la barre
            // du bas de l'ecran de lecture.
            actions: [
              // ── SIGNET : REPRENDRE OU ON EN ETAIT ────────────────────────
              //
              // Demande utilisateur (2026-08-06) : « place-le dans le coin en
              // haut, a cote de l'oeil et suivre priere ». Un signet qu'on ne
              // peut rouvrir que depuis l'ecran ou on l'a pose ne sert a rien.
              //
              // ⚠️ LE DERNIER POSE, PAS LE PLUS AVANCE. Premiere version : on
              // triait par position dans le Mushaf et on prenait la derniere.
              // Defaut signale aussitot -- « je constate que je marque une
              // autre page, elle ne se modifie pas » : marquer un verset
              // ANTERIEUR ne changeait rien. `MarquePagesNotifier.basculer`
              // construit un `Set<String>.from(state)` -- donc un
              // LinkedHashSet, qui conserve l'ordre d'INSERTION. Le dernier
              // pose est simplement `state.last`, et c'est lui qu'on veut :
              // « reprendre » veut dire la ou on s'est arrete en dernier.
              KeyedSubtree(key: _cleSignet, child: const _BoutonSignet()),
              IconButton(
                icon: const Icon(Icons.hearing_rounded, color: AppColors.cream),
                tooltip: t.homeIdentifyTooltip,
                onPressed: _openShazamFromHome,
              ),
              // ── « SUIVRE UNE PRIÈRE » RETIRÉ DE LA v1 (2026-08-09) ────────
              //
              // Décision utilisateur : « désactive le mode prière, je ne vais
              // pas l'inclure dans la première version [...] reste dans l'app
              // mais pas utilisé ».
              //
              // RIEN N'EST SUPPRIMÉ : `PrayerFollowScreen`, le mode `PRIERE`
              // de la chaîne v2 (`sautLibre`), l'identification de sourate et
              // tout le cycle takbir/Fatiha/cible restent en place et
              // fonctionnels -- c'est un gros chantier mesuré, pas un
              // brouillon. Seul CE bouton disparaissait de la barre par
              // défaut.
              //
              // ── ACCÈS CACHÉ RÉTABLI (2026-08-26, demande utilisateur) ─────
              // « je veux un accès caché de suivre la prière si on tape 5
              // fois coach dans la page accueil ». Le bouton ne réapparaît
              // que si `suivrePriereAccesCacheProvider` est vrai (cf. sa doc,
              // `app_settings_provider.dart`, et le compteur de taps dans
              // `main.dart::_HomeScreenState._openCoachTab`) -- la décision du
              // 2026-08-09 tient toujours pour tout le monde, ceci n'est
              // qu'une porte de secours qu'il faut connaître pour trouver.
              if (ref.watch(suivrePriereAccesCacheProvider))
                IconButton(
                  icon: const Icon(Icons.mosque_rounded, color: AppColors.cream),
                  tooltip: t.homeFollowPrayerTooltip,
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PrayerFollowScreen())),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.green900, AppColors.green800],
                  ),
                ),
                // Couverture : même filigrane que le défilement (cohérence
                // visuelle), un peu plus visible ici car sur fond vert foncé
                // uni (pas de texte à concurrencer) -- cf.
                // widgets/quran_pattern_background.dart.
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: QuranPatternBackground(opacity: 0.10),
                    ),
                    SafeArea(
                      // ── LE BLOC-TITRE ETAIT COLLE AU BORD DE DEPART, PAS
                      // CENTRE (2026-09-13) ──────────────────────────────
                      //
                      // Constat utilisateur, capture a l'appui, sur la page
                      // d'accueil : « en arabe c'est mal agence ». Cause :
                      // `Column` etait un enfant NON positionne d'un `Stack` ;
                      // sans largeur imposee, il se contracte a la largeur de
                      // son texte le plus large puis se colle a l'alignement
                      // par defaut du Stack (`AlignmentDirectional.topStart`)
                      // -- le bord de DEPART, qui est la DROITE en arabe (la
                      // locale bascule la Directionality de toute l'app).
                      // Le titre semblait donc plaque contre le bord droit au
                      // lieu d'etre centre, et le filet en dessous (`_TitleRule`)
                      // avec lui. `crossAxisAlignment.center` du Column ne
                      // pouvait rien y faire : il centre les ENFANTS du
                      // Column DANS SA PROPRE largeur, pas le Column dans
                      // celle de l'ecran.
                      //
                      // `Align` resout les deux a la fois : il s'etend a
                      // TOUTE la zone du Stack (bornes lâches, donc pas de
                      // contrainte de taille), puis positionne son enfant
                      // (le Column, reduit a sa taille naturelle via
                      // `mainAxisSize.min`) en bas-CENTRE de cette zone --
                      // replique exactement le `mainAxisAlignment.end`
                      // d'origine (colle en bas), en ajoutant le centrage
                      // horizontal qui manquait.
                      //
                      // ⚠️ LE CENTRAGE A ETE REFUSE (2026-09-13, meme jour) :
                      // « remet Coran Karim dans le côté, c'est mieux que le
                      // milieu ». Le titre retourne donc au bord de DEPART --
                      // ce qu'il faisait avant, mais par ACCIDENT (l'alignement
                      // par defaut d'un enfant non positionne d'un `Stack`) et
                      // non par choix. La difference compte : le bloc etait
                      // aussi contraint a la largeur de son texte le plus
                      // large, ce qui entrainait le filet `_TitleRule` avec lui
                      // et produisait le « mal agence » d'origine.
                      //
                      // `AlignmentDirectional.bottomStart` et non
                      // `Alignment.bottomLeft` : le bord de depart suit la
                      // langue -- a GAUCHE en francais et en anglais, a DROITE
                      // en arabe, ou la locale bascule la Directionality de
                      // toute l'app. Un `bottomLeft` en dur collerait le titre
                      // arabe du mauvais cote, contre le sens de lecture.
                      // Le padding de depart evite qu'il touche le bord.
                      child: Align(
                        alignment: AlignmentDirectional.bottomStart,
                        child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'القرآن الكريم',
                              textAlign: TextAlign.start,
                              style: GoogleFonts.scheherazadeNew(
                                fontSize: 32, color: AppColors.cream,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const _TitleRule(),
                            // "CORAN KARIM" est une graphie latine du titre --
                            // masquée en mode arabe (règle verrouillée
                            // REFONTE_IHM.md §7bis, bug corrigé 2026-07-22 :
                            // seul texte latin restant sur la page de couverture).
                            if (!isArabic) ...[
                              const SizedBox(height: 6),
                              Text(
                                'CORAN KARIM',
                                style: GoogleFonts.fraunces(
                                  fontSize: 13, color: AppColors.brassLight,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppColors.green800)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48, color: AppColors.green700),
                    const SizedBox(height: 12),
                    Text(t.commonConnectionRequired, style: GoogleFonts.manrope(
                      color: AppColors.inkLight, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _load, child: Text(t.commonRetry)),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              // Clé lue par la visite guidée pour mettre cette carte en
              // lumière (cf. `data/guides_catalogue.dart`). `KeyedSubtree` et
              // non une clé posée sur `CompactPrayerQiblaCard` : ce widget est
              // `const`, et lui donner une clé lui ferait perdre sa
              // canonicalisation -- il serait reconstruit à chaque frame.
              child: KeyedSubtree(
                key: _cleCartePriere,
                child: const CompactPrayerQiblaCard(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _SurahTile(
                    surah: _surahs[i],
                    // Seule la PREMIÈRE ligne porte la clé : la visite montre
                    // « le bouton d'écoute », pas les 114. Une clé par ligne
                    // serait de toute façon invalide -- un `GlobalKey` doit
                    // être unique dans l'arbre.
                    cleEcoute: i == 0 ? _cleBoutonEcoute : null,
                  ),
                  childCount: _surahs.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


// Filet titre : simple règle horizontale + petit losange central --
// séparateur entre le titre arabe et le sous-titre latin sur la couverture.
// Volontairement minimal (un trait, un losange) après le retour utilisateur
// sur la V1 du bandeau de sourate ("catastrophique... trop chargée") :
// pas de cadre, pas de motif répété, juste de quoi marquer la coupure.
class _TitleRule extends StatelessWidget {
  const _TitleRule();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _line(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Transform.rotate(
              angle: 0.785398, // 45°
              child: Container(width: 6, height: 6, color: AppColors.brass),
            ),
          ),
          _line(),
        ],
      );

  Widget _line() => Container(
        width: 36,
        height: 1,
        color: AppColors.brassLight.withValues(alpha: 0.6),
      );
}

// "Suivre une prière" / "Identifier" en grandes cartes (§5 du plan) --
// ESSAYE puis RETIRE (2026-07-19, retour utilisateur : "avant c'était
// mieux") : revenu aux simples icônes d'app bar (voir SliverAppBar.actions
// plus haut), Identifier ajoutée à côté de Suivre une prière plutôt que
// laissée seule dans la barre du bas de l'écran de lecture. Implémentation
// des cartes conservée dans l'historique git si on veut la reprendre un jour
// avec un design différent.

class _SurahTile extends ConsumerWidget {
  /// Posée sur le bouton d'écoute de la PREMIÈRE ligne seulement, pour la
  /// visite guidée. `null` partout ailleurs : un `GlobalKey` doit être unique
  /// dans l'arbre, une clé par ligne serait invalide.
  final GlobalKey? cleEcoute;
  final Surah surah;
  const _SurahTile({required this.surah, this.cleEcoute});

  // ── LANCER LA LECTURE DEPUIS LA LISTE (2026-09-13) ───────────────────────
  //
  // Demande utilisateur : « rajoute aussi la possibilite de lancer le play
  // de la sourate » -- sans passer par l'ecran de lecture. Meme lecteur
  // GLOBAL que `mushaf_screen.dart::_onPlayTap` (`playerProvider`, un seul
  // par app) : le meme discriminant s'applique -- si CETTE sourate est deja
  // celle chargee, le bouton devient transport (pause/reprise) ; sinon un
  // tap (re)lance depuis le premier verset, playlist = la sourate entiere
  // (le lecteur enchaine tout seul, cf. `PlayerNotifier.play`).
  //
  // `QuranApi.fetchVerses` est deja mis en cache par sourate (cf. sa doc) :
  // un tap suivant sur la meme sourate ne refait pas la requete reseau.
  Future<void> _togglePlay(WidgetRef ref) async {
    final player = ref.read(playerProvider);
    final dejaChargee = player.currentVerse?.surahNumber == surah.number;
    if (dejaChargee && player.isPlaying) {
      ref.read(playerProvider.notifier).pause();
      return;
    }
    if (dejaChargee && player.isPaused) {
      ref.read(playerProvider.notifier).resume();
      return;
    }
    final versets = await QuranApi.fetchVerses(surah.number);
    if (versets.isEmpty) return;
    await ref.read(playerProvider.notifier).play(versets.first, versets);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final place = surah.revelationPlace == 'makkah' ? t.surahMeccan : t.surahMedinan;
    final metaLine = t.surahMetaLine(surah.versesCount, place);
    final player = ref.watch(playerProvider);
    final enCours =
        player.currentVerse?.surahNumber == surah.number && player.isPlaying;
    return InkWell(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => MushafScreen(surah: surah))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.cream300, width: 0.8),
          ),
        ),
        child: Row(
          children: [
            // Number badge
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brass, width: 1.5),
                color: AppColors.cream200,
              ),
              child: Center(
                child: Text(
                  '${surah.number}',
                  style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.brass,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Nom + métadonnées -- en arabe, le nom arabe DEVIENT le titre
            // principal (pas de romanisation à côté, règle verrouillée
            // REFONTE_IHM.md §7bis) ; en fr/en, le nom romanisé reste le
            // titre et le nom arabe garde son flourish à droite (ci-dessous).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isArabic ? surah.nameArabic : surah.nameSimple,
                    textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                    style: isArabic
                        ? GoogleFonts.scheherazadeNew(
                            fontSize: 19, fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          )
                        : GoogleFonts.manrope(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          )),
                  const SizedBox(height: 2),
                  Text(
                    metaLine,
                    style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight),
                  ),
                ],
              ),
            ),
            // Nom arabe en flourish -- seulement en fr/en (en arabe, c'est
            // déjà le titre principal ci-dessus, pas de doublon).
            if (!isArabic) ...[
              Text(
                surah.nameArabic,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                  fontSize: 20, color: AppColors.green800,
                ),
              ),
              const SizedBox(width: 4),
            ],
            // ── BOUTON LECTURE, TOUJOURS PRESENT (2026-09-13) ────────────
            //
            // Deuxieme effet du meme ajout, constate par l'utilisateur :
            // « quand c'est la langue arabe le nom de la sourate est trop
            // colle et on a de l'espace ». En arabe, ce Row est en RTL (la
            // locale arabe bascule la Directionality de toute l'app, cf.
            // `main.dart`) -- l'element `if (!isArabic)` ci-dessus disparait
            // alors completement, et rien ne restait pour occuper le bord
            // qui devient visuellement le bord GAUCHE. Ce bouton est
            // desormais toujours present (arabe compris) : il comble cet
            // espace au lieu de le laisser vide, et donne en plus l'acces
            // lecture demande.
            // ── COULEUR ADOUCIE (2026-09-13, meme session) ────────────────
            //
            // Retour utilisateur immediat : « c'est tres fonce, je veux une
            // couleur pas trop imposante, surtout que de l'autre cote c'est
            // couleur doree ». Le rond plein vert fonce (`green800`)
            // tranchait avec le badge numerote (bordure `brass`, fond clair)
            // de l'autre bout de la meme ligne. Meme traitement que le
            // badge : contour dore fin sur fond clair, plus d'aplat sombre.
            IconButton(
              key: cleEcoute,
              onPressed: () => _togglePlay(ref),
              tooltip: enCours ? t.mushafPause : t.mushafPlay,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cream200,
                  border: Border.all(color: AppColors.brass, width: 1.3),
                ),
                child: Icon(
                  enCours
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 18,
                  color: AppColors.brass,
                ),
              ),
            ),
            // Icône « carte mentale » par sourate RETIRÉE le 2026-07-20
            // (demande utilisateur : « la carte mentale, je veux que tu
            // l'enlèves de la première page »). La page principale redevient
            // une simple liste de sourates. La carte mentale reste accessible
            // depuis l'en-tête de lecture et depuis le volet erreurs du hub
            // Coach (REFONTE_IHM.md §11.3/§11.5).
          ],
        ),
      ),
    );
  }
}

/// Accès direct au dernier signet posé (barre du haut de l'accueil).
///
/// Invisible tant qu'aucun signet n'existe : un bouton qui ne fait rien
/// apprend à l'ignorer. Le saut passe par `MushafScreen(initialAyahNumber:)`,
/// le même chemin que la liste des signets et que le « Shazam coranique » --
/// pas un troisième mécanisme de navigation.
class _BoutonSignet extends ConsumerWidget {
  const _BoutonSignet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cle = ref.watch(marquePagesProvider);
    if (cle == null) return const SizedBox.shrink();
    // Un seul signet depuis le 2026-09-09 (cf. `marquePagesProvider`) : plus
    // besoin de choisir « le dernier pose », c'est le seul.
    final p = cle.split(':').map(int.parse).toList();
    return IconButton(
      icon: const Icon(Icons.bookmark_rounded, color: AppColors.brassLight),
      tooltip: '${p[0]}:${p[1]}',
      onPressed: () async {
        try {
          final sourates = await QuranApi.fetchSurahs();
          final s = sourates.where((x) => x.number == p[0]);
          if (s.isEmpty || !context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MushafScreen(surah: s.first, initialAyahNumber: p[1]),
          ));
        } catch (_) {
          // Best-effort : sans les metadonnees on n'ouvre pas un ecran vide.
        }
      },
    );
  }
}


