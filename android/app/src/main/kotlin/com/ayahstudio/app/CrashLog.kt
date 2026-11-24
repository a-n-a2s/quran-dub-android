package com.ayahstudio.app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * تشخيص انهيار التطبيق (يوم 8، بعد بلاغ أنس: التطبيق بيطلع لما يكبس تصدير).
 * - انهيار Java/Kotlin: بنسجّل الاستثناء بملف قبل ما العملية تموت.
 * - انهيار native أو قتل من النظام (OOM...): أندرويد 11+ بيخبّرنا السبب
 *   بـ [ApplicationExitInfo] بالفتحة الجاية.
 * - آثار خطوات التصدير من Dart ([trace]) عشان نعرف وين وقف.
 * الواجهة بتعرض التقرير وبتخلّي المستخدم ينسخه.
 */
object CrashLog {
    private fun crashFile(c: Context) = File(c.filesDir, "last_crash.txt")
    private fun traceFile(c: Context) = File(c.filesDir, "export_trace.txt")
    private fun now() = SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date())

    @Volatile private var installed = false

    fun install(c: Context) {
        if (installed) return
        installed = true
        val app = c.applicationContext
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                crashFile(app).writeText(
                    "thread=${t.name} time=${now()}\n" + android.util.Log.getStackTraceString(e)
                )
            } catch (_: Throwable) {}
            prev?.uncaughtException(t, e)
        }
    }

    fun trace(c: Context, line: String) {
        try {
            val f = traceFile(c)
            if (line == "START") f.writeText("") // تصدير جديد: امسح القديم
            else f.appendText("${now()} $line\n")
        } catch (_: Throwable) {}
    }

    /** نص التقرير، أو null لو ما في شي يستاهل. */
    fun report(c: Context): String? {
        val sb = StringBuilder()
        val crash = crashFile(c)
        if (crash.exists()) sb.append("== انهيار Java ==\n").append(crash.readText().take(6000)).append('\n')
        val tr = traceFile(c)
        val traceText = if (tr.exists()) tr.readText().trim() else ""
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                val am = c.getSystemService(ActivityManager::class.java)
                val exits = am.getHistoricalProcessExitReasons(c.packageName, 0, 3)
                for (x in exits) {
                    val r = x.reason
                    // نعرض بس الأسباب غير الطبيعية.
                    if (r == ApplicationExitInfo.REASON_USER_REQUESTED ||
                        r == ApplicationExitInfo.REASON_EXIT_SELF ||
                        r == ApplicationExitInfo.REASON_USER_STOPPED ||
                        r == ApplicationExitInfo.REASON_OTHER && x.description.isNullOrEmpty()) continue
                    sb.append("== خروج: ${reasonName(r)} ==\n")
                        .append("وقت=${SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(Date(x.timestamp))} ")
                        .append("desc=${x.description} status=${x.status} rss=${x.rss / 1024}KB\n")
                    if (r == ApplicationExitInfo.REASON_CRASH_NATIVE || r == ApplicationExitInfo.REASON_ANR) {
                        try {
                            x.traceInputStream?.bufferedReader()?.use {
                                sb.append(it.readText().take(5000)).append('\n')
                            }
                        } catch (_: Throwable) {}
                    }
                }
            } catch (_: Throwable) {}
        }
        if (sb.isEmpty()) return null
        sb.append("== آخر خطوات التصدير ==\n").append(if (traceText.isEmpty()) "(ما في)" else traceText)
        sb.append("\nجهاز: ${Build.MANUFACTURER} ${Build.MODEL}، أندرويد ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        return sb.toString()
    }

    fun clear(c: Context) {
        crashFile(c).delete()
        traceFile(c).delete()
    }

    private fun reasonName(r: Int) = when (r) {
        ApplicationExitInfo.REASON_CRASH -> "CRASH (Java)"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INIT_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        else -> "code $r"
    }
}
