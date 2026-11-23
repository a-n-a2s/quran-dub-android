package com.ayahstudio.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val audioExecutor = Executors.newSingleThreadExecutor()

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
    }
}
