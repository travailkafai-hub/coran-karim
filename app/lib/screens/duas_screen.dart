import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/player_provider.dart';
import '../services/quran_api.dart';
import '../theme/app_theme.dart';
import '../widgets/tajweed_text.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class Dua {
  final String titleFr;
  final String titleAr;
  final String textAr;
  final String translationFr;
  final String? source;     // e.g., "Al-Baqara 2:286"
  final String category;
  final int repeat;         // nombre de répétitions recommandées (défaut 1)
  // Renseignés uniquement pour les duas issues directement d'un verset —
  // permet de rejouer l'audio réciteur déjà présent dans l'app (pas de
  // source audio libre trouvée pour les invocations hadith, cf. recherche
  // 2026-07-10 : aucune API gratuite équivalente à quran.com pour celles-ci).
  final int? surahNumber;
  final int? ayahNumber;

  const Dua({
    required this.titleFr,
    required this.titleAr,
    required this.textAr,
    required this.translationFr,
    this.source,
    required this.category,
    this.repeat = 1,
    this.surahNumber,
    this.ayahNumber,
  });

  bool get isQuranic => surahNumber != null && ayahNumber != null;
}

enum DuaCategory { matin, soir, aprierespriere, coran, quotidien }

const _kCategories = [
  (id: 'tout',     label: 'Tout',          icon: Icons.apps_rounded),
  (id: 'matin',    label: 'Matin',         icon: Icons.wb_sunny_rounded),
  (id: 'soir',     label: 'Soir',          icon: Icons.nightlight_round),
  (id: 'priere',   label: 'Après prière',  icon: Icons.mosque_rounded),
  (id: 'coran',    label: 'Du Coran',      icon: Icons.menu_book_rounded),
  (id: 'quotidien',label: 'Quotidien',     icon: Icons.refresh_rounded),
];

