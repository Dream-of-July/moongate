package com.moongate.mobile.worker

import com.moongate.mobile.domain.MobileDownloadRequest
import com.moongate.mobile.domain.AndroidDownloadItem
import com.moongate.mobile.domain.AndroidDownloadState
import com.moongate.mobile.domain.MobileExportProfile
import com.moongate.mobile.domain.MobilePlatform
import com.moongate.mobile.domain.MobileTaskError
import com.moongate.mobile.domain.MobileTaskPhase
import com.moongate.mobile.domain.MobileTaskProgress
import com.moongate.mobile.domain.MobileTaskSnapshot
import com.moongate.mobile.domain.MobileTaskState
import com.moongate.mobile.domain.TaskRepository
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import java.nio.file.Files
import java.nio.file.Path

class AndroidBackgroundWorkSchedulerTest {
    @Test
    fun descriptorForTaskIDDeclaresConservativeWorkManagerContract() {
        val descriptor = AndroidBackgroundWorkScheduler()
            .descriptorForTaskID("task-direct-download")

        assertEquals("task-direct-download", descriptor.taskID)
        assertTrue(descriptor.workHandle.startsWith("moongate-work-"))
        assertFalse(descriptor.workHandle.contains("task-direct-download"))
        assertEquals(descriptor.workHandle, descriptor.uniqueWorkName)
        assertFalse(descriptor.uniqueWorkName.contains("task-direct-download"))
        assertEquals(AndroidDownloadWorker::class.java.name, descriptor.workerClassName)
        assertTrue(descriptor.requiresConnectedNetwork)
        assertTrue(descriptor.requiresStorageNotLow)
        assertTrue(descriptor.requiresForegroundNotification)
        assertTrue(descriptor.doesNotGuaranteeUnlimitedBackgroundRuntime)
    }

    @Test
    fun workRequestInputDataPersistsOnlyOpaqueHandleAndGeneration() {
        val descriptor = AndroidBackgroundWorkScheduler()
            .descriptorForTaskID("task-direct-download")
        val request = AndroidBackgroundWorkScheduler()
            .requestForTaskID("task-direct-download")
        val input = request.workSpec.input

        assertEquals(descriptor.workHandle, input.getString(AndroidDownloadWorker.InputWorkHandleKey))
        assertEquals(descriptor.generationID, input.getString(AndroidDownloadWorker.InputGenerationIDKey))
        assertTrue(descriptor.generationID.startsWith("moongate-generation-"))
        assertFalse(input.getString(AndroidDownloadWorker.InputWorkHandleKey).orEmpty().contains("task-direct-download"))
        assertFalse(input.getString(AndroidDownloadWorker.InputGenerationIDKey).orEmpty().contains("task-direct-download"))
        assertEquals(
            setOf(
                AndroidDownloadWorker.InputWorkHandleKey,
                AndroidDownloadWorker.InputGenerationIDKey,
            ),
            input.keyValueMap.keys,
        )
        assertFalse(input.keyValueMap.containsKey("task_id"))
        assertFalse(input.keyValueMap.containsKey("sourceURL"))
        assertFalse(input.keyValueMap.containsKey("sourceUrl"))
        assertFalse(input.keyValueMap.containsKey("url"))
        assertFalse(input.keyValueMap.containsKey("contentUri"))
        assertFalse(input.keyValueMap.containsKey("Authorization"))
        assertFalse(input.keyValueMap.containsKey("token"))
        assertFalse(input.keyValueMap.containsKey("secret"))
    }

    @Test
    fun schedulerUsesOpaqueUniqueWorkNameAndCancellationContract() {
        val source = androidBackgroundWorkSchedulerSource()

        assertTrue(source.contains("import androidx.work.ExistingWorkPolicy"))
        assertTrue(source.contains("val uniqueWorkName: String"))
        assertTrue(source.contains("val generationID: String"))
        assertTrue(source.contains("uniqueWorkName = workHandle"))
        assertTrue(source.contains("workManager?.enqueueUniqueWork("))
        assertTrue(source.contains("ExistingWorkPolicy.REPLACE"))
        assertTrue(source.contains("descriptor.uniqueWorkName"))
        assertTrue(source.contains("fun cancelTaskID(taskID: String): AndroidBackgroundWorkDescriptor"))
        assertTrue(source.contains("workManager?.cancelUniqueWork(descriptor.uniqueWorkName)"))
        assertTrue(source.contains("handoffStore?.cancelLatest(descriptor.workHandle)"))
        assertTrue(source.contains("fun workInfosForTaskID(taskID: String)"))
        assertTrue(source.contains("workManager?.getWorkInfosForUniqueWorkLiveData(descriptor.uniqueWorkName)"))
        assertTrue(source.contains("putString(AndroidDownloadWorker.InputWorkHandleKey, descriptor.workHandle)"))
        assertTrue(source.contains("putString(AndroidDownloadWorker.InputGenerationIDKey, descriptor.generationID)"))
        assertTrue(source.contains("private fun String.androidBackgroundWorkGenerationID(): String"))
        assertTrue(source.contains("private fun newAndroidBackgroundWorkGenerationID(): String"))
        assertTrue(source.contains("return \"moongate-generation-\$digest\""))
        assertFalse(source.contains("enqueue(oneTimeRequest(descriptor))"))
        assertFalse(source.contains("cancelAllWork"))
    }

