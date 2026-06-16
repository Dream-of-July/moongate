package com.moongate.mobile.worker

import androidx.lifecycle.Observer
import androidx.work.WorkInfo

fun interface AndroidBackgroundWorkObservationRegistration {
    fun cancel()
}

object AndroidNoopBackgroundWorkObservationRegistration : AndroidBackgroundWorkObservationRegistration {
    override fun cancel() = Unit
}

class AndroidBackgroundWorkForegroundObserver(
    private val scheduler: AndroidBackgroundWorkScheduler,
) {
    fun observeTaskStatuses(
        taskIDs: List<String>,
        onStatus: (taskID: String, status: AndroidBackgroundObservedWorkStatus) -> Unit,
    ): AndroidBackgroundWorkObservationRegistration {
        val registrations = taskIDs
            .distinct()
            .mapNotNull { taskID ->
                val liveData = scheduler.workInfosForTaskID(taskID) ?: return@mapNotNull null
                val observer = Observer<List<WorkInfo>> { workInfos ->
                    onStatus(taskID, AndroidBackgroundWorkStatusMapper.from(workInfos.preferredForegroundWorkInfo()))
                }
                liveData.observeForever(observer)
                AndroidBackgroundWorkObservationRegistration {
                    liveData.removeObserver(observer)
                }
            }

        if (registrations.isEmpty()) {
            return AndroidNoopBackgroundWorkObservationRegistration
        }

        return AndroidBackgroundWorkObservationRegistration {
            registrations.forEach { it.cancel() }
        }
    }
}

private fun List<WorkInfo>.preferredForegroundWorkInfo(): WorkInfo? =
    firstOrNull { it.state == WorkInfo.State.RUNNING }
        ?: firstOrNull { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED }
        ?: firstOrNull { it.state == WorkInfo.State.FAILED || it.state == WorkInfo.State.CANCELLED }
        ?: firstOrNull { it.state == WorkInfo.State.SUCCEEDED }
        ?: firstOrNull()
