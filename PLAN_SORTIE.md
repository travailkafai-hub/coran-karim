# Plan de sortie — se rendre indépendant des fournisseurs

**Écrit le 2026-08-12.** Complément de `PUBLICATION_PLAY.md`, qui traite de la
publication. Celui-ci traite d'une autre question : **de qui l'application
dépend, et comment ne plus en dépendre** si on le décide.

À lire d'abord : sortir n'est pas un but en soi. Aujourd'hui Quran Foundation
est le **seul** fournisseur pour lequel il existe une **autorisation écrite**,
obtenue le 2026-08-10, qui couvre le stockage hors ligne, l'attribution et les
dons. Tout ce qui suit ne vaut que si on obtient un socle au moins aussi solide.

---

## 1. De quoi l'app dépend réellement

| Élément | Fournisseur actuel | Statut juridique | Remplaçable ? |
|---|---|---|---|
| Texte coranique **Hafs** + métadonnées de pages | Quran Foundation | **autorisé par écrit** | oui — Tanzil |
| Texte coranique **Warsh** | *aucun* | — | **n'existe pas encore, cf. §2** |
| Coloration tajwid | Quran Foundation | autorisé | oui — chaîne d'annotation déjà embarquée |
| Traduction française | Montada / Noor Intl. | licence générale QuranEnc | déjà tiers, indépendant de QF |
| URL des récitations audio | Quran Foundation | autorisé | everyayah / quranicaudio — **non vérifié, cf. §3** |
| **Minutage mot à mot** (`segments`) | Quran Foundation | autorisé | **aucun équivalent public** — d'où §4 |

Deux lignes commandent tout : le **minutage**, parce que rien ne le remplace, et
l'**audio**, parce que c'est la seule dépendance en ligne qui reste au
quotidien.

---

## 2. Le texte — et le trou Warsh

### Hafs : réglé, ou presque

**Tanzil** convient : conditions explicites, redistribution verbatim autorisée
avec attribution et lien, aucun compte, aucune limite de conservation, usage
commercial non interdit. Il fournit le texte uthmanien, le texte simple, et les
métadonnées (pages du Mushaf, juz, hizb, sajda).

Ce que Tanzil **ne** fournit pas : le balisage tajwid. Sans objet — l'app a sa
propre chaîne d'annotation (`quran_rules_annotated.json`), et l'audit du
2026-07-10 avait montré que le balisage de quran.com diverge du texte canonique
sur **4278 versets sur 6236**. On remplacerait une source approximative par la
sienne.

### Warsh : un texte vient d'arriver (2026-08-12)

⚠️ **Cette section a été écrite quelques heures avant l'arrivée du fichier.
Elle est conservée parce que son analyse du corpus reste vraie — mais son
premier constat, « le projet n'a aucun texte Warsh », ne l'est plus.**

`benchmark/warshData_v10.json` (2,77 Mo, apparu le 2026-08-12) est un **vrai
texte Warsh**, et c'est vérifiable sans croire personne :

- **6214 versets**, soit le décompte **madanī** — celui de Warsh — et non les
  6236 du décompte kūfī de Hafs ;
- le **verset 1 d'Al-Fātiḥah y est `الحمد لله رب العالمين`**, pas la Basmala :
  c'est la signature du décompte madanī, où la Basmala n'est pas comptée ;
- l'orthographe warshienne est présente (`اِ۬لْحَمْدُ`) ;
- la mise en page complète est là : 604 pages, `line_start`/`line_end`, juz.

**Ce que ça règle** : le préalable n°3 ci-dessous (obtenir un texte Warsh
vérifié) est levé, sous réserve des deux points suivants.

### CORRECTION DU MÊME JOUR — le chantier était déjà fait

En écrivant ce qui précède j'ai listé trois risques. **Les trois étaient déjà
traités**, sur la branche `chantier-warsh` (6 commits, `b32c422` → `a067cfe`).
Je les corrige ici plutôt que de laisser des affirmations fausses dans un
document destiné à être repris.

| Ce que j'avais annoncé comme risque | La réalité |
|---|---|
| « Provenance et licence inconnues » | **KFGQPC** (Complexe du Roi Fahd), texte complet et libre — versé avec le script qui le consomme (`a067cfe`) |
| « 6214 mots fantômes : le numéro de verset est dans le texte » | **Déjà retiré.** Vérifié sur l'asset embarqué : **0 chiffre arabo-indien sur 6236 versets** |
| « La numérotation n'est pas interchangeable » | **Résolu par remappage** : l'asset `quran_verses_warsh.json` porte **6236 entrées aux clés Hafs**. Texte Warsh, numérotation Hafs |

