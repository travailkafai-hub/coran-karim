# Passation de contexte entre agents/machines (Windows ↔ Ubuntu)

## 2026-09-17 — la GRAPHIE DE LIAISON, cause de faux signalements jamais vue

Analyse mot par mot des 58 faux du banc d'erreurs reelles, sans hypothese de
depart. Une propriete separe nettement : un mot a **shadda initiale** est
faussement signale dans **28,6 %** des cas contre **7,0 %** ailleurs.

Cause : en arabe coranique la shadda sur la PREMIERE lettre note un idgham
avec le mot PRECEDENT (`مِن مَّا`). Elle n'appartient pas au mot ; le modele
transcrit `مَا` et il a raison phonetiquement. L'app comparait une graphie de
LIAISON a une transcription de PRONONCIATION -- et condamnait le recitateur
pour avoir applique correctement le tajwid.

Corrige dans `Orthographe` (famille 11, premiere lettre uniquement) et, pour
les finales assimilees, dans `Orthographe.variantesLiaison` appelee depuis
`Decideur` -- conditionnee au mot SUIVANT, car une finale absente sans regle
reste une faute.

Mesure : faux **8,1 % -> 7,3 %** (vote), **2,0 % -> 1,8 %** (historique),
detection **inchangee a 68 %**, et les 682 mots hors cible strictement
identiques. L'idgham en fin de mot, lui, n'a rendu qu'UN faux : il etait
correle aux faux sans en etre la cause -- lecon de methode notee dans le
document.

Detail : [FAUX_SIGNALEMENTS_GRAPHIE_DE_LIAISON_20260917.md](benchmark/FAUX_SIGNALEMENTS_GRAPHIE_DE_LIAISON_20260917.md).

**Tete 3 Hafs v2** (recue de PC A le 17/09, split par groupe, 99,29 % en test
isole) : mesuree **neutre** dans la chaine (54/80 et memes faux que le vote
seul), et **nuisible avec son seuil -1,782** (+19 faux, 0 detection). Le seuil
est donc lu mais DESACTIVE par defaut (`-DseuilTete3=true` pour mesurer) : un
seuil calibre sur des mots ISOLES ne transfere pas a une regle qui agrege 2-3
fenetres par mot.

## 2026-09-15 (soir) — le plafond est dans l'ALIGNEMENT

Objectif utilisateur : 80 % de detection, moins de 5 % de faux. Mesure apres la
correction de tokenisation de Codex, 10 cas rejoues hors device (103 mutations,
534 mots corrects) : **67 % / 9,2 %**.

Fait etabli : sur les **57 fautes ratees, AUCUNE n'etait alignee sur l'audio
modifie** (37 a moins de 25 % de recouvrement, 0 au-dessus de 75 %). Elles ne
sont pas inaudibles -- la chaine lisait l'audio du voisin, intact. Cause :
l'alignement force n'a pas d'option « absent », il doit placer tous les mots et
redistribue les frames. Le meme defaut produit 60 des 78 faux signalements
(19 cas ou le debut manquant se retrouve dans la lecture du voisin). C'est aussi
la cause du decrochage sur audio correct : **un defaut, trois symptomes**.

Six pistes testees, cinq mortes (marge de lettres, `couvert`, tous fragments,
gop, duree) -- chiffres dans le document, ne pas les refaire. Seule retenue et
implementee : une lecture ENTIERE ecarte les lectures en suffixe du meme mot
(vote 55 -> 48 faux, detection inchangee).

Verdict revise sur la tete 3, avec les bons jetons : elle est **neutre** (meme
detection que le vote seul, +2 faux), ni utile ni nuisible. Les chiffres
anterieurs qui la disaient nuisible sont caduques ; les documents concernes
portent un correctif en tete.

Diagnostic, pistes et commandes de reproduction :
[TACHE_CODEX_ALIGNEMENT_PLAFOND_20260915.md](benchmark/TACHE_CODEX_ALIGNEMENT_PLAFOND_20260915.md).
⚠️ La suite de tests complete n'a pas ete relancee apres le changement du
`Decideur`, et rien n'est commite.

## 2026-09-15 — correction Codex mesuree sur JVM (apres la campagne Claude)

Cause confirmee : le lookup/glouton de l'aligneur donnait a la tete 3 des
tokens differents du SentencePiece d'entrainement. Nouveau tokeniseur T3
Hafs/Warsh separe, parite 606 342/606 342 textes (normalisation et ids).
Autre correction : le vote ignore uniquement la kashida decorative U+0640.
Sur T805 en flux natif ONNX : faux rouges 10/200 -> 5/200, mutations signalees
11/20 -> 11/20. Gain de precision, pas de rappel prouve. T023/T005 conserves.
Le vote et la tete restent experimentaux : faux rouges restants et decrochage
T807 a 18,16 s. Aucun changement de seuil ou activation de marqueur.

