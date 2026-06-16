package com.moongate.mobile.worker

import com.moongate.mobile.domain.MobileArtifactKind
import com.moongate.mobile.domain.MobileBackgroundExecution
import com.moongate.mobile.domain.MobileBackgroundLimit
import com.moongate.mobile.domain.MobileBackgroundPolicy
import com.moongate.mobile.domain.MobileBackgroundResumability
import com.moongate.mobile.domain.MobileDownloadRequest
import com.moongate.mobile.domain.MobilePlatform
import com.moongate.mobile.domain.MobileProcessingCapabilities
import com.moongate.mobile.domain.MobileProcessingCapability
import com.moongate.mobile.domain.MobileTaskArtifact
import com.moongate.mobile.domain.MobileTaskError
import com.moongate.mobile.domain.MobileTaskPhase
import com.moongate.mobile.domain.MobileTaskProgress
import com.moongate.mobile.domain.MobileTaskResult
import com.moongate.mobile.domain.MobileTaskSnapshot
import com.moongate.mobile.domain.MobileTaskState
import com.moongate.mobile.domain.TaskRepository
import java.io.IOException
import java.util.concurrent.CancellationException

data class AndroidBackgroundDownloadProgress(
    val bytesDownloaded: Long,
    val totalBytes: Long?,
)

data class AndroidBackgroundDownloadedFile(
    val storageIdentifier: String,
    val byteCount: Long?,
) {
    init {
        require(storageIdentifier.startsWith("android-owned:")) {
            "Android background downloads must finish into app-owned storage."
        }
    }
}

interface AndroidBackgroundDirectDownloader {
    suspend fun download(
        request: MobileDownloadRequest,
        progress: suspend (AndroidBackgroundDownloadProgress) -> Unit,
    ): AndroidBackgroundDownloadedFile
}

internal sealed class AndroidBackgroundDownloadFailure(
    val mobileTaskError: MobileTaskError,
    message: String,
    cause: Throwable? = null,
) : IOException(message, cause) {
    class StorageFull(
        message: String,
        cause: Throwable? = null,
    ) : AndroidBackgroundDownloadFailure(MobileTaskError.STORAGE_FULL, message, cause)

    class UnsupportedOnMobile(
        message: String,
        cause: Throwable? = null,
    ) : AndroidBackgroundDownloadFailure(MobileTaskError.UNSUPPORTED_ON_MOBILE, message, cause)

    class NetworkUnavailable(
        message: String,
        cause: Throwable? = null,
    ) : AndroidBackgroundDownloadFailure(MobileTaskError.NETWORK_UNAVAILABLE, message, cause)
}

sealed class AndroidBackgroundDownloadRuntimeResult {
    data class Completed(
        val snapshot: MobileTaskSnapshot,
    ) : AndroidBackgroundDownloadRuntimeResult()

    data class Blocked(
        val reason: String,
    ) : AndroidBackgroundDownloadRuntimeResult()

    data class Retrying(
        val snapshot: MobileTaskSnapshot,
        val reason: String,
    ) : AndroidBackgroundDownloadRuntimeResult()

    data class Failed(
        val snapshot: MobileTaskSnapshot,
        val reason: String,
    ) : AndroidBackgroundDownloadRuntimeResult()
}