Le remappage est le choix qui commande tout le reste, et il est justifié par
une mesure : `(sourate, verset)` n'est **pas** une identité stable entre
riwāyāt — 50 sourates sur 114 n'ont pas le même nombre de versets, et sur les
6 188 clés communes, **4 943 désignent un autre verset** (2:132 Warsh = 2:133
Hafs). Persister quoi que ce soit sous `(surah, ayah, word_index)` deviendrait
donc faux au basculement, **en silence**. En ramenant le texte Warsh sur les
clés Hafs, signets, portions, statistiques et archives restent valides.

Coup de chance vérifié : **l'audio Warsh d'everyayah est déjà indexé en
numérotation Hafs** (`002286.mp3` existe alors que la Baqara Warsh s'arrête à
285). Aucune migration de base n'était nécessaire.

### Ce qui reste ouvert sur Warsh

1. **everyayah devient une dépendance dure.** Les deux récitateurs Warsh
   complets viennent de là, et leurs URL se déduisent du numéro de verset —
   élégant, mais ça veut dire que la fonctionnalité Warsh **repose entièrement
   sur une source dont les conditions ne sont toujours pas vérifiées** (§3).
   Le courrier en annexe devient donc plus urgent, pas moins.

2. **Les timings mot à mot sont ESTIMÉS en Warsh.** quran.com ne publie de
   `segments` que pour ses récitateurs Hafs. La découpe Warsh est pondérée par
   la longueur des mots, et le journal le dit à chaque fois. C'est honnête, mais
   ça déplace le chantier de l'aligneur (§4) : il n'est plus seulement un moyen
   de gagner son indépendance, **il est devenu un besoin fonctionnel**.

3. **Le modèle ASR n'a pas été touché** (décision utilisateur) et sera observé
   à l'œuvre sur du Warsh. La mesure qui dit à quoi s'attendre : squelette
   consonantique identique à **99,16 %** entre les deux textes, mais **37,88 %
   des mots diffèrent une fois les harakat prises en compte** — or le tokenizer
   du modèle les conserve. Il devrait donc retrouver les bons mots et signaler
   beaucoup de prononciations. C'est l'expérience à mener, elle est outillée.

4. **Les ~86 000 clips Warsh du corpus** restent étiquetés avec le texte Hafs.
   Le texte KFGQPC permet enfin de les réétiqueter ; ce n'est pas fait.

### Vérification du texte Warsh — EN ATTENTE DU GPU (décision 2026-08-12)

Chantier **décidé, non commencé**, à reprendre au retour sur le poste Ubuntu.

**Le problème** : le KFGQPC embarqué n'a rien contre quoi être vérifié. La
recherche du 2026-08-12 le confirme — pour le Warsh, ce qui existe librement,
ce sont des **images** (Mushaf de Médine sur Internet Archive, `pdf.quran.ws`,
Noor Library, Scribd), pas du texte structuré. Tanzil ne publie que du Hafs.
L'exemplaire d'Internet Archive est un scan dont la « couche de texte » est de
l'**OCR Tesseract** — 99,02 % de confiance *auto-déclarée*, ce qui n'est pas
une exactitude, et reste inacceptable pour produire un texte coranique.

**La méthode retenue** (proposition utilisateur, et c'est elle qui rend le
chantier défendable) : ne pas *produire* le texte par OCR, mais le
**confirmer**. Trois sources qui votent —

1. le texte KFGQPC déjà embarqué ;
2. un premier mushaf Warsh scanné ;
3. un second, d'une **édition réellement différente** (deux scans de la même
   édition ne se vérifient pas : ils répètent la même erreur d'impression).

Là où les trois concordent, c'est acquis. Là où ils divergent, **on ne tranche
pas automatiquement** : on produit une liste courte à relire. C'est la double
saisie, la méthode employée pour les textes qu'on n'a pas le droit de rater.

**Deux couches à traiter séparément** : l'OCR arabe est bon sur le squelette
consonantique et mauvais sur les **harakat**. Une divergence sur les lettres
est un vrai signal ; une divergence sur une haraka accuse d'abord l'OCR.

