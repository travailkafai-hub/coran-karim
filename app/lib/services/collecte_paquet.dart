// Ce qu'on envoie, et sous quelle forme.
//
// ── UN PAQUET = UNE SESSION ──────────────────────────────────────────────
//
// Archive ZIP, puis chiffrée (cf. collecte_chiffrement.dart) :
//
//     session.json    verdicts mot par mot, texte attendu, versions
//     audio.wav       le flux de la session
//     journal.log     la trace de la chaîne, si elle existe
//
// Le ZIP compresse déjà (deflate). Mesuré sur un WAV réel de l'appareil :
// 120 364 -> 60 737 octets, soit 50 % — exactement le gain qu'on attendait du
// FLAC, sans dépendance ni perte. Le FLAC a donc été retiré du plan.
//
// ── POURQUOI L'AUDIO ENTIER ET PAS LES SEGMENTS SIGNALÉS ─────────────────
//
// Le plan visait les seuls segments autour des mots signalés : dix fois moins
// de données, et l'essentiel de l'information. C'est toujours la bonne cible.
//
// CE QUI L'EMPÊCHE AUJOURD'HUI, et il faut le dire précisément : découper
// suppose de savoir OÙ un mot se trouve dans le flux. Or `AlignedWord` porte
// `gop`, `forced`, le nombre de frames articulées — mais AUCUN offset absolu.
// L'information existe côté Kotlin (les observations portent `debut`/`fin` en
// échantillons) ; elle ne remonte simplement pas jusqu'à Dart.
//
// La faire remonter est une modification de la chaîne de récitation, donc
// soumise à validation (règle projet). On livre en attendant l'audio entier,
// et on assume les conséquences :
//
//     volume        ~5 Mo pour 5 min au lieu de ~500 Ko
//     10 Go gratuits ~2 000 sessions au lieu de ~20 000
//     sensibilité   toute la récitation part, pas seulement les passages douteux
//
// ⇒ Tâche identifiée pour plus tard : remonter l'offset de chaque mot, puis
// ne garder que `[debut - marge, fin + marge]` des mots signalés. Le reste de
// la chaîne d'envoi n'aura pas à changer.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import '../models/recitation_state.dart';

class CollectePaquet {
  /// Construit l'archive d'une session. Rend `null` s'il n'y a rien d'utile à
  /// envoyer — un paquet sans audio ne sert à personne.
  ///
  /// [dossierCapture] contient le `stream_*.wav` écrit par la chaîne.
  static Future<Uint8List?> construire({
    required String dossierCapture,
    required List<RecitedWord> mots,
    required int sourate,
    required int premierVerset,
    required String riwaya,
    required String modele,
    required String build,
    File? journal,
  }) async {
    final dir = Directory(dossierCapture);
    if (!dir.existsSync()) return null;

    final wavs = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.wav'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (wavs.isEmpty) return null;

    // Le texte attendu et le verdict de chaque mot. `heard` est ce que le
    // modèle a réellement lu : c'est la colonne qui permet, hors appareil, de
    // distinguer une faute de récitation d'un défaut de la chaîne.
    final session = <String, dynamic>{
      'schema': 1,
      'horodatage': DateTime.now().toUtc().toIso8601String(),
      'sourate': sourate,
      'premier_verset': premierVerset,
      'riwaya': riwaya,
      // Sans la version du modèle ET du build, une mesure relue plus tard est
      // ambiguë — piège déjà payé sur `fastconformer-ctc-mixed-e02`, dont le
      // nom ne dit pas qu'il contient l'epoch 14.
      'modele': modele,
      'build': build,
      'mots': [
        for (var i = 0; i < mots.length; i++)
          {
            'index': i,
            'attendu': mots[i].display,
            'entendu': mots[i].heard,
            'statut': mots[i].status.name,
            'verrouille': mots[i].locked,
          },
      ],
    };

    final archive = Archive()
      ..addFile(ArchiveFile.string(
          'session.json', const JsonEncoder.withIndent('  ').convert(session)));

    for (final wav in wavs) {
      final octets = wav.readAsBytesSync();
      archive.addFile(
          ArchiveFile(wav.uri.pathSegments.last, octets.length, octets));
    }
    if (journal != null && journal.existsSync()) {
      final octets = journal.readAsBytesSync();
      archive.addFile(ArchiveFile('journal.log', octets.length, octets));
    }

    final zip = ZipEncoder().encode(archive);
    return zip == null ? null : Uint8List.fromList(zip);
  }
}
