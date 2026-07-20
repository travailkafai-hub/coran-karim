import '../models/dua.dart';
import 'duas_coeur.dart';
import 'duas_coran.dart';
import 'duas_jour.dart';
import 'duas_priere.dart';
import 'duas_vie.dart';

/// Catalogue complet, réassemblé depuis les fichiers par univers.
///
/// Point d'entrée unique pour les écrans : ceux-ci n'ont jamais à savoir
/// dans quel fichier vit une invocation.
final List<Dua> kAllDuas = [
  ...kDuasJour,
  ...kDuasPriere,
  ...kDuasCoran,
  ...kDuasVie,
  ...kDuasCoeur,
];

/// Index tag de collection → invocations, construit une fois au démarrage.
///
/// Sans cet index, chaque ouverture de collection re-filtrait les ~130
/// entrées. Peu coûteux à cette taille, mais l'index rend aussi possible
/// l'affichage du COMPTE par collection sur le hub (« 14 invocations »),
/// qui lui demanderait autant de parcours qu'il y a de collections.
final Map<String, List<Dua>> kDuasByCollection = () {
  final map = <String, List<Dua>>{};
  for (final dua in kAllDuas) {
    for (final tag in dua.tags) {
      map.putIfAbsent(tag, () => []).add(dua);
    }
  }
  return map;
}();

/// Index id → invocation (résolution depuis les favoris persistés et depuis
/// les étapes de rite, qui référencent des duas par id).
final Map<String, Dua> kDuasById = {for (final d in kAllDuas) d.id: d};

List<Dua> duasForCollection(String collectionId) =>
    kDuasByCollection[collectionId] ?? const [];

/// Recherche plein texte sur FR + AR + translittération + source.
///
/// Volontairement naïve (`contains` sur une chaîne agrégée) : à 130 entrées
/// c'est instantané, et une recherche floue introduirait des faux positifs
/// pénibles sur un corpus où les titres se ressemblent beaucoup
/// (« dhikr du matin », « dhikr du soir »…).
List<Dua> searchDuas(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return kAllDuas.where((d) => d.searchBlob.contains(q)).toList();
}