    @Test
    fun workStatusMapperUsesOnlyWorkerProgressDataAndTerminalStates() {
        val source = androidBackgroundWorkStatusMapperSource()

        assertTrue(source.contains("object AndroidBackgroundWorkStatusMapper"))
        assertTrue(source.contains("data class AndroidBackgroundObservedWorkStatus"))
        assertTrue(source.contains("enum class AndroidBackgroundObservedWorkState"))
        assertTrue(source.contains("WorkInfo.State.ENQUEUED -> AndroidBackgroundObservedWorkState.ENQUEUED"))
        assertTrue(source.contains("WorkInfo.State.RUNNING -> AndroidBackgroundObservedWorkState.RUNNING"))
        assertTrue(source.contains("WorkInfo.State.SUCCEEDED -> AndroidBackgroundObservedWorkState.SUCCEEDED"))
        assertTrue(source.contains("WorkInfo.State.FAILED -> AndroidBackgroundObservedWorkState.FAILED"))
        assertTrue(source.contains("WorkInfo.State.CANCELLED -> AndroidBackgroundObservedWorkState.CANCELLED"))
        assertTrue(source.contains("workInfo?.progress?.getLong(AndroidDownloadWorker.ProgressBytesDownloadedKey"))
        assertTrue(source.contains("workInfo?.progress?.getLong(AndroidDownloadWorker.ProgressTotalBytesKey"))
        assertTrue(source.contains("workInfo?.progress?.getInt(AndroidDownloadWorker.ProgressPercentKey"))
        assertTrue(source.contains("val isTerminal: Boolean"))
        assertFalse(source.contains("inputData"))
        assertFalse(source.contains("InputWorkHandleKey"))
        assertFalse(source.contains("sourceURL"))
        assertFalse(source.contains("sourceUrl"))
        assertFalse(source.contains("Authorization"))
        assertFalse(source.contains("Bearer "))
        assertFalse(source.contains("apiKey"))
        assertFalse(source.contains("secret"))
    }

    @Test
    fun workStatusProjectionUpdatesOnlyQueueSafeTaskStateAndProgress() {
        val snapshot = workerSnapshot()

        val running = AndroidBackgroundWorkStatusProjection.apply(
            snapshot,
            AndroidBackgroundObservedWorkStatus(
                state = AndroidBackgroundObservedWorkState.RUNNING,
                bytesDownloaded = 32L,
                totalBytes = 128L,
                progressPercent = 25,
            ),
        )

        assertEquals(MobileTaskState.DOWNLOADING, running.state)
        assertEquals(MobileTaskPhase.DOWNLOADING, running.progress.phase)
        assertEquals(25, running.progress.completedUnitCount)
        assertEquals(100, running.progress.totalUnitCount)
        assertTrue(running.backgroundPolicy.canResume)
        assertNull(running.error)

        val failed = AndroidBackgroundWorkStatusProjection.apply(
            running,
            AndroidBackgroundObservedWorkStatus(
                state = AndroidBackgroundObservedWorkState.FAILED,
                bytesDownloaded = null,
                totalBytes = null,
                progressPercent = null,
            ),
        )
        assertEquals(MobileTaskState.FAILED, failed.state)
        assertEquals(MobileTaskError.NETWORK_UNAVAILABLE, failed.error)

        val cancelled = AndroidBackgroundWorkStatusProjection.apply(
            running,
            AndroidBackgroundObservedWorkStatus(
                state = AndroidBackgroundObservedWorkState.CANCELLED,
                bytesDownloaded = null,
                totalBytes = null,
                progressPercent = null,
            ),
        )
        assertEquals(MobileTaskState.CANCELLED, cancelled.state)
        assertEquals(MobileTaskError.CANCELLED, cancelled.error)
    }

    @Test
    fun workStatusProjectionDoesNotPretendSucceededWorkHasRepositoryResult() {
        val snapshot = workerSnapshot().copy(
            state = MobileTaskState.DOWNLOADING,
            progress = MobileTaskProgress(
                phase = MobileTaskPhase.DOWNLOADING,
                completedUnitCount = 60,
                totalUnitCount = 100,
            ),
        )

        val projected = AndroidBackgroundWorkStatusProjection.apply(
            snapshot,
            AndroidBackgroundObservedWorkStatus(
                state = AndroidBackgroundObservedWorkState.SUCCEEDED,
                bytesDownloaded = null,
                totalBytes = null,
                progressPercent = 100,
            ),
        )

        assertEquals(snapshot, projected)
        assertFalse(projected.state == MobileTaskState.COMPLETED)
    }

    @Test
    fun workStatusProjectionSourceDoesNotReadWorkerInputsOrSecrets() {
        val source = androidBackgroundWorkStatusProjectionSource()

        assertTrue(source.contains("object AndroidBackgroundWorkStatusProjection"))
        assertTrue(source.contains("fun apply("))
        assertTrue(source.contains("MobileTaskSnapshot"))
        assertTrue(source.contains("AndroidBackgroundObservedWorkStatus"))
        assertTrue(source.contains("AndroidBackgroundObservedWorkState.RUNNING"))
        assertTrue(source.contains("AndroidBackgroundObservedWorkState.FAILED"))
        assertTrue(source.contains("AndroidBackgroundObservedWorkState.CANCELLED"))
        assertTrue(source.contains("AndroidBackgroundObservedWorkState.SUCCEEDED"))
        assertTrue(source.contains("MobileBackgroundExecution.SCHEDULED_WORK"))
        assertTrue(source.contains("MobileBackgroundLimit.USER_VISIBLE_NOTIFICATION_REQUIRED"))
        assertFalse(source.contains("inputData"))
        assertFalse(source.contains("InputWorkHandleKey"))
        assertFalse(source.contains("InputGenerationIDKey"))
        assertFalse(source.contains("sourceURL"))
        assertFalse(source.contains("sourceUrl"))
        assertFalse(source.contains("Authorization"))
        assertFalse(source.contains("Bearer "))
        assertFalse(source.contains("apiKey"))
        assertFalse(source.contains("secret"))
        assertFalse(source.contains("MobileTaskState.COMPLETED"))
    }

