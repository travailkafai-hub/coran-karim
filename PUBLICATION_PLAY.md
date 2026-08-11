# Publier Coran Karim sur Google Play — dossier de reprise

**Écrit le 2026-08-10.** Ce document est fait pour être repris par quelqu'un qui
n'a pas assisté aux décisions. Il contient donc, pour chaque point : l'état
réel vérifié, ce qui a été décidé et **pourquoi**, ce qui reste à faire, et les
pièges déjà payés qu'il ne faut pas repayer.

Règle de lecture : tout ce qui est écrit ici a été **vérifié** (commande,
fichier, réponse écrite). Ce qui n'a pas été vérifié est signalé comme tel.
Ne pas transformer une hypothèse de ce document en fait.

---

## 1. Ce qu'est l'application

Application Android (Flutter + Kotlin) de mémorisation et de récitation du
Coran. Trois piliers :

- **Récitation vérifiée** : l'app écoute au micro et compare mot à mot au texte,
  avec un modèle de reconnaissance de la parole **qui tourne sur l'appareil**.
- **Lecture** (Mushaf, modes clair / sépia / sombre), invocations, horaires de
  prière, Qibla.
- **Coach / jeux de mémorisation.**

`applicationId` : `com.corankarim.coran_karim` — version `1.0.0+1`.

Principe directeur, qui explique presque toutes les décisions ci-dessous :
**tout fonctionne hors ligne, rien n'est envoyé nulle part.** Ce n'est pas une
préférence, c'est la promesse affichée dans l'écran « À propos ».

---

## 2. Ce qui BLOQUE la publication aujourd'hui

Par ordre de traitement. Les deux premiers sont des verrous durs : sans eux, le
téléversement est impossible ou l'app est inutilisable.

### 2.1 — Signature release (VERROU DUR, ~30 min) — **À FAIRE**

`app/android/app/build.gradle.kts` contient encore :

```kotlin
// TODO: Add your own signing config for the release build.
signingConfig = signingConfigs.getByName("debug")
```

Play refuse tout binaire signé avec la clé de debug, **y compris en test
interne**. Il faut aussi produire un `.aab` et non un `.apk`.

**Procédure.** Générer le keystore (l'éditeur le fait lui-même — le mot de passe
ne doit apparaître ni dans le dépôt ni dans une conversation) :

```bash
keytool -genkey -v -keystore ~/coran-karim-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias coran-karim
```

Puis `app/android/key.properties` (**à ajouter au `.gitignore`, jamais commité**) :

```properties
storeFile=/chemin/absolu/coran-karim-release.jks
storePassword=...
keyAlias=coran-karim
keyPassword=...
```

Et dans `build.gradle.kts`, lire ce fichier et remplacer le `signingConfig` de
`release`. Activer Play App Signing côté console (Google conserve la clé de
signature, on ne téléverse qu'une clé de dépôt — c'est ce qui sauve le jour où
le keystore est perdu).

⚠️ **Perdre ce keystore = ne plus jamais pouvoir mettre l'app à jour.** En faire
une sauvegarde hors machine avant même le premier téléversement.

### 2.2 — Le modèle de reconnaissance n'est pas livré (DÉCISION REQUISE)

**C'est le point le plus structurant du dossier.** Aujourd'hui les modèles sont
poussés à la main sur les téléphones de développement. Un testeur qui installe
depuis Play obtient une app qui **ne vérifie aucune récitation** : la fonction
principale ne tourne pas. Restent la lecture, les invocations, les horaires, la
Qibla.

**Chiffres mesurés le 2026-08-10** (dossier `trois-tetes-2026-08-04-combine`,
celui que `fastconformer_verifier.dart` attend) :

| | |
|---|---|
| `model.onnx` | **437,6 Mo** |
| compressé (gzip) | **404,8 Mo — soit 93 %** |
| autres fichiers | `vocab.json`, `word_tokens.json`, `tete3.json`, `rules.json` (~3,9 Mo) |

Les poids ONNX ne se compriment pas. Or **la limite de téléchargement du module
de base d'un AAB est de 200 Mo**. Le modèle ne peut donc **pas** être mis dans
l'APK/AAB tel quel — ce n'est pas un choix, c'est une limite de la plateforme.

Trois voies :

