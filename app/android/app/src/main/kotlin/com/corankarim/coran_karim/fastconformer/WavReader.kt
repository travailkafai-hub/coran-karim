package com.corankarim.coran_karim.fastconformer

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Lecture minimale WAV PCM 16-bit mono (format produit par `package:record`, voir
 * recitation_verifier.dart : RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000,
 * numChannels: 1)). Retourne l'audio normalise en float32 [-1, 1]. */
object WavReader {
    fun readMono16kFloat(path: String): FloatArray {
        val bytes = File(path).readBytes()
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

        require(bytes.size > 44) { "Fichier WAV trop court: $path" }
        require(buf.getInt(0) == 0x46464952) { "Pas un fichier RIFF valide: $path" } // "RIFF" LE

        // Cherche le sous-bloc "data" (peut ne pas etre a l'offset fixe 44 si des
        // chunks additionnels existent, ex. certains encodeurs ajoutent un chunk "LIST").
        var offset = 12
        var dataOffset = -1
        var dataSize = -1
        while (offset + 8 <= bytes.size) {
            val chunkId = buf.getInt(offset)
            val chunkSize = buf.getInt(offset + 4)
            if (chunkId == 0x61746164) { // "data" LE
                dataOffset = offset + 8
                dataSize = chunkSize
                break
            }
            offset += 8 + chunkSize + (chunkSize % 2)
        }
        require(dataOffset >= 0) { "Chunk 'data' introuvable dans: $path" }

        val nSamples = dataSize / 2 // PCM 16-bit
        val out = FloatArray(nSamples)
        for (i in 0 until nSamples) {
            val sample = buf.getShort(dataOffset + i * 2)
            out[i] = sample / 32768.0f
        }
        return out
    }
}