    @Test
    fun foregroundObserverSourceMapsOnlyPreferredWorkInfoProgressAndDisposesRegistrations() {
        val source = androidBackgroundWorkForegroundObserverSource()

        assertTrue(source.contains("class AndroidBackgroundWorkForegroundObserver"))
        assertTrue(source.contains("fun interface AndroidBackgroundWorkObservationRegistration"))
        assertTrue(source.contains("fun observeTaskStatuses("))
        assertTrue(source.contains("scheduler.workInfosForTaskID(taskID)"))
        assertTrue(source.contains("liveData.observeForever(observer)"))
        assertTrue(source.contains("liveData.removeObserver(observer)"))
        assertTrue(source.contains("AndroidBackgroundWorkStatusMapper.from(workInfos.preferredForegroundWorkInfo())"))
        assertTrue(source.contains("firstOrNull { it.state == WorkInfo.State.RUNNING }"))
        assertTrue(source.contains("firstOrNull { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED }"))
        assertTrue(source.contains("firstOrNull { it.state == WorkInfo.State.FAILED || it.state == WorkInfo.State.CANCELLED }"))
        assertTrue(source.contains("firstOrNull { it.state == WorkInfo.State.SUCCEEDED }"))
        assertFalse(source.contains("inputData"))
        assertFalse(source.contains("InputWorkHandleKey"))
        assertFalse(source.contains("InputGenerationIDKey"))
        assertFalse(source.contains("sourceURL"))
        assertFalse(source.contains("sourceUrl"))
        assertFalse(source.contains("Authorization"))
        assertFalse(source.contains("Bearer "))
        assertFalse(source.contains("apiKey"))
        assertFalse(source.contains("secret"))
    }

    @Test
    fun workerDeclaresForegroundNotificationBeforeRuntimeResultMapping() {
        val source = androidDownloadWorkerSource()
        val cancelReceiverSource = androidDownloadCancelReceiverSource()
        val foregroundIndex = source.indexOf("setForeground(foregroundInfo(null))")
        val runtimeIndex = source.indexOf("AndroidDownloadWorkerRuntimeRegistry.runtime(applicationContext)")
        val notificationBlock = source.substringAfter("private fun foregroundNotification(): Notification")
            .substringBefore("private fun ensureNotificationChannel()")

        assertTrue(foregroundIndex >= 0)
        assertTrue(runtimeIndex > foregroundIndex)
        assertTrue(source.contains("val canRetry = runAttemptCount < MaxBackgroundDownloadRetryAttempts"))
        assertTrue(source.contains("runtime.run("))
        assertTrue(source.contains("inputData.getString(InputWorkHandleKey)"))
        assertTrue(source.contains("inputData.getString(InputGenerationIDKey)"))
        assertTrue(source.contains("canRetry = canRetry"))
        assertTrue(source.contains("progress = ::publishProgress"))
        assertTrue(source.contains("private suspend fun publishProgress(progress: AndroidBackgroundDownloadProgress)"))
        assertTrue(source.contains("setForeground(foregroundInfo(null))"))
        assertTrue(source.contains("progressPercent = ProgressNotificationStartPercent"))
        assertTrue(source.contains("val progressPercent = safeTotal?.let"))
        assertTrue(source.contains("((safeDownloaded * 100L) / total).coerceIn(1L, 99L).toInt()"))
        assertTrue(source.contains("setForeground(foregroundInfo(progressPercent))"))
        assertTrue(source.contains("setProgress("))
        assertTrue(source.contains("Data.Builder()"))
        assertTrue(source.contains("ProgressBytesDownloadedKey"))
        assertTrue(source.contains("ProgressTotalBytesKey"))
        assertTrue(source.contains("ProgressPercentKey"))
        assertTrue(source.contains("ProgressNotificationStartPercent"))
        assertTrue(source.contains("is AndroidBackgroundDownloadRuntimeResult.Completed -> Result.success()"))
        assertTrue(source.contains("is AndroidBackgroundDownloadRuntimeResult.Blocked -> Result.failure()"))
        assertTrue(source.contains("is AndroidBackgroundDownloadRuntimeResult.Retrying -> Result.retry()"))
        assertTrue(source.contains("is AndroidBackgroundDownloadRuntimeResult.Failed -> Result.failure()"))
        assertTrue(source.contains("MaxBackgroundDownloadRetryAttempts = 3"))
        assertTrue(source.contains("ForegroundInfo"))
        assertTrue(source.contains("data class AndroidBackgroundDownloadNotificationContent"))
        assertTrue(source.contains("internal fun androidBackgroundDownloadNotificationContent("))
        assertTrue(source.contains("NotificationCompat.Builder"))
        assertTrue(source.contains("text = \"后台下载中\""))
        assertTrue(source.contains("channelDescription = \"后台下载进度与取消\""))
        assertTrue(source.contains("cancelActionLabel = \"取消\""))
        assertTrue(notificationBlock.contains("androidBackgroundDownloadNotificationContent(applicationLabel())"))
        assertTrue(notificationBlock.contains(".setContentTitle(content.title)"))
        assertTrue(notificationBlock.contains(".setContentText(content.text)"))
        assertTrue(notificationBlock.contains(".setProgress("))
        assertTrue(notificationBlock.contains("progressPercent ?: content.progressValue"))
        assertTrue(notificationBlock.contains("progressPercent == null"))
        assertTrue(notificationBlock.contains(".addAction("))
        assertTrue(notificationBlock.contains("AndroidDownloadCancelReceiver.pendingIntent("))
        assertTrue(notificationBlock.contains("workHandle = inputData.getString(InputWorkHandleKey).orEmpty()"))
        assertTrue(notificationBlock.contains("generationID = inputData.getString(InputGenerationIDKey).orEmpty()"))
        assertTrue(notificationBlock.contains("workID = id.toString()"))
        assertTrue(cancelReceiverSource.contains("class AndroidDownloadCancelReceiver : BroadcastReceiver()"))
        assertTrue(cancelReceiverSource.contains("cancelIfGenerationMatches("))
        assertTrue(cancelReceiverSource.contains("WorkManager.getInstance(appContext).cancelWorkById(workID)"))
        assertTrue(cancelReceiverSource.contains("isOpaqueWorkHandle()"))
        assertTrue(cancelReceiverSource.contains("isOpaqueWorkGenerationID()"))
        assertTrue(source.contains("NotificationChannel"))
        assertTrue(source.contains("ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC"))
        assertTrue(source.contains("Build.VERSION_CODES.Q"))
        assertFalse(notificationBlock.contains("sourceURL"))
        assertFalse(notificationBlock.contains("sourceUrl"))
        assertFalse(notificationBlock.contains("Authorization"))
        assertFalse(notificationBlock.contains("Bearer "))
        assertFalse(notificationBlock.contains("apiKey"))
        assertFalse(notificationBlock.contains("secret"))
        assertFalse(source.contains("safeWorkHandle"))
        assertFalse(source.contains("setContentText(\"Preparing background work"))
        assertFalse(source.contains("InputTaskIDKey"))
        assertFalse(source.contains("sourceURL"))
        assertFalse(source.contains("sourceUrl"))
        assertFalse(source.contains("Authorization"))
        assertFalse(source.contains("apiKey"))
        assertFalse(source.contains("secret"))
    }

