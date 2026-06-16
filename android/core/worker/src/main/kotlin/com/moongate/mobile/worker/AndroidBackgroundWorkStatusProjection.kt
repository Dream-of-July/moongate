package com.moongate.mobile.worker

import com.moongate.mobile.domain.MobileBackgroundExecution
import com.moongate.mobile.domain.MobileBackgroundLimit
import com.moongate.mobile.domain.MobileBackgroundPolicy
import com.moongate.mobile.domain.MobileTaskError
import com.moongate.mobile.domain.MobileTaskPhase
import com.moongate.mobile.domain.MobileTaskProgress
import com.moongate.mobile.domain.MobileTaskSnapshot
import com.moongate.mobile.domain.MobileTaskState

object AndroidBackgroundWorkStatusProjection {
    fun apply(
        snapshot: MobileTaskSnapshot,
        observed: AndroidBackgroundObservedWorkStatus?,
    ): MobileTaskSnapshot =
        when (observed?.state) {
            AndroidBackgroundObservedWorkState.ENQUEUED,
            AndroidBackgroundObservedWorkState.BLOCKED,
            -> snapshot.copy(
                state = MobileTaskState.DOWNLOADING,
                progress = observed.progressSnapshot() ?: snapshot.progress,
                backgroundPolicy = androidObservedWorkPolicy,
                error = null,
            )

            AndroidBackgroundObservedWorkState.RUNNING -> snapshot.copy(
                state = MobileTaskState.DOWNLOADING,
                progress = observed.progressSnapshot() ?: snapshot.progress,
                backgroundPolicy = androidObservedWorkPolicy,
                error = null,
            )

            AndroidBackgroundObservedWorkState.FAILED -> snapshot.copy(
                state = MobileTaskState.FAILED,
                progress = observed.progressSnapshot() ?: snapshot.progress,
                backgroundPolicy = androidObservedWorkPolicy,
                error = MobileTaskError.NETWORK_UNAVAILABLE,
            )

            AndroidBackgroundObservedWorkState.CANCELLED -> snapshot.copy(
                state = MobileTaskState.CANCELLED,
                progress = observed.progressSnapshot() ?: snapshot.progress,
                backgroundPolicy = androidObservedWorkPolicy,
                error = MobileTaskError.CANCELLED,
            )

            AndroidBackgroundObservedWorkState.SUCCEEDED,
            AndroidBackgroundObservedWorkState.UNKNOWN,
            null,
            -> snapshot
        }

    private fun AndroidBackgroundObservedWorkStatus.progressSnapshot(): MobileTaskProgress? =
        progressPercent
            ?.coerceIn(0, 100)
            ?.let { percent ->
                MobileTaskProgress(
                    phase = MobileTaskPhase.DOWNLOADING,
                    completedUnitCount = percent,
                    totalUnitCount = 100,
                )
            }
            ?: bytesDownloaded
                ?.coerceAtLeast(0L)
                ?.coerceAtMost(Int.MAX_VALUE.toLong())
                ?.toInt()
                ?.let { downloaded ->
                    MobileTaskProgress(
                        phase = MobileTaskPhase.DOWNLOADING,
                        completedUnitCount = downloaded,
                        totalUnitCount = totalBytes
                            ?.takeIf { it > 0L && it <= Int.MAX_VALUE.toLong() }
                            ?.toInt(),
                    )
                }
}

private val androidObservedWorkPolicy: MobileBackgroundPolicy
    get() = MobileBackgroundPolicy(
        execution = MobileBackgroundExecution.SCHEDULED_WORK,
        limits = listOf(MobileBackgroundLimit.USER_VISIBLE_NOTIFICATION_REQUIRED),
    )
