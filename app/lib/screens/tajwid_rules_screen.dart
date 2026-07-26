// Écran de sélection des règles de tajwid + presets -- REFONTE_IHM.md §1.4.
// Trois presets (tajwid strict / adulte tolérant tajwid / enfant tolérant
// lettres) + réglages fins. Les règles non fiables (cf.
// assets/data/rule_reliability.json) sont grisées et non activables --
// jamais corriger un élève avec un détecteur peu fiable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../models/judgement_options.dart';
import '../providers/app_settings_provider.dart';
import '../providers/judgement_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/tajwid_help_sheet.dart' show kTajwidRuleInfo;

class TajwidRulesScreen extends ConsumerWidget {
  const TajwidRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(judgementOptionsProvider);
    final reliabilityAsync = ref.watch(ruleReliabilityProvider);
    final notifier = ref.read(judgementOptionsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: AppColors.cream,
        title: Text('Vérification de la récitation',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: reliabilityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (reliability) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PresetRow(current: options.preset, notifier: notifier),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Harakat exigées'),
              subtitle: const Text(
                  'Désactivé : les voyelles courtes ne comptent pas comme erreur'),
              value: options.strictHarakat,
              onChanged: notifier.setStrictHarakat,
              activeTrackColor: AppColors.green700,
            ),
            SwitchListTile(
              title: const Text('Tolérer les lettres proches'),
              subtitle: const Text(
                  'ص/س, ط/ت, ض/د, ذ/ز, ح/ه, ق/ك, ع/ء comptées équivalentes (mode enfant)'),
              value: options.tolerateConfusables,
              onChanged: notifier.setTolerateConfusables,
              activeTrackColor: AppColors.green700,
            ),
            const Divider(height: 32),
            _RepeatEngineSettings(preset: options.preset),
            const Divider(height: 32),
            Text('RÈGLES DE TAJWID',
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.inkLight)),
            const SizedBox(height: 4),
            Text(
              'Choisissez les règles que l\'app doit vérifier pendant votre récitation.',
              style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.inkLight),
            ),
            const SizedBox(height: 8),
            for (final rule in TajwidRule.values)
              _RuleTile(
                rule: rule,
                active: options.activeRules.contains(rule),
                reliability: reliability[rule],
                onChanged: (v) => notifier.toggleRule(rule, v),
              ),
          ],
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final JudgementPreset current;
  final JudgementOptionsNotifier notifier;
  const _PresetRow({required this.current, required this.notifier});

  @override
  Widget build(BuildContext context) {
    Widget chip(JudgementPreset preset, String label, IconData icon) {
      final selected = current == preset;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => notifier.applyPreset(preset),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: selected ? AppColors.green800 : AppColors.cream200,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? AppColors.brass : AppColors.cream300,
                    width: selected ? 1.6 : 1),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      color: selected ? AppColors.brassLight : AppColors.inkLight,
                      size: 22),
                  const SizedBox(height: 6),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.cream : AppColors.ink)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(JudgementPreset.tajwid, 'Tajwid', Icons.auto_awesome),
        chip(JudgementPreset.adulte, 'Adulte', Icons.person),
        chip(JudgementPreset.enfant, 'Enfant', Icons.child_care),
      ],
    );
  }
}