    @Test
    fun workerProgressDataPersistsOnlyNumericProgressFields() {
        val source = androidDownloadWorkerSource()
        val progressBlock = source.substringAfter("private suspend fun publishProgress")
            .substringBefore("private fun foregroundInfo(")

        assertTrue(progressBlock.contains("setProgress("))
        assertTrue(progressBlock.contains("Data.Builder()"))
        assertTrue(progressBlock.contains(".putLong(ProgressBytesDownloadedKey, safeDownloaded)"))
        assertTrue(progressBlock.contains(".putLong(ProgressTotalBytesKey, safeTotal)"))
        assertTrue(progressBlock.contains(".putInt("))
        assertTrue(progressBlock.contains("ProgressPercentKey"))
        assertTrue(source.contains("const val ProgressBytesDownloadedKey = \"bytes_downloaded\""))
        assertTrue(source.contains("const val ProgressTotalBytesKey = \"total_bytes\""))
        assertTrue(source.contains("const val ProgressPercentKey = \"progress_percent\""))
        assertFalse(progressBlock.contains("InputWorkHandleKey"))
        assertFalse(progressBlock.contains("sourceURL"))
        assertFalse(progressBlock.contains("sourceUrl"))
        assertFalse(progressBlock.contains("Authorization"))
        assertFalse(progressBlock.contains("Bearer "))
        assertFalse(progressBlock.contains("apiKey"))
        assertFalse(progressBlock.contains("secret"))
    }

    @Test
    fun workerRefreshesForegroundNotificationWithNumericProgressOnly() {
        val source = androidDownloadWorkerSource()
        val progressBlock = source.substringAfter("private suspend fun publishProgress")
            .substringBefore("private fun foregroundInfo(")
        val notificationBlock = source.substringAfter("private fun foregroundNotification(")
            .substringBefore("private fun ensureNotificationChannel()")

        assertTrue(progressBlock.contains("val progressPercent = safeTotal?.let"))
        assertTrue(progressBlock.contains("setForeground(foregroundInfo(progressPercent))"))
        assertTrue(notificationBlock.contains("progressPercent: Int"))
        assertTrue(notificationBlock.contains("progressPercent ?: content.progressValue"))
        assertTrue(notificationBlock.contains("progressPercent == null"))
        assertFalse(progressBlock.contains("sourceURL"))
        assertFalse(progressBlock.contains("sourceUrl"))
        assertFalse(progressBlock.contains("Authorization"))
        assertFalse(progressBlock.contains("Bearer "))
        assertFalse(progressBlock.contains("apiKey"))
        assertFalse(progressBlock.contains("secret"))
        assertFalse(notificationBlock.contains("sourceURL"))
        assertFalse(notificationBlock.contains("sourceUrl"))
        assertFalse(notificationBlock.contains("Authorization"))
        assertFalse(notificationBlock.contains("Bearer "))
        assertFalse(notificationBlock.contains("apiKey"))
        assertFalse(notificationBlock.contains("secret"))
    }

