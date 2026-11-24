package com.ayahstudio.app

import org.json.JSONObject
import java.io.File

/**
 * خطة التصدير (يوم 8) زي ما بيكتبها Dart (`lib/export/export_plan.dart`، نفس
 * المفاتيح). الـ Kotlin ما بيرسم ولا بيحسب أي شي من شكل النص: بس بيحط الصور
 * الجاهزة فوق الإطارات بالتوقيت والشفافية اللي بالخطة.
 */
data class ExportPlan(
    val id: String,
    val input: String,
    /** "original" / "external" / "none" (يوم 11 بيضيف التوطية والدمج). */
    val audioKind: String,
    val audioPath: String?,
    val width: Int,
    val height: Int,
    val sourceWidth: Int,
    val sourceHeight: Int,
    val videoBitrate: Int,
    val audioBitrate: Int,
    val fps: Double,
    val durationMs: Long,
    val fileName: String,
    val output: String,
    val estimatedBytes: Long,
    val bandTop: Int,
    val bandHeight: Int,
    val cues: List<Cue>,
    val title: String,
) {
    /** صورة نص من [startUs] لـ [endUs]، وشفافيتها عينات (وقت، alpha) خطية. */
    class Cue(
        val startUs: Long,
        val endUs: Long,
        val png: String,
        private val keyTimesUs: LongArray,
        private val keyAlphas: FloatArray,
    ) {
        /** الشفافية بلحظة [tUs] (نفس OverlayTimeline.opacityOf بالـ Dart، بعينات). */
        fun alphaAt(tUs: Long): Float {
            val n = keyTimesUs.size
            if (n == 0) return 1f
            if (tUs <= keyTimesUs[0]) return keyAlphas[0]
            if (tUs >= keyTimesUs[n - 1]) return keyAlphas[n - 1]
            var lo = 0
            var hi = n - 1
            while (hi - lo > 1) {
                val mid = (lo + hi) ushr 1
                if (keyTimesUs[mid] <= tUs) lo = mid else hi = mid
            }
            val t0 = keyTimesUs[lo]
            val t1 = keyTimesUs[hi]
            val f = if (t1 > t0) (tUs - t0).toFloat() / (t1 - t0).toFloat() else 0f
            return (keyAlphas[lo] + (keyAlphas[hi] - keyAlphas[lo]) * f).coerceIn(0f, 1f)
        }
    }

    companion object {
        fun read(path: String): ExportPlan = parse(File(path).readText())

        fun parse(json: String): ExportPlan {
            val o = JSONObject(json)
            val audio = o.getJSONObject("audio")
            val band = o.getJSONObject("band")
            val cuesJson = o.getJSONArray("cues")
            val cues = ArrayList<Cue>(cuesJson.length())
            for (i in 0 until cuesJson.length()) {
                val c = cuesJson.getJSONObject(i)
                val keys = c.getJSONArray("alpha")
                val times = LongArray(keys.length())
                val alphas = FloatArray(keys.length())
                for (k in 0 until keys.length()) {
                    val pair = keys.getJSONArray(k)
                    times[k] = (pair.getDouble(0) * 1e6).toLong()
                    alphas[k] = pair.getDouble(1).toFloat()
                }
                cues.add(
                    Cue(
                        startUs = (c.getDouble("start") * 1e6).toLong(),
                        endUs = (c.getDouble("end") * 1e6).toLong(),
                        png = c.getString("png"),
                        keyTimesUs = times,
                        keyAlphas = alphas,
                    )
                )
            }
            cues.sortBy { it.startUs }
            return ExportPlan(
                id = o.getString("id"),
                input = o.getString("input"),
                audioKind = audio.getString("kind"),
                audioPath = if (audio.isNull("path")) null else audio.getString("path"),
                width = o.getInt("width"),
                height = o.getInt("height"),
                sourceWidth = o.optInt("sourceWidth", o.getInt("width")),
                sourceHeight = o.optInt("sourceHeight", o.getInt("height")),
                videoBitrate = o.getInt("videoBitrate"),
                audioBitrate = o.optInt("audioBitrate", 192000),
                fps = o.optDouble("fps", 30.0),
                durationMs = o.optLong("durationMs", 0L),
                fileName = o.getString("fileName"),
                output = o.getString("output"),
                estimatedBytes = o.optLong("estimatedBytes", 0L),
                bandTop = band.getInt("top"),
                bandHeight = band.getInt("height"),
                cues = cues,
                title = o.optString("title", ""),
            )
        }
    }
}