/// Réglages du moteur de répétition incrémentale du Coach (étape "Répète",
/// demande utilisateur 2026-07-24) -- vivent ici, avec les autres réglages
/// de vérification, pas dans Settings global (même logique déjà en place
/// pour les presets tajwid/adulte/enfant).
class _RepeatEngineSettings extends ConsumerWidget {
  final JudgementPreset preset;
  const _RepeatEngineSettings({required this.preset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final chunkWords = ref.watch(adultChunkWordCountProvider);
    final windowSize = ref.watch(repeatWindowSizeProvider);
    final isEnfant = preset == JudgementPreset.enfant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.settingsRepeatEngineSectionTitle,
            style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.inkLight)),
        const SizedBox(height: 8),
        Opacity(
          opacity: isEnfant ? 0.4 : 1.0,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: !isEnfant,
            title: Text(t.settingsAdultChunkWordCountTitle,
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            subtitle: Text(
                t.settingsAdultChunkWordCountDescription(kAdultChunkWordCountMax),
                style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight)),
            trailing: Text('$chunkWords',
                style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.brass)),
            onTap: isEnfant
                ? null
                : () => showModalBottomSheet(
                      context: context,
                      backgroundColor: AppColors.green900,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                      builder: (_) => _StepperSheet(
                        title: t.settingsAdultChunkWordCountTitle,
                        description:
                            t.settingsAdultChunkWordCountDescription(kAdultChunkWordCountMax),
                        current: chunkWords,
                        min: kAdultChunkWordCountMin,
                        max: kAdultChunkWordCountMax,
                        onPick: (v) {
                          ref.read(adultChunkWordCountProvider.notifier).set(v);
                          Navigator.pop(context);
                        },
                      ),
                    ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.settingsRepeatWindowSizeTitle,
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
          subtitle: Text(t.settingsRepeatWindowSizeDescription(kRepeatWindowSizeMax),
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight)),
          trailing: Text('$windowSize',
              style: GoogleFonts.manrope(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.brass)),
          onTap: () => showModalBottomSheet(
            context: context,
            backgroundColor: AppColors.green900,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            builder: (_) => _StepperSheet(
              title: t.settingsRepeatWindowSizeTitle,
              description: t.settingsRepeatWindowSizeDescription(kRepeatWindowSizeMax),
              current: windowSize,
              min: kRepeatWindowSizeMin,
              max: kRepeatWindowSizeMax,
              onPick: (v) {
                ref.read(repeatWindowSizeProvider.notifier).set(v);
                Navigator.pop(context);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Feuille stepper générique +/- (même forme que l'ancienne
/// `_RepeatDrillCountSheet` de settings_screen.dart, retirée avec l'ancien
/// mode de répétition -- reprise ici de façon paramétrable pour servir aux
/// deux nouveaux réglages sans dupliquer le boilerplate).
class _StepperSheet extends StatefulWidget {
  final String title;
  final String description;
  final int current;
  final int min;
  final int max;
  final void Function(int) onPick;
  const _StepperSheet({
    required this.title,
    required this.description,
    required this.current,
    required this.min,
    required this.max,
    required this.onPick,
  });

  @override
  State<_StepperSheet> createState() => _StepperSheetState();
}

class _StepperSheetState extends State<_StepperSheet> {
  late int _value = widget.current;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: GoogleFonts.fraunces(fontSize: 16, color: AppColors.brassLight)),
            const SizedBox(height: 4),
            Text(widget.description,
                style: GoogleFonts.manrope(
                    fontSize: 12, color: AppColors.cream.withAlpha(180))),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed:
                      _value > widget.min ? () => setState(() => _value--) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: AppColors.cream,
                  disabledColor: AppColors.cream.withAlpha(70),
                  iconSize: 30,
                ),
                SizedBox(
                  width: 64,
                  child: Text('$_value',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                          fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.cream)),
                ),
                IconButton(
                  onPressed:
                      _value < widget.max ? () => setState(() => _value++) : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: AppColors.cream,
                  disabledColor: AppColors.cream.withAlpha(70),
                  iconSize: 30,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => widget.onPick(_value),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brass,
                  foregroundColor: AppColors.green900,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: Text(AppLocalizations.of(context)!.settingsValidate,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
}

class _RuleTile extends StatelessWidget {
  final TajwidRule rule;
  final bool active;
  final RuleReliability? reliability;
  final ValueChanged<bool> onChanged;

  const _RuleTile({
    required this.rule,
    required this.active,
    required this.reliability,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final info = kTajwidRuleInfo[rule.key];
    final label = info?.name(t) ?? rule.key;
    final explanation = info?.explanation(t) ?? '';
    // Plus AUCUNE règle n'est bloquée (décision utilisateur 2026-07-20 : le
    // madd 6 était grisé alors que c'est une règle fondamentale, cf.
    // RuleReliability.selectable pour les 3 raisons mesurées). Le garde-fou
    // devient informatif : badge de fiabilité + pas de vert franc en jugement.
    final r = reliability;
    final caps = r?.capsToUnclear ?? true;

    return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: info?.color ?? AppColors.inkLight,
            shape: BoxShape.circle,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(label,
                  style: GoogleFonts.manrope(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            if (r != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: caps
                      ? AppColors.brass.withValues(alpha: 0.18)
                      : AppColors.green50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(r.badgeLabel(t),
                    style: GoogleFonts.manrope(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: caps ? AppColors.brass : AppColors.green700)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explanation,
                style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight)),
            if (caps)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Détection encore imprécise : cette règle peut signaler un '
                  'doute, mais ne validera jamais un mot en vert à elle seule.',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.inkLight),
                ),
              ),
          ],
        ),
        trailing: Switch(
          value: active,
          onChanged: onChanged,
          activeTrackColor: AppColors.green700,
        ),
    );
  }
}