    @Test
    fun foregroundNotificationContentIsGenericAndDoesNotExposeWorkInput() {
        val content = androidBackgroundDownloadNotificationContent(
            applicationLabel = "视频下载器",
        )

        assertEquals("视频下载器", content.title)
        assertEquals("后台下载中", content.text)
        assertEquals("后台下载进度与取消", content.channelDescription)
        assertEquals(100, content.progressMax)
        assertEquals(0, content.progressValue)
        assertTrue(content.progressIndeterminate)
        assertEquals("取消", content.cancelActionLabel)

        val joined = listOf(
            content.title,
            content.text,
            content.channelDescription,
            content.cancelActionLabel,
        ).joinToString("\n")
        assertFalse(joined.contains("task-direct-download"))
        assertFalse(joined.contains("moongate-work-"))
        assertFalse(joined.contains("https://"))
        assertFalse(joined.contains("token"))
        assertFalse(joined.contains("Authorization"))
        assertFalse(joined.contains("Bearer "))
        assertFalse(joined.contains("apiKey"))
        assertFalse(joined.contains("secret"))
    }

    @Test
    fun backgroundHandoffStorePersistsRestorableDirectRequestByOpaqueHandleOnly() {
        val directory = Files.createTempDirectory("moongate-handoff-store").toFile()
        val descriptor = AndroidBackgroundWorkScheduler()
            .descriptorForTaskID("task-direct-download")
        val request = directDownloadRequest("https://cdn.example.com/video.mp4")
        val handoff = AndroidBackgroundDownloadHandoffStore(directory)
            .save(descriptor, request)

        assertEquals(descriptor.workHandle, handoff.workHandle)
        assertEquals(request.copy(preferredTitle = "片段 标题"), handoff.request)

        val files = directory.listFiles().orEmpty()
        assertEquals(1, files.size)
        assertEquals("${descriptor.workHandle}.handoff", files.first().name)
        assertFalse(files.first().name.contains("task-direct-download"))
        assertFalse(files.first().name.contains("cdn.example.com"))

        val stored = files.first().readText()
        assertFalse(stored.contains("Bearer "))
        assertFalse(stored.contains("Authorization"))
        assertFalse(stored.contains("apiKey"))
        assertFalse(stored.contains("secret"))

        val restored = AndroidBackgroundDownloadHandoffStore(directory).load(descriptor.workHandle)
        assertNotNull(restored)
        assertEquals(request.sourceURL, restored.request.sourceURL)
        assertEquals("片段 标题", restored.request.preferredTitle)
    }

    @Test
    fun backgroundHandoffStoreSourceWritesAtomicallyAndLocksByHandle() {
        val source = androidBackgroundDownloadHandoffStoreSource()

        assertTrue(source.contains("withHandoffLock(descriptor.workHandle)"))
        assertTrue(source.contains("withHandoffLock(workHandle)"))
        assertTrue(source.contains("val generationID: String"))
        assertTrue(source.contains("\"generationID\" to generationID"))
        assertTrue(source.contains("fun cancelLatest(workHandle: String)"))
        assertTrue(source.contains("fun cancelIfGenerationMatches("))
        assertTrue(source.contains("handoff.generationID == generationID"))
        assertTrue(source.contains("fun removeIfGenerationMatches("))
        assertTrue(source.contains("handoff.workHandle != workHandle || handoff.generationID != generationID"))
        assertTrue(source.contains("fun String.isOpaqueWorkGenerationID()"))
        assertTrue(source.contains("writeHandoffAtomically(fileFor(descriptor.workHandle), handoff.encode())"))
        assertTrue(source.contains("File.createTempFile"))
        assertTrue(source.contains("Files.move("))
        assertTrue(source.contains("StandardCopyOption.ATOMIC_MOVE"))
        assertTrue(source.contains("FileChannel.open"))
        assertTrue(source.contains("channel.lock().use"))
        assertTrue(source.contains("ConcurrentHashMap<Path, Any>"))
        assertTrue(source.contains("processLocks.computeIfAbsent(lockKey)"))
        assertTrue(source.contains("fun lockFileFor(workHandle: String): File"))
        assertFalse(source.contains("fileFor(descriptor.workHandle).writeText"))
    }

    @Test
    fun backgroundHandoffStoreRejectsTokenizedOrNonDirectSources() {
        val directory = Files.createTempDirectory("moongate-handoff-store-reject").toFile()
        val descriptor = AndroidBackgroundWorkScheduler()
            .descriptorForTaskID("task-direct-download")
        val store = AndroidBackgroundDownloadHandoffStore(directory)

        assertFailsWith<IllegalArgumentException> {
            store.save(descriptor, directDownloadRequest("https://cdn.example.com/video.mp4?token=abc"))
        }
        assertFailsWith<IllegalArgumentException> {
            store.save(descriptor, directDownloadRequest("https://example.com/watch"))
        }
        assertFailsWith<IllegalArgumentException> {
            store.save(descriptor, directDownloadRequest("http://cdn.example.com/video.mp4"))
        }
        assertFailsWith<IllegalArgumentException> {
            store.save(descriptor, directDownloadRequest("https://user:pass@cdn.example.com/video.mp4"))
        }
        assertTrue(directory.listFiles().isNullOrEmpty())
    }

