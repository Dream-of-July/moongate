import XCTest

final class AndroidDataBoundaryTests: XCTestCase {
    func testAndroidCoreDataModuleIsDeclaredAndPureJvm() throws {
        let root = packageRoot()
        let settings = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("settings.gradle.kts"))
        let buildFile = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("data")
            .appendingPathComponent("build.gradle.kts"))

        XCTAssertTrue(settings.contains(#"include(":core:data")"#))
        XCTAssertTrue(buildFile.contains(#"alias(libs.plugins.kotlin.jvm)"#))
        XCTAssertFalse(buildFile.contains("com.android.library"))
        XCTAssertTrue(buildFile.contains(#"implementation(project(":core:domain"))"#))
    }

    func testAndroidWorkerModuleDeclaresBoundedWorkManagerSkeletonWithoutNetworkImplementation() throws {
        let root = packageRoot()
        let settings = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("settings.gradle.kts"))
        let versions = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("gradle")
            .appendingPathComponent("libs.versions.toml"))
        let workerDirectory = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("worker")
        let buildFileURL = workerDirectory.appendingPathComponent("build.gradle.kts")
        let manifestURL = root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("AndroidManifest.xml")
        let sourceDirectory = workerDirectory
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("worker")
        let schedulerURL = sourceDirectory.appendingPathComponent("AndroidBackgroundWorkScheduler.kt")
        let workerURL = sourceDirectory.appendingPathComponent("AndroidDownloadWorker.kt")
        let cancelReceiverURL = sourceDirectory.appendingPathComponent("AndroidDownloadCancelReceiver.kt")
        let runtimeURL = sourceDirectory.appendingPathComponent("AndroidBackgroundDownloadRuntime.kt")
        let directDownloaderURL = sourceDirectory.appendingPathComponent("AndroidDirectMediaBackgroundDownloader.kt")
        let statusMapperURL = sourceDirectory.appendingPathComponent("AndroidBackgroundWorkStatusMapper.kt")
        let statusProjectionURL = sourceDirectory.appendingPathComponent("AndroidBackgroundWorkStatusProjection.kt")
        let foregroundObserverURL = sourceDirectory.appendingPathComponent("AndroidBackgroundWorkForegroundObserver.kt")
        let workerTestURL = workerDirectory
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("worker")
            .appendingPathComponent("AndroidBackgroundWorkSchedulerTest.kt")

        XCTAssertTrue(settings.contains(#"include(":core:worker")"#))
        XCTAssertTrue(versions.contains("androidxWork"))
        XCTAssertTrue(versions.contains("androidx-work-runtime-ktx"))
        XCTAssertTrue(versions.contains("androidxCore"))
        XCTAssertTrue(versions.contains("androidx-core"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: buildFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: schedulerURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workerURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cancelReceiverURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directDownloaderURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: statusMapperURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: statusProjectionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foregroundObserverURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workerTestURL.path))

        guard
            FileManager.default.fileExists(atPath: buildFileURL.path),
            FileManager.default.fileExists(atPath: manifestURL.path),
            FileManager.default.fileExists(atPath: schedulerURL.path),
            FileManager.default.fileExists(atPath: workerURL.path),
            FileManager.default.fileExists(atPath: cancelReceiverURL.path),
            FileManager.default.fileExists(atPath: runtimeURL.path),
            FileManager.default.fileExists(atPath: directDownloaderURL.path),
            FileManager.default.fileExists(atPath: statusMapperURL.path),
            FileManager.default.fileExists(atPath: statusProjectionURL.path),
            FileManager.default.fileExists(atPath: foregroundObserverURL.path),
            FileManager.default.fileExists(atPath: workerTestURL.path)
        else {
            return
        }

        let buildFile = try String(contentsOf: buildFileURL)
        let manifest = try String(contentsOf: manifestURL)
        let workerFile = try String(contentsOf: workerURL)
        let cancelReceiverFile = try String(contentsOf: cancelReceiverURL)
        let runtimeFile = try String(contentsOf: runtimeURL)
        let runtimeRegistryFile = try String(contentsOf: sourceDirectory
            .appendingPathComponent("AndroidDownloadWorkerRuntimeRegistry.kt"))
        XCTAssertTrue(buildFile.contains(#"alias(libs.plugins.android.library)"#))
        XCTAssertTrue(buildFile.contains(#"alias(libs.plugins.kotlin.android)"#))
        XCTAssertTrue(buildFile.contains(#"implementation(project(":core:data"))"#))
        XCTAssertTrue(buildFile.contains(#"implementation(project(":core:domain"))"#))
        XCTAssertTrue(buildFile.contains("implementation(libs.androidx.work.runtime.ktx)"))
        XCTAssertTrue(buildFile.contains("implementation(libs.androidx.core)"))
        XCTAssertTrue(buildFile.contains(#"testImplementation(kotlin("test-junit"))"#))
        XCTAssertTrue(manifest.contains(#"<uses-permission android:name="android.permission.INTERNET" />"#))
        XCTAssertTrue(manifest.contains(#"<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />"#))
        XCTAssertTrue(manifest.contains(#"<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />"#))
        XCTAssertTrue(manifest.contains(#"<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />"#))
        XCTAssertTrue(manifest.contains(#"xmlns:tools="http://schemas.android.com/tools""#))
        XCTAssertTrue(manifest.contains(#"androidx.work.impl.foreground.SystemForegroundService"#))
        XCTAssertTrue(manifest.contains(#"android:foregroundServiceType="dataSync""#))
        XCTAssertTrue(manifest.contains(#"tools:node="merge""#))
        XCTAssertTrue(manifest.contains(#"android:name="com.moongate.mobile.worker.AndroidDownloadCancelReceiver""#))
        XCTAssertTrue(manifest.contains(#"android:exported="false""#))

        let source = try kotlinSourceContents(under: sourceDirectory)
        let testSource = try String(contentsOf: workerTestURL)
        let schedulerSource = try String(contentsOf: schedulerURL)
        let handoffStoreSource = try String(contentsOf: sourceDirectory
            .appendingPathComponent("AndroidBackgroundDownloadHandoffStore.kt"))
        let directDownloaderSource = try String(contentsOf: directDownloaderURL)
        let statusMapperSource = try String(contentsOf: statusMapperURL)
        let statusProjectionSource = try String(contentsOf: statusProjectionURL)
        let foregroundObserverSource = try String(contentsOf: foregroundObserverURL)
        XCTAssertTrue(source.contains("package com.moongate.mobile.worker"))
        XCTAssertTrue(source.contains("class AndroidBackgroundWorkScheduler"))
        XCTAssertTrue(source.contains("fun descriptorFor(request: MobileDownloadRequest): AndroidBackgroundWorkDescriptor"))
        XCTAssertTrue(source.contains("fun descriptorForTaskID(taskID: String): AndroidBackgroundWorkDescriptor"))
        XCTAssertTrue(source.contains("fun enqueueTaskID(taskID: String): AndroidBackgroundWorkDescriptor"))
        XCTAssertTrue(source.contains("import androidx.work.ExistingWorkPolicy"))
        XCTAssertTrue(source.contains("OneTimeWorkRequest"))
        XCTAssertTrue(source.contains("NetworkType.CONNECTED"))
        XCTAssertTrue(source.contains("uniqueWorkName = workHandle"))
        XCTAssertTrue(source.contains("enqueueUniqueWork("))
        XCTAssertTrue(source.contains("ExistingWorkPolicy.REPLACE"))
        XCTAssertTrue(source.contains("cancelUniqueWork(descriptor.uniqueWorkName)"))
        XCTAssertTrue(source.contains("handoffStore?.cancelLatest(descriptor.workHandle)"))
        XCTAssertTrue(source.contains("fun workInfosForTaskID(taskID: String)"))
        XCTAssertTrue(source.contains("workManager?.getWorkInfosForUniqueWorkLiveData(descriptor.uniqueWorkName)"))
        XCTAssertTrue(source.contains("setRequiresStorageNotLow(true)"))
        XCTAssertTrue(source.contains("requiresForegroundNotification = true"))
        XCTAssertTrue(source.contains("doesNotGuaranteeUnlimitedBackgroundRuntime = true"))
        XCTAssertTrue(source.contains("class AndroidDownloadWorker"))
        XCTAssertTrue(source.contains("CoroutineWorker"))
        XCTAssertTrue(source.contains("setForeground(foregroundInfo(null))"))
        XCTAssertTrue(source.contains("ForegroundInfo"))
        XCTAssertTrue(source.contains("NotificationCompat.Builder"))
        XCTAssertTrue(source.contains("NotificationChannel"))
        XCTAssertTrue(source.contains("Build.VERSION_CODES.O"))
        XCTAssertTrue(source.contains("Build.VERSION_CODES.Q"))
        XCTAssertTrue(source.contains("ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC"))
        XCTAssertTrue(source.contains("loadLabel(packageManager)"))
        XCTAssertTrue(source.contains("applicationInfo.icon"))
        XCTAssertTrue(source.contains("android.R.drawable.stat_sys_download"))
        XCTAssertTrue(workerFile.contains("data class AndroidBackgroundDownloadNotificationContent"))
        XCTAssertTrue(workerFile.contains("internal fun androidBackgroundDownloadNotificationContent("))
        XCTAssertTrue(workerFile.contains(#"text = "后台下载中""#))
        XCTAssertTrue(workerFile.contains(#"channelDescription = "后台下载进度与取消""#))
        XCTAssertTrue(workerFile.contains(#"cancelActionLabel = "取消""#))
        XCTAssertTrue(workerFile.contains("androidBackgroundDownloadNotificationContent(applicationLabel())"))
        XCTAssertTrue(workerFile.contains(".setContentTitle(content.title)"))
        XCTAssertTrue(workerFile.contains(".setContentText(content.text)"))
        XCTAssertTrue(workerFile.contains(".setProgress("))
        XCTAssertTrue(workerFile.contains("progressPercent ?: content.progressValue"))
        XCTAssertTrue(workerFile.contains("progressPercent == null"))
        XCTAssertTrue(workerFile.contains(".addAction("))
        XCTAssertTrue(workerFile.contains("AndroidDownloadCancelReceiver.pendingIntent("))
        XCTAssertTrue(workerFile.contains("workHandle = inputData.getString(InputWorkHandleKey).orEmpty()"))
        XCTAssertTrue(workerFile.contains("generationID = inputData.getString(InputGenerationIDKey).orEmpty()"))
        XCTAssertTrue(workerFile.contains("workID = id.toString()"))
        XCTAssertTrue(cancelReceiverFile.contains("class AndroidDownloadCancelReceiver : BroadcastReceiver()"))
        XCTAssertTrue(cancelReceiverFile.contains("takeIf { it.isOpaqueWorkHandle() }"))
        XCTAssertTrue(cancelReceiverFile.contains("takeIf { it.isOpaqueWorkGenerationID() }"))
        XCTAssertTrue(cancelReceiverFile.contains("AndroidBackgroundDownloadHandoffStore("))
        XCTAssertTrue(cancelReceiverFile.contains("File(appContext.noBackupFilesDir, \"background-download-handoffs\")"))
        XCTAssertTrue(cancelReceiverFile.contains("cancelIfGenerationMatches("))
        XCTAssertTrue(cancelReceiverFile.contains("WorkManager.getInstance(appContext).cancelWorkById(workID)"))
        XCTAssertFalse(cancelReceiverFile.contains("cancelUniqueWork"))
        XCTAssertFalse(cancelReceiverFile.contains("sourceURL"))
        XCTAssertFalse(cancelReceiverFile.contains("Authorization"))
        XCTAssertFalse(workerFile.contains(#".setContentText("后台下载准备中")"#))
        XCTAssertFalse(workerFile.contains("Preparing background work"))
        XCTAssertTrue(source.contains("Result.failure"))
        XCTAssertTrue(workerFile.contains("AndroidDownloadWorkerRuntimeRegistry.runtime(applicationContext)"))
        XCTAssertTrue(workerFile.contains("val canRetry = runAttemptCount < MaxBackgroundDownloadRetryAttempts"))
        XCTAssertTrue(workerFile.contains("runtime.run("))
        XCTAssertTrue(workerFile.contains("inputData.getString(InputWorkHandleKey)"))
        XCTAssertTrue(workerFile.contains("inputData.getString(InputGenerationIDKey)"))
        XCTAssertTrue(workerFile.contains("canRetry = canRetry"))
        XCTAssertTrue(workerFile.contains("progress = ::publishProgress"))
        XCTAssertTrue(workerFile.contains("private suspend fun publishProgress(progress: AndroidBackgroundDownloadProgress)"))
        XCTAssertTrue(workerFile.contains("setProgress("))
        XCTAssertTrue(workerFile.contains("val progressPercent = safeTotal?.let"))
        XCTAssertTrue(workerFile.contains("((safeDownloaded * 100L) / total).coerceIn(1L, 99L).toInt()"))
        XCTAssertTrue(workerFile.contains("setForeground(foregroundInfo(progressPercent))"))
        XCTAssertTrue(workerFile.contains("Data.Builder()"))
        XCTAssertTrue(workerFile.contains(#"const val InputGenerationIDKey = "generation_id""#))
        XCTAssertTrue(workerFile.contains(#"const val ProgressBytesDownloadedKey = "bytes_downloaded""#))
        XCTAssertTrue(workerFile.contains(#"const val ProgressTotalBytesKey = "total_bytes""#))
        XCTAssertTrue(workerFile.contains(#"const val ProgressPercentKey = "progress_percent""#))
        XCTAssertTrue(workerFile.contains("progressPercent ?: content.progressValue"))
        XCTAssertTrue(workerFile.contains("progressPercent == null"))
        XCTAssertTrue(workerFile.contains("AndroidBackgroundDownloadRuntimeResult.Completed"))
        XCTAssertTrue(workerFile.contains("AndroidBackgroundDownloadRuntimeResult.Blocked"))
        XCTAssertTrue(workerFile.contains("AndroidBackgroundDownloadRuntimeResult.Retrying"))
        XCTAssertTrue(workerFile.contains("AndroidBackgroundDownloadRuntimeResult.Failed"))
        XCTAssertTrue(workerFile.contains("Result.success()"))
        XCTAssertTrue(workerFile.contains("Result.retry()"))
        XCTAssertTrue(workerFile.contains("Result.failure()"))
        XCTAssertTrue(workerFile.contains("MaxBackgroundDownloadRetryAttempts = 3"))
        XCTAssertTrue(runtimeRegistryFile.contains("object AndroidDownloadWorkerRuntimeRegistry"))
        XCTAssertTrue(runtimeRegistryFile.contains("File(context.noBackupFilesDir, \"background-download-handoffs\")"))
        XCTAssertTrue(runtimeRegistryFile.contains("JsonTaskRepository("))
        XCTAssertTrue(runtimeRegistryFile.contains("File(File(context.filesDir, \"tasks\"), \"tasks.json\").toPath()"))
        XCTAssertTrue(runtimeRegistryFile.contains("AndroidDirectMediaBackgroundDownloader("))
        XCTAssertTrue(runtimeRegistryFile.contains("File(context.filesDir, \"downloads\")"))
        XCTAssertTrue(source.contains("class AndroidBackgroundDownloadRuntime"))
        XCTAssertTrue(source.contains("class AndroidDirectMediaBackgroundDownloader"))
        XCTAssertTrue(runtimeFile.contains("interface AndroidBackgroundDirectDownloader"))
        XCTAssertTrue(runtimeFile.contains("progress: suspend (AndroidBackgroundDownloadProgress) -> Unit"))
        XCTAssertTrue(runtimeFile.contains("progress: suspend (AndroidBackgroundDownloadProgress) -> Unit = {}"))
        XCTAssertTrue(runtimeFile.contains("private val downloader: AndroidBackgroundDirectDownloader"))
        XCTAssertTrue(runtimeFile.contains("private val taskRepository: TaskRepository"))
        XCTAssertTrue(runtimeFile.contains("private val handoffStore: AndroidBackgroundDownloadHandoffStore"))
        XCTAssertTrue(runtimeFile.contains("data class Retrying("))
        XCTAssertTrue(runtimeFile.contains("canRetry: Boolean"))
        XCTAssertTrue(runtimeFile.contains("val safeGenerationID = generationID?.takeIf { it.isOpaqueWorkGenerationID() }"))
        XCTAssertTrue(runtimeFile.contains("Android background work generation is missing or invalid."))
        XCTAssertTrue(runtimeFile.contains("handoffStore.load(safeWorkHandle)"))
        XCTAssertTrue(runtimeFile.contains("handoff.generationID != safeGenerationID"))
        XCTAssertTrue(runtimeFile.contains("Android background download handoff was replaced."))
        XCTAssertTrue(runtimeFile.contains("taskRepository.saveTask(request.downloadingSnapshot(safeGenerationID))"))
        XCTAssertTrue(runtimeFile.contains("request.downloadingSnapshot("))
        XCTAssertTrue(runtimeFile.contains("generationID = safeGenerationID"))
        XCTAssertTrue(runtimeFile.contains("progress = downloadProgress.mobileTaskProgress()"))
        XCTAssertTrue(runtimeFile.contains("progress(downloadProgress)"))
        XCTAssertTrue(runtimeFile.contains("handoffStore.isActiveGeneration(safeWorkHandle, safeGenerationID)"))
        XCTAssertTrue(runtimeFile.contains("Android background download handoff was replaced before completion."))
        XCTAssertTrue(runtimeFile.contains("taskRepository.saveTask(completed)"))
        XCTAssertTrue(runtimeFile.contains("handoffStore.removeIfGenerationMatches("))
        XCTAssertTrue(runtimeFile.contains("handoffStore.cancelIfGenerationMatches("))
        XCTAssertTrue(runtimeFile.contains("taskRepository.saveTask(request.cancelledSnapshot(safeGenerationID))"))
        XCTAssertTrue(runtimeFile.contains("taskRepository.saveTask(retrying)"))
        XCTAssertTrue(runtimeFile.contains("AndroidBackgroundDownloadRuntimeResult.Retrying("))
        XCTAssertTrue(runtimeFile.contains("val failed = request.failedSnapshot("))
        XCTAssertTrue(runtimeFile.contains("error = error.mobileTaskError()"))
        XCTAssertTrue(runtimeFile.contains("private fun Exception.mobileTaskError(): MobileTaskError"))
        XCTAssertTrue(runtimeFile.contains("is AndroidBackgroundDownloadFailure -> mobileTaskError"))
        XCTAssertTrue(runtimeFile.contains("else -> MobileTaskError.NETWORK_UNAVAILABLE"))
        XCTAssertTrue(runtimeFile.contains("private fun MobileDownloadRequest.failedSnapshot("))
        XCTAssertTrue(runtimeFile.contains("error: MobileTaskError"))
        XCTAssertTrue(runtimeFile.contains("executionGenerationID = generationID"))
        XCTAssertTrue(runtimeFile.contains("private fun MobileDownloadRequest.cancelledSnapshot(generationID: String)"))
        XCTAssertFalse(runtimeFile.contains("private fun MobileDownloadRequest.failedSnapshot(): MobileTaskSnapshot"))
        XCTAssertFalse(runtimeFile.contains("error = MobileTaskError.NETWORK_UNAVAILABLE"))
        XCTAssertTrue(runtimeFile.contains("taskRepository.saveTask(failed)"))
        XCTAssertTrue(runtimeFile.contains("MobileBackgroundExecution.SCHEDULED_WORK"))
        XCTAssertTrue(runtimeFile.contains("MobileBackgroundLimit.USER_VISIBLE_NOTIFICATION_REQUIRED"))
        XCTAssertTrue(runtimeFile.contains("MobileProcessingCapability.BACKGROUND_TRANSFER"))
        XCTAssertTrue(runtimeFile.contains("require(storageIdentifier.startsWith(\"android-owned:\"))"))
        XCTAssertTrue(runtimeFile.contains("sealed class AndroidBackgroundDownloadFailure"))
        XCTAssertTrue(runtimeFile.contains("val mobileTaskError: MobileTaskError"))
        XCTAssertTrue(runtimeFile.contains("MobileTaskError.STORAGE_FULL"))
        XCTAssertTrue(runtimeFile.contains("MobileTaskError.UNSUPPORTED_ON_MOBILE"))
        XCTAssertTrue(runtimeFile.contains("MobileTaskError.NETWORK_UNAVAILABLE"))
        XCTAssertTrue(statusMapperSource.contains("object AndroidBackgroundWorkStatusMapper"))
        XCTAssertTrue(statusMapperSource.contains("data class AndroidBackgroundObservedWorkStatus"))
        XCTAssertTrue(statusMapperSource.contains("enum class AndroidBackgroundObservedWorkState"))
        XCTAssertTrue(statusMapperSource.contains("WorkInfo.State.ENQUEUED -> AndroidBackgroundObservedWorkState.ENQUEUED"))
        XCTAssertTrue(statusMapperSource.contains("WorkInfo.State.RUNNING -> AndroidBackgroundObservedWorkState.RUNNING"))
        XCTAssertTrue(statusMapperSource.contains("WorkInfo.State.SUCCEEDED -> AndroidBackgroundObservedWorkState.SUCCEEDED"))
        XCTAssertTrue(statusMapperSource.contains("WorkInfo.State.FAILED -> AndroidBackgroundObservedWorkState.FAILED"))
        XCTAssertTrue(statusMapperSource.contains("WorkInfo.State.CANCELLED -> AndroidBackgroundObservedWorkState.CANCELLED"))
        XCTAssertTrue(statusMapperSource.contains("AndroidDownloadWorker.ProgressBytesDownloadedKey"))
        XCTAssertTrue(statusMapperSource.contains("AndroidDownloadWorker.ProgressTotalBytesKey"))
        XCTAssertTrue(statusMapperSource.contains("AndroidDownloadWorker.ProgressPercentKey"))
        XCTAssertFalse(statusMapperSource.contains("inputData"))
        XCTAssertFalse(statusMapperSource.contains("InputWorkHandleKey"))
        XCTAssertFalse(statusMapperSource.contains("sourceURL"))
        XCTAssertFalse(statusMapperSource.contains("sourceUrl"))
        XCTAssertFalse(statusMapperSource.contains("Authorization"))
        XCTAssertFalse(statusMapperSource.contains("Bearer "))
        XCTAssertFalse(statusMapperSource.contains("apiKey"))
        XCTAssertFalse(statusMapperSource.contains("secret"))
        XCTAssertTrue(statusProjectionSource.contains("object AndroidBackgroundWorkStatusProjection"))
        XCTAssertTrue(statusProjectionSource.contains("fun apply("))
        XCTAssertTrue(statusProjectionSource.contains("MobileTaskSnapshot"))
        XCTAssertTrue(statusProjectionSource.contains("AndroidBackgroundObservedWorkStatus"))
        XCTAssertTrue(statusProjectionSource.contains("AndroidBackgroundObservedWorkState.RUNNING"))
        XCTAssertTrue(statusProjectionSource.contains("AndroidBackgroundObservedWorkState.FAILED"))
        XCTAssertTrue(statusProjectionSource.contains("AndroidBackgroundObservedWorkState.CANCELLED"))
        XCTAssertTrue(statusProjectionSource.contains("AndroidBackgroundObservedWorkState.SUCCEEDED"))
        XCTAssertTrue(statusProjectionSource.contains("MobileTaskState.DOWNLOADING"))
        XCTAssertTrue(statusProjectionSource.contains("MobileTaskState.FAILED"))
        XCTAssertTrue(statusProjectionSource.contains("MobileTaskState.CANCELLED"))
        XCTAssertTrue(statusProjectionSource.contains("MobileTaskError.NETWORK_UNAVAILABLE"))
        XCTAssertTrue(statusProjectionSource.contains("MobileTaskError.CANCELLED"))
        XCTAssertTrue(statusProjectionSource.contains("MobileTaskPhase.DOWNLOADING"))
        XCTAssertTrue(statusProjectionSource.contains("MobileBackgroundExecution.SCHEDULED_WORK"))
        XCTAssertTrue(statusProjectionSource.contains("MobileBackgroundLimit.USER_VISIBLE_NOTIFICATION_REQUIRED"))
        XCTAssertFalse(statusProjectionSource.contains("inputData"))
        XCTAssertFalse(statusProjectionSource.contains("InputWorkHandleKey"))
        XCTAssertFalse(statusProjectionSource.contains("InputGenerationIDKey"))
        XCTAssertFalse(statusProjectionSource.contains("sourceURL"))
        XCTAssertFalse(statusProjectionSource.contains("sourceUrl"))
        XCTAssertFalse(statusProjectionSource.contains("Authorization"))
        XCTAssertFalse(statusProjectionSource.contains("Bearer "))
        XCTAssertFalse(statusProjectionSource.contains("apiKey"))
        XCTAssertFalse(statusProjectionSource.contains("secret"))
        XCTAssertFalse(statusProjectionSource.contains("MobileTaskState.COMPLETED"))
        XCTAssertTrue(foregroundObserverSource.contains("class AndroidBackgroundWorkForegroundObserver"))
        XCTAssertTrue(foregroundObserverSource.contains("fun interface AndroidBackgroundWorkObservationRegistration"))
        XCTAssertTrue(foregroundObserverSource.contains("fun observeTaskStatuses("))
        XCTAssertTrue(foregroundObserverSource.contains("scheduler.workInfosForTaskID(taskID)"))
        XCTAssertTrue(foregroundObserverSource.contains("liveData.observeForever(observer)"))
        XCTAssertTrue(foregroundObserverSource.contains("liveData.removeObserver(observer)"))
        XCTAssertTrue(foregroundObserverSource.contains("AndroidBackgroundWorkStatusMapper.from(workInfos.preferredForegroundWorkInfo())"))
        XCTAssertTrue(foregroundObserverSource.contains("firstOrNull { it.state == WorkInfo.State.RUNNING }"))
        XCTAssertTrue(foregroundObserverSource.contains("firstOrNull { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED }"))
        XCTAssertTrue(foregroundObserverSource.contains("firstOrNull { it.state == WorkInfo.State.FAILED || it.state == WorkInfo.State.CANCELLED }"))
        XCTAssertTrue(foregroundObserverSource.contains("firstOrNull { it.state == WorkInfo.State.SUCCEEDED }"))
        XCTAssertFalse(foregroundObserverSource.contains("inputData"))
        XCTAssertFalse(foregroundObserverSource.contains("InputWorkHandleKey"))
        XCTAssertFalse(foregroundObserverSource.contains("InputGenerationIDKey"))
        XCTAssertFalse(foregroundObserverSource.contains("sourceURL"))
        XCTAssertFalse(foregroundObserverSource.contains("sourceUrl"))
        XCTAssertFalse(foregroundObserverSource.contains("Authorization"))
        XCTAssertFalse(foregroundObserverSource.contains("Bearer "))
        XCTAssertFalse(foregroundObserverSource.contains("apiKey"))
        XCTAssertFalse(foregroundObserverSource.contains("secret"))
        XCTAssertTrue(directDownloaderSource.contains("class AndroidDirectMediaBackgroundDownloader"))
        XCTAssertTrue(directDownloaderSource.contains("request.sourceURL.isSafeBackgroundSourceURL()"))
        XCTAssertTrue(directDownloaderSource.contains("instanceFollowRedirects = false"))
        XCTAssertTrue(directDownloaderSource.contains("finalURL.isSafeBackgroundSourceURL()"))
        XCTAssertTrue(directDownloaderSource.contains("AndroidBackgroundDownloadFailure.UnsupportedOnMobile"))
        XCTAssertTrue(directDownloaderSource.contains("AndroidBackgroundDownloadFailure.StorageFull"))
        XCTAssertTrue(directDownloaderSource.contains("AndroidBackgroundDownloadFailure.NetworkUnavailable"))
        XCTAssertTrue(directDownloaderSource.contains("!downloadsDirectory.exists() && !downloadsDirectory.mkdirs()"))
        XCTAssertTrue(directDownloaderSource.contains("import kotlinx.coroutines.ensureActive"))
        XCTAssertTrue(directDownloaderSource.contains("import kotlin.coroutines.coroutineContext"))
        XCTAssertTrue(directDownloaderSource.contains("coroutineContext.ensureActive()"))
        XCTAssertTrue(directDownloaderSource.contains("maxDownloadBytes: Long = 512L * 1024L * 1024L"))
        XCTAssertTrue(directDownloaderSource.contains(".part"))
        XCTAssertTrue(directDownloaderSource.contains(".replace"))
        XCTAssertTrue(directDownloaderSource.contains("storageIdentifier = \"android-owned:$"))
        XCTAssertTrue(directDownloaderSource.contains("{output.name}\""))
        XCTAssertTrue(source.contains("class AndroidBackgroundDownloadHandoffStore"))
        XCTAssertTrue(handoffStoreSource.contains("fun save(descriptor: AndroidBackgroundWorkDescriptor, request: MobileDownloadRequest)"))
        XCTAssertTrue(handoffStoreSource.contains("request.safeForBackgroundHandoff()"))
        XCTAssertTrue(handoffStoreSource.contains("require(sourceURL.isSafeBackgroundSourceURL())"))
        XCTAssertTrue(handoffStoreSource.contains("uri.scheme.equals(\"https\", ignoreCase = true)"))
        XCTAssertTrue(handoffStoreSource.contains("uri.rawUserInfo == null"))
        XCTAssertTrue(handoffStoreSource.contains("uri.rawQuery == null"))
        XCTAssertTrue(handoffStoreSource.contains("uri.rawFragment == null"))
        XCTAssertTrue(handoffStoreSource.contains("path.endsWith(it)"))
        XCTAssertTrue(handoffStoreSource.contains("!lowered.contains(\"token\")"))
        XCTAssertTrue(handoffStoreSource.contains("!lowered.contains(\"signature\")"))
        XCTAssertTrue(handoffStoreSource.contains("!lowered.contains(\"access_key\")"))
        XCTAssertTrue(handoffStoreSource.contains("require(workHandle.isOpaqueWorkHandle())"))
        XCTAssertTrue(handoffStoreSource.contains("File(directory, \"$workHandle.handoff\")"))
        XCTAssertTrue(handoffStoreSource.contains("withHandoffLock(descriptor.workHandle)"))
        XCTAssertTrue(handoffStoreSource.contains("withHandoffLock(workHandle)"))
        XCTAssertTrue(handoffStoreSource.contains("val generationID: String"))
        XCTAssertTrue(handoffStoreSource.contains("\"generationID\" to generationID"))
        XCTAssertTrue(handoffStoreSource.contains("fields[\"generationID\"]?.takeIf { it.isOpaqueWorkGenerationID() }"))
        XCTAssertTrue(handoffStoreSource.contains("fun cancelLatest(workHandle: String)"))
        XCTAssertTrue(handoffStoreSource.contains("fun cancelIfGenerationMatches("))
        XCTAssertTrue(handoffStoreSource.contains("handoff.generationID == generationID"))
        XCTAssertTrue(handoffStoreSource.contains("fun removeIfGenerationMatches("))
        XCTAssertTrue(handoffStoreSource.contains("handoff.workHandle != workHandle || handoff.generationID != generationID"))
        XCTAssertTrue(handoffStoreSource.contains("fun isActiveGeneration("))
        XCTAssertTrue(handoffStoreSource.contains("handoff.workHandle == workHandle &&"))
        XCTAssertTrue(handoffStoreSource.contains("handoff.generationID == generationID &&"))
        XCTAssertTrue(handoffStoreSource.contains("handoff.isActive"))
        XCTAssertTrue(handoffStoreSource.contains("internal fun String.isOpaqueWorkGenerationID()"))
        XCTAssertTrue(handoffStoreSource.contains("File.createTempFile"))
        XCTAssertTrue(handoffStoreSource.contains("Files.move("))
        XCTAssertTrue(handoffStoreSource.contains("StandardCopyOption.ATOMIC_MOVE"))
        XCTAssertTrue(handoffStoreSource.contains("FileChannel.open"))
        XCTAssertTrue(handoffStoreSource.contains("channel.lock().use"))
        XCTAssertTrue(handoffStoreSource.contains("ConcurrentHashMap<Path, Any>"))
        XCTAssertFalse(handoffStoreSource.contains("fileFor(descriptor.workHandle).writeText"))
        XCTAssertTrue(testSource.contains("descriptorForTaskIDDeclaresConservativeWorkManagerContract"))
        XCTAssertTrue(testSource.contains("workRequestInputDataPersistsOnlyOpaqueHandleAndGeneration"))
        XCTAssertTrue(testSource.contains("schedulerUsesOpaqueUniqueWorkNameAndCancellationContract"))
        XCTAssertTrue(testSource.contains("workStatusMapperUsesOnlyWorkerProgressDataAndTerminalStates"))
        XCTAssertTrue(testSource.contains("workStatusProjectionUpdatesOnlyQueueSafeTaskStateAndProgress"))
        XCTAssertTrue(testSource.contains("workStatusProjectionDoesNotPretendSucceededWorkHasRepositoryResult"))
        XCTAssertTrue(testSource.contains("workStatusProjectionSourceDoesNotReadWorkerInputsOrSecrets"))
        XCTAssertTrue(testSource.contains("foregroundObserverSourceMapsOnlyPreferredWorkInfoProgressAndDisposesRegistrations"))
        XCTAssertTrue(testSource.contains("workerDeclaresForegroundNotificationBeforeRuntimeResultMapping"))
        XCTAssertTrue(testSource.contains("workerProgressDataPersistsOnlyNumericProgressFields"))
        XCTAssertTrue(testSource.contains("workerRefreshesForegroundNotificationWithNumericProgressOnly"))
        XCTAssertTrue(testSource.contains("assertFalse(progressBlock.contains(\"sourceURL\"))"))
        XCTAssertTrue(testSource.contains("foregroundNotificationContentIsGenericAndDoesNotExposeWorkInput"))
        XCTAssertTrue(testSource.contains("androidBackgroundDownloadNotificationContent("))
        XCTAssertTrue(testSource.contains("assertFalse(joined.contains(\"https://\"))"))
        XCTAssertTrue(testSource.contains("backgroundHandoffStorePersistsRestorableDirectRequestByOpaqueHandleOnly"))
        XCTAssertTrue(testSource.contains("backgroundHandoffStoreSourceWritesAtomicallyAndLocksByHandle"))
        XCTAssertTrue(testSource.contains("backgroundHandoffStoreRejectsTokenizedOrNonDirectSources"))
        XCTAssertTrue(testSource.contains("https://user:pass@cdn.example.com/video.mp4"))
        XCTAssertTrue(testSource.contains("coordinatorBlocksUnsafeSourcesInsteadOfThrowingWhenRuntimeGatesAreEnabled"))
        XCTAssertTrue(testSource.contains("backgroundDownloadRuntimeSourceWritesProgressResultAndRemovesMatchingHandoffOnSuccess"))
        XCTAssertTrue(testSource.contains("backgroundDownloadRuntimeSourceBlocksMissingHandoffWithoutSavingTask"))
        XCTAssertTrue(testSource.contains("backgroundDownloadRuntimeSourceKeepsRetryingAttemptsNonFinalAndKeepsHandoff"))
        XCTAssertTrue(testSource.contains("runtimeBlocksReplacedGenerationBeforeSavingTask"))
        XCTAssertTrue(testSource.contains("runtimeDoesNotDeleteNewHandoffWhenOldGenerationCompletesAfterReenqueue"))
        XCTAssertTrue(testSource.contains("handoffCancelWritesTombstoneForMatchingGeneration"))
        XCTAssertTrue(testSource.contains("directMediaBackgroundDownloaderSourceIsDirectHttpsOnlyAndAppOwned"))
        XCTAssertTrue(testSource.contains("assertTrue(source.contains(\"coroutineContext.ensureActive()\"))"))
        XCTAssertTrue(testSource.contains("assertTrue(source.contains(\"handoffStore.removeIfGenerationMatches(\"))"))
        XCTAssertTrue(testSource.contains("assertTrue(source.contains(\"handoffStore.cancelIfGenerationMatches(\"))"))
        XCTAssertTrue(testSource.contains("assertFalse(failureBlock.contains(\"handoffStore.remove\"))"))
        XCTAssertTrue(testSource.contains("AndroidDownloadWorker.InputGenerationIDKey"))
        XCTAssertTrue(testSource.contains("assertFalse(input.getString(AndroidDownloadWorker.InputGenerationIDKey).orEmpty().contains(\"task-direct-download\"))"))
        XCTAssertTrue(testSource.contains("assertFalse(input.keyValueMap.containsKey(\"task_id\"))"))
        XCTAssertTrue(testSource.contains("assertFalse(input.keyValueMap.containsKey(\"sourceURL\"))"))
        XCTAssertTrue(testSource.contains("assertFalse(input.keyValueMap.containsKey(\"Authorization\"))"))
        XCTAssertTrue(testSource.contains("assertFalse(descriptor.workHandle.contains(\"task-direct-download\"))"))
        XCTAssertTrue(testSource.contains("assertFalse(descriptor.uniqueWorkName.contains(\"task-direct-download\"))"))
        XCTAssertTrue(testSource.contains("assertTrue(descriptor.requiresForegroundNotification)"))
        XCTAssertTrue(testSource.contains("assertTrue(descriptor.doesNotGuaranteeUnlimitedBackgroundRuntime)"))

        XCTAssertFalse(source.localizedCaseInsensitiveContains("unlimited background"))
        XCTAssertFalse(workerFile.contains("InputTaskIDKey"))
        XCTAssertFalse(source.contains("task-direct-download"))
        XCTAssertFalse(workerFile.contains("sourceURL"))
        XCTAssertFalse(workerFile.contains("sourceUrl"))
        XCTAssertFalse(workerFile.contains("setContentText(inputData"))
        XCTAssertFalse(workerFile.contains("setContentText(\"moongate-work-"))
        XCTAssertFalse(schedulerSource.contains("HttpURLConnection"))
        XCTAssertFalse(schedulerSource.contains("URL("))
        XCTAssertFalse(schedulerSource.contains("enqueue(oneTimeRequest(descriptor))"))
        XCTAssertFalse(schedulerSource.contains("cancelAllWork"))
        XCTAssertFalse(runtimeFile.contains("HttpURLConnection"))
        XCTAssertFalse(runtimeFile.contains("URL("))
        XCTAssertFalse(runtimeFile.contains("WorkManager.getInstance"))
        XCTAssertFalse(runtimeFile.contains("setForeground("))
        XCTAssertFalse(runtimeFile.contains("Authorization"))
        XCTAssertFalse(runtimeFile.contains("Bearer "))
        XCTAssertFalse(runtimeFile.contains("apiKey"))
        XCTAssertFalse(runtimeFile.contains("secret"))
        XCTAssertFalse(directDownloaderSource.contains("Authorization"))
        XCTAssertFalse(directDownloaderSource.contains("Bearer "))
        XCTAssertFalse(directDownloaderSource.contains("apiKey"))
        XCTAssertFalse(directDownloaderSource.contains("secret"))
        XCTAssertFalse(directDownloaderSource.contains("WorkManager.getInstance"))
        XCTAssertFalse(directDownloaderSource.contains("setForeground("))
        XCTAssertFalse(workerFile.contains("JsonTaskRepository"))
        XCTAssertFalse(workerFile.contains("AndroidDirectMediaBackgroundDownloader("))
        XCTAssertFalse(workerFile.contains("File(context.filesDir"))
        XCTAssertFalse(workerFile.contains("Authorization"))
        XCTAssertFalse(workerFile.contains("Bearer "))
        XCTAssertFalse(workerFile.contains("apiKey"))
        XCTAssertFalse(workerFile.contains("secret"))
        XCTAssertTrue(source.contains("class AndroidDownloadCancelReceiver"))
        XCTAssertTrue(source.contains("cancelIfGenerationMatches("))
        XCTAssertTrue(source.contains("WorkManager.getInstance(appContext).cancelWorkById(workID)"))
        XCTAssertFalse(schedulerSource.contains("delete("))
        XCTAssertFalse(schedulerSource.contains("java.io.File"))
    }

    func testAndroidTaskRepositoryDoesNotIntroducePlatformOrNetworkSideEffects() throws {
        let root = packageRoot()
        let sourceDirectory = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("data")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("data")
        let source = try kotlinSourceContents(under: sourceDirectory)

        XCTAssertTrue(source.contains("class JsonTaskRepository"))
        XCTAssertTrue(source.contains("object AndroidTaskRecoveryPolicy"))
        XCTAssertTrue(source.contains("FileChannel.open(lockFile"))
        XCTAssertTrue(source.contains("channel.lock().use"))
        XCTAssertTrue(source.contains("ConcurrentHashMap<Path, Any>"))
        XCTAssertTrue(source.contains("computeIfAbsent(file.toAbsolutePath().normalize())"))
        XCTAssertTrue(source.contains("readTasksUnlocked()"))
        XCTAssertTrue(source.contains("writeUnlocked("))
        XCTAssertTrue(source.contains("existing.mergedWith(sanitizedForPersistence(snapshot))"))
        XCTAssertTrue(source.contains("executionGenerationID != incoming.executionGenerationID -> this"))
        XCTAssertTrue(source.contains("state.isTerminal && !incoming.state.isTerminal"))
        XCTAssertTrue(source.contains("MobileTaskState.COMPLETED || this == MobileTaskState.CANCELLED"))
        XCTAssertFalse(source.contains("WorkManager"))
        XCTAssertFalse(source.contains("ForegroundService"))
        XCTAssertFalse(source.contains("Keystore"))
        XCTAssertFalse(source.contains("HttpURLConnection"))
        XCTAssertFalse(source.contains("URL("))
        XCTAssertFalse(source.contains("Authorization"))
        XCTAssertFalse(source.contains("Bearer "))
        XCTAssertFalse(source.contains("apiKey"))
    }

    func testAndroidTaskRepositoryTestsCoverSharedInstanceLocking() throws {
        let root = packageRoot()
        let testSource = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("data")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("data")
            .appendingPathComponent("repository")
            .appendingPathComponent("JsonTaskRepositoryTest.kt"))

        XCTAssertTrue(testSource.contains("independentInstancesMergeWritesThroughSharedRepositoryLock"))
        XCTAssertTrue(testSource.contains("val appRepository = JsonTaskRepository(file)"))
        XCTAssertTrue(testSource.contains("val workerRepository = JsonTaskRepository(file)"))
        XCTAssertTrue(testSource.contains("appRepository.saveTask(taskSnapshot(\"app-task\""))
        XCTAssertTrue(testSource.contains("workerRepository.saveTask(taskSnapshot(\"worker-task\""))
        XCTAssertTrue(testSource.contains(#"listOf("app-task", "worker-task")"#))
        XCTAssertTrue(testSource.contains("staleAppSnapshotCannotRevertWorkerCompletedTask"))
        XCTAssertTrue(testSource.contains("failedTaskCanStillMoveBackToDownloadingForUserRetry"))
        XCTAssertTrue(testSource.contains("oldWorkerGenerationCannotOverwriteNewerTaskGeneration"))
        XCTAssertTrue(testSource.contains("newerTaskGenerationCanStartAfterOlderTerminalGeneration"))
        XCTAssertTrue(testSource.contains("workerRepository.saveTask(taskSnapshot(\"task-1\", MobileTaskState.COMPLETED))"))
        XCTAssertTrue(testSource.contains("appRepository.saveTask(oldAppSnapshot)"))
        XCTAssertTrue(testSource.contains("assertEquals(MobileTaskState.COMPLETED"))
        XCTAssertTrue(testSource.contains("assertEquals(MobileTaskState.DOWNLOADING"))
    }

    func testAndroidAppPersistsQueueAndUsesGuardedBackgroundCoordinator() throws {
        let root = packageRoot()
        let buildFile = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("build.gradle.kts"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let workerDirectory = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("worker")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("worker")
        let coordinatorSource = try String(contentsOf: workerDirectory
            .appendingPathComponent("AndroidBackgroundWorkCoordinator.kt"))
        let schedulerSource = try String(contentsOf: workerDirectory
            .appendingPathComponent("AndroidBackgroundWorkScheduler.kt"))
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(buildFile.contains(#"implementation(project(":core:data"))"#))
        XCTAssertTrue(buildFile.contains(#"implementation(project(":core:worker"))"#))
        XCTAssertFalse(buildFile.contains("implementation(libs.androidx.work.runtime.ktx)"))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.data.repository.JsonTaskRepository"))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.data.repository.AndroidTaskRecoveryPolicy"))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.worker.AndroidBackgroundWorkCoordinator"))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.worker.AndroidBackgroundWorkHandoff"))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.worker.AndroidBackgroundObservedWorkState"))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.worker.AndroidBackgroundObservedWorkStatus"))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.worker.AndroidBackgroundWorkStatusProjection"))
        XCTAssertTrue(activity.contains("import androidx.compose.runtime.DisposableEffect"))
        XCTAssertTrue(activity.contains("import androidx.compose.runtime.rememberUpdatedState"))
        XCTAssertTrue(activity.contains("import androidx.compose.runtime.mutableIntStateOf"))
        XCTAssertTrue(activity.contains("private var foregroundRefreshRequest by mutableIntStateOf(0)"))
        XCTAssertTrue(activity.contains("override fun onResume()"))
        XCTAssertTrue(activity.contains("foregroundRefreshRequest += 1"))
        XCTAssertTrue(activity.contains("foregroundRefreshRequest = foregroundRefreshRequest"))
        XCTAssertTrue(activity.contains("foregroundRefreshRequest: Int = 0"))
        XCTAssertTrue(activity.contains("val taskRepository = remember { context.androidTaskRepository() }"))
        XCTAssertTrue(activity.contains("val backgroundWorkCoordinator = remember { AndroidBackgroundWorkCoordinator.from(context) }"))
        XCTAssertFalse(activity.contains("notificationFlowAvailable = true"))
        XCTAssertFalse(activity.contains("downloadWorkerRuntimeAvailable = true"))
        XCTAssertTrue(activity.contains("backgroundWorkCoordinator.enqueueDownloadIfReady(item)"))
        XCTAssertTrue(activity.contains("is AndroidBackgroundWorkHandoff.Enqueued ->"))
        XCTAssertTrue(activity.contains("fun persistQueueItem(id: String)"))
        XCTAssertTrue(activity.contains("taskRepository.saveTask(snapshot)"))
        XCTAssertTrue(activity.contains("fun removePersistedTask(id: String)"))
        XCTAssertTrue(activity.contains("taskRepository.removeTask(id)"))
        XCTAssertTrue(activity.contains("AndroidTaskRecoveryPolicy.recoverAll(taskRepository.loadTasks())"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withPersistedTasks(restoredTasks)"))
        XCTAssertTrue(activity.contains("LaunchedEffect(foregroundRefreshRequest, taskRepository)"))
        XCTAssertTrue(activity.contains("refreshPersistedTasks()"))
        XCTAssertTrue(activity.contains("fun applyObservedBackgroundStatus("))
        XCTAssertTrue(activity.contains("if (observed.state == AndroidBackgroundObservedWorkState.SUCCEEDED)"))
        XCTAssertTrue(activity.contains("refreshPersistedTasks()"))
        XCTAssertTrue(activity.contains("AndroidBackgroundWorkStatusProjection.apply(snapshot, observed)"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withProjectedBackgroundTask(projected)"))
        XCTAssertTrue(activity.contains("TaskPersistenceRequest.Save(projected)"))
        XCTAssertTrue(activity.contains("val observedBackgroundTaskIDs = currentAppState.queue"))
        XCTAssertTrue(activity.contains("item.state == AndroidDownloadState.COMPLETED ||"))
        XCTAssertTrue(activity.contains("item.state == AndroidDownloadState.FAILED"))
        XCTAssertTrue(activity.contains("DisposableEffect(backgroundWorkCoordinator, observedBackgroundTaskIDs)"))
        XCTAssertTrue(activity.contains("backgroundWorkCoordinator.observeForegroundWorkStatuses("))
        XCTAssertTrue(activity.contains("registration.cancel()"))
        XCTAssertTrue(activity.contains("currentAppState.persistedTaskForQueueItem(id)"))
        let observedStatusHandler = try sourceSlice(
            in: activity,
            from: "fun applyObservedBackgroundStatus(",
            to: "LaunchedEffect(credentialStore)"
        )
        XCTAssertTrue(observedStatusHandler.contains("observed.state == AndroidBackgroundObservedWorkState.SUCCEEDED"))
        XCTAssertTrue(observedStatusHandler.contains("refreshPersistedTasks()"))
        XCTAssertTrue(observedStatusHandler.contains("return"))
        XCTAssertTrue(observedStatusHandler.contains("AndroidBackgroundWorkStatusProjection.apply(snapshot, observed)"))
        XCTAssertFalse(
            observedStatusHandler.contains("MobileTaskState.COMPLETED"),
            "WorkInfo success must reload the worker-written repository result instead of fabricating completion in the app."
        )
        XCTAssertTrue(activity.contains("private fun Context.androidTaskRepository(): TaskRepository"))
        XCTAssertTrue(activity.contains("JsonTaskRepository(File(File(filesDir, \"tasks\"), \"tasks.json\").toPath())"))
        XCTAssertTrue(activity.contains("rawUri.scheme == \"android-owned\""))
        XCTAssertTrue(activity.contains("File(File(filesDir, \"downloads\"), fileName).canonicalFile"))
        XCTAssertFalse(activity.contains("WorkManager.getInstance"))
        XCTAssertFalse(activity.contains("AndroidBackgroundWorkScheduler"))
        XCTAssertFalse(activity.contains("AndroidDownloadWorker"))
        XCTAssertFalse(activity.contains("androidx.work"))
        XCTAssertFalse(activity.contains("OneTimeWorkRequestBuilder"))
        let refreshPersistedTasks = try sourceSlice(
            in: activity,
            from: "suspend fun refreshPersistedTasks()",
            to: "LaunchedEffect(credentialStore)"
        )
        XCTAssertTrue(refreshPersistedTasks.contains("AndroidTaskRecoveryPolicy.recoverAll(taskRepository.loadTasks())"))
        XCTAssertTrue(refreshPersistedTasks.contains("currentAppState = currentAppState.withPersistedTasks(restoredTasks)"))
        XCTAssertTrue(refreshPersistedTasks.contains("TaskPersistenceRequest.Save(task)"))
        XCTAssertFalse(refreshPersistedTasks.contains("WorkManager"))
        XCTAssertFalse(refreshPersistedTasks.contains("AndroidBackgroundWorkCoordinator"))

        XCTAssertTrue(coordinatorSource.contains("class AndroidBackgroundWorkCoordinator"))
        XCTAssertTrue(coordinatorSource.contains("WorkManager.getInstance(appContext.applicationContext)"))
        XCTAssertTrue(coordinatorSource.contains("workManagerProvider: (Context) -> WorkManager"))
        XCTAssertTrue(coordinatorSource.contains("schedulerProvider = {"))
        XCTAssertTrue(coordinatorSource.contains("notificationFlowAvailable: Boolean = false"))
        XCTAssertTrue(coordinatorSource.contains("downloadWorkerRuntimeAvailable: Boolean = false"))
        XCTAssertTrue(coordinatorSource.contains("fun enqueueDownloadIfReady(item: AndroidDownloadItem): AndroidBackgroundWorkHandoff"))
        XCTAssertTrue(coordinatorSource.contains("fun cancelDownload(taskID: String): AndroidBackgroundWorkDescriptor"))
        XCTAssertTrue(coordinatorSource.contains("schedulerProvider().cancelTaskID(taskID)"))
        XCTAssertTrue(coordinatorSource.contains("fun observeForegroundWorkStatuses("))
        XCTAssertTrue(coordinatorSource.contains("if (taskIDs.isEmpty())"))
        XCTAssertTrue(coordinatorSource.contains("return AndroidNoopBackgroundWorkObservationRegistration"))
        XCTAssertTrue(coordinatorSource.contains("AndroidBackgroundWorkForegroundObserver(schedulerProvider())"))
        XCTAssertTrue(coordinatorSource.contains(".observeTaskStatuses(taskIDs, onStatus)"))
        XCTAssertTrue(coordinatorSource.contains("AndroidBackgroundWorkHandoff.Blocked"))
        XCTAssertTrue(coordinatorSource.contains("AndroidBackgroundWorkScheduler().descriptorForTaskID(item.id)"))
        XCTAssertTrue(coordinatorSource.contains("if (!notificationFlowAvailable)"))
        XCTAssertTrue(coordinatorSource.contains("if (!downloadWorkerRuntimeAvailable)"))
        XCTAssertTrue(coordinatorSource.contains("if (!item.sourceUrlForDownload.isSafeBackgroundSourceURL())"))
        XCTAssertTrue(coordinatorSource.contains("Background download requires a direct HTTPS media URL without credentials, query, or fragment."))
        XCTAssertTrue(coordinatorSource.contains("val scheduler = schedulerProvider()"))
        XCTAssertTrue(coordinatorSource.contains("val request = item.backgroundDownloadRequest()"))
        XCTAssertTrue(coordinatorSource.contains("scheduler.enqueue(request)"))
        XCTAssertTrue(coordinatorSource.contains("AndroidBackgroundDownloadHandoffStore("))
        XCTAssertTrue(coordinatorSource.contains("File(context.noBackupFilesDir, \"background-download-handoffs\")"))
        XCTAssertFalse(coordinatorSource.contains("File(context.filesDir, \"background-download-handoffs\")"))
        XCTAssertTrue(coordinatorSource.contains("private fun AndroidDownloadItem.backgroundDownloadRequest(): MobileDownloadRequest"))
        XCTAssertTrue(schedulerSource.contains("putString(AndroidDownloadWorker.InputWorkHandleKey, descriptor.workHandle)"))
        XCTAssertTrue(schedulerSource.contains("putString(AndroidDownloadWorker.InputGenerationIDKey, descriptor.generationID)"))
        XCTAssertTrue(schedulerSource.contains("private fun String.androidBackgroundWorkGenerationID(): String"))
        XCTAssertTrue(schedulerSource.contains("private fun newAndroidBackgroundWorkGenerationID(): String"))
        XCTAssertTrue(schedulerSource.contains("return \"moongate-generation-$digest\""))
        XCTAssertFalse(schedulerSource.contains("putString(AndroidDownloadWorker.InputTaskIDKey"))
        XCTAssertFalse(schedulerSource.contains("putString(\"task_id\""))
        XCTAssertFalse(schedulerSource.contains("putString(\"source"))
        XCTAssertFalse(schedulerSource.contains("putString(\"url"))
        XCTAssertFalse(schedulerSource.contains("putString(\"contentUri"))
        XCTAssertFalse(coordinatorSource.contains("HttpURLConnection"))
        XCTAssertFalse(schedulerSource.contains("HttpURLConnection"))
        XCTAssertFalse(coordinatorSource.contains("Authorization"))
        XCTAssertFalse(schedulerSource.contains("Authorization"))
        XCTAssertFalse(coordinatorSource.contains("Bearer "))
        XCTAssertFalse(schedulerSource.contains("Bearer "))
        XCTAssertFalse(coordinatorSource.contains("apiKey"))
        XCTAssertFalse(schedulerSource.contains("apiKey"))
        XCTAssertFalse(coordinatorSource.contains("secret"))
        XCTAssertFalse(schedulerSource.contains("secret"))

        XCTAssertTrue(appModels.contains("fun taskSnapshot(): MobileTaskSnapshot"))
        XCTAssertTrue(appModels.contains("fun withPersistedTasks("))
        XCTAssertTrue(appModels.contains("fun withProjectedBackgroundTask(snapshot: MobileTaskSnapshot): AndroidAppState"))
        XCTAssertTrue(appModels.contains("fun persistedTaskForQueueItem(id: String): MobileTaskSnapshot?"))
        XCTAssertTrue(appModels.contains("val executionGenerationID: String? = null"))
        XCTAssertTrue(appModels.contains("executionGenerationID = executionGenerationID"))
        XCTAssertTrue(appModels.contains("val backgroundPolicy: MobileBackgroundPolicy = MobileBackgroundPolicy()"))
        XCTAssertTrue(appModels.contains("backgroundPolicy = task.backgroundPolicy"))
        XCTAssertTrue(appModels.contains("backgroundPolicy = snapshot.backgroundPolicy"))
        XCTAssertTrue(appModels.contains("private val AndroidDownloadItem.effectiveBackgroundPolicy"))
        XCTAssertTrue(appModels.contains("private val MobileTaskSnapshot.androidBackgroundTaskStatus"))
        XCTAssertTrue(appModels.contains("MobileBackgroundExecution.SCHEDULED_WORK"))
        XCTAssertTrue(appModels.contains("AndroidBackgroundTaskStatus.TRANSFER_ALLOWED"))
        XCTAssertTrue(appModels.contains("private val MobileTaskSnapshot.androidObservedBackgroundDetail"))
        XCTAssertTrue(appModels.contains("后台下载已交给系统调度"))
        XCTAssertTrue(appModels.contains("storageIdentifier = completedArtifactStorageIdentifier.sanitizedAndroidArtifactStorageIdentifier(id)"))
        XCTAssertTrue(appModels.contains("val taskResult: MobileTaskResult? = null"))
        XCTAssertTrue(appModels.contains("val result = taskResult?.sanitizedForAndroidTaskSnapshot(id)"))
        XCTAssertTrue(appModels.contains("private fun MobileTaskResult.sanitizedForAndroidTaskSnapshot(taskID: String): MobileTaskResult"))
        XCTAssertTrue(appModels.contains("private fun String.sanitizedAndroidArtifactStorageIdentifier(taskID: String): String"))
        XCTAssertTrue(appModels.contains(#"else -> "android-sanitized:${taskID.hashCode().toUInt()}""#))
        XCTAssertFalse(appModels.contains(#"else -> "android-sanitized:$taskID""#))
        XCTAssertTrue(appModels.contains("?: if (completedArtifactStorageIdentifier != null)"))
        XCTAssertTrue(appModels.contains("taskResult = task.result"))
        XCTAssertTrue(appModels.contains("completedArtifactStorageIdentifier != null"))
        XCTAssertFalse(appModels.contains(#"?: "android-owned:${appOwnedDownloadFileName()}""#))
        XCTAssertTrue(appModels.contains("fun AndroidDownloadItem.appOwnedDownloadFileName(): String"))
        XCTAssertTrue(appModels.contains("val sourceUrlForDownload: String = \"\""))
        XCTAssertTrue(appStateTests.contains("completedForegroundDownloadCanPersistAndRestoreQueueAndLibraryRecords"))
        XCTAssertTrue(appStateTests.contains("restoredQueuedDirectDownloadDoesNotPretendSourceUrlSurvivedRelaunch"))
        XCTAssertTrue(appStateTests.contains("projectedBackgroundWorkStatusUpdatesExistingQueueItemWithoutLosingGenerationOrSource"))
        XCTAssertTrue(appStateTests.contains("recoveredLibraryContentUriPersistsAsSanitizedContentReference"))
        XCTAssertTrue(appStateTests.contains("recoveredLibraryContentUriWithQueryDoesNotPersistSecretReference"))
        XCTAssertTrue(appStateTests.contains("assertFalse(encoded.contains(\"https://cdn.example.com/video.mp4\"))"))
        XCTAssertTrue(appStateTests.contains("assertFalse(restoredItem.primaryAction.isEnabled)"))
    }

    func testAndroidPersistenceWritesAreSerializedThroughSingleRequestQueue() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("private sealed interface TaskPersistenceRequest"))
        XCTAssertTrue(activity.contains("Channel<TaskPersistenceRequest>(Channel.UNLIMITED)"))
        XCTAssertTrue(activity.contains("for (request in taskPersistenceRequests)"))
        XCTAssertTrue(activity.contains("TaskPersistenceRequest.Save"))
        XCTAssertTrue(activity.contains("TaskPersistenceRequest.Remove"))
        XCTAssertFalse(
            activity.contains("coroutineScope.launch(Dispatchers.IO) {\n            taskRepository.saveTask(snapshot)"),
            "Task persistence saves must flow through the serialized request queue."
        )
        XCTAssertFalse(
            activity.contains("coroutineScope.launch(Dispatchers.IO) {\n            taskRepository.removeTask(id)"),
            "Task persistence deletes must flow through the serialized request queue."
        )
    }

    func testAndroidCompletedTaskDeletionKeepsQueueLibraryAndPersistenceConsistent() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains(#"library = library.filterNot { it.id == "library-$id" }"#))
        XCTAssertTrue(appModels.contains(#"val taskID = id.removePrefix("library-")"#))
        XCTAssertTrue(appModels.contains("queue = queue.filterNot { it.id == taskID }"))
        XCTAssertTrue(appModels.contains("availability = if (storageUri != null)"))

        XCTAssertTrue(appStateTests.contains("deletingCompletedQueueItemAlsoRemovesLibraryProjection"))
        XCTAssertTrue(appStateTests.contains("deletingCompletedLibraryItemAlsoRemovesQueueProjection"))
        XCTAssertTrue(appStateTests.contains("restoredImportedTaskDoesNotClaimAvailableFileWithoutPersistedUri"))
    }

    func testAndroidTaskRepositorySanitizesLegacySourceURLArtifactsBeforePersistence() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("data")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("data")
            .appendingPathComponent("repository")
            .appendingPathComponent("JsonTaskRepository.kt"))

        XCTAssertTrue(source.contains("private fun sanitizedForPersistence"))
        XCTAssertTrue(source.contains("\"mobile-source:${snapshot.id}\""))
        XCTAssertFalse(
            source.contains("artifact.kind == MobileArtifactKind.METADATA"),
            "All legacy source: artifact identifiers must be sanitized, not only metadata artifacts."
        )
        XCTAssertFalse(
            source.contains("+ snapshot\n        write"),
            "JsonTaskRepository must not append unsanitized snapshots directly before writing JSON."
        )

        let testSource = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("data")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("data")
            .appendingPathComponent("repository")
            .appendingPathComponent("JsonTaskRepositoryTest.kt"))

        XCTAssertTrue(testSource.contains("MobileArtifactKind.ORIGINAL_MEDIA"))
        XCTAssertTrue(testSource.contains("MobileArtifactKind.TRANSCRIPT"))
        XCTAssertTrue(testSource.contains("source:$signedURL"))
        XCTAssertTrue(testSource.contains("assertFalse(stored.contains(\"source:https://\"))"))
    }

    func testAndroidCredentialStoreInterfaceCanSaveSecretWithoutPersistingItInTaskRepository() throws {
        let root = packageRoot()
        let services = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("MobileServices.kt"))

        XCTAssertTrue(services.contains("suspend fun saveCredential(secret: String, reference: SecureCredentialReference)"))
        XCTAssertTrue(services.contains("suspend fun credential(reference: SecureCredentialReference): String?"))
        XCTAssertFalse(services.contains("saveCredentialReference"))
    }

    func testAndroidAppProvidesKeystoreBackedCredentialStoreAdapter() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("AndroidKeystoreCredentialStore.kt"))

        XCTAssertTrue(source.contains("class AndroidKeystoreCredentialStore"))
        XCTAssertTrue(source.contains(": SecureCredentialStore"))
        XCTAssertTrue(source.contains("AndroidKeyStore"))
        XCTAssertTrue(source.contains("KeyGenParameterSpec"))
        XCTAssertTrue(source.contains("KeyProperties"))
        XCTAssertTrue(source.contains("Cipher.getInstance(\"AES/GCM/NoPadding\")"))
        XCTAssertTrue(source.contains("Context.MODE_PRIVATE"))
        XCTAssertTrue(source.contains("MessageDigest.getInstance(\"SHA-256\")"))
    }

    func testAndroidCredentialStorePersistsOnlyEncryptedBlobsAndDoesNotLogSecrets() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("AndroidKeystoreCredentialStore.kt"))
        let putStringLines = source
            .components(separatedBy: .newlines)
            .filter { $0.contains("putString") }

        XCTAssertTrue(source.contains("cipher.doFinal(secret.toByteArray(Charsets.UTF_8))"))
        XCTAssertTrue(putStringLines.contains { $0.contains("ciphertextKey(reference)") })
        XCTAssertTrue(putStringLines.contains { $0.contains("ivKey(reference)") })
        XCTAssertFalse(putStringLines.contains { $0.contains("secret") })
        XCTAssertFalse(source.contains("Log."))
        XCTAssertFalse(source.contains("println("))
        XCTAssertFalse(source.contains("apiKeySecret"))
        XCTAssertFalse(source.contains("apiKeyValue"))
    }

    func testAndroidSettingsStateTracksCredentialReferenceWithoutSecretValue() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(appModels.contains("val apiKeyReference: SecureCredentialReference? = null"))
        XCTAssertTrue(appModels.contains("val hasConfiguredAPIKey: Boolean"))
        XCTAssertTrue(appModels.contains("data class AndroidCloudTranslationReadiness"))
        XCTAssertTrue(appModels.contains("val cloudTranslationReadiness: AndroidCloudTranslationReadiness"))
        XCTAssertTrue(appModels.contains("val cloudTranslationAction: AndroidActionState"))
        XCTAssertTrue(appModels.contains("fun withCredentialReference(reference: SecureCredentialReference?)"))
        XCTAssertTrue(appModels.contains("val mobileConfiguration: MobileTranslationConfiguration"))
        XCTAssertTrue(appModels.contains("fun live(apiKeyReference: SecureCredentialReference? = null)"))
        XCTAssertTrue(appModels.contains("fun withAPIKeyReference(reference: SecureCredentialReference): AndroidAppState"))
        XCTAssertTrue(activity.contains("appState.settings.apiKeyStatusText"))
        XCTAssertTrue(activity.contains("SectionCard(title = \"云端翻译\")"))
        XCTAssertTrue(activity.contains("appState.settings.cloudTranslationDetailText"))
        XCTAssertTrue(activity.contains("appState.settings.cloudTranslationStatusText"))
        XCTAssertTrue(activity.contains("ActionStatusChip(appState.settings.cloudTranslationAction)"))
        XCTAssertFalse(appModels.contains("apiKeySecret"))
        XCTAssertFalse(appModels.contains("apiKeyValue"))
        XCTAssertFalse(activity.contains("rememberSaveable { mutableStateOf(\"\") }"))
        XCTAssertTrue(activity.contains("PasswordVisualTransformation()"))
        XCTAssertTrue(activity.contains("KeyboardOptions(keyboardType = KeyboardType.Password)"))
    }

    func testAndroidSettingsSavesAPIKeyThroughKeystoreWithoutSaveableSecretState() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("remember { AndroidKeystoreCredentialStore("))
        XCTAssertTrue(activity.contains("var apiKeyDraft by remember { mutableStateOf(\"\") }"))
        XCTAssertFalse(activity.contains("var apiKeyDraft by rememberSaveable"))
        XCTAssertTrue(activity.contains("credentialStore.saveCredential(secret, reference)"))
        XCTAssertTrue(activity.contains("SecureCredentialReference("))
        XCTAssertTrue(activity.contains("onAPIKeyReferenceChanged(savedReference)"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withAPIKeyReference(reference)"))
        XCTAssertFalse(activity.contains("currentAppState = AndroidAppState.live(apiKeyReference = reference)"))
        XCTAssertTrue(activity.contains("apiKeyDraft = \"\""))
        XCTAssertTrue(activity.contains("enabled = apiKeyDraft.trim().isNotEmpty()"))
        XCTAssertFalse(activity.contains("Log."))
        XCTAssertFalse(activity.contains("println("))
    }

    func testAndroidSettingsDeletesAPIKeyThroughKeystoreWithoutDroppingAppState() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(appModels.contains("fun withoutAPIKeyReference(): AndroidAppState"))
        XCTAssertTrue(activity.contains("onAPIKeyReferenceCleared = {"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withoutAPIKeyReference()"))
        XCTAssertFalse(activity.contains("currentAppState = AndroidAppState.live(apiKeyReference = null)"))

        let settingsScreen = try sourceSlice(
            in: activity,
            from: "private fun SettingsScreen(",
            to: "SectionCard(title = \"本机翻译\")"
        )
        XCTAssertTrue(settingsScreen.contains("onAPIKeyReferenceCleared: () -> Unit"))
        XCTAssertTrue(settingsScreen.contains("val reference = appState.settings.apiKeyReference"))
        XCTAssertTrue(settingsScreen.contains("credentialStore.deleteCredential(reference)"))
        XCTAssertTrue(settingsScreen.contains("onAPIKeyReferenceCleared()"))
        XCTAssertTrue(settingsScreen.contains("apiKeyDraft = \"\""))
        XCTAssertTrue(settingsScreen.contains("apiKeySaveStatus = \"已移除。\""))
        XCTAssertTrue(settingsScreen.contains("enabled = appState.settings.hasConfiguredAPIKey"))
        XCTAssertTrue(settingsScreen.contains("Icons.Outlined.Delete"))
        XCTAssertFalse(settingsScreen.contains("rememberSaveable"))
        XCTAssertFalse(settingsScreen.contains("credentialStore.saveCredential(\"\")"))
    }

    func testAndroidLiveShellUsesDomainActionStateInsteadOfClickOnlyUnsupportedCopy() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(appModels.contains("data class AndroidActionState"))
        XCTAssertTrue(appModels.contains("val isEnabled: Boolean"))
        XCTAssertTrue(appModels.contains("primaryAction = AndroidActionState"))
        XCTAssertTrue(appModels.contains("val primaryAction: AndroidActionState"))
        XCTAssertTrue(appModels.contains("val secondaryActions: List<AndroidActionState>"))
        XCTAssertTrue(appModels.contains("val backgroundCapabilities: List<AndroidBackgroundCapabilityItem>"))
        XCTAssertTrue(appModels.contains("val notificationPermissionAction: AndroidActionState"))
        XCTAssertTrue(appModels.contains("AndroidNotificationPermissionState.UNKNOWN"))
        XCTAssertTrue(appModels.contains("AndroidNotificationPermissionState.GRANTED"))
        XCTAssertTrue(appModels.contains("AndroidNotificationPermissionState.DENIED"))
        XCTAssertTrue(appModels.contains("AndroidNotificationPermissionState.NOT_REQUIRED"))

        XCTAssertTrue(activity.contains("PrimaryActionButton("))
        XCTAssertTrue(activity.contains("appState.addUrlState.primaryAction"))
        XCTAssertTrue(activity.contains("appState.addUrlState.primaryAction.helperText"))
        XCTAssertTrue(activity.contains("appState.fileImportState.primaryAction"))
        XCTAssertTrue(activity.contains("action = item.primaryAction"))
        XCTAssertTrue(activity.contains("SecondaryActionRow("))
        XCTAssertTrue(activity.contains("actions = item.secondaryActions"))
        XCTAssertTrue(activity.contains("ActionStatusChip(appState.settings.apiKeyAction)"))
        XCTAssertTrue(activity.contains("SectionCard(title = \"云端翻译\")"))
        XCTAssertTrue(activity.contains("StatusPill(text = appState.settings.cloudTranslationStatusText)"))
        XCTAssertTrue(activity.contains("ActionStatusChip(appState.settings.cloudTranslationAction)"))
        XCTAssertTrue(activity.contains("SectionCard(title = \"本机翻译\")"))
        XCTAssertTrue(activity.contains("StatusPill(text = localModelStatusLabel(model))"))
        XCTAssertFalse(activity.contains("action = appState.settings.localModelPrimaryAction"))
        XCTAssertFalse(activity.contains("appState.settings.localModelSecondaryAction?.let"))
        XCTAssertTrue(activity.contains("appState.settings.backgroundCapabilities.forEach"))
        XCTAssertTrue(activity.contains("appState.settings.notificationPermissionAction"))
        XCTAssertTrue(activity.contains("ActivityResultContracts.RequestPermission()"))
        XCTAssertTrue(activity.contains("notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)"))
        XCTAssertTrue(activity.contains("ContextCompat.checkSelfPermission("))
        XCTAssertTrue(activity.contains("PackageManager.PERMISSION_GRANTED"))
        XCTAssertTrue(activity.contains("Settings.ACTION_APP_NOTIFICATION_SETTINGS"))
        XCTAssertTrue(activity.contains("Settings.EXTRA_APP_PACKAGE"))
        XCTAssertTrue(activity.contains("context.openAppNotificationSettings()"))
        XCTAssertTrue(activity.contains("context.androidNotificationPermissionState()"))
        XCTAssertTrue(activity.contains("currentAppState.withAndroidNotificationPermission("))
        XCTAssertTrue(activity.contains("onAddClick = { selectedSurface = AndroidSurface.ADD }"))
        XCTAssertTrue(activity.contains("Button(onClick = { onActionClick?.invoke() })"))
        XCTAssertFalse(activity.contains("notificationFlowAvailable = true"))
        XCTAssertFalse(activity.contains("downloadWorkerRuntimeAvailable = true"))
        XCTAssertFalse(activity.contains("当前版本暂不支持"))
        XCTAssertFalse(activity.contains("mock 产物"))
        XCTAssertFalse(activity.contains("此版本暂不支持保存密钥"))
        XCTAssertFalse(appModels.contains("mock only"))
        XCTAssertFalse(appModels.contains("yt-dlp 未接入"))
        XCTAssertFalse(appModels.contains("ffmpeg 未接入"))
        XCTAssertFalse(appModels.contains("adapter、"))
        XCTAssertFalse(appModels.contains("adapter。"))
        XCTAssertFalse(appModels.contains("adapter，"))
        for term in ["任务服务", "运行时验证", "适配器接入", "接入后执行"] {
            XCTAssertFalse(appModels.contains(term), "\(term) should not appear in Android production copy.")
        }
    }

    func testAndroidAddUrlPlannerStagesDirectHTTPSMediaURLWithoutNetworkOrCredentials() throws {
        let root = packageRoot()
        let appModelsURL = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt")
        let appModels = try String(contentsOf: appModelsURL)

        XCTAssertTrue(appModels.contains("sealed class AndroidAddUrlPlanResult"))
        XCTAssertTrue(appModels.contains("data class Staged"))
        XCTAssertTrue(appModels.contains("data class Rejected"))
        XCTAssertTrue(appModels.contains("object AndroidAddUrlPlanner"))
        XCTAssertTrue(appModels.contains("fun stageDirectUrl("))
        XCTAssertTrue(appModels.contains("input: String"))
        XCTAssertTrue(appModels.contains("val trimmed = input.trim()"))
        XCTAssertTrue(appModels.contains("import java.net.URI"))
        XCTAssertTrue(appModels.contains("val uri = runCatching { URI(trimmed) }.getOrNull()"))
        XCTAssertTrue(appModels.contains("uri.scheme?.equals(\"https\", ignoreCase = true) != true"))
        XCTAssertTrue(appModels.contains("uri.host.isNullOrBlank()"))
        XCTAssertTrue(appModels.contains("if (uri.rawUserInfo != null)"))
        XCTAssertTrue(appModels.contains("fun withStagedDirectUrl(input: String): AndroidAppState"))
        XCTAssertTrue(appModels.contains("AndroidAddUrlPlanner.stageDirectUrl(input)"))

        let addUrlPlanner = try sourceSlice(
            in: appModels,
            from: "object AndroidAddUrlPlanner",
            to: "@Serializable\ndata class AndroidAppState"
        )
        let addUrlStateMutation = try sourceSlice(
            in: appModels,
            from: "fun withStagedDirectUrl(input: String): AndroidAppState",
            to: "fun withImportedFile(file: AndroidImportedFile"
        )
        let addUrlBoundary = addUrlPlanner + "\n" + addUrlStateMutation

        XCTAssertTrue(addUrlPlanner.contains("val readyState: AndroidAddReadyState"))
        XCTAssertTrue(addUrlPlanner.contains("if (uri.rawQuery != null || uri.rawFragment != null)"))
        XCTAssertTrue(addUrlPlanner.contains("带参数"))
        XCTAssertTrue(addUrlPlanner.contains("MobileVideoInfo("))
        XCTAssertTrue(addUrlPlanner.contains("MobileFormatChoice("))
        XCTAssertTrue(addUrlPlanner.contains("selectedFormatID ="))
        XCTAssertFalse(
            addUrlPlanner.contains("MobileSubtitleChoice("),
            "Direct media links should not expose fabricated subtitle options before a parser/sidecar subtitle adapter exists."
        )
        XCTAssertFalse(addUrlPlanner.contains("val queueItem = AndroidDownloadItem("))
        XCTAssertTrue(addUrlStateMutation.contains("selectedSurface = AndroidSurface.ADD"))
        XCTAssertTrue(addUrlStateMutation.contains("addReadyState = result.readyState"))
        XCTAssertFalse(addUrlStateMutation.contains("queue = queue + result.queueItem"))

        XCTAssertFalse(addUrlBoundary.contains("HttpURLConnection"))
        XCTAssertFalse(addUrlBoundary.contains("URL("))
        XCTAssertFalse(addUrlBoundary.contains("WorkManager"))
        XCTAssertFalse(addUrlBoundary.contains("Authorization"))
        XCTAssertFalse(addUrlBoundary.contains("Bearer "))
        XCTAssertFalse(addUrlBoundary.contains("apiKey"))
        XCTAssertFalse(addUrlBoundary.contains("secret"))
        XCTAssertFalse(addUrlBoundary.contains("token"))
    }

    func testAndroidDirectUrlTaskIDIsOpaqueBeforeWorkManagerHandoff() throws {
        let root = packageRoot()
        let appModelsURL = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt")
        let appStateTestsURL = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt")
        let appModels = try String(contentsOf: appModelsURL)
        let appStateTests = try String(contentsOf: appStateTestsURL)
        let addUrlPlanner = try sourceSlice(
            in: appModels,
            from: "object AndroidAddUrlPlanner",
            to: "@Serializable\ndata class AndroidAppState"
        )
        let readyState = try sourceSlice(
            in: appModels,
            from: "@Serializable\ndata class AndroidAddReadyState",
            to: "companion object {"
        )

        XCTAssertTrue(addUrlPlanner.contains("idFactory: AndroidOpaqueIDFactory"))
        XCTAssertTrue(appModels.contains("object AndroidOpaqueID"))
        XCTAssertTrue(readyState.contains("downloadTaskID: String"))
        XCTAssertTrue(readyState.contains("id = downloadTaskID"))
        XCTAssertFalse(
            addUrlPlanner.contains("hashCode()"),
            "Direct URL candidate, session, video, and download task IDs must not be derived from the URL hash."
        )
        XCTAssertFalse(
            readyState.contains(#"id = "download-$sessionID""#),
            "Queued Android direct URL task IDs are passed to WorkManager and must be independently opaque."
        )
        XCTAssertTrue(appStateTests.contains("directUrlTaskIDIsOpaqueAndNotURLHashDerived"))
    }

    func testAndroidStagedReadyStateRemainsInMemoryAndOutOfPersistence() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let repository = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("data")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("data")
            .appendingPathComponent("repository")
            .appendingPathComponent("JsonTaskRepository.kt"))
        let workerDirectory = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("worker")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("worker")
        let workerSource = try kotlinSourceContents(under: workerDirectory)
        let addScreen = try sourceSlice(
            in: activity,
            from: "private fun AddScreen(",
            to: "@Composable\nprivate fun ReadyVideoCard("
        )

        XCTAssertTrue(addScreen.contains("val readyState = appState.addReadyState"))
        XCTAssertTrue(addScreen.contains("val currentReadyState = readyState?.copy("))
        XCTAssertTrue(addScreen.contains("onEnqueueClick?.invoke(ready.downloadRequest)"))
        XCTAssertTrue(addScreen.contains("rememberSaveable(readyState?.sessionID)"))
        XCTAssertTrue(addScreen.contains("readyState?.selectedManualSubtitleIDs"))
        XCTAssertTrue(addScreen.contains("readyState?.selectedAutoSubtitleIDs"))
        XCTAssertFalse(
            addScreen.contains("rememberSaveable { mutableStateOf(appState.addReadyState"),
            "The staged ready state may contain a raw direct URL and must not be saved across process recreation."
        )
        XCTAssertFalse(addScreen.contains("rememberSaveable { mutableStateOf(readyState"))
        XCTAssertFalse(addScreen.contains("rememberSaveable(readyState)"))
        XCTAssertFalse(addScreen.contains("mutableStateOf(readyState)"))

        XCTAssertTrue(repository.contains("import com.moongate.mobile.domain.MobileTaskSnapshot"))
        XCTAssertTrue(repository.contains("override suspend fun saveTask(snapshot: MobileTaskSnapshot)"))
        XCTAssertTrue(repository.contains("json.encodeToString(tasks)"))
        XCTAssertFalse(repository.contains("AndroidAppState"))
        XCTAssertFalse(repository.contains("AndroidAddReadyState"))
        XCTAssertFalse(repository.contains("MobileVideoCandidate"))

        let workerSchedulerSource = try String(contentsOf: workerDirectory
            .appendingPathComponent("AndroidBackgroundWorkScheduler.kt"))
        let workerDownloadSource = try String(contentsOf: workerDirectory
            .appendingPathComponent("AndroidDownloadWorker.kt"))
        XCTAssertFalse(workerSource.contains("AndroidAddReadyState"))
        XCTAssertFalse(workerSource.contains("MobileVideoCandidate"))
        XCTAssertFalse(workerSchedulerSource.contains("sourceURL"))
        XCTAssertFalse(workerDownloadSource.contains("sourceURL"))
    }

    func testAndroidLiveAddDoesNotFabricateReadyMediaForGenericWebPages() throws {
        let root = packageRoot()
        let appModelsURL = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt")
        let appModels = try String(contentsOf: appModelsURL)
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        let addUrlPlanner = try sourceSlice(
            in: appModels,
            from: "object AndroidAddUrlPlanner",
            to: "@Serializable\ndata class AndroidAppState"
        )
        let supportedExtensions = try sourceSlice(
            in: addUrlPlanner,
            from: "private val supportedDirectMediaExtensions = setOf(",
            to: ")"
        )
        let addUrlStateMutation = try sourceSlice(
            in: appModels,
            from: "fun withStagedDirectUrl(input: String): AndroidAppState",
            to: "fun withImportedFile(file: AndroidImportedFile"
        )

        XCTAssertTrue(addUrlPlanner.contains("private val supportedDirectMediaExtensions"))
        XCTAssertTrue(supportedExtensions.contains("\"mp4\""))
        XCTAssertTrue(supportedExtensions.contains("\"mov\""))
        XCTAssertTrue(supportedExtensions.contains("\"m4v\""))
        XCTAssertTrue(supportedExtensions.contains("\"webm\""))
        XCTAssertFalse(supportedExtensions.contains("\"mkv\""))
        XCTAssertFalse(supportedExtensions.contains("\"mp3\""))
        XCTAssertFalse(supportedExtensions.contains("\"m4a\""))
        XCTAssertFalse(supportedExtensions.contains("\"aac\""))
        XCTAssertFalse(supportedExtensions.contains("\"wav\""))
        XCTAssertTrue(addUrlPlanner.contains("isSupportedDirectMediaPath(uri.path)"))
        XCTAssertTrue(addUrlPlanner.contains("URI(trimmed)"))
        XCTAssertTrue(addUrlPlanner.contains("if (uri.rawUserInfo != null)"))
        XCTAssertTrue(addUrlPlanner.contains("MobileUnsupportedReason.REQUIRES_DESKTOP_EXTRACTOR"))
        XCTAssertTrue(addUrlPlanner.contains("WEB_PAGE_VIDEO"))
        XCTAssertTrue(addUrlPlanner.contains("直接视频文件链接"))
        XCTAssertTrue(addUrlPlanner.contains(".mp4、.mov、.m4v 或 .webm"))
        XCTAssertFalse(
            addUrlPlanner.contains("MobileSubtitleChoice("),
            "The Android live URL planner must not fabricate subtitle choices for a direct media URL."
        )
        XCTAssertTrue(appStateTests.contains("genericWebUrlIsRejectedInsteadOfFabricatingReadyMedia"))
        XCTAssertTrue(appStateTests.contains("genericWebUrlClearsPreviouslyStagedReadyMedia"))
        XCTAssertTrue(appStateTests.contains("uppercaseHttpsDirectMediaUrlStagesBeforeQueueing"))
        XCTAssertTrue(appStateTests.contains("audioDirectMediaUrlIsRejectedBeforeQueueing"))
        XCTAssertTrue(appStateTests.contains("signedDirectMediaUrlIsRejectedBeforeQueueing"))
        XCTAssertTrue(appStateTests.contains("credentialedDirectMediaUrlIsRejectedBeforeQueueing"))
        XCTAssertTrue(appStateTests.contains("assertEquals(null, rejected.addReadyState)"))
        XCTAssertTrue(appStateTests.contains("assertTrue(rejected.addUrlState.errorMessage?.contains(\"直接视频文件链接\") == true)"))
        XCTAssertTrue(appStateTests.contains("assertTrue(staged.addReadyState?.manualSubtitles?.isEmpty() == true)"))
        XCTAssertTrue(appStateTests.contains("assertTrue(staged.addReadyState?.autoSubtitles?.isEmpty() == true)"))
        XCTAssertTrue(
            addUrlStateMutation.contains("addReadyState = null"),
            "Rejecting a generic web URL must clear any previously staged ready media."
        )
    }

    func testAndroidAddDomainExposesFullMaterialAddStateMachine() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let mobileMediaModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("MobileMediaModels.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))
        let appStateDeclaration = try sourceSlice(
            in: appModels,
            from: "@Serializable\ndata class AndroidAppState",
            to: "fun withQueuedDownloadRequest"
        )
        let addUrlStateMutation = try sourceSlice(
            in: appModels,
            from: "fun withStagedDirectUrl(input: String): AndroidAppState",
            to: "fun withImportedSubtitle(file: AndroidImportedFile"
        )

        XCTAssertTrue(mobileMediaModels.contains("enum class MobileAddSessionState"))
        XCTAssertTrue(appStateDeclaration.contains("val addSessionState: MobileAddSessionState = MobileAddSessionState.IDLE"))
        XCTAssertTrue(appStateDeclaration.contains("val addCandidates: List<MobileVideoCandidate> = emptyList()"))
        XCTAssertTrue(appStateDeclaration.contains("val selectedAddCandidateID: String? = null"))
        XCTAssertTrue(addUrlStateMutation.contains("addSessionState = MobileAddSessionState.READY"))
        XCTAssertTrue(addUrlStateMutation.contains("addSessionState = result.sessionState"))
        XCTAssertTrue(addUrlStateMutation.contains("addCandidates = listOf(result.readyState.videoInfo.candidate)"))
        XCTAssertTrue(addUrlStateMutation.contains("addCandidates = result.candidates"))
        XCTAssertTrue(appModels.contains("fun withCandidateSelection("))
        XCTAssertTrue(appModels.contains("fun withSelectedAddCandidate(candidateID: String): AndroidAppState"))
        XCTAssertTrue(appModels.contains("candidate.isSupportedOnMobile"))
        XCTAssertTrue(appModels.contains("val sessionState: MobileAddSessionState"))
        XCTAssertTrue(appModels.contains("val candidates: List<MobileVideoCandidate> = emptyList()"))
        XCTAssertTrue(appModels.contains("MobileAddSessionState.UNSUPPORTED"))
        XCTAssertTrue(appModels.contains("MobileAddSessionState.FAILED"))

        XCTAssertTrue(appStateTests.contains("liveAddSessionStateStartsIdleAndCoversMaterialStates"))
        XCTAssertTrue(appStateTests.contains("candidateSelectionOnlySelectsSupportedMobileCandidates"))
        XCTAssertTrue(appStateTests.contains("assertEquals(MobileAddSessionState.IDLE, state.addSessionState)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(MobileAddSessionState.READY, staged.addSessionState)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(MobileAddSessionState.UNSUPPORTED, rejected.addSessionState)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(MobileAddSessionState.FAILED, failed.addSessionState)"))
    }

    func testAndroidAddScreenRendersFullMaterialAddStateMachine() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let addScreen = try sourceSlice(
            in: activity,
            from: "private fun AddScreen(",
            to: "@Composable\nprivate fun QueueScreen("
        )
        let addStateCard = try sourceSlice(
            in: activity,
            from: "private fun AndroidAddSessionStateCard(",
            to: "@Composable\nprivate fun AddStateCard("
        )
        let candidateList = try sourceSlice(
            in: activity,
            from: "private fun AndroidCandidateSelectionCard(",
            to: "@Composable\nprivate fun AndroidCandidateRow("
        )
        let candidateRow = try sourceSlice(
            in: activity,
            from: "private fun AndroidCandidateRow(",
            to: "@Composable\nprivate fun AddStateCard("
        )

        XCTAssertTrue(addScreen.contains("AndroidAddSessionStateCard("))
        XCTAssertTrue(addScreen.contains("sessionState = appState.addSessionState"))
        XCTAssertTrue(addScreen.contains("candidates = appState.addCandidates"))
        XCTAssertTrue(addScreen.contains("selectedCandidateID = appState.selectedAddCandidateID"))
        XCTAssertTrue(addScreen.contains("errorMessage = appState.addUrlState.errorMessage"))
        XCTAssertTrue(addScreen.contains("hasReadyState = currentReadyState != null"))
        XCTAssertTrue(addScreen.contains("AndroidCandidateSelectionCard("))
        XCTAssertTrue(addStateCard.contains("MobileAddSessionState.ANALYZING"))
        XCTAssertTrue(addStateCard.contains("MobileAddSessionState.CANDIDATE_SELECTION"))
        XCTAssertTrue(addStateCard.contains("MobileAddSessionState.UNSUPPORTED"))
        XCTAssertTrue(addStateCard.contains("MobileAddSessionState.FAILED"))
        XCTAssertTrue(addStateCard.contains("当前链接暂不支持"))
        XCTAssertTrue(addStateCard.contains("检查失败"))
        XCTAssertTrue(addStateCard.contains("正在检查链接"))
        XCTAssertTrue(addStateCard.contains("选择视频"))
        XCTAssertTrue(addStateCard.contains("isError = true"))
        XCTAssertTrue(activity.contains("private fun AddStateCard("))
        XCTAssertTrue(activity.contains("MaterialTheme.colorScheme.errorContainer"))
        XCTAssertTrue(activity.contains("MaterialTheme.colorScheme.secondaryContainer"))
        XCTAssertTrue(candidateList.contains("candidates: List<MobileVideoCandidate>"))
        XCTAssertTrue(candidateList.contains("AndroidCandidateRow("))
        XCTAssertTrue(candidateList.contains("isSelected = selectedCandidateID == candidate.id"))
        XCTAssertTrue(candidateRow.contains("candidate.isSupportedOnMobile"))
        XCTAssertTrue(candidateRow.contains("if (isSupported)"))
        XCTAssertTrue(candidateRow.contains("Button("))
        XCTAssertTrue(candidateRow.contains("candidateUnsupportedReasonLabel(candidate.unsupportedReason)"))
        XCTAssertTrue(candidateRow.contains("StatusPill(text = reasonLabel)"))
        XCTAssertTrue(activity.contains("private fun candidateUnsupportedReasonLabel("))
        XCTAssertFalse(candidateList.contains("HttpURLConnection"))
        XCTAssertFalse(candidateRow.contains("HttpURLConnection"))
        XCTAssertFalse(candidateList.contains("Authorization"))
        XCTAssertFalse(candidateRow.contains("Authorization"))
        XCTAssertFalse(candidateList.contains("Bearer "))
        XCTAssertFalse(candidateRow.contains("Bearer "))
    }

    func testAndroidAddUrlButtonStagesReadyStateBeforeQueueingSelection() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withStagedDirectUrl(url)"))
        XCTAssertTrue(activity.contains("selectedSurface = AndroidSurface.ADD"))
        XCTAssertTrue(activity.contains("onAddUrlClick = { url ->"))
        let addUrlCallback = try sourceSlice(
            in: activity,
            from: "onAddUrlClick = { url ->",
            to: "onImportClick = {"
        )

        XCTAssertFalse(addUrlCallback.contains("HttpURLConnection"))
        XCTAssertFalse(addUrlCallback.contains("URL("))
        XCTAssertFalse(addUrlCallback.contains("WorkManager"))
        XCTAssertFalse(addUrlCallback.contains("Authorization"))
        XCTAssertFalse(addUrlCallback.contains("Bearer "))
        XCTAssertFalse(addUrlCallback.contains("apiKey"))
        XCTAssertFalse(addUrlCallback.contains("secret"))
        XCTAssertFalse(addUrlCallback.contains("token"))
    }

    func testAndroidSharesheetStagesIncomingTextURLWithoutPersistingRawText() throws {
        let root = packageRoot()
        let manifest = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("AndroidManifest.xml"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(manifest.contains(#"android.intent.action.SEND"#))
        XCTAssertTrue(manifest.contains(#"android.intent.category.DEFAULT"#))
        XCTAssertTrue(manifest.contains(#"android:mimeType="text/plain""#))

        XCTAssertTrue(activity.contains("private var sharedURL by mutableStateOf<String?>(null)"))
        XCTAssertTrue(activity.contains("sharedURL = intent.sharedHttpUrl()"))
        XCTAssertTrue(activity.contains("override fun onNewIntent(intent: Intent)"))
        XCTAssertTrue(activity.contains("initialSharedURL: String? = null"))
        XCTAssertTrue(activity.contains("LaunchedEffect(initialSharedURL)"))
        XCTAssertTrue(activity.contains("val sharedURL = initialSharedURL ?: return@LaunchedEffect"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withStagedDirectUrl(sharedURL)"))
        XCTAssertTrue(activity.contains("private fun Intent.sharedHttpUrl(): String?"))
        XCTAssertTrue(activity.contains("action != Intent.ACTION_SEND"))
        XCTAssertTrue(activity.contains("type != \"text/plain\""))
        XCTAssertTrue(activity.contains("getStringExtra(Intent.EXTRA_TEXT)?.firstSharedHttpUrl()"))
        XCTAssertFalse(activity.contains("getStringExtra(Intent.EXTRA_TEXT)?.trim()"))
        XCTAssertFalse(activity.contains("startsWith(\"http://\") || it.startsWith(\"https://\")"))

        let shareHandler = try sourceSlice(
            in: activity,
            from: "private fun Intent.sharedHttpUrl(): String?",
            to: "private val AndroidTranslationCredentialReference"
        )
        XCTAssertFalse(shareHandler.contains("SharedPreferences"))
        XCTAssertFalse(shareHandler.contains("Log."))
        XCTAssertFalse(shareHandler.contains("println("))
        XCTAssertFalse(shareHandler.contains("WorkManager"))
        XCTAssertFalse(shareHandler.contains("Authorization"))
        XCTAssertFalse(shareHandler.contains("Bearer "))
        XCTAssertFalse(shareHandler.contains("apiKey"))
        XCTAssertFalse(shareHandler.contains("secret"))
        XCTAssertFalse(shareHandler.contains("token"))
    }

    func testAndroidSharesheetExtractsFirstHTTPURLFromSharedText() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let domainSource = try kotlinSourceContents(under: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(domainSource.contains("fun String.firstSharedHttpUrl(): String?"))
        XCTAssertTrue(domainSource.contains("RegexOption.IGNORE_CASE"))
        XCTAssertTrue(domainSource.contains("SharedHttpUrlPattern.find(this)?.value"))
        XCTAssertTrue(domainSource.contains("trimEnd("))
        XCTAssertTrue(domainSource.contains("startsWith(\"http://\", ignoreCase = true)"))
        XCTAssertTrue(domainSource.contains("startsWith(\"https://\", ignoreCase = true)"))
        XCTAssertTrue(activity.contains("getStringExtra(Intent.EXTRA_TEXT)?.firstSharedHttpUrl()"))
        XCTAssertFalse(activity.contains("getStringExtra(Intent.EXTRA_TEXT)?.trim()"))

        XCTAssertTrue(appStateTests.contains("sharedTextUrlExtractorAcceptsSurroundedHttpText"))
        XCTAssertTrue(appStateTests.contains("\"推荐这个视频 https://example.com/watch?v=42。\".firstSharedHttpUrl()"))
        XCTAssertTrue(appStateTests.contains("\"ftp://example.com/file\".firstSharedHttpUrl()"))

        let shareHandler = try sourceSlice(
            in: activity,
            from: "private fun Intent.sharedHttpUrl(): String?",
            to: "private val AndroidTranslationCredentialReference"
        )
        XCTAssertFalse(shareHandler.contains("SharedPreferences"))
        XCTAssertFalse(shareHandler.contains("Log."))
        XCTAssertFalse(shareHandler.contains("println("))
        XCTAssertFalse(shareHandler.contains("WorkManager"))
        XCTAssertFalse(shareHandler.contains("Authorization"))
        XCTAssertFalse(shareHandler.contains("Bearer "))
        XCTAssertFalse(shareHandler.contains("apiKey"))
        XCTAssertFalse(shareHandler.contains("secret"))
        XCTAssertFalse(shareHandler.contains("token"))
    }

    func testAndroidKotlinDomainTestsMatchLiveAddUrlStagingContract() throws {
        let root = packageRoot()
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appStateTests.contains("liveAddActionsStageDirectUrlIntoReadyStateBeforeQueueingSelection"))
        XCTAssertTrue(appStateTests.contains("assertEquals(AndroidActionAvailability.ENABLED, state.addUrlState.primaryAction.availability)"))
        XCTAssertTrue(appStateTests.contains("val staged = state.withStagedDirectUrl(\" https://cdn.example.com/video.mp4 \")"))
        XCTAssertTrue(appStateTests.contains("uppercaseHttpsDirectMediaUrlStagesBeforeQueueing"))
        XCTAssertTrue(appStateTests.contains("signedDirectMediaUrlIsRejectedBeforeQueueing"))
        XCTAssertTrue(appStateTests.contains("repeatedDirectDownloadQueueingUsesUniqueItemIDs"))
        XCTAssertTrue(appStateTests.contains("startingDirectDownloadMarksItemDownloadingToPreventRepeatClicks"))
        XCTAssertTrue(appStateTests.contains("assertEquals(AndroidSurface.ADD, staged.selectedSurface)"))
        XCTAssertTrue(appStateTests.contains("assertTrue(staged.queue.isEmpty())"))
        XCTAssertTrue(appStateTests.contains("assertEquals(\"original\", staged.addReadyState?.selectedFormat?.id)"))
        XCTAssertTrue(appStateTests.contains("val queued = request?.let { staged.withQueuedDownloadRequest(it) }"))
        XCTAssertTrue(appStateTests.contains("assertEquals(AndroidDownloadState.QUEUED, queued?.queue?.single()?.state)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(\"original\", queued?.queue?.single()?.selectedFormatID)"))
        XCTAssertTrue(appStateTests.contains("assertFalse(queued?.queue?.single()?.detail?.contains(\"token\", ignoreCase = true) == true)"))
        XCTAssertTrue(appStateTests.contains("savingAPIKeyReferencePreservesCurrentNavigationAndTaskState"))
        XCTAssertTrue(appStateTests.contains("val configured = imported.withAPIKeyReference(reference)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(imported.selectedSurface, configured.selectedSurface)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(imported.addReadyState, configured.addReadyState)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(imported.queue, configured.queue)"))
        XCTAssertTrue(appStateTests.contains("assertEquals(imported.library, configured.library)"))
        XCTAssertFalse(appStateTests.contains("assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, state.addUrlState.primaryAction.availability)"))
    }

    func testAndroidSliceDoesNotDependOnGeneratedGradleWrapper() throws {
        let root = packageRoot()
        let fileManager = FileManager.default

        XCTAssertFalse(fileManager.fileExists(atPath: root
            .appendingPathComponent("android")
            .appendingPathComponent("gradlew")
            .path))
        XCTAssertFalse(fileManager.fileExists(atPath: root
            .appendingPathComponent("android")
            .appendingPathComponent("gradlew.bat")
            .path))
    }

    func testAndroidOfflineFileImportCreatesSanitizedTaskAndQueueLibraryProjections() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))
        let repositoryTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("data")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("data")
            .appendingPathComponent("repository")
            .appendingPathComponent("JsonTaskRepositoryTest.kt"))

        XCTAssertTrue(appModels.contains("data class AndroidImportedFile"))
        XCTAssertTrue(appModels.contains("object AndroidOfflineFileImportPlanner"))
        XCTAssertTrue(appModels.contains("fun taskSnapshot(file: AndroidImportedFile"))
        XCTAssertTrue(appModels.contains("private fun sanitizedImportID"))
        XCTAssertTrue(appModels.contains("val safeFileID = sanitizedImportID(file.id)"))
        XCTAssertTrue(appModels.contains(#"storageIdentifier = "android-import:$safeFileID""#))
        XCTAssertTrue(appModels.contains("fun fromTaskSnapshot(task: MobileTaskSnapshot): AndroidDownloadItem"))
        XCTAssertTrue(appModels.contains("fun fromTaskSnapshot(task: MobileTaskSnapshot, createdAtLabel: String): AndroidLibraryItem?"))
        XCTAssertTrue(appModels.contains("fun withImportedFile(file: AndroidImportedFile"))
        XCTAssertTrue(appModels.contains("AndroidOfflineFileImportPlanner.taskSnapshot(file)"))
        XCTAssertTrue(appModels.contains("AndroidDownloadItem.fromTaskSnapshot(task)"))
        XCTAssertTrue(appModels.contains("AndroidLibraryItem.fromTaskSnapshot(task"))
        XCTAssertTrue(appModels.contains("contentUri: String? = null"))
        XCTAssertTrue(appModels.contains("withStorageUri(file.contentUri)"))
        XCTAssertFalse(appModels.contains("storageIdentifier = file."))

        XCTAssertTrue(appStateTests.contains("importedVideoCreatesCompletedTaskWithoutRawContentUri"))
        XCTAssertTrue(appStateTests.contains("importedVideoSanitizesUnsafeIDsBeforeTaskPersistence"))
        XCTAssertTrue(appStateTests.contains("importedTaskProjectsIntoQueueAndLibrary"))
        XCTAssertTrue(appStateTests.contains("assertFalse(encoded.contains(\"content://\"))"))
        XCTAssertTrue(appStateTests.contains("assertFalse(encoded.contains(\"SECRET_TOKEN\"))"))
        XCTAssertTrue(appStateTests.contains("assertTrue(task.id.startsWith(\"android-import-imported-\"))"))
        XCTAssertTrue(appStateTests.contains("assertEquals(\"content://media/doc-456\", state.library.single().storageUri)"))
        XCTAssertTrue(appStateTests.contains("assertTrue(state.library.single().hasVerifiedLocalFile)"))
        XCTAssertTrue(repositoryTests.contains("importedFileTaskPersistsWithoutRawContentUri"))
        XCTAssertTrue(repositoryTests.contains("assertFalse(stored.contains(\"content://\"))"))
    }

    func testAndroidAddScreenUsesSystemFilePickerForOfflineImport() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("rememberLauncherForActivityResult"))
        XCTAssertTrue(activity.contains("ActivityResultContracts.OpenDocument()"))
        XCTAssertTrue(activity.contains(#"arrayOf("video/*")"#))
        XCTAssertTrue(activity.contains("Intent.FLAG_GRANT_READ_URI_PERMISSION"))
        XCTAssertTrue(activity.contains("Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION"))
        XCTAssertTrue(activity.contains("contentResolver.takePersistableUriPermission"))
        XCTAssertTrue(activity.contains("AndroidImportedFile("))
        XCTAssertTrue(activity.contains("contentUri = uri.toString()"))
        XCTAssertTrue(activity.contains("MessageDigest.getInstance(\"SHA-256\")"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withImportedFile(importedFile)"))
        XCTAssertTrue(activity.contains("selectedSurface = AndroidSurface.QUEUE"))
        XCTAssertTrue(activity.contains("onImportClick = {"))
        XCTAssertTrue(activity.contains("fileImportLauncher.launch(arrayOf(\"video/*\"))"))
        XCTAssertTrue(activity.contains("pendingLibraryFileRecovery = null"))
        XCTAssertFalse(activity.contains("var importedFileUri by rememberSaveable"))
    }

    func testAndroidAddScreenPrioritizesLocalVideoImportOverDirectLinks() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))
        let addScreen = try sourceSlice(
            in: activity,
            from: "private fun AddScreen(",
            to: "currentReadyState?.let"
        )
        let fileImportCard = try XCTUnwrap(addScreen.range(of: "SectionCard(title = appState.fileImportState.title)"))
        let directLinkCard = try XCTUnwrap(addScreen.range(of: "SectionCard(title = appState.addUrlState.title)"))

        XCTAssertLessThan(fileImportCard.lowerBound, directLinkCard.lowerBound)
        XCTAssertTrue(appModels.contains("title = \"导入视频\""))
        XCTAssertTrue(appModels.contains("label = \"选择视频文件\""))
        XCTAssertTrue(appModels.contains("title = \"直链\""))
        XCTAssertTrue(appModels.contains("仅支持 HTTPS 直接媒体文件链接"))
        XCTAssertFalse(appModels.contains("导入本地文件"))
        XCTAssertTrue(appStateTests.contains("assertEquals(\"选择视频文件\", state.fileImportState.primaryAction.label)"))
    }

    func testAndroidProductionUIDoesNotExposeEmptyOnClickPrimaryActions() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertFalse(
            activity.contains("Button(\n                    onClick = {},"),
            "Unavailable Add actions should render as status text/chips, not visible dead buttons."
        )
        XCTAssertFalse(
            activity.contains("OutlinedButton(\n                onClick = {},"),
            "Unavailable Settings actions should render as status text/chips, not visible dead buttons."
        )
    }

    func testAndroidLiveSettingsShowsUnavailableLocalTranslationAsStatusNotDeadControls() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))
        let settingsScreen = try sourceSlice(
            in: activity,
            from: "private fun SettingsScreen(",
            to: "SectionCard(title = \"后台处理\")"
        )
        let localModelDefaults = try sourceSlice(
            in: appModels,
            from: "companion object {\n        fun unavailableDefault(): AndroidLocalTranslationModel",
            to: "@Serializable\nenum class AndroidBackgroundCapability"
        )

        XCTAssertTrue(settingsScreen.contains("SectionCard(title = \"本机翻译\")"))
        XCTAssertTrue(settingsScreen.contains("StatusPill(text = localModelStatusLabel(model))"))
        XCTAssertTrue(activity.contains("private fun localModelStatusLabel(model: AndroidLocalTranslationModel): String"))
        XCTAssertTrue(activity.contains("\"当前不可用\""))
        XCTAssertFalse(settingsScreen.contains("StatusPill(text = model.statusLabel)"))
        XCTAssertFalse(settingsScreen.contains("PrimaryActionButton(\n                action = appState.settings.localModelPrimaryAction"))
        XCTAssertFalse(settingsScreen.contains("localModelSecondaryAction?.let"))
        XCTAssertFalse(settingsScreen.contains("本地翻译模型"))
        XCTAssertFalse(settingsScreen.contains("下载模型"))

        XCTAssertTrue(localModelDefaults.contains("fun unavailableDefault(): AndroidLocalTranslationModel"))
        XCTAssertTrue(localModelDefaults.contains("displayName = \"本机翻译\""))
        XCTAssertTrue(localModelDefaults.contains("readinessIssues = listOf(\"本机翻译当前不可用。可先使用云端 API 翻译。\")"))
        XCTAssertFalse(localModelDefaults.contains("mockDefault"))
        XCTAssertFalse(localModelDefaults.contains("android-local-translation-mock"))
        XCTAssertFalse(localModelDefaults.contains("此版本尚不支持"))
        XCTAssertFalse(localModelDefaults.contains("接入"))
        XCTAssertFalse(localModelDefaults.contains("运行时验证"))

        XCTAssertTrue(appStateTests.contains("liveSettingsShowsUnavailableLocalTranslationAsStatus"))
    }

    func testAndroidQueueAndLibraryRenderPrimaryActionsOnlyWhenCallbacksExist() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("fun QueueItemCard("))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.domain.AndroidQueueAction"))
        XCTAssertTrue(activity.contains("onPrimaryActionClick: ((AndroidDownloadItem) -> Unit)?"))
        XCTAssertTrue(activity.contains("onSecondaryActionClick: (AndroidDownloadItem, AndroidActionState) -> Unit"))
        XCTAssertTrue(activity.contains("PrimaryActionButton("))
        XCTAssertTrue(activity.contains("action = item.primaryAction"))
        XCTAssertTrue(activity.contains("if (onPrimaryActionClick != null && item.primaryAction.isEnabled)"))
        XCTAssertTrue(activity.contains("onClick = { onPrimaryActionClick(item) }"))
        XCTAssertTrue(activity.contains("ActionStatusChip(action = item.primaryAction)"))
        XCTAssertTrue(activity.contains("SecondaryActionRow("))
        XCTAssertTrue(activity.contains("onActionClick = { action -> onSecondaryActionClick(item, action) }"))
        XCTAssertTrue(activity.contains("onQueueItemRemoved = { item ->"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withoutQueueItem(item.id)"))
        XCTAssertTrue(activity.contains("AndroidQueueAction.REMOVE -> onRemove(item)"))
        XCTAssertFalse(activity.contains("if (action.label == \"移除\" && action.isEnabled)"))

        XCTAssertTrue(activity.contains("fun LibraryItemCard("))
        XCTAssertTrue(activity.contains("import com.moongate.mobile.domain.AndroidLibraryAction"))
        XCTAssertTrue(activity.contains("onPrimaryActionClick: ((AndroidLibraryItem) -> Unit)?"))
        XCTAssertTrue(activity.contains("onSecondaryActionClick: (AndroidLibraryItem, AndroidActionState) -> Unit"))
        XCTAssertTrue(activity.contains("action = item.primaryAction"))
        XCTAssertTrue(activity.contains("if (onPrimaryActionClick != null && item.primaryAction.isEnabled)"))
        XCTAssertTrue(activity.contains("onClick = { onPrimaryActionClick(item) }"))
        XCTAssertTrue(activity.contains("ActionStatusChip(action = item.primaryAction)"))
        XCTAssertTrue(activity.contains("onActionClick = { action -> onSecondaryActionClick(item, action) }"))
        XCTAssertTrue(activity.contains("onLibraryItemDeleted = { item ->"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withoutLibraryItem(item.id)"))
        XCTAssertTrue(activity.contains("handleLibraryAction("))
        XCTAssertTrue(activity.contains("action.libraryAction"))
        XCTAssertFalse(activity.contains("if (action.label == \"删除记录\" && action.isEnabled)"))

        XCTAssertTrue(appModels.contains("fun withoutQueueItem(id: String): AndroidAppState"))
        XCTAssertTrue(appModels.contains("enum class AndroidQueueAction"))
        XCTAssertTrue(appModels.contains("queueAction = AndroidQueueAction.REMOVE"))
        XCTAssertTrue(appModels.contains("queue = queue.filterNot { it.id == id }"))
        XCTAssertTrue(appModels.contains(#"library = library.filterNot { it.id == "library-$id" }"#))
        XCTAssertTrue(appModels.contains("fun withoutLibraryItem(id: String): AndroidAppState"))
        XCTAssertTrue(appModels.contains(#"val taskID = id.removePrefix("library-")"#))
        XCTAssertTrue(appModels.contains("queue = queue.filterNot { it.id == taskID }"))
        XCTAssertTrue(appModels.contains("library = library.filterNot { it.id == id }"))

        let secondaryActionRow = try sourceSlice(
            in: activity,
            from: "private fun SecondaryActionRow(",
            to: "private data class NavigationItem"
        )
        XCTAssertTrue(secondaryActionRow.contains("OutlinedButton("))
        XCTAssertTrue(secondaryActionRow.contains("enabled = action.isEnabled"))
        XCTAssertTrue(secondaryActionRow.contains("onClick = { onActionClick(action) }"))
        XCTAssertFalse(secondaryActionRow.contains("StatusPill(text = action.label)"))
    }

    func testAndroidQueueRowsExposeRecoveryPresentationAndHideDemoBanners() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains("data class AndroidQueueRecoveryPresentation"))
        XCTAssertTrue(appModels.contains("object AndroidQueueRecoveryPresenter"))
        XCTAssertTrue(appModels.contains("fun present(item: AndroidDownloadItem): AndroidQueueRecoveryPresentation?"))
        XCTAssertTrue(appModels.contains("val recoveryPresentation: AndroidQueueRecoveryPresentation?"))
        XCTAssertTrue(appModels.contains("val error: MobileTaskError? = null"))
        XCTAssertTrue(appModels.contains("MobileTaskError.SYSTEM_BACKGROUND_LIMIT"))
        XCTAssertTrue(appModels.contains("MobileTaskError.NETWORK_UNAVAILABLE"))
        XCTAssertTrue(appModels.contains("MobileTaskError.STORAGE_FULL"))
        XCTAssertTrue(appModels.contains("MobileTaskError.EXPORT_FAILED"))
        XCTAssertTrue(appModels.contains("error = MobileTaskError.NETWORK_UNAVAILABLE"))

        XCTAssertTrue(activity.contains("SnackbarHost("))
        XCTAssertTrue(activity.contains("snackbarHostState.showSnackbar"))
        XCTAssertTrue(activity.contains("RecoveryMessage("))
        XCTAssertTrue(activity.contains("item.recoveryPresentation?.let"))
        XCTAssertTrue(activity.contains("text = recovery.title"))
        XCTAssertTrue(activity.contains("text = recovery.nextStep"))

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        XCTAssertFalse(queueSurface.contains("MockBanner("))

        let queueScreen = try sourceSlice(
            in: activity,
            from: "private fun QueueScreen(",
            to: "@Composable\nprivate fun LibraryScreen("
        )
        XCTAssertFalse(queueScreen.contains("MockBanner("))
        XCTAssertFalse(queueScreen.contains("mock"))
        XCTAssertFalse(queueScreen.contains("demo"))

        XCTAssertTrue(appStateTests.contains("failedDirectDownloadRecoveryPresentationIsActionable"))
        XCTAssertTrue(appStateTests.contains("retryingAndCompletingFailedDirectDownloadClearsPreviousError"))
        XCTAssertTrue(appStateTests.contains("backgroundLimitedQueueItemExplainsForegroundRecovery"))
    }

    func testAndroidQueueRowsExposeTypedRecoveryActions() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains("enum class AndroidQueueRecoveryAction"))
        XCTAssertTrue(appModels.contains("RETRY_DOWNLOAD"))
        XCTAssertTrue(appModels.contains("RESTART_IN_FOREGROUND"))
        XCTAssertTrue(appModels.contains("REOPEN_ADD"))
        XCTAssertTrue(appModels.contains("RESELECT_FILE"))
        XCTAssertTrue(appModels.contains("OPEN_SETTINGS"))
        XCTAssertTrue(appModels.contains("val actionLabel: String? = null"))
        XCTAssertTrue(appModels.contains("val action: AndroidQueueRecoveryAction? = null"))
        XCTAssertTrue(appModels.contains("val isActionable: Boolean"))
        XCTAssertTrue(appModels.contains(#"if (item.sourceUrlForDownload.isNotBlank()) "重试" else "重新添加""#))
        XCTAssertTrue(appModels.contains("AndroidQueueRecoveryAction.RETRY_DOWNLOAD"))
        XCTAssertTrue(appModels.contains("actionLabel = \"回到前台\""))
        XCTAssertTrue(appModels.contains("action = AndroidQueueRecoveryAction.RESTART_IN_FOREGROUND"))
        XCTAssertTrue(appModels.contains("actionLabel = \"重新添加\""))
        XCTAssertTrue(appModels.contains("action = AndroidQueueRecoveryAction.REOPEN_ADD"))
        XCTAssertTrue(appModels.contains("actionLabel = \"重新选择\""))
        XCTAssertTrue(appModels.contains("action = AndroidQueueRecoveryAction.RESELECT_FILE"))

        XCTAssertTrue(activity.contains("import com.moongate.mobile.domain.AndroidQueueRecoveryAction"))
        XCTAssertTrue(activity.contains("onRecoveryActionClick: (AndroidDownloadItem, AndroidQueueRecoveryAction) -> Unit"))
        XCTAssertTrue(activity.contains("handleQueueRecoveryAction("))
        XCTAssertTrue(activity.contains("when (recoveryAction)"))
        XCTAssertTrue(activity.contains("AndroidQueueRecoveryAction.RETRY_DOWNLOAD ->"))
        XCTAssertTrue(activity.contains("AndroidQueueRecoveryAction.RESTART_IN_FOREGROUND ->"))
        XCTAssertTrue(activity.contains("AndroidQueueRecoveryAction.REOPEN_ADD ->"))
        XCTAssertTrue(activity.contains("AndroidQueueRecoveryAction.RESELECT_FILE ->"))
        XCTAssertTrue(activity.contains("selectedSurface = AndroidSurface.ADD"))
        XCTAssertTrue(activity.contains("RecoveryMessage("))
        XCTAssertTrue(activity.contains("onActionClick = { action -> onRecoveryActionClick(item, action) }"))
        XCTAssertTrue(activity.contains("TextButton("))
        XCTAssertTrue(activity.contains("enabled = recovery.action != null"))
        XCTAssertTrue(activity.contains("recovery.actionLabel?.let"))
        XCTAssertFalse(activity.contains("if (recovery.isActionable)"))

        XCTAssertTrue(appStateTests.contains("waitingForForegroundRecoveryPresentationHasTypedAction"))
        XCTAssertTrue(appStateTests.contains("failedDirectDownloadRecoveryPresentationHasRetryAction"))
        XCTAssertTrue(appStateTests.contains("missingSourceRecoveryPresentationRoutesToAdd"))
    }

    func testAndroidDestructiveQueueAndLibraryActionsRequireConfirmationAndOfferUndo() throws {
        let activity = try String(contentsOf: packageRoot()
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("import androidx.compose.material3.AlertDialog"))
        XCTAssertTrue(activity.contains("import androidx.compose.material3.TextButton"))
        XCTAssertTrue(activity.contains("import androidx.compose.material3.SnackbarResult"))
        XCTAssertTrue(activity.contains("var pendingQueueDeletion by remember { mutableStateOf<AndroidDownloadItem?>(null) }"))
        XCTAssertTrue(activity.contains("var pendingLibraryDeletion by remember { mutableStateOf<AndroidLibraryItem?>(null) }"))
        XCTAssertTrue(activity.contains("ConfirmDestructiveActionDialog("))

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        XCTAssertTrue(queueSurface.contains("pendingQueueDeletion = item"))
        XCTAssertFalse(
            queueSurface.contains("if (action.label == \"移除\" && action.isEnabled) {\n                        downloadJobs[item.id]?.cancel()\n                        onQueueItemRemoved(item)"),
            "Queue removal must not delete immediately from the overflow action."
        )

        let librarySurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.LIBRARY -> LibraryScreen(",
            to: "AndroidSurface.SETTINGS -> SettingsScreen("
        )
        XCTAssertTrue(librarySurface.contains("pendingLibraryDeletion = item"))
        XCTAssertTrue(librarySurface.contains("if (action.isDestructiveLibraryAction())"))
        XCTAssertTrue(librarySurface.contains("return@LibraryScreen"))
        XCTAssertFalse(
            librarySurface.contains("onDelete = onLibraryItemDeleted"),
            "Library delete actions should stage confirmation before mutating app state."
        )

        let queueConfirmation = try sourceSlice(
            in: activity,
            from: "private fun confirmQueueDeletion(",
            to: "private fun confirmLibraryDeletion("
        )
        XCTAssertTrue(queueConfirmation.contains("downloadJobs.remove(item.id)?.cancel()"))
        XCTAssertTrue(queueConfirmation.contains("onQueueItemRemoved(item)"))
        XCTAssertTrue(queueConfirmation.contains("snackbarHostState.showSnackbar("))
        XCTAssertTrue(queueConfirmation.contains(#"actionLabel = "撤销""#))
        XCTAssertTrue(queueConfirmation.contains("SnackbarResult.ActionPerformed"))
        XCTAssertTrue(queueConfirmation.contains("onRestore(item.restorableAfterCancellation())"))

        let libraryConfirmation = try sourceSlice(
            in: activity,
            from: "private fun confirmLibraryDeletion(",
            to: "private fun Context.openLibraryItem("
        )
        XCTAssertTrue(libraryConfirmation.contains("AndroidLibraryAction.DELETE_FILE -> true"))
        XCTAssertTrue(libraryConfirmation.contains("AndroidLibraryAction.DELETE_RECORD -> false"))
        XCTAssertTrue(libraryConfirmation.contains("val file = context.appOwnedLibraryFile(item)"))
        XCTAssertTrue(libraryConfirmation.contains("onDelete(item)"))
        XCTAssertTrue(libraryConfirmation.contains("snackbarHostState.showSnackbar("))
        XCTAssertTrue(libraryConfirmation.contains(#"actionLabel = "撤销""#))
        XCTAssertTrue(libraryConfirmation.contains("SnackbarResult.ActionPerformed"))
        XCTAssertTrue(libraryConfirmation.contains("onRestore(item)"))
        XCTAssertTrue(libraryConfirmation.contains("return@launch"))
        XCTAssertTrue(libraryConfirmation.contains("context.deleteAppOwnedLibraryFile("))
        XCTAssertTrue(libraryConfirmation.contains("onDelete = { _ -> }"))
        XCTAssertTrue(libraryConfirmation.contains("if (!deleted)"))
        XCTAssertLessThan(
            try XCTUnwrap(libraryConfirmation.range(of: "onDelete(item)")).lowerBound,
            try XCTUnwrap(libraryConfirmation.range(of: "context.deleteAppOwnedLibraryFile(")).lowerBound,
            "Library records should be removable during the undo window before the app-owned file is physically deleted."
        )
        XCTAssertTrue(activity.contains("fun AndroidActionState.isDestructiveLibraryAction"))
    }

    func testAndroidLibraryDeleteActionsRemainReachableAndUseActionSpecificConfirmationCopy() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))

        let libraryActions = try sourceSlice(
            in: appModels,
            from: "val secondaryActions: List<AndroidActionState>",
            to: "private val canDeleteAppOwnedFile"
        )
        XCTAssertTrue(libraryActions.contains("AndroidLibraryAction.SHARE"))
        XCTAssertTrue(libraryActions.contains("AndroidLibraryAction.SAVE_COPY"))
        XCTAssertTrue(libraryActions.contains("AndroidLibraryAction.DELETE_FILE"))
        XCTAssertTrue(libraryActions.contains("AndroidLibraryAction.DELETE_RECORD"))

        let secondaryActionRow = try sourceSlice(
            in: activity,
            from: "private fun SecondaryActionRow(",
            to: "private data class NavigationItem"
        )
        XCTAssertTrue(secondaryActionRow.contains("Column("))
        XCTAssertTrue(secondaryActionRow.contains("actions.forEach"))
        XCTAssertFalse(
            secondaryActionRow.contains("actions.take(2)"),
            "Library delete is the third secondary action for app-owned completed items, so truncating to two actions makes deletion unreachable."
        )

        let pendingLibraryDialog = try sourceSlice(
            in: activity,
            from: "pendingLibraryDeletion?.let { item ->",
            to: "private fun QueueScreen("
        )
        XCTAssertTrue(pendingLibraryDialog.contains("libraryDeletionTitle("))
        XCTAssertTrue(pendingLibraryDialog.contains("libraryDeletionBody("))
        XCTAssertTrue(activity.contains("private fun libraryDeletionTitle(action: AndroidActionState?): String"))
        XCTAssertTrue(activity.contains("private fun libraryDeletionBody(action: AndroidActionState?): String"))
        XCTAssertTrue(activity.contains("AndroidLibraryAction.DELETE_FILE -> \"删除文件？\""))
        XCTAssertTrue(activity.contains("AndroidLibraryAction.DELETE_RECORD -> \"删除记录？\""))
        XCTAssertTrue(activity.contains("AndroidLibraryAction.DELETE_FILE -> \"删除后会先从资料库移除，撤销窗口结束后再删除 App 内文件。\""))
        XCTAssertTrue(activity.contains("AndroidLibraryAction.DELETE_RECORD -> \"删除后只会移除资料库记录，不会删除原文件。\""))
    }

    func testAndroidDirectDownloadLifecycleActionsRemainReachableAndRestorable() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(appModels.contains("val completedArtifactStorageIdentifier: String? = null"))
        XCTAssertTrue(appModels.contains("state == AndroidDownloadState.DOWNLOADING && usesRealDownloader"))
        XCTAssertTrue(appModels.contains("fun withRestoredLibraryItem(item: AndroidLibraryItem): AndroidAppState"))
        XCTAssertTrue(appModels.contains("completedArtifactStorageIdentifier = artifactStorageIdentifier"))
        XCTAssertTrue(appModels.contains("storageIdentifier = completedArtifactStorageIdentifier"))
        XCTAssertTrue(appModels.contains("fun AndroidDownloadItem.restorableAfterCancellation(): AndroidDownloadItem"))
        XCTAssertTrue(appModels.contains("state = AndroidDownloadState.QUEUED"))

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        XCTAssertTrue(queueSurface.contains("onPrimaryActionClick = startQueueItemDownload"))

        let downloadHandler = try sourceSlice(
            in: activity,
            from: "val startQueueItemDownload: (AndroidDownloadItem) -> Unit = startDownload@ { item ->",
            to: "val fileImportLauncher = rememberLauncherForActivityResult("
        )
        XCTAssertTrue(downloadHandler.contains("if (item.isActive && item.primaryAction.isEnabled)"))
        XCTAssertTrue(downloadHandler.contains("pendingQueueDeletion = item"))
        XCTAssertTrue(downloadHandler.contains("return@startDownload"))

        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withRestoredLibraryItem(item)"))
        XCTAssertTrue(activity.contains(#"storageUri = "android-owned:$fileName""#))
        XCTAssertFalse(activity.contains("storageUri = contentUri.toString()"))
        XCTAssertTrue(activity.contains("onRestore(item.restorableAfterCancellation())"))

        XCTAssertTrue(appStateTests.contains("activeForegroundDownloadPrimaryCancelIsReachable"))
        XCTAssertTrue(appStateTests.contains("cancelledActiveForegroundDownloadRestoresAsQueuedNotZombieDownloading"))
        XCTAssertTrue(appStateTests.contains("completedForegroundDownloadUsesAppOwnedStorageForSameSessionFileDelete"))
        XCTAssertTrue(appStateTests.contains("restoringDeletedLibraryItemAlsoRestoresQueueProjectionAndPersistence"))
        XCTAssertFalse(appStateTests.contains("withDownloadedFile(retryingItem, \"content://downloads/video.mp4\""))
    }

    func testAndroidProgressIndicatorsExposeTalkBackSemantics() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("import androidx.compose.foundation.progressSemantics"))
        XCTAssertTrue(activity.contains("import androidx.compose.ui.semantics.semantics"))
        XCTAssertTrue(activity.contains("import androidx.compose.ui.semantics.stateDescription"))

        let localModelProgress = try sourceSlice(
            in: activity,
            from: "if (model.downloadState == AndroidModelDownloadState.QUEUED",
            to: "SectionCard(title = \"后台处理\")"
        )
        XCTAssertTrue(
            localModelProgress.contains(".progressSemantics(model.downloadFraction ?: 0f)"),
            "Local model download progress should expose a determinate TalkBack progress range."
        )
        XCTAssertTrue(
            localModelProgress.contains(".semantics { stateDescription = localModelProgressDescription(model) }"),
            "Local model progress should announce queued/downloading state and percentage."
        )

        let queueItemCard = try sourceSlice(
            in: activity,
            from: "private fun QueueItemCard(",
            to: "@Composable\nprivate fun RecoveryMessage("
        )
        XCTAssertTrue(
            queueItemCard.contains(".progressSemantics(progress / 100f)"),
            "Queue item progress should expose a determinate TalkBack progress range."
        )
        XCTAssertTrue(
            queueItemCard.contains(".semantics { stateDescription = queueProgressDescription(progress) }"),
            "Queue item progress should announce a spoken percentage instead of only a visual bar."
        )

        XCTAssertTrue(activity.contains("private fun localModelProgressDescription(model: AndroidLocalTranslationModel): String"))
        XCTAssertTrue(activity.contains("private fun queueProgressDescription(progress: Int): String"))
    }

    func testAndroidCompletedQueueItemsDoNotStartDownloadFromPrimaryAction() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains(#"label = "查看资料库""#))
        XCTAssertTrue(appModels.contains("fun isReadyForForegroundDownload(): Boolean"))
        XCTAssertTrue(appStateTests.contains("completedQueueItemPrimaryActionPointsToLibraryInsteadOfDownload"))
        XCTAssertTrue(appStateTests.contains(#"assertEquals("查看资料库", completedItem.primaryAction.label)"#))
        XCTAssertFalse(appStateTests.contains(#"assertEquals("打开", completedItem.primaryAction.label)"#))

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        XCTAssertTrue(queueSurface.contains("onPrimaryActionClick = startQueueItemDownload"))

        let downloadHandler = try sourceSlice(
            in: activity,
            from: "val startQueueItemDownload: (AndroidDownloadItem) -> Unit = startDownload@ { item ->",
            to: "val fileImportLauncher = rememberLauncherForActivityResult("
        )
        XCTAssertTrue(downloadHandler.contains("if (!item.isReadyForForegroundDownload())"))
        XCTAssertTrue(downloadHandler.contains("selectedSurface = AndroidSurface.LIBRARY"))
        XCTAssertTrue(downloadHandler.contains("return@startDownload"))

        let readyBranch = try sourceSlice(
            in: downloadHandler,
            from: "if (!item.isReadyForForegroundDownload())",
            to: "downloadJobs[item.id]?.cancel()"
        )
        XCTAssertTrue(readyBranch.contains("return@startDownload"))
        XCTAssertFalse(readyBranch.contains("foregroundDownloader.download"))
    }

    func testAndroidLibraryActionsUseTypedIntentsForOpenShareSaveAndDelete() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains("enum class AndroidLibraryAction"))
        XCTAssertTrue(appModels.contains(#"@SerialName("open")"#))
        XCTAssertTrue(appModels.contains(#"@SerialName("share")"#))
        XCTAssertTrue(appModels.contains(#"@SerialName("saveCopy")"#))
        XCTAssertTrue(appModels.contains(#"@SerialName("deleteFile")"#))
        XCTAssertTrue(appModels.contains(#"@SerialName("deleteRecord")"#))
        XCTAssertTrue(appModels.contains("val libraryAction: AndroidLibraryAction? = null"))
        XCTAssertTrue(appModels.contains("libraryAction = AndroidLibraryAction.OPEN"))
        XCTAssertTrue(appModels.contains("libraryAction = AndroidLibraryAction.SHARE"))
        XCTAssertTrue(appModels.contains("libraryAction = AndroidLibraryAction.SAVE_COPY"))
        XCTAssertTrue(appModels.contains("libraryAction = AndroidLibraryAction.DELETE_FILE"))
        XCTAssertTrue(appModels.contains("libraryAction = AndroidLibraryAction.DELETE_RECORD"))
        XCTAssertFalse(appModels.contains("storageUri = \"content://"))
        XCTAssertFalse(appModels.contains("storageUri = \"file://"))

        XCTAssertTrue(appStateTests.contains("libraryItemsExposeMockArtifactsWithoutClaimingLocalFiles"))
        XCTAssertTrue(appStateTests.contains("verifiedLibraryItemsExposeTypedOpenShareSaveAndDeleteActions"))
        XCTAssertTrue(appStateTests.contains("assertEquals(AndroidLibraryAction.OPEN, item.primaryAction.libraryAction)"))
        XCTAssertTrue(appStateTests.contains("AndroidLibraryAction.SHARE"))
        XCTAssertTrue(appStateTests.contains("AndroidLibraryAction.SAVE_COPY"))
        XCTAssertTrue(appStateTests.contains("AndroidLibraryAction.DELETE_FILE"))
        XCTAssertTrue(appStateTests.contains("AndroidLibraryAction.DELETE_RECORD"))
        XCTAssertTrue(appStateTests.contains("importedContentLibraryItemsOnlyDeleteRecordNotExternalFile"))
        XCTAssertTrue(appStateTests.contains("storageUri = \"android-owned:artifact-video\""))
        XCTAssertEqual(
            appStateTests.components(separatedBy: "fun sharedTextUrlExtractorAcceptsSurroundedHttpText()").count - 1,
            1
        )
        XCTAssertTrue(appStateTests.contains("fun sharedTextUrlExtractorTrimsUppercaseAndRejectsNonHttpText()"))
    }

    func testAndroidLibraryMissingFilesExposeTypedRecoveryAction() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains("enum class AndroidLibraryRecoveryAction"))
        XCTAssertTrue(appModels.contains(#"@SerialName("reselectFile")"#))
        XCTAssertTrue(appModels.contains("data class AndroidLibraryRecoveryPresentation"))
        XCTAssertTrue(appModels.contains("object AndroidLibraryRecoveryPresenter"))
        XCTAssertTrue(appModels.contains("val recoveryPresentation: AndroidLibraryRecoveryPresentation?"))
        XCTAssertTrue(appModels.contains("AndroidLibraryRecoveryAction.RESELECT_FILE"))
        XCTAssertTrue(appModels.contains("val isActionable: Boolean"))
        XCTAssertTrue(appModels.contains("AndroidLibraryAvailability.PERMISSION_DENIED -> AndroidLibraryRecoveryPresentation"))
        XCTAssertTrue(appModels.contains("androidPersistableContentStorageIdentifier"))
        XCTAssertTrue(appModels.contains("androidPersistedContentStorageUri"))
        XCTAssertTrue(appModels.contains(#"return "android-content:${encodeAndroidHex()}""#))
        XCTAssertFalse(appModels.contains("actionLabel == \"重新选择文件\""))

        XCTAssertTrue(activity.contains("import com.moongate.mobile.domain.AndroidLibraryRecoveryAction"))
        XCTAssertTrue(activity.contains("onRecoveryActionClick: (AndroidLibraryItem, AndroidLibraryRecoveryAction) -> Unit"))
        XCTAssertTrue(activity.contains("LibraryRecoveryMessage("))
        XCTAssertTrue(activity.contains("onActionClick = { action -> onRecoveryActionClick(item, action) }"))
        XCTAssertTrue(activity.contains("handleLibraryRecoveryAction("))
        XCTAssertTrue(activity.contains("AndroidLibraryRecoveryAction.RESELECT_FILE -> onReselectFile(item)"))
        XCTAssertTrue(activity.contains("pendingLibraryFileRecovery = recoveryItem"))
        XCTAssertTrue(activity.contains("pendingLibraryFileRecovery = null"))
        XCTAssertTrue(activity.contains("onLibraryFileRecovered(recoveryItem, importedFile)"))
        XCTAssertFalse(activity.contains("recovery.actionLabel == \"重新选择文件\""))

        XCTAssertTrue(appStateTests.contains("missingLibraryFileRecoveryPresentationRequestsFileReselection"))
        XCTAssertTrue(appStateTests.contains("permissionDeniedLibraryRecoveryPresentationRequestsFileReselection"))
        XCTAssertTrue(appStateTests.contains("recoveredLibraryContentUriPersistsAsSanitizedContentReference"))
        XCTAssertTrue(appStateTests.contains("recoveredLibraryContentUriWithQueryDoesNotPersistSecretReference"))
        XCTAssertTrue(appStateTests.contains("assertEquals(AndroidLibraryRecoveryAction.RESELECT_FILE, recovery.action)"))
    }

    func testAndroidLibraryScreenConnectsVerifiedFilesToSystemIntents() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        let librarySurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.LIBRARY -> LibraryScreen(",
            to: "AndroidSurface.SETTINGS -> SettingsScreen("
        )
        XCTAssertFalse(librarySurface.contains("onPrimaryActionClick = null"))
        XCTAssertTrue(librarySurface.contains("onPrimaryActionClick = { item ->"))
        XCTAssertTrue(librarySurface.contains("handleLibraryAction("))
        XCTAssertTrue(librarySurface.contains("item.primaryAction"))
        XCTAssertTrue(librarySurface.contains("action,"))
        XCTAssertTrue(librarySurface.contains("onSaveCopy = { saveItem ->"))
        XCTAssertTrue(librarySurface.contains("pendingSaveCopyItem = saveItem"))
        XCTAssertTrue(librarySurface.contains("saveCopyLauncher.launch(saveItem.suggestedCopyFileName)"))

        let handler = try sourceSlice(
            in: activity,
            from: "private fun handleLibraryAction(",
            to: "private fun Intent.sharedHttpUrl(): String?"
        )
        XCTAssertTrue(activity.contains("ActivityResultContracts.CreateDocument(\"*/*\")"))
        XCTAssertTrue(handler.contains("when (action.libraryAction)"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.OPEN -> context.openLibraryItem(item, onFeedback)"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.SHARE -> context.shareLibraryItem(item, onFeedback)"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.SAVE_COPY -> context.saveLibraryItemCopy(item, onSaveCopy, onFeedback)"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.DELETE_FILE -> onDelete(item)"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.DELETE_RECORD -> onDelete(item)"))
        XCTAssertFalse(handler.contains("AndroidLibraryAction.DELETE_FILE -> context.deleteAppOwnedLibraryFile"))
        XCTAssertTrue(handler.contains("Intent.ACTION_VIEW"))
        XCTAssertTrue(handler.contains("Intent.ACTION_SEND"))
        XCTAssertTrue(handler.contains("Intent.createChooser"))
        XCTAssertTrue(handler.contains("Intent.FLAG_GRANT_READ_URI_PERMISSION"))
        XCTAssertTrue(handler.contains("private fun Context.exportableLibraryUri(item: AndroidLibraryItem): Uri?"))
        XCTAssertTrue(handler.contains("Uri.parse(storageUri)"))
        XCTAssertTrue(handler.contains("if (rawUri.scheme == \"content\")"))
        XCTAssertTrue(handler.contains("if (rawUri.scheme != \"file\")"))
        XCTAssertTrue(handler.contains("File(context.filesDir, \"downloads\").canonicalFile"))
        XCTAssertTrue(handler.contains("rawFile.toPath().startsWith(downloadsDirectory.toPath())"))
        XCTAssertTrue(handler.contains("!rawFile.exists()"))
        XCTAssertTrue(handler.contains("FileProvider.getUriForFile("))
        XCTAssertTrue(handler.contains("LibraryFileUnavailableMessage"))
        XCTAssertTrue(handler.contains("ClipData.newUri(contentResolver, item.title, uri)"))
        XCTAssertTrue(handler.contains("private fun Context.copyLibraryItemBytes(source: Uri, destination: Uri)"))
        XCTAssertTrue(handler.contains("contentResolver.openInputStream(source)"))
        XCTAssertTrue(handler.contains("contentResolver.openOutputStream(destination)"))
        XCTAssertFalse(handler.contains("val uri = Uri.parse(storageUri)"))
        XCTAssertFalse(handler.contains(".setDataAndType(Uri.parse(storageUri)"))
        XCTAssertFalse(handler.contains(".putExtra(Intent.EXTRA_STREAM, Uri.parse(storageUri))"))
        XCTAssertFalse(handler.contains("startActivity(Intent("))
    }

    func testAndroidLibraryFileDeleteIsLimitedToAppOwnedDownloads() throws {
        let activity = try String(contentsOf: packageRoot()
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        let deleteHandler = try sourceSlice(
            in: activity,
            from: "private fun Context.deleteAppOwnedLibraryFile(",
            to: "private const val LibraryFileUnavailableMessage"
        )
        XCTAssertTrue(deleteHandler.contains("val file = appOwnedLibraryFile(item)"))
        XCTAssertTrue(deleteHandler.contains("if (file == null)"))
        XCTAssertTrue(deleteHandler.contains("if (!file.exists())"))
        XCTAssertTrue(deleteHandler.contains("if (!file.delete())"))
        XCTAssertTrue(deleteHandler.contains("onDelete(item)"))
        XCTAssertTrue(deleteHandler.contains("LibraryFileDeletedMessage"))
        XCTAssertFalse(deleteHandler.contains("contentResolver.delete"))
        XCTAssertFalse(deleteHandler.contains("Uri.parse"))

        let resolver = try sourceSlice(
            in: activity,
            from: "private fun Context.appOwnedLibraryFile(",
            to: "private fun Context.exportableLibraryUri("
        )
        XCTAssertTrue(resolver.contains("rawUri.scheme != \"android-owned\""))
        XCTAssertTrue(resolver.contains("fileName.isBlank() || fileName.contains(\"/\") || fileName.contains(\"..\")"))
        XCTAssertTrue(resolver.contains("File(File(filesDir, \"downloads\"), fileName).canonicalFile"))
        XCTAssertTrue(resolver.contains("File(filesDir, \"downloads\").canonicalFile"))
        XCTAssertTrue(resolver.contains("!file.toPath().startsWith(downloadsDirectory.toPath())"))
        XCTAssertFalse(resolver.contains("rawUri.scheme == \"content\""))
        XCTAssertFalse(resolver.contains("rawUri.scheme == \"file\""))
    }

    func testAndroidLibraryActionsSurfaceSnackbarFeedbackInsteadOfSilentFailures() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        let librarySurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.LIBRARY -> LibraryScreen(",
            to: "AndroidSurface.SETTINGS -> SettingsScreen("
        )
        XCTAssertTrue(activity.contains("val showLibraryFeedback: (String) -> Unit = { message ->"))
        XCTAssertTrue(activity.contains("coroutineScope.launch"))
        XCTAssertTrue(activity.contains("snackbarHostState.showSnackbar(message)"))
        XCTAssertTrue(librarySurface.contains("onFeedback = showLibraryFeedback"))

        let saveCopyLauncher = try sourceSlice(
            in: activity,
            from: "val saveCopyLauncher = rememberLauncherForActivityResult(",
            to: "Scaffold("
        )
        XCTAssertTrue(saveCopyLauncher.contains("LibraryCopySavedMessage"))
        XCTAssertTrue(saveCopyLauncher.contains("LibraryCopyFailedMessage"))
        XCTAssertTrue(saveCopyLauncher.contains("LibraryFileUnavailableMessage"))
        XCTAssertTrue(saveCopyLauncher.contains(".onSuccess {"))
        XCTAssertTrue(saveCopyLauncher.contains(".onFailure {"))
        XCTAssertTrue(saveCopyLauncher.contains("showLibraryFeedback("))

        let handler = try sourceSlice(
            in: activity,
            from: "private fun handleLibraryAction(",
            to: "private fun Intent.sharedHttpUrl(): String?"
        )
        XCTAssertTrue(handler.contains("onFeedback: (String) -> Unit"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.OPEN -> context.openLibraryItem(item, onFeedback)"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.SHARE -> context.shareLibraryItem(item, onFeedback)"))
        XCTAssertTrue(handler.contains("AndroidLibraryAction.SAVE_COPY -> context.saveLibraryItemCopy(item, onSaveCopy, onFeedback)"))
        XCTAssertTrue(handler.contains("LibraryFileUnavailableMessage"))
        XCTAssertTrue(handler.contains("LibraryOpenStartedMessage"))
        XCTAssertTrue(handler.contains("LibraryOpenFailedMessage"))
        XCTAssertTrue(handler.contains("LibraryShareStartedMessage"))
        XCTAssertTrue(handler.contains("LibraryShareFailedMessage"))
        XCTAssertTrue(handler.contains("onFeedback(LibraryOpenStartedMessage)"))
        XCTAssertTrue(handler.contains("onFeedback(LibraryOpenFailedMessage)"))
        XCTAssertTrue(handler.contains("onFeedback(LibraryShareStartedMessage)"))
        XCTAssertTrue(handler.contains("onFeedback(LibraryShareFailedMessage)"))
        XCTAssertFalse(handler.contains("exportableLibraryUri(item) ?: return"))
    }

    func testAndroidDirectHTTPSDownloadUsesAppOwnedForegroundAdapter() throws {
        let root = packageRoot()
        let manifest = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("AndroidManifest.xml"))
        let buildFile = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("build.gradle.kts"))
        let filePaths = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("res")
            .appendingPathComponent("xml")
            .appendingPathComponent("file_paths.xml"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))

        XCTAssertTrue(manifest.contains("android.permission.INTERNET"))
        XCTAssertTrue(manifest.contains("androidx.core.content.FileProvider"))
        XCTAssertTrue(manifest.contains(#"android:authorities="${applicationId}.files""#))
        XCTAssertTrue(manifest.contains("android.support.FILE_PROVIDER_PATHS"))
        XCTAssertTrue(manifest.contains("@xml/file_paths"))
        XCTAssertTrue(filePaths.contains("<files-path"))
        XCTAssertTrue(filePaths.contains(#"name="downloads""#))
        XCTAssertTrue(filePaths.contains(#"path="downloads/""#))
        XCTAssertTrue(buildFile.contains("implementation(libs.androidx.core)"))

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        XCTAssertFalse(queueSurface.contains("onPrimaryActionClick = null"))
        XCTAssertTrue(queueSurface.contains("onPrimaryActionClick = startQueueItemDownload"))

        let downloadHandler = try sourceSlice(
            in: activity,
            from: "val startQueueItemDownload: (AndroidDownloadItem) -> Unit = startDownload@ { item ->",
            to: "val fileImportLauncher = rememberLauncherForActivityResult("
        )
        XCTAssertTrue(downloadHandler.contains("onDirectDownloadStarted(item)"))
        XCTAssertTrue(downloadHandler.contains("foregroundDownloader.download(item)"))
        XCTAssertTrue(downloadHandler.contains("onDirectDownloadCompleted("))
        XCTAssertTrue(downloadHandler.contains(".onFailure {"))
        XCTAssertTrue(downloadHandler.contains("onDirectDownloadFailed("))
        XCTAssertTrue(downloadHandler.contains("downloaded.storageUri"))
        XCTAssertTrue(downloadHandler.contains("downloaded.byteCount"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withDownloadedFile("))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withDownloadFailed("))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withDownloadStarted(item)"))

        let downloader = try sourceSlice(
            in: activity,
            from: "private class AndroidForegroundDirectDownloader(",
            to: "private fun handleLibraryAction("
        )
        XCTAssertTrue(downloader.contains("val sourceUrl = item.sourceUrlForDownload"))
        XCTAssertTrue(downloader.contains("throw IllegalArgumentException(\"Missing source URL\")"))
        XCTAssertTrue(downloader.contains("URL(sourceUrl)"))
        XCTAssertTrue(downloader.contains("withContext(Dispatchers.IO)"))
        XCTAssertTrue(downloader.contains("url.openConnection() as HttpURLConnection"))
        XCTAssertTrue(downloader.contains("if (!url.isSafeForegroundDirectMediaUrl())"))
        XCTAssertFalse(downloader.contains("if (url.protocol != \"https\")"))
        XCTAssertFalse(downloader.contains("if (url.query != null || url.ref != null)"))
        XCTAssertTrue(downloader.contains("connection.instanceFollowRedirects = false"))
        XCTAssertTrue(downloader.contains("val finalUrl = connection.url"))
        XCTAssertTrue(downloader.contains("if (!finalUrl.isSafeForegroundDirectMediaUrl())"))
        XCTAssertTrue(downloader.contains("Download target changed to an unsupported mobile URL."))
        XCTAssertTrue(downloader.contains("context.filesDir"))
        XCTAssertTrue(downloader.contains("File(context.filesDir, \"downloads\")"))
        XCTAssertTrue(downloader.contains("item.downloadFileName()"))
        XCTAssertTrue(downloader.contains("val partialOutput = File(downloadsDirectory, \"$fileName.part\")"))
        XCTAssertTrue(downloader.contains("val output = File(downloadsDirectory, fileName)"))
        XCTAssertFalse(downloader.contains("FileProvider.getUriForFile("))
        XCTAssertFalse(downloader.contains("\"${context.packageName}.files\""))
        XCTAssertTrue(downloader.contains("private val maxDownloadBytes: Long ="))
        XCTAssertTrue(downloader.contains("connection.requestMethod = \"GET\""))
        XCTAssertTrue(downloader.contains("connection.responseCode !in 200..299"))
        XCTAssertTrue(downloader.contains("val contentLength = connection.contentLengthLong"))
        XCTAssertTrue(downloader.contains("if (contentLength > maxDownloadBytes)"))
        XCTAssertTrue(downloader.contains("throw IOException(\"Download is too large for foreground mobile storage\")"))
        XCTAssertTrue(downloader.contains("input.copyTo("))
        XCTAssertTrue(downloader.contains("limitBytes = maxDownloadBytes + 1"))
        XCTAssertTrue(downloader.contains("if (bytesCopied > maxDownloadBytes)"))
        XCTAssertTrue(downloader.contains("val replacementOutput = File(downloadsDirectory, \"$fileName.replace\")"))
        XCTAssertTrue(downloader.contains("partialOutput.renameTo(replacementOutput)"))
        XCTAssertTrue(downloader.contains("replacementOutput.renameTo(output)"))
        XCTAssertTrue(downloader.contains("throw IOException(\"Could not finalize downloaded file\")"))
        XCTAssertTrue(downloader.contains("if (!completed)"))
        XCTAssertTrue(downloader.contains("partialOutput.delete()"))
        XCTAssertTrue(downloader.contains("replacementOutput.delete()"))
        XCTAssertTrue(downloader.contains(#"storageUri = "android-owned:$fileName""#))
        XCTAssertTrue(downloader.contains("private fun AndroidDownloadItem.downloadFileName()"))
        XCTAssertTrue(downloader.contains("return appOwnedDownloadFileName()"))
        XCTAssertTrue(appModels.contains("fun AndroidDownloadItem.appOwnedDownloadFileName(): String"))
        XCTAssertTrue(appModels.contains("val safeID = id.safeAndroidFileNamePart()"))
        XCTAssertTrue(appModels.contains("val safeTitle = title.safeAndroidFileNamePart()"))
        XCTAssertTrue(appModels.contains("private fun String.safeAndroidFileNamePart(): String"))
        XCTAssertFalse(downloader.contains("storageUri = output.toURI().toString()"))
        XCTAssertFalse(downloader.contains("WorkManager"))
        XCTAssertFalse(downloader.contains("ForegroundService"))
        XCTAssertFalse(downloader.contains("NotificationManager"))
        XCTAssertFalse(downloader.contains("POST_NOTIFICATIONS"))
        XCTAssertFalse(downloader.contains("Authorization"))
        XCTAssertFalse(downloader.contains("Bearer "))
        XCTAssertFalse(downloader.contains("apiKey"))
    }

    func testAndroidBackgroundDownloaderKeepsPartialFileAndUsesRangeResume() throws {
        let root = packageRoot()
        let downloader = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("worker")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("worker")
            .appendingPathComponent("AndroidDirectMediaBackgroundDownloader.kt"))
        let workerTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("worker")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("worker")
            .appendingPathComponent("AndroidBackgroundWorkSchedulerTest.kt"))

        XCTAssertTrue(downloader.contains("val resumeOffset = existingPartialBytes(partialOutput)"))
        XCTAssertTrue(downloader.contains("connection.setRequestProperty(\"Range\", \"bytes=$resumeOffset-\")"))
        XCTAssertTrue(downloader.contains("status == HttpURLConnection.HTTP_PARTIAL"))
        XCTAssertTrue(downloader.contains("status == HttpURLConnection.HTTP_OK"))
        XCTAssertTrue(downloader.contains("val shouldAppend = resumeOffset > 0L && status == HttpURLConnection.HTTP_PARTIAL"))
        XCTAssertTrue(downloader.contains("val effectiveResumeOffset = if (shouldAppend) resumeOffset else 0L"))
        XCTAssertTrue(downloader.contains("partialOutput.outputStream(append = shouldAppend)"))
        XCTAssertTrue(downloader.contains("bytesDownloaded = effectiveResumeOffset + copied"))
        XCTAssertTrue(downloader.contains("totalBytes = normalizedTotalBytes"))
        XCTAssertTrue(downloader.contains("if (status == HttpURLConnection.HTTP_OK && resumeOffset > 0L)"))
        XCTAssertTrue(downloader.contains("partialOutput.delete()"))
        XCTAssertFalse(downloader.contains("partialOutput.delete()\n            replacementOutput.delete()"))
        XCTAssertTrue(workerTests.contains("directMediaBackgroundDownloaderKeepsPartialFileForRangeResume"))
    }

    func testAndroidRemovingActiveForegroundDownloadCancelsRunningCoroutine() throws {
        let root = packageRoot()
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(activity.contains("import kotlinx.coroutines.Job"))
        XCTAssertTrue(activity.contains("import kotlinx.coroutines.CancellationException"))
        XCTAssertTrue(activity.contains("mutableStateMapOf<String, Job>()"))
        XCTAssertTrue(activity.contains("downloadJobs[item.id] = downloadJob"))
        XCTAssertTrue(activity.contains("downloadJobs.remove(item.id)"))
        XCTAssertTrue(activity.contains("downloadJobs[item.id]?.cancel()"))
        XCTAssertTrue(activity.contains("downloadJobs.remove(item.id)?.cancel()"))
        XCTAssertTrue(activity.contains("backgroundWorkCoordinator.cancelDownload(item.id)"))
        XCTAssertTrue(activity.contains("}.onFailure { error ->"))
        XCTAssertTrue(activity.contains("if (error is CancellationException)"))
        XCTAssertTrue(activity.contains("throw error"))
        XCTAssertTrue(activity.contains("onQueueItemRemoved(item)"))

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        XCTAssertTrue(queueSurface.contains("onPrimaryActionClick = startQueueItemDownload"))

        let downloadHandler = try sourceSlice(
            in: activity,
            from: "val startQueueItemDownload: (AndroidDownloadItem) -> Unit = startDownload@ { item ->",
            to: "val fileImportLauncher = rememberLauncherForActivityResult("
        )
        XCTAssertTrue(downloadHandler.contains("val downloadJob = coroutineScope.launch"))
        XCTAssertTrue(downloadHandler.contains("downloadJobs[item.id]?.cancel()"))
        XCTAssertTrue(downloadHandler.contains("downloadJobs[item.id] = downloadJob"))
        XCTAssertTrue(downloadHandler.contains("downloadJobs.remove(item.id)"))

        let secondaryHandler = try sourceSlice(
            in: queueSurface,
            from: "onSecondaryActionClick = { item, action ->",
            to: "},\n                modifier = Modifier"
        )
        XCTAssertTrue(secondaryHandler.contains("pendingQueueDeletion = item"))
        XCTAssertFalse(secondaryHandler.contains("downloadJobs.remove(item.id)?.cancel()"))
        XCTAssertFalse(secondaryHandler.contains("onQueueItemRemoved(item)"))

        let confirmationHandler = try sourceSlice(
            in: activity,
            from: "private fun confirmQueueDeletion(",
            to: "private fun confirmLibraryDeletion("
        )
        XCTAssertTrue(confirmationHandler.contains("downloadJobs.remove(item.id)?.cancel()"))
        XCTAssertTrue(confirmationHandler.contains("backgroundWorkCoordinator.cancelDownload(item.id)"))
        XCTAssertTrue(confirmationHandler.contains("onQueueItemRemoved(item)"))
        XCTAssertFalse(confirmationHandler.contains("WorkManager"))
        XCTAssertFalse(confirmationHandler.contains("cancelUniqueWork"))
    }

    func testAndroidForegroundDirectDownloadReportsByteProgressToQueueState() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains("fun withDownloadProgress("))
        XCTAssertTrue(appModels.contains("bytesDownloaded: Long"))
        XCTAssertTrue(appModels.contains("totalBytes: Long?"))
        XCTAssertTrue(appModels.contains("bytesDownloaded.coerceAtLeast(0L)"))
        XCTAssertTrue(appModels.contains("totalBytes?.takeIf { it > 0L }"))
        XCTAssertTrue(appModels.contains("((safeDownloaded * 100L) / total).coerceIn(1L, 99L).toInt()"))
        XCTAssertTrue(appModels.contains("progressPercent = progressPercent"))
        XCTAssertTrue(appModels.contains("detail = progressDetail"))

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        let downloadHandler = try sourceSlice(
            in: activity,
            from: "val startQueueItemDownload: (AndroidDownloadItem) -> Unit = startDownload@ { item ->",
            to: "val fileImportLauncher = rememberLauncherForActivityResult("
        )
        XCTAssertTrue(downloadHandler.contains("foregroundDownloader.download(item) { progress ->"))
        XCTAssertTrue(downloadHandler.contains("onDirectDownloadProgress(item, progress.bytesDownloaded, progress.totalBytes)"))

        let downloader = try sourceSlice(
            in: activity,
            from: "private class AndroidForegroundDirectDownloader(",
            to: "private fun handleLibraryAction("
        )
        XCTAssertTrue(downloader.contains("data class AndroidDownloadProgress"))
        XCTAssertTrue(downloader.contains("bytesDownloaded: Long"))
        XCTAssertTrue(downloader.contains("totalBytes: Long?"))
        XCTAssertTrue(downloader.contains("onProgress: suspend (AndroidDownloadProgress) -> Unit,"))
        XCTAssertTrue(downloader.contains("val normalizedContentLength = contentLength.takeIf { it > 0L }"))
        XCTAssertTrue(downloader.contains("input.copyTo("))
        XCTAssertTrue(downloader.contains("onBytesCopied = { bytesCopied ->"))
        XCTAssertTrue(downloader.contains("onProgress(AndroidDownloadProgress(bytesCopied, normalizedContentLength))"))
        XCTAssertTrue(downloader.contains("onBytesCopied: suspend (Long) -> Unit = {},"))
        XCTAssertTrue(downloader.contains("onBytesCopied(bytesCopied)"))

        XCTAssertTrue(activity.contains("onDirectDownloadProgress: (AndroidDownloadItem, Long, Long?) -> Unit"))
        XCTAssertTrue(queueSurface.contains("onPrimaryActionClick = startQueueItemDownload"))
        XCTAssertTrue(downloadHandler.contains("coroutineScope.launch"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withDownloadProgress(item, bytesDownloaded, totalBytes)"))
        XCTAssertTrue(appStateTests.contains("foregroundDownloadProgressUpdatesQueuePercentWithoutCompleting"))
        XCTAssertTrue(appStateTests.contains("assertEquals(50, progressItem.progressPercent)"))
        XCTAssertTrue(appStateTests.contains("assertTrue(progressItem.detail.contains(\"50%\"))"))
    }

    func testAndroidAddReadyStateExposesFormatAndSubtitleSelections() throws {
        let root = packageRoot()
        let mediaModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("MobileMediaModels.kt"))
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))

        XCTAssertTrue(mediaModels.contains("val selectedFormatID: String? = null"))
        XCTAssertTrue(mediaModels.contains("val selectedSubtitleIDs: List<String> = emptyList()"))
        XCTAssertTrue(mediaModels.contains("val selectedAutoSubtitleIDs: List<String> = emptyList()"))
        XCTAssertTrue(mediaModels.contains("fun downloadRequest("))
        XCTAssertTrue(mediaModels.contains("formatID = selectedFormatID ?:"))
        XCTAssertTrue(mediaModels.contains("subtitleIDs = selectedSubtitleIDs"))
        XCTAssertTrue(mediaModels.contains("autoSubtitleIDs = selectedAutoSubtitleIDs"))

        XCTAssertTrue(appModels.contains("data class AndroidAddReadyState"))
        XCTAssertTrue(appModels.contains("val selectedFormat: MobileFormatChoice?"))
        XCTAssertTrue(appModels.contains("val selectedManualSubtitles: List<MobileSubtitleChoice>"))
        XCTAssertTrue(appModels.contains("val selectedAutoSubtitles: List<MobileSubtitleChoice>"))
        XCTAssertTrue(appModels.contains("val enqueueAction: AndroidActionState"))
        XCTAssertTrue(appModels.contains("val addReadyState: AndroidAddReadyState?"))
        XCTAssertTrue(appModels.contains("val selectedFormatID: String? = null"))
        XCTAssertTrue(appModels.contains("val selectedSubtitleIDs: List<String> = emptyList()"))
        XCTAssertTrue(appModels.contains("val selectedAutoSubtitleIDs: List<String> = emptyList()"))
        XCTAssertTrue(appModels.contains("fun fromDownloadRequest(request: MobileDownloadRequest"))
        XCTAssertTrue(appModels.contains("selectedFormatID = request.formatID"))
        XCTAssertTrue(appModels.contains("selectedSubtitleIDs = request.subtitleIDs"))
        XCTAssertTrue(appModels.contains("selectedAutoSubtitleIDs = request.autoSubtitleIDs"))
        XCTAssertTrue(appModels.contains("fun withQueuedDownloadRequest(request: MobileDownloadRequest"))
        XCTAssertTrue(appModels.contains("private fun nextQueueID(baseID: String): String"))
        XCTAssertTrue(appModels.contains("queue.any { it.id == candidate }"))
        XCTAssertTrue(appModels.contains("fun withDownloadStarted(item: AndroidDownloadItem): AndroidAppState"))
        XCTAssertTrue(appModels.contains("state = AndroidDownloadState.DOWNLOADING"))
        XCTAssertTrue(appModels.contains("MobileDownloadRequest("))
        XCTAssertTrue(appModels.contains("subtitleIDs = selectedManualSubtitles.map { it.id }"))
        XCTAssertTrue(appModels.contains("autoSubtitleIDs = selectedAutoSubtitles.map { it.id }"))
        XCTAssertTrue(appModels.contains("formatLabel"))
        XCTAssertTrue(appModels.contains("manualSubtitleLabel"))
        XCTAssertTrue(appModels.contains("autoSubtitleLabel"))

        XCTAssertTrue(activity.contains("readyState = appState.addReadyState"))
        XCTAssertTrue(activity.contains("FormatSelectionCard("))
        XCTAssertTrue(activity.contains("SubtitleSelectionCard("))
        XCTAssertTrue(activity.contains("selectedManualSubtitleIDs"))
        XCTAssertTrue(activity.contains("selectedAutoSubtitleIDs"))
        XCTAssertTrue(activity.contains("onFormatSelected = { selectedFormatID = it }"))
        XCTAssertTrue(activity.contains("selectedManualSubtitleIDs = selectedManualSubtitleIDs.toggled(subtitleID)"))
        XCTAssertTrue(activity.contains("selectedAutoSubtitleIDs = selectedAutoSubtitleIDs.toggled(subtitleID)"))
        XCTAssertTrue(activity.contains("onClick = { onEnqueueClick?.invoke(ready.downloadRequest) }"))
        XCTAssertTrue(activity.contains("currentAppState = currentAppState.withQueuedDownloadRequest(request)"))
        XCTAssertTrue(activity.contains("text = item.selectionSummary"))
        XCTAssertFalse(activity.contains("onClick = { }"))
        XCTAssertFalse(activity.contains("onClick = {},"))
        XCTAssertFalse(activity.contains("mock/adapter/JSON/Keystore"))
    }

    func testAndroidAddScreenImportsLocalSubtitlesAndPreservesExportMode() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        let addScreen = try sourceSlice(
            in: activity,
            from: "private fun AddScreen(",
            to: "private fun QueueScreen("
        )
        let pickerWiring = try sourceSlice(
            in: activity,
            from: "val fileImportLauncher = rememberLauncherForActivityResult(",
            to: "val saveCopyLauncher = rememberLauncherForActivityResult("
        )

        XCTAssertTrue(appModels.contains("enum class AndroidAddExportMode"))
        XCTAssertTrue(appModels.contains("SUBTITLE_FILE"))
        XCTAssertTrue(appModels.contains("BURNED_IN_VIDEO"))
        XCTAssertTrue(appModels.contains("fun withImportedSubtitle(file: AndroidImportedFile): AndroidAppState"))
        XCTAssertTrue(appModels.contains("fun withExportMode(mode: AndroidAddExportMode): AndroidAddReadyState"))
        XCTAssertTrue(appModels.contains("selectedExportMode: AndroidAddExportMode = AndroidAddExportMode.SUBTITLE_FILE"))
        XCTAssertTrue(appModels.contains("exportProfile = exportMode.exportProfile"))
        XCTAssertTrue(appModels.contains("MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE"))
        XCTAssertTrue(appModels.contains("MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE"))
        XCTAssertTrue(appModels.contains("MobileSubtitleChoice("))
        XCTAssertTrue(appModels.contains("selectedManualSubtitleIDs = selectedManualSubtitleIDs + importedSubtitle.id"))
        XCTAssertTrue(appModels.contains("exportProfile = request.exportProfile"))

        XCTAssertTrue(pickerWiring.contains("val subtitleImportLauncher = rememberLauncherForActivityResult("))
        XCTAssertTrue(pickerWiring.contains("onImportedSubtitle(importedSubtitle)"))
        XCTAssertTrue(pickerWiring.contains("selectedSurface = AndroidSurface.ADD"))
        XCTAssertTrue(activity.contains("onSubtitleImportClick = { subtitleImportLauncher.launch(AndroidSubtitleMimeTypes) }"))
        XCTAssertTrue(activity.contains("onImportClick = {"))
        XCTAssertTrue(activity.contains("fileImportLauncher.launch(arrayOf(\"video/*\"))"))
        XCTAssertTrue(activity.contains("private val AndroidSubtitleMimeTypes = arrayOf("))
        XCTAssertTrue(activity.contains("\"text/*\""))
        XCTAssertTrue(activity.contains("\"application/x-subrip\""))
        XCTAssertFalse(activity.contains("subtitleImportLauncher.launch(arrayOf(\"video/*\"))"))

        XCTAssertTrue(addScreen.contains("onSubtitleImportClick: (() -> Unit)? = null"))
        XCTAssertTrue(addScreen.contains("selectedExportMode"))
        XCTAssertTrue(addScreen.contains("readyState?.selectedManualSubtitleIDs"))
        XCTAssertTrue(addScreen.contains("ExportModeSelectionCard("))
        XCTAssertTrue(addScreen.contains("title = \"导出方式\""))
        XCTAssertTrue(activity.contains("mode.label"))
        XCTAssertTrue(appModels.contains(#"label = "字幕文件""#))
        XCTAssertTrue(appModels.contains(#"label = "带字幕视频""#))
        XCTAssertFalse(addScreen.contains("soft subtitle"))
        XCTAssertFalse(addScreen.contains("Soft subtitle"))
        XCTAssertFalse(addScreen.contains("软字幕"))

        XCTAssertTrue(appStateTests.contains("importedSubtitleIsAddedToReadyStateWithoutPersistingRawUri"))
        XCTAssertTrue(appStateTests.contains("burnedInExportModeIsPreservedWhenQueueingDownloadRequest"))
        XCTAssertTrue(appStateTests.contains("assertFalse(encoded.contains(\"content://\"))"))
        XCTAssertTrue(appStateTests.contains("assertEquals(MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE"))
        XCTAssertTrue(appStateTests.contains("MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE"))
    }

    func testAndroidBackgroundWorkPlannerDefinesConservativeRuntimeContract() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidBackgroundWorkModels.kt"))
        let testSource = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidBackgroundWorkPlannerTest.kt"))

        XCTAssertTrue(source.contains("object AndroidBackgroundWorkPlanner"))
        XCTAssertTrue(source.contains("enum class AndroidNotificationPermissionState"))
        XCTAssertTrue(source.contains("data class AndroidBackgroundRuntimeReadiness"))
        XCTAssertTrue(source.contains("val hasDownloadWorkerRuntime: Boolean = false"))
        XCTAssertTrue(source.contains("val canRunDownloadInBackground: Boolean"))
        XCTAssertTrue(source.contains("hasDownloadWorkerRuntime &&"))
        XCTAssertTrue(source.contains("notificationPermission != AndroidNotificationPermissionState.UNKNOWN"))
        XCTAssertTrue(source.contains("notificationPermission != AndroidNotificationPermissionState.DENIED"))
        XCTAssertTrue(source.contains("USER_INITIATED_DATA_TRANSFER"))
        XCTAssertTrue(source.contains("FOREGROUND_SERVICE"))
        XCTAssertTrue(source.contains("WORK_MANAGER"))
        XCTAssertTrue(source.contains("NOTIFICATION_PERMISSION"))
        XCTAssertTrue(source.contains("WORKER_RUNTIME"))
        XCTAssertTrue(source.contains("FOREGROUND_UNTIL_ADAPTER_EXISTS"))
        XCTAssertTrue(source.contains("NETWORK_LOST"))
        XCTAssertTrue(source.contains("BATTERY_SAVER"))
        XCTAssertTrue(source.contains("TIME_LIMIT"))
        XCTAssertTrue(source.contains("fun defaultCapabilityItems("))
        XCTAssertTrue(source.contains("runtimeReadiness: AndroidBackgroundRuntimeReadiness = AndroidBackgroundRuntimeReadiness()"))
        XCTAssertTrue(source.contains("AndroidBackgroundCapabilityItem("))
        XCTAssertFalse(source.contains("import android."))
        XCTAssertFalse(source.contains("androidx.work"))
        XCTAssertFalse(source.contains("WorkManager.getInstance"))
        XCTAssertFalse(source.contains("startForegroundService"))
        XCTAssertFalse(source.contains("NotificationManager"))
        XCTAssertFalse(source.contains("HttpURLConnection"))
        XCTAssertTrue(testSource.contains("downloadPlanStaysForegroundBoundUntilAdaptersAndNotificationsExist"))
        XCTAssertTrue(testSource.contains("downloadPlanCanBecomeBackgroundEligibleOnlyWithAdapterNotificationAndWorkerRuntime"))
        XCTAssertTrue(testSource.contains("downloadPlanStaysForegroundBoundWhenNotificationPermissionOrWorkerRuntimeIsMissing"))
        XCTAssertTrue(testSource.contains("AndroidNotificationPermissionState.GRANTED"))
        XCTAssertTrue(testSource.contains("AndroidNotificationPermissionState.DENIED"))
        XCTAssertTrue(testSource.contains("hasDownloadWorkerRuntime = false"))
        XCTAssertTrue(testSource.contains("renderPlanStaysForegroundBoundUntilRendererAndCheckpointingExist"))
        XCTAssertTrue(testSource.contains("assertFalse(plan.isProductionReady)"))
        XCTAssertTrue(testSource.contains("assertTrue(plan.requiresForeground)"))
    }

    func testAndroidTaskActionsExposeSubtitleAndRenderExportParity() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("MobileTaskModels.kt"))

        XCTAssertTrue(source.contains(#"@SerialName("exportTranslatedSubtitle")"#))
        XCTAssertTrue(source.contains("EXPORT_TRANSLATED_SUBTITLE"))
        XCTAssertTrue(source.contains(#"@SerialName("exportRenderedVideo")"#))
        XCTAssertTrue(source.contains("EXPORT_RENDERED_VIDEO"))
        XCTAssertTrue(source.contains("MobileTaskAction.EXPORT_TRANSLATED_SUBTITLE"))
        XCTAssertTrue(source.contains("MobileTaskAction.EXPORT_RENDERED_VIDEO"))
        XCTAssertTrue(source.contains("MobileArtifactKind.TRANSCRIPT"))
        XCTAssertTrue(source.contains("MobileArtifactKind.TRANSLATED_SUBTITLE_FILE"))
        XCTAssertTrue(source.contains("MobileArtifactKind.ORIGINAL_MEDIA"))
        XCTAssertFalse(
            source.contains("MobileArtifactKind.SOFT_SUBTITLE ||"),
            "Android render actions should not offer burned-in export for soft subtitles until conversion exists."
        )
    }

    func testAndroidCompletedQueueExportActionsAreTypedAndReachable() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains("EXPORT_TRANSLATED_SUBTITLE"))
        XCTAssertTrue(appModels.contains("EXPORT_RENDERED_VIDEO"))
        XCTAssertTrue(appModels.contains(#"@SerialName("exportTranslatedSubtitle")"#))
        XCTAssertTrue(appModels.contains(#"@SerialName("exportRenderedVideo")"#))
        XCTAssertTrue(appModels.contains("val availableTaskActions: List<MobileTaskAction> = emptyList()"))
        XCTAssertTrue(appModels.contains("availableTaskActions = task.availableActions"))
        XCTAssertTrue(appModels.contains("queueAction = AndroidQueueAction.EXPORT_TRANSLATED_SUBTITLE"))
        XCTAssertTrue(appModels.contains("queueAction = AndroidQueueAction.EXPORT_RENDERED_VIDEO"))
        XCTAssertTrue(appModels.contains("fun withTranslatedSubtitleExportStarted(item: AndroidDownloadItem): AndroidAppState"))
        XCTAssertTrue(appModels.contains("fun withRenderExportStarted(item: AndroidDownloadItem): AndroidAppState"))
        XCTAssertTrue(appModels.contains("state = AndroidDownloadState.WAITING_FOR_FOREGROUND"))
        XCTAssertTrue(appModels.contains("backgroundStatus = AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER"))
        let completedQueueActions = try sourceSlice(
            in: appModels,
            from: "AndroidDownloadState.COMPLETED -> buildList {",
            to: "AndroidDownloadState.FAILED -> listOf("
        )
        XCTAssertFalse(
            completedQueueActions.contains(#"label = "分享","#),
            "Completed queue secondary actions must not expose an enabled no-op share action without a queue handler."
        )
        XCTAssertFalse(
            appModels.contains("queueAction = AndroidQueueAction.EXPORT_RENDERED_VIDEO") &&
                appModels.contains("state = AndroidDownloadState.COMPLETED") &&
                appModels.contains("rendered video exported"),
            "Android must not fabricate a completed rendered-video result before renderer and runtime validation exist."
        )

        let queueSurface = try sourceSlice(
            in: activity,
            from: "AndroidSurface.QUEUE -> QueueScreen(",
            to: "AndroidSurface.LIBRARY -> LibraryScreen("
        )
        let shell = try sourceSlice(
            in: activity,
            from: "private fun MoongateShell(",
            to: "private fun AddScreen("
        )
        XCTAssertTrue(queueSurface.contains("onSecondaryActionClick = { item, action ->"))
        XCTAssertTrue(queueSurface.contains("handleQueueAction("))
        XCTAssertTrue(activity.contains("private fun handleQueueAction("))
        XCTAssertTrue(activity.contains("AndroidQueueAction.EXPORT_TRANSLATED_SUBTITLE -> onExportTranslatedSubtitle(item)"))
        XCTAssertTrue(activity.contains("AndroidQueueAction.EXPORT_RENDERED_VIDEO -> onExportRenderedVideo(item)"))
        let previewCall = try sourceSlice(
            in: activity,
            from: "private fun MoongateAppPreview()",
            to: "private fun ignoreDirectUrl(url: String) = Unit"
        )
        XCTAssertTrue(previewCall.contains("onTranslatedSubtitleExportRequested = ::ignoreQueuePrimaryAction"))
        XCTAssertTrue(previewCall.contains("onRenderExportRequested = ::ignoreQueuePrimaryAction"))
        XCTAssertFalse(
            shell.contains("currentAppState = currentAppState.withTranslatedSubtitleExportStarted(item)"),
            "MoongateShell is a top-level composable and must not close over MoongateApp.currentAppState."
        )
        XCTAssertFalse(
            shell.contains("currentAppState = currentAppState.withRenderExportStarted(item)"),
            "MoongateShell should receive queue export callbacks from the owning app state instead of mutating it directly."
        )
        XCTAssertTrue(activity.contains("onTranslatedSubtitleExportRequested"))
        XCTAssertTrue(activity.contains("onRenderExportRequested"))
        XCTAssertTrue(activity.contains("persistQueueItem(item.id)"))

        XCTAssertTrue(appStateTests.contains("completedTranscriptTaskExposesReachableSubtitleExportQueueAction"))
        XCTAssertTrue(appStateTests.contains("completedBurnedInTaskExposesReachableRenderExportQueueAction"))
        XCTAssertTrue(appStateTests.contains("id = \"content://tasks/export?token=TASK_SECRET&Authorization=Bearer%20TASK\""))
        XCTAssertTrue(appStateTests.contains("assertFalse(encodedStorage.contains(\"TASK_SECRET\"))"))
        XCTAssertTrue(appStateTests.contains("withTranslatedSubtitleExportStarted"))
        XCTAssertTrue(appStateTests.contains("withRenderExportStarted"))
    }

    func testAndroidRenderRequestPlannerDefinesPureDomainContract() throws {
        let root = packageRoot()
        let source = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("MobileRenderRequestPlanner.kt"))

        XCTAssertTrue(source.contains("enum class MobileRenderRequestPlanStatus"))
        XCTAssertTrue(source.contains("NOT_REQUIRED"))
        XCTAssertTrue(source.contains("READY"))
        XCTAssertTrue(source.contains("BLOCKED"))
        XCTAssertTrue(source.contains("enum class MobileRenderRequestBlockedReason"))
        XCTAssertTrue(source.contains("TASK_NOT_COMPLETED"))
        XCTAssertTrue(source.contains("UNSUPPORTED_EXPORT_PROFILE"))
        XCTAssertTrue(source.contains("MISSING_SOURCE_MEDIA"))
        XCTAssertTrue(source.contains("MISSING_SUBTITLE"))
        XCTAssertTrue(source.contains("data class MobileRenderRequestPlan"))
        XCTAssertTrue(source.contains("object MobileRenderRequestPlanner"))
        XCTAssertTrue(source.contains("fun plan(task: MobileTaskSnapshot): MobileRenderRequestPlan"))
        XCTAssertTrue(source.contains("MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE"))
        XCTAssertTrue(source.contains("MobileArtifactKind.ORIGINAL_MEDIA"))
        XCTAssertTrue(source.contains("MobileArtifactKind.TRANSLATED_SUBTITLE_FILE"))
        XCTAssertFalse(
            source.contains("MobileArtifactKind.SOFT_SUBTITLE"),
            "Planner should only pass SRT translated subtitle artifacts to burned-in rendering until soft subtitle conversion exists."
        )
        XCTAssertFalse(source.contains("import android."))
        XCTAssertFalse(source.contains("WorkManager"))
        XCTAssertFalse(source.contains("HttpURLConnection"))
        XCTAssertFalse(source.contains("Authorization"))
        XCTAssertFalse(source.contains("Bearer "))
    }

    func testAndroidRenderRequestPlannerKotlinTestsCoverDomainStates() throws {
        let root = packageRoot()
        let testSource = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("MobileRenderRequestPlannerTest.kt"))

        XCTAssertTrue(testSource.contains("skipsProfilesThatDoNotNeedVideoRender"))
        XCTAssertTrue(testSource.contains("blocksActiveTasksBeforeCreatingRequest"))
        XCTAssertTrue(testSource.contains("blocksUnsupportedRenderProfiles"))
        XCTAssertTrue(testSource.contains("reportsMissingSourceMediaWithoutFakeRequest"))
        XCTAssertTrue(testSource.contains("reportsMissingSubtitleWithoutFakeRequest"))
        XCTAssertTrue(testSource.contains("buildsBurnedInRequestFromOriginalMediaAndTranslatedSubtitle"))
        XCTAssertTrue(testSource.contains("rejectsSoftSubtitleArtifactForBurnInUntilConversionExists"))
        XCTAssertTrue(testSource.contains("completedTasksWithTranscriptExposeSubtitleExportAction"))
        XCTAssertTrue(testSource.contains("completedBurnedInTasksExposeRenderExportAction"))
    }

    func testAndroidLocalModelPlannerDefinesPureDownloadDeleteStateMachine() throws {
        let root = packageRoot()
        let appModels = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppModels.kt"))
        let activity = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("app")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("android")
            .appendingPathComponent("MainActivity.kt"))
        let appStateTests = try String(contentsOf: root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAppStateTest.kt"))

        XCTAssertTrue(appModels.contains("enum class AndroidLocalModelAction"))
        XCTAssertTrue(appModels.contains(#"@SerialName("download")"#))
        XCTAssertTrue(appModels.contains(#"@SerialName("delete")"#))
        XCTAssertTrue(appModels.contains("data class AndroidLocalModelPlan"))
        XCTAssertTrue(appModels.contains("object AndroidLocalModelPlanner"))
        XCTAssertTrue(appModels.contains("fun planDownload(model: AndroidLocalTranslationModel): AndroidLocalModelPlan"))
        XCTAssertTrue(appModels.contains("fun applyDownloadQueued(model: AndroidLocalTranslationModel): AndroidLocalTranslationModel"))
        XCTAssertTrue(appModels.contains("fun applyDownloadProgress("))
        XCTAssertTrue(appModels.contains("fun applyDownloadReady(model: AndroidLocalTranslationModel): AndroidLocalTranslationModel"))
        XCTAssertTrue(appModels.contains("fun applyDownloadFailure("))
        XCTAssertTrue(appModels.contains("fun applyDelete(model: AndroidLocalTranslationModel): AndroidLocalTranslationModel"))
        XCTAssertTrue(appModels.contains("val primaryAction: AndroidActionState"))
        XCTAssertTrue(appModels.contains("val secondaryAction: AndroidActionState?"))
        XCTAssertTrue(appModels.contains("downloadedBytes.coerceIn(0L, targetTotal)"))
        XCTAssertTrue(appModels.contains("readinessIssues = emptyList()"))
        XCTAssertTrue(appModels.contains("readinessIssues = listOf(message)"))
        XCTAssertTrue(appModels.contains("val localModelPrimaryAction: AndroidActionState"))
        XCTAssertTrue(appModels.contains("val localModelSecondaryAction: AndroidActionState?"))

        XCTAssertTrue(activity.contains("SectionCard(title = \"本机翻译\")"))
        XCTAssertTrue(activity.contains("StatusPill(text = localModelStatusLabel(model))"))
        XCTAssertFalse(
            activity.contains("action = appState.settings.localModelPrimaryAction"),
            "The planner should stay testable, but unavailable local translation should not render a dead primary button in live Settings."
        )
        XCTAssertFalse(activity.contains("appState.settings.localModelSecondaryAction?.let"))

        XCTAssertTrue(appStateTests.contains("localModelPlannerQueuesDownloadAndReportsProgress"))
        XCTAssertTrue(appStateTests.contains("localModelPlannerMarksReadyAndDeleteReturnsToSafeUnavailableState"))
        XCTAssertTrue(appStateTests.contains("localModelPlannerFailureDoesNotBecomeRunnable"))
        XCTAssertTrue(appStateTests.contains("liveSettingsShowsUnavailableLocalTranslationAsStatus"))
        XCTAssertTrue(appStateTests.contains("liveSettingsShowsCloudTranslationReadinessWithoutTreatingSavedKeyAsRunnable"))
        XCTAssertTrue(appStateTests.contains("cloudTranslationReadinessProducesMobileConfigurationWithoutSecretValues"))

        let localModelBoundary = try sourceSlice(
            in: appModels,
            from: "@Serializable\nenum class AndroidTranslationProvider",
            to: "@Serializable\nenum class AndroidBackgroundCapability"
        )

        XCTAssertFalse(localModelBoundary.contains("WorkManager"))
        XCTAssertFalse(localModelBoundary.contains("HttpURLConnection"))
        XCTAssertFalse(localModelBoundary.contains("URL("))
        XCTAssertFalse(localModelBoundary.contains("Authorization"))
        XCTAssertFalse(localModelBoundary.contains("Bearer "))
        XCTAssertFalse(localModelBoundary.contains("apiKeySecret"))
        XCTAssertFalse(localModelBoundary.contains("apiKeyValue"))
        XCTAssertFalse(localModelBoundary.contains("secret"))
        XCTAssertFalse(localModelBoundary.contains("token"))
    }

    func testAndroidLocalBuildGateScriptUsesOnlyExistingGradle() throws {
        let root = packageRoot()
        let scriptURL = root
            .appendingPathComponent("Scripts")
            .appendingPathComponent("build-android-local.sh")
        let script = try String(contentsOf: scriptURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue

        XCTAssertEqual(permissions & 0o111, 0o111)
        XCTAssertTrue(script.contains("android/gradlew"))
        XCTAssertTrue(script.contains("command -v gradle"))
        XCTAssertTrue(script.contains(":core:domain:test"))
        XCTAssertTrue(script.contains(":core:data:test"))
        XCTAssertTrue(script.contains(":core:worker:test"))
        XCTAssertTrue(script.contains(":app:assembleDebug"))
        XCTAssertTrue(script.contains("--offline"))
        XCTAssertTrue(script.contains("--no-daemon"))
        XCTAssertTrue(script.contains("exit 66"))
        XCTAssertTrue(script.contains("No wrapper download"))
        XCTAssertTrue(script.contains("cached dependencies"))
        XCTAssertFalse(script.contains("curl "))
        XCTAssertFalse(script.contains("wget "))
        XCTAssertFalse(script.contains("sdkmanager"))
        XCTAssertFalse(script.contains("brew "))
        XCTAssertFalse(script.contains("sudo "))
        XCTAssertFalse(script.contains("gradle wrapper"))
        XCTAssertFalse(script.contains("./gradlew wrapper"))
        XCTAssertFalse(script.contains("--refresh-dependencies"))
    }

    func testAndroidAPICompatibleTranslationPlannerBuildsCloudRequestsWithoutPersistingSecrets() throws {
        let root = packageRoot()
        let sourceURL = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("main")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("MobileTranslationModels.kt")
        let testURL = root
            .appendingPathComponent("android")
            .appendingPathComponent("core")
            .appendingPathComponent("domain")
            .appendingPathComponent("src")
            .appendingPathComponent("test")
            .appendingPathComponent("kotlin")
            .appendingPathComponent("com")
            .appendingPathComponent("moongate")
            .appendingPathComponent("mobile")
            .appendingPathComponent("domain")
            .appendingPathComponent("AndroidAPICompatibleTranslationPlannerTest.kt")
        let source = try String(contentsOf: sourceURL)
        let testSource = try String(contentsOf: testURL)
        let planner = try sourceSlice(
            in: source,
            from: "data class AndroidTranslationTransportRequest",
            to: "@Serializable\ndata class MobileSubtitleProcessingRequest"
        )

        XCTAssertTrue(planner.contains("data class AndroidTranslationTransportRequest"))
        XCTAssertTrue(planner.contains("object AndroidAPICompatibleTranslationPlanner"))
        XCTAssertTrue(planner.contains("fun plan("))
        XCTAssertTrue(planner.contains("TranslationEngine.OPENAI_COMPATIBLE"))
        XCTAssertTrue(planner.contains("TranslationEngine.ANTHROPIC_COMPATIBLE"))
        XCTAssertTrue(planner.contains("\"/v1/responses\""))
        XCTAssertTrue(planner.contains("\"/v1/messages\""))
        XCTAssertTrue(planner.contains("\"content-type\" to \"application/json\""))
        XCTAssertTrue(planner.contains("\"Authorization\" to \"Bearer $normalizedSecret\""))
        XCTAssertTrue(planner.contains("\"x-api-key\" to normalizedSecret"))
        XCTAssertTrue(planner.contains("private const val ANTHROPIC_VERSION = \"2023-06-01\""))
        XCTAssertTrue(planner.contains("\"anthropic-version\" to ANTHROPIC_VERSION"))
        XCTAssertTrue(planner.contains("host != \"api.anthropic.com\""))
        XCTAssertTrue(planner.contains("put(\"store\", false)"))
        XCTAssertTrue(planner.contains("\"${it.id}=${it.text}\""))
        XCTAssertTrue(planner.contains("startsWith(\"https://\", ignoreCase = true)"))
        XCTAssertTrue(planner.contains("requiresCloudConfiguration"))
        XCTAssertTrue(testSource.contains("buildsOpenAIResponsesRequestWithoutPersistingSecretInConfiguration"))
        XCTAssertTrue(testSource.contains("officialAnthropicRequestDoesNotSendAuthorizationHeader"))
        XCTAssertTrue(testSource.contains("rejectsInvalidConfigurationBeforeBuildingRequest"))
        XCTAssertTrue(testSource.contains("assertTrue(request.body.contains(\"\\\"store\\\":false\"))"))
        XCTAssertTrue(testSource.contains("assertFalse(encodedConfiguration.contains(\"TEST_SECRET_VALUE_DO_NOT_STORE\"))"))

        XCTAssertFalse(source.contains("@Serializable\ndata class AndroidTranslationTransportRequest"))
        XCTAssertFalse(planner.contains("import android."))
        XCTAssertFalse(planner.contains("WorkManager"))
        XCTAssertFalse(planner.contains("HttpURLConnection"))
        XCTAssertFalse(planner.contains("URLConnection"))
        XCTAssertFalse(planner.contains("java.net.URL"))
        XCTAssertFalse(planner.contains("KeyStore"))
        XCTAssertFalse(planner.contains("Keystore"))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func kotlinSourceContents(under directory: URL) throws -> String {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ))
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "kt" }
            .sorted { $0.path < $1.path }
        XCTAssertFalse(files.isEmpty)
        return try files
            .map { try String(contentsOf: $0) }
            .joined(separator: "\n")
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
