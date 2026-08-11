# Traduction française et tafsir — état des droits

**Décision du 2026-08-09 : aucun courrier à envoyer aujourd'hui.**
Ce document garde le dossier prêt, pas ouvert. Il ne se rouvre que le jour où
le tafsir Mukhtasar est réellement embarqué dans l'app.

---

## Pourquoi il n'y a rien à demander aujourd'hui

| Œuvre | Dans l'app ? | Droits | Action |
|---|---|---|---|
| Traduction fr des sens du Coran — **Montada / Noor International** (Dr. Nabîl Ridwân) | **OUI**, embarquée (`resource_id: 136` dans `assets/data/quran_verses.json`) | **Couverte** par la licence générale de QuranEnc.com | Respecter les 7 conditions (ci-dessous) |
| Tafsir **al-Mukhtasar**, version française (Tafsir Center for Quranic Studies) | **NON** — ni embarqué ni téléchargé, `QuranSciencesService.ensureLoaded()` rend `false` | **Non couvert** : sa fiche sur QuranEnc n'a ni bouton de téléchargement ni lien de licence | Rien. Courrier prêt plus bas, à envoyer **si** on l'embarque un jour |

La seule œuvre exposée est donc la seule qui soit déjà autorisée.

## La licence générale de QuranEnc.com — texte intégral

Relevée dans le HTML brut de la page (la modale « Terms and Policies » n'a pas
d'URL propre, elle s'ouvre en JavaScript) :

> Contents of the translations can be downloaded and re-published, with the
> following terms and conditions:
>
> 1. No modification, addition, or deletion of the content.
> 2. Clearly referring to the publisher and the source (QuranEnc.com).
> 3. Mentioning the version number when re-publishing the translation.
> 4. Keeping the transcript information inside the document.
> 5. Notifying the source (QuranEnc.com) of any note on the translation.
> 6. Updating the translation according to the latest version issued from the
>    source (QuranEnc.com).
> 7. Inappropriate advertisements must not be included when displaying
>    translations of the meanings of the Noble Quran.

⚠️ Cette licence ne couvre **pas** uniformément tout le site : elle s'applique
aux entrées qui portent le bouton de téléchargement et le lien de licence.
Vérifié entrée par entrée sur la page française — `french_montada` les a,
`french_mokhtasar` ne les a pas.

## Ce que ces 7 conditions exigent DANS l'app

C'est ici que se trouve le vrai travail, et il remplace les courriers.