    @Test
    fun coordinatorBlocksUnsafeSourcesInsteadOfThrowingWhenRuntimeGatesAreEnabled() {
        val coordinator = AndroidBackgroundWorkCoordinator(
            schedulerProvider = { AndroidBackgroundWorkScheduler() },
            notificationFlowAvailable = true,
            downloadWorkerRuntimeAvailable = true,
        )

        val handoff = coordinator.enqueueDownloadIfReady(
            AndroidDownloadItem(
                id = "task-direct-download",
                title = "视频",
                sourceLabel = "测试",
                state = AndroidDownloadState.QUEUED,
                detail = "等待下载",
                sourceUrlForDownload = "https://user:pass@cdn.example.com/video.mp4",
            )
        )

        assertTrue(handoff is AndroidBackgroundWorkHandoff.Blocked)
        val blocked = handoff as AndroidBackgroundWorkHandoff.Blocked
        assertEquals(
            "Background download requires a direct HTTPS media URL without credentials, query, or fragment.",
            blocked.reason,
        )
        assertNotNull(blocked.descriptor)
    }

    @Test
    fun backgroundDownloadRuntimeSourceWritesProgressResultAndRemovesMatchingHandoffOnSuccess() {
        val source = androidBackgroundDownloadRuntimeSource()

        assertTrue(source.contains("class AndroidBackgroundDownloadRuntime"))
        assertTrue(source.contains("progress: suspend (AndroidBackgroundDownloadProgress) -> Unit = {}"))
        assertTrue(source.contains("handoffStore.load(safeWorkHandle)"))
        assertTrue(source.contains("safeGenerationID"))
        assertTrue(source.contains("handoff.generationID != safeGenerationID"))
        assertTrue(source.contains("taskRepository.saveTask(request.downloadingSnapshot(safeGenerationID))"))
        assertTrue(source.contains("generationID = safeGenerationID"))
        assertTrue(source.contains("throw CancellationException(\"Android background download handoff is no longer active.\")"))
        assertTrue(source.contains("progress(downloadProgress)"))
        assertTrue(source.contains("handoffStore.isActiveGeneration(safeWorkHandle, safeGenerationID)"))
        assertTrue(source.contains("taskRepository.saveTask(completed)"))
        assertTrue(source.contains("handoffStore.removeIfGenerationMatches("))
        assertTrue(source.contains("workHandle = safeWorkHandle"))
        assertTrue(source.contains("generationID = safeGenerationID"))
        assertTrue(source.contains("handoffStore.cancelIfGenerationMatches("))
        assertTrue(source.contains("taskRepository.saveTask(request.cancelledSnapshot(safeGenerationID))"))
        assertTrue(source.contains("AndroidBackgroundDownloadRuntimeResult.Completed(completed)"))
        assertTrue(source.contains("MobileTaskState.COMPLETED"))
        assertTrue(source.contains("storageIdentifier = downloaded.storageIdentifier"))
        assertTrue(source.contains("MobileProcessingCapability.BACKGROUND_TRANSFER"))
    }

    @Test
    fun backgroundDownloadRuntimeSourceBlocksMissingHandoffWithoutSavingTask() {
        val source = androidBackgroundDownloadRuntimeSource()
        val missingHandoffBlock = source.substringAfter("val handoff = handoffStore.load(safeWorkHandle)")
            .substringBefore("val request = handoff.request")

        assertTrue(missingHandoffBlock.contains("AndroidBackgroundDownloadRuntimeResult.Blocked"))
        assertTrue(missingHandoffBlock.contains("Android background download handoff is missing."))
        assertFalse(missingHandoffBlock.contains("taskRepository.saveTask"))
    }

    @Test
    fun backgroundDownloadRuntimeSourceKeepsRetryingAttemptsNonFinalAndKeepsHandoff() {
        val source = androidBackgroundDownloadRuntimeSource()
        val failureBlock = source.substringAfter("} catch (error: Exception) {")
            .substringBefore("private fun AndroidBackgroundDownloadProgress.mobileTaskProgress()")

        assertTrue(source.contains("data class Retrying("))
        assertTrue(source.contains("canRetry: Boolean"))
        assertTrue(failureBlock.contains("if (canRetry)"))
        assertTrue(failureBlock.contains("val retrying = request.downloadingSnapshot(safeGenerationID)"))
        assertTrue(failureBlock.contains("taskRepository.saveTask(retrying)"))
        assertTrue(failureBlock.contains("AndroidBackgroundDownloadRuntimeResult.Retrying("))
        assertTrue(failureBlock.contains("val failed = request.failedSnapshot("))
        assertTrue(failureBlock.contains("generationID = safeGenerationID"))
        assertTrue(failureBlock.contains("error = error.mobileTaskError()"))
        assertTrue(failureBlock.contains("taskRepository.saveTask(failed)"))
        assertTrue(failureBlock.contains("AndroidBackgroundDownloadRuntimeResult.Failed("))
        assertFalse(failureBlock.contains("handoffStore.remove"))
        assertTrue(source.contains("MobileTaskState.FAILED"))
        assertTrue(source.contains("sealed class AndroidBackgroundDownloadFailure"))
        assertTrue(source.contains("MobileTaskError.STORAGE_FULL"))
        assertTrue(source.contains("MobileTaskError.UNSUPPORTED_ON_MOBILE"))
        assertTrue(source.contains("MobileTaskError.NETWORK_UNAVAILABLE"))
        assertTrue(source.contains("private fun Exception.mobileTaskError(): MobileTaskError"))
        assertFalse(source.contains("private fun MobileDownloadRequest.failedSnapshot(): MobileTaskSnapshot"))
    }

