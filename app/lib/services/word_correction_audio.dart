import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/reciter.dart';
import '../models/verse.dart';
import 'audio_player_service.dart';
import 'diagnostic_log.dart';
import 'mp3quran_api.dart';
import 'quran_api.dart';
import 'recitation_verifier.dart' show ArabicNormalizer;
import 'reciter_download_service.dart';

/// Lecteur audio DÉDIÉ à la correction automatique (demande utilisateur
/// 2026-07-05) — volontairement séparé du lecteur principal (`AudioPlayerService`,
/// singleton partagé par `PlayerNotifier`/Mushaf) : réutiliser ce singleton
/// déclencherait aussi la logique d'avance de playlist du lecteur principal
/// (`_onComplete` -> `_advance()`) sur un état (`playerState.playlist`) qui n'a
/// rien à voir avec la session de récitation en cours. Instance isolée, un
/// seul rôle : jouer UN verset et signaler la fin.
///
/// Réutilisée depuis 2026-07-24 par le moteur de répétition incrémentale du
/// Coach (`coach_incremental_repeat.dart`) pour jouer l'audio réel du
/// récitateur sur la fenêtre de mots en cours d'apprentissage -- malgré son
/// nom, [playWordRange] n'a rien de spécifique à la correction d'erreur,
/// c'est un lecteur générique "plage de mots" ; ne pas dupliquer ce
/// mécanisme ailleurs.
class WordCorrectionAudio {
  static final _player = AudioPlayer();

  /// ── UNE SEULE LECTURE VIVANTE A LA FOIS (2026-09-12) ───────────────────
  ///
  /// DEFAUT MESURE, scenario donne par l'utilisateur : lancer la memorisation
  /// par palier sur un verset, revenir en arriere, en lancer un autre -- plus
  /// aucun son ; recommencer -- et c'est l'audio du verset PRECEDENT qui
  /// part. Le journal le montre au milliseconde pres :
  ///
  ///     14:20:43.513  Correction-Audio  verset=33:1     <- demande 33:1
  ///     14:20:51.208  Correction-Audio  verset=33:5     <- demande 33:5
  ///     14:20:51.429  joue verset=33:1  reel=7577 ms  <-- PLUS COURT
  ///     14:21:06.764  Correction-Audio  verset=33:6
  ///     14:21:06.966  joue verset=33:5  reel=15754 ms <-- PLUS COURT
  ///     14:21:06.970  joue verset=33:5  reel=4458 ms  <-- PLUS COURT
  ///
  /// Deux lectures du MEME verset se terminent a 4 ms d'intervalle, et celle
  /// qui s'annonce est toujours celle d'avant.
  ///
  /// LA CAUSE N'EST PAS LE LECTEUR PARTAGE, c'est qu'une lecture SURVIT a
  /// l'ecran qui l'a lancee. Entre la demande et la fin il s'ecoule plusieurs
  /// secondes ; pendant ce temps `posSub`/`doneSub` restent abonnes au
  /// lecteur. Quand l'ecran suivant demarre sa propre lecture, les ecouteurs
  /// de l'ancienne recoivent les positions de la NOUVELLE, croient leur
  /// fenetre finie, et appellent `_player.pause()` -- ils coupent la lecture
  /// de quelqu'un d'autre, puis completent leur `Completer` et journalisent
  /// leur propre verset.
  ///
  /// `dispose()` appelle pourtant bien `stop()` cote ecran : ca n'aide pas,
  /// Flutter construit le nouvel ecran AVANT de detruire l'ancien, donc ce
  /// `stop()` arrive apres le `play()` du suivant et le coupe.
  ///
  /// POURQUOI PAS « UN LECTEUR PAR ECRAN » (question posee le 2026-09-12) :
  /// le scenario oppose deux fois le MEME usage, deux ecrans palier. Leur
  /// donner un lecteur chacun ne ferait pas taire l'ancien -- on entendrait
  /// les deux versets ensemble. Le silence deviendrait une cacophonie, la
  /// cause resterait. L'app dissocie deja par USAGE (Mushaf, duas, coran,
  /// corrections) et arbitre entre eux par `_faireTaireLeMushaf`.
  ///
  /// LE JETON. Chaque lecture prend un numero au demarrage ; toute lecture
  /// dont le numero n'est plus le courant est PERIMEE : elle se desabonne,
  /// ne touche jamais au lecteur, et n'ecrit aucun verdict. La derniere
  /// demandee gagne toujours. Meme mecanisme que la `generation` du micro
  /// (cf. `[CTL][Micro] ... generation=` dans les journaux).
  static int _generation = 0;

  /// Ouvre une lecture et rend son jeton. A appeler AVANT le premier
  /// `_player.stop()`/`play()`, pour que toute lecture deja en vol soit
  /// perimee des cet instant -- et cesse donc de pouvoir couper celle-ci.
  static int _nouvelleLecture() => ++_generation;

  /// Cette lecture a-t-elle ete supplantee ? Tout ce qui touche au lecteur ou
  /// journalise un verdict doit le demander d'abord.
  static bool _perimee(int jeton) => jeton != _generation;

  /// ── LE JETON NE PROTEGE PAS DE CE QUI N'A PAS ENCORE COMMENCE ───────────
  ///
  /// Compteur des ARRETS demandes, distinct de [_generation] et pour une
  /// raison precise : le jeton est pris JUSTE AVANT de toucher au lecteur,
  /// donc APRES toute la preparation (chargement du minutage, `ayatTiming`
  /// reseau, telechargement de la sourate entiere -- 4,5 a 9,2 s mesurees sur
  /// reseau degrade, cf. la doc de [prefetch]).
  ///
  /// CONSEQUENCE, ET C'EST LE DEFAUT : un [stop] demande PENDANT cette
  /// preparation n'annulait rien. La lecture finissait de se preparer, prenait
  /// alors un jeton TOUT NEUF -- elle devenait donc « la plus recente », jamais
  /// perimee -- et demarrait. L'ecran qui l'avait demandee n'existait plus.
  ///
  /// ET PLUS RIEN NE POUVAIT L'ARRETER : l'ecoute de position se retire sans
  /// toucher au lecteur des qu'elle se croit supplantee (c'est voulu, cf.
  /// `_generation`), et aucun autre `stop()` ne viendra puisque l'ecran est
  /// parti. Le fichier jouait donc jusqu'a sa fin -- la sourate entiere depuis
  /// la position demandee. Symptome utilisateur (2026-09-14) : « je suis sur
  /// audio, je passe directement au controle, l'audio continue ».
  ///
  /// Chaque lecture releve donc ce compteur A SON ENTREE et le revalide avant
  /// de toucher au lecteur : un arret survenu entre les deux l'annule.
  static int _arrets = 0;

