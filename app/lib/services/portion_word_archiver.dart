// Suivi permanent par portion + extension aux mots contigus en erreur --
// FACTORISÉ le 2026-08-24 (demande utilisateur : « ça sera mieux de
// réutiliser », après avoir constaté que l'écran Contrôle (`coach_screen.dart`)
// avait dérivé de l'écran karaoké (`karaoke_recitation_screen.dart`) : verset
// entier affiché au lieu du seul mot fautif, et pouce vers le bas sans aucune
// ligne `portion_words` à mettre à jour. Les DEUX défauts venaient de la même
// cause -- une logique dupliquée, pas partagée, donc corrigée d'un côté sans
// jamais l'être de l'autre. Un seul endroit désormais ; un correctif futur
// profite aux deux écrans à la fois.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recitation_state.dart' show RecitedWord, WordStatus;
import '../models/riwaya.dart';
import '../models/verse.dart';
import '../providers/app_settings_provider.dart'
    show portionGranularityProvider, appLocaleProvider;
import '../providers/recitation_provider.dart';
import 'diagnostic_log.dart';
import 'portion_service.dart';
import 'session_archive_service.dart';

/// Lecteur de provider passé par l'appelant plutôt qu'un `WidgetRef` brut --
/// c'est CE choix qui rend la fonction sûre après démontage. `WidgetRef.read`
/// jette `Bad state: Cannot use "ref" after the widget was disposed` dès que
/// l'écran a disparu (ex. navigation pendant que la dernière écriture est
/// encore en vol) ; un appelant peut passer un lecteur adossé à un
/// `ProviderContainer` capturé au premier build, qui SURVIT au démontage --
/// cf. `_lireProvider` dans `karaoke_recitation_screen.dart`, le précédent
/// déjà établi (et le bug réel qu'il corrige, payé une première fois le
/// 2026-08-23 sur `_comptabiliserPourCoach`).
typedef LecteurProvider = T Function<T>(ProviderListenable<T> p);

/// Étend [wordIndexLocal] (indice LOCAL au verset affiché) aux mots CONTIGUS
/// qui portent eux aussi un verdict négatif -- pour que la fiche tajwid
/// n'affiche que la difficulté réelle, pas tout le verset.
///
/// Demande utilisateur (2026-08-05, écran karaoké) : « quand je clique sur le
/// mot en erreur j'ai toute l'aya qui s'affiche ; je veux que ça reste sur le
/// mot en question. Si deux ou trois mots en erreur sont côte à côte, on peut
/// les fusionner dans la même fenêtre. »
///
/// ⚠️ SEULS LES VERDICTS NÉGATIFS FUSIONNENT : un mot `pending`/`current` n'a
/// pas été jugé, l'inclure ferait grossir l'extrait au fil de la récitation
/// jusqu'à redonner le verset entier.
///
/// @param wordIndexGlobal indice du mot dans [words] (peut concaténer
///   plusieurs versets, cf. les deux appelants).
/// @param wordIndexLocal indice du même mot DANS le verset affiché.
/// @param motsDuVerset nombre de mots du verset affiché (borne l'extension :
///   déborder sur le verset voisin afficherait un texte que la feuille ne
///   sait pas rendre, elle part de `verse.textUthmani` seul).
/// @return (débutLocal, finLocaleExclusive) -- bornes à passer telles quelles
///   à `extraitDebut`/`extraitFin` de `showTajwidHelpSheet`.
(int, int) etendreAuxMotsContigusEnErreur({
  required List<RecitedWord> words,
  required int wordIndexGlobal,
  required int wordIndexLocal,
  required int motsDuVerset,
}) {
  bool estEnErreur(int i) {
    if (i < 0 || i >= words.length) return false;
    final s = words[i].status;
    return s == WordStatus.error ||
        s == WordStatus.unclear ||
        s == WordStatus.skipped;
  }

  var debut = wordIndexLocal;
  var fin = wordIndexLocal;
  if (estEnErreur(wordIndexGlobal)) {
    while (debut > 0 &&
        estEnErreur(wordIndexGlobal - (wordIndexLocal - debut) - 1)) {
      debut--;
    }
    while (fin + 1 < motsDuVerset &&
        estEnErreur(wordIndexGlobal + (fin - wordIndexLocal) + 1)) {
      fin++;
      if (fin - wordIndexLocal > 12) break; // garde-fou : jamais un verset entier
    }
  }
  return (debut, fin + 1);
}

/// Suivi PERMANENT par portion (sourate, ou tranche de Hizb/demi-Hizb) --
/// écrit pour TOUT mot verrouillé (vert compris) dans `portion_words`, le
/// pourcentage lu par « Mes portions » et le badge de portion. Distinct du
/// journal `session_words` (daté à 7 jours) : les deux écritures coexistent,
/// chacune alimente son propre écran du Coach.
///
/// L'extrait audio n'est tenté QUE pour un mot non vert -- inutile de
/// consommer l'anneau natif (300 s, urgent) pour un mot déjà correct dont
/// personne n'aura besoin de réentendre la preuve.
///
/// Ne touche jamais au déroulement de la récitation en cours : une panne ici
/// (réseau, timing indisponible, `ref` invalide) est journalisée et avalée,
/// jamais propagée -- c'est un suivi EN PLUS, pas une condition.
Future<void> archiverMotDansPortion({
  required LecteurProvider lire,
  required Verse verse,
  required int wordIndexLocal,
  required int wordIndexGlobal,
  required RecitedWord mot,
}) async {
  if (mot.isBasmala) return; // jamais jugée, cf. la règle du 2026-07-20
  String? extrait;
  if (mot.status != WordStatus.correct) {
    try {
      extrait = await lire(recitationVerifierProvider).v2ExtraitVoix(
          wordIndexGlobal > 0 ? wordIndexGlobal - 1 : wordIndexGlobal,
          wordIndexGlobal);
    } catch (e) {
      DiagnosticLog.log(
          'Archive', 'extrait voix (portion) impossible mot=$wordIndexGlobal : $e');
    }
  }
  try {
    final granularite = lire(portionGranularityProvider);
    final portion = await PortionService.resolve(
        verse: verse,
        granularity: granularite,
        locale: Locale(lire(appLocaleProvider)));
    await SessionArchiveService.instance.upsertPortionWord(
      surahNumber: verse.surahNumber,
      unitKey: portion.unitKey,
      label: portion.label,
      firstAyah: portion.firstAyah,
      lastAyah: portion.lastAyah,
      wordsTotal: portion.wordsTotal,
      ayahNumber: verse.ayahNumber,
      wordInAyah: wordIndexLocal,
      expectedWord: mot.display,
      status: mot.status.name,
      heardWord: mot.heard,
      kind: mot.status == WordStatus.correct
          ? null
          : lire(recitationProvider.notifier).classifyError(wordIndexGlobal).name,
      audioSource: extrait,
      // riwaya de LA SESSION (déjà figée par setup()) -- pas le réglage
      // global vivant, cf. RecitationSessionState.riwaya.
      riwaya: lire(recitationProvider).riwaya == Riwaya.warsh ? 'warsh' : 'hafs',
    );
  } catch (e) {
    DiagnosticLog.log(
        'Archive', 'archivage portion impossible mot=$wordIndexGlobal : $e');
  }
}
