// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get preparationCommencerTest => 'ابدأ التجربة';

  @override
  String get preparationFermerExplication => 'إغلاق الشرح';

  @override
  String get preparationEssaiErreur =>
      'تعذر فتح التجربة. حاول مجددًا بعد قليل.';

  @override
  String get preparationEssaiMushaf => 'قراءة المصحف';

  @override
  String get preparationEssaiMushafSous => 'صفحات القرآن كما في المصحف الورقي';

  @override
  String get preparationConsigneMushaf =>
      'يفتح المصحف الورقي بملء الشاشة حسب الرواية المختارة: حفص أو ورش.\n\nالمس الصفحة للتقدم أو اسحب من اليسار إلى اليمين. اقرأ الصفحة اليمنى ثم اليسرى؛ يظهر تأثير تقليب الورقة بعد قراءة الصفحتين. اسحب في الاتجاه المعاكس للرجوع.\n\nتتيح العلامة أعلى الشاشة حفظ موضع الصفحة. اضغط مطولًا لاختيار الخط. يعيدك سهم الرجوع إلى التجارب.';

  @override
  String get preparationEnfantTitre => 'تعلّم مع طفلك';

  @override
  String get preparationEnfantSous => 'مقاطع صغيرة ولحظات تتشاركانها.';

  @override
  String get preparationEssaiEnfant => 'وضع الطفل';

  @override
  String get preparationEssaiEnfantSous => 'استمعا وردّدا وتقدّما معًا';

  @override
  String get preparationEnfantEcouter => 'الاستماع';

  @override
  String get preparationEnfantRepeter => 'الترديد';

  @override
  String get preparationEnfantAccompagner => 'المرافقة';

  @override
  String get preparationConsigneEnfant =>
      'اجلس مع طفلك لتجربة سورة الإخلاص، وهي سورة قصيرة.\n\nيقدّم التدريب مجموعات صغيرة من كلمتين. يستمع طفلك ثم يردّد بصوت مسموع، ويزداد المقطع تدريجيًا. خذا الوقت لإعادة الاستماع عند الحاجة.\n\nيُفعّل وضع الطفل الموجود في التطبيق لهذه التجربة فقط، وتُستعاد إعداداتك السابقة عند الخروج.\n\nقد تخطئ ملاحظات الذكاء الاصطناعي؛ رافق طفلك واستعن بمعلّم عند وجود صعوبات. لا يُستخدم الميكروفون إلا عند بدء التلاوة.';

  @override
  String get navQuran => 'القرآن';

  @override
  String get navDuas => 'الأذكار';

  @override
  String get navCoach => 'مدرّبي';

  @override
  String get navSettings => 'الإعدادات';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count آية',
      few: '$count آيات',
      two: 'آيتان',
      one: 'آية واحدة',
      zero: 'لا آيات',
    );
    return '$_temp0';
  }

  @override
  String get mindMapGoToVerse => 'الانتقال إلى الآية';

  @override
  String get mindMapThemeLabel => 'المحور الرئيسي';

  @override
  String get mindMapSourcesLabel => 'المصادر والتنبيهات';

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
  String get settingsRiwayaTitle => 'الرواية';

  @override
  String get settingsRiwayaHafs => 'حفص عن عاصم';

  @override
  String get settingsRiwayaWarsh => 'ورش عن نافع';

  @override
  String get settingsRiwayaChangeNotice =>
      'يُحفظ سجل التلاوة وتقدّم الحفظ لكل رواية على حدة. تغيير الرواية لا يمحو تقدّمك السابق.';

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
  String get settingsSectionVoicePersonalization => 'تخصيص التعرّف على صوتك';

  @override
  String get settingsVoiceCalibTitle => 'معايرة الصوت (الحروف المتشابهة)';

  @override
  String get settingsVoiceCalibSubtitle =>
      'سجّل نحو 14 كلمة بنطق صحيح ثم بخطأ متعمّد، مثل ص/س وط/ت، لإعداد عينات تخصيص التعرّف على صوتك.';

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
      other: 'التسجيلات المحفوظة: $count، اضغط للتصدير',
      many: '$count تسجيلًا محفوظًا، اضغط للتصدير',
      few: '$count تسجيلات محفوظة، اضغط لتصديرها',
      two: 'تسجيلان محفوظان، اضغط لتصديرهما',
      one: 'تسجيل واحد محفوظ، اضغط لتصديره',
      zero: 'لا توجد تسجيلات محفوظة',
    );
    return '$_temp0';
  }

  @override
  String get settingsExportStarted => 'بدأ التصدير — اختر أين ترسل الملف.';

  @override
  String get settingsDisputedTitle => 'التقييمات المعترض عليها';

  @override
  String get settingsDisputedEmpty =>
      'لا توجد اعتراضات بعد. للاعتراض على تقييم كلمة، استمع إلى تسجيلك ثم اختر «غير موافق» أسفل «صوتي».';

  @override
  String settingsDisputedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'التقييمات المعترض عليها: $count، اضغط للإرسال',
      many: '$count تقييمًا معترضًا عليه، اضغط للإرسال',
      few: '$count تقييمات معترض عليها، اضغط لإرسالها',
      two: 'تقييمان معترض عليهما، اضغط لإرسالهما',
      one: 'تقييم واحد معترض عليه، اضغط لإرساله',
      zero: 'لا توجد تقييمات معترض عليها',
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
      'تحدّد اللغة نصوص الواجهة والشروحات. يبقى القرآن بالعربية دائمًا، ولا تُعرض ترجمة مع الآيات عند اختيار الواجهة العربية.';

  @override
  String get settingsAboutSubtitle => 'الإصدار والمصادر والتراخيص والخصوصية';

  @override
  String get settingsValidate => 'تأكيد';

  @override
  String get settingsRepeatEngineSectionTitle => 'التكرار التدريجي';

  @override
  String get settingsAdultChunkWordCountTitle =>
      'كلمات المقطع التدريبي للبالغين';

  @override
  String settingsAdultChunkWordCountDescription(int max) {
    return 'حجم المقطع من 1 إلى $max كلمة. لا ينطبق هذا الإعداد على وضع الطفل، الذي يقسّم الآية إلى مجموعات من كلمتين، مع كلمة أخيرة منفردة إذا كان العدد فرديًا.';
  }

  @override
  String get settingsRepeatWindowSizeTitle => 'نافذة المراجعة (إعداد سابق)';

  @override
  String settingsRepeatWindowSizeDescription(int max) {
    return 'قيمة محفوظة من 1 إلى $max. لا تؤثر في التدريب الحالي، الذي يعيد المقطع من بداية الآية ويزيده تدريجيًا.';
  }

  @override
  String get commonConnectionRequired => 'يلزم الاتصال بالإنترنت';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get homeIdentifyTooltip => 'البحث عن آية بالصوت';

  @override
  String get homeFollowPrayerTooltip => 'متابعة التلاوة في الصلاة';

  @override
  String get surahMeccan => 'مكية';

  @override
  String get surahMedinan => 'مدنية';

  @override
  String surahMetaLine(int count, String place) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count آية',
      few: '$count آيات',
      two: 'آيتان',
      one: 'آية واحدة',
    );
    return '$_temp0 • $place';
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
  String get mushafFavorites => 'علامة القراءة';

  @override
  String get mushafMemorize => 'حفظ';

  @override
  String get mushafTranslation => 'ترجمة';

  @override
  String get mushafCoachAi => 'المدرّب الذكي';

  @override
  String get mushafMore => 'المزيد';

  @override
  String get mushafAnnotateButton => 'تظليل النص';

  @override
  String get mushafAnnotateEraser => 'ممحاة';

  @override
  String get mushafAnnotateDone => 'تم';

  @override
  String get mushafAutoScroll => 'تمرير تلقائي';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get shazamListening =>
      'اقرأ أو شغّل تلاوة مسموعة.\nيبحث التطبيق عن الآية ويفتح موضعها.';

  @override
  String get shazamSearching => 'جارٍ البحث عن الآية…';

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
  String get shazamGoThere => 'فتح موضع الآية';

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
  String get readingSettingsRepeatSection => 'تكرار الاستماع';

  @override
  String get readingSettingsRepeatDescription =>
      'أعد الاستماع إلى الآية أو السورة بالعدد الذي تختاره.';

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
  String get readingSettingsKindleSection => 'سمة القراءة';

  @override
  String get readingSettingsKindleDescription =>
      'اختر خلفية القراءة: فاتحة، أو بلون الورق، أو سوداء للقراءة الليلية.';

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
  String get tajwidHelpVoiceFeedbackPrompt =>
      'هل توافق على تقييم التطبيق لهذه الكلمة؟';

  @override
  String get tajwidHelpVoiceFeedbackNeedsListen =>
      'استمع إلى \"صوتي\" أعلاه لإبداء رأيك';

  @override
  String get tajwidHelpVoiceThumbsUp => 'موافق، هذا خطأ فعلي';

  @override
  String get tajwidHelpVoiceThumbsDown => 'غير موافق، لقد نطقتها صحيحة';

  @override
  String get tajwidHelpVoiceFeedbackThanks => 'شكرًا، حُفظت ملاحظتك';

  @override
  String get tajwidHelpRetryThisWord => 'إعادة تلاوة هذه الكلمة';

  @override
  String tajwidHelpCorrectedHeard(String text) {
    return 'تم التصحيح — المسموع: \"$text\"';
  }

  @override
  String get tajwidHelpNothingHeard => '(لم يُسمع شيء)';

  @override
  String tajwidHelpNotYetHeard(String text) {
    return 'لم يتعرّف التطبيق على النطق المطلوب بعد. المسموع: «$text». حاول مجددًا بهدوء.';
  }

  @override
  String get tajwidHelpAnalyzing => 'التحليل جارٍ…';

  @override
  String get tajwidHelpFinishRecording => 'إنهاء التسجيل';

  @override
  String get tajwidHelpRecordThisWord => 'سجّل هذه الكلمة';

  @override
  String get tajwidHelpRecordWithContext =>
      'قل أيضًا الكلمات المحيطة بها، وليس هذه الكلمة فقط:';

  @override
  String get tajwidHelpRecordWithContextNone =>
      'قل هذه الكلمة، فهي أول كلمة في الآية.';

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
  String get tajwidRuleSlntName => 'حرف غير منطوق';

  @override
  String get tajwidRuleSlntExplanation => 'يُكتب ولا يُنطق.';

  @override
  String get duasScreenTitle => 'الأذكار والأدعية';

  @override
  String get duasSearchHint => 'ابحث عن دعاء أو كلمة أو مصدر…';

  @override
  String get duasRadiosTitre => 'إذاعة الأذكار';

  @override
  String get duasRadioMatin => 'أذكار الصباح';

  @override
  String get duasRadioSoir => 'أذكار المساء';

  @override
  String get duasRadioSousTitre => 'بث مباشر — يتطلب اتصالاً بالإنترنت';

  @override
  String get duasRadioErreur => 'تعذّر التشغيل. تحقق من اتصالك.';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دعاء',
      few: '$count أدعية',
      two: 'دعاءان',
      one: 'دعاء واحد',
      zero: 'لا أدعية',
    );
    return '$_temp0';
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
  String get duaShowVirtue => 'فضل هذا الدعاء';

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
      'اقرأ الآية بصوت مسموع. يسجّل التطبيق تلاوتك ويحدّد الكلمات التي قد تحتاج إلى تدريب.';

  @override
  String get coachListeningLecture => 'جارٍ تسجيل التلاوة وتحليلها…';

  @override
  String get coachDoneLecture => 'تم تحليل القراءة';

  @override
  String get coachTapToRead => 'اضغط واقرأ الآية';

  @override
  String get coachAlreadyKnow => 'أحفظ هذه الآية';

  @override
  String get coachTrainButton => 'تدرّب';

  @override
  String get coachSubStepListen => 'استماع';

  @override
  String get coachSubStepImitate => 'ترديد مع القارئ';

  @override
  String get coachSubStepRepeat => 'تكرار';

  @override
  String get coachListenInstruction => 'استمع إلى القارئ. تابع كل كلمة بعينيك.';

  @override
  String get coachListeningAudio => 'الاستماع جارٍ…';

  @override
  String get coachTapToListen => 'اضغط للاستماع';

  @override
  String get coachMoveToImitation => 'الترديد مع القارئ';

  @override
  String get coachImitateInstruction =>
      'شغّل التلاوة وردّد مع القارئ، متابعًا نطقه وإيقاعه ومواضع وقفه.';

  @override
  String get coachSpeakAlong => 'ردّد مع القارئ';

  @override
  String get coachLaunchAndImitate => 'تشغيل التلاوة والترديد معها';

  @override
  String get coachImitatedNext => 'جاهز للترديد وحدي';

  @override
  String get coachIncrementalInstruction =>
      'استمع ثم ردّد. يزداد طول المقطع تدريجيًا مع تقدّمك.';

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
    return 'دقة التعرّف: $pct٪';
  }

  @override
  String coachFingerprintScore(int pct) {
    return 'بصمة الصوت: $pct٪';
  }

  @override
  String get coachMemorizedConfirmed => 'اجتزت اختبار الحفظ!';

  @override
  String get coachKeepTraining => 'واصل التدريب';

  @override
  String coachGapSummary(int baseline, int control, String delta) {
    return 'القراءة الأولى: $baseline٪ ← من الحفظ: $control٪ ($delta٪)';
  }

  @override
  String get coachMsgLectureExcellent =>
      'أحسنت! لم يرصد التطبيق صعوبة واضحة في هذه القراءة.';

  @override
  String coachMsgLectureDifficultWords(String words) {
    return 'أشار التطبيق إلى هذه الكلمات: $words\n\nاستمع إليها وراجع نطقها أثناء التدريب.';
  }

  @override
  String get coachMsgLectureHesitant =>
      'لوحظ بعض التردد. سيساعدك التدريب على تصحيحه.';

  @override
  String get coachMsgTrainGreat =>
      'أحسنت! تكرارك صحيح. يمكنك الآن اختبار حفظك دون النص.';

  @override
  String get coachMsgTrainGoodStart =>
      'بداية جيدة. أعد المحاولة لتثبيت الكلمات التي تردّدت فيها.';

  @override
  String get coachMsgTrainRestart =>
      'استمع مجددًا وردّد مع القارئ، ثم حاول وحدك.';

  @override
  String get coachMsgControlMashallah =>
      'ما شاء الله! تحسّنت نتيجتك في التلاوة من الحفظ مقارنة بالقراءة الأولى. واصل المراجعة لتثبيت الآية.';

  @override
  String get coachMsgControlVeryGood =>
      'تلاوة جيدة جدًا! واصل المراجعة بانتظام لترسيخها.';

  @override
  String get coachMsgControlGoodPath =>
      'أنت تتقدّم. واصل التكرار والمراجعة لتثبيت الآية.';

  @override
  String get coachMsgControlKeepTraining =>
      'واصل التدريب، وارجع إلى القراءة لمراجعة الكلمات التي تحتاج إلى اهتمام.';

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
  String get homeReprendreTitre => 'تابِع القراءة';

  @override
  String homeReprendreSous(String sourate, int verset) {
    return '$sourate · الآية $verset';
  }

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
  String get coachHubPickerMemorizeSubtitle => 'اختر السورة التي تريد حفظها';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count خطأ',
      few: '$count أخطاء',
      two: 'خطآن',
      one: 'خطأ واحد',
      zero: 'لا أخطاء مسجّلة',
    );
    return 'الآية $ayah · $_temp0';
  }

  @override
  String get coachHubExplanationTooltip => 'شرح';

  @override
  String get coachHubReviewVerseTooltip => 'مراجعة هذه الآية';

  @override
  String get coachHubErrorNoteExplainer =>
      'يشير تصنيف «الحروف» أو «الحركات» إلى اختلاف في النطق. أما تصنيف «التجويد» فهو استنتاج عند وجود اختلاف لا يفسّره حرف أو حركة في كلمة لها حكم تجويد؛ وليس دليلًا قاطعًا على خطأ في أداء الحكم.';

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
  String get coachHubGameSectionSubtitle => 'تدرّب على ترتيب الكلمات من حفظك';

  @override
  String get coachHubGameActionTitle => 'لعبة تسلسل الكلمات';

  @override
  String get coachHubGameActionSubtitle =>
      'اختر الكلمة التالية وأكمل الآية من حفظك';

  @override
  String get coachHubPickerGameTitle => 'لعبة تسلسل الكلمات';

  @override
  String get coachHubPickerGameSubtitle => 'اختر السورة التي تريد حفظها باللعب';

  @override
  String get memorizationGameTitle => 'لعبة تسلسل الكلمات';

  @override
  String get memorizationGameRestartVerseTooltip => 'إعادة هذه الآية';

  @override
  String get memorizationGameRulesHint =>
      'اختر الكلمة التالية. الإجابة الخاطئة تخصم 5 نقاط وتعيدك إلى الآية السابقة.';

  @override
  String get memorizationGameBridgeHint => 'خاتمة الآية السابقة';

  @override
  String get memorizationGameWrongAnswerBanner =>
      'العودة إلى الآية السابقة (-5)';

  @override
  String get memorizationGameStyleChaining => 'تسلسل الكلمات';

  @override
  String get memorizationGameStyleVerseStart => 'بداية الآية';

  @override
  String get memorizationGameStyleVerseStartHint =>
      'اعثر على أول كلمتين من هذه الآية.';

  @override
  String get memorizationGameStyleVerseStartTooShort =>
      'لا يحتوي هذا الجزء على آيات كافية لهذا الوضع.';

  @override
  String memorizationGameVerseProgress(int current, int total) {
    return 'الآية $current من $total';
  }

  @override
  String get memorizationGameCompleteTitle => 'اكتملت السورة!';

  @override
  String memorizationGameCompleteBody(String surah) {
    return 'أكملت جميع مراحل $surah. أعد اللعب لتثبيت حفظك.';
  }

  @override
  String get memorizationGameBackToHub => 'رجوع';

  @override
  String memorizationGameWordsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الكلمات المتتالية: $count',
      many: '$count كلمة متتالية',
      few: '$count كلمات متتالية',
      two: 'كلمتان متتاليتان',
      one: 'كلمة واحدة صحيحة',
      zero: 'لم تُكمل أي كلمة بعد',
    );
    return '$_temp0';
  }

  @override
  String memorizationGameRecordLabel(int best, int total) {
    return 'الرقم القياسي: $best من $total';
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
      other: 'الكلمات المتتالية: $count',
      many: '$count كلمة متتالية',
      few: '$count كلمات متتالية',
      two: 'كلمتان متتاليتان',
      one: 'كلمة واحدة صحيحة',
      zero: 'لم تُكمل أي كلمة هذه المرة',
    );
    return '$_temp0. أفضل نتيجة: $best';
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
  String get qiblaKmToMecca => 'كم إلى مكة';

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
      'هذا الإعداد خاص بمتابعة الصلاة. الوضع المتساهل يقبل فروقًا أكبر في النطق، والوضع الصارم يتطلّب تطابقًا أدق.';

  @override
  String get prayerFollowSouffleurTitle => 'التلقين التلقائي';

  @override
  String prayerFollowSouffleurSubtitle(int seconds) {
    return 'يُسمعك الكلمة المتوقعة بعد $seconds ثانية من الصمت، دون إلزامك بإعادتها لمتابعة التلاوة.';
  }

  @override
  String get prayerFollowTitle => 'متابعة الصلاة';

  @override
  String get prayerFollowSettingsTooltip => 'الإعدادات';

  @override
  String get prayerFollowWaitingFatiha => 'بانتظار بداية الفاتحة…';

  @override
  String get prayerFollowIdentifying =>
      'انتهت الفاتحة. جارٍ التعرّف على السورة التالية…';

  @override
  String get prayerFollowListening => 'الاستماع جارٍ…';

  @override
  String get prayerFollowTapToStart =>
      'الاستماع متوقف. اضغط على الميكروفون لإعادة المحاولة.';

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
      'هذا الدليل للتذكير، وليس فتوى. تختلف بعض تفاصيل المناسك باختلاف المذاهب الفقهية. عند الشك، اسأل مرشدًا مؤهّلًا أو المشرف على مجموعتك.';

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
  String get riteMarkAsDone => 'تأكيد إتمام الخطوة';

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
    return 'المقاطع قيد التحليل: $count…';
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
  String get recitationTapToStart => 'ابدأ تلاوة الآيات تباعًا';

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
      'اختر القارئ الذي تفضّله. تُشغّل التلاوة عبر الإنترنت ما لم تنزّل السورة للاستماع دون اتصال.';

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
    return 'اكتمل تسجيل المقاطع: $count. أُضيفت إلى عيناتك الموثّقة؛ صدّرها من الإعدادات لإعداد تخصيص التعرّف على صوتك.';
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
    return 'مقاطع المعايرة المحفوظة: $count. يمكنك تصديرها من الإعدادات لتخصيص النموذج.';
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
  String get ruleNotMeasuredLabel => 'لم تُقَس الدقة بعد';

  @override
  String get tajwidRulesTitle => 'التحقق من التلاوة';

  @override
  String tajwidRulesLoadError(String error) {
    return 'خطأ: $error';
  }

  @override
  String get tajwidRulesHarakatTitle => 'التدقيق في الحركات';

  @override
  String get tajwidRulesHarakatSubtitle =>
      'عند تعطيله، لا تُحتسب الفروق في الحركات القصيرة أخطاءً.';

  @override
  String get tajwidRulesConfusablesTitle => 'التسامح مع الحروف المتقاربة';

  @override
  String get tajwidRulesConfusablesSubtitle =>
      'يسمح التقييم ببعض الخلط بين الحروف، مثل ص/س وط/ت، للتدرّب في وضع الطفل. هذا تساهل في التقييم، وليس إقرارًا بصحة النطق.';

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
  String get tajwidPresetAdult => 'للبالغين';

  @override
  String get tajwidPresetChild => 'للأطفال';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count آية',
      few: '$count آيات',
      two: 'آيتان',
      one: 'آية واحدة',
      zero: 'لا آيات',
    );
    return '$_temp0';
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
    return '، $count لم يتعرّف عليها التطبيق';
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
  String get karaokeVerificationModeForcedTajwid => 'وضع التجويد';

  @override
  String get karaokeVerificationModeSubtitle =>
      'إعدادات التجويد والبالغين والأطفال';

  @override
  String get karaokeSensitivityTitle => 'حساسية التصحيح';

  @override
  String get karaokeSensitivityDescription =>
      'أكثر تساهلاً: يقبل الحركات/النطق غير الدقيق باللون الأخضر. أكثر صرامة: يتطلب نطقًا أقرب إلى النموذج.';

  @override
  String get karaokeEngineTitle => 'مطابقة الصوت بالنص (GOP)';

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
      'عند رصد كلمة تحتاج إلى تصحيح، تتوقف المتابعة مؤقتًا لتسمع نطق القارئ، ثم تُستأنف تلقائيًا.';

  @override
  String get karaokeStrictnessTitle => 'صرامة التصحيح';

  @override
  String get karaokeStrictnessStrictSubtitle =>
      'صارم — يُعاد الأحمر والبرتقالي (غير الدقيق) معًا';

  @override
  String get karaokeStrictnessTolerantSubtitle =>
      'متساهل — يُعاد الأحمر فقط (الكلمة الخاطئة)';

  @override
  String get karaokeFollowFreeTitle => 'المتابعة دون إلزام بالإعادة';

  @override
  String get karaokeFollowFreeOnSubtitle =>
      'تستمر المتابعة حتى إن لم تُعِد الكلمة بدقة.';

  @override
  String get karaokeFollowFreeOffSubtitle =>
      'تتطلب متابعة التلاوة إعادة الكلمة التي رصد التطبيق خطأً فيها.';

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
  String get karaokeRestartTooltip => 'إعادة';

  @override
  String get karaokeReferenceRecordingTitle => 'تلاوة مرجعية';

  @override
  String get karaokeReferenceRecordingBody =>
      'اقرأ المقطع بإيقاعك المعتاد. إذا كانت نتيجة التعرّف كافية، يحفظ التطبيق وقفاتك وإيقاعك للاستفادة منها في تلاواتك اللاحقة لهذا المقطع.';

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
  String get karaokeFinalizing => 'جارٍ إكمال التحليل…';

  @override
  String get karaokePausedHint => 'متوقف مؤقتًا — المس ⏸ للاستئناف';

  @override
  String get karaokeEcouteEnCours => 'أسمعك… واصل';

  @override
  String get karaokeEcouteBientot => 'ستظهر الألوان بعد الكلمات الأولى';

  @override
  String get karaokeListeningHint => 'التطبيق يستمع إلى تلاوتك…';

  @override
  String get karaokeFinishedHint => 'المس الشاشة لإعادة البدء';

  @override
  String get karaokeReferenceStartHint =>
      'اضغط لإعادة محاولة تسجيل التلاوة المرجعية';

  @override
  String get karaokeTapToStartHint => 'استعد للتلاوة';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count آية',
      few: '$count آيات',
      two: 'آيتان',
      one: 'آية واحدة',
    );
    return '$number · $name · $_temp0';
  }

  @override
  String surahOrnamentMeta(String place, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count آية',
      few: '$count آيات',
      two: 'آيتان',
      one: 'آية واحدة',
    );
    return '$place · $_temp0';
  }

  @override
  String get miniPlayerRepeatOff => 'تكرار';

  @override
  String miniPlayerRepeatVerse(int count) {
    return 'الآية × $count';
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
  String portionUnknownSurah(int n) {
    return 'سورة $n';
  }

  @override
  String portionSurahHizb(String surah, int hizb) {
    return '$surah · حزب $hizb';
  }

  @override
  String portionSurahHizbQuarter(String surah, int hizb, int quarter) {
    return '$surah · حزب $hizb — ربع $quarter/٤';
  }

  @override
  String portionSurahHizbHalf(String surah, int hizb, String half) {
    return '$surah · حزب $hizb ($half)';
  }

  @override
  String get portionHalfFirst => 'النصف الأول';

  @override
  String get portionHalfSecond => 'النصف الثاني';

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
  String get reciterDownloadsTitle => 'تنزيل التلاوات';

  @override
  String reciterDownloadAll(String size) {
    return 'تنزيل الكل ($size)';
  }

  @override
  String get reciterDownloadStop => 'إيقاف';

  @override
  String get reciterDeleteAllTitle => 'حذف التلاوات المنزّلة';

  @override
  String get reciterDeleteAllBody =>
      'ستُحذف من الجهاز جميع التلاوات المنزّلة لهذا القارئ. سيظل الاستماع إليها متاحًا عبر الإنترنت.';

  @override
  String get reciterDeleteAllConfirm => 'حذف';

  @override
  String reciterStorageUsed(String size, String done, String total) {
    return '$size على هذا الجهاز • $done/$total سورة دون اتصال';
  }

  @override
  String get reciterDownloadFailed =>
      'تعذّر التنزيل. تحقّق من اتصالك؛ الملفات التي اكتمل تنزيلها محفوظة.';

  @override
  String reciterDownloadingProgress(String done, String total) {
    return 'جارٍ التنزيل… $done/$total آية';
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
      'الميكروفون متوقف. اضغط لاستئناف التلاوة.';

  @override
  String get tajwidHelpClose => 'إغلاق';

  @override
  String get mushafBookmarksTitle => 'علامات القراءة';

  @override
  String get mushafNoBookmarks =>
      'لا توجد علامات قراءة بعد. اضغط على أيقونة العلامة لحفظ موضع الآية التي توقفت عندها.';

  @override
  String readingSettingsGroupSize(int n) {
    return '١ — ما يُكرَّر: $n آية في كل مرة';
  }

  @override
  String readingSettingsGroupRepeats(int n) {
    return '٢ — مرات تكرار المجموعة: $n';
  }

  @override
  String readingSettingsGlobalRepeats(int n) {
    return '٣ — مرات تكرار السورة كاملة: $n';
  }

  @override
  String get readingSettingsUnlimited => 'بلا حد';

  @override
  String get readingSettingsLoopSection => 'تكرار الاستماع';

  @override
  String get readingSettingsLoopDescription =>
      'مثال: 3 آيات تُكرَّر 3 مرات، والسورة كاملة تُعاد 3 مرات.';

  @override
  String get aboutTitle => 'حول التطبيق';

  @override
  String get aboutTagline =>
      'اقرأ القرآن وتدرّب على تلاوته بتحليل صوتي على جهازك.';

  @override
  String aboutVersionLine(String version, String build) {
    return 'الإصدار $version (بناء $build)';
  }

  @override
  String get aboutSectionPrivacy => 'بياناتك';

  @override
  String get aboutPrivacyIntro =>
      'تُحلّل تلاوتك على هاتفك. لا يتطلب التطبيق حسابًا، ولا يعرض إعلانات أو يستخدم أدوات تتبّع.';

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
      'الإنترنت — يُستخدم لجلب محتوى القرآن والتلاوات والأذكار وتشغيل الإذاعات، بحسب ما تفتحه أو تختار تنزيله.';

  @override
  String get aboutSectionAsr => 'كيف يحلّل التطبيق تلاوتك؟';

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
  String get onboardingSkip => 'تخطٍّ';

  @override
  String get onboardingNext => 'التالي';

  @override
  String get onboardingStart => 'لنبدأ';

  @override
  String get onboardingWelcomeTitle => 'مرحبًا';

  @override
  String get onboardingWelcomeBody =>
      'اقرأ القرآن وتدرّب على تلاوته وحفظه بالوتيرة التي تناسبك. بلا إعلانات أو حساب.';

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
      'اختر خلفية فاتحة، أو بلون الورق، أو سوداء للقراءة الليلية.';

  @override
  String get onboardingReciteTitle => 'تلاوة مع التصحيح';

  @override
  String get onboardingReciteBody =>
      'اقرأ بصوت مسموع. يلوّن التطبيق الكلمات بحسب ما يتعرّف عليه: الأخضر للكلمة المقبولة، والبرتقالي أو الأحمر لما يحتاج إلى مراجعة. وقد يخطئ التطبيق في التقييم.';

  @override
  String get onboardingReciteHint =>
      'نسيت كلمة؟ استمع إلى نطق القارئ للكلمة المتوقعة ثم تابع.';

  @override
  String get onboardingMemorizeTitle => 'التدريب على الحفظ';

  @override
  String get onboardingMemorizeBody =>
      'استمع إلى المقطع ثم ردّده بصوت مسموع. يتابع التطبيق تلاوتك ويزيد طول المقطع تدريجيًا حتى تتدرّب على الآية كاملة.';

  @override
  String get onboardingMemorizeHint =>
      'ثم ينتقل التدريب إلى المراجعة: يُخفى النص، وتتلو وحدك.';

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
      'تصفّح أذكار اليوم والليلة مع عدّاد للتكرار وصوت عند توفره. وتابع مواقيت الصلاة والأذان واتجاه القبلة بحسب موقعك.';

  @override
  String get onboardingPrivacyTitle => 'بياناتك تبقى عندك';

  @override
  String get onboardingPrivacyBody =>
      'تُحلّل تلاوتك على الجهاز. لا حساب ولا إعلانات ولا أدوات تتبّع. تحتاج بعض المحتويات والتلاوات والإذاعات إلى الإنترنت، وتصدير تسجيلاتك إجراء تختاره بنفسك.';

  @override
  String get duaPourNousTileTitle => 'ادعُ لنا';

  @override
  String get duaPourNousTileSubtitle => 'هذا التطبيق مجاني وبلا إعلانات';

  @override
  String get duaPourNousTitle => 'الدعاء ونشر التطبيق';

  @override
  String get duaPourNousIntro =>
      'أُنشئ هذا التطبيق ليسهّل عليك قراءة القرآن وتعلّم تلاوته وحفظه.';

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
  String get duaPourNousHassanatTitle => 'شارِك في الحسنات';

  @override
  String get duaPourNousHassanatBody =>
      'انشُر التطبيق بين من حولك: كل من يستعمله لقراءة القرآن أو حفظه فلك نصيب من أجره، إن شاء الله.';

  @override
  String get duaPourNousShare => 'انشُر التطبيق';

  @override
  String get duaPourNousArguments => 'بلا إعلانات · بلا حساب · بلا تتبّع';

  @override
  String get duaPourNousShareText =>
      'قرآن كريم — اقرأ القرآن واتلُه واحفظه، بلا إعلانات.';

  @override
  String get navDuaPourNous => 'دعاء';

  @override
  String get settingsContactTitle => 'تواصل معنا';

  @override
  String get settingsContactSubtitle => 'آراء وملاحظات واقتراحات';

  @override
  String get coachTrainInstruction =>
      'اتلُ الآية كاملة من البداية. أعد المحاولة كلما احتجت.';

  @override
  String get coachTapToTrain => 'اضغط واتلُ الآية';

  @override
  String get coachTrainListening => 'أستمع إليك...';

  @override
  String get coachTrainDone => 'انتهت الجولة';

  @override
  String get coachMoveToControl => 'اختبار الحفظ';

  @override
  String get coachObjectifTitle => 'هدفي';

  @override
  String coachObjectifStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أيام المواظبة المتتالية: $count',
      many: '$count يومًا متتاليًا',
      few: '$count أيام متتالية',
      two: 'يومان متتاليان',
      one: 'يوم واحد من المواظبة',
      zero: 'ابدأ المواظبة اليوم',
    );
    return '$_temp0';
  }

  @override
  String coachObjectifWeekProgress(int faits, String total) {
    return 'أرباع الحزب هذا الأسبوع: $faits من $total';
  }

  @override
  String get coachObjectifEmptyTitle => 'لا يوجد هدف محدد';

  @override
  String get coachObjectifEmptyBody =>
      'حدّد هدفًا للحفظ لتتابع تقدّمك وأيام مواظبتك.';

  @override
  String get coachObjectifSetButton => 'تحديد هدف';

  @override
  String get coachObjectifSheetTitle => 'هدف الحفظ';

  @override
  String coachObjectifQuartsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أرباع الحزب: $count',
      many: '$count ربع حزب',
      few: '$count أرباع حزب',
      two: 'ربعان من الحزب',
      one: 'ربع حزب واحد',
      zero: 'لا أرباع حزب',
    );
    return '$_temp0';
  }

  @override
  String coachObjectifResteAnneesMois(int annees, int mois) {
    String _temp0 = intl.Intl.pluralLogic(
      annees,
      locale: localeName,
      other: '$annees سنة',
      many: '$annees سنة',
      few: '$annees سنوات',
      two: 'سنتان',
      one: 'سنة واحدة',
      zero: 'أقل من سنة',
    );
    String _temp1 = intl.Intl.pluralLogic(
      mois,
      locale: localeName,
      other: ' و$mois شهر',
      many: ' و$mois شهرًا',
      few: ' و$mois أشهر',
      two: ' وشهران',
      one: ' وشهر واحد',
      zero: '',
    );
    return 'المدة المتبقية: $_temp0$_temp1';
  }

  @override
  String coachObjectifResteMois(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الأشهر المتبقية: $count',
      many: 'بقي $count شهرًا',
      few: 'بقيت $count أشهر',
      two: 'بقي شهران',
      one: 'بقي شهر واحد',
      zero: 'أقل من شهر متبقٍ',
    );
    return '$_temp0';
  }

  @override
  String coachObjectifResteJours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الأيام المتبقية: $count',
      many: 'بقي $count يومًا',
      few: 'بقيت $count أيام',
      two: 'بقي يومان',
      one: 'بقي يوم واحد',
      zero: 'الموعد اليوم',
    );
    return '$_temp0';
  }

  @override
  String get coachObjectifEcheanceDepassee =>
      'انتهى الأجل — يمكنك منح نفسك وقتًا إضافيًا';

  @override
  String coachObjectifAnneesLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حفظ القرآن كاملًا في $count سنة',
      many: 'حفظ القرآن كاملًا في $count سنة',
      few: 'حفظ القرآن كاملًا في $count سنوات',
      two: 'حفظ القرآن كاملًا في سنتين',
      one: 'حفظ القرآن كاملًا في سنة واحدة',
    );
    return '$_temp0';
  }

  @override
  String coachObjectifAnneesCourt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سنة',
      many: '$count سنة',
      few: '$count سنوات',
      two: 'سنتان',
      one: 'سنة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get coachObjectifSheetDureeTitle => 'ما المدة التي تناسبك؟';

  @override
  String get coachObjectifQuartUnite => 'ربع حزب';

  @override
  String coachObjectifResteLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أرباع الحزب المتبقية: $count من 240',
      many: 'بقي $count ربع حزب من 240',
      few: 'بقيت $count أرباع حزب من 240',
      two: 'بقي ربعان من 240',
      one: 'بقي ربع حزب واحد من 240',
      zero: 'اكتمل هدف حفظ القرآن',
    );
    return '$_temp0';
  }

  @override
  String coachObjectifRythmeDetail(String parJour, String parSemaine) {
    return 'الهدف بأرباع الحزب: نحو $parJour يوميًا و$parSemaine أسبوعيًا.';
  }

  @override
  String get coachObjectifPeriodeCeMois => 'هذا الشهر';

  @override
  String get coachObjectifPeriodeCetteAnnee => 'هذه السنة';

  @override
  String get coachObjectifPeriodeCoranEntier => 'القرآن كاملاً';

  @override
  String get coachDashProgressMoreHorizons => 'عرض السنة والقرآن كاملاً';

  @override
  String get coachRythmeTenu => 'ملتزم بالهدف';

  @override
  String get coachRythmeDerape => 'تأخّر يسير';

  @override
  String get coachRythmeARattraper => 'تحتاج إلى تدارك التأخر';

  @override
  String get coachObjectifPeriodeJour => 'في اليوم';

  @override
  String get coachObjectifPeriodeSemaine => 'في الأسبوع';

  @override
  String get coachObjectifPeriodeMois => 'في الشهر';

  @override
  String coachObjectifPeriodProgress(int faits, int total, String periode) {
    return 'أرباع الحزب: $faits من $total، $periode';
  }

  @override
  String get coachObjectifMiniEvolutionCaption => 'آخر 7 أيام';

  @override
  String get coachObjectifToday => 'اليوم';

  @override
  String get karaokePhraseFinTitle => 'عبارة ختام السورة';

  @override
  String get karaokePhraseFinSubtitle =>
      'توقّع « صدق الله العظيم » بعد الآية الأخيرة';

  @override
  String get coachDashTodayLabel => 'اليوم';

  @override
  String get coachDashTodayDone => 'تم';

  @override
  String get coachDashTodayPending => 'جارٍ';

  @override
  String get coachDashStreakLabel => 'أيام المواظبة';

  @override
  String coachDashStreakValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count يوم',
      many: '$count يومًا',
      few: '$count أيام',
      two: 'يومان',
      one: 'يوم واحد',
      zero: 'لم تبدأ بعد',
    );
    return '$_temp0';
  }

  @override
  String get coachDashPointsLabel => 'النقاط';

  @override
  String coachDashProgressTitle(String periode) {
    return 'التقدّم — $periode';
  }

  @override
  String coachDashProgressRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أرباع الحزب المتبقية: $count',
      many: 'بقي $count ربع حزب',
      few: 'بقيت $count أرباع حزب',
      two: 'بقي ربعان من الحزب',
      one: 'بقي ربع حزب واحد',
      zero: 'تم بلوغ الهدف',
    );
    return '$_temp0';
  }

  @override
  String get coachAccompagnementSousTitre =>
      'تذكيرات يومية، ومراجعة الآيات التي تحتاج إلى تدريب، وتنبيه للمحافظة على المواظبة.';

  @override
  String get coachNiveauTitle => 'المرافقة';

  @override
  String get coachNiveauAMonRythme => 'بوتيرتي';

  @override
  String get coachNiveauRegulier => 'منتظم';

  @override
  String get coachNiveauExigeant => 'صارم';

  @override
  String get coachObjectifValider => 'تأكيد';

  @override
  String get coachPortionsTitle => 'الحفظ حسب السورة';

  @override
  String get coachRefreshTooltip => 'تحديث';

  @override
  String coachPortionsError(Object error) {
    return 'تعذّر تحميل المقاطع: $error';
  }

  @override
  String get coachPortionsEmpty =>
      'لم تبدأ متابعة أي مقطع بعد. ستظهر هنا السور أو مقاطع الأحزاب التي تتلوها، مع تقدّمك المتراكم.';

  @override
  String coachPortionWordsCovered(int reached, int total) {
    return 'الكلمات التي تلوتها: $reached/$total';
  }

  @override
  String coachPortionWordsAcquired(int green, int total) {
    return '$green/$total كلمة متقنة';
  }

  @override
  String coachPortionCoveredSuffix(int reached) {
    return ' · $reached متلوة';
  }

  @override
  String coachSessionWordsCorrect(int green, int reached) {
    return '$green/$reached كلمة صحيحة';
  }

  @override
  String get coachSessionAccuracyLabel => 'من الكلمات المتلوة';

  @override
  String get coachPortionFullCoverage => ' · تمت تلاوة المقطع كاملًا';

  @override
  String get coachPortionAccuracyLabel => 'من كلمات المقطع';

  @override
  String get coachPortionBadgeLabel => 'مقطع مُتقَن';

  @override
  String coachPortionGameRecord(int best, int total) {
    return 'أفضل سلسلة: $best من $total';
  }

  @override
  String coachPortionBilanPercent(int percent) {
    return '$percent٪ من الكلمات صحيحة';
  }

  @override
  String coachPortionBilanDetail(int green, int reached, int total) {
    return 'الكلمات المقبولة: $green، من أصل $reached كلمة تلوتها. مجموع كلمات المقطع: $total. الكلمة التي اعترضت على تقييمها تُحتسب صحيحة.';
  }

  @override
  String get coachPortionNoneRecitedYet =>
      'لم تُتلَ أي كلمة في هذا المقطع بعد.';

  @override
  String get coachPortionNothingToReview =>
      'لا توجد كلمات للمراجعة في هذا المقطع.';

  @override
  String get coachWordUnavailable => 'الآية غير متاحة';

  @override
  String get coachPortionHistorySection => 'كلمات تحسّنت في تلاوتها';

  @override
  String get coachPortionCorrectedBadge => 'صُحّحت';

  @override
  String get coachPortionContestedBadge => 'معترَض عليها';

  @override
  String get coachTogglePassageAutoTitre => 'الانتقال التلقائي';

  @override
  String get coachTogglePassageAutoDetail =>
      'عند نجاح الاختبار يبدأ تدريب الآية التالية من تلقاء نفسه.';

  @override
  String get coachToggleCumulTitre => 'اختبار تراكمي';

  @override
  String get coachToggleCumulDetail =>
      'يشمل الاختبار كل الآيات المحفوظة منذ بداية الجلسة.';

  @override
  String get commonStop => 'إيقاف';

  @override
  String get mushafTajwidBanner =>
      'متابعة التجويد: الأحكام التي لم يرصدها التطبيق تظهر بالبنفسجي';

  @override
  String get mushafClearAllTooltip => 'مسح الكل';

  @override
  String get mushafClearAllTitle => 'مسح الكل؟';

  @override
  String get mushafClearAllBody =>
      'ستُحذف جميع علامات التظليل والخطوط التي أضفتها في كل السور. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get mushafBarTajwid => 'تجويد';

  @override
  String get mushafBarChain => 'تسلسل';

  @override
  String get mushafBarMap => 'خريطة';

  @override
  String get mushafPaperTooltip => 'المصحف الورقي';

  @override
  String get mushafBookmarkHere => 'ضع علامة هنا';

  @override
  String get mushafBookmarkRemove => 'إزالة العلامة';

  @override
  String get tajwidHelpTwoVersesBefore => 'بدءًا من آيتين قبلها';

  @override
  String get tajwidHelpStepTraining => 'تدريب تدريجي';

  @override
  String get tajwidHelpListenImitate => 'استمع، قلّد، تحقّق — في هذه الآية';

  @override
  String get tajwidHelpGameOrSteps => 'لعبة أو تدريب تدريجي';

  @override
  String get settingsDiagnosticSubtitle =>
      'يحفظ تفاصيل التلاوة لأغراض التشخيص. يُفضّل إبقاؤه معطّلًا في الاستخدام العادي.';

  @override
  String get settingsMushafScriptTitle => 'خط المصحف';

  @override
  String get settingsPrayerTimesTitle => 'مواقيت الصلاة';

  @override
  String get settingsPrayerTimesSubtitle => 'أذان مُجدوَل، وتنبيه قبل الفجر';

  @override
  String get coachGemmeAmethyste => 'أميثيست';

  @override
  String get coachGemmeSaphir => 'ياقوت أزرق';

  @override
  String get coachGemmeTopaze => 'توباز';

  @override
  String get coachGemmeEmeraude => 'زمرّد';

  @override
  String coachGemmeSeuil(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تلاوة كاملة',
      many: '$count تلاوة كاملة',
      few: '$count تلاوات كاملة',
      two: 'تلاوتان كاملتان',
      one: 'تلاوة كاملة',
    );
    return '$_temp0';
  }

  @override
  String get settingsBluetoothMicTitle => 'ميكروفون سماعة البلوتوث';

  @override
  String get settingsBluetoothMicOn => 'مُفعّل — جودة أقل: البلوتوث يضغط الصوت';

  @override
  String get settingsBluetoothMicOff =>
      'معطّل (موصى به): يُستخدم ميكروفون الهاتف لالتقاط صوت أوضح.';

  @override
  String get tajwidRulesScreenTitle => 'التحقق من التلاوة';

  @override
  String get tajwidRulesBetaSection => 'أحكام التجويد (تجريبي)';

  @override
  String get tajwidRulesBetaNote =>
      'يتحقّق التطبيق من الأحكام بحسب الوضع المختار أعلاه. النتائج إرشادية وقد تخطئ.';

  @override
  String get tajwidRulesBetaBadge => 'تجريبي';

  @override
  String get tajwidRulesBetaWarning =>
      'التعرّف على هذا الحكم ما زال غير دقيق. قد يستدعي مراجعة الكلمة، لكنه لا يكفي وحده لاعتبارها صحيحة.';

  @override
  String get contactTitle => 'تواصل معنا';

  @override
  String get contactIntro =>
      'لديك سؤال أو اقتراح أو مشكلة؟ اكتب رسالتك هنا، ثم افتحها في تطبيق البريد لمراجعتها وإرسالها.';

  @override
  String get contactSubjectLabel => 'الموضوع (اختياري)';

  @override
  String get contactSubjectDefault => 'القرآن الكريم — رسالة';

  @override
  String get contactMessageHint => 'اكتب رسالتك…';

  @override
  String get coachStepsTitle => 'مراحل التلاوة';

  @override
  String get coachStepsExplain =>
      'تحصل على علامة عند إتقان كلمات المقطع كلها. ومع تكرار تلاوته كاملًا، تحصل على شارة حجر كريم يتغيّر لونها بحسب عدد التلاوات المكتملة.';

  @override
  String get coachMyRecitations => 'تلاواتي';

  @override
  String coachArchiveUnreadable(String erreur) {
    return 'تعذّر فتح سجل التلاوات: $erreur';
  }

  @override
  String get coachNoRecitationYet =>
      'لا توجد جلسة مسجّلة بعد. بعد استخدام التلاوة مع التصحيح، ستجد هنا الكلمات التي أشار إليها التطبيق وتسجيلاتك المتاحة.';

  @override
  String get coachDeleteRecitationTitle => 'حذف هذه التلاوة؟';

  @override
  String get coachDeleteRecitationBody =>
      'ستُحذف نتيجة هذه الجلسة وتسجيلات كلماتها نهائيًا. أما سجل المدرّب التراكمي (إحصاءات كل سورة) فلا يتأثر.';

  @override
  String get coachNoFlaggedWord =>
      'لم يحدّد التطبيق كلمات تحتاج إلى مراجعة في هذه التلاوة.';

  @override
  String coachNotRecitedYet(int nombre) {
    return 'لم تُتلَ بعد — $nombre';
  }

  @override
  String get coachContinuePortion => 'تلاوة هذا المقطع مجددًا';

  @override
  String get coachDeleteRecitation => 'حذف هذه التلاوة';

  @override
  String get coachMindMap => 'الخريطة الذهنية';

  @override
  String get coachStartSurah => 'ابدأ هذه السورة';

  @override
  String get scriptTajwidColors => 'ألوان التجويد';

  @override
  String get scriptSheetTitle => 'خط المصحف';

  @override
  String get scriptSheetExplain =>
      'يغيّر الخط شكل الكتابة في عرض الصفحة، ولا يغيّر الرواية أو نص الآيات. بعض الخطوط لا تُظهر جميع علامات الوقف والسجدة ونهاية الآية؛ راجع المعاينة قبل الاختيار.';

  @override
  String get prayerTimesTitle => 'مواقيت الصلاة';

  @override
  String get prayerTimesNext => 'الصلاة القادمة';

  @override
  String prayerTimesDetected(String methode) {
    return 'طريقة الحساب المحدّدة: $methode';
  }

  @override
  String get qiblaMagneticWarning =>
      'تم رصد مجال مغناطيسي — ابتعد عن المعدن أو المغناطيس (الغطاء، الحامل، السمّاعة…)، ثم أعد المعايرة برسم الرقم 8 بالهاتف.';

  @override
  String prayerNotifSoon(String priere, int minutes) {
    return 'قريبًا — $priere بعد $minutes د';
  }

  @override
  String get mushafTajwidOnPage => 'التجويد على الصفحة';

  @override
  String get mushafTajwidWarshIndisponible =>
      'التحقّق من أحكام التجويد متاح حاليًا لرواية حفص فقط، ولا يتوفر لرواية ورش في هذا الإصدار.';

  @override
  String get settingsNoiseSuppressTitle => 'تقليل ضوضاء الميكروفون';

  @override
  String get prayerNameFajr => 'الفجر';

  @override
  String get prayerNameDhuhr => 'الظهر';

  @override
  String get prayerNameAsr => 'العصر';

  @override
  String get prayerNameMaghrib => 'المغرب';

  @override
  String get prayerNameIsha => 'العشاء';

  @override
  String get prayerMethodMwl => 'رابطة العالم الإسلامي';

  @override
  String get prayerMethodUmmAlQura => 'أم القرى (الخليج)';

  @override
  String get prayerMethodEgyptian => 'الهيئة المصرية';

  @override
  String get prayerMethodFranceUoif => 'فرنسا (UOIF، ‏12°)';

  @override
  String get prayerInNow => 'الآن';

  @override
  String prayerInMinutes(int minutes) {
    return 'بعد $minutes د';
  }

  @override
  String prayerInHours(int heures) {
    return 'بعد $heures س';
  }

  @override
  String prayerInHoursMinutes(int minutes, int heures) {
    return 'بعد $heures س و$minutes د';
  }

  @override
  String get preparationLangueSous =>
      'اختر لغة الواجهة. يمكنك تغييرها لاحقًا من الإعدادات.';

  @override
  String get preparationRiwayaSous =>
      'اختر الرواية التي تتلو بها؛ يتبعها نص القرآن والقرّاء المتاحون.';

  @override
  String get preparationEcritureSous =>
      'عاين الخط أدناه واختر ما يناسب قراءتك في المصحف.';

  @override
  String get preparationOptionsTitre => 'بعض الخيارات';

  @override
  String get preparationOptionsSous =>
      'لا شيء إلزامي. يمكنك التخطي والعودة لاحقاً.';

  @override
  String get preparationModeSombre => 'الوضع الداكن';

  @override
  String get preparationToutModifiable =>
      'تبقى هذه الخيارات كلها قابلة للتعديل في الإعدادات. لن يُطلب الميكروفون ولا الموقع إلا عندما تحتاجهما إحدى الوظائف فعلاً.';

  @override
  String get preparationPasser => 'تخطٍّ';

  @override
  String get preparationRetour => 'رجوع';

  @override
  String get preparationSuivant => 'التالي';

  @override
  String get preparationCommencer => 'ابدأ';

  @override
  String get preparationFin => 'إنهاء';

  @override
  String get preparationReciteurSous =>
      'اختر قارئًا لسماع نموذج من بداية سورة البقرة. ستسمع تلاوته أثناء الاستماع والتصحيح الصوتي.';

  @override
  String get guidePasser => 'تخطي الدليل';

  @override
  String get guideRetour => 'رجوع';

  @override
  String get guideSuivant => 'التالي';

  @override
  String get guideFin => 'إنهاء';

  @override
  String get visiteCoranTexte =>
      'المصحف كاملاً. اضغط على سورة لقراءتها أو الاستماع إليها.';

  @override
  String get visiteDuasTexte =>
      'أدعية اليوم والصلاة والسفر، مرتبة حسب المناسبة.';

  @override
  String get visiteCoachTexte => 'متابعتك: ما قرأته، وما بقي للمراجعة.';

  @override
  String get visiteFinTitre => 'الدور عليك';

  @override
  String get visiteFinTexte =>
      'هذا كل شيء. يمكنك إعادة هذه الجولة متى شئت من الإعدادات.';

  @override
  String get guideDecouverteTitre => 'اكتشف التطبيق';

  @override
  String get guideDecouverteSous =>
      'جولة تفاعلية توضّح أهم الأدوات ومواضعها. يمكنك إيقافها في أي وقت.';

  @override
  String get guideRejouer => 'إعادة';

  @override
  String get guideChapitreGlobalTitre => 'نظرة عامة';

  @override
  String get guideChapitreGlobalResume =>
      'أقسام التطبيق الرئيسية في أربع خطوات.';

  @override
  String get guideChapitrePrieresTitre => 'الصلاة والقبلة';

  @override
  String get guideChapitrePrieresResume => 'اتجاه مكة، وأوقات الصلاة، والأذان.';

  @override
  String get guideChapitreDuasResume => 'الأدعية مرتبة حسب أوقات اليوم.';

  @override
  String get guideChapitreReglagesResume =>
      'اللغة والرواية والخط وإعدادات الخصوصية.';

  @override
  String get guidePriereAccueilTexte =>
      'وقت الصلاة القادمة واتجاه القبلة هنا، في الشاشة الرئيسية.';

  @override
  String get guideQiblaTexte =>
      'السهم يشير إلى مكة، ويصبح ذهبياً عند الاتجاه الصحيح.';

  @override
  String get guideHorairesTexte =>
      'اضبط طريقة حساب المواقيت والأذان والتذكير قبل الفجر من هنا.';

  @override
  String get guidePriereFinTexte =>
      'هذا كل شيء. يمكنك إعادة أي فصل من الإعدادات.';

  @override
  String get guideDuasUniversTexte =>
      'ستة أبواب: اليوم، والصلاة، والقرآن، والحياة اليومية، والقلب، والحج.';

  @override
  String get guideDuasCollectionsTitre => 'المجموعات';

  @override
  String get guideDuasCollectionsTexte =>
      'تجد داخل كل باب مجموعات بحسب المناسبة، مثل الاستيقاظ والنوم والسفر.';

  @override
  String get guideDuasAudioTitre => 'الاستماع';

  @override
  String get guideDuasAudioTexte =>
      'استمع إلى الدعاء عند توفر تسجيل له، واستخدم العدّاد لمتابعة عدد مرات ترديده.';

  @override
  String get guideReglagesLangueTexte =>
      'اختر العربية أو الفرنسية أو الإنجليزية. تتجه الواجهة من اليمين إلى اليسار عند اختيار العربية.';

  @override
  String get guideReglagesRiwayaTexte =>
      'اختر حفصًا أو ورشًا؛ يتبع نص القرآن والقرّاء المتاحون الرواية المختارة.';

  @override
  String get guideReglagesEcritureTexte =>
      'عاين خطوط المصحف المتاحة قبل اختيار الخط الأنسب لك.';

  @override
  String get guideReglagesViePriveeTitre => 'بياناتك';

  @override
  String get guideReglagesViePriveeTexte =>
      'كل شيء يجري على هاتفك. بلا حساب، وبلا إعلانات.';

  @override
  String get guideChapitreLectureTitre => 'قراءة القرآن';

  @override
  String get guideChapitreLectureResume =>
      'قائمة السور، والاستماع، والتمرير، والعلامات.';

  @override
  String get guideLectureListeTexte =>
      'السور المئة والأربع عشرة، مع عدد آياتها ومكان نزولها.';

  @override
  String get guideLectureEcouteTitre => 'الاستماع';

  @override
  String get guideLectureEcouteTexte => 'زر التشغيل يشغّل تلاوة السورة كاملة.';

  @override
  String get guideLectureDefilementTitre => 'المتابعة أثناء الاستماع';

  @override
  String get guideLectureDefilementTexte =>
      'النص يتمرّر وحده وتبقى الآية الجارية ظاهرة.';

  @override
  String get guideLectureSignetTitre => 'المتابعة من حيث توقفت';

  @override
  String get guideLectureSignetTexte =>
      'العلامة أعلى القائمة تعيدك إلى آخر قراءة.';

  @override
  String get guideChapitreMushafTitre => 'المصحف الورقي';

  @override
  String get guideChapitreMushafResume =>
      'اقرأ القرآن بتقسيم المصحف الورقي إلى ٦٠٤ صفحات.';

  @override
  String get guideMushafOuvrirTexte =>
      'يُفتح الغلاف على الصفحة التي توقفت عندها.';

  @override
  String get guideMushafTournerTitre => 'تقليب الصفحات';

  @override
  String get guideMushafTournerTexte =>
      'اسحب من اليسار إلى اليمين للتقدّم، كما في المصحف الحقيقي.';

  @override
  String get guideMushafEcritureTitre => 'تغيير الخط';

  @override
  String get guideMushafEcritureTexte =>
      'اضغط مطولًا على الصفحة لعرض الخطوط المتاحة واختيار أحدها.';

  @override
  String get guideChapitreRecitationTitre => 'تلاوة مع التصحيح';

  @override
  String get guideChapitreRecitationResume =>
      'التطبيق يستمع إلى تلاوتك وينبّه على الفروق.';

  @override
  String get guideRecitationDepartTexte =>
      'افتح سورة، ثم ابدأ التلاوة من شاشة القراءة.';

  @override
  String get guideRecitationCouleursTitre => 'ألوان الكلمات';

  @override
  String get guideRecitationCouleursTexte =>
      'بحسب تقييم التطبيق: الأخضر كلمة مقبولة، والبرتقالي نطق يحتاج إلى التحقق، والأحمر اختلاف يحتاج إلى مراجعة. قد يخطئ التقييم.';

  @override
  String get guideRecitationCorrectionTitre => 'التصحيح';

  @override
  String get guideRecitationCorrectionTexte =>
      'عند الانقطاع يعيد القارئ المقطع لتستأنف منه.';

  @override
  String get guideRecitationMicroTitre => 'الميكروفون';

  @override
  String get guideRecitationMicroTexte =>
      'يُطلب عند التلاوة لا قبلها. وكل التحليل يجري على الهاتف.';

  @override
  String get guideChapitreCoachResume =>
      'مقاطع التدريب وأيام المواظبة وهدف الحفظ وسجل التلاوات.';

  @override
  String get guideCoachPortionsTexte =>
      'تابع تقدّمك في كل مقطع: الكلمات المقبولة وما يحتاج إلى مراجعة.';

  @override
  String get guideCoachSerieTitre => 'أيام المواظبة';

  @override
  String get guideCoachSerieTexte =>
      'عدد الأيام المتتالية التي سجّلت فيها تلاوة. تبدأ سلسلة جديدة إذا فاتك يوم.';

  @override
  String get guideCoachMemoTitre => 'الحفظ';

  @override
  String get guideCoachMemoTexte =>
      'استمع وردّد لتثبيت الحفظ تدريجيًا، أو اختر لعبة تسلسل الكلمات للتدرّب على ترتيبها.';

  @override
  String get guideCoachSessionsTitre => 'السجل';

  @override
  String get guideCoachSessionsTexte =>
      'راجع نتيجة كل جلسة والكلمات التي أشار إليها التطبيق، واستمع إلى تسجيلاتك المتاحة.';

  @override
  String get guideChapitreAudioTitre => 'القرّاء والصوت';

  @override
  String get guideChapitreAudioResume =>
      'اختيار صوت، وتنزيله للاستماع دون اتصال.';

  @override
  String get guideAudioReciteurTitre => 'اختيار القارئ';

  @override
  String get guideAudioReciteurTexte =>
      'أصوات عدّة متاحة، والاختيار يسري على التطبيق كله.';

  @override
  String get guideAudioHorsLigneTitre => 'دون اتصال';

  @override
  String get guideAudioHorsLigneTexte =>
      'بعد تنزيل تلاوة السورة، يمكنك الاستماع إليها دون اتصال ما دامت محفوظة على الجهاز.';

  @override
  String get guideAudioNotifTitre => 'من الإشعار';

  @override
  String get guideAudioNotifTexte =>
      'يمكنك إيقاف التلاوة واستئنافها من الإشعار عند مغادرة التطبيق.';

  @override
  String get demoRecitationTitre => 'عرض توضيحي';

  @override
  String get demoRecitationBandeau =>
      'مثال مُعدّ مسبقاً. الميكروفون غير مستخدم، ولا يُسجَّل شيء، ولا يتغيّر تقدّمك.';

  @override
  String get demoRecitationLancer => 'ابدأ العرض';

  @override
  String get demoRecitationRejouer => 'إعادة';

  @override
  String get demoRecitationEnCours => 'جارٍ…';

  @override
  String get demoLegendeVert => 'صحيح';

  @override
  String get demoLegendeOrange => 'يحتاج إلى تحقق';

  @override
  String get demoLegendeRouge => 'اختلاف مرصود';

  @override
  String get guideChapitreDemoTitre => 'شاهد تلاوة';

  @override
  String get guideChapitreDemoResume =>
      'مثال مسجّل مسبقًا يوضّح ألوان التقييم والتصحيح واستئناف التلاوة.';

  @override
  String get guideDemoTexte =>
      'انظر كيف تتلوّن الكلمات تباعاً. هذا عرض توضيحي، وليس تلاوة حقيقية.';

  @override
  String get preparationRiwayaWarshNote =>
      'التحقّق الصوتي من أحكام التجويد غير متاح لرواية ورش في هذا الإصدار. تبقى قراءة المصحف والتلاوة مع تصحيح الكلمات متاحتين.';

  @override
  String get preparationEssaisTitre => 'جرّب الآن';

  @override
  String get preparationEssaisSous =>
      'اكتشف الأدوات على مقطع قصير، ويمكنك العودة إليها لاحقًا.';

  @override
  String get preparationEssaiReciter => 'تلاوة مع التصحيح';

  @override
  String get preparationEssaiReciterSous =>
      'اتلُ، والتطبيق يستمع ويلوّن كل كلمة';

  @override
  String get preparationEssaiTajwid => 'وضع التجويد';

  @override
  String get preparationEssaiTajwidSous => 'متابعة صوتية لأداء أحكام التجويد';

  @override
  String get preparationEssaiJeu => 'لعبة تسلسل الكلمات';

  @override
  String get preparationEssaiJeuSous => 'ابحث عن الكلمة التالية بين عدة كلمات';

  @override
  String get preparationConsigneJeu =>
      'تظهر الكلمة الأولى، ثم تختار ما بعدها من بين عدة كلمات. وعند الخطأ تظهر الكلمة الصحيحة، ثم تُستأنف الجولة من الآية السابقة.';

  @override
  String get preparationEssaiMemoriser => 'التدرّب على الحفظ';

  @override
  String get preparationEssaiMemoriserSous => 'استمع ثم ردِّد، على مراحل';

  @override
  String get preparationEssaiLire => 'اقرأ واستمع';

  @override
  String get preparationEssaiLireSous => 'النص والترجمة والتلاوة';

  @override
  String get preparationEssaisNote =>
      'لا يُطلب الميكروفون إلا إذا اخترت التلاوة.';

  @override
  String get preparationConsigneTajwid =>
      'اقرأ بصوت مسموع مع مراعاة أحكام التجويد.\n\nالأخضر: رصد التطبيق الأحكام المتوقعة. البنفسجي: لم يرصد حكمًا متوقعًا. دون لون: لا يوجد حكم يتابعه التطبيق في هذه الكلمة.\n\nهذه مؤشرات آلية قد تخطئ، ولا تغني عن التعلّم مع معلّم.';

  @override
  String get preparationConsigneReciter =>
      'اقرأ بصوت مسموع وبإيقاعك المعتاد. يستمع التطبيق إلى تلاوتك ويُلوّن الكلمات لمساعدتك على المراجعة.\n\nالأخضر: كلمة تعرّف عليها التطبيق على أنها صحيحة. البرتقالي: نطق يحتاج إلى التحقق. الأحمر: اختلاف رصده التطبيق.\n\nقد يخطئ التطبيق في التقييم؛ استعن بمعلّم عند الشك.';

  @override
  String get preparationConsigneMemoriser =>
      'استمع إلى المقطع ثم ردّده بصوت مسموع. يزداد طول المقطع تدريجيًا حتى تتدرّب على الآية كاملة، ثم يمكنك اختبار حفظك دون إظهار النص.';

  @override
  String get preparationConsigneLire =>
      'مرّر النص، واضغط على آية لسماعها، واضغط مطولاً لفتح قائمتها.';
}
