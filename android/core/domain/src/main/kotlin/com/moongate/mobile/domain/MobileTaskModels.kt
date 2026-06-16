package com.moongate.mobile.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MobileTaskState {
    @SerialName("waiting")
    WAITING,

    @SerialName("analyzing")
    ANALYZING,

    @SerialName("ready")
    READY,

    @SerialName("downloading")
    DOWNLOADING,

    @SerialName("translating")
    TRANSLATING,

    @SerialName("exporting")
    EXPORTING,

    @SerialName("needsForegroundToContinue")
    NEEDS_FOREGROUND_TO_CONTINUE,

    @SerialName("completed")
    COMPLETED,

    @SerialName("failed")
    FAILED,

    @SerialName("cancelled")
    CANCELLED,
}

@Serializable
enum class MobileTaskError {
    @SerialName("unsupportedOnMobile")
    UNSUPPORTED_ON_MOBILE,

    @SerialName("networkUnavailable")
    NETWORK_UNAVAILABLE,

    @SerialName("credentialRequired")
    CREDENTIAL_REQUIRED,

    @SerialName("permissionDenied")
    PERMISSION_DENIED,

    @SerialName("storageFull")
    STORAGE_FULL,

    @SerialName("systemBackgroundLimit")
    SYSTEM_BACKGROUND_LIMIT,

    @SerialName("exportFailed")
    EXPORT_FAILED,

    @SerialName("cancelled")
    CANCELLED,

    @SerialName("unknown")
    UNKNOWN;

    val isUserFixable: Boolean
        get() = when (this) {
            CREDENTIAL_REQUIRED,
            PERMISSION_DENIED,
            STORAGE_FULL,
            NETWORK_UNAVAILABLE,
            -> true

            UNSUPPORTED_ON_MOBILE,
            SYSTEM_BACKGROUND_LIMIT,
            EXPORT_FAILED,
            CANCELLED,
            UNKNOWN,
            -> false
        }
}

@Serializable
data class MobileExportProfile(
    val subtitleMode: SubtitleMode = SubtitleMode.TRANSLATED_SUBTITLE_FILE,
    val maxRenderHeight: Int? = 1080,
) {
    val requiresVideoRender: Boolean
        get() = subtitleMode == SubtitleMode.BURNED_IN_SUBTITLE

    @Serializable
    enum class SubtitleMode {
        @SerialName("none")
        NONE,

        @SerialName("translatedSubtitleFile")
        TRANSLATED_SUBTITLE_FILE,

        @SerialName("softSubtitle")
        SOFT_SUBTITLE,

        @SerialName("burnedInSubtitle")
        BURNED_IN_SUBTITLE,
    }
}

@Serializable
enum class MobileTaskPhase {
    @SerialName("waiting")
    WAITING,

    @SerialName("analyzing")
    ANALYZING,

    @SerialName("downloading")
    DOWNLOADING,

    @SerialName("translating")
    TRANSLATING,

    @SerialName("exporting")
    EXPORTING,
}