**La coloration tajwid des PDF ne sert à rien ici** — les aplats de couleur
dégradent l'OCR, et l'app calcule déjà ses règles elle-même
(`quran_rules_annotated.json`). Le vrai sujet Warsh est de vérifier que ce
moteur tient sur les particularités warshiennes.

**Besoin réel en GPU** : faible pour le texte (Tesseract tourne sur processeur ;
le GPU sert seulement à faire tourner un modèle de vision meilleur sur les
diacritiques, **sans envoyer le mushaf à un service tiers**). Fort pour l'audio
et le modèle (§4, réétiquetage des 86 000 clips, aligneur, mesure sur Warsh).

**Premier geste au retour, avant tout OCR** : contrôle de structure du KFGQPC —
décomptes par sourate selon le madanī, total 6214, cohérence des 604 pages. Ça
ne demande ni GPU ni scan, et un défaut structurel doit se savoir avant qu'on
ait numérisé une seule page.

**Piège de méthode relevé au passage, et qui vaut au-delà de Warsh** : sans le
mapping du YEH BARREE (U+06D2, 2 996 occurrences) et de l'ALEF WASLA (U+0671),
on mesure **son propre normaliseur** (6,25 % d'écart) et non les deux textes
(0,84 %). Le YEH BARREE est une *lettre*, pas un diacritique : la classe des
harakat ne le retirait pas, et `فے` attendu ne pouvait jamais correspondre au
`في` produit par le modèle. Correction mesurée : 94,29 % → **98,06 %** de
correspondance, soit 2 921 mots qui seraient sortis rouges quoi que récite
l'utilisateur.

---

Le constat d'origine, conservé pour la mémoire du dossier :

**Le projet n'avait aucun texte Warsh.** C'est documenté dans
`benchmark/BENCHMARK_RESULTS.md` :

> le label texte de ces clips est le texte **Hafs** standard (pas le vrai texte
> Warsh, `download_assajda.py::load_quran_text()` charge le même texte pour
> tous) — le WER absolu y est gonflé par de vraies divergences textuelles
> Warsh/Hafs

Conséquences, à ne pas confondre :

1. **Les ~86 000 clips Warsh du corpus sont mal étiquetés.** Ils sont exclus de
   l'entraînement Hafs (`build_hafs_only_manifest.py`), donc ils ne polluent
   rien — mais ils sont **inutilisables tels quels** pour entraîner du Warsh.
2. **Les chiffres Warsh des bancs ne mesurent pas ce qu'on croit.** Un WER
   « squelette » de 28 à 43 % sur ce jeu mélange les erreurs du modèle et les
   divergences réelles entre les deux riwāyāt. Seule la comparaison *relative*
   entre deux checkpoints y est interprétable — c'est écrit dans le banc, et
   c'est un piège à ne pas repayer.
3. **Ajouter Warsh à l'app suppose d'abord d'obtenir un texte Warsh vérifié**,
   puis de réétiqueter ces 86 000 clips avec. C'est un préalable, pas une
   conséquence.

**Ce point est indépendant de la question Quran Foundation** : ni QF ni Tanzil
ne fournissent Warsh. Il faudra une troisième source de toute façon — les
mushafs Warsh publiés par le Complexe du Roi Fahd sont la piste la plus
évidente, **à vérifier**, je ne l'ai pas fait.

---

## 3. L'audio — moins documenté qu'on ne le croyait

**Correction d'une formulation antérieure de ce dossier.** everyayah et
quranicaudio ont été présentés comme « sans clé, sans condition, sans serveur ».
C'est vrai techniquement, et trompeur juridiquement : **« aucune condition
annoncée » ne veut pas dire « aucune condition ».**

Vérifié le 2026-08-12 : **everyayah.com ne publie ni conditions d'utilisation,
ni licence, ni notice de copyright, ni identité d'exploitant.** Le seul contact
est un portail Zendesk.

La seule affirmation de licence en circulation vient d'un **commentaire d'un
contributeur extérieur** sur l'issue #434 de `quran/quran_android` :

> « Data from www.everyayah.com [...] are **CC-BY-NC** because it is Quran too. »

Aucun mainteneur ne l'a confirmée, et la page de licence citée en source renvoie
une **404**.

⚠️ **Le point qui compte** : la seule piste disponible pointe vers **NC —
NonCommercial**, c'est-à-dire précisément la famille de licence qui entrerait en
conflit avec l'acceptation de dons. Alors que Quran Foundation a écrit
explicitement que les dons volontaires ne nécessitent aucune licence
commerciale.

**La sortie audio n'est donc pas établie comme plus libre que la situation
actuelle. Elle pourrait être plus contraignante.** D'où le courrier en annexe.

Et un point structurel : everyayah **héberge**, il n'est pas nécessairement
l'ayant droit. Chaque récitateur détient des droits sur son enregistrement —
une licence du site ne les couvrirait pas automatiquement.

---

## 4. Le minutage — le plus gros chantier, et le seul qui décide

C'est le verrou. Tant que les `segments` de Quran Foundation sont
indispensables, il faut leur API, donc le proxy qu'ils imposent, donc un serveur
à maintenir à vie et le contrôle de contenu tous les 7 jours.

**Si l'aligneur maison passe la mesure, tout ça disparaît d'un coup.**

### Ce qu'on a déjà

- L'aligneur forcé CTC est **déjà dans le projet**, des deux côtés :
  `ForcedAligner.kt` sur l'appareil, `spans_mots()` sur PC.
- Le modèle ASR est ajusté sur la récitation coranique — donc bien meilleur sur
  ce matériau qu'un aligneur générique.
- L'audio complet des récitateurs, déjà téléchargé pour l'entraînement.
- **Un jeu de validation étiqueté gratuit** : les 3520 versets de
  `app/assets/data/word_timings_ms.json`, qui viennent des `segments` de
  quran.com. S'en servir pour *mesurer* son propre aligneur n'est pas de la
  redistribution.
- Le GPU.

### Pourquoi c'est jouable alors qu'une mesure du projet dit le contraire

`ETAT_CTC_NEMO.md` documente un échec de l'alignement forcé : **43,3 % de WER**,
avec la cause nommée — « l'alignement CTC est POINTU par nature (un mot mesuré à
1 frame quand son voisin en fait 31) ».

