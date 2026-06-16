package com.moongate.mobile.domain

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AndroidAppStateTest {
    @Test
    fun sampleStateExposesMaterialSurfacesAndMockBoundaries() {
        val state = AndroidAppState.sample()

        assertEquals(AndroidSurface.ADD, state.selectedSurface)
        assertEquals(
            listOf(
                AndroidSurface.ADD,
                AndroidSurface.QUEUE,
                AndroidSurface.LIBRARY,
                AndroidSurface.SETTINGS,
            ),
            state.surfaces,
        )
        assertTrue(state.addUrlState.isMockOnly)
        assertTrue(state.fileImportState.isMockOnly)
        assertTrue(state.mockBoundaries.any { it.contains("yt-dlp") })
        assertTrue(state.mockBoundaries.any { it.contains("ffmpeg") })
    }

    @Test
    fun liveAddSessionStateStartsIdleAndCoversMaterialStates() {
        val state = AndroidAppState.live()
        val failed = state.withStagedDirectUrl("not a url")

        assertEquals(
            listOf(
                MobileAddSessionState.IDLE,
                MobileAddSessionState.ANALYZING,
                MobileAddSessionState.CANDIDATE_SELECTION,
                MobileAddSessionState.READY,
                MobileAddSessionState.UNSUPPORTED,
                MobileAddSessionState.FAILED,
            ),
            MobileAddSessionState.values().toList(),
        )
        assertEquals(AndroidSurface.ADD, state.selectedSurface)
        assertEquals(AndroidDefaultSurfaces, state.surfaces)
        assertFalse(state.addUrlState.isMockOnly)
        assertFalse(state.fileImportState.isMockOnly)
        assertEquals(MobileAddSessionState.IDLE, state.addSessionState)
        assertEquals(MobileAddSessionState.FAILED, failed.addSessionState)
        assertEquals(null, failed.addReadyState)
        assertTrue(state.queue.isEmpty())
        assertTrue(state.library.isEmpty())
        assertTrue(state.mockBoundaries.isEmpty())
        assertFalse(state.addUrlState.helperText.contains("mock", ignoreCase = true))
        assertFalse(state.addUrlState.helperText.contains("yt-dlp", ignoreCase = true))
        assertFalse(state.fileImportState.helperText.contains("未接入"))
        assertFalse(state.settings.apiKeyMockMessage.contains("占位"))
        assertFalse(state.settings.apiKeyMockMessage.contains("未接入"))
    }

    @Test
    fun liveAddActionsStageDirectUrlIntoReadyStateBeforeQueueingSelection() {
        val state = AndroidAppState.live()

        assertEquals("解析链接", state.addUrlState.primaryAction.label)
        assertEquals(AndroidActionAvailability.ENABLED, state.addUrlState.primaryAction.availability)
        assertEquals("选择视频文件", state.fileImportState.primaryAction.label)
        assertEquals(AndroidActionAvailability.ENABLED, state.fileImportState.primaryAction.availability)
        assertEquals("导入视频", state.fileImportState.title)
        assertEquals("直链", state.addUrlState.title)
        assertTrue(state.addUrlState.helperText.contains("HTTPS 直接媒体文件链接"))
        assertTrue(state.addUrlState.primaryAction.helperText?.contains("adapter", ignoreCase = true) != true)
        assertTrue(state.fileImportState.primaryAction.helperText?.contains("adapter", ignoreCase = true) != true)

        val staged = state.withStagedDirectUrl(" https://cdn.example.com/video.mp4 ")

        assertEquals(AndroidSurface.ADD, staged.selectedSurface)
        assertEquals(MobileAddSessionState.READY, staged.addSessionState)
        assertTrue(staged.queue.isEmpty())
        assertEquals(1, staged.addCandidates.size)
        assertEquals(staged.addReadyState?.videoInfo?.candidate?.id, staged.selectedAddCandidateID)
        assertTrue(staged.addCandidates.single().isSupportedOnMobile)
        assertEquals("video.mp4", staged.addReadyState?.videoInfo?.title)
        assertEquals("original", staged.addReadyState?.selectedFormat?.id)
        assertTrue(staged.addReadyState?.manualSubtitles?.isEmpty() == true)
        assertTrue(staged.addReadyState?.autoSubtitles?.isEmpty() == true)
        val request = staged.addReadyState?.downloadRequest
        val queued = request?.let { staged.withQueuedDownloadRequest(it) }

        assertEquals(AndroidSurface.QUEUE, queued?.selectedSurface)
        assertEquals(1, queued?.queue?.size)
        assertEquals(AndroidDownloadState.QUEUED, queued?.queue?.single()?.state)
        assertEquals("video.mp4", queued?.queue?.single()?.title)
        assertEquals("original", queued?.queue?.single()?.selectedFormatID)
        assertTrue(queued?.queue?.single()?.selectedSubtitleIDs?.isEmpty() == true)
        assertTrue(queued?.queue?.single()?.selectedAutoSubtitleIDs?.isEmpty() == true)
        assertFalse(queued?.queue?.single()?.detail?.contains("token", ignoreCase = true) == true)
    }

    @Test
    fun directUrlTaskIDIsOpaqueAndNotURLHashDerived() {
        var next = 0
        val factory = AndroidOpaqueIDFactory { prefix ->
            next += 1
            "$prefix-fixed-$next"
        }

        val result = AndroidAddUrlPlanner.stageDirectUrl(
            input = "https://cdn.example.com/private/path/video.mp4",
            idFactory = factory,
        )
        val readyState = (result as AndroidAddUrlPlanResult.Staged).readyState
        val queued = AndroidAppState.live()
            .copy(addReadyState = readyState)
            .withQueuedDownloadRequest(readyState.downloadRequest)
        val item = queued.queue.single()

        assertTrue(readyState.downloadRequest.id.startsWith("android-download-fixed-"))
        assertEquals(readyState.downloadRequest.id, item.id)
        assertFalse(readyState.downloadRequest.id == readyState.sessionID)
        assertFalse(readyState.downloadRequest.id == readyState.videoInfo.videoID)
        assertFalse(readyState.downloadRequest.id == readyState.videoInfo.candidate.id)
        assertFalse(item.id.contains("cdn.example.com"))
        assertFalse(item.id.contains("private"))
        assertFalse(item.id.contains("video.mp4"))
        assertFalse(item.id.contains("hash", ignoreCase = true))
    }

    @Test
    fun queueSelectionSummaryDoesNotExposeRawFormatOrSubtitleIds() {
        val item = AndroidDownloadItem(
            id = "download-1",
            title = "clip.mp4",
            sourceLabel = "移动端任务",
            state = AndroidDownloadState.QUEUED,
            detail = "等待下载",
            selectedFormatID = "original",
            selectedSubtitleIDs = listOf("en-original"),
            selectedAutoSubtitleIDs = listOf("zh-Hans-auto"),
        )

        assertEquals("已选格式 · 已选 1 个手动字幕 · 已选 1 个自动字幕 · 字幕文件", item.selectionSummary)
        assertFalse(item.selectionSummary.contains("original"))
        assertFalse(item.selectionSummary.contains("zh-Hans-auto"))
        assertFalse(item.selectionSummary.contains("en-original"))
    }

    @Test
    fun signedDirectMediaUrlIsRejectedBeforeQueueing() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")

        val rejected = staged.withStagedDirectUrl("https://cdn.example.com/video.mp4?signature=redacted")

        assertEquals(null, rejected.addReadyState)
        assertEquals(MobileAddSessionState.UNSUPPORTED, rejected.addSessionState)
        assertTrue(rejected.queue.isEmpty())
        assertTrue(rejected.addUrlState.errorMessage?.contains("带参数") == true)
    }

    @Test
    fun audioDirectMediaUrlIsRejectedBeforeQueueing() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")

        val rejected = staged.withStagedDirectUrl("https://cdn.example.com/audio.mp3")

        assertEquals(null, rejected.addReadyState)
        assertEquals(MobileAddSessionState.UNSUPPORTED, rejected.addSessionState)
        assertTrue(rejected.queue.isEmpty())
        assertTrue(rejected.addUrlState.errorMessage?.contains(".mp4") == true)
        assertTrue(rejected.addUrlState.errorMessage?.contains(".webm") == true)
    }

    @Test
    fun credentialedDirectMediaUrlIsRejectedBeforeQueueing() {
        val rejected = AndroidAppState.live()
            .withStagedDirectUrl("https://user:pass@cdn.example.com/video.mp4")

        assertEquals(null, rejected.addReadyState)
        assertEquals(MobileAddSessionState.UNSUPPORTED, rejected.addSessionState)
        assertTrue(rejected.queue.isEmpty())
        assertTrue(rejected.addUrlState.errorMessage?.contains("直接媒体链接") == true)
    }

    @Test
    fun genericWebUrlIsRejectedInsteadOfFabricatingReadyMedia() {
        val state = AndroidAppState.live()

        val rejected = state.withStagedDirectUrl("https://example.com/watch")

        assertEquals(null, rejected.addReadyState)
        assertEquals(MobileAddSessionState.UNSUPPORTED, rejected.addSessionState)
        assertTrue(rejected.queue.isEmpty())
        assertEquals(1, rejected.addCandidates.size)
        assertEquals(MobileUnsupportedReason.REQUIRES_DESKTOP_EXTRACTOR, rejected.addCandidates.single().unsupportedReason)
        assertTrue(rejected.addUrlState.errorMessage?.contains("直接视频文件链接") == true)
    }

    @Test
    fun candidateSelectionOnlySelectsSupportedMobileCandidates() {
        val supported = MobileVideoCandidate(
            id = "direct",
            sourceURL = "https://cdn.example.com/video.mp4",
            kind = MobileCandidateKind.DIRECT_FILE,
            title = "直接视频",
            detail = "可在手机端处理",
        )
        val unsupported = MobileVideoCandidate(
            id = "web",
            sourceURL = "https://example.com/watch",
            kind = MobileCandidateKind.WEB_PAGE_VIDEO,
            title = "网页视频",
            detail = "需要桌面解析",
            unsupportedReason = MobileUnsupportedReason.REQUIRES_DESKTOP_EXTRACTOR,
        )

        val state = AndroidAppState.live()
            .withCandidateSelection(listOf(unsupported, supported), selectedCandidateID = unsupported.id)
        val selected = state.withSelectedAddCandidate(supported.id)
        val unchanged = selected.withSelectedAddCandidate(unsupported.id)

        assertEquals(MobileAddSessionState.CANDIDATE_SELECTION, state.addSessionState)
        assertEquals(listOf(unsupported, supported), state.addCandidates)
        assertEquals(null, state.selectedAddCandidateID)
        assertEquals(supported.id, selected.selectedAddCandidateID)
        assertEquals(supported.id, unchanged.selectedAddCandidateID)
        assertEquals(null, state.addReadyState)
        assertTrue(state.queue.isEmpty())
    }

    @Test
    fun genericWebUrlClearsPreviouslyStagedReadyMedia() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")

        val rejected = staged.withStagedDirectUrl("https://example.com/watch?v=42")

        assertEquals(null, rejected.addReadyState)
        assertEquals(MobileAddSessionState.UNSUPPORTED, rejected.addSessionState)
        assertTrue(rejected.queue.isEmpty())
        assertTrue(rejected.addUrlState.errorMessage?.contains("直接视频文件链接") == true)
    }

    @Test
    fun uppercaseHttpsDirectMediaUrlStagesBeforeQueueing() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl(" HTTPS://CDN.EXAMPLE.COM/VIDEO.MP4 ")

        assertEquals(AndroidSurface.ADD, staged.selectedSurface)
        assertEquals("VIDEO.MP4", staged.addReadyState?.videoInfo?.title)
        assertEquals("HTTPS://CDN.EXAMPLE.COM/VIDEO.MP4", staged.addReadyState?.downloadRequest?.sourceURL)
        assertEquals(null, staged.addUrlState.errorMessage)
    }

    @Test
    fun failedDirectDownloadUpdatesQueueInsteadOfSilentlyDisappearing() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val item = requireNotNull(staged.addReadyState?.downloadRequest)
            .let { staged.withQueuedDownloadRequest(it) }
            .queue
            .single()

        val failed = staged
            .withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
            .withDownloadFailed(item, "下载失败，请稍后重试。")

        assertEquals(AndroidSurface.QUEUE, failed.selectedSurface)
        assertEquals(AndroidDownloadState.FAILED, failed.queue.single().state)
        assertTrue(failed.queue.single().detail.contains("下载失败"))
        assertFalse(failed.library.any { it.title == item.title })
    }

    @Test
    fun failedDirectDownloadRecoveryPresentationIsActionable() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val item = queued.queue.single()

        val failed = queued.withDownloadFailed(item, "下载没有完成，请检查网络后重试。")
        val failedItem = failed.queue.single()
        val recovery = requireNotNull(failedItem.recoveryPresentation)

        assertEquals(MobileTaskError.NETWORK_UNAVAILABLE, failedItem.error)
        assertEquals("下载没有完成", recovery.title)
        assertTrue(recovery.nextStep.contains("检查网络"))
        assertTrue(recovery.isActionable)
        assertEquals("重试", recovery.actionLabel)
        assertEquals(AndroidQueueRecoveryAction.RETRY_DOWNLOAD, recovery.action)
        assertEquals("重试", failedItem.primaryAction.label)
        assertTrue(failedItem.primaryAction.isEnabled)
        assertTrue(failedItem.primaryAction.helperText?.contains("前台下载") == true)
        assertTrue(failedItem.secondaryActions.any { it.label == "移除" && it.isEnabled })
    }

    @Test
    fun failedDirectDownloadRecoveryPresentationHasRetryAction() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val failedItem = queued
            .withDownloadFailed(queued.queue.single(), "下载没有完成，请检查网络后重试。")
            .queue
            .single()
        val recovery = requireNotNull(failedItem.recoveryPresentation)

        assertEquals("重试", recovery.actionLabel)
        assertEquals(AndroidQueueRecoveryAction.RETRY_DOWNLOAD, recovery.action)
    }

    @Test
    fun missingSourceRecoveryPresentationRoutesToAdd() {
        val item = AndroidDownloadItem(
            id = "restored-download",
            title = "恢复的任务",
            sourceLabel = "移动端任务",
            state = AndroidDownloadState.FAILED,
            detail = "缺少可恢复来源，请重新添加任务。",
            error = MobileTaskError.NETWORK_UNAVAILABLE,
        )
        val recovery = requireNotNull(item.recoveryPresentation)

        assertEquals("重新添加", recovery.actionLabel)
        assertEquals(AndroidQueueRecoveryAction.REOPEN_ADD, recovery.action)
    }

    @Test
    fun projectedBackgroundWorkStatusUpdatesExistingQueueItemWithoutLosingGenerationOrSource() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val item = queued.queue.single()
        val projectedSnapshot = requireNotNull(queued.persistedTaskForQueueItem(item.id)).copy(
            state = MobileTaskState.DOWNLOADING,
            progress = MobileTaskProgress(
                phase = MobileTaskPhase.DOWNLOADING,
                completedUnitCount = 40,
                totalUnitCount = 100,
            ),
            backgroundPolicy = MobileBackgroundPolicy(
                execution = MobileBackgroundExecution.SCHEDULED_WORK,
                resumability = MobileBackgroundResumability.RESUMABLE,
                limits = listOf(MobileBackgroundLimit.USER_VISIBLE_NOTIFICATION_REQUIRED),
            ),
            executionGenerationID = "moongate-generation-observed",
            error = null,
        )

        val projected = queued.withProjectedBackgroundTask(projectedSnapshot)
        val projectedItem = projected.queue.single()
        val persisted = requireNotNull(projected.persistedTaskForQueueItem(item.id))

        assertEquals(AndroidSurface.QUEUE, projected.selectedSurface)
        assertEquals(AndroidDownloadState.DOWNLOADING, projectedItem.state)
        assertEquals(40, projectedItem.progressPercent)
        assertEquals(AndroidBackgroundTaskStatus.TRANSFER_ALLOWED, projectedItem.backgroundStatus)
        assertTrue(projectedItem.detail.contains("后台下载中 40%"))
        assertEquals("https://cdn.example.com/video.mp4", projectedItem.sourceUrlForDownload)
        assertTrue(projectedItem.usesRealDownloader)
        assertEquals("moongate-generation-observed", projectedItem.executionGenerationID)
        assertEquals("moongate-generation-observed", persisted.executionGenerationID)
    }

    @Test
    fun retryingAndCompletingFailedDirectDownloadClearsPreviousError() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val failedItem = queued
            .withDownloadFailed(queued.queue.single(), "下载没有完成，请检查网络后重试。")
            .queue
            .single()

        val retryingItem = queued.withDownloadStarted(failedItem).queue.single()
        val completedItem = queued
            .withDownloadStarted(failedItem)
            .withDownloadedFile(retryingItem, "android-owned:video.mp4", 42L)
            .queue
            .single()

        assertEquals(AndroidDownloadState.DOWNLOADING, retryingItem.state)
        assertEquals(null, retryingItem.error)
        assertEquals(AndroidDownloadState.COMPLETED, completedItem.state)
        assertEquals(null, completedItem.error)
        assertEquals(null, completedItem.recoveryPresentation)
    }

    @Test
    fun completedForegroundDownloadCanPersistAndRestoreQueueAndLibraryRecords() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val item = queued.queue.single()
        val completed = queued.withDownloadedFile(
            item,
            storageUri = "android-owned:video.mp4",
            byteCount = 42L,
        )
        val snapshot = requireNotNull(completed.persistedTaskForQueueItem(item.id))
        val encoded = Json.encodeToString(snapshot)

        assertEquals(MobileTaskState.COMPLETED, snapshot.state)
        assertEquals("android-owned:video.mp4", snapshot.result?.primaryArtifact?.storageIdentifier)
        assertFalse(encoded.contains("https://cdn.example.com/video.mp4"))
        assertFalse(encoded.contains("Authorization"))
        assertFalse(encoded.contains("Bearer "))

        val restored = AndroidAppState.live().withPersistedTasks(listOf(snapshot))

        assertEquals(AndroidSurface.QUEUE, restored.selectedSurface)
        assertEquals(AndroidDownloadState.COMPLETED, restored.queue.single().state)
        assertTrue(restored.queue.single().usesRealDownloader)
        assertEquals("", restored.queue.single().sourceUrlForDownload)
        assertEquals(1, restored.library.size)
        assertEquals(AndroidLibraryAvailability.AVAILABLE, restored.library.single().availability)
        assertTrue(restored.library.single().storageUri?.startsWith("android-owned:") == true)
        assertTrue(restored.library.single().hasVerifiedLocalFile)
    }

    @Test
    fun completedQueueItemPrimaryActionPointsToLibraryInsteadOfDownload() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val completed = queued.withDownloadedFile(
            queued.queue.single(),
            storageUri = "android-owned:video.mp4",
            byteCount = 42L,
        )
        val completedItem = completed.queue.single()

        assertEquals(AndroidDownloadState.COMPLETED, completedItem.state)
        assertEquals("查看资料库", completedItem.primaryAction.label)
        assertEquals(AndroidActionAvailability.ENABLED, completedItem.primaryAction.availability)
        assertFalse(completedItem.isReadyForForegroundDownload())
        assertTrue(completedItem.primaryAction.helperText?.contains("资料库") == true)
    }

    @Test
    fun completedQueueItemDoesNotExposeEnabledNoOpShareSecondaryAction() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val completed = queued.withDownloadedFile(
            queued.queue.single(),
            storageUri = "android-owned:video.mp4",
            byteCount = 42L,
        )
        val completedItem = completed.queue.single()

        assertEquals(AndroidDownloadState.COMPLETED, completedItem.state)
        assertTrue(completedItem.secondaryActions.none { it.label == "分享" && it.queueAction == null })
        assertTrue(completedItem.secondaryActions.any { it.queueAction == AndroidQueueAction.REMOVE })
    }

    @Test
    fun completedTranscriptTaskExposesReachableSubtitleExportQueueAction() {
        val task = completedTaskWithArtifacts(
            exportProfile = MobileExportProfile(
                subtitleMode = MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE,
            ),
            capabilities = MobileProcessingCapabilities(
                platform = MobilePlatform.ANDROID,
                supportedCapabilities = listOf(
                    MobileProcessingCapability.DOWNLOAD,
                    MobileProcessingCapability.TRANSLATION,
                    MobileProcessingCapability.SUBTITLE_EXPORT,
                ),
            ),
            artifacts = listOf(
                originalMediaArtifact(),
                transcriptArtifact(),
            ),
        )
        val state = AndroidAppState.live().withPersistedTasks(listOf(task))
        val item = state.queue.single()

        val exportAction = requireNotNull(
            item.secondaryActions.firstOrNull {
                it.queueAction == AndroidQueueAction.EXPORT_TRANSLATED_SUBTITLE
            },
        )
        val exporting = state.withTranslatedSubtitleExportStarted(item)
        val exportingItem = exporting.queue.single()
        val snapshot = requireNotNull(exporting.persistedTaskForQueueItem(task.id))

        assertEquals("导出字幕", exportAction.label)
        assertTrue(exportAction.isEnabled)
        assertEquals(AndroidDownloadState.TRANSLATING, exportingItem.state)
        assertEquals(AndroidBackgroundTaskStatus.FOREGROUND_ONLY, exportingItem.backgroundStatus)
        assertEquals(MobileTaskError.SYSTEM_BACKGROUND_LIMIT, exportingItem.error)
        assertTrue(exportingItem.detail.contains("保持应用打开"))
        assertEquals(MobileTaskState.TRANSLATING, snapshot.state)
        assertEquals(
            task.result?.artifacts?.map { it.id },
            snapshot.result?.artifacts?.map { it.id },
        )
        assertFalse(
            snapshot.result?.artifacts.orEmpty()
                .any { it.kind == MobileArtifactKind.TRANSLATED_SUBTITLE_FILE },
        )
    }

    @Test
    fun exportStartSanitizesRestoredSensitiveArtifactStorageIdentifiers() {
        val sensitiveStorage = "content://media/doc-999?token=SECRET_TOKEN&Authorization=Bearer%20SECRET"
        val task = completedTaskWithArtifacts(
            id = "content://tasks/export?token=TASK_SECRET&Authorization=Bearer%20TASK",
            exportProfile = MobileExportProfile(
                subtitleMode = MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE,
            ),
            capabilities = MobileProcessingCapabilities(
                platform = MobilePlatform.ANDROID,
                supportedCapabilities = listOf(
                    MobileProcessingCapability.DOWNLOAD,
                    MobileProcessingCapability.TRANSLATION,
                    MobileProcessingCapability.SUBTITLE_EXPORT,
                ),
            ),
            artifacts = listOf(
                originalMediaArtifact(storageIdentifier = sensitiveStorage),
                transcriptArtifact(storageIdentifier = "android-import:doc-123?token=SECRET_TOKEN"),
            ),
        )
        val state = AndroidAppState.live().withPersistedTasks(listOf(task))
        val exporting = state.withTranslatedSubtitleExportStarted(state.queue.single())
        val snapshot = requireNotNull(exporting.persistedTaskForQueueItem(task.id))
        val encodedStorage = snapshot.result?.artifacts.orEmpty()
            .joinToString(separator = "\n") { it.storageIdentifier }

        assertTrue(
            snapshot.result?.artifacts.orEmpty()
                .all { it.storageIdentifier.startsWith("android-sanitized:") },
        )
        assertTrue(snapshot.result?.artifacts.orEmpty().map { it.storageIdentifier }.distinct().size == 1)
        assertFalse(encodedStorage.contains("content://"))
        assertFalse(encodedStorage.contains("token="))
        assertFalse(encodedStorage.contains("SECRET_TOKEN"))
        assertFalse(encodedStorage.contains("TASK_SECRET"))
        assertFalse(encodedStorage.contains("Authorization"))
        assertFalse(encodedStorage.contains("Bearer"))
    }

    @Test
    fun completedBurnedInTaskExposesReachableRenderExportQueueAction() {
        val task = completedTaskWithArtifacts(
            exportProfile = MobileExportProfile(
                subtitleMode = MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE,
            ),
            capabilities = MobileProcessingCapabilities(
                platform = MobilePlatform.ANDROID,
                supportedCapabilities = listOf(
                    MobileProcessingCapability.DOWNLOAD,
                    MobileProcessingCapability.VIDEO_RENDER,
                ),
                maxRenderHeight = 1080,
            ),
            artifacts = listOf(
                originalMediaArtifact(),
                translatedSubtitleArtifact(),
            ),
        )
        val state = AndroidAppState.live().withPersistedTasks(listOf(task))
        val item = state.queue.single()

        val renderAction = requireNotNull(
            item.secondaryActions.firstOrNull {
                it.queueAction == AndroidQueueAction.EXPORT_RENDERED_VIDEO
            },
        )
        val exporting = state.withRenderExportStarted(item)
        val exportingItem = exporting.queue.single()
        val snapshot = requireNotNull(exporting.persistedTaskForQueueItem(task.id))

        assertEquals("生成带字幕视频", renderAction.label)
        assertTrue(renderAction.isEnabled)
        assertEquals(AndroidDownloadState.WAITING_FOR_FOREGROUND, exportingItem.state)
        assertEquals(AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER, exportingItem.backgroundStatus)
        assertEquals(MobileTaskError.SYSTEM_BACKGROUND_LIMIT, exportingItem.error)
        assertTrue(exportingItem.detail.contains("渲染适配器"))
        assertEquals(MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE, snapshot.state)
        assertEquals(
            task.result?.artifacts?.map { it.id },
            snapshot.result?.artifacts?.map { it.id },
        )
        assertFalse(
            snapshot.result?.artifacts.orEmpty()
                .any { it.kind == MobileArtifactKind.RENDERED_VIDEO },
        )
    }

    @Test
    fun activeForegroundDownloadPrimaryCancelIsReachable() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val activeItem = queued
            .withDownloadStarted(queued.queue.single())
            .queue
            .single()

        assertEquals(AndroidDownloadState.DOWNLOADING, activeItem.state)
        assertTrue(activeItem.usesRealDownloader)
        assertEquals("取消", activeItem.primaryAction.label)
        assertEquals(AndroidActionAvailability.ENABLED, activeItem.primaryAction.availability)
        assertTrue(activeItem.primaryAction.helperText?.contains("取消") == true)
    }

    @Test
    fun cancelledActiveForegroundDownloadRestoresAsQueuedNotZombieDownloading() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val activeItem = queued
            .withDownloadStarted(queued.queue.single())
            .queue
            .single()

        val restored = activeItem.restorableAfterCancellation()

        assertEquals(AndroidDownloadState.QUEUED, restored.state)
        assertEquals(null, restored.progressPercent)
        assertTrue(restored.usesRealDownloader)
        assertEquals(AndroidActionAvailability.ENABLED, restored.primaryAction.availability)
        assertTrue(restored.detail.contains("重新开始"))
    }

    @Test
    fun completedForegroundDownloadUsesAppOwnedStorageForSameSessionFileDelete() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val completed = queued.withDownloadedFile(
            queued.queue.single(),
            storageUri = "android-owned:video.mp4",
            byteCount = 42L,
        )

        val item = completed.library.single()

        assertEquals("android-owned:video.mp4", item.storageUri)
        assertTrue(item.hasVerifiedLocalFile)
        assertTrue(item.secondaryActions.any { it.libraryAction == AndroidLibraryAction.DELETE_FILE })
        assertTrue(item.secondaryActions.none { it.libraryAction == AndroidLibraryAction.DELETE_RECORD })
        assertEquals("android-owned:video.mp4", completed.queue.single().completedArtifactStorageIdentifier)
    }

    @Test
    fun deletingCompletedQueueItemAlsoRemovesLibraryProjection() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val completed = queued.withDownloadedFile(
            queued.queue.single(),
            storageUri = "android-owned:video.mp4",
            byteCount = 42L,
        )

        val deleted = completed.withoutQueueItem(completed.queue.single().id)

        assertTrue(deleted.queue.isEmpty())
        assertTrue(deleted.library.isEmpty())
        assertEquals(null, deleted.persistedTaskForQueueItem(completed.queue.single().id))
    }

    @Test
    fun deletingCompletedLibraryItemAlsoRemovesQueueProjection() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val completed = queued.withDownloadedFile(
            queued.queue.single(),
            storageUri = "android-owned:video.mp4",
            byteCount = 42L,
        )

        val deleted = completed.withoutLibraryItem(completed.library.single().id)

        assertTrue(deleted.queue.isEmpty())
        assertTrue(deleted.library.isEmpty())
        assertEquals(null, deleted.persistedTaskForQueueItem(completed.queue.single().id))
    }

    @Test
    fun restoringDeletedLibraryItemAlsoRestoresQueueProjectionAndPersistence() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val completed = queued.withDownloadedFile(
            queued.queue.single(),
            storageUri = "android-owned:video.mp4",
            byteCount = 42L,
        )
        val libraryItem = completed.library.single()
        val deleted = completed.withoutLibraryItem(libraryItem.id)

        val restored = deleted.withRestoredLibraryItem(libraryItem)
        val snapshot = requireNotNull(restored.persistedTaskForQueueItem(completed.queue.single().id))

        assertEquals(1, restored.queue.size)
        assertEquals(1, restored.library.size)
        assertEquals(AndroidDownloadState.COMPLETED, restored.queue.single().state)
        assertEquals("android-owned:video.mp4", restored.queue.single().completedArtifactStorageIdentifier)
        assertEquals("android-owned:video.mp4", snapshot.result?.primaryArtifact?.storageIdentifier)
        assertFalse(Json.encodeToString(snapshot).contains("https://cdn.example.com/video.mp4"))
    }

    @Test
    fun restoredQueuedDirectDownloadDoesNotPretendSourceUrlSurvivedRelaunch() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val snapshot = requireNotNull(queued.persistedTaskForQueueItem(queued.queue.single().id))

        val restored = AndroidAppState.live().withPersistedTasks(listOf(snapshot))
        val restoredItem = restored.queue.single()

        assertEquals(AndroidDownloadState.QUEUED, restoredItem.state)
        assertEquals("", restoredItem.sourceUrlForDownload)
        assertFalse(restoredItem.primaryAction.isEnabled)
        assertTrue(restoredItem.detail.contains("重新添加"))
    }

    @Test
    fun backgroundLimitedQueueItemExplainsForegroundRecovery() {
        val item = AndroidDownloadItem(
            id = "render-1",
            title = "字幕烧录",
            sourceLabel = "本地导入",
            state = AndroidDownloadState.WAITING_FOR_FOREGROUND,
            backgroundStatus = AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER,
            detail = "系统暂停了后台渲染。",
            error = MobileTaskError.SYSTEM_BACKGROUND_LIMIT,
        )
        val recovery = requireNotNull(item.recoveryPresentation)

        assertEquals("保持应用打开", recovery.title)
        assertTrue(recovery.nextStep.contains("回到应用"))
        assertTrue(recovery.isActionable)
        assertEquals("回到前台", recovery.actionLabel)
        assertEquals(AndroidQueueRecoveryAction.RESTART_IN_FOREGROUND, recovery.action)
        assertFalse(item.primaryAction.isEnabled)
        assertTrue(item.secondaryActions.any { it.label == "移除" && it.isEnabled })
    }

    @Test
    fun waitingForForegroundRecoveryPresentationHasTypedAction() {
        val item = AndroidDownloadItem(
            id = "render-1",
            title = "字幕烧录",
            sourceLabel = "本地导入",
            state = AndroidDownloadState.WAITING_FOR_FOREGROUND,
            backgroundStatus = AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER,
            detail = "系统暂停了后台渲染。",
            error = MobileTaskError.SYSTEM_BACKGROUND_LIMIT,
        )
        val recovery = requireNotNull(item.recoveryPresentation)

        assertEquals("回到前台", recovery.actionLabel)
        assertEquals(AndroidQueueRecoveryAction.RESTART_IN_FOREGROUND, recovery.action)
    }

    @Test
    fun repeatedDirectDownloadQueueingUsesUniqueItemIDs() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val request = requireNotNull(staged.addReadyState?.downloadRequest)

        val queued = staged
            .withQueuedDownloadRequest(request)
            .withQueuedDownloadRequest(request)

        assertEquals(2, queued.queue.size)
        assertEquals("${queued.queue[0].id}-2", queued.queue[1].id)
        assertEquals(2, queued.queue.map { it.id }.toSet().size)
    }

    @Test
    fun startingDirectDownloadMarksItemDownloadingToPreventRepeatClicks() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val item = queued.queue.single()

        val downloading = queued.withDownloadStarted(item)

        assertEquals(AndroidDownloadState.DOWNLOADING, downloading.queue.single().state)
        assertEquals(1, downloading.queue.single().progressPercent)
        assertFalse(downloading.queue.single().primaryAction.isEnabled)
        assertTrue(downloading.queue.single().detail.contains("正在下载"))
    }

    @Test
    fun foregroundDownloadProgressUpdatesQueuePercentWithoutCompleting() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val queued = staged.withQueuedDownloadRequest(requireNotNull(staged.addReadyState?.downloadRequest))
        val item = queued.queue.single()

        val progressItem = queued
            .withDownloadStarted(item)
            .withDownloadProgress(item, bytesDownloaded = 50L, totalBytes = 100L)
            .queue
            .single()

        assertEquals(AndroidDownloadState.DOWNLOADING, progressItem.state)
        assertEquals(50, progressItem.progressPercent)
        assertTrue(progressItem.detail.contains("50%"))
        assertTrue(progressItem.usesRealDownloader)
    }

    @Test
    fun sharedTextUrlExtractorTrimsUppercaseAndRejectsNonHttpText() {
        assertEquals(
            "https://example.com/watch?v=42",
            "推荐这个视频 https://example.com/watch?v=42。".firstSharedHttpUrl(),
        )
        assertEquals(
            "http://cdn.example.com/video.mp4",
            "标题\nhttp://cdn.example.com/video.mp4\n备注".firstSharedHttpUrl(),
        )
        assertEquals(
            "HTTPS://EXAMPLE.COM/VIDEO",
            "HTTPS://EXAMPLE.COM/VIDEO".firstSharedHttpUrl(),
        )
        assertEquals(null, "ftp://example.com/file".firstSharedHttpUrl())
        assertEquals(null, "没有链接".firstSharedHttpUrl())
    }

    @Test
    fun importedVideoCreatesCompletedTaskWithoutRawContentUri() {
        val file = AndroidImportedFile(
            id = "doc-123",
            displayName = "clip.mp4",
            mimeType = "video/mp4",
            byteCount = 42L,
        )

        val task = AndroidOfflineFileImportPlanner.taskSnapshot(file)
        val encoded = Json.encodeToString(task)

        assertEquals("android-import-doc-123", task.id)
        assertEquals(MobileTaskState.COMPLETED, task.state)
        assertEquals(MobilePlatform.ANDROID, task.platform)
        assertEquals("android-import:doc-123", task.result?.primaryArtifact?.storageIdentifier)
        assertEquals(MobileArtifactKind.ORIGINAL_MEDIA, task.result?.primaryArtifact?.kind)
        assertFalse(encoded.contains("content://"))
        assertFalse(encoded.contains("file://"))
    }

    @Test
    fun importedSubtitleIsAddedToReadyStateWithoutPersistingRawUri() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")

        val withSubtitle = staged.withImportedSubtitle(
            AndroidImportedFile(
                id = "subtitle-123",
                displayName = "captions.srt",
                mimeType = "application/x-subrip",
                byteCount = 128L,
                contentUri = "content://docs/subtitle-123?token=SECRET_TOKEN",
            ),
        )
        val encoded = Json.encodeToString(requireNotNull(withSubtitle.addReadyState))

        assertEquals(AndroidSurface.ADD, withSubtitle.selectedSurface)
        assertEquals(1, withSubtitle.addReadyState?.manualSubtitles?.size)
        assertEquals("captions.srt", withSubtitle.addReadyState?.manualSubtitles?.single()?.label)
        assertEquals(
            listOf("android-subtitle-subtitle-123"),
            withSubtitle.addReadyState?.selectedManualSubtitleIDs,
        )
        assertFalse(encoded.contains("content://"))
        assertFalse(encoded.contains("SECRET_TOKEN"))
        assertFalse(encoded.contains("token="))
    }

    @Test
    fun importedSubtitleWithoutReadyVideoDoesNotCreateQueueOrPersistRawUri() {
        val state = AndroidAppState.live().withImportedSubtitle(
            AndroidImportedFile(
                id = "subtitle-123",
                displayName = "captions.srt",
                mimeType = "application/x-subrip",
                contentUri = "content://docs/subtitle-123",
            ),
        )
        val encoded = Json.encodeToString(state)

        assertEquals(AndroidSurface.ADD, state.selectedSurface)
        assertEquals(null, state.addReadyState)
        assertTrue(state.queue.isEmpty())
        assertTrue(state.library.isEmpty())
        assertFalse(encoded.contains("content://"))
    }

    @Test
    fun burnedInExportModeIsPreservedWhenQueueingDownloadRequest() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
            .withImportedSubtitle(
                AndroidImportedFile(
                    id = "subtitle-123",
                    displayName = "captions.srt",
                    mimeType = "text/plain",
                ),
            )

        val subtitleFileReady = requireNotNull(staged.addReadyState)
            .withExportMode(AndroidAddExportMode.SUBTITLE_FILE)
        assertEquals(
            MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE,
            subtitleFileReady.downloadRequest.exportProfile.subtitleMode,
        )

        val burnedInReady = subtitleFileReady.withExportMode(AndroidAddExportMode.BURNED_IN_VIDEO)
        val request = burnedInReady.downloadRequest
        val queued = staged.withQueuedDownloadRequest(request)

        assertEquals(MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE, request.exportProfile.subtitleMode)
        assertEquals(MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE, queued.queue.single().exportProfile.subtitleMode)
        assertTrue(queued.queue.single().selectionSummary.contains("带字幕视频"))
    }

    @Test
    fun restoredImportedTaskDoesNotClaimAvailableFileWithoutPersistedUri() {
        val file = AndroidImportedFile(
            id = "doc-123",
            displayName = "clip.mp4",
            mimeType = "video/mp4",
            byteCount = 42L,
        )
        val task = AndroidOfflineFileImportPlanner.taskSnapshot(file)

        val restored = AndroidAppState.live().withPersistedTasks(listOf(task))

        assertEquals(AndroidDownloadState.COMPLETED, restored.queue.single().state)
        assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, restored.queue.single().primaryAction.availability)
        assertEquals(AndroidLibraryAvailability.FILE_MISSING, restored.library.single().availability)
        assertFalse(restored.library.single().hasVerifiedLocalFile)
        assertEquals(null, restored.library.single().storageUri)
    }

    @Test
    fun missingLibraryFileRecoveryPresentationRequestsFileReselection() {
        val file = AndroidImportedFile(
            id = "doc-123",
            displayName = "clip.mp4",
            mimeType = "video/mp4",
            byteCount = 42L,
        )
        val task = AndroidOfflineFileImportPlanner.taskSnapshot(file)

        val item = AndroidAppState.live()
            .withPersistedTasks(listOf(task))
            .library
            .single()
        val recovery = requireNotNull(item.recoveryPresentation)

        assertEquals(AndroidLibraryAvailability.FILE_MISSING, item.availability)
        assertTrue(recovery.isActionable)
        assertEquals("重新选择文件", recovery.actionLabel)
        assertEquals(AndroidLibraryRecoveryAction.RESELECT_FILE, recovery.action)
    }

    @Test
    fun recoveredLibraryContentUriPersistsAsSanitizedContentReference() {
        val missingItem = AndroidLibraryItem(
            id = "library-download-123",
            title = "clip.mp4",
            createdAtLabel = "已恢复",
            artifacts = listOf(
                AndroidLibraryArtifact(
                    id = "downloaded-download-123",
                    kind = AndroidLibraryArtifactKind.ORIGINAL_VIDEO,
                    displayName = "clip.mp4",
                ),
            ),
            availability = AndroidLibraryAvailability.FILE_MISSING,
        )
        val recovered = AndroidAppState.live().withRecoveredLibraryFile(
            item = missingItem,
            file = AndroidImportedFile(
                id = "doc-999",
                displayName = "clip.mp4",
                mimeType = "video/mp4",
                contentUri = "content://media/doc-999",
            ),
        )
        val snapshot = requireNotNull(recovered.persistedTaskForQueueItem("download-123"))
        val encoded = Json.encodeToString(snapshot)

        assertEquals(AndroidLibraryAvailability.AVAILABLE, recovered.library.single().availability)
        assertEquals("content://media/doc-999", recovered.library.single().storageUri)
        assertEquals("android-content:636f6e74656e743a2f2f6d656469612f646f632d393939", snapshot.result?.primaryArtifact?.storageIdentifier)
        assertFalse(encoded.contains("content://"))
        assertFalse(encoded.contains("SECRET_TOKEN"))
        assertFalse(encoded.contains("android-owned:"))

        val restored = AndroidAppState.live().withPersistedTasks(listOf(snapshot))
        assertEquals(AndroidLibraryAvailability.AVAILABLE, restored.library.single().availability)
        assertEquals("content://media/doc-999", restored.library.single().storageUri)
    }

    @Test
    fun recoveredLibraryContentUriWithQueryDoesNotPersistSecretReference() {
        val missingItem = AndroidLibraryItem(
            id = "library-download-123",
            title = "clip.mp4",
            createdAtLabel = "已恢复",
            artifacts = listOf(
                AndroidLibraryArtifact(
                    id = "downloaded-download-123",
                    kind = AndroidLibraryArtifactKind.ORIGINAL_VIDEO,
                    displayName = "clip.mp4",
                ),
            ),
            availability = AndroidLibraryAvailability.FILE_MISSING,
        )
        val recovered = AndroidAppState.live().withRecoveredLibraryFile(
            item = missingItem,
            file = AndroidImportedFile(
                id = "doc-999",
                displayName = "clip.mp4",
                mimeType = "video/mp4",
                contentUri = "content://media/doc-999?token=SECRET_TOKEN",
            ),
        )
        val snapshot = requireNotNull(recovered.persistedTaskForQueueItem("download-123"))
        val encoded = Json.encodeToString(snapshot)

        assertEquals(null, snapshot.result)
        assertFalse(encoded.contains("content://"))
        assertFalse(encoded.contains("SECRET_TOKEN"))
        assertFalse(encoded.contains("android-owned:"))

        val restored = AndroidAppState.live().withPersistedTasks(listOf(snapshot))
        assertTrue(restored.library.isEmpty())
    }

    @Test
    fun permissionDeniedLibraryRecoveryPresentationRequestsFileReselection() {
        val item = AndroidLibraryItem(
            id = "library-permission",
            title = "clip.mp4",
            createdAtLabel = "已恢复",
            artifacts = listOf(
                AndroidLibraryArtifact(
                    id = "downloaded-permission",
                    kind = AndroidLibraryArtifactKind.ORIGINAL_VIDEO,
                    displayName = "clip.mp4",
                ),
            ),
            availability = AndroidLibraryAvailability.PERMISSION_DENIED,
            storageUri = "content://media/doc-999",
        )
        val recovery = requireNotNull(item.recoveryPresentation)

        assertTrue(recovery.isActionable)
        assertEquals(AndroidLibraryRecoveryAction.RESELECT_FILE, recovery.action)
    }

    @Test
    fun importedVideoSanitizesUnsafeIDsBeforeTaskPersistence() {
        val file = AndroidImportedFile(
            id = "content://media/doc-123?token=SECRET_TOKEN",
            displayName = "clip.mp4",
            mimeType = "video/mp4",
            byteCount = 42L,
            contentUri = "content://media/doc-123?token=SECRET_TOKEN",
        )

        val task = AndroidOfflineFileImportPlanner.taskSnapshot(file)
        val encoded = Json.encodeToString(task)

        assertFalse(encoded.contains("content://"))
        assertFalse(encoded.contains("SECRET_TOKEN"))
        assertFalse(encoded.contains("token="))
        assertTrue(task.id.startsWith("android-import-imported-"))
        assertTrue(task.result?.primaryArtifact?.storageIdentifier?.startsWith("android-import:imported-") == true)
    }

    @Test
    fun importedTaskProjectsIntoQueueAndLibrary() {
        val state = AndroidAppState.live().withImportedFile(
            AndroidImportedFile(
                id = "doc-456",
                displayName = "local movie.mov",
                mimeType = "video/quicktime",
                byteCount = 2048L,
                contentUri = "content://media/doc-456",
            ),
            createdAtLabel = "刚刚",
        )

        assertEquals(AndroidSurface.QUEUE, state.selectedSurface)
        assertEquals(1, state.queue.size)
        assertEquals(1, state.library.size)
        assertEquals("local movie.mov", state.queue.single().title)
        assertEquals("本地导入", state.queue.single().sourceLabel)
        assertEquals(AndroidDownloadState.COMPLETED, state.queue.single().state)
        assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, state.queue.single().primaryAction.availability)
        assertEquals("local movie.mov", state.library.single().title)
        assertEquals(AndroidLibraryAvailability.AVAILABLE, state.library.single().availability)
        assertTrue(state.library.single().hasVerifiedLocalFile)
        assertEquals("content://media/doc-456", state.library.single().storageUri)
    }

    @Test
    fun savingAPIKeyReferencePreservesCurrentNavigationAndTaskState() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val request = staged.addReadyState?.downloadRequest
        val imported = requireNotNull(request)
            .let { staged.withQueuedDownloadRequest(it) }
            .withImportedFile(
                AndroidImportedFile(
                    id = "doc-789",
                    displayName = "local movie.mov",
                    mimeType = "video/quicktime",
                    byteCount = 2048L,
                ),
            )
        val reference = SecureCredentialReference(
            service = "translation.android",
            account = "default",
            displayName = "Android Keystore",
        )

        val configured = imported.withAPIKeyReference(reference)

        assertEquals(imported.selectedSurface, configured.selectedSurface)
        assertEquals(imported.addReadyState, configured.addReadyState)
        assertEquals(imported.queue, configured.queue)
        assertEquals(imported.library, configured.library)
        assertEquals(reference, configured.settings.apiKeyReference)
        assertTrue(configured.settings.hasConfiguredAPIKey)
    }

    @Test
    fun deletingAPIKeyReferencePreservesCurrentNavigationAndTaskState() {
        val staged = AndroidAppState.live()
            .withStagedDirectUrl("https://cdn.example.com/video.mp4")
        val request = staged.addReadyState?.downloadRequest
        val imported = requireNotNull(request)
            .let { staged.withQueuedDownloadRequest(it) }
            .withImportedFile(
                AndroidImportedFile(
                    id = "doc-api-delete",
                    displayName = "local movie.mov",
                    mimeType = "video/quicktime",
                    byteCount = 2048L,
                ),
            )
        val reference = SecureCredentialReference(
            service = "translation.android",
            account = "default",
            displayName = "Android Keystore",
        )
        val configured = imported.withAPIKeyReference(reference)
            .withAndroidNotificationPermission(AndroidNotificationPermissionState.GRANTED)

        val cleared = configured.withoutAPIKeyReference()

        assertEquals(configured.selectedSurface, cleared.selectedSurface)
        assertEquals(configured.addReadyState, cleared.addReadyState)
        assertEquals(configured.queue, cleared.queue)
        assertEquals(configured.library, cleared.library)
        assertEquals(
            configured.settings.backgroundRuntimeReadiness,
            cleared.settings.backgroundRuntimeReadiness,
        )
        assertEquals(null, cleared.settings.apiKeyReference)
        assertFalse(cleared.settings.hasConfiguredAPIKey)
    }

    @Test
    fun sharedTextUrlExtractorAcceptsSurroundedHttpText() {
        assertEquals(
            "https://example.com/watch?v=42",
            "推荐这个视频 https://example.com/watch?v=42。".firstSharedHttpUrl(),
        )
        assertEquals(
            "HTTP://EXAMPLE.COM/CLIP.MP4",
            "  打开：HTTP://EXAMPLE.COM/CLIP.MP4  ".firstSharedHttpUrl(),
        )
        assertEquals(null, "ftp://example.com/file".firstSharedHttpUrl())
    }

    @Test
    fun liveSettingsShowsUnavailableLocalTranslationAsStatus() {
        val state = AndroidAppState.live()

        assertEquals("本机翻译", state.settings.localModel.displayName)
        assertFalse(state.settings.localModel.isRunnable)
        assertTrue(state.settings.localModel.readinessIssues.single().contains("云端 API 翻译"))
        assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, state.settings.localModelPrimaryAction.availability)
    }

    @Test
    fun liveSettingsShowsCloudTranslationReadinessWithoutTreatingSavedKeyAsRunnable() {
        val state = AndroidAppState.live()
        val savedKey = SecureCredentialReference(
            service = "translation.android",
            account = "default",
            displayName = "API key 已安全保存",
        )
        val savedKeyOnly = state.withAPIKeyReference(savedKey)

        assertEquals(AndroidCloudTranslationProtocol.OPENAI_COMPATIBLE, state.settings.cloudTranslationReadiness.protocol)
        assertFalse(state.settings.cloudTranslationReadiness.isRunnable)
        assertTrue(state.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("Base URL") })
        assertTrue(state.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("模型") })
        assertTrue(state.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("API key") })
        assertTrue(state.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("执行层") })
        assertEquals(AndroidActionAvailability.NEEDS_CONFIGURATION, state.settings.cloudTranslationAction.availability)
        assertEquals("需要 API key", state.settings.cloudTranslationStatusText)

        assertEquals(savedKey, savedKeyOnly.settings.cloudTranslationReadiness.credentialReference)
        assertFalse(savedKeyOnly.settings.cloudTranslationReadiness.isRunnable)
        assertFalse(savedKeyOnly.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("API key") })
        assertTrue(savedKeyOnly.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("Base URL") })
        assertTrue(savedKeyOnly.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("模型") })
        assertTrue(savedKeyOnly.settings.cloudTranslationReadiness.readinessIssues.any { it.contains("执行层") })
        assertEquals("需要配置", savedKeyOnly.settings.cloudTranslationStatusText)
    }

    @Test
    fun cloudTranslationReadinessProducesMobileConfigurationWithoutSecretValues() {
        val readiness = AndroidCloudTranslationReadiness(
            protocol = AndroidCloudTranslationProtocol.ANTHROPIC_COMPATIBLE,
            baseURL = " https://gateway.example.com/v1 ",
            model = " claude-compatible ",
            credentialReference = SecureCredentialReference(
                service = "translation.android",
                account = "default",
                displayName = "API key 已安全保存",
            ),
            transportRuntimeAvailable = false,
        )
        val configuration = readiness.mobileConfiguration
        val encoded = Json.encodeToString(configuration)

        assertFalse(readiness.isRunnable)
        assertEquals("等待启用", readiness.statusLabel)
        assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, readiness.actionState.availability)
        assertEquals(TranslationEngine.ANTHROPIC_COMPATIBLE, configuration.engine)
        assertEquals("https://gateway.example.com/v1", configuration.baseURL)
        assertEquals("claude-compatible", configuration.model)
        assertFalse(configuration.readiness.isReady)
        assertFalse(encoded.contains("Authorization"))
        assertFalse(encoded.contains("Bearer "))
        assertFalse(encoded.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
    }

    @Test
    fun localTranslationModelStartsUnavailableAndNeedsDownload() {
        val model = AndroidLocalTranslationModel.unavailableDefault()

        assertEquals(AndroidTranslationProvider.LOCAL_MODEL, model.provider)
        assertEquals(AndroidTranslationEngine.ON_DEVICE_PLACEHOLDER, model.engine)
        assertEquals(AndroidModelDownloadState.NOT_DOWNLOADED, model.downloadState)
        assertFalse(model.isRunnable)
        assertTrue(model.statusLabel.contains("未下载"))
    }

    @Test
    fun localModelPlannerQueuesDownloadAndReportsProgress() {
        val model = AndroidLocalTranslationModel.unavailableDefault()

        val plan = AndroidLocalModelPlanner.planDownload(model)
        val queued = AndroidLocalModelPlanner.applyDownloadQueued(model)
        val downloading = AndroidLocalModelPlanner.applyDownloadProgress(
            queued,
            downloadedBytes = 128L,
            totalBytes = 256L,
        )

        assertEquals(AndroidLocalModelAction.DOWNLOAD, plan.action)
        assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, plan.actionState.availability)
        assertEquals(AndroidModelDownloadState.QUEUED, queued.downloadState)
        assertEquals(AndroidModelDownloadState.DOWNLOADING, downloading.downloadState)
        assertEquals(128L, downloading.downloadedBytes)
        assertEquals(256L, downloading.totalBytes)
        assertFalse(downloading.isRunnable)
    }

    @Test
    fun localModelPlannerMarksReadyAndDeleteReturnsToSafeUnavailableState() {
        val ready = AndroidLocalModelPlanner.applyDownloadReady(
            AndroidLocalTranslationModel.unavailableDefault(),
        )
        val settings = AndroidSettingsState.live(localModel = ready)
        val deleted = AndroidLocalModelPlanner.applyDelete(ready)

        assertEquals(AndroidModelDownloadState.READY, ready.downloadState)
        assertTrue(ready.isRunnable)
        assertEquals(AndroidActionAvailability.ENABLED, settings.localModelPrimaryAction.availability)
        assertEquals(AndroidLocalModelAction.DELETE, settings.localModelSecondaryAction?.intent)
        assertEquals(AndroidModelDownloadState.NOT_DOWNLOADED, deleted.downloadState)
        assertFalse(deleted.isRunnable)
        assertEquals(0L, deleted.downloadedBytes)
        assertTrue(deleted.readinessIssues.isNotEmpty())
    }

    @Test
    fun localModelPlannerFailureDoesNotBecomeRunnable() {
        val failed = AndroidLocalModelPlanner.applyDownloadFailure(
            AndroidLocalTranslationModel.unavailableDefault(),
            message = "存储空间不足，无法完成模型下载。",
        )
        val settings = AndroidSettingsState.live(localModel = failed)

        assertEquals(AndroidModelDownloadState.FAILED, failed.downloadState)
        assertFalse(failed.isRunnable)
        assertTrue(failed.readinessIssues.single().contains("存储空间不足"))
        assertEquals(AndroidLocalModelAction.DOWNLOAD, settings.localModelPrimaryAction.intent)
        assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, settings.localModelPrimaryAction.availability)
        assertEquals(null, settings.localModelSecondaryAction)
    }

    @Test
    fun sampleQueueSeparatesBackgroundTransferFromRenderPlaceholder() {
        val state = AndroidAppState.sample()

        assertTrue(state.queue.isNotEmpty())
        assertTrue(state.queue.any { it.backgroundStatus == AndroidBackgroundTaskStatus.TRANSFER_ALLOWED })
        assertTrue(state.queue.any { it.backgroundStatus == AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER })
        assertTrue(state.queue.none { it.usesRealDownloader })
        assertTrue(state.queue.none { it.usesRealRenderer })
        assertTrue(state.queue.all { it.primaryAction.label.isNotBlank() })
        assertTrue(state.queue.all { it.secondaryActions.isNotEmpty() })
        assertEquals("取消", state.queue.first().primaryAction.label)
        assertEquals("继续", state.queue.last().primaryAction.label)
    }

    @Test
    fun libraryItemsExposeMockArtifactsWithoutClaimingLocalFiles() {
        val state = AndroidAppState.sample()
        val item = state.library.first()

        assertEquals(AndroidLibraryAvailability.MOCK_ONLY, item.availability)
        assertFalse(item.hasVerifiedLocalFile)
        assertTrue(item.artifacts.any { it.kind == AndroidLibraryArtifactKind.TRANSLATED_SUBTITLE })
        assertEquals("打开", item.primaryAction.label)
        assertEquals(AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER, item.primaryAction.availability)
        assertTrue(item.secondaryActions.map { it.label }.containsAll(listOf("分享", "保存", "删除记录")))
        assertEquals(AndroidLibraryAction.OPEN, item.primaryAction.libraryAction)
        assertTrue(item.secondaryActions.any { it.libraryAction == AndroidLibraryAction.SHARE })
        assertTrue(item.secondaryActions.any { it.libraryAction == AndroidLibraryAction.SAVE_COPY })
        assertTrue(item.secondaryActions.any { it.libraryAction == AndroidLibraryAction.DELETE_RECORD })
    }

    @Test
    fun verifiedLibraryItemsExposeTypedOpenShareSaveAndDeleteActions() {
        val item = AndroidLibraryItem(
            id = "library-real-1",
            title = "完成视频",
            createdAtLabel = "刚刚",
            artifacts = listOf(
                AndroidLibraryArtifact(
                    id = "artifact-video",
                    kind = AndroidLibraryArtifactKind.ORIGINAL_VIDEO,
                    displayName = "clip.mp4",
                ),
            ),
            availability = AndroidLibraryAvailability.AVAILABLE,
            storageUri = "android-owned:artifact-video",
        )

        assertTrue(item.hasVerifiedLocalFile)
        assertEquals(AndroidActionAvailability.ENABLED, item.primaryAction.availability)
        assertEquals(AndroidLibraryAction.OPEN, item.primaryAction.libraryAction)
        assertEquals(
            listOf(
                AndroidLibraryAction.SHARE,
                AndroidLibraryAction.SAVE_COPY,
                AndroidLibraryAction.DELETE_FILE,
            ),
            item.secondaryActions.map { it.libraryAction },
        )
        assertTrue(item.secondaryActions.all { it.isEnabled })
    }

    @Test
    fun importedContentLibraryItemsOnlyDeleteRecordNotExternalFile() {
        val item = AndroidLibraryItem(
            id = "library-imported-1",
            title = "导入视频",
            createdAtLabel = "刚刚",
            artifacts = listOf(
                AndroidLibraryArtifact(
                    id = "artifact-video",
                    kind = AndroidLibraryArtifactKind.ORIGINAL_VIDEO,
                    displayName = "clip.mp4",
                ),
            ),
            availability = AndroidLibraryAvailability.AVAILABLE,
            storageUri = "content://media/doc-456",
        )

        assertTrue(item.hasVerifiedLocalFile)
        assertTrue(item.secondaryActions.any { it.libraryAction == AndroidLibraryAction.DELETE_RECORD })
        assertTrue(item.secondaryActions.none { it.libraryAction == AndroidLibraryAction.DELETE_FILE })
    }

    private fun completedTaskWithArtifacts(
        id: String = "completed-export-task",
        exportProfile: MobileExportProfile,
        capabilities: MobileProcessingCapabilities,
        artifacts: List<MobileTaskArtifact>,
    ): MobileTaskSnapshot =
        MobileTaskSnapshot(
            id = id,
            platform = MobilePlatform.ANDROID,
            state = MobileTaskState.COMPLETED,
            exportProfile = exportProfile,
            capabilities = capabilities,
            result = MobileTaskResult(
                artifacts = artifacts,
                primaryArtifactID = artifacts.firstOrNull()?.id,
            ),
        )

    private fun originalMediaArtifact(
        storageIdentifier: String = "android-owned:clip.mp4",
    ): MobileTaskArtifact =
        MobileTaskArtifact(
            id = "original",
            kind = MobileArtifactKind.ORIGINAL_MEDIA,
            displayName = "clip.mp4",
            storageIdentifier = storageIdentifier,
        )

    private fun transcriptArtifact(
        storageIdentifier: String = "android-content:7472616e736372697074",
    ): MobileTaskArtifact =
        MobileTaskArtifact(
            id = "transcript",
            kind = MobileArtifactKind.TRANSCRIPT,
            displayName = "clip.en.srt",
            storageIdentifier = storageIdentifier,
        )

    private fun translatedSubtitleArtifact(): MobileTaskArtifact =
        MobileTaskArtifact(
            id = "translated-subtitle",
            kind = MobileArtifactKind.TRANSLATED_SUBTITLE_FILE,
            displayName = "clip.zh.srt",
            storageIdentifier = "android-owned:clip.zh.srt",
        )
}
