// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get navQuran => 'Coran';

  @override
  String get navDuas => 'Invocations';

  @override
  String get navCoach => 'Coach';

  @override
  String get navSettings => 'Réglages';

  @override
  String get appTitle => 'Coran Karim';

  @override
  String mindMapAppBarTitle(String name) {
    return 'Carte mentale — $name';
  }

  @override
  String mindMapVerses(String range) {
    return 'Versets $range';
  }

  @override
  String mindMapAyahCountBadge(int count) {
    return '$count versets';
  }

  @override
  String get mindMapGoToVerse => 'Aller au verset';

  @override
  String get mindMapThemeLabel => 'Fil directeur';

  @override
  String get mindMapSourcesLabel => 'Sources et réserves';

  @override
  String get mindMapNotReadyTitle => 'Bientôt disponible';

  @override
  String mindMapNotReadyBody(String name) {
    return 'La carte mentale de $name (thèmes, branches, liens vers les versets) est en cours de rédaction.';
  }

  @override
  String get mindMapCatRecits => 'Récits';

  @override
  String get mindMapCatCroyance => 'Croyance';

  @override
  String get mindMapCatEschatologie => 'Au-delà';

  @override
  String get mindMapCatArgumentation => 'Argumentation';

  @override
  String get mindMapCatEthique => 'Éthique';

  @override
  String get mindMapCatLegislation => 'Législation';

  @override
  String get mindMapCatSignes => 'Signes';

  @override
  String get mindMapCatAdoration => 'Adoration';

  @override
  String get mindMapCatAutre => 'Autre';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsSectionAudio => 'Audio';

  @override
  String get settingsReciterTitle => 'Récitateur';

  @override
  String get settingsStyleMurattal => 'Murattal';

  @override
  String get settingsStyleMujawwad => 'Mujawwad';

  @override
  String get settingsSectionPrayer => 'Prière';

  @override
  String get settingsQiblaTitle => 'Direction de la Qibla';

  @override
  String get settingsQiblaSubtitle =>
      'Boussole vers la Mecque depuis ta position';

  @override
  String get settingsSectionVoicePersonalization => 'Personnalisation vocale';

  @override
  String get settingsVoiceCalibTitle =>
      'Calibration voix (lettres confusables)';

  @override
  String get settingsVoiceCalibSubtitle =>
      'Enregistre ~14 mots exprès bien/mal prononcés (ص/س, ط/ت...) pour affiner ta sensibilité';

  @override
  String get settingsMyClipsTitle => 'Enregistrements de mes récitations';

  @override
  String get settingsMyClipsLoading => 'Chargement…';

  @override
  String get settingsMyClipsEmpty =>
      'Aucun enregistrement — ils sont conservés à chaque récitation';

  @override
  String settingsMyClipsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enregistrements conservés — appuie pour les exporter',
      one: '1 enregistrement conservé — appuie pour l\'exporter',
    );
    return '$_temp0';
  }

  @override
  String get settingsExportStarted =>
      'Export lancé — choisis où envoyer le fichier.';

  @override
  String get settingsDisputedTitle => 'Verdicts contestés';

  @override
  String get settingsDisputedEmpty =>
      'Aucun verdict contesté — utilise le pouce 👎 sous « Ma voix » pendant une récitation';

  @override
  String settingsDisputedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verdicts contestés — appuie pour les envoyer',
      one: '1 verdict contesté — appuie pour l\'envoyer',
    );
    return '$_temp0';
  }

  @override
  String get settingsExportCancelled =>
      'Export annulé ou aucun clip disponible.';

  @override
  String get settingsSectionDisplay => 'Affichage';

  @override
  String get settingsTajweedColorsTitle => 'Couleurs Tajweed';

  @override
  String get settingsTajweedColorsSubtitle =>
      'Coloration selon les règles de récitation';

  @override
  String get settingsSectionApp => 'Application';

  @override
  String get settingsLocaleTitle => 'Langue de l\'application';

  @override
  String get settingsLocaleSheetDescription =>
      'En arabe, tout le contenu (menus et Coran) reste en arabe, sans traduction. En français/anglais, le Coran reste toujours en arabe ; seuls les menus et les explications changent de langue.';

  @override
  String get settingsAboutSubtitle =>
      'Version, sources, licences et confidentialité';

  @override
  String get settingsValidate => 'Valider';

  @override
  String get settingsRepeatEngineSectionTitle => 'RÉPÉTITION INCRÉMENTALE';

  @override
  String get settingsAdultChunkWordCountTitle =>
      'Mots par palier (mode Adulte)';

  @override
  String settingsAdultChunkWordCountDescription(int max) {
    return 'Approxime une ligne du Mushaf (1 à $max mots). Sans effet en mode Enfant, toujours mot par mot.';
  }

  @override
  String get settingsRepeatWindowSizeTitle => 'Fenêtre de récitation (curseur)';

  @override
  String settingsRepeatWindowSizeDescription(int max) {
    return 'Nombre de paliers à réciter ensemble pour valider (1 à $max). Cette taille reste fixe, la fenêtre glisse au fil des paliers.';
  }

  @override
  String get commonConnectionRequired => 'Connexion requise';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get homeIdentifyTooltip => 'Identifier une récitation';

  @override
  String get homeFollowPrayerTooltip => 'Suivre une prière';

  @override
  String get surahMeccan => 'Mecquoise';

  @override
  String get surahMedinan => 'Médinoise';

  @override
  String surahMetaLine(int count, String place) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '1 verset',
    );
    return '$_temp0 • $place';
  }

  @override
  String mushafExplanationTitleSurahVerse(String surah, int ayah) {
    return '$surah — verset $ayah';
  }

  @override
  String mushafExplanationTitleSurahVerseWord(
    String surah,
    int ayah,
    String word,
  ) {
    return '$surah $ayah — $word';
  }

  @override
  String get mushafPlay => 'Lire';

  @override
  String get mushafPause => 'Pause';

  @override
  String get mushafFavorites => 'Signet';

  @override
  String get mushafMemorize => 'Mémoriser';

  @override
  String get mushafTranslation => 'Trad.';

  @override
  String get mushafCoachAi => 'Coach IA';

  @override
  String get mushafMore => 'Plus';

  @override
  String get mushafAutoScroll => 'Défilement auto';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonClose => 'Fermer';

  @override
  String get shazamListening =>
      'Écoute en cours...\nApproche le téléphone du son.';

  @override
  String get shazamSearching => 'Recherche dans le Coran...';

  @override
  String get shazamFound => 'Passage identifié !';

  @override
  String get shazamNotFound =>
      'Passage non identifié.\nRapproche-toi du son et réessaie.';

  @override
  String get shazamError => 'Erreur pendant l\'écoute.';

  @override
  String shazamMatchLabel(int surah, int ayah) {
    return 'Sourate $surah, verset $ayah';
  }

  @override
  String get shazamGoThere => 'Y aller';

  @override
  String get readingSettingsDisplaySection => 'AFFICHAGE';

  @override
  String get readingSettingsAutoScrollSection => 'DÉFILEMENT AUTOMATIQUE';

  @override
  String get readingSettingsAutoScrollDescription =>
      'Le texte défile tout seul à la vitesse choisie — pratique pour lire sans les mains. Un glissement manuel l\'arrête.';

  @override
  String get readingSettingsPlaybackSpeedSection =>
      'VITESSE DE LECTURE (AUDIO)';

  @override
  String get readingSettingsRepeatSection => 'RÉPÉTITION / BOUCLES';

  @override
  String get readingSettingsRepeatDescription =>
      'Répète chaque verset (ou toute la sourate) en boucle avant de passer au suivant.';

  @override
  String get readingSettingsRepeatOff => 'Désactivé';

  @override
  String readingSettingsRepeatVerseCount(int count) {
    return 'Verset × $count';
  }

  @override
  String get readingSettingsRepeatVerseInfinite => 'Verset × ∞';

  @override
  String get readingSettingsRepeatSurah => 'Sourate entière';

  @override
  String get readingSettingsSpeedOff => 'Arrêté';

  @override
  String get readingSettingsSpeedSlow => 'Lent';

  @override
  String get readingSettingsSpeedNormal => 'Normal';

  @override
  String get readingSettingsSpeedFast => 'Rapide';

  @override
  String get readingSettingsKindleSection => 'MODE KINDLE';

  @override
  String get readingSettingsKindleDescription =>
      'Thème reposant, sans lumière bleue : navigation par pages, comme une liseuse.';

  @override
  String get readingSettingsKindleToggle => 'Activer le mode Kindle';

  @override
  String get readingSettingsKindleAutoTurn =>
      'Tourner les pages automatiquement';

  @override
  String readingSettingsKindleSpeed(int seconds) {
    return 'Vitesse : $seconds s / page';
  }

  @override
  String get coachExplanationListen => 'Écouter';

  @override
  String get coachExplanationStop => 'Arrêter';

  @override
  String get coachExplanationLanguageTooltip => 'Langue';

  @override
  String coachExplanationError(String error) {
    return 'Erreur : $error';
  }

  @override
  String coachExplanationRoot(String root) {
    return 'Racine : $root';
  }

  @override
  String get coachExplanationExpand => 'Approfondir';

  @override
  String get coachExplanationNoneAvailable =>
      'Aucune explication disponible pour ce passage sur cet appareil.';

  @override
  String tajwidHelpVerseLabel(String key) {
    return 'Verset $key';
  }

  @override
  String get tajwidHelpRulesInVerse => 'RÈGLES DANS CE VERSET';

  @override
  String tajwidHelpListenWithReciter(String name) {
    return 'Écouter — $name';
  }

  @override
  String get tajwidHelpListenPronunciation => 'ÉCOUTER LA PRONONCIATION';

  @override
  String get tajwidHelpThisWord => 'Ce mot';

  @override
  String get tajwidHelpPlusPrevious => '+ mot précédent';

  @override
  String get tajwidHelpPlusBoth => '+ précédent et suivant';

  @override
  String get tajwidHelpPlaying => 'Lecture…';

  @override
  String get tajwidHelpVoiceFeedbackPrompt => 'L\'app a-t-elle bien entendu ?';

  @override
  String get tajwidHelpVoiceFeedbackNeedsListen =>
      'Écoute « Ma voix » ci-dessus pour donner ton avis';

  @override
  String get tajwidHelpVoiceThumbsUp => 'D\'accord, c\'est une vraie erreur';

  @override
  String get tajwidHelpVoiceThumbsDown => 'Pas d\'accord, je l\'ai bien dit';

  @override
  String get tajwidHelpVoiceFeedbackThanks => 'Merci, c\'est noté';

  @override
  String get tajwidHelpRetryThisWord => 'RÉESSAYER CE MOT';

  @override
  String tajwidHelpCorrectedHeard(String text) {
    return 'Corrigé — entendu : \"$text\"';
  }

  @override
  String get tajwidHelpNothingHeard => '(rien entendu)';

  @override
  String tajwidHelpNotYetHeard(String text) {
    return 'Pas encore — entendu : \"$text\". Réessaie, à ton rythme.';
  }

  @override
  String get tajwidHelpAnalyzing => 'Analyse en cours…';

  @override
  String get tajwidHelpFinishRecording => 'Terminer l\'enregistrement';

  @override
  String get tajwidHelpRecordThisWord => 'S\'enregistrer sur ce mot';

  @override
  String get tajwidRuleMaddaNecessaryName => 'Madd — 6 temps (obligatoire)';

  @override
  String get tajwidRuleMaddaNecessaryExplanation =>
      'Allongement obligatoire de 6 temps (madd lâzim).';

  @override
  String get tajwidRuleMaddaObligatoryName =>
      'Madd — 4 ou 5 temps (obligatoire)';

  @override
  String get tajwidRuleMaddaObligatoryExplanation =>
      'Allongement obligatoire de 4 à 5 temps.';

  @override
  String get tajwidRuleMaddaPermissibleName =>
      'Madd — 2, 4 ou 6 temps (permis)';

  @override
  String get tajwidRuleMaddaPermissibleExplanation =>
      'Allongement de 2, 4 ou 6 temps selon l\'école de lecture.';

  @override
  String get tajwidRuleGhunnahName => 'Ghunna / Ikhfâ\'';

  @override
  String get tajwidRuleGhunnahExplanation =>
      'Son nasal tenu environ 2 temps (noûn/mîm doublé), ou dissimulation avec nasalisation.';

  @override
  String get tajwidRuleIkhafaName => 'Ikhfâ\' (dissimulation)';

  @override
  String get tajwidRuleIkhafaExplanation =>
      'Le noûn sâkin/tanwîn se prononce \"caché\", entre le noûn et la lettre suivante, avec nasalisation.';

  @override
  String get tajwidRuleIkhafaShafawiName => 'Ikhfâ\' shafawî';

  @override
  String get tajwidRuleIkhafaShafawiExplanation =>
      'Le mîm sâkin devant bâ\' se prononce légèrement dissimulé, avec nasalisation.';

  @override
  String get tajwidRuleIdghamGhunnahName => 'Idghâm avec ghunna';

  @override
  String get tajwidRuleIdghamGhunnahExplanation =>
      'Le noûn sâkin/tanwîn s\'assimile à la lettre suivante (ي ن م و) avec nasalisation.';

  @override
  String get tajwidRuleIdghamShafawiName => 'Idghâm shafawî';

  @override
  String get tajwidRuleIdghamShafawiExplanation =>
      'Le mîm sâkin s\'assimile au mîm suivant, avec nasalisation.';

  @override
  String get tajwidRuleIqlabName => 'Iqlâb (conversion)';

  @override
  String get tajwidRuleIqlabExplanation =>
      'Le noûn sâkin/tanwîn devient mîm devant la lettre bâ\', avec nasalisation.';

  @override
  String get tajwidRuleIdghamWoGhunnahName => 'Idghâm sans ghunna';

  @override
  String get tajwidRuleIdghamWoGhunnahExplanation =>
      'Le noûn sâkin/tanwîn s\'assimile complètement à la lettre suivante (ل ر), sans nasalisation.';

  @override
  String get tajwidRuleIdghamMutajanisaynName => 'Idghâm mutajânisayn';

  @override
  String get tajwidRuleIdghamMutajanisaynExplanation =>
      'Deux lettres de même point d\'articulation : la première s\'assimile à la seconde.';

  @override
  String get tajwidRuleIdghamMutaqaribaynName => 'Idghâm mutaqâribayn';

  @override
  String get tajwidRuleIdghamMutaqaribaynExplanation =>
      'Deux lettres proches : la première s\'assimile à la seconde.';

  @override
  String get tajwidRuleQalaqahName => 'Qalqala (rebond)';

  @override
  String get tajwidRuleQalaqahExplanation =>
      'Rebond sonore sur ق ط ب ج د quand elles portent un soukoûn.';

  @override
  String get tajwidRuleHamWaslName => 'Hamzat al-wasl';

  @override
  String get tajwidRuleHamWaslExplanation =>
      'Ne se prononce qu\'en début de lecture — s\'élide quand on enchaîne depuis le mot précédent.';

  @override
  String get tajwidRuleLaamShamsiyahName => 'Lâm solaire';

  @override
  String get tajwidRuleLaamShamsiyahExplanation =>
      'Le lâm de \"ال\" ne se prononce pas : la lettre suivante est doublée à la place.';

  @override
  String get tajwidRuleSlntName => 'Lettre muette';

  @override
  String get tajwidRuleSlntExplanation => 'S\'écrit mais ne se prononce pas.';

  @override
  String get duasScreenTitle => 'Invocations & Adhkar';

  @override
  String get duasSearchHint => 'Chercher une invocation, un mot, une source…';

  @override
  String get duasExplore => 'Explorer';

  @override
  String get duasMyFavorites => 'Mes favoris';

  @override
  String get duasNow => 'MAINTENANT';

  @override
  String get duasGuideBadge => 'GUIDE';

  @override
  String get duasNoneFound => 'Aucun résultat.';

  @override
  String duasInvocationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count invocations',
      one: '1 invocation',
    );
    return '$_temp0';
  }

  @override
  String get duaRemoveFavorite => 'Retirer des favoris';

  @override
  String get duaAddFavorite => 'Mettre en favori';

  @override
  String duaPlaybackError(String error) {
    return 'Lecture impossible : $error';
  }

  @override
  String get duaHideVirtue => 'Masquer le mérite';

  @override
  String get duaShowVirtue => 'Pourquoi la dire';

  @override
  String duaRepeatComplete(int target) {
    return 'Terminé — $target/$target';
  }

  @override
  String get duaResetCount => 'Recommencer le compte';

  @override
  String get duaCollectionEmpty => 'Cette collection est encore vide.';

  @override
  String get duaSequencePlayAll => 'Lire tout';

  @override
  String get duaSequenceNoneAudio =>
      'Aucune invocation audio dans cette liste — seules les invocations coraniques ont un enregistrement.';

  @override
  String duaSequenceProgress(int index, int total) {
    return 'Invocation $index/$total';
  }

  @override
  String get duaSequenceStop => 'Arrêter la lecture';

  @override
  String get duaSequenceSkip => 'Invocation suivante';

  @override
  String coachSurahLabel(int number) {
    return 'Sourate $number';
  }

  @override
  String get coachHeaderLabel => 'COACH MÉMORISATION';

  @override
  String get coachVerificationModeTooltip => 'Mode de vérification';

  @override
  String get coachStepLecture => 'Lecture';

  @override
  String get coachStepTrain => 'Entraîne';

  @override
  String get coachStepControl => 'Contrôle';

  @override
  String get coachReadAloudInstruction =>
      'Lis ce verset à voix haute — l\'app détecte les mots difficiles et mémorise ta voix.';

  @override
  String get coachListeningLecture => 'Je note les mots difficiles…';

  @override
  String get coachDoneLecture => 'Lecture analysée';

  @override
  String get coachTapToRead => 'Appuie et lis le verset';

  @override
  String get coachAlreadyKnow => 'Je sais déjà';

  @override
  String get coachTrainButton => 'S\'entraîner';

  @override
  String get coachSubStepListen => 'Écoute';

  @override
  String get coachSubStepImitate => 'Imite';

  @override
  String get coachSubStepRepeat => 'Répète';

  @override
  String get coachListenInstruction =>
      'Écoute le récitateur. Suis chaque mot avec les yeux.';

  @override
  String get coachListeningAudio => 'Écoute en cours…';

  @override
  String get coachTapToListen => 'Appuie pour écouter';

  @override
  String get coachMoveToImitation => 'Passons à l\'imitation';

  @override
  String get coachImitateInstruction =>
      'Lance l\'audio et parle en même temps. Copie le rythme, les pauses, l\'intonation.';

  @override
  String get coachSpeakAlong => 'Parle en même temps que l\'audio';

  @override
  String get coachLaunchAndImitate => 'Lance l\'audio et imite';

  @override
  String get coachImitatedNext => 'J\'ai imité — Répéter seul';

  @override
  String get coachIncrementalInstruction =>
      'Écoute puis répète. Le palier grandit à chaque réussite.';

  @override
  String get coachIncrementalPreparing => 'Préparation…';

  @override
  String get coachIncrementalListening => 'Écoute en cours…';

  @override
  String get coachIncrementalTapToStart => 'Appuie pour réessayer';

  @override
  String coachIncrementalUnitProgress(int done, int total) {
    return 'Palier $done/$total';
  }

  @override
  String get coachIncrementalVerseAdvance => 'Verset suivant';

  @override
  String get coachRecallInstruction =>
      'Récite de mémoire — le texte est masqué.';

  @override
  String get coachRecallBadge => 'Récite de mémoire';

  @override
  String get coachListeningControl => 'Récite de mémoire…';

  @override
  String get coachControlDone => 'Récitation terminée';

  @override
  String get coachTapToRecall => 'Appuie et récite de mémoire';

  @override
  String get coachBackToTraining => 'Retour entraînement';

  @override
  String get coachTranscriptLabel => 'TRANSCRIPT MODÈLE';

  @override
  String get coachAnalyzingAudio => 'Analyse Whisper en cours…';

  @override
  String coachAccuracyPercent(int pct) {
    return '$pct% de précision';
  }

  @override
  String coachFingerprintScore(int pct) {
    return 'Empreinte vocale : $pct%';
  }

  @override
  String get coachMemorizedConfirmed => 'Mémorisation confirmée !';

  @override
  String get coachKeepTraining => 'Continue à t\'entraîner';

  @override
  String coachGapSummary(int baseline, int control, String delta) {
    return '1ère lecture : $baseline%  →  De mémoire : $control%  ($delta%)';
  }

  @override
  String get coachMsgLectureExcellent =>
      'Excellente lecture ! Tu maîtrises bien la prononciation de ce verset.';

  @override
  String coachMsgLectureDifficultWords(String words) {
    return 'Ces mots t\'ont posé problème : $words\n\nConcentre-toi dessus lors de l\'entraînement.';
  }

  @override
  String get coachMsgLectureHesitant =>
      'Quelques hésitations détectées. L\'entraînement va t\'aider à les corriger.';

  @override
  String get coachMsgTrainGreat =>
      'Très bien ! Tu répètes correctement. Tu peux maintenant tester ta mémorisation sans le texte.';

  @override
  String get coachMsgTrainGoodStart =>
      'C\'est un bon début. Recommence encore une fois pour ancrer les mots hésitants.';

  @override
  String get coachMsgTrainRestart =>
      'Reprends l\'écoute et l\'imitation, puis réessaie la répétition.';

  @override
  String get coachMsgControlMashallah =>
      'Ma cha Allah ! Tu récites mieux de mémoire que lors de ta première lecture — le verset est mémorisé !';

  @override
  String get coachMsgControlVeryGood =>
      'Très bonne récitation ! Continue à réviser régulièrement pour consolider.';

  @override
  String get coachMsgControlGoodPath =>
      'Tu es sur la bonne voie. Encore quelques répétitions et le verset sera ancré.';

  @override
  String get coachMsgControlKeepTraining =>
      'Continue à t\'entraîner. Reviens à la phase lecture pour cibler les points faibles.';

  @override
  String get errorKindLettre => 'Lettre';

  @override
  String get errorKindHarakat => 'Harakat';

  @override
  String get errorKindTajwid => 'Tajwid';

  @override
  String get errorKindSkippedWord => 'Mot sauté';

  @override
  String get errorKindOubli => 'Oubli';

  @override
  String get errorKindUnknown => 'Indéterminé';

  @override
  String get coachHubTitle => 'Mon coach';

  @override
  String get coachHubResumeLabel => 'Reprendre';

  @override
  String coachHubResumeVerse(String surahName, int ayah) {
    return '$surahName — verset $ayah';
  }

  @override
  String get coachHubContinue => 'Continuer';

  @override
  String get coachHubMemorizeSectionTitle => 'MÉMORISER';

  @override
  String get coachHubMemorizeSectionSubtitle =>
      'Verset par verset, avec le micro';

  @override
  String get coachHubMemorizeSurahTitle => 'Mémoriser une sourate';

  @override
  String get coachHubMemorizeSurahSubtitle =>
      'Lecture → Apprentissage → Contrôle';

  @override
  String get coachHubPickerMemorizeTitle => 'Mémoriser';

  @override
  String get coachHubPickerMemorizeSubtitle =>
      'Choisis la sourate à travailler';

  @override
  String get coachHubReciteSurahTitle => 'Réciter une sourate';

  @override
  String get coachHubReciteSurahSubtitle =>
      'Suivi mot à mot, correction en direct';

  @override
  String get coachHubPickerReciteTitle => 'Réciter';

  @override
  String get coachHubPickerReciteSubtitle => 'Choisis la sourate à réciter';

  @override
  String get coachHubErrorsSectionTitle => 'MES ERREURS';

  @override
  String get coachHubErrorsSectionSubtitle => 'Par type, puis par sourate';

  @override
  String coachHubLoadErrorLog(String error) {
    return 'Impossible de charger le journal : $error';
  }

  @override
  String get coachHubNoErrorsTitle => 'Aucune erreur journalisée';

  @override
  String get coachHubNoErrorsBody =>
      'Récite depuis « Réciter » ou « Mémoriser » : les mots repris apparaîtront ici, regroupés par sourate.';

  @override
  String coachHubVersesTouched(int count, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '1 verset',
    );
    return '$_temp0 sur $total';
  }

  @override
  String get coachHubGoToMindMap => 'Situer dans la carte mentale';

  @override
  String coachHubAyahErrorCount(int ayah, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count erreurs',
      one: '1 erreur',
    );
    return 'Verset $ayah  ·  $_temp0';
  }

  @override
  String get coachHubExplanationTooltip => 'Explication';

  @override
  String get coachHubReviewVerseTooltip => 'Revoir ce verset';

  @override
  String get coachHubErrorNoteExplainer =>
      'Lettre et Harakat = prononciation. « Tajwid » signifie que ni les lettres ni les voyelles n\'expliquent l\'écart sur un mot porteur d\'une règle — c\'est une déduction, pas une preuve que la règle a été ratée.';

  @override
  String get coachHubRuleBreakdownTitle => 'Détail par règle de tajwid';

  @override
  String get coachHubResetErrorsTooltip =>
      'Réinitialiser le journal d\'erreurs';

  @override
  String get coachHubResetErrorsDialogTitle =>
      'Réinitialiser les statistiques ?';

  @override
  String get coachHubResetErrorsDialogBody =>
      'Tout l\'historique des erreurs (toutes sourates, tous types) sera effacé définitivement. Cette action est irréversible.';

  @override
  String get coachHubResetErrorsDialogConfirm => 'Réinitialiser';

  @override
  String get coachHubResetErrorsDialogCancel => 'Annuler';

  @override
  String get coachHubResetErrorsDone => 'Journal d\'erreurs réinitialisé.';

  @override
  String get coachHubGameSectionTitle => 'Jouer';

  @override
  String get coachHubGameSectionSubtitle =>
      'Rappel progressif, palier par palier';

  @override
  String get coachHubGameActionTitle => 'Jeu de mémorisation';

  @override
  String get coachHubGameActionSubtitle =>
      'Les mots se dévoilent un à un, à toi de réciter le reste';

  @override
  String get coachHubPickerGameTitle => 'Jeu de mémorisation';

  @override
  String get coachHubPickerGameSubtitle =>
      'Choisis la sourate à mémoriser en jouant';

  @override
  String get memorizationGameTitle => 'Jeu de mémorisation';

  @override
  String get memorizationGameRestartVerseTooltip => 'Recommencer ce verset';

  @override
  String memorizationGameVerseProgress(int current, int total) {
    return 'Verset $current sur $total';
  }

  @override
  String get memorizationGameCompleteTitle => 'Sourate terminée !';

  @override
  String memorizationGameCompleteBody(String surah) {
    return 'Tu as parcouru tous les paliers de $surah. Recommence pour renforcer ta mémorisation.';
  }

  @override
  String get memorizationGameBackToHub => 'Retour';

  @override
  String memorizationGameWordsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mots enchaînés',
      one: '1 mot enchaîné',
      zero: 'Aucun mot',
    );
    return '$_temp0';
  }

  @override
  String memorizationGameRecordLabel(int count) {
    return 'Record : $count';
  }

  @override
  String get memorizationGameNewRecord => 'Nouveau record !';

  @override
  String get memorizationGameLoadingNextPage => 'Page suivante…';

  @override
  String memorizationGameFinalScore(int count, int best) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mots enchaînés',
      one: '1 mot enchaîné',
      zero: 'Aucun mot enchaîné cette fois',
    );
    return '$_temp0 — record : $best';
  }

  @override
  String get memorizationAyahPickerTitle => 'Choisis ton départ';

  @override
  String memorizationAyahPickerSubtitle(String surah) {
    return '$surah est longue : choisis d\'abord la page où tu veux commencer';
  }

  @override
  String memorizationAyahPickerPageLabel(int page) {
    return 'Page $page';
  }

  @override
  String memorizationAyahPickerAyahSubtitle(int page) {
    return 'Page $page : choisis le verset où tu veux commencer à jouer';
  }

  @override
  String get memorizationAyahPickerBackToPages => 'Changer de page';

  @override
  String get qiblaSubtitle => 'Direction de la Mecque';

  @override
  String get qiblaEnableLocationMessage =>
      'Active la localisation pour trouver la Qibla depuis ton emplacement actuel.';

  @override
  String get qiblaEnableLocationAction => 'Activer la localisation';

  @override
  String get qiblaPermissionDeniedMessage =>
      'La localisation est refusée pour Coran Karim. Autorise-la dans les réglages du téléphone pour voir la Qibla.';

  @override
  String get qiblaOpenSettingsAction => 'Ouvrir les réglages';

  @override
  String qiblaPositionError(String error) {
    return 'Impossible de déterminer ta position : $error';
  }

  @override
  String get qiblaNoCompassMessage =>
      'Cet appareil ne possède pas de boussole. La distance jusqu\'à la Mecque reste disponible ci-dessous.';

  @override
  String get qiblaKmToMecca => 'KM JUSQU\'À LA MECQUE';

  @override
  String get qiblaFacingQibla => 'Tu fais face à la Qibla ✓';

  @override
  String get qiblaTurnPhoneHint =>
      'Tourne ton téléphone jusqu\'à ce que l\'aiguille pointe en haut';

  @override
  String get prayerFollowSensitivityTolerant => 'Tolérant';

  @override
  String get prayerFollowSensitivityStrict => 'Strict';

  @override
  String get prayerFollowSensitivityBalanced => 'Équilibré (par défaut)';

  @override
  String get prayerFollowSensitivityTitle => 'Sensibilité (suivi de prière)';

  @override
  String get prayerFollowSensitivityDescription =>
      'Réglage indépendant de celui de la récitation classique -- plus tolérant accepte des prononciations imprécises en vert, plus strict exige davantage de précision.';

  @override
  String get prayerFollowSouffleurTitle => 'Souffleur automatique';

  @override
  String prayerFollowSouffleurSubtitle(int seconds) {
    return 'Joue le mot attendu après ${seconds}s de silence -- jamais de blocage dans ce mode.';
  }

  @override
  String get prayerFollowTitle => 'Suivre une prière';

  @override
  String get prayerFollowSettingsTooltip => 'Réglages';

  @override
  String get prayerFollowWaitingFatiha => 'En attente du début d\'Al-Fatiha…';

  @override
  String get prayerFollowIdentifying =>
      'Al-Fatiha terminée -- identification de la sourate suivante…';

  @override
  String get prayerFollowListening => 'En écoute…';

  @override
  String get prayerFollowTapToStart =>
      'Appuyez sur le micro pour commencer à suivre la prière.';

  @override
  String get prayerPhaseStandby => 'En attente (rukū\'/sujūd)';

  @override
  String get prayerPhaseFatiha => 'Al-Fatiha';

  @override
  String get prayerPhaseDetecting => 'Identification…';

  @override
  String get prayerPhaseTarget => 'Sourate suivie';

  @override
  String get prayerPhaseListening => 'En écoute';

  @override
  String get prayerPhaseStopped => 'Arrêté';

  @override
  String get riteBeforeStartTooltip => 'À savoir avant de commencer';

  @override
  String get riteRestartTooltip => 'Recommencer le rite';

  @override
  String get riteWhatWeDoLabel => 'CE QUE L\'ON FAIT';

  @override
  String get riteWhatWeSayLabel => 'CE QUE L\'ON DIT ICI';

  @override
  String riteStepOfTotal(int index, int total) {
    return 'ÉTAPE $index SUR $total';
  }

  @override
  String get riteBeforeStartTitle => 'Avant de commencer';

  @override
  String get riteDisclaimer =>
      'Ce guide est un aide-mémoire, pas une fatwa. Les écoles juridiques divergent sur plusieurs détails secondaires : en cas de doute sur place, demandez à un guide qualifié ou à l\'encadrement de votre groupe.';

  @override
  String get riteResetConfirmTitle => 'Recommencer ?';

  @override
  String get riteResetConfirmBody =>
      'Les étapes validées et tous les compteurs seront remis à zéro.';

  @override
  String get riteResetConfirmAction => 'Recommencer';

  @override
  String get ritePreviousStepTooltip => 'Étape précédente';

  @override
  String get riteNextStepTooltip => 'Étape suivante';

  @override
  String get riteStepDone => 'Étape faite';

  @override
  String get riteMarkAsDone => 'Marquer comme faite';

  @override
  String get recitationModeLabel => 'Mode mémorisation';

  @override
  String recitationVerseTitle(String key) {
    return 'Verset $key';
  }

  @override
  String recitationRangeTitle(String from, String to, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '1 verset',
    );
    return '$from → $to ($_temp0)';
  }

  @override
  String recitationSegmentAnalyzing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segments en attente d\'analyse…',
      one: '1 segment en cours d\'analyse…',
    );
    return '$_temp0';
  }

  @override
  String get recitationTranscriptLabel => 'Transcript modèle';

  @override
  String get recitationStatCorrect => 'Corrects';

  @override
  String get recitationStatErrors => 'Erreurs';

  @override
  String get recitationStatAccuracy => 'Précision';

  @override
  String get recitationListeningContinuous =>
      'Récite en continu… pause naturelle = verset suivant';

  @override
  String get recitationFinalizing => 'Finalisation de l\'analyse…';

  @override
  String get recitationFinishedRestart => 'Terminé — appuie pour recommencer';

  @override
  String get recitationTapToStart =>
      'Appuie et récite (plusieurs versets d\'affilée)';

  @override
  String recitationMashallahAccuracy(String pct) {
    return 'Ma cha Allah ! $pct% de précision';
  }

  @override
  String recitationContinueAccuracy(String pct) {
    return 'Continue — $pct% de précision';
  }

  @override
  String get reciterSelectTitle => 'Choisir un réciteur';

  @override
  String get reciterSelectStreamingNote =>
      'Récitateurs intégrés. Par défaut la lecture passe par internet ; télécharge une sourate pour l\'écouter hors-ligne.';

  @override
  String get reciterSelectOfflineTitle => 'Téléchargement hors-ligne';

  @override
  String get reciterSelectOfflineSubtitle =>
      'Télécharge sourate par sourate depuis l\'icône de chaque récitateur.';

  @override
  String get voiceCalibTitle => 'Calibration voix';

  @override
  String get voiceCalibDoneTitle => 'Calibration terminée !';

  @override
  String voiceCalibDoneBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips enregistrés.',
      one: '1 clip enregistré.',
    );
    return '$_temp0 Ils rejoignent tes clips vérifiés — exporte-les depuis Réglages pour lancer la personnalisation.';
  }

  @override
  String get voiceCalibSave => 'Enregistrer';

  @override
  String voiceCalibWordProgress(int index, int total, String reference) {
    return 'Mot $index/$total — $reference';
  }

  @override
  String voiceCalibWrongInstruction(String target, String confused) {
    return 'Dis ce mot en remplaçant EXPRÈS le \"$target\" par un \"$confused\" — une faute volontaire, pas une vraie récitation.';
  }

  @override
  String get voiceCalibCorrectInstruction =>
      'Dis ce mot correctement, comme d\'habitude.';

  @override
  String get voiceCalibRecording => 'Enregistrement… touche pour arrêter';

  @override
  String get voiceCalibTapToRecord => 'Touche pour enregistrer';

  @override
  String voiceCalibSavedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips de calibration enregistrés',
      one: '1 clip de calibration enregistré',
    );
    return '$_temp0 — exporte-les depuis Réglages pour personnaliser le modèle.';
  }

  @override
  String get ruleReliableLabel => 'fiable';

  @override
  String ruleReliableLabelWithPct(int pct) {
    return 'fiable · $pct%';
  }

  @override
  String get ruleUnreliableLabel => 'peu fiable';

  @override
  String ruleUnreliableLabelWithPct(int pct) {
    return 'peu fiable · $pct%';
  }

  @override
  String get ruleNotMeasuredLabel => 'non mesurée';

  @override
  String get tajwidRulesTitle => 'Vérification de la récitation';

  @override
  String tajwidRulesLoadError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get tajwidRulesHarakatTitle => 'Harakat exigées';

  @override
  String get tajwidRulesHarakatSubtitle =>
      'Désactivé : les voyelles courtes ne comptent pas comme erreur';

  @override
  String get tajwidRulesConfusablesTitle => 'Tolérer les lettres proches';

  @override
  String get tajwidRulesConfusablesSubtitle =>
      'ص/س, ط/ت, ض/د, ذ/ز, ح/ه, ق/ك, ع/ء comptées équivalentes (mode enfant)';

  @override
  String get tajwidRulesSectionTitle => 'RÈGLES DE TAJWID';

  @override
  String get tajwidRulesSectionSubtitle =>
      'Choisissez les règles que l\'app doit vérifier pendant votre récitation.';

  @override
  String get tajwidRulesImpreciseNote =>
      'Détection encore imprécise : cette règle peut signaler un doute, mais ne validera jamais un mot en vert à elle seule.';

  @override
  String get tajwidPresetTajwid => 'Tajwid';

  @override
  String get tajwidPresetAdult => 'Adulte';

  @override
  String get tajwidPresetChild => 'Enfant';

  @override
  String surahPickerLoadVersesError(String error) {
    return 'Chargement impossible : $error';
  }

  @override
  String surahPickerLoadListError(String error) {
    return 'Impossible de charger les sourates : $error';
  }

  @override
  String surahPickerVerseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '1 verset',
    );
    return '$_temp0';
  }

  @override
  String get karaokeAudioUnavailable => 'Audio indisponible pour ce mot';

  @override
  String get karaokeRepeatIndicated => 'Répète le mot indiqué ↓';

  @override
  String get karaokeFirstRecitationTitle => 'Première récitation de ce passage';

  @override
  String get karaokeFirstRecitationBody =>
      'Veux-tu que cette récitation serve de référence pour ton rythme naturel (pauses mesurées, sans correction automatique), ou réciter normalement dès maintenant (avec correction automatique) ?';

  @override
  String get karaokeReciteNormally => 'Réciter normalement';

  @override
  String get karaokeMakeReference => 'Faire une référence';

  @override
  String karaokeReferenceNotSaved(
    int pct,
    int correct,
    int total,
    String extra,
  ) {
    return 'Référence non enregistrée : seulement $pct% des mots ont été bien reconnus ($correct/$total corrects$extra). Une référence doit refléter une récitation fiable — rapproche-toi du micro, réduis le bruit ambiant, et réessaie à ton rythme naturel.';
  }

  @override
  String karaokeUnclearSuffix(int count) {
    return ', $count imprécis';
  }

  @override
  String karaokeMissedSuffix(int count) {
    return ', $count non reconnus';
  }

  @override
  String karaokeReferenceSaved(int pct, int pauseCount) {
    return 'Ta manière de réciter ce passage est mémorisée ✓ ($pct% de reconnaissance, $pauseCount pauses apprises)';
  }

  @override
  String get karaokeVerificationSettingsTitle => 'Paramètres de vérification';

  @override
  String get karaokeVerificationModeTitle => 'Mode de vérification';

  @override
  String get karaokeVerificationModeSubtitle =>
      'Presets tajwid / adulte / enfant, 17 règles';

  @override
  String get karaokeSensitivityTitle => 'Sensibilité de la correction';

  @override
  String get karaokeSensitivityDescription =>
      'Plus tolérant : accepte des harakat/prononciations imprécises en vert. Plus strict : exige une prononciation plus proche du modèle.';

  @override
  String get karaokeEngineTitle => 'Moteur : alignement forcé (gop)';

  @override
  String get karaokeEngineActiveSubtitle =>
      'Actif — sensible aux harakat, parfois trop sévère sur certains mots';

  @override
  String get karaokeEngineInactiveSubtitle =>
      'Désactivé — comparaison texte (historique), moins fine sur les harakat';

  @override
  String get karaokeAutoCorrectionTitle => 'Correction automatique';

  @override
  String get karaokeAutoCorrectionSubtitle =>
      'Mot rouge → pause, le récitateur corrige, reprise auto';

  @override
  String get karaokeStrictnessTitle => 'Rigueur de la correction';

  @override
  String get karaokeStrictnessStrictSubtitle =>
      'Strict — rouge ET orange (imprécis) sont repris';

  @override
  String get karaokeStrictnessTolerantSubtitle =>
      'Tolérant — seul le rouge (mot faux) est repris';

  @override
  String get karaokeFollowFreeTitle => 'Suivre sans bloquer';

  @override
  String get karaokeFollowFreeOnSubtitle =>
      'Avance librement même sans reprise exacte';

  @override
  String get karaokeFollowFreeOffSubtitle =>
      'Chaque échec force à reprendre le mot';

  @override
  String get karaokeNewReferenceSnackbar =>
      'La prochaine récitation redéfinira ta référence pour ce passage.';

  @override
  String get karaokeHearExpectedWordTooltip => 'Entendre le mot attendu';

  @override
  String get karaokeResumeTooltip => 'Reprendre';

  @override
  String get karaokePauseTooltip => 'Mettre en pause';

  @override
  String get karaokeRedoReferenceTooltip =>
      'Refaire ma récitation de référence';

  @override
  String get karaokeReferenceRecordingTitle => 'Récitation de référence';

  @override
  String get karaokeReferenceRecordingBody =>
      'Première récitation de ce passage : récite à ton rythme naturel — ta manière de réciter (pauses, tempo) sera mémorisée et respectée pour toutes tes prochaines récitations.';

  @override
  String get karaokeReferenceInProgressTitle =>
      'Référence en cours d\'enregistrement';

  @override
  String get karaokeReferenceInProgressBody =>
      'Récite naturellement, à ton rythme.';

  @override
  String get karaokeHeardLabel => 'entendu';

  @override
  String get karaokeTranscriptFullTitle => 'TRANSCRIPT COMPLET';

  @override
  String get karaokeNothingHeardYet => 'Rien entendu pour l\'instant.';

  @override
  String get karaokeFinalizing => 'Finalisation…';

  @override
  String get karaokePausedHint => 'En pause — touche ⏸ pour reprendre';

  @override
  String get karaokeListeningHint =>
      'À l\'écoute — touche le cercle pour t\'arrêter';

  @override
  String get karaokeFinishedHint => 'Touche l\'écran pour recommencer';

  @override
  String get karaokeReferenceStartHint =>
      'Touche l\'écran pour enregistrer ta récitation de référence';

  @override
  String get karaokeTapToStartHint => 'Touche l\'écran pour commencer';

  @override
  String get karaokeLoadingModel => 'Chargement du modèle de récitation…';

  @override
  String get karaokeGetReady => 'Prépare-toi';

  @override
  String get karaokePreparingMicrophone => 'Préparation du micro…';

  @override
  String get karaokeGo => 'GO !';

  @override
  String get karaokeModelUnavailable =>
      'Le modèle de récitation est indisponible.';

  @override
  String get karaokeStartFailed => 'Impossible de démarrer l’écoute.';

  @override
  String karaokeSurahTransitionMeta(int number, String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '1 verset',
    );
    return '$number · $name · $_temp0';
  }

  @override
  String surahOrnamentMeta(String place, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versets',
      one: '1 verset',
    );
    return '$place · $_temp0';
  }

  @override
  String get miniPlayerRepeatOff => 'Répéter';

  @override
  String miniPlayerRepeatVerse(int count) {
    return '×$count verset';
  }

  @override
  String get miniPlayerRepeatSurah => 'Sourate ∞';

  @override
  String get mushafMindMapTooltip => 'Carte mentale';

  @override
  String get mushafPrayerNextIn => 'Dhuhr dans 2h 14m';

  @override
  String get mushafPrayerTimeLabel => 'Dhuhr 13:30';

  @override
  String mushafJuzChip(int n) {
    return 'JUZ $n';
  }

  @override
  String get settingsSectionDiagnostic => 'Diagnostic';

  @override
  String get settingsDiagnosticTitle => 'Journal et audio de diagnostic';

  @override
  String get settingsDiagnosticSubtitleOn =>
      'Actif — écrit le journal et garde les extraits audio';

  @override
  String get settingsDiagnosticSubtitleOff =>
      'Désactivé — aucune écriture pendant la récitation';

  @override
  String get reciterDownloadsTitle => 'Téléchargement hors-ligne';

  @override
  String reciterDownloadAll(String size) {
    return 'Tout télécharger ($size)';
  }

  @override
  String get reciterDownloadStop => 'Arrêter';

  @override
  String get reciterDeleteAllTitle => 'Supprimer les téléchargements';

  @override
  String get reciterDeleteAllBody =>
      'Tout l\'audio téléchargé pour ce récitateur sera effacé de l\'appareil. La lecture repassera par internet.';

  @override
  String get reciterDeleteAllConfirm => 'Supprimer';

  @override
  String reciterStorageUsed(String size, String done, String total) {
    return '$size sur cet appareil • $done/$total sourates hors-ligne';
  }

  @override
  String get reciterDownloadFailed =>
      'Échec du téléchargement — vérifie ta connexion. Ce qui est déjà téléchargé est conservé.';

  @override
  String reciterDownloadingProgress(String done, String total) {
    return 'Téléchargement… $done/$total versets';
  }

  @override
  String get reciterSurahOffline => 'Disponible hors-ligne';

  @override
  String get reciterVersesShort => 'versets';

  @override
  String get reciterBadgeOfflineFull => 'Hors-ligne';

  @override
  String reciterBadgeOfflinePartial(String done, String total) {
    return 'Hors-ligne · $done/$total';
  }

  @override
  String get reciterBadgeOnline => 'Internet';

  @override
  String reciterSelectStorageTotal(String size) {
    return '$size utilisés sur cet appareil';
  }

  @override
  String get mushafRecite => 'Réciter';

  @override
  String get mushafFromHere => 'À partir de ce verset';

  @override
  String get mushafBookmarkAdded => 'Marque-page posé';

  @override
  String get mushafBookmarkRemoved => 'Marque-page retiré';

  @override
  String get readingSettingsGroupRead => 'LIRE';

  @override
  String get readingSettingsGroupListen => 'ÉCOUTER';

  @override
  String get recitationPausedTapToResume =>
      'Micro coupé — touchez pour reprendre';

  @override
  String get tajwidHelpClose => 'Fermer';

  @override
  String get mushafBookmarksTitle => 'Mes signets';

  @override
  String get mushafNoBookmarks =>
      'Aucun signet pour l\'instant. Touchez l\'icône pour marquer le verset où vous vous êtes arrêté.';

  @override
  String get readingSettingsUnitLabel => 'Unité répétée';

  @override
  String get readingSettingsUnitVerse => 'Versets';

  @override
  String get readingSettingsUnitWord => 'Mots';

  @override
  String readingSettingsGroupSizeWords(int n) {
    return '1 — Ce qu’on répète : $n mot(s) à la fois';
  }

  @override
  String get readingSettingsWordUnitHint =>
      'La répétition au mot découpe l’audio du récitateur grâce à ses repères mot à mot. Si le récitateur choisi n’en publie pas, la lecture revient au verset.';

  @override
  String readingSettingsGroupSize(int n) {
    return '1 — Ce qu’on répète : $n verset(s) à la fois';
  }

  @override
  String readingSettingsGroupRepeats(int n) {
    return '2 — Combien de fois ce groupe : $n';
  }

  @override
  String readingSettingsGlobalRepeats(int n) {
    return '3 — Combien de fois la sourate entière : $n';
  }

  @override
  String get readingSettingsUnlimited => 'illimité';

  @override
  String get readingSettingsLoopSection => 'RÉPÉTITION ET BOUCLES';

  @override
  String get readingSettingsLoopDescription =>
      'Exemple : 3 versets répétés 3 fois, et la sourate entière reprise 3 fois.';

  @override
  String get aboutTitle => 'À propos';

  @override
  String get aboutTagline => 'Réciter le Coran, vérifié sur votre appareil.';

  @override
  String aboutVersionLine(String version, String build) {
    return 'Version $version (build $build)';
  }

  @override
  String get aboutSectionPrivacy => 'Vos données';

  @override
  String get aboutPrivacyIntro =>
      'Tout se passe sur votre téléphone : aucun compte, aucune publicité, aucun traceur.';

  @override
  String get aboutPrivacyMic =>
      'Micro — votre récitation est analysée sur l\'appareil, jamais envoyée ailleurs.';

  @override
  String get aboutPrivacyLocation =>
      'Position — pour la Qibla et les horaires de prière. Elle reste sur l\'appareil.';

  @override
  String get aboutPrivacyDiagnostic =>
      'Diagnostic — s\'il est activé dans les Réglages, des extraits audio et un journal sont conservés sur l\'appareil. Vous pouvez les supprimer à tout moment.';

  @override
  String get aboutPrivacyNetwork =>
      'Réseau — seulement pour télécharger les récitations et invocations que vous demandez.';

  @override
  String get aboutSectionAsr => 'Ce qui vérifie votre récitation';

  @override
  String get aboutAsrBody =>
      'Un modèle de reconnaissance de la parole arabe, entraîné sur des récitations, compare ce que vous dites au texte. Il peut se tromper : un mot signalé n\'est pas toujours une faute.';

  @override
  String get aboutAsrCredit =>
      'Modèle dérivé d\'un modèle NVIDIA, sous licence CC BY 4.0, modifié pour la récitation coranique.';

  @override
  String get aboutSectionAi => 'Tuteur IA';

  @override
  String get aboutAiWarning =>
      'Les explications de versets sont produites par un modèle de langage qui tourne sur votre téléphone. Il peut se tromper, omettre ou déformer. Ces textes n\'ont aucune autorité religieuse : pour toute question de compréhension ou de jurisprudence, référez-vous au Coran, à la Sunna et à des savants qualifiés.';

  @override
  String get aboutAiReportTitle => 'Signaler une réponse inappropriée';

  @override
  String aboutAiReportBody(String email) {
    return 'Écrivez-nous à $email en précisant le verset concerné et le texte affiché.';
  }

  @override
  String get aboutCopied => 'Adresse copiée';

  @override
  String get aboutSectionSources => 'Sources';

  @override
  String get aboutSourceQuran => 'Texte du Coran et récitations : Quran.com.';

  @override
  String get aboutSourceDuas => 'Audio des invocations : hisnmuslim.com.';

  @override
  String get aboutSectionLicenses => 'Licences';

  @override
  String get aboutLicensesAll => 'Voir toutes les licences';

  @override
  String get onboardingSkip => 'Passer';

  @override
  String get onboardingNext => 'Suivant';

  @override
  String get onboardingStart => 'Commencer';

  @override
  String get onboardingWelcomeTitle => 'Bienvenue';

  @override
  String get onboardingWelcomeBody =>
      'Lire, réciter et mémoriser le Coran, à votre rythme. Sans publicité, sans compte, sans être dérangé.';

  @override
  String get onboardingWelcomeDedication =>
      'Cette application est dédiée à la mémoire de mon père. Qu\'Allah lui fasse miséricorde et lui pardonne. Et qu\'Il facilite à chacun de vous la récitation et l\'apprentissage de Son Livre.';

  @override
  String get onboardingReadTitle => 'Lire le Coran';

  @override
  String get onboardingReadBody =>
      'Le Mushaf complet, avec les couleurs du tajwid pour voir les règles en lisant. Écoutez le récitateur de votre choix, posez un signet pour reprendre où vous en étiez.';

  @override
  String get onboardingReadHint =>
      'Trois ambiances de lecture : claire, sépia reposante, ou fond noir pour la nuit.';

  @override
  String get onboardingReciteTitle => 'Réciter et être corrigé';

  @override
  String get onboardingReciteBody =>
      'Récitez à voix haute : l\'application écoute et colore chaque mot au fur et à mesure. Vert, le mot est juste ; orange ou rouge, il mérite d\'être revu.';

  @override
  String get onboardingReciteHint =>
      'Un trou de mémoire ? Le souffleur vous fait entendre le mot attendu, sans jugement.';

  @override
  String get onboardingMemorizeTitle => 'Mémoriser en jouant';

  @override
  String get onboardingMemorizeBody =>
      'Le jeu de mémorisation vous fait reconstruire le texte mot après mot. La partie ne s\'arrête pas en fin de page : elle continue tant que vous enchaînez.';

  @override
  String get onboardingMemorizeHint =>
      'Votre record personnel de mots enchaînés est conservé d\'une partie à l\'autre.';

  @override
  String get onboardingCoachTitle => 'Votre coach';

  @override
  String get onboardingCoachBody =>
      'Après chaque récitation, retrouvez ce qui a coincé : les mots signalés, votre propre voix sur chacun, et la lecture du récitateur pour comparer.';

  @override
  String get onboardingCoachHint =>
      'Les erreurs sont regroupées par sourate et par règle de tajwid, pour voir ce qui revient.';

  @override
  String get onboardingDuasTitle => 'Invocations et prière';

  @override
  String get onboardingDuasBody =>
      'Les invocations du quotidien, avec leur audio et le nombre de répétitions. Les horaires de prière calculés pour votre position, l\'adhan, et la direction de la Qibla.';

  @override
  String get onboardingPrivacyTitle => 'Vos données restent chez vous';

  @override
  String get onboardingPrivacyBody =>
      'Votre récitation est analysée sur l\'appareil, elle n\'est jamais envoyée ailleurs. Aucun compte, aucune publicité, aucun traceur. Le réseau ne sert qu\'à télécharger les récitations que vous demandez.';

  @override
  String get duaPourNousTileTitle => 'Une invocation pour nous';

  @override
  String get duaPourNousTileSubtitle =>
      'Cette application est offerte, sans publicité';

  @override
  String get duaPourNousTitle => 'Une invocation';

  @override
  String get duaPourNousIntro =>
      'Cette application a été écrite pour que la récitation et l\'apprentissage du Coran vous soient plus faciles.';

  @override
  String get duaPourNousAskTitle => 'Si elle vous est utile';

  @override
  String get duaPourNousAskBody =>
      'En retour, une seule chose : une invocation. Pour mon père décédé, pour mes parents, et pour ma famille.';

  @override
  String get duaPourNousDeceasedArabic =>
      'اللَّهُمَّ اغْفِرْ لَهُ وَارْحَمْهُ، وَعَافِهِ وَاعْفُ عَنْهُ، وَأَكْرِمْ نُزُلَهُ، وَوَسِّعْ مُدْخَلَهُ';

  @override
  String get duaPourNousDeceasedTranslation =>
      'Ô Allah, pardonne-lui, fais-lui miséricorde, préserve-le et efface ses fautes ; réserve-lui un généreux accueil et élargis son entrée.';

  @override
  String get duaPourNousDeceasedSource => 'Rapporté par Muslim';

  @override
  String get duaPourNousForYouTitle => 'Et pour vous';

  @override
  String get duaPourNousForYouBody =>
      'Qu\'Allah vous facilite la récitation de Son Livre, qu\'Il affermisse sa mémorisation dans votre cœur, qu\'Il agrée votre effort et fasse de ce Coran le printemps de votre cœur et la lumière de votre poitrine.';

  @override
  String get duaPourNousForYouArabic =>
      'اللَّهُمَّ اجْعَلِ الْقُرْآنَ رَبِيعَ قَلْبِي، وَنُورَ صَدْرِي، وَجَلَاءَ حُزْنِي، وَذَهَابَ هَمِّي';

  @override
  String get duaPourNousShare => 'Partager l\'application';

  @override
  String get duaPourNousShareText =>
      'Coran Karim — lire, réciter et mémoriser le Coran, sans publicité.';

  @override
  String get navDuaPourNous => 'Dua';
}
