import 'package:flutter/material.dart';
import 'dart:async';
import '../models/prayer_settings.dart';
import 'prayer_times_settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/verse.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/quran_shazam_sheet.dart';
import '../widgets/quran_pattern_background.dart';
import 'mushaf_screen.dart';
import '../providers/app_settings_provider.dart';
import '../providers/prayer_settings_provider.dart';
// Import conservé volontairement, en commentaire : le bouton « Suivre une
// prière » est retiré de la v1 (cf. plus bas), l'écran lui existe toujours.
// import 'prayer_follow_screen.dart';

class SurahListScreen extends ConsumerStatefulWidget {
  const SurahListScreen({super.key});

  @override
  ConsumerState<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends ConsumerState<SurahListScreen> {
  List<Surah> _surahs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
              const _BoutonSignet(),
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
              // brouillon. Seul CE bouton disparaît, donc le seul chemin qui
              // y menait depuis l'IHM. Le rebrancher = rétablir ces six
              // lignes, rien d'autre.
              //
              // Ancien code, gardé en trace (convention projet) :
              //   IconButton(
              //     icon: const Icon(Icons.mosque_rounded, color: AppColors.cream),
              //     tooltip: t.homeFollowPrayerTooltip,
              //     onPressed: () => Navigator.push(context,
              //         MaterialPageRoute(builder: (_) => const PrayerFollowScreen())),
              //   ),
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'القرآن الكريم',
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
            const SliverToBoxAdapter(child: _RappelPriere()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _SurahTile(surah: _surahs[i]),
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


/// Rappel de la prochaine priere, pose en tete de la liste des sourates.
///
/// ── POURQUOI ICI (2026-08-19) ───────────────────────────────────────────────
/// Constat utilisateur : « ce qui manque dans cette page du debut, c'est un
/// endroit pour mettre la prochaine heure de priere, avec combien il reste de
/// temps -- parce que pour l'information il faut aller dans le parametrage ».
/// C'est juste : l'horaire etait calcule et deja affiche, mais seulement sur
/// l'ecran qui sert a le REGLER. Une information qu'on consulte plusieurs fois
/// par jour n'a rien a faire derriere un ecran de reglages.
///
/// Le bandeau ne calcule rien lui-meme : il lit `prochainePriere`, la meme
/// regle que l'ecran des reglages (cf. son extraction dans
/// prayer_settings_provider.dart). Deux endroits qui annonceraient une
/// prochaine priere differente seraient pires que pas de rappel du tout.
class _RappelPriere extends ConsumerStatefulWidget {
  const _RappelPriere();
  @override
  ConsumerState<_RappelPriere> createState() => _RappelPriereState();
}

class _RappelPriereState extends ConsumerState<_RappelPriere> {
  Timer? _horloge;

  @override
  void initState() {
    super.initState();
    // Une minute : le compte a rebours s'affiche en heures et minutes, donc
    // rafraichir plus souvent redessinerait pour rien. Plus rarement, et le
    // « dans 1 h 23 » resterait faux jusqu'a une minute -- visible quand on
    // regarde justement pour savoir s'il reste du temps.
    _horloge = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _horloge?.cancel();
    super.dispose();
  }

  static const _noms = {
    PrayerName.fajr: 'Sobh',
    PrayerName.dhuhr: 'Dhohr',
    PrayerName.asr: 'Asr',
    PrayerName.maghrib: 'Maghrib',
    PrayerName.isha: 'Ichaa',
  };

  /// « dans 1 h 23 », « dans 24 min », « maintenant ».
  String _restant(Duration d) {
    if (d.inMinutes < 1) return 'maintenant';
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) return 'dans $m min';
    return m == 0 ? 'dans $h h' : 'dans $h h $m';
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(prayerSettingsProvider);
    final suivante = etat.prochainePriere;
    // Position pas encore connue, ou refusee : rien a annoncer. On n'affiche
    // PAS un bandeau vide ni un « -- : -- » qui ferait croire a une panne.
    if (suivante == null) return const SizedBox.shrink();

    final locale = suivante.time.toLocal();
    final hm = '${locale.hour.toString().padLeft(2, '0')}:'
        '${locale.minute.toString().padLeft(2, '0')}';
    final reste = suivante.time.difference(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      child: Material(
        color: AppColors.green900,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PrayerTimesSettingsScreen())),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
            child: Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    size: 19, color: AppColors.brassLight),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Prochaine priere'.toUpperCase(),
                          style: GoogleFonts.manrope(
                              fontSize: 9.5,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brassLight)),
                      const SizedBox(height: 3),
                      Text('${_noms[suivante.name]} · $hm',
                          style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.cream)),
                    ],
                  ),
                ),
                Text(_restant(reste),
                    style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brassLight)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.brassLight),
              ],
            ),
          ),
        ),
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

class _SurahTile extends StatelessWidget {
  final Surah surah;
  const _SurahTile({required this.surah});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final place = surah.revelationPlace == 'makkah' ? t.surahMeccan : t.surahMedinan;
    final metaLine = t.surahMetaLine(surah.versesCount, place);
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
            if (!isArabic)
              Text(
                surah.nameArabic,
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                  fontSize: 20, color: AppColors.green800,
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
    final cles = ref.watch(marquePagesProvider);
    if (cles.isEmpty) return const SizedBox.shrink();
    // `state` est un LinkedHashSet : le DERNIER pose est le dernier insere.
    final p = cles.last.split(':').map(int.parse).toList();
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
