package com.ayahstudio.app

import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import java.io.IOException

/**
 * قراءة معلومات الفيديو (يوم 6، المواصفات القسم 2): الأبعاد الخام (قبل
 * الدوران)، الدوران، المدة، fps، وفي مسار صوت ولا لأ. الأبعاد الفعلية بعد
 * الدوران (عمودي/أفقي/مربع) محسوبة بـ Dart الصافي
 * (`lib/pipeline/project_input.dart` → `VideoInfo.rotatedWidth/rotatedHeight`)
 * عشان تكون جزء مختبر بالاختبارات بدل Kotlin.
 *
 * العرض/الارتفاع وfps من `MediaExtractor` (مسار الفيديو)، والدوران والمدة من
 * `MediaMetadataRetriever` (أدق للـ metadata على مستوى الملف). لو
 * `MediaExtractor` ما قدر يطلّع العرض/الارتفاع (نادر)، بنرجع لـ
 * `MediaMetadataRetriever` كخيار بديل.
 */
object VideoInfoReader {
    data class Info(
        val width: Int,
        val height: Int,
        val rotation: Int,
        val durationMs: Long,
        val fps: Double,
        val hasAudioTrack: Boolean,
    )

    @Throws(IOException::class)
    fun read(path: String): Info {
        var width = 0
        var height = 0
        var fps = 0.0
        var hasAudio = false

        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/") && width == 0 && height == 0) {
                    if (f.containsKey(MediaFormat.KEY_WIDTH)) width = f.getInteger(MediaFormat.KEY_WIDTH)
                    if (f.containsKey(MediaFormat.KEY_HEIGHT)) height = f.getInteger(MediaFormat.KEY_HEIGHT)
                    if (f.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        fps = try {
                            f.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble()
                        } catch (_: ClassCastException) {
                            f.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                        }
                    }
                } else if (mime.startsWith("audio/")) {
                    hasAudio = true
                }
            }
        } finally {
            extractor.release()
        }

        var rotation = 0
        var durationMs = 0L
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            if (width == 0 || height == 0) {
                width = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: width
                height = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: height
            }
        } finally {
            retriever.release()
        }

        return Info(width, height, rotation, durationMs, fps, hasAudio)
    }
}
