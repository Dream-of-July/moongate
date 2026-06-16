package com.moongate.mobile.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import java.net.URI
import java.util.UUID

fun interface AndroidOpaqueIDFactory {
    fun nextID(prefix: String): String
}

object AndroidOpaqueID {
    val factory = AndroidOpaqueIDFactory { prefix -> next(prefix) }

    fun next(prefix: String): String =
        "$prefix-${UUID.randomUUID()}"
}

@Serializable
enum class AndroidSurface {
    @SerialName("add")
    ADD,

    @SerialName("queue")
    QUEUE,

    @SerialName("library")
    LIBRARY,

    @SerialName("settings")
    SETTINGS,
}

val AndroidDefaultSurfaces = listOf(
    AndroidSurface.ADD,
    AndroidSurface.QUEUE,
    AndroidSurface.LIBRARY,
    AndroidSurface.SETTINGS,
)

@Serializable
data class AndroidMockInputState(
    val title: String,
    val helperText: String,
    val isMockOnly: Boolean = true,
    val errorMessage: String? = null,
    val primaryAction: AndroidActionState = AndroidActionState(
        label = "继续",
        availability = AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER,
        statusLabel = "待接入",
    ),
)

@Serializable
enum class AndroidActionAvailability {
    @SerialName("enabled")
    ENABLED,

    @SerialName("needsPlatformAdapter")
    NEEDS_PLATFORM_ADAPTER,

    @SerialName("needsConfiguration")
    NEEDS_CONFIGURATION,

    @SerialName("systemBlocked")
    SYSTEM_BLOCKED,
}

@Serializable
enum class AndroidLibraryAction {
    @SerialName("open")
    OPEN,

    @SerialName("share")
    SHARE,

    @SerialName("saveCopy")
    SAVE_COPY,

    @SerialName("deleteFile")
    DELETE_FILE,

    @SerialName("deleteRecord")
    DELETE_RECORD,
}

@Serializable
enum class AndroidLibraryRecoveryAction {
    @SerialName("reselectFile")
    RESELECT_FILE,
}

@Serializable
enum class AndroidQueueAction {
    @SerialName("exportTranslatedSubtitle")
    EXPORT_TRANSLATED_SUBTITLE,

    @SerialName("exportRenderedVideo")
    EXPORT_RENDERED_VIDEO,

    @SerialName("remove")
    REMOVE,
}

@Serializable
data class AndroidActionState(
    val label: String,
    val availability: AndroidActionAvailability,
    val statusLabel: String,
    val helperText: String? = null,
    val intent: AndroidLocalModelAction? = null,
    val queueAction: AndroidQueueAction? = null,
    val libraryAction: AndroidLibraryAction? = null,
) {
    val isEnabled: Boolean
        get() = availability == AndroidActionAvailability.ENABLED
}

@Serializable
data class AndroidImportedFile(
    val id: String,
    val displayName: String,
    val mimeType: String? = null,
    val byteCount: Long? = null,
    val contentUri: String? = null,
)

object AndroidOfflineFileImportPlanner {
    fun taskSnapshot(file: AndroidImportedFile): MobileTaskSnapshot {
        val safeFileID = sanitizedImportID(file.id)
        val artifact = MobileTaskArtifact(
            id = "original-$safeFileID",
            kind = MobileArtifactKind.ORIGINAL_MEDIA,
            displayName = file.displayName,
            storageIdentifier = "android-import:$safeFileID",
            byteCount = file.byteCount,
        )

        return MobileTaskSnapshot(
            id = "android-import-$safeFileID",
            platform = MobilePlatform.ANDROID,
            state = MobileTaskState.COMPLETED,
            progress = MobileTaskProgress(
                phase = MobileTaskPhase.DOWNLOADING,
                completedUnitCount = 1,
                totalUnitCount = 1,
            ),
            backgroundPolicy = MobileBackgroundPolicy(),
            result = MobileTaskResult(
                artifacts = listOf(artifact),
                primaryArtifactID = artifact.id,
            ),
        )
    }

    private fun sanitizedImportID(value: String): String {
        val trimmed = value.trim()
        val isPlainOpaqueID = trimmed.isNotEmpty() && trimmed.all { character ->
            character.isLetterOrDigit() || character == '-' || character == '_'
        }
        return if (isPlainOpaqueID) {
            trimmed
        } else {
            "imported-${trimmed.hashCode().toUInt()}"
        }
    }
}

@Serializable
enum class AndroidAddExportMode(
    val label: String,
    val detail: String,
    val exportProfile: MobileExportProfile,
) {
    @SerialName("subtitleFile")
    SUBTITLE_FILE(
        label = "字幕文件",
        detail = "生成可单独保存和分享的字幕文件。",
        exportProfile = MobileExportProfile(
            subtitleMode = MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE,
        ),
    ),

    @SerialName("burnedInVideo")
    BURNED_IN_VIDEO(
        label = "带字幕视频",
        detail = "将字幕压进导出视频；当前需要保持应用打开。",
        exportProfile = MobileExportProfile(
            subtitleMode = MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE,
        ),
    ),
}

private fun AndroidImportedFile.importedSubtitleChoice(): MobileSubtitleChoice {
    val safeID = sanitizedAndroidOpaqueID(id)
    val label = displayName.trim().ifBlank { "本地字幕" }
    return MobileSubtitleChoice(
        id = "android-subtitle-$safeID",
        languageCode = "und",
        label = label,
        isAutoGenerated = false,
    )
}

private fun sanitizedAndroidOpaqueID(value: String): String {
    val trimmed = value.trim()
    val isPlainOpaqueID = trimmed.isNotEmpty() && trimmed.all { character ->
        character.isLetterOrDigit() || character == '-' || character == '_'
    }
    return if (isPlainOpaqueID) {
        trimmed
    } else {
        "imported-${trimmed.hashCode().toUInt()}"
    }
}

@Serializable
data class AndroidAddReadyState(
    val sessionID: String,
    val downloadTaskID: String,
    val videoInfo: MobileVideoInfo,
    val selectedFormatID: String? = null,
    val selectedManualSubtitleIDs: List<String> = emptyList(),
    val selectedAutoSubtitleIDs: List<String> = emptyList(),
    val selectedExportMode: AndroidAddExportMode = AndroidAddExportMode.SUBTITLE_FILE,
    val enqueueAction: AndroidActionState = AndroidActionState(
        label = "加入队列",
        availability = AndroidActionAvailability.ENABLED,
        statusLabel = "可加入",
        helperText = "确认格式和字幕后加入下载队列。",
    ),
) {
    val selectedFormat: MobileFormatChoice?
        get() = selectedFormatID?.let { id -> videoInfo.formats.firstOrNull { it.id == id } }
            ?: videoInfo.recommendedFormat

    val manualSubtitles: List<MobileSubtitleChoice>
        get() = videoInfo.subtitles.filter { !it.isAutoGenerated }

    val autoSubtitles: List<MobileSubtitleChoice>
        get() = videoInfo.subtitles.filter { it.isAutoGenerated }

    val selectedManualSubtitles: List<MobileSubtitleChoice>
        get() = selectedManualSubtitleIDs.mapNotNull { id -> manualSubtitles.firstOrNull { it.id == id } }

    val selectedAutoSubtitles: List<MobileSubtitleChoice>
        get() = selectedAutoSubtitleIDs.mapNotNull { id -> autoSubtitles.firstOrNull { it.id == id } }

    val formatLabel: String
        get() = selectedFormat?.label ?: "选择格式"

    val manualSubtitleLabel: String
        get() = selectedManualSubtitles.selectionLabel(emptyLabel = "不使用手动字幕")

    val autoSubtitleLabel: String
        get() = selectedAutoSubtitles.selectionLabel(emptyLabel = "不使用自动字幕")

    val exportMode: AndroidAddExportMode
        get() = selectedExportMode

    val exportModeLabel: String
        get() = exportMode.label

    val canCreateDownloadRequest: Boolean
        get() = selectedFormat != null

    val downloadRequest: MobileDownloadRequest
        get() = MobileDownloadRequest(
            id = downloadTaskID,
            sourceURL = videoInfo.candidate.sourceURL,
            candidateID = videoInfo.candidate.id,
            videoID = videoInfo.videoID,
            formatID = requireNotNull(selectedFormat?.id) { "A selected format is required before enqueueing." },
            subtitleIDs = selectedManualSubtitles.map { it.id },
            autoSubtitleIDs = selectedAutoSubtitles.map { it.id },
            exportProfile = exportMode.exportProfile,
            preferredTitle = videoInfo.title,
        )

    fun withImportedSubtitle(file: AndroidImportedFile): AndroidAddReadyState {
        val importedSubtitle = file.importedSubtitleChoice()
        val filteredSubtitles = videoInfo.subtitles.filterNot { it.id == importedSubtitle.id }
        val selectedManualSubtitleIDs = selectedManualSubtitleIDs + importedSubtitle.id
        return copy(
            videoInfo = videoInfo.copy(subtitles = filteredSubtitles + importedSubtitle),
            selectedManualSubtitleIDs = selectedManualSubtitleIDs.distinct(),
        )
    }

    fun withExportMode(mode: AndroidAddExportMode): AndroidAddReadyState =
        copy(selectedExportMode = mode)

    companion object {
        fun sample(): AndroidAddReadyState =
            AndroidAddReadyState(
                sessionID = "sample-ready",
                downloadTaskID = "download-sample-ready",
                videoInfo = MobileVideoInfo(
                    candidate = MobileVideoCandidate(
                        id = "candidate-sample",
                        sourceURL = "https://cdn.example.com/sample.mp4",
                        kind = MobileCandidateKind.DIRECT_FILE,
                        title = "公开视频样例",
                        detail = "可在手机端处理的媒体链接",
                    ),
                    videoID = "sample-video",
                    title = "公开视频样例",
                    durationSeconds = 242.0,
                    formats = listOf(
                        MobileFormatChoice(
                            id = "1080p",
                            label = "1080p MP4",
                            detail = "高清，适合保存",
                            height = 1080,
                        ),
                        MobileFormatChoice(
                            id = "720p",
                            label = "720p MP4",
                            detail = "体积更小",
                            height = 720,
                        ),
                    ),
                    subtitles = listOf(
                        MobileSubtitleChoice(
                            id = "zh-Hans",
                            languageCode = "zh-Hans",
                            label = "中文字幕",
                            isAutoGenerated = false,
                        ),
                        MobileSubtitleChoice(
                            id = "en",
                            languageCode = "en",
                            label = "英文字幕",
                            isAutoGenerated = false,
                        ),
                        MobileSubtitleChoice(
                            id = "zh-Hans-auto",
                            languageCode = "zh-Hans",
                            label = "自动生成中文",
                            isAutoGenerated = true,
                        ),
                    ),
                ),
                selectedFormatID = "1080p",
                selectedManualSubtitleIDs = listOf("zh-Hans"),
                selectedAutoSubtitleIDs = emptyList(),
            )
    }
}

