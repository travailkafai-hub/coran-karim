# Audit du projet Coran Karim : securite, fiabilite et optimisations ASR

Auteur : **ChGPT (ChatGPT / Codex)**, pour identification lors de la reprise par Claude.
Date : **6 septembre 2026**.
Reference auditee : **ac785d4a883b809473560d097ffc94f2e9d0b230**, application `1.0.5+6`.
Nature du travail : revue de code, controles de configuration, verification des dependances et tests locaux. **Aucun correctif applicatif applique pendant cet audit.**

Complement demande le 6 septembre et finalise le **7 septembre 2026** : **optimisations sans sacrifier la rapidite ni la qualite ASR**, detaillees en section 10. Cette extension est une analyse du code et un protocole de validation, pas un benchmark de gains deja obtenus.

## 1. Conclusion et priorites

Le traitement ASR local, le texte embarque et les protections deja presentes dans la version release reduisent l'exposition. Cependant, plusieurs garanties de confidentialite et d'isolation Hafs/Warsh ne sont pas tenues par tous les chemins du code.

Les premiers points a traiter sont : le diagnostic qui n'obeit pas partout a son interrupteur, la purge incomplete des extraits vocaux, les serveurs de developpement exposes lorsqu'ils sont lances, et les caches de texte capables de melanger Hafs et Warsh. Les derniers changements de paliers comportent aussi une divergence mesuree entre le fichier precalcule et le calcul effectif de l'application.

**Aucune compromission ni faille critique exploitee n'a ete demontree.** Ce rapport identifie des defauts et des risques dans le perimetre examine ; ce n'est ni un certificat de securite ni un audit exhaustif de chaque ligne, modele et dependance native.

### Echelle utilisee

- **P1 / elevee** : traiter en priorite, avant une nouvelle publication concernee ou une exposition reseau du composant.
- **P2 / moyenne** : corriger dans une prochaine iteration dediee ; impact reel mais conditions d'exposition plus limitees.
- **P3 / faible** : durcissement ou probleme limite a l'outillage et a des entrees de confiance.
- **Reproduit** : comportement observe par execution locale controlee.
- **Confirme par le code** : chemin identifie statiquement ; pas de demonstration sur un telephone release.
- **Conditionnel** : risque dependant notamment du lancement d'un outil, d'un fichier non fiable ou d'une migration Android.

La priorite du projet n'est pas un score CVSS : une bibliotheque notee HIGH par une base publique peut avoir ici une exposition faible lorsqu'elle est reservee aux tests.

### Registre des constats

| ID | Priorite | Sujet | Etat de la preuve |
|---|---|---|---|
| SEC-01 | P1 | L'interrupteur de diagnostic ne controle pas tous les journaux | Confirme par le code |
| SEC-02 | P2 | La purge peut laisser des extraits vocaux expires | Confirme par le code |
| SEC-03 | P2 | Captures et journaux de diagnostic sans budget de conservation | Confirme par le code |
| SEC-04 | P2 | Transfert Android entre appareils insuffisamment encadre | Configuration confirmee, effet conditionnel |
| SEC-05 | P2 | Politique de confidentialite en decalage avec le produit | Confirme par le code et le document |
| SEC-06 | P1 | Serveurs ASR de developpement sans authentification ni limites | Conditionnel a leur lancement/exposition |
| SEC-07 | P2 | Verification de l'identite SSH affaiblie | Confirme dans les scripts |
| SEC-08 | P2 | Corpus d'entrainement telecharge en HTTP sans preuve d'integrite | Confirme dans le script |
| SEC-09 | P3 | Chargement de checkpoints avec deserialisation non restreinte | Conditionnel a la provenance des fichiers |
| SEC-10 | P2 | Telechargements audio insuffisamment bornes | Confirme par le code |
| SEC-11 | P2 | Repli de signature release sur une cle de debug | Conditionnel a l'absence de configuration |
| SEC-12 | P3 | Deux avis de securite sur JSON-java, uniquement pour les tests JVM | Versions verifiees avec OSV |
| QUAL-01 | P1 | Course du cache QuranApi et contamination Hafs/Warsh | Reproduit, deux scenarios |
| QUAL-02 | P2 | Les paliers ne sont pas isoles par riwaya | Confirme par le code |
| QUAL-03 | P2 | 265 versets retrouvent des coupures omises par le precalcul | Reproduit sur les assets courants |
| QUAL-04 | P2 | Cache d'URL de correction non distingue par recitateur | Confirme par le code |
| QUAL-05 | P2 | Suite de tests en echec et protections de non-regression incompletes | Execute et confirme |

## 2. Perimetre et methode

L'inventaire Git compte 128 fichiers Dart sous `app/lib`, 37 fichiers Kotlin de production, 272 scripts Python sous `benchmark`, 18 fichiers de tests Flutter et 14 fichiers Kotlin sous `src/test`. Ce comptage ne signifie pas une lecture integrale de chacun : la lecture detaillee cible les entrees, donnees sensibles, sorties reseau, persistances, configurations et changements recents.

Perimetre examine :

- Application Flutter : demarrage, reglages, chargement des textes, lecture et telechargement audio, archives, diagnostic, empreintes et exports vocaux.
- Android : manifeste source, activite exposee, canaux Dart/Kotlin, chargement des modeles, configurations de signature et dependances.
- Outillage : serveurs ASR Python, transport SSH, acquisition de corpus et chargement de checkpoints.
- Documentation : architecture, passation et politique de confidentialite.
- Changements recents : commits `ac785d4`, `5032fec`, `f260fb5`, `4e2272f`, `5b5dc30`, `a9f267c`, `228783b` ; attention particuliere aux paliers, decoupes audio et separation Hafs/Warsh.

Les fichiers deja non suivis au debut ont ete laisses en place. Aucun modele, fichier de voix utilisateur, reglage de telephone ou service distant n'a ete modifie. Aucun serveur de test n'a ete lance et aucun APK n'a ete installe. Les requetes OSV ont porte sur des noms et versions de dependances publiques, pas sur le code du projet.

Le manifeste release fusionne present localement date du **4 septembre 2026**. Il indique `minSdk=24`, `targetSdk=36`, `allowBackup=false`, sans `dataExtractionRules` ni attribut `debuggable`. Il constitue un indice sur un build precedent, pas une attestation du binaire actuellement distribue.

### Donnees et frontieres de confiance

| Donnee / flux | Emplacement ou destination observe | Protection / limite |
|---|---|---|
| Audio micro et inference ASR | Appareil, moteur Kotlin/ONNX | Pas d'upload automatique de la voix trouve dans les services applicatifs examines |
| Extraits de sessions et de portions | Documents prives, `archive_sessions`, SQLite | Retention annoncee de 7 jours ; defaut SEC-02 |
| Captures de diagnostic | Documents prives, `recitation_captures/session_*` | Activation explicite en release pour ce chemin ; conservation sans borne |
| Journal Dart/Kotlin | Stockage externe propre a l'app, `recitation_diagnostic.log`, et logcat | Contient des informations de session ; voir SEC-01 et SEC-03 |
| Empreinte vocale | Documents prives, `voice_fingerprints/*.bin` | Stockage local ; presence du service ne prouve pas une activation chez tous les utilisateurs |
| Audio des recitateurs | Quran.com, EveryAyah, MP3Quran et caches locaux | HTTPS dans les URL applicatives trouvees ; limites SEC-10 |
| Polices | Amiri embarquee ; autres familles Google Fonts a la demande | Reseau supplementaire non decrit completement dans la politique |
| Texte lu par synthese vocale | Moteur TTS configure sur Android | Le service ne selectionne pas explicitement une voix garantie hors ligne |
| Exports vocaux | ZIP en cache puis partage natif | Geste de partage explicite ; une copie peut sortir du telephone |
| Audio des bancs Python | PC lorsque les serveurs de test sont lances | Perimetre developpement distinct de l'application livree |

## 3. Constats de securite et de confidentialite

### SEC-01 : des journaux restent possibles avec le diagnostic desactive

**Priorite P1.** Sources : [DiagnosticLog.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/DiagnosticLog.kt), l. 29 et 32 ; [diagnostic_log.dart](app/lib/services/diagnostic_log.dart), l. 104 et 148 ; [settings_screen.dart](app/lib/screens/settings_screen.dart), l. 180 ; [quran_verse_locator_service.dart](app/lib/services/quran_verse_locator_service.dart), l. 314.

Le journal natif initialise `enabled = true`. Au lancement, Dart relit la preference et transmet un chemin avec `setLogFile`, mais ne transmet pas en meme temps l'etat d'activation. Le commutateur actuellement affiche dans les reglages ecrit la preference et le champ statique Dart ; il ne pousse pas l'etat vers le natif. L'ancien widget `_DiagnosticTile` le faisait, mais ce n'est pas le commutateur utilise ici.

En parallele, la recherche de sourate appelle directement `debugPrint` avec le texte entendu et les mots normalises, sans verifier `DiagnosticLog.enabled`. Le nom `debugPrint` ne constitue pas une protection de compilation release : le SDK Flutter local le confirme dans `packages/flutter/lib/src/foundation/print.dart:37`.

**Consequence :** la position "desactive" ne garantit pas l'absence de traces. Le natif est resynchronise au demarrage d'une session par `_applyDiagnosticCapture`, mais cela ne couvre pas toutes les etapes avant cette synchronisation, ni les impressions directes. Le risque porte sur les textes reconnus et les metadonnees ; ce constat ne prouve pas un upload ou un enregistrement micro permanent.

**Correction recommandee :** une seule commande appliquee aux preferences, au journal Dart, au journal natif et au cycle des captures ; initialisation du natif dans un etat ferme avant `setLogFile` ; aucune transcription brute dans un `debugPrint` de production. Respecter le choix de diagnostic en cours de session et au redemarrage.

**Verification attendue :** release neuve, diagnostic coupe, identification puis recitation, changement de reglage et relancement. Examiner a la fois le fichier, logcat et les nouvelles captures. Ne pas utiliser uniquement les messages de l'interface comme preuve.

