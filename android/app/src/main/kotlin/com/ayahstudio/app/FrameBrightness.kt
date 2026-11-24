package com.ayahstudio.app

import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.IOException

/**
 * يوم 7 (بعد تجربة أنس: النص الأبيض ما بيّن فوق فيديو خلفيته فاتحة):
 * بيقيس سطوع الفيديو **بمنطقة النص** (من 58% لـ 92% من الارتفاع، وبعيد عن
 * الحواف) بكم إطار موزّعين على المقطع، عشان التطبيق يختار لون النص الأوضح
 * (أبيض أو أسود) تلقائياً. المستخدم بيقدر يغيّره بالزر.
 *
 * MediaMetadataRetriever بيرجّع الإطار مصغّر (≤ 192px) ومعدول حسب الدوران
 * على أغلب الأجهزة؛ لو طلع مش معدول (الشكل عكس المتوقع) بنعدله بإيدنا.
 */
object FrameBrightness {
    data class Result(val luma: Double, val brightFraction: Double, val frames: Int)

    private const val BAND_TOP = 0.58
    private const val BAND_BOTTOM = 0.92
    private const val BAND_SIDE = 0.06
    private const val BRIGHT = 0.7

    @Throws(IOException::class)
    fun measure(path: String, durationMs: Long, expectPortrait: Boolean?, samples: Int = 6): Result {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0
            val dur = if (durationMs > 0) durationMs else
                (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L)
            var sumLuma = 0.0
            var sumBright = 0.0
            var n = 0
            for (k in 0 until samples) {
                val tUs = if (dur > 0) dur * 1000L * (2 * k + 1) / (2 * samples) else 0L
                val raw = frameAt(r, tUs) ?: continue
                val bmp = upright(raw, rotation, expectPortrait)
                val (l, b) = bandStats(bmp)
                if (bmp !== raw) bmp.recycle()
                raw.recycle()
                sumLuma += l
                sumBright += b
                n++
            }
            if (n == 0) throw IOException("ما قدرنا نقرأ إطارات من الفيديو")
            return Result(sumLuma / n, sumBright / n, n)
        } finally {
            try { r.release() } catch (_: Exception) {}
        }
    }

    private fun frameAt(r: MediaMetadataRetriever, tUs: Long): Bitmap? {
        val opt = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
        return if (Build.VERSION.SDK_INT >= 27) {
            r.getScaledFrameAtTime(tUs, opt, 192, 192)
        } else {
            val full = r.getFrameAtTime(tUs, opt) ?: return null
            val scale = 192.0 / maxOf(full.width, full.height)
            if (scale >= 1.0) return full
            val small = Bitmap.createScaledBitmap(
                full, maxOf(1, (full.width * scale).toInt()), maxOf(1, (full.height * scale).toInt()), true)
            if (small !== full) full.recycle()
            small
        }
    }

    /** لو الإطار مش معدول حسب الدوران (عمودي/أفقي عكس المتوقع)، بنعدله. */
    private fun upright(b: Bitmap, rotation: Int, expectPortrait: Boolean?): Bitmap {
        if (expectPortrait == null || rotation % 180 == 0 || b.width == b.height) return b
        val isPortrait = b.height > b.width
        if (isPortrait == expectPortrait) return b
        val m = Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(b, 0, 0, b.width, b.height, m, true)
    }

    /** (متوسط السطوع 0..1، نسبة البكسلات الفاتحة) بمنطقة النص. */
    private fun bandStats(b: Bitmap): Pair<Double, Double> {
        val w = b.width
        val h = b.height
        val y0 = (h * BAND_TOP).toInt().coerceIn(0, h - 1)
        val y1 = (h * BAND_BOTTOM).toInt().coerceIn(y0 + 1, h)
        val x0 = (w * BAND_SIDE).toInt().coerceIn(0, w - 1)
        val x1 = (w * (1 - BAND_SIDE)).toInt().coerceIn(x0 + 1, w)
        val row = IntArray(x1 - x0)
        var sum = 0.0
        var bright = 0
        var count = 0
        for (y in y0 until y1) {
            b.getPixels(row, 0, row.size, x0, y, row.size, 1)
            for (p in row) {
                val rr = (p shr 16) and 0xff
                val gg = (p shr 8) and 0xff
                val bb = p and 0xff
                val l = (0.2126 * rr + 0.7152 * gg + 0.0722 * bb) / 255.0
                sum += l
                if (l > BRIGHT) bright++
                count++
            }
        }
        if (count == 0) return Pair(0.0, 0.0)
        return Pair(sum / count, bright.toDouble() / count)
    }
}
