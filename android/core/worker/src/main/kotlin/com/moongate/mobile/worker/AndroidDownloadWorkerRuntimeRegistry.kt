package com.moongate.mobile.worker

import android.content.Context
import com.moongate.mobile.data.repository.JsonTaskRepository
import java.io.File

object AndroidDownloadWorkerRuntimeRegistry {
    fun runtime(context: Context): AndroidBackgroundDownloadRuntime =
        AndroidBackgroundDownloadRuntime(
            handoffStore = AndroidBackgroundDownloadHandoffStore(
                File(context.noBackupFilesDir, "background-download-handoffs"),
            ),
            taskRepository = JsonTaskRepository(
                File(File(context.filesDir, "tasks"), "tasks.json").toPath(),
            ),
            downloader = AndroidDirectMediaBackgroundDownloader(
                File(context.filesDir, "downloads"),
            ),
        )
}
