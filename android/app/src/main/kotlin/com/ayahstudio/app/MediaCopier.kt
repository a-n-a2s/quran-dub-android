package com.ayahstudio.app

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.IOException

/**
 * نسخ محتوى Uri (من المعرض أو SAF أو الكاميرا) لملف محلي، بتقدّم (بايتات
 * نسخت / الكلي لو معروف) — عشان التطبيق ما "يتعلّق" مع الفيديوهات الكبيرة
 * (المواصفات، يوم 6: "بدون ما يتعلّق التطبيق مع الفيديوهات الكبيرة، تقدّم
 * النسخ"). بنسخة واحدة Dart صافي ما بيقدر يستعملها (تحتاج ContentResolver
 * من أندرويد)، فهاي Kotlin بس بدون أي اعتماد على Activity.
 */
object MediaCopier {
    data class CopiedFile(val path: String, val name: String, val bytes: Long)

    /** اسم العرض وحجم الملف من `OpenableColumns` لو الـ Uri بيدعمهم. */
    fun displayNameAndSize(resolver: ContentResolver, uri: Uri): Pair<String?, Long?> {
        resolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null
        )?.use { c ->
            if (c.moveToFirst()) {
                val nameIdx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIdx = c.getColumnIndex(OpenableColumns.SIZE)
                val name = if (nameIdx >= 0) c.getString(nameIdx) else null
                val size = if (sizeIdx >= 0 && !c.isNull(sizeIdx)) c.getLong(sizeIdx) else null
                return name to size
            }
        }
        return null to null
    }

    /** بينسخ بـ buffer 1MB، وبيستدعي [onProgress] بعد كل chunk (ممكن يكون
     * [total] null لو الـ Uri ما بيرجّع حجمه مسبقاً). */
    @Throws(IOException::class)
    fun copy(
        resolver: ContentResolver,
        uri: Uri,
        destDir: File,
        fallbackName: String,
        onProgress: ((copied: Long, total: Long?) -> Unit)? = null,
    ): CopiedFile {
        val (rawName, size) = displayNameAndSize(resolver, uri)
        val name = rawName ?: fallbackName
        val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        destDir.mkdirs()
        val out = File(destDir, "${System.currentTimeMillis()}_$safe")
        val input = resolver.openInputStream(uri) ?: throw IOException("ما قدرت أفتح الملف")
        var copied = 0L
        input.use { src ->
            out.outputStream().use { dst ->
                val buf = ByteArray(1 shl 20) // 1MB
                while (true) {
                    val n = src.read(buf)
                    if (n < 0) break
                    dst.write(buf, 0, n)
                    copied += n
                    onProgress?.invoke(copied, size)
                }
            }
        }
        return CopiedFile(out.absolutePath, name, out.length())
    }
}