class AndroidBackgroundDownloadRuntime(
    private val handoffStore: AndroidBackgroundDownloadHandoffStore,
    private val taskRepository: TaskRepository,
    private val downloader: AndroidBackgroundDirectDownloader,
) {
    suspend fun run(
        workHandle: String?,
        generationID: String?,
        canRetry: Boolean,
        progress: suspend (AndroidBackgroundDownloadProgress) -> Unit = {},
    ): AndroidBackgroundDownloadRuntimeResult {
        val safeWorkHandle = workHandle?.takeIf { it.isOpaqueWorkHandle() }
            ?: return AndroidBackgroundDownloadRuntimeResult.Blocked(
                reason = "Android background work handle is missing or invalid.",
            )
        val safeGenerationID = generationID?.takeIf { it.isOpaqueWorkGenerationID() }
            ?: return AndroidBackgroundDownloadRuntimeResult.Blocked(
                reason = "Android background work generation is missing or invalid.",
            )
        val handoff = handoffStore.load(safeWorkHandle)
            ?: return AndroidBackgroundDownloadRuntimeResult.Blocked(
                reason = "Android background download handoff is missing.",
            )
        if (!handoff.isActive) {
            return AndroidBackgroundDownloadRuntimeResult.Blocked(
                reason = "Android background download was cancelled.",
            )
        }
        if (handoff.generationID != safeGenerationID) {
            return AndroidBackgroundDownloadRuntimeResult.Blocked(
                reason = "Android background download handoff was replaced.",
            )
        }
        val request = handoff.request
        taskRepository.saveTask(request.downloadingSnapshot(safeGenerationID))
        return try {
            val downloaded = downloader.download(request) { downloadProgress ->
                if (!handoffStore.isActiveGeneration(safeWorkHandle, safeGenerationID)) {
                    throw CancellationException("Android background download handoff is no longer active.")
                }
                taskRepository.saveTask(
                    request.downloadingSnapshot(
                        generationID = safeGenerationID,
                        progress = downloadProgress.mobileTaskProgress(),
                    ),
                )
                progress(downloadProgress)
            }
            val completed = request.completedSnapshot(
                downloaded = downloaded,
                generationID = safeGenerationID,
            )
            if (!handoffStore.isActiveGeneration(safeWorkHandle, safeGenerationID)) {
                return AndroidBackgroundDownloadRuntimeResult.Blocked(
                    reason = "Android background download handoff was replaced before completion.",
                )
            }
            taskRepository.saveTask(completed)
            handoffStore.removeIfGenerationMatches(
                workHandle = safeWorkHandle,
                generationID = safeGenerationID,
            )
            AndroidBackgroundDownloadRuntimeResult.Completed(completed)
        } catch (error: CancellationException) {
            handoffStore.cancelIfGenerationMatches(
                workHandle = safeWorkHandle,
                generationID = safeGenerationID,
            )
            taskRepository.saveTask(request.cancelledSnapshot(safeGenerationID))
            throw error
        } catch (error: Exception) {
            if (canRetry) {
                val retrying = request.downloadingSnapshot(safeGenerationID)
                taskRepository.saveTask(retrying)
                return AndroidBackgroundDownloadRuntimeResult.Retrying(
                    snapshot = retrying,
                    reason = "Android background download will retry.",
                )
            }
            val failed = request.failedSnapshot(
                generationID = safeGenerationID,
                error = error.mobileTaskError(),
            )
            taskRepository.saveTask(failed)
            AndroidBackgroundDownloadRuntimeResult.Failed(
                snapshot = failed,
                reason = "Android background download failed.",
            )
        }
    }
}

private fun Exception.mobileTaskError(): MobileTaskError =
    when (this) {
        is AndroidBackgroundDownloadFailure -> mobileTaskError
        else -> MobileTaskError.NETWORK_UNAVAILABLE
    }

private fun AndroidBackgroundDownloadProgress.mobileTaskProgress(): MobileTaskProgress {
    val safeDownloaded = bytesDownloaded.coerceAtLeast(0L)
    val safeTotal = totalBytes?.takeIf { it > 0L }
    return if (safeTotal != null) {
        val percent = ((safeDownloaded * 100L) / safeTotal).coerceIn(1L, 99L).toInt()
        MobileTaskProgress(
            phase = MobileTaskPhase.DOWNLOADING,
            completedUnitCount = percent,
            totalUnitCount = 100,
        )
    } else {
        MobileTaskProgress(
            phase = MobileTaskPhase.DOWNLOADING,
            completedUnitCount = safeDownloaded.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            totalUnitCount = null,
        )
    }
}

