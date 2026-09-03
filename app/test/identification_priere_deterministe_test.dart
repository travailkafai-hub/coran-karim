// Banc de test DÉTERMINISTE pour l'identification de sourate du mode
// "Suivre une prière" -- demande utilisateur explicite (2026-08-29) :
// « est-ce que tu as effectué des tests d'une manière déterministe ? » --
// réponse honnête : non, tout avait été vérifié en récitant en direct sur le
// téléphone (audio différent à chaque prise). CE FICHIER comble ce trou :
// il rejoue des textes FIXES (dont des cas réellement mesurés en session,
// bruités volontairement) à travers `_meilleureTroncature` (copie fidèle de
// `_meilleureTroncatureDeTete`, cf. `recitation_provider.dart`) puis
// `QuranVerseLocatorService.locate()` -- sans micro, sans utilisateur,
// reproductible à l'identique.
//
// ⚠️ GARDÉ (pas supprimé après usage, contrairement au diagnostic ponctuel du
// même jour) : à relancer avant toute nouvelle recette live sur ce
// mécanisme. Si `_meilleureTroncatureDeTete` change dans le provider, mettre
// à jour `_meilleureTroncature` ci-dessous en miroir.
import 'package:flutter_test/flutter_test.dart';
import 'package:coran_karim/services/quran_verse_locator_service.dart';

/// Copie fidèle de `RecitationNotifier._meilleureTroncatureDeTete` --
/// privée dans le provider, donc dupliquée ici pour rester testable sans
/// instancier tout le notifier (verifier, providers Riverpod...).
Future<String> _meilleureTroncature(String requete) async {
  final mots =
      requete.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  var meilleure = requete;
  var meilleurScore = -1.0;
  for (var drop = 0; drop <= 4 && mots.length - drop >= 2; drop++) {
    final variante = mots.sublist(drop).join(' ');
    final matches = await QuranVerseLocatorService.instance
        .locateTopMatches(variante, k: 1, minScore: 0.0);
    final score = matches.isEmpty ? 0.0 : matches.first.confidence;
    if (score > meilleurScore) {
      meilleurScore = score;
      meilleure = variante;
    }
  }
  return meilleure;
}

Future<QuranMatch?> _identifie(String texteEntendu) async {
  final requete = await _meilleureTroncature(texteEntendu);
  return QuranVerseLocatorService.instance.locate(requete);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('identification de sourate -- cas mesures en session reelle', () {
    test('texte PROPRE (tape a la main dans "l\'oreille") -> 4:1', () async {
      const texte = 'يَـٰٓأَيُّهَا ٱلنَّاسُ ٱتَّقُوا۟ رَبَّكُمُ ٱلَّذِى خَلَقَكُمْ';
      final match = await _identifie(texte);
      expect(match, isNotNull, reason: 'devrait trouver un candidat');
      expect(match!.surahNumber, 4);
      expect(match.ayahNumber, 1);
      expect(match.confidence, greaterThan(0.9),
          reason: 'texte propre : score quasi parfait attendu');
    });

    test(
        'residu court "وَحِيف" en tete (mesure device 2026-08-29, build v193) '
        '-> doit rester 4:1 apres troncature, PAS 3:200', () async {
      const texte = 'وَحِيف يَـٰٓأَيُّهَا ٱلنَّاسُ ٱتَّقُوا۟ رَبَّكُمُ';
      // AVANT le correctif v194 : locate() direct sur ce texte donnait
      // RETENU 3:200 (6 votes, score 0.600) -- mesure reelle, cf. le log de
      // la session 14:09:28. Avec la troncature, le mot "وَحِيف" doit etre
      // retire et le vrai 4:1 retrouve.
      final match = await _identifie(texte);
      expect(match, isNotNull);
      expect(match!.surahNumber, 4,
          reason: 'le residu "وَحِيف" ne doit plus faire devier vers 3:200');
      expect(match.ayahNumber, 1);
    });

    test(
        'residu Bismillah garble en tete (mesure device 2026-08-29, build '
        'v185) -> doit rester 4:1 apres troncature, PAS 6:19', () async {
      const texte =
          'ءَامِي بِسْمِـٰنِحِيمِ مِي يَـٰٓ يَـٰٓأَيُّهَا ٱلنَّاسُ ٱتَّقُوا۟ '
          'رَبَّكُمُ ٱلَّذِى خَلَقَكُمْ';
      // AVANT le correctif v188 : ce residu (4 mots) melange au vrai debut
      // d'An-Nisa faisait tomber le score de 1,000 (texte seul) a un mauvais
      // match. Cf. le log de la session ayant produit "RETENU 6:19".
      final match = await _identifie(texte);
      expect(match, isNotNull);
      expect(match!.surahNumber, 4,
          reason: 'le residu Bismillah ne doit plus faire devier vers 6:19');
      expect(match.ayahNumber, 1);
    });

    test(
        'probe de 2 mots (mesure device 2026-08-29, build v196, ecoute 3s '
        'sans accumulation) -> score parfait mais votes insuffisants, '
        'DOIT etre ecarte par le plancher de votes cote appelant', () async {
      // Log reel : "identification (capture dediee) : RETENU 2:21 1
      // vote(s), score 1.000" -- FAUX (le recitateur disait le debut
      // d'An-Nisa 4:1). `locate()` lui-meme ne peut pas le savoir : avec 1
      // seule paire testee, 1 vote = 100% mecaniquement. La protection est
      // `_kVotesMinCaptureDediee` cote provider (pas dans `locate()`), ce
      // test documente POURQUOI elle existe -- reproduit ici le signal brut
      // que le plancher doit filtrer.
      const texte = 'يَـٰٓأَيُّهَا ٱلنَّاسُ';
      final match = await QuranVerseLocatorService.instance.locate(texte);
      expect(match, isNotNull, reason: 'locate() trouve bien un candidat...');
      expect(match!.votes, lessThan(3),
          reason:
              '...mais avec si peu de votes que le score seul (${match.confidence}) '
              'ne suffit pas a le distinguer d\'une coincidence -- '
              'RecitationNotifier._kVotesMinCaptureDediee doit l\'ecarter');
    });

    test('locate() retrouve bien Al-Fatiha sur un extrait assez long',
        () async {
      // `_tryIdentifyTarget`/`_identifierParCaptureDediee` ecartent tout
      // candidat surah==1 (residu de fin d'Al-Fatiha) -- verifie ici que
      // `locate()` lui-meme peut retrouver la Fatiha si on la lui donne (le
      // filtre est une decision APPELANTE, pas une propriete de `locate()`).
      //
      // ⚠️ PIEGE DECOUVERT EN ECRIVANT CE TEST : un extrait COURT de 4 mots
      // ("الحمد لله رب العالمين" seul) matche 10:10 (Yunus se termine par la
      // MEME formule exacte) avant Al-Fatiha 1:2 -- ambiguite reelle du texte
      // coranique, pas un bug de l'app (meme famille que "يا أيها الناس" qui
      // ouvre 3 sourates differentes, deja documente plus haut). D'ou
      // l'extrait plus long ici : Bismillah + versets 2-4, une suite qui
      // n'existe qu'au debut d'Al-Fatiha.
      const texte = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ ٱلْحَمْدُ '
          'لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ مَـٰلِكِ '
          'يَوْمِ ٱلدِّينِ';
      final match = await QuranVerseLocatorService.instance.locate(texte);
      expect(match, isNotNull);
      expect(match!.surahNumber, 1);
    });
  });
}
