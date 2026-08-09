// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get navQuran => 'القرآن';

  @override
  String get navDuas => 'الأذكار';

  @override
  String get navCoach => 'مدرّبي';

  @override
  String get navSettings => 'إعدادات';

  @override
  String get appTitle => 'قرآن كريم';

  @override
  String mindMapAppBarTitle(String name) {
    return 'الخريطة الذهنية — $name';
  }

  @override
  String mindMapVerses(String range) {
    return 'الآيات $range';
  }

  @override
  String mindMapAyahCountBadge(int count) {
    return '$count آية';
  }

  @override
  String get mindMapGoToVerse => 'الانتقال إلى الآية';

  @override
  String get mindMapThemeLabel => 'الخيط الناظم';

  @override
  String get mindMapSourcesLabel => 'المصادر والتحفظات';

  @override
  String get mindMapNotReadyTitle => 'قريبًا';

  @override
  String mindMapNotReadyBody(String name) {
    return 'الخريطة الذهنية لسورة $name (المحاور والفروع وروابط الآيات) قيد الإعداد.';
  }

  @override
  String get mindMapCatRecits => 'قصص';

  @override
  String get mindMapCatCroyance => 'عقيدة';

  @override
  String get mindMapCatEschatologie => 'الآخرة';

  @override
  String get mindMapCatArgumentation => 'الجدال';

  @override
  String get mindMapCatEthique => 'أخلاق';

  @override
  String get mindMapCatLegislation => 'أحكام';

  @override
  String get mindMapCatSignes => 'آيات كونية';

  @override
  String get mindMapCatAdoration => 'عبادة';

  @override
  String get mindMapCatAutre => 'أخرى';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsSectionAudio => 'الصوت';

  @override
  String get settingsReciterTitle => 'القارئ';

  @override
  String get settingsStyleMurattal => 'مرتّل';

  @override
  String get settingsStyleMujawwad => 'مجوّد';

  @override
  String get settingsSectionPrayer => 'الصلاة';

  @override
  String get settingsQiblaTitle => 'اتجاه القبلة';

  @override
  String get settingsQiblaSubtitle => 'بوصلة نحو مكة من موقعك';

  @override
  String get settingsSectionVoicePersonalization => 'تخصيص الصوت';

  @override
  String get settingsVoiceCalibTitle => 'معايرة الصوت (الحروف المتشابهة)';

  @override
  String get settingsVoiceCalibSubtitle =>
      'سجّل نحو 14 كلمة منطوقة عمدًا بشكل صحيح/خاطئ (ص/س، ط/ت...) لضبط حساسيتك';

  @override
  String get settingsMyClipsTitle => 'تسجيلات تلاواتي';

  @override
  String get settingsMyClipsLoading => 'جارٍ التحميل…';

  @override
  String get settingsMyClipsEmpty => 'لا توجد تسجيلات — تُحفظ مع كل تلاوة';

  @override
  String settingsMyClipsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تسجيلات محفوظة — اضغط لتصديرها',
      one: 'تسجيل واحد محفوظ — اضغط لتصديره',
    );
    return '$_temp0';
  }

  @override
  String get settingsExportStarted => 'بدأ التصدير — اختر أين ترسل الملف.';

  @override
  String get settingsDisputedTitle => 'الأحكام المُعترض عليها';

  @override
  String get settingsDisputedEmpty =>
      'لا توجد أحكام معترض عليها بعد — استخدم 👎 تحت \"صوتي\" أثناء التلاوة';

  @override
  String settingsDisputedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count أحكام معترض عليها — اضغط لإرسالها',
      one: 'حكم واحد معترض عليه — اضغط لإرساله',
    );
    return '$_temp0';
  }

  @override
  String get settingsExportCancelled =>
      'أُلغي التصدير أو لا يوجد أي مقطع متاح.';

  @override
  String get settingsSectionDisplay => 'العرض';

  @override
  String get settingsTajweedColorsTitle => 'ألوان التجويد';

  @override
  String get settingsTajweedColorsSubtitle => 'تلوين حسب أحكام التجويد';

  @override
  String get settingsSectionApp => 'التطبيق';

  @override
  String get settingsLocaleTitle => 'لغة التطبيق';

  @override
  String get settingsLocaleSheetDescription =>
      'بالعربية، يبقى كل المحتوى (القوائم والقرآن) بالعربية دون ترجمة. بالفرنسية/الإنجليزية، يبقى القرآن دائمًا بالعربية؛ فقط القوائم والشروحات تتغيّر لغتها.';

  @override
  String get settingsAboutSubtitle => 'الإصدار والمصادر والتراخيص والخصوصية';

  @override
  String get settingsValidate => 'تأكيد';

  @override
  String get settingsRepeatEngineSectionTitle => 'التكرار التدريجي';

  @override
  String get settingsAdultChunkWordCountTitle =>
      'عدد الكلمات في كل مرحلة (وضع البالغ)';

  @override
  String settingsAdultChunkWordCountDescription(int max) {
    return 'يقارب سطرًا من المصحف (من 1 إلى $max كلمة). بلا أثر في وضع الطفل، الذي يبقى كلمة بكلمة دائمًا.';
  }

  @override
  String get settingsRepeatWindowSizeTitle => 'نافذة التلاوة (المؤشر)';

  @override
  String settingsRepeatWindowSizeDescription(int max) {
    return 'عدد المراحل الواجب تلاوتها معًا للتثبيت (من 1 إلى $max). هذا العدد ثابت، والنافذة تنزلق مع تقدّم المراحل.';
  }

  @override
  String get commonConnectionRequired => 'الاتصال مطلوب';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get homeIdentifyTooltip => 'التعرّف على تلاوة';

  @override
  String get homeFollowPrayerTooltip => 'متابعة صلاة';

  @override
  String get surahMeccan => 'مكية';

  @override
  String get surahMedinan => 'مدنية';

  @override
  String surahMetaLine(int count, String place) {
    return '$count آية • $place';
  }

  @override
  String mushafExplanationTitleSurahVerse(String surah, int ayah) {
    return '$surah — الآية $ayah';
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
  String get mushafPlay => 'تشغيل';

  @override
  String get mushafPause => 'إيقاف مؤقت';

  @override
  String get mushafFavorites => 'علامة';

  @override
  String get mushafMemorize => 'حفظ';

  @override
  String get mushafTranslation => 'ترجمة';

  @override
  String get mushafCoachAi => 'المدرّب الذكي';

  @override
  String get mushafMore => 'المزيد';

  @override
  String get mushafAutoScroll => 'تمرير تلقائي';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get shazamListening => 'الاستماع جارٍ...\nقرّب الهاتف من الصوت.';

  @override
  String get shazamSearching => 'البحث في القرآن...';

  @override
  String get shazamFound => 'تم التعرّف على المقطع!';

  @override
  String get shazamNotFound =>
      'لم يتم التعرّف على المقطع.\nاقترب من الصوت وأعد المحاولة.';

  @override
  String get shazamError => 'حدث خطأ أثناء الاستماع.';

  @override
  String shazamMatchLabel(int surah, int ayah) {
    return 'سورة $surah، الآية $ayah';
  }

  @override
  String get shazamGoThere => 'الانتقال إليه';

  @override
  String get readingSettingsDisplaySection => 'العرض';

  @override
  String get readingSettingsAutoScrollSection => 'التمرير التلقائي';

  @override
  String get readingSettingsAutoScrollDescription =>
      'يتمرّر النص تلقائيًا بالسرعة المختارة — مفيد للقراءة دون استخدام يديك. أي تمرير يدوي يوقفه.';

  @override
  String get readingSettingsPlaybackSpeedSection => 'سرعة التلاوة (الصوت)';

  @override
  String get readingSettingsRepeatSection => 'التكرار / الحلقات';

  @override
  String get readingSettingsRepeatDescription =>
      'يكرّر كل آية (أو السورة كاملة) في حلقة قبل الانتقال إلى التالية.';

  @override
  String get readingSettingsRepeatOff => 'معطّل';

  @override
  String readingSettingsRepeatVerseCount(int count) {
    return 'الآية × $count';
  }

  @override
  String get readingSettingsRepeatVerseInfinite => 'الآية × ∞';

  @override
  String get readingSettingsRepeatSurah => 'السورة كاملة';

  @override
  String get readingSettingsSpeedOff => 'متوقف';

  @override
  String get readingSettingsSpeedSlow => 'بطيء';

  @override
  String get readingSettingsSpeedNormal => 'عادي';

  @override
  String get readingSettingsSpeedFast => 'سريع';

  @override
  String get readingSettingsKindleSection => 'وضع القراءة الهادئة';

  @override
  String get readingSettingsKindleDescription =>
      'سمة مريحة للعين تقلل الضوء الأزرق، مع تنقل بالصفحات كجهاز القراءة الإلكتروني.';

  @override
  String get readingSettingsKindleToggle => 'تفعيل وضع القراءة الهادئة';

  @override
  String get readingSettingsKindleAutoTurn => 'تقليب الصفحات تلقائيًا';

  @override
  String readingSettingsKindleSpeed(int seconds) {
    return 'السرعة: $seconds ث / صفحة';
  }

  @override
  String get coachExplanationListen => 'استماع';

  @override
  String get coachExplanationStop => 'إيقاف';

  @override
  String get coachExplanationLanguageTooltip => 'اللغة';

  @override
  String coachExplanationError(String error) {
    return 'خطأ: $error';
  }

  @override
  String coachExplanationRoot(String root) {
    return 'الجذر: $root';
  }

  @override
  String get coachExplanationExpand => 'تعمّق أكثر';

  @override
  String get coachExplanationNoneAvailable =>
      'لا يوجد شرح متاح لهذا المقطع على هذا الجهاز.';

  @override
  String tajwidHelpVerseLabel(String key) {
    return 'الآية $key';
  }

  @override
  String get tajwidHelpRulesInVerse => 'الأحكام في هذه الآية';

  @override
  String tajwidHelpListenWithReciter(String name) {
    return 'استماع — $name';
  }

  @override
  String get tajwidHelpListenPronunciation => 'استماع للنطق';

  @override
  String get tajwidHelpThisWord => 'هذه الكلمة';

  @override
  String get tajwidHelpPlusPrevious => '+ الكلمة السابقة';

  @override
  String get tajwidHelpPlusBoth => '+ السابقة والتالية';

  @override
  String get tajwidHelpPlaying => 'قيد التشغيل…';

  @override
  String get tajwidHelpVoiceFeedbackPrompt => 'هل سمع التطبيق بشكل صحيح؟';

  @override
  String get tajwidHelpVoiceFeedbackNeedsListen =>
      'استمع إلى \"صوتي\" أعلاه لإبداء رأيك';

  @override
  String get tajwidHelpVoiceThumbsUp => 'موافق، هذا خطأ فعلي';

  @override
  String get tajwidHelpVoiceThumbsDown => 'غير موافق، لقد نطقتها صحيحة';

  @override
  String get tajwidHelpVoiceFeedbackThanks => 'شكرًا، تم التسجيل';

  @override
  String get tajwidHelpRetryThisWord => 'إعادة المحاولة على هذه الكلمة';

  @override
  String tajwidHelpCorrectedHeard(String text) {
    return 'تم التصحيح — المسموع: \"$text\"';
  }

  @override
  String get tajwidHelpNothingHeard => '(لم يُسمع شيء)';

  @override
  String tajwidHelpNotYetHeard(String text) {
    return 'ليس بعد — المسموع: \"$text\". أعد المحاولة على راحتك.';
  }

  @override
  String get tajwidHelpAnalyzing => 'التحليل جارٍ…';

  @override
  String get tajwidHelpFinishRecording => 'إنهاء التسجيل';

  @override
  String get tajwidHelpRecordThisWord => 'سجّل هذه الكلمة';

  @override
  String get tajwidRuleMaddaNecessaryName => 'مدّ لازم (٦ حركات)';

  @override
  String get tajwidRuleMaddaNecessaryExplanation =>
      'مدّ إلزامي مقداره ست حركات.';

  @override
  String get tajwidRuleMaddaObligatoryName => 'مدّ واجب (٤ أو ٥ حركات)';

  @override
  String get tajwidRuleMaddaObligatoryExplanation =>
      'مدّ إلزامي مقداره أربع إلى خمس حركات.';

  @override
  String get tajwidRuleMaddaPermissibleName => 'مدّ جائز (٢ أو ٤ أو ٦ حركات)';

  @override
  String get tajwidRuleMaddaPermissibleExplanation =>
      'مدّ مقداره حركتان أو أربع أو ست حركات حسب رواية القراءة.';

  @override
  String get tajwidRuleGhunnahName => 'غنّة / إخفاء';

  @override
  String get tajwidRuleGhunnahExplanation =>
      'صوت أنفي يُمَدّ نحو حركتين (نون أو ميم مشدّدة)، أو إخفاء مع غنّة.';

  @override
  String get tajwidRuleIkhafaName => 'إخفاء';

  @override
  String get tajwidRuleIkhafaExplanation =>
      'تُنطق النون الساكنة أو التنوين مُخفاة بين النون والحرف التالي، مع غنّة.';

  @override
  String get tajwidRuleIkhafaShafawiName => 'إخفاء شفوي';

  @override
  String get tajwidRuleIkhafaShafawiExplanation =>
      'تُنطق الميم الساكنة قبل الباء مخفاة قليلًا، مع غنّة.';

  @override
  String get tajwidRuleIdghamGhunnahName => 'إدغام بغنّة';

  @override
  String get tajwidRuleIdghamGhunnahExplanation =>
      'تُدغم النون الساكنة أو التنوين في الحرف التالي (ي ن م و) مع غنّة.';

  @override
  String get tajwidRuleIdghamShafawiName => 'إدغام شفوي';

  @override
  String get tajwidRuleIdghamShafawiExplanation =>
      'تُدغم الميم الساكنة في الميم التالية، مع غنّة.';

  @override
  String get tajwidRuleIqlabName => 'إقلاب';

  @override
  String get tajwidRuleIqlabExplanation =>
      'تُقلب النون الساكنة أو التنوين ميمًا قبل الباء، مع غنّة.';

  @override
  String get tajwidRuleIdghamWoGhunnahName => 'إدغام بلا غنّة';

  @override
  String get tajwidRuleIdghamWoGhunnahExplanation =>
      'تُدغم النون الساكنة أو التنوين إدغامًا كاملًا في الحرف التالي (ل ر)، دون غنّة.';

  @override
  String get tajwidRuleIdghamMutajanisaynName => 'إدغام متجانسَين';

  @override
  String get tajwidRuleIdghamMutajanisaynExplanation =>
      'حرفان من نفس المخرج: يُدغم الأول في الثاني.';

  @override
  String get tajwidRuleIdghamMutaqaribaynName => 'إدغام متقارِبَين';

  @override
  String get tajwidRuleIdghamMutaqaribaynExplanation =>
      'حرفان متقاربا المخرج: يُدغم الأول في الثاني.';

  @override
  String get tajwidRuleQalaqahName => 'قلقلة';

  @override
  String get tajwidRuleQalaqahExplanation =>
      'ارتداد صوتي على حروف ق ط ب ج د عند سكونها.';

  @override
  String get tajwidRuleHamWaslName => 'همزة الوصل';

  @override
  String get tajwidRuleHamWaslExplanation =>
      'لا تُنطق إلا في بداية القراءة — تسقط عند الوصل بالكلمة السابقة.';

  @override
  String get tajwidRuleLaamShamsiyahName => 'لام شمسية';

  @override
  String get tajwidRuleLaamShamsiyahExplanation =>
      'لا تُنطق لام «ال» بل يُشدَّد الحرف التالي بدلًا منها.';

  @override
  String get tajwidRuleSlntName => 'حرف صامت';

  @override
  String get tajwidRuleSlntExplanation => 'يُكتب ولا يُنطق.';

  @override
  String get duasScreenTitle => 'الأذكار والأدعية';

  @override
  String get duasSearchHint => 'ابحث عن دعاء أو كلمة أو مصدر…';

  @override
  String get duasExplore => 'استكشاف';

  @override
  String get duasMyFavorites => 'المفضلة';

  @override
  String get duasNow => 'الآن';

  @override
  String get duasGuideBadge => 'دليل';

  @override
  String get duasNoneFound => 'لا توجد نتائج.';

  @override
  String duasInvocationCount(int count) {
    return '$count دعاء';
  }

  @override
  String get duaRemoveFavorite => 'إزالة من المفضلة';

  @override
  String get duaAddFavorite => 'إضافة إلى المفضلة';

  @override
  String duaPlaybackError(String error) {
    return 'تعذّر التشغيل: $error';
  }

  @override
  String get duaHideVirtue => 'إخفاء الفضل';

  @override
  String get duaShowVirtue => 'لماذا تُقال';

  @override
  String duaRepeatComplete(int target) {
    return 'تم — $target/$target';
  }

  @override
  String get duaResetCount => 'إعادة العدّ من جديد';

  @override
  String get duaCollectionEmpty => 'هذه المجموعة لا تزال فارغة.';

  @override
  String get duaSequencePlayAll => 'تشغيل الكل';

  @override
  String get duaSequenceNoneAudio =>
      'لا توجد تلاوة صوتية في هذه القائمة — التسجيل الصوتي متاح فقط للأدعية القرآنية.';

  @override
  String duaSequenceProgress(int index, int total) {
    return 'دعاء $index/$total';
  }

  @override
  String get duaSequenceStop => 'إيقاف التشغيل';

  @override
  String get duaSequenceSkip => 'الدعاء التالي';

  @override
  String coachSurahLabel(int number) {
    return 'سورة $number';
  }

  @override
  String get coachHeaderLabel => 'مدرّب الحفظ';

  @override
  String get coachVerificationModeTooltip => 'وضع التحقق';

  @override
  String get coachStepLecture => 'قراءة';

  @override
  String get coachStepTrain => 'تدريب';

  @override
  String get coachStepControl => 'اختبار';

  @override
  String get coachReadAloudInstruction =>
      'اقرأ هذه الآية بصوت مرتفع — يكتشف التطبيق الكلمات الصعبة ويحفظ صوتك.';

  @override
  String get coachListeningLecture => 'أسجّل الكلمات الصعبة…';

  @override
  String get coachDoneLecture => 'تم تحليل القراءة';

  @override
  String get coachTapToRead => 'اضغط واقرأ الآية';

  @override
  String get coachAlreadyKnow => 'أعرفها من قبل';

  @override
  String get coachTrainButton => 'تدرّب';

  @override
  String get coachSubStepListen => 'استماع';

  @override
  String get coachSubStepImitate => 'محاكاة';

  @override
  String get coachSubStepRepeat => 'تكرار';

  @override
  String get coachListenInstruction => 'استمع إلى القارئ. تابع كل كلمة بعينيك.';

  @override
  String get coachListeningAudio => 'الاستماع جارٍ…';

  @override
  String get coachTapToListen => 'اضغط للاستماع';

  @override
  String get coachMoveToImitation => 'الانتقال إلى المحاكاة';

  @override
  String get coachImitateInstruction =>
      'شغّل الصوت وتكلّم في الوقت نفسه. حاكِ الإيقاع والوقفات والنبرة.';

  @override
  String get coachSpeakAlong => 'تكلّم في نفس وقت الصوت';

  @override
  String get coachLaunchAndImitate => 'شغّل الصوت وحاكِه';

  @override
  String get coachImitatedNext => 'حاكيت — أكرّر وحدي';

  @override
  String get coachIncrementalInstruction =>
      'استمع ثم كرّر. تكبر المرحلة مع كل نجاح.';

  @override
  String get coachIncrementalPreparing => 'التحضير جارٍ…';

  @override
  String get coachIncrementalListening => 'الاستماع جارٍ…';

  @override
  String get coachIncrementalTapToStart => 'اضغط لإعادة المحاولة';

  @override
  String coachIncrementalUnitProgress(int done, int total) {
    return 'المرحلة $done/$total';
  }

  @override
  String get coachIncrementalVerseAdvance => 'الآية التالية';

  @override
  String get coachRecallInstruction => 'اتلُ من حفظك — النص مخفي.';

  @override
  String get coachRecallBadge => 'التلاوة من الحفظ';

  @override
  String get coachListeningControl => 'التلاوة من الحفظ جارية…';

  @override
  String get coachControlDone => 'انتهت التلاوة';

  @override
  String get coachTapToRecall => 'اضغط واتلُ من حفظك';

  @override
  String get coachBackToTraining => 'العودة إلى التدريب';

  @override
  String get coachTranscriptLabel => 'النص المسموع';

  @override
  String get coachAnalyzingAudio => 'تحليل الصوت جارٍ…';

  @override
  String coachAccuracyPercent(int pct) {
    return 'دقة $pct٪';
  }

  @override
  String coachFingerprintScore(int pct) {
    return 'بصمة الصوت: $pct٪';
  }

  @override
  String get coachMemorizedConfirmed => 'تأكّد الحفظ!';

  @override
  String get coachKeepTraining => 'واصل التدريب';

  @override
  String coachGapSummary(int baseline, int control, String delta) {
    return 'القراءة الأولى: $baseline٪ ← من الحفظ: $control٪ ($delta٪)';
  }

  @override
  String get coachMsgLectureExcellent => 'قراءة ممتازة! أتقنت نطق هذه الآية.';

  @override
  String coachMsgLectureDifficultWords(String words) {
    return 'هذه الكلمات كانت صعبة عليك: $words\n\nركّز عليها أثناء التدريب.';
  }

  @override
  String get coachMsgLectureHesitant =>
      'لوحظ بعض التردد. سيساعدك التدريب على تصحيحه.';

  @override
  String get coachMsgTrainGreat =>
      'أحسنت! تكرارك صحيح. يمكنك الآن اختبار حفظك دون النص.';

  @override
  String get coachMsgTrainGoodStart =>
      'بداية جيدة. أعد المحاولة مرة أخرى لترسيخ الكلمات المتردد فيها.';

  @override
  String get coachMsgTrainRestart =>
      'أعد الاستماع والمحاكاة، ثم حاول التكرار من جديد.';

  @override
  String get coachMsgControlMashallah =>
      'ما شاء الله! تلاوتك من الحفظ أفضل من قراءتك الأولى — الآية محفوظة!';

  @override
  String get coachMsgControlVeryGood =>
      'تلاوة جيدة جدًا! واصل المراجعة بانتظام لترسيخها.';

  @override
  String get coachMsgControlGoodPath =>
      'أنت في الطريق الصحيح. بضع تكرارات أخرى وستُرسَّخ الآية.';

  @override
  String get coachMsgControlKeepTraining =>
      'واصل التدريب. عد إلى مرحلة القراءة لتستهدف نقاط الضعف.';

  @override
  String get errorKindLettre => 'الحرف';

  @override
  String get errorKindHarakat => 'الحركات';

  @override
  String get errorKindTajwid => 'التجويد';

  @override
  String get errorKindSkippedWord => 'كلمة مُسقَطة';

  @override
  String get errorKindOubli => 'نسيان';

  @override
  String get errorKindUnknown => 'غير محدّد';

  @override
  String get coachHubTitle => 'مدرّبي';

  @override
  String get coachHubResumeLabel => 'متابعة';

  @override
  String coachHubResumeVerse(String surahName, int ayah) {
    return '$surahName — الآية $ayah';
  }

  @override
  String get coachHubContinue => 'متابعة';

  @override
  String get coachHubMemorizeSectionTitle => 'الحفظ';

  @override
  String get coachHubMemorizeSectionSubtitle => 'آية بآية، بالميكروفون';

  @override
  String get coachHubMemorizeSurahTitle => 'حفظ سورة';

  @override
  String get coachHubMemorizeSurahSubtitle => 'قراءة ← تدريب ← اختبار';

  @override
  String get coachHubPickerMemorizeTitle => 'حفظ';

  @override
  String get coachHubPickerMemorizeSubtitle => 'اختر السورة للعمل عليها';

  @override
  String get coachHubReciteSurahTitle => 'تلاوة سورة';

  @override
  String get coachHubReciteSurahSubtitle => 'متابعة كلمة بكلمة، تصحيح مباشر';

  @override
  String get coachHubPickerReciteTitle => 'تلاوة';

  @override
  String get coachHubPickerReciteSubtitle => 'اختر السورة للتلاوة';

  @override
  String get coachHubErrorsSectionTitle => 'أخطائي';

  @override
  String get coachHubErrorsSectionSubtitle => 'حسب النوع ثم حسب السورة';

  @override
  String coachHubLoadErrorLog(String error) {
    return 'تعذّر تحميل السجل: $error';
  }

  @override
  String get coachHubNoErrorsTitle => 'لا توجد أخطاء مسجّلة';

  @override
  String get coachHubNoErrorsBody =>
      'اتلُ من «تلاوة» أو «حفظ»: ستظهر هنا الكلمات المُعادة، مجمّعة حسب السورة.';

  @override
  String coachHubVersesTouched(int count, int total) {
    return '$count آية من $total';
  }

  @override
  String get coachHubGoToMindMap => 'تحديد الموقع في الخريطة الذهنية';

  @override
  String coachHubAyahErrorCount(int ayah, int count) {
    return 'الآية $ayah  ·  $count خطأ';
  }

  @override
  String get coachHubExplanationTooltip => 'شرح';

  @override
  String get coachHubReviewVerseTooltip => 'مراجعة هذه الآية';

  @override
  String get coachHubErrorNoteExplainer =>
      'الحرف والحركات = النطق. «التجويد» تعني أن لا الحروف ولا الحركات تفسّر الفارق في كلمة تحمل حكمًا — إنه استنتاج، لا دليل على أن الحكم لم يُراعَ.';

  @override
  String get coachHubRuleBreakdownTitle => 'التفصيل حسب حكم التجويد';

  @override
  String get coachHubResetErrorsTooltip => 'إعادة تعيين سجل الأخطاء';

  @override
  String get coachHubResetErrorsDialogTitle => 'إعادة تعيين الإحصائيات؟';

  @override
  String get coachHubResetErrorsDialogBody =>
      'سيُمحى كامل سجل الأخطاء (كل السور، كل الأنواع) نهائيًا. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get coachHubResetErrorsDialogConfirm => 'إعادة التعيين';

  @override
  String get coachHubResetErrorsDialogCancel => 'إلغاء';

  @override
  String get coachHubResetErrorsDone => 'تمت إعادة تعيين سجل الأخطاء.';

  @override
  String get coachHubGameSectionTitle => 'العب';

  @override
  String get coachHubGameSectionSubtitle => 'استرجاع تدريجي، درجة بعد درجة';

  @override
  String get coachHubGameActionTitle => 'لعبة الحفظ';

  @override
  String get coachHubGameActionSubtitle =>
      'تظهر الكلمات واحدة تلو الأخرى، أكمل الباقي من حفظك';

  @override
  String get coachHubPickerGameTitle => 'لعبة الحفظ';

  @override
  String get coachHubPickerGameSubtitle => 'اختر السورة التي تريد حفظها باللعب';

  @override
  String get memorizationGameTitle => 'لعبة الحفظ';

  @override
  String get memorizationGameRestartVerseTooltip => 'إعادة هذه الآية';

  @override
  String memorizationGameVerseProgress(int current, int total) {
    return 'الآية $current من $total';
  }

  @override
  String get memorizationGameCompleteTitle => 'اكتملت السورة!';

  @override
  String memorizationGameCompleteBody(String surah) {
    return 'لقد اجتزت جميع درجات $surah. أعد المحاولة لترسيخ حفظك.';
  }

  @override
  String get memorizationGameBackToHub => 'رجوع';

  @override
  String memorizationGameWordsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count كلمة متتالية',
      one: 'كلمة واحدة متتالية',
      zero: 'لا كلمات بعد',
    );
    return '$_temp0';
  }

  @override
  String memorizationGameRecordLabel(int count) {
    return 'الرقم القياسي: $count';
  }

  @override
  String get memorizationGameNewRecord => 'رقم قياسي جديد!';

  @override
  String get memorizationGameLoadingNextPage => 'الصفحة التالية…';

  @override
  String memorizationGameFinalScore(int count, int best) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count كلمة متتالية',
      one: 'كلمة واحدة متتالية',
      zero: 'لا كلمات هذه المرة',
    );
    return '$_temp0 — الرقم القياسي: $best';
  }

  @override
  String get memorizationAyahPickerTitle => 'اختر نقطة البداية';

  @override
  String memorizationAyahPickerSubtitle(String surah) {
    return 'سورة $surah طويلة: اختر أولًا الصفحة التي تريد البدء منها';
  }

  @override
  String memorizationAyahPickerPageLabel(int page) {
    return 'الصفحة $page';
  }

  @override
  String memorizationAyahPickerAyahSubtitle(int page) {
    return 'الصفحة $page: اختر الآية التي تريد بدء اللعب منها';
  }

  @override
  String get memorizationAyahPickerBackToPages => 'تغيير الصفحة';

  @override
  String get qiblaSubtitle => 'اتجاه القبلة نحو مكة';

  @override
  String get qiblaEnableLocationMessage =>
      'فعّل خدمة الموقع لتحديد القبلة من موقعك الحالي.';

  @override
  String get qiblaEnableLocationAction => 'تفعيل خدمة الموقع';

  @override
  String get qiblaPermissionDeniedMessage =>
      'تم رفض إذن الموقع لتطبيق قرآن كريم. فعّله من إعدادات الهاتف لعرض القبلة.';

  @override
  String get qiblaOpenSettingsAction => 'فتح الإعدادات';

  @override
  String qiblaPositionError(String error) {
    return 'تعذّر تحديد موقعك: $error';
  }

  @override
  String get qiblaNoCompassMessage =>
      'لا يحتوي هذا الجهاز على بوصلة. تبقى المسافة إلى مكة متاحة أدناه.';

  @override
  String get qiblaKmToMecca => 'كم حتى مكة';

  @override
  String get qiblaFacingQibla => 'أنت تواجه القبلة ✓';

  @override
  String get qiblaTurnPhoneHint => 'أدر هاتفك حتى يشير السهم إلى الأعلى';

  @override
  String get prayerFollowSensitivityTolerant => 'متساهل';

  @override
  String get prayerFollowSensitivityStrict => 'صارم';

  @override
  String get prayerFollowSensitivityBalanced => 'متوازن (افتراضي)';

  @override
  String get prayerFollowSensitivityTitle => 'الحساسية (متابعة الصلاة)';

  @override
  String get prayerFollowSensitivityDescription =>
      'إعداد مستقل عن حساسية التلاوة العادية -- كلما زاد التساهل قُبلت نطقات أقل دقة باللون الأخضر، وكلما زادت الصرامة تطلّب الأمر دقة أكبر.';

  @override
  String get prayerFollowSouffleurTitle => 'التلقين التلقائي';

  @override
  String prayerFollowSouffleurSubtitle(int seconds) {
    return 'يشغّل الكلمة المتوقعة بعد $seconds ثانية من الصمت -- لا حظر أبدًا في هذا الوضع.';
  }

  @override
  String get prayerFollowTitle => 'متابعة صلاة';

  @override
  String get prayerFollowSettingsTooltip => 'الإعدادات';

  @override
  String get prayerFollowWaitingFatiha => 'بانتظار بداية الفاتحة…';

  @override
  String get prayerFollowIdentifying =>
      'انتهت الفاتحة -- يتم تحديد السورة التالية…';

  @override
  String get prayerFollowListening => 'الاستماع جارٍ…';

  @override
  String get prayerFollowTapToStart =>
      'اضغط على الميكروفون لبدء متابعة الصلاة.';

  @override
  String get prayerPhaseStandby => 'انتظار (الركوع/السجود)';

  @override
  String get prayerPhaseFatiha => 'الفاتحة';

  @override
  String get prayerPhaseDetecting => 'التعرّف جارٍ…';

  @override
  String get prayerPhaseTarget => 'السورة المتابَعة';

  @override
  String get prayerPhaseListening => 'الاستماع';

  @override
  String get prayerPhaseStopped => 'متوقف';

  @override
  String get riteBeforeStartTooltip => 'معلومات قبل البدء';

  @override
  String get riteRestartTooltip => 'إعادة بدء النسك';

  @override
  String get riteWhatWeDoLabel => 'ما نقوم به';

  @override
  String get riteWhatWeSayLabel => 'ما نقوله هنا';

  @override
  String riteStepOfTotal(int index, int total) {
    return 'الخطوة $index من $total';
  }

  @override
  String get riteBeforeStartTitle => 'قبل البدء';

  @override
  String get riteDisclaimer =>
      'هذا الدليل مذكّر لا فتوى. تختلف المذاهب الفقهية في عدة تفاصيل ثانوية: عند الشك في الموقع، اسأل مرشدًا مؤهلاً أو المشرفين على مجموعتك.';

  @override
  String get riteResetConfirmTitle => 'إعادة البدء؟';

  @override
  String get riteResetConfirmBody =>
      'ستُعاد جميع الخطوات المُنجزة والعدّادات إلى الصفر.';

  @override
  String get riteResetConfirmAction => 'إعادة البدء';

  @override
  String get ritePreviousStepTooltip => 'الخطوة السابقة';

  @override
  String get riteNextStepTooltip => 'الخطوة التالية';

  @override
  String get riteStepDone => 'أُنجزت الخطوة';

  @override
  String get riteMarkAsDone => 'وضع علامة كمنجزة';

  @override
  String get recitationModeLabel => 'وضع الحفظ';

  @override
  String recitationVerseTitle(String key) {
    return 'الآية $key';
  }

  @override
  String recitationRangeTitle(String from, String to, int count) {
    return '$from ← $to ($count آية)';
  }

  @override
  String recitationSegmentAnalyzing(int count) {
    return '$count مقطع قيد التحليل…';
  }

  @override
  String get recitationTranscriptLabel => 'النص المسموع';

  @override
  String get recitationStatCorrect => 'صحيح';

  @override
  String get recitationStatErrors => 'أخطاء';

  @override
  String get recitationStatAccuracy => 'الدقة';

  @override
  String get recitationListeningContinuous =>
      'تلاوة متواصلة… التوقف الطبيعي = الآية التالية';

  @override
  String get recitationFinalizing => 'إنهاء التحليل…';

  @override
  String get recitationFinishedRestart => 'انتهت — اضغط لإعادة البدء';

  @override
  String get recitationTapToStart => 'اضغط وتلُ (عدة آيات متتالية)';

  @override
  String recitationMashallahAccuracy(String pct) {
    return 'ما شاء الله! دقة $pct٪';
  }

  @override
  String recitationContinueAccuracy(String pct) {
    return 'واصل — دقة $pct٪';
  }

  @override
  String get reciterSelectTitle => 'اختيار قارئ';

  @override
  String get reciterSelectStreamingNote =>
      'القرّاء المدمجون. القراءة تتم عبر الإنترنت افتراضيًا؛ حمّل سورة للاستماع دون اتصال.';

  @override
  String get reciterSelectOfflineTitle => 'تنزيل للاستخدام دون اتصال';

  @override
  String get reciterSelectOfflineSubtitle =>
      'حمّل سورة بسورة من أيقونة كل قارئ.';

  @override
  String get voiceCalibTitle => 'معايرة الصوت';

  @override
  String get voiceCalibDoneTitle => 'اكتملت المعايرة!';

  @override
  String voiceCalibDoneBody(int count) {
    return 'تم تسجيل $count مقطع. ستنضم إلى مقاطعك الموثّقة — صدّرها من الإعدادات لبدء التخصيص.';
  }

  @override
  String get voiceCalibSave => 'حفظ';

  @override
  String voiceCalibWordProgress(int index, int total, String reference) {
    return 'الكلمة $index/$total — $reference';
  }

  @override
  String voiceCalibWrongInstruction(String target, String confused) {
    return 'انطق هذه الكلمة مستبدلاً عمدًا حرف \"$target\" بحرف \"$confused\" — خطأ متعمّد، لا تلاوة حقيقية.';
  }

  @override
  String get voiceCalibCorrectInstruction =>
      'انطق هذه الكلمة بشكل صحيح، كالمعتاد.';

  @override
  String get voiceCalibRecording => 'التسجيل جارٍ… اضغط للإيقاف';

  @override
  String get voiceCalibTapToRecord => 'اضغط للتسجيل';

  @override
  String voiceCalibSavedSnackbar(int count) {
    return 'تم تسجيل $count مقطع معايرة — صدّرها من الإعدادات لتخصيص النموذج.';
  }

  @override
  String get ruleReliableLabel => 'موثوق';

  @override
  String ruleReliableLabelWithPct(int pct) {
    return 'موثوق · $pct٪';
  }

  @override
  String get ruleUnreliableLabel => 'غير موثوق';

  @override
  String ruleUnreliableLabelWithPct(int pct) {
    return 'غير موثوق · $pct٪';
  }

  @override
  String get ruleNotMeasuredLabel => 'غير مقاس';

  @override
  String get tajwidRulesTitle => 'التحقق من التلاوة';

  @override
  String tajwidRulesLoadError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get tajwidRulesHarakatTitle => 'الحركات مطلوبة';

  @override
  String get tajwidRulesHarakatSubtitle =>
      'معطّل: الحركات القصيرة لا تُحتسب خطأً';

  @override
  String get tajwidRulesConfusablesTitle => 'التسامح مع الحروف المتقاربة';

  @override
  String get tajwidRulesConfusablesSubtitle =>
      'ص/س، ط/ت، ض/د، ذ/ز، ح/ه، ق/ك، ع/ء تُحتسب متكافئة (وضع الطفل)';

  @override
  String get tajwidRulesSectionTitle => 'أحكام التجويد';

  @override
  String get tajwidRulesSectionSubtitle =>
      'اختر الأحكام التي يتحقق منها التطبيق أثناء تلاوتك.';

  @override
  String get tajwidRulesImpreciseNote =>
      'الكشف لا يزال غير دقيق: قد يشير هذا الحكم إلى شك، لكنه لن يصادق وحده على كلمة باللون الأخضر.';

  @override
  String get tajwidPresetTajwid => 'تجويد';

  @override
  String get tajwidPresetAdult => 'بالغ';

  @override
  String get tajwidPresetChild => 'طفل';

  @override
  String surahPickerLoadVersesError(String error) {
    return 'تعذّر التحميل: $error';
  }

  @override
  String surahPickerLoadListError(String error) {
    return 'تعذّر تحميل السور: $error';
  }

  @override
  String surahPickerVerseCount(int count) {
    return '$count آية';
  }

  @override
  String get karaokeAudioUnavailable => 'الصوت غير متاح لهذه الكلمة';

  @override
  String get karaokeRepeatIndicated => 'كرّر الكلمة المشار إليها ↓';

  @override
  String get karaokeFirstRecitationTitle => 'أول تلاوة لهذا المقطع';

  @override
  String get karaokeFirstRecitationBody =>
      'هل تريد أن تكون هذه التلاوة مرجعًا لإيقاعك الطبيعي (وقفات مقاسة، دون تصحيح تلقائي)، أم تلاوة عادية الآن (بتصحيح تلقائي)؟';

  @override
  String get karaokeReciteNormally => 'تلاوة عادية';

  @override
  String get karaokeMakeReference => 'إنشاء مرجع';

  @override
  String karaokeReferenceNotSaved(
    int pct,
    int correct,
    int total,
    String extra,
  ) {
    return 'لم يُحفظ المرجع: تم التعرّف بشكل جيد على $pct٪ فقط من الكلمات ($correct/$total صحيحة$extra). يجب أن يعكس المرجع تلاوة موثوقة — اقترب من الميكروفون، قلّل الضجيج المحيط، وأعد المحاولة بإيقاعك الطبيعي.';
  }

  @override
  String karaokeUnclearSuffix(int count) {
    return '، $count غير دقيقة';
  }

  @override
  String karaokeMissedSuffix(int count) {
    return '، $count غير معروفة';
  }

  @override
  String karaokeReferenceSaved(int pct, int pauseCount) {
    return 'تم حفظ طريقتك في التلاوة لهذا المقطع ✓ (نسبة تعرّف $pct٪، $pauseCount وقفة مكتسبة)';
  }

  @override
  String get karaokeVerificationSettingsTitle => 'إعدادات التحقق';

  @override
  String get karaokeVerificationModeTitle => 'وضع التحقق';

  @override
  String get karaokeVerificationModeSubtitle =>
      'أنماط تجويد / بالغ / طفل، 17 حكمًا';

  @override
  String get karaokeSensitivityTitle => 'حساسية التصحيح';

  @override
  String get karaokeSensitivityDescription =>
      'أكثر تساهلاً: يقبل الحركات/النطق غير الدقيق باللون الأخضر. أكثر صرامة: يتطلب نطقًا أقرب إلى النموذج.';

  @override
  String get karaokeEngineTitle => 'المحرّك: المحاذاة القسرية (gop)';

  @override
  String get karaokeEngineActiveSubtitle =>
      'نشط — حساس للحركات، قد يكون صارمًا جدًا على بعض الكلمات';

  @override
  String get karaokeEngineInactiveSubtitle =>
      'معطّل — مقارنة نصية (تقليدية)، أقل دقة في الحركات';

  @override
  String get karaokeAutoCorrectionTitle => 'التصحيح التلقائي';

  @override
  String get karaokeAutoCorrectionSubtitle =>
      'كلمة حمراء ← إيقاف مؤقت، يصحّح القارئ، استئناف تلقائي';

  @override
  String get karaokeStrictnessTitle => 'صرامة التصحيح';

  @override
  String get karaokeStrictnessStrictSubtitle =>
      'صارم — يُعاد الأحمر والبرتقالي (غير الدقيق) معًا';

  @override
  String get karaokeStrictnessTolerantSubtitle =>
      'متساهل — يُعاد الأحمر فقط (الكلمة الخاطئة)';

  @override
  String get karaokeFollowFreeTitle => 'المتابعة دون حظر';

  @override
  String get karaokeFollowFreeOnSubtitle => 'يتقدّم بحرية حتى دون إعادة دقيقة';

  @override
  String get karaokeFollowFreeOffSubtitle => 'كل خطأ يفرض إعادة الكلمة';

  @override
  String get karaokeNewReferenceSnackbar =>
      'ستُعيد التلاوة القادمة تحديد مرجعك لهذا المقطع.';

  @override
  String get karaokeHearExpectedWordTooltip => 'سماع الكلمة المتوقعة';

  @override
  String get karaokeResumeTooltip => 'استئناف';

  @override
  String get karaokePauseTooltip => 'إيقاف مؤقت';

  @override
  String get karaokeRedoReferenceTooltip => 'إعادة تلاوتي المرجعية';

  @override
  String get karaokeReferenceRecordingTitle => 'تلاوة مرجعية';

  @override
  String get karaokeReferenceRecordingBody =>
      'أول تلاوة لهذا المقطع: اتلُ بإيقاعك الطبيعي — ستُحفظ طريقتك في التلاوة (الوقفات، الإيقاع) وتُحترم في كل تلاواتك القادمة.';

  @override
  String get karaokeReferenceInProgressTitle => 'تسجيل المرجع جارٍ';

  @override
  String get karaokeReferenceInProgressBody => 'اتلُ بشكل طبيعي، بإيقاعك.';

  @override
  String get karaokeHeardLabel => 'المسموع';

  @override
  String get karaokeTranscriptFullTitle => 'النص الكامل المسموع';

  @override
  String get karaokeNothingHeardYet => 'لم يُسمع شيء بعد.';

  @override
  String get karaokeFinalizing => 'الإنهاء جارٍ…';

  @override
  String get karaokePausedHint => 'متوقف مؤقتًا — المس ⏸ للاستئناف';

  @override
  String get karaokeListeningHint => 'الاستماع جارٍ — المس الدائرة للتوقف';

  @override
  String get karaokeFinishedHint => 'المس الشاشة لإعادة البدء';

  @override
  String get karaokeReferenceStartHint => 'المس الشاشة لتسجيل تلاوتك المرجعية';

  @override
  String get karaokeTapToStartHint => 'المس الشاشة للبدء';

  @override
  String get karaokeLoadingModel => 'جارٍ تحميل نموذج التلاوة…';

  @override
  String get karaokeGetReady => 'استعد';

  @override
  String get karaokePreparingMicrophone => 'جارٍ تجهيز الميكروفون…';

  @override
  String get karaokeGo => 'ابدأ!';

  @override
  String get karaokeModelUnavailable => 'نموذج التلاوة غير متاح.';

  @override
  String get karaokeStartFailed => 'تعذر بدء الاستماع.';

  @override
  String karaokeSurahTransitionMeta(int number, String name, int count) {
    return '$number · $name · $count آية';
  }

  @override
  String surahOrnamentMeta(String place, int count) {
    return '$place · $count آية';
  }

  @override
  String get miniPlayerRepeatOff => 'تكرار';

  @override
  String miniPlayerRepeatVerse(int count) {
    return '×$count آية';
  }

  @override
  String get miniPlayerRepeatSurah => 'سورة ∞';

  @override
  String get mushafMindMapTooltip => 'الخريطة الذهنية';

  @override
  String get mushafPrayerNextIn => 'الظهر بعد ٢س ١٤د';

  @override
  String get mushafPrayerTimeLabel => 'الظهر ١٣:٣٠';

  @override
  String mushafJuzChip(int n) {
    return 'الجزء $n';
  }

  @override
  String get settingsSectionDiagnostic => 'التشخيص';

  @override
  String get settingsDiagnosticTitle => 'سجل التشخيص والصوت';

  @override
  String get settingsDiagnosticSubtitleOn =>
      'مُفعَّل — يكتب السجل ويحفظ مقاطع الصوت';

  @override
  String get settingsDiagnosticSubtitleOff =>
      'مُعطَّل — لا يُكتب شيء أثناء التلاوة';

  @override
  String get reciterDownloadsTitle => 'التحميل للاستماع دون اتصال';

  @override
  String reciterDownloadAll(String size) {
    return 'تحميل الكل ($size)';
  }

  @override
  String get reciterDownloadStop => 'إيقاف';

  @override
  String get reciterDeleteAllTitle => 'حذف التحميلات';

  @override
  String get reciterDeleteAllBody =>
      'سيتم حذف جميع المقاطع الصوتية المحمّلة لهذا القارئ من الجهاز، وستعود القراءة عبر الإنترنت.';

  @override
  String get reciterDeleteAllConfirm => 'حذف';

  @override
  String reciterStorageUsed(String size, String done, String total) {
    return '$size على هذا الجهاز • $done/$total سورة دون اتصال';
  }

  @override
  String get reciterDownloadFailed =>
      'فشل التحميل — تحقّق من اتصالك. الملفات المحمّلة محفوظة.';

  @override
  String reciterDownloadingProgress(String done, String total) {
    return 'جارٍ التحميل… $done/$total آية';
  }

  @override
  String get reciterSurahOffline => 'متاحة دون اتصال';

  @override
  String get reciterVersesShort => 'آية';

  @override
  String get reciterBadgeOfflineFull => 'دون اتصال';

  @override
  String reciterBadgeOfflinePartial(String done, String total) {
    return 'دون اتصال · $done/$total';
  }

  @override
  String get reciterBadgeOnline => 'إنترنت';

  @override
  String reciterSelectStorageTotal(String size) {
    return '$size مستخدمة على هذا الجهاز';
  }

  @override
  String get mushafRecite => 'تلاوة';

  @override
  String get mushafFromHere => 'ابتداءً من هذه الآية';

  @override
  String get mushafBookmarkAdded => 'تم وضع العلامة';

  @override
  String get mushafBookmarkRemoved => 'تم حذف العلامة';

  @override
  String get readingSettingsGroupRead => 'القراءة';

  @override
  String get readingSettingsGroupListen => 'الاستماع';

  @override
  String get recitationPausedTapToResume =>
      'المِيكروفون متوقّف — انقر للمتابعة';

  @override
  String get tajwidHelpClose => 'إغلاق';

  @override
  String get mushafBookmarksTitle => 'علاماتي';

  @override
  String get mushafNoBookmarks =>
      'لا توجد علامة بعد. انقر على الأيقونة لتعليم الآية التي توقّفت عندها.';

  @override
  String get readingSettingsUnitLabel => 'وحدة التكرار';

  @override
  String get readingSettingsUnitVerse => 'آيات';

  @override
  String get readingSettingsUnitWord => 'كلمات';

  @override
  String readingSettingsGroupSizeWords(int n) {
    return '١ — ما يُكرَّر: $n كلمة في كل مرة';
  }

  @override
  String get readingSettingsWordUnitHint =>
      'التكرار بالكلمة يقطّع صوت القارئ اعتمادًا على توقيت الكلمات. إذا لم يوفّرها القارئ المختار، يعود التشغيل إلى الآيات.';

  @override
  String readingSettingsGroupSize(int n) {
    return '١ — ما يُكرَّر: $n آية في كل مرة';
  }

  @override
  String readingSettingsGroupRepeats(int n) {
    return '٢ — عدد مرات هذه المجموعة: $n';
  }

  @override
  String readingSettingsGlobalRepeats(int n) {
    return '٣ — عدد مرات السورة كاملة: $n';
  }

  @override
  String get readingSettingsUnlimited => 'بلا حد';

  @override
  String get readingSettingsLoopSection => 'التكرار والحلقات';

  @override
  String get readingSettingsLoopDescription =>
      'مثال: 3 آيات تُكرَّر 3 مرات، والسورة كاملة تُعاد 3 مرات.';

  @override
  String get aboutTitle => 'حول التطبيق';

  @override
  String get aboutTagline => 'تلاوة القرآن، مع التحقق داخل جهازك.';

  @override
  String aboutVersionLine(String version, String build) {
    return 'الإصدار $version (بناء $build)';
  }

  @override
  String get aboutSectionPrivacy => 'بياناتك';

  @override
  String get aboutPrivacyIntro =>
      'كل شيء يجري داخل هاتفك: لا حساب، ولا إعلانات، ولا أدوات تتبُّع.';

  @override
  String get aboutPrivacyMic =>
      'الميكروفون — تُحلَّل تلاوتك داخل الجهاز، ولا تُرسَل إلى أي جهة.';

  @override
  String get aboutPrivacyLocation =>
      'الموقع — للقبلة ومواقيت الصلاة. ويبقى داخل الجهاز.';

  @override
  String get aboutPrivacyDiagnostic =>
      'التشخيص — عند تفعيله في الإعدادات، تُحفَظ مقاطع صوتية وسجلٌّ داخل الجهاز. ويمكنك حذفها في أي وقت.';

  @override
  String get aboutPrivacyNetwork =>
      'الشبكة — فقط لتنزيل التلاوات والأذكار التي تطلبها.';

  @override
  String get aboutSectionAsr => 'ما الذي يتحقَّق من تلاوتك';

  @override
  String get aboutAsrBody =>
      'نموذج للتعرُّف على الكلام العربي، دُرِّب على تلاوات، يقارن ما تقوله بالنص. وقد يُخطئ: فالكلمة المُشار إليها ليست خطأً دائمًا.';

  @override
  String get aboutAsrCredit =>
      'نموذج مشتق من نموذج NVIDIA، بترخيص CC BY 4.0، عُدِّل للتلاوة القرآنية.';

  @override
  String get aboutSectionAi => 'المعلِّم الذكي';

  @override
  String get aboutAiWarning =>
      'تُنتَج شروح الآيات بواسطة نموذج لغوي يعمل داخل هاتفك، وقد يُخطئ أو يُغفل أو يُحرِّف. وليست لهذه النصوص أي حجية شرعية: فلأي مسألة في الفهم أو الأحكام، ارجع إلى القرآن والسنة وأهل العلم المؤهَّلين.';

  @override
  String get aboutAiReportTitle => 'الإبلاغ عن إجابة غير لائقة';

  @override
  String aboutAiReportBody(String email) {
    return 'راسلنا على $email مع ذكر الآية المعنية والنص الذي ظهر لك.';
  }

  @override
  String get aboutCopied => 'تم نسخ العنوان';

  @override
  String get aboutSectionSources => 'المصادر';

  @override
  String get aboutSourceQuran => 'نص القرآن والتلاوات: Quran.com.';

  @override
  String get aboutSourceDuas => 'صوت الأذكار: hisnmuslim.com.';

  @override
  String get aboutSectionLicenses => 'التراخيص';

  @override
  String get aboutLicensesAll => 'عرض جميع التراخيص';

  @override
  String get onboardingSkip => 'تخطّي';

  @override
  String get onboardingNext => 'التالي';

  @override
  String get onboardingStart => 'لنبدأ';

  @override
  String get onboardingWelcomeTitle => 'مرحبًا';

  @override
  String get onboardingWelcomeBody =>
      'اقرأ القرآن واتلُه واحفظه على وتيرتك. بلا إعلانات، بلا حساب، وبلا إزعاج.';

  @override
  String get onboardingWelcomeDedication =>
      'هذا التطبيق مُهدى إلى روح والدي، رحمه الله وغفر له. ويسّر الله لكم جميعًا تلاوة كتابه وحفظه.';

  @override
  String get onboardingReadTitle => 'قراءة القرآن';

  @override
  String get onboardingReadBody =>
      'المصحف كاملًا بألوان التجويد لترى الأحكام أثناء القراءة. استمع إلى القارئ الذي تختاره، وضع علامة لتتابع من حيث توقّفت.';

  @override
  String get onboardingReadHint =>
      'ثلاثة أجواء للقراءة: فاتح، وبنّي مريح للعين، وخلفية سوداء لليل.';

  @override
  String get onboardingReciteTitle => 'اتلُ وصحِّح';

  @override
  String get onboardingReciteBody =>
      'اتلُ بصوت مسموع: يستمع التطبيق ويلوّن كل كلمة تباعًا. الأخضر يعني أن الكلمة صحيحة، والبرتقالي أو الأحمر يعني أنها تحتاج مراجعة.';

  @override
  String get onboardingReciteHint =>
      'نسيت الكلمة؟ يُسمعك المُلقِّن الكلمة المنتظرة دون أي حكم عليك.';

  @override
  String get onboardingMemorizeTitle => 'الحفظ باللعب';

  @override
  String get onboardingMemorizeBody =>
      'تجعلك لعبة الحفظ تعيد بناء النص كلمة بعد كلمة. ولا تتوقف الجولة عند نهاية الصفحة، بل تستمر ما دمت تتابع.';

  @override
  String get onboardingMemorizeHint =>
      'يُحفظ رقمك القياسي في عدد الكلمات المتتالية من جولة إلى أخرى.';

  @override
  String get onboardingCoachTitle => 'مدرّبك';

  @override
  String get onboardingCoachBody =>
      'بعد كل تلاوة، تجد ما تعثّرت فيه: الكلمات المُشار إليها، وصوتك أنت في كل منها، وقراءة القارئ للمقارنة.';

  @override
  String get onboardingCoachHint =>
      'تُجمَع الأخطاء حسب السورة وحسب حكم التجويد، لترى ما يتكرّر منها.';

  @override
  String get onboardingDuasTitle => 'الأذكار والصلاة';

  @override
  String get onboardingDuasBody =>
      'أذكار اليوم والليلة بصوتها وعدد تكرارها. ومواقيت الصلاة محسوبة حسب موقعك، والأذان، واتجاه القبلة.';

  @override
  String get onboardingPrivacyTitle => 'بياناتك تبقى عندك';

  @override
  String get onboardingPrivacyBody =>
      'تُحلَّل تلاوتك على الجهاز ولا تُرسل إلى أي مكان. لا حساب، ولا إعلانات، ولا متتبّعات. ولا تُستخدم الشبكة إلا لتنزيل التلاوات التي تطلبها.';

  @override
  String get duaPourNousTileTitle => 'دعوة لنا';

  @override
  String get duaPourNousTileSubtitle => 'هذا التطبيق مجاني وبلا إعلانات';

  @override
  String get duaPourNousTitle => 'دعوة';

  @override
  String get duaPourNousIntro =>
      'كُتب هذا التطبيق ليكون تلاوة القرآن وتعلّمه أيسر عليك.';

  @override
  String get duaPourNousAskTitle => 'إن نفعك';

  @override
  String get duaPourNousAskBody => 'ادعُ لوالدي المتوفَّى ولأهلي.';

  @override
  String get duaPourNousDeceasedArabic =>
      'اللَّهُمَّ اغْفِرْ لَهُ وَارْحَمْهُ، وَعَافِهِ وَاعْفُ عَنْهُ، وَأَكْرِمْ نُزُلَهُ، وَوَسِّعْ مُدْخَلَهُ';

  @override
  String get duaPourNousDeceasedTranslation =>
      'اللهم اغفر له وارحمه، وعافه واعف عنه، وأكرم نزله، ووسّع مدخله.';

  @override
  String get duaPourNousDeceasedSource => 'رواه مسلم';

  @override
  String get duaPourNousForYouTitle => 'ولك أنت';

  @override
  String get duaPourNousForYouBody =>
      'يسّر الله عليك تلاوة كتابه، وثبّت حفظه في قلبك، وتقبّل منك سعيك، وجعل القرآن ربيع قلبك ونور صدرك.';

  @override
  String get duaPourNousForYouArabic =>
      'اللَّهُمَّ اجْعَلِ الْقُرْآنَ رَبِيعَ قَلْبِي، وَنُورَ صَدْرِي، وَجَلَاءَ حُزْنِي، وَذَهَابَ هَمِّي';

  @override
  String get duaPourNousShare => 'مشاركة التطبيق';

  @override
  String get duaPourNousShareText =>
      'قرآن كريم — اقرأ القرآن واتلُه واحفظه، بلا إعلانات.';

  @override
  String get navDuaPourNous => 'دعاء';
}
