package com.corankarim.coran_karim.fastconformer

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Recalcule le mel-spectrogramme EXACTEMENT comme
 * nemo.collections.asr.parts.preprocessing.features.FilterbankFeatures
 * (config du modele nvidia/stt_ar_fastconformer_hybrid_large_pcd_v1.0) :
 * sample_rate=16000, n_fft=512, win_length=400 (25ms), hop_length=160 (10ms),
 * hann(periodic=false), preemph=0.97, n_mels=80, fmin=0, fmax=8000,
 * mel_norm=slaney, mag_power=2.0, log(x + 2^-24), normalize per_feature (ddof=1, +1e-5).
 *
 * Formule validee bit-exacte cote Python (benchmark/mel_numpy_reference.py,
 * benchmark/validate_mel_numpy.py : diff moyenne ~0.001 sur echelle [-3,3]).
 *
 * Piege a ne pas reintroduire : quand win_length < n_fft, chaque frame FFT couvre
 * n_fft echantillons [t*hop, t*hop+n_fft), et seule la portion CENTREE de
 * win_length echantillons est ponderee par la fenetre Hann -- PAS les win_length
 * premiers echantillons de la frame. Un decalage ici donne un spectrogramme qui
 * "ressemble" a un resultat valide (memes dimensions) mais dont le contenu par bin
 * est faux, sans erreur visible.
 */
object MelSpectrogram {
    private const val SAMPLE_RATE = 16000
    private const val N_FFT = 512
    private const val WIN_LENGTH = 400
    private const val HOP_LENGTH = 160
    private const val N_MELS = 80
    private const val PREEMPH = 0.97f
    private const val FMIN = 0.0
    private const val FMAX = 8000.0
    private const val LOG_ZERO_GUARD = 5.9604644775390625e-8 // 2^-24
    private const val NORM_EPS = 1e-5

    private val hannWindow: DoubleArray = buildHannWindow(WIN_LENGTH)
    private val melFilterbank: Array<DoubleArray> = buildMelFilterbank() // (N_MELS, N_FFT/2+1)

    /** periodic=false => fenetre symetrique standard (torch.hann_window(n, periodic=False)). */
    private fun buildHannWindow(n: Int): DoubleArray {
        if (n == 1) return doubleArrayOf(1.0)
        return DoubleArray(n) { k -> 0.5 - 0.5 * cos(2.0 * PI * k / (n - 1)) }
    }

    private fun hzToMel(f: Double): Double {
        val fSp = 200.0 / 3.0
        var mel = f / fSp
        val minLogHz = 1000.0
        val minLogMel = minLogHz / fSp
        val logstep = ln(6.4) / 27.0
        if (f >= minLogHz) {
            mel = minLogMel + ln(max(f, 1e-10) / minLogHz) / logstep
        }
        return mel
    }

    private fun melToHz(m: Double): Double {
        val fSp = 200.0 / 3.0
        var f = fSp * m
        val minLogHz = 1000.0
        val minLogMel = minLogHz / fSp
        val logstep = ln(6.4) / 27.0
        if (m >= minLogMel) {
            f = minLogHz * exp(logstep * (m - minLogMel))
        }
        return f
    }

    /** Reimplementation de librosa.filters.mel(norm='slaney'), validee identique a 1e-9 pres
     * cote Python (mel_filterbank_slaney() dans mel_numpy_reference.py). */
    private fun buildMelFilterbank(): Array<DoubleArray> {
        val nFreqs = N_FFT / 2 + 1
        val fftFreqs = DoubleArray(nFreqs) { i -> i * (SAMPLE_RATE / 2.0) / (nFreqs - 1) }

        val minMel = hzToMel(FMIN)
        val maxMel = hzToMel(FMAX)
        val melPts = DoubleArray(N_MELS + 2) { i -> minMel + i * (maxMel - minMel) / (N_MELS + 1) }
        val hzPts = DoubleArray(N_MELS + 2) { i -> melToHz(melPts[i]) }

        val fb = Array(N_MELS) { DoubleArray(nFreqs) }
        val fdiff = DoubleArray(N_MELS + 1) { i -> hzPts[i + 1] - hzPts[i] }

        for (i in 0 until N_MELS) {
            for (j in 0 until nFreqs) {
                val l = -(hzPts[i] - fftFreqs[j]) / fdiff[i]
                val u = (hzPts[i + 2] - fftFreqs[j]) / fdiff[i + 1]
                fb[i][j] = max(0.0, min(l, u))
            }
            val enorm = 2.0 / (hzPts[i + 2] - hzPts[i])
            for (j in 0 until nFreqs) fb[i][j] *= enorm
        }
        return fb
    }

