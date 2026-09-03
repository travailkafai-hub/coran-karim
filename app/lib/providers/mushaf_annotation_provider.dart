import 'package:flutter/material.dart' show Color, Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/diagnostic_log.dart';
import '../services/session_archive_service.dart';

/// Surlignage libre du Mushaf -- « crayon » (demande utilisateur 2026-08-28) :
/// « on permet de tracer sur le mushaf en train d'apprendre, il surligne
/// quelque chose avec différentes couleurs [...] ça doit rester avec
/// mémorisation sauf si il lance initialisation qui efface tout ».
///
/// Persisté mot par mot dans `session_archive.db` (cf. la doc de
/// `SessionArchiveService._creerTableMushafMarks`), volontairement dans la
/// MÊME base que le suivi de mémorisation -- pas un fichier séparé -- pour
/// que la remise à zéro complète (`toutEffacer`) les efface ensemble sans
/// rien de plus à maintenir.

/// Palette -- QUATRE couleurs élémentaires bien foncées (demande utilisateur
/// 2026-08-28, après la palette pastel initiale à six teintes : « je veux
/// juste 4 couleurs élémentaires bien foncées »), dans l'alpha qui sert le
/// SURLIGNEUR (fond de mot translucide -- un aplat plein masquerait les
/// diacritiques). Le CRAYON, lui, repeint en pleine opacité à l'affichage
/// (cf. `_TraitsPainter._peindreTrait` dans mushaf_screen.dart) : une seule
/// liste sert donc les deux outils sans dupliquer la palette.
/// ── DEUX COULEURS, DEUX RENDUS (2026-09-02) ────────────────────────────────
/// Demande utilisateur : « laisse deux couleurs rouge et verte quand c'est
/// stylo, et ca devient des couleurs fluorescentes quand c'est pour surligner
/// [...] les couleurs se remplacent selon le type ».
///
/// Rouge et vert, et rien d'autre : ce sont les deux seules marques dont la
/// lecture a besoin -- ce qui est faux, ce qui est acquis. Le bleu et le noir
/// de la palette precedente ne portaient aucun sens convenu, et leur presence
/// avait un cout cache : avec quatre pastilles la barre debordait et poussait
/// la GOMME hors de l'ecran (defilement horizontal), au point que
/// l'utilisateur l'a crue absente.
///
/// STYLO : opaque. Un trait trace a la main doit se voir comme un trait
/// d'encre, pas comme un voile.
const List<Color> kMushafPenColors = [
  Color(0xFFC62828), // rouge encre
  Color(0xFF2E7D32), // vert encre
];

/// SURLIGNEUR : les MEMES deux couleurs, en fluo et translucides.
///
/// Translucides parce qu'un aplat plein masquerait les diacritiques -- c'est
/// la raison qui valait deja pour l'ancienne palette, et elle n'a pas change.
/// Fluo parce que c'est ce qu'on attend d'un surligneur : la couleur doit
/// SORTIR du papier, la ou l'encre du stylo s'y pose.
const List<Color> kMushafHighlighterColors = [
  Color(0x99FF3D57), // rouge fluo
  Color(0x997CFC00), // vert fluo
];

/// Palette de l'outil courant. C'est le point unique du « les couleurs se
/// remplacent selon le type » : un seul endroit decide, l'IHM et la
/// conversion de couleur en dependent toutes deux.
List<Color> couleursPour(MushafAnnotationTool outil) =>
    outil == MushafAnnotationTool.pen
        ? kMushafPenColors
        : kMushafHighlighterColors;

/// L'EQUIVALENTE dans l'autre palette, par position.
///
/// Sert au changement d'outil : passer du stylo au surligneur doit garder la
/// couleur CHOISIE (rouge reste rouge) et n'en changer que le rendu. Sans
/// cela, la couleur active resterait une valeur de l'ancienne palette et la
/// pastille selectionnee n'aurait plus de correspondance visible -- aucune
/// pastille ne paraitrait cochee.
Color? equivalenteDans(Color? couleur, MushafAnnotationTool cible) {
  if (couleur == null) return null; // gomme : elle n'a pas de couleur
  for (final source in [kMushafPenColors, kMushafHighlighterColors]) {
    final i = source.indexWhere((c) => c.toARGB32() == couleur.toARGB32());
    if (i >= 0) return couleursPour(cible)[i];
  }
  return couleursPour(cible).first;
}

