import 'package:audioplayers/audioplayers.dart' show AssetSource, UrlSource;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/dua.dart';
import '../providers/dua_prefs_provider.dart';
import '../providers/player_provider.dart';
import '../services/dua_audio_service.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import 'tajweed_text.dart';

/// Carte d'une invocation, repliable.
///
/// EXTRAITE de `duas_screen.dart` (2026-07-20) : elle est désormais utilisée
/// à trois endroits — la liste d'une collection, les résultats de recherche,
/// et les étapes d'un rite guidé, où les invocations propres à l'étape
/// s'affichent en ligne. La dupliquer aurait garanti trois comportements
/// divergents au premier ajustement.
class DuaCard extends ConsumerStatefulWidget {
  final Dua dua;

  /// Couleur d'accent héritée de l'univers parent.
  final Color accent;

  /// Ouvre la carte d'emblée — utilisé dans les rites, où l'invocation EST
  /// le contenu de l'étape et où replier n'apporte rien.
  final bool initiallyExpanded;

  /// Vrai quand cette carte est celle en cours dans la lecture enchaînée
  /// (« Lire tout » de `DuaCollectionScreen`) — pur repère visuel, la
  /// progression réelle (répétitions, chargement) vit dans le bandeau de
  /// `_SequenceBar`, pas ici, pour ne pas dupliquer l'état du lecteur.
  final bool playingInSequence;

  /// Vrai tant qu'une lecture enchaînée est active sur l'écran parent — le
  /// bouton « Écouter » de CETTE carte est alors désactivé. Les deux
  /// partagent le même lecteur global (`playerProvider`) : sans ce verrou,
  /// un tap ici pendant la séquence percuterait sa lecture en cours (verset
  /// remplacé sous elle, décompte de répétitions faussé).
  final bool audioLocked;

  const DuaCard({
    super.key,
    required this.dua,
    this.accent = AppColors.brass,
    this.initiallyExpanded = false,
    this.playingInSequence = false,
    this.audioLocked = false,
  });

  @override
  ConsumerState<DuaCard> createState() => _DuaCardState();
}

class _DuaCardState extends ConsumerState<DuaCard> {
  late bool _expanded = widget.initiallyExpanded;

