import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/reciter.dart';
import '../models/riwaya.dart';
import '../providers/app_settings_provider.dart';
import '../providers/mushaf_annotation_provider.dart';
import '../providers/player_provider.dart';
import '../screens/reciter_select_screen.dart';
import '../theme/app_theme.dart';
import 'choix_ecriture_sheet.dart';

/// Réglages de lecture (demande utilisateur 2026-07-06) : taille du texte
/// ("zoomer") et défilement automatique à vitesse réglable ("lire le Coran
/// et ça scroll selon sa vitesse"). Regroupés dans un même tiroir "Plus".
///
/// [showTranslation]/[onToggleTranslation] (2026-08-09, demande utilisateur :
/// « mettre traduction dans les trois points ») : la traduction avait sa
/// propre icône dans la barre du bas du Mushaf, aux côtés de Mémoriser --
/// sortie d'ici pour lui laisser la place. L'état vit toujours dans
/// `_MushafScreenState._showTranslation` (pas un réglage persistant comme les
/// autres de cette feuille) ; `onToggleTranslation` null masque simplement la
/// section, pour un futur appelant qui n'aurait pas ce concept.
/// [cleVersetActif]/[onToggleSignet] (2026-09-05) : le
/// (`onOuvrirSignets` retire le 2026-09-09 -- il n'y a plus de LISTE de
///  signets, cf. le bloc « MES SIGNETS A ETE RETIRE » dans le corps)
/// SIGNET descend de la barre du bas du Mushaf, dont le tajwid a pris la place
/// (demande utilisateur : « acces rapide depuis le menu avec une icone propre ;
/// par exemple le signet, range-le a un autre endroit »). Il y gagne ce que
/// l'icone ne pouvait pas donner : sa liste s'ouvrait par un appui LONG que
/// rien n'annoncait, elle devient une ligne ecrite. `null` sur les trois =
/// section masquee, pour un appelant qui n'a pas de verset courant.
void showReadingSettingsSheet(
  BuildContext context,
  WidgetRef ref, {
  bool showTranslation = false,
  VoidCallback? onToggleTranslation,
  String? cleVersetActif,
  VoidCallback? onToggleSignet,
}) {
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
    builder: (ctx) => _ReadingSettingsSheet(
      showTranslation: showTranslation,
      onToggleTranslation: onToggleTranslation,
      cleVersetActif: cleVersetActif,
      onToggleSignet: onToggleSignet,
    ),
  );
}

/// ⚠️ STATEFUL, ET C'EST NECESSAIRE (2026-09-02).
///
/// Defaut signale : « quand j'active la traduction elle s'active, mais
/// l'interrupteur ne se met pas a jour instantanement -- on pense que ce n'est
/// pas active et on s'acharne ».
///
/// Cause : `showTranslation` est capture PAR VALEUR a l'ouverture de la
/// feuille. Le basculement changeait bien l'etat du Mushaf (`onToggleTranslation`
/// ecrit dans `_MushafScreenState`), mais cette feuille-ci, ouverte par
/// `showModalBottomSheet`, ne se reconstruit pas quand l'ecran DERRIERE elle se
/// reconstruit : elle affichait donc eternellement la valeur d'origine. La
/// traduction s'activait vraiment ; seul le temoin mentait.
///
/// Correctif : un etat LOCAL, initialise sur la valeur recue et bascule au
/// meme instant que l'appel au parent. L'interrupteur suit le doigt, le
/// Mushaf suit l'interrupteur.
class _ReadingSettingsSheet extends ConsumerStatefulWidget {
  final bool showTranslation;
  final VoidCallback? onToggleTranslation;
  /// Cf. la doc de [showReadingSettingsSheet].
  final String? cleVersetActif;
  final VoidCallback? onToggleSignet;

  const _ReadingSettingsSheet({
    required this.showTranslation,
    required this.onToggleTranslation,
    this.cleVersetActif,
    this.onToggleSignet,
  });

  @override
  ConsumerState<_ReadingSettingsSheet> createState() =>
      _ReadingSettingsSheetState();
}

class _ReadingSettingsSheetState extends ConsumerState<_ReadingSettingsSheet> {
  /// Copie locale : cf. la doc de la classe. Le parent reste la source de
  /// verite pour l'AFFICHAGE du Mushaf, celle-ci ne sert qu'au temoin.
  late bool _traduction = widget.showTranslation;

