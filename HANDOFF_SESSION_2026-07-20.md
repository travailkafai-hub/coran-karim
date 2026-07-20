# Passation — session 2026-07-20 (agent Opus 4.8)

Fichier destiné à l'agent suivant. Il retrace CE QUI A ÉTÉ FAIT, **les pièges
réellement tombés** (dont un déjà documenté et reproduit quand même), et ce qui
reste ouvert. Complète `HANDOFF.md` (point d'entrée courant) — ne le remplace pas.

Commits de la session, du plus ancien au plus récent :

| Commit | Portée |
|---|---|
| `0d3dea7` | Entraînement stage1b sur 260h Coran + 2 bugs de chemins corrigés |
| `508dede` | Export stage1b-260h (⚠️ MAUVAISE convention, corrigé plus tard par `ae2362c`) |
| `08efcc9` | Déploiement du modèle dans le cœur ASR + câblage des modes de jugement |
| `b060070` | Fix overflow barre de navigation |
| `ae2362c` | **Fix export ONNX : `audio_signal` (mel) au lieu de `raw_audio`** |
| `59dbae9` | Tiroir de lecture scrollable + filigrane mushaf |
| `07579bc` | **Refonte du volet Coach** (hub mémorisation) |

---

## 1. Entraînement : stage1b-260h est le meilleur modèle à ce jour

Relancé le stage1b depuis `stage1b/stage1b-final.nemo` sur **260h de Coran**
(au lieu de 150h), même mix ASC×10/TTS×5 (337,5h au total), 8 epochs,
`ctc_loss_weight=0.7`, convergé à `val_wer_ctc=0.147`.

**Sortie** : `benchmark/models/fastconformer-quran-hybrid-v1/stage1b-260h/stage1b-final.nemo`
(rien d'écrasé, les runs précédents sont intacts).

**Comparaison officielle** (`eval_error_detection_rules_stripped.py`, n=150,
même protocole que la comparaison mixed-e14 précédente) :

| Métrique (n=150) | mixed-e14 (déployé) | Hybride 150h | **Hybride 260h** |
|---|---|---|---|
| Détection d'erreur (fidèle) | 65,3% | 65,3% | 64,7% (bruit) |
| Corrigé à tort vers canonique | 14,7% | 10,7% | **10,7%** |
| CER canonique (anti-oubli) | 9,18% | 9,69% | **6,85%** |

Le point faible du run 150h (CER canonique dégradé) est **résolu** : les 110h
supplémentaires préservent l'acquis canonique sans perdre le gain anti-biais.
Détail complet : `PLAN_ENTRAINEMENT_HYBRIDE.md` §5ter.

**Deux bugs de chemins corrigés au passage** (ils rendaient la mesure impossible) :
1. `build_rules_manifests.py` ne reconnaissait pas le montage HDD actuel →
   **0 clip Coran annoté** avec les symboles de règles (0/156892). Corrigé,
   revérifié : 59232/59232, 0 mismatch.
2. `build_mixed_manifest.py` ne remappait jamais les chemins de
   `val_canonical.jsonl` → chemins morts `/mnt/hdd/...`, invisible jusqu'à un
   vrai `FileNotFoundError` en éval. Corrigé. Au passage, les chemins pointent
   désormais vers la **copie SSD locale** (`data/train_wav_local/`) plutôt que
   le HDD : lectures aléatoires bien plus rapides (~4 it/s → ~15 it/s).

---

## 2. ⚠️ PIÈGE MAJEUR — export ONNX : `audio_signal`, jamais `raw_audio`

**À lire avant tout export destiné à l'app.** Ce piège était **déjà documenté**
en en-tête de `export_tajweed_checkpoint.py` (correction du 2026-07-13) et je
l'ai **reproduit quand même** le 2026-07-19. Une règle a été ajoutée dans
`CLAUDE.md` pour qu'il ne tombe pas une troisième fois.

**Le symptôme** : sur device, le modèle se charge (`Modèle chargé : true` —
rassurant et trompeur) mais **aucune transcription, aucun suivi, aucune
coloration**. L'utilisateur le vit comme « le modèle ne marche pas ».

**La cause**, visible uniquement dans le log natif :
```
[BufferedTranscriber] echec retranscription:
Unknown input name audio_signal, expected one of [raw_audio, length]
```
Le plugin Kotlin calcule le mel-spectrogramme LUI-MÊME (`MelSpectrogram.kt`) et
appelle le modèle avec `audio_signal` de forme `(batch, 80, time)`. Un export
« E2E » (`raw_audio` → preprocessor+encoder+ctc) valide pourtant très bien
PyTorch==ONNX — il est simplement **inutilisable par l'app**.

**Règles à respecter :**
- Partir de `export_rules_260h_checkpoint.py` ou `export_tajweed_checkpoint.py`
  (wrapper encodeur+ctc_decoder seul). **Jamais** d'un `*_full_pipeline.py`.
- Vérification **obligatoire** avant tout déploiement (doit afficher `audio_signal`) :
  ```
  python3 -c "import onnxruntime as ort; print([i.name for i in ort.InferenceSession('<model.onnx>').get_inputs()])"
  ```
- **Corollaire de diagnostic** : « le modèle est chargé » ne prouve RIEN sur son
  utilisabilité. Toujours vérifier une **vraie transcription** (log natif
  `DiagnosticLog` / logcat), pas seulement la ligne de chargement.

`export_rules_260h_full_pipeline.py` est conservé mais marqué « NE PAS
UTILISER » (règle projet : ne pas effacer la trace d'une tentative).

**État du déploiement** : modèle corrigé exporté, validé (PyTorch==ONNX,
symboles de règles bien émis) et **poussé sur le téléphone**
(`files/models/fastconformer-ctc-rules-260h/`, 458 Mo).
⚠️ **Le test live n'a PAS été fait** (récitation réelle → coloration/suivi) :
téléphone verrouillé en fin de session. C'est la première chose à valider.

---

## 3. Refonte du volet Coach (`07579bc`) — spec : `REFONTE_IHM.md` §11

**Demande** : « tout ce qui est en lien avec la mémorisation il faut le mettre
dans coach [...] **il ne faut pas faire juste une copie-coller** ».

**Avant** : l'onglet Coach n'était qu'un journal d'erreurs à plat
(`coach_ai_screen.dart`) ; le vrai coach de mémorisation (`coach_screen.dart`,
3 étapes, 1863 l.) n'était atteignable que depuis la lecture.

**Après** : `coach_hub_screen.dart`, hub en 4 zones qui **orchestre** les écrans
existants (aucun n'est réécrit) :
- **A. Reprendre** — dernier verset travaillé, relancé en un tap
- **B. Mémoriser** — ayah par ayah → `CoachScreen`
- **C. Réciter** — récitation continue + **tous** les réglages, modifiables ici
- **D. Mes erreurs** — regroupées **par sourate**

**Fichiers créés** :
- `screens/coach_hub_screen.dart`
- `screens/surah_picker_screen.dart` — sélecteur **réutilisé** par les zones B et
  C (évite la duplication de liste que la demande interdisait)
- `providers/error_review_provider.dart` — agrégat erreurs par sourate
  (regroupement **client-side** de `errorCountsByAyah()`, volumes faibles, zéro
  risque sur le schéma sqlite)
- `providers/last_coach_verse_provider.dart` — mémoire du dernier verset
  (écrite par `CoachScreen.initState`)

**Fichiers supprimés** (l'historique git les conserve) :
- `memorization_screen.dart` — **maquette morte** : `// Demo feedback state`,
  `_WordResult` factices, aucun ASR réel. Examinée avant de trancher, rien à
  récupérer, supplantée par `coach_screen.dart`.
- `coach_ai_screen.dart` — remplacé par le hub.

**Volet erreurs (zone D), conception** : deux niveaux repliables. Niveau sourate
= total + versets touchés + **barre de ratio** (parce que 5/7 et 5/286 ne
veulent pas dire la même chose), trié par erreurs décroissantes. Au dépliage,
les versets fautifs avec 3 actions : **Revoir** (mémorisation ciblée),
**Explication** (Gemma), **Situer dans la carte mentale**.
Le lien carte mentale est **masqué si le contenu n'existe pas** pour la sourate
(12 rédigées à ce jour) — jamais de bouton mort.

**Déplacements / retraits** :
- gros micro **retiré** de la barre du bas de la lecture (la récitation vit dans
  Coach) ; reste un bouton discret « Mémoriser »
- icône carte mentale **retirée** de la page principale (`surah_list_screen`)
- section « Récitation » **entièrement retirée** de Réglages global (Réciteur,
  Correction auto, Rigueur, Suivre sans bloquer, Répétitions) → vit dans Coach
  zone C. **Déplacée, pas dupliquée.**

### Décisions utilisateur VERROUILLÉES (ne pas rouvrir sans lui) — §11.6
1. Raccourci « travailler ce verset » depuis la lecture : **GARDÉ**
   (l'écran de mémorisation reste unique et vit dans Coach ; la lecture n'y
   renvoie que par un raccourci — ce n'est pas une duplication de code).
2. `memorization_screen.dart` : **SUPPRIMÉ** (maquette factice).
3. Réglages de récitation : **DÉPLACÉS**, pas dupliqués. Réglages global ne
   garde que le transverse (prière, voix, affichage, langue).

---

## 3bis. Corrections de fin de session (après premiers retours utilisateur)

Deux passes de correction ont suivi la livraison de la refonte Coach. Elles
comptent autant que la refonte elle-même : elles fixent **le critère de
rangement des réglages** et **la doctrine du garde-fou tajwid**.

### a) Rangement des réglages — critère « à quoi sert ce réglage ? »

Commit à venir/`07579bc` corrigé ensuite. L'utilisateur a repris trois points :

1. **Récitateur → Réglages généraux** (« le récitateur c'est dans réglages
   générale »). C'est un choix **transverse** (écoute d'une sourate, souffleur,
   corrections audio), pas propre à la récitation. Le mettre dans Coach le
   rendait introuvable pour ses autres usages.
2. **Paramètres de VÉRIFICATION → sur l'écran de récitation, derrière une
   icône** (« tous les paramètres de vérification seront sur la page de
   récitation moyennant une icône »). Mode de vérification, sensibilité,
   rigueur, correction auto, suivre sans bloquer. Ils ne servent QUE là, et
   souvent **en cours** de récitation. Implémentation :
   `karaoke_recitation_screen.dart::_openVerificationSheet`, icône
   `tune_rounded` de la barre du haut (élargit la feuille « sensibilité » qui
   existait déjà là depuis le 2026-07-12).
3. **« Réciter une sourate » = le MOTEUR de l'app** (« il n'est pas mis en
   valeur »). Était une ligne de liste parmi des réglages → devient une
   **grande carte d'action** (dégradé, bordure laiton, micro en pastille).

→ **Règle à retenir** : ranger un réglage selon **à quoi il sert**, pas selon
l'écran où on se trouve. Cf. `REFONTE_IHM.md` §11.4bis.

### b) ⚠️ Règles tajwid : le garde-fou passe d'un BLOCAGE à un PLAFOND (`8f8c00a`)

**Revirement d'une décision antérieure verrouillée** (§1 disait « règles non
fiables jamais activables, grisées »). Déclencheur : « pourquoi il y a des
toggles désactivés, exemple **madd 6** et autres, même pour enfants ? ».

Vérification faite, le blocage était **mal fondé** :
1. La mesure évaluait la **mauvaise chose** — « quand la règle est BIEN faite,
   le modèle émet-il le symbole ? » — alors que pour enseigner il faut savoir
   « quand l'utilisateur **RATE** la règle, le modèle le voit-il ? ». Jamais
   mesuré. Une règle a été grisée sur un **proxy**.
2. Échantillons minuscules : `madda_necessary` **n=32** → 72%, IC95%
   **[55%–84%]** ; `idgham_mutaqaribayn` **n=3** → « 100% », IC **[44%–100%]**
   (aucune information).
3. Cause probable = **rareté** (143 occurrences de `madda_necessary` dans tout
   le Coran), pas difficulté acoustique — un madd est une **durée**.

**Ce qui remplace le blocage** : toutes les règles activables + **badge de
fiabilité** + une règle active peu fiable **plafonne le verdict à « incertain »**
(orange) au lieu du vert (`RecitationNotifier._capByRuleReliability`).

**Principe conservé, à ne pas casser** : un **vert franc sur une faute réelle**
est le pire comportement possible (biais canonique — l'utilisateur croit avoir
juste). L'orange dit honnêtement « je ne peux pas trancher », ce qui est mieux
que l'absence de retour ET que la fausse validation.

Détail complet + tableau des IC : `REFONTE_IHM.md` §12.

## 4. Autres corrections de la session

- **Overflow barre de navigation** (`b060070`) : « RIGHT OVERFLOWED BY 5.5
  PIXELS ». Régression du passage des libellés arabes courts aux libellés
  traduits plus larges, avec un padding horizontal **fixe** de 24px × 4 onglets.
  Fix : chaque onglet dans un `Expanded` + `maxLines:1`/ellipsis.
  → **Ne plus jamais mettre de padding horizontal fixe dans cette Row.**
- **Overflow tiroir de lecture** (`59dbae9`) : « BOTTOM OVERFLOWED BY 284
  PIXELS » après l'ajout des sections vitesse audio + répétition. Fix :
  `isScrollControlled` + `SingleChildScrollView`, plafonné à 85% de l'écran.
- **Médaillon de sourate** : V1 (cadre `CustomPainter` complet) jugée
  « catastrophique » par l'utilisateur → V2 avec l'asset SVG
  `assets/illumination/medallion.svg`, un seul élément ornemental. Vérifiée
  visuellement sur device.

---

## 5. ⚠️ Environnement — le piège qui casse le build sans toucher au code

**Le SDK Android vit sur le disque dur externe** :
`~/android-sdk-hdd` → `/run/media/kafai/HDD/android-sdk`.

Si le HDD est démonté, Gradle retombe sur `/usr/lib/android-sdk` (qui ne
contient que `platform-tools`, aucune licence, aucun NDK) et le build échoue sur
`LicenceNotAcceptedException: ndk;29.0.13113456`. **Ça n'a rien à voir avec le
code Dart** (`flutter analyze` reste propre).

Remontage :
```
udisksctl mount -b /dev/sda2          # label HDD, 7,3 To
# puis vérifier app/android/local.properties :
sdk.dir=/run/media/kafai/HDD/android-sdk
```
(`local.properties` est gitignoré, donc non versionné — à revérifier après
chaque remontage.)

**Piège d'interprétation à connaître** : quand le build Gradle échoue, un
`adb install` qui suit affiche quand même **`Success`** — il réinstalle l'APK
**précédent** encore sur disque. Toujours lire la ligne
`✓ Built build/app/outputs/flutter-apk/app-debug.apk`, jamais se fier au
`Success` de l'install.

---

## 6. Ce qui reste ouvert

**Priorité 1 — validation live du modèle** (bloquée sur téléphone déverrouillé) :
récitation réelle → vérifier suivi + coloration, et lire les lignes `[GOP]` du
log. Si le suivi marche mais que les couleurs sont mal placées, **recalibrer les
seuils GOP** (`_kGopCorrectDefault`/`_kGopUnclearDefault` dans
`recitation_provider.dart`) : le nouveau modèle peut avoir une plage de gop
différente de l'ancien. Cette mesure n'a jamais pu être faite.

**Refonte Coach — affinages non faits** (délibérément, pour ne pas élargir) :
- zone B « Mémoriser » lance la **sourate entière** : pas encore de sélection
  d'une plage de versets ;
- le lien carte mentale ouvre la sourate sans se **positionner sur le verset
  précis** de l'erreur.

**Mesure de fiabilité des règles — la vraie, jamais faite** : `rule_reliability.json`
contient aujourd'hui des **proxys** (détection d'une règle bien réalisée, sur
n=3 à 50 selon les classes). La mesure qui compte est la **détection de fautes
délibérées** sur un set humain — à constituer. Tant qu'elle n'existe pas, les
seuils qui pilotent le plafonnement au vert restent provisoires.

**Madd — piste reportée, pas abandonnée** : le madd est structurellement mal
servi par le symbole ASR (le alif suscrit ٰ est remplacé par un alif normal
dans les labels d'entraînement ET dans la normalisation de l'app → la durée
n'existe nulle part dans le texte comparé). Seule voie sérieuse : **mesurer la
durée** (option A de `FONCTIONNALITES_FUTURES.md` §1 — exploiter les timings
déjà produits par le CTC, sans ré-entraînement). Reporté explicitement par
l'utilisateur le 2026-07-20 (« plus tard, on note et on avance »).

**Chantiers IHM plus anciens, toujours ouverts** :
- extraction ARB **écran par écran** (seule la barre de nav est traduite ; les
  titres de Réglages/Coach sont encore en arabe codé en dur) ;
- palette de couleurs définitive de la carte mentale (les 6 couleurs de
  catégorie sont des **PLACEHOLDERS**, cf. commentaire dans `app_theme.dart` —
  l'utilisateur doit fournir sa palette) ;
- contenu carte mentale : 12 sourates rédigées sur 114.

**Piste ML ouverte** : brancher la tête **RNNT** sur « Suivre une prière »
(localisation). Le plan (`PLAN_ENTRAINEMENT_HYBRIDE.md`) exige une **mesure
offline AVANT tout code app** — elle n'a pas été faite. Le locator actuel
travaille uniquement sur la sortie CTC.

---

## 7. Règles projet à ne pas contourner

Rappel des règles de `CLAUDE.md` qui ont compté cette session :
- **Aucune piste éliminée tant que le retour en arrière est possible** : jamais
  écraser un checkpoint, chaque run dans un nouveau dossier.
- **Committer l'état courant AVANT un changement important** (fait ici :
  `59dbae9` juste avant la refonte Coach).
- **Ne jamais supprimer un commentaire qui documente une tentative ou un piège**
  — ajouter une note à côté, pas effacer. (C'est précisément l'oubli de LIRE un
  tel commentaire qui a coûté le piège §2.)
- **Métrique CTC** : lire `val_wer_ctc` uniquement, `val_wer` = bruit.
- Vérifier le **périmètre** avec l'utilisateur avant de committer (app et
  benchmark ont des cycles de vie différents).