private fun List<MobileSubtitleChoice>.selectionLabel(emptyLabel: String): String =
    if (isEmpty()) {
        emptyLabel
    } else {
        joinToString { it.label }
    }

private val MobileExportProfile.SubtitleMode.androidSelectionLabel: String
    get() = when (this) {
        MobileExportProfile.SubtitleMode.NONE -> "不导出字幕"
        MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE -> "字幕文件"
        MobileExportProfile.SubtitleMode.SOFT_SUBTITLE -> "字幕文件"
        MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE -> "带字幕视频"
    }

@Serializable
enum class AndroidDownloadState {
    @SerialName("queued")
    QUEUED,

    @SerialName("downloading")
    DOWNLOADING,

    @SerialName("translating")
    TRANSLATING,

    @SerialName("waitingForForeground")
    WAITING_FOR_FOREGROUND,

    @SerialName("completed")
    COMPLETED,

    @SerialName("failed")
    FAILED,
}

@Serializable
enum class AndroidBackgroundTaskStatus {
    @SerialName("foregroundOnly")
    FOREGROUND_ONLY,

    @SerialName("transferAllowed")
    TRANSFER_ALLOWED,

    @SerialName("systemDeferred")
    SYSTEM_DEFERRED,

    @SerialName("renderForegroundOnlyPlaceholder")
    RENDER_FOREGROUND_ONLY_PLACEHOLDER,
}

@Serializable
enum class AndroidQueueRecoveryAction {
    @SerialName("retryDownload")
    RETRY_DOWNLOAD,

    @SerialName("restartInForeground")
    RESTART_IN_FOREGROUND,

    @SerialName("reopenAdd")
    REOPEN_ADD,

    @SerialName("reselectFile")
    RESELECT_FILE,

    @SerialName("openSettings")
    OPEN_SETTINGS,
}

@Serializable
data class AndroidQueueRecoveryPresentation(
    val title: String,
    val nextStep: String,
    val actionLabel: String? = null,
    val action: AndroidQueueRecoveryAction? = null,
    val isActionable: Boolean = action != null,
)

object AndroidQueueRecoveryPresenter {
    fun present(item: AndroidDownloadItem): AndroidQueueRecoveryPresentation? {
        if (item.state == AndroidDownloadState.WAITING_FOR_FOREGROUND) {
            return AndroidQueueRecoveryPresentation(
                title = "保持应用打开",
                nextStep = "回到应用后继续处理；较大的任务可能需要保持屏幕点亮。",
                actionLabel = "回到前台",
                action = AndroidQueueRecoveryAction.RESTART_IN_FOREGROUND,
            )
        }

        if (item.state != AndroidDownloadState.FAILED) {
            return null
        }

        return when (item.error ?: MobileTaskError.UNKNOWN) {
            MobileTaskError.NETWORK_UNAVAILABLE -> AndroidQueueRecoveryPresentation(
                title = "下载没有完成",
                nextStep = "请检查网络后重试。",
                actionLabel = if (item.sourceUrlForDownload.isNotBlank()) "重试" else "重新添加",
                action = if (item.sourceUrlForDownload.isNotBlank()) {
                    AndroidQueueRecoveryAction.RETRY_DOWNLOAD
                } else {
                    AndroidQueueRecoveryAction.REOPEN_ADD
                },
            )

            MobileTaskError.CREDENTIAL_REQUIRED -> AndroidQueueRecoveryPresentation(
                title = "需要登录或凭证",
                nextStep = "在支持登录态恢复前，请换用不需要登录的直接媒体链接。",
                actionLabel = "重新添加",
                action = AndroidQueueRecoveryAction.REOPEN_ADD,
            )

            MobileTaskError.PERMISSION_DENIED -> AndroidQueueRecoveryPresentation(
                title = "缺少文件权限",
                nextStep = "重新选择文件或授予系统文件访问权限。",
                actionLabel = "重新选择",
                action = AndroidQueueRecoveryAction.RESELECT_FILE,
            )

            MobileTaskError.STORAGE_FULL -> AndroidQueueRecoveryPresentation(
                title = "存储空间不足",
                nextStep = "释放空间后再重试下载或导出。",
                actionLabel = if (item.sourceUrlForDownload.isNotBlank()) "重试" else "重新添加",
                action = if (item.sourceUrlForDownload.isNotBlank()) {
                    AndroidQueueRecoveryAction.RETRY_DOWNLOAD
                } else {
                    AndroidQueueRecoveryAction.REOPEN_ADD
                },
            )

            MobileTaskError.SYSTEM_BACKGROUND_LIMIT -> AndroidQueueRecoveryPresentation(
                title = "保持应用打开",
                nextStep = "系统暂停了后台处理，回到应用后继续。",
                actionLabel = "回到前台",
                action = AndroidQueueRecoveryAction.RESTART_IN_FOREGROUND,
            )

            MobileTaskError.EXPORT_FAILED -> AndroidQueueRecoveryPresentation(
                title = "导出失败",
                nextStep = "检查源文件是否仍可访问，再重新导出。",
                actionLabel = "重新选择",
                action = AndroidQueueRecoveryAction.RESELECT_FILE,
            )

            MobileTaskError.UNSUPPORTED_ON_MOBILE -> AndroidQueueRecoveryPresentation(
                title = "手机端暂不支持",
                nextStep = "请换用直接媒体链接，或回到桌面端处理这个来源。",
            )

            MobileTaskError.CANCELLED -> AndroidQueueRecoveryPresentation(
                title = "任务已取消",
                nextStep = "需要时重新添加任务。",
            )

            MobileTaskError.UNKNOWN -> AndroidQueueRecoveryPresentation(
                title = "任务失败",
                nextStep = "请重试；如果仍失败，换一个来源或稍后再试。",
                actionLabel = if (item.sourceUrlForDownload.isNotBlank()) "重试" else "重新添加",
                action = if (item.sourceUrlForDownload.isNotBlank()) {
                    AndroidQueueRecoveryAction.RETRY_DOWNLOAD
                } else {
                    AndroidQueueRecoveryAction.REOPEN_ADD
                },
            )
        }
    }
}