const _kDuas = [
  // ── Coran ──
  Dua(
    titleFr: 'Dua de conclusion du Coran',
    titleAr: 'دعاء ختم القرآن',
    textAr: 'رَبَّنَا لَا تُزِغْ قُلُوبَنَا بَعْدَ إِذْ هَدَيْتَنَا وَهَبْ لَنَا مِن لَّدُنكَ رَحْمَةً ۚ إِنَّكَ أَنتَ الْوَهَّابُ',
    translationFr: 'Seigneur, ne laisse pas nos cœurs dévier après que Tu nous as guidés. Accorde-nous Ta miséricorde car Tu es le Grand Donateur.',
    source: 'Āl ʿImrān 3:8',
    category: 'coran',
    surahNumber: 3, ayahNumber: 8,
  ),
  Dua(
    titleFr: 'Demande de pardon et de miséricorde',
    titleAr: 'طلب المغفرة والرحمة',
    textAr: 'رَبَّنَا ظَلَمْنَا أَنفُسَنَا وَإِن لَّمْ تَغْفِرْ لَنَا وَتَرْحَمْنَا لَنَكُونَنَّ مِنَ الْخَاسِرِينَ',
    translationFr: 'Seigneur, nous avons lésé nos âmes et si Tu ne nous pardonnes pas et ne nous fais pas miséricorde, nous serons du nombre des perdants.',
    source: 'Al-Aʿrāf 7:23',
    category: 'coran',
    surahNumber: 7, ayahNumber: 23,
  ),
  Dua(
    titleFr: 'Demande de science utile',
    titleAr: 'دعاء طلب العلم',
    textAr: 'رَبِّ زِدْنِي عِلْمًا',
    translationFr: 'Seigneur, accrois mon savoir.',
    source: 'Ṭāhā 20:114',
    category: 'coran',
    surahNumber: 20, ayahNumber: 114,
  ),
  Dua(
    titleFr: 'Prière pour la famille',
    titleAr: 'الدعاء للذرية',
    textAr: 'رَبَّنَا هَبْ لَنَا مِنْ أَزْوَاجِنَا وَذُرِّيَّاتِنَا قُرَّةَ أَعْيُنٍ وَاجْعَلْنَا لِلْمُتَّقِينَ إِمَامًا',
    translationFr: 'Seigneur, donne-nous, de nos époux et de nos descendants, la joie des yeux, et fais de nous un modèle pour les pieux.',
    source: 'Al-Furqān 25:74',
    category: 'coran',
    surahNumber: 25, ayahNumber: 74,
  ),
  Dua(
    titleFr: 'Ayat Al-Kursi',
    titleAr: 'آية الكرسي',
    textAr: 'اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ',
    translationFr: 'Allah, point de divinité à part Lui, le Vivant, Celui qui subsiste par Lui-même. Ni somnolence ni sommeil ne Le saisissent. À Lui appartient ce qui est dans les cieux et ce qui est sur la terre.',
    source: 'Al-Baqara 2:255',
    category: 'coran',
    surahNumber: 2, ayahNumber: 255,
  ),

  // ── Matin ──
  Dua(
    titleFr: 'Invocation du matin',
    titleAr: 'ذكر الصباح',
    textAr: 'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ',
    translationFr: 'Nous sommes entrés dans le matin, et le Royaume appartient à Allah. Toute louange est due à Allah. Il n\'y a de divinité qu\'Allah, Seul, sans associé.',
    source: 'Rapporté par Abou Dawoud',
    category: 'matin',
  ),
  Dua(
    titleFr: 'Seigneur du matin et du soir',
    titleAr: 'دعاء المساء والصباح',
    textAr: 'اللَّهُمَّ بِكَ أَصْبَحْنَا وَبِكَ أَمْسَيْنَا وَبِكَ نَحْيَا وَبِكَ نَمُوتُ وَإِلَيْكَ النُّشُورُ',
    translationFr: 'Ô Allah, c\'est par Toi que nous commençons le matin, que nous entrons dans le soir, que nous vivons, que nous mourons, et c\'est vers Toi que sera la résurrection.',
    source: 'Rapporté par At-Tirmidhi',
    category: 'matin',
  ),
  Dua(
    titleFr: 'Sayyid al-Istighfar (le maître de la demande de pardon)',
    titleAr: 'سيد الاستغفار',
    textAr: 'اللّهـمَّ أَنْتَ رَبِّـي لا إلهَ إلاّ أَنْتَ ، خَلَقْتَنـي وَأَنا عَبْـدُك ، وَأَنا عَلـى عَهْـدِكَ وَوَعْـدِكَ ما اسْتَـطَعْـت ، أَعـوذُبِكَ مِنْ شَـرِّ ما صَنَـعْت ، أَبـوءُ لَـكَ بِنِعْـمَتِـكَ عَلَـيَّ وَأَبـوءُ بِذَنْـبي فَاغْفـِرْ لي فَإِنَّـهُ لا يَغْـفِرُ الذُّنـوبَ إِلاّ أَنْتَ .',
    translationFr: 'Ô Allah, Tu es mon Seigneur, il n\'y a de divinité que Toi. Tu m\'as créé et je suis Ton serviteur, je m\'en tiens à Ton pacte et à Ta promesse autant que je le peux. Je cherche refuge auprès de Toi contre le mal que j\'ai commis. Je reconnais devant Toi Ton bienfait envers moi, et je reconnais mon péché : pardonne-moi, car nul ne pardonne les péchés sauf Toi.',
    source: 'Rapporté par Al-Boukhari',
    category: 'matin',
    repeat: 1,
  ),
  Dua(
    titleFr: 'Allah me suffit',
    titleAr: 'حسبي الله',
    textAr: 'حَسْبِـيَ اللّهُ لا إلهَ إلاّ هُوَ عَلَـيهِ تَوَكَّـلتُ وَهُوَ رَبُّ العَرْشِ العَظـيم.',
    translationFr: 'Allah me suffit, il n\'y a de divinité que Lui. C\'est en Lui que je place ma confiance, et Il est le Seigneur du Trône immense.',
    source: 'Rapporté par At-Tirmidhi',
    category: 'matin',
    repeat: 7,
  ),
  Dua(
    titleFr: 'La ilaha illa Allah (grande récompense)',
    titleAr: 'التهليل',
    textAr: 'لَا إلَه إلّا اللهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءِ قَدِيرِ.',
    translationFr: 'Il n\'y a de divinité qu\'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange, et Il est capable de toute chose.',
    source: 'Rapporté par Al-Boukhari et Mouslim (×100 = équivalent à affranchir dix esclaves)',
    category: 'matin',
    repeat: 100,
  ),
  Dua(
    titleFr: 'Gloire à Allah',
    titleAr: 'التسبيح',
    textAr: 'سُبْحـانَ اللهِ وَبِحَمْـدِهِ.',
    translationFr: 'Gloire et pureté à Allah, et louange à Lui.',
    source: 'Rapporté par Al-Boukhari et Mouslim',
    category: 'matin',
    repeat: 100,
  ),
  Dua(
    titleFr: 'Demande de pardon (formule longue)',
    titleAr: 'الاستغفار',
    textAr: 'أسْتَغْفِرُ اللهَ العَظِيمَ الَّذِي لاَ إلَهَ إلاَّ هُوَ، الحَيُّ القَيُّومُ، وَأتُوبُ إلَيهِ.',
    translationFr: 'Je demande pardon à Allah, l\'Immense, il n\'y a de divinité que Lui, le Vivant, Celui qui subsiste par Lui-même, et je me repens à Lui.',
    source: 'Rapporté par Abou Dawoud et At-Tirmidhi',
    category: 'matin',
    repeat: 3,
  ),
  Dua(
    titleFr: 'Les trois sourates protectrices',
    titleAr: 'المعوذات',
    textAr: 'بِسْمِ اللهِ الرَّحْمنِ الرَّحِيم قُلْ هُوَ ٱللَّهُ أَحَدٌ، ٱللَّهُ ٱلصَّمَدُ، لَمْ يَلِدْ وَلَمْ يُولَدْ، وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ. بِسْمِ اللهِ الرَّحْمنِ الرَّحِيم قُلْ أَعُوذُ بِرَبِّ ٱلْفَلَقِ، مِن شَرِّ مَا خَلَقَ، وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ، وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ، وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ. بِسْمِ اللهِ الرَّحْمنِ الرَّحِيم قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ، مَلِكِ ٱلنَّاسِ، إِلَٰهِ ٱلنَّاسِ، مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ، ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ، مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ.',
    translationFr: 'Dis : Il est Allah, Unique. Allah, Le Seul à être imploré pour ce que nous désirons. Il n\'a jamais engendré, n\'a pas été engendré non plus. Et nul n\'est égal à Lui. Dis : Je cherche protection auprès du Seigneur de l\'aube naissante, contre le mal des êtres qu\'Il a créés, contre le mal de l\'obscurité quand elle s\'approfondit, contre le mal de celles qui soufflent sur les nœuds, et contre le mal de l\'envieux quand il envie. Dis : Je cherche protection auprès du Seigneur des hommes, le Souverain des hommes, le Dieu des hommes, contre le mal du mauvais conseiller furtif, qui souffle le mal dans les poitrines des hommes, qu\'il soit des djinns ou des hommes.',
    source: 'Sourates Al-Ikhlas, Al-Falaq, An-Nas — Rapporté par Abou Dawoud et At-Tirmidhi',
    category: 'matin',
    repeat: 3,
  ),

  // ── Soir ──
  Dua(
    titleFr: 'Protection du soir',
    titleAr: 'ذكر المساء',
    textAr: 'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ',
    translationFr: 'Nous sommes entrés dans le soir, et le Royaume appartient à Allah. Toute louange est due à Allah. Il n\'y a de divinité qu\'Allah, Seul, sans associé.',
    source: 'Rapporté par Abou Dawoud',
    category: 'soir',
  ),
  Dua(
    titleFr: 'Prise à témoin du soir',
    titleAr: 'الإشهاد المسائي',
    textAr: 'اللّهُـمَّ إِنِّـي أَمسيتُ أُشْـهِدُك ، وَأُشْـهِدُ حَمَلَـةَ عَـرْشِـك ، وَمَلَائِكَتَكَ ، وَجَمـيعَ خَلْـقِك ، أَنَّـكَ أَنْـتَ اللهُ لا إلهَ إلاّ أَنْـتَ وَحْـدَكَ لا شَريكَ لَـك ، وَأَنَّ ُ مُحَمّـداً عَبْـدُكَ وَرَسـولُـك.',
    translationFr: 'Ô Allah, je Te prends à témoin en ce début de soirée, ainsi que les Anges qui portent Ton Trône, Tes anges et toutes Tes créatures, que Tu es Allah, il n\'y a de divinité que Toi, Seul, sans associé, et que Muhammad est Ton serviteur et Ton Messager.',
    source: 'Rapporté par Abou Dawoud',
    category: 'soir',
    repeat: 4,
  ),
  Dua(
    titleFr: 'Les trois sourates protectrices',
    titleAr: 'المعوذات',
    textAr: 'بِسْمِ اللهِ الرَّحْمنِ الرَّحِيم قُلْ هُوَ ٱللَّهُ أَحَدٌ، ٱللَّهُ ٱلصَّمَدُ، لَمْ يَلِدْ وَلَمْ يُولَدْ، وَلَمْ يَكُن لَّهُۥ كُفُوًا أَحَدٌۢ. بِسْمِ اللهِ الرَّحْمنِ الرَّحِيم قُلْ أَعُوذُ بِرَبِّ ٱلْفَلَقِ، مِن شَرِّ مَا خَلَقَ، وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ، وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ، وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ. بِسْمِ اللهِ الرَّحْمنِ الرَّحِيم قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ، مَلِكِ ٱلنَّاسِ، إِلَٰهِ ٱلنَّاسِ، مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ، ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ، مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ.',
    translationFr: 'Dis : Il est Allah, Unique. Allah, Le Seul à être imploré pour ce que nous désirons. Il n\'a jamais engendré, n\'a pas été engendré non plus. Et nul n\'est égal à Lui. Dis : Je cherche protection auprès du Seigneur de l\'aube naissante, contre le mal des êtres qu\'Il a créés, contre le mal de l\'obscurité quand elle s\'approfondit, contre le mal de celles qui soufflent sur les nœuds, et contre le mal de l\'envieux quand il envie. Dis : Je cherche protection auprès du Seigneur des hommes, le Souverain des hommes, le Dieu des hommes, contre le mal du mauvais conseiller furtif, qui souffle le mal dans les poitrines des hommes, qu\'il soit des djinns ou des hommes.',
    source: 'Sourates Al-Ikhlas, Al-Falaq, An-Nas — Rapporté par Abou Dawoud et At-Tirmidhi',
    category: 'soir',
    repeat: 3,
  ),
  Dua(
    titleFr: 'Sur la disposition naturelle de l\'Islam',
    titleAr: 'على الفطرة',
    textAr: 'أَمْسَيْـنا عَلَى فِطْرَةِ الإسْلاَمِ، وَعَلَى كَلِمَةِ الإِخْلاَصِ، وَعَلَى دِينِ نَبِيِّنَا مُحَمَّدٍ صَلَّى اللهُ عَلَيْهِ وَسَلَّمَ، وَعَلَى مِلَّةِ أَبِينَا إبْرَاهِيمَ حَنِيفاً مُسْلِماً وَمَا كَانَ مِنَ المُشْرِكِينَ.',
    translationFr: 'Nous voici au soir sur la disposition naturelle de l\'Islam, sur la parole de la sincérité, sur la religion de notre Prophète Muhammad — paix et bénédiction sur lui —, et sur la voie de notre père Abraham, monothéiste sincère et soumis, qui n\'était pas du nombre des associateurs.',
    source: 'Rapporté par Ahmad',
    category: 'soir',
    repeat: 1,
  ),

  // ── Après prière ──
  Dua(
    titleFr: 'Tasbih après la prière',
    titleAr: 'التسبيح بعد الصلاة',
    textAr: 'سُبْحَانَ اللَّهِ، وَالْحَمْدُ لِلَّهِ، وَاللَّهُ أَكْبَرُ',
    translationFr: 'Gloire à Allah (×33), Louange à Allah (×33), Allah est le Plus Grand (×33).',
    source: 'Rapporté par Mouslim',
    category: 'priere',
    repeat: 33,
  ),
  Dua(
    titleFr: 'Demande de pardon après la prière',
    titleAr: 'الاستغفار بعد الصلاة',
    textAr: 'أَسْتَغْفِرُ اللَّهَ ، أَسْتَغْفِرُ اللَّهَ ، أَسْتَغْفِرُ اللَّهَ',
    translationFr: 'Je demande pardon à Allah (×3).',
    source: 'Rapporté par Mouslim',
    category: 'priere',
    repeat: 3,
  ),
  Dua(
    titleFr: 'La ilaha illa Allah après la prière',
    titleAr: 'تهليل بعد الصلاة',
    textAr: 'لا إله إلا الله وحـده لا شريك له، له الملك وله الحمد، يحيـي ويمـيت وهو على كل شيء قدير.',
    translationFr: 'Il n\'y a de divinité qu\'Allah, Seul, sans associé. À Lui la royauté, à Lui la louange. Il fait vivre et fait mourir, et Il est capable de toute chose.',
    source: 'Rapporté par At-Tirmidhi — dix fois après la prière de l\'aube et du couchant',
    category: 'priere',
    repeat: 10,
  ),
  Dua(
    titleFr: 'Aide pour Ton invocation',
    titleAr: 'دعاء معاذ بن جبل',
    textAr: 'اللهم أعني على ذكرك وشكرك وحسن عبادتك.',
    translationFr: 'Ô Allah, aide-moi à T\'invoquer, à Te remercier, et à T\'adorer de la meilleure manière.',
    source: 'Rapporté par Abou Dawoud (hadith de Mou\'adh ibn Jabal)',
    category: 'priere',
    repeat: 1,
  ),
  Dua(
    titleFr: 'Préservation du Feu',
    titleAr: 'دعاء الإجارة من النار',
    textAr: 'اللهم أجرني من النار.',
    translationFr: 'Ô Allah, préserve-moi du Feu.',
    source: 'Rapporté par Abou Dawoud — sept fois après la prière de l\'aube et du couchant',
    category: 'priere',
    repeat: 7,
  ),

  // ── Quotidien ──
  Dua(
    titleFr: 'En entrant à la mosquée',
    titleAr: 'دعاء دخول المسجد',
    textAr: 'اللَّهُمَّ افْتَحْ لِي أَبْوَابَ رَحْمَتِكَ',
    translationFr: 'Ô Allah, ouvre-moi les portes de Ta miséricorde.',
    source: 'Rapporté par Mouslim',
    category: 'quotidien',
  ),
  Dua(
    titleFr: 'Avant de manger',
    titleAr: 'دعاء الأكل',
    textAr: 'بِسْمِ اللَّهِ وَعَلَى بَرَكَةِ اللَّهِ',
    translationFr: 'Au nom d\'Allah et avec la bénédiction d\'Allah.',
    source: 'Rapporté par Abou Dawoud',
    category: 'quotidien',
  ),
  Dua(
    titleFr: 'Après avoir mangé',
    titleAr: 'دعاء بعد الأكل',
    textAr: 'الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنَا وَسَقَانَا وَجَعَلَنَا مُسْلِمِينَ',
    translationFr: 'Louange à Allah qui nous a nourris, abreuvés, et fait Musulmans.',
    source: 'Rapporté par Abou Dawoud & At-Tirmidhi',
    category: 'quotidien',
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class DuasScreen extends ConsumerStatefulWidget {
  const DuasScreen({super.key});
  @override
  ConsumerState<DuasScreen> createState() => _DuasScreenState();
}

class _DuasScreenState extends ConsumerState<DuasScreen> {
  String _activeCategory = 'tout';

  List<Dua> get _filtered => _activeCategory == 'tout'
      ? _kDuas
      : _kDuas.where((d) => d.category == _activeCategory).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: NestedScrollView(
        headerSliverBuilder: (_, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.green900,
            foregroundColor: AppColors.cream,
            title: Text('الأذكار والأدعية',
                textDirection: TextDirection.rtl,
                style: GoogleFonts.scheherazadeNew(
                    fontSize: 22, color: AppColors.brassLight)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: _CategoryBar(
                active: _activeCategory,
                onSelect: (c) => setState(() => _activeCategory = c),
              ),
            ),
          ),
        ],
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _filtered.length,
          itemBuilder: (context, i) => _DuaCard(dua: _filtered[i]),
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String active;
  final void Function(String) onSelect;
  const _CategoryBar({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          itemCount: _kCategories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final cat = _kCategories[i];
            final sel = cat.id == active;
            return GestureDetector(
              onTap: () => onSelect(cat.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? AppColors.brass : AppColors.green800,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat.icon, size: 14,
                        color: sel ? AppColors.green900 : AppColors.cream),
                    const SizedBox(width: 6),
                    Text(cat.label,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: sel ? AppColors.green900 : AppColors.cream,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class _DuaCard extends ConsumerStatefulWidget {
  final Dua dua;
  const _DuaCard({required this.dua});
  @override
  ConsumerState<_DuaCard> createState() => _DuaCardState();
}

class _DuaCardState extends ConsumerState<_DuaCard> {
  bool _expanded = false;
  // Compteur de répétitions (demande utilisateur 2026-07-10 : pouvoir taper
  // à chaque récitation pour savoir où on en est / quand c'est terminé).
  // Volontairement en mémoire seule (pas persisté) : c'est un suivi de
  // séance en cours, pas un historique.
  int _repeatDone = 0;
  bool _audioLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cream300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() {
              _expanded = !_expanded;
              if (!_expanded) _repeatDone = 0;
            }),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Category dot
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _catColor(widget.dua.category),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.dua.titleFr,
                            style: GoogleFonts.fraunces(
                                fontSize: 14,
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600)),
                        Text(widget.dua.titleAr,
                            textDirection: TextDirection.rtl,
                            style: GoogleFonts.scheherazadeNew(
                                fontSize: 14, color: AppColors.green700)),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.inkLight,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (_expanded) ...[
            Divider(height: 1, color: AppColors.cream300),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Arabic text
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.green50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TajweedText(
                      textUthmani: widget.dua.textAr,
                      fontSize: 22,
                      lineHeight: 2.0,
                    ),
                  ),
                  // Écoute (duas coraniques uniquement — réutilise le
                  // réciteur déjà présent dans l'app ; aucune source audio
                  // libre trouvée pour les invocations hadith, cf. recherche
                  // 2026-07-10).
                  if (widget.dua.isQuranic) ...[
                    const SizedBox(height: 10),
                    _ListenButton(
                      loading: _audioLoading,
                      onTap: _playAudio,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Translation
                  Text(
                    widget.dua.translationFr,
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: AppColors.inkLight, height: 1.6),
                  ),
                  if (widget.dua.source != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.bookmark_outline,
                            size: 13, color: AppColors.brass),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(widget.dua.source!,
                              style: GoogleFonts.manrope(
                                  fontSize: 10,
                                  color: AppColors.brass,
                                  fontStyle: FontStyle.italic)),
                        ),
                      ],
                    ),
                  ],
                  // Compteur de répétitions.
                  if (widget.dua.repeat > 1) ...[
                    const SizedBox(height: 14),
                    _RepeatCounter(
                      done: _repeatDone,
                      target: widget.dua.repeat,
                      onTap: () => setState(() {
                        if (_repeatDone < widget.dua.repeat) _repeatDone++;
                      }),
                      onReset: () => setState(() => _repeatDone = 0),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _playAudio() async {
    final surah = widget.dua.surahNumber;
    final ayah = widget.dua.ayahNumber;
    if (surah == null || ayah == null || _audioLoading) return;
    setState(() => _audioLoading = true);
    try {
      final verses = await QuranApi.fetchVerses(surah);
      final verse = verses.firstWhere((v) => v.ayahNumber == ayah);
      await ref.read(playerProvider.notifier).play(verse, [verse]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lecture impossible : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _audioLoading = false);
    }
  }

  Color _catColor(String cat) {
    switch (cat) {
      case 'matin':    return Colors.orange;
      case 'soir':     return Colors.indigo;
      case 'priere':   return AppColors.green700;
      case 'coran':    return AppColors.brass;
      case 'quotidien':return Colors.teal;
      default:         return AppColors.inkLight;
    }
  }
}

class _ListenButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _ListenButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.brass.withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.brass),
                )
              else
                const Icon(Icons.play_circle_outline_rounded,
                    size: 16, color: AppColors.brass),
              const SizedBox(width: 6),
              Text('Écouter',
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.brass,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

/// Compteur de répétitions — demande utilisateur 2026-07-10 : pouvoir taper
/// à chaque récitation pour suivre où on en est et savoir quand c'est fini,
/// plutôt que de compter de tête (utile pour ×33, ×100...).
class _RepeatCounter extends StatelessWidget {
  final int done;
  final int target;
  final VoidCallback onTap;
  final VoidCallback onReset;
  const _RepeatCounter({
    required this.done,
    required this.target,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final complete = done >= target;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: complete ? null : onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: complete
                    ? AppColors.green700.withAlpha(30)
                    : AppColors.cream300.withAlpha(120),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: complete ? AppColors.green700 : AppColors.brass,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    complete
                        ? Icons.check_circle_rounded
                        : Icons.touch_app_rounded,
                    size: 18,
                    color: complete ? AppColors.green700 : AppColors.brass,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    complete ? 'Terminé — $target/$target' : '$done / $target',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: complete ? AppColors.green700 : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (done > 0) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded,
                size: 18, color: AppColors.inkLight),
            tooltip: 'Recommencer le compte',
          ),
        ],
      ],
    );
  }
}
