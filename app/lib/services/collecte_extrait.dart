// Découper, dans le clip d'un segment, le mot signalé et ses deux voisins.
//
// ── POURQUOI UN MOT DE CHAQUE CÔTÉ, ET PAS UNE DURÉE ────────────────────
//
// Demande utilisateur (2026-09-19) : « faut pas réfléchir par seconde, 1 mot de
// chaque côté c'est le bon compromis ». C'est le bon critère, et pas seulement
// par commodité :
//
//   - le voisin ENTIER porte la liaison — idghām, shadda de liaison,
//     proclitique — c'est-à-dire exactement les défauts qu'on cherche à
//     corriger. Une marge en secondes couperait au milieu de ce qui compte ;
//   - la transcription du clip reste EXACTE : trois mots, ni tronqués ni
//     devinés. Un extrait dont le texte est sûr est directement utilisable à
//     l'entraînement ; un extrait coupé en plein mot ne l'est pas.
//
// La durée en découle : au débit médian mesuré sur de vraies récitations
// (0,77 mot/s), trois mots font ~3,9 s, et l'utilisateur a confirmé que
// 2,5 à 3,5 s était la bonne taille. On ne la contraint donc pas.
//
// ── LA CONVERSION N'EST JAMAIS CODÉE EN DUR ─────────────────────────────
//
// `samplesParFrame` vient du natif, qui le DÉDUIT (`segmentSamples / nbFrames`)
// parce que le facteur de sous-échantillonnage est une propriété du modèle
// exporté. Une constante écrite ici (1280, « 80 ms ») ne se verrait pas et
// décalerait tous les extraits le jour d'un nouvel export — la même règle est
// déjà écrite côté Kotlin, là où la valeur est calculée.

import 'dart:io';
import 'dart:typed_data';

/// En-tête WAV canonique : 44 octets avant les échantillons.
const int _kEnteteWav = 44;

class CollecteExtrait {
  /// Extrait `[premier mot voisin … dernier mot voisin]` du clip [clipPath].
  ///
  /// [debutFrame] et [finFrame] sont les bornes À RETENIR (déjà élargies aux
  /// voisins par l'appelant). Rend `null` si le clip est absent, illisible, ou
  /// si les bornes ne veulent rien dire (`-1` quand la DP n'a rien placé).
  static Uint8List? decouper({
    required String clipPath,
    required int debutFrame,
    required int finFrame,
    required int samplesParFrame,
  }) {
    if (samplesParFrame <= 0 || debutFrame < 0 || finFrame < debutFrame) {
      return null;
    }
    final f = File(clipPath);
    if (!f.existsSync()) return null;

    final octets = f.readAsBytesSync();
    if (octets.length <= _kEnteteWav) return null;
    final entete = octets.sublist(0, _kEnteteWav);
    final pcm = octets.sublist(_kEnteteWav);

    // 16 bits mono : deux octets par échantillon.
    var debut = debutFrame * samplesParFrame * 2;
    var fin = (finFrame + 1) * samplesParFrame * 2;
    // Les bornes viennent d'un alignement, pas d'une mesure du fichier : on les
    // ramène DANS le clip plutôt que de refuser l'extrait. Un mot en fin de
    // segment peut déborder de quelques frames.
    if (debut < 0) debut = 0;
    if (fin > pcm.length) fin = pcm.length;
    if (fin - debut < samplesParFrame * 2) return null; // trop court pour servir

    final extrait = pcm.sublist(debut, fin);
    return _wav(entete, extrait);
  }

  /// Reconstruit un WAV lisible : sans réécrire les deux tailles de l'en-tête,
  /// le fichier annoncerait la durée du segment entier et la plupart des
  /// lecteurs — comme les chargeurs d'entraînement — liraient au-delà des
  /// données ou refuseraient le fichier.
  static Uint8List _wav(Uint8List enteteOrigine, Uint8List pcm) {
    final out = Uint8List.fromList([...enteteOrigine, ...pcm]);
    final vue = ByteData.sublistView(out);
    // offset 4  : taille totale du fichier moins 8
    vue.setUint32(4, out.length - 8, Endian.little);
    // offset 40 : taille du bloc de données
    vue.setUint32(40, pcm.length, Endian.little);
    return out;
  }

  /// Durée d'un extrait, pour le manifeste d'entraînement.
  static double dureeSecondes(Uint8List wav, {int tauxEchantillonnage = 16000}) {
    if (wav.length <= _kEnteteWav) return 0;
    return (wav.length - _kEnteteWav) / 2 / tauxEchantillonnage;
  }
}
