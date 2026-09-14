// Choix de l'ÉCRITURE du texte coranique — catalogue et feuille de sélection.
//
// ── POURQUOI CE FICHIER EXISTE (2026-09-03) ──────────────────────────────────
//
// Demande utilisateur : « fais-moi toutes les écritures EN PARAMÈTRE, comme ça
// je change et je regarde, sans toucher à celui qu'on affiche en premier ».
//
// Première version : la feuille vivait dans `mushaf_maquette_screen.dart` et ne
// s'ouvrait que par un appui long sur la page. Retour immédiat : « je ne vois
// pas comment changer entre les écritures ». Il avait raison — un geste sans
// indice visible n'est pas un réglage, et il avait demandé « en paramètre »,
// c'est-à-dire dans les Réglages. Le code est donc sorti de l'écran pour être
// appelable des deux endroits : l'entrée des Réglages (découvrable) et l'appui
// long sur la page (raccourci pour comparer sans quitter la lecture).
//
// ── CE QUE LE CHIFFRE `signes` VEUT DIRE ─────────────────────────────────────
//
// Nombre, sur 19, des caractères proprement coraniques que la police sait
// dessiner : marques de waqf (ﺝ, ﺹﻝﻯ, ﻕﻝﻯ…), sajda, rub el hizb, médaillon de
// fin de verset, petit zéro des lettres muettes, alif suscrit. Relevé dans le
// binaire de chaque police avec fontTools. Un caractère absent ne s'affiche pas
// — le texte perd le signe en silence, ce qui est précisément ce qu'on veut
// pouvoir anticiper.
//
// Toutes ces polices ont la table `mkmk` (mark-to-mark), celle qui pose un
// signe AU-DESSUS d'un autre signe : c'est elle qui gouverne shadda + fatha
// empilées, le défaut d'origine (« le style d'écriture ne fait pas bien
// apparaître les lettres avec harakat et shadda »). Elle est présente partout,
// donc ce n'est pas une table manquante qui explique le rendu : c'est le dessin
// et les métriques. Seul l'œil peut trancher — d'où ce sélecteur.
//
// ⚠️ AUCUNE ÉCRITURE N'EST ÉCARTÉE. La première liste en retirait cinq sur ma
// seule mesure ; consigne utilisateur : « je ne te demande pas de choisir à ma
// place ». La mesure reste affichée comme information, jamais comme filtre.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_settings_provider.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Une écriture proposée : le nom Google Fonts, son libellé, ce qu'elle est,
/// et sa couverture des signes coraniques.
typedef EcritureMushaf = ({
  String famille,
  String libelle,
  String note,
  int signes,

  /// La police est-elle EMBARQUEE dans l'app (`fonts:` du pubspec) plutot que
  /// tiree de Google Fonts ? Les deux ne se designent pas de la meme facon :
  /// une police Google passe par `GoogleFonts.getFont(nom)`, une police
  /// embarquee par `TextStyle(fontFamily: nom)`. Se tromper ne leve aucune
  /// erreur -- le texte se rabat silencieusement sur la police systeme.
  bool locale,
});

/// Construit le style d'une ecriture, qu'elle soit embarquee ou distante.
///
/// Point de passage UNIQUE : les trois endroits qui batissent un style de
/// texte de page (mesure, spans colores, rendu) l'appellent, pour qu'aucun
/// n'oublie le cas des polices embarquees.
TextStyle styleEcriture(
  EcritureMushaf e, {
  double? taille,
  double? interligne,
  Color? couleur,
  FontWeight? graisse,
}) => e.locale
    ? TextStyle(
        fontFamily: e.famille,
        fontSize: taille,
        height: interligne,
        fontWeight: graisse,
        color: couleur,
      )
    : GoogleFonts.getFont(
        e.famille,
        fontSize: taille,
        height: interligne,
        fontWeight: graisse,
        color: couleur,
      );

/// L'entree du catalogue portant cette famille, ou Amiri a defaut.
EcritureMushaf ecriturePour(String famille) {
  for (final e in kEcrituresMushaf) {
    if (e.famille == famille) return e;
  }
  return kEcrituresMushaf.first;
}