  VoidCallback? get onToggleTranslation => widget.onToggleTranslation;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    // Pas de traduction en mode 100% arabe (REFONTE_IHM.md §7bis) -- même
    // règle que l'ex-icône de la barre du bas.
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final scale = ref.watch(textScaleProvider);
    final kindleMode = ref.watch(kindleModeProvider);
    final modeSombre = ref.watch(modeSombreProvider);
    final kindleAutoTurn = ref.watch(kindleAutoTurnProvider);
    final playerState = ref.watch(playerProvider);
    final playbackSpeed = playerState.speed;
    const speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    // ── RÉCITATEUR / ÉCRITURE / RIWAYA (2026-09-11) ─────────────────────────
    // Cf. les deux blocs plus bas pour le pourquoi du déménagement depuis
    // settings_screen.dart. Même calcul de sous-titre récitateur que là-bas
    // (REFONTE_IHM.md §7bis : aucun mot latin à l'écran en arabe).
    final riwaya = ref.watch(riwayaProvider);
    final reciter = playerState.reciter;
    final reciterStyleLabel = reciter.style == 'Mujawwad'
        ? t.settingsStyleMujawwad
        : t.settingsStyleMurattal;
    final reciterSubtitle = isArabic
        ? '${reciter.nameAr} • $reciterStyleLabel'
        : '${reciter.nameFr}  •  ${reciter.style}';

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
            // ── ÉCRITURE DU MUSHAF ET RIWAYA (2026-09-11) ────────────────
            //
            // Déménagées depuis settings_screen.dart (Réglages généraux),
            // où elles vivaient depuis leur création -- cf. le commentaire
            // toujours en place là-bas, conservé pour expliquer pourquoi
            // elles y étaient (« fais-moi toutes les écritures en
            // paramètre » pour l'écriture, 2026-09-03 ; « placée juste sous
            // le récitateur » pour la riwaya, 2026-08-12). Demande
            // utilisateur du jour : ce sont des réglages qu'on ajuste EN
            // LISANT le Mushaf, pas des réglages généraux de l'app -- « le
            // mieux les mettre [...] côté Mushaf, facile d'accès ». Même
            // famille que la taille du texte juste au-dessus : comment le
            // texte s'écrit et se lit.
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.font_download_outlined,
                  color: AppColors.green800, size: 20),
              title: Text(t.settingsMushafScriptTitle,
                  style:
                      GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink)),
              subtitle: Text(
                  libelleEcriture(ref.watch(policeMushafPageProvider)),
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: AppColors.inkLight)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.inkLight),
              onTap: () =>
                  ouvrirChoixEcriture(context, ref, sombre: modeSombre),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.menu_book_rounded,
                  color: AppColors.green800, size: 20),
              title: Text(t.settingsRiwayaTitle,
                  style:
                      GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink)),
              subtitle: Text(
                  riwaya == Riwaya.warsh
                      ? t.settingsRiwayaWarsh
                      : t.settingsRiwayaHafs,
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: AppColors.inkLight)),
              value: riwaya == Riwaya.warsh,
              activeColor: AppColors.green700,
              onChanged: (v) async {
                await ref
                    .read(riwayaProvider.notifier)
                    .set(v ? Riwaya.warsh : Riwaya.hafs);
                // Le récitateur doit suivre le texte, sinon on entend une
                // riwāya et on en lit une autre (même geste que l'ancien
                // emplacement, settings_screen.dart).
                ref.read(playerProvider.notifier).accorderALaRiwaya();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(t.settingsRiwayaChangeNotice),
                    duration: const Duration(seconds: 4),
                  ));
                }
              },
            ),
            // ── SIGNET (2026-09-05) ───────────────────────────────────
            //
            // Deux lignes la ou il y avait un bouton a deux gestes : poser le
            // signet, et ouvrir la liste. Le second geste etait un appui long
            // invisible -- c'est le defaut meme que l'utilisateur venait de
            // reprocher a l'acces du mode tajwid.
            //
            // L'etat se LIT ici (`marquePagesProvider`), il n'est pas recu :
            // la ligne change donc de libelle et d'icone au moment du tap,
            // feuille ouverte.
            // ── UNE ENTREE SORT, UNE ENTRE (2026-09-09) ──────────────────
            //
            // Demande utilisateur, en trois temps : « a la place de l'acces
            // mindmap remplace-le par l'acces Mushaf papier ; a la place de
            // l'icone Mushaf papier rajoute la possibilite de marquer signet
            // la ou on est arrive ; enleve Signet des parametres des trois
            // points ».
            //
            // CE QUI EST PARTI D'ICI : l'action « Signet » (poser/retirer sur
            // le verset actif). Elle est devenue le bouton rond de l'ecran de
            // lecture -- c'est un geste qu'on fait EN LISANT, a l'endroit
            // precis ou l'on s'arrete, il n'avait rien a faire au fond d'un
            // panneau. Son icone y suit l'etat du verset.
            //
            // CE QUI EST GARDE : « Mes signets », la LISTE. C'est une
            // consultation et non un geste de lecture, et c'est le seul moyen
            // de revenir a un signet pose ailleurs.
            //
            // CE QUI ARRIVE : la carte mentale, qui occupait l'en-tete. Elle
            // s'ouvre UNE FOIS pour situer une sourate ; le signet se pose au
            // fil de la lecture. L'acces en un tap va a ce qu'on repete. Le
            // panneau ne s'allonge donc d'aucune ligne : c'est un echange.
            // ── CE BLOC A ETE VIDE, EN DEUX TEMPS (2026-09-09) ───────────
            //
            // Il portait « Signet » (poser) puis « Mes signets » (la liste),
            // et j'y avais fait descendre la carte mentale. Les trois en sont
            // sortis le meme jour, chacun pour sa raison :
            //
            //   - « Signet » : poser un signet est un geste qu'on fait EN
            //     LISANT, il est devenu le bouton rond de l'ecran ;
            //   - « Mes signets » : il n'y a plus de liste, un seul signet
            //     existe (cf. `marquePagesProvider`, `Set<String>` -> `String?`) ;
            //   - la carte mentale : « je ne suis pas d'accord pour cacher la
            //     carte mentale » -- elle est remontee dans la barre du bas,
            //     ou elle se voit sans ouvrir quoi que ce soit.
            //
            // Ce qui reste vrai et vaut d'etre garde : un panneau qu'il faut
            // ouvrir n'est pas un acces, c'est un rangement. Ce qui se repete
            // en lisant appartient a l'ecran, pas au tiroir.
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
            if (!isArabic && onToggleTranslation != null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t.mushafTranslation,
                  style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink),
                ),
                value: _traduction,
                activeColor: AppColors.green700,
                onChanged: (_) {
                  // Les deux d'un coup : le temoin local pour que
                  // l'interrupteur bouge tout de suite, et le parent pour que
                  // le Mushaf suive.
                  setState(() => _traduction = !_traduction);
                  onToggleTranslation!();
                },
              ),
            ],
            // ── SURLIGNAGE LIBRE ("crayon", 2026-08-28, demande utilisateur)
            //
            // « on permet de tracer sur le mushaf en train d'apprendre, il
            // surligne quelque chose avec différentes couleurs [...] ça doit
            // rester avec mémorisation sauf si il lance initialisation qui
            // efface tout ». Le mode se pilote par un provider global
            // (`mushafAnnotationModeProvider`) -- pas de callback à faire
            // remonter jusqu'ici, contrairement à `onToggleTranslation` (état
            // local de l'écran) : une fois activé, la barre d'outils du
            // crayon flotte au-dessus de la barre du bas du Mushaf tant que
            // ce switch reste actif.
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.edit_rounded,
                  color: AppColors.green800, size: 20),
              title: Text(
                t.mushafAnnotateButton,
                style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink),
              ),
              value: ref.watch(mushafAnnotationModeProvider),
              activeColor: AppColors.green700,
              onChanged: (v) =>
                  ref.read(mushafAnnotationModeProvider.notifier).state = v,
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
            // ── RÉCITATEUR (2026-09-11) ──────────────────────────────────
            //
            // Déménagé depuis settings_screen.dart, même mouvement que
            // l'écriture et la riwaya ci-dessus (cf. leur commentaire).
            // Choix TRANSVERSE au départ (écoute, souffleur, corrections
            // audio -- cf. la note d'origine, toujours en place là-bas),
            // mais c'est ICI, en train d'écouter le Mushaf, qu'on a besoin
            // d'en changer : en tête du bloc ÉCOUTER, avant la vitesse.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.record_voice_over,
                  color: AppColors.green800, size: 20),
              title: Text(t.settingsReciterTitle,
                  style:
                      GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink)),
              subtitle: Text(reciterSubtitle,
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: AppColors.inkLight)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.inkLight),
              onTap: () async {
                final picked = await Navigator.push<Reciter>(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ReciterSelectScreen(currentId: reciter.id)),
                );
                if (picked != null) {
                  ref.read(playerProvider.notifier).setReciter(picked);
                }
              },
            ),
            const SizedBox(height: 14),
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
            // Répétition PAR VERSET uniquement (2026-08-09, demande
            // utilisateur : « corrige la répétition en boucle, supprime par
            // mot, garde que par verset »). L'unité MOT (moteur séparé par
            // plages temporelles, `PlayerNotifier._boucleMots`) a été
            // retirée -- source de la boucle mal maîtrisée signalée.
            Text(t.readingSettingsGroupSize(playerState.groupeVersets),
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
            const SizedBox(height: 10),
            // ── CURSEUR 3 COULEURS (2026-08-09, demande utilisateur) ────────
            // Remplace les deux interrupteurs texte (Mode Kindle / Fond noir)
            // -- « un curseur avec trois positions vert/beige/noir, sans
            // texte, les codes couleur ». Trois pastilles, une par thème de
            // lecture : vert = normal (couleur de marque), beige/marron =
            // sépia façon liseuse, noir = lecture nocturne. Mutuellement
            // exclusifs (contrairement aux deux interrupteurs d'avant, qui
            // pouvaient être cochés ensemble).
            Row(
              children: [
                // ── LA PASTILLE MONTRE LE FOND, PAS LA MARQUE (2026-09-02)
                // Elle affichait `green700`, la couleur d'identite de l'app.
                // Or le fond de lecture du mode normal est `cream` (#fbf7ee),
                // un blanc casse : la pastille annoncait donc une couleur que
                // l'ecran n'a jamais. Signale par l'utilisateur : « il y a
                // vert, aucun rapport, il est pareil que le marron ; ca
                // concerne le fond derriere le texte, donc je veux un blanc,
                // un marron comme maintenant, et le noir ».
                //
                // Les trois pastilles reprennent maintenant EXACTEMENT les
                // trois `backgroundColor` de `MushafScreen` (cf. sa ligne
                // `backgroundColor:`) : cream / kindleBg / sombreBg. Un
                // selecteur de theme doit montrer le theme.
                _ThemeSwatch(
                  // Le papier reel, cf. MushafScreen.backgroundColor.
                  color: AppColors.mushafPapier,
                  selected: !kindleMode && !modeSombre,
                  onTap: () {
                    ref.read(kindleModeProvider.notifier).set(false);
                    ref.read(modeSombreProvider.notifier).set(false);
                  },
                ),
                const SizedBox(width: 14),
                _ThemeSwatch(
                  // `kindleBg` (le fond reel) et non `kindleAccent` (l'encre
                  // marron) : meme raison que ci-dessus. L'utilisateur voulait
                  // « un marron comme maintenant » -- kindleBg EST ce marron
                  // clair qu'il voit a l'ecran, kindleAccent est plus fonce
                  // que tout ce que la page affiche.
                  color: AppColors.kindleBg,
                  selected: kindleMode && !modeSombre,
                  onTap: () {
                    ref.read(kindleModeProvider.notifier).set(true);
                    ref.read(modeSombreProvider.notifier).set(false);
                  },
                ),
                const SizedBox(width: 14),
                _ThemeSwatch(
                  color: AppColors.sombreBg,
                  selected: modeSombre,
                  onTap: () {
                    ref.read(modeSombreProvider.notifier).set(true);
                    ref.read(kindleModeProvider.notifier).set(false);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Tournage automatique -- SORTI du `if (kindleMode)` (2026-08-09,
            // demande utilisateur : « pas un bug, juste qu'il soit proposé
            // sur toutes les configurations, pas que pour Kindle »). Le
            // mécanisme (`MushafScreen._kindleJumpPage`) fait défiler le
            // ScrollController d'un écran, peu importe le thème actif -- rien
            // dans son fonctionnement ne dépendait réellement du mode Kindle,
            // seule la visibilité du réglage l'était.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                t.readingSettingsKindleAutoTurn,
                style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink),
              ),
              value: kindleAutoTurn,
              activeColor: AppColors.green700,
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

/// Pastille de couleur du sélecteur de thème de lecture -- volontairement
/// SANS TEXTE (demande utilisateur 2026-08-09 : « sans texte, tu mets les
/// trois codes couleur ») : la couleur EST le libellé.
class _ThemeSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeSwatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.green900 : AppColors.cream300,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
        child: selected
            ? Icon(Icons.check_rounded,
                size: 18,
                color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
            : null,
      ),
    );
  }
}