**Mais cette mesure portait sur le découpage de clips d'ENTRAÎNEMENT**, où une
erreur de quelques dizaines de millisecondes empoisonne l'étiquette. Rejouer un
mot à un récitateur tolère ±100 ms sans que personne ne l'entende : il suffit de
démarrer un peu avant et de finir un peu après. **La mesure qui condamnait la
piste ne se transporte pas ici.** C'est la seule raison pour laquelle ce
chantier est rouvert, et elle doit être dite à chaque fois qu'on le rouvre.

### Le banc à écrire, et son critère

Aligner les 3520 versets déjà étiquetés, comparer début et fin de chaque mot aux
`segments`, sortir la distribution de l'erreur en millisecondes.

> **Critère : erreur médiane < 80 ms et 95ᵉ centile < 200 ms.**

Au-dessus : on construit le proxy et on garde l'autorisation en main.
En dessous : plus besoin des `segments`, donc plus d'API, donc **ni proxy, ni
contrôle hebdomadaire, ni identifiants à protéger**.

Garde-fous à implanter dès le premier jet, contre la « pointe » du CTC qui est
le défaut connu : plancher de durée par mot, répartition du reste au prorata du
nombre de lettres, intervalles strictement croissants et non chevauchants.

### Discipline de mesure

Rappels des règles du projet, qui s'appliquent ici sans exception :

- **trois passes minimum**, sur trois passages de nature différente — un à
  répétitions (sourate 55), un long (2), un court (67 ou 36). Mesurer toujours
  sur le même passage revient à corriger *ce* passage ;
- **ne pas conclure sur une seule largeur de fenêtre** : un mot peut être
  parfait à 3 s et introuvable à 12 s ;
- **ne jamais écrire « absent » sur un test de sous-chaîne** : le modèle décode
  souvent une quasi-homophone (`قاموا` → `قالوا`). Lire le texte réellement
  décodé.

⚠️ **Ce chantier tourne sur le poste Ubuntu, actuellement injoignable**
(cf. `PUBLICATION_PLAY.md` §10). C'est le premier déblocage à obtenir.

---

## 5. Ordre d'exécution

1. **Envoyer le courrier à everyayah** (annexe ci-dessous). Ça ne coûte rien et
   la réponse conditionne toute la partie audio. La même démarche auprès de
   Quran Foundation avait abouti en 24 h.