@Serializable
data class AndroidDownloadItem(
    val id: String,
    val title: String,
    val sourceLabel: String,
    val state: AndroidDownloadState,
    val progressPercent: Int? = null,
    val backgroundStatus: AndroidBackgroundTaskStatus = AndroidBackgroundTaskStatus.FOREGROUND_ONLY,
    val backgroundPolicy: MobileBackgroundPolicy = MobileBackgroundPolicy(),
    val detail: String,
    val selectedFormatID: String? = null,
    val selectedSubtitleIDs: List<String> = emptyList(),
    val selectedAutoSubtitleIDs: List<String> = emptyList(),
    val exportProfile: MobileExportProfile = MobileExportProfile(),
    val error: MobileTaskError? = null,
    val completedArtifactStorageIdentifier: String? = null,
    val taskResult: MobileTaskResult? = null,
    val availableTaskActions: List<MobileTaskAction> = emptyList(),
    val executionGenerationID: String? = null,
    @Transient
    val sourceUrlForDownload: String = "",
    val usesRealDownloader: Boolean = false,
    val usesRealRenderer: Boolean = false,
) {
    val isActive: Boolean
        get() = state == AndroidDownloadState.DOWNLOADING ||
            state == AndroidDownloadState.TRANSLATING ||
            state == AndroidDownloadState.WAITING_FOR_FOREGROUND

    val selectionSummary: String
        get() = listOfNotNull(
            selectedFormatID?.let { "已选格式" },
            selectedSubtitleIDs.takeIf { it.isNotEmpty() }?.let { "已选 ${it.size} 个手动字幕" },
            selectedAutoSubtitleIDs.takeIf { it.isNotEmpty() }?.let { "已选 ${it.size} 个自动字幕" },
            exportProfile.subtitleMode.androidSelectionLabel,
        ).ifEmpty {
            listOf("使用默认选择")
        }.joinToString(" · ")

    val recoveryPresentation: AndroidQueueRecoveryPresentation?
        get() = AndroidQueueRecoveryPresenter.present(this)

    val primaryAction: AndroidActionState
        get() = when (state) {
            AndroidDownloadState.QUEUED -> AndroidActionState(
                label = "开始",
                availability = if (sourceUrlForDownload.isNotBlank()) {
                    AndroidActionAvailability.ENABLED
                } else {
                    AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
                },
                statusLabel = if (sourceUrlForDownload.isNotBlank()) {
                    "可前台下载"
                } else {
                    "需要重新添加"
                },
                helperText = if (sourceUrlForDownload.isNotBlank()) {
                    "保持应用在前台，将文件保存到应用文件夹。"
                } else {
                    "这条恢复记录缺少可下载来源，请重新添加链接。"
                },
            )

            AndroidDownloadState.DOWNLOADING,
            AndroidDownloadState.TRANSLATING,
            -> AndroidActionState(
                label = "取消",
                availability = if (state == AndroidDownloadState.DOWNLOADING && usesRealDownloader) {
                    AndroidActionAvailability.ENABLED
                } else {
                    AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
                },
                statusLabel = if (state == AndroidDownloadState.DOWNLOADING && usesRealDownloader) {
                    "可取消"
                } else {
                    "处理进行中"
                },
                helperText = if (state == AndroidDownloadState.DOWNLOADING && usesRealDownloader) {
                    "取消后会停止当前前台下载并移除这条记录。"
                } else {
                    "需要任务控制服务接入后才能取消。"
                },
            )

            AndroidDownloadState.WAITING_FOR_FOREGROUND -> AndroidActionState(
                label = "继续",
                availability = AndroidActionAvailability.SYSTEM_BLOCKED,
                statusLabel = "需回到前台",
                helperText = "系统暂停了后台处理，打开任务后继续。",
            )

            AndroidDownloadState.COMPLETED -> AndroidActionState(
                label = "查看资料库",
                availability = AndroidActionAvailability.ENABLED,
                statusLabel = "已保存",
                helperText = "文件已保存到资料库，请从资料库打开、分享或保存副本。",
            )

            AndroidDownloadState.FAILED -> AndroidActionState(
                label = "重试",
                availability = if (sourceUrlForDownload.isNotBlank()) {
                    AndroidActionAvailability.ENABLED
                } else {
                    AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
                },
                statusLabel = if (sourceUrlForDownload.isNotBlank()) {
                    "可重试"
                } else {
                    "需要重新添加"
                },
                helperText = if (sourceUrlForDownload.isNotBlank()) {
                    "检查网络后可以再次前台下载。"
                } else {
                    "缺少可恢复来源，请重新添加任务。"
                },
            )
        }

    val secondaryActions: List<AndroidActionState>
        get() = when (state) {
            AndroidDownloadState.QUEUED,
            AndroidDownloadState.DOWNLOADING,
            AndroidDownloadState.TRANSLATING,
            AndroidDownloadState.WAITING_FOR_FOREGROUND,
            -> listOf(
                AndroidActionState(
                    label = "移除",
                    availability = if (state == AndroidDownloadState.QUEUED) {
                        AndroidActionAvailability.ENABLED
                    } else {
                        AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
                    },
                    statusLabel = if (state == AndroidDownloadState.QUEUED) "可移除" else "处理中",
                    queueAction = AndroidQueueAction.REMOVE,
                )
            )

            AndroidDownloadState.COMPLETED -> buildList {
                if (availableTaskActions.contains(MobileTaskAction.EXPORT_TRANSLATED_SUBTITLE)) {
                    add(
                        AndroidActionState(
                            label = "导出字幕",
                            availability = AndroidActionAvailability.ENABLED,
                            statusLabel = "可导出",
                            helperText = "生成翻译字幕文件需要保持应用打开。",
                            queueAction = AndroidQueueAction.EXPORT_TRANSLATED_SUBTITLE,
                        ),
                    )
                }
                if (availableTaskActions.contains(MobileTaskAction.EXPORT_RENDERED_VIDEO)) {
                    add(
                        AndroidActionState(
                            label = "生成带字幕视频",
                            availability = AndroidActionAvailability.ENABLED,
                            statusLabel = "需前台处理",
                            helperText = "视频渲染仍需前台和后续运行时适配。",
                            queueAction = AndroidQueueAction.EXPORT_RENDERED_VIDEO,
                        ),
                    )
                }
                add(
                    AndroidActionState(
                        label = "移除",
                        availability = AndroidActionAvailability.ENABLED,
                        statusLabel = "可移除",
                        queueAction = AndroidQueueAction.REMOVE,
                    ),
                )
            }

            AndroidDownloadState.FAILED -> listOf(
                AndroidActionState(
                    label = "移除",
                    availability = AndroidActionAvailability.ENABLED,
                    statusLabel = "可移除",
                    queueAction = AndroidQueueAction.REMOVE,
                )
            )
        }

    fun taskSnapshot(): MobileTaskSnapshot {
        val result = taskResult?.sanitizedForAndroidTaskSnapshot(id) ?: if (completedArtifactStorageIdentifier != null) {
            MobileTaskResult(
                artifacts = listOf(
                    MobileTaskArtifact(
                        id = "downloaded-$id",
                        kind = MobileArtifactKind.ORIGINAL_MEDIA,
                        displayName = title,
                        storageIdentifier = completedArtifactStorageIdentifier.sanitizedAndroidArtifactStorageIdentifier(id),
                    ),
                ),
                primaryArtifactID = "downloaded-$id",
            )
        } else {
            null
        }

        return MobileTaskSnapshot(
            id = id,
            platform = MobilePlatform.ANDROID,
            state = mobileTaskState,
            progress = progressPercent?.let { percent ->
                MobileTaskProgress(
                    phase = MobileTaskPhase.DOWNLOADING,
                    completedUnitCount = percent.coerceIn(0, 100),
                    totalUnitCount = 100,
                )
            } ?: MobileTaskProgress(),
            backgroundPolicy = effectiveBackgroundPolicy,
            executionGenerationID = executionGenerationID,
            result = result,
            exportProfile = exportProfile,
            capabilities = capabilitiesForTaskSnapshot,
            error = error,
        )
    }

    fun isReadyForForegroundDownload(): Boolean =
        state == AndroidDownloadState.QUEUED || state == AndroidDownloadState.FAILED

    companion object {
        fun fromDownloadRequest(request: MobileDownloadRequest): AndroidDownloadItem =
            AndroidDownloadItem(
                id = request.id,
                title = request.preferredTitle ?: "下载任务",
                sourceLabel = "移动端任务",
                state = AndroidDownloadState.QUEUED,
                detail = "已保留所选格式和字幕，等待开始下载。",
                selectedFormatID = request.formatID,
                selectedSubtitleIDs = request.subtitleIDs,
                selectedAutoSubtitleIDs = request.autoSubtitleIDs,
                exportProfile = request.exportProfile,
                sourceUrlForDownload = request.sourceURL,
            )

        fun fromTaskSnapshot(task: MobileTaskSnapshot): AndroidDownloadItem {
            val primaryArtifact = task.result?.primaryArtifact
            return AndroidDownloadItem(
                id = task.id,
                title = primaryArtifact?.displayName ?: "未命名视频",
                sourceLabel = if (primaryArtifact?.storageIdentifier?.isAndroidLocalContentStorage == true) {
                    "本地导入"
                } else {
                    "移动端任务"
                },
                state = task.androidDownloadState,
                progressPercent = task.progress.fractionCompleted?.let { (it * 100).toInt() },
                backgroundStatus = task.androidBackgroundTaskStatus,
                backgroundPolicy = task.backgroundPolicy,
                exportProfile = task.exportProfile,
                error = task.error,
                detail = task.androidRestoredDetail,
                usesRealDownloader = primaryArtifact?.storageIdentifier?.startsWith("android-owned:") == true,
                usesRealRenderer = task.result?.artifacts.orEmpty()
                    .any { it.kind == MobileArtifactKind.RENDERED_VIDEO },
                completedArtifactStorageIdentifier = primaryArtifact?.storageIdentifier,
                taskResult = task.result,
                availableTaskActions = task.availableActions,
                executionGenerationID = task.executionGenerationID,
            )
        }

        fun fromLibraryItem(item: AndroidLibraryItem): AndroidDownloadItem {
            val taskID = item.id.removePrefix("library-")
            val appOwnedStorage = item.storageUri?.takeIf { it.startsWith("android-owned:") }
            val contentStorage = item.storageUri?.androidPersistableContentStorageIdentifier
            val importStorage = taskID
                .takeIf { it.startsWith("android-import-") }
                ?.removePrefix("android-import-")
                ?.let { "android-import:$it" }
            val storageIdentifier = appOwnedStorage ?: contentStorage ?: importStorage
            return AndroidDownloadItem(
                id = taskID,
                title = item.title,
                sourceLabel = if (storageIdentifier?.isAndroidLocalContentStorage == true) {
                    "本地导入"
                } else {
                    "移动端任务"
                },
                state = AndroidDownloadState.COMPLETED,
                progressPercent = 100,
                detail = if (appOwnedStorage != null) {
                    "文件已保存，可在资料库打开或分享。"
                } else {
                    "记录已恢复；如果文件位置不可用，请重新导入。"
                },
                usesRealDownloader = appOwnedStorage != null,
                completedArtifactStorageIdentifier = storageIdentifier,
                taskResult = storageIdentifier?.let {
                    val artifact = MobileTaskArtifact(
                        id = "downloaded-$taskID",
                        kind = MobileArtifactKind.ORIGINAL_MEDIA,
                        displayName = item.title,
                        storageIdentifier = it,
                    )
                    MobileTaskResult(
                        artifacts = listOf(artifact),
                        primaryArtifactID = artifact.id,
                    )
                },
                availableTaskActions = listOf(
                    MobileTaskAction.OPEN_RESULT,
                    MobileTaskAction.SHARE_RESULT,
                    MobileTaskAction.REMOVE,
                ),
            )
        }
    }
}

private fun MobileTaskResult.sanitizedForAndroidTaskSnapshot(taskID: String): MobileTaskResult =
    copy(
        artifacts = artifacts.map { artifact ->
            artifact.copy(
                storageIdentifier = artifact.storageIdentifier.sanitizedAndroidArtifactStorageIdentifier(taskID),
            )
        },
    )

private fun String.sanitizedAndroidArtifactStorageIdentifier(taskID: String): String =
    when {
        startsWith("android-owned:") && removePrefix("android-owned:").isSafeAndroidStoragePayload(
            allowDot = true,
        ) -> this
        startsWith("android-import:") && removePrefix("android-import:").isSafeAndroidStoragePayload(
            allowDot = false,
        ) -> this
        startsWith("android-content:") && removePrefix("android-content:").isSafeAndroidHexPayload() -> this
        else -> "android-sanitized:${taskID.hashCode().toUInt()}"
    }

private fun String.isSafeAndroidStoragePayload(allowDot: Boolean): Boolean =
    isNotBlank() && all { character ->
        character.isLetterOrDigit() ||
            character == '-' ||
            character == '_' ||
            (allowDot && character == '.')
    }

private fun String.isSafeAndroidHexPayload(): Boolean =
    isNotBlank() && all { character ->
        character in '0'..'9' || character in 'a'..'f' || character in 'A'..'F'
    }

private val AndroidDownloadItem.capabilitiesForTaskSnapshot: MobileProcessingCapabilities
    get() {
        val capabilities = mutableListOf<MobileProcessingCapability>()
        if (usesRealDownloader || completedArtifactStorageIdentifier != null) {
            capabilities.add(MobileProcessingCapability.DOWNLOAD)
        }
        if (usesRealRenderer) {
            capabilities.add(MobileProcessingCapability.VIDEO_RENDER)
        }
        if (availableTaskActions.contains(MobileTaskAction.EXPORT_TRANSLATED_SUBTITLE)) {
            capabilities.add(MobileProcessingCapability.TRANSLATION)
            capabilities.add(MobileProcessingCapability.SUBTITLE_EXPORT)
        }
        if (availableTaskActions.contains(MobileTaskAction.EXPORT_RENDERED_VIDEO)) {
            capabilities.add(MobileProcessingCapability.VIDEO_RENDER)
        }
        return MobileProcessingCapabilities(
            platform = MobilePlatform.ANDROID,
            supportedCapabilities = capabilities.distinct(),
            maxRenderHeight = exportProfile.maxRenderHeight,
        )
    }

fun AndroidDownloadItem.restorableAfterCancellation(): AndroidDownloadItem =
    if (isActive && usesRealDownloader) {
        copy(
            state = AndroidDownloadState.QUEUED,
            progressPercent = null,
            detail = "下载已取消，可重新开始前台下载。",
            error = null,
        )
    } else {
        this
    }
}