Preuves, limites, prochaines investigations et commande de replay sans
telephone : [CORRECTION_TOKENISATION_TETE3_JVM_20260915.md](benchmark/CORRECTION_TOKENISATION_TETE3_JVM_20260915.md).
Les anciennes sorties sont conservees dans
`benchmark/replay_chaine_jvm_20260915_avant_kashida/`.

## Actualisation 2026-09-15 : vote entre fenetres, deux tetes 3, et trois mesures

Branche **`Astra`** (partie de `chantier-warsh`, commit `6bbf5b0`). Le vote
entre fenetres et les deux tetes 3 (Hafs + Warsh) sont branches dans la
decision, derriere des marqueurs de debug — **rien ne change pour l'APK de
production**.

Ce qui est ACQUIS et teste : une `Politique` par riwaya dans `JugementTete3`
(la riwaya choisit un fichier de poids, jamais une regle), controle croise des
empreintes, et parite Warsh fermee sur de la **vraie recitation**. 134 tests
`recitation2`.

Ce qui est MESURE sur Samsung (3 configurations, memes WAV, meme modele —
`benchmark/CAMPAGNE_PALIERS_20260915.md`) :
- **la tete 3 en decision n'apporte rien** (+1 detection, +3 faux ; aucun
  effet au palier ou la comparaison est stricte) → **eteinte par defaut**,
  marqueur propre `files/tete3_decision_actif` ;
- **le vote porte le gain ET le cout** : +18 pts de detection, mais une
  detection gagnee coute trois accusations fausses → **non activable en
  l'etat** ;
- **un temoin sans aucune erreur decroche** — fragment de mot au bord de
  fenetre pris pour du hors-texte, defaut **anterieur au vote** (18 des 30
  decrochages `horsTexte` de dense30 le 14/09). Cf. `PROBLEMATIQUES_ASR.md`.

Deux correctifs identifies et **non appliques**, ils touchent la chaine de
decision et doivent etre arbitres : le fragment de bord ci-dessus, et le
decalage d'index de la fiche « Reessayer ce mot » (elle fait redire un mot qui
n'est pas celui signale ; **le jugement n'est pas touche**, verifie sur
2 282 verdicts, 0 discordance).

## Actualisation ChGPT, 2026-09-13 : ouverture sans icone centree

Nouvelle demande utilisateur : retirer l'icone avant la couverture. Checkpoint
`b74d24b`. Splash transparent sur Android 12+, couverture native plein cadre
sur les anciens Android, sas Flutter immediat sans providers avant la fin
des services. Modele et ASR non modifies. Un bref fond vert systeme reste
possible sur Android 12+. Pas de recette telephone, a la demande utilisateur.
Details : [DEMARRAGE_MUSHAF_CHGPT_2026-09-13.md](DEMARRAGE_MUSHAF_CHGPT_2026-09-13.md).

## Actualisation ChGPT, 2026-09-13 : performance Mushaf

Priorite utilisateur : performance, chantier IHM suspendu. Point de retour
`30fc708`, sur le correctif preexistant `8c4e596` preserve. Mesures TextPainter
reparties entre frames, cache exact, anticipation des pages voisines, Future
de donnees stable et decodeur papier Warsh en isolate/coalesce. Recherches
de taille et interligne inchangees. Aucun changement ASR. Aucun test lance
sur demande utilisateur ; gains non mesures. Details et limites :
[PERFORMANCE_MUSHAF_CHGPT_2026-09-13.md](PERFORMANCE_MUSHAF_CHGPT_2026-09-13.md).

## Actualisation ChGPT, 2026-09-13 : cadre de lecture

Cadre ornemental partage entre papier et lecture defilante, palettes clair,
sepia et sombre. Dessin uniquement, marges de texte et pagination conservees.
Sauvegarde avant modification : `9406f92`. Aucun test ni manipulation du
telephone pour recette, sur demande utilisateur ; build et installation DEV
uniquement. Details : [CADRE_LECTURE_CHGPT_2026-09-13.md](CADRE_LECTURE_CHGPT_2026-09-13.md).

## Actualisation ChGPT, 2026-09-13 : agencement accueil

