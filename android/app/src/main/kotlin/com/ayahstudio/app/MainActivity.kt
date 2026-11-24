package com.ayahstudio.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import androidx.media3.common.util.UnstableApi
import java.io.File
import java.util.concurrent.Executors

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class MainActivity : FlutterActivity() {
    private val audioExecutor = Executors.newSingleThreadExecutor()

    // --- يوم 5: اختيار ملف صوت/فيديو عام (زر التجربة) ---
    private var pendingPick: MethodChannel.Result? = null

    // --- يوم 6: اختيار فيديو من المعرض (Photo Picker أو SAF) ---
    private var pendingGalleryPick: MethodChannel.Result? = null
    private var galleryProgressSink: EventChannel.EventSink? = null

    // --- يوم 6: تصوير بالكاميرا ---
    private var pendingCameraRecord: MethodChannel.Result? = null
    private var pendingCameraFile: File? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    // --- يوم 8: التصدير (صلاحيات وقت الحاجة + حالة الخدمة للـ Dart) ---
    private var pendingNotifPermission: MethodChannel.Result? = null
    private var pendingStoragePermission: MethodChannel.Result? = null
    private var exportStatusSink: EventChannel.EventSink? = null
    private val exportListener: (Map<String, Any?>) -> Unit = { exportStatusSink?.success(it) }

    companion object {
        private const val PICK_MEDIA = 4201
        private const val PICK_GALLERY_VIDEO = 4202
        private const val RECORD_VIDEO = 4203
        private const val REQUEST_CAMERA_PERMS = 4204
        private const val REQUEST_NOTIFICATIONS = 4205
        private const val REQUEST_STORAGE = 4206
        private val CAMERA_PERMISSIONS = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureAudioChannel(flutterEngine)
        configurePickerChannel(flutterEngine)
        configureVideoInfoChannel(flutterEngine)
        configureGalleryChannel(flutterEngine)
        configureCameraChannel(flutterEngine)
        configureExportChannel(flutterEngine)
    }

    override fun onDestroy() {
        ExportHub.removeListener(exportListener)
        super.onDestroy()
    }

    // =====================================================================
    // يوم 8: التصدير (ExportService بالخلفية) — بدء/إلغاء/حالة، مشاركة وفتح
    // الناتج، وصلاحيتي الإشعارات (13+) والتخزين (7–9 بس) وقت الحاجة.
    // =====================================================================
    private fun configureExportChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/export")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val plan = call.argument<String>("plan")
                        if (plan == null) {
                            result.error("ARGS", "plan مطلوب", null)
                        } else if (ExportHub.isRunning) {
                            result.error("BUSY", "في تصدير شغّال", null)
                        } else {
                            try {
                                ExportService.start(this, plan)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("START", e.message ?: e.toString(), null)
                            }
                        }
                    }
                    "cancel" -> {
                        ExportService.cancel(this)
                        result.success(null)
                    }
                    "getStatus" -> result.success(ExportHub.status)
                    "share", "open" -> {
                        val uri = ExportService.shareableUri(this, ExportHub.status)
                        if (uri == null) {
                            result.error("NO_OUTPUT", "ما في فيديو جاهز", null)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(
                                if (call.method == "share") ExportNotifications.shareIntent(uri)
                                else ExportNotifications.viewIntent(uri)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NO_APP", e.message ?: e.toString(), null)
                        }
                    }
                    "saveToGallery" -> saveLastToGallery(result)
                    "notificationsEnabled" -> result.success(
                        androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled()
                    )
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < 33 ||
                            hasPermission(Manifest.permission.POST_NOTIFICATIONS)
                        ) {
                            result.success(true)
                        } else if (pendingNotifPermission != null) {
                            result.error("BUSY", "في طلب صلاحية شغّال", null)
                        } else {
                            pendingNotifPermission = result
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS
                            )
                        }
                    }
                    "requestStoragePermission" -> {
                        if (GallerySaver.canSave(this)) {
                            result.success(true)
                        } else if (pendingStoragePermission != null) {
                            result.error("BUSY", "في طلب صلاحية شغّال", null)
                        } else {
                            pendingStoragePermission = result
                            ActivityCompat.requestPermissions(
                                this, arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_STORAGE
                            )
                        }
                    }
                    "freeBytes" -> {
                        val path = call.argument<String>("path") ?: cacheDir.absolutePath
                        result.success(
                            try { android.os.StatFs(path).availableBytes } catch (_: Exception) { -1L }
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/export/status")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    exportStatusSink = events
                    ExportHub.addListener(exportListener)
                }
                override fun onCancel(arguments: Any?) {
                    ExportHub.removeListener(exportListener)
                    exportStatusSink = null
                }
            })
    }

    /** إعادة محاولة الحفظ بالمعرض (مثلاً بعد ما المستخدم أعطى صلاحية التخزين). */
    private fun saveLastToGallery(result: MethodChannel.Result) {
        val st = ExportHub.status
        if (st["phase"] != "done") {
            result.error("NO_OUTPUT", "ما في فيديو جاهز", null)
            return
        }
        if (st["savedToGallery"] == true) {
            result.success(true)
            return
        }
        val path = st["outputPath"] as? String
        if (path == null || !File(path).exists()) {
            result.error("NO_OUTPUT", "ملف الفيديو مش موجود", null)
            return
        }
        val name = File(path).name.let { if (it.startsWith("AyahStudio")) it else "AyahStudio_$it" }
        audioExecutor.execute {
            try {
                val saved = GallerySaver.save(this, File(path), name) {}
                ExportHub.update(
                    st + mapOf(
                        "savedToGallery" to true,
                        "contentUri" to saved.uri.toString(),
                        "galleryPath" to saved.displayPath,
                    )
                )
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("SAVE", e.message ?: e.toString(), null) }
            }
        }
    }

    // =====================================================================
    // فك الصوت (lib/asr/native_audio_decoder.dart) — يوم 4، سرّع يوم 6.
    // =====================================================================
    private fun configureAudioChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "decodeToMonoWav" -> {
                        val input = call.argument<String>("input")
                        val output = call.argument<String>("output")
                        if (input == null || output == null) {
                            result.error("ARGS", "input و output مطلوبين", null)
                            return@setMethodCallHandler
                        }
                        audioExecutor.execute {
                            try {
                                val r = AudioDecoder.decodeToMonoWav(input, output)
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "sampleRate" to r.sampleRate,
                                            "channels" to r.channels,
                                            "frames" to r.frames,
                                            "mime" to r.mime,
                                            "elapsedMs" to r.elapsedMs,
                                            "extractorMs" to r.extractorMs,
                                            "decodeMs" to r.decodeMs,
                                            "writeMs" to r.writeMs,
                                        )
                                    )
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("DECODE", e.message ?: e.toString(), null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // =====================================================================
    // يوم 5: اختيار ملف صوت/فيديو عام (زر التجربة، SAF، بدون صلاحيات).
    // =====================================================================
    private fun configurePickerChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/picker")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickMedia" -> {
                        if (pendingPick != null) {
                            result.error("BUSY", "في اختيار ملف شغّال", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "video/*"))
                        }
                        pendingPick = result
                        try {
                            startActivityForResult(intent, PICK_MEDIA)
                        } catch (e: Exception) {
                            pendingPick = null
                            result.error("PICK", e.message ?: e.toString(), null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // =====================================================================
    // يوم 6: معلومات الفيديو (MediaExtractor/MediaMetadataRetriever).
    // =====================================================================
    private fun configureVideoInfoChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/video")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInfo" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARGS", "path مطلوب", null)
                            return@setMethodCallHandler
                        }
                        audioExecutor.execute {
                            try {
                                val info = VideoInfoReader.read(path)
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "width" to info.width,
                                            "height" to info.height,
                                            "rotation" to info.rotation,
                                            "durationMs" to info.durationMs,
                                            "fps" to info.fps,
                                            "hasAudioTrack" to info.hasAudioTrack,
                                        )
                                    )
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("VIDEO_INFO", e.message ?: e.toString(), null) }
                            }
                        }
                    }
                    // يوم 8: إطار RGBA (تجربة التصدير بالمحاكي، وصور مصغّرة لاحقاً).
                    "frameRgba" -> {
                        val path = call.argument<String>("path")
                        val timeUs = (call.argument<Number>("timeUs") ?: 0).toLong()
                        val w = call.argument<Int>("width") ?: 0
                        val h = call.argument<Int>("height") ?: 0
                        if (path == null || w <= 0 || h <= 0) {
                            result.error("ARGS", "path/width/height مطلوبين", null)
                            return@setMethodCallHandler
                        }
                        audioExecutor.execute {
                            try {
                                val bytes = FrameGrabber.rgbaAt(path, timeUs, w, h)
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("FRAME", e.message ?: e.toString(), null) }
                            }
                        }
                    }
                    // يوم 7: سطوع منطقة النص (لاختيار نص أبيض أو أسود تلقائياً).
                    "textBandBrightness" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARGS", "path مطلوب", null)
                            return@setMethodCallHandler
                        }
                        val durationMs = (call.argument<Number>("durationMs") ?: 0).toLong()
                        val expectPortrait = call.argument<Boolean>("expectPortrait")
                        audioExecutor.execute {
                            try {
                                val b = FrameBrightness.measure(path, durationMs, expectPortrait)
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "luma" to b.luma,
                                            "brightFraction" to b.brightFraction,
                                            "frames" to b.frames,
                                        )
                                    )
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("BRIGHTNESS", e.message ?: e.toString(), null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // =====================================================================
    // يوم 6: اختيار فيديو من المعرض — Android Photo Picker (فيديو بس،
    // بدون صلاحيات)، ولو مش متوفر SAF. النسخ من الـ Uri بتقدّم (بدون ما
    // "يتعلّق" التطبيق مع الفيديوهات الكبيرة).
    // =====================================================================
    private fun configureGalleryChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/gallery")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickVideo" -> {
                        if (pendingGalleryPick != null) {
                            result.error("BUSY", "في اختيار فيديو شغّال", null)
                            return@setMethodCallHandler
                        }
                        pendingGalleryPick = result
                        val photoPicker = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                            type = "video/*"
                            putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 1)
                        }
                        val useSaf = packageManager.resolveActivity(photoPicker, 0) == null
                        val intent = if (useSaf) {
                            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "video/*"
                            }
                        } else {
                            photoPicker
                        }
                        try {
                            startActivityForResult(intent, PICK_GALLERY_VIDEO)
                        } catch (e: Exception) {
                            pendingGalleryPick = null
                            result.error("PICK", e.message ?: e.toString(), null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/gallery/progress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    galleryProgressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    galleryProgressSink = null
                }
            })
    }

    // =====================================================================
    // يوم 6: التصوير بالكاميرا من جوا التطبيق (فيديو مع صوت). intent
    // الكاميرا (ACTION_VIDEO_CAPTURE) عبر FileProvider، بدل مكتبة كاميرا
    // خارجية (تجنّب مشاكل توافق AGP 9.3.1 / Built-in Kotlin). صلاحيات
    // CAMERA و RECORD_AUDIO بوقت الحاجة بس.
    // =====================================================================
    private fun configureCameraChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ayahstudio.app/camera")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermissions" -> result.success(
                        mapOf(
                            "camera" to hasPermission(Manifest.permission.CAMERA),
                            "audio" to hasPermission(Manifest.permission.RECORD_AUDIO),
                        )
                    )
                    "requestPermissions" -> {
                        if (pendingPermissionResult != null) {
                            result.error("BUSY", "في طلب صلاحيات شغّال", null)
                            return@setMethodCallHandler
                        }
                        if (hasPermission(Manifest.permission.CAMERA) &&
                            hasPermission(Manifest.permission.RECORD_AUDIO)
                        ) {
                            result.success(mapOf("camera" to true, "audio" to true))
                            return@setMethodCallHandler
                        }
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(this, CAMERA_PERMISSIONS, REQUEST_CAMERA_PERMS)
                    }
                    "recordVideo" -> {
                        if (pendingCameraRecord != null) {
                            result.error("BUSY", "في تصوير شغّال", null)
                            return@setMethodCallHandler
                        }
                        if (!hasPermission(Manifest.permission.CAMERA) ||
                            !hasPermission(Manifest.permission.RECORD_AUDIO)
                        ) {
                            result.error(
                                "PERMISSION_DENIED",
                                "لازم صلاحية الكاميرا والمايكروفون قبل التصوير", null
                            )
                            return@setMethodCallHandler
                        }
                        val captureIntent = Intent(MediaStore.ACTION_VIDEO_CAPTURE)
                        if (packageManager.resolveActivity(captureIntent, 0) == null) {
                            result.error("NO_CAMERA_APP", "ما في تطبيق كاميرا على الجوال", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val dir = File(cacheDir, "camera").apply { mkdirs() }
                            val file = File(dir, "video_${System.currentTimeMillis()}.mp4")
                            val uri: Uri = FileProvider.getUriForFile(
                                this, "$packageName.fileprovider", file
                            )
                            captureIntent.putExtra(MediaStore.EXTRA_OUTPUT, uri)
                            captureIntent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            captureIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            pendingCameraRecord = result
                            pendingCameraFile = file
                            startActivityForResult(captureIntent, RECORD_VIDEO)
                        } catch (e: Exception) {
                            pendingCameraRecord = null
                            pendingCameraFile = null
                            result.error("CAMERA", e.message ?: e.toString(), null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasPermission(permission: String) =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) {
            val r = pendingNotifPermission ?: return
            pendingNotifPermission = null
            r.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            return
        }
        if (requestCode == REQUEST_STORAGE) {
            val r = pendingStoragePermission ?: return
            pendingStoragePermission = null
            r.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            return
        }
        if (requestCode != REQUEST_CAMERA_PERMS) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        result.success(
            mapOf(
                "camera" to hasPermission(Manifest.permission.CAMERA),
                "audio" to hasPermission(Manifest.permission.RECORD_AUDIO),
            )
        )
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            PICK_MEDIA -> handleGenericPickResult(resultCode, data)
            PICK_GALLERY_VIDEO -> handleGalleryPickResult(resultCode, data)
            RECORD_VIDEO -> handleCameraRecordResult(resultCode, data)
        }
    }

    private fun handleGenericPickResult(resultCode: Int, data: Intent?) {
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        audioExecutor.execute {
            try {
                val name = displayName(uri) ?: "picked"
                val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val out = File(cacheDir, "picked_${System.currentTimeMillis()}_$safe")
                val input = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("ما قدرت أفتح الملف")
                input.use { src -> out.outputStream().use { dst -> src.copyTo(dst) } }
                runOnUiThread {
                    result.success(
                        mapOf("path" to out.absolutePath, "name" to name, "bytes" to out.length())
                    )
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("COPY", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun handleGalleryPickResult(resultCode: Int, data: Intent?) {
        val result = pendingGalleryPick ?: return
        pendingGalleryPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        audioExecutor.execute {
            try {
                val dir = File(cacheDir, "gallery")
                val copied = MediaCopier.copy(contentResolver, uri, dir, "video.mp4") { copied, total ->
                    runOnUiThread {
                        galleryProgressSink?.success(
                            mapOf("copiedBytes" to copied, "totalBytes" to total)
                        )
                    }
                }
                runOnUiThread {
                    result.success(
                        mapOf("path" to copied.path, "name" to copied.name, "bytes" to copied.bytes)
                    )
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("COPY", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun handleCameraRecordResult(resultCode: Int, data: Intent?) {
        val result = pendingCameraRecord ?: return
        val file = pendingCameraFile
        pendingCameraRecord = null
        pendingCameraFile = null
        if (resultCode != Activity.RESULT_OK || file == null) {
            result.success(null)
            return
        }
        // أغلب تطبيقات الكاميرا بتكتب على الـ Uri المُعطى (EXTRA_OUTPUT)، بس
        // بعضها بيرجع Uri لحاله بـ data.data — بهالحالة ننسخه لمكانه المتوقع.
        if (file.exists() && file.length() > 0) {
            result.success(mapOf("path" to file.absolutePath, "name" to file.name, "bytes" to file.length()))
            return
        }
        val returnedUri = data?.data
        if (returnedUri == null) {
            result.error("CAMERA", "ما رجع التصوير ملف فيديو", null)
            return
        }
        audioExecutor.execute {
            try {
                val copied = MediaCopier.copy(contentResolver, returnedUri, file.parentFile!!, file.name)
                runOnUiThread {
                    result.success(
                        mapOf("path" to copied.path, "name" to copied.name, "bytes" to copied.bytes)
                    )
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("CAMERA", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
}
