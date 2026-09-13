# Performance — audit du 2026-09-13

Demande utilisateur : « j'ai un serieur probelme de performence sur ce tel
audite », puis « audite bien la preformence », puis « solution !! / améliore /
documente tout ».

> ## ⚠️ LIRE CECI EN PREMIER — L'AUDIT A CHANGÉ DE CIBLE EN COURS DE ROUTE
>
> Les §1 à §3 ci-dessous portent sur le **démarrage**. C'est là que l'audit a
> commencé, et le travail y est réel — mais **ce n'était pas le problème de
> l'utilisateur**. Il l'a dit lui-même, après coup :
>
> > « la deja suis mushaf papier je n'utilise mme pas ASR ! juste un page de
> > mushaf »
> > « mon probelem aussi c le scrolling c pas bon du tt c long ya un souci »
> > « est ce que c tt le curan qui est chargé !! »
>
> **La vraie cause est au §7**, et la troisième citation la nomme exactement :
> oui, tout le Coran est chargé, sur le thread qui dessine, pour afficher une
> seule page. Commencer par le démarrage parce que c'est ce qui se mesure le
> plus facilement (`am start -W`) est une erreur de méthode à retenir : **on a
> mesuré ce qui était commode, pas ce dont l'utilisateur se plaignait.**
>
> Autre précision donnée par l'utilisateur, qui valide le choix de l'appareil :
> *« j'ai pas ce probelem dasn samsung c bien avec un tel moyen game pour montré
> ces probleme »* — le Redmi milieu de gamme est un bon révélateur, il reste la
> référence de mesure.

Téléphone : **Redmi Note 9 Pro** (`joyeuse_eea`, Adreno 618, MIUI), nouvellement
mis en service — c'est lui qui a fait apparaître le problème, l'app n'avait
jamais été mesurée dessus. Contrainte permanente rappelée par l'utilisateur :
*« ton travail doit être fonctionnel sur n'importe quel téléphone »*.

---

## 0. Le résultat, en une ligne

Le démarrage est passé de **~3450 ms à ~1970 ms** (−43 %) sur ce téléphone, et
la cause principale n'était pas dans le code de l'application : c'était le
**régime de compilation**. Trois correctifs ont été appliqués, et une piste
soupçonnée a été **disculpée par la mesure**.

---

## 1. Ce qui a été mesuré, et avec quel instrument

Toutes les valeurs ci-dessous viennent d'une exécution sur l'appareil, pas
d'une estimation.

### 1.1 Démarrage à froid (`am start -W`, médiane sur 3-4 lancements)

| variante | lancements (ms) | médiane |
|---|---|---|
| debug (avant) | 3828 / 3434 / 3450 | **~3450 ms** |
| profile (AOT) | 1984 / 1996 / 1947 / 1897 | **~1970 ms** |

Le profile est non seulement plus rapide, il est **beaucoup plus stable**
(±50 ms contre ±400 ms). Une dispersion de 400 ms est en soi le symptôme d'une
compilation qui a lieu *pendant* le lancement.