Suite couverture : image vert/or approuvee remplace l'ancien WebP (213 ko),
sans titre Flutter superpose. Sauvegarde `a860160`. Puis demande de cadre
plein ecran : `BoxFit.fill`, sans bandes ajoutees, avec etirement au ratio
du telephone ; sauvegarde avant ce changement `501f099`.
L'utilisateur demande de ne plus tester : installation uniquement, recette
visuelle par lui-meme. Aucun lancement ni capture telephone apres installation.

Refonte ciblee de l'accueil : titre arabe contraint, horaires regroupes,
miniature Qibla connectee au capteur et ouverture de la boussole existante.
Compte a rebours corrige (arguments minutes/heures inverses dans l'ancien
appel). Sauvegarde avant modifications : `2aabf9d`. 24 tests passent,
analyse ciblee propre. DEV installee, nouvel accueil capture sur telephone ;
ouverture Qibla observee, retour et rotation physique restent a verifier. Aucun changement
ASR ni pagination Hafs/Warsh. Details et limites dans
[ACCUEIL_CHGPT_2026-09-13.md](ACCUEIL_CHGPT_2026-09-13.md).

## Actualisation ChGPT, 2026-09-09 : retour du Mushaf papier

v396 corrige le debordement de l'en-tete de lecture classique au retour du
papier : `SafeArea(bottom: false)` et restauration du mode systeme demande
par l'appelant (immersif depuis la lecture, edgeToEdge par defaut ailleurs).
Hauteur de l'en-tete inchangee, aucune modification ASR ou pagination.
Sauvegarde ciblee avant correction : `38ee875`. 32 tests passent ; build debug
et installation DEV reussis. Analyse ciblee sans erreur, neuf signalements
preexistants. Verification visuelle du retour sur v396 encore en attente de
disponibilite du telephone ; ne pas confondre la capture avant correction
avec une validation apres correction. Details et graphe :
[CORRECTION_MUSHAF_CHGPT_2026-09-09.md](CORRECTION_MUSHAF_CHGPT_2026-09-09.md).

## Actualisation ChGPT, 2026-09-09 : Mushaf papier

Correction du debordement et des dernieres lignes coupees dans la vue papier.
Mesure et rendu partagent les memes spans et comptent basmala, bandeaux et
reserves avant de choisir la taille. Pagination Hafs/Warsh preservee ; aucune
modification ASR. 29 tests passent, build v395 installe sur le SM-S931B,
pages 573 et 574 verifiees par captures. Point de retour : `cabc45e`.
Details, graphe de rendu et limites :
[CORRECTION_MUSHAF_CHGPT_2026-09-09.md](CORRECTION_MUSHAF_CHGPT_2026-09-09.md).

## Actualisation ChGPT, 2026-09-07

Correction du suivi de priere, sur la reference commitee `6eb88b7` : capture
continue pour identifier la sourate, confirmation distincte du jugement,
souffleur sans recul/reset et conservation de la riwaya. Detail et limites :
[CORRECTION_SUIVI_PRIERE_CHGPT_2026-09-07.md](CORRECTION_SUIVI_PRIERE_CHGPT_2026-09-07.md).
143 tests cibles passent ; aucune recette sur telephone, aucun gain x2 mesure.
Les sections historiques ci-dessous ne decrivent pas toutes le code courant.

