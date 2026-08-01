// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navQuran => 'Quran';

  @override
  String get navDuas => 'Duas';

  @override
  String get navCoach => 'Coach';

  @override
  String get navSettings => 'Settings';

  @override
  String get appTitle => 'Coran Karim';

  @override
  String mindMapAppBarTitle(String name) {
    return 'Mind map — $name';
  }

  @override
  String mindMapVerses(String range) {
    return 'Verses $range';
  }

  @override
  String mindMapAyahCountBadge(int count) {
    return '$count verses';
  }

  @override
  String get mindMapGoToVerse => 'Go to verse';

  @override
  String get mindMapThemeLabel => 'Main thread';

  @override
  String get mindMapSourcesLabel => 'Sources and caveats';

  @override
  String get mindMapNotReadyTitle => 'Coming soon';

  @override
  String mindMapNotReadyBody(String name) {
    return 'The mind map for $name (themes, branches, links to verses) is being written.';
  }

  @override
  String get mindMapCatRecits => 'Stories';

  @override
  String get mindMapCatCroyance => 'Belief';

  @override
  String get mindMapCatEschatologie => 'Afterlife';

  @override
  String get mindMapCatArgumentation => 'Argumentation';

  @override
  String get mindMapCatEthique => 'Ethics';

  @override
  String get mindMapCatLegislation => 'Legislation';

  @override
  String get mindMapCatSignes => 'Signs';

  @override
  String get mindMapCatAdoration => 'Worship';

  @override
  String get mindMapCatAutre => 'Other';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAudio => 'Audio';

  @override
  String get settingsReciterTitle => 'Reciter';

  @override
  String get settingsStyleMurattal => 'Murattal';

  @override
  String get settingsStyleMujawwad => 'Mujawwad';

  @override
  String get settingsSectionPrayer => 'Prayer';

  @override
  String get settingsQiblaTitle => 'Qibla direction';

  @override
  String get settingsQiblaSubtitle => 'Compass toward Mecca from your location';

  @override
  String get settingsSectionVoicePersonalization => 'Voice personalization';

  @override
  String get settingsVoiceCalibTitle =>
      'Voice calibration (confusable letters)';

  @override
  String get settingsVoiceCalibSubtitle =>
      'Record ~14 words deliberately said right/wrong (ص/س, ط/ت...) to fine-tune your sensitivity';

  @override
  String get settingsMyClipsTitle => 'My recitation recordings';

  @override
  String get settingsMyClipsLoading => 'Loading…';

  @override
  String get settingsMyClipsEmpty =>
      'No recordings yet — they are kept for every recitation';

  @override
  String settingsMyClipsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings kept — tap to export them',
      one: '1 recording kept — tap to export it',
    );
    return '$_temp0';
  }

  @override
  String get settingsExportStarted =>
      'Export started — choose where to send the file.';

  @override
  String get settingsExportCancelled =>
      'Export cancelled or no clip available.';

  @override
  String get settingsSectionDisplay => 'Display';

  @override
  String get settingsTajweedColorsTitle => 'Tajweed colors';

  @override
  String get settingsTajweedColorsSubtitle =>
      'Coloring based on recitation rules';

  @override
  String get settingsSectionApp => 'Application';

  @override
  String get settingsLocaleTitle => 'Application language';

  @override
  String get settingsLocaleSheetDescription =>
      'In Arabic, all content (menus and Quran) stays in Arabic, with no translation. In French/English, the Quran always stays in Arabic; only menus and explanations change language.';

  @override
  String get settingsAboutSubtitle =>
      'Version 1.0.0  •  Powered by Gemma 4 + Whisper';

  @override
  String get settingsValidate => 'Confirm';

  @override
  String get settingsRepeatEngineSectionTitle => 'INCREMENTAL REPETITION';

  @override
  String get settingsAdultChunkWordCountTitle => 'Words per step (Adult mode)';

  @override
  String settingsAdultChunkWordCountDescription(int max) {
    return 'Approximates a Mushaf line (1 to $max words). No effect in Child mode, which always stays word by word.';
  }

  @override
  String get settingsRepeatWindowSizeTitle => 'Recitation window (cursor)';

  @override
  String settingsRepeatWindowSizeDescription(int max) {
    return 'Number of steps to recite together to validate (1 to $max). This size stays fixed, the window slides forward as steps are added.';
  }

  @override
  String get commonConnectionRequired => 'Connection required';

  @override
  String get commonRetry => 'Retry';

  @override
  String get homeIdentifyTooltip => 'Identify a recitation';

  @override
  String get homeFollowPrayerTooltip => 'Follow a prayer';

  @override
  String get surahMeccan => 'Meccan';

  @override
  String get surahMedinan => 'Medinan';

  @override
  String surahMetaLine(int count, String place) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verses',
      one: '1 verse',
    );
    return '$_temp0 • $place';
  }

  @override
  String mushafExplanationTitleSurahVerse(String surah, int ayah) {
    return '$surah — verse $ayah';
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
  String get mushafPlay => 'Play';

  @override
  String get mushafPause => 'Pause';

  @override
  String get mushafFavorites => 'Favorites';

  @override
  String get mushafMemorize => 'Memorize';

  @override
  String get mushafTranslation => 'Transl.';

  @override
  String get mushafCoachAi => 'AI Coach';

  @override
  String get mushafMore => 'More';

  @override
  String get mushafAutoScroll => 'Auto-scroll';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get shazamListening =>
      'Listening...\nMove the phone closer to the sound.';

  @override
  String get shazamSearching => 'Searching the Quran...';

  @override
  String get shazamFound => 'Passage identified!';

  @override
  String get shazamNotFound =>
      'Passage not identified.\nGet closer to the sound and try again.';

  @override
  String get shazamError => 'An error occurred while listening.';

  @override
  String shazamMatchLabel(int surah, int ayah) {
    return 'Surah $surah, verse $ayah';
  }

  @override
  String get shazamGoThere => 'Go there';

  @override
  String get readingSettingsDisplaySection => 'DISPLAY';

  @override
  String get readingSettingsAutoScrollSection => 'AUTO-SCROLL';

  @override
  String get readingSettingsAutoScrollDescription =>
      'The text scrolls on its own at the chosen speed — handy for reading hands-free. A manual swipe stops it.';

  @override
  String get readingSettingsPlaybackSpeedSection => 'PLAYBACK SPEED (AUDIO)';

  @override
  String get readingSettingsRepeatSection => 'REPEAT / LOOPS';

  @override
  String get readingSettingsRepeatDescription =>
      'Repeats each verse (or the whole surah) in a loop before moving to the next.';

  @override
  String get readingSettingsRepeatOff => 'Off';

  @override
  String readingSettingsRepeatVerseCount(int count) {
    return 'Verse × $count';
  }

  @override
  String get readingSettingsRepeatVerseInfinite => 'Verse × ∞';

  @override
  String get readingSettingsRepeatSurah => 'Whole surah';

  @override
  String get readingSettingsSpeedOff => 'Stopped';

  @override
  String get readingSettingsSpeedSlow => 'Slow';

  @override
  String get readingSettingsSpeedNormal => 'Normal';

  @override
  String get readingSettingsSpeedFast => 'Fast';

  @override
  String get readingSettingsKindleSection => 'KINDLE MODE';

  @override
  String get readingSettingsKindleDescription =>
      'Restful, low blue light theme with page-based navigation, like an e-reader.';

  @override
  String get readingSettingsKindleToggle => 'Enable Kindle mode';

  @override
  String get readingSettingsKindleAutoTurn => 'Turn pages automatically';

  @override
  String readingSettingsKindleSpeed(int seconds) {
    return 'Speed: ${seconds}s / page';
  }

  @override
  String get coachExplanationListen => 'Listen';

  @override
  String get coachExplanationStop => 'Stop';

  @override
  String get coachExplanationLanguageTooltip => 'Language';

  @override
  String coachExplanationError(String error) {
    return 'Error: $error';
  }

  @override
  String coachExplanationRoot(String root) {
    return 'Root: $root';
  }

  @override
  String get coachExplanationExpand => 'Learn more';

  @override
  String get coachExplanationNoneAvailable =>
      'No explanation available for this passage on this device.';

  @override
  String tajwidHelpVerseLabel(String key) {
    return 'Verse $key';
  }

  @override
  String get tajwidHelpRulesInVerse => 'RULES IN THIS VERSE';

  @override
  String tajwidHelpListenWithReciter(String name) {
    return 'Listen — $name';
  }

  @override
  String get tajwidHelpListenPronunciation => 'LISTEN TO THE PRONUNCIATION';

  @override
  String get tajwidHelpThisWord => 'This word';

  @override
  String get tajwidHelpPlusPrevious => '+ previous word';

  @override
  String get tajwidHelpPlusBoth => '+ previous and next';

  @override
  String get tajwidHelpPlaying => 'Playing…';

  @override
  String get tajwidHelpRetryThisWord => 'RETRY THIS WORD';

  @override
  String tajwidHelpCorrectedHeard(String text) {
    return 'Corrected — heard: \"$text\"';
  }

  @override
  String get tajwidHelpNothingHeard => '(nothing heard)';

  @override
  String tajwidHelpNotYetHeard(String text) {
    return 'Not yet — heard: \"$text\". Try again, at your own pace.';
  }

  @override
  String get tajwidHelpAnalyzing => 'Analyzing…';

  @override
  String get tajwidHelpFinishRecording => 'Finish recording';

  @override
  String get tajwidHelpRecordThisWord => 'Record yourself on this word';

  @override
  String get tajwidRuleMaddaNecessaryName => 'Madd — 6 beats (mandatory)';

  @override
  String get tajwidRuleMaddaNecessaryExplanation =>
      'Mandatory elongation of 6 beats (madd lazim).';

  @override
  String get tajwidRuleMaddaObligatoryName => 'Madd — 4 or 5 beats (mandatory)';

  @override
  String get tajwidRuleMaddaObligatoryExplanation =>
      'Mandatory elongation of 4 to 5 beats.';

  @override
  String get tajwidRuleMaddaPermissibleName =>
      'Madd — 2, 4 or 6 beats (permitted)';

  @override
  String get tajwidRuleMaddaPermissibleExplanation =>
      'Elongation of 2, 4 or 6 beats depending on the reading school.';

  @override
  String get tajwidRuleGhunnahName => 'Ghunnah / Ikhfa\'';

  @override
  String get tajwidRuleGhunnahExplanation =>
      'Nasal sound held about 2 beats (doubled noon/meem), or concealment with nasalization.';

  @override
  String get tajwidRuleIkhafaName => 'Ikhfa\' (concealment)';

  @override
  String get tajwidRuleIkhafaExplanation =>
      'The sakin noon/tanween is pronounced \"hidden\", between the noon and the next letter, with nasalization.';

  @override
  String get tajwidRuleIkhafaShafawiName => 'Ikhfa\' shafawi';

  @override
  String get tajwidRuleIkhafaShafawiExplanation =>
      'The sakin meem before ba\' is pronounced slightly concealed, with nasalization.';

  @override
  String get tajwidRuleIdghamGhunnahName => 'Idgham with ghunnah';

  @override
  String get tajwidRuleIdghamGhunnahExplanation =>
      'The sakin noon/tanween merges into the next letter (ي ن م و) with nasalization.';

  @override
  String get tajwidRuleIdghamShafawiName => 'Idgham shafawi';

  @override
  String get tajwidRuleIdghamShafawiExplanation =>
      'The sakin meem merges into the following meem, with nasalization.';

  @override
  String get tajwidRuleIqlabName => 'Iqlab (conversion)';

  @override
  String get tajwidRuleIqlabExplanation =>
      'The sakin noon/tanween turns into meem before the letter ba\', with nasalization.';

  @override
  String get tajwidRuleIdghamWoGhunnahName => 'Idgham without ghunnah';

  @override
  String get tajwidRuleIdghamWoGhunnahExplanation =>
      'The sakin noon/tanween fully merges into the next letter (ل ر), without nasalization.';

  @override
  String get tajwidRuleIdghamMutajanisaynName => 'Idgham mutajanisayn';

  @override
  String get tajwidRuleIdghamMutajanisaynExplanation =>
      'Two letters with the same articulation point: the first merges into the second.';

  @override
  String get tajwidRuleIdghamMutaqaribaynName => 'Idgham mutaqaribayn';

  @override
  String get tajwidRuleIdghamMutaqaribaynExplanation =>
      'Two letters with close articulation points: the first merges into the second.';

  @override
  String get tajwidRuleQalaqahName => 'Qalqalah (bounce)';

  @override
  String get tajwidRuleQalaqahExplanation =>
      'Sound bounce on ق ط ب ج د when they carry a sukoon.';

  @override
  String get tajwidRuleHamWaslName => 'Hamzat al-wasl';

  @override
  String get tajwidRuleHamWaslExplanation =>
      'Only pronounced at the start of reading — elided when linking from the previous word.';

  @override
  String get tajwidRuleLaamShamsiyahName => 'Sun lam';

  @override
  String get tajwidRuleLaamShamsiyahExplanation =>
      'The lam of \"ال\" is not pronounced: the next letter is doubled instead.';

  @override
  String get tajwidRuleSlntName => 'Silent letter';

  @override
  String get tajwidRuleSlntExplanation => 'Written but not pronounced.';

  @override
  String get duasScreenTitle => 'Duas & Adhkar';

  @override
  String get duasSearchHint => 'Search an invocation, a word, a source…';

  @override
  String get duasExplore => 'Explore';

  @override
  String get duasMyFavorites => 'My favorites';

  @override
  String get duasNow => 'NOW';

  @override
  String get duasGuideBadge => 'GUIDE';

  @override
  String get duasNoneFound => 'No results.';

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
  String get duaRemoveFavorite => 'Remove from favorites';

  @override
  String get duaAddFavorite => 'Add to favorites';

  @override
  String duaPlaybackError(String error) {
    return 'Playback failed: $error';
  }

  @override
  String get duaHideVirtue => 'Hide the virtue';

  @override
  String get duaShowVirtue => 'Why say it';

  @override
  String duaRepeatComplete(int target) {
    return 'Done — $target/$target';
  }

  @override
  String get duaResetCount => 'Reset the count';

  @override
  String get duaCollectionEmpty => 'This collection is still empty.';

  @override
  String coachSurahLabel(int number) {
    return 'Surah $number';
  }

  @override
  String get coachHeaderLabel => 'MEMORIZATION COACH';

  @override
  String get coachVerificationModeTooltip => 'Verification mode';

  @override
  String get coachStepLecture => 'Read';

  @override
  String get coachStepTrain => 'Train';

  @override
  String get coachStepControl => 'Test';

  @override
  String get coachReadAloudInstruction =>
      'Read this verse aloud — the app detects difficult words and memorizes your voice.';

  @override
  String get coachListeningLecture => 'Noting difficult words…';

  @override
  String get coachDoneLecture => 'Reading analyzed';

  @override
  String get coachTapToRead => 'Tap and read the verse';

  @override
  String get coachAlreadyKnow => 'I already know it';

  @override
  String get coachTrainButton => 'Train';

  @override
  String get coachSubStepListen => 'Listen';

  @override
  String get coachSubStepImitate => 'Imitate';

  @override
  String get coachSubStepRepeat => 'Repeat';

  @override
  String get coachListenInstruction =>
      'Listen to the reciter. Follow each word with your eyes.';

  @override
  String get coachListeningAudio => 'Listening…';

  @override
  String get coachTapToListen => 'Tap to listen';

  @override
  String get coachMoveToImitation => 'Move on to imitation';

  @override
  String get coachImitateInstruction =>
      'Play the audio and speak at the same time. Copy the rhythm, the pauses, the intonation.';

  @override
  String get coachSpeakAlong => 'Speak along with the audio';

  @override
  String get coachLaunchAndImitate => 'Play the audio and imitate';

  @override
  String get coachImitatedNext => 'I imitated it — Repeat alone';

  @override
  String get coachIncrementalInstruction =>
      'Listen then repeat. The step grows with each success.';

  @override
  String get coachIncrementalPreparing => 'Preparing…';

  @override
  String get coachIncrementalListening => 'Listening…';

  @override
  String get coachIncrementalTapToStart => 'Tap to try again';

  @override
  String coachIncrementalUnitProgress(int done, int total) {
    return 'Step $done/$total';
  }

  @override
  String get coachIncrementalVerseAdvance => 'Next verse';

  @override
  String get coachRecallInstruction =>
      'Recite from memory — the text is hidden.';

  @override
  String get coachRecallBadge => 'Recite from memory';

  @override
  String get coachListeningControl => 'Reciting from memory…';

  @override
  String get coachControlDone => 'Recitation finished';

  @override
  String get coachTapToRecall => 'Tap and recite from memory';

  @override
  String get coachBackToTraining => 'Back to training';

  @override
  String get coachTranscriptLabel => 'MODEL TRANSCRIPT';

  @override
  String get coachAnalyzingAudio => 'Analyzing…';

  @override
  String coachAccuracyPercent(int pct) {
    return '$pct% accuracy';
  }

  @override
  String coachFingerprintScore(int pct) {
    return 'Voice fingerprint: $pct%';
  }

  @override
  String get coachMemorizedConfirmed => 'Memorization confirmed!';

  @override
  String get coachKeepTraining => 'Keep training';

  @override
  String coachGapSummary(int baseline, int control, String delta) {
    return '1st reading: $baseline%  →  From memory: $control%  ($delta%)';
  }

  @override
  String get coachMsgLectureExcellent =>
      'Excellent reading! You handle the pronunciation of this verse well.';

  @override
  String coachMsgLectureDifficultWords(String words) {
    return 'These words gave you trouble: $words\n\nFocus on them during training.';
  }

  @override
  String get coachMsgLectureHesitant =>
      'A few hesitations detected. Training will help you fix them.';

  @override
  String get coachMsgTrainGreat =>
      'Very good! You\'re repeating correctly. You can now test your memorization without the text.';

  @override
  String get coachMsgTrainGoodStart =>
      'That\'s a good start. Go through it once more to anchor the hesitant words.';

  @override
  String get coachMsgTrainRestart =>
      'Go back to listening and imitating, then try repeating again.';

  @override
  String get coachMsgControlMashallah =>
      'Ma sha Allah! You recite better from memory than on your first reading — the verse is memorized!';

  @override
  String get coachMsgControlVeryGood =>
      'Very good recitation! Keep reviewing regularly to consolidate it.';

  @override
  String get coachMsgControlGoodPath =>
      'You\'re on the right track. A few more repetitions and the verse will be anchored.';

  @override
  String get coachMsgControlKeepTraining =>
      'Keep training. Go back to the reading phase to target the weak points.';

  @override
  String get errorKindLettre => 'Letter';

  @override
  String get errorKindHarakat => 'Harakat';

  @override
  String get errorKindTajwid => 'Tajwid';

  @override
  String get errorKindSkippedWord => 'Skipped word';

  @override
  String get errorKindUnknown => 'Undetermined';

  @override
  String get coachHubTitle => 'My coach';

  @override
  String get coachHubResumeLabel => 'Resume';

  @override
  String coachHubResumeVerse(String surahName, int ayah) {
    return '$surahName — verse $ayah';
  }

  @override
  String get coachHubContinue => 'Continue';

  @override
  String get coachHubMemorizeSectionTitle => 'MEMORIZE';

  @override
  String get coachHubMemorizeSectionSubtitle =>
      'Verse by verse, with the microphone';

  @override
  String get coachHubMemorizeSurahTitle => 'Memorize a surah';

  @override
  String get coachHubMemorizeSurahSubtitle => 'Reading → Training → Test';

  @override
  String get coachHubPickerMemorizeTitle => 'Memorize';

  @override
  String get coachHubPickerMemorizeSubtitle => 'Choose the surah to work on';

  @override
  String get coachHubReciteSurahTitle => 'Recite a surah';

  @override
  String get coachHubReciteSurahSubtitle =>
      'Word-by-word tracking, live correction';

  @override
  String get coachHubPickerReciteTitle => 'Recite';

  @override
  String get coachHubPickerReciteSubtitle => 'Choose the surah to recite';

  @override
  String get coachHubErrorsSectionTitle => 'MY MISTAKES';

  @override
  String get coachHubErrorsSectionSubtitle => 'By type, then by surah';

  @override
  String coachHubLoadErrorLog(String error) {
    return 'Couldn\'t load the log: $error';
  }

  @override
  String get coachHubNoErrorsTitle => 'No errors logged';

  @override
  String get coachHubNoErrorsBody =>
      'Recite from \"Recite\" or \"Memorize\": the words you retry will appear here, grouped by surah.';

  @override
  String coachHubVersesTouched(int count, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verses',
      one: '1 verse',
    );
    return '$_temp0 out of $total';
  }

  @override
  String get coachHubGoToMindMap => 'Locate in the mind map';

  @override
  String coachHubAyahErrorCount(int ayah, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errors',
      one: '1 error',
    );
    return 'Verse $ayah  ·  $_temp0';
  }

  @override
  String get coachHubExplanationTooltip => 'Explanation';

  @override
  String get coachHubReviewVerseTooltip => 'Review this verse';

  @override
  String get coachHubErrorNoteExplainer =>
      'Letter and Harakat = pronunciation. \"Tajwid\" means that neither the letters nor the vowels explain the gap on a word carrying a rule — it\'s a deduction, not proof that the rule was missed.';

  @override
  String get coachHubRuleBreakdownTitle => 'Breakdown by tajwid rule';

  @override
  String get coachHubResetErrorsTooltip => 'Reset error log';

  @override
  String get coachHubResetErrorsDialogTitle => 'Reset statistics?';

  @override
  String get coachHubResetErrorsDialogBody =>
      'All error history (every surah, every type) will be permanently erased. This action cannot be undone.';

  @override
  String get coachHubResetErrorsDialogConfirm => 'Reset';

  @override
  String get coachHubResetErrorsDialogCancel => 'Cancel';

  @override
  String get coachHubResetErrorsDone => 'Error log reset.';

  @override
  String get coachHubGameSectionTitle => 'Play';

  @override
  String get coachHubGameSectionSubtitle => 'Progressive recall, tier by tier';

  @override
  String get coachHubGameActionTitle => 'Memorization game';

  @override
  String get coachHubGameActionSubtitle =>
      'Words appear one by one — recite the rest yourself';

  @override
  String get coachHubPickerGameTitle => 'Memorization game';

  @override
  String get coachHubPickerGameSubtitle =>
      'Choose the surah to memorize by playing';

  @override
  String get memorizationGameTitle => 'Memorization game';

  @override
  String get memorizationGameRestartVerseTooltip => 'Restart this verse';

  @override
  String memorizationGameVerseProgress(int current, int total) {
    return 'Verse $current of $total';
  }

  @override
  String get memorizationGameCompleteTitle => 'Surah complete!';

  @override
  String memorizationGameCompleteBody(String surah) {
    return 'You went through every tier of $surah. Restart to reinforce your memorization.';
  }

  @override
  String get memorizationGameBackToHub => 'Back';

  @override
  String get memorizationAyahPickerTitle => 'Choose your start';

  @override
  String memorizationAyahPickerSubtitle(String surah) {
    return '$surah is long: choose the page where you want to start first';
  }

  @override
  String memorizationAyahPickerPageLabel(int page) {
    return 'Page $page';
  }

  @override
  String memorizationAyahPickerAyahSubtitle(int page) {
    return 'Page $page: choose the verse where you want to start playing';
  }

  @override
  String get memorizationAyahPickerBackToPages => 'Change page';

  @override
  String get qiblaSubtitle => 'Direction to Mecca';

  @override
  String get qiblaEnableLocationMessage =>
      'Enable location to find the Qibla from your current position.';

  @override
  String get qiblaEnableLocationAction => 'Enable location';

  @override
  String get qiblaPermissionDeniedMessage =>
      'Location is denied for Coran Karim. Allow it in the phone settings to see the Qibla.';

  @override
  String get qiblaOpenSettingsAction => 'Open settings';

  @override
  String qiblaPositionError(String error) {
    return 'Couldn\'t determine your position: $error';
  }

  @override
  String get qiblaNoCompassMessage =>
      'This device doesn\'t have a compass. The distance to Mecca is still available below.';

  @override
  String get qiblaKmToMecca => 'KM TO MECCA';

  @override
  String get qiblaFacingQibla => 'You\'re facing the Qibla ✓';

  @override
  String get qiblaTurnPhoneHint => 'Turn your phone until the needle points up';

  @override
  String get prayerFollowSensitivityTolerant => 'Tolerant';

  @override
  String get prayerFollowSensitivityStrict => 'Strict';

  @override
  String get prayerFollowSensitivityBalanced => 'Balanced (default)';

  @override
  String get prayerFollowSensitivityTitle => 'Sensitivity (prayer follow)';

  @override
  String get prayerFollowSensitivityDescription =>
      'Setting independent from regular recitation -- more tolerant accepts imprecise pronunciations as correct, more strict requires more precision.';

  @override
  String get prayerFollowSouffleurTitle => 'Automatic prompter';

  @override
  String prayerFollowSouffleurSubtitle(int seconds) {
    return 'Plays the expected word after ${seconds}s of silence -- never blocks in this mode.';
  }

  @override
  String get prayerFollowTitle => 'Follow a prayer';

  @override
  String get prayerFollowSettingsTooltip => 'Settings';

  @override
  String get prayerFollowWaitingFatiha => 'Waiting for Al-Fatiha to begin…';

  @override
  String get prayerFollowIdentifying =>
      'Al-Fatiha finished -- identifying the next surah…';

  @override
  String get prayerFollowListening => 'Listening…';

  @override
  String get prayerFollowTapToStart =>
      'Tap the microphone to start following the prayer.';

  @override
  String get prayerPhaseStandby => 'Waiting (ruku\'/sujud)';

  @override
  String get prayerPhaseFatiha => 'Al-Fatiha';

  @override
  String get prayerPhaseDetecting => 'Identifying…';

  @override
  String get prayerPhaseTarget => 'Followed surah';

  @override
  String get prayerPhaseListening => 'Listening';

  @override
  String get prayerPhaseStopped => 'Stopped';

  @override
  String get riteBeforeStartTooltip => 'Good to know before starting';

  @override
  String get riteRestartTooltip => 'Restart the ritual';

  @override
  String get riteWhatWeDoLabel => 'WHAT WE DO';

  @override
  String get riteWhatWeSayLabel => 'WHAT WE SAY HERE';

  @override
  String riteStepOfTotal(int index, int total) {
    return 'STEP $index OF $total';
  }

  @override
  String get riteBeforeStartTitle => 'Before starting';

  @override
  String get riteDisclaimer =>
      'This guide is a memory aid, not a fatwa. Legal schools differ on several secondary details: if in doubt on site, ask a qualified guide or your group\'s leaders.';

  @override
  String get riteResetConfirmTitle => 'Restart?';

  @override
  String get riteResetConfirmBody =>
      'Completed steps and all counters will be reset to zero.';

  @override
  String get riteResetConfirmAction => 'Restart';

  @override
  String get ritePreviousStepTooltip => 'Previous step';

  @override
  String get riteNextStepTooltip => 'Next step';

  @override
  String get riteStepDone => 'Step done';

  @override
  String get riteMarkAsDone => 'Mark as done';

  @override
  String get recitationModeLabel => 'Memorization mode';

  @override
  String recitationVerseTitle(String key) {
    return 'Verse $key';
  }

  @override
  String recitationRangeTitle(String from, String to, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verses',
      one: '1 verse',
    );
    return '$from → $to ($_temp0)';
  }

  @override
  String recitationSegmentAnalyzing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segments awaiting analysis…',
      one: '1 segment analyzing…',
    );
    return '$_temp0';
  }

  @override
  String get recitationTranscriptLabel => 'Model transcript';

  @override
  String get recitationStatCorrect => 'Correct';

  @override
  String get recitationStatErrors => 'Errors';

  @override
  String get recitationStatAccuracy => 'Accuracy';

  @override
  String get recitationListeningContinuous =>
      'Reciting continuously… natural pause = next verse';

  @override
  String get recitationFinalizing => 'Finalizing analysis…';

  @override
  String get recitationFinishedRestart => 'Done — tap to restart';

  @override
  String get recitationTapToStart => 'Tap and recite (several verses in a row)';

  @override
  String recitationMashallahAccuracy(String pct) {
    return 'Ma sha Allah! $pct% accuracy';
  }

  @override
  String recitationContinueAccuracy(String pct) {
    return 'Keep going — $pct% accuracy';
  }

  @override
  String get reciterSelectTitle => 'Choose a reciter';

  @override
  String get reciterSelectStreamingNote =>
      'Built-in reciters. Playback streams over the internet by default; download a surah to listen offline.';

  @override
  String get reciterSelectOfflineTitle => 'Offline download';

  @override
  String get reciterSelectOfflineSubtitle =>
      'Download surah by surah from each reciter\'s icon.';

  @override
  String get voiceCalibTitle => 'Voice calibration';

  @override
  String get voiceCalibDoneTitle => 'Calibration complete!';

  @override
  String voiceCalibDoneBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips recorded.',
      one: '1 clip recorded.',
    );
    return '$_temp0 They join your verified clips — export them from Settings to start personalization.';
  }

  @override
  String get voiceCalibSave => 'Save';

  @override
  String voiceCalibWordProgress(int index, int total, String reference) {
    return 'Word $index/$total — $reference';
  }

  @override
  String voiceCalibWrongInstruction(String target, String confused) {
    return 'Say this word deliberately replacing \"$target\" with \"$confused\" — an intentional mistake, not a real recitation.';
  }

  @override
  String get voiceCalibCorrectInstruction =>
      'Say this word correctly, as usual.';

  @override
  String get voiceCalibRecording => 'Recording… tap to stop';

  @override
  String get voiceCalibTapToRecord => 'Tap to record';

  @override
  String voiceCalibSavedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calibration clips saved',
      one: '1 calibration clip saved',
    );
    return '$_temp0 — export them from Settings to personalize the model.';
  }

  @override
  String get ruleReliableLabel => 'reliable';

  @override
  String ruleReliableLabelWithPct(int pct) {
    return 'reliable · $pct%';
  }

  @override
  String get ruleUnreliableLabel => 'not very reliable';

  @override
  String ruleUnreliableLabelWithPct(int pct) {
    return 'not very reliable · $pct%';
  }

  @override
  String get ruleNotMeasuredLabel => 'not measured';

  @override
  String get tajwidRulesTitle => 'Recitation verification';

  @override
  String tajwidRulesLoadError(String error) {
    return 'Error: $error';
  }

  @override
  String get tajwidRulesHarakatTitle => 'Harakat required';

  @override
  String get tajwidRulesHarakatSubtitle =>
      'Off: short vowels don\'t count as an error';

  @override
  String get tajwidRulesConfusablesTitle => 'Tolerate close letters';

  @override
  String get tajwidRulesConfusablesSubtitle =>
      'ص/س, ط/ت, ض/د, ذ/ز, ح/ه, ق/ك, ع/ء counted as equivalent (child mode)';

  @override
  String get tajwidRulesSectionTitle => 'TAJWID RULES';

  @override
  String get tajwidRulesSectionSubtitle =>
      'Choose the rules the app should check during your recitation.';

  @override
  String get tajwidRulesImpreciseNote =>
      'Detection is still imprecise: this rule can flag a doubt, but will never validate a word green on its own.';

  @override
  String get tajwidPresetTajwid => 'Tajwid';

  @override
  String get tajwidPresetAdult => 'Adult';

  @override
  String get tajwidPresetChild => 'Child';

  @override
  String surahPickerLoadVersesError(String error) {
    return 'Couldn\'t load: $error';
  }

  @override
  String surahPickerLoadListError(String error) {
    return 'Couldn\'t load the surahs: $error';
  }

  @override
  String surahPickerVerseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verses',
      one: '1 verse',
    );
    return '$_temp0';
  }

  @override
  String get karaokeAudioUnavailable => 'Audio unavailable for this word';

  @override
  String get karaokeRepeatIndicated => 'Repeat the indicated word ↓';

  @override
  String get karaokeFirstRecitationTitle => 'First recitation of this passage';

  @override
  String get karaokeFirstRecitationBody =>
      'Do you want this recitation to serve as a reference for your natural rhythm (measured pauses, no automatic correction), or recite normally right now (with automatic correction)?';

  @override
  String get karaokeReciteNormally => 'Recite normally';

  @override
  String get karaokeMakeReference => 'Make a reference';

  @override
  String karaokeReferenceNotSaved(
    int pct,
    int correct,
    int total,
    String extra,
  ) {
    return 'Reference not saved: only $pct% of words were correctly recognized ($correct/$total correct$extra). A reference must reflect a reliable recitation — move closer to the microphone, reduce background noise, and try again at your natural pace.';
  }

  @override
  String karaokeUnclearSuffix(int count) {
    return ', $count unclear';
  }

  @override
  String karaokeMissedSuffix(int count) {
    return ', $count unrecognized';
  }

  @override
  String karaokeReferenceSaved(int pct, int pauseCount) {
    return 'Your way of reciting this passage is memorized ✓ ($pct% recognition, $pauseCount pauses learned)';
  }

  @override
  String get karaokeVerificationSettingsTitle => 'Verification settings';

  @override
  String get karaokeVerificationModeTitle => 'Verification mode';

  @override
  String get karaokeVerificationModeSubtitle =>
      'Tajwid / adult / child presets, 17 rules';

  @override
  String get karaokeSensitivityTitle => 'Correction sensitivity';

  @override
  String get karaokeSensitivityDescription =>
      'More tolerant: accepts imprecise harakat/pronunciations as correct. Stricter: requires pronunciation closer to the model.';

  @override
  String get karaokeEngineTitle => 'Engine: forced alignment (gop)';

  @override
  String get karaokeEngineActiveSubtitle =>
      'Active — sensitive to harakat, sometimes too strict on some words';

  @override
  String get karaokeEngineInactiveSubtitle =>
      'Off — text comparison (legacy), less precise on harakat';

  @override
  String get karaokeAutoCorrectionTitle => 'Automatic correction';

  @override
  String get karaokeAutoCorrectionSubtitle =>
      'Red word → pause, the reciter corrects, auto resume';

  @override
  String get karaokeStrictnessTitle => 'Correction strictness';

  @override
  String get karaokeStrictnessStrictSubtitle =>
      'Strict — red AND orange (unclear) are retried';

  @override
  String get karaokeStrictnessTolerantSubtitle =>
      'Tolerant — only red (wrong word) is retried';

  @override
  String get karaokeFollowFreeTitle => 'Follow without blocking';

  @override
  String get karaokeFollowFreeOnSubtitle =>
      'Moves forward freely even without an exact retry';

  @override
  String get karaokeFollowFreeOffSubtitle =>
      'Every failure forces retrying the word';

  @override
  String get karaokeNewReferenceSnackbar =>
      'The next recitation will redefine your reference for this passage.';

  @override
  String get karaokeHearExpectedWordTooltip => 'Hear the expected word';

  @override
  String get karaokeResumeTooltip => 'Resume';

  @override
  String get karaokePauseTooltip => 'Pause';

  @override
  String get karaokeRedoReferenceTooltip => 'Redo my reference recitation';

  @override
  String get karaokeReferenceRecordingTitle => 'Reference recitation';

  @override
  String get karaokeReferenceRecordingBody =>
      'First recitation of this passage: recite at your natural pace — your way of reciting (pauses, tempo) will be memorized and respected for all your future recitations.';

  @override
  String get karaokeReferenceInProgressTitle => 'Recording reference';

  @override
  String get karaokeReferenceInProgressBody =>
      'Recite naturally, at your own pace.';

  @override
  String get karaokeHeardLabel => 'heard';

  @override
  String get karaokeTranscriptFullTitle => 'FULL TRANSCRIPT';

  @override
  String get karaokeNothingHeardYet => 'Nothing heard yet.';

  @override
  String get karaokeFinalizing => 'Finalizing…';

  @override
  String get karaokePausedHint => 'Paused — tap ⏸ to resume';

  @override
  String get karaokeListeningHint => 'Listening — tap the circle to stop';

  @override
  String get karaokeFinishedHint => 'Tap the screen to restart';

  @override
  String get karaokeReferenceStartHint =>
      'Tap the screen to record your reference recitation';

  @override
  String get karaokeTapToStartHint => 'Tap the screen to start';

  @override
  String get karaokeLoadingModel => 'Loading the recitation model…';

  @override
  String get karaokeGetReady => 'Get ready';

  @override
  String get karaokePreparingMicrophone => 'Preparing the microphone…';

  @override
  String get karaokeGo => 'GO!';

  @override
  String get karaokeModelUnavailable => 'The recitation model is unavailable.';

  @override
  String get karaokeStartFailed => 'Unable to start listening.';

  @override
  String karaokeSurahTransitionMeta(int number, String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verses',
      one: '1 verse',
    );
    return '$number · $name · $_temp0';
  }

  @override
  String surahOrnamentMeta(String place, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verses',
      one: '1 verse',
    );
    return '$place · $_temp0';
  }

  @override
  String get miniPlayerRepeatOff => 'Repeat';

  @override
  String miniPlayerRepeatVerse(int count) {
    return '×$count verse';
  }

  @override
  String get miniPlayerRepeatSurah => 'Surah ∞';

  @override
  String get mushafMindMapTooltip => 'Mind map';

  @override
  String get mushafPrayerNextIn => 'Dhuhr in 2h 14m';

  @override
  String get mushafPrayerTimeLabel => 'Dhuhr 13:30';

  @override
  String mushafJuzChip(int n) {
    return 'JUZ $n';
  }

  @override
  String get settingsSectionDiagnostic => 'Diagnostics';

  @override
  String get settingsDiagnosticTitle => 'Diagnostic log and audio';

  @override
  String get settingsDiagnosticSubtitleOn =>
      'On — writes the log and keeps audio clips';

  @override
  String get settingsDiagnosticSubtitleOff =>
      'Off — nothing is written while reciting';

  @override
  String get reciterDownloadsTitle => 'Offline download';

  @override
  String reciterDownloadAll(String size) {
    return 'Download all ($size)';
  }

  @override
  String get reciterDownloadStop => 'Stop';

  @override
  String get reciterDeleteAllTitle => 'Delete downloads';

  @override
  String get reciterDeleteAllBody =>
      'All downloaded audio for this reciter will be erased from the device. Playback will go back to streaming.';

  @override
  String get reciterDeleteAllConfirm => 'Delete';

  @override
  String reciterStorageUsed(String size, String done, String total) {
    return '$size on this device • $done/$total surahs offline';
  }

  @override
  String get reciterDownloadFailed =>
      'Download failed — check your connection. Files already downloaded are kept.';

  @override
  String reciterDownloadingProgress(String done, String total) {
    return 'Downloading… $done/$total verses';
  }

  @override
  String get reciterSurahOffline => 'Available offline';

  @override
  String get reciterVersesShort => 'verses';

  @override
  String get reciterBadgeOfflineFull => 'Offline';

  @override
  String reciterBadgeOfflinePartial(String done, String total) {
    return 'Offline · $done/$total';
  }

  @override
  String get reciterBadgeOnline => 'Internet';

  @override
  String reciterSelectStorageTotal(String size) {
    return '$size used on this device';
  }
}