fun AndroidDownloadItem.appOwnedDownloadFileName(): String {
    val safeID = id.safeAndroidFileNamePart()
    val safeTitle = title.safeAndroidFileNamePart()
    return "$safeID-$safeTitle".take(128)
}

private fun String.safeAndroidFileNamePart(): String {
    val normalized = map { character ->
        if (character.isLetterOrDigit() || character == '.' || character == '-' || character == '_') {
            character
        } else {
            '-'
        }
    }.joinToString("")
        .trim('-')
        .takeIf { it.isNotBlank() }
        ?: "downloaded-video"
    return normalized.take(96)
}

private val AndroidDownloadItem.mobileTaskState: MobileTaskState
    get() = when (state) {
        AndroidDownloadState.QUEUED -> MobileTaskState.WAITING
        AndroidDownloadState.DOWNLOADING -> MobileTaskState.DOWNLOADING
        AndroidDownloadState.TRANSLATING -> MobileTaskState.TRANSLATING
        AndroidDownloadState.WAITING_FOR_FOREGROUND -> MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE
        AndroidDownloadState.COMPLETED -> MobileTaskState.COMPLETED
        AndroidDownloadState.FAILED -> MobileTaskState.FAILED
    }

private val AndroidDownloadItem.effectiveBackgroundPolicy: MobileBackgroundPolicy
    get() = when (state) {
        AndroidDownloadState.DOWNLOADING,
        AndroidDownloadState.TRANSLATING,
        AndroidDownloadState.WAITING_FOR_FOREGROUND,
        -> if (backgroundPolicy != MobileBackgroundPolicy()) {
            backgroundPolicy
        } else {
            MobileBackgroundPolicy(
                execution = MobileBackgroundExecution.FOREGROUND_REQUIRED,
                resumability = MobileBackgroundResumability.RESUMABLE,
                limits = listOf(MobileBackgroundLimit.FOREGROUND_REQUIRED),
            )
        }

        else -> backgroundPolicy
    }

private val MobileTaskSnapshot.androidRestoredDetail: String
    get() = when (state) {
        MobileTaskState.COMPLETED -> "本地文件已加入资料库，可继续处理字幕或导出。"
        MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE -> "任务从上次会话恢复；请保持应用打开继续。"
        MobileTaskState.FAILED,
        MobileTaskState.CANCELLED,
        -> "任务状态已从移动端队列恢复。"

        else -> "任务记录已恢复；如缺少来源，请重新添加链接。"
    }

private val MobileTaskSnapshot.androidDownloadState: AndroidDownloadState
    get() = when (state) {
        MobileTaskState.WAITING,
        MobileTaskState.READY,
        MobileTaskState.ANALYZING,
        -> AndroidDownloadState.QUEUED

        MobileTaskState.DOWNLOADING -> AndroidDownloadState.DOWNLOADING
        MobileTaskState.TRANSLATING -> AndroidDownloadState.TRANSLATING
        MobileTaskState.EXPORTING,
        MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE,
        -> AndroidDownloadState.WAITING_FOR_FOREGROUND

        MobileTaskState.COMPLETED -> AndroidDownloadState.COMPLETED
        MobileTaskState.FAILED -> AndroidDownloadState.FAILED
        MobileTaskState.CANCELLED -> AndroidDownloadState.FAILED
    }

private fun Long.androidByteCountLabel(): String =
    when {
        this >= 1024L * 1024L -> "${this / (1024L * 1024L)} MB"
        this >= 1024L -> "${this / 1024L} KB"
        else -> "$this B"
    }

@Serializable
enum class AndroidLibraryArtifactKind {
    @SerialName("originalVideo")
    ORIGINAL_VIDEO,

    @SerialName("translatedSubtitle")
    TRANSLATED_SUBTITLE,

    @SerialName("renderedVideo")
    RENDERED_VIDEO,
}

@Serializable
data class AndroidLibraryArtifact(
    val id: String,
    val kind: AndroidLibraryArtifactKind,
    val displayName: String,
)

@Serializable
enum class AndroidLibraryAvailability {
    @SerialName("mockOnly")
    MOCK_ONLY,

    @SerialName("available")
    AVAILABLE,

    @SerialName("fileMissing")
    FILE_MISSING,

    @SerialName("permissionDenied")
    PERMISSION_DENIED,
}

@Serializable
data class AndroidLibraryRecoveryPresentation(
    val title: String,
    val nextStep: String,
    val actionLabel: String? = null,
    val action: AndroidLibraryRecoveryAction? = null,
) {
    val isActionable: Boolean
        get() = action != null
}

object AndroidLibraryRecoveryPresenter {
    fun present(item: AndroidLibraryItem): AndroidLibraryRecoveryPresentation? =
        when (item.availability) {
            AndroidLibraryAvailability.FILE_MISSING -> AndroidLibraryRecoveryPresentation(
                title = "找不到文件",
                nextStep = "重新选择原文件后，可以继续打开、分享或保存副本。",
                actionLabel = "重新选择文件",
                action = AndroidLibraryRecoveryAction.RESELECT_FILE,
            )

            AndroidLibraryAvailability.PERMISSION_DENIED -> AndroidLibraryRecoveryPresentation(
                title = "需要文件权限",
                nextStep = "重新授权文件访问后，可以继续处理这条记录。",
                actionLabel = "重新选择文件",
                action = AndroidLibraryRecoveryAction.RESELECT_FILE,
            )

            AndroidLibraryAvailability.AVAILABLE,
            AndroidLibraryAvailability.MOCK_ONLY,
            -> null
        }
}

@Serializable
data class AndroidLibraryItem(
    val id: String,
    val title: String,
    val createdAtLabel: String,
    val artifacts: List<AndroidLibraryArtifact>,
    val availability: AndroidLibraryAvailability = AndroidLibraryAvailability.MOCK_ONLY,
    val storageUri: String? = null,
) {
    val hasVerifiedLocalFile: Boolean
        get() = availability == AndroidLibraryAvailability.AVAILABLE && storageUri != null

    val recoveryPresentation: AndroidLibraryRecoveryPresentation?
        get() = AndroidLibraryRecoveryPresenter.present(this)

    val primaryAction: AndroidActionState
        get() = AndroidActionState(
            label = "打开",
            availability = if (hasVerifiedLocalFile) {
                AndroidActionAvailability.ENABLED
            } else {
                AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
            },
            statusLabel = when (availability) {
                AndroidLibraryAvailability.AVAILABLE -> if (hasVerifiedLocalFile) "可打开" else "需要文件位置"
                AndroidLibraryAvailability.MOCK_ONLY -> "需要文件位置"
                AndroidLibraryAvailability.FILE_MISSING -> "文件缺失"
                AndroidLibraryAvailability.PERMISSION_DENIED -> "需要权限"
            },
            helperText = "真实文件可用后会打开系统预览。",
            libraryAction = AndroidLibraryAction.OPEN,
        )

    val secondaryActions: List<AndroidActionState>
        get() {
            return listOf(
                AndroidActionState(
                    label = "分享",
                    availability = if (hasVerifiedLocalFile) {
                        AndroidActionAvailability.ENABLED
                    } else {
                        AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
                    },
                    statusLabel = if (hasVerifiedLocalFile) "可分享" else primaryAction.statusLabel,
                    libraryAction = AndroidLibraryAction.SHARE,
                ),
                AndroidActionState(
                    label = "保存",
                    availability = if (hasVerifiedLocalFile) {
                        AndroidActionAvailability.ENABLED
                    } else {
                        AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
                    },
                    statusLabel = if (hasVerifiedLocalFile) "可保存" else primaryAction.statusLabel,
                    libraryAction = AndroidLibraryAction.SAVE_COPY,
                ),
                if (canDeleteAppOwnedFile) {
                    AndroidActionState(
                        label = "删除文件",
                        availability = AndroidActionAvailability.ENABLED,
                        statusLabel = "可删除",
                        libraryAction = AndroidLibraryAction.DELETE_FILE,
                    )
                } else {
                    AndroidActionState(
                        label = "删除记录",
                        availability = AndroidActionAvailability.ENABLED,
                        statusLabel = "可删除",
                        libraryAction = AndroidLibraryAction.DELETE_RECORD,
                    )
                },
            )
        }

    private val canDeleteAppOwnedFile: Boolean
        get() = hasVerifiedLocalFile && storageUri?.startsWith("android-owned:") == true

    companion object {
        fun fromTaskSnapshot(task: MobileTaskSnapshot, createdAtLabel: String): AndroidLibraryItem? {
            if (task.state != MobileTaskState.COMPLETED) {
                return null
            }
            val artifacts = task.result?.artifacts.orEmpty()
                .mapNotNull { artifact -> artifact.androidLibraryArtifact() }
            if (artifacts.isEmpty()) {
                return null
            }
            val primaryArtifact = task.result?.primaryArtifact
            val storageUri = primaryArtifact?.androidOwnedStorageUri
                ?: primaryArtifact?.androidContentStorageUri
            return AndroidLibraryItem(
                id = "library-${task.id}",
                title = primaryArtifact?.displayName ?: "未命名视频",
                createdAtLabel = createdAtLabel,
                artifacts = artifacts,
                availability = if (storageUri != null) {
                    AndroidLibraryAvailability.AVAILABLE
                } else {
                    AndroidLibraryAvailability.FILE_MISSING
                },
                storageUri = storageUri,
            )
        }
    }

    fun withStorageUri(storageUri: String?): AndroidLibraryItem =
        if (storageUri.isNullOrBlank()) {
            copy(availability = AndroidLibraryAvailability.FILE_MISSING, storageUri = null)
        } else {
            copy(availability = AndroidLibraryAvailability.AVAILABLE, storageUri = storageUri)
        }
}

private val String.isAndroidLocalContentStorage: Boolean
    get() = startsWith("android-import:") || startsWith("android-content:")

private val String.androidPersistableContentStorageIdentifier: String?
    get() {
        if (!startsWith("content://")) {
            return null
        }
        if (contains('?') || contains('#')) {
            return null
        }
        return "android-content:${encodeAndroidHex()}"
    }

private val String.androidPersistedContentStorageUri: String?
    get() {
        val encoded = removePrefix("android-content:")
        if (encoded == this || encoded.isBlank() || encoded.length % 2 != 0) {
            return null
        }
        val decoded = encoded.chunked(2)
            .map { byte ->
                byte.toIntOrNull(16)?.toChar() ?: return null
            }
            .joinToString("")
        return decoded.takeIf { it.startsWith("content://") && !it.contains('?') && !it.contains('#') }
    }

