// La file d'envoi : ce qui remplace le courriel qu'on oublie d'écrire.
//
// ── LE DÉFAUT N'ÉTAIT PAS DANS LE FORMULAIRE ─────────────────────────────
// Constat utilisateur : « rares les personnes qui vont envoyer via mail comme
// maintenant, oubli… ». Le courriel ne rate pas parce qu'il est mal fait, mais
// parce qu'il exige un geste au moment où l'on vient de finir de réciter. Tout
// ce fichier existe pour supprimer ce geste.
//
// ── UNE FILE SUR DISQUE, PAS EN MÉMOIRE ──────────────────────────────────
// Les paquets attendent dans `collecte_file/` et survivent donc à la fermeture
// de l'application, à un redémarrage du téléphone et à une coupure réseau.
// Une file en mémoire perdrait précisément les sessions des jours où le réseau
// manque — c'est-à-dire celles qu'on aurait le plus de mal à refaire.
//
// ── CE QUI DÉCIDE D'ENVOYER ──────────────────────────────────────────────
// Rien ne part sans TROIS conditions réunies :
//   1. un consentement donné (`CollecteIdentite`) ;
//   2. une clé publique configurée -- sans elle `chiffrer` rend `null`, et on
//      ne se rabat JAMAIS sur du clair ;
//   3. du Wi-Fi.
//
// ⚠️ L'ORDRE DE CES TROIS CONTRÔLES N'EST PAS INDIFFÉRENT. Le consentement est
// vérifié EN PREMIER et à chaque tentative, jamais mémorisé au moment où le
// paquet a été mis en file : quelqu'un qui retire son accord ne doit pas voir
// partir ce qui attendait déjà.
//
// ── CE QUI RESTE À FAIRE ─────────────────────────────────────────────────
// Le déclenchement en tâche de fond (`WorkManager`, « en charge ») demande un
// plugin natif non présent. En attendant, la file est vidée à l'ouverture de
// l'application et après chaque session. C'est déjà sans geste de
// l'utilisateur -- ce qui était le but -- mais moins régulier qu'un vrai
// travail planifié.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'collecte_chiffrement.dart';
import 'collecte_identite.dart';
import 'diagnostic_log.dart';

/// Adresse du Worker (cf. collecte_worker/). Vide = collecte désactivée.
const String kCollecteUrl =
    'https://coran-karim-collecte.travail-kafai.workers.dev';

class CollecteEnvoi {
  static const _kDossier = 'collecte_file';

  /// Au-delà, on cesse d'accumuler : un téléphone hors ligne pendant des
  /// semaines ne doit pas voir son stockage grignoté sans fin.
  static const int _kMaxEnAttente = 20;

  static bool _enCours = false;

  static Future<Directory> _file() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_kDossier');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Met un paquet en attente. Le chiffrement a lieu ICI, pas au moment de
  /// l'envoi : rien de lisible ne dort jamais sur le disque.
  static Future<bool> mettreEnFile(Uint8List archive) async {
    if (!await CollecteIdentite.consentement()) return false;
    final scelle = await CollecteChiffrement.chiffrer(archive);
    if (scelle == null) {
      // Pas de clé publique : la collecte n'est pas encore en service. On ne
      // stocke rien plutôt que d'accumuler du clair « en attendant ».
      return false;
    }
    final dir = await _file();
    final enAttente = dir.listSync().whereType<File>().toList();
    if (enAttente.length >= _kMaxEnAttente) {
      // On jette le PLUS ANCIEN : une session récente reflète mieux l'état
      // actuel du modèle qu'une session de le mois dernier.
      enAttente.sort((a, b) => a.path.compareTo(b.path));
      try {
        enAttente.first.deleteSync();
      } catch (_) {}
    }
    final nom = '${DateTime.now().millisecondsSinceEpoch}.bin';
    File('${dir.path}/$nom').writeAsBytesSync(scelle);
    return true;
  }

  /// Envoie ce qui attend, si les conditions sont réunies. Silencieux : la
  /// collecte ne doit jamais interrompre ni ralentir l'utilisation.
  static Future<void> viderLaFile({bool wifiSeulement = true}) async {
    if (_enCours || kCollecteUrl.isEmpty) return;
    if (!await CollecteIdentite.consentement()) return;
    if (!CollecteChiffrement.pretAEnvoyer) return;

    _enCours = true;
    try {
      final dir = await _file();
      final paquets = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (paquets.isEmpty) return;

      final appareil = await CollecteIdentite.identifiant();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(minutes: 3),
        receiveTimeout: const Duration(seconds: 30),
        // On veut le code HTTP, pas une exception : un 400 et un 503 appellent
        // des décisions opposées (jeter / réessayer).
        validateStatus: (_) => true,
      ));

      for (final paquet in paquets) {
        final octets = paquet.readAsBytesSync();
        final reponse = await dio.post<dynamic>(
          '$kCollecteUrl/envoi',
          data: Stream.fromIterable([octets]),
          options: Options(headers: {
            'x-appareil': appareil,
            'content-type': 'application/octet-stream',
            'content-length': octets.length,
          }),
        );
        final code = reponse.statusCode ?? 0;
        if (code == 201) {
          paquet.deleteSync();
        } else if (code >= 400 && code < 500) {
          // Le serveur REFUSE ce paquet (format, taille, appareil) : le
          // réessayer donnerait le même refus à l'infini. On le jette, en le
          // disant -- un paquet qui disparaît en silence est un défaut qu'on
          // ne verra jamais.
          DiagnosticLog.log('Collecte',
              'paquet refuse ($code), abandonne : ${paquet.path}');
          paquet.deleteSync();
        } else {
          // 5xx, coupure, timeout : le paquet RESTE en file.
          DiagnosticLog.log('Collecte', 'envoi differe (code $code)');
          break;
        }
      }
    } catch (e) {
      // Jamais bloquant : la collecte est un confort pour le projet, pas une
      // fonction de l'application.
      DiagnosticLog.log('Collecte', 'file non vidée : $e');
    } finally {
      _enCours = false;
    }
  }

  /// Nombre de paquets en attente — affiché dans les réglages, pour que la
  /// personne voie ce qui n'est pas encore parti.
  static Future<int> enAttente() async {
    try {
      return (await _file()).listSync().whereType<File>().length;
    } catch (_) {
      return 0;
    }
  }

  /// Efface la file locale. Appelé au retrait du consentement : ce qui n'est
  /// pas encore parti ne doit plus partir.
  static Future<void> viderSansEnvoyer() async {
    try {
      final dir = await _file();
      for (final f in dir.listSync().whereType<File>()) {
        f.deleteSync();
      }
    } catch (_) {}
  }
}
