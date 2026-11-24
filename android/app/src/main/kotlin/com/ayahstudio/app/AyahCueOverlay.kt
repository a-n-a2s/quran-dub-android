package com.ayahstudio.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.StaticOverlaySettings

/**
 * طبقة النص فوق إطارات الفيديو (يوم 8) لـ Media3 `OverlayEffect`.
 *
 * - بأي لحظة في مقطع واحد ظاهر بالأكثر (النوافذ ما بتتداخل، OverlayTimeline).
 *   صورته (PNG شفافة رسمها Flutter بـ AyahOverlayFrame) بتنقرأ مرة وحدة لما
 *   يبلّش المقطع، وبتضل لحد ما يبلّش اللي بعده.
 * - الصورة بحجمها بالبكسل (Media3 بيحافظ على حجم الـ overlay بالنسبة للإطار)،
 *   ومحطوطة على شريط الكتلة ([ExportPlan.bandTop]) بعرض الإطار كامل.
 * - الشفافية (fade) من [ExportPlan.Cue.alphaAt]، بدون إعادة رسم الصورة لكل إطار.
 */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class AyahCueOverlay(private val plan: ExportPlan) : BitmapOverlay() {
    private val transparent: Bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
    private var loadedIndex = -1
    private var loadedBitmap: Bitmap? = null

    /** للتقرير بعد التصدير: كم صورة انقرأت فعلاً. */
    @Volatile var loadedCount = 0
        private set

    // NDC (فوق = +1): مركز الشريط عمودياً، وبالنص أفقياً.
    private val bandAnchorY: Float =
        1f - 2f * (plan.bandTop + plan.bandHeight / 2f) / plan.height.toFloat()

    private fun cueIndexAt(tUs: Long): Int {
        val cues = plan.cues
        var lo = 0
        var hi = cues.size - 1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val c = cues[mid]
            when {
                tUs < c.startUs -> hi = mid - 1
                tUs >= c.endUs -> lo = mid + 1
                else -> return mid
            }
        }
        return -1
    }

    @Throws(VideoFrameProcessingException::class)
    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val i = cueIndexAt(presentationTimeUs)
        if (i < 0) return transparent
        if (i != loadedIndex) {
            val cue = plan.cues[i]
            val bmp = BitmapFactory.decodeFile(cue.png)
                ?: throw VideoFrameProcessingException("ما قدرنا نقرأ صورة النص: ${cue.png}")
            loadedBitmap = bmp
            loadedIndex = i
            loadedCount++
        }
        return loadedBitmap!!
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        val i = cueIndexAt(presentationTimeUs)
        val alpha = if (i < 0) 0f else plan.cues[i].alphaAt(presentationTimeUs)
        return StaticOverlaySettings.Builder()
            .setAlphaScale(alpha)
            .setBackgroundFrameAnchor(0f, bandAnchorY)
            .setOverlayFrameAnchor(0f, 0f)
            .build()
    }
}
