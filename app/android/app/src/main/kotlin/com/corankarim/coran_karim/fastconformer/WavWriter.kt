package com.corankarim.coran_karim.fastconformer

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Écriture minimale WAV PCM 16-bit mono 16kHz — miroir de [WavReader], même
 * convention float32 [-1, 1]. Utilisé pour capturer les clips de récitation
 * VÉRIFIÉS CORRECTS (session de référence validée) en vue d'un futur mini-LoRA
 * de personnalisation vocale (cf. FONCTIONNALITES_FUTURES.md, "Personnalisation
 * voix — niveau 3", implémenté 2026-07-12). */
object WavWriter {
    fun writeMono16k(path: String, samples: FloatArray) {
        val sampleRate = 16000
        val byteRate = sampleRate * 2
        val dataSize = samples.size * 2
        val buf = ByteBuffer.allocate(44 + dataSize).order(ByteOrder.LITTLE_ENDIAN)

        buf.putInt(0x46464952) // "RIFF"
        buf.putInt(36 + dataSize)
        buf.putInt(0x45564157) // "WAVE"
        buf.putInt(0x20746d66) // "fmt "
        buf.putInt(16)         // taille du sous-bloc fmt
        buf.putShort(1)        // PCM
        buf.putShort(1)        // mono
        buf.putInt(sampleRate)
        buf.putInt(byteRate)
        buf.putShort(2)        // block align (mono 16-bit = 2 octets/echantillon)
        buf.putShort(16)       // bits par echantillon
        buf.putInt(0x61746164) // "data"
        buf.putInt(dataSize)
        for (s in samples) {
            val clamped = (s * 32768.0f).coerceIn(-32768.0f, 32767.0f)
            buf.putShort(clamped.toInt().toShort())
        }
        File(path).writeBytes(buf.array())
    }
}