    @Test
    fun runtimeBlocksReplacedGenerationBeforeSavingTask() {
        val directory = Files.createTempDirectory("moongate-handoff-runtime-replaced").toFile()
        val store = AndroidBackgroundDownloadHandoffStore(directory)
        val descriptor = AndroidBackgroundWorkScheduler()
            .descriptorForTaskID("task-direct-download")
        store.save(descriptor, directDownloadRequest("https://cdn.example.com/video.mp4"))
        val repository = RecordingTaskRepository()

        val result = runSuspend {
            AndroidBackgroundDownloadRuntime(
                handoffStore = store,
                taskRepository = repository,
                downloader = SuccessfulDirectDownloader(),
            ).run(
                workHandle = descriptor.workHandle,
                generationID = "moongate-generation-0000000000000000000000000000000000000000000000000000000000000000",
                canRetry = false,
            )
        }

        assertIs<AndroidBackgroundDownloadRuntimeResult.Blocked>(result)
        assertTrue(result.reason.contains("replaced"))
        assertTrue(repository.saved.isEmpty())
        assertNotNull(store.load(descriptor.workHandle))
    }

    @Test
    fun runtimeDoesNotDeleteNewHandoffWhenOldGenerationCompletesAfterReenqueue() {
        val directory = Files.createTempDirectory("moongate-handoff-runtime-old-worker").toFile()
        val store = AndroidBackgroundDownloadHandoffStore(directory)
        val scheduler = AndroidBackgroundWorkScheduler(handoffStore = store)
        val oldDescriptor = scheduler.enqueue(directDownloadRequest("https://cdn.example.com/video.mp4"))
        val newDescriptor = scheduler.enqueue(directDownloadRequest("https://cdn.example.com/video-new.mp4"))
        val repository = RecordingTaskRepository()

        val result = runSuspend {
            AndroidBackgroundDownloadRuntime(
                handoffStore = store,
                taskRepository = repository,
                downloader = SuccessfulDirectDownloader(),
            ).run(
                workHandle = oldDescriptor.workHandle,
                generationID = oldDescriptor.generationID,
                canRetry = false,
            )
        }

        assertIs<AndroidBackgroundDownloadRuntimeResult.Blocked>(result)
        assertTrue(result.reason.contains("replaced"))
        assertEquals(newDescriptor.generationID, store.load(newDescriptor.workHandle)?.generationID)
        assertFalse(repository.saved.any { it.state == MobileTaskState.COMPLETED })
    }

    @Test
    fun handoffCancelWritesTombstoneForMatchingGeneration() {
        val directory = Files.createTempDirectory("moongate-handoff-runtime-cancel").toFile()
        val store = AndroidBackgroundDownloadHandoffStore(directory)
        val descriptor = AndroidBackgroundWorkScheduler()
            .descriptorForTaskID("task-direct-download")
        store.save(descriptor, directDownloadRequest("https://cdn.example.com/video.mp4"))

        val cancelled = store.cancelIfGenerationMatches(
            workHandle = descriptor.workHandle,
            generationID = descriptor.generationID,
        )

        assertNotNull(cancelled)
        assertEquals(AndroidBackgroundDownloadHandoff.State.CANCELLED, cancelled.state)
        assertFalse(store.load(descriptor.workHandle)?.isActive ?: true)
        assertFalse(store.isActiveGeneration(descriptor.workHandle, descriptor.generationID))
    }

    @Test
    fun directMediaBackgroundDownloaderSourceIsDirectHttpsOnlyAndAppOwned() {
        val source = androidDirectMediaBackgroundDownloaderSource()

        assertTrue(source.contains("class AndroidDirectMediaBackgroundDownloader"))
        assertTrue(source.contains("request.sourceURL.isSafeBackgroundSourceURL()"))
        assertTrue(source.contains("instanceFollowRedirects = false"))
        assertTrue(source.contains("finalURL.isSafeBackgroundSourceURL()"))
        assertTrue(source.contains("AndroidBackgroundDownloadFailure.UnsupportedOnMobile"))
        assertTrue(source.contains("AndroidBackgroundDownloadFailure.StorageFull"))
        assertTrue(source.contains("AndroidBackgroundDownloadFailure.NetworkUnavailable"))
        assertTrue(source.contains("maxDownloadBytes: Long = 512L * 1024L * 1024L"))
        assertTrue(source.contains(".part"))
        assertTrue(source.contains(".replace"))
        assertTrue(source.contains("coroutineContext.ensureActive()"))
        assertTrue(source.contains("storageIdentifier = \"android-owned:"))
        assertTrue(source.contains("{output.name}\""))
        assertFalse(source.contains("Authorization"))
        assertFalse(source.contains("Bearer "))
        assertFalse(source.contains("apiKey"))
        assertFalse(source.contains("secret"))
    }

