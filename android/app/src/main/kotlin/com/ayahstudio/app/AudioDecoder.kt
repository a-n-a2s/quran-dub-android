package com.ayahstudio.app

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

/**
 * بيفك أول مسار صوت من أي ملف بيدعمه أندرويد (mp3، m4a/aac، ogg/opus، flac،
 * wav، وكمان الفيديو mp4/3gp/webm...) لـ WAV PCM 16-bit **mono** بنفس الـ
 * sample rate الأصلي. التحويل لـ 16kHz بيصير بـ Dart (WavAudio).
 *
 * يوم 4: عشان المحرك يقبل أي ملف تلاوة (حسب المواصفات التلاوة ممكن تيجي من
 * ملف منفصل). يوم 6 رح يستعمله لاستخراج الصوت من الفيديو.
 */
object AudioDecoder {
    data class Result(
        val sampleRate: Int,
        val channels: Int,
        val frames: Long,
        val mime: String,
        val elapsedMs: Long,
    )

    @Throws(IOException::class)
    fun decodeToMonoWav(inputPath: String, outputPath: String): Result {
        val t0 = System.currentTimeMillis()
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(inputPath)
            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    track = i
                    format = f
                    break
                }
            }
            if (track < 0 || format == null) throw IOException("ما في مسار صوت بالملف")
            extractor.selectTrack(track)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING))
                format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT

            val c = MediaCodec.createDecoderByType(mime)
            codec = c
            c.configure(format, null, null, 0)
            c.start()

            var frames = 0L
            BufferedOutputStream(FileOutputStream(outputPath), 1 shl 16).use { out ->
                out.write(ByteArray(44)) // header بنكتبه بالآخر
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                var outputDone = false
                val timeoutUs = 10_000L
                while (!outputDone) {
                    if (!inputDone) {
                        val inIdx = c.dequeueInputBuffer(timeoutUs)
                        if (inIdx >= 0) {
                            val buf = c.getInputBuffer(inIdx)!!
                            val size = extractor.readSampleData(buf, 0)
                            if (size < 0) {
                                c.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                c.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                    val outIdx = c.dequeueOutputBuffer(info, timeoutUs)
                    if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val f = c.outputFormat
                        sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (f.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            encoding = f.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        }
                    } else if (outIdx >= 0) {
                        val buf = c.getOutputBuffer(outIdx)
                        if (buf != null && info.size > 0) {
                            buf.position(info.offset)
                            buf.limit(info.offset + info.size)
                            frames += writeMono(buf.slice().order(ByteOrder.LITTLE_ENDIAN),
                                channels, encoding, out)
                        }
                        c.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }
            writeWavHeader(outputPath, sampleRate, frames)
            return Result(sampleRate, channels, frames, mime, System.currentTimeMillis() - t0)
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            codec?.release()
            extractor.release()
        }
    }

    private fun bytesPerSample(encoding: Int): Int = when (encoding) {
        AudioFormat.ENCODING_PCM_8BIT -> 1
        AudioFormat.ENCODING_PCM_FLOAT -> 4
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
        AudioFormat.ENCODING_PCM_32BIT -> 4
        else -> 2
    }

    private fun readSample(b: ByteBuffer, encoding: Int): Double = when (encoding) {
        AudioFormat.ENCODING_PCM_8BIT -> ((b.get().toInt() and 0xff) - 128) / 128.0
        AudioFormat.ENCODING_PCM_FLOAT -> b.float.toDouble()
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
            var v = (b.get().toInt() and 0xff) or ((b.get().toInt() and 0xff) shl 8) or
                ((b.get().toInt() and 0xff) shl 16)
            if (v and 0x800000 != 0) v -= 0x1000000
            v / 8388608.0
        }
        AudioFormat.ENCODING_PCM_32BIT -> b.int / 2147483648.0
        else -> b.short / 32768.0
    }

    /** بيخلط القنوات (متوسط) وبيكتب PCM16 little-endian. بيرجع عدد الإطارات. */
    private fun writeMono(b: ByteBuffer, channels: Int, encoding: Int, out: OutputStream): Long {
        val ch = if (channels < 1) 1 else channels
        val frameCount = b.remaining() / (bytesPerSample(encoding) * ch)
        val bytes = ByteArray(frameCount * 2)
        for (i in 0 until frameCount) {
            var sum = 0.0
            for (k in 0 until ch) sum += readSample(b, encoding)
            val s = ((sum / ch).coerceIn(-1.0, 1.0) * 32767.0).roundToInt()
            bytes[2 * i] = (s and 0xff).toByte()
            bytes[2 * i + 1] = ((s shr 8) and 0xff).toByte()
        }
        out.write(bytes)
        return frameCount.toLong()
    }

    private fun writeWavHeader(path: String, sampleRate: Int, frames: Long) {
        val dataLen = frames * 2
        val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        h.put("RIFF".toByteArray(Charsets.US_ASCII))
        h.putInt((36 + dataLen).toInt())
        h.put("WAVE".toByteArray(Charsets.US_ASCII))
        h.put("fmt ".toByteArray(Charsets.US_ASCII))
        h.putInt(16)
        h.putShort(1) // PCM
        h.putShort(1) // mono
        h.putInt(sampleRate)
        h.putInt(sampleRate * 2)
        h.putShort(2)
        h.putShort(16)
        h.put("data".toByteArray(Charsets.US_ASCII))
        h.putInt(dataLen.toInt())
        RandomAccessFile(path, "rw").use { f ->
            f.seek(0)
            f.write(h.array())
        }
    }
}
