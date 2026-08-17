import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Source audio MP3Quran.net — remplace, pour Al-Afasy uniquement, la
/// diffusion audio qui passait par `verses.quran.com` (Quran Foundation).
///
/// ── POURQUOI (2026-08-13) ─────────────────────────────────────────────────
/// L'API de récitation de Quran Foundation exige désormais un `client_secret`
/// confidentiel (flux Client Credentials) — inutilisable tel quel dans un
/// APK, et leur réponse écrite recommande un proxy côté serveur pour toute
/// l'app. MP3Quran.net sert ses fichiers à des URL publiques, sans clé ni
/// jeton, et sa page de confidentialité déclare explicitement (vérifiée le
/// 2026-08-13, section « الحقوق ») : « جميع الحقوق متاحة للجميع و يحق لأي
/// زائر أو مطور استخدام اي مادة أو رابط من الموقع » -- « All rights are
/// available to everyone, and we allow any visitor or developer to copy any
/// material or use any link on the websites ». Aucun serveur, aucun secret
/// à protéger.
///
/// ── DIFFÉRENCE STRUCTURELLE AVEC LE MODÈLE quran.com ──────────────────────
/// `QuranApi.fetchSurahAudioUrls` renvoie UNE URL PAR VERSET (286 fichiers
/// pour Al-Baqara). MP3Quran.net sert UN FICHIER PAR SOURATE ENTIÈRE ; le
/// découpage par verset vient d'une table de temps séparée (`ayat_timing`),
/// en millisecondes. Lire un seul verset revient donc à ouvrir le flux de la
/// sourate, sauter (`seek`) au `startMs` du verset, et arrêter la lecture au
/// `endMs` -- cf. `AudioPlayerService._jouerViaMp3Quran`.
///
/// ── CE QUI N'EST PAS VÉRIFIÉ SUR DEVICE AU MOMENT DE L'ÉCRITURE ───────────
/// La convention de nom de fichier `{server}{sss}.mp3` (ex.
/// `https://server8.mp3quran.net/afs/001.mp3`) suit le standard quasi
/// universel des CDN de récitation coranique (everyayah, quranicaudio) mais
/// n'a pas pu être confirmée par une requête directe depuis cet
/// environnement (403 -- absence d'en-têtes navigateur côté outil, pas
/// nécessairement un vrai blocage). La table `ayat_timing` ci-dessous, elle,
/// EST vérifiée : réponse réelle obtenue pour la sourate 1, 7 entrées,
/// durées plausibles (13 189 ms pour la Bismillah). C'est le premier test
/// sur device qui tranchera pour l'audio -- d'où l'A/B implicite : si la
/// lecture échoue, `AudioPlayerService` doit le signaler clairement plutôt
/// que de rester silencieux.
///
/// ── PORTÉE VOLONTAIREMENT ÉTROITE ──────────────────────────────────────
/// Un seul récitateur, Al-Afasy (id interne de l'app = 7), confirmé côté
/// MP3Quran par DEUX requêtes indépendantes cohérentes (reciter_id=123,
/// serveur `server8.mp3quran.net/afs/`, rewaya=1 = Hafs). Les autres
/// récitateurs de l'app restent sur le chemin quran.com existant, inchangé :
/// une tentative d'établir leur correspondance ce même jour a produit des
/// résultats CONTRADICTOIRES pour Al-Qatami (deux noms différents renvoyés
/// pour le même id, l'un d'eux étant Al-Qahtani -- un récitateur différent).
/// Servir la mauvaise voix sous le mauvais nom est un défaut de confiance,
/// pas un détail : mieux vaut une couverture étroite et exacte qu'une table
/// large et douteuse.
class Mp3QuranApi {
  Mp3QuranApi._();

  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://www.mp3quran.net/api/v3',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // Client SÉPARÉ pour le téléchargement des fichiers audio -- distinct du
  // client JSON ci-dessus, dont le `receiveTimeout` de 30 s couperait le
  // téléchargement d'une longue sourate (Al-Baqara peut dépasser plusieurs
  // dizaines de Mo). `responseType: bytes` évite que Dio tente de décoder
  // le flux comme du texte/JSON.
  static final _dioAudio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 5),
    responseType: ResponseType.bytes,
  ));

  /// Serveur du moshaf Hafs-Murattal d'Al-Afasy chez MP3Quran.net.
  /// reciter_id=123 côté MP3Quran -- vérifié le 2026-08-13, cohérent sur deux
  /// requêtes indépendantes (moshaf name="حفص عن عاصم - مرتل", type=11).
  static const _kAfasyServer = 'https://server8.mp3quran.net/afs/';

  /// Vrai si ce récitateur (identifiant INTERNE à l'app, cf. `Reciter.id`
  /// dans `models/reciter.dart`) est servi par MP3Quran plutôt que par
  /// quran.com. Point d'extension : ajouter une entrée ici seulement après
  /// avoir vérifié la correspondance par DEUX requêtes API cohérentes, pas
  /// une seule (cf. le piège Qatami/Qahtani ci-dessus).
  static bool sertCeReciter(int appReciterId) => appReciterId == 7;

  static String urlSourate(int appReciterId, int surahNumber) {
    assert(sertCeReciter(appReciterId));
    return '$_kAfasyServer${surahNumber.toString().padLeft(3, '0')}.mp3';
  }

  static final _fichierLocalEnCours = <String, Future<String>>{};

  /// Chemin LOCAL du fichier de la sourate entière, en le téléchargeant une
  /// fois si nécessaire.
  ///
  /// ── POURQUOI UN FICHIER LOCAL ET NON UN FLUX (2026-08-16, demande
  /// utilisateur : « au lieu de travailler en flux tendu avec l'API ») ──────
  /// Même avec un minutage exact, sauter (`seek`) dans un flux SERVI PAR LE
  /// RÉSEAU (`UrlSource`) peut obliger le lecteur natif à re-tamponner autour
  /// du nouveau point s'il n'est pas déjà reçu -- un vrai trou audible,
  /// indépendant de tout `pause()`/`resume()` côté Dart (cf. l'historique
  /// dans `AudioPlayerService._jouerViaMp3Quran`). Un fichier déjà sur le
  /// disque n'a besoin d'aucune requête réseau pour sauter d'un point à un
  /// autre : la classe de défaut disparaît, elle n'est pas seulement réduite.
  ///
  /// COMPROMIS ASSUMÉ, à la charge du premier appel sur une sourate neuve :
  /// la lecture attend la fin du téléchargement du fichier ENTIER avant de
  /// démarrer, au lieu de démarrer immédiatement en streaming. De l'ordre de
  /// la seconde pour une sourate courte, plusieurs secondes pour une longue
  /// (Al-Baqara). `PlayerNotifier.play()` affiche déjà `PlayerStatus.loading`
  /// pendant ce délai pour un tap manuel -- aucune plomberie supplémentaire
  /// n'est nécessaire côté IHM pour ce cas.
  ///
  /// Idempotent et résistant aux doubles appels concurrents : le `Future` de
  /// téléchargement en cours est partagé (`_fichierLocalEnCours`) plutôt que
  /// de laisser deux appels lancer deux téléchargements du même fichier.
  static Future<String> fichierLocalSourate(
      int appReciterId, int surahNumber) async {
    // ── PIÈGE CORRIGÉ (2026-08-16) ──────────────────────────────────────────
    // `$appReciterId:$surahNumber` (avec un DEUX-POINTS) produisait un nom de
    // fichier comme `7:4.mp3`. Constat sur device : `_player.play()` échouait
    // TOUJOURS sur ce fichier avec `MEDIA_ERROR_SYSTEM`, même pour un
    // téléchargement complet et validé (76 576 952 octets reçus = annoncés,
    // aucune troncature -- donc PAS le bug de troncature corrigé juste avant).
    // Le deux-points est un caractère significatif en syntaxe URI (séparateur
    // de schéma, `file://...`) : le lecteur natif construit une URI à partir
    // du chemin, et un deux-points AILLEURS que dans le schéma la rend
    // invalide -- symptôme exact d'une source mal formée, pas d'un fichier
    // corrompu. Underscore : aucun sens spécial en URI ni sur aucun système
    // de fichiers cible.
    final cle = '${appReciterId}_$surahNumber';
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/mp3quran_cache/$cle.mp3';
    final file = File(path);
    if (await file.exists() && await file.length() > 0) return path;

    final enCours = _fichierLocalEnCours[cle];
    if (enCours != null) return enCours;

    final future = () async {
      try {
        await file.parent.create(recursive: true);
        final url = urlSourate(appReciterId, surahNumber);
        debugPrint('[Mp3Quran] telechargement demarre : $url');
        final chrono = Stopwatch()..start();
        final r = await _dioAudio.get<List<int>>(url);
        final bytes = r.data;
        debugPrint('[Mp3Quran] telechargement recu : '
            '${bytes?.length ?? 0} octets en ${chrono.elapsedMilliseconds} ms');
        if (bytes == null || bytes.isEmpty) {
          throw StateError('reponse audio vide pour $url');
        }
        // ── VALIDATION D'INTÉGRITÉ (2026-08-16) ─────────────────────────────
        //
        // BUG RÉEL CONSTATÉ SUR DEVICE : un téléchargement d'Al-Baqara
        // (attendu ~120 641 555 octets) s'est arrêté en cours de route sur un
        // réseau mobile instable, SANS que `_dioAudio.get()` ne lève
        // d'exception -- `bytes` était non nul et non vide (donc acceptable
        // selon le seul contrôle ci-dessus), mais sa FIN contenait du
        // remplissage (`0x55` répété) au lieu d'audio réel. Le fichier a été
        // mis en cache comme "complet", et le lecteur natif a refusé de
        // l'ouvrir (`MEDIA_ERROR_SYSTEM`) -- silencieusement, sans que rien
        // ne le redemande jamais, puisque `fichierLocalSourate` ne vérifie
        // QUE l'existence et la non-nullité du fichier au prochain appel.
        //
        // Un serveur HTTP correct annonce la taille réelle via `Content-
        // Length` -- comparer les octets REÇUS à ce qui était ANNONCÉ détecte
        // exactement ce cas, sans avoir à deviner la taille attendue d'une
        // sourate à l'avance.
        final annonce = r.headers.value('content-length');
        if (annonce != null) {
          final tailleAnnoncee = int.tryParse(annonce);
          if (tailleAnnoncee != null && bytes.length != tailleAnnoncee) {
            throw StateError(
                'telechargement tronque pour $url : ${bytes.length} octets '
                'recus, $tailleAnnoncee annonces par le serveur');
          }
        }
        // Écriture sous nom temporaire puis renommage : un fichier
        // partiellement écrit (app tuée en plein téléchargement) ne doit
        // jamais être pris pour un fichier complet au prochain lancement --
        // même précaution que `ReciterDownloadService.downloadSurah`.
        final tmp = File('$path.part');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(path);
        return path;
      } catch (e) {
        debugPrint('[Mp3Quran] telechargement ECHOUE : $e');
        rethrow;
      } finally {
        _fichierLocalEnCours.remove(cle);
      }
    }();
    _fichierLocalEnCours[cle] = future;
    return future;
  }

  static final _timingCache = <int, List<AyahTiming>>{};

  /// Minutage par verset (ms) pour une sourate. Mis en cache : la même
  /// sourate est interrogée à chaque verset tapé tant qu'on y reste.
  ///
  /// ── PIÈGE CORRIGÉ (2026-08-16, constat utilisateur : « il y a un écart,
  /// l'audio change, le surligneur suit avec retard, puis coupure ») ────────
  /// `read` (nom du paramètre imposé par l'API) N'EST PAS une table générique
  /// par riwāya comme documenté ici jusqu'alors : c'est le récitateur, mais
  /// PAS FORCÉMENT le bon si on ne vérifie pas. La version précédente
  /// utilisait `read: 1` -- une valeur qui répondait sans erreur pour la
  /// sourate 1, donc jugée valide à tort. Comparaison directe, verset 1 de la
  /// sourate 1 :
  ///   read=1   -> 0-13189 ms   (13,2 s)
  ///   read=123 -> 6420-11120 ms (4,7 s, avec un silence initial)
  /// Complètement différent : `read=1` est le minutage d'UN AUTRE récitateur
  /// que celui qui joue réellement (`_kAfasyServer`). Le Timer de
  /// `AudioPlayerService._jouerViaMp3Quran` coupait donc juste, mais pour la
  /// voix d'un autre -- l'écart grandissant verset après verset, et les
  /// coupures en plein mot, avaient cette cause précise, pas une limite du
  /// streaming réseau. `read: 123` = le `reciter_id` MP3Quran d'Al-Afasy,
  /// le même que celui utilisé pour construire l'URL audio -- c'est cette
  /// cohérence entre la SOURCE et le MINUTAGE qui doit toujours être vraie.
  static Future<List<AyahTiming>> ayatTiming(int surahNumber) async {
    final cached = _timingCache[surahNumber];
    if (cached != null) return cached;
    debugPrint('[Mp3Quran] minutage demande : sourate $surahNumber');
    final chrono = Stopwatch()..start();
    try {
      final r = await _dio.get('/ayat_timing', queryParameters: {
        'surah': surahNumber,
        'read': 123,
        'mp3quran': 1,
      });
      final list = (r.data as List)
          .map((e) => AyahTiming(
                ayah: e['ayah'] as int,
                startMs: (e['start_time'] as num).toInt(),
                endMs: (e['end_time'] as num).toInt(),
              ))
          .toList();
      debugPrint('[Mp3Quran] minutage recu : ${list.length} versets en '
          '${chrono.elapsedMilliseconds} ms');
      return _timingCache[surahNumber] = list;
    } catch (e) {
      debugPrint('[Mp3Quran] minutage ECHOUE apres '
          '${chrono.elapsedMilliseconds} ms : $e');
      rethrow;
    }
  }
}

