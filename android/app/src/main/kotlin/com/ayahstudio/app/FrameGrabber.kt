package com.ayahstudio.app

import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.ByteBuffer

/**
 * إطار من فيديو بلحظة معينة، مستقيم (حسب الدوران) ومصغّر لأبعاد معينة،
 * كبكسلات RGBA (يوم 8). مستعمل بتجربة التصدير بالمحاكي (مقارنة إطار الناتج
 * مع الأصل + صورة النص)، وممكن لصور المشاريع المصغّرة (يوم 13).
 */
object FrameGrabber {
    @Throws(IOException::class)
    fun rgbaAt(path: String, timeUs: Long, width: Int, height: Int): ByteArray {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val raw = r.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: throw IOException("ما في إطار عند $timeUs")
            // أغلب الأجهزة بترجع الإطار معدول؛ لو لأ (الشكل عكس المطلوب) بنعدله.
            val wantPortrait = height > width
            val isPortrait = raw.height > raw.width
            val upright = if (rotation % 180 != 0 && width != height && raw.width != raw.height &&
                isPortrait != wantPortrait
            ) {
                Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height,
                    Matrix().apply { postRotate(rotation.toFloat()) }, true)
            } else raw
            val scaled = if (upright.width == width && upright.height == height) upright
                else Bitmap.createScaledBitmap(upright, width, height, true)
            val argb = if (scaled.config == Bitmap.Config.ARGB_8888) scaled
                else scaled.copy(Bitmap.Config.ARGB_8888, false)
            val buf = ByteBuffer.allocate(width * height * 4)
            argb.copyPixelsToBuffer(buf)
            return buf.array()
        } finally {
            try { r.release() } catch (_: Exception) {}
        }
    }

    /**
     * صور مصغّرة لمسار الفيديو بالخط الزمني (الواجهة الجديدة): [count] إطار موزّعين
     * على المدة، أقرب إطار مفتاحي (سريع)، بارتفاع [height] بكسل، كـ JPEG. الإطار
     * اللي ما انقرأ = مصفوفة فاضية (بيضل الترتيب نفسه).
     */
    fun thumbnails(
        path: String, durationMs: Long, count: Int, height: Int, portrait: Boolean?
    ): List<ByteArray> {
        val r = MediaMetadataRetriever()
        val out = ArrayList<ByteArray>(count)
        try {
            r.setDataSource(path)
            val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val durUs = if (durationMs > 0) durationMs * 1000L else
                (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000L
            for (i in 0 until count) {
                try {
                    val t = if (count <= 1) 0L else durUs * (2L * i + 1L) / (2L * count)
                    val raw = r.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    if (raw == null) {
                        out.add(ByteArray(0))
                        continue
                    }
                    val isPortrait = raw.height > raw.width
                    val upright = if (portrait != null && rotation % 180 != 0 &&
                        raw.width != raw.height && isPortrait != portrait
                    ) {
                        Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height,
                            Matrix().apply { postRotate(rotation.toFloat()) }, true)
                    } else raw
                    val w = maxOf(1, upright.width * height / maxOf(1, upright.height))
                    val scaled = Bitmap.createScaledBitmap(upright, w, height, true)
                    val bos = ByteArrayOutputStream()
                    scaled.compress(Bitmap.CompressFormat.JPEG, 72, bos)
                    out.add(bos.toByteArray())
                    if (scaled !== upright) scaled.recycle()
                    if (upright !== raw) upright.recycle()
                    raw.recycle()
                } catch (e: Exception) {
                    out.add(ByteArray(0))
                }
            }
        } finally {
            try { r.release() } catch (_: Exception) {}
        }
        return out
    }
}
