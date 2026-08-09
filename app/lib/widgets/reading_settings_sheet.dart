import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_settings_provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';

/// Réglages de lecture (demande utilisateur 2026-07-06) : taille du texte
/// ("zoomer") et défilement automatique à vitesse réglable ("lire le Coran
/// et ça scroll selon sa vitesse"). Regroupés dans un même tiroir "Plus".
void showReadingSettingsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.cream,
    // isScrollControlled + hauteur bornée : depuis l'ajout des sections
    // "vitesse de lecture (audio)" et "répétition / boucles" (2026-07-19), le
    // contenu dépasse la hauteur par défaut d'un bottom sheet (constaté :
    // "BOTTOM OVERFLOWED BY 284 PIXELS"). Le contenu défile désormais dans la
    // limite de 85% de l'écran au lieu de déborder.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _ReadingSettingsSheet(),
  );
}

class _ReadingSettingsSheet extends ConsumerWidget {
  const _ReadingSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final scale = ref.watch(textScaleProvider);
    final kindleMode = ref.watch(kindleModeProvider);
    final modeSombre = ref.watch(modeSombreProvider);
    final kindleAutoTurn = ref.watch(kindleAutoTurnProvider);
    final playerState = ref.watch(playerProvider);
    final playbackSpeed = playerState.speed;
    const speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