2. **Récupérer l'accès au poste Ubuntu.**
3. **Écrire le banc d'alignement et sortir le chiffre.** C'est lui qui tranche
   entre « proxy à vie » et « indépendance ».
4. **Selon le chiffre**, et seulement après : soit construire le proxy, soit
   basculer le texte sur Tanzil et l'audio sur la source dont on aura obtenu
   l'accord.
5. **Warsh** : chantier distinct, qui commence par obtenir un texte Warsh
   vérifié — sans quoi ni l'entraînement ni la vérification n'ont de sens.

**Ne pas construire le proxy avant l'étape 3.** C'est le seul endroit de ce plan
où l'ordre peut éviter un serveur à maintenir indéfiniment.

---

## Annexe — courrier à everyayah.com

À envoyer via leur portail de contact (Zendesk, lien « Contact » du site).
Champs à compléter : nom, adresse e-mail.

### Version anglaise — à envoyer

**Subject:** Permission and licence question — use of EveryAyah recitations in a free Qur'an app

Dear EveryAyah team,

I am an independent developer. I am building a free Android application, *Coran Karim*, which helps a user memorise and recite the Qur'an: the application listens through the microphone and checks the recitation word by word against the text, using a speech-recognition model that runs entirely on the device.

I would like to use the recitations you host, and I could not find any terms of use or licence statement on your site — which is why I am writing rather than assuming.

**What I would use.** The per-ayah audio files served from `everyayah.com/data/{reciter}/{surah}{ayah}.mp3`, played in the application and, when a user explicitly asks to download a surah, stored in the application's private storage on that user's own device until they delete it. Nothing would be copied to any server of mine, aggregated, or re-served to anyone else.

**My questions.**

1. Is there a licence or terms of use that apply to these recordings? If so, where can I read them?
2. Does that permission extend to a **free application distributed on Google Play**, including the offline storage described above?
3. The application is free and has no revenue. I am considering accepting **voluntary donations** to cover costs. Would that be compatible with your terms? I ask specifically because a licence of the NonCommercial family would not be, and I would rather know now than later.
4. Do the **reciters** retain rights that require separate permission, or does your permission cover them?
5. How would you like to be credited inside the application?

**My commitments.** The audio is never modified, never resold or sublicensed, and never distributed outside the end-user experience of the application. Attribution would be displayed in the application's "About" screen. If you would prefer that I do not use these recordings, I will not, and there will be no hard feelings.

Thank you for the service you provide, and for the time you give to this request.

Kind regards,

[Name]
[Email address]
Android package: `com.corankarim.coran_karim`

### Traduction française — pour ta lecture

**Objet :** Question de licence et d'autorisation — usage des récitations EveryAyah dans une application gratuite

Chère équipe d'EveryAyah,

Je suis un développeur indépendant. Je réalise une application Android gratuite, *Coran Karim*, qui aide à mémoriser et à réciter le Coran : elle écoute au micro et vérifie la récitation mot à mot par rapport au texte, à l'aide d'un modèle de reconnaissance de la parole qui fonctionne entièrement sur l'appareil.

Je souhaiterais utiliser les récitations que vous hébergez, et je n'ai trouvé sur votre site ni conditions d'utilisation ni mention de licence — c'est pourquoi je vous écris plutôt que de présumer.

**Ce que j'utiliserais.** Les fichiers audio par verset servis depuis `everyayah.com/data/{reciter}/{surah}{ayah}.mp3`, lus dans l'application et, lorsqu'un utilisateur demande explicitement le téléchargement d'une sourate, conservés dans le stockage privé de l'application sur son propre appareil jusqu'à ce qu'il les supprime. Rien ne serait copié sur un serveur m'appartenant, ni agrégé, ni re-servi à quiconque.

**Mes questions.**

1. Existe-t-il une licence ou des conditions d'utilisation applicables à ces enregistrements ? Si oui, où puis-je les lire ?
2. Cette autorisation couvre-t-elle une **application gratuite distribuée sur Google Play**, y compris la conservation hors ligne décrite ci-dessus ?
3. L'application est gratuite et sans revenu. J'envisage d'accepter des **dons volontaires** pour couvrir les frais. Serait-ce compatible avec vos conditions ? Je pose la question explicitement parce qu'une licence de la famille NonCommercial ne le serait pas, et je préfère le savoir maintenant.
4. Les **récitateurs** conservent-ils des droits nécessitant une autorisation distincte, ou votre autorisation les couvre-t-elle ?
5. Sous quelle forme souhaitez-vous être crédités dans l'application ?

