package com.example.coran_karim

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder.AudioSource
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android audio recorder using AudioSource.VOICE_RECOGNITION.
 *
 * This source automatically enables the platform-level WebRTC pipeline:
 *   - Acoustic Echo Cancellation (AEC)
 *   - Noise Suppressor (NS)  ← handles ambient noise, crowd, traffic
 *   - Automatic Gain Control (AGC)
 *
 * Output: PCM 16kHz mono int16 → converted to float32 for Whisper.
 *
 * To activate: register this plugin in MainActivity.kt:
 *   AudioRecorderPlugin(flutterEngine.dartExecutor.binaryMessenger)
 */
class AudioRecorderPlugin(messenger: io.flutter.plugin.common.BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.corankarim/audio_recorder")

    companion object {
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CFG = AudioFormat.CHANNEL_IN_MONO
        const val ENCODING   = AudioFormat.ENCODING_PCM_16BIT
    }

    private var recorder: AudioRecord? = null
    private val recordedSamples = mutableListOf<Short>()
    @Volatile private var isRecording = false
    private var recordThread: Thread? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> startRecording(result)
            "stop"  -> stopRecording(result)
            else    -> result.notImplemented()
        }
    }

    private fun startRecording(result: MethodChannel.Result) {
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CFG, ENCODING)
        val bufSize = maxOf(minBuf, SAMPLE_RATE * 2)  // 1 second min buffer

        recorder = AudioRecord(
            AudioSource.VOICE_RECOGNITION,  // enables NS / AEC / AGC
            SAMPLE_RATE, CHANNEL_CFG, ENCODING, bufSize
        )

        if (recorder!!.state != AudioRecord.STATE_INITIALIZED) {
            result.error("INIT_FAILED", "AudioRecord failed to initialize", null)
            return
        }

        recordedSamples.clear()
        isRecording = true
        recorder!!.startRecording()

        recordThread = Thread {
            val buf = ShortArray(1024)
            while (isRecording) {
                val read = recorder!!.read(buf, 0, buf.size)
                if (read > 0) {
                    synchronized(recordedSamples) {
                        for (i in 0 until read) recordedSamples.add(buf[i])
                    }
                }
            }
        }.also { it.start() }

        result.success(null)
    }

    private fun stopRecording(result: MethodChannel.Result) {
        isRecording = false
        recordThread?.join(200)
        recorder?.stop()
        recorder?.release()
        recorder = null

        // Convert int16 PCM → float32 in [-1, 1]
        val floats: List<Double>
        synchronized(recordedSamples) {
            floats = recordedSamples.map { it.toDouble() / 32768.0 }
            recordedSamples.clear()
        }
        result.success(floats)
    }
}
