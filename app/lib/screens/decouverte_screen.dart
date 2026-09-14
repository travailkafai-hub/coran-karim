import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/guides_catalogue.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/guide_interactif.dart';
import '../widgets/mushaf_cover_reveal.dart';

/// ChGPT: searchable chapters, direct steps and tutorial-only resume state.
class DecouverteScreen extends StatefulWidget {
  const DecouverteScreen({super.key});
  @override
  State<DecouverteScreen> createState() => _DecouverteScreenState();
}

class _DecouverteScreenState extends State<DecouverteScreen> {
  static const _pref = 'chgpt_guide_positions_v1';
  final _positions = <String, int>{};
  final _search = TextEditingController();
  String _query = '';
  bool _lancement = false;
  Future<void> _ecriture = Future.value();
  String _tr(String fr, String en, String ar) =>
      guideTexte(context, fr, en, ar);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pref);
      if (!mounted || raw == null || _lancement) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      setState(() {
        for (final entry in decoded.entries) {
          if (entry.key is String && entry.value is int && entry.value >= 0) {
            _positions[entry.key as String] = entry.value as int;
          }
        }
      });
    } catch (_) {
      /* A corrupt guide bookmark must not prevent discovery. */
    }
  }

  void _retenir(String id, int i) {
    _positions[id] = i;
    final json = jsonEncode(_positions);
    // Serialize writes so rapid Next/Previous cannot restore an older index.
    _ecriture = _ecriture.then((_) async {
      try {
        await (await SharedPreferences.getInstance()).setString(_pref, json);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _lancer(String id, List<EtapeGuide> etapes, {int? index}) async {
    if (_lancement || etapes.isEmpty) return;
    setState(() => _lancement = true);
    final t = AppLocalizations.of(context)!;
    try {
      await GuideHote.lancer(
        context,
        etapes: etapes,
        indexInitial: (index ?? _positions[id] ?? 0).clamp(
          0,
          etapes.length - 1,
        ),
        onIndex: (i) => _retenir(id, i),
        libellePasser: t.guidePasser,
        libelleSuivant: t.guideSuivant,
        libelleFin: t.guideFin,
      );
    } finally {
      if (mounted) setState(() => _lancement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final chapters = kChapitresGuide;
    final details = {
      for (final ch in chapters) ch.id: etapesDecouverte(ch, context, t),
    };
    final all = [for (final ch in chapters.skip(1)) ...details[ch.id]!];
    final visible = chapters.where((ch) {
      final q = _query.trim().toLowerCase();
      return q.isEmpty ||
          ch.titre(t).toLowerCase().contains(q) ||
          details[ch.id]!.any(
            (e) => '${e.titre} ${e.texte}'.toLowerCase().contains(q),
          );
    }).toList();
    final style = GoogleFonts.manrope(
      color: AppColors.ink,
      fontSize: 14,
      letterSpacing: 0,
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F5),
      appBar: AppBar(
        title: Text(
          t.guideDecouverteTitre,
          style: style.copyWith(fontWeight: FontWeight.w800, fontSize: 19),
        ),
        backgroundColor: const Color(0xFFF4F7F5),
        foregroundColor: AppColors.ink,
      ),
      body: DefaultTextStyle(
        style: style,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    mushafCoverAsset,
                    width: 64,
                    height: 96,
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr('À ton rythme', 'At your own pace', 'على وتيرتك'),
                          style: style.copyWith(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tr(
                            'Parcours complet ou accès direct à une fonctionnalité.',
                            'Full tour or direct access to a feature.',
                            'جولة كاملة أو وصول مباشر إلى ميزة.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _lancement
                              ? null
                              : () => _lancer('complet', all),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.green800,
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            _positions.containsKey('complet')
                                ? _tr(
                                    'Reprendre le parcours',
                                    'Resume tour',
                                    'استئناف الجولة',
                                  )
                                : _tr(
                                    'Tout découvrir',
                                    'Explore everything',
                                    'اكتشاف الكل',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: style,
                decoration: InputDecoration(
                  hintText: _tr(
                    'Rechercher une fonctionnalité',
                    'Find a feature',
                    'البحث عن ميزة',
                  ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: _tr(
                            'Effacer la recherche',
                            'Clear search',
                            'مسح البحث',
                          ),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _tr(
                    'Aucune fonctionnalité trouvée.',
                    'No features found.',
                    'لم يتم العثور على ميزة.',
                  ),
                ),
              ),
            for (final ch in visible)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: PageStorageKey(ch.id),
                    leading: Text(
                      ch.emoji,
                      style: const TextStyle(fontSize: 23),
                    ),
                    title: Text(
                      ch.titre(t),
                      style: style.copyWith(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${details[ch.id]!.length} ${_tr('étapes', 'steps', 'خطوات')}',
                      style: style.copyWith(
                        fontSize: 12,
                        color: AppColors.inkLight,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: _lancement
                                    ? null
                                    : () => _lancer(ch.id, details[ch.id]!),
                                icon: Icon(
                                  _positions.containsKey(ch.id)
                                      ? Icons.play_circle_outline
                                      : Icons.play_arrow,
                                ),
                                label: Text(
                                  _positions.containsKey(ch.id)
                                      ? _tr('Reprendre', 'Resume', 'استئناف')
                                      : _tr('Commencer', 'Start', 'ابدأ'),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: _tr(
                                'Recommencer le chapitre',
                                'Restart chapter',
                                'إعادة الفصل',
                              ),
                              icon: const Icon(Icons.replay),
                              onPressed: _lancement
                                  ? null
                                  : () => _lancer(
                                      ch.id,
                                      details[ch.id]!,
                                      index: 0,
                                    ),
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < details[ch.id]!.length; i++)
                        ListTile(
                          dense: true,
                          leading: Text(
                            '${i + 1}',
                            style: style.copyWith(color: AppColors.green700),
                          ),
                          title: Text(
                            details[ch.id]![i].titre,
                            style: style.copyWith(fontSize: 13),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: _lancement
                              ? null
                              : () => _lancer(ch.id, details[ch.id]!, index: i),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