**Mes engagements.** L'audio n'est jamais modifié, jamais revendu ni sous-licencié, et jamais diffusé hors de l'expérience utilisateur de l'application. L'attribution serait affichée dans l'écran « À propos ». Si vous préférez que je n'utilise pas ces enregistrements, je ne le ferai pas, sans rancune.

Merci pour le service que vous rendez, et pour le temps consacré à cette demande.

Cordialement,

[Nom]
[Adresse e-mail]
Paquet Android : `com.corankarim.coran_karim`

---
---

## Annexe 2 — courrier à MP3Quran.net

**À qui l'envoyer : non trouvé.** Cinq tentatives de lecture de leur site
(page d'accueil, `/eng/api`, `/privacy`) ont toutes échoué en 403 — probable
protection anti-robot. Aucune adresse e-mail ni formulaire de contact
identifié à ce jour. **À compléter en ouvrant le site depuis un navigateur
normal** : chercher « اتصل بنا » (contact) ou une page « عن الموقع » (à
propos).

**Pourquoi ce courrier, distinct de celui à everyayah.** MP3Quran.net couvre
une partie différente et complémentaire du besoin :

- en **Hafs**, au moins trois récitateurs de l'app confirmés présents chez
  eux : Mishary Al-Afasy, Abdul Basit Abdul Samad (Mujawwad et Murattal), et
  **Nasser Al-Qatami** — qui n'est couvert ni par everyayah pour le minutage,
  ni par `cpfair/quran-align` (12 récitateurs, aucun Qatami) ;
- en **Warsh**, six récitateurs identifiés (Al-Kouchi, Al-Husary, Yassin,
  Al-Ayrawy, Diban, Muhammad Sayed) — contre deux seulement chez everyayah,
  qui sont ceux déjà utilisés sans permission par l'app aujourd'hui.

Une réponse favorable comblerait donc à la fois le trou Qatami côté Hafs et
donnerait une alternative Warsh à la dépendance everyayah actuelle.

**Ce que ce courrier NE demande PAS** : aucun minutage mot à mot. Vérifié le
2026-08-12 sur leur documentation d'API (`MP3Quran/apis` sur GitHub, fichiers
`moshafs.md`/`suars.md`/`reciters.md`) : la granularité s'arrête à la
**sourate**, aucun point d'accès par verset ni par mot. Pour ça, seul
l'aligneur maison (§4) répond au besoin.

### Version arabe (à envoyer)

**الموضوع:** استفسار عن ترخيص استعمال تسجيلاتكم الصوتية داخل تطبيق مجاني لتلاوة القرآن

السلام عليكم ورحمة الله وبركاته،

أنا مطوّر مستقل، وقد أنجزت تطبيقًا مجانيًا لنظام أندرويد باسم *Coran Karim*،
يساعد المستخدم على حفظ القرآن الكريم وتلاوته: يستمع التطبيق إلى التلاوة عبر
الميكروفون ويقارنها بالنص كلمةً كلمة، بواسطة نموذج للتعرّف على الكلام يعمل
داخل الجهاز نفسه دون اتصال بالإنترنت.

**ما أودّ استعماله من موقعكم**

لاحظت أن موقعكم يستضيف تسجيلات عدد كبير من القرّاء، برواية حفص وبرواية ورش عن
نافع معًا -- من بينهم مشاري العفاسي وعبد الباسط عبد الصمد وناصر القطامي
(حفص)، وكذلك العيون الكوشي والحصري وياسين ومحمد الإيراوي وأحمد ديبان ومحمد
سايد (ورش). وقد بحثت في موقعكم عن شروط استخدام أو ترخيص لهذه التسجيلات ولم
أجد شيئًا، لذا أفضّل السؤال بدل الافتراض.

**ما أطلبه**

1. هل هناك إذن أو ترخيص يسمح باستعمال هذه التسجيلات -- بثًّا مباشرًا، وعند
   طلب المستخدم الصريح تنزيل سورة، حفظها في التخزين الخاص بالتطبيق على جهازه
   حتى يحذفها -- داخل تطبيق مجاني منشور على المتجر؟