private fun String.encodeAndroidHex(): String =
    encodeToByteArray().joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

private val MobileTaskArtifact.androidOwnedStorageUri: String?
    get() {
        val fileName = storageIdentifier.removePrefix("android-owned:")
        if (fileName == storageIdentifier || fileName.isBlank()) {
            return null
        }
        return "android-owned:$fileName"
    }

private val MobileTaskArtifact.androidContentStorageUri: String?
    get() = storageIdentifier.androidPersistedContentStorageUri

private fun MobileTaskArtifact.androidLibraryArtifact(): AndroidLibraryArtifact? {
    val kind = when (kind) {
        MobileArtifactKind.ORIGINAL_MEDIA -> AndroidLibraryArtifactKind.ORIGINAL_VIDEO
        MobileArtifactKind.TRANSLATED_SUBTITLE_FILE,
        MobileArtifactKind.TRANSCRIPT,
        MobileArtifactKind.SOFT_SUBTITLE,
        -> AndroidLibraryArtifactKind.TRANSLATED_SUBTITLE

        MobileArtifactKind.RENDERED_VIDEO -> AndroidLibraryArtifactKind.RENDERED_VIDEO
        MobileArtifactKind.METADATA -> return null
    }
    return AndroidLibraryArtifact(
        id = id,
        kind = kind,
        displayName = displayName,
    )
}

@Serializable
enum class AndroidTranslationProvider {
    @SerialName("cloudApi")
    CLOUD_API,

    @SerialName("localModel")
    LOCAL_MODEL,
}

@Serializable
enum class AndroidTranslationEngine {
    @SerialName("apiKeyPlaceholder")
    API_KEY_PLACEHOLDER,

    @SerialName("onDevicePlaceholder")
    ON_DEVICE_PLACEHOLDER,
}

@Serializable
enum class AndroidCloudTranslationProtocol {
    @SerialName("openAICompatible")
    OPENAI_COMPATIBLE,

    @SerialName("anthropicCompatible")
    ANTHROPIC_COMPATIBLE,
}

val AndroidCloudTranslationProtocol.label: String
    get() = when (this) {
        AndroidCloudTranslationProtocol.OPENAI_COMPATIBLE -> "OpenAI-compatible"
        AndroidCloudTranslationProtocol.ANTHROPIC_COMPATIBLE -> "Anthropic-compatible"
    }

val AndroidCloudTranslationProtocol.translationEngine: TranslationEngine
    get() = when (this) {
        AndroidCloudTranslationProtocol.OPENAI_COMPATIBLE -> TranslationEngine.OPENAI_COMPATIBLE
        AndroidCloudTranslationProtocol.ANTHROPIC_COMPATIBLE -> TranslationEngine.ANTHROPIC_COMPATIBLE
    }

@Serializable
data class AndroidCloudTranslationReadiness(
    val protocol: AndroidCloudTranslationProtocol = AndroidCloudTranslationProtocol.OPENAI_COMPATIBLE,
    val baseURL: String? = null,
    val model: String? = null,
    val credentialReference: SecureCredentialReference? = null,
    val transportRuntimeAvailable: Boolean = false,
) {
    val readinessIssues: List<String>
        get() = buildList {
            if (baseURL.normalizedSettingValue() == null) {
                add("需要填写 Base URL。")
            }
            if (model.normalizedSettingValue() == null) {
                add("需要选择或填写模型。")
            }
            if (credentialReference == null) {
                add("需要先保存 API key。")
            }
            if (!transportRuntimeAvailable) {
                add("云端翻译请求执行层尚未启用。")
            }
        }

    val isRunnable: Boolean
        get() = readinessIssues.isEmpty()

    val statusLabel: String
        get() = when {
            isRunnable -> "可用"
            credentialReference == null -> "需要 API key"
            baseURL.normalizedSettingValue() == null || model.normalizedSettingValue() == null -> "需要配置"
            else -> "等待启用"
        }

    val detailText: String
        get() = readinessIssues.firstOrNull()
            ?: "${protocol.label} 已准备好，可用于字幕翻译。"

    val actionState: AndroidActionState
        get() = AndroidActionState(
            label = when {
                isRunnable -> "云端翻译可用"
                credentialReference == null -> "保存 API key"
                baseURL.normalizedSettingValue() == null || model.normalizedSettingValue() == null ->
                    "配置云端翻译"
                else -> "等待启用"
            },
            availability = when {
                isRunnable -> AndroidActionAvailability.SYSTEM_BLOCKED
                !transportRuntimeAvailable &&
                    credentialReference != null &&
                    baseURL.normalizedSettingValue() != null &&
                    model.normalizedSettingValue() != null ->
                    AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER
                else -> AndroidActionAvailability.NEEDS_CONFIGURATION
            },
            statusLabel = statusLabel,
            helperText = detailText,
        )

    val mobileConfiguration: MobileTranslationConfiguration
        get() = MobileTranslationConfiguration(
            engine = protocol.translationEngine,
            baseURL = baseURL.normalizedSettingValue(),
            model = model.normalizedSettingValue(),
            credential = credentialReference,
            readiness = TranslationReadiness(
                issues = readinessIssues.map { issue ->
                    TranslationReadinessIssue(
                        kind = if (issue.contains("执行层")) {
                            TranslationReadinessIssue.Kind.NEEDS_RUNTIME_VERIFICATION
                        } else {
                            TranslationReadinessIssue.Kind.NEEDS_CONFIGURATION
                        },
                        message = issue,
                    )
                },
            ),
        )

    fun withCredentialReference(reference: SecureCredentialReference?): AndroidCloudTranslationReadiness =
        copy(credentialReference = reference)
}

private fun String?.normalizedSettingValue(): String? =
    this?.trim()?.takeIf { it.isNotEmpty() }

@Serializable
enum class AndroidModelDownloadState {
    @SerialName("notDownloaded")
    NOT_DOWNLOADED,

    @SerialName("queued")
    QUEUED,

    @SerialName("downloading")
    DOWNLOADING,

    @SerialName("ready")
    READY,

    @SerialName("failed")
    FAILED,
}

@Serializable
enum class AndroidLocalModelAction {
    @SerialName("download")
    DOWNLOAD,

    @SerialName("delete")
    DELETE,
}

@Serializable
data class AndroidLocalModelPlan(
    val action: AndroidLocalModelAction,
    val actionState: AndroidActionState,
)

object AndroidLocalModelPlanner {
    fun planDownload(model: AndroidLocalTranslationModel): AndroidLocalModelPlan {
        val actionState = when (model.downloadState) {
            AndroidModelDownloadState.NOT_DOWNLOADED -> AndroidActionState(
                label = "下载模型",
                availability = AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER,
                statusLabel = "等待模型下载服务",
                helperText = "需要先接入模型下载、校验和存储配额检查。",
                intent = AndroidLocalModelAction.DOWNLOAD,
            )

            AndroidModelDownloadState.QUEUED -> AndroidActionState(
                label = "下载模型",
                availability = AndroidActionAvailability.SYSTEM_BLOCKED,
                statusLabel = "等待下载",
                helperText = "模型下载已排队，系统会显示进度和失败原因。",
                intent = AndroidLocalModelAction.DOWNLOAD,
            )

            AndroidModelDownloadState.DOWNLOADING -> AndroidActionState(
                label = "下载模型",
                availability = AndroidActionAvailability.SYSTEM_BLOCKED,
                statusLabel = "下载中",
                helperText = "模型文件下载和校验完成前不能作为翻译引擎使用。",
                intent = AndroidLocalModelAction.DOWNLOAD,
            )

            AndroidModelDownloadState.READY -> AndroidActionState(
                label = "使用本地模型",
                availability = AndroidActionAvailability.ENABLED,
                statusLabel = "可用",
                helperText = "本机翻译可用后会优先使用本地模型。",
                intent = AndroidLocalModelAction.DOWNLOAD,
            )

            AndroidModelDownloadState.FAILED -> AndroidActionState(
                label = "重新下载模型",
                availability = AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER,
                statusLabel = "下载失败",
                helperText = model.readinessIssues.firstOrNull() ?: "模型下载失败，请重试。",
                intent = AndroidLocalModelAction.DOWNLOAD,
            )
        }
        return AndroidLocalModelPlan(
            action = AndroidLocalModelAction.DOWNLOAD,
            actionState = actionState,
        )
    }

    fun planDelete(model: AndroidLocalTranslationModel): AndroidLocalModelPlan? {
        if (model.downloadState != AndroidModelDownloadState.READY) {
            return null
        }
        return AndroidLocalModelPlan(
            action = AndroidLocalModelAction.DELETE,
            actionState = AndroidActionState(
                label = "删除模型",
                availability = AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER,
                statusLabel = "可删除",
                helperText = "需要本地模型存储服务接入后才能删除文件。",
                intent = AndroidLocalModelAction.DELETE,
            ),
        )
    }

    fun applyDownloadQueued(model: AndroidLocalTranslationModel): AndroidLocalTranslationModel =
        model.copy(
            downloadState = AndroidModelDownloadState.QUEUED,
            downloadedBytes = 0L,
            readinessIssues = listOf("模型下载已排队，等待系统开始。"),
        )

    fun applyDownloadProgress(
        model: AndroidLocalTranslationModel,
        downloadedBytes: Long,
        totalBytes: Long? = model.totalBytes,
    ): AndroidLocalTranslationModel {
        val targetTotal = totalBytes ?: model.totalBytes ?: downloadedBytes.coerceAtLeast(0L)
        return model.copy(
            downloadState = AndroidModelDownloadState.DOWNLOADING,
            downloadedBytes = downloadedBytes.coerceIn(0L, targetTotal),
            totalBytes = targetTotal,
            readinessIssues = listOf("模型下载中，完成校验前不可用于翻译。"),
        )
    }

    fun applyDownloadReady(model: AndroidLocalTranslationModel): AndroidLocalTranslationModel {
        val total = model.totalBytes ?: model.downloadedBytes
        return model.copy(
            downloadState = AndroidModelDownloadState.READY,
            downloadedBytes = total,
            totalBytes = total,
            readinessIssues = emptyList(),
        )
    }

    fun applyDownloadFailure(
        model: AndroidLocalTranslationModel,
        message: String,
    ): AndroidLocalTranslationModel =
        model.copy(
            downloadState = AndroidModelDownloadState.FAILED,
            readinessIssues = listOf(message),
        )

    fun applyDelete(model: AndroidLocalTranslationModel): AndroidLocalTranslationModel =
        model.copy(
            downloadState = AndroidModelDownloadState.NOT_DOWNLOADED,
            downloadedBytes = 0L,
            readinessIssues = listOf("模型已删除，需要重新下载后才能本地翻译。"),
        )
}