| Voie | Faisable ? | Coût | Remarque |
|---|---|---|---|
| **Play Asset Delivery**, pack `install-time` | **oui** (1 Go/pack, 2 Go au total) | config Gradle | Le modèle arrive AVEC l'installation, l'app reste hors ligne ensuite. **Recommandé** |
| **Quantifier en INT8** (~110 Mo) puis mettre en assets | oui | perte de qualité **à mesurer** | Le projet a déjà fait des exports INT8 (`whisper-*-onnx-int8`). Ne rien décider sans mesure — cf. règles projet |
| **Téléchargement au 1er lancement** | oui | hébergement + attente au démarrage | Contredit « ça marche dès l'installation », et ajoute un serveur à maintenir |

**MISE À JOUR DU 2026-08-10, APRÈS RETRAIT DE GEMMA — la recommandation
change.** Le retrait des paquets `flutter_gemma` / `flutter_gemma_litertlm`
(§3.8) a libéré **101 Mo par architecture**. Mesures sur l'APK release :

| | Avant | Après |
|---|---|---|
| APK universel | 226,3 Mo | **123,8 Mo** |
| Charge `lib/arm64-v8a` | 138,3 Mo | **37,3 Mo** |
| Téléchargement estimé, téléphone arm64 | ~150 Mo | **~52 Mo** |
| Marge sous la limite de 200 Mo | ~50 Mo | **148 Mo** |

Il reste 148 Mo de marge dans le module de base. **Un modèle quantifié INT8
(~110 Mo) y tiendrait donc directement**, sans pack séparé — c'est-à-dire
« le modèle dans l'app », ce que demandait l'éditeur.

**Recommandation révisée, dans cet ordre :**

1. **Mesurer la quantification INT8** du modèle à trois têtes (WER avant/après,
   sur les bancs du projet). Si la perte est acceptable, le modèle rentre dans
   le module de base : pas de Play Asset Delivery, pas de pack, pas d'étape de
   téléchargement. **C'est la solution la plus simple, et elle n'est devenue
   possible qu'après le retrait de Gemma.**
2. **Si la perte INT8 est inacceptable**, revenir à **Play Asset Delivery en
   `install-time`** avec le modèle FP32 (405 Mo compressés) : le pack arrive
   avec l'installation, l'app reste hors ligne, aucun serveur.

⚠️ Piège d'implémentation, dans les deux cas : **ONNX Runtime a besoin d'un
CHEMIN DE FICHIER**, pas d'un flux d'assets. Depuis `assets/`, il faut donc une
copie unique vers le stockage interne au premier lancement (~110 Mo à copier
une fois). Avec un pack PAD `install-time` livré non compressé, on obtient un
vrai chemin directement — **à vérifier au moment de l'implémentation**, je ne
l'ai pas testé.

Le FP32 à 405 Mo, lui, ne rentrera jamais dans le module de base : même sans
Gemma, on serait à ~460 Mo.

**Implémenté le 2026-08-11 (session parallèle, non commité) — voie 2 (PAD
install-time, FP32) directement, sans passer par l'étape 1 ci-dessus (mesure
INT8).** ⚠️ **À confirmer avec l'utilisateur** : l'ordre recommandé n'a pas été
suivi, l'INT8 n'a donc pas été comparé au FP32 avant ce choix.

Module Gradle `app/android/model_pack` (`com.android.asset-pack`,
`deliveryType=install-time`), fichiers du modèle en **hardlink NTFS** vers
`benchmark/models_deployes/...` (zéro octet dupliqué sur le dépôt). Le piège
du paragraphe précédent est confirmé réel : `AssetManager` ne rend pas de
chemin fichier pour un pack `install-time` (seul `on-demand`/`fast-follow` en
donnent un) — ONNX Runtime exige un chemin réel, donc extraction unique au
premier `ensureLoaded()` vers `getApplicationSupportDirectory()`, via un
nouveau canal natif `extractModelFromAssetPack` (copie `.tmp` + renommage
atomique, jamais de destination visible incomplète). Le chemin `kDebugMode`
(§5.1) n'est pas touché. Fichiers modifiés : `fastconformer_verifier.dart`,
`FastConformerCtcPlugin.kt`, `android/settings.gradle.kts`,
`android/app/build.gradle.kts`.

⚠️ **Coût disque permanent non chiffré avant ce jour : ~860-900 Mo.** Un pack
`install-time` ne se supprime jamais après coup — le modèle existe donc **en
double** en permanence : une fois dans le pack installé (~405-459 Mo), une
fois dans sa copie extraite pour ONNX Runtime (458,8 Mo). Argument de plus en
faveur de mesurer l'INT8 (~110 Mo, un seul exemplaire) avant de valider le
FP32 en pack séparé.