| Condition | État actuel | À faire |
|---|---|---|
| 1 et 4 — aucune suppression de contenu | ❌ `_stripHtml` ([verse_tile.dart:183 et 219](app/lib/widgets/verse_tile.dart#L183)) retire **toutes** les balises avant affichage, donc les appels de note `<sup foot_note=…>1</sup>`. Supprimer les renvois de notes est une suppression de contenu | Afficher les appels de note, ou à défaut ne pas les effacer silencieusement |
| 2 — citer l'éditeur **et** QuranEnc.com | ❌ L'écran « À propos » crédite « Quran.com » | Créditer **Montada Islamic Foundation / Noor International**, et **QuranEnc.com** comme source |
| 3 — mentionner le numéro de version | ❌ absent | Relever la version au téléchargement et l'afficher |
| 6 — suivre la dernière version | ❌ figée depuis le 2026-07-19 | À reprendre lors d'une mise à jour du JSON |
| 7 — pas de publicité inappropriée | ✅ aucune publicité | rien |
| 5 — signaler toute remarque | ✅ sans objet | rien |

**Un gain à ne pas manquer :** aujourd'hui la traduction vient de l'API de
**quran.com**, pas de QuranEnc. Or c'est la licence de QuranEnc qui l'autorise.
Reprendre le fichier **depuis QuranEnc**, avec son numéro de version, fait deux
choses d'un coup : ça met la traduction sous une licence claire, et ça la
retire de ce que tu dois demander à Quran Foundation.

## Contacts (si le dossier se rouvre)

- **Tafsir Center for Quranic Studies** — `info@tafsir.net`,
  +966 11 210 9620, formulaire `https://tafsir.net/contact`, Riyad
  (حي الياسمين).
- **QuranEnc.com / Rowwad Translation Center** — `info@quranenc.com`,
  formulaire `https://quranenc.com/en/home/contact_us`.
  Utile seulement pour faire confirmer la formulation d'attribution — la
  licence, elle, n'exige aucune demande préalable.

---

# COURRIER DORMANT — Tafsir Center for Quranic Studies

**À n'envoyer QUE si l'on décide d'embarquer le Mukhtasar français.**
Destinataire : `info@tafsir.net`.

## Version arabe (à envoyer)

**الموضوع:** طلب إذن بإدراج «المختصر في التفسير» (الترجمة الفرنسية) داخل تطبيق مجاني

السلام عليكم ورحمة الله وبركاته،

أنا مطوّر مستقل، وقد أنجزت تطبيقًا مجانيًا لنظام أندرويد باسم *Coran Karim*،
يساعد المستخدم على حفظ القرآن الكريم وتلاوته: يستمع التطبيق إلى التلاوة عبر
الميكروفون ويقارنها بالنص كلمةً كلمة، بواسطة نموذج للتعرّف على الكلام يعمل
داخل الجهاز دون اتصال بالإنترنت.

**ما أودّ إدراجه**

أعمل على خاصيّة يضغط فيها المستخدم على آية أو على كلمة فيظهر له شرحها. وأودّ
أن يكون الشرح الأساسيّ للمستخدم الفرنسيّ هو **الترجمة الفرنسية لـ«المختصر في
التفسير»** الصادر عن **مركز تفسير للدراسات القرآنية**.

وأصارحكم بحقيقة ما أطلبه: لا يتعلّق الأمر باقتباس مقاطع يسيرة، بل بإدراج
التفسير كاملًا، آيةً آية، في قاعدة بيانات محفوظة داخل الجهاز ليعمل الشرح دون
اتصال. وهذا أوسع ما يمكن أن يُطلب، ولذلك أُفضّل أن أطلبه صراحةً بدل أن أُجمِل.

ولم أُدرج شيئًا من هذا في النسخة المنشورة حتى الآن، وأنتظر جوابكم قبل ذلك.

**ما أطلبه**

1. إذنًا مكتوبًا بإدراج الترجمة الفرنسية لـ«المختصر في التفسير» على هذا النحو،
   أو الدلالة على إذن عام منشور إن كان موجودًا.
2. الصيغة التي تحبّون أن يُنسب بها العمل إليكم داخل التطبيق.
3. التطبيق مجانيّ ولا دخل له ولا إعلان فيه. وأفكّر مستقبلًا في قبول تبرّعات
   اختيارية لتغطية التكاليف — فهل يغيّر ذلك شيئًا في نظركم؟

**تعهّداتي**

- لا أعدّل النصّ ولا أختصره ولا أخلطه بغيره.
- لا أبيع التفسير ولا أرخّصه لغيري ولا أنشره خارج التطبيق.
- أذكر مركز تفسير مصدرًا، مع اسم التفسير، عند كلّ عرض للشرح.
- إن لم تأذنوا، فلن أُدرجه، وسأكتفي بالتفاسير التي انتهت حقوقها.

جزاكم الله خيرًا على هذا العمل النافع، وشكرًا لوقتكم.

وبالله التوفيق،

[الاسم]
[البريد الإلكتروني]
اسم حزمة التطبيق: `com.corankarim.coran_karim`

## Traduction française (pour ta lecture)

**Objet :** Demande d'autorisation d'intégrer « al-Mukhtasar fî al-Tafsîr » (traduction française) dans une application gratuite

Assalamu alaykum wa rahmatullahi wa barakatuh,

Je suis un développeur indépendant et j'ai réalisé une application Android gratuite, *Coran Karim*, qui aide à mémoriser et à réciter le Coran : l'application écoute la récitation au micro et la compare au texte mot à mot, à l'aide d'un modèle de reconnaissance de la parole qui fonctionne dans l'appareil, sans connexion.

**Ce que je souhaite intégrer**

Je travaille sur une fonctionnalité où l'utilisateur touche un verset ou un mot et en voit l'explication. Je souhaiterais que l'explication de premier niveau, pour l'utilisateur francophone, soit la **traduction française d'« al-Mukhtasar fî al-Tafsîr »**, édité par le **Tafsir Center for Quranic Studies**.

Je vous dis franchement l'ampleur de ma demande : il ne s'agit pas de citer de courts extraits, mais d'intégrer le tafsir **en entier, verset par verset**, dans une base de données conservée sur l'appareil afin que l'explication fonctionne hors ligne. C'est la demande la plus large qui puisse être formulée, et je préfère la poser explicitement plutôt que de rester vague.

Je n'ai rien intégré de tout cela dans la version publiée à ce jour : j'attends votre réponse.

**Ce que je demande**

1. Une autorisation écrite d'intégrer la traduction française d'« al-Mukhtasar » de cette manière, ou l'indication d'une autorisation générale publiée si elle existe.
2. La formulation par laquelle vous souhaitez que l'œuvre vous soit attribuée dans l'application.
3. L'application est gratuite, sans revenu ni publicité. J'envisage à l'avenir d'accepter des dons volontaires pour couvrir les frais — cela change-t-il quelque chose à vos yeux ?

**Mes engagements**

- Je ne modifie, n'abrège ni ne mélange le texte.
- Je ne vends pas le tafsir, je ne le sous-licencie pas et je ne le diffuse pas hors de l'application.
- Je cite le Tafsir Center comme source, avec le nom du tafsir, à chaque affichage d'une explication.
- Si vous n'autorisez pas, je ne l'intégrerai pas et me limiterai aux tafsirs dont les droits sont éteints.

Qu'Allah vous récompense pour ce travail utile, et merci pour votre temps.

[Nom]
[Adresse e-mail]
Paquet Android : `com.corankarim.coran_karim`
