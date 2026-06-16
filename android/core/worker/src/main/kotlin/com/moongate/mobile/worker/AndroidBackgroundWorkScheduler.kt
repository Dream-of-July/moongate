package com.moongate.mobile.worker

import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.moongate.mobile.domain.MobileDownloadRequest
import java.security.MessageDigest
import java.util.UUID

data class AndroidBackgroundWorkDescriptor(
    val taskID: String,
    val workHandle: String,
    val generationID: String,
    val uniqueWorkName: String,
    val workerClassName: String,
    val requiresConnectedNetwork: Boolean,
    val requiresStorageNotLow: Boolean,
    val requiresForegroundNotification: Boolean,
    val doesNotGuaranteeUnlimitedBackgroundRuntime: Boolean,
)

class AndroidBackgroundWorkScheduler(
    private val workManager: WorkManager? = null,
    private val handoffStore: AndroidBackgroundDownloadHandoffStore? = null,
) {
    fun descriptorFor(request: MobileDownloadRequest): AndroidBackgroundWorkDescriptor =
        descriptorForTaskID(request.id)

    fun descriptorForTaskID(taskID: String): AndroidBackgroundWorkDescriptor =
        descriptorForTaskID(
            taskID = taskID,
            generationID = taskID.androidBackgroundWorkGenerationID(),
        )

    private fun descriptorForTaskID(
        taskID: String,
        generationID: String,
    ): AndroidBackgroundWorkDescriptor =
        taskID.androidBackgroundWorkHandle().let { workHandle ->
        AndroidBackgroundWorkDescriptor(
            taskID = taskID,
            workHandle = workHandle,
            generationID = generationID,
            uniqueWorkName = workHandle,
            workerClassName = AndroidDownloadWorker::class.java.name,
            requiresConnectedNetwork = true,
            requiresStorageNotLow = true,
            requiresForegroundNotification = true,
            doesNotGuaranteeUnlimitedBackgroundRuntime = true,
        )
    }

    fun requestFor(request: MobileDownloadRequest): OneTimeWorkRequest =
        oneTimeRequest(descriptorFor(request))

    fun requestForTaskID(taskID: String): OneTimeWorkRequest =
        oneTimeRequest(descriptorForTaskID(taskID))

    fun enqueue(request: MobileDownloadRequest): AndroidBackgroundWorkDescriptor {
        val descriptor = descriptorForTaskID(
            taskID = request.id,
            generationID = newAndroidBackgroundWorkGenerationID(),
        )
        handoffStore?.save(descriptor, request)
        workManager?.enqueueUniqueWork(
            descriptor.uniqueWorkName,
            ExistingWorkPolicy.REPLACE,
            oneTimeRequest(descriptor),
        )
        return descriptor
    }

    fun enqueueTaskID(taskID: String): AndroidBackgroundWorkDescriptor {
        val descriptor = descriptorForTaskID(taskID)
        workManager?.enqueueUniqueWork(
            descriptor.uniqueWorkName,
            ExistingWorkPolicy.REPLACE,
            oneTimeRequest(descriptor),
        )
        return descriptor
    }

    fun cancelTaskID(taskID: String): AndroidBackgroundWorkDescriptor {
        val descriptor = descriptorForTaskID(taskID)
        workManager?.cancelUniqueWork(descriptor.uniqueWorkName)
        handoffStore?.cancelLatest(descriptor.workHandle)
        return descriptor
    }

    fun workInfosForTaskID(taskID: String) =
        descriptorForTaskID(taskID).let { descriptor ->
            workManager?.getWorkInfosForUniqueWorkLiveData(descriptor.uniqueWorkName)
        }

    private fun oneTimeRequest(descriptor: AndroidBackgroundWorkDescriptor): OneTimeWorkRequest =
        OneTimeWorkRequestBuilder<AndroidDownloadWorker>()
            .setConstraints(backgroundConstraints())
            .setInputData(
                Data.Builder()
                    .putString(AndroidDownloadWorker.InputWorkHandleKey, descriptor.workHandle)
                    .putString(AndroidDownloadWorker.InputGenerationIDKey, descriptor.generationID)
                    .build()
            )
            .build()

    private fun backgroundConstraints(): Constraints =
        Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresStorageNotLow(true)
            .build()
}

private fun String.androidBackgroundWorkHandle(): String {
    val digest = MessageDigest
        .getInstance("SHA-256")
        .digest(toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
    return "moongate-work-$digest"
}

private fun String.androidBackgroundWorkGenerationID(): String =
    "descriptor:$this".androidBackgroundGenerationHash()

private fun newAndroidBackgroundWorkGenerationID(): String =
    "${UUID.randomUUID()}:${System.nanoTime()}".androidBackgroundGenerationHash()

private fun String.androidBackgroundGenerationHash(): String {
    val digest = MessageDigest
        .getInstance("SHA-256")
        .digest(toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
    return "moongate-generation-$digest"
}