  // Compteur de répétitions (demande utilisateur 2026-07-10 : pouvoir taper
  // à chaque récitation pour savoir où on en est / quand c'est terminé).
  // Volontairement en mémoire seule (pas persisté) : c'est un suivi de
  // séance en cours, pas un historique. À ne pas confondre avec les
  // compteurs de RITE, eux persistés (un Hajj dure six jours) —
  // cf. `dua_prefs_provider.dart`.
  int _repeatDone = 0;
  bool _audioLoading = false;
  bool _showVirtue = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final dua = widget.dua;
    final isFav = ref.watch(favoriteDuasProvider).contains(dua.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.playingInSequence ? widget.accent : AppColors.cream300,
          width: widget.playingInSequence ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              _expanded = !_expanded;
              if (!_expanded) _repeatDone = 0;
            }),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isArabic)
                          Text(
                            dua.titleFr,
                            style: GoogleFonts.fraunces(
                              fontSize: 14,
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          dua.titleAr,
                          textDirection: TextDirection.rtl,
                          style: GoogleFonts.scheherazadeNew(
                            fontSize: isArabic ? 16 : 14,
                            color: isArabic ? AppColors.ink : AppColors.green700,
                            fontWeight: isArabic ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pastille de répétitions visible carte repliée : c'est
                  // l'information qui décide si on ouvre (×100 ne se tente
                  // pas dans la file d'attente d'un supermarché).
                  if (dua.repeat > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.accent.withAlpha(28),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '×${dua.repeat}',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: widget.accent,
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () =>
                        ref.read(favoriteDuasProvider.notifier).toggle(dua.id),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 20,
                      color: isFav ? AppColors.brass : AppColors.inkLight,
                    ),
                    tooltip: isFav ? t.duaRemoveFavorite : t.duaAddFavorite,
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.inkLight,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: AppColors.cream300),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.green50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TajweedText(
                      textUthmani: dua.textAr,
                      fontSize: 22,
                      lineHeight: 2.0,
                    ),
                  ),
                  // Translittération en script latin -- masquée en arabe
                  // (règle verrouillée REFONTE_IHM.md §7bis : aucun mot latin).
                  if (dua.translit != null && !isArabic) ...[
                    const SizedBox(height: 10),
                    Text(
                      dua.translit!,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.green700,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ],
                  // Écoute (duas coraniques uniquement — réutilise le
                  // réciteur déjà présent dans l'app ; les invocations hadith
                  // utilisent l'audio de hisnmuslim.com depuis le 2026-08-07
                  // (cf. `Dua.audioUrl`) -- recherche 2026-07-10 corrigée.
                  if (dua.hasAudio) ...[
                    const SizedBox(height: 10),
                    _ListenButton(
                      loading: _audioLoading,
                      locked: widget.audioLocked,
                      onTap: _playAudio,
                    ),
                  ],
                  // Traduction, source et mérite -- texte français uniquement
                  // dans les données actuelles, donc masqués en arabe (même
                  // règle que le texte coranique : en arabe, pas de traduction
                  // affichée à côté, cf. REFONTE_IHM.md §7bis). Mieux vaut
                  // omettre que fabriquer une traduction non relue d'un texte
                  // à caractère religieux.
                  if (!isArabic) ...[
                  const SizedBox(height: 12),
                  Text(
                    dua.translationFr,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.inkLight,
                      height: 1.6,
                    ),
                  ),
                  if (dua.source != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.bookmark_outline,
                            size: 13, color: AppColors.brass),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dua.source!,
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              color: AppColors.brass,
                              fontStyle: FontStyle.italic,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Le mérite est replié par défaut : c'est ce qui donne
                  // envie de pratiquer, mais l'afficher d'emblée noierait le
                  // texte de l'invocation, qui reste l'essentiel.
                  if (dua.virtue != null) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => setState(() => _showVirtue = !_showVirtue),
                      child: Row(
                        children: [
                          Icon(
                            _showVirtue
                                ? Icons.expand_less_rounded
                                : Icons.auto_awesome_rounded,
                            size: 14,
                            color: widget.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _showVirtue ? t.duaHideVirtue : t.duaShowVirtue,
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: widget.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showVirtue) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.accent.withAlpha(18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(color: widget.accent, width: 3),
                          ),
                        ),
                        child: Text(
                          dua.virtue!,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppColors.inkLight,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ], // fin du bloc masqué en arabe (traduction/source/mérite)
                  ],
                  if (dua.repeat > 1) ...[
                    const SizedBox(height: 14),
                    _RepeatCounter(
                      done: _repeatDone,
                      target: dua.repeat,
                      accent: widget.accent,
                      onTap: () => setState(() {
                        if (_repeatDone < dua.repeat) _repeatDone++;
                      }),
                      onReset: () => setState(() => _repeatDone = 0),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _playAudio() async {
    final dua = widget.dua;
    if (_audioLoading || widget.audioLocked || !dua.hasAudio) return;
    setState(() => _audioLoading = true);
    try {
      if (dua.isQuranic) {
        // Un seul son à la fois dans l'app : coupe l'éventuelle lecture
        // hadith en cours avant de prendre la main sur le lecteur partagé.
        await DuaAudioService.instance.stop();
        final ranges = dua.verseRanges;
        if (ranges != null) {
          // Plusieurs versets (potentiellement plusieurs sourates, ex. les
          // muʿawwidhāt) -- une seule lecture, pas de répétition ici : le
          // bouton individuel sert à ENTENDRE la prononciation, pas à
          // imposer le nombre de répétitions (cf. `_RepeatCounter`, à taper
          // manuellement).
          final playlist = await QuranApi.fetchVerseRanges(ranges);
          if (playlist.isNotEmpty) {
            await ref.read(playerProvider.notifier).play(playlist.first, playlist);
          }
        } else {
          final verses = await QuranApi.fetchVerses(dua.surahNumber!);
          final verse = verses.firstWhere((v) => v.ayahNumber == dua.ayahNumber);
          await ref.read(playerProvider.notifier).play(verse, [verse]);
        }
      } else {
        await ref.read(playerProvider.notifier).stop();
        final asset = dua.audioAsset;
        await DuaAudioService.instance.play(
          asset != null ? AssetSource(asset) : UrlSource(dua.audioUrl!),
          key: dua.audioKey!,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.duaPlaybackError('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }
}

class _ListenButton extends StatelessWidget {
  final bool loading;
  final bool locked;
  final VoidCallback onTap;
  const _ListenButton({
    required this.loading,
    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: (loading || locked) ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: (locked ? AppColors.inkLight : AppColors.brass).withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: locked ? AppColors.inkLight : AppColors.brass),
                )
              else
                Icon(Icons.play_circle_outline_rounded,
                    size: 16,
                    color: locked ? AppColors.inkLight : AppColors.brass),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.coachExplanationListen,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: locked ? AppColors.inkLight : AppColors.brass,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Compteur de répétitions — demande utilisateur 2026-07-10 : pouvoir taper
/// à chaque récitation pour suivre où on en est et savoir quand c'est fini,
/// plutôt que de compter de tête (utile pour ×33, ×100...).
class _RepeatCounter extends StatelessWidget {
  final int done;
  final int target;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const _RepeatCounter({
    required this.done,
    required this.target,
    required this.accent,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final complete = done >= target;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: complete ? null : onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: complete
                    ? AppColors.green700.withAlpha(30)
                    : AppColors.cream300.withAlpha(120),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: complete ? AppColors.green700 : accent,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        complete
                            ? Icons.check_circle_rounded
                            : Icons.touch_app_rounded,
                        size: 18,
                        color: complete ? AppColors.green700 : accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        complete ? t.duaRepeatComplete(target) : '$done / $target',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: complete ? AppColors.green700 : AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: target == 0 ? 0 : done / target,
                        minHeight: 4,
                        backgroundColor: Colors.white.withAlpha(140),
                        color: complete ? AppColors.green700 : accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (done > 0) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded,
                size: 18, color: AppColors.inkLight),
            tooltip: t.duaResetCount,
          ),
        ],
      ],
    );
  }
}
