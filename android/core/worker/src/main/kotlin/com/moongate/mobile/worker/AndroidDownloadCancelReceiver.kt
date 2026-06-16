package com.moongate.mobile.worker

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.WorkManager
import java.io.File
import java.util.UUID

class AndroidDownloadCancelReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action != ActionCancel) {
            return
        }
        val workHandle = intent.getStringExtra(ExtraWorkHandle)
            ?.takeIf { it.isOpaqueWorkHandle() }
            ?: return
        val generationID = intent.getStringExtra(ExtraGenerationID)
            ?.takeIf { it.isOpaqueWorkGenerationID() }
            ?: return
        val workID = intent.getStringExtra(ExtraWorkID)
            ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
            ?: return

        val appContext = context.applicationContext
        AndroidBackgroundDownloadHandoffStore(
            File(appContext.noBackupFilesDir, "background-download-handoffs"),
        ).cancelIfGenerationMatches(
            workHandle = workHandle,
            generationID = generationID,
        )
        WorkManager.getInstance(appContext).cancelWorkById(workID)
    }

    companion object {
        private const val ActionCancel = "com.moongate.mobile.worker.action.CANCEL_BACKGROUND_DOWNLOAD"
        private const val ExtraWorkHandle = "work_handle"
        private const val ExtraGenerationID = "generation_id"
        private const val ExtraWorkID = "work_id"

        fun pendingIntent(
            context: Context,
            workHandle: String,
            generationID: String,
            workID: String,
        ): PendingIntent {
            val intent = Intent(context, AndroidDownloadCancelReceiver::class.java)
                .setAction(ActionCancel)
                .putExtra(ExtraWorkHandle, workHandle)
                .putExtra(ExtraGenerationID, generationID)
                .putExtra(ExtraWorkID, workID)
            return PendingIntent.getBroadcast(
                context,
                generationID.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
