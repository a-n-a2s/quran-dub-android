package com.ayahstudio.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import java.io.File
import java.util.concurrent.Executors

/**
 * خدمة التصدير بالخلفية (يوم 8، المواصفات القسم 6): Media3 Transformer بيرمّز
 * الفيديو (H.264 + AAC بـ MP4) بنفس أبعاد المقطع، وفوقه صور النص اللي رسمها
 * Flutter ([AyahCueOverlay]). Foreground service عشان يكمّل لو المستخدم طلع من
 * التطبيق، مع إشعار تقدّم (فيه "إلغاء") وإشعار "خلص" (فتح/مشاركة).
 *
 * نوع الخدمة: `mediaProcessing` على أندرويد 15+ (النوع المخصّص لترميز
 * الوسائط)، و`dataSync` على أندرويد 14 (mediaProcessing مش موجود هناك)، وبدون
 * نوع على الأقدم. الاثنين إلهم حد 6 ساعات باليوم على أندرويد 15 ([onTimeout]).
 */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class ExportService : Service() {
    companion object {
        const val ACTION_START = "com.ayahstudio.app.export.START"
        const val ACTION_CANCEL = "com.ayahstudio.app.export.CANCEL"
        const val EXTRA_PLAN = "plan"
        private const val TAG = "AyahExport"

        fun start(ctx: Context, planPath: String) {
            val i = Intent(ctx, ExportService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_PLAN, planPath)
            ContextCompat.startForegroundService(ctx, i)
        }

        fun cancel(ctx: Context) {
            if (!ExportHub.isRunning) return
            ctx.startService(Intent(ctx, ExportService::class.java).setAction(ACTION_CANCEL))
        }

        /** Uri للمشاركة/الفتح: المعرض لو انحفظ، وإلا FileProvider للملف. */
        fun shareableUri(ctx: Context, status: Map<String, Any?>): Uri? {
            (status["contentUri"] as? String)?.let { return Uri.parse(it) }
            val path = status["outputPath"] as? String ?: return null
            val f = File(path)
            if (!f.exists()) return null
            return FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f)
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val progressHolder = ProgressHolder()
    private var transformer: Transformer? = null
    private var plan: ExportPlan? = null
    private var overlay: AyahCueOverlay? = null
    private var startedAt = 0L
    private var lastPercent = -1
    private var keepWorkFiles = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val path = intent.getStringExtra(EXTRA_PLAN)
                goForeground("تجهيز…", 0, true)
                if (transformer != null) {
                    // تصدير شغّال: الواجهة بتمنع هالحالة، بس للاحتياط.
                    Log.w(TAG, "export already running, ignoring new request")
                    return START_NOT_STICKY
                }
                if (path == null) {
                    fail("unknown", "ما في خطة تصدير")
                } else {
                    begin(path)
                }
            }
            ACTION_CANCEL -> cancelExport()
            else -> if (transformer == null) stopSelf()
        }
        // ما بنرجع لحالنا لو النظام قتل العملية: الخطة والصور بتكون راحت.
        return START_NOT_STICKY
    }

    private fun goForeground(text: String, percent: Int, indeterminate: Boolean) {
        ExportNotifications.ensureChannels(this)
        val n = ExportNotifications.progress(this, plan?.title ?: "", percent, indeterminate, text)
        val type = when {
            Build.VERSION.SDK_INT >= 35 -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            Build.VERSION.SDK_INT >= 34 -> ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            else -> 0
        }
        ServiceCompat.startForeground(this, ExportNotifications.ID_PROGRESS, n, type)
    }

    private fun updateNotification(text: String, percent: Int, indeterminate: Boolean) {
        val n = ExportNotifications.progress(this, plan?.title ?: "", percent, indeterminate, text)
        androidx.core.app.NotificationManagerCompat.from(this).let {
            if (it.areNotificationsEnabled()) {
                @Suppress("MissingPermission")
                it.notify(ExportNotifications.ID_PROGRESS, n)
            }
        }
    }

    private fun status(phase: String, fraction: Double = 0.0, extra: Map<String, Any?> = emptyMap()) {
        ExportHub.update(mapOf("id" to plan?.id, "phase" to phase, "fraction" to fraction) + extra)
    }

    private fun begin(planPath: String) {
        val p = try {
            ExportPlan.read(planPath)
        } catch (e: Exception) {
            fail("unknown", "خطة التصدير مش مقروءة: ${e.message}")
            return
        }
        plan = p
        keepWorkFiles = try {
            org.json.JSONObject(File(planPath).readText()).optBoolean("keepWorkFiles", false)
        } catch (_: Exception) { false }
        ExportNotifications.cancelDone(this)

        if (!File(p.input).exists() || (p.audioKind == "external" && !File(p.audioPath ?: "").exists())) {
            fail("inputMissing", "input=${p.input} audio=${p.audioPath}")
            return
        }
        for (c in p.cues) {
            if (!File(c.png).exists()) {
                fail("overlay", "صورة ناقصة: ${c.png}")
                return
            }
        }
        // مساحة: الملف المؤقت + نسخة المعرض + هامش.
        val outFile = File(p.output)
        outFile.parentFile?.mkdirs()
        val free = try { StatFs(outFile.parentFile!!.absolutePath).availableBytes } catch (_: Exception) { Long.MAX_VALUE }
        val needed = p.estimatedBytes * 2 + 50L * 1024 * 1024
        if (free < needed) {
            fail("noSpace", "free=$free needed=$needed")
            return
        }
        outFile.delete()

        try {
            val ov = AyahCueOverlay(p)
            overlay = ov
            val composition = buildComposition(p, ov)
            val encoderFactory = DefaultEncoderFactory.Builder(this)
                .setRequestedVideoEncoderSettings(
                    VideoEncoderSettings.Builder().setBitrate(p.videoBitrate).build()
                )
                .setRequestedAudioEncoderSettings(
                    AudioEncoderSettings.Builder().setBitrate(p.audioBitrate).build()
                )
                .setEnableFallback(true)
                .build()
            val t = Transformer.Builder(this)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)
                .addListener(listener)
                .build()
            transformer = t
            startedAt = SystemClock.elapsedRealtime()
            lastPercent = -1
            status("encoding", 0.0)
            t.start(composition, p.output)
            main.post(pollProgress)
        } catch (e: Exception) {
            Log.e(TAG, "start failed", e)
            transformer = null
            fail("unknown", e.toString())
        }
    }

    /**
     * الفيديو بأبعاد الناتج (زوجية؛ `SCALE_TO_FIT_WITH_CROP` = بدون تمطيط،
     * لو ضلع فردي بينقص بكسل) + طبقة النص. Media3 بيلف الإطارات حسب دوران
     * الملف قبل الـ effects، فالنص دايماً على الفيديو المستقيم زي المعاينة.
     *
     * الصوت (يوم 11 بيضيف التوطية/الدمج هون بس):
     * - original: صوت الفيديو زي ما هو (AAC بينسخ بدون إعادة ترميز).
     * - external: صوت الفيديو مكتوم، وملف التلاوة مقصوص على مدة الفيديو.
     * - none: بدون صوت.
     */
    private fun buildComposition(p: ExportPlan, ov: AyahCueOverlay): Composition {
        val effects = Effects(
            ImmutableList.of<AudioProcessor>(),
            ImmutableList.of<Effect>(
                Presentation.createForWidthAndHeight(p.width, p.height, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP),
                OverlayEffect(ImmutableList.of<TextureOverlay>(ov)),
            )
        )
        val keepAudio = p.audioKind == "original"
        val video = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(p.input))))
            .setEffects(effects)
            .setRemoveAudio(!keepAudio)
            .build()
        val videoSeq = if (keepAudio) {
            EditedMediaItemSequence.withAudioAndVideoFrom(listOf(video))
        } else {
            EditedMediaItemSequence.withVideoFrom(listOf(video))
        }
        if (p.audioKind != "external") return Composition.Builder(videoSeq).build()

        val clip = MediaItem.ClippingConfiguration.Builder()
        if (p.durationMs > 0) clip.setEndPositionMs(p.durationMs)
        val audioItem = MediaItem.Builder()
            .setUri(Uri.fromFile(File(p.audioPath!!)))
            .setClippingConfiguration(clip.build())
            .build()
        val audio = EditedMediaItem.Builder(audioItem).setRemoveVideo(true).build()
        return Composition.Builder(videoSeq, EditedMediaItemSequence.withAudioFrom(listOf(audio))).build()
    }

    private val pollProgress = object : Runnable {
        override fun run() {
            val t = transformer ?: return
            val state = t.getProgress(progressHolder)
            if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                val pct = progressHolder.progress
                if (pct != lastPercent) {
                    lastPercent = pct
                    status("encoding", pct / 100.0)
                    updateNotification("$pct٪", pct, false)
                }
            } else if (state == Transformer.PROGRESS_STATE_UNAVAILABLE && lastPercent < 0) {
                lastPercent = 0
                updateNotification("جاري التصدير…", 0, true)
            }
            main.postDelayed(this, 500)
        }
    }

    private val listener = object : Transformer.Listener {
        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
            main.removeCallbacks(pollProgress)
            transformer = null
            onEncoded(exportResult)
        }

        override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
            main.removeCallbacks(pollProgress)
            transformer = null
            Log.e(TAG, "export failed", exportException)
            val p = plan
            val lowSpace = p != null && try {
                StatFs(File(p.output).parentFile!!.absolutePath).availableBytes < 20L * 1024 * 1024
            } catch (_: Exception) { false }
            val kind = when {
                lowSpace -> "noSpace"
                else -> when (exportException.errorCode) {
                    ExportException.ERROR_CODE_ENCODER_INIT_FAILED,
                    ExportException.ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED,
                    ExportException.ERROR_CODE_ENCODING_FAILED -> "encoderUnsupported"
                    ExportException.ERROR_CODE_DECODER_INIT_FAILED,
                    ExportException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
                    ExportException.ERROR_CODE_DECODING_FAILED -> "decoderUnsupported"
                    ExportException.ERROR_CODE_IO_FILE_NOT_FOUND -> "inputMissing"
                    ExportException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED -> "overlay"
                    in 2000..2999, ExportException.ERROR_CODE_MUXING_FAILED -> "io"
                    else -> "unknown"
                }
            }
            p?.let { File(it.output).delete() }
            fail(kind, "${exportException.errorCodeName}: ${exportException.message}")
        }
    }

    private fun onEncoded(r: ExportResult) {
        val p = plan ?: return
        val out = File(p.output)
        val base = mapOf(
            "outputPath" to out.absolutePath,
            "width" to r.width,
            "height" to r.height,
            "fileSizeBytes" to out.length(),
            "durationMs" to r.approximateDurationMs,
            "elapsedMs" to (SystemClock.elapsedRealtime() - startedAt),
            "videoEncoder" to r.videoEncoderName,
            "averageVideoBitrate" to r.averageVideoBitrate,
            "overlayImagesLoaded" to (overlay?.loadedCount ?: 0),
        )
        status("saving", 0.0, base)
        updateNotification("الحفظ بالمعرض…", 100, true)
        io.execute {
            var extra: Map<String, Any?> = mapOf("savedToGallery" to false)
            var uri: Uri? = null
            if (GallerySaver.canSave(this)) {
                try {
                    val saved = GallerySaver.save(this, out, p.fileName) { f ->
                        status("saving", f.toDouble(), base)
                    }
                    uri = saved.uri
                    extra = mapOf(
                        "savedToGallery" to true,
                        "contentUri" to saved.uri.toString(),
                        "galleryPath" to saved.displayPath,
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "gallery save failed", e)
                    extra = mapOf("savedToGallery" to false, "saveError" to e.toString())
                }
            }
            val saved = extra["savedToGallery"] == true
            if (saved && !keepWorkFiles) out.delete()
            cleanupWork(p)
            main.post {
                val final = base + extra + mapOf("outputPath" to (if (out.exists()) out.absolutePath else null))
                ExportHub.update(mapOf("id" to p.id, "phase" to "done", "fraction" to 1.0) + final)
                val shareUri = uri ?: shareableUri(this, final)
                finishForeground()
                if (shareUri != null) ExportNotifications.done(this, p.title, shareUri, saved)
                stopSelf()
            }
        }
    }

    private fun cancelExport() {
        val t = transformer
        main.removeCallbacks(pollProgress)
        if (t != null) {
            try { t.cancel() } catch (e: Exception) { Log.w(TAG, "cancel", e) }
        }
        transformer = null
        plan?.let {
            File(it.output).delete()
            cleanupWork(it)
        }
        ExportHub.update(mapOf("id" to plan?.id, "phase" to "cancelled", "fraction" to 0.0))
        finishForeground()
        stopSelf()
    }

    private fun fail(kind: String, detail: String) {
        Log.e(TAG, "fail $kind: $detail")
        ExportHub.update(
            mapOf("id" to plan?.id, "phase" to "failed", "error" to kind, "errorDetail" to detail, "fraction" to 0.0)
        )
        plan?.let { cleanupWork(it) }
        finishForeground()
        ExportNotifications.failed(this, plan?.title ?: "", errorMessage(kind))
        stopSelf()
    }

    private fun errorMessage(kind: String) = when (kind) {
        "noSpace" -> "المساحة على الجوال ما بتكفي."
        "encoderUnsupported" -> "الجوال ما بيدعم ترميز فيديو بهالأبعاد."
        "decoderUnsupported" -> "ما قدرنا نقرأ صيغة الفيديو الأصلي."
        "inputMissing" -> "ملف الفيديو الأصلي مش موجود."
        "timeout" -> "أندرويد وقّف التصدير لأنه طوّل كتير بالخلفية."
        else -> "صار خطأ بالتصدير. افتح التطبيق للتفاصيل."
    }

    /** صور النص وملف الخطة (بمجلد التصدير) ما عاد إلهم لزوم. */
    private fun cleanupWork(p: ExportPlan) {
        if (keepWorkFiles) return
        try {
            for (c in p.cues) File(c.png).delete()
            p.cues.firstOrNull()?.let { File(it.png).parentFile?.delete() }
        } catch (_: Exception) {}
    }

    private fun finishForeground() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }

    /** أندرويد 15: الخدمة وصلت حد الوقت (6 ساعات باليوم) → لازم نوقف فوراً. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        val t = transformer
        main.removeCallbacks(pollProgress)
        try { t?.cancel() } catch (_: Exception) {}
        transformer = null
        plan?.let { File(it.output).delete() }
        fail("timeout", "fgs timeout type=$fgsType")
    }

    override fun onDestroy() {
        main.removeCallbacks(pollProgress)
        transformer?.let {
            try { it.cancel() } catch (_: Exception) {}
            transformer = null
            ExportHub.update(mapOf("id" to plan?.id, "phase" to "cancelled", "fraction" to 0.0))
        }
        io.shutdown()
        super.onDestroy()
    }
}

