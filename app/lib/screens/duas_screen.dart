import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/duas_data.dart';
import '../l10n/app_localizations.dart';
import '../models/dua.dart';
import '../models/radio_dhikr.dart';
import '../providers/dua_prefs_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/dua_card.dart';
import 'dua_collection_screen.dart';
import 'rite_screen.dart';

/// Hub des invocations.
///
/// REFONTE 2026-07-20. L'écran précédent était une liste plate de ~20 duas
/// filtrée par six puces. Ça tenait tant que le catalogue était petit ; à
/// ~130 entrées, une liste plate n'est plus navigable — on scrolle sans
/// jamais savoir ce qui existe.
///
/// Trois entrées désormais, par ordre de fréquence d'usage réel :
///   1. « Maintenant » — l'app propose ce qui correspond à l'heure et au
///      jour (cf. `currentDuaMoment`). Un tap, on y est.
///   2. La recherche — pour qui sait ce qu'il cherche.
///   3. Les six univers — pour explorer.
/// Les favoris s'intercalent en 1 bis dès qu'il y en a.
class DuasScreen extends ConsumerStatefulWidget {
  const DuasScreen({super.key});

  @override
  ConsumerState<DuasScreen> createState() => _DuasScreenState();
}

class _DuasScreenState extends ConsumerState<DuasScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final favorites = ref.watch(favoriteDuasProvider);
    final searching = _query.trim().isNotEmpty;
    final results = searching ? searchDuas(_query) : const <Dua>[];

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.green900,
            foregroundColor: AppColors.cream,
            title: Text(
              t.duasScreenTitle,
              style: GoogleFonts.scheherazadeNew(
                fontSize: 22,
                color: AppColors.brassLight,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(58),
              child: _SearchField(
                controller: _searchCtrl,
                hintText: t.duasSearchHint,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          if (searching)
            _SearchResults(results: results)
          else ...[
            SliverToBoxAdapter(child: _MomentCard(moment: currentDuaMoment())),
            if (favorites.isNotEmpty)
              SliverToBoxAdapter(child: _FavoritesRow(ids: favorites)),
            SliverToBoxAdapter(child: _SectionLabel(t.duasExplore)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.builder(
                itemCount: kDuaUnivers.length,
                itemBuilder: (_, i) => _UniversCard(univers: kDuaUnivers[i]),
              ),
            ),
            // ── ÉCOUTE CONTINUE (2026-08-17) ────────────────────────────────
            // Placée APRÈS les invocations, et pas avant : ce sont des flux,
            // pas des duas. L'écran existe d'abord pour dire une invocation
            // précise ; la radio est un complément d'ambiance. Cf.
            // `RadioDhikr` pour ce que ces flux sont, et ne sont pas.
            SliverToBoxAdapter(child: _SectionLabel(t.duasRadiosTitre)),
            SliverToBoxAdapter(child: const _RadiosDhikr()),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.hintText, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.cream,
              hintText: hintText,
              hintStyle: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight),
              prefixIcon:
                  const Icon(Icons.search_rounded, size: 18, color: AppColors.green700),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: AppColors.inkLight,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(21),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      );
}

/// Bandeau contextuel — l'usage n°1 est « il est telle heure, que dit-on ? ».
class _MomentCard extends StatelessWidget {
  final DuaMoment moment;
  const _MomentCard({required this.moment});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final collection = kCollectionsById[moment.collectionId];
    final univers = kUniversByCollectionId[moment.collectionId];
    if (collection == null || univers == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DuaCollectionScreen(collectionId: collection.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.green900, univers.color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Text(moment.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.duasNow,
                      style: GoogleFonts.manrope(
                        fontSize: 9,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brassLight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isArabic ? collection.labelAr : moment.titleFr,
                      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                      style: isArabic
                          ? GoogleFonts.scheherazadeNew(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: AppColors.cream,
                            )
                          : GoogleFonts.fraunces(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppColors.cream,
                            ),
                    ),
                    // Pas de sous-titre descriptif en arabe : moment.subtitle
                    // n'existe qu'en français dans les données actuelles --
                    // mieux vaut l'omettre que de fabriquer une traduction
                    // non relue d'un texte à caractère religieux.
                    if (!isArabic) ...[
                      const SizedBox(height: 3),
                      Text(
                        moment.subtitle,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.cream.withAlpha(200),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppColors.brassLight, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesRow extends ConsumerWidget {
  final Set<String> ids;
  const _FavoritesRow({required this.ids});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final duas = ids.map((id) => kDuasById[id]).whereType<Dua>().toList();
    if (duas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(t.duasMyFavorites),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: duas.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final dua = duas[i];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DuaCollectionScreen(
                      collectionId: dua.tags.first,
                      highlightDuaId: dua.id,
                    ),
                  ),
                ),
                child: Container(
                  width: 168,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cream300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.brass),
                      const SizedBox(height: 4),
                      Text(
                        isArabic ? dua.titleAr : dua.titleFr,
                        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: isArabic
                            ? GoogleFonts.scheherazadeNew(
                                fontSize: 13, color: AppColors.ink, height: 1.3)
                            : GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                                height: 1.3,
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UniversCard extends StatelessWidget {
  final DuaUnivers univers;
  const _UniversCard({required this.univers});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    // Les collections de rite (`rite:umra`) ne comptent pas d'invocations :
    // afficher « 0 invocation » à côté de « Hajj » serait absurde, on compte
    // donc les étapes pour elles.
    final total = univers.collections
        .where((c) => !c.id.startsWith('rite:'))
        .fold<int>(0, (sum, c) => sum + duasForCollection(c.id).length);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cream300),
      ),
      child: Theme(
        // Retire les liserés par défaut de l'ExpansionTile, qui coupent la
        // carte en deux visuellement.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: univers.color.withAlpha(28),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(univers.emoji, style: const TextStyle(fontSize: 22)),
          ),
          title: Text(
            isArabic ? univers.labelAr : univers.labelFr,
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: isArabic
                ? GoogleFonts.scheherazadeNew(
                    fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)
                : GoogleFonts.fraunces(
                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          // Le tagline n'existe qu'en français dans les données actuelles --
          // en arabe on affiche seulement le compte (donnée numérique, pas de
          // traduction à fabriquer), plutôt que de laisser du français.
          subtitle: isArabic
              ? (total > 0 ? Text(t.duasInvocationCount(total),
                  style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight))
                  : null)
              : Text(
                  total > 0
                      ? '${univers.tagline} · ${t.duasInvocationCount(total)}'
                      : univers.tagline,
                  style: GoogleFonts.manrope(fontSize: 11, color: AppColors.inkLight),
                ),
          trailing: isArabic
              ? null
              : Text(
                  univers.labelAr,
                  textDirection: TextDirection.rtl,
                  style: GoogleFonts.scheherazadeNew(
                    fontSize: 16,
                    color: univers.color,
                  ),
                ),
          children: [
            for (final c in univers.collections)
              _CollectionRow(collection: c, accent: univers.color),
          ],
        ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  final DuaCollection collection;
  final Color accent;
  const _CollectionRow({required this.collection, required this.accent});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final isRite = collection.id.startsWith('rite:');
    final count = isRite ? 0 : duasForCollection(collection.id).length;

    return InkWell(
      onTap: () {
        // Une collection « rite:<id> » ouvre le guide pas à pas au lieu
        // d'une liste — c'est le seul cas où le second niveau de navigation
        // change de nature.
        if (isRite) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RiteScreen(riteId: collection.id.substring(5)),
          ));
        } else {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => DuaCollectionScreen(collectionId: collection.id),
          ));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text(collection.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isArabic ? collection.labelAr : collection.labelFr,
                          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                          style: isArabic
                              ? GoogleFonts.scheherazadeNew(
                                  fontSize: 15, color: AppColors.ink)
                              : GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                        ),
                      ),
                      if (isRite) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            t.duasGuideBadge,
                            style: GoogleFonts.manrope(
                              fontSize: 8,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // collection.hint n'existe qu'en français -- omis en arabe
                  // pour la même raison que le tagline plus haut.
                  if (!isArabic) ...[
                    const SizedBox(height: 2),
                    Text(
                      collection.hint,
                      style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        color: AppColors.inkLight,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (count > 0)
              Text(
                '$count',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.inkLight),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<Dua> results;
  const _SearchResults({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text(
              AppLocalizations.of(context)!.duasNoneFound,
              style: const TextStyle(color: AppColors.inkLight),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      sliver: SliverList.builder(
        itemCount: results.length,
        itemBuilder: (_, i) {
          final dua = results[i];
          final accent =
              kUniversByCollectionId[dua.tags.first]?.color ?? AppColors.brass;
          return DuaCard(dua: dua, accent: accent);
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 16, 10),
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w800,
            color: AppColors.inkLight,
          ),
        ),
      );
}


/// Les trois radios de dhikr, en écoute continue.
///
/// UN SEUL lecteur pour les trois, et il est PROPRE À CETTE SECTION : ne pas
/// réutiliser `AudioPlayerService`, qui porte l'écoute du Mushaf (position de
/// verset, minuteur de frontière, récitateur courant). Un flux sans fin n'a
/// aucune de ces notions, et les mélanger ferait qu'appuyer ici couperait la
/// récitation en cours -- exactement le genre de couplage que ce projet a déjà
/// payé ailleurs.
class _RadiosDhikr extends StatefulWidget {
  const _RadiosDhikr();

  @override
  State<_RadiosDhikr> createState() => _RadiosDhikrState();
}

class _RadiosDhikrState extends State<_RadiosDhikr> {
  final _player = AudioPlayer();
  int? _enCours;
  bool _chargement = false;

  /// Reconnexions consécutives sans écoute utile, pour ne pas boucler à
  /// l'infini quand le flux est réellement mort (cf. `_surCompletion`).
  int _reconnexions = 0;
  DateTime? _debutEcoute;
  StreamSubscription<void>? _finSub;

  @override
  void initState() {
    super.initState();
    // ── UN FLUX SHOUTCAST N'A PAS DE FIN, LE LECTEUR CROIT QUE SI ──────────
    //
    // Constat utilisateur : « c'est pas continu, ça s'arrête ». Vérifié à la
    // source : le serveur diffuse bien sans fin (761 Ko reçus en 30 s), et
    // ses en-têtes disent ce qu'il est vraiment --
    //     Transfer-Encoding: chunked
    //     Accept-Ranges: none
    //     icy-notice2: Shoutcast DNAS ... / icy-br: 128
    // C'est un flux ICY/Shoutcast, pas un fichier. Le lecteur Android, lui,
    // le traite comme un fichier : au premier creux de tampon il conclut à la
    // fin du morceau, émet `onPlayerComplete` et s'arrête.
    //
    // On se RECONNECTE donc tant que l'utilisateur n'a pas appuyé sur stop.
    // Ce n'est pas un palliatif à un défaut de notre code : la fin annoncée
    // par le lecteur est FAUSSE pour ce type de source, et aucune couche en
    // amont ne peut la rendre vraie.
    _finSub = _player.onPlayerComplete.listen((_) => _surCompletion());
  }

  Future<void> _surCompletion() async {
    final r = _enCours;
    if (r == null || !mounted) return;
    final radio = kRadiosDhikr.where((x) => x.id == r).firstOrNull;
    if (radio == null) return;
    // Une reconnexion n'est légitime que si l'on a réellement écouté : sinon
    // c'est que le flux ne s'ouvre pas, et réessayer sans fin ne ferait que
    // marteler le serveur en silence. Trois échecs immédiats -> on abandonne
    // et on le DIT.
    final ecouteUtile = _debutEcoute != null &&
        DateTime.now().difference(_debutEcoute!).inSeconds >= 5;
    _reconnexions = ecouteUtile ? 0 : _reconnexions + 1;
    if (_reconnexions >= 3) {
      if (!mounted) return;
      final t = AppLocalizations.of(context)!;
      setState(() {
        _enCours = null;
        _chargement = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.duasRadioErreur)));
      return;
    }
    try {
      _debutEcoute = DateTime.now();
      await _player.play(UrlSource(radio.url));
    } catch (_) {
      // Silencieux ici : la prochaine complétion repassera par ce chemin, et
      // le compteur ci-dessus finira par trancher.
    }
  }

  @override
  void dispose() {
    _finSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _titre(AppLocalizations t, String cle) => switch (cle) {
        'matin' => t.duasRadioMatin,
        'soir' => t.duasRadioSoir,
        _ => t.duasRadioRoqya,
      };

  Future<void> _basculer(RadioDhikr r) async {
    final t = AppLocalizations.of(context)!;
    // Deuxième appui sur la radio en cours : on arrête. Sans ça, il n'y a
    // aucun moyen de couper un flux qui, par nature, ne se termine jamais.
    if (_enCours == r.id) {
      // `_enCours` à null AVANT le stop : `onPlayerComplete` peut se
      // déclencher pendant l'arrêt, et `_surCompletion` doit alors voir que
      // plus rien n'est demandé -- sinon un appui sur stop relancerait le flux.
      setState(() => _enCours = null);
      await _player.stop();
      return;
    }
    setState(() {
      _chargement = true;
      _enCours = r.id;
    });
    try {
      await _player.stop();
      _reconnexions = 0;
      _debutEcoute = DateTime.now();
      await _player.play(UrlSource(r.url));
      if (mounted) setState(() => _chargement = false);
    } catch (_) {
      // Un bouton qui ne fait rien est indiscernable d'un bug : on le DIT.
      // Même raisonnement que pour « Ma voix » dans la fiche d'aide.
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _enCours = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.duasRadioErreur)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        children: [
          for (final r in kRadiosDhikr)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cream300),
              ),
              child: ListTile(
                onTap: () => _basculer(r),
                leading: (_chargement && _enCours == r.id)
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _enCours == r.id
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                        color: AppColors.green700,
                        size: 28,
                      ),
                title: Text(_titre(t, r.cleTitre),
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                subtitle: Text(t.duasRadioSousTitre,
                    style: GoogleFonts.manrope(
                        fontSize: 11.5, color: AppColors.inkLight)),
              ),
            ),
        ],
      ),
    );
  }
}
