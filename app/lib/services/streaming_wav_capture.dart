import 'dart:io';
import 'dart:typed_data';

/// Écrit progressivement un flux PCM16LE mono 16 kHz dans un WAV valide.
///
/// Le flux causal n'a pas de segments VAD à partir desquels reconstruire
/// l'audio après coup. Le corps PCM est donc écrit au fil de l'eau, puis les
/// tailles RIFF sont finalisées à la fermeture.
class StreamingWavCapture {
  StreamingWavCapture._(this.path, this._file);

  final String path;
  final RandomAccessFile _file;

  Future<void> _writeTail = Future.value();
  Future<String>? _closing;
  var _accepting = true;
  var _dataBytes = 0;

  static Future<StreamingWavCapture> open(String path) async {
    final output = File(path);
    await output.parent.create(recursive: true);
    final file = await output.open(mode: FileMode.write);
    // En-tête VALIDE dès l'ouverture (0 octet de data -- un WAV vide est un
    // WAV valide), pas un simple espace réservé à zéro. Bug corrigé
    // 2026-07-26 : si le process meurt avant close() (mise en veille,
    // changement d'écran, appli tuée), le fichier restait bloqué avec un
    // en-tête tout à zéro -- DÉFINITIVEMENT illisible par n'importe quel
    // lecteur, alors que le PCM à l'intérieur était intact (constaté deux
    // fois sur device le même jour, une capture réparée à la main pour
    // analyse). `add()` resynchronise cet en-tête à chaque bloc écrit.
    await file.writeFrom(_header(0));
    return StreamingWavCapture._(path, file);
  }

  /// Copie immédiatement [pcm16] : le plugin `record` peut réutiliser son
  /// tampon dès le retour du callback.
  void add(Uint8List pcm16) {
    if (!_accepting || pcm16.isEmpty) return;
    final owned = Uint8List.fromList(pcm16);
    _writeTail = _writeTail.then((_) async {
      await _file.writeFrom(owned);
      _dataBytes += owned.length;
      // Resynchronise l'en-tête à CHAQUE bloc (cf. `open()`) : coût
      // négligeable (44 octets) face au flux audio, et garantit qu'à tout
      // instant le fichier est un WAV valide jusqu'au dernier bloc
      // réellement écrit -- pas seulement à la fermeture propre.
      final pos = await _file.position();
      await _file.setPosition(0);
      await _file.writeFrom(_header(_dataBytes));
      await _file.setPosition(pos);
    });
  }

  Future<String> close() => _closing ??= _closeOnce();

  Future<String> _closeOnce() async {
    _accepting = false;
    await _writeTail;
    // L'en-tête est déjà à jour (resynchronisé à chaque bloc dans `add()`) --
    // plus besoin de le réécrire ici, juste s'assurer que tout est sur disque.
    await _file.flush();
    await _file.close();
    return path;
  }

  static Uint8List _header(int dataBytes) {
    final bytes = Uint8List(44);
    final data = ByteData.sublistView(bytes);

    void ascii(int offset, String value) {
      bytes.setRange(offset, offset + value.length, value.codeUnits);
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 16000, Endian.little);
    data.setUint32(28, 16000 * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataBytes, Endian.little);
    return bytes;
  }
}