  /// Un arret a-t-il ete demande depuis [marque] ? A demander en plus de
  /// [_perimee] : les deux repondent a des questions differentes -- « quelqu'un
  /// d'autre joue-t-il ? » et « m'a-t-on dit de me taire ? ».
  static bool _arreteDepuis(int marque) => _arrets != marque;
  /// ── LA CLE PORTE LE RECITATEUR, PAS SEULEMENT LA SOURATE (2026-09-06) ──
  ///
  /// Signale par l'audit (QUAL-04) et VERIFIE : ce cache etait indexe par le
  /// seul numero de sourate, alors qu'il est rempli par
  /// `QuranApi.fetchSurahAudioUrls(reciter.id, ...)`. Apres une correction avec
  /// le recitateur A, choisir B sur la meme sourate rejouait donc l'URL de A --
  /// la mauvaise voix, avec les minutages de B.
  ///
  /// ⚠️ CE DEFAUT ETAIT DORMANT, ET C'EST MOI QUI L'AI REVEILLE. Tant qu'un
  /// SEUL recitateur Hafs passait par quran.com (Al-Afasy), le cache ne pouvait
  /// rien melanger -- une seule voix, une seule URL par sourate. Les onze
  /// recitations quran.com ajoutees la veille l'ont rendu atteignable.
  ///
  /// La cle est donc `reciterId * 1000 + surah`. Les chemins everyayah et
  /// MP3Quran ne sont pas concernes : ils CONSTRUISENT leurs URL au lieu de les
  /// demander, donc rien n'y est mis en cache.
  static final _urlCache = <int, Map<String, String>>{};

  static int _cleUrl(int reciterId, int surah) => reciterId * 1000 + surah;
  static final _segmentsCache = <String, List<List<int>>>{};
  // Fichier MP3 local déjà téléchargé pour segKey ('${reciter.id}:${verse.key}')
  // -- le format (MP3, servi tel quel par verses.quran.com) n'est PAS le
  // problème : le convertir n'aurait réduit ni la taille (déjà compressé) ni
  // le principal coût mesuré (les DEUX appels réseau JSON de métadonnées
  // dans playWordRange, cf. `prefetch`). Le vrai levier est QUAND le
  // téléchargement a lieu : ici, l'audio lui-même est aussi précaché en local
  // pendant la récitation (avant toute erreur), pour que la lecture démarre
  // depuis le disque -- zéro dépendance réseau au moment de la correction --
  // plutôt que de streamer depuis `verses.quran.com` au moment précis où le
  // réseau peut être dégradé.
  static final _fileCache = <String, String>{};
  // Ordre d'insertion (LRU approximatif) -- borne le nombre de clips MP3
  // conservés sur disque pendant une longue session continue (chaque clip
  // fait quelques dizaines à ~200 Ko, pas de quoi remplir le stockage, mais
  // pas de raison d'accumuler indéfiniment sur une récitation de plusieurs
  // heures/sourates).
  static final _fileCacheOrder = <String>[];
  static const _kMaxCachedFiles = 12;
  static final _dio = Dio();

  /// Joue le mot fautif de [verse], entouré d'[wordsBefore] mots avant et
  /// [wordsAfter] mots après (par défaut 1 avant / 0 après = comportement de
  /// la correction automatique) — PAS tout le verset (demande utilisateur
  /// 2026-07-05 : "rester sur le mot en lui-même... ne pas continuer, c'est
  /// au réciteur de se souvenir de la suite"). [wordsBefore]/[wordsAfter]
  /// réglables (demande utilisateur 2026-07-06 : "choisir" combien de mots
  /// entourent le mot tapé, pour l'écoute manuelle). [errorWordIndex] est la
  /// position 0-based du mot fautif DANS ce verset. Découpe l'audio réel du
  /// récitateur au bon endroit grâce aux segments de timing officiels
  /// (`QuranApi.fetchAyahSegments`) plutôt que d'estimer une découpe
  /// approximative. Ne jette pas si l'audio ou le timing sont introuvables
  /// (retourne simplement immédiatement).
  /// Joue un fichier local ENTIER et attend la fin — sert à rejouer la VOIX DU
  /// RÉCITATEUR extraite du flux brut (2026-08-06, cf.
  /// `FastConformerCtcVerifier.v2ExtraitVoix`).
  ///
  /// Passe par le MÊME lecteur statique que [playWordRange] : les deux ne
  /// doivent jamais jouer en parallèle (un seul haut-parleur, et surtout un
  /// seul jeu d'abonnements — piège déjà payé le 2026-07-16 entre correction
  /// automatique et souffleur).
  /// Combien de temps au plus attendre la fin d'une lecture de [dureeMs].
  ///
  /// ── LE PLAFOND FIXE DE 15 s COUPAIT LES PALIERS (2026-08-18) ─────────────
  /// Les trois points de lecture bornaient l'attente à 15 s en dur. C'était
  /// juste tant que ce fichier ne servait qu'à faire réentendre UN mot
  /// (~2 s). Le coach « mémorisation par palier » rejoue, lui, toute la
  /// fenêtre CUMULATIVE depuis le premier mot du verset -- elle dépasse 15 s
  /// dès le deuxième palier.
  ///
  /// Mesuré sur 4:1 (An-Nisâ), récitateur Al-Afasy :
  ///     P1  6,6 s demandés -> 6,6 s joués
  ///     P2 17,1 s demandés -> 15 s   (coupé)
  ///     P3 26,5 s demandés -> 15 s   (coupé)
  ///     P4 36,0 s demandés -> 15 s   (coupé)
  /// À partir de P2, TOUS les paliers faisaient donc entendre exactement les
  /// mêmes 15 premières secondes -- constat utilisateur : « P3 c'est pareil
  /// que P2, on dirait P2 rejoué », « ça ne dit pas jusqu'à نِسَآءً ». La coupe
  /// tombait au milieu de `وَٰحِدَةٍ` (mot 8), très loin du mot 16.
  ///
  /// Le garde-fou reste nécessaire (lecteur bloqué, fichier corrompu) : il
  /// devient simplement PROPORTIONNEL, avec une marge pour l'ouverture du
  /// fichier et le positionnement, et un plancher pour les extraits courts.
  static Duration _plafondLecture(int dureeMs) => Duration(
      milliseconds: dureeMs <= 0 ? 15000 : (dureeMs + 5000).clamp(15000, 180000));

  /// Fait taire le lecteur PRINCIPAL avant de jouer un extrait.
  ///
  /// ── LE COUPLAGE ETAIT A SENS UNIQUE (2026-08-19) ─────────────────────────
  /// Ce fichier a son propre `AudioPlayer`, « volontairement separe du lecteur
  /// principal » (cf. l'en-tete). `PlayerNotifier.stop()` appelle bien
  /// `WordCorrectionAudio.stop()` -- le Mushaf fait taire les extraits, au nom
  /// du « un seul son a la fois dans l'app ». Mais L'INVERSE N'EXISTAIT PAS :
  /// un extrait ou un palier demarrait par-dessus une lecture du Mushaf
  /// encore en cours.
  ///
  /// Constat utilisateur (2026-08-19) : « dans la memorisation coach, j'ai
  /// l'impression qu'elle lance parfois la lecture du Mushaf la ou il y a le
  /// curseur -- il y a un chevauchement de code ». C'est exactement ca : deux
  /// lecteurs, deux flux, et le meme fichier de sourate ouvert des deux cotes.
  ///
  /// Le cas se produit des que l'etape Lecture est quittee autrement que par
  /// son bouton (glissement, retour, changement de mode) : ce bouton-la est le
  /// SEUL endroit qui appelait `playerProvider.stop()`.
  ///
  /// `pause()` et non `stop()` : le Mushaf garde sa position, l'utilisateur
  /// reprend ou il en etait apres la correction.
  static Future<void> _faireTaireLeMushaf() async {
    try {
      await AudioPlayerService().pause();
    } catch (_) {
      // Best-effort : un lecteur principal jamais demarre n'est pas une erreur.
    }
  }

