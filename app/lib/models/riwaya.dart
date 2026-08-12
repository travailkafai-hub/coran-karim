/// Riwāya (transmission de lecture) du Coran affichée, récitée et jugée par
/// l'application (demande utilisateur 2026-08-12 : « une fois l'utilisateur
/// bascule sur Warsh, la page du Mushaf, la recherche, la récitation, l'audio
/// de correction — tout doit être en Warsh »).
///
/// Vit dans son propre fichier, et non à côté du réglage qui le porte
/// (`riwayaProvider`, app_settings_provider.dart) : `QuranApi` doit connaître
/// ce type, et le réglage doit connaître `QuranApi` pour lui pousser la
/// valeur — les mettre ensemble créerait un cycle d'imports.
///
/// Ce que ce type NE change PAS, volontairement (décision utilisateur) : le
/// modèle ASR, qui reste celui entraîné sur du Hafs et qu'on observe à
/// l'œuvre sur du Warsh ; et les schémas de stockage, puisque les deux textes
/// partagent les mêmes clés de verset (cf.
/// `benchmark/build_warsh_verses_asset.py`).
enum Riwaya {
  /// Hafs 'an 'Asim — la lecture d'origine de l'app, comportement inchangé.
  hafs,

  /// Warsh 'an Nafi' — texte KFGQPC, récitateurs Warsh d'everyayah.
  warsh,
}