L'acces a logcat n'est pas ouvert a toutes les applications ordinaires sur Android moderne ; restent notamment ADB autorise et certains composants privilegies. Cette restriction limite le risque sans justifier d'y ecrire les transcriptions. [Reference Android sur les journaux sensibles](https://developer.android.com/privacy-and-security/risks/log-info-disclosure).

### SEC-02 : la purge de la voix depend a tort des anciennes sessions

**Priorite P2.** Source : [session_archive_service.dart](app/lib/services/session_archive_service.dart), l. 47, 552, 1066, 1073 et 1099.

`purgerAnciennes()` retourne immediatement lorsque la requete sur les anciennes `sessions` est vide. `_purgerAudioPortions()` se trouve apres ce retour. Des `portion_words` dont `audio_expires_at` est depasse ne sont donc pas purges lorsqu'il n'y a aucune ancienne session a supprimer.

**Scenario concret :** conserver des portions, supprimer l'historique des sessions correspondant, puis revenir apres l'expiration des extraits. La purge est appelee, mais le retour anticipe empeche le traitement des portions. Autre limite : elle n'est appelee qu'au demarrage d'une nouvelle session ; une app inactive ne purge pas a l'echeance exacte.

Les suppressions de fichiers avalent aussi les erreurs avant de supprimer les references SQL. Un echec disque peut laisser un WAV orphelin ; aucun balayage de reconciliation n'apparait dans cette methode, contrairement a ce qu'annonce son commentaire.

**Correction recommandee :** purger sessions et portions independamment ; definir une politique explicite pour l'inactivite ; conserver la trace d'une suppression echouee ou reconciler les fichiers orphelins. Ne pas supprimer les captures de developpement par assimilation aux archives utilisateur.

**Verification attendue :** base sans ancienne session mais avec portion expiree, echec de suppression simule, reprise apres plus de 7 jours. Verifier fichiers physiques et references SQLite.

### SEC-03 : diagnostic durable sans quota ni nettoyage accessible complet

**Priorite P2.** Sources : [voice_lora_clip_service.dart](app/lib/services/voice_lora_clip_service.dart), l. 45, 64, 85 et 93 ; [diagnostic_log.dart](app/lib/services/diagnostic_log.dart), l. 128 et methode `log` ; [settings_screen.dart](app/lib/screens/settings_screen.dart), l. 227.

Les captures de diagnostic s'accumulent dans des repertoires durables. Le fichier de diagnostic est ecrit en ajout. Il n'y a pas de quota global ni de rotation du fichier. Une borne existe pour la trace en memoire, mais elle ne borne pas l'historique sur disque.

`deleteAllRecitationCaptures()` existe, mais la recherche dans `app/lib` ne trouve pas d'appel. Les anciens controles d'export sont conserves dans le code et retires du parcours visible. Effacer les donnees Android reste possible, au prix de toutes les autres donnees de l'app. Les ZIP d'export ne sont pas explicitement nettoyes apres leur utilisation.

**Impact :** accumulation de voix et de traces au-dela du besoin, saturation possible du disque et effacement selectif difficile. Le journal externe propre a l'app beneficie des restrictions d'Android moderne ; les anciennes versions prises en charge et les moyens d'acces privilegies meritent toutefois un controle distinct. Les WAV prives ne sont pas a confondre avec un dossier public librement lisible.