    /**
     * FFT Cooley-Tukey radix-2 recursive, portee depuis whisper.cpp
     * (patches/whisper_ggml/android/src/whisper/whisper.cpp/whisper.cpp:2354-2429).
     * Entree reelle, sortie complexe entrelacee [re0,im0,re1,im1,...]. N doit etre une
     * puissance de 2 (N_FFT=512 ici, le fallback DFT naif de whisper.cpp n'est pas necessaire).
     */
    private fun fft(input: DoubleArray): DoubleArray {
        val n = input.size
        val out = DoubleArray(n * 2)
        if (n == 1) {
            out[0] = input[0]
            out[1] = 0.0
            return out
        }
        val even = DoubleArray(n / 2)
        val odd = DoubleArray(n / 2)
        for (i in 0 until n) {
            if (i % 2 == 0) even[i / 2] = input[i] else odd[i / 2] = input[i]
        }
        val evenFft = fft(even)
        val oddFft = fft(odd)
        for (k in 0 until n / 2) {
            val theta = 2.0 * PI * k / n
            val re = cos(theta)
            val im = -sin(theta)
            val reOdd = oddFft[2 * k]
            val imOdd = oddFft[2 * k + 1]
            out[2 * k] = evenFft[2 * k] + re * reOdd - im * imOdd
            out[2 * k + 1] = evenFft[2 * k + 1] + re * imOdd + im * reOdd
            out[2 * (k + n / 2)] = evenFft[2 * k] - re * reOdd + im * imOdd
            out[2 * (k + n / 2) + 1] = evenFft[2 * k + 1] - re * imOdd - im * reOdd
        }
        return out
    }

    // ── Acces frame-par-frame pour le mode STREAMING ─────────────────────────
    // (FastConformerStreamingSession calcule ses frames de maniere strictement
    // causale et gere sa propre normalisation cumulative — il ne peut pas
    // utiliser compute() qui normalise sur tout le buffer d'un coup.)

    /** Nb d'echantillons de marge du fenetrage centre : (n_fft-win_length)/2 = 56. */
    const val WIN_PAD_SAMPLES = (N_FFT - WIN_LENGTH) / 2

    /** Fin (exclusive) des echantillons PADDES requis pour la frame t :
     * t*hop + winPad + winLength. Une frame n'est calculable que quand le
     * signal padde atteint cette longueur — PAS de zero-padding de fin. */
    fun paddedEndForFrame(t: Long): Long = t * HOP_LENGTH + WIN_PAD_SAMPLES + WIN_LENGTH

    /**
     * log-mel (80 valeurs, SANS normalisation) de la frame commencant a
     * [startIdx] dans un buffer de signal deja preemphasise+padde-centre.
     * Le buffer doit contenir au moins startIdx+WIN_PAD_SAMPLES+WIN_LENGTH echantillons.
     */
    fun frameLogMel(padded: DoubleArray, startIdx: Int): FloatArray {
        val frame = DoubleArray(N_FFT)
        for (j in 0 until WIN_LENGTH) {
            frame[WIN_PAD_SAMPLES + j] = padded[startIdx + WIN_PAD_SAMPLES + j] * hannWindow[j]
        }
        val spec = fft(frame)
        val nFreqs = N_FFT / 2 + 1
        val power = DoubleArray(nFreqs)
        for (k in 0 until nFreqs) {
            val re = spec[2 * k]
            val im = spec[2 * k + 1]
            power[k] = re * re + im * im
        }
        val out = FloatArray(N_MELS)
        for (m in 0 until N_MELS) {
            var acc = 0.0
            val row = melFilterbank[m]
            for (k in 0 until nFreqs) acc += row[k] * power[k]
            out[m] = ln(acc + LOG_ZERO_GUARD).toFloat()
        }
        return out
    }