/// Les écritures proposées, GROUPÉES PAR TRADITION.
///
/// Vingt-quatre entrées depuis le 2026-09-03 : « rajoute-les, ça reste un
/// choix de l'utilisateur, je veux que l'app devienne mondiale ». L'ordre suit
/// les traditions du mushaf — naskh arabe, Maghreb et Afrique de l'Ouest,
/// sous-continent indien, Iran, koufique et calligraphies, contemporaines —
/// et non plus la seule couverture des signes.
///
/// ⚠️ UNE POLICE NE FAIT PAS UN MUSHAF INDO-PAK. Le texte du sous-continent
/// s'ÉCRIT autrement (alif et hamza, lettres muettes, notation des madd), pour
/// se passer des règles de grammaire arabe ; Tanzil en publie un flux `Imlaei`
/// distinct de l'Uthmani. Les nastaliq ci-dessous changent le DESSIN du texte
/// arabe actuel, pas sa graphie — servir vraiment le Pakistan demanderait un
/// troisième asset texte, sur le modèle de la pagination Warsh.
///
/// ⚠️ `Alkalami` n'a pas la table `mkmk` : shadda et voyelle s'y poseront au
/// même endroit. C'est dit dans son libellé plutôt qu'en la retirant.
///
/// `Amiri` ouvre la liste : c'est le défaut et le rendu d'origine, que la
/// consigne demandait de ne pas changer tant qu'aucun autre choix n'est fait.
/// C'est aussi la seule EMBARQUÉE dans l'APK (cf. `pubspec.yaml`, section
/// `google_fonts/`) — les autres se téléchargent à la demande au premier usage,
/// ce qui suppose une connexion la première fois.
const kEcrituresMushaf = <EcritureMushaf>[
  (
    famille: 'Amiri',
    libelle: 'Amiri',
    note: "Naskh — par défaut, incluse hors ligne",
    signes: 19,
    // `false` MALGRE le fait qu'elle soit embarquee : ses fichiers sont dans
    // `google_fonts/`, ou le package les reconnait par leur nom officiel et
    // les prefere au reseau. Elle passe donc par `GoogleFonts.getFont`.
    // `locale: true` est reserve aux polices declarees sous `fonts:` du
    // pubspec, que seul `TextStyle(fontFamily:)` sait designer -- aujourd'hui
    // la seule est Bouazzi Maghribi. Se tromper ne leve aucune erreur : le
    // texte se rabat en silence sur la police systeme.
    locale: false,
  ),
  (
    famille: 'Noto Naskh Arabic',
    libelle: 'Noto Naskh',
    note: "Naskh — tres lisible a l'ecran",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'Scheherazade New',
    libelle: 'Scheherazade New',
    note: "Naskh SIL — diacritiques amples",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'Lateef',
    libelle: 'Lateef',
    note: "Naskh etroit — plus de mots par ligne",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'Amiri Quran',
    libelle: 'Amiri Quran',
    note: "Naskh coranique — rend les harakat en ROUGE",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'Noto Sans Arabic',
    libelle: 'Noto Sans Arabic',
    note: "Naskh sans empattement — moderne",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'IBM Plex Sans Arabic',
    libelle: 'IBM Plex Arabic',
    note: "Naskh sans empattement — tres regulier",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'Markazi Text',
    libelle: 'Markazi Text',
    note: "Naskh moderne",
    signes: 4,
    locale: false,
  ),
  (
    famille: 'Bouazzi Maghribi',
    libelle: 'Maghribi',
    note: "Maghribi — ecriture du Maroc",
    signes: 4,
    locale: true,
  ),
  (
    famille: 'Harmattan',
    libelle: 'Harmattan',
    note: "SIL Afrique de l'Ouest — proche du maghribi",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'Alkalami',
    libelle: 'Alkalami',
    note: "SIL Nigeria (barnawi) — sans empilement des signes",
    signes: 7,
    locale: false,
  ),
  (
    famille: 'Noto Nastaliq Urdu',
    libelle: 'Noto Nastaliq',
    note: "Nastaliq — Pakistan, Inde, Bangladesh",
    signes: 9,
    locale: false,
  ),
  (
    famille: 'Gulzar',
    libelle: 'Gulzar',
    note: "Nastaliq — variante plus deliee",
    signes: 6,
    locale: false,
  ),
  (
    famille: 'Mirza',
    libelle: 'Mirza',
    note: "Naskh persan",
    signes: 17,
    locale: false,
  ),
  (
    famille: 'Vazirmatn',
    libelle: 'Vazirmatn',
    note: "Persan contemporain",
    signes: 8,
    locale: false,
  ),
  (
    famille: 'Noto Kufi Arabic',
    libelle: 'Noto Kufi',
    note: "Koufique — anguleux",
    signes: 19,
    locale: false,
  ),
  (
    famille: 'Kufam',
    libelle: 'Kufam',
    note: "Koufique contemporain",
    signes: 7,
    locale: false,
  ),
  (
    famille: 'Reem Kufi',
    libelle: 'Reem Kufi',
    note: "Koufique decoratif",
    signes: 4,
    locale: false,
  ),
  (
    famille: 'Katibeh',
    libelle: 'Katibeh',
    note: "Calligraphique persan",
    signes: 17,
    locale: false,
  ),
  (
    famille: 'Aref Ruqaa',
    libelle: 'Aref Ruqaa',
    note: "Ruqa — ecriture manuscrite",
    signes: 5,
    locale: false,
  ),
  (
    famille: 'Cairo',
    libelle: 'Cairo',
    note: "Contemporaine — Egypte",
    signes: 4,
    locale: false,
  ),
  (
    famille: 'Almarai',
    libelle: 'Almarai',
    note: "Contemporaine — Golfe",
    signes: 5,
    locale: false,
  ),
  (
    famille: 'Tajawal',
    libelle: 'Tajawal',
    note: "Contemporaine — geometrique",
    signes: 3,
    locale: false,
  ),
  (
    famille: 'Readex Pro',
    libelle: 'Readex Pro',
    note: "Contemporaine — tres ouverte",
    signes: 4,
    locale: false,
  ),
];