**Taille mesurée le 2026-08-11 avec l'outil officiel — le chiffre de 1066 Mo
ci-dessus était bien faux, cause confirmée.** `flutter build appbundle
--release` (retombe sur la clé de debug faute de `key.properties`, sans
conséquence pour une mesure de taille) puis :
```
java -jar bundletool.jar build-apks --bundle=app-release.aab --output=out.apks \
  --connected-device --adb=<chemin adb>
java -jar bundletool.jar get-size total --apks=out.apks --modules=base
java -jar bundletool.jar get-size total --apks=out.apks
```
ciblé sur un Xiaomi 22101316UG réel (arm64) :

| | Taille réelle par appareil |
|---|---|
| Module de base seul | **29,2 Mo** — largement sous la limite de 200 Mo, confirmé |
| Total installé (base + `model_pack`) | **435,8 Mo** |

Cause du chiffre de 1066 Mo confirmée : un `unzip -l` brut sur un `.aab`
**debug** somme les 4 ABI non splittées et le code non minifié -- ce n'est
pas ce qu'un appareil reçoit. `bundletool` reproduit exactement ce que Play
sert à un appareil donné ; c'est la mesure qui fait foi désormais.

### 2.3 — Politique de confidentialité + Data safety — **URL DISPONIBLE, À COLLER DANS LA CONSOLE**

Play l'exige dès qu'on demande le micro et la position. **Le contenu existe
déjà** : c'est le texte de l'écran « À propos »
(`app/lib/screens/about_screen.dart` et les clés `about*` des `.arb`).

**Page rédigée le 2026-08-11** : `docs/politique-confidentialite.html`
(autonome, sans dépendance externe). Reprend les points vérifiés ailleurs dans
ce dossier : micro/position traités sur l'appareil, réseau limité aux
téléchargements demandés, `allowBackup=false` (§3.4), pas de compte/pub/
traceur, sources et licence CC BY 4.0 du modèle ASR.