2. هل يشملكم الأمر أنتم، أم أن لكل قارئ حقوقًا يجب طلبها منه على حدة؟
3. التطبيق مجانيّ اليوم بلا أي دخل. وأفكّر مستقبلًا في قبول تبرّعات اختيارية
   لتغطية التكاليف -- فهل يغيّر ذلك شيئًا في نظركم؟
4. الصيغة التي تحبّون أن يُنسب بها موقعكم داخل التطبيق.

**نقطة أعرضها عليكم بصراحة** : إن أذنتم، فقد يستهلك التطبيق حجمًا معتبرًا من
النطاق الترددي لخوادمكم إن اتسعت قاعدة مستخدميه -- أفضّل إخباركم بذلك مسبقًا
بدل أن تكتشفوه لاحقًا. إن كان لديكم حدّ أقصى للطلبات ترونه مناسبًا، فأنا على
استعداد للالتزام به.

**تعهّداتي**

- لا أعدّل التسجيلات ولا أقتطع منها.
- لا أبيعها ولا أرخّصها لغيري ولا أنشرها خارج تجربة المستخدم داخل التطبيق.
- أذكر المصدر داخل شاشة «حول التطبيق».
- إن فضّلتم ألّا أستعمل هذه التسجيلات، فلن أستعملها، ودون أي اعتراض.

جزاكم الله خيرًا على هذا العمل، وشكرًا لوقتكم.

وبالله التوفيق،

[الاسم]
[البريد الإلكتروني]
اسم حزمة التطبيق: `com.corankarim.coran_karim`

### Traduction française — pour ta lecture

**Objet :** Question de licence pour l'utilisation de vos enregistrements audio dans une application gratuite de récitation du Coran

Assalamu alaykum wa rahmatullahi wa barakatuh,

Je suis un développeur indépendant et j'ai réalisé une application Android gratuite, *Coran Karim*, qui aide à mémoriser et à réciter le Coran : elle écoute au micro et vérifie la récitation mot à mot par rapport au texte, à l'aide d'un modèle de reconnaissance de la parole qui fonctionne entièrement sur l'appareil, sans connexion.

**Ce que je souhaiterais utiliser de votre site**

J'ai remarqué que votre site héberge les enregistrements d'un grand nombre de récitateurs, en riwāya Hafs et en riwāya Warsh ʿan Nāfiʿ à la fois — parmi lesquels Mishary Al-Afasy, Abdul Basit Abdul Samad et Nasser Al-Qatami (Hafs), ainsi qu'Al-Kouchi, Al-Husary, Yassin, Muhammad Al-Ayrawy, Ahmad Diban et Muhammad Sayed (Warsh). J'ai cherché sur votre site des conditions d'utilisation ou une licence pour ces enregistrements et n'ai rien trouvé — je préfère donc demander plutôt que présumer.

**Ce que je demande**

1. Existe-t-il une autorisation ou une licence permettant d'utiliser ces enregistrements — en streaming, et lorsque l'utilisateur demande explicitement le téléchargement d'une sourate, en les conservant dans le stockage privé de l'application sur son appareil jusqu'à ce qu'il les supprime — dans une application gratuite publiée sur le store ?
2. Cette autorisation vous concerne-t-elle vous, ou chaque récitateur détient-il des droits à demander séparément ?
3. L'application est gratuite aujourd'hui, sans aucun revenu. J'envisage à l'avenir d'accepter des dons volontaires pour couvrir les frais — cela change-t-il quelque chose à vos yeux ?
4. La formulation par laquelle vous souhaitez que votre site soit crédité dans l'application.

**Un point que je vous expose franchement** : si vous l'autorisez, l'application pourrait consommer une bande passante non négligeable sur vos serveurs si sa base d'utilisateurs s'élargit — je préfère vous en informer à l'avance plutôt que vous le découvriez plus tard. Si vous avez une limite de requêtes que vous jugez appropriée, je suis prêt à la respecter.

**Mes engagements**

- Je ne modifie ni ne découpe les enregistrements.
- Je ne les vends pas, je ne les sous-licencie pas et je ne les diffuse pas hors de l'expérience utilisateur de l'application.
- Je cite la source dans l'écran « À propos ».
- Si vous préférez que je n'utilise pas ces enregistrements, je ne le ferai pas, sans aucune objection.

Qu'Allah vous récompense pour ce travail, et merci pour votre temps.

[Nom]
[Adresse e-mail]
Paquet Android : `com.corankarim.coran_karim`