/// Libellé de l'écriture courante, pour l'afficher sous l'entrée des Réglages.
/// Repli sur la valeur brute si le réglage porte une famille retirée depuis.
String libelleEcriture(String famille) {
  for (final e in kEcrituresMushaf) {
    if (e.famille == famille) return e.libelle;
  }
  return famille;
}

/// Ouvre la feuille de choix de l'écriture.
///
/// Chaque ligne porte le nom, ce que l'écriture est, sa couverture, et surtout
/// un APERÇU du même verset dans cette écriture : c'est l'aperçu qui permet de
/// choisir, pas le nom. Le verset témoin est la Bismillah — elle porte une
/// shadda, un alif suscrit et plusieurs harakat, donc exactement ce qui
/// distinguait mal les polices.
Future<void> ouvrirChoixEcriture(
  BuildContext context,
  WidgetRef ref, {
  required bool sombre,
}) {
  const temoin = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ';
  final actuelle = ref.read(policeMushafPageProvider);
  // ── LES PLUS COMPLETES EN PREMIER (2026-09-03) ─────────────────────────
  //
  // « enlève les notes d'affichage, mais fais quand même un tri, les
  // meilleures en premier ». Les notes disparaissent de l'écran : c'est donc
  // l'ORDRE qui doit porter l'information, et il la porte sur le seul critère
  // objectif dont on dispose — le nombre des 19 signes proprement coraniques
  // que la police sait dessiner, relevé dans son binaire.
  //
  // Tri STABLE : `List.sort` ne l'est pas en Dart, et deux écritures à égalité
  // se retrouveraient dans un ordre changeant d'une ouverture à l'autre. On
  // départage donc par la position d'origine, qui suit les traditions du
  // mushaf (naskh arabe, Maghreb, sous-continent, Iran, koufique…). Amiri,
  // écriture par défaut, reste ainsi en tête de son groupe.
  //
  // ── UNE EXCEPTION AU TRI, ASSUMÉE ──────────────────────────────────────
  //
  // « remonte le maghribi parmi les premiers, exception » (même jour). Le tri
  // objectif la reléguait au 20ᵉ rang : elle ne dessine que 4 des 19 signes.
  // Mais c'est l'écriture du mushaf marocain, celle de la riwāya Warsh que
  // l'application sert — la classer derrière des polices d'affichage
  // contemporaines n'aurait aucun sens pour un lecteur du Maghreb.
  //
  // C'est donc un choix ÉDITORIAL, pas une mesure : d'où une liste nommée
  // plutôt qu'un champ de plus dans le catalogue. Y ajouter une écriture,
  // c'est décider qu'elle prime sur sa couverture — à ne pas faire sans raison.
  const misesEnAvant = <String>['Bouazzi Maghribi'];
  final triees = [
    for (var i = 0; i < kEcrituresMushaf.length; i++) (i, kEcrituresMushaf[i]),
  ]..sort((a, b) {
      final ra = misesEnAvant.indexOf(a.$2.famille);
      final rb = misesEnAvant.indexOf(b.$2.famille);
      if (ra != rb) {
        // -1 = absente de la liste : elle passe APRÈS celles qui y sont.
        if (ra == -1) return 1;
        if (rb == -1) return -1;
        return ra.compareTo(rb);
      }
      final parSignes = b.$2.signes.compareTo(a.$2.signes);
      return parSignes != 0 ? parSignes : a.$1.compareTo(b.$1);
    });
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: sombre ? AppColors.sombreBgDeep : const Color(0xFFFDFDF3),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (feuille) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (contexte, controleur) => ListView.separated(
          controller: controleur,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: kEcrituresMushaf.length + 2,
          separatorBuilder: (contexte, index) => Divider(
            height: 1,
            color: (sombre ? AppColors.brass : AppColors.green800)
                .withValues(alpha: 0.12),
          ),
          itemBuilder: (contexte, i) {
            if (i == 0) return _EnTeteFeuille(sombre: sombre);
            if (i == 1) return const _BasculeTajwid();
            final e = triees[i - 2].$2;
            final choisie = e.famille == actuelle;
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              // ── LIGNE EPUREE (2026-09-03) ────────────────────────────────
              // « enlève les notes d'affichage, mais fais quand même un tri,
              // les meilleures en premier ». La description et le compteur
              // `x/19` disparaissent de la liste : c'est désormais l'ORDRE qui
              // porte l'information, et l'aperçu qui fait choisir. Le détail
              // reste dans `kEcrituresMushaf` pour qui lit le code.
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.libelle,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: choisie ? FontWeight.w800 : FontWeight.w600,
                        color: sombre ? AppColors.cream : AppColors.green900,
                      ),
                    ),
                  ),
                  if (choisie)
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: sombre ? AppColors.brass : AppColors.green800,
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text(
                      temoin,
                      style: styleEcriture(
                        e,
                        taille: 24,
                        interligne: 1.9,
                        couleur:
                            sombre ? AppColors.cream : const Color(0xFF1A1208),
                      ),
                    ),
                  ),
                ],
              ),
              onTap: () {
                ref.read(policeMushafPageProvider.notifier).definir(e.famille);
                Navigator.of(contexte).pop();
              },
            );
          },
        ),
      ),
    ),
  );
}

