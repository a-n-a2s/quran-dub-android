package com.ayahstudio.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private var pendingPick: MethodChannel.Result? = null

    companion object {
        private const val PICK_MEDIA = 4201
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // فك أي ملف صوت/فيديو لـ WAV mono (lib/asr/native_audio_decoder.dart).
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

        // يوم 5: اختيار ملف صوت/فيديو (Storage Access Framework، بدون صلاحيات
        // وبدون مكتبة خارجية). بننسخه لـ cache وبنرجّع المسار.
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

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_MEDIA) return
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

    private fun displayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
}
