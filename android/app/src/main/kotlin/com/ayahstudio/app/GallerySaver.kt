package com.ayahstudio.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import java.io.File
import java.io.InputStream
import java.io.OutputStream

/**
 * حفظ الفيديو الناتج بالمعرض (يوم 8): `Movies/AyahStudio`.
 * - أندرويد 10+ (API 29): MediaStore بـ RELATIVE_PATH، **بدون أي صلاحية**.
 * - أندرويد 7–9: بدها WRITE_EXTERNAL_STORAGE (maxSdkVersion 28 بالـ manifest)،
 *   بتنطلب وقت التصدير بس. لو مرفوضة: الفيديو بيضل بملفات التطبيق
 *   وبتقدر تشاركه.
 */
object GallerySaver {
    const val ALBUM = "AyahStudio"

    data class Saved(val uri: Uri, val displayPath: String)

    fun needsLegacyPermission(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    fun canSave(ctx: Context): Boolean =
        !needsLegacyPermission() ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED

    fun save(ctx: Context, file: File, displayName: String, onProgress: (Float) -> Unit): Saved {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveScoped(ctx, file, displayName, onProgress)
        } else {
            saveLegacy(ctx, file, displayName, onProgress)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveScoped(ctx: Context, file: File, name: String, onProgress: (Float) -> Unit): Saved {
        val resolver = ctx.contentResolver
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/$ALBUM")
            put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore رفض إضافة الفيديو")
        try {
            val out = resolver.openOutputStream(uri) ?: throw IllegalStateException("ما انفتح ملف المعرض")
            file.inputStream().use { src -> out.use { dst -> copy(src, dst, file.length(), onProgress) } }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return Saved(uri, "${Environment.DIRECTORY_MOVIES}/$ALBUM/$name")
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(ctx: Context, file: File, name: String, onProgress: (Float) -> Unit): Saved {
        if (!canSave(ctx)) throw SecurityException("صلاحية التخزين مش موجودة")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), ALBUM)
        if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("ما قدرنا ننشئ مجلد $dir")
        val dest = File(dir, name)
        file.inputStream().use { src -> dest.outputStream().use { dst -> copy(src, dst, file.length(), onProgress) } }
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.DATA, dest.absolutePath)
            put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
        }
        val uri = ctx.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: Uri.fromFile(dest)
        return Saved(uri, dest.absolutePath)
    }

    private fun copy(src: InputStream, dst: OutputStream, total: Long, onProgress: (Float) -> Unit) {
        val buf = ByteArray(1 shl 20)
        var done = 0L
        var lastReport = 0L
        while (true) {
            val n = src.read(buf)
            if (n < 0) break
            dst.write(buf, 0, n)
            done += n
            if (total > 0 && done - lastReport > (4 shl 20)) {
                lastReport = done
                onProgress(done.toFloat() / total)
            }
        }
        onProgress(1f)
    }
}
