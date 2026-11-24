package com.ayahstudio.app

import android.os.Handler
import android.os.Looper

/**
 * حالة التصدير الحالية (يوم 8)، مشتركة بين [ExportService] (اللي بيشتغل
 * بالخلفية) والواجهة (MainActivity → Dart). الحالة بتضل محفوظة هون حتى لو
 * الواجهة انقفلت ورجعت، فالـ Dart بيسأل عنها لما يرجع (`getStatus`).
 *
 * نفس أسماء المراحل والأخطاء بـ `lib/export/export_status.dart`.
 */
object ExportHub {
    private val main = Handler(Looper.getMainLooper())
    private val listeners = LinkedHashSet<(Map<String, Any?>) -> Unit>()

    @Volatile
    var status: Map<String, Any?> = mapOf("phase" to "idle")
        private set

    fun update(newStatus: Map<String, Any?>) {
        status = newStatus
        main.post { for (l in listeners.toList()) l(newStatus) }
    }

    fun addListener(l: (Map<String, Any?>) -> Unit) {
        main.post {
            listeners.add(l)
            l(status)
        }
    }

    fun removeListener(l: (Map<String, Any?>) -> Unit) {
        main.post { listeners.remove(l) }
    }

    val isRunning: Boolean
        get() = when (status["phase"]) {
            "encoding", "saving" -> true
            else -> false
        }
}
