package com.moongate.mobile.worker

import androidx.work.WorkInfo

enum class AndroidBackgroundObservedWorkState {
    ENQUEUED,
    RUNNING,
    SUCCEEDED,
    FAILED,
    BLOCKED,
    CANCELLED,
    UNKNOWN,
}

data class AndroidBackgroundObservedWorkStatus(
    val state: AndroidBackgroundObservedWorkState,
    val bytesDownloaded: Long?,
    val totalBytes: Long?,
    val progressPercent: Int?,
) {
    val isTerminal: Boolean
        get() = state == AndroidBackgroundObservedWorkState.SUCCEEDED ||
            state == AndroidBackgroundObservedWorkState.FAILED ||
            state == AndroidBackgroundObservedWorkState.CANCELLED
}

object AndroidBackgroundWorkStatusMapper {
    fun from(workInfo: WorkInfo?): AndroidBackgroundObservedWorkStatus =
        AndroidBackgroundObservedWorkStatus(
            state = workInfo?.state.observedState,
            bytesDownloaded = workInfo?.progress?.getLong(AndroidDownloadWorker.ProgressBytesDownloadedKey, -1L)
                ?.takeIf { it >= 0L },
            totalBytes = workInfo?.progress?.getLong(AndroidDownloadWorker.ProgressTotalBytesKey, -1L)
                ?.takeIf { it > 0L },
            progressPercent = workInfo?.progress?.getInt(AndroidDownloadWorker.ProgressPercentKey, -1)
                ?.takeIf { it in 0..100 },
        )
}

private val WorkInfo.State?.observedState: AndroidBackgroundObservedWorkState
    get() = when (this) {
        WorkInfo.State.ENQUEUED -> AndroidBackgroundObservedWorkState.ENQUEUED
        WorkInfo.State.RUNNING -> AndroidBackgroundObservedWorkState.RUNNING
        WorkInfo.State.SUCCEEDED -> AndroidBackgroundObservedWorkState.SUCCEEDED
        WorkInfo.State.FAILED -> AndroidBackgroundObservedWorkState.FAILED
        WorkInfo.State.BLOCKED -> AndroidBackgroundObservedWorkState.BLOCKED
        WorkInfo.State.CANCELLED -> AndroidBackgroundObservedWorkState.CANCELLED
        null -> AndroidBackgroundObservedWorkState.UNKNOWN
    }
