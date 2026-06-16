package com.moongate.mobile.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MobileRenderRequestPlanStatus {
    @SerialName("notRequired")
    NOT_REQUIRED,

    @SerialName("ready")
    READY,

    @SerialName("blocked")
    BLOCKED,
}

@Serializable
enum class MobileRenderRequestBlockedReason {
    @SerialName("taskNotCompleted")
    TASK_NOT_COMPLETED,

    @SerialName("unsupportedExportProfile")
    UNSUPPORTED_EXPORT_PROFILE,

    @SerialName("missingSourceMedia")
    MISSING_SOURCE_MEDIA,

    @SerialName("missingSubtitle")
    MISSING_SUBTITLE,
}

@Serializable
data class MobileRenderRequestPlan(
    val status: MobileRenderRequestPlanStatus,
    val request: MobileRenderRequest? = null,
    val blockedReason: MobileRenderRequestBlockedReason? = null,
)

object MobileRenderRequestPlanner {
    fun plan(task: MobileTaskSnapshot): MobileRenderRequestPlan {
        if (task.exportProfile.subtitleMode != MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE) {
            return MobileRenderRequestPlan(status = MobileRenderRequestPlanStatus.NOT_REQUIRED)
        }

        if (task.state != MobileTaskState.COMPLETED) {
            return MobileRenderRequestPlan(
                status = MobileRenderRequestPlanStatus.BLOCKED,
                blockedReason = MobileRenderRequestBlockedReason.TASK_NOT_COMPLETED,
            )
        }

        if (!task.capabilities.canSatisfy(task.exportProfile)) {
            return MobileRenderRequestPlan(
                status = MobileRenderRequestPlanStatus.BLOCKED,
                blockedReason = MobileRenderRequestBlockedReason.UNSUPPORTED_EXPORT_PROFILE,
            )
        }

        val artifacts = task.result?.artifacts.orEmpty()
        val sourceMedia = artifacts.firstOrNull { it.kind == MobileArtifactKind.ORIGINAL_MEDIA }
            ?: return MobileRenderRequestPlan(
                status = MobileRenderRequestPlanStatus.BLOCKED,
                blockedReason = MobileRenderRequestBlockedReason.MISSING_SOURCE_MEDIA,
            )
        val subtitles = artifacts.filter { it.kind == MobileArtifactKind.TRANSLATED_SUBTITLE_FILE }
        if (subtitles.isEmpty()) {
            return MobileRenderRequestPlan(
                status = MobileRenderRequestPlanStatus.BLOCKED,
                blockedReason = MobileRenderRequestBlockedReason.MISSING_SUBTITLE,
            )
        }

        return MobileRenderRequestPlan(
            status = MobileRenderRequestPlanStatus.READY,
            request = MobileRenderRequest(
                sourceMedia = sourceMedia,
                subtitles = subtitles,
                exportProfile = task.exportProfile,
            ),
        )
    }
}