`onCreate` : **5449 ms au tout premier lancement après installation**
(artefact d'installation du profil ART, non reproductible), **903 ms** en
régime établi. Ne jamais tirer de conclusion du premier lancement post-install.

### 1.2 Ce que contiennent réellement les deux APK

C'est la preuve matérielle du diagnostic — obtenue en listant le contenu des
archives, pas en le supposant.

| contenu | debug | profile | rôle |
|---|---|---|---|
| `kernel_blob.bin` | **33,6 Mo** | absent | code Dart **non compilé**, JIT au lancement |
| `libapp.so` | absent | présent | code Dart **compilé AOT** |
| `libVkLayer_khronos_validation.so` | **15,2 Mo** | absent | valide **chaque appel Vulkan** du moteur de rendu |
| `lib/arm64-v8a` | 80,4 Mo | — | le seul jeu d'instructions utilisé ici |
| `lib/x86_64` | 72,2 Mo | — | **émulateur uniquement** |
| `lib/armeabi-v7a` | 51,6 Mo | — | téléphones 32 bits |

Et la couche de validation n'est pas seulement embarquée, elle est **chargée** :
`added global layer 'VK_LAYER_KHRONOS_validation'` apparaît dans logcat au
démarrage.

---

## 2. Les erreurs de méthode commises pendant cet audit

Consignées parce que ce sont elles qui ont fait perdre le plus de temps, et
qu'elles se referont sinon.

### 2.1 ⛔ `dumpsys gfxinfo` ne mesure PAS une application Flutter

`adb shell dumpsys gfxinfo <paquet>` a été utilisé et a rendu :

```
Total frames rendered: 5      Janky frames: 3 (60%)
50th percentile: 300ms        90th/95th/99th percentile: 1250ms
50th gpu percentile: 2ms      99th gpu percentile: 7ms
Number Slow UI thread: 2
```

J'en ai conclu « le coût est sur le thread UI, pas sur le GPU ». **C'était une
conclusion bâtie sur un instrument hors sujet.** gfxinfo rapporte les frames de
**HWUI**, le moteur de rendu des *vues Android*. Flutter dessine dans sa propre
surface via Impeller et ne passe pas par HWUI : ces 5 frames sont celles du
décor Android, pas de l'interface. Contrôle décisif fait ensuite — après six
`input swipe` sur la liste des sourates, gfxinfo annonçait **« Total frames
rendered: 0 »**. Un écran qui défile et produit zéro frame : l'instrument ne
voit rien.

➡️ L'instrument correct est `SchedulerBinding.addTimingsCallback`. Il est
désormais branché en permanence dans l'app, cf. §3.3.

### 2.2 Le pic CPU à 92,8 % était le mien

Relevé de charge CPU à 92,8 % interprété d'abord comme une boucle de l'app.
Contrôle : laissé 15 s sans y toucher, il retombe au repos. C'était la rafale
de commandes `adb` de la mesure elle-même. Un diagnostic qui modifie ce qu'il
mesure n'est pas un diagnostic.

### 2.3 La piste TTS était fausse — disculpée par la mesure

Hypothèse de départ, appuyée sur deux faits réels : (a) `I/TextToSpeech:
Sucessfully bound to com.google.android.tts` apparaît au démarrage **avant** que
la VM Dart ne démarre, alors que `ExplanationTtsService` n'est référencé que
depuis `coach_explanation_sheet.dart` ; (b) une trace antérieure montrait
`Slow Binder: BpBinder transact took 11021 ms, interface=ITextToSpeechService`.

**Le mécanisme est confirmé** — lecture du code du plugin, pas supposition :
`flutter_tts-4.2.5/.../FlutterTtsPlugin.kt`, `onAttachedToEngine` →
`initInstance` → `tts = TextToSpeech(context, ...)`, inconditionnellement. Comme
`GeneratedPluginRegistrant` s'exécute dans `configureFlutterEngine`, le moteur
TTS est bien lié avant tout code Dart.

**Mais le coût mesuré est négligeable.** Trace de démarrage horodatée :

```
19:34:34.315  Dart VM service listening
19:34:34.323  TextToSpeech: Sucessfully bound     (+8 ms)
19:34:34.342  TextToSpeech: Connected to engine   (+19 ms au total)
```

**~20 ms, et asynchrone.** Les 11 s du relevé antérieur étaient un réveil à
froid du processus `com.google.android.tts`, non reproductible. ➡️ **Aucun
correctif appliqué sur le TTS** : il n'y avait pas de défaut à corriger. Le
forker pour le rendre paresseux aurait été du travail invasif sur une cause
imaginaire.

---

## 3. Les correctifs appliqués

### 3.1 La variante `profile` ne compilait plus depuis 9 jours — réparée

`flutter build apk --profile` échouait net :

```
ERROR: AndroidManifest.xml:137: AAPT: error: resource string/app_name
       (aka com.corankarim.coran_karim:string/app_name) not found.
```

Cause : le manifeste porte `@string/app_name` depuis le 2026-09-04 (pour que la
variante DEV puisse s'appeler autrement), et cette ressource est définie par
`resValue` dans les blocs `release` et `debug` — mais **`profile` est créée par
le plugin Gradle de Flutter**, pas par nous, et n'héritait donc d'aucun des
deux.

**Pourquoi c'est le défaut le plus coûteux de cet audit :** `profile` est *la*
variante de mesure de performance de Flutter. Tant qu'elle ne compile pas, la
seule chose installable sur un téléphone est un build `debug`, et toute plainte
de lenteur devient **indécidable** — on ne peut pas distinguer « l'app est
lente » de « le mode debug est lent », faute de point de comparaison. C'est
exactement le mur rencontré au début de cet audit.

Correctif dans `app/android/app/build.gradle.kts` : bloc
`getByName("profile")` avec `resValue`, `applicationIdSuffix = ".dev"` (les
chemins de diagnostic restent identiques, tous les scripts adb continuent de
marcher) et `versionNameSuffix = "-profile"` (pour qu'un relevé ne puisse
jamais être attribué à la mauvaise variante).

### 3.2 La couche de validation Vulkan retirée des builds debug

**Pourquoi ça compte ici, et pas dans un projet ordinaire :** la règle de ce
projet est que *les builds sont en debug par défaut* (en release le journal Dart
est muet et les WAV de diagnostic inaccessibles). Le debug est donc le régime de
tous les jours. « C'est lent parce que c'est du debug » n'est pas une réponse
recevable — il faut rendre le debug utilisable.

Des deux surcoûts du debug, un seul peut partir sans perdre le debug :

- `kernel_blob.bin` / JIT → **inséparable du debug**. C'est ce qui permet le
  hot reload. On le garde.
- `libVkLayer_khronos_validation.so` → **retirable**. C'est un outil pour qui
  développe le *moteur* Flutter, pas une application : il valide chaque appel
  Vulkan émis par Impeller, ne diagnostique rien de ce code-ci, et son coût est
  payé à chaque frame.

Ce qu'on **ne perd pas** : JIT, hot reload, `DiagnosticLog`, WAV de capture,
`run-as`, VM service, assertions Dart, banc à deux téléphones. Tout le
diagnostic du projet est intact.

Réversible sans toucher au fichier :
`flutter build apk --debug -PgarderValidationVulkan=true`.

### 3.3 Trois démarrages séquentiels rendus parallèles + instrumentés

`main()` enchaînait trois `await` **l'un après l'autre** alors qu'aucun ne
dépend du résultat d'un autre — trois allers-retours de canal de plateforme mis
bout à bout :

```dart
await DiagnosticLog.init();
await ReciterDownloadService().ensureReady();
await initSessionMedia();
```

Désormais lancés ensemble et attendus ensemble (`Future.wait`). Le total est
maintenant le **maximum** des trois, plus leur somme.

⚠️ **Ce qui n'a PAS été fait, et c'est délibéré** — la tentation suivante serait
de les repousser *après* `runApp` pour afficher l'écran plus tôt. Ce serait un
piège, écrit dans le code pour que personne ne le redécouvre :

- `ReciterDownloadService.ensureReady` : tant qu'il n'a pas répondu,
  `localPathIfPresent` rend `null` et une sourate **pourtant téléchargée**
  repart en streaming, silencieusement ;
- `initSessionMedia` : `AudioService.init` doit précéder la création de
  `PlayerNotifier`. Après `runApp`, un premier `ref.watch(playerProvider)` peut
  arriver avant, et la notification média serait morte sans que rien ne le dise.

Le gain vient du recouvrement, pas d'un report : aucune garantie d'ordre n'est
sacrifiée.

**Instrumentation ajoutée en même temps.** Chaque lancement écrit désormais dans
le journal :

```
[Demarrage] avant runApp=XXXms (journal=Ams audioLocal=Bms sessionMedia=Cms
            — lances en parallele, le total est donc le MAX et non la somme)
```

C'est ce qui manquait : `am start -W` donnait 3861 ms et `onCreate` 903 ms, mais
entre les deux **personne ne pouvait dire quelle étape coûtait quoi**. Trois
`Stopwatch` suppriment la supposition.

### 3.4 Mesure de fluidité permanente — `lib/services/mesure_fluidite.dart`

Nouveau fichier. Utilise `SchedulerBinding.addTimingsCallback` (ce que fait
DevTools) pour rapporter, toutes les 240 frames :

```
[Fluidite] frames=240 budget=16.7ms ratees=N (x%) graves=M |
           construction p50=… p90=… p99=… | rasterisation p50=… p90=… p99=…
```

`construction` = thread UI (Dart), `rasterisation` = thread GPU — la séparation
qui permet de dire *où* est le coût, celle que gfxinfo ne pouvait pas donner.

Trois choix à ne pas défaire :
- **le budget de frame est lu sur l'appareil**, pas codé à 16,7 ms : une frame
  de 15 ms est confortable à 60 Hz et ratée à 120 Hz. Un seuil fixe donnerait un
  verdict faux sur la moitié du parc — directement la règle « fonctionnel sur
  n'importe quel téléphone » ;
- **inactif si `DiagnosticLog.enabled` est faux**, donc silencieux en release —
  même précaution que pour la journalisation ;
- **les listes sont vidées après chaque rapport**, jamais avant : un rapport est
  une tranche fermée de 240 frames, pas une moyenne glissante depuis le
  démarrage. Sinon l'à-coup du lancement resterait dans le p99 toute la session.

### 3.5 72 Mo d'émulateur retirés des APK de développement

L'APK debug fait **303 Mo**, dont 204 Mo de bibliothèques natives en trois jeux
d'instructions. `lib/x86_64` (72,2 Mo) ne sert qu'à un émulateur ; le banc de ce
projet tourne sur **deux téléphones réels** (`benchmark/recette_2tel.sh`).

⚠️ **Honnêteté sur ce que ça corrige** : un jeu d'instructions inutilisé n'est
jamais chargé en mémoire (les `.so` sont mappés à la demande). Retirer x86_64 ne
change **rien** au temps de démarrage ni à la fluidité. Ce n'est pas un
correctif de performance de l'application — c'est un correctif de la **boucle de
développement** : 72 Mo de moins à transférer et installer à chaque
`adb install`, et 72 Mo rendus sur le téléphone.

`armeabi-v7a` est **conservé** : la règle « fonctionnel sur n'importe quel
téléphone » couvre les appareils 32 bits, et rien ne prouve qu'aucun téléphone
de recette ne l'est.

Réversible : `flutter build apk --debug -PgarderAbiEmulateur=true`.

---

## 4. Deux constats propres à CE téléphone, non corrigés

### 4.1 Impeller ne tourne pas en Vulkan sur cet appareil

Séquence observée dans logcat au démarrage :

```
android_context_vk_impeller.cc(62)  Using the Impeller rendering backend (Vulkan).
android_context_gl_impeller.cc(104) Using the Impeller rendering backend (OpenGLES).
```

Le backend finalement utilisé est **OpenGLES**, pas Vulkan. Le pilote Adreno de
l'appareil est daté du **11/04/21** (`Driver Path: /vendor/lib64/hw/vulkan.adreno.so`,
`QUALCOMM build: 820d4a4028`). Flutter maintient une liste de pilotes Adreno
connus pour poser problème et bascule sur OpenGLES dans ce cas.

⚠️ **Le fait est mesuré ; la cause (liste de repli de Flutter) est une
inférence, pas une preuve.** Le vérifier demanderait de forcer les deux backends
et de comparer — non fait. C'est noté ici parce que c'est un facteur de
performance **spécifique à ce téléphone**, ce qui correspond exactement au
symptôme rapporté (« un sérieux problème de performance **sur ce tél** »).

### 4.2 Une exception au démarrage qui n'est pas la nôtre

```
org.json.JSONException: No value for joyeuse
  at android.util.MiuiMultiWindowUtils.initFreeFormResolutionArgsOfDevice(...)
  at com.android.internal.policy.DecorView.<init>(DecorView.java:335)
  at io.flutter.embedding.android.FlutterActivity.onCreate(FlutterActivity.java:652)
```

`joyeuse` est le nom de code de ce Redmi. MIUI cherche cet appareil dans sa
propre table de résolutions « fenêtre libre » et **ne l'y trouve pas** : c'est un
défaut du système du constructeur, dans `DecorView`, déclenché au passage par
`FlutterActivity.onCreate`. **Rien à corriger de notre côté.** Documenté ici
pour que la pile d'appel, qui mentionne `FlutterActivity.onCreate`, n'envoie
personne chasser un bug dans l'app.

---

## 7. LA VRAIE CAUSE — tout le Coran est chargé pour afficher une page

C'est ici que se trouve le problème rapporté. Les §1-§4 sont du travail réel
mais à côté de la plainte.

### 7.1 Ce que fait `QuranApi._ensureLoaded()`

Pour afficher **une** page de Mushaf, l'app :

1. lit `assets/data/quran_verses.json` — **8,0 Mo sur disque, 6,67 Mo décodés** ;
2. le passe à `json.decode` — 6 236 objets ;
3. construit un `Verse` par verset et deux index (`_versesBySurah`,
   `_versesByPage`).

**Le tout sur l'isolate principal**, celui qui dessine. `json.decode` est
synchrone et non interruptible : pendant son exécution, aucune frame n'est
produite et **aucun geste n'est traité**.

### 7.2 La mesure (instrumentation ajoutée ce jour, ligne `[Perf]`)

```
[Perf] QuranApi chargement TOTAL du Coran (assets/data/quran_verses.json) :
       lecture=623ms decodage=154ms indexation=26ms   <- 1er lancement (à froid)
       lecture=321ms decodage=140ms indexation=29ms
       lecture=284ms decodage=162ms indexation=34ms
       lecture=276ms decodage=172ms indexation=30ms   <- régime établi
       -> 6236 versets, 604 pages
       (SUR L'ISOLATE PRINCIPAL : interface gelée pendant tout ce temps)
```

**~470 ms en régime établi, ~800 ms à froid.** Fait contre-intuitif à retenir :
c'est la **lecture** de l'asset qui domine (276-623 ms), pas le décodage JSON
(140-172 ms). `rootBundle.loadString` doit décompresser l'entrée de l'APK puis
décoder 8 Mo d'UTF-8, et cette seconde moitié est synchrone sur le thread UI.

### 7.3 Confirmation croisée par l'instrument de fluidité

La même seconde, côté frames :

```
[Fluidite] frames=20 budget=16.7ms ratees=15 (75.0%) graves=13 PIRE=880.5ms |
           construction p50=10.7 p90=518.7 p99=878.1 |
           rasterisation p50=23.4 p90=55.6 p99=170.8
```

`PIRE=880,5 ms` : **une seule frame** bloquée près de neuf dixièmes de seconde,
et elle est sur la **construction** (thread Dart), pas sur la rastérisation.
C'est le chargement du Coran, vu depuis l'autre bout de la chaîne. Les deux
instruments, indépendants, donnent le même chiffre — c'est ce qui rend le
diagnostic sûr.

Conséquence directe et visible : lors d'un premier essai, **12 gestes de tourne
de page n'ont fait avancer que 7 pages**. Cinq gestes perdus, parce que pendant
le gel la file d'événements tactiles n'est pas servie.

### 7.4 La fenêtre dynamique existait déjà… mais seulement en façade

`fetchVersesByPage` porte en commentaire **la demande de l'utilisateur du
2026-07-11** : *« il faut faire ça dynamiquement, une page avant et une page
après »*. Voici ce que fait réellement la fonction :

```dart
static Future<List<Verse>> fetchVersesByPage(int pageNumber) async {
  await _ensureLoaded();               // décode les 6,67 Mo entiers
  return byPage[pageNumber] ?? const []; // puis rend ~10 Ko
}
```

Le fenêtrage a été implémenté dans la couche **consommatrice** (l'écran ne
demande qu'une page à la fois) pendant que la couche **source** continuait de
tout charger. C'est exactement le motif que la règle projet « PAS DE CORRECTIF
PALLIATIF » interdit — *« un correctif qui neutralise un symptôme dans une
couche AVAL alors que le défaut NAÎT dans une couche AMONT »* — et c'est
pourquoi l'utilisateur redemande la même chose deux mois plus tard.

Et sur la branche `chantier-warsh`, le chemin Warsh **paie les deux** :

```dart
static Future<List<Verse>> fetchWarshMushafVersesByPage(int pageNumber) async {
  await _ensureLoaded();                                  // 6,67 Mo (Hafs)
  ... rootBundle.loadString('assets/data/quran_mushaf_warsh.json')  // + 2,0 Mo
```

⚠️ Ce chemin n'a **pas** pu être mesuré : l'appareil était en Hafs pendant les
relevés (`[Lecture] ChGPT ouverture hafs page=19`). L'instrumentation est en
place (ligne `[Perf] QuranApi Mushaf WARSH`), il suffit de basculer en Warsh et
de relire le journal. **Ne pas annoncer de chiffre pour ce chemin avant de
l'avoir lu.**

### 7.5 Ce que la fenêtre de 3 pages rapporterait — chiffré

Répartition du poids de l'asset, mesurée sur le fichier :

| contenu | poids | part |
|---|---|---|
| **total décodé** | **6,67 Mo** | 100 % |
| `text_uthmani_tajweed` (texte coloré) | 3,06 Mo | 45,9 % |
| `translations` (français) | 1,24 Mo | 18,6 % |
| `text_uthmani` (texte nu) | 0,72 Mo | 10,8 % |
| reste (métadonnées : hizb, juz, page, sajdah…) | 1,65 Mo | 24,7 % |

Découpage par page : **604 pages, page médiane 10,5 Ko, page maximale 21,8 Ko.**

> **Fenêtre de 3 pages ≈ 31,5 Ko au lieu de 6 670 Ko — un facteur 210.**

À ~470 ms pour 6,67 Mo, 31,5 Ko se lisent et se décodent en **quelques
millisecondes**. L'intuition de l'utilisateur (« sinon il faut se limiter sur
3 pages, une avant et une autre arrière ») est non seulement bonne, elle est la
correction *de la couche où le défaut naît*.

Deux atouts déjà en place qui rendent le travail plus court qu'il n'y paraît :
- `assets/data/mushaf_lignes.json` est **déjà indexé par page** (clés `"1"` à
  `"604"`, 345 Ko) : la mise en page ne pose aucun problème ;
- chaque verset de `quran_verses.json` porte déjà `page_number` : le découpage
  est un simple regroupement, pas une inférence.

---

## 8. LA DEUXIÈME CAUSE, INDÉPENDANTE — le rendu d'une page dépasse le budget

Remontée par l'utilisateur : *« mon probelem aussi c le scrolling c pas bon du
tt c long ya un souci »*. Ce n'est **pas** le même défaut que §7, et l'instrument
le prouve : sur des tranches où le thread Dart ne fait rien, la rastérisation
dépasse quand même le budget.

```
[Fluidite] frames=20 ratees=20 (100.0%) graves=0 PIRE=825.6ms |
           construction p50=2.7 p90=3.3 p99=5.1   <- Dart ne fait RIEN
           rasterisation p50=23.5 p90=24.9 p99=29.0  <- et pourtant 23,5 ms

[Fluidite] frames=21 ratees=21 (100.0%) graves=0 |
           construction p50=2.9 p90=3.6 p99=3.7
           rasterisation p50=17.1 p90=17.8 p99=18.0
```

`construction p50 = 2,7 ms` : le calcul des widgets est bon marché. Mais
`rasterisation p50 = 17,1 à 23,5 ms` pour un budget de **16,7 ms** → `ratees =
100 %`, **frame après frame, sans aucun à-coup**. Autrement dit : même une fois
le Coran chargé, **le seul fait de dessiner une page de Mushaf coûte plus qu'une
frame à 60 Hz.** C'est la définition d'un défilement qui « traîne ».

### 8.0 LA CAUSE RÉELLE DE L'À-COUP — trouvée, mesurée, corrigée (v448)

⚠️ **Deux fausses pistes d'abord, elles valent d'être notées.**

1. *Le chargement du Coran (§7) n'était pas le principal coupable.* Après
   l'avoir sorti du thread UI (v447, `compute`), le gel est resté :
   `octets=32ms` (contre 400 ms avant, la lecture part bien en fond) mais
   `[Fluidite] PIRE=767ms construction p99=718ms`. **Un correctif qui ne
   déplace pas le chiffre qu'il visait n'est pas un correctif** — il fallait le
   dire et continuer à chercher, pas s'en satisfaire.
2. *La dichotomie de `_pageLignes` (ligne 964) n'est jamais exécutée.* Ce code
   a été **débranché le 2026-09-04** (rendu refusé par l'utilisateur : « c'est
   quoi cette connerie, reviens à la situation d'avant »). Il porte pourtant
   exactement le motif coûteux recherché (10 itérations × lignes × mots). Sans
   vérifier ses appelants, on « corrigeait » du code mort.

**Le vrai coût est dans `_blocAjuste`**, le chemin réellement exécuté :

```dart
double basse = 0, haute = 52;
for (var i = 0; i < 12; i++) {           // dichotomie 1 : 12 tours
  ... _hauteursSegments(...)             //   met en page LE TEXTE COMPLET
}
for (var essai = 0; essai < 8; essai++) {// dichotomie 2 : 8 tours
  ... _hauteursSegments(...)             //   idem
}
```

≈ **20 mises en page complètes d'une page de texte coranique** (diacritiques,
spans de tajwid) via `TextPainter`, dans un `LayoutBuilder`, sur l'isolate qui
dessine — rejouées à chaque reconstruction.

Mesure ajoutée (`[Perf] mise en page mesuree`) :

```
page=30 564ms   page=31 330ms   page=32 341ms
page=33 377ms   page=34 368ms   page=29 369ms
```

**~350 ms par page**, ~560 ms pour la première.

**Correctif (v448) : cache de la mise en page mesurée**, clé = page, écriture,
riwaya, tajwid, contraintes arrondies au pixel, nombre de segments.

| | page neuve | page en cache |
|---|---|---|
| `construction p99` | 391–426 ms | **3,9 ms** |
| frames « graves » | 23 | **0** |

**Facteur ~100**, et **aucun pixel changé** : la dichotomie est déterministe et
ne lit aucun état extérieur, donc pour des entrées identiques elle redonne
exactement le même résultat. C'était la condition pour toucher à ce code — la
mise en page du mushaf a coûté beaucoup d'allers-retours, un correctif de
performance n'a pas le droit d'en déplacer un pixel.

**Ce qui reste, et qu'il ne faut pas masquer :** la **première** visite d'une
page coûte toujours ~350 ms. En lecture continue vers l'avant, chaque nouvelle
page les paie. Deux suites possibles, non faites :
- réchauffer le cache des pages N−1 et N+1 pendant le temps mort qui suit une
  tourne (c'est la demande « une avant, une après » appliquée à la mise en page
  et non aux données) — demande d'extraire la mesure hors du `build` ;
- réduire le nombre de tours (12+8 → 8+5 donne une précision de 0,2 pt sur le
  corps, invisible, et −35 % de coût). ⚠️ Cela **peut** rendre une page
  marginalement moins pleine : à faire valider, pas à décider seul.

### 8.1 Le coût de rastérisation, lui, n'a pas bougé — piste NON confirmée

`mushaf_page_chrome.dart:153` :

```dart
CustomPaint(
  painter: MushafOrnamentalFramePainter(...),   // cadre ciselé, chemins + clip
  child: Padding( ... toute la page ... ),      // ← enfant dans la MÊME couche
)
```

Un `CustomPaint` **avec enfant** peint le painter derrière l'enfant *dans la même
couche*, et il n'y a aucun `RepaintBoundary` entre les deux. Dès que le contenu
se repeint, le cadre entier est re-rastérisé avec lui. `shouldRepaint` est
pourtant correctement écrit (il compare `tone`, `band`, `opening`) — mais
`shouldRepaint` n'évite que l'appel à `paint()` du painter lui-même, pas la
re-rastérisation de la couche qui le contient.

⚠️ **C'est une hypothèse, pas un résultat.** Elle n'a pas été mesurée. Les deux
tests qui trancheraient, dans l'ordre :
1. `RepaintBoundary` autour du cadre + `isComplex: true, willChange: false`,
   puis relire `rasterisation p50` ;
2. contre-test : retirer temporairement le cadre et mesurer — si `rasterisation
   p50` ne bouge pas, la cause est ailleurs (texte arabe colorisé, ombres,
   nombre de glyphes) et l'hypothèse tombe.

### 8.2 Réserve de méthode sur ces chiffres

Ces relevés viennent d'un build **debug**. La rastérisation est du code natif
(Impeller), donc bien moins pénalisée par le debug que le code Dart — mais
**« bien moins » n'est pas « pas du tout »**, et aucune mesure ne l'établit ici.
Avant de dimensionner un correctif sur les 17-23 ms, **refaire le relevé sur un
build profile** (désormais possible, cf. §3.1) et comparer. Ne pas promettre un
gain calculé sur un chiffre de debug.

---

## 5. Le plan de correction, et ce qui attend un arbitrage

### 5.1 Résultat du correctif de démarrage — mesuré, et décevant, il faut le dire

Après §3.2 (couche Vulkan retirée) et §3.3 (trois `await` en parallèle), même
protocole, après stabilisation d'ART :

| | avant | après |
|---|---|---|
| `am start -W` (médiane) | ~3450 ms | **~3725 ms** |
| étapes Dart dans `main()` | 2843 ms (somme séquentielle) | **1669 ms** (max parallèle) |

**Le gain interne est réel et mesuré** — la répartition par étape le montre :
`journal=1282ms audioLocal=162ms sessionMedia=1399ms` à froid, soit 2843 ms
enchaînés contre 1669 ms recouverts, **~1,2 s économisées dans `main()`**. Une
fois chaud : `journal=497ms audioLocal=183ms sessionMedia=527ms` → 806 ms.

**Mais il ne ressort pas sur `am start -W`**, qui n'a pas baissé. Deux lectures
possibles, et aucune n'est tranchée : la comparaison est polluée (la référence
de 3450 ms venait d'un APK dont le profil ART était chaud depuis longtemps,
l'APK mesuré après venait d'être installé), ou bien le temps gagné dans `main()`
est repris ailleurs. **Ne pas présenter §3.3 comme un gain de démarrage
bout-en-bout tant que ce point n'est pas élucidé.** Ce qui est acquis : la
répartition est désormais visible à chaque lancement, ce qui n'existait pas.

### 5.2 Cause n°1 (§7) — deux étapes, dont une structurelle

**Étape A — sortir le chargement du thread qui dessine.** Lecture, décodage et
indexation partent sur un isolate de fond (`compute`). Le gel de 880 ms
disparaît, plus aucun geste n'est perdu. La page apparaît toujours après
~470 ms, mais l'interface reste vivante pendant ce temps.
*Sûr, réversible, ne change aucune donnée — seulement le thread.*

**Étape B — la fenêtre de 3 pages demandée par l'utilisateur.** Asset indexé par
page, chargement de N-1 / N / N+1 : **31,5 Ko au lieu de 6 670 Ko**. C'est le
correctif *de la couche où le défaut naît*, et il rend l'étape A presque
superflue sur ce chemin.
⚠️ **Demande un arbitrage avant d'être codé**, pour une raison précise : il
touche la génération des assets et le contrat de `QuranApi`, que consomment
aussi la récitation, le lecteur audio, la recherche et le Coach — lesquels
veulent une **sourate entière**, pas une page. Il faut donc décider ce que
devient leur chemin (index par sourate chargé à la demande ? conservation de
l'asset global pour eux seuls ?). La règle projet « avant tout changement
important, committer d'abord l'état courant » s'applique : **rien n'est commité
depuis v425**.

### 5.3 Cause n°2 (§8) — mesurer avant de corriger

Tester `RepaintBoundary` + `isComplex/willChange` sur le cadre ornemental, puis
le contre-test sans cadre. **Refaire le relevé en build profile d'abord**
(§8.2) : dimensionner un correctif sur un chiffre de debug serait refaire
l'erreur du §2.

### 5.4 Autres points ouverts

- **Le chemin Warsh n'a pas été mesuré** (§7.4) : l'instrumentation est posée,
  l'appareil était en Hafs. Basculer en Warsh et relire `[Perf] QuranApi Mushaf
  WARSH`.
- **`quran_verse_locator_service._ensureLoaded`** construit un index de paires
  sur **tous les mots du Coran** (~78 000 mots × plusieurs écarts), également
  sur l'isolate principal. Non mesuré, non déclenché sur le chemin Mushaf — à
  instrumenter avant de conclure quoi que ce soit.
- **17 plugins Android** sont enregistrés séquentiellement sur le thread
  principal à `onCreate` (`audio_service`, `audio_session`, `audioplayers`,
  `flutter_compass`, `flutter_local_notifications`, `flutter_timezone`,
  `flutter_tts`, `geolocator`, `jni`, `jni_flutter`, `package_info_plus`,
  `path_provider`, `record`, `share_plus`, `shared_preferences`, `sqflite`,
  `url_launcher`). Le seul suspecté a été disculpé (§2.3) ; **le coût des 16
  autres n'a pas été mesuré individuellement**. Ne pas partir là-dessus sans
  mesure — c'est précisément l'erreur commise avec le TTS.

---

## 6. Protocole de mesure, pour refaire l'exercice

```bash
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
P=com.corankarim.coran_karim.dev

# Démarrage à froid — jeter le PREMIER lancement après installation
for i in 1 2 3 4; do
  "$ADB" shell am force-stop $P
  "$ADB" shell am start -W -n $P/com.corankarim.coran_karim.MainActivity | grep TotalTime
done

# Trace de démarrage horodatée (plugins, backend de rendu, binders lents)
"$ADB" shell am force-stop $P; "$ADB" logcat -c
"$ADB" shell am start -W -n $P/com.corankarim.coran_karim.MainActivity
"$ADB" logcat -d -v time | grep -iE "Displayed|Dart VM|Impeller|Slow Binder|TextToSpeech"

# Répartition des étapes Dart + fluidité : dans le journal de l'app
"$ADB" shell cat /sdcard/Android/data/$P/files/recitation_diagnostic.log \
  | grep -E "\[Demarrage\]|\[Fluidite\]"
```

**Ne pas utiliser `dumpsys gfxinfo` sur cette app** (§2.1).
