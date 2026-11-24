package com.ayahstudio.app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * إشعارات التصدير (يوم 8): تقدّم (مع زر إلغاء) وبعدين "خلص" (بيفتح الفيديو،
 * وفيه زر مشاركة) أو خطأ. على أندرويد 13+ صلاحية الإشعارات بتنطلب من
 * الواجهة وقت ما المستخدم يضغط "تصدير" بس؛ لو رفضها، التصدير بيكمّل عادي
 * بس بدون إشعار ظاهر.
 */
object ExportNotifications {
    const val CHANNEL_PROGRESS = "export_progress"
    const val CHANNEL_DONE = "export_done"
    const val ID_PROGRESS = 7101
    const val ID_DONE = 7102

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_PROGRESS, "تقدّم التصدير", NotificationManager.IMPORTANCE_LOW).apply {
                description = "تقدّم تصدير الفيديو بالخلفية"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_DONE, "انتهاء التصدير", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "لما الفيديو يجهز أو يصير خطأ"
            }
        )
    }

    private fun openAppIntent(ctx: Context): PendingIntent {
        val intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?: Intent(ctx, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            ctx, 1, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    fun progress(ctx: Context, title: String, percent: Int, indeterminate: Boolean, text: String): Notification {
        val cancel = PendingIntent.getService(
            ctx, 2,
            Intent(ctx, ExportService::class.java).setAction(ExportService.ACTION_CANCEL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(ctx, CHANNEL_PROGRESS)
            .setSmallIcon(R.drawable.ic_stat_ayah)
            .setContentTitle(if (title.isEmpty()) "تصدير الفيديو" else "تصدير: $title")
            .setContentText(text)
            .setProgress(100, percent.coerceIn(0, 100), indeterminate)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openAppIntent(ctx))
            .addAction(0, "إلغاء", cancel)
            .build()
    }

    fun viewIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "video/mp4")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)

    fun shareIntent(uri: Uri): Intent {
        val send = Intent(Intent.ACTION_SEND)
            .setType("video/mp4")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return Intent.createChooser(send, "مشاركة الفيديو")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    @SuppressLint("MissingPermission") // بنفحص areNotificationsEnabled قبل.
    fun done(ctx: Context, title: String, uri: Uri, saved: Boolean) {
        val nm = NotificationManagerCompat.from(ctx)
        if (!nm.areNotificationsEnabled()) return
        val view = PendingIntent.getActivity(
            ctx, 3, viewIntent(uri), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val share = PendingIntent.getActivity(
            ctx, 4, shareIntent(uri), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL_DONE)
            .setSmallIcon(R.drawable.ic_stat_ayah)
            .setContentTitle("الفيديو جاهز ✅")
            .setContentText(
                (if (title.isEmpty()) "" else "$title — ") +
                    (if (saved) "محفوظ بالمعرض (Movies/AyahStudio)" else "اضغط للفتح")
            )
            .setAutoCancel(true)
            .setContentIntent(view)
            .addAction(0, "مشاركة", share)
            .build()
        nm.notify(ID_DONE, n)
    }

    @SuppressLint("MissingPermission")
    fun failed(ctx: Context, title: String, message: String) {
        val nm = NotificationManagerCompat.from(ctx)
        if (!nm.areNotificationsEnabled()) return
        val n = NotificationCompat.Builder(ctx, CHANNEL_DONE)
            .setSmallIcon(R.drawable.ic_stat_ayah)
            .setContentTitle(if (title.isEmpty()) "ما خلص التصدير" else "ما خلص التصدير: $title")
            .setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(ctx))
            .build()
        nm.notify(ID_DONE, n)
    }

    fun cancelDone(ctx: Context) = NotificationManagerCompat.from(ctx).cancel(ID_DONE)
}
