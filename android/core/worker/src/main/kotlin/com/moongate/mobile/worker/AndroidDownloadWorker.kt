package com.moongate.mobile.worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Data
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters

data class AndroidBackgroundDownloadNotificationContent(
    val title: String,
    val text: String,
    val channelDescription: String,
    val progressMax: Int,
    val progressValue: Int,
    val progressIndeterminate: Boolean,
    val cancelActionLabel: String,
)

internal fun androidBackgroundDownloadNotificationContent(
    applicationLabel: String,
): AndroidBackgroundDownloadNotificationContent =
    AndroidBackgroundDownloadNotificationContent(
        title = applicationLabel,
        text = "后台下载中",
        channelDescription = "后台下载进度与取消",
        progressMax = 100,
        progressValue = 0,
        progressIndeterminate = true,
        cancelActionLabel = "取消",
    )

class AndroidDownloadWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        setForeground(foregroundInfo(null))
        val runtime = AndroidDownloadWorkerRuntimeRegistry.runtime(applicationContext)
        val canRetry = runAttemptCount < MaxBackgroundDownloadRetryAttempts
        return when (runtime.run(
            inputData.getString(InputWorkHandleKey),
            inputData.getString(InputGenerationIDKey),
            canRetry = canRetry,
            progress = ::publishProgress,
        )) {
            is AndroidBackgroundDownloadRuntimeResult.Completed -> Result.success()
            is AndroidBackgroundDownloadRuntimeResult.Blocked -> Result.failure()
            is AndroidBackgroundDownloadRuntimeResult.Retrying -> Result.retry()
            is AndroidBackgroundDownloadRuntimeResult.Failed -> Result.failure()
        }
    }

    private suspend fun publishProgress(progress: AndroidBackgroundDownloadProgress) {
        val safeDownloaded = progress.bytesDownloaded.coerceAtLeast(0L)
        val safeTotal = progress.totalBytes?.takeIf { it > 0L }
        val progressPercent = safeTotal?.let { total ->
            ((safeDownloaded * 100L) / total).coerceIn(1L, 99L).toInt()
        }
        setForeground(foregroundInfo(progressPercent))
        setProgress(
            Data.Builder()
                .putLong(ProgressBytesDownloadedKey, safeDownloaded)
                .apply {
                    if (safeTotal != null) {
                        putLong(ProgressTotalBytesKey, safeTotal)
                        putInt(ProgressPercentKey, progressPercent ?: ProgressNotificationStartPercent)
                    }
                }
                .build()
        )
    }

    private fun foregroundInfo(progressPercent: Int?): ForegroundInfo {
        val notification = foregroundNotification(progressPercent)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                ForegroundNotificationID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(ForegroundNotificationID, notification)
        }
    }

    private fun foregroundNotification(progressPercent: Int?): Notification {
        ensureNotificationChannel()
        val content = androidBackgroundDownloadNotificationContent(applicationLabel())
        return NotificationCompat.Builder(applicationContext, NotificationChannelID)
            .setSmallIcon(safeNotificationIcon())
            .setContentTitle(content.title)
            .setContentText(content.text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setProgress(
                content.progressMax,
                progressPercent ?: content.progressValue,
                progressPercent == null,
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                content.cancelActionLabel,
                AndroidDownloadCancelReceiver.pendingIntent(
                    context = applicationContext,
                    workHandle = inputData.getString(InputWorkHandleKey).orEmpty(),
                    generationID = inputData.getString(InputGenerationIDKey).orEmpty(),
                    workID = id.toString(),
                ),
            )
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            NotificationChannelID,
            applicationLabel(),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = androidBackgroundDownloadNotificationContent(applicationLabel()).channelDescription
        }
        NotificationManagerCompat
            .from(applicationContext)
            .createNotificationChannel(channel)
    }

    private fun applicationLabel(): String {
        val packageManager = applicationContext.packageManager
        return applicationContext.applicationInfo
            .loadLabel(packageManager)
            .toString()
            .ifBlank { applicationContext.packageName }
    }

    private fun safeNotificationIcon(): Int =
        applicationContext.applicationInfo.icon
            .takeIf { icon -> icon != 0 }
            ?: android.R.drawable.stat_sys_download

    companion object {
        const val InputWorkHandleKey = "work_handle"
        const val InputGenerationIDKey = "generation_id"
        const val ProgressBytesDownloadedKey = "bytes_downloaded"
        const val ProgressTotalBytesKey = "total_bytes"
        const val ProgressPercentKey = "progress_percent"

        private const val ProgressNotificationStartPercent = 0
        private const val MaxBackgroundDownloadRetryAttempts = 3
        private const val ForegroundNotificationID = 8801
        private const val NotificationChannelID = "moongate_background_work"
    }
}