@Serializable
data class AndroidLocalTranslationModel(
    val id: String,
    val displayName: String,
    val provider: AndroidTranslationProvider,
    val engine: AndroidTranslationEngine,
    val downloadState: AndroidModelDownloadState,
    val downloadedBytes: Long = 0L,
    val totalBytes: Long? = null,
    val readinessIssues: List<String> = emptyList(),
) {
    val isRunnable: Boolean
        get() = downloadState == AndroidModelDownloadState.READY && readinessIssues.isEmpty()

    val statusLabel: String
        get() = when (downloadState) {
            AndroidModelDownloadState.NOT_DOWNLOADED -> "未下载"
            AndroidModelDownloadState.QUEUED -> "等待下载"
            AndroidModelDownloadState.DOWNLOADING -> "下载中"
            AndroidModelDownloadState.READY -> if (isRunnable) "可用" else "需要检查"
            AndroidModelDownloadState.FAILED -> "下载失败"
        }

    val primaryAction: AndroidActionState
        get() = AndroidLocalModelPlanner.planDownload(this).actionState

    val secondaryAction: AndroidActionState?
        get() = AndroidLocalModelPlanner.planDelete(this)?.actionState

    companion object {
        fun unavailableDefault(): AndroidLocalTranslationModel =
            AndroidLocalTranslationModel(
                id = "android-local-translation-unavailable",
                displayName = "本机翻译",
                provider = AndroidTranslationProvider.LOCAL_MODEL,
                engine = AndroidTranslationEngine.ON_DEVICE_PLACEHOLDER,
                downloadState = AndroidModelDownloadState.NOT_DOWNLOADED,
                totalBytes = 450L * 1024L * 1024L,
                readinessIssues = listOf("本机翻译当前不可用。可先使用云端 API 翻译。"),
            )
    }
}

@Serializable
enum class AndroidBackgroundCapability {
    @SerialName("download")
    DOWNLOAD,

    @SerialName("render")
    RENDER,
}

@Serializable
data class AndroidBackgroundCapabilityItem(
    val capability: AndroidBackgroundCapability,
    val title: String,
    val statusLabel: String,
    val detail: String,
    val isProductionReady: Boolean = false,
    val action: AndroidActionState? = null,
)

@Serializable
data class AndroidSettingsState(
    val apiKeyReference: SecureCredentialReference? = null,
    val selectedProvider: AndroidTranslationProvider = AndroidTranslationProvider.CLOUD_API,
    val selectedEngine: AndroidTranslationEngine = AndroidTranslationEngine.API_KEY_PLACEHOLDER,
    val cloudTranslationReadiness: AndroidCloudTranslationReadiness = AndroidCloudTranslationReadiness(
        credentialReference = apiKeyReference,
    ),
    val localModel: AndroidLocalTranslationModel = AndroidLocalTranslationModel.unavailableDefault(),
    val apiKeyMockMessage: String = "密钥只保存在本机安全存储中；界面只显示是否已配置。",
    val apiKeyAction: AndroidActionState = AndroidActionState(
        label = "保存 API key",
        availability = AndroidActionAvailability.NEEDS_CONFIGURATION,
        statusLabel = "需要配置",
        helperText = "保存后输入框会清空，不会在任务记录里显示。",
    ),
    val backgroundRuntimeReadiness: AndroidBackgroundRuntimeReadiness = AndroidBackgroundRuntimeReadiness(),
    val backgroundCapabilities: List<AndroidBackgroundCapabilityItem> =
        AndroidBackgroundWorkPlanner.defaultCapabilityItems(backgroundRuntimeReadiness),
) {
    val hasConfiguredAPIKey: Boolean
        get() = apiKeyReference != null

    val apiKeyStatusText: String
        get() = if (hasConfiguredAPIKey) {
            apiKeyReference?.displayName ?: "API key 已配置"
        } else {
            "API key 尚未配置"
        }

    val cloudTranslationStatusText: String
        get() = cloudTranslationReadiness.statusLabel

    val cloudTranslationDetailText: String
        get() = cloudTranslationReadiness.detailText

    val cloudTranslationAction: AndroidActionState
        get() = cloudTranslationReadiness.actionState

    val localModelPrimaryAction: AndroidActionState
        get() = localModel.primaryAction

    val localModelSecondaryAction: AndroidActionState?
        get() = localModel.secondaryAction

    val localModelAction: AndroidActionState
        get() = localModelPrimaryAction

    val notificationPermissionAction: AndroidActionState
        get() = when (backgroundRuntimeReadiness.notificationPermission) {
            AndroidNotificationPermissionState.NOT_REQUIRED -> AndroidActionState(
                label = "无需授权",
                availability = AndroidActionAvailability.SYSTEM_BLOCKED,
                statusLabel = "系统已允许",
                helperText = "当前系统版本不需要单独授权通知；后台处理会在系统允许时启用。",
            )

            AndroidNotificationPermissionState.GRANTED -> AndroidActionState(
                label = "通知已允许",
                availability = AndroidActionAvailability.SYSTEM_BLOCKED,
                statusLabel = "已允许",
                helperText = "通知权限已允许；后台下载会在满足系统条件后启用。",
            )

            AndroidNotificationPermissionState.DENIED -> AndroidActionState(
                label = "打开系统设置",
                availability = AndroidActionAvailability.ENABLED,
                statusLabel = "未授权",
                helperText = "没有通知权限时，后台下载和渲染不会启用；请到系统设置允许通知。",
            )

            AndroidNotificationPermissionState.UNKNOWN -> AndroidActionState(
                label = "允许通知",
                availability = AndroidActionAvailability.ENABLED,
                statusLabel = "需授权",
                helperText = "Android 13 及以上需要通知权限，后台任务才可显示系统通知。",
            )
        }

    companion object {
        fun live(
            apiKeyReference: SecureCredentialReference? = null,
            cloudTranslationReadiness: AndroidCloudTranslationReadiness = AndroidCloudTranslationReadiness(),
            localModel: AndroidLocalTranslationModel = AndroidLocalTranslationModel.unavailableDefault(),
            backgroundRuntimeReadiness: AndroidBackgroundRuntimeReadiness = AndroidBackgroundRuntimeReadiness(),
        ): AndroidSettingsState =
            AndroidSettingsState(
                apiKeyReference = apiKeyReference,
                cloudTranslationReadiness = cloudTranslationReadiness
                    .withCredentialReference(apiKeyReference),
                localModel = localModel,
                backgroundRuntimeReadiness = backgroundRuntimeReadiness,
                apiKeyMockMessage = "密钥只保存在本机安全存储中；设置只显示是否已配置。",
                apiKeyAction = AndroidActionState(
                    label = if (apiKeyReference == null) "保存 API key" else "更新 API key",
                    availability = AndroidActionAvailability.NEEDS_CONFIGURATION,
                    statusLabel = if (apiKeyReference == null) "需要配置" else "已配置",
                    helperText = "保存后输入框会清空，不会在任务记录里显示。",
                ),
            )
    }
}

sealed class AndroidAddUrlPlanResult {
    data class Staged(
        val readyState: AndroidAddReadyState,
    ) : AndroidAddUrlPlanResult()

    data class Rejected(
        val message: String,
        val sessionState: MobileAddSessionState = MobileAddSessionState.FAILED,
        val candidates: List<MobileVideoCandidate> = emptyList(),
        val selectedCandidateID: String? = null,
    ) : AndroidAddUrlPlanResult()
}

object AndroidAddUrlPlanner {
    private val supportedDirectMediaExtensions = setOf(
        "mp4",
        "mov",
        "m4v",
        "webm",
    )

    fun stageDirectUrl(
        input: String,
        idFactory: AndroidOpaqueIDFactory = AndroidOpaqueID.factory,
    ): AndroidAddUrlPlanResult {
        val trimmed = input.trim()
        val uri = runCatching { URI(trimmed) }.getOrNull()
        if (uri == null || uri.scheme?.equals("https", ignoreCase = true) != true || uri.host.isNullOrBlank()) {
            return AndroidAddUrlPlanResult.Rejected(message = "请输入 HTTPS 直接媒体链接。")
        }
        if (uri.rawQuery != null || uri.rawFragment != null) {
            return AndroidAddUrlPlanResult.Rejected(
                message = "Android 当前仅支持不带参数的 HTTPS 直接媒体链接；带参数或片段的签名链接暂不加入队列。",
                sessionState = MobileAddSessionState.UNSUPPORTED,
            )
        }
        if (uri.rawUserInfo != null) {
            return AndroidAddUrlPlanResult.Rejected(
                message = "请输入 HTTPS 直接媒体链接。",
                sessionState = MobileAddSessionState.UNSUPPORTED,
            )
        }
        if (!isSupportedDirectMediaPath(uri.path)) {
            val unsupportedCandidateID = idFactory.nextID("android-url")
            val unsupported = MobileVideoCandidate(
                id = unsupportedCandidateID,
                sourceURL = trimmed,
                kind = MobileCandidateKind.WEB_PAGE_VIDEO,
                title = "需要桌面解析的网页链接",
                detail = "手机端目前只支持 .mp4、.mov、.m4v 或 .webm 的 HTTPS 直接视频文件链接。网页或音频链接可先在桌面端处理。",
                unsupportedReason = MobileUnsupportedReason.REQUIRES_DESKTOP_EXTRACTOR,
            )
            return AndroidAddUrlPlanResult.Rejected(
                message = "${unsupported.detail}",
                sessionState = MobileAddSessionState.UNSUPPORTED,
                candidates = listOf(unsupported),
                selectedCandidateID = unsupported.id,
            )
        }

        val displayTitle = trimmed
            .substringAfterLast("/")
            .takeIf { it.isNotBlank() }
            ?: "直接媒体链接"
        val candidateID = idFactory.nextID("android-url")
        val sessionID = idFactory.nextID("android-session")
        val videoID = idFactory.nextID("android-video")
        val downloadTaskID = idFactory.nextID("android-download")
        val candidate = MobileVideoCandidate(
            id = candidateID,
            sourceURL = trimmed,
            kind = MobileCandidateKind.DIRECT_FILE,
            title = displayTitle,
            detail = "直接媒体链接",
        )
        val readyState: AndroidAddReadyState = AndroidAddReadyState(
            sessionID = sessionID,
            downloadTaskID = downloadTaskID,
            videoInfo = MobileVideoInfo(
                candidate = candidate,
                videoID = videoID,
                title = displayTitle,
                formats = listOf(
                    MobileFormatChoice(
                        id = "original",
                        label = "原始文件",
                        detail = "保留来源格式",
                    ),
                ),
                subtitles = emptyList(),
            ),
            selectedFormatID = "original",
        )
        return AndroidAddUrlPlanResult.Staged(readyState = readyState)
    }