    @Test
    fun directMediaBackgroundDownloaderKeepsPartialFileForRangeResume() {
        val source = androidDirectMediaBackgroundDownloaderSource()

        assertTrue(source.contains("val resumeOffset = existingPartialBytes(partialOutput)"))
        assertTrue(source.contains("connection.setRequestProperty(\"Range\", \"bytes=$resumeOffset-\")"))
        assertTrue(source.contains("status == HttpURLConnection.HTTP_PARTIAL"))
        assertTrue(source.contains("status == HttpURLConnection.HTTP_OK"))
        assertTrue(source.contains("val shouldAppend = resumeOffset > 0L && status == HttpURLConnection.HTTP_PARTIAL"))
        assertTrue(source.contains("val effectiveResumeOffset = if (shouldAppend) resumeOffset else 0L"))
        assertTrue(source.contains("partialOutput.outputStream(append = shouldAppend)"))
        assertTrue(source.contains("bytesDownloaded = effectiveResumeOffset + copied"))
        assertTrue(source.contains("totalBytes = normalizedTotalBytes"))
        assertTrue(source.contains("if (status == HttpURLConnection.HTTP_OK && resumeOffset > 0L)"))
        assertTrue(source.contains("private fun existingPartialBytes(partialOutput: File): Long"))
        assertFalse(source.contains("partialOutput.delete()\n                replacementOutput.delete()"))
        assertFalse(source.contains("Authorization"))
        assertFalse(source.contains("Bearer "))
        assertFalse(source.contains("apiKey"))
        assertFalse(source.contains("secret"))
    }

    private fun androidDownloadWorkerSource(): String {
        val sourcePath = workerSourcePath("AndroidDownloadWorker.kt")
        return Files.readString(sourcePath)
    }

    private fun androidDownloadCancelReceiverSource(): String {
        val sourcePath = workerSourcePath("AndroidDownloadCancelReceiver.kt")
        return Files.readString(sourcePath)
    }

    private fun androidBackgroundDownloadRuntimeSource(): String {
        val sourcePath = workerSourcePath("AndroidBackgroundDownloadRuntime.kt")
        return Files.readString(sourcePath)
    }

    private fun androidBackgroundDownloadHandoffStoreSource(): String {
        val sourcePath = workerSourcePath("AndroidBackgroundDownloadHandoffStore.kt")
        return Files.readString(sourcePath)
    }

    private fun androidBackgroundWorkSchedulerSource(): String {
        val sourcePath = workerSourcePath("AndroidBackgroundWorkScheduler.kt")
        return Files.readString(sourcePath)
    }

    private fun androidBackgroundWorkStatusMapperSource(): String {
        val sourcePath = workerSourcePath("AndroidBackgroundWorkStatusMapper.kt")
        return Files.readString(sourcePath)
    }

    private fun androidBackgroundWorkStatusProjectionSource(): String {
        val sourcePath = workerSourcePath("AndroidBackgroundWorkStatusProjection.kt")
        return Files.readString(sourcePath)
    }

    private fun androidBackgroundWorkForegroundObserverSource(): String {
        val sourcePath = workerSourcePath("AndroidBackgroundWorkForegroundObserver.kt")
        return Files.readString(sourcePath)
    }

    private fun androidDirectMediaBackgroundDownloaderSource(): String {
        val sourcePath = workerSourcePath("AndroidDirectMediaBackgroundDownloader.kt")
        return Files.readString(sourcePath)
    }

    private fun workerSourcePath(fileName: String): Path {
        val candidates = listOf(
            Path.of(
                "src",
                "main",
                "kotlin",
                "com",
                "moongate",
                "mobile",
                "worker",
                fileName,
            ),
            Path.of(
                "android",
                "core",
                "worker",
                "src",
                "main",
                "kotlin",
                "com",
                "moongate",
                "mobile",
                "worker",
                fileName,
            ),
        )
        return candidates.firstOrNull(Files::exists)
            ?: error("$fileName source path was not found")
    }

    private fun directDownloadRequest(sourceURL: String): MobileDownloadRequest =
        MobileDownloadRequest(
            id = "task-direct-download",
            sourceURL = sourceURL,
            candidateID = "candidate",
            videoID = "video",
            formatID = "direct",
            subtitleIDs = listOf("subtitle-en"),
            autoSubtitleIDs = emptyList(),
            exportProfile = MobileExportProfile(),
            preferredTitle = "片段 标题",
        )

    private fun workerSnapshot(): MobileTaskSnapshot =
        MobileTaskSnapshot(
            id = "task-direct-download",
            platform = MobilePlatform.ANDROID,
            state = MobileTaskState.WAITING,
        )

    private fun <T> runSuspend(block: suspend () -> T): T {
        var outcome: Result<T>? = null
        block.startCoroutine(
            object : Continuation<T> {
                override val context = EmptyCoroutineContext

                override fun resumeWith(result: Result<T>) {
                    outcome = result
                }
            },
        )
        return (outcome ?: error("Suspend block did not complete synchronously")).getOrThrow()
    }

    private class RecordingTaskRepository : TaskRepository {
        val saved = mutableListOf<MobileTaskSnapshot>()

        override suspend fun loadTasks(): List<MobileTaskSnapshot> = saved.toList()

        override suspend fun saveTask(snapshot: MobileTaskSnapshot) {
            saved.add(snapshot)
        }

        override suspend fun removeTask(id: String) {
            saved.removeAll { it.id == id }
        }
    }

    private class SuccessfulDirectDownloader : AndroidBackgroundDirectDownloader {
        override suspend fun download(
            request: MobileDownloadRequest,
            progress: suspend (AndroidBackgroundDownloadProgress) -> Unit,
        ): AndroidBackgroundDownloadedFile {
            progress(
                AndroidBackgroundDownloadProgress(
                    bytesDownloaded = 5,
                    totalBytes = 10,
                ),
            )
            return AndroidBackgroundDownloadedFile(
                storageIdentifier = "android-owned:${request.id}.mp4",
                byteCount = 10,
            )
        }
    }

}
