// ChGPT: same UI components as the app, navigated in a read-only tutorial.
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../screens/about_screen.dart';
import '../screens/contact_screen.dart';
import '../screens/coach_hub_screen.dart';
import '../screens/duas_screen.dart';
import '../screens/guide_apercus.dart';
import '../screens/mushaf_maquette_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/qibla_screen.dart';
import '../widgets/guide_interactif.dart';
import '../widgets/reading_settings_sheet.dart';

// Existing first-launch overview anchors, owned and cleared by HomeScreen.
/// ⚠️ INTERRUPTEUR UNIQUE — LES VISITES GUIDÉES SONT DÉSACTIVÉES (2026-09-14)
///
/// Décision utilisateur, après les avoir vues tourner : « du coup supprimer les
/// 57 étapes qui ne servent à rien ». Elles sont remplacées par l'étape
/// « Essaie tout de suite » de `preparation_screen.dart`, qui ouvre les VRAIS
/// écrans sur Al-Ikhlāṣ — quatre boutons qui font ESSAYER valent mieux que 57
/// étapes qui COMMENTENT.
///
/// DÉSACTIVÉ ET NON SUPPRIMÉ, exactement comme `kOnboardingActif` avant lui :
/// ce catalogue, `guide_apercus.dart`, `decouverte_screen.dart` et 38
/// marqueurs `GuideCible` posés dans les écrans réels représentent un travail
/// entier. L'effet pour l'utilisateur est le même — plus rien ne s'affiche — et
/// le retour en arrière tient à cette ligne au lieu d'une journée.
///
/// POUR RÉACTIVER : passer cette constante à `true`. Rien d'autre. Ne pas
/// remplacer ce mécanisme par la suppression des appels : c'est précisément ce
/// qui rendrait le retour coûteux, et la règle du projet l'interdit.
///
/// Les `GuideCible` laissés dans les écrans ne coûtent rien tant que c'est
/// faux : ce widget se contente de rendre son enfant.
const bool kVisitesGuideesActives = false;

void Function(int)? allerAOngletGuide;
GlobalKey? cleOngletCoran;
GlobalKey? cleOngletDuas;
GlobalKey? cleOngletCoach;
GlobalKey? cleCartePriere;
GlobalKey? cleBoutonEcoute;
GlobalKey? cleSignet;

class ChapitreGuide {
  final String id, emoji;
  final String Function(AppLocalizations) titre, resume;
  final List<EtapeGuide> Function(BuildContext, AppLocalizations) etapes;
  const ChapitreGuide({
    required this.id,
    required this.emoji,
    required this.titre,
    required this.resume,
    required this.etapes,
  });
}

typedef _Message = (String, String, String);
String _texte(BuildContext c, _Message m) => guideTexte(c, m.$1, m.$2, m.$3);

EtapeGuide _e(
  BuildContext c,
  String chapitre,
  String screen,
  WidgetBuilder view,
  String? target,
  _Message titre,
  _Message texte, {
  bool scroll = false,
}) => EtapeGuide(
  chapitre: chapitre,
  ecranId: screen,
  apercu: view,
  cibleId: target,
  titre: _texte(c, titre),
  texte: _texte(c, texte),
  geste: scroll ? GesteGuide.balayage : GesteGuide.appui,
);

Widget _reglages(BuildContext _) => const SettingsScreen();
Widget _lecture(BuildContext _) => const ReadingSettingsGuide();
Widget _versets(BuildContext _) => const GuideLecture();
Widget _actions(BuildContext _) => const GuideLecture(menu: true);
Widget _prieres(BuildContext _) => const GuidePrieres();
Widget _duas(BuildContext _) => const DuasScreen();
Widget _coach(BuildContext _) => const CoachHubScreen();