**Hébergée le 2026-08-11** sur un dépôt GitHub dédié (public, contient
UNIQUEMENT cette page -- pas le code de l'app), Pages activé :

**URL à coller dans la console Play : <https://travailkafai-hub.github.io/coran-karim-legal/politique-confidentialite.html>**

(vérifiée en ligne, réponse HTTP 200). Dépôt source :
<https://github.com/travailkafai-hub/coran-karim-legal>. Pour mettre à jour la
page, modifier `docs/politique-confidentialite.html` ici puis copier vers ce
dépôt et pousser -- les deux copies ne sont pas synchronisées automatiquement.

**Reste à faire, hors de portée sans accès à un hébergeur** :
1. **Héberger** cette page (aucun remote git n'est configuré sur ce dépôt —
   GitHub Pages est l'option la plus simple si un dépôt GitHub existe/est créé,
   sinon tout hébergeur statique convient) et obtenir une URL publique.
2. Coller l'URL dans Play Console → Présence sur le Store → Politique de
   confidentialité.
3. Remplir le formulaire **Data safety** de la console à partir des mêmes
   faits : micro (traité sur l'appareil, non transmis), position (traitée sur
   l'appareil, non transmise), aucune collecte, aucun partage à des tiers.

Le formulaire Data safety doit dire la vérité, qui est simple depuis
le 2026-08-10 : **aucune donnée ne quitte l'appareil**. Micro et position sont
utilisés localement, la sauvegarde automatique est coupée (§3.4).

### 2.4 — Icône de lancement — **À FAIRE**

`app/android/app/src/main/res/mipmap-*/ic_launcher.png` est encore **le logo
Flutter par défaut** (vérifié en ouvrant le PNG). Ça ne bloque pas
techniquement, mais ça signe une app non finie.

---

## 3. Ce qui a été FAIT le 2026-08-09/10

Tout est dans l'arbre de travail, non commité. `flutter analyze` : aucune
erreur. Les tests ajoutés sont verts.

### 3.1 — Écran « À propos » (nouveau)

`app/lib/screens/about_screen.dart` + `test/about_screen_test.dart` (6 tests).

La tuile des Réglages existait mais **n'avait aucun `onTap`** et annonçait
« Whisper » alors que la chaîne tourne sur FastConformer. Elle ouvre désormais
un écran qui porte ce que l'app doit dire avant d'être publiée : données
captées, ce qui vérifie la récitation, sources, licences.

**Attribution CC BY 4.0 du modèle ASR** (obligation vérifiée le 2026-08-09 sur
la fiche du modèle) : le modèle dérive de
`nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1`, publié en **CC BY 4.0**. La
licence impose cinq éléments — créateur, titre, lien, licence + lien, **et
l'indication que l'œuvre a été modifiée**. Ils sont dans `kNoticeAsr`, affiché
sur la page des licences, et un test unitaire vérifie qu'aucun ne disparaît.

**Drapeau `kTuteurIaEmbarque = false`** : le modèle Gemma n'est ni embarqué ni
téléchargé, donc ses conditions d'utilisation ne s'appliquent pas. Le drapeau
commande d'un seul point la notice Gemma, l'avertissement sur le texte généré et
le bloc de signalement. **Le repasser à `true` le jour où le modèle est
embarqué** — les trois obligations reviennent ensemble.

### 3.2 — Micro relâché en sortie de récitation

`app/lib/services/garde_micro.dart` (nouveau) + `test/garde_micro_test.dart`
(5 tests) + un getter `captureEnCours` sur le vérificateur + branchement dans
`main.dart`.

**Défaut corrigé TROIS fois avant, et revenu à chaque fois** (`4a09848`,
`aa67adf`, `05240c2`). Cause enfin établie : **trois écrans démarrent une
récitation** — `karaoke_recitation_screen`, `prayer_follow_screen`,
`recitation_screen` — et **un seul relâchait le micro**. Les correctifs
précédents durcissaient ce même écran pendant que les deux autres restaient
ouverts.

Le garde est un `NavigatorObserver` + `WidgetsBindingObserver` unique, posé
au-dessus de toute navigation : aucun écran, présent ou futur, n'a rien à se
rappeler de faire.

**Décisions utilisateur du 2026-08-10** :
- la **pause conserve** le micro (le relâcher imposerait un `start()` à la
  reprise, et le projet a mesuré le 2026-07-25 qu'un cycle micro mal mené fait
  que le flux PCM **ne revient jamais**) ;
- seule la **sortie** relâche ;
- le passage en **arrière-plan** est traité dans le même correctif — il
  n'existait aucun observateur de cycle de vie dans toute l'app.

### 3.3 — Diagnostic éteint par défaut en release

`DiagnosticLog.enabled = !kReleaseMode`, et le défaut des préférences suit.
Laissé actif, il conservait indéfiniment des extraits de la voix de
l'utilisateur (`recitation_captures/`, « rien ne les supprime ») et un journal
qui « grandit en annexe, jamais tronqué ». **Inchangé en debug** : le banc à
deux téléphones installe un APK debuggable, ses mesures ne bougent pas.

### 3.4 — `allowBackup=false`

`AndroidManifest.xml`. Sans cette ligne, Android copiait vers le Google Drive de
l'utilisateur : les WAV de récitation, l'empreinte vocale (donnée de nature
biométrique), les verdicts contestés, les bases SQLite. **Vérifié sur
l'appareil** avant correction (`flags=[ ... ALLOW_BACKUP ... ]`).

C'était la seule contradiction directe entre ce que l'app promet et ce qu'elle
fait. Choix de `false` plutôt que de règles d'exclusion : on perd la
restauration des signets, mais une règle mal écrite renverrait la voix en
sauvegarde **en silence**.

### 3.5 — Retrait des 11 MP3 de hisnmuslim

Les fichiers `assets/audio/duas/*_cut.mp3` étaient des copies **découpées** de
fichiers de hisnmuslim.com, livrées dans l'APK. Site sans conditions, sans
licence, sans propriétaire identifiable (vérifié). C'était le risque juridique
le plus net de l'app.

Remplacés par `Dua.audioCutMs` : on lit **leur** fichier depuis **leur** serveur
et on s'arrête après une occurrence. Seule une **durée** subsiste dans le code —
une mesure, pas une œuvre. Durées relevées à `ffprobe` sur les clips avant leur
suppression, + 150 ms de marge.

**Effet de bord assumé** : ces 11 invocations ne s'écoutent plus hors ligne.
Elles ne l'étaient pas non plus avant le 2026-08-09.

### 3.6 — Entrée de recette fermée en release

`MainActivity.kt` : l'extra d'intent `recette` n'est lu que si l'APK est
debuggable. `MainActivity` est `exported=true` : n'importe quelle app installée
pouvait détourner l'app vers l'écran de recette avec un chemin WAV arbitraire.
Le banc n'est pas affecté (il installe un APK debuggable).

### 3.7 — Corrections d'affichage

Bandeau Bismillah en mode Kindle (le paramètre `kindleMode` n'était pas
transmis), vert du curseur de lecture renforcé, emoji retiré du bandeau de la
page collection avec réduction de `expandedHeight` (132 → 100).

---

### 3.8 — Retrait du tuteur Gemma (2026-08-10)

Paquets `flutter_gemma` et `flutter_gemma_litertlm` retirés de `pubspec.yaml`,
`FlutterGemma.initialize` retiré de `main.dart`,
`lib/services/tutor_llm_service.dart` supprimé, et le repli Gemma de
`coach_explanation_sheet` remplacé par le message « aucune explication
disponible » qui existait déjà (`coachExplanationNoneAvailable`).

**Pourquoi** : le modèle `.litertlm` n'a jamais été livré. `ensureLoaded()` ne
le trouvait pas, `explainVerse` rendait toujours `null` — aucun utilisateur n'a
vu une ligne produite par ce modèle. Mais ses bibliothèques natives pesaient
**~90 Mo par architecture** : `libLiteRtLm.so` 24,8 Mo, quatre
`libQnnHtpV*Skel.so` 42,4 Mo, deux accélérateurs LiteRT 15,7 Mo,
`libGemmaModelConstraintProvider.so`, `libQnnSystem.so`.

**Ce qui est CONSERVÉ** : la cascade de tafsir (`QuranSciencesService`) reste
en place. C'est la vraie source d'explications — du texte écrit et sourcé, pas
de la génération. Le jour où ses fichiers sont livrés, l'écran fonctionne.

**Pour revenir en arrière** : remettre les deux paquets, restaurer
`tutor_llm_service.dart` depuis git, et repasser `kTuteurIaEmbarque` à `true`
dans `about_screen.dart` — ce qui rétablit d'un coup la notice Gemma,
l'avertissement sur le texte généré et le bloc de signalement exigé par la
politique « IA générative » de Play.

---

## 4. État juridique — source par source

C'est la partie qui a demandé le plus de vérifications. **Ne pas la refaire de
mémoire.**

| Source | Ce qu'on en fait | Statut | Reste à faire |
|---|---|---|---|
| **Modèle ASR NVIDIA** `stt_ar_fastconformer_hybrid_large_pcd_v1` | modèle affiné, embarqué | **CC BY 4.0 — vérifié** | rien, attribution en place |
| **Quran Foundation** (texte, audio, `segments`) | texte embarqué, audio téléchargé | **AUTORISATION ÉCRITE OBTENUE le 2026-08-10** | conditions ci-dessous |
| **Traduction fr Montada / Noor Intl.** (`resource_id: 136`) | embarquée dans le JSON | **couverte** par la licence générale de QuranEnc.com | 3 écarts à corriger, §4.2 |
| **Polices Amiri / Scheherazade** | via `google_fonts`, téléchargées à l'exécution | OFL, usage commercial permis | §5.3 |
| **ONNX Runtime, Flutter** | bibliothèques | MIT / BSD | rien |
| **hisnmuslim.com** | streaming uniquement depuis le 2026-08-10 | **aucune licence, aucun propriétaire identifiable** | §4.3 |
| **Tafsirs / explications** | **rien n'est livré** — fichiers absents de l'APK | sans objet aujourd'hui | §5.4 |
| **`adhan_makkah.mp3`** | embarqué | **provenance inconnue — NON VÉRIFIÉ** | à tracer avant production |

### 4.1 — L'accord Quran Foundation et ses conditions

Accordé par écrit : stockage hors ligne de l'audio **et** du texte, attribution
« Qur'anic text and recitations: Quran.com » validée telle quelle, **dons
autorisés sans licence commerciale séparée**.

**Trois conditions, dont une est du développement :**

1. **Contrôle des changements au moins tous les 7 jours** dès que le réseau est
   disponible, avec rattrapage au retour de connectivité, et application
   effective des mises à jour / suppressions / remplacements. L'app peut
   embarquer une copie de base mais doit pouvoir la mettre à jour.
   → **N'existe pas. À développer.**
2. **Migration** vers les Content APIs actuelles avec identifiants client.
3. Leur accord **ne couvre pas les tiers** : traductions et récitations gardent
   leurs propres licences.

**Sur la migration — réponse du 2026-08-10 :** ils **ne peuvent pas** délivrer
de client public sans secret, et ils recommandent un **proxy** côté serveur qui
détient le secret, met le jeton en cache et **relaie les appels** (plutôt que de
rendre des jetons à l'app).

Mécanique vérifiée sur leur documentation :
- jeton : `POST https://oauth2.quran.foundation/oauth2/token`, Basic
  `client_id:client_secret`, `grant_type=client_credentials&scope=content`,
  durée **3600 s** ;
- appels : `https://apis.quran.foundation/content/api/v4/...` avec les en-têtes
  `x-auth-token` et `x-client-id` ;
- prélive séparé : `apis-prelive.quran.foundation`, **ne jamais mélanger les
  jetons des deux environnements** ;
- **les chemins ne changent pas** : `api.quran.com/api/v4/chapters` devient
  `apis.quran.foundation/content/api/v4/chapters`. Côté `quran_api.dart`, c'est
  une base URL, deux en-têtes et un gestionnaire de jeton.

⚠️ **Ne pas embarquer le `client_secret` dans l'APK.** Un APK est une archive
zip ; la clé en serait extraite. Ce n'est pas un fichier de données, c'est une
**identité** : un tiers qui l'utilise consomme le quota et fait suspendre *votre*
client — et la suspension ferait tomber le contrôle à 7 jours, donc la
conformité, sans qu'on ait rien fait.

### 4.2 — La licence QuranEnc et les trois écarts

La traduction française embarquée est celle de **Montada Islamic Foundation /
Noor International**, couverte par l'autorisation générale de QuranEnc.com
(7 conditions). Trois ne sont pas respectées aujourd'hui :

1. **On supprime du contenu.** `_stripHtml`
   (`app/lib/widgets/verse_tile.dart:183` et `:219`) retire toutes les balises
   avant affichage, donc les appels de note `<sup foot_note=…>`. La condition 1
   interdit toute suppression, la 4 demande de conserver l'information du
   document. → décision requise : afficher les appels de note (leur texte n'est
   pas dans le JSON embarqué) ou au minimum ne pas les effacer.
2. **L'attribution est incomplète** : créditer **Montada / Noor International**
   comme éditeur **et QuranEnc.com** comme source, en plus de Quran.com.
3. **Le numéro de version de la traduction manque.**

**Gain à saisir** : la traduction vient aujourd'hui de l'API de quran.com, alors
que c'est la licence de **QuranEnc** qui l'autorise. La reprendre depuis
QuranEnc, avec son numéro de version, la met sous une licence claire **et** la
sort du périmètre Quran Foundation.

### 4.3 — hisnmuslim : ce qui reste

Le streaming subsiste (`Dua.audioUrl`). Aucune licence n'a été trouvée, ni sur
le site, ni sur le pack audio équivalent déposé sur Internet Archive par
Greentech, ni ailleurs. L'usage est **universel** dans les apps islamiques, et
personne ne publie d'autorisation — une app du Play Store écrit même en clair
« collected from all over the web, so if I have violated your copyright, please
let me know ».

Trois sorties, par solidité croissante :
1. streaming seul (état actuel) — on ne redistribue plus rien ;
2. demander à **IslamHouse**, dont le modèle est la diffusion gratuite ;
3. **produire ses propres enregistrements**. Piste en cours d'évaluation :
   ElevenLabs. Vérifier alors les droits d'usage commercial du plan souscrit,
   et savoir qu'une voix synthétique récitant des adhkâr ne fera pas
   l'unanimité — mieux vaut l'annoncer dans l'app.

---

## 5. Sécurité — audit du 2026-08-09

### 5.1 — Chargement du modèle depuis le stockage externe — **À CORRIGER**

`app/lib/services/fastconformer_verifier.dart:289-304` :

```dart
// A retirer pour le deploiement definitif.
final ext = await getExternalStorageDirectory();
if (ext != null && await File('${ext.path}/$_kModelSubdir/$_kModelFile').exists()) {
  appDir = ext;   // le modele EXTERNE gagne sur le modele interne
```

L'app charge **en priorité** un modèle depuis `/sdcard/Android/data/<pkg>/files`.
Deux conséquences : c'est l'endroit le plus simple pour **extraire** le modèle
(`adb pull`, sans root, y compris sur un build release), et surtout n'importe
qui peut y **déposer** un ONNX fabriqué que l'app préférera au sien — un modèle
substitué falsifie silencieusement tous les verdicts, c'est-à-dire la raison
d'être de l'app.

**Correctif recommandé** : conditionner ce chemin au drapeau debuggable, comme
l'entrée de recette (§3.6) — cela préserve le confort de test sans laisser la
porte ouverte en production. Ajouter ensuite une vérification d'empreinte
SHA-256 du modèle avant chargement.

### 5.2 — Journal de diagnostic sur stockage externe

`DiagnosticLog` écrit dans `getExternalStorageDirectory()` : hors du bac à sable
interne, récupérable par câble sans root. Sans conséquence depuis que le
diagnostic est éteint par défaut en release (§3.3), mais à déplacer vers
`getApplicationSupportDirectory()` — et à borner : il n'a aujourd'hui aucune
rotation ni plafond.

### 5.3 — Polices téléchargées à l'exécution

`google_fonts` récupère Amiri et Scheherazade New depuis les serveurs de Google
au premier lancement (375 usages dans le code). Deux conséquences : **au premier
démarrage sans réseau, une app de Coran affiche l'arabe en police système**, et
ce sont des requêtes réseau à déclarer dans Data safety. → embarquer les polices
dans `assets/fonts`.

### 5.4 — Ce qui est SAIN, à ne pas « corriger »

Vérifié : aucun secret ni keystore dans le dépôt, **zéro injection SQL**
(placeholders partout), pas de WebView, pas de trafic en clair, pas de
`badCertificateCallback`, texte coranique 100 % local, aucune remontée
automatique de la voix. R8 est désactivé **volontairement** (crash JNI d'ONNX
Runtime documenté le 2026-07-23) — ne pas le réactiver sans relire
`proguard-rules.pro`.

Les explications de versets (`ayah_explanations.jsonl` 128 Mo,
`word_explanations.jsonl` 177 Mo) ne sont **pas** dans l'APK et
`QuranSciencesService.ensureLoaded()` rend `false` quand elles manquent :
exposition nulle aujourd'hui. Le jour où on les embarque, ~14 éditions de tafsir
entrent dans le périmètre, dont plusieurs modernes et sous droits — le script
`benchmark/filtrer_explications.py` est prêt pour ne garder que celles dont les
droits sont éteints.

---

## 6. Procédure de publication

1. **Signature release** (§2.1). Sauvegarder le keystore hors machine.
2. **Décider de la livraison du modèle** (§2.2) — Play Asset Delivery recommandé.
3. **Corriger le chemin externe du modèle** (§5.1).
4. **Icône** (§2.4).
5. **Publier la politique de confidentialité** et remplir Data safety (§2.3).
6. **Test interne** (jusqu'à 100 testeurs, sans délai de validation) : vérifier
   que le build signé s'installe, démarre, et que le modèle arrive bien.
7. **Test fermé** : lance l'horloge imposée aux comptes développeur personnels
   (nombre de testeurs et durée — **vérifier la règle en vigueur**, elle a
   changé récemment). À démarrer au plus tôt, elle tourne en parallèle du reste.
8. **Production**, une fois §4.1 condition 1 (contrôle à 7 jours) livrée.

### Comptes (2026-08-10)

- **Compte Play Console** : `travail.kafai@gmail.com`.
- **Liste de testeurs — test fermé** : `kafai.allae@gmail.com` (à ajouter dans
  Console → Test → Testeurs, liste d'e-mails).

### Permissions à justifier dans la console

`RECORD_AUDIO` (vérification de la récitation), `ACCESS_FINE/COARSE_LOCATION`
(Qibla et horaires de prière), `POST_NOTIFICATIONS` (adhan),
`SCHEDULE_EXACT_ALARM` + `USE_EXACT_ALARM`.

⚠️ **`USE_EXACT_ALARM` est réservé par Play aux applications d'alarme et
d'agenda.** Une app de prière peut être refusée. Prévoir de le retirer et de
n'utiliser que `SCHEDULE_EXACT_ALARM` avec son formulaire de déclaration, ou de
basculer sur des alarmes inexactes pour l'adhan.

---

## 7. Décisions ouvertes

| # | Décision | Options | Recommandation |
|---|---|---|---|
| 1 | Livraison du modèle | PAD install-time / INT8 / téléchargement | **PAD install-time** |
| 2 | Rester chez Quran Foundation ? | proxy + contrôle 7 jours **ou** Tanzil + everyayah + aligneur maison | **trancher après la mesure de l'aligneur**, cf. §8 |
| 3 | Appels de note de la traduction | les afficher / ne plus les effacer | ne plus les effacer, au minimum |
| 4 | Audio des invocations | streaming / IslamHouse / enregistrements propres | évaluer ElevenLabs, puis décider |
| 5 | `USE_EXACT_ALARM` | garder et justifier / retirer | retirer si l'adhan tolère une alarme inexacte |
| 6 | Tuteur Gemma | embarquer le modèle / retirer les 3 entrées IHM | **retirer les entrées** tant qu'il n'est pas embarqué — aujourd'hui le bouton n'aboutit jamais |

---

## 8. La mesure qui décide de la question n°2

**Ne pas construire le proxy avant d'avoir ce chiffre.**

La seule chose que Quran Foundation fournit sans équivalent, ce sont les
`segments` — le minutage mot à mot qui permet de rejouer uniquement le mot raté.
Tout le reste est remplaçable : le texte par **Tanzil** (conditions explicites,
redistribution verbatim avec attribution, aucun compte, aucune obligation de
rafraîchissement), les URL audio par **everyayah** ou **quranicaudio** (URL
statiques, sans clé — mais **conditions non vérifiées**), la coloration tajwid
par la chaîne d'annotation déjà embarquée dans l'app.

**Le banc à écrire** : aligner par alignement forcé CTC les 3520 versets déjà
étiquetés dans `app/assets/data/word_timings_ms.json`, comparer début et fin de
chaque mot aux `segments` de quran.com, et sortir la distribution de l'erreur.

**Critère : erreur médiane < ~80 ms et 95ᵉ centile < ~200 ms** → suffisant pour
du rejeu, donc plus besoin des `segments`, donc **ni proxy, ni contrôle
hebdomadaire, ni identifiants**.

Pourquoi c'est plausible alors que le projet a déjà mesuré un échec (43,3 % de
WER, `ETAT_CTC_NEMO.md`) : **cette mesure portait sur le découpage de clips
d'ENTRAÎNEMENT**, où une erreur de quelques dizaines de millisecondes empoisonne
l'étiquette. Le rejeu tolère ±100 ms sans que personne ne l'entende. **La mesure
qui condamnait la piste ne se transporte pas.** Prévoir les garde-fous contre la
« pointe » du CTC : plancher de durée par mot, répartition du reste au prorata
du nombre de lettres, intervalles strictement croissants et non chevauchants.

Ce banc tourne sur le poste Ubuntu — **actuellement injoignable**, cf. §10.

---

## 9. Pièges déjà payés — ne pas les repayer

- **« Le modèle est chargé » ne prouve rien.** Un export ONNX en `raw_audio` se
  charge très bien et **chaque** transcription échoue en silence. L'app calcule
  le mel elle-même : l'entrée doit être `audio_signal`. Piège tombé deux fois.
  Vérification avant tout déploiement :
  `python3 -c "import onnxruntime as ort; print([i.name for i in ort.InferenceSession('<model.onnx>').get_inputs()])"`
- **Ne jamais faire `git add -A`.** L'arbre porte en permanence un gros état non
  commité préexistant (fichiers supprimés, dossiers de build). Committer fichier
  par fichier.
- **Un correctif placé dans `dispose()` ne couvre qu'un écran.** Cf. §3.2 : trois
  correctifs successifs ont durci le même écran pendant que deux autres
  restaient ouverts.
- **`ref.keepAlive()` sur un provider `autoDispose`** (`recitation_provider.dart:131`)
  fait que le `dispose()` du notifier **ne s'exécute jamais**. Il contient
  pourtant la bonne logique de libération. Ne pas compter dessus comme filet.
- **Un résultat négatif est une affirmation à vérifier.** Un `grep` qui ne
  trouve rien peut être un problème d'encodage, pas une absence.
- **Ne pas optimiser contre une mesure plus bruitée que le gain cherché.** Le
  même binaire sur la même sourate a donné de 0,0 % à 10,9 % de mots non verts
  selon les passes.

---

## 10. Infrastructure

**Poste Ubuntu (`kailbayern-atlas.nord`, 100.126.1.149) — injoignable.**
Diagnostic du 2026-08-10 : le ping répond (35 ms, TTL 64 = Linux), les
permissions Meshnet sont correctes (« Accès à distance : Autorisées »), mais
**tous les ports TCP renvoient `ConnectionRefused`** — un refus immédiat, pas un
blocage de pare-feu (qui laisserait tomber les paquets en silence). Les services
`xrdp` et `ssh` ne tournent pas.

La panne est survenue **pendant une session RDP, au lancement de Claude Code**.
À vérifier une fois devant la machine :

```bash
df -h /                                   # partition racine pleine ? (piege deja paye)
dmesg | grep -i "killed process"          # le tueur OOM a-t-il frappe ?
journalctl -u xrdp --since "3 days ago"
sudo systemctl enable --now ssh xrdp      # et pour que ca survive au redemarrage
```

Il n'existe **aucun** chemin d'accès distant tant que ces services sont arrêtés.

**Ce que ça bloque** : le banc d'alignement (§8) et le filtrage des JSON
d'explications. **Rien d'autre** — l'app, les builds et la recette à deux
téléphones passent par le poste Windows.

**Téléphones** : Samsung SM-S931B (`R3CY20XW7TD`) et Xiaomi 22101316UG
(`m7geugpr8x5tfec6`), branchés sur le poste Windows. Ils se déconnectent
régulièrement ; `adb kill-server && adb start-server` suffit à les récupérer.