    const val N_MELS_PUBLIC = N_MELS
    const val HOP_PUBLIC = HOP_LENGTH
    const val CENTER_PAD = N_FFT / 2
    const val PREEMPH_PUBLIC = PREEMPH

    /**
     * Calcule les features (N_MELS, T) pretes a envoyer au modele ONNX
     * (entree "audio_signal" [1, 80, T] + "length" [T]).
     * @param pcm audio brut mono 16kHz, echantillons float32 dans [-1, 1]
     */
    fun compute(pcm: FloatArray): Array<FloatArray> {
        val n = pcm.size

        // 1) Preemphasis
        val x = DoubleArray(n)
        x[0] = pcm[0].toDouble()
        // Kotlin ne convertit jamais Float -> Double implicitement (contrairement a Java) ;
        // .toDouble() explicite necessaire ici, piege facile a manquer en portant depuis numpy.
        for (i in 1 until n) x[i] = (pcm[i] - PREEMPH * pcm[i - 1]).toDouble()

        // 2) Zero-pad centre (torch.stft center=True, pad_mode="constant")
        val pad = N_FFT / 2
        val padded = DoubleArray(n + 2 * pad)
        System.arraycopy(x, 0, padded, pad, n)

        // 3) Framing : chaque frame = N_FFT echantillons, fenetre Hann centree de WIN_LENGTH
        val winPad = (N_FFT - WIN_LENGTH) / 2
        val nFrames = 1 + (padded.size - N_FFT) / HOP_LENGTH
        val nFreqs = N_FFT / 2 + 1
        val power = Array(nFrames) { DoubleArray(nFreqs) }

        val frame = DoubleArray(N_FFT)
        for (t in 0 until nFrames) {
            java.util.Arrays.fill(frame, 0.0)
            val start = t * HOP_LENGTH
            for (j in 0 until WIN_LENGTH) {
                frame[winPad + j] = padded[start + winPad + j] * hannWindow[j]
            }
            val spec = fft(frame) // (N_FFT*2) interleaved re/im
            for (k in 0 until nFreqs) {
                val re = spec[2 * k]
                val im = spec[2 * k + 1]
                power[t][k] = re * re + im * im // mag_power=2.0 (spectre de puissance)
            }
        }

        // 4) Filterbank mel (slaney) : (N_MELS, nFreqs) . (nFreqs, T) -> (N_MELS, T)
        val logMel = Array(N_MELS) { DoubleArray(nFrames) }
        for (m in 0 until N_MELS) {
            val fbRow = melFilterbank[m]
            for (t in 0 until nFrames) {
                var acc = 0.0
                for (k in 0 until nFreqs) acc += fbRow[k] * power[t][k]
                logMel[m][t] = ln(acc + LOG_ZERO_GUARD)
            }
        }

        // 5) Normalisation per_feature (par bin mel, ddof=1) + epsilon
        val out = Array(N_MELS) { FloatArray(nFrames) }
        for (m in 0 until N_MELS) {
            var mean = 0.0
            for (t in 0 until nFrames) mean += logMel[m][t]
            mean /= nFrames
            var variance = 0.0
            for (t in 0 until nFrames) {
                val d = logMel[m][t] - mean
                variance += d * d
            }
            val std = sqrt(variance / (nFrames - 1)) + NORM_EPS
            for (t in 0 until nFrames) out[m][t] = ((logMel[m][t] - mean) / std).toFloat()
        }
        return out // (N_MELS, T)
    }
}
