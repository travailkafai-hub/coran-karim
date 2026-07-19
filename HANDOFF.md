# Passation de contexte entre agents/machines (Windows ↔ Ubuntu)

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