/// ANCIENNE PALETTE, conservee pour lire ce qui a deja ete marque.
///
/// Regle projet : on n'efface pas ce qui a servi. Les traits et surlignages
/// deja poses portent ces valeurs en base (`color` en ARGB) et doivent
/// continuer a s'afficher tels quels -- ils ne sont simplement plus
/// PROPOSABLES. Ne pas supprimer sans purger la base, ce qui ferait perdre
/// des annotations de l'utilisateur.
const List<Color> kMushafHighlightColors = [
  Color(0x99C62828), // rouge
  Color(0x991565C0), // bleu
  Color(0x992E7D32), // vert
  Color(0x991A1A1A), // noir
];

/// Mode annotation actif ou non. Volontairement TRANSITOIRE (pas persisté) :
/// s'active à la demande depuis le menu du Mushaf, se referme en quittant le
/// mode -- ce qui a déjà été marqué reste (`mushafHighlightsProvider`), seul
/// « je suis en train de marquer » ne doit pas survivre malgré soi à la
/// prochaine ouverture de l'écran.
final mushafAnnotationModeProvider = StateProvider<bool>((ref) => false);

/// Couleur actuellement sélectionnée dans la barre d'outils. `null` = outil
/// gomme (le tap retire la marque au lieu d'en poser une).
final mushafAnnotationColorProvider =
    StateProvider<Color?>((ref) => kMushafPenColors.first);

/// Outil actif -- surligneur (tap sur un mot, existant) ou crayon (tracé
/// libre au doigt/stylet, 2026-08-28, demande utilisateur : « je pensais à
/// un vrai stylet comme des apps de dessin », référence montrée : Notes
/// Samsung -- pen/highlighter/gomme + palette). Défaut au crayon : c'est la
/// demande explicite, le surligneur reste un raccourci pour marquer un mot
/// entier d'un coup sans avoir à le souligner à la main.
enum MushafAnnotationTool { pen, highlighter }

final mushafAnnotationToolProvider =
    StateProvider<MushafAnnotationTool>((ref) => MushafAnnotationTool.pen);

/// Barre d'outils réduite à une simple pastille flottante (demande
/// utilisateur 2026-08-28 : « le widget soit minimaliste, placé en bas qui
/// se réduit également »). Transitoire comme `mushafAnnotationModeProvider`
/// -- ne présage de rien à la prochaine ouverture du mode annotation.
final mushafAnnotationToolbarReducedProvider = StateProvider<bool>((ref) => false);

/// Un trait libre, en coordonnées NORMALISÉES [0,1] par rapport à la largeur/
/// hauteur du VERSET où il a été tracé -- pas des pixels absolus. Un verset
/// ne se déplace jamais à l'écran (il défile en bloc), mais sa TAILLE peut
/// changer (police, traduction affichée) : normaliser par rapport à son
/// propre cadre garde le trait à la bonne place tant que le texte visible
/// dans ce cadre ne change pas de nombre de lignes -- même logique
/// qu'annoter une page imprimée : l'encre suit la page, pas l'écran.
class MushafStroke {
  final int? id; // null tant que non persisté (jamais le cas en pratique ici)
  final List<Offset> points;
  final Color couleur;
  const MushafStroke({required this.id, required this.points, required this.couleur});
}

/// Traits libres du Mushaf, mêmes principes de chargement/persistance que
/// [MushafHighlightsNotifier] -- cf. sa doc pour le "pourquoi" partagé
/// (même base que la mémorisation, chargé une fois, tenu à jour en mémoire).
///
/// Clé : `"surah:ayah:riwaya"` (pas de mot : un trait libre n'appartient pas
/// à UN mot).
final mushafStrokesProvider =
    StateNotifierProvider<MushafStrokesNotifier, Map<String, List<MushafStroke>>>(
        (ref) {
  return MushafStrokesNotifier();
});

class MushafStrokesNotifier extends StateNotifier<Map<String, List<MushafStroke>>> {
  MushafStrokesNotifier() : super(const {}) {
    _charger();
  }

  Future<void> _charger() async {
    try {
      final traits = await SessionArchiveService.instance.tousLesTraitsMushaf();
      if (mounted) {
        state = {
          for (final e in traits.entries)
            e.key: [
              for (final t in e.value)
                MushafStroke(id: t.id, points: t.points, couleur: Color(t.color)),
            ],
        };
      }
    } catch (e) {
      DiagnosticLog.log('Mushaf', 'chargement des traits : echec $e');
    }
  }

  static String cle(int surah, int ayah, String riwaya) => '$surah:$ayah:$riwaya';

