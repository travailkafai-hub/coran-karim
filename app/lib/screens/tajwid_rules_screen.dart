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
            // « Harakat exigées » (rigueur de correction) retiré le
            // 2026-08-10 (demande utilisateur : « la rigueur de correction
            // n'est plus intéressante »). `strictHarakat` reste dans le
            // modèle/le moteur de jugement (presets tajwid/adulte/enfant le
            // pilotent toujours) -- seul ce réglage manuel disparaît.
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
            // « (bêta) » ajouté et bascules retirées le 2026-08-10 (demande
            // utilisateur : « les toggles sur toutes les règles avec la
            // fiabilité, ça sert à rien, ils seront pour information »). Les
            // presets (Tajwid/Adulte/Enfant) pilotent toujours `activeRules`
            // -- cette liste devient une référence, plus un réglage manuel
            // règle par règle.
            Text('RÈGLES DE TAJWID (BÊTA)',
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.inkLight)),
            const SizedBox(height: 4),
            Text(
              'Règles vérifiées selon le mode choisi ci-dessus, à titre indicatif.',
              style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.inkLight),
            ),
            const SizedBox(height: 8),
            for (final rule in TajwidRule.values)
              _RuleTile(
                rule: rule,
                active: options.activeRules.contains(rule),
                reliability: reliability[rule],
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
    // ── BÊTA sur le preset Tajwid (2026-08-10) ──────────────────────────
    //
    // Demande utilisateur, après mesure sur une session réelle (sourate 90,
    // tableau attendu/détecté mot par mot) : la tête de détection des règles
    // tajwid (modèle "trois-têtes") sort des règles très bruitées -- sur 20
    // mots consécutifs, AUCUN ne correspond proprement à l'attendu, et des
    // mots sans aucune règle attendue se voient quand même attribuer 4 à 6
    // règles détectées. Conclusion utilisateur : « ça augmente la raison de
    // mettre bêta dans ce mode ».
    //
    // Le mode reste UTILISABLE (il ne verrouille jamais un rouge sur un
    // écart de règle, seulement un orange -- cf. `_capByRuleReliability`
    // dans recitation_provider.dart) mais l'étiquette prévient qu'il ne faut
    // pas encore s'y fier comme verdict fiable.
    Widget chip(JudgementPreset preset, String label, IconData icon,
        {bool beta = false}) {
      final selected = current == preset;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => notifier.applyPreset(preset),
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
              decoration: BoxDecoration(
                color: selected ? AppColors.green800 : AppColors.cream200,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? AppColors.brass : AppColors.cream300,
                    width: selected ? 1.6 : 1),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
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
                  if (beta)
                    Positioned(
                      top: -8,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brass,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('BÊTA',
                            style: GoogleFonts.manrope(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: AppColors.green900)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(JudgementPreset.tajwid, 'Tajwid', Icons.auto_awesome, beta: true),
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

  const _RuleTile({
    required this.rule,
    required this.active,
    required this.reliability,
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
        // Grisée si hors du preset courant -- pure indication, plus un
        // réglage : cf. bascule retirée le 2026-08-10.
        enabled: active,
        leading: Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: info?.color ?? AppColors.inkLight,
            shape: BoxShape.circle,
          ),
        ),
        // ── BADGE DE POURCENTAGE RETIRÉ (2026-08-10) ──────────────────────
        //
        // Demande utilisateur, après avoir vu ces pourcentages sans pouvoir
        // se fier à leur origine : « enlève aussi la fiabilité qui ne veut
        // rien dire, je ne comprends comment on a ces pourcentages ». La
        // documentation du calcul (cf. `RuleReliability` ci-dessus, décision
        // du 2026-07-20) confirme le doute : la mesure évalue l'INVERSE de
        // ce qui compte pour juger (« le modèle émet-il le symbole quand la
        // règle est bien faite », pas « la détecte-t-il quand elle est
        // ratée »), sur des échantillons parfois minuscules (n=3, n=32) --
        // un pourcentage qui ne dit pas ce qu'il prétend dire. À revérifier
        // sur la machine Ubuntu (accès à `rule_reliability.json` et aux
        // scripts d'éval qui l'ont produit).
        //
        // `capsToUnclear` continue de s'appliquer dans le JUGEMENT
        // (`recitation_provider.dart`, jamais de vert franc sur une règle
        // non fiable) -- seul l'AFFICHAGE du pourcentage disparaît ici.
        title: Text(label,
            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
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
    );
  }
}