    private fun isSupportedDirectMediaPath(value: String?): Boolean {
        val path = value
            ?.takeIf { it.isNotBlank() }
            ?: return false
        val normalizedPath = path
            .trimEnd('/')
        val extension = normalizedPath.substringAfterLast('.', missingDelimiterValue = "")
            .lowercase()
        return supportedDirectMediaExtensions.contains(extension)
    }
}

@Serializable
data class AndroidAppState(
    val selectedSurface: AndroidSurface = AndroidSurface.ADD,
    val surfaces: List<AndroidSurface> = AndroidDefaultSurfaces,
    val addUrlState: AndroidMockInputState,
    val fileImportState: AndroidMockInputState,
    // Uses the shared enum class MobileAddSessionState from MobileMediaModels.kt.
    val addSessionState: MobileAddSessionState = MobileAddSessionState.IDLE,
    val addCandidates: List<MobileVideoCandidate> = emptyList(),
    val selectedAddCandidateID: String? = null,
    val addReadyState: AndroidAddReadyState? = null,
    val queue: List<AndroidDownloadItem>,
    val library: List<AndroidLibraryItem>,
    val settings: AndroidSettingsState,
    val mockBoundaries: List<String>,
) {
    fun withQueuedDownloadRequest(request: MobileDownloadRequest): AndroidAppState =
        AndroidDownloadItem.fromDownloadRequest(request).let { item ->
            copy(
                selectedSurface = AndroidSurface.QUEUE,
                queue = queue + item.copy(id = nextQueueID(item.id)),
            )
        }

    private fun nextQueueID(baseID: String): String {
        var candidate = baseID
        var suffix = 2
        while (queue.any { it.id == candidate }) {
            candidate = "$baseID-$suffix"
            suffix += 1
        }
        return candidate
    }

    fun withPersistedTasks(
        tasks: List<MobileTaskSnapshot>,
        createdAtLabel: String = "已恢复",
    ): AndroidAppState {
        val restoredQueue = tasks.map { AndroidDownloadItem.fromTaskSnapshot(it) }
        val restoredLibrary = tasks.mapNotNull { AndroidLibraryItem.fromTaskSnapshot(it, createdAtLabel) }
        return copy(
            selectedSurface = if (restoredQueue.isNotEmpty()) AndroidSurface.QUEUE else selectedSurface,
            queue = restoredQueue,
            library = restoredLibrary,
        )
    }

    fun withStagedDirectUrl(input: String): AndroidAppState =
        when (val result = AndroidAddUrlPlanner.stageDirectUrl(input)) {
            is AndroidAddUrlPlanResult.Staged -> copy(
                selectedSurface = AndroidSurface.ADD,
                addSessionState = MobileAddSessionState.READY,
                addCandidates = listOf(result.readyState.videoInfo.candidate),
                selectedAddCandidateID = result.readyState.videoInfo.candidate.id,
                addReadyState = result.readyState,
                addUrlState = addUrlState.copy(errorMessage = null),
            )
            is AndroidAddUrlPlanResult.Rejected -> copy(
                addSessionState = result.sessionState,
                addCandidates = result.candidates,
                selectedAddCandidateID = result.selectedCandidateID,
                addReadyState = null,
                addUrlState = addUrlState.copy(errorMessage = result.message),
            )
        }

    fun withCandidateSelection(
        candidates: List<MobileVideoCandidate>,
        selectedCandidateID: String? = candidates.firstOrNull { it.isSupportedOnMobile }?.id,
    ): AndroidAppState =
        copy(
            selectedSurface = AndroidSurface.ADD,
            addSessionState = MobileAddSessionState.CANDIDATE_SELECTION,
            addCandidates = candidates,
            selectedAddCandidateID = selectedCandidateID
                ?.takeIf { candidateID ->
                    candidates.any { candidate -> candidate.id == candidateID && candidate.isSupportedOnMobile }
                },
            addReadyState = null,
            addUrlState = addUrlState.copy(errorMessage = null),
        )

    fun withSelectedAddCandidate(candidateID: String): AndroidAppState {
        val candidate = addCandidates.firstOrNull { it.id == candidateID && it.isSupportedOnMobile }
            ?: return this
        return copy(selectedAddCandidateID = candidate.id)
    }

    fun withImportedSubtitle(file: AndroidImportedFile): AndroidAppState =
        copy(
            selectedSurface = AndroidSurface.ADD,
            addReadyState = addReadyState?.withImportedSubtitle(file),
        )

    fun withImportedFile(file: AndroidImportedFile, createdAtLabel: String = "刚刚"): AndroidAppState {
        val task = AndroidOfflineFileImportPlanner.taskSnapshot(file)
        return copy(
            selectedSurface = AndroidSurface.QUEUE,
            queue = queue + AndroidDownloadItem.fromTaskSnapshot(task),
            library = library + listOfNotNull(
                AndroidLibraryItem.fromTaskSnapshot(task, createdAtLabel)
                    ?.withStorageUri(file.contentUri),
            ),
        )
    }

    fun withDownloadedFile(item: AndroidDownloadItem, storageUri: String, byteCount: Long? = null): AndroidAppState {
        val artifactStorageIdentifier = storageUri
            .takeIf { it.startsWith("android-owned:") }
            ?: "android-owned:${item.appOwnedDownloadFileName()}"
        val artifact = AndroidLibraryArtifact(
            id = "downloaded-${item.id}",
            kind = AndroidLibraryArtifactKind.ORIGINAL_VIDEO,
            displayName = item.title,
        )
        val completedItem = item.copy(
            state = AndroidDownloadState.COMPLETED,
            progressPercent = 100,
            detail = "文件已保存，可在资料库打开或分享。",
            usesRealDownloader = true,
            sourceUrlForDownload = "",
            completedArtifactStorageIdentifier = artifactStorageIdentifier,
            taskResult = MobileTaskResult(
                artifacts = listOf(
                    MobileTaskArtifact(
                        id = "downloaded-${item.id}",
                        kind = MobileArtifactKind.ORIGINAL_MEDIA,
                        displayName = item.title,
                        storageIdentifier = artifactStorageIdentifier,
                        byteCount = byteCount,
                    ),
                ),
                primaryArtifactID = "downloaded-${item.id}",
            ),
            availableTaskActions = listOf(
                MobileTaskAction.OPEN_RESULT,
                MobileTaskAction.SHARE_RESULT,
                MobileTaskAction.REMOVE,
            ),
            error = null,
        )
        val libraryItem = AndroidLibraryItem(
            id = "library-${item.id}",
            title = item.title,
            createdAtLabel = "刚刚",
            artifacts = listOf(artifact),
            availability = AndroidLibraryAvailability.AVAILABLE,
            storageUri = artifactStorageIdentifier,
        )
        return copy(
            selectedSurface = AndroidSurface.LIBRARY,
            queue = queue.map { existing -> if (existing.id == item.id) completedItem else existing },
            library = library.filterNot { it.id == libraryItem.id } + libraryItem,
        )
    }

    fun withTranslatedSubtitleExportStarted(item: AndroidDownloadItem): AndroidAppState {
        val exportingItem = item.copy(
            state = AndroidDownloadState.TRANSLATING,
            progressPercent = null,
            backgroundStatus = AndroidBackgroundTaskStatus.FOREGROUND_ONLY,
            detail = "字幕导出需要保持应用打开；当前暂不能继续处理。",
            error = MobileTaskError.SYSTEM_BACKGROUND_LIMIT,
        )
        return copy(
            selectedSurface = AndroidSurface.QUEUE,
            queue = queue.map { existing -> if (existing.id == item.id) exportingItem else existing },
        )
    }

    fun withRenderExportStarted(item: AndroidDownloadItem): AndroidAppState {
        val exportingItem = item.copy(
            state = AndroidDownloadState.WAITING_FOR_FOREGROUND,
            progressPercent = null,
            backgroundStatus = AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER,
            detail = "生成带字幕视频需要保持应用打开；当前暂不能开始。",
            error = MobileTaskError.SYSTEM_BACKGROUND_LIMIT,
        )
        return copy(
            selectedSurface = AndroidSurface.QUEUE,
            queue = queue.map { existing -> if (existing.id == item.id) exportingItem else existing },
        )
    }

    fun withDownloadStarted(item: AndroidDownloadItem): AndroidAppState {
        val downloadingItem = item.copy(
            state = AndroidDownloadState.DOWNLOADING,
            progressPercent = 1,
            detail = "正在下载，请保持应用在前台。",
            usesRealDownloader = true,
            error = null,
        )
        return copy(
            selectedSurface = AndroidSurface.QUEUE,
            queue = queue.map { existing -> if (existing.id == item.id) downloadingItem else existing },
        )
    }

    fun withDownloadProgress(
        item: AndroidDownloadItem,
        bytesDownloaded: Long,
        totalBytes: Long?,
    ): AndroidAppState {
        val safeDownloaded = bytesDownloaded.coerceAtLeast(0L)
        val total = totalBytes?.takeIf { it > 0L }
        val progressPercent = if (total != null) {
            ((safeDownloaded * 100L) / total).coerceIn(1L, 99L).toInt()
        } else {
            null
        }
        val progressDetail = progressPercent?.let {
            "正在下载 $it%，请保持应用在前台。"
        } ?: "已下载 ${safeDownloaded.androidByteCountLabel()}，请保持应用在前台。"
        return copy(
            selectedSurface = AndroidSurface.QUEUE,
            queue = queue.map { existing ->
                if (existing.id == item.id) {
                    existing.copy(
                        state = AndroidDownloadState.DOWNLOADING,
                        progressPercent = progressPercent,
                        detail = progressDetail,
                        usesRealDownloader = true,
                        error = null,
                    )
                } else {
                    existing
                }
            },
        )
    }

    fun withDownloadFailed(item: AndroidDownloadItem, message: String): AndroidAppState {
        val failedItem = item.copy(
            state = AndroidDownloadState.FAILED,
            progressPercent = null,
            detail = message,
            error = MobileTaskError.NETWORK_UNAVAILABLE,
            usesRealDownloader = true,
        )
        return copy(
            selectedSurface = AndroidSurface.QUEUE,
            queue = queue.map { existing -> if (existing.id == item.id) failedItem else existing },
        )
    }

    fun withoutQueueItem(id: String): AndroidAppState =
        copy(
            queue = queue.filterNot { it.id == id },
            library = library.filterNot { it.id == "library-$id" },
        )

    fun withoutLibraryItem(id: String): AndroidAppState {
        val taskID = id.removePrefix("library-")
        return copy(
            queue = queue.filterNot { it.id == taskID },
            library = library.filterNot { it.id == id },
        )
    }

    fun withQueuedDownloadItem(item: AndroidDownloadItem): AndroidAppState =
        copy(
            selectedSurface = AndroidSurface.QUEUE,
            queue = queue.filterNot { it.id == item.id } + item,
        )

    fun withProjectedBackgroundTask(snapshot: MobileTaskSnapshot): AndroidAppState {
        var matchedQueueItem = false
        val updatedQueue = queue.map { existing ->
            if (existing.id != snapshot.id) {
                existing
            } else {
                matchedQueueItem = true
                val projected = AndroidDownloadItem.fromTaskSnapshot(snapshot)
                existing.copy(
                    state = projected.state,
                    progressPercent = projected.progressPercent,
                    backgroundStatus = snapshot.androidBackgroundTaskStatus,
                    backgroundPolicy = snapshot.backgroundPolicy,
                    detail = snapshot.androidObservedBackgroundDetail,
                    error = projected.error,
                    completedArtifactStorageIdentifier = projected.completedArtifactStorageIdentifier,
                    taskResult = projected.taskResult,
                    availableTaskActions = projected.availableTaskActions,
                    executionGenerationID = projected.executionGenerationID,
                    usesRealDownloader = existing.usesRealDownloader ||
                        snapshot.backgroundPolicy.execution == MobileBackgroundExecution.SCHEDULED_WORK,
                    usesRealRenderer = existing.usesRealRenderer || projected.usesRealRenderer,
                )
            }
        }
        val restoredLibrary = AndroidLibraryItem.fromTaskSnapshot(snapshot, "已恢复")
        return copy(
            selectedSurface = if (matchedQueueItem) AndroidSurface.QUEUE else selectedSurface,
            queue = updatedQueue,
            library = if (restoredLibrary == null) {
                library
            } else {
                library.filterNot { it.id == restoredLibrary.id } + restoredLibrary
            },
        )
    }

    fun withLibraryItem(item: AndroidLibraryItem): AndroidAppState =
        copy(
            selectedSurface = AndroidSurface.LIBRARY,
            library = library.filterNot { it.id == item.id } + item,
        )

    fun withRecoveredLibraryFile(item: AndroidLibraryItem, file: AndroidImportedFile): AndroidAppState {
        val recoveredItem = item.withStorageUri(file.contentUri)
        val recoveredQueueItem = AndroidDownloadItem.fromLibraryItem(recoveredItem)
        return copy(
            selectedSurface = AndroidSurface.LIBRARY,
            queue = queue.filterNot { it.id == recoveredQueueItem.id } + recoveredQueueItem,
            library = library.filterNot { it.id == recoveredItem.id } + recoveredItem,
        )
    }

    fun withRestoredLibraryItem(item: AndroidLibraryItem): AndroidAppState {
        val restoredQueueItem = AndroidDownloadItem.fromLibraryItem(item)
        return copy(
            selectedSurface = AndroidSurface.LIBRARY,
            queue = queue.filterNot { it.id == restoredQueueItem.id } + restoredQueueItem,
            library = library.filterNot { it.id == item.id } + item,
        )
    }

    fun persistedTaskForQueueItem(id: String): MobileTaskSnapshot? =
        queue.firstOrNull { it.id == id }?.taskSnapshot()

    fun withAPIKeyReference(reference: SecureCredentialReference): AndroidAppState =
        copy(settings = AndroidSettingsState.live(
            apiKeyReference = reference,
            cloudTranslationReadiness = settings.cloudTranslationReadiness,
            localModel = settings.localModel,
            backgroundRuntimeReadiness = settings.backgroundRuntimeReadiness,
        ))

    fun withoutAPIKeyReference(): AndroidAppState =
        copy(settings = AndroidSettingsState.live(
            apiKeyReference = null,
            cloudTranslationReadiness = settings.cloudTranslationReadiness,
            localModel = settings.localModel,
            backgroundRuntimeReadiness = settings.backgroundRuntimeReadiness,
        ))

    fun withAndroidNotificationPermission(state: AndroidNotificationPermissionState): AndroidAppState =
        copy(settings = AndroidSettingsState.live(
            apiKeyReference = settings.apiKeyReference,
            cloudTranslationReadiness = settings.cloudTranslationReadiness,
            localModel = settings.localModel,
            backgroundRuntimeReadiness = settings.backgroundRuntimeReadiness.copy(
                notificationPermission = state,
            ),
        ))

    companion object {
        val defaultSurfaces: List<AndroidSurface>
            get() = AndroidDefaultSurfaces

        fun live(apiKeyReference: SecureCredentialReference? = null): AndroidAppState =
            AndroidAppState(
                addUrlState = AndroidMockInputState(
                    title = "直链",
                    helperText = "仅支持 HTTPS 直接媒体文件链接。",
                    isMockOnly = false,
                    primaryAction = AndroidActionState(
                        label = "解析链接",
                        availability = AndroidActionAvailability.ENABLED,
                        statusLabel = "可解析",
                        helperText = "仅支持 HTTPS 直接媒体文件链接。",
                    ),
                ),
                fileImportState = AndroidMockInputState(
                    title = "导入视频",
                    helperText = "从系统文件选择器导入本地视频。",
                    isMockOnly = false,
                    primaryAction = AndroidActionState(
                        label = "选择视频文件",
                        availability = AndroidActionAvailability.ENABLED,
                        statusLabel = "可导入",
                        helperText = "选择本地视频后会加入队列和资料库。",
                    ),
                ),
                addSessionState = MobileAddSessionState.IDLE,
                addCandidates = emptyList(),
                selectedAddCandidateID = null,
                addReadyState = null,
                queue = emptyList(),
                library = emptyList(),
                settings = AndroidSettingsState.live(apiKeyReference = apiKeyReference),
                mockBoundaries = emptyList(),
            )

        fun sample(): AndroidAppState {
            val readyState = AndroidAddReadyState.sample()
            return AndroidAppState(
                addUrlState = AndroidMockInputState(
                    title = "添加链接",
                    helperText = "预览只展示链接入口；真实使用仅支持 HTTPS 直接媒体文件。",
                    primaryAction = AndroidActionState(
                        label = "添加到队列",
                        availability = AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER,
                        statusLabel = "示例",
                        helperText = "预览只展示按钮位置，不创建真实任务。",
                    ),
                ),
                fileImportState = AndroidMockInputState(
                    title = "导入视频",
                    helperText = "预览只展示文件导入入口。",
                    primaryAction = AndroidActionState(
                        label = "选择视频文件",
                        availability = AndroidActionAvailability.NEEDS_PLATFORM_ADAPTER,
                        statusLabel = "示例",
                        helperText = "预览不读取本地文件。",
                    ),
                ),
                addSessionState = MobileAddSessionState.READY,
                addCandidates = listOf(readyState.videoInfo.candidate),
                selectedAddCandidateID = readyState.videoInfo.candidate.id,
                addReadyState = readyState,
                queue = listOf(
                    AndroidDownloadItem(
                        id = "queue-transfer-mock",
                        title = "公开视频下载样例",
                        sourceLabel = "URL mock",
                        state = AndroidDownloadState.DOWNLOADING,
                        progressPercent = 42,
                        backgroundStatus = AndroidBackgroundTaskStatus.TRANSFER_ALLOWED,
                        detail = "仅模拟 Android 后台传输通知；没有真实网络下载。",
                    ),
                    AndroidDownloadItem(
                        id = "queue-render-mock",
                        title = "字幕烧录样例",
                        sourceLabel = "本地文件 mock",
                        state = AndroidDownloadState.WAITING_FOR_FOREGROUND,
                        progressPercent = null,
                        backgroundStatus = AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER,
                        detail = "ffmpeg 渲染未实现，后台渲染能力仅占位。",
                    ),
                ),
                library = listOf(
                    AndroidLibraryItem(
                        id = "library-mock-1",
                        title = "字幕导出样例",
                        createdAtLabel = "今天",
                        artifacts = listOf(
                            AndroidLibraryArtifact(
                                id = "artifact-subtitle-mock",
                                kind = AndroidLibraryArtifactKind.TRANSLATED_SUBTITLE,
                                displayName = "sample.zh-Hans.srt",
                            ),
                        ),
                    ),
                ),
                settings = AndroidSettingsState(),
                mockBoundaries = listOf(
                    "完整站点解析还在接入中：当前优先验证直接媒体链接。",
                    "视频渲染还在接入中：字幕烧录和后台恢复会单独验证。",
                    "API key 只通过安全存储入口保存，不写入任务记录。",
                    "本地翻译模型需要下载、校验和推理准备完成后才能运行。",
                ),
            )
        }
    }
}