  Future<void> ajouter(int surah, int ayah, String riwaya, Color couleur,
      List<Offset> points) async {
    if (points.length < 2) return;
    final id = await SessionArchiveService.instance.ajouterTraitMushaf(
      surahNumber: surah,
      ayahNumber: ayah,
      riwaya: riwaya,
      color: couleur.toARGB32(),
      points: points,
    );
    final c = cle(surah, ayah, riwaya);
    final existants = state[c] ?? const [];
    state = {
      ...state,
      c: [...existants, MushafStroke(id: id, points: points, couleur: couleur)],
    };
  }

  Future<void> effacer(int surah, int ayah, String riwaya, int strokeId) async {
    final c = cle(surah, ayah, riwaya);
    final existants = state[c];
    if (existants == null) return;
    final apres = existants.where((t) => t.id != strokeId).toList();
    if (apres.length == existants.length) return;
    state = {...state, c: apres};
    await SessionArchiveService.instance.effacerTraitMushaf(strokeId);
  }

  /// Vide les traits EN MEMOIRE. La base est videe par
  /// `MushafHighlightsNotifier.toutEffacer`, qui appelle la methode SQLite
  /// commune aux deux -- une seule transaction, pas deux.
  void viderMemoire() => state = const {};
}

/// Marques posées sur le Mushaf, chargées une fois depuis
/// [SessionArchiveService] puis tenues à jour en mémoire à chaque geste --
/// une requête SQLite par mot taillé pendant un défilement serait inutile,
/// le volume (quelques marques, jamais tout le Coran) tient sans effort en
/// mémoire.
///
/// Clé de la map : `"surah:ayah:mot:riwaya"`, même format que la table SQLite
/// (`SessionArchiveService.toutesLesMarquesMushaf`) -- pas de traduction dans
/// un sens puis dans l'autre. Valeur : la couleur, encodée en ARGB 32 bits.
final mushafHighlightsProvider =
    StateNotifierProvider<MushafHighlightsNotifier, Map<String, int>>((ref) {
  return MushafHighlightsNotifier();
});

class MushafHighlightsNotifier extends StateNotifier<Map<String, int>> {
  MushafHighlightsNotifier() : super(const {}) {
    _charger();
  }

  Future<void> _charger() async {
    try {
      final marques =
          await SessionArchiveService.instance.toutesLesMarquesMushaf();
      if (mounted) state = marques;
    } catch (e) {
      DiagnosticLog.log('Mushaf', 'chargement des marques : echec $e');
    }
  }

  static String cle(int surah, int ayah, int mot, String riwaya) =>
      '$surah:$ayah:$mot:$riwaya';

  Color? couleurDe(int surah, int ayah, int mot, String riwaya) {
    final v = state[cle(surah, ayah, mot, riwaya)];
    return v == null ? null : Color(v);
  }

  Future<void> definir(
      int surah, int ayah, int mot, String riwaya, Color couleur) async {
    final c = cle(surah, ayah, mot, riwaya);
    state = {...state, c: couleur.toARGB32()};
    await SessionArchiveService.instance.definirMarqueMushaf(
      surahNumber: surah,
      ayahNumber: ayah,
      wordInAyah: mot,
      riwaya: riwaya,
      color: couleur.toARGB32(),
    );
  }

  Future<void> effacer(int surah, int ayah, int mot, String riwaya) async {
    final c = cle(surah, ayah, mot, riwaya);
    if (!state.containsKey(c)) return;
    final copie = {...state}..remove(c);
    state = copie;
    await SessionArchiveService.instance.effacerMarqueMushaf(
      surahNumber: surah,
      ayahNumber: ayah,
      wordInAyah: mot,
      riwaya: riwaya,
    );
  }

  /// Efface TOUTES les annotations du Mushaf : surlignages ET traits, toutes
  /// riwayat, toutes sourates, sans limite de date.
  ///
  /// La methode que la doc de ce fichier annoncait depuis le debut sans
  /// qu'elle existe (ajoutee le 2026-09-02). Prend [traits] en parametre
  /// plutot que de lire un provider : un StateNotifier qui en pilote un autre
  /// par `ref` cree un couplage que rien ici ne justifie -- l'appelant a les
  /// deux sous la main.
  ///
  /// IRREVERSIBLE : a n'appeler qu'apres confirmation explicite.
  Future<void> toutEffacer(MushafStrokesNotifier traits) async {
    state = const {};
    traits.viderMemoire();
    await SessionArchiveService.instance.effacerToutesAnnotationsMushaf();
  }
}