class AyahTiming {
  final int ayah;
  final int startMs;
  final int endMs;
  const AyahTiming(
      {required this.ayah, required this.startMs, required this.endMs});
}

/// Minutage mot à mot, calculé LOCALEMENT sur l'audio MP3Quran d'Al-Afasy --
/// remplace `QuranApi.fetchAyahSegments` (Quran Foundation) pour ce
/// récitateur, sans aucun appel réseau.
///
/// ── PROVENANCE (2026-08-16) ───────────────────────────────────────────────
/// `assets/data/word_segments_mp3quran_afasy.json` est produit par
/// `benchmark/generer_predictions_mp3quran.py` : alignement forcé CTC (le
/// même algorithme que `ForcedAligner.kt`, tourné hors-app sur le poste de
/// développement) sur les 6236 versets de l'audio MP3Quran réellement servi
/// par l'app (cf. `Mp3QuranApi.urlSourate`). AUCUNE dépendance à Quran
/// Foundation dans sa génération -- seul le texte local de l'app
/// (`quran_verses.json`, Tanzil/KFGQPC) et le modèle ASR déployé y
/// contribuent. Détail complet, limites assumées et mesures de validation :
/// `AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md` §3bis (médiane 78ms, p95
/// 233ms sur un échantillon recoupé avec un second enregistrement
/// indépendant -- pas un 100% garanti, mais un signal net que l'alignement
/// retrouve une vraie structure de mots).
///
/// Format du fichier : `{"surah:ayah": [[début_ms, fin_ms], ...]}`, un
/// couple par mot, dans l'ordre de `ArabicNormalizer.splitExpectedWords` --
/// MÊME AVERTISSEMENT que `WordTimingService` : l'appelant doit vérifier que
/// la longueur correspond à son propre découpage avant tout usage
/// positionnel, un décalage silencieux attribuerait le minutage d'un mot à
/// son voisin.
class Mp3QuranWordSegments {
  Mp3QuranWordSegments._();
  static final instance = Mp3QuranWordSegments._();