List<ChapitreGuide> get kChapitresGuide => [
  ChapitreGuide(
    id: 'global',
    emoji: '🗺️',
    titre: (t) => t.guideChapitreGlobalTitre,
    resume: (t) => t.guideChapitreGlobalResume,
    etapes: (c, t) => [
      EtapeGuide(
        cible: cleOngletCoran,
        titre: t.navQuran,
        texte: t.visiteCoranTexte,
        action: () async {
          allerAOngletGuide?.call(0);
        },
      ),
      EtapeGuide(
        cible: cleOngletDuas,
        titre: t.navDuas,
        texte: t.visiteDuasTexte,
        action: () async {
          allerAOngletGuide?.call(1);
        },
      ),
      EtapeGuide(
        cible: cleOngletCoach,
        titre: t.navCoach,
        texte: t.visiteCoachTexte,
        action: () async {
          allerAOngletGuide?.call(2);
        },
      ),
      EtapeGuide(
        cible: cleOngletCoran,
        titre: t.visiteFinTitre,
        texte: t.visiteFinTexte,
        action: () async {
          allerAOngletGuide?.call(0);
        },
      ),
    ],
  ),
  ChapitreGuide(
    id: 'lecture',
    emoji: '📖',
    titre: (t) => t.guideChapitreLectureTitre,
    resume: (t) => t.guideChapitreLectureResume,
    etapes: (c, t) {
      final ch = t.guideChapitreLectureTitre;
      return [
        _e(
          c,
          ch,
          'versets',
          _versets,
          'verse.0',
          ('Lire un verset', 'Read a verse', 'قراءة آية'),
          (
            'Le texte se lit ici. Un appui sélectionne le verset ; un appui long ouvre les actions à partir de ce passage.',
            'Read here. Tap to select a verse; long-press to open actions from that passage.',
            'اقرأ النص هنا. المس الآية لتحديدها، واضغط مطولاً لفتح الإجراءات من هذا الموضع.',
          ),
        ),
        _e(
          c,
          ch,
          'versets',
          _versets,
          'verse.3',
          ('Défiler dans le texte', 'Scroll through the text', 'تمرير النص'),
          (
            'Fais glisser le texte vers le haut pour poursuivre la lecture. Le guide défile jusqu’au verset concerné.',
            'Swipe the text upwards to continue reading. The tour scrolls to the relevant verse.',
            'مرر النص إلى أعلى لمتابعة القراءة. تنتقل الجولة إلى الآية المعنية.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'actions',
          _actions,
          'actions.recite',
          ('Ouvrir les actions', 'Open verse actions', 'فتح إجراءات الآية'),
          (
            'Après un appui long, ce menu propose récitation, tajwid, mémorisation et jeu. Le départ est le verset sélectionné.',
            'Long-press opens recitation, tajwid, memorization and game actions. They start at the selected verse.',
            'يفتح الضغط المطول التلاوة والتجويد والحفظ واللعبة، انطلاقاً من الآية المحددة.',
          ),
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'read.size',
          ('Plus → taille du texte', 'More → text size', 'المزيد ← حجم النص'),
          (
            'Dans le panneau Plus du lecteur, ajuste la taille avec le curseur. Le texte de cette visite n’est pas enregistré comme réglage.',
            'In the reader’s More panel, adjust the text size with the slider. This tour does not save settings.',
            'في لوحة المزيد بالقارئ، اضبط حجم النص بالشريط. لا تحفظ هذه الجولة أي تغيير.',
          ),
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'read.script',
          ('Choisir l’écriture', 'Choose a script', 'اختيار الخط'),
          (
            'Cette ligne ouvre le choix des polices du Mushaf papier. L’écriture change le dessin, pas la riwaya.',
            'This row opens the paper Mushaf font selector. A font changes appearance, not the riwaya.',
            'يفتح هذا السطر خطوط المصحف الورقي. يغيّر الخط الشكل لا الرواية.',
          ),
        ),
        if (Localizations.localeOf(c).languageCode != 'ar')
          _e(
            c,
            ch,
            'reading',
            _lecture,
            'read.translation',
            ('Afficher la traduction', 'Show translation', 'عرض الترجمة'),
            (
              'Ce commutateur affiche la traduction dans le lecteur. Il n’apparaît pas dans l’interface entièrement arabe.',
              'This switch shows the translation in the reader. It is hidden in the fully Arabic interface.',
              'يعرض المفتاح الترجمة في القارئ، ولا يظهر في الواجهة العربية الكاملة.',
            ),
          ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'read.annotations',
          (
            'Surligner et annoter',
            'Highlight and annotate',
            'التظليل والتعليق',
          ),
          (
            'Active le crayon pour retrouver les outils d’annotation dans le lecteur. Les couleurs du crayon ne sont pas des verdicts de récitation.',
            'Enable the pencil to reveal annotation tools in the reader. Pencil colours are not recitation verdicts.',
            'فعّل القلم لإظهار أدوات التعليق في القارئ. ألوان القلم ليست أحكاماً على التلاوة.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'read.theme',
          (
            'Trois ambiances de lecture',
            'Three reading themes',
            'ثلاثة مظاهر للقراءة',
          ),
          (
            'Les pastilles choisissent le papier clair, le sépia ou le fond sombre. Elles restent un réglage de lecture.',
            'The swatches select light paper, sepia or dark background. They only affect reading appearance.',
            'تختار الدوائر الورق الفاتح أو البني الفاتح أو الداكن. تخص مظهر القراءة فقط.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'read.auto',
          (
            'Tourner automatiquement',
            'Automatic page advance',
            'التقدم التلقائي',
          ),
          (
            'Ce réglage permet au lecteur de suivre une cadence de tournage. Il est distinct de la vitesse de l’enregistrement audio.',
            'This setting lets the reader follow a page-turning cadence. It is separate from audio playback speed.',
            'يضبط هذا الخيار وتيرة انتقال الصفحات، وهو مستقل عن سرعة التسجيل الصوتي.',
          ),
          scroll: true,
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'mushaf',
    emoji: '📜',
    titre: (t) => t.guideChapitreMushafTitre,
    resume: (t) => t.guideChapitreMushafResume,
    etapes: (c, t) {
      final ch = t.guideChapitreMushafTitre;
      return [
        _e(
          c,
          ch,
          'paper',
          (_) => const MushafMaquetteScreen(apercuGuide: true),
          'paper.page',
          (
            'Ouvrir le Mushaf papier',
            'Open the paper Mushaf',
            'فتح المصحف الورقي',
          ),
          (
            'L’icône Mushaf du lecteur ouvre la pagination papier. Voici le vrai rendu de la première page, avec ta riwaya actuelle.',
            'The reader’s Mushaf icon opens paper pagination. This is the actual first page using your current riwaya.',
            'تفتح أيقونة المصحف في القارئ ترقيم المصحف الورقي. هذه الصفحة الأولى بالرواية الحالية.',
          ),
        ),
        _e(
          c,
          ch,
          'paper',
          (_) => const MushafMaquetteScreen(apercuGuide: true, pageInitiale: 2),
          'paper.page',
          (
            'Passer à la page suivante',
            'Turn to the next page',
            'الانتقال إلى الصفحة التالية',
          ),
          (
            'La page suivante s’ouvre ici. Le sens du livre arabe reste le même quelle que soit la langue de l’interface. Un appui sur la page avance aussi.',
            'The next page opens here. Arabic book direction stays the same in every interface language. Tapping the page also advances.',
            'تفتح الصفحة التالية هنا. يبقى اتجاه المصحف العربي نفسه مهما كانت لغة الواجهة. كما تنقل لمسة الصفحة إلى التالية.',
          ),
        ),
        _e(
          c,
          ch,
          'paper',
          (_) => const MushafMaquetteScreen(apercuGuide: true),
          'paper.page',
          (
            'Revenir au passage précédent',
            'Return to the previous page',
            'العودة إلى الصفحة السابقة',
          ),
          (
            'Un balayage dans l’autre sens revient à la page précédente. Feuilleter pendant cette visite ne change pas ta position de lecture enregistrée.',
            'Swipe the other way to return. Turning pages in this tour does not change your saved reading position.',
            'مرر في الاتجاه المعاكس للعودة. تقليب الصفحات في الجولة لا يغيّر موضع قراءتك المحفوظ.',
          ),
        ),
        _e(
          c,
          ch,
          'paper',
          (_) => const MushafMaquetteScreen(apercuGuide: true),
          'paper.bookmark',
          ('Poser un signet', 'Bookmark a page', 'وضع علامة'),
          (
            'Le signet en haut permet de marquer le passage. Dans cette visite, il est montré sans être ajouté ni retiré.',
            'Use the top bookmark to mark this passage. The tour shows it without adding or removing a bookmark.',
            'تضع العلامة العلوية إشارة على الموضع. تعرضها الجولة دون إضافة علامة أو حذفها.',
          ),
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'audio',
    emoji: '🔊',
    titre: (t) => t.guideChapitreAudioTitre,
    resume: (t) => t.guideChapitreAudioResume,
    etapes: (c, t) {
      final ch = t.guideChapitreAudioTitre;
      return [
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'audio.reciter',
          ('Plus → récitateur', 'More → reciter', 'المزيد ← القارئ'),
          (
            'Le choix du récitateur est dans Plus, section Écouter, et non dans les paramètres généraux.',
            'Choose the reciter in More, under Listen, not in general settings.',
            'اختر القارئ من المزيد ضمن الاستماع، وليس من الإعدادات العامة.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'reciters',
          (_) => const GuideReciteurs(),
          'audio.reciters',
          ('Parcourir les récitateurs', 'Browse reciters', 'تصفح القراء'),
          (
            'Voici la liste réellement proposée pour ta riwaya. Les indications distinguent les contenus disponibles hors ligne.',
            'This is the actual list for your riwaya. Indicators identify available offline content.',
            'هذه قائمة القراء المتاحة لروايتك. تبيّن المؤشرات المحتوى المتاح دون اتصال.',
          ),
        ),
        _e(
          c,
          ch,
          'downloads',
          (_) => const GuideReciteurs(telechargements: true),
          'audio.downloads',
          (
            'Télécharger par sourate',
            'Download by surah',
            'التنزيل حسب السورة',
          ),
          (
            'Depuis le récitateur, ouvre ses téléchargements. Tu peux choisir des sourates et consulter l’espace utilisé ; aucun téléchargement ne démarre dans la visite.',
            'Open downloads from a reciter. Choose surahs and inspect storage usage; the tour starts no downloads.',
            'افتح التنزيلات من القارئ لاختيار السور ومعرفة المساحة المستخدمة. لا تبدأ الجولة أي تنزيل.',
          ),
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'audio.speed',
          ('Régler la vitesse audio', 'Set audio speed', 'ضبط سرعة الصوت'),
          (
            'Ce curseur ralentit ou accélère l’audio du récitateur. Il ne règle ni le micro ni la reconnaissance.',
            'This slider slows down or speeds up the reciter’s audio. It does not configure the microphone or recognition.',
            'يبطئ هذا الشريط صوت القارئ أو يسرّعه، ولا يضبط الميكروفون أو التعرف.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'audio.group',
          ('1. Taille du groupe', '1. Group size', '١. حجم المجموعة'),
          (
            'Choisis combien de versets forment un groupe. Par exemple, 3 signifie trois versets travaillés ensemble.',
            'Choose how many verses form a group. For example, 3 means three verses practised together.',
            'اختر عدد الآيات في المجموعة. مثلاً، ٣ تعني ثلاث آيات تتدرب عليها معاً.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'audio.groupRepeat',
          (
            '2. Répétitions du groupe',
            '2. Group repetitions',
            '٢. تكرار المجموعة',
          ),
          (
            'Choisis combien de fois répéter chaque groupe avant de poursuivre. Zéro signifie illimité.',
            'Choose how often each group repeats before continuing. Zero means unlimited.',
            'اختر مرات تكرار كل مجموعة قبل المتابعة. الصفر يعني تكراراً غير محدود.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'reading',
          _lecture,
          'audio.globalRepeat',
          (
            '3. Répétitions globales',
            '3. Overall repetitions',
            '٣. التكرار الكامل',
          ),
          (
            'Le dernier curseur répète l’ensemble. Exemple : groupes de 3 versets, chaque groupe 2 fois, ensemble 3 fois.',
            'The final slider repeats the entire sequence. Example: groups of 3 verses, each group twice, the whole sequence three times.',
            'يكرر الشريط الأخير التسلسل كله. مثال: مجموعات من ٣ آيات، كل مجموعة مرتين، والتسلسل كله ثلاث مرات.',
          ),
          scroll: true,
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'recitation',
    emoji: '🎙️',
    titre: (t) => t.guideChapitreRecitationTitre,
    resume: (t) => t.guideChapitreRecitationResume,
    etapes: (c, t) {
      final ch = t.guideChapitreRecitationTitre;
      return [
        // ── CE QUE LA RECITATION DONNE A VOIR, EN PREMIER (2026-09-14) ─────
        //
        // Demande utilisateur : « je veux que tu montres reciter avec un
        // exemple de recitation (juste la coloration des textes) ». Les etapes
        // qui suivent expliquent OU demarrer et QUELS reglages existent ; aucune
        // ne montrait le RESULTAT -- or c est la seule chose qui donne envie
        // d essayer. On commence donc par la.
        //
        // GuideRecitationCouleurs est un exemple PREPARE, et c est le seul
        // apercu de ce guide qui en est un : les couleurs des mots n existent
        // que comme sortie du modele sur du son capte au micro, donc afficher
        // le vrai ecran ne montrerait rien. Il n ouvre ni micro ni modele et
        // n ecrit nulle part -- garanti par l ABSENCE D IMPORT dans
        // guide_apercus.dart, pas par une condition.
        _e(
          c,
          ch,
          'recitation.couleurs',
          (_) => const GuideRecitationCouleurs(),
          null,
          (
            'Ce que tu vois en recitant',
            'What you see while reciting',
            'ما تراه أثناء التلاوة',
          ),
          (
            'Chaque mot se colore : vert quand il est juste, orange sur une articulation approximative, rouge sur un ecart entendu. Exemple prepare, sans micro.',
            'Each word takes colour: green when correct, orange for an approximate articulation, red for a difference heard. Prepared example, no microphone.',
            'تتلون كل كلمة: أخضر إذا صحت، وبرتقالي عند نطق تقريبي، وأحمر عند فرق مسموع. مثال معد بلا ميكروفون.',
          ),
        ),
        _e(
          c,
          ch,
          'versets',
          _versets,
          'verse.0',
          (
            'Choisir le point de départ',
            'Choose a starting point',
            'اختيار نقطة البداية',
          ),
          (
            'Commence dans le lecteur : sélectionne le verset, puis ouvre son menu par un appui long.',
            'Start in the reader: select the verse, then long-press to open its menu.',
            'ابدأ في القارئ: حدد الآية ثم اضغط مطولاً لفتح قائمتها.',
          ),
        ),
        _e(
          c,
          ch,
          'actions',
          _actions,
          'actions.recite',
          ('Démarrer la récitation', 'Start reciting', 'بدء التلاوة'),
          (
            'Réciter ouvre le suivi de ta voix depuis le passage choisi. Le micro ne sera demandé que lors d’un usage réel, pas par ce guide.',
            'Recite opens voice tracking from the chosen passage. This tour does not request microphone access.',
            'تفتح التلاوة متابعة صوتك من الموضع المختار. لا تطلب هذه الجولة إذن الميكروفون.',
          ),
        ),
        _e(
          c,
          ch,
          'actions',
          _actions,
          'actions.tajwid',
          (
            'Distinguer le mode tajwid',
            'Recognize tajwid mode',
            'تمييز وضع التجويد',
          ),
          (
            'Le tajwid possède son accès propre. Cet accès reste grisé pour Warsh dans la version actuelle ; le guide ne contourne pas cette limite.',
            'Tajwid has its own entry. It remains greyed out for Warsh in the current version; the tour does not bypass this restriction.',
            'للتجويد مدخل مستقل يبقى باهتاً لورش في الإصدار الحالي. لا تتجاوز الجولة هذا القيد.',
          ),
        ),
        _e(
          c,
          ch,
          'settings',
          _reglages,
          'settings.micro',
          (
            'Choisir le micro Bluetooth',
            'Bluetooth microphone',
            'ميكروفون بلوتوث',
          ),
          (
            'Le réglage du micro de casque est dans les paramètres généraux. Il concerne le son capté, pas la voix du récitateur écouté.',
            'The headset microphone setting is in general settings. It affects captured sound, not the reciter you listen to.',
            'إعداد ميكروفون السماعة في الإعدادات العامة. يخص الصوت الملتقط لا القارئ الذي تسمعه.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'settings',
          _reglages,
          'settings.disputed',
          (
            'Retrouver les signalements',
            'Find disputed verdicts',
            'مراجعة الأحكام المعترض عليها',
          ),
          (
            'Les réglages regroupent aussi la gestion des verdicts contestés. La visite montre cet accès sans transmettre ni supprimer de données.',
            'Settings also contain disputed-verdict management. The tour shows this entry without sending or deleting data.',
            'تضم الإعدادات إدارة الأحكام المعترض عليها. تعرض الجولة هذا المدخل دون إرسال بيانات أو حذفها.',
          ),
          scroll: true,
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'memorisation',
    emoji: '🧩',
    titre: (t) => t.mushafMemorize,
    resume: (t) => t.guideCoachMemoTexte,
    etapes: (c, t) {
      final ch = t.mushafMemorize;
      return [
        _e(
          c,
          ch,
          'actions',
          _actions,
          'actions.memorize',
          (
            'Apprendre depuis ce verset',
            'Learn from this verse',
            'الحفظ من هذه الآية',
          ),
          (
            'Mémoriser se lance depuis le menu du verset. Le Coach sert ensuite à retrouver le travail effectué.',
            'Start Memorize from the verse menu. Use the Coach afterwards to review your work.',
            'ابدأ الحفظ من قائمة الآية، ثم راجع عملك في المدرب.',
          ),
        ),
        _e(
          c,
          ch,
          'actions',
          _actions,
          'actions.game',
          ('Ouvrir le jeu', 'Open the game', 'فتح اللعبة'),
          (
            'Le jeu est une autre entrée du même menu. Il propose de retrouver l’enchaînement des mots ; aucun score de jeu n’est produit ici.',
            'The game is another entry in this menu. Practise word sequencing there; no game scores are created here.',
            'اللعبة مدخل آخر في القائمة للتدرب على تسلسل الكلمات. لا تنتج الجولة نقاط لعبة.',
          ),
        ),
        _e(
          c,
          ch,
          'coach',
          _coach,
          'coach.portions',
          (
            'Retrouver ses portions',
            'Find your portions',
            'العثور على الأجزاء المحفوظة',
          ),
          (
            'Reviens au Coach pour consulter les portions travaillées. Une visite guidée ne valide ni sourate ni quart de hizb.',
            'Return to the Coach to review practised portions. A guided tour does not validate a surah or quarter hizb.',
            'ارجع إلى المدرب لمراجعة المقاطع المتدرّب عليها. لا تعتمد الجولة سورة أو ربع حزب.',
          ),
          scroll: true,
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'coach',
    emoji: '🎓',
    titre: (t) => t.navCoach,
    resume: (t) => t.guideChapitreCoachResume,
    etapes: (c, t) {
      final ch = t.navCoach;
      return [
        _e(
          c,
          ch,
          'coach',
          _coach,
          'coach.goal',
          ('Objectif et rythme', 'Goal and pace', 'الهدف والوتيرة'),
          (
            'Le haut du Coach présente ton objectif. L’état affiché dépend de tes réglages et de ton activité réelle, sans progression inventée.',
            'The top of the Coach shows your goal. Its state depends on your settings and actual activity, without invented progress.',
            'يعرض أعلى المدرب هدفك حسب إعداداتك ونشاطك الحقيقي، دون تقدم مختلق.',
          ),
        ),
        _e(
          c,
          ch,
          'coach',
          _coach,
          'coach.goal',
          ('Série et activité', 'Streak and activity', 'الاستمرارية والنشاط'),
          (
            'Les indicateurs d’activité et de série se consultent dans ce tableau de bord. Ils résument les séances réelles, pas les étapes du tutoriel.',
            'Review activity and streak indicators in this dashboard. They summarize real practice, not tutorial steps.',
            'راجع مؤشرات النشاط والاستمرارية هنا. تلخص التدريب الحقيقي لا خطوات الجولة.',
          ),
        ),
        _e(
          c,
          ch,
          'coach',
          _coach,
          'coach.portions',
          (
            'Sourates et quarts de hizb',
            'Surahs and quarter hizbs',
            'السور وأرباع الأحزاب',
          ),
          (
            'La liste des portions permet de retrouver ton travail par passage. Son contenu peut être vide tant que tu n’as pas commencé.',
            'The portions list groups your work by passage. It may be empty before you start practising.',
            'تجمع قائمة المقاطع عملك حسب الموضع، وقد تكون فارغة قبل بدء التدريب.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'coach',
          _coach,
          'coach.portions',
          (
            'Revoir les mots à travailler',
            'Review words to practise',
            'مراجعة الكلمات للتدريب',
          ),
          (
            'Ouvre une portion pour examiner les mots et revenir au passage à travailler. La visite ne crée pas de faux historique pour remplir cet écran.',
            'Open a portion to inspect its words and return to the passage to practise. The tour creates no fake history to populate this screen.',
            'افتح المقطع لفحص كلماته والعودة للتدريب. لا تنشئ الجولة سجلاً وهمياً لملء الشاشة.',
          ),
          scroll: true,
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'prieres',
    emoji: '🕌',
    titre: (t) => t.guideChapitrePrieresTitre,
    resume: (t) => t.guideChapitrePrieresResume,
    etapes: (c, t) {
      final ch = t.guideChapitrePrieresTitre;
      return [
        _e(
          c,
          ch,
          'settings',
          _reglages,
          'settings.prayers',
          ('Ouvrir les horaires', 'Open prayer times', 'فتح مواقيت الصلاة'),
          (
            'Les horaires détaillés sont accessibles dans la section Prières des réglages, en complément du bandeau d’accueil.',
            'Detailed times are in the Prayer section of settings, complementing the home panel.',
            'توجد المواقيت المفصلة في قسم الصلاة بالإعدادات، إضافة إلى لوحة الرئيسية.',
          ),
        ),
        _e(
          c,
          ch,
          'prayers',
          _prieres,
          'prayer.times',
          (
            'Lire les heures de la journée',
            'Read today’s times',
            'قراءة مواقيت اليوم',
          ),
          (
            'Le tableau montre les horaires déjà calculés. Sans position disponible, cette zone peut être absente : la visite n’invente pas d’heures.',
            'The table shows already calculated times. Without an available location this area may be absent: the tour invents no times.',
            'يعرض الجدول المواقيت المحسوبة. قد تغيب المنطقة دون موقع متاح، ولا تختلق الجولة مواقيت.',
          ),
        ),
        _e(
          c,
          ch,
          'prayers',
          _prieres,
          'prayer.location',
          (
            'Position et méthode',
            'Location and method',
            'الموقع وطريقة الحساب',
          ),
          (
            'Vérifie la position et la méthode de calcul ici. Actualiser la position reste une action volontaire hors du tutoriel.',
            'Check the location and calculation method here. Refreshing the location remains a deliberate action outside the tour.',
            'تحقق هنا من الموقع وطريقة الحساب. يبقى تحديث الموقع إجراءً تختاره خارج الجولة.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'prayers',
          _prieres,
          'prayer.notifications',
          ('Adhan et rappels', 'Adhan and reminders', 'الأذان والتذكير'),
          (
            'Le tableau permet de régler les notifications par prière. Le tutoriel ne coche aucune option et n’accorde aucune autorisation.',
            'Use this table to configure notifications per prayer. The tour selects no option and grants no permission.',
            'يضبط الجدول الإشعارات لكل صلاة. لا تختار الجولة أي خيار ولا تمنح أي إذن.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'settings',
          _reglages,
          'settings.qibla',
          ('Trouver la Qibla', 'Find the Qibla', 'العثور على القبلة'),
          (
            'Cette entrée ouvre la boussole. Pour l’utiliser réellement, autorise la position si demandée et suis les indications du téléphone. Le guide n’active pas le GPS.',
            'This entry opens the compass. For real use, grant location if requested and follow the phone’s guidance. The tour does not activate GPS.',
            'يفتح هذا المدخل البوصلة. للاستخدام الفعلي اسمح بالموقع عند الطلب واتبع إرشادات الهاتف. لا تفعّل الجولة GPS.',
          ),
        ),
        _e(
          c,
          ch,
          'qibla',
          (_) => const QiblaScreen(demanderPermission: false),
          null,
          ('Lire la boussole', 'Read the compass', 'قراءة البوصلة'),
          (
            'Voici l’écran de la Qibla. Il utilise les autorisations déjà accordées ; si elles manquent, il affiche cet état sans ouvrir de demande pendant la visite.',
            'This is the Qibla screen. It uses existing permissions; if they are missing it shows that state without requesting access during the tour.',
            'هذه شاشة القبلة. تستخدم الأذونات الممنوحة؛ وإذا غابت تعرض الحالة دون طلب إذن خلال الجولة.',
          ),
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'invocations',
    emoji: '🤲',
    titre: (t) => t.navDuas,
    resume: (t) => t.guideChapitreDuasResume,
    etapes: (c, t) {
      final ch = t.navDuas;
      return [
        _e(
          c,
          ch,
          'duas',
          _duas,
          'duas.search',
          (
            'Rechercher une invocation',
            'Search for an invocation',
            'البحث عن دعاء',
          ),
          (
            'La recherche est en haut de l’onglet Invocations. Elle filtre les résultats selon le texte saisi.',
            'Search is at the top of the Invocations tab. It filters results using the text you enter.',
            'البحث في أعلى تبويب الأدعية، ويصفي النتائج حسب النص المدخل.',
          ),
        ),
        _e(
          c,
          ch,
          'duas',
          _duas,
          'duas.moment',
          ('Selon le moment', 'By time of day', 'حسب وقت اليوم'),
          (
            'Cette proposition rassemble les invocations liées au moment de la journée.',
            'This suggestion groups invocations related to the time of day.',
            'يجمع هذا الاقتراح الأدعية المرتبطة بوقت اليوم.',
          ),
        ),
        _e(
          c,
          ch,
          'duas',
          _duas,
          'duas.universe',
          (
            'Univers puis collections',
            'Topics, then collections',
            'المواضيع ثم المجموعات',
          ),
          (
            'Ouvre un univers pour trouver ses collections. Dans une invocation, les commandes disponibles dépendent du contenu et de son audio.',
            'Open a topic to find its collections. An invocation’s available controls depend on its content and audio.',
            'افتح الموضوع للوصول إلى مجموعاته. تعتمد أدوات الدعاء المتاحة على محتواه وصوته.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'duas',
          _duas,
          'duas.radio',
          ('Écoute continue', 'Continuous listening', 'الاستماع المستمر'),
          (
            'Les radios sont plus bas, après les collections. Ce sont des flux distincts des invocations individuelles ; aucun flux n’est lancé par la visite.',
            'Radios are further down, after collections. They are streams, distinct from individual invocations; the tour starts none.',
            'توجد الإذاعات أسفل المجموعات. إنها تدفقات مستقلة عن الأدعية المفردة، ولا تبدأ الجولة تشغيلها.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'invocation',
          (_) => const GuideInvocation(),
          'dua.favorite',
          (
            'Garder une invocation en favori',
            'Save a favourite invocation',
            'حفظ دعاء في المفضلة',
          ),
          (
            'Dans la fiche dépliée, l’étoile ajoute ou retire l’invocation des favoris. Aucun favori n’est modifié par la visite.',
            'In the expanded card, the star adds or removes a favourite. The tour changes none of your favourites.',
            'في البطاقة المفتوحة، تضيف النجمة الدعاء للمفضلة أو تزيله. لا تغير الجولة مفضلتك.',
          ),
        ),
        _e(
          c,
          ch,
          'invocation',
          (_) => const GuideInvocation(),
          'dua.audio',
          (
            'Écouter une invocation',
            'Listen to an invocation',
            'الاستماع إلى دعاء',
          ),
          (
            'Le bouton Écouter apparaît quand un audio existe. Il est distinct des radios et du compteur de répétitions.',
            'Listen appears when audio is available. It is separate from radios and the repetition counter.',
            'يظهر زر الاستماع عند توفر صوت، وهو مستقل عن الإذاعات وعدّاد التكرار.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'invocation',
          (_) => const GuideInvocation(),
          'dua.counter',
          ('Compter ses répétitions', 'Count repetitions', 'عدّ التكرار'),
          (
            'Un appui sur le compteur compte une répétition ; la flèche circulaire remet le compteur à zéro. Le tutoriel n’ajoute aucune répétition.',
            'Tap the counter to count one repetition; the circular arrow resets it. The tour adds no repetitions.',
            'تعد لمسة العدّاد تكراراً واحداً، ويعيده السهم الدائري للصفر. لا تضيف الجولة تكراراً.',
          ),
          scroll: true,
        ),
      ];
    },
  ),
  ChapitreGuide(
    id: 'reglages',
    emoji: '⚙️',
    titre: (t) => t.settingsTitle,
    resume: (t) => t.guideChapitreReglagesResume,
    etapes: (c, t) {
      final ch = t.settingsTitle;
      return [
        _e(
          c,
          ch,
          'settings',
          _reglages,
          'settings.riwaya',
          ('Hafs ou Warsh', 'Hafs or Warsh', 'حفص أو ورش'),
          (
            'La riwaya se choisit ici. Elle détermine le texte et les récitateurs proposés ; ce n’est pas un simple changement de police.',
            'Choose the riwaya here. It determines the text and available reciters; it is not just a font change.',
            'اختر الرواية هنا. تحدد النص والقراء المتاحين، وليست مجرد تغيير للخط.',
          ),
        ),
        _e(
          c,
          ch,
          'settings',
          _reglages,
          'settings.language',
          ('Langue de l’interface', 'Interface language', 'لغة الواجهة'),
          (
            'Cette ligne ouvre le choix de langue des menus. Le texte coranique conserve sa langue et sa riwaya.',
            'This row opens the menu language selector. Quranic text keeps its language and riwaya.',
            'يفتح هذا السطر اختيار لغة القوائم. يحتفظ النص القرآني بلغته وروايته.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'settings',
          _reglages,
          'settings.contact',
          ('Contacter l’équipe', 'Contact the team', 'التواصل مع الفريق'),
          (
            'Pour signaler un problème, ouvre le formulaire de contact. Prépare un objet et un message avant d’envoyer.',
            'Open the contact form to report an issue. Prepare a subject and message before sending.',
            'افتح نموذج الاتصال للإبلاغ عن مشكلة. جهز الموضوع والرسالة قبل الإرسال.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'contact',
          (_) => const ContactScreen(),
          'contact.subject',
          ('Préparer un message', 'Prepare a message', 'تحضير رسالة'),
          (
            'Voici le formulaire réel. La visite ne saisit rien, n’envoie rien et n’ouvre pas ton application de courrier.',
            'This is the actual form. The tour types nothing, sends nothing and does not open your mail app.',
            'هذا النموذج الحقيقي. لا تكتب الجولة شيئاً ولا ترسل ولا تفتح تطبيق بريدك.',
          ),
        ),
        _e(
          c,
          ch,
          'contact',
          (_) => const ContactScreen(),
          'contact.message',
          (
            'Décrire ce qui s’est passé',
            'Describe what happened',
            'وصف ما حدث',
          ),
          (
            'Précise l’écran, le geste et le problème observé. Ne partage pas d’enregistrement personnel sans le vouloir.',
            'Describe the screen, action and observed problem. Do not share personal recordings unintentionally.',
            'صف الشاشة والإجراء والمشكلة الملحوظة. لا تشارك تسجيلاتك الشخصية دون قصد.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'contact',
          (_) => const ContactScreen(),
          'contact.send',
          (
            'Vérifier avant d’envoyer',
            'Review before sending',
            'المراجعة قبل الإرسال',
          ),
          (
            'Envoyer prépare le courrier dans ton application de messagerie. La confirmation réelle reste entre tes mains ; le guide ne déclenche pas cet envoi.',
            'Send prepares the email in your mail app. You remain in control of the final confirmation; the tour does not send.',
            'يجهز الإرسال البريد في تطبيقك. يبقى التأكيد النهائي بيدك، ولا ترسل الجولة شيئاً.',
          ),
          scroll: true,
        ),
        _e(
          c,
          ch,
          'about',
          (_) => const AboutScreen(),
          null,
          (
            'Données, sources et limites',
            'Data, sources and limitations',
            'البيانات والمصادر والحدود',
          ),
          (
            'À propos regroupe les informations sur l’application, ses sources et ses limites. Tu peux retrouver cet écran depuis les réglages.',
            'About contains application information, sources and limitations. Reopen this screen from settings.',
            'تجمع صفحة حول معلومات التطبيق ومصادره وحدوده. يمكنك الرجوع إليها من الإعدادات.',
          ),
        ),
      ];
    },
  ),
];

/// The catalogue overview shows real previews; first launch retains its four tabs.
List<EtapeGuide> etapesDecouverte(
  ChapitreGuide chapitre,
  BuildContext c,
  AppLocalizations t,
) => chapitre.id == 'global'
    ? [for (final ch in kChapitresGuide.skip(1)) ch.etapes(c, t).first]
    : chapitre.etapes(c, t);
