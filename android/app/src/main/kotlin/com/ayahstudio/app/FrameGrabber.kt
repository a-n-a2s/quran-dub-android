package com.ayahstudio.app

import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
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
}