private fun MobileDownloadRequest.downloadingSnapshot(
    generationID: String,
    progress: MobileTaskProgress = MobileTaskProgress(
        phase = MobileTaskPhase.DOWNLOADING,
        completedUnitCount = 1,
        totalUnitCount = 100,
    ),
): MobileTaskSnapshot =
    MobileTaskSnapshot(
        id = id,
        platform = MobilePlatform.ANDROID,
        state = MobileTaskState.DOWNLOADING,
        progress = progress,
        exportProfile = exportProfile,
        executionGenerationID = generationID,
        backgroundPolicy = androidBackgroundDownloadPolicy,
        capabilities = androidBackgroundDownloadCapabilities,
        error = null,
    )

private fun MobileDownloadRequest.completedSnapshot(
    downloaded: AndroidBackgroundDownloadedFile,
    generationID: String,
): MobileTaskSnapshot {
    val artifact = MobileTaskArtifact(
        id = "downloaded-$id",
        kind = MobileArtifactKind.ORIGINAL_MEDIA,
        displayName = preferredTitle ?: "下载任务",
        storageIdentifier = downloaded.storageIdentifier,
        byteCount = downloaded.byteCount,
    )
    return MobileTaskSnapshot(
        id = id,
        platform = MobilePlatform.ANDROID,
        state = MobileTaskState.COMPLETED,
        progress = MobileTaskProgress(
            phase = MobileTaskPhase.DOWNLOADING,
            completedUnitCount = 100,
            totalUnitCount = 100,
        ),
        exportProfile = exportProfile,
        executionGenerationID = generationID,
        backgroundPolicy = androidBackgroundDownloadPolicy,
        capabilities = androidBackgroundDownloadCapabilities,
        result = MobileTaskResult(
            artifacts = listOf(artifact),
            primaryArtifactID = artifact.id,
        ),
        error = null,
    )
}

private fun MobileDownloadRequest.failedSnapshot(
    generationID: String,
    error: MobileTaskError,
): MobileTaskSnapshot =
    MobileTaskSnapshot(
        id = id,
        platform = MobilePlatform.ANDROID,
        state = MobileTaskState.FAILED,
        progress = MobileTaskProgress(phase = MobileTaskPhase.DOWNLOADING),
        exportProfile = exportProfile,
        executionGenerationID = generationID,
        backgroundPolicy = androidBackgroundDownloadPolicy,
        capabilities = androidBackgroundDownloadCapabilities,
        error = error,
    )

private fun MobileDownloadRequest.cancelledSnapshot(generationID: String): MobileTaskSnapshot =
    MobileTaskSnapshot(
        id = id,
        platform = MobilePlatform.ANDROID,
        state = MobileTaskState.CANCELLED,
        progress = MobileTaskProgress(phase = MobileTaskPhase.DOWNLOADING),
        exportProfile = exportProfile,
        executionGenerationID = generationID,
        backgroundPolicy = androidBackgroundDownloadPolicy,
        capabilities = androidBackgroundDownloadCapabilities,
        error = MobileTaskError.CANCELLED,
    )

private val androidBackgroundDownloadPolicy: MobileBackgroundPolicy
    get() = MobileBackgroundPolicy(
        execution = MobileBackgroundExecution.SCHEDULED_WORK,
        resumability = MobileBackgroundResumability.RESUMABLE,
        limits = listOf(MobileBackgroundLimit.USER_VISIBLE_NOTIFICATION_REQUIRED),
    )

private val androidBackgroundDownloadCapabilities: MobileProcessingCapabilities
    get() = MobileProcessingCapabilities(
        platform = MobilePlatform.ANDROID,
        supportedCapabilities = listOf(
            MobileProcessingCapability.DOWNLOAD,
            MobileProcessingCapability.BACKGROUND_TRANSFER,
        ),
    )