private val MobileTaskSnapshot.androidBackgroundTaskStatus: AndroidBackgroundTaskStatus
    get() = when (backgroundPolicy.execution) {
        MobileBackgroundExecution.BACKGROUND_TRANSFER,
        MobileBackgroundExecution.SCHEDULED_WORK,
        MobileBackgroundExecution.SYSTEM_MANAGED,
        -> AndroidBackgroundTaskStatus.TRANSFER_ALLOWED

        MobileBackgroundExecution.CONTINUED_PROCESSING,
        MobileBackgroundExecution.SYSTEM_DEFERRED,
        -> AndroidBackgroundTaskStatus.SYSTEM_DEFERRED

        MobileBackgroundExecution.FOREGROUND_REQUIRED,
        MobileBackgroundExecution.SYSTEM_INTERRUPTED,
        -> if (exportProfile.requiresVideoRender && state == MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE) {
            AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER
        } else {
            AndroidBackgroundTaskStatus.FOREGROUND_ONLY
        }
    }

private val MobileTaskSnapshot.androidObservedBackgroundDetail: String
    get() = when (state) {
        MobileTaskState.DOWNLOADING -> progress.fractionCompleted
            ?.let { fraction ->
                "后台下载中 ${(fraction * 100).toInt()}%，可从系统通知查看或取消。"
            }
            ?: "后台下载已交给系统调度，可从系统通知查看或取消。"

        MobileTaskState.FAILED -> "后台下载没有完成，请检查网络后重试。"
        MobileTaskState.CANCELLED -> "后台下载已取消，需要时重新开始。"
        else -> androidRestoredDetail
    }
