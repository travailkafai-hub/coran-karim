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
/// Ce que ce type NE change JAMAIS, par construction : les schémas de
/// stockage, puisque les deux textes partagent les mêmes clés de verset
/// (cf. `benchmark/build_warsh_verses_asset.py`).
///
/// ⚠️ RÉVISÉ le 2026-08-22 : la ligne ci-dessus disait « le modèle ASR reste
/// celui entraîné sur du Hafs et qu'on observe à l'œuvre sur du Warsh » —
/// vrai tant que le modèle n'avait pas de tête Warsh entraînée. Depuis le
/// modèle à quatre/deux têtes (`warsh_logprobs`, vocabulaire SentencePiece
/// propre), cette décision est caduque : `FastConformerVerifier.setRiwaya`
/// bascule désormais le moteur natif sur la tête et le vocabulaire Warsh
/// dès qu'une session démarre avec `riwaya == Riwaya.warsh` (cf.
/// `RecitationNotifier._startInterne`). Cloisonnement Hafs/Warsh voulu par
/// l'utilisateur (« garder cette séparation... je veux un cloisonnement ») :
/// pas de bascule à chaud pendant une récitation active, seulement au
/// démarrage de la SUIVANTE.
enum Riwaya {
  /// Hafs 'an 'Asim — la lecture d'origine de l'app, comportement inchangé.
  hafs,

  /// Warsh 'an Nafi' — texte KFGQPC, récitateurs Warsh d'everyayah.
  warsh,
}