  static Future<void> playFile(String path) async {
    final jeton = _nouvelleLecture();
    DiagnosticLog.log('Voix', 'lecture extrait : $path');
    await _player.stop();
    final completer = Completer<void>();
    late final StreamSubscription doneSub;
    doneSub = _player.onPlayerComplete.listen((_) {
      doneSub.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    if (_perimee(jeton)) {
      // Supplantee entre-temps : on rend la main sans jouer. Ne pas appeler
      // `stop()` ici -- ce serait couper la lecture de celui qui nous a
      // remplaces, le defaut meme que ce jeton corrige.
      doneSub.cancel();
      return;
    }
    await _player.play(DeviceFileSource(path));
    // Garde-fou : un extrait fait au plus quelques secondes. Sans borne, une
    // fin de lecture jamais notifiée laisserait le bouton bloqué.
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      doneSub.cancel();
    });
  }

  /// Rend `true` si un extrait a REELLEMENT ete joue (2026-08-18) : les
  /// abandons (minutage absent, index hors bornes, reseau) etaient muets, et
  /// le palier enchainait alors sans faire entendre le recitateur.
  static Future<bool> playWordRange(
    Verse verse,
    Reciter reciter, {
    required int errorWordIndex,
    /// Fraction de la duree jouee (1.0 = tout). Demande utilisateur
    /// 2026-08-07 : « l'audio de repetition est un peu long, reduis de 20 % ».
    /// On rogne la FIN, jamais le debut : c'est le depart du passage qui
    /// permet de le reconnaitre. Plancher a 800 ms pour ne pas rendre un
    /// souffle inaudible sur une plage deja courte.
    double facteurDuree = 1.0,
    int wordsBefore = 1,
    int wordsAfter = 0,
  }) async {
    // Releve AVANT toute attente : c'est le point de comparaison qui dira si
    // un `stop()` est arrive pendant la preparation (cf. `_arrets`).
    final marqueArret = _arrets;
    // ── CHEMIN LOCAL MP3QURAN, SANS QURAN FOUNDATION (2026-08-16) ───────────
    //
    // Pour Al-Afasy (seul récitateur MP3Quran de l'app à ce jour), le
    // minutage mot à mot est calculé HORS LIGNE une fois pour toutes
    // (`benchmark/generer_predictions_mp3quran.py`, aucune dépendance QF dans
    // sa génération) et embarqué comme asset -- plus jamais d'appel réseau à
    // `fetchAyahSegments`/`fetchSurahAudioUrls` pour ce récitateur. Décision
    // utilisateur du même jour : jeu de données précalculé plutôt qu'un
    // alignement à la demande sur l'appareil (qui toucherait `ForcedAligner.kt`
    // et la chaîne ASR -- hors périmètre validé aujourd'hui).
    if (Mp3QuranApi.sertCeReciter(reciter.id)) {
      // Le RÉSULTAT du chemin MP3Quran est celui de cette méthode -- il a été
      // perdu une fois (2026-08-18) en transformant en bloc les `return;` de
      // ce fichier : la lecture réussissait, `false` remontait quand même, le
      // palier retentait et l'utilisateur entendait l'audio DEUX FOIS avant
      // de lire « ABSENT » au journal. Une délégation rend ce qu'elle délègue.
      return _playWordRangeMp3Quran(verse, reciter,
          errorWordIndex: errorWordIndex,
          facteurDuree: facteurDuree,
          wordsBefore: wordsBefore,
          wordsAfter: wordsAfter);
    }
    final segKey = '${reciter.id}:${verse.key}';
    // ── AUDIO TÉLÉCHARGÉ D'ABORD (2026-08-01) ─────────────────────────────
    // AVANT : ce service appelait `fetchSurahAudioUrls` (RÉSEAU) en tout
    // premier et abandonnait en silence sur `url == null` -- même quand le
    // récitateur avait DÉJÀ téléchargé la sourate. Symptôme rapporté par
    // l'utilisateur : « les deux corrections sont activées, je fais des
    // erreurs, je n'entends aucun audio » -- aucune erreur affichée, aucune
    // trace, d'où l'impression que « les audios ne sont plus là ».
    // Le lecteur du Mushaf (`audio_player_service.dart`) consultait pourtant
    // déjà `ReciterDownloadService.localPathIfPresent` ; ce service, lui, ne
    // connaissait que son propre cache MÉMOIRE de session (`_fileCache`,
    // rempli par `prefetch`), perdu à chaque redémarrage.
    // Demande explicite : « favoriser les audios qui sont en local au lieu de
    // chercher par API ».
    final telecharge = ReciterDownloadService().localPathIfPresent(reciter.id, verse);
    String? url;
    if (telecharge == null) {
      // ── WARSH : l'URL se déduit, elle ne se demande pas (2026-08-12) ──────
      // everyayah nomme ses fichiers `SSSAAA.mp3` avec les mêmes numéros de
      // verset que l'app : aucun appel réseau de métadonnées, donc aucun des
      // 4,5 à 9,2 s d'attente que le préchauffage existe pour éviter côté
      // Hafs. Le chemin Hafs ci-dessous n'est pas touché.
      // ⚠️ ETAIT `!reciter.aSegmentsQuranCom` JUSQU'AU 2026-09-05.
      // Deux choses confondues parce qu'elles coincidaient : la riwaya, et
      // « ce recitateur a-t-il des URL et des segments chez quran.com ? ».
      // Vrai tant que les seuls recitateurs hors quran.com etaient les deux
      // Warsh ; faux des qu'Ayman Suwaid arrive -- Hafs, absent de quran.com.
      // Teste sur la riwaya, il serait alle demander une URL pour un
      // identifiant inconnu et n'aurait produit aucun son. Cf.
      // `Reciter.aSegmentsQuranCom`. Le comportement des Warsh est INCHANGE :
      // ils ont tous un id negatif, donc le meme cote du test qu'avant.
      // (Le meme remplacement s'applique aux deux autres sites de ce fichier.)
      if (!reciter.aSegmentsQuranCom) {
        url = reciter.urlVerset(verse.surahNumber, verse.ayahNumber);
      } else {
      _urlCache[_cleUrl(reciter.id, verse.surahNumber)] ??=
          await QuranApi.fetchSurahAudioUrls(reciter.id, verse.surahNumber);
      url = _urlCache[_cleUrl(reciter.id, verse.surahNumber)]?[verse.key];
      }
      if (url == null) {
        // Journalisé : cet abandon était MUET, ce qui rendait la panne
        // indiagnosticable côté utilisateur comme côté log.
        DiagnosticLog.log('Correction-Audio',
            'ABANDON verset=${verse.key} : aucun fichier local ET aucune URL '
            '(réseau indisponible ou récitateur ${reciter.id} sans audio) '
            '-> pas de correction audible');
        return false;
      }
    }

    // ── TIMINGS : mesurés en Hafs, ESTIMÉS en Warsh (2026-08-12) ───────────
    // quran.com ne publie de segments mot-à-mot que pour ses propres
    // récitateurs, tous Hafs. Sans eux, la correction Warsh serait purement
    // et simplement muette (l'abandon ci-dessous) -- or c'est précisément la
    // fonction demandée : « en cas d'erreur, c'est l'audio du mot avec la
    // prononciation Warsh ». On estime donc la découpe, en le DISANT dans le
    // journal : une estimation qu'on prend pour une mesure est un piège, une
    // estimation nommée est un point de départ mesurable.
    // À remplacer par de vrais timings dès qu'on fera passer l'aligneur forcé
    // du modèle sur l'audio Warsh -- c'est l'outil exact pour les produire.
    final segments = _segmentsCache[segKey] ??= !reciter.aSegmentsQuranCom
        ? await _segmentsEstimes(verse, telecharge, url)
        : await QuranApi.fetchAyahSegments(reciter.id, verse.key);
    // Pas de timing dispo pour ce récitateur/verset -> on abandonne plutôt
    // que de rejouer tout le verset par défaut (contredirait la demande).
    // Journalisé depuis le 2026-08-01 : SECOND point d'abandon muet, et
    // second appel réseau -- avoir le MP3 en local ne suffit donc pas encore,
    // il faut aussi ces timings (mis en cache mémoire seulement). Si cette
    // ligne apparaît souvent dans les logs, c'est ici qu'il faudra
    // persister/embarquer les segments.
    if (segments.isEmpty) {
      DiagnosticLog.log('Correction-Audio',
          'ABANDON verset=${verse.key} : timings mot-à-mot indisponibles '
          '(récitateur ${reciter.id}) -> pas de correction audible');
      return false;
    }

    final fromIdx =
        (errorWordIndex - wordsBefore).clamp(0, errorWordIndex);
    final toIdx = errorWordIndex + wordsAfter;
    final startSeg = segments.firstWhere((s) => s[0] == fromIdx,
        orElse: () => segments.first);
    final endSeg = segments.firstWhere((s) => s[0] == toIdx,
        orElse: () => segments.last);
    final startMs = startSeg[2];
    var endMs = endSeg[3];
    if (facteurDuree < 1.0 && endMs > startMs) {
      final pleine = endMs - startMs;
      final reduite = (pleine * facteurDuree).round();
      endMs = startMs + (reduite < 800 ? (pleine < 800 ? pleine : 800) : reduite);
    }
    // Priorité : (1) sourate TÉLÉCHARGÉE par l'utilisateur, (2) précache
    // mémoire de la session (cf. `prefetch`), (3) streaming direct.
    // (1) est nouveau (2026-08-01) -- cf. commentaire en tête de fonction.
    // Ne JAMAIS attendre un téléchargement ici, ce serait aussi lent que
    // l'ancien chemin.
    final localPath = telecharge ?? _fileCache[segKey];
    final source =
        localPath != null ? DeviceFileSource(localPath) : UrlSource(url!);
    DiagnosticLog.log('Correction-Audio', 'verset=${verse.key} '
        'errorWordIndex=$errorWordIndex (mot attendu local) '
        'fromIdx=$fromIdx toIdx=$toIdx '
        'startSeg=$startSeg endSeg=$endSeg '
        'startMs=$startMs endMs=$endMs '
        'source=${telecharge != null ? "telecharge($telecharge)" : localPath != null ? "precache($localPath)" : "url($url)"}');

    // Jeton de cette lecture (cf. `_generation`) : pris avant tout appel au
    // lecteur, pour perimer ce qui serait encore en vol.
    final jeton = _nouvelleLecture();
    final completer = Completer<void>();
    late final StreamSubscription posSub;
    late final StreamSubscription doneSub;
    void finish() {
      posSub.cancel();
      doneSub.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    // ── IGNORER LA POSITION PÉRIMÉE DU LECTEUR (2026-08-18) ──────────────
    //
    // DÉFAUT MESURÉ, rendu visible par le traçage ajouté le même jour :
    //     joue verset=4:1 mots=0..23 demande=37040 ms reel=2 ms
    // Le rejeu après échec ne faisait entendre STRICTEMENT RIEN.
    //
    // `audioplayers` continue d'émettre la DERNIÈRE position connue (ici
    // ~50520 ms, là où la lecture précédente s'était arrêtée) pendant le
    // court instant où le repositionnement n'a pas encore pris effet. Le test
    // `pos >= endMs` était donc vrai immédiatement, et la lecture se coupait
    // avant d'avoir commencé.
    //
    // `amorce` n'autorise le test de fin qu'une fois qu'une position est
    // réellement tombée DANS la fenêtre demandée -- c'est-à-dire une fois que
    // le repositionnement a été observé, pas supposé.
    var amorce = false;
    posSub = _player.onPositionChanged.listen((pos) {
      // Perimee : se retirer sans toucher au lecteur (cf. `_generation`).
      if (_perimee(jeton)) {
        finish();
        return;
      }
      if (!amorce) {
        if (pos.inMilliseconds < endMs) amorce = true;
        return;
      }
      if (pos.inMilliseconds >= endMs) {
        _player.pause();
        finish();
      }
    });
    doneSub = _player.onPlayerComplete.listen((_) => finish());

    await _faireTaireLeMushaf();
    // ── UN ARRET PENDANT LA PREPARATION ANNULE CETTE LECTURE (2026-09-14) ──
    // Sans ce garde, la lecture demarrait APRES le `stop()` qui la visait, et
    // plus rien ne pouvait l'arreter. Cf. `_arrets` pour le detail.
    if (_arreteDepuis(marqueArret)) {
      finish();
      DiagnosticLog.log('Correction-Audio',
          'verset=${verse.key} : lecture ANNULEE avant de commencer '
          '(arret demande pendant la preparation)');
      return false;
    }
    final depart = DateTime.now();
    // `stop()` d'abord : remet la position du lecteur à zéro pour qu'aucun
    // événement de l'ancienne lecture ne puisse être pris pour la nouvelle.
    await _player.stop();
    // Re-demande apres CHAQUE attente : `stop()` et `play()` sont deux appels
    // de plateforme, l'arret peut tomber entre les deux.
    if (_arreteDepuis(marqueArret) || _perimee(jeton)) {
      finish();
      return false;
    }
    await _player.play(source, position: Duration(milliseconds: startMs));
    // Garde-fou : si ni la position ni la fin de lecture ne se déclenchent
    // (URL corrompue, lecteur bloqué), ne pas bloquer la reprise indéfiniment.
    // PROPORTIONNEL depuis le 2026-08-18, cf. `_plafondLecture` -- le plafond
    // fixe coupait les paliers longs de la mémorisation.
    await completer.future.timeout(_plafondLecture(endMs - startMs), onTimeout: () {
      posSub.cancel();
      doneSub.cancel();
      if (!_perimee(jeton)) _player.pause();
      DiagnosticLog.log('Correction-Audio',
          'TRONQUE par le garde-fou : demande=${endMs - startMs} ms '
          'verset=${verse.key}');
    });
    final jouees = DateTime.now().difference(depart).inMilliseconds;
    if (_perimee(jeton)) {
      // Supplantee : son verdict mentirait sur ce qui a ete entendu -- c'est
      // cette ligne-la qui annoncait « joue verset=33:1 » pendant que 33:5
      // jouait (cf. `_generation`). On le dit, sans pretendre avoir joue.
      DiagnosticLog.log('Correction-Audio',
          'verset=${verse.key} : lecture SUPPLANTEE apres $jouees ms '
          '-- aucun verdict');
      return false;
    }
    DiagnosticLog.log('Correction-Audio',
        'joue verset=${verse.key} demande=${endMs - startMs} ms '
        'reel=$jouees ms '
        '${jouees + 400 < endMs - startMs ? "<-- PLUS COURT QUE DEMANDE" : "ok"}');
    return true;
  }

  /// Variante MP3Quran de [playWordRange] : source et minutage 100% locaux.
  ///
  /// ── DEUX REPÈRES À COMBINER, PAS UN SEUL ─────────────────────────────────
  /// `Mp3QuranWordSegments` donne le minutage mot à mot RELATIF au verset
  /// isolé (c'est ainsi qu'il a été calculé, cf. son commentaire de tête).
  /// Mais l'audio réellement joué ici est le fichier de la SOURATE ENTIÈRE
  /// (`Mp3QuranApi.fichierLocalSourate`, le même que `AudioPlayerService`
  /// utilise pour l'écoute au Mushaf -- un seul téléchargement sert les deux
  /// fonctions). Il faut donc ADDITIONNER le début absolu du verset dans ce
  /// fichier (`Mp3QuranApi.ayatTiming`) aux décalages relatifs de chaque mot
  /// -- l'erreur classique (déjà rencontrée deux fois dans ce chantier, cf.
  /// `PLAN_SORTIE.md` §4 et l'audit du 2026-08-16) est d'utiliser l'un sans
  /// l'autre.
  static Future<bool> _playWordRangeMp3Quran(
    Verse verse,
    Reciter reciter, {
    required int errorWordIndex,
    required double facteurDuree,
    required int wordsBefore,
    required int wordsAfter,
  }) async {
    // Releve AVANT toute attente (cf. `_arrets`) : ce chemin attend le
    // minutage local, `ayatTiming` en reseau, PUIS le telechargement de la
    // sourate entiere. C'est la fenetre la plus large du fichier.
    final marqueArret = _arrets;
    // ── CES SEGMENTS SONT CEUX D'AL-AFASY, ET DE LUI SEUL (2026-09-05) ───
    //
    // `word_segments_mp3quran_afasy.json` a ete calcule par alignement force
    // SUR SON ENREGISTREMENT. Depuis que MP3Quran sert six recitations de
    // plus, ce chemin serait traverse par des voix pour lesquelles ces
    // minutages ne veulent rien dire : l'app jouerait un extrait pris au
    // mauvais endroit, sans que rien ne le signale.
    //
    // On abandonne donc -- l'utilisateur n'entend pas de correction mot a mot
    // sur ces recitateurs, ce qui est honnete, plutot que d'entendre le
    // mauvais mot, ce qui ne l'est pas. Socle n°1 : mieux vaut pas de verdict
    // qu'un verdict faux, et c'est vrai aussi de l'audio.
    //
    // POUR LEVER CETTE LIMITE : refaire tourner l'aligneur force sur leur
    // audio et livrer un asset par recitateur -- exactement ce qui a ete fait
    // pour Afasy en aout (6 236 versets, 77 433 mots).
    // ── GARDE RETIRE LE 2026-09-06, SUR UN ARGUMENT DE L'UTILISATEUR ─────
    //
    // J'avais pose ici un abandon pur : « segments d'Afasy, donc pas de
    // correction sur les autres voix ». L'utilisateur l'a leve, et son
    // raisonnement corrige le mien : « le mot a mot n'est pas vraiment mot a
    // mot, on rajoute un peu, du coup ca retombe sur le mot ».
    //
    // C'est exact, et pour deux raisons qui se cumulent. D'abord l'extrait
    // n'est jamais un mot isole : `wordsBefore`/`wordsAfter` et
    // `etendreAuxMotsContigusEnErreur` l'elargissent deja aux voisins, donc
    // une bordure approximative reste dans la plage jouee. Ensuite l'erreur
    // est BORNEE AU VERSET : les segments sont RELATIFS au verset et se
    // combinent au debut ABSOLU donne par `ayatTiming`, qui est desormais
    // celui du bon recitateur -- rien ne se cumule d'un verset au suivant.
    //
    // CE QUI RESTE VRAI, et qu'il faut savoir : la position du mot DANS le
    // verset vient d'Al-Afasy. Sur un mujawwad, beaucoup plus lent, l'extrait
    // peut tomber a cote sur un verset long. Si ca gene, la correction tient
    // en une mise a l'echelle des segments par le rapport des durees de
    // verset -- les deux valeurs sont deja disponibles ici.
    await Mp3QuranWordSegments.instance.ensureLoaded();
    final segments = Mp3QuranWordSegments.instance
        .segmentsForVerse(verse.surahNumber, verse.ayahNumber);

    final fromIdx = (errorWordIndex - wordsBefore).clamp(0, errorWordIndex);
    final toIdx = errorWordIndex + wordsAfter;

    // Verset non couvert, ou l'index visé dépasse ce que le minutage local
    // connaît (texte re-découpé différemment, cf. l'avertissement de
    // `Mp3QuranWordSegments`) -- abandon SANS retomber sur Quran Foundation :
    // c'est précisément la dépendance que ce chemin existe pour supprimer.
    // Même discipline de log que le chemin quran.com ci-dessus.
    if (segments == null || toIdx >= segments.length || fromIdx < 0) {
      DiagnosticLog.log('Correction-Audio',
          'ABANDON (MP3Quran) verset=${verse.key} : minutage local absent ou '
          'index hors bornes (fromIdx=$fromIdx toIdx=$toIdx '
          'segments=${segments?.length}) -> pas de correction audible');
      return false;
    }

    final List<AyahTiming> timing;
    final String path;
    try {
      timing = await Mp3QuranApi.ayatTiming(verse.surahNumber, read: Mp3QuranApi.readPour(reciter.id) ?? 123);
      path = await Mp3QuranApi.fichierLocalSourate(
          reciter.id, verse.surahNumber);
    } catch (e) {
      DiagnosticLog.log('Correction-Audio',
          'ABANDON (MP3Quran) verset=${verse.key} : $e');
      return false;
    }
    AyahTiming? t;
    for (final e in timing) {
      if (e.ayah == verse.ayahNumber) {
        t = e;
        break;
      }
    }
    if (t == null) {
      DiagnosticLog.log('Correction-Audio',
          'ABANDON (MP3Quran) verset=${verse.key} : verset absent de ayat_timing');
      return false;
    }

    // ── LES SEGMENTS D'AFASY, MIS A L'ECHELLE DU RECITATEUR ──────────────
    // (2026-09-06, idee de l'utilisateur : « en prenant comme reference le
    // timing de l'autre recitateur »)
    //
    // Les segments viennent d'Al-Afasy et sont RELATIFS au verset. Sur un
    // mujawwad, beaucoup plus lent, le mot 12 d'un verset ne tombe pas au meme
    // instant : plus le verset est long, plus l'ecart grandit. Le rapport des
    // DUREES DE VERSET donne exactement le facteur qui les recale -- les deux
    // valeurs viennent de la meme API, chacune pour sa voix.
    //
    // POURQUOI CA SUFFIT LA PLUPART DU TEMPS : l'erreur qui reste est celle du
    // RYTHME INTERNE (une pause plus longue ici, une lettre tenue la), pas
    // celle du debit global -- et l'extrait joue est deja elargi aux voisins,
    // donc elle retombe sur le mot. C'est le geste le moins cher qui traite
    // l'essentiel ; l'alignement force sur l'audio reel (`v2AnalyserWav`
    // existe deja) reste la voie exacte, mais il demande de decoder le MP3 en
    // PCM 16 kHz sur l'appareil, ce que rien ne sait faire ici aujourd'hui.
    //
    // Facteur borne a [0,5 ; 2,5] : au-dela, c'est que l'un des deux minutages
    // est faux, et mieux vaut un extrait non recale qu'un extrait projete
    // n'importe ou. Le facteur est journalise pour qu'on puisse le lire.
    var echelle = 1.0;
    if (reciter.id != 7) {
      try {
        final refAfasy = await Mp3QuranApi.ayatTiming(verse.surahNumber, read: 123);
        for (final e in refAfasy) {
          if (e.ayah != verse.ayahNumber) continue;
          final dRef = e.endMs - e.startMs;
          final dIci = t.endMs - t.startMs;
          if (dRef > 500 && dIci > 500) {
            echelle = (dIci / dRef).clamp(0.5, 2.5);
          }
          break;
        }
      } catch (e) {
        DiagnosticLog.log('Correction-Audio',
            'echelle NON APPLIQUEE verset=${verse.key} : $e '
            '-> segments d Afasy tels quels');
      }
    }

    final debutAbsoluVerset = t.startMs;
    final startMs =
        debutAbsoluVerset + (segments[fromIdx][0] * echelle).round();
    var endMs = debutAbsoluVerset + (segments[toIdx][1] * echelle).round();
    if (facteurDuree < 1.0 && endMs > startMs) {
      final pleine = endMs - startMs;
      final reduite = (pleine * facteurDuree).round();
      endMs = startMs + (reduite < 800 ? (pleine < 800 ? pleine : 800) : reduite);
    }

    DiagnosticLog.log('Correction-Audio', 'verset=${verse.key} (MP3Quran) '
        'errorWordIndex=$errorWordIndex fromIdx=$fromIdx toIdx=$toIdx '
        'startMs=$startMs endMs=$endMs echelle=${echelle.toStringAsFixed(2)} '
        'source=$path');

    // Jeton de cette lecture (cf. `_generation`) : pris avant tout appel au
    // lecteur, pour perimer ce qui serait encore en vol.
    final jeton = _nouvelleLecture();
    final completer = Completer<void>();
    late final StreamSubscription posSub;
    late final StreamSubscription doneSub;
    void finish() {
      posSub.cancel();
      doneSub.cancel();
      if (!completer.isCompleted) completer.complete();
    }

    // ── IGNORER LA POSITION PÉRIMÉE DU LECTEUR (2026-08-18) ──────────────
    //
    // DÉFAUT MESURÉ, rendu visible par le traçage ajouté le même jour :
    //     joue verset=4:1 mots=0..23 demande=37040 ms reel=2 ms
    // Le rejeu après échec ne faisait entendre STRICTEMENT RIEN.
    //
    // `audioplayers` continue d'émettre la DERNIÈRE position connue (ici
    // ~50520 ms, là où la lecture précédente s'était arrêtée) pendant le
    // court instant où le repositionnement n'a pas encore pris effet. Le test
    // `pos >= endMs` était donc vrai immédiatement, et la lecture se coupait
    // avant d'avoir commencé.
    //
    // `amorce` n'autorise le test de fin qu'une fois qu'une position est
    // réellement tombée DANS la fenêtre demandée -- c'est-à-dire une fois que
    // le repositionnement a été observé, pas supposé.
    var amorce = false;
    posSub = _player.onPositionChanged.listen((pos) {
      // Perimee : se retirer sans toucher au lecteur (cf. `_generation`).
      if (_perimee(jeton)) {
        finish();
        return;
      }
      if (!amorce) {
        if (pos.inMilliseconds < endMs) amorce = true;
        return;
      }
      if (pos.inMilliseconds >= endMs) {
        _player.pause();
        finish();
      }
    });
    doneSub = _player.onPlayerComplete.listen((_) => finish());

    await _faireTaireLeMushaf();
    // Même garde que le chemin quran.com (2026-09-14) : ce chemin-ci est le
    // plus exposé, il télécharge la sourate entière avant de jouer.
    if (_arreteDepuis(marqueArret)) {
      finish();
      DiagnosticLog.log('Correction-Audio',
          'verset=${verse.key} (MP3Quran) : lecture ANNULEE avant de commencer '
          '(arret demande pendant la preparation)');
      return false;
    }
    final depart = DateTime.now();
    // `stop()` d'abord, même raison que le chemin quran.com ci-dessus.
    await _player.stop();
    if (_arreteDepuis(marqueArret) || _perimee(jeton)) {
      finish();
      return false;
    }
    await _player.play(DeviceFileSource(path),
        position: Duration(milliseconds: startMs));
    // Même garde-fou que le chemin quran.com : ne jamais bloquer indéfiniment
    // si ni la position ni la fin de lecture ne se déclenchent. PROPORTIONNEL
    // depuis le 2026-08-18, cf. `_plafondLecture`.
    await completer.future.timeout(_plafondLecture(endMs - startMs), onTimeout: () {
      posSub.cancel();
      doneSub.cancel();
      if (!_perimee(jeton)) _player.pause();
      // Une troncature ne doit JAMAIS être silencieuse : c'est elle qui a
      // fait passer quatre paliers pour le même audio sans laisser de trace.
      DiagnosticLog.log('Correction-Audio',
          'TRONQUE par le garde-fou : demande=${endMs - startMs} ms '
          'verset=${verse.key} mots=$fromIdx..$toIdx');
    });
    // Ce qui a RÉELLEMENT été joué, à chaque palier et à chaque répétition
    // (demande utilisateur 2026-08-18 : « fais du traçage de log »).
    final jouees = DateTime.now().difference(depart).inMilliseconds;
    if (_perimee(jeton)) {
      // Supplantee : son verdict mentirait sur ce qui a ete entendu -- c'est
      // cette ligne-la qui annoncait « joue verset=33:1 » pendant que 33:5
      // jouait (cf. `_generation`). On le dit, sans pretendre avoir joue.
      DiagnosticLog.log('Correction-Audio',
          'verset=${verse.key} : lecture SUPPLANTEE apres $jouees ms '
          '-- aucun verdict');
      return false;
    }
    DiagnosticLog.log('Correction-Audio',
        'joue verset=${verse.key} mots=$fromIdx..$toIdx '
        'demande=${endMs - startMs} ms reel=$jouees ms '
        '${jouees + 400 < endMs - startMs ? "<-- PLUS COURT QUE DEMANDE" : "ok"}');
    return true;
  }

  /// Découpe ESTIMÉE d'un verset en mots, au format des segments de
  /// `QuranApi.fetchAyahSegments` (`[indexMot, _, debutMs, finMs]`), pour les
  /// récitations dont personne ne publie de timings mesurés — aujourd'hui les
  /// récitateurs Warsh (2026-08-12).
  ///
  /// Pondérée par la LONGUEUR des mots, pas uniforme : un découpage à parts
  /// égales placerait `وَٱلَّذِينَ` et `مَا` sur la même durée, et l'erreur
  /// s'accumulerait jusqu'à la fin du verset. Le nombre de lettres est un
  /// mauvais prédicteur de durée pris isolément, mais un bon prédicteur
  /// RELATIF entre deux mots du même verset, dit par la même voix.
  ///
  /// Reste une estimation : la plage jouée peut déborder d'une syllabe sur le
  /// mot voisin. C'est assumé — l'alternative était de ne rien faire entendre.
  static Future<List<List<int>>> _segmentsEstimes(
      Verse verse, String? cheminLocal, String? url) async {
    final mots = ArabicNormalizer.splitExpectedWords(verse.textUthmani);
    if (mots.isEmpty) return const [];

    // Durée réelle du fichier : sans elle on n'estime rien du tout. Un
    // lecteur dédié et jetable — surtout pas `_player`, qui est peut-être en
    // train de jouer la correction précédente.
    final sonde = AudioPlayer();
    Duration? duree;
    try {
      if (cheminLocal != null) {
        await sonde.setSource(DeviceFileSource(cheminLocal));
      } else if (url != null) {
        await sonde.setSource(UrlSource(url));
      } else {
        return const [];
      }
      duree = await sonde.getDuration();
    } catch (e) {
      DiagnosticLog.log('Correction-Audio',
          'estimation impossible verset=${verse.key} : $e');
    } finally {
      await sonde.dispose();
    }
    if (duree == null || duree.inMilliseconds <= 0) return const [];

    final poids = [
      for (final m in mots) ArabicNormalizer.normalize(m).length.clamp(1, 99)
    ];
    final total = poids.fold<int>(0, (s, p) => s + p);
    final segments = <List<int>>[];
    var curseur = 0;
    for (var i = 0; i < mots.length; i++) {
      final part = (duree.inMilliseconds * poids[i] / total).round();
      final fin = i == mots.length - 1 ? duree.inMilliseconds : curseur + part;
      segments.add([i, i, curseur, fin]);
      curseur = fin;
    }
    DiagnosticLog.log('Correction-Audio',
        'timings ESTIMES (Warsh) verset=${verse.key} mots=${mots.length} '
        'duree=${duree.inMilliseconds}ms -- decoupe ponderee, non mesuree');
    return segments;
  }

  /// Joue exactement les mots [startWordIdx]..[endWordIdx] (inclus) --
  /// wrapper de lisibilité au-dessus de [playWordRange] pour le moteur de
  /// répétition incrémentale (fenêtre de mots à apprendre), qui n'a pas de
  /// notion de "mot fautif" mais veut une plage explicite.
  /// ── JOUER UNE PLAGE, PAS UN INDEX DE MOT (2026-09-06) ──────────────────
  ///
  /// L'ECART QUE CECI SUPPRIME est signale depuis le 2026-08-27, et le
  /// commentaire de `coach_incremental_repeat` le disait sans pouvoir
  /// conclure : « il y a toujours un ecart dans la memorisation par palier
  /// entre l'audio qui recite et le texte [...] la cause restante n'est donc
  /// pas decidable depuis le code seul ».
  ///
  /// Elle l'est. `playWordWindow` prend des INDEX de mots, puis va rechercher
  /// les millisecondes AILLEURS -- dans les segments d'Al-Afasy, ou dans
  /// l'estimation ponderee en Warsh. Le texte etait donc coupe d'apres une
  /// source et l'audio d'apres une autre. Deux nombres qui ne parlaient pas de
  /// la meme chose.
  ///
  /// Diagnostic de l'utilisateur, mot pour mot : « ta methode genere des ecarts
  /// entre texte et audio, oublie les 6 mots ». Repasser par l'index, c'est
  /// ressortir chercher le temps ailleurs -- il faut garder les millisecondes
  /// que l'alignement vient de produire.
  ///
  /// Cette methode joue donc une plage BRUTE d'un fichier local. Elle ne
  /// consulte aucun minutage, aucune estimation, aucun segment : les bornes
  /// qu'on lui donne sont les bornes qu'elle joue. C'est a l'appelant de les
  /// tenir de la meme mesure que le texte qu'il affiche -- et c'est exactement
  /// ce que `DecoupeAudioService` lui fournit.
  static Future<bool> playRangeMs(
    String path,
    int startMs,
    int endMs, {
    String etiquette = '',
  }) async {
    if (endMs <= startMs) return false;
    final marqueArret = _arrets;
    final jeton = _nouvelleLecture();
    DiagnosticLog.log('Correction-Audio',
        'plage MESUREE $etiquette : startMs=$startMs endMs=$endMs '
        '(duree=${endMs - startMs} ms) source=$path');

    final completer = Completer<void>();
    late final StreamSubscription posSub;
    late final StreamSubscription doneSub;
    void finish() {
      posSub.cancel();
      doneSub.cancel();
      if (!completer.isCompleted) completer.complete();
    }
    // `amorce` : meme garde qu'ailleurs dans ce fichier -- `audioplayers`
    // continue d'emettre la DERNIERE position connue tant que le
    // repositionnement n'a pas pris effet, et le test de fin serait vrai
    // immediatement. Cf. le defaut du 2026-08-18, qui ne faisait plus rien
    // entendre du tout.
    var amorce = false;
    posSub = _player.onPositionChanged.listen((pos) {
      // Perimee : on se retire SANS toucher au lecteur. Sans ce garde, cette
      // lecture-ci lisait les positions de la SUIVANTE, croyait sa fenetre
      // finie, et la mettait en pause -- le silence signale le 2026-09-12.
      if (_perimee(jeton)) {
        finish();
        return;
      }
      if (!amorce) {
        if (pos.inMilliseconds < endMs) amorce = true;
        return;
      }
      if (pos.inMilliseconds >= endMs) {
        _player.pause();
        finish();
      }
    });
    doneSub = _player.onPlayerComplete.listen((_) => finish());

    await _faireTaireLeMushaf();
    final depart = DateTime.now();
    if (_perimee(jeton) || _arreteDepuis(marqueArret)) {
      // Supplantee pendant l'attente ci-dessus : ne rien jouer, et surtout ne
      // pas arreter le lecteur -- il appartient desormais a la lecture qui
      // nous a remplaces.
      // `_arreteDepuis` depuis le 2026-09-14 : un `stop()` peut aussi etre
      // tombe ici sans qu'aucune autre lecture ne nous supplante (cf.
      // `_arrets`) -- le jeton seul ne le voyait pas.
      finish();
      return false;
    }
    await _player.stop();
    if (_perimee(jeton) || _arreteDepuis(marqueArret)) {
      finish();
      return false;
    }
    await _player.play(DeviceFileSource(path),
        position: Duration(milliseconds: startMs));
    await completer.future.timeout(_plafondLecture(endMs - startMs),
        onTimeout: () {
      posSub.cancel();
      doneSub.cancel();
      if (!_perimee(jeton)) _player.pause();
      DiagnosticLog.log('Correction-Audio',
          'plage MESUREE $etiquette : TRONQUEE au plafond '
          '(demande=${endMs - startMs} ms)');
    });
    final reel = DateTime.now().difference(depart).inMilliseconds;
    if (_perimee(jeton)) {
      // Le verdict d'une lecture supplantee ment sur ce qui a ete entendu :
      // c'est lui qui annoncait « joue verset=33:1 » alors que 33:5 jouait.
      DiagnosticLog.log('Correction-Audio',
          'plage MESUREE $etiquette : SUPPLANTEE par une lecture plus '
          'recente apres $reel ms -- aucun verdict');
      return false;
    }
    DiagnosticLog.log('Correction-Audio',
        'plage MESUREE $etiquette : demande=${endMs - startMs} ms reel=$reel ms');
    return true;
  }

  static Future<bool> playWordWindow(
    Verse verse,
    Reciter reciter, {
    required int startWordIdx,
    required int endWordIdx,
  }) =>
      playWordRange(
        verse,
        reciter,
        errorWordIndex: endWordIdx,
        wordsBefore: endWordIdx - startWordIdx,
        wordsAfter: 0,
      );

  /// Préchauffe les caches réseau (URLs audio du récitateur + segments de
  /// timing du verset) AVANT qu'une erreur ne survienne (demande utilisateur
  /// 2026-07-11 : "en cas d'erreur ça prend beaucoup de temps pour réagir").
  /// Log natif corrélé au moment de l'écriture de ce fix : le fetch À LA
  /// DEMANDE dans [playWordRange] (`fetchSurahAudioUrls`/`fetchAyahSegments`,
  /// jamais préchargés) coûtait 4,5 à 9,2 s sur un réseau dégradé -- capture
  /// déjà en pause tout ce temps, sans le moindre retour utilisateur. Appelé
  /// dès qu'un nouveau verset devient "courant" pendant la récitation (avant
  /// toute erreur), pour que le cache soit déjà chaud le temps qu'une
  /// correction soit éventuellement nécessaire sur CE verset. Best-effort :
  /// une erreur ici (réseau) est silencieusement ignorée -- [playWordRange]
  /// retente son propre fetch si le cache n'a pas eu le temps de se remplir.
  static Future<void> prefetch(Verse verse, Reciter reciter) async {
    // MP3Quran (2026-08-16) : rien à préchauffer côté réseau QF pour ce
    // récitateur -- le minutage est un asset local (chargé une fois pour
    // toute l'app, `ensureLoaded()` est idempotent) et l'audio est la MÊME
    // sourate entière que `AudioPlayerService` télécharge déjà pour
    // l'écoute au Mushaf. On amorce ce même téléchargement ici (best-effort,
    // fire-and-forget) : s'il est déjà en cours ou terminé pour l'écoute,
    // cet appel ne fait rien de plus ; sinon, il a une longueur d'avance sur
    // la correction.
    if (Mp3QuranApi.sertCeReciter(reciter.id)) {
      unawaited(Mp3QuranWordSegments.instance.ensureLoaded());
      unawaited(Mp3QuranApi
          .fichierLocalSourate(reciter.id, verse.surahNumber)
          .catchError((_) => ''));
      return;
    }
    final segKey = '${reciter.id}:${verse.key}';
    try {
      // Warsh : ni liste d'URLs ni segments à demander (l'URL se déduit, les
      // timings s'estiment sur le fichier) -- appeler quran.com ici ne
      // rapporterait rien et coûterait les mêmes secondes de réseau. Il reste
      // utile de PRÉ-TÉLÉCHARGER le MP3, qui est tout le gain du préchauffage.
      final String? url;
      if (!reciter.aSegmentsQuranCom) {
        url = reciter.urlVerset(verse.surahNumber, verse.ayahNumber);
      } else {
      _urlCache[_cleUrl(reciter.id, verse.surahNumber)] ??=
          await QuranApi.fetchSurahAudioUrls(reciter.id, verse.surahNumber);
      url = _urlCache[_cleUrl(reciter.id, verse.surahNumber)]?[verse.key];
      _segmentsCache[segKey] ??=
          await QuranApi.fetchAyahSegments(reciter.id, verse.key);
      }
      if (url != null && !_fileCache.containsKey(segKey)) {
        await _downloadToCache(segKey, url);
      }
    } catch (_) {
      // best-effort -- playWordRange retentera son propre fetch/streaming si
      // le cache n'a pas eu le temps de se remplir.
    }
  }

  /// Télécharge [url] vers un fichier local et l'enregistre sous [segKey]
  /// dans `_fileCache`, en évinçant le plus ancien au-delà de
  /// `_kMaxCachedFiles` (borne le disque sur une longue session continue).
  static Future<void> _downloadToCache(String segKey, String url) async {
    final dir = await getTemporaryDirectory();
    final safeName = segKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${dir.path}/word_correction_cache/$safeName.mp3';
    await Directory('${dir.path}/word_correction_cache').create(recursive: true);
    await _dio.download(url, path);
    _fileCache[segKey] = path;
    _fileCacheOrder.remove(segKey);
    _fileCacheOrder.add(segKey);
    while (_fileCacheOrder.length > _kMaxCachedFiles) {
      final evicted = _fileCacheOrder.removeAt(0);
      final evictedPath = _fileCache.remove(evicted);
      if (evictedPath != null) {
        try {
          await File(evictedPath).delete();
        } catch (_) {}
      }
    }
  }

  /// Arrete la lecture en cours ET perime toute lecture en vol (2026-09-12).
  ///
  /// L'increment est le point essentiel : sans lui, une lecture lancee juste
  /// avant ce `stop()` continuerait de recevoir les evenements du lecteur et
  /// pourrait couper la SUIVANTE quelques secondes plus tard. C'est ce qui se
  /// produisait quand un ecran se fermait pendant sa propre lecture -- cf. le
  /// bloc de `_generation`.
  static Future<void> stop() {
    // Avant l'increment de generation : une lecture encore EN PREPARATION ne
    // sera jamais perimee par ce jeton-la (elle n'a pas encore le sien), c'est
    // ce compteur qui l'annule. Cf. `_arrets`.
    _arrets++;
    _nouvelleLecture();
    return _player.stop();
  }
}
