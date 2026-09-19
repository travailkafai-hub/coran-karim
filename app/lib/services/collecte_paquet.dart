// Ce qui part : des extraits directement utilisables à l'entraînement.
//
// ── UNE ARCHIVE = PLUSIEURS INCIDENTS D'UNE MÊME SÉANCE ─────────────────
//
//     manifest.jsonl    une ligne par extrait, format NeMo
//     diagnostic.json   verdicts, avis de la personne, versions
//     extrait_<n>.wav   le mot signalé et ses deux voisins (~3,9 s)
//
// `manifest.jsonl` est écrit AU FORMAT D'ENTRAÎNEMENT, pas dans un format
// maison à convertir plus tard :
//
//     {"audio_filepath": "extrait_0.wav", "text": "…", "duration": 3.87}
//
// C'est la demande : « on aura tout pour directement l'intégrer à
// l'entraînement ». Un format intermédiaire obligerait à écrire un convertisseur
// — et à le maintenir d'accord avec ce fichier, ce qui finit toujours par ne
// plus l'être.
//
// ── CE QUI DÉCIDE DE CE QUI PART ────────────────────────────────────────
//
// Seuls les incidents sur lesquels la personne s'est prononcée. Un incident
// sans avis n'a pas d'étiquette fiable : il vaut un enregistrement brut, c'est
// -à-dire ce qu'on cherchait justement à ne plus envoyer.
//
// ⚠️ LA DISTINCTION QUI COMPTE À L'ENTRAÎNEMENT. `appSeTrompe` donne un
// exemple SÛR : le texte attendu est bien ce qui a été prononcé, puisque la
// personne dit que sa récitation était juste. `fauteReelle` donne un extrait
// dont on ignore le contenu réel — il est marqué `a_annoter`, et le manifeste
// ne le porte PAS : l'entraîner sur le texte attendu apprendrait au modèle à
// lire une faute comme si elle était correcte.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import 'collecte_extrait.dart';
import 'collecte_incidents.dart';

class CollectePaquet {
  /// Rend `null` s'il n'y a rien à envoyer.
  static Future<Uint8List?> construire({
    required List<Incident> incidents,
    required String build,
  }) async {
    final retenus = incidents.where((i) => i.avis != null).toList();
    if (retenus.isEmpty) return null;

    final archive = Archive();
    final manifeste = StringBuffer();
    final diagnostic = <Map<String, dynamic>>[];
    var n = 0;

    for (final incident in retenus) {
      final wav = CollecteExtrait.decouper(
        clipPath: incident.clipPath,
        debutFrame: incident.debutFrame,
        finFrame: incident.finFrame,
        samplesParFrame: incident.samplesParFrame,
      );
      // Le clip a pu disparaître entre la séance et l'envoi : on saute cet
      // incident plutôt que d'écrire une ligne de manifeste qui pointerait sur
      // un fichier absent — un manifeste qui ment fait échouer l'entraînement
      // loin de sa cause.
      if (wav == null) continue;

      final nom = 'extrait_$n.wav';
      archive.addFile(ArchiveFile(nom, wav.length, wav));
      final duree = CollecteExtrait.dureeSecondes(wav);

      if (incident.avis == AvisSurVerdict.appSeTrompe) {
        manifeste.writeln(jsonEncode({
          'audio_filepath': nom,
          'text': incident.texteExtrait,
          'duration': double.parse(duree.toStringAsFixed(3)),
        }));
      }
      diagnostic.add({
        'extrait': nom,
        'index_mot': incident.indexMot,
        'mot_attendu': incident.motAttendu,
        'texte_extrait': incident.texteExtrait,
        'entendu': incident.entendu,
        'gop': double.parse(incident.gop.toStringAsFixed(3)),
        'duree': double.parse(duree.toStringAsFixed(3)),
        'avis': incident.avis == AvisSurVerdict.appSeTrompe
            ? 'app_se_trompe'
            : 'faute_reelle',
        // Ce drapeau évite la seule erreur vraiment coûteuse : entraîner sur
        // un extrait dont on ne connaît pas la transcription.
        'a_annoter': incident.avis == AvisSurVerdict.fauteReelle,
      });
      n++;
    }
    if (n == 0) return null;

    archive
      ..addFile(ArchiveFile.string('manifest.jsonl', manifeste.toString()))
      ..addFile(ArchiveFile.string(
          'diagnostic.json',
          const JsonEncoder.withIndent('  ').convert({
            'schema': 2,
            'horodatage': DateTime.now().toUtc().toIso8601String(),
            'build': build,
            'incidents': diagnostic,
          })));

    final zip = ZipEncoder().encode(archive);
    return zip == null ? null : Uint8List.fromList(zip);
  }
}