But de ce fichier : contrairement à `HANDOFF_UBUNTU.md`/`HANDOFF_UBUNTU_TRAINING.md`
(instantanés ponctuels d'une migration training passée, maintenant datés/obsolètes),
celui-ci se veut le point d'entrée COURANT à relire à chaque changement de machine
pendant le développement de l'app -- à tenir à jour au fil des sessions plutôt que
de le figer une fois pour toutes. Mets à jour la section 1 (chantier en cours) et
la section 3 (état git) avant de basculer de machine.

---

## 0. Session 2026-07-19 (agent Fable) — rescoring/décodage contraint + déploiement

**Ce qui a été fait, dans l'ordre :**

1. **Prototypé le décodage contraint au texte attendu** (piste 🟢 prioritaire,
   cf. `ETAT_CTC_NEMO.md` §5a-bis) : `benchmark/constrained_decoding_eval.py`
   (nouveau script) — génère à l'aveugle les variantes confusables d'un mot
   attendu (harakat + confusions de lettres apprises du corpus TTS) et laisse
   le modèle élire celle qui explique le mieux l'audio (NLL CTC), testé sur
   `mixed-e14-snapshot.nemo`. Résultat : 82,1%/45,0% (letter/harakat)
   d'identification correcte du mot fautif, mais 77,9% des versets *corrects*
   auraient ≥1 faux positif au seuil le plus permissif — pas un GO immédiat,
   détail complet dans `ETAT_CTC_NEMO.md`.
2. **Branché ce mécanisme + le rescoring NLL déjà validé le 16/07** dans le
   code app, **désactivé par défaut, diagnostic uniquement** (ne touche pas
   au verdict rouge/vert) : nouveaux `ConfusableVariants.kt`,
   `ForcedAligner.ctcForwardNll`/`WordResult.rescoreMargin`,
   `FastConformerCtcPlugin.setRescoringEnabled`, côté Dart
   `AlignedWord.rescoreMargin`/`FastConformerVerifier.setRescoringEnabled`,
   log `[GOP] ... rescore=...` dans `recitation_provider.dart`. Activable via
   `setRescoringEnabled(true)` une fois un seuil calibré sur device réel (pas
   fait cette session — les chiffres ci-dessus sont sur holdout TTS offline,
   pas représentatifs du bruit device).
3. **Vérifié que ça compile** : `flutter analyze` propre (Dart),
   `./gradlew :app:compileDebugKotlin` OK (`-x compileFlutterBuildDebug`,
   cf. point 4 ci-dessous).
4. **Débogué la chaîne de build/déploiement sur CETTE machine Ubuntu**
   (jamais fait depuis ce PC avant, donc plusieurs pièges de première fois,
   ajoutés en §4 pour la prochaine fois) :
   - Cache `.dart_tool/flutter_build/` contenait des chemins Windows figés
     (`C:\Users\Adam\AppData\Local\flutter_gemma\...`) d'une session
     antérieure → `flutter build apk` échouait sur
     `compileFlutterBuildDebug`/`Release`. Fix : supprimer
     `app/.dart_tool/flutter_build/` (safe, ignoré par git, régénéré au
     prochain build).
   - `flutter install` a d'abord réutilisé un **vieux** `app-release.apk` du
     12/07 sans rebuild (piège : ne pas supposer que `flutter install`
     rebuild toujours — vérifier la date du fichier `.apk` avant de faire
     confiance à l'install).
   - Le device (Samsung, `R3CY20XW7TD`) avait une version installée d'une
     **autre machine/keystore** → `adb install -r` a échoué
     (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, signatures différentes) →
     `adb uninstall` puis reinstall a été nécessaire → **a effacé toutes les
     données locales de l'app sur CE téléphone** (modèles poussés
     manuellement, empreinte vocale, progression FSRS...).
   - Le build `release` de ce projet signe avec la clé `debug`
     (`signingConfig = signingConfigs.getByName("debug")`,
     `build.gradle.kts:34`, commentaire "en attendant une vraie config") mais
     reste **non-debuggable** (`debuggable` par défaut du buildType release,
     indépendant de la clé de signature) → `adb shell run-as` échoue
     (`package not debuggable`) sur un `app-release.apk`. Pour tout
     déploiement manuel de modèle (§ suivante), **utiliser un build
     `--debug`**, pas `--release` — même clé debug sur cette machine donc
     `adb install -r` derrière un `app-release.apk` déjà installé (construit
     ici) fonctionne SANS perte de données, contrairement au premier
     changement de machine.
5. **Redéployé le modèle epoch14** (`fastconformer-ctc-mixed-e02`, effacé par
   l'uninstall du point 4) via la méthode déjà documentée en §4 ci-dessous
   (`adb push` → `/data/local/tmp/` → `adb shell run-as ... cp` → nettoyage
   tmp), source `benchmark/models_deployes/fastconformer-ctc-mixed-e02/`
   (448 Mo). **Première tentative dans le mauvais dossier** :
   `app_flutter/models/...` (supposition erronée que
   `getApplicationSupportDirectory()` pointe là) — confirmé faux par
   logcat : `[FastConformer] Modèle/vocab absents
   (/data/user/0/com.corankarim.coran_karim/files/models/...) — ignoré`, le
   verificateur entier (donc TOUTE la coloration karaoké) restait désactivé
   silencieusement, `start()` s'exécutait normalement (mots/permission OK)
   mais sans aucun jugement possible. **Bon dossier confirmé empiriquement** :
   `files/models/fastconformer-ctc-mixed-e02/` (PAS `app_flutter/...` malgré
   ce que suggérerait le nom `getApplicationSupportDirectory` — vérifier
   d'abord le chemin exact via `adb logcat | grep FastConformer` avant de
   pousser à l'aveugle la prochaine fois, plutôt que de déduire le chemin du
   nom de la fonction path_provider).

**Pas fait cette session, à vérifier avant la prochaine session sur ce
téléphone** : les AUTRES modèles (whisper-medium-ft, ceux du tuteur Gemma,
`fastconformer-ctc-pcd` pour l'empreinte vocale — cf. §2 de ce fichier et
`voice_fingerprint_service.dart`/`tutor_llm_service.dart`) ont probablement
aussi été effacés par l'uninstall du point 4 et n'ont PAS été repoussés — à
vérifier au premier lancement de l'app (soit ils se retéléchargent seuls via
l'UI de settings, soit ils manquent silencieusement).

**Rien de tout ça n'est commité** (cf. §3, inchangé sur ce point).

---

## 1. Chantier en cours : "Suivre une prière"

Fonctionnalité pour un imam qui mène la salât sans choisir de sourate au
préalable -- détecte Al-Fatiha puis identifie la sourate suivante à la volée
(Shazam interne). **Tout le détail technique (architecture, bugs trouvés,
correctifs, questions ouvertes) est dans [`SUIVI_PRIERE.md`](SUIVI_PRIERE.md)
-- le lire en entier avant de continuer ce chantier, ne pas le redécouvrir.**

Résumé ultra-court de l'état (voir SUIVI_PRIERE.md pour le détail) :
- Écran dédié `app/lib/screens/prayer_follow_screen.dart`, logique dans
  `app/lib/providers/recitation_provider.dart` (`PrayerPhase`,
  `startPrayerFollow`, `_maybeResyncPosition`...).
- Plusieurs bugs réels trouvés et corrigés via logs device (ambiguïté
  bismillah, détection ancrée en position 0, faux rattrapage par confiance
  trop faible, pointeur qui accumule du retard...).
- Dernier ajouts (2026-07-19, pas encore testés en conditions réelles) :
  repli de continuité entre rak'ah, défilement automatique, pas de
  correction affichée pendant Al-Fatiha (jugée trop fiable pour que les
  erreurs soient autre chose que du bruit ASR).
- **Prochaine étape** : retest live complet d'une salât entière avec tous
  les correctifs cumulés, puis lecture du journal par un autre modèle
  (Fable) pour avis/pistes supplémentaires (section 5 de SUIVI_PRIERE.md).

## 2. Modèle ASR déployé sur le téléphone

- Sous-dossier device : `models/fastconformer-ctc-mixed-e02` (nom
  historique -- **le modèle RÉELLEMENT déployé est le checkpoint epoch 14**
  du run "tajweed-mixed", pas l'epoch 2 que le nom du dossier suggère.
  Renommer le dossier casserait le code déployé pour rien ; c'était plus
  simple de garder le nom et remplacer le contenu). `val_wer_ctc≈0.1234`,
  entraîné avec repli anti-oubli Coran + Arabic Speech Corpus + TTS
  contre-exemples (sin/sad, harakat) -- voir mémoire projet
  "Décision Nemotron vs FastConformer" et "Métrique training CTC-only".
- Scripts d'export/déploiement de ce checkpoint : `benchmark/ckpt_to_nemo_epoch14.py`,
  `benchmark/build_word_token_lookup_mixed_e14.py`,
  `benchmark/validate_epoch14_local.py` (tous non commités, cf. §3).
- Un training a par ailleurs continué côté Ubuntu depuis (TTS + arabe pour
  la détection d'erreur sans forcer la correction) -- si tu es sous Ubuntu
  et qu'un run plus récent existe, vérifier avant de redéployer l'epoch14
  qu'il n'y a pas mieux disponible entretemps.

## 3. État git au 2026-07-19 (À METTRE À JOUR)

**Rien n'est commité cette session** -- volume important de changements en
attente :
- App (Flutter/Kotlin) : toute la feature "Suivre une prière" (§1), plus
  des fichiers modifiés d'une session antérieure (`ForcedAligner.kt`,
  `diagnostic_log.dart`, `mushaf_screen.dart`...) **plus, ajouté par la
  session rescoring/décodage contraint (§0)** : `ForcedAligner.kt`,
  `BufferedTranscriber.kt`, `FastConformerCtcPlugin.kt`,
  `fastconformer_verifier.dart` modifiés ; nouveau fichier
  `ConfusableVariants.kt` (untracked).
- `benchmark/` : beaucoup de scripts non commités (export/training/QA TTS)
  -- probablement d'une session Ubuntu antérieure, pas retouchés ici, **plus**
  le nouveau `constrained_decoding_eval.py` (§0, untracked).
- Docs modifiées par la session §0 : `ETAT_CTC_NEMO.md`,
  `GLOSSAIRE_TECHNIQUES_ASR.md`.
- Nouveaux fichiers non trackés notables : `SUIVI_PRIERE.md`,
  `HANDOFF_UBUNTU.md`, `HANDOFF_UBUNTU_TRAINING.md`, ce fichier (jamais
  commité malgré son ancienneté probable),
  `app/lib/screens/prayer_follow_screen.dart`,
  `app/lib/services/quran_verse_locator_service.dart`,
  `app/lib/widgets/quran_shazam_sheet.dart`, `app/lib/screens/voice_calibration_screen.dart`.

**Avant de committer quoi que ce soit** : vérifier avec l'utilisateur le
périmètre (l'app et le benchmark ont probablement des cycles de vie
différents) -- ne pas tout committer d'un bloc sans confirmation.

## 4. Environnement -- pièges pratiques

- **Windows** : `adb` n'est PAS sur le PATH par défaut dans ce shell.
  Utiliser le chemin complet :
  `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe` (PowerShell) ou
  l'équivalent en Bash. `flutter`/`dart` sont sur le PATH normalement
  (`D:\flutter\bin`).
- **Déploiement modèle sur device** : storage privé de l'app pas accessible
  en écriture directe -- passer par `adb push` vers `/data/local/tmp/` puis
  `adb shell run-as com.corankarim.coran_karim cp ...` vers
  `files/models/...`, puis nettoyer le fichier tmp.
- **`adb install -r`** (même signature) NE VIDE PAS le storage privé (donc
  garde le modèle déployé) -- un `adb uninstall` + reinstall, lui, efface
  tout. Toujours préférer `-r` sauf mismatch de signature entre builds de
  sessions différentes.
- **Python pour le training/export** : `benchmark/.venv/Scripts/python.exe`
  (venv Windows natif avec NeMo 2.7.3) -- PAS le `python` du PATH global (pas
  NeMo dedans), PAS `.venv_nemo` (format Linux, synced depuis Ubuntu,
  inutilisable sous Windows).
- **Chemin du projet contient un espace** ("Coran Karim") -- casse
  sentencepiece/certains outils training ; passer par un dossier temp sans
  espace si ça pose problème (cf. `HANDOFF_UBUNTU.md` §1.3).

## 5. Autres documents de référence dans ce repo

- `SUIVI_PRIERE.md` -- journal détaillé du chantier en cours (§1).
- `CODE_REVIEW_20260716.md`, `REVUE_ARCHITECTURE_KARAOKE.md` -- revues de
  code passées (karaoké classique), ponctuelles, pas à mettre à jour.
- `HANDOFF_UBUNTU.md`, `HANDOFF_UBUNTU_TRAINING.md` -- instantanés d'une
  migration de training passée (2026-07-12), datés/obsolètes sur l'état du
  training mais gardent des recettes/commandes encore valables (§2 de
  HANDOFF_UBUNTU.md pour reprendre un training NeMo).
- `FONCTIONNALITES_FUTURES.md` -- idées validées mais pas implémentées.
- `.claude/skills/model-training/references/asr.md` -- mémoire technique
  ASR détaillée (au-delà du périmètre de ce fichier).
- Mémoire auto-persistante de l'agent (hors repo, voir système) -- contexte
  utilisateur/projet qui survit entre conversations, complémentaire à ces
  fichiers (pas redondant : la mémoire est côté agent, ces fichiers sont
  côté repo, lisibles par n'importe quel agent/machine).

---

## 2026-07-25 — ÉTAT GIT : quelle branche, quel moteur, où sont les commits

### Les deux branches de test, et ce qui les distingue RÉELLEMENT

| | `test-1-gop` | `test-2-gop` |
|---|---|---|
| dernier commit | **`08556f8`** (2026-07-25) | `58db2fa` (2026-07-23) |
| message d'origine | « moteur ASR à l'état 5d97e09 (1 GOP + tête tajwid séparée) » | « moteur ASR à l'état c9c531f (2 têtes + segmentation recouvrement 2s) » |
| GOP lettres | oui | oui |
| **GOP tajwid** (`WordResult.tajwidGop`) | **non** — la tête 2 est seulement DÉCODÉE (`detectedRules` : règle réalisée ou pas), elle ne produit aucun score | **oui** — un `forced − free` par classe de règle sur les logprobs de la tête 2 |
| **Recouvrement de segment** | non | **oui** — au gel, on garde les dernières secondes d'audio comme contexte, en ne conservant que des **mots ENTIERS** (une durée fixe de 2 s coupait des mots en deux) et en reculant l'ancre en conséquence |
| écart sur la chaîne ASR | — | **666 lignes ajoutées, 71 retirées** sur 5 fichiers |

### « 1 GOP » et « modèle à 2 têtes » ne sont PAS contradictoires

Deux axes différents, d'où la confusion :

- **Le MODÈLE** déployé (`fastconformer-ctc-dual-head-multilabel-v3`) a bien
  **2 sorties** — vérifié : `out: [logprobs, ...]`, 2 sorties, contre 1 seule
  pour tous les modèles de `models_deployes/`.
- **L'ALGORITHME** de `test-1-gop` n'exploite qu'**une** tête pour NOTER : un
  seul `forced − free` sur les lettres. La tête tajwid est décodée pour dire
  « règle réalisée / non réalisée », sans score gradué.

Donc `test-1-gop` **utilise** le modèle à 2 têtes mais n'en score qu'une. C'est
cohérent, ce n'est pas un bug — mais ce n'est pas le moteur qu'on croyait
tester. Le 2e GOP vient de l'idée citée dans le code de `test-2-gop` :
« le tajwid juge le tajwid, donc on doit avoir deux GOP ».

### Ce qui s'est passé le 2026-07-25 (à ne pas reproduire)

- `test-1-gop` était déjà la branche active depuis le **2026-07-24**
  (`reflog` : `checkout: moving from asr-nemo-solutions to test-1-gop`). Aucun
  changement de branche n'a eu lieu ce jour-là.
- **Erreur de méthode** : dès le premier diagnostic j'ai constaté que le
  téléphone exécute un modèle à 2 têtes, sans jamais vérifier si la branche
  active correspondait au moteur visé. Une journée de mesures a été menée sur
  `test-1-gop`.
- **Conséquence coûteuse** : j'ai proposé comme une découverte le principe
  « conserver l'audio à la frontière de segment, aligné sur des mots entiers » —
  or `test-2-gop` l'implémente **depuis le 2026-07-23**, avec la même
  correction (garder des mots entiers plutôt qu'une durée fixe). J'ai même
  produit une mesure qui semblait le contredire (elle ajoutait du contexte des
  DEUX côtés en allongeant le segment, ce qui n'est pas ce que fait cette
  branche).
- La règle du projet le disait déjà : « aucun historique git ne compense un
  agent qui ne pense pas à `git log -p` avant d'agir ». **Vérifier
  `git branch -a` + `git log` des branches sœurs AVANT toute analyse.**

### Où retrouver le travail du 2026-07-25

`08556f8` sur **`test-1-gop`** — 24 fichiers, périmètre chaîne de récitation :
course de gel (`commitInFlight`), suppression de `secPerWord`, purge de l'audio
consommé, `entendu=""` interdit tout verdict, `src=dp|libre`, réglage
diagnostic, bouton pause rogné, `benchmark/compare_onnx_on_device_wavs.py`.
Mesures chiffrées : `JOURNAL_TESTS_LOGS.md`. Refonte proposée :
`ARCHITECTURE_RECITATION.md`.

**La plupart de ces correctifs sont indépendants du nombre de GOP** (buffer,
jugement, diagnostic, IHM) et devraient se transposer sur `test-2-gop` — sauf
`BufferedTranscriber.kt`, qui diffère de 374 lignes entre les deux branches : un
cherry-pick y entrera forcément en conflit et devra être fait à la main.

---

## 1. Session 2026-07-31/08-01 — piste 10 (contrastif) + tête tajwid + plan d'action

**Point d'entrée pour la suite, à relire avant de continuer cette nuit.**

### Ce qui est fait, vérifié, sur disque (rien de déployé)

- **Tête tajwid, stage a, 12 epochs** — `val_tajwid` 0,201 → **0,138**
  (meilleur que la lignée historique 0,170). Entraînée sur l'encodeur
  `causal-v4-phrases`. Fichiers :
  `HDD/.../fastconformer-dual-head-v1/stagea-tajwid-v4-long/`
  (`stagea-final.nemo`, `stagea-tajwid-head.pt`).
- **Encodeur contrastif (piste 10)** — détection sur audio réellement fauté,
  2 % de collatéral : **25 % → 53 %** ; biais canonique (médiane gopC sur mot
  fauté) **+0,109 → −0,105**, signe inversé. Entraîné sur le corpus de paires
  `tts_phrases_concat` (1 265 paires), encodeur COMPLET dégelé.
  `benchmark/models/fastconformer-contrastif-v1/contrastif-v1/contrastif-final.nemo`.
- **Fine-tune sur données vérifiées** (`fastconformer-verifie-v1`), base =
  contrastif, 6 epochs sur 131 723 lignes (50 343 clips longs contrôlés
  récitateur par récitateur + 81 380 fautes TTS déjà auditées à 93,9 %
  d'audibilité). `val_wer_ctc` = 0,180-0,182, stable par rapport au point de
  départ causal (0,182) — **mais c'est une métrique interne, pas une preuve**.
  `HDD/.../fastconformer-verifie-v1/causal-final.nemo`.
- **9 récitateurs exclus, documentés** (`benchmark/recitateurs_exclus.py`) —
  couple (audio, texte) du manifeste ne correspondant pas, mesuré par
  décodage réel + WER normé sur les clips LONGS ORIGINAUX (pas un défaut de
  découpage). Ne jamais les réintroduire sans nouvelle mesure.
- **Corpus de fragments courts 3-8 s — ÉCHOUÉ deux fois, ne pas retenter sans
  lire `ETAT_CTC_NEMO.md` §"Pistes de qualité" d'abord.** v1 (proportions
  externes) : WER 37,2 %. v2 (alignement Viterbi CTC brut) : WER 43,3 %, pire
  — spans CTC pointus (1 frame contre 31 pour des mots comparables), piège
  déjà documenté depuis le 2026-07-14 (`2ae8dc7`) et pas relu avant de coder
  la v2. Corpus supprimés, rien n'a été entraîné dessus pour de vrai.

### Point de blocage cette nuit

**Téléphones débranchés** — aucune recette device possible. Rien n'a été
poussé sur l'appareil ; le modèle déployé n'a pas bougé.

### Plan d'action, dans l'ordre

1. **Recette device sur `fastconformer-verifie-v1`**, dès que les téléphones
   sont rebranchés — seule mesure qui compte réellement. Exporter via
   `export_causal_checkpoint.py` (une seule tête, `audio_signal`/`length`
   contrôlés), pousser en gardant le modèle actuel en
   `model.onnx.avant_verifie`, puis `benchmark/recette_2tel.sh`. Contrôles
   dans l'ordre : aucun rouge sans preuve, ancre ~294-302, RESYNC 0, puis le
   taux de non-verts contre la référence 2,03-2,71 %.
   - **Si ça tient** : `verifie-v1` devient la référence, on continue dessus.
   - **Si ça casse** : retour immédiat au modèle précédent (une commande),
     et chercher lequel des deux runs (contrastif ou le fine-tune) est en
     cause — les deux ont leur propre checkpoint, testables séparément.
2. **⚠️ Dépendance à vérifier avant d'exporter la tête tajwid** : elle a été
   entraînée sur l'encodeur `v4-phrases`, qui n'est PLUS l'encodeur courant
   (contrastif puis verifie-v1 l'ont fait bouger deux fois depuis). La
   brancher telle quelle sur `verifie-v1` reproduirait exactement le défaut
   déjà nommé cette nuit (« la tête tajwid vit dans un autre run, incompatible
   depuis que l'encodeur a bougé »). Il faut soit re-entraîner le stage a sur
   `verifie-v1` (rapide, sans risque, encodeur gelé pendant ce stage), soit
   figer `v4-phrases` comme référence si `verifie-v1` ne passe pas la recette.
3. **Exporter les trois sorties ensemble** (`export_trois_tetes.py`, déjà
   écrit et vérifié) une fois l'encodeur de référence choisi et la tête
   tajwid réentraînée dessus.
4. **Réécrire `decodeTajwid`** (argmax → seuil par classe/top-k, cf.
   `Decideur.kt`/`FastConformerCtc.kt`) — code de jugement, à proposer et
   faire valider avant d'implémenter (règle du projet).
5. **Dernier maillon de la tête 3** : calculer les 12 caractéristiques
   conditionnées par la cible côté Kotlin et brancher au `Decideur`. Le
   `tete3.json` actuel est calé sur `v4-phrases` — à recalibrer sur
   l'encodeur de référence retenu à l'étape 1.
6. **Calibrage pause/jauge** (spécifié dans
   `CALIBRAGE_DEBIT_ET_PAUSES.md`) : remettre `pauseMinSecondes` à 0,40
   (mesuré meilleur que 0,35), ajouter `intervalleHabituel` au calibrage,
   implémenter la jauge de débit — non bloquant, peut se faire en parallèle.
7. **Corpus courtes-durées, si repris un jour** : ne pas utiliser les spans
   Viterbi CTC comme bornes directes. Piste correcte non tentée : repères de
   position (le pic) + modèle de durée, pas la largeur du span brut. Écrire
   le protocole de vérification (petit échantillon, décodage réel, WER normé)
   AVANT tout script de génération à l'échelle.
