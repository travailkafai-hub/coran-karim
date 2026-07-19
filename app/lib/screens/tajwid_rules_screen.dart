// Écran de sélection des règles de tajwid + presets -- REFONTE_IHM.md §1.4.
// Trois presets (tajwid strict / adulte tolérant tajwid / enfant tolérant
// lettres) + réglages fins. Les règles non fiables (cf.
// assets/data/rule_reliability.json) sont grisées et non activables --
// jamais corriger un élève avec un détecteur peu fiable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/judgement_options.dart';
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
    final info = kTajwidRuleInfo[rule.key];
    final selectable = reliability?.selectable ?? false;
    final label = info?.name ?? rule.key;
    final explanation = info?.explanation ?? '';

    return Opacity(
      opacity: selectable ? 1.0 : 0.45,
      child: ListTile(
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
        title: Text(label,
            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explanation,
                style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight)),
            if (!selectable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Bientôt disponible — détection pas encore assez fiable',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.inkLight),
                ),
              ),
          ],
        ),
        trailing: Switch(
          value: selectable && active,
          onChanged: selectable ? onChanged : null,
          activeTrackColor: AppColors.green700,
        ),
      ),
    );
  }
}