  Map<String, List<List<double>>>? _parVerse;
  bool _chargement = false;

  Future<void> ensureLoaded() async {
    if (_parVerse != null || _chargement) return;
    _chargement = true;
    try {
      final brut = await rootBundle
          .loadString('assets/data/word_segments_mp3quran_afasy.json');
      final data = jsonDecode(brut) as Map<String, dynamic>;
      _parVerse = data.map((k, v) => MapEntry(
          k,
          (v as List)
              .map((paire) => (paire as List)
                  .map((n) => (n as num).toDouble())
                  .toList())
              .toList()));
      debugPrint('[Mp3Quran] segments mot-à-mot locaux chargés : '
          '${_parVerse!.length} versets');
    } catch (e) {
      debugPrint('[Mp3Quran] échec chargement segments locaux : $e');
      _parVerse = const {}; // asset absent -> repli silencieux
    } finally {
      _chargement = false;
    }
  }

  /// Segments `[début_ms, fin_ms]` par mot du verset [surah]:[ayah], ou null
  /// si non couvert. `ensureLoaded()` DOIT avoir été appelé avant (aucun
  /// chargement paresseux ici, pour rester synchrone comme
  /// `WordTimingService.msForVerse`).
  List<List<double>>? segmentsForVerse(int surah, int ayah) =>
      _parVerse?['$surah:$ayah'];
}