/// Couleurs du tajwid : allumées ou éteintes.
///
/// Demande utilisateur 2026-09-03 : « tu peux laisser option couleur tajwid ou
/// pas, avec icône tablette de coloriage enfant ». D'où la palette.
///
/// Elle vit ICI, dans la feuille d'appui long, et non en bouton permanent :
/// l'utilisateur a demandé plusieurs fois que l'écran revienne au texte, et un
/// bouton reprendrait la place qu'on vient de lui rendre. L'appui long est
/// déjà le geste qui ouvre les options de la page.
///
/// ⚠️ Couper la couleur ne change RIEN aux caractères peints : ils viennent
/// toujours de `text_uthmani`, l'annotation ne fournit que la teinte. Le champ
/// `text_uthmani_tajweed` diffère du texte de référence sur 100 % des versets ;
/// il ne doit jamais fournir de caractères, avec ou sans couleur.
class _BasculeTajwid extends ConsumerWidget {
  const _BasculeTajwid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(tajwidMushafPageProvider);
    final sombre = ref.watch(modeSombreProvider);
    return SwitchListTile.adaptive(
      value: on,
      onChanged: (v) => ref.read(tajwidMushafPageProvider.notifier).set(v),
      secondary: Icon(
        Icons.palette_rounded,
        color: on
            ? AppColors.green800
            : (sombre ? AppColors.cream : AppColors.inkLight)
                .withValues(alpha: 0.5),
      ),
      title: Text(
        AppLocalizations.of(context)!.scriptTajwidColors,
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: sombre ? AppColors.cream : AppColors.green900,
        ),
      ),
      subtitle: Text(
        on ? 'Règles colorées sur la page' : 'Page en une seule encre',
        style: GoogleFonts.manrope(
          fontSize: 11,
          color: sombre
              ? AppColors.cream.withValues(alpha: 0.6)
              : AppColors.inkLight,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}

class _EnTeteFeuille extends StatelessWidget {
  final bool sombre;
  const _EnTeteFeuille({required this.sombre});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.scriptSheetTitle,
          style: GoogleFonts.manrope(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: sombre ? AppColors.cream : AppColors.green900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)!.scriptSheetExplain,
          style: GoogleFonts.manrope(
            fontSize: 12,
            height: 1.4,
            color: sombre
                ? AppColors.cream.withValues(alpha: 0.7)
                : AppColors.inkLight,
          ),
        ),
      ],
    ),
  );
}
