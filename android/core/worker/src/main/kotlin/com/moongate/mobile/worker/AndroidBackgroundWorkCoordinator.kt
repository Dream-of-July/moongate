package com.moongate.mobile.worker

import android.content.Context
import androidx.work.WorkManager
import com.moongate.mobile.domain.AndroidDownloadItem
import com.moongate.mobile.domain.MobileDownloadRequest
import com.moongate.mobile.domain.MobileExportProfile
import java.io.File

sealed class AndroidBackgroundWorkHandoff {
    data class Blocked(
        val descriptor: AndroidBackgroundWorkDescriptor?,
        val reason: String,
    ) : AndroidBackgroundWorkHandoff()

    data class Enqueued(
        val descriptor: AndroidBackgroundWorkDescriptor,
    ) : AndroidBackgroundWorkHandoff()
}

class AndroidBackgroundWorkCoordinator(
    private val schedulerProvider: () -> AndroidBackgroundWorkScheduler,
    private val notificationFlowAvailable: Boolean = false,
    private val downloadWorkerRuntimeAvailable: Boolean = false,
) {
    fun enqueueDownloadIfReady(item: AndroidDownloadItem): AndroidBackgroundWorkHandoff {
        if (item.sourceUrlForDownload.isBlank()) {
            return AndroidBackgroundWorkHandoff.Blocked(
                descriptor = null,
                reason = "Background download requires a restorable direct media request.",
            )
        }
        val descriptor = AndroidBackgroundWorkScheduler().descriptorForTaskID(item.id)
        if (!notificationFlowAvailable) {
            return AndroidBackgroundWorkHandoff.Blocked(
                descriptor = descriptor,
                reason = "Android notification and foreground-service flow is not runtime verified yet.",
            )
        }
        if (!downloadWorkerRuntimeAvailable) {
            return AndroidBackgroundWorkHandoff.Blocked(
                descriptor = descriptor,
                reason = "Android background download worker is still an unsupported skeleton.",
            )
        }
        if (!item.sourceUrlForDownload.isSafeBackgroundSourceURL()) {
            return AndroidBackgroundWorkHandoff.Blocked(
                descriptor = descriptor,
                reason = "Background download requires a direct HTTPS media URL without credentials, query, or fragment.",
            )
        }
        val scheduler = schedulerProvider()
        val request = item.backgroundDownloadRequest()
        return AndroidBackgroundWorkHandoff.Enqueued(scheduler.enqueue(request))
    }

    fun cancelDownload(taskID: String): AndroidBackgroundWorkDescriptor =
        schedulerProvider().cancelTaskID(taskID)

    fun observeForegroundWorkStatuses(
        taskIDs: List<String>,
        onStatus: (taskID: String, status: AndroidBackgroundObservedWorkStatus) -> Unit,
    ): AndroidBackgroundWorkObservationRegistration {
        if (taskIDs.isEmpty()) {
            return AndroidNoopBackgroundWorkObservationRegistration
        }
        return AndroidBackgroundWorkForegroundObserver(schedulerProvider())
            .observeTaskStatuses(taskIDs, onStatus)
    }

    companion object {
        fun blocked(): AndroidBackgroundWorkCoordinator =
            AndroidBackgroundWorkCoordinator(
                schedulerProvider = { AndroidBackgroundWorkScheduler() },
            )

        fun from(
            context: Context,
            notificationFlowAvailable: Boolean = false,
            downloadWorkerRuntimeAvailable: Boolean = false,
            workManagerProvider: (Context) -> WorkManager = { appContext ->
                WorkManager.getInstance(appContext.applicationContext)
            },
        ): AndroidBackgroundWorkCoordinator =
            AndroidBackgroundWorkCoordinator(
                schedulerProvider = {
                    AndroidBackgroundWorkScheduler(
                        workManager = workManagerProvider(context),
                        handoffStore = AndroidBackgroundDownloadHandoffStore(
                            File(context.noBackupFilesDir, "background-download-handoffs"),
                        ),
                    )
                },
                notificationFlowAvailable = notificationFlowAvailable,
                downloadWorkerRuntimeAvailable = downloadWorkerRuntimeAvailable,
            )
    }
}

private fun AndroidDownloadItem.backgroundDownloadRequest(): MobileDownloadRequest =
    MobileDownloadRequest(
        id = id,
        sourceURL = sourceUrlForDownload,
        candidateID = "android-background-$id",
        videoID = id,
        formatID = "direct",
        exportProfile = MobileExportProfile(),
        preferredTitle = title,
    )