@Serializable
data class MobileTaskProgress(
    val phase: MobileTaskPhase = MobileTaskPhase.WAITING,
    val completedUnitCount: Int = 0,
    val totalUnitCount: Int? = null,
) {
    val fractionCompleted: Double?
        get() {
            val total = totalUnitCount ?: return null
            if (total <= 0) return null

            return (completedUnitCount.toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
        }
}

@Serializable
enum class MobileArtifactKind {
    @SerialName("originalMedia")
    ORIGINAL_MEDIA,

    @SerialName("translatedSubtitleFile")
    TRANSLATED_SUBTITLE_FILE,

    @SerialName("softSubtitle")
    SOFT_SUBTITLE,

    @SerialName("renderedVideo")
    RENDERED_VIDEO,

    @SerialName("transcript")
    TRANSCRIPT,

    @SerialName("metadata")
    METADATA,
}

@Serializable
data class MobileTaskArtifact(
    val id: String,
    val kind: MobileArtifactKind,
    val displayName: String,
    val storageIdentifier: String,
    val byteCount: Long? = null,
)

@Serializable
data class MobileTaskResult(
    val artifacts: List<MobileTaskArtifact> = emptyList(),
    val primaryArtifactID: String? = null,
) {
    val primaryArtifact: MobileTaskArtifact?
        get() = primaryArtifactID?.let { id -> artifacts.firstOrNull { it.id == id } }
}

@Serializable
enum class MobileTaskAction {
    @SerialName("startDownload")
    START_DOWNLOAD,

    @SerialName("exportTranslatedSubtitle")
    EXPORT_TRANSLATED_SUBTITLE,

    @SerialName("exportRenderedVideo")
    EXPORT_RENDERED_VIDEO,

    @SerialName("pause")
    PAUSE,

    @SerialName("resume")
    RESUME,

    @SerialName("cancel")
    CANCEL,

    @SerialName("retry")
    RETRY,

    @SerialName("openAppToContinue")
    OPEN_APP_TO_CONTINUE,

    @SerialName("openResult")
    OPEN_RESULT,

    @SerialName("shareResult")
    SHARE_RESULT,

    @SerialName("remove")
    REMOVE,
}

@Serializable
data class MobileTaskSnapshot(
    val id: String,
    val platform: MobilePlatform,
    val state: MobileTaskState = MobileTaskState.WAITING,
    val progress: MobileTaskProgress = MobileTaskProgress(),
    val exportProfile: MobileExportProfile = MobileExportProfile(),
    val capabilities: MobileProcessingCapabilities = MobileProcessingCapabilities(platform),
    val backgroundPolicy: MobileBackgroundPolicy = MobileBackgroundPolicy(),
    val executionGenerationID: String? = null,
    val result: MobileTaskResult? = null,
    val error: MobileTaskError? = null,
) {
    val availableActions: List<MobileTaskAction>
        get() = when (state) {
            MobileTaskState.WAITING,
            MobileTaskState.READY,
            -> listOf(MobileTaskAction.START_DOWNLOAD, MobileTaskAction.CANCEL)

            MobileTaskState.ANALYZING -> listOf(MobileTaskAction.CANCEL)

            MobileTaskState.DOWNLOADING,
            MobileTaskState.TRANSLATING,
            MobileTaskState.EXPORTING,
            -> if (backgroundPolicy.canResume) {
                listOf(MobileTaskAction.PAUSE, MobileTaskAction.CANCEL)
            } else {
                listOf(MobileTaskAction.CANCEL)
            }

            MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE ->
                listOf(MobileTaskAction.OPEN_APP_TO_CONTINUE, MobileTaskAction.CANCEL)

            MobileTaskState.COMPLETED -> {
                val artifacts = result?.artifacts.orEmpty()
                if (artifacts.isEmpty()) {
                    listOf(MobileTaskAction.REMOVE)
                } else {
                    val actions = mutableListOf<MobileTaskAction>()
                    if (
                        canExportTranslatedSubtitle(artifacts)
                    ) {
                        actions.add(MobileTaskAction.EXPORT_TRANSLATED_SUBTITLE)
                    }
                    if (
                        canExportRenderedVideo(artifacts)
                    ) {
                        actions.add(MobileTaskAction.EXPORT_RENDERED_VIDEO)
                    }
                    actions.addAll(
                        listOf(
                        MobileTaskAction.OPEN_RESULT,
                        MobileTaskAction.SHARE_RESULT,
                        MobileTaskAction.REMOVE,
                        ),
                    )
                    actions
                }
            }

            MobileTaskState.FAILED -> listOf(MobileTaskAction.RETRY, MobileTaskAction.REMOVE)
            MobileTaskState.CANCELLED -> listOf(MobileTaskAction.REMOVE)
        }

    private fun canExportTranslatedSubtitle(artifacts: List<MobileTaskArtifact>): Boolean =
        exportProfile.subtitleMode == MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE &&
            artifacts.any { it.kind == MobileArtifactKind.TRANSCRIPT } &&
            artifacts.none { it.kind == MobileArtifactKind.TRANSLATED_SUBTITLE_FILE }

    private fun canExportRenderedVideo(artifacts: List<MobileTaskArtifact>): Boolean =
        exportProfile.requiresVideoRender &&
            capabilities.canSatisfy(exportProfile) &&
            artifacts.any { it.kind == MobileArtifactKind.ORIGINAL_MEDIA } &&
            artifacts.any { it.kind == MobileArtifactKind.TRANSLATED_SUBTITLE_FILE } &&
            artifacts.none { it.kind == MobileArtifactKind.RENDERED_VIDEO }
}

@Serializable
enum class MobileLibraryState {
    @SerialName("available")
    AVAILABLE,

    @SerialName("fileMissing")
    FILE_MISSING,

    @SerialName("permissionDenied")
    PERMISSION_DENIED,

    @SerialName("deleting")
    DELETING,
}

@Serializable
enum class MobileLibraryAction {
    @SerialName("open")
    OPEN,

    @SerialName("share")
    SHARE,

    @SerialName("saveToFiles")
    SAVE_TO_FILES,

    @SerialName("saveToPhotos")
    SAVE_TO_PHOTOS,

    @SerialName("deleteRecord")
    DELETE_RECORD,

    @SerialName("locateFile")
    LOCATE_FILE,
}

@Serializable
data class MobileLibraryItem(
    val id: String,
    val title: String,
    val createdAtEpochMillis: Long,
    val artifacts: List<MobileTaskArtifact>,
    val state: MobileLibraryState = MobileLibraryState.AVAILABLE,
    val sourceTaskID: String? = null,
) {
    val availableActions: List<MobileLibraryAction>
        get() = when (state) {
            MobileLibraryState.AVAILABLE -> {
                val hasVideo = artifacts.any {
                    it.kind == MobileArtifactKind.RENDERED_VIDEO ||
                        it.kind == MobileArtifactKind.ORIGINAL_MEDIA
                }
                if (hasVideo) {
                    listOf(
                        MobileLibraryAction.OPEN,
                        MobileLibraryAction.SHARE,
                        MobileLibraryAction.SAVE_TO_FILES,
                        MobileLibraryAction.SAVE_TO_PHOTOS,
                        MobileLibraryAction.DELETE_RECORD,
                    )
                } else {
                    listOf(
                        MobileLibraryAction.OPEN,
                        MobileLibraryAction.SHARE,
                        MobileLibraryAction.SAVE_TO_FILES,
                        MobileLibraryAction.DELETE_RECORD,
                    )
                }
            }

            MobileLibraryState.FILE_MISSING ->
                listOf(MobileLibraryAction.LOCATE_FILE, MobileLibraryAction.DELETE_RECORD)

            MobileLibraryState.PERMISSION_DENIED ->
                listOf(MobileLibraryAction.SAVE_TO_FILES, MobileLibraryAction.DELETE_RECORD)

            MobileLibraryState.DELETING -> emptyList()
        }
}