    return SafeArea(
      child: ConstrainedBox(
        // Plafonne à 85% de l'écran ; au-delà, le contenu défile (cf.
        // SingleChildScrollView) plutôt que de déborder.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── GROUPE PAR INTENTION, PAS PAR TECHNIQUE (2026-08-05) ──
                //
                // Demande utilisateur : la feuille melangeait taille de
                // police, vitesse audio, boucles de repetition, mode Kindle et
                // tournage automatique dans un seul defilement. Rien n'y
                // repondait a la question qu'on se pose en l'ouvrant -- « je
                // veux LIRE autrement » ou « je veux ECOUTER autrement » --
                // et il fallait parcourir tout le reste pour trouver.
                //
                // Deux intentions, deux blocs, dans l'ordre de l'usage : on lit
                // d'abord, on ecoute ensuite. Le mode Kindle rejoint LIRE (il
                // change la page et le theme, pas le son) ; la vitesse et les
                // boucles rejoignent ECOUTER.
                _EnTeteIntention(t.readingSettingsGroupRead),
                const SizedBox(height: 10),
                Text(
                  t.readingSettingsDisplaySection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.text_decrease_rounded),
                  color: AppColors.green800,
                  onPressed: () => ref
                      .read(textScaleProvider.notifier)
                      .set(scale - 0.1),
                ),
                Expanded(
                  child: Slider(
                    value: scale,
                    min: kTextScaleMin,
                    max: kTextScaleMax,
                    divisions: 9,
                    activeColor: AppColors.green700,
                    label: '${(scale * 100).round()}%',
                    onChanged: (v) =>
                        ref.read(textScaleProvider.notifier).set(v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.text_increase_rounded),
                  color: AppColors.green800,
                  onPressed: () => ref
                      .read(textScaleProvider.notifier)
                      .set(scale + 0.1),
                ),
              ],
            ),
            Center(
              child: Text(
                'بِسْمِ ٱللَّهِ',
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                  fontSize: 26 * scale,
                  color: AppColors.ink,
                ),
              ),
            ),
            // Défilement automatique (off/slow/normal/fast) RETIRÉ
            // 2026-08-01 (demande utilisateur : "plus raison d'être" une fois
            // le mode Kindle en place, qui couvre ce besoin -- cf. §Kindle
            // plus bas, tournage de page automatique).
            //
            // Vitesse de lecture (audio) -- curseur plutôt que des puces
            // fixes (demande utilisateur 2026-08-01 : "un curseur avec les
            // choix, ça optimise l'espace"). DIFFÉRENTE de l'ancien
            // "défilement automatique" (qui faisait scroller le TEXTE) :
            // celle-ci change la vitesse de l'AUDIO du réciteur.
            const SizedBox(height: 22),
            _EnTeteIntention(t.readingSettingsGroupListen),
            const SizedBox(height: 10),
            Text(
              t.readingSettingsPlaybackSpeedSection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${playbackSpeed.toStringAsFixed(2)}×',
              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.inkLight),
            ),
            Slider(
              value: playbackSpeed,
              min: speedOptions.first,
              max: speedOptions.last,
              divisions: 6, // pas de 0.25 entre 0.5 et 2.0
              activeColor: AppColors.green700,
              onChanged: (v) => ref.read(playerProvider.notifier).setSpeed(v),
            ),
            // Répétition / boucles -- curseur pour le nombre de répétitions
            // (même raison que ci-dessus), "Illimité"/"Sourate entière"
            // restent des puces car ce ne sont pas des points sur une échelle
            // numérique continue.
            const SizedBox(height: 12),
            // ── L'ANCIEN REGLAGE DE REPETITION EST REMPLACE (2026-08-06) ───
            //
            // Il y avait ici un curseur « repeter le verset N fois » plus deux
            // puces (« illimite », « sourate entiere »). Les trois curseurs
            // ci-dessous les couvrent tous : un verset repete N fois, c'est
            // groupe=1 / chaque groupe=N ; la sourate en boucle, c'est
            // groupe=1 / chaque groupe=1 / la sourate=0 (illimite).
            //
            // Les avoir gardes cote a cote donnait QUATRE curseurs et des
            // puces pour le meme sujet -- retour utilisateur : « c'est mal
            // fait ». `RepeatMode` et `repeatCount` restent dans le modele et
            // le moteur : rien n'est casse pour les autres ecrans qui les
            // lisent, seul ce reglage disparait de CETTE feuille.
            // ── BOUCLES IMBRIQUEES (demande utilisateur 2026-08-06) ────────
            //
            // « on doit avoir deux curseurs : un pour ce qu'on va répéter, et
            // l'autre pour la boucle globale. Exemple : répéter la sourate 3
            // fois, mais pour chaque sourate répéter 3 versets 3 fois. »
            //
            // Il en faut TROIS, pas deux : la taille du groupe, le nombre de
            // fois qu'on le redit, et le nombre de fois qu'on reprend tout.
            // Sans le premier, « 3 versets » n'est pas exprimable.
            //
            // Les reglages historiques (verset seul / sourate en boucle)
            // restent en dessous : ils ne sont pas remplaces, et le moteur ne
            // bascule sur les boucles imbriquees que si l'un de ces trois
            // curseurs quitte sa valeur neutre (cf. `_onCompleted`).
            const SizedBox(height: 14),
            Text(
              t.readingSettingsLoopSection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.readingSettingsLoopDescription,
              style: GoogleFonts.manrope(
                  fontSize: 12, height: 1.4, color: AppColors.inkLight),
            ),
            const SizedBox(height: 8),
            // L'unite repetee : le verset (defaut) ou le MOT (demande
            // utilisateur 2026-08-06). Au mot, la lecture change de moteur --
            // plages temporelles decoupees dans l'audio du recitateur grace a
            // ses reperes mot-a-mot, cf. `PlayerNotifier._boucleMots`. Le
            // texte d'aide dit franchement la dependance : tous les
            // recitateurs ne publient pas ces reperes.
            Row(
              children: [
                Text(t.readingSettingsUnitLabel,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.inkLight)),
                const Spacer(),
                SegmentedButton<bool>(
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                        GoogleFonts.manrope(fontSize: 12)),
                  ),
                  segments: [
                    ButtonSegment(
                        value: false, label: Text(t.readingSettingsUnitVerse)),
                    ButtonSegment(
                        value: true, label: Text(t.readingSettingsUnitWord)),
                  ],
                  selected: {playerState.uniteMot},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => ref
                      .read(playerProvider.notifier)
                      .setUniteMot(s.first),
                ),
              ],
            ),
            if (playerState.uniteMot) ...[
              const SizedBox(height: 4),
              Text(t.readingSettingsWordUnitHint,
                  style: GoogleFonts.manrope(
                      fontSize: 11, height: 1.35, color: AppColors.inkLight)),
            ],
            const SizedBox(height: 6),
            Text(
                playerState.uniteMot
                    ? t.readingSettingsGroupSizeWords(
                        playerState.groupeVersets)
                    : t.readingSettingsGroupSize(playerState.groupeVersets),
                style: GoogleFonts.manrope(
                    fontSize: 12, color: AppColors.inkLight)),
            Slider(
              value: playerState.groupeVersets.clamp(1, 10).toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              activeColor: AppColors.green700,
              onChanged: (v) => ref
                  .read(playerProvider.notifier)
                  .setBoucle(groupe: v.round()),
            ),
            // 0 = illimite, a l'extremite gauche : c'est la seule valeur qui
            // n'est pas un nombre de tours, elle ne se melange pas au reste.
            Text(
              t.readingSettingsGroupRepeats(playerState.repetitionsGroupe) +
                  (playerState.repetitionsGroupe == 0
                      ? ' (${t.readingSettingsUnlimited})'
                      : ''),
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight),
            ),
            Slider(
              value: playerState.repetitionsGroupe.clamp(0, 20).toDouble(),
              min: 0,
              max: 20,
              divisions: 20,
              activeColor: AppColors.green700,
              onChanged: (v) => ref
                  .read(playerProvider.notifier)
                  .setBoucle(repGroupe: v.round()),
            ),
            Text(
              t.readingSettingsGlobalRepeats(playerState.repetitionsGlobales) +
                  (playerState.repetitionsGlobales == 0
                      ? ' (${t.readingSettingsUnlimited})'
                      : ''),
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.inkLight),
            ),
            Slider(
              value: playerState.repetitionsGlobales.clamp(0, 10).toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              activeColor: AppColors.green700,
              onChanged: (v) => ref
                  .read(playerProvider.notifier)
                  .setBoucle(repGlobal: v.round()),
            ),
            // Mode Kindle (demande utilisateur 2026-08-01) : thème repos-yeux
            // + navigation par pages, regroupé ici avec les autres réglages
            // de lecture -- même logique que le défilement et la répétition
            // ci-dessus (§ commentaires 2026-07-19/20).
            const SizedBox(height: 20),
            Text(
              t.readingSettingsKindleSection,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.readingSettingsKindleDescription,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkLight,
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                t.readingSettingsKindleToggle,
                style: GoogleFonts.manrope(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              value: kindleMode,
              activeColor: AppColors.kindleAccent,
              onChanged: (v) => ref.read(kindleModeProvider.notifier).set(v),
            ),
            // ── LECTURE SUR FOND NOIR (demande utilisateur 2026-08-07) ─────
            // Reglage SEPARE du mode Kindle, pas une de ses options : le
            // sepia sert le confort diurne, le noir la lecture nocturne. On
            // peut vouloir l'un sans l'autre. Quand les deux sont coches, le
            // FOND est noir (il ne peut pas etre les deux) et la pagination
            // du mode Kindle reste active.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Fond noir',
                style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
              subtitle: Text(
                'Ecriture claire sur fond noir, pour la lecture de nuit',
                style: GoogleFonts.manrope(
                    fontSize: 11.5, color: AppColors.inkLight),
              ),
              value: modeSombre,
              activeColor: AppColors.sombreAccent,
              onChanged: (v) => ref.read(modeSombreProvider.notifier).set(v),
            ),
            if (kindleMode) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t.readingSettingsKindleAutoTurn,
                  style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink),
                ),
                value: kindleAutoTurn,
                activeColor: AppColors.kindleAccent,
                onChanged: (v) =>
                    ref.read(kindleAutoTurnProvider.notifier).state = v,
              ),
              // ── LE CURSEUR DE VITESSE A ÉTÉ RETIRÉ (2026-08-05) ───────────
              //
              // Demande utilisateur : « il y a un temps, je ne veux même pas
              // qu'on affiche ce temps-là ». Le réglage était une question à
              // laquelle personne ne sait répondre : combien de secondes met-on
              // à lire une page ? On ne le sait qu'après, et cela change avec
              // le passage, la fatigue et le jour.
              //
              // La cadence s'APPREND désormais du geste qui la porte déjà :
              // tourner la page à la main avant l'échéance dit « trop lent »,
              // revenir en arrière dit « trop rapide »
              // (cf. KindlePageSecondsNotifier.apprendre, branché dans
              // MushafScreen._tapManuel). Le `kindlePageSecondsProvider`
              // existe donc toujours et reste persisté -- il n'est simplement
              // plus exposé, ni affiché.
              //
              // ⚠️ Ne pas remettre ce curseur « pour laisser le choix » sans
              // remettre en cause l'apprentissage : deux sources qui écrivent
              // la même valeur, l'une par geste l'autre par réglage, se
              // contrediraient en silence -- l'utilisateur règlerait 12 s et
              // verrait la valeur bouger toute seule.
            ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Titre de GROUPE — plus fort que les sous-titres de section existants, pour
/// qu'on voie d'un coup d'oeil ou commence « lire » et ou commence « ecouter ».
/// Sans cette hierarchie, tous les libelles avaient le meme poids et la feuille
/// se lisait comme une liste plate.
class _EnTeteIntention extends StatelessWidget {
  final String titre;
  const _EnTeteIntention(this.titre);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 16, color: AppColors.green700),
        const SizedBox(width: 8),
        Text(
          titre,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: AppColors.green900,
          ),
        ),
      ],
    );
  }
}