**Correction recommandee :** afficher le volume et la duree de conservation ; proposer un effacement explicite par categorie ; borner ou interrompre la collecte lorsque le budget est atteint. Pour les diagnostics que le developpeur veut conserver, preferer avertissement et export a une suppression silencieuse. Stocker les traces sensibles en interne et les exporter sur demande. [Reference Android sur le choix du stockage](https://developer.android.com/training/data-storage).

### SEC-04 : allowBackup=false ne couvre pas uniformement les migrations Android

**Priorite P2, effet conditionnel.** Source : [AndroidManifest.xml](app/android/app/src/main/AndroidManifest.xml), l. 73.

Le manifeste desactive correctement Auto Backup, mais ne declare pas `android:dataExtractionRules`. Android documente que, sur certains appareils Android 12 et suivants, `allowBackup=false` bloque la sauvegarde cloud sans bloquer le transfert appareil a appareil.

**Impact :** les archives et autres donnees sensibles peuvent participer a une migration systeme alors que le commentaire du manifeste presente cette solution comme couvrant tous les canaux. Cela ne prouve pas une sauvegarde cloud actuellement active, ni une fuite deja survenue.

**Correction recommandee :** definir et verifier les exclusions `cloud-backup` et `device-transfer` pour les donnees concernees, avec les regles compatibles pour les anciens Android ; documenter les consequences sur la restauration de la progression.

**Verification attendue :** inspection du manifeste final et test de migration sur un appareil constructeur pris en charge. [Documentation Android Auto Backup](https://developer.android.com/identity/data/autobackup?hl=en).

### SEC-05 : la politique de confidentialite doit suivre le comportement actuel

**Priorite P2.** Sources : [politique-confidentialite.html](docs/politique-confidentialite.html), l. 29, 38, 46 et 75 ; [karaoke_recitation_screen.dart](app/lib/screens/karaoke_recitation_screen.dart), l. 1518 et 3128 ; [session_archive_service.dart](app/lib/services/session_archive_service.dart), l. 620 ; [explanation_tts_service.dart](app/lib/services/explanation_tts_service.dart), l. 51 ; [pubspec.yaml](app/pubspec.yaml), section des polices.

Le texte du 11 aout presente le reseau comme reserve a deux fournisseurs audio et les extraits vocaux comme une fonction de diagnostic desactivee par defaut. Or le code actuel comporte EveryAyah, MP3Quran, des requetes de minutage, des polices telechargeables et un archivage fonctionnel des mots non verts, distinct du diagnostic. Les API de partage peuvent transmettre volontairement des fichiers hors de l'appareil.

Le TTS utilise le moteur Android avec `setLanguage`, sans selection explicite d'une voix locale. L'affirmation "toujours hors ligne" pour ce composant n'est donc pas garantie par ce service ; aucun envoi TTS effectif n'a ete mesure pendant l'audit.

**Correction recommandee :** inventorier fournisseurs, finalites, metadonnees des requetes, archives fonctionnelles, durees, suppression et partage explicite ; distinguer traitement local, absence d'upload automatique de la voix et dependances reseau. Conserver des formulations verifiables. Il s'agit ici d'un constat technique, pas d'une conclusion juridique de conformite.

### SEC-06 : serveurs ASR Python exposes sans controle d'acces

**Priorite P1 lorsqu'ils sont exposes.** Sources : [server_test.py](benchmark/server_test.py), l. 50, 124 et 155 ; [whisper_server.py](benchmark/whisper_server.py), l. 54 et 100.

Les deux serveurs ecoutent par defaut sur `0.0.0.0`. Les routes de transcription n'ont pas d'authentification. Les requetes audio sont lues en memoire sans borne applicative explicite ; l'inference et le decodage consomment ensuite des ressources importantes. `server_test.py` utilise un serveur multithread et conserve de l'audio sous `data/mic_test`.

**Scenario :** lancement sur un reseau accessible par d'autres postes, pare-feu autorisant le port. Un tiers peut soumettre de nombreuses requetes ou de gros fichiers, saturer CPU/GPU/RAM/disque ; le transport HTTP n'assure pas la confidentialite de la voix entre telephone et PC.

**Limite :** ce sont des outils de benchmark, pas un serveur decouvert dans l'application Android. Aucun listener sur les ports 8000 ou 8765 n'a ete trouve lors du controle local. Aucun acces public a Internet n'est demontre.

**Correction recommandee :** boucle locale par defaut ; ouverture LAN explicite avec restriction du pare-feu ; authentification, taille maximale, duree maximale decodee, nombre d'inferences concurrentes borne et delais. Utiliser un transport chiffre lorsque la voix traverse le reseau.

### SEC-07 : SSH accepte une identite de serveur insuffisamment verifiee

**Priorite P2.** Sources : [adb_pcb.sh](benchmark/adb_pcb.sh), l. 22 ; [installer_pcb.sh](benchmark/installer_pcb.sh), l. 15 ; [recette_2tel.sh](benchmark/recette_2tel.sh), l. 101.

Les scripts imposent `StrictHostKeyChecking=no`. Cela affaiblit notamment la verification du premier serveur rencontre. Une connexion reussie ne prouve alors pas que la bonne machine de test a ete contactee.

**Impact conditionnel :** interception ou substitution des fichiers et commandes de recette en presence d'un attaquant reseau et d'une identite d'hote non fiable. Cela ne signifie pas que SSH transmet en clair.

**Correction recommandee :** enregistrer la cle d'hote par un canal fiable, utiliser un `known_hosts` dedie et exiger sa verification. Faire echouer la recette sur un changement d'identite inattendu.

### SEC-08 : acquisition d'un corpus par HTTP non authentifie

**Priorite P2, outillage.** Source : [download_arabic_speech_corpus.py](benchmark/download_arabic_speech_corpus.py), l. 33 et 113.

`CORPUS_URL` utilise HTTP. Le telechargement est repris puis extrait sans comparaison avec une empreinte authentifiee du fournisseur.

**Impact :** une interception peut substituer le corpus ou livrer une archive disproportionnee. Pour ce projet, l'integrite des donnees d'entrainement conditionne aussi l'integrite des futurs jugements ASR. Aucun empoisonnement effectif n'a ete constate.

**Correction recommandee :** source HTTPS et empreinte obtenue independamment, limites de taille compressee/decompressee et manifestes de provenance avant integration dans un entrainement. La presence de `ZipFile.extractall` ne suffit pas, seule, a conclure a une faille de traversee de chemins : elle n'est pas declaree ici.

### SEC-09 : certains checkpoints sont deserialises sans restriction

**Priorite P3 dans l'usage local actuel, potentiellement elevee avec une entree hostile.** Sources : [make_causal_init.py](benchmark/make_causal_init.py), l. 51 ; [ckpt_to_nemo_epoch14.py](benchmark/ckpt_to_nemo_epoch14.py), l. 39.

Ces scripts appellent `torch.load(..., weights_only=False)`. Un checkpoint provenant d'un tiers ne doit pas etre traite comme un simple tableau de poids : la deserialisation peut executer des objets Python.

**Limite :** les chemins examines visent des artefacts locaux ; aucun chargement malveillant n'est demontre. Ce point ne concerne pas le chargement ONNX dans l'APK.

**Correction recommandee :** conserver la provenance et les empreintes ; preferer un chargement restreint ou un format de poids sans objets executables lorsque compatible ; isoler la conversion d'un checkpoint non fiable des comptes, cles SSH et secrets du poste. [Documentation PyTorch de torch.load](https://docs.pytorch.org/docs/stable/generated/torch.load.html).

### SEC-10 : telechargements audio pouvant epuiser les ressources

**Priorite P2.** Sources : [mp3quran_api.dart](app/lib/services/mp3quran_api.dart), l. 219 ; [reciter_download_service.dart](app/lib/services/reciter_download_service.dart), l. 175 et 370 ; [word_correction_audio.dart](app/lib/services/word_correction_audio.dart), l. 51 et 787.

Des sourates entieres sont recues avec `ResponseType.bytes`, donc accumulees en memoire avant ecriture. Aucun plafond d'octets recus n'est impose par ces services. Les quatre workers de telechargement de versets bornent une requete de sourate, pas le nombre global de sourates simultanees. Le client Dio des corrections est cree sans delais explicites.

**Impact :** manque de memoire sur de gros audios ordinaires, blocage en cas de serveur lent et saturation possible si une reponse est anormalement volumineuse. Les URL observees sont des fournisseurs fixes en HTTPS : ce n'est pas une demonstration de telechargement arbitraire impose par n'importe quel utilisateur distant.

La comparaison a `Content-Length` detecte certaines troncatures, pas un fichier different de meme longueur ni l'authenticite du contenu. Le chemin de telechargement verset par verset ne realise pas cette comparaison. Plusieurs caches reutilisent tout fichier non vide.

**Correction recommandee :** flux vers un `.part` avec compteur limite, budget global de concurrence et de disque, annulation et delais coherents, validation de decodage avant promotion, invalidation d'un cache corrompu. Une verification cryptographique n'est utile que si l'empreinte attendue est elle-meme digne de confiance.

**Verification attendue :** gros audio, reponse sans longueur annoncee, flux infini simule, deconnexion, annulation, disque presque plein et MP3 invalide ; utiliser un serveur local de test controle.

### SEC-11 : un build release peut etre signe avec la cle de debug

**Priorite P2, conditionnelle.** Source : [build.gradle.kts](app/android/app/build.gradle.kts), l. 92, bloc `release`.

En l'absence de `android/key.properties`, le build ne s'arrete pas : il utilise `signingConfigs.getByName("debug")` et emet un avertissement. Le nom "release" de l'artefact ne prouve donc pas une signature de publication.

**Impact :** artefact non publiable sur Play, confusion de distribution et de compatibilite de mise a jour. **Signature debug et flag debuggable sont deux choses differentes** : ce repli ne suffit pas a activer les portes de recette protegees par `FLAG_DEBUGGABLE`.

Le fichier `key.properties` existe sur cette machine et est ignore par Git ; ses valeurs n'ont pas ete affichees. Aucun APK distribue n'a ete trouve signe en debug par cet audit.

**Correction recommandee :** echouer explicitement pour toute commande de publication sans configuration de signature valide, garder le confort de developpement dans une variante dediee, verifier le certificat et les drapeaux du binaire effectivement livre.

### SEC-12 : JSON-java vulnerable dans les tests JVM

**Priorite P3 pour l'exposition du projet.** Source : [build.gradle.kts](app/android/app/build.gradle.kts), declaration `testImplementation("org.json:json:20180813")`.

La verification OSV confirme deux avis concernant cette version :

| Avis | Probleme | Premiere version corrigee indiquee pour org.json:json |
|---|---|---|
| [CVE-2022-45688 / GHSA-3vqj-43w4-2q58](https://osv.dev/vulnerability/GHSA-3vqj-43w4-2q58) | Epuisement de pile lors du traitement d'entrees fabriquees | `20230227` |
| [CVE-2023-5072 / GHSA-4jq9-2xhw-jpx7](https://osv.dev/vulnerability/GHSA-4jq9-2xhw-jpx7) | Deni de service dans JSON-java | `20231013` |

**Distinction essentielle :** cette coordonnee est une dependance de tests et n'apparait pas dans `releaseRuntimeClasspath`, verifie par Gradle. Les classes `org.json` du framework Android ne sont pas automatiquement la meme version que cet artefact Maven. Ces deux avis ne sont donc pas declares comme deux failles embarquees dans l'APK.

**Correction recommandee :** mettre a jour la dependance de test vers une version corrigee compatible et verifier les bancs JVM ; ne pas accepter de gros JSON non fiables dans ces bancs.

## 4. Fiabilite, integrite des textes et derniers changements

### QUAL-01 : QuranApi peut crasher ou conserver Hafs sous une selection Warsh

**Priorite P1, reproduit.** Source : [quran_api.dart](app/lib/services/quran_api.dart), l. 62, 106 et 156.

Premier defaut : `_ensureLoaded()` considere `_chapters != null` comme preuve de chargement complet. Pourtant `_chapters` est affecte avant l'attente de lecture des versets. Un second appel pendant cette attente retourne trop tot, puis `fetchVerses()` dereference `_versesBySurah!` encore nul.

Second defaut : changer `riwaya` remet `_loading` et les caches a null, mais n'invalide pas le travail asynchrone deja lance. Un ancien chargement peut terminer apres le nouveau et remplacer ses resultats.

**Reproduction controlee :** canal d'assets Flutter intercepte avec deux jeux de donnees factices. Aucun texte coranique n'a ete modifie. Resultats observes :

```text
AUDIT concurrent fetch: Null check operator used on a null value
AUDIT active=warsh, cached=HAFS_FIXTURE
```

Le deuxieme resultat a ete obtenu dans cet ordre : lecture Hafs suspendue, selection Warsh, lecture Warsh terminee et verifiee, liberation de l'ancienne lecture Hafs, nouvelle demande de versets.

**Impact :** panne de chargement et incoherence possible entre la riwaya selectionnee et le texte fourni aux ecrans ou a un consommateur ASR. Le test demontre l'incoherence du service, pas la frequence du probleme sur le telephone ni un verdict acoustique errone deja produit.

**Correction recommandee :** caches et futures distincts par riwaya, ou generations de chargement verifiees avant publication ; publier atomiquement un ensemble complet de donnees ; ne pas prendre la presence des chapitres pour la fin du chargement des versets. Conserver le type de recitation explicitement dans la session.

**Verification attendue :** appels simultanes au premier lancement, bascules Hafs/Warsh dans les deux sens pendant la lecture des assets, asset indisponible puis nouvelle tentative. Les nouveaux tests de non-regression devront attendre le comportement correct, contrairement aux sondes d'audit qui constataient le defaut.

### QUAL-02 : les nouveaux paliers ne respectent pas une isolation par riwaya

**Priorite P2.** Sources : [coupes_texte_service.dart](app/lib/services/coupes_texte_service.dart), l. 259 et 326 ; [coach_incremental_repeat.dart](app/lib/screens/coach_incremental_repeat.dart), l. 272 ; [build_coupes_paliers.py](benchmark/build_coupes_paliers.py), l. 20 et 224.

`coupes(surah, ayah, motsAttendus)` ne recoit pas de `Riwaya`. Le generateur utilise le Hafs et une union des marques Hafs/Warsh ; le repli dans Dart effectue aussi cette union. `refendreLongs` travaille sur `_hafs`. La liste precalculee est filtree selon le nombre de mots demande, sans correspondance explicite des mots entre variantes.

**Consequence :** le calcul utilise en Hafs depend maintenant de donnees Warsh ; inversement, des indices issus du Hafs peuvent servir en Warsh. Verifier une longueur ou borner un indice ne prouve pas une equivalence de position et de sens.

Cela ne prouve pas que toutes les coupures sont mauvaises. L'union est meme explicite dans les commits recents. Mais elle ne respecte pas la contrainte anterieure d'isolation des corrections Warsh et doit etre assumee comme un changement fonctionnel commun, avec validation dans les deux lectures.

**Correction recommandee :** rendre le type obligatoire, produire des assets par riwaya ou une correspondance de mots verifiee, separer les regles propres aux lectures. Geler un jeu de resultats Hafs avant toute correction Warsh. Ce sujet concerne les paliers du coach ; il ne demontre pas une modification des poids du modele.

### QUAL-03 : les versets sans coupe precalculee reprennent l'ancien algorithme

**Priorite P2, reproduit sur les donnees du depot.** Sources : [build_coupes_paliers.py](benchmark/build_coupes_paliers.py), l. 231 ; [coupes_texte_service.dart](app/lib/services/coupes_texte_service.dart), l. 266 ; asset [coupes_paliers.json](app/assets/data/coupes_paliers.json).

Le generateur n'ecrit une cle que si sa liste de coupes n'est pas vide. L'absence d'une cle signifie donc notamment "analyse effectuee, aucune coupe retenue". Dans Dart, cette absence signifie au contraire "pas de precalcul, utiliser l'ancien calcul". Ce repli peut retablir des coupes que l'analyse globale n'a pas retenues.

Une sonde Flutter a charge les assets reels et appele le service pour tous les versets absents de l'asset : **265 versets rendent une liste non vide**. Exemples d'indices 0-based rendus :

```text
1:7=[6]
2:39=[1, 6]
2:77=[6]
2:82=[1, 6]
2:107=[7, 13]
```

L'asset courant contient 4 497 cles. La mesure demontre une divergence d'algorithme ; elle ne declare pas religieusement incorrectes ces 265 coupures.

**Correction recommandee :** distinguer absence de calcul et resultat vide, par exemple avec des entrees `[]` explicites ou une couverture/version de corpus ; empecher le repli de contredire une decision precalculee. Ne pas corriger ce probleme en modifiant les seuils de jugement ASR.

Un second point a surveiller : `ensureLoaded()` retourne immediatement si `_chargement` est deja vrai. Un appelant qui fait `await ensureLoaded()` peut donc continuer sans que le premier chargement soit termine. Une future partagee doit representer la disponibilite reelle de toutes les donnees utilisees.

### QUAL-04 : les URL audio de correction ignorent le recitateur dans la cle

**Priorite P2.** Source : [word_correction_audio.dart](app/lib/services/word_correction_audio.dart), l. 31, 217 et 769.

`_urlCache` est indexe uniquement par numero de sourate. Les minutages et fichiers, eux, utilisent `reciter.id` dans leur cle. Apres une correction avec le recitateur A, choisir B sur la meme sourate peut donc reutiliser l'URL de A avec les minutages de B, dans le chemin qui utilise les segments Quran.com.

**Impact :** mauvais recitateur et extraction d'un mauvais passage lors de la correction. La recherche n'a pas trouve de remise a zero de ce cache lors de `setReciter`. Le defaut n'est pas generalise aux branches EveryAyah/MP3Quran qui construisent leurs URL autrement.

**Correction recommandee :** utiliser une cle incluant au minimum `(reciterId, surahNumber)` et la variante quand elle n'est pas deja determinee par l'identifiant ; gerer aussi les prechargements encore en cours lors d'une bascule.

**Verification attendue :** charger un mot avec A, choisir B, rejouer le meme verset avec reseau simule et verifier que l'URL, les segments et le fichier appartiennent tous a B.

### QUAL-05 : les tests actuels ne constituent pas une barriere de publication verte

**Priorite P2.** Sources : [tests Flutter](app/test), [tests Kotlin](app/android/app/src/test), [pubspec.yaml](app/pubspec.yaml).

`flutter analyze --no-pub` echoue avec **138 points**, dont une erreur `undefined_method` dans `test/recitation_basmala_test.dart:84` : `startContinuous` n'existe plus sur le notifier teste. La majorite des autres points visibles sont des avertissements ou informations de lint ; ce ne sont pas 138 vulnerabilites.

`flutter test --no-pub --reporter expanded` termine avec **190 reussites et 9 echecs**. Une seconde execution au format machine confirme les neuf cas pour obtenir une liste complete sans les traces tres volumineuses :

| Fichier / cas | Resultat observe | Interpretation |
|---|---|---|
| `recitation_basmala_test.dart:84` | `startContinuous` introuvable | Test non compilable, contrat devenu obsolete |
| `memorization_game_reprise_test.dart:84` | Verset attendu 1, obtenu 2 | Comportement ou attente de reprise a reconcilier |
| `memorization_game_reprise_test.dart:97` | Reprise attendue vraie, obtenue fausse | Meme famille de contrat |
| `memorization_game_reprise_test.dart:116` | Index attendu 0, obtenu 1 | Meme famille de contrat |
| `recitation_start_overlay_test.dart:20` | Le texte `3` n'est pas trouve | Compte a rebours/attente de test a verifier |
| `streaming_wav_capture_test.dart`, cas avant `close()` | Suppression refusee sous Windows, fichier encore ouvert | Nettoyage de test non portable ; pas une preuve de WAV corrompu |
| `tajweed_parse_test.dart`, verset 1:1 | L'attente contient un numero final retire du rendu | Attente de rendu a reconcilier |
| `tajweed_parse_test.dart`, verset 2:10 | Couleur attendue differente | Palette/contrat du test a reconcilier |
| `widget_test.dart`, smoke test | Exception du test widget | Harness et initialisation a diagnostiquer |

La revue ne trouve pas de pipeline GitHub Actions suivi dans le depot. Cela ne prouve pas l'absence de toute CI externe. Les tests versionnes ne fournissent pas actuellement de matrice complete Hafs/Warsh pour les caches, paliers, archives et commutateurs de confidentialite.

**Correction recommandee :** distinguer tests obsoletes, erreurs de harness et regressions du produit ; retablir une commande de verification verte ; ajouter des tests de comportements pour les constats reproduits et un controle de publication automatise. Ne pas changer le produit uniquement pour satisfaire une ancienne attente de couleur ou de navigation.

## 5. Protections deja presentes a conserver

- Les extras de recette de `MainActivity` sont conditionnes au flag Android `FLAG_DEBUGGABLE`. Une activite de lancement exportee n'est pas, a elle seule, une faille.
- La priorite au modele externe dans `FastConformerVerifier.ensureLoaded()` est conditionnee par `kDebugMode`. Il ne faut pas decrire cette ancienne porte de test comme ouverte en release.
- Les modeles du pack sont copies vers le stockage interne ; un `.tmp` et un renommage limitent le risque de copie partielle. L'asset pack participe a la livraison signee Android.
- `allowBackup=false` est bien present ; conserver cette protection tout en traitant SEC-04.
- Les services/receivers d'adhan propres au projet sont non exportes. Les composants media exportes servent une fonction Android attendue ; aucun contournement d'autorisation n'a ete demontre ici.
- Les URL reseau trouvees dans les services applicatifs sont HTTPS. Aucun contournement de validation TLS (`badCertificateCallback`, etc.) n'a ete trouve dans ce perimetre.
- Les requetes SQLite examinees utilisent des parametres pour les valeurs. Les placeholders `IN (...)` generes a partir du nombre d'elements ne constituent pas automatiquement une injection SQL.
- Les cles reconnues par motifs de fournisseurs et les blocs de cle privee recherches n'apparaissent pas dans les fichiers suivis de l'etat courant. Les fichiers locaux `key.properties` et `gradle-cacerts.jks` sont ignores par Git ; un magasin de certificats n'est pas automatiquement une cle privee divulguee.
- Le diagnostic Dart est desactive par defaut en release et les partages vocaux passent par un geste explicite. Il faut completer ces protections, pas perdre la distinction entre archivage fonctionnel, diagnostic et export.
- La plupart des donnees utilisateurs se trouvent dans le stockage prive. L'absence de chiffrement applicatif supplementaire ne suffit pas a conclure qu'une autre application ordinaire peut les lire.

## 6. Verifications executees et limites

| Controle | Resultat |
|---|---|
| Etat Git et huit derniers commits | Reference et modifications recentes identifies ; fichiers applicatifs suivis non modifies par cet audit |
| Recherche de secrets dans les fichiers suivis courants | Aucun motif de cle fournisseur/bloc prive recherche trouve ; recherche generique d'affectations sensibles sans resultat dans le code cible |
| `flutter analyze --no-pub` | Echec, 138 points ; erreur de test identifiee |
| `flutter test --no-pub --reporter expanded` | Echec, 190 reussites / 9 echecs |
| Seconde execution Flutter `--machine` | Memes neuf cas en echec identifies |
| Sondes isolees sur QuranApi | Deux comportements defectueux reproduits avec des fixtures synthetiques |
| Sonde sur les paliers et les vrais assets | 265 divergences "absent de l'asset mais coupe non vide a l'execution" |
| `gradlew.bat :app:dependencies --configuration releaseRuntimeClasspath --offline --console=plain` | Reussite, 98 coordonnees Maven resolues analysees, aucune resolution `FAILED` |
| OSV sur 176 paquets Pub heberges resolus | Aucun avis retourne pour les versions interrogees |
| OSV sur les 98 coordonnees Maven de release | Aucun avis retourne pour les versions interrogees |
| OSV sur `org.json:json:20180813` de test | Deux avis confirmes, SEC-12 |
| Ports locaux 8000 et 8765 | Aucun listener trouve au moment du controle |

Les versions Pub proviennent de `.dart_tool/package_graph.json` et de `package_config.json` pour identifier les paquets heberges ; les dependances locales et le SDK Flutter ne sont pas assimiles a des paquets Pub publics. Les deux coordonnees Maven de production initialement verifiees a la main ont aussi ete couvertes par le graphe complet de release.

**Les resultats OSV ne garantissent pas l'absence de vulnerabilites.** Ils ne couvrent pas exhaustivement les versions des bibliotheques C/C++ internes aux AAR, le moteur Flutter, Android du telephone, les plugins Gradle, les environnements Python et les checkpoints. Les versions resolues localement ne remplacent pas un inventaire du binaire effectivement publie.

Les sondes ont ete creees hors du depot sous `%TEMP%/chgpt_audit_20260906/quran_cache_audit_test.dart` et executees depuis `app` avec `flutter test --no-pub --reporter expanded <chemin-de-la-sonde>`. Leurs trois tests passent parce qu'ils **constatent les defauts attendus** ; cela n'est pas une validation de correction. Les etapes et sorties utiles sont reproduites dans QUAL-01 et QUAL-03.

Non realise : pentest d'un telephone release, interception des flux reels, test de migration constructeur, controle de la console Play, validation du certificat du binaire distribue, balayage de tous les commits Git par un scanner de secrets, tests JVM d'alignement, fuzzing de parseurs natifs, evaluation acoustique GOP/forced alignment sur un corpus Hafs et Warsh. Gitleaks et TruffleHog ne sont pas disponibles dans le PATH. La recherche par motifs ne detecte pas tous les secrets possibles.

## 7. Plan de correction propose

Les actions ci-dessous sont des recommandations, **pas des changements deja realises**.

1. **Confidentialite de production :** centraliser l'etat de diagnostic, retirer les transcriptions des impressions directes et synchroniser le natif avant toute journalisation. Corriger la purge sans effacer les archives de developpement non concernees.
2. **Integrite Hafs/Warsh :** corriger le cycle du cache QuranApi, figer la riwaya de chaque chargement/session et verrouiller les deux reproductions avec des tests qui attendent le bon resultat.
3. **Derniers paliers :** distinguer resultat vide et precalcul absent ; rendre explicite la riwaya ; comparer les resultats a une reference Hafs avant integration d'une evolution Warsh.
4. **Postes de developpement :** fermer par defaut les serveurs de benchmark, verifier les hotes SSH, securiser la provenance des corpus et checkpoints. Ne pas lancer ces outils sur un reseau partage avant ce controle.
5. **Cycle de vie des donnees :** exclusions de transfert Android, interface d'effacement selectif et budgets de stockage ; actualisation de la politique selon le fonctionnement final, avec verification du TTS et des polices.
6. **Audio et publication :** flux de telechargement bornes, cache par recitateur, publication refusee sans signature valide, mise a jour de JSON-java de test et verification automatisee verte.

### Conditions de validation Hafs/Warsh

Une correction de securite ne doit pas modifier les normalisations, tokens, seuils GOP ou regles d'alignement pour masquer un probleme. Avant toute evolution de la chaine partagee, conserver une reference et comparer les deux lectures separement.

Pour chaque correction concernant les textes, le coach ou l'ASR, verifier : lancement a froid en Hafs, lancement a froid en Warsh, bascule dans les deux sens, appels simultanes, changement pendant un chargement, retour d'arriere-plan, modele/asset indisponible et recitation interrompue. Les preuves acoustiques doivent utiliser le meme audio et des parametres documentes avant/apres ; une compilation reussie ne mesure pas une regression GOP.

## 8. Points complementaires a suivre

- **Modeles copies deja presents :** `extractModelFromAssetPack` saute tout fichier existant (`FastConformerCtcPlugin.kt:470`). Maintenir des repertoires vraiment versionnes et une coherence modele/vocabulaire/tokens/seuils ; ajouter un manifeste d'integrite si des mises a jour reutilisent un chemin. Aucune substitution de modele en release n'a ete demontree.
- **Donnees de reference :** versionner l'origine, le schema, les compteurs et les empreintes des assets de texte et de minutage. La pagination native Warsh et les identifiants utilises par l'audio doivent rester des contrats distingues.
- **Permission de stockage :** reevaluer `READ_EXTERNAL_STORAGE` jusqu'a API 32 maintenant que la livraison du modele release utilise le pack et le stockage interne. Ne pas la retirer sans verifier les parcours des Android anciens.
- **Synchronisation des telechargements :** `ReciterDownloadService` verifie `_active` avant un `await _rootDir()`, puis pose le verrou apres. Deux demandes simultanees peuvent passer cette fenetre. Verrouiller avant l'attente et tester suppression/annulation pendant ecriture ; ce point n'a pas ete reproduit dynamiquement ici.
- **Reproductibilite de l'outillage :** `benchmark/sherpa_requirements.txt` ne fige pas sa version d'`openai-whisper`, et le wrapper Gradle n'annonce pas de `distributionSha256Sum`. Verrouiller versions et empreintes des outils de livraison sans convertir cet ecart de durcissement en CVE inventee.
- **Documentation vieillissante :** `ARCHITECTURE.md` decrit encore des choix de dependances et de modeles qui ne correspondent pas au `pubspec.yaml` actuel, notamment le tuteur Gemma retire. Plusieurs commentaires conservent des etats historiques contredits par le code ; l'audit s'appuie sur les instructions executables.
- **Taille des composants :** le provider de recitation, l'ecran karaoke et le plugin natif concentrent plusieurs milliers de lignes chacun. Clarifier progressivement leurs responsabilites et contrats, avec des tests de comportement ; eviter une refonte simultanee a une correction de securite urgente.

## 9. Reprise par Claude ou un autre intervenant

Ce document a ete produit par **ChGPT**. Les constats ne sont pas des correctifs et les cas de test existants en echec sont anterieurs a l'audit. Ne pas marquer un point resolu parce qu'un commentaire a ete ajoute ou qu'une dependance a ete declaree plus recente : joindre une preuve apres correction.

Pour chaque suivi, noter l'ID, le commit correctif, les tests executes, la variante debug/release et la riwaya verifiee. Une correction Warsh qui modifie un resultat Hafs doit etre identifiee explicitement et evaluee comme une modification commune.

## 10. Optimisations sans degradation ASR

### 10.1. Conclusion et contrat de non-regression

**Oui, le code presente des possibilites de reduction du travail annexe, des allocations et des copies sans vouloir changer la reconnaissance.** Les pistes les mieux etayees concernent la FFT du mel-spectrogramme, les tableaux temporaires de l'alignement, les buffers d'entree ONNX et les journaux. Leur presence dans le code est constatee ; leur part dans la latence totale sur les telephones cibles reste a mesurer.

Il faut distinguer quatre objectifs : taille de l'application installee, pic de RAM, temps de calcul et delai de validation ressenti. Une baisse de RAM n'est pas automatiquement une acceleration ; une inference plus courte ne garantit pas un verdict plus rapide si sa file d'attente augmente. Les chiffres ci-dessous sont des calculs statiques de volumes ou de nombres d'allocations, **pas des mesures de CPU, de GC ou de vitesse**.

Le contrat a respecter est le suivant :

- Meme audio, meme echantillonnage et memes bornes d'echantillons ; pas de suppression silencieuse de blocs, de pauses ou de fins de mots.
- Meme texte attendu, meme vocabulaire, meme riwaya, memes variantes et memes tokens. La ressemblance entre deux mots affiches ne prouve pas l'identite des entrees acoustiques ou des chemins CTC.
- Memes regles GOP/forced alignment, preuves, seuils et etats du decideur ; pas d'amelioration apparente obtenue en validant plus facilement.
- Pas de nouveaux faux verts, faux rouges, mots omis/non juges ou retards de verrouillage ; examiner les resultats mot par mot, pas seulement le WER moyen.
- **Hafs conserve son comportement de reference.** Une correction linguistique Warsh doit passer par une fonction/strategie Warsh selectionnee explicitement par le type de recitation, sans elargir discretement une normalisation commune.
- Une optimisation numerique partagee exige une comparaison Hafs ET Warsh. Tant que cette preuve manque, conserver l'implementation de reference et isoler la variante experimentale ; ne pas activer automatiquement le nouveau chemin Hafs.
- CTL, REF et PRIERE ne sont pas interchangeables : une recette REF reussie ne valide pas a elle seule le chemin utilisateur CTL.

### 10.2. Ce qui est deja optimise

Ces mecanismes sont deja presents et ne doivent pas etre proposes comme de nouveaux gains :

| Etage | Etat courant observe | Consequence pour l'audit |
|---|---|---|
| Moteur ONNX | Session conservee dans `FastConformerCtc`, encodeur commun et sorties par tete | Ne pas compter plusieurs encodeurs a supprimer simplement parce qu'il existe plusieurs sorties |
| Parallelisme natif | `setIntraOpNumThreads(2)` et `setInterOpNumThreads(1)` | Le projet ne tourne pas ici avec un nombre de threads ORT non borne |
| V1 / V2 | `v1Coupee = v2Actif && v2Mots.isNotEmpty()` dans `feedBufferedAudio` | La V1 est deja court-circuitee sur ce chemin quand la V2 a sa cible ; ne pas promettre de diviser le CPU par deux en la retirant |
| Preparation du texte | Tokens, variantes et confusions prepares lors de la definition/extension de cible | Chercher les reconstructions restantes, pas ajouter un deuxieme cache des memes tokens |
| Spectrogramme | Fenetre Hann et banque de filtres mel conservees dans l'objet | Le probleme restant est notamment la FFT recursive et ses temporaires |
| Historique audio | `FluxBrut` utilise un anneau `ShortArray` PCM16 | Ne pas proposer une conversion Float -> PCM16 deja effectuee |
| Traces fines | Tampon en memoire borne a 200 000 lignes, vidage en fin de session | Distinguer `trace()` de `log()`, qui ecrit encore de facon synchrone |
| Evenements V2 | `alimenterV2` retourne les changements de statut | Ne pas supposer que chaque appel renvoie deja toute la grille a remplacer par des deltas |

Preuves : [FastConformerCtc.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt), lignes 124, 138 et 545 ; [FastConformerCtcPlugin.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtcPlugin.kt), lignes 754, 771 et 1717 ; [ChaineRecitation.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/ChaineRecitation.kt), champs vers 430 et extension vers 750 ; [MelSpectrogram.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/MelSpectrogram.kt), lignes 42 et 43 ; [FluxBrut.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/FluxBrut.kt) ; [diagnostic_log.dart](app/lib/services/diagnostic_log.dart), lignes 174 et 235.

### 10.3. Registre des pistes

Toutes les lignes ci-dessous ont le statut **propose, non implemente, gain non mesure**. Le risque indique la possibilite de regression lors d'une implementation, pas une vulnerabilite de securite. L'ordre final doit etre confirme par le profilage.

| ID | Piste | Benefice vise | Risque | Position proposee |
|---|---|---|---|---|
| OPT-01 | Diagnostic coherent et messages prepares seulement si utiles | Moins d'I/O, de formatage et de contention ; confidentialite | Faible a moyen | Premier lot avec SEC-01 |
| OPT-02 | FFT avec espace de travail reutilisable | Moins d'allocations et de calculs trigonometriques repetes | Moyen, numerique et concurrence | Forte priorite de mesure |
| OPT-03 | Calcul puissance -> mel par frame | Moins de RAM temporaire | Moyen, precision et ordre des operations | Apres une reference mel verrouillee |
| OPT-04 | Buffers ONNX directs a propriete explicite | Moins de copies et d'allocations d'entree | Moyen, duree de vie native | Apres instrumentation des copies |
| OPT-05 | Deux lignes de scores Viterbi / forward | Moins de RAM et de renouvellement de tableaux | Moyen, chemin CTC et sentinelles | Bon candidat isole avec tests JVM |
| OPT-06 | Cache borne des graphes d'ecritures | Moins de construction de graphes et de sous-chaines | Moyen, isolation du vocabulaire | Si le profil confirme ce cout |
| OPT-07 | Reconstruction UI selective | Moins de travail Dart et de saccades | Faible a moyen | Si les frames UI depassent leur budget |
| OPT-08 | Metadonnees de portions et ecritures groupees | Moins d'aller-retour SQL et de travail repetitif | Moyen a eleve, archivage | Apres correction des contrats de cache |
| OPT-09 | Telechargements audio en flux et concurrence bornee | Moins de pics RAM et de competition avec l'ASR | Moyen, cache et annulation | Avec SEC-10 / QUAL-04 |
| OPT-10 | Parcours contigus de l'anneau PCM16 | Moins de modulo dans les copies audio | Faible a moyen | Secondaire, selon profil |
| OPT-11 | Reglage mesure de l'execution ORT | CPU, energie et latence soutenue | Eleve si reglage aveugle | Experimentation par appareil |
| OPT-12 | Sorties ONNX strictement necessaires selon l'appel | Moins de materialisation, eventuellement de calcul | Eleve, contrat multi-tetes | Dernier lot, sans couper les preuves |

### 10.4. OPT-01 : journaux et traces

**Constat.** [diagnostic_log.dart](app/lib/services/diagnostic_log.dart), ligne 249, utilise `writeAsStringSync(..., flush: true)` dans `log()`. [DiagnosticLog.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/DiagnosticLog.kt), lignes 117 et 126, synchronise le logger et ouvre/ecrit/ferme un `FileWriter`. Les gardes internes `enabled` n'evitent pas de construire un argument deja interpole au site d'appel. Les chemins `trace()` ont deja un tampon et ne doivent pas etre confondus avec ces ecritures.

**Proposition.** Corriger d'abord SEC-01 ; ensuite mesurer et proteger les messages couteux avant leur construction, ou fournir une variante paresseuse du logger. Pour l'instrumentation de performance, reutiliser les traces bornees existantes et des compteurs numeriques. Une file d'ecriture asynchrone est un second changement : elle doit avoir un proprietaire clair, un budget memoire et une politique explicite de saturation/vidage, notamment puisque Dart et Kotlin partagent actuellement le fichier.

**Validation.** Comparer diagnostic desactive/active, arret, redemarrage et saturation. Conserver l'ordre utile, l'identifiant de session, la riwaya et CTL/REF/PRIERE dans les preuves. Ne pas supprimer les archives vocales fonctionnelles au motif de desactiver le diagnostic. Les anciens commentaires citant 22 a 32 ecritures/s sont un historique, pas une mesure du build audite.

### 10.5. OPT-02 : FFT et allocations du mel-spectrogramme

**Constat.** [MelSpectrogram.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/MelSpectrogram.kt), lignes 107 a 133 : chaque appel recursif cree `out`, et chaque appel non terminal cree `even` et `odd`. `cos` et `sin` sont recalcules aux memes angles pour chaque frame FFT de taille 512.

Pour une FFT de 512 points, l'arbre comporte 1 023 appels, dont 511 non terminaux. Cela represente **1 023 + 2 x 511 = 2 045 creations de `DoubleArray` par frame** dans ce seul helper. Pour 64 000 echantillons, soit quatre secondes a 16 kHz, `compute` produit `1 + floor(64000 / 160) = 401` frames mel : **820 045 creations de tableaux dans les FFT**, avant les autres temporaires. Ce comptage du code ne dit ni combien d'objets restent simultanement vivants, ni ce qu'un runtime optimise, ni combien de millisecondes seront economisees.

**Proposition.** Precalculer les coefficients trigonometriques immuables ; remplacer les allocations recursives par un espace de travail reutilisable, en conservant d'abord le meme ordre des operations et les memes types. Une implementation iterative/in-place ou une bibliotheque FFT peut etre evaluee ensuite, mais ce n'est pas automatiquement bit-identique. La portee du changement comprend aussi `frameLogMel`, qui appelle ce helper : ne pas tester uniquement `compute`.

**Risques a verrouiller.** Pas de tampon mutable global partage par plusieurs inferences. Prevoir une propriete par calcul, ou un pool borne avec acquisition/restitution sure. Conserver la preaccentuation effectuee en Float avant conversion Double, le centrage de la fenetre, le zero-padding et les constantes actuelles. Ne pas remplacer les Double par des Float pour gagner de la place dans le meme correctif.

**Validation.** Reference avant/apres sur silence, impulsion, sinus, bruit reproductible, voix, longueurs aux frontieres de hop et longueurs variees. Comparer les valeurs mel, les log-probabilites et les verdicts. L'expression historique "bit-exacte" dans le commentaire ne constitue pas une nouvelle preuve : etablir le niveau reel d'egalite. Exiger l'identite lorsque l'ordre numerique est conserve ; tout ecart doit etre explique et evalue acoustiquement, jamais absorbe par un changement de seuil GOP.

### 10.6. OPT-03 : ne pas conserver tout le spectre de puissance

**Constat.** Le meme fichier, ligne 206, alloue `power[Tmel][257]` en Double, puis remplit `logMel[80][Tmel]` aux lignes 224 a 230. La puissance d'une frame n'est plus utile une fois ses 80 valeurs mel calculees.

**Proposition.** Calculer FFT, puissance et projection mel pour chaque frame ; conserver seulement un tampon de puissance de 257 Double et la matrice log-mel necessaire a la normalisation finale. Garder l'ordre de sommation des frequences, le calcul du logarithme en Double et la normalisation par feature sur **la meme fenetre entiere**, avec `ddof=1` et le meme epsilon. Appeler simplement `frameLogMel` n'est pas equivalent ici : ce helper convertit deja ses resultats en Float avant la normalisation.

**Volume statique.** Le contenu numerique de la matrice actuelle occupe `8 x 257 x Tmel` octets, hors entetes. Pour quatre secondes : 824 456 octets, environ 0,79 Mio. Pour dix secondes : 2 058 056 octets, environ 1,96 Mio. Un tampon de remplacement occuperait 2 056 octets, hors entete. Il s'agit de RAM temporaire potentiellement evitable par inference, pas d'une reduction equivalente de l'APK.

**Validation.** Meme protocole mel qu'OPT-02, plus pic de RAM/allocations et duree par longueur. Ne pas remplacer la normalisation de fenetre par des statistiques fixes, cumulatives ou glissantes : cela change les entrees du modele. Le contexte aux bords doit egalement rester identique si une mise en cache des frames se chevauchant est etudiee plus tard.

### 10.7. OPT-04 : copies d'entree et duree de vie ONNX

**Constat.** [FastConformerCtc.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt), lignes 550 a 559, cree un `FloatBuffer.allocate(80 * Tmel)` sur le tas, le remplit, puis cree le tenseur. La documentation ONNX Runtime indique qu'un buffer non direct entraine une copie directe ; un buffer direct doit utiliser l'ordre natif. Source : [API Java OnnxTensor](https://onnxruntime.ai/docs/api/java/ai/onnxruntime/OnnxTensor.html).

**Proposition.** Tester un buffer direct correctement dimensionne et, si son allocation est significative, un pool borne par capacite et par calcul simultane. Conserver l'ordre `[1, 80, Tmel]`, la longueur exacte et les valeurs. Une premiere etape peut conserver `feats` et supprimer seulement la copie supplementaire de passage a ORT ; fusionner la production mel dans le buffer est une autre etape, a mesurer separement.

**Risques.** `position`, `limit`, dimensions et propriete doivent etre explicites. Ne jamais reecrire un buffer pendant `session.run`, reutiliser un tenseur de forme differente ou laisser croitre un pool au rythme des longueurs observees. La memoire directe n'apparait pas toute dans le tas Java : mesurer aussi la memoire native et liberer les references au bon moment.

**Validation.** Comparer les entrees element par element et les sorties, puis alterner fenetres courtes/longues, appels concurrents, annulation et fin de session. A quatre secondes, les seuls Float d'entree representent 128 320 octets par copie ; le benefice global depend du nombre reel d'appels et du cout des autres etages.

### 10.8. OPT-05 : memoire du forced alignment et du forward

**Constat.** [AligneurForce.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/AligneurForce.kt), lignes 372 a 400, conserve `dp[Tctc][S]` et `back[Tctc][S]`. Les transitions ne lisent que la ligne precedente de `dp`, puis le choix final ne lit que la derniere. La reconstruction du chemin utilise `back`, pas les anciennes lignes de `dp`.

**Proposition.** Utiliser deux lignes de scores alternees et conserver toute la matrice des predecesseurs `back`. Pour `Tctc >= 2`, le contenu numerique des scores passe de `4 x Tctc x S` a `8 x S` octets, soit une reduction de `4 x S x (Tctc - 2)` octets. Le cout de `back` reste proportionnel a `Tctc x S` : **l'aligneur complet ne devient donc pas O(S) en memoire**. `Tctc` designe les frames de sortie CTC et ne doit pas etre confondu avec `Tmel` du spectrogramme.

Les fonctions `forwardMoyenGraphe` et `forwardMoyen`, lignes 592 et 626, recreent egalement une ligne de scores par frame. Deux buffers remis a la sentinelle puis echanges eviteraient ce renouvellement sans devoir changer la recurrence.

**Risques.** Reinitialiser chaque ligne, conserver `neginf`, l'ordre des predecesseurs, le strict `>` en cas d'egalite et le traitement de la sentinelle avant division. Ne pas remplacer le forward par Viterbi, une approximation de `logSomme` ou un elagage de chemins : ce serait un changement de score acoustique, pas une simple economie memoire.

**Validation.** Comparer les chemins frame par frame, bornes de mots, forced/free, marges et verdicts sur des logits fixes. Inclure une seule frame, alignement impossible, blancs CTC, tokens identiques consecutifs, scores ex aequo, variantes d'ecriture Hafs/Warsh et mots sans preuve. Conserver les tests de sentinelles pour eviter les marges artificielles de tres grande amplitude deja decrites dans le code.

### 10.9. OPT-06 : cache des graphes d'ecritures

**Constat.** `grapheEcritures`, dans [AligneurForce.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/AligneurForce.kt), ligne 196, reconstruit les aretes de tokenisation. Il est utilise dans l'alignement et dans `forwardMoyenGraphe`, ligne 580 ; ce dernier reconstruit aussi les listes d'aretes entrantes/sortantes. Ce travail est distinct des tokens deja prepares par `ChaineRecitation`.

**Proposition.** Si les appels repetes apparaissent au profil, conserver des graphes immuables et leur topologie derivee dans un cache borne appartenant a l'aligneur. Identifier l'entree par le texte exact attendu par cette fonction et garantir que la duree de vie du cache ne depasse pas celle du vocabulaire/blank/riwaya correspondants. Un cache partage exigerait des cles explicites incluant ces identites et versions ; ne pas employer un texte arabe simplifie comme cle universelle.

**Validation.** Memes aretes et ordre de parcours, puis memes scores ; tester mots absents, resultat vide, caracteres specifiques Warsh, eviction, reconstruction et bascule de modele/riwaya. Compter taux de hit, temps de construction et memoire retenue. Un cache sans reutilisation significative ne serait qu'une augmentation de RAM.

### 10.10. OPT-07 : affichage Flutter sans retarder les verdicts

**Constat.** [karaoke_recitation_screen.dart](app/lib/screens/karaoke_recitation_screen.dart), ligne 3797, observe tout `recitationProvider`. Un changement d'etat peut donc reconstruire cet arbre, meme si une petite partie de l'affichage change. Un usage de `select` existe deja pour la transcription, ligne 5577. Aucun nombre de frames perdues n'a ete mesure pour cette extension.

**Proposition.** Profiler les reconstructions, puis separer les consommateurs d'etat selon leur besoin : curseur, verdicts visibles, commandes, transcription. Conserver les ecoutes qui declenchent l'archivage et les actions metier. Ne pas ajouter un debounce aux verdicts, diminuer la cadence d'ASR ou cacher les mises a jour pour embellir un graphe de performance.

Les mesures Flutter doivent etre faites en mode profile sur appareil physique, les couts debug n'etant pas representatifs. Distinguer temps UI et raster ; le budget d'une frame depend de la frequence d'ecran, par exemple environ 16,7 ms a 60 Hz. Source : [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance).

**Validation.** Mesurer p95/p99 des frames et delai evenement natif -> affichage. Tester grille longue, changement de page, defilement, plein ecran et accessibilite, avec Hafs puis Warsh. Les signes waqf, harakat, rendu des lettres isolees et pagination papier restent des tests visuels distincts : une optimisation du rendu ne doit pas reintroduire les chevauchements signales par l'utilisateur.

### 10.11. OPT-08 : portions, SQL et preuves vocales

**Constat.** [portion_word_archiver.dart](app/lib/services/portion_word_archiver.dart), lignes 107 et 118, extrait une preuve et resout la portion lors de l'archivage d'un mot. [session_archive_service.dart](app/lib/services/session_archive_service.dart), lignes 780, 837 et 887, effectue des recherches/ecritures de portion et de mot ainsi que des controles de completude. La copie audio ligne 871 protege notamment contre la reutilisation du fichier temporaire natif.

**Proposition.** Reutiliser les metadonnees immuables de portion a l'echelle appropriee, apres correction de QUAL-01 a QUAL-03 ; inclure riwaya, granularite et version des coupures dans leur identite. Mesurer les requetes, puis etudier de petites transactions ordonnees ou un batch SQL pour les evenements deja disponibles. Une file d'archivage doit etre bornee et dissociee de la livraison immediate du verdict, sans ajouter une attente arbitraire pour remplir un lot.

**Risques.** Ne pas fusionner plusieurs transitions d'un mot en ne gardant que la derniere : `deja_rate` est monotone et les repetitions comptent les transitions incomplet -> complet, lignes 891 et 939. Ne pas supprimer une copie WAV sous pretexte de doublon si les plages/contextes different ou si sa source temporaire peut etre ecrasee. Une transaction SQLite ne rend pas les operations de fichiers atomiques.

**Validation.** Comparer contenu SQL, compteur de repetitions et empreintes/plages audio a la reference. Tester corrections successives, arret brutal, espace disque insuffisant, reprise et purge. Mesurer profondeur/age de file, duree d'extraction et de copie, requetes par mot et impact sur le delai d'affichage. L'economie est indirecte pour l'ASR ; elle ne justifie aucune perte de preuve.

### 10.12. OPT-09 : reseau et cache audio pendant l'ASR

**Constat.** Les telechargements de SEC-10 materialisent des reponses audio entieres en memoire dans les services examines. QUAL-04 identifie en outre une cle de cache qui peut reutiliser un recitateur incorrect. Ces travaux peuvent coexister avec la capture, l'inference et le rendu ; leur competition effective reste a mesurer.

**Proposition.** Ecrire le flux vers un fichier temporaire avec compteur d'octets, limites adaptees, timeouts et annulation ; publier le fichier apres controle. Borner la concurrence et eviter les telechargements identiques simultanes. Garder les memes octets audio, le meme recitateur et la bonne riwaya : changer le debit, le codec ou la source n'est pas necessaire pour supprimer la mise en memoire complete.

**Validation.** Comparer les fichiers avant/apres, cache hit/miss, reseau lent, reponse tronquee, annulation et changement de recitateur. Mesurer RAM et latence ASR avec et sans telechargement concurrent. Ne pas retarder sans mesure l'audio correctif demande par l'utilisateur pour privilegier une statistique CPU.

### 10.13. OPT-10 : copies depuis l'anneau audio

**Constat.** [FluxBrut.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/FluxBrut.kt), notamment `extraire` ligne 55, calcule un index circulaire par echantillon puis convertit le PCM16 en Float. Le tampon par defaut de 300 secondes contient 4 800 000 Short a 16 kHz, soit 9 600 000 octets de contenu numerique, environ 9,16 Mio.

**Proposition.** Evaluer une extraction par au plus deux plages contigues pour limiter les modulo, tout en conservant les controles de bornes absolues, la quantification et la division par `32767f`. Le FloatArray retourne reste necessaire aux consommateurs actuels ; supprimer sa copie imposerait un autre contrat de duree de vie.

**Validation.** Egalite des echantillons aux passages de fin d'anneau, extremes PCM, ajout/extraction et demande hors historique. Ne pas reduire les 300 secondes pour obtenir un chiffre RAM plus bas : cela peut retirer des preuves d'archives et des possibilites de reprise. Cette piste est secondaire tant que son cout n'est pas visible au profil.

### 10.14. OPT-11 : threads et ordonnancement, uniquement apres mesure

**Constat.** Les reglages ORT sont deja 2/1 ; le plugin utilise aussi `CoroutineScope(Dispatchers.Default)`, ligne 254 de [FastConformerCtcPlugin.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtcPlugin.kt). Le nombre de threads d'une session et le nombre de calculs simultanes dans l'application sont deux sujets differents.

ORT distingue parallelisme intra-operateur et inter-operateurs ; ce dernier est lie au mode d'execution parallele. L'attente active des workers implique un compromis entre latence de reveil et consommation CPU. Les options et leur disponibilite doivent etre verifiees pour la version embarquee, pas copiees aveuglement depuis une documentation plus recente. Source : [ONNX Runtime thread management](https://onnxruntime.ai/docs/performance/tune-performance/threading.html).

**Proposition experimentale.** Mesurer la configuration actuelle, puis une seule variante a la fois sur les appareils cibles. Observer ensemble inferences en vol, file d'attente, UI, capture et temperature. Ne pas imposer un seul thread, augmenter le parallelisme, ajouter un verrou global ou annuler les fenetres dites anciennes sans preuve que toutes les observations requises restent disponibles a temps.

**Validation.** Latence p95/p99 de bout en bout, absence d'echantillons perdus et de calculs termines dans une mauvaise session, CPU et comportement apres 20 a 30 minutes. Une baisse du CPU accompagnee de verdicts plus tardifs ne satisfait pas la demande. Aucun reglage universel "plus de threads = plus rapide" ou "moins de threads = meilleur" n'est justifie ici.

### 10.15. OPT-12 : sorties du modele et materialisation

**Constat.** `computeAll`, dans [FastConformerCtc.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt), ligne 561, demande les sorties avec `session.run(inputs)`, puis materialise lettres, tajwid et etat encodeur lorsqu'ils existent. Le chemin `computeLogProbs` delegue aussi a `computeAll`. La remise en ordre de `encoder_state`, lignes 603 a 607, corrige un contrat de dimensions : elle ne doit pas etre retiree comme une copie supposee inutile.

**Proposition experimentale.** Inventorier les consommateurs et, seulement lorsqu'une sortie est reellement inutilisee pour un appel, evaluer `run(inputs, requestedOutputs)`. Cette surcharge existe dans l'[API Java OrtSession](https://onnxruntime.ai/docs/api/java/ai/onnxruntime/OrtSession.html). Son existence ne prouve pas que le graphe partage evitera tout le calcul correspondant ; mesurer le resultat reel. Garder les sorties necessaires aux preuves tajwid et a la tete utilisant l'etat encodeur.

**Risques.** Une selection de sorties peut changer l'ordre retourne : recuperer les resultats par nom, sans conserver aveuglement le repli `results[0]`. Prevoir explicitement les anciens modeles sans toutes les sorties et la riwaya choisie. Ne pas transformer la fermeture actuelle des resultats en fuite native ou en lecture apres fermeture.

Une representation aplatie des sorties peut etre testee separement, mais `getFloatBuffer()` est documente comme une copie ; `getBufferRef()` n'est pas une garantie de reference disponible pour une sortie allouee par ORT. Source : [API Java OnnxTensor](https://onnxruntime.ai/docs/api/java/ai/onnxruntime/OnnxTensor.html). Un changement de stockage imposerait de verifier tous les lecteurs d'indices et la propriete des donnees.

**Validation.** Meme tete selectionnee, memes dimensions et valeurs consommees, memes decisions lettres/harakat/tajwid. Mesurer temps ORT, conversion des sorties et RAM separement. Ne pas desactiver une tete uniquement parce qu'un essai de transcription ne l'utilise pas : la transcription et le jugement de recitation n'ont pas le meme contrat.

### 10.16. Pistes exclues du lot "sans sacrifice"

Les changements suivants peuvent etre des recherches utiles, mais ils ne doivent pas etre vendus comme de simples optimisations equivalentes :

- Reduire l'echantillonnage, le contexte, le recouvrement, les apercus, la fusion ou le nombre de preuves ; augmenter l'intervalle entre inferences.
- Eliminer toutes les pauses avec un VAD, ou ne plus traiter la fin de session : les silences et bornes participent aux preuves et a la validation des derniers mots.
- Modifier le beam, les variantes, la normalisation arabe, les symboles reconnus, le blank, les seuils GOP ou les chemins du forced alignment.
- Changer la normalisation mel, sa precision ou son padding ; remplacer l'entree mel `audio_signal` par de l'audio brut sous le meme nom.
- Quantifier davantage, elaguer/distiller le modele, changer d'encodeur ou passer a un autre execution provider GPU/NPU : il faut alors une qualification numerique et acoustique propre a ce changement.
- Remplacer l'ASR embarque par un service distant pour alleger l'application : cela modifie confidentialite, disponibilite hors ligne et latence reseau.

Le graphe historique [graph.json](graphify-out/graph.json), consulte avec [GRAPHE_RECITATION.md](GRAPHE_RECITATION.md) et [ARCHITECTURE_ASR.md](ARCHITECTURE_ASR.md), rappelle notamment `mort_fenetre_glissante_naive`, `mort_stats_normalisation_fixes`, `piege_audio_signal` et `piege_v2_portier_gele_la_grille`. Ce sont des garde-fous issus d'experiences anterieures, pas des mesures du build actuel. Les commentaires du plugin vers 1796 a 1822 rapportent eux-memes des effets de fusion differents selon modele/banc : aucune conclusion universelle ne doit en etre deduite.

### 10.17. Banc de mesure requis avant implementation

**Reference reproductible.** Identifier A par commit, empreintes du modele/vocabulaire/assets, version ORT, options, telephone/Android, mode de build et reglages. Identifier B avec les memes donnees et une seule optimisation. Fixer riwaya et mode de session avant le chargement. Les defauts de cache QUAL-01 a QUAL-04 doivent etre corriges ou isoles explicitement dans la recette pour ne pas comparer des textes/recitateurs differents.

**Deux etages de mesure.** Un rejeu deterministe des memes PCM/logits permet la comparaison numerique et metier. Une execution sur telephone avec capture, UI et archivage mesure l'experience reelle. Un rejeu accelere sur PC ne remplace pas une mesure temps reel sur appareil. Pour le mode profile Flutter, preparer un identifiant/stockage de test distinct avant installation afin de ne pas remplacer ni migrer les donnees de la version utilisateur.

| Mesure a collecter | Definition / utilite |
|---|---|
| Chargement a froid / a chaud | Temps et pic RAM separes du regime de recitation ; inclure copie/extraction d'asset lorsqu'elle a reellement lieu |
| Preparation mel | Duree de `MelSpectrogram.compute` et allocations, par longueur reelle de fenetre |
| Entrees ONNX | Temps de remplissage, creation de tenseurs et volume copie |
| Inference ORT seule | Temps autour de `session.run`, sans le confondre avec le calcul mel ou les copies de sortie |
| Sorties / alignement | Materialisation/transposition, graphes, Viterbi, forward, tete de traits et decision, mesures distinctes |
| Files et concurrence | Nombre de calculs en vol, age de la plus ancienne demande, fin hors session/ordre attendu |
| Qualite ASR | WER avec convention explicite et erreurs par mot ; faux verts, faux rouges, oublis, non-juges, etat final et stabilite du verdict |
| Latence ressentie | Debut de parole -> premier resultat ; fin acoustique du mot -> verdict stable visible, en p50/p95/p99 |
| Integrite audio | Compteurs d'echantillons captures/traites, bornes absolues, discontinuites et dernier mot effectivement traite |
| Interface | Durees UI/raster, frames hors budget, delai evenement natif -> frame visible |
| Ressources | CPU, allocations/GC, tas Dart/JVM, memoire native/directe, PSS/RSS, stockage ecrit et profondeur de file d'archives |
| Endurance | Evolution latence/temperature apres 20 a 30 minutes, stabilite memoire et consommation dans des conditions documentees |

Le chronometre de [FrontAcoustique.kt](app/android/app/src/main/kotlin/com/corankarim/coran_karim/recitation2/FrontAcoustique.kt), lignes 125 a 129, entoure actuellement `computeAll` : il comprend donc mel, buffers, inference et sorties. Le renommer mentalement "temps ONNX pur" conduirait a attribuer les gains au mauvais composant.

Utiliser des horloges monotones. Pour rapprocher timestamps Dart et Kotlin, etablir leur correspondance ; ne pas soustraire directement deux origines d'horloge independantes. Les bornes d'echantillons donnent une reference acoustique, mais il faut aussi relier cette reference a la capture et a la frame effectivement affichee.

Le RTF d'un appel est sa duree divisee par la duree de sa fenetre audio. Dans cette application, des fenetres peuvent se recouvrir : ajouter le volume audio total inferre / la duree capturee et la latence de file. Un bon RTF par appel peut masquer beaucoup de recalcul ; une somme des durees de calcul en concurrence n'est pas une duree murale de session.

**Corpus minimum.** Hafs et Warsh mesures separement ; lecture lente/rapide, environnement calme/bruite, pauses, reprises, mots repetes, basmala, lettres isolees dont le debut de la Baqara Warsh, harakat, madd et waqf. Inclure des fautes intentionnelles annotees : un moteur qui verdit tout peut avoir une interface tres rapide et etre pedagogiquement incorrect. Prevoir clips courts, longue recitation et cas proches des seuils.

**Execution comparative.** Au moins deux classes d'appareils cibles, plusieurs repetitions appairees A/B et alternance de l'ordre pour limiter les effets de chauffe/cache. Documenter conditions batterie, charge, ecran, reseau et autres applications. Separer phase de chauffe, mesure a froid et mesure soutenue. Conserver les resultats par appareil/riwaya : une moyenne globale favorable ne doit pas cacher une regression Warsh ou sur un telephone modeste.

**Acceptation.** Exiger l'egalite des resultats metier pour les optimisations de stockage/allocations sur le corpus deterministe et investiguer tout ecart numerique. Sur telephone, n'accepter aucun ralentissement reproductible des latences utiles ni perte de qualite. Si la dispersion ne permet pas de conclure, augmenter la mesure ; une difference noyee dans le bruit n'est ni un gain demontre ni une preuve de non-regression. Une baisse de RAM seule reste un resultat valable uniquement si rapidite et qualite sont preservees.

**Limite actuelle.** Aucun profil CPU/allocations, benchmark acoustique avant/apres ou test d'endurance sur telephone n'a ete execute pour cette extension. Le fichier `banc_inference.py` cite par un commentaire de `FastConformerCtc.kt` n'a pas ete retrouve dans les fichiers recherches ; ne pas presenter son execution comme une validation disponible. Adapter un banc existant apres verification de son chemin reel, ou ajouter un banc dedie, sera un travail d'implementation distinct.

### 10.18. Taille de livraison, priorites et transmission

OPT-01 a OPT-10 ciblent principalement CPU/RAM/I/O et peuvent etre etudies sans ajouter de modele, sans embarquer les photos des 604 pages et sans changer les poids acoustiques. Le gain de RAM estime dans une fonction n'est pas un gain de taille telechargee. Mesurer separement APK/AAB, split installe, pack modele, copie extraite du modele, cache audio et archives.

Pour le rendu mushaf, conserver des ornements vectoriels/`CustomPainter` reutilisables et des polices embarquees appropriees permet de separer decoration et texte ; l'audit ne valide pas une nouvelle police ni le sous-ensemble de glyphes necessaire. Toute reduction de police demande une couverture complete Hafs/Warsh, signes waqf/sajda et composition des harakat. Ne pas economiser quelques glyphes au prix des regressions visuelles deja signalees.

**Ordre de travail conseille :**

1. Traiter les priorites de securite et d'integrite, conserver une reference stable par riwaya et rendre les tests pertinents verts. Les neuf echecs Flutter de la section 6 restent a traiter ; ils ne sont pas effaces par ce complement.
2. Ajouter une instrumentation legere et etablir la repartition reelle mel / ORT / alignement / UI / archivage.
3. Corriger le diagnostic, puis essayer une seule economie d'allocations a la fois : OPT-05, OPT-02/03 ou OPT-04 selon le profil. Conserver pour chaque lot la preuve numerique avant/apres.
4. Optimiser UI, cache et I/O seulement la ou ils pesent effectivement ; verifier les changements de session/riwaya et l'integrite des preuves.
5. Reserver threads, selection de sorties et changements de representation plus larges aux experiences instrumentees. Ne pas introduire simultanement une optimisation et un nouveau modele.

Fiche a remplir pour chaque tentative : `ID OPT`, auteur, commit de reference, commit candidat, fichiers touches, riwayas/modes couverts, empreintes des entrees, appareil, mesures A/B p50/p95/p99, RAM, ecarts de logits/verdicts, limites, decision garder/rejeter et moyen de retour a la reference. Ne marquer "sans regression" que pour le perimetre effectivement teste.

**Transmission ChGPT a Claude :** les douze OPT sont des propositions documentees, pas des optimisations appliquees. Aucun modele, fonction d'alignement, seuil, asset Quran, code Flutter ou reglage d'execution n'a ete modifie par cette extension. Les tests de la section 6 appartiennent a l'audit initial ; ils n'ont pas ete relances pour cet ajout documentaire et ne prouvent aucun gain de performance.
