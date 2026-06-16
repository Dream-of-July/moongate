package com.moongate.mobile.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MobileRenderRequestPlannerTest {
    @Test
    fun skipsProfilesThatDoNotNeedVideoRender() {
        val task = completedTask(exportProfile = MobileExportProfile())

        val plan = MobileRenderRequestPlanner.plan(task)

        assertEquals(MobileRenderRequestPlanStatus.NOT_REQUIRED, plan.status)
        assertNull(plan.request)
        assertNull(plan.blockedReason)
    }

    @Test
    fun blocksActiveTasksBeforeCreatingRequest() {
        val task = completedTask(
            state = MobileTaskState.EXPORTING,
            exportProfile = burnInProfile(),
            artifacts = listOf(originalMediaArtifact(), translatedSubtitleArtifact()),
        )

        val plan = MobileRenderRequestPlanner.plan(task)

        assertEquals(MobileRenderRequestPlanStatus.BLOCKED, plan.status)
        assertEquals(MobileRenderRequestBlockedReason.TASK_NOT_COMPLETED, plan.blockedReason)
        assertNull(plan.request)
    }

    @Test
    fun blocksUnsupportedRenderProfiles() {
        val task = completedTask(
            exportProfile = MobileExportProfile(
                subtitleMode = MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE,
                maxRenderHeight = 2160,
            ),
            capabilities = renderCapabilities(maxRenderHeight = 1080),
            artifacts = listOf(originalMediaArtifact(), translatedSubtitleArtifact()),
        )

        val plan = MobileRenderRequestPlanner.plan(task)

        assertEquals(MobileRenderRequestPlanStatus.BLOCKED, plan.status)
        assertEquals(MobileRenderRequestBlockedReason.UNSUPPORTED_EXPORT_PROFILE, plan.blockedReason)
    }

    @Test
    fun reportsMissingSourceMediaWithoutFakeRequest() {
        val task = completedTask(
            exportProfile = burnInProfile(),
            artifacts = listOf(translatedSubtitleArtifact()),
        )

        val plan = MobileRenderRequestPlanner.plan(task)

        assertEquals(MobileRenderRequestPlanStatus.BLOCKED, plan.status)
        assertEquals(MobileRenderRequestBlockedReason.MISSING_SOURCE_MEDIA, plan.blockedReason)
        assertNull(plan.request)
    }

    @Test
    fun reportsMissingSubtitleWithoutFakeRequest() {
        val task = completedTask(
            exportProfile = burnInProfile(),
            artifacts = listOf(originalMediaArtifact()),
        )

        val plan = MobileRenderRequestPlanner.plan(task)

        assertEquals(MobileRenderRequestPlanStatus.BLOCKED, plan.status)
        assertEquals(MobileRenderRequestBlockedReason.MISSING_SUBTITLE, plan.blockedReason)
        assertNull(plan.request)
    }

    @Test
    fun buildsBurnedInRequestFromOriginalMediaAndTranslatedSubtitle() {
        val task = completedTask(
            exportProfile = burnInProfile(),
            artifacts = listOf(originalMediaArtifact(), translatedSubtitleArtifact()),
        )

        val plan = MobileRenderRequestPlanner.plan(task)

        assertEquals(MobileRenderRequestPlanStatus.READY, plan.status)
        assertEquals(MobileArtifactKind.ORIGINAL_MEDIA, plan.request?.sourceMedia?.kind)
        assertEquals(listOf(MobileArtifactKind.TRANSLATED_SUBTITLE_FILE), plan.request?.subtitles?.map { it.kind })
        assertEquals(task.exportProfile, plan.request?.exportProfile)
    }

    @Test
    fun rejectsSoftSubtitleArtifactForBurnInUntilConversionExists() {
        val task = completedTask(
            exportProfile = burnInProfile(),
            artifacts = listOf(
                originalMediaArtifact(),
                MobileTaskArtifact(
                    id = "soft",
                    kind = MobileArtifactKind.SOFT_SUBTITLE,
                    displayName = "clip.movtxt",
                    storageIdentifier = "Subtitles/clip.movtxt",
                ),
            ),
        )

        val plan = MobileRenderRequestPlanner.plan(task)

        assertEquals(MobileRenderRequestPlanStatus.BLOCKED, plan.status)
        assertEquals(MobileRenderRequestBlockedReason.MISSING_SUBTITLE, plan.blockedReason)
        assertNull(plan.request)
    }

    @Test
    fun completedTasksWithTranscriptExposeSubtitleExportAction() {
        val task = completedTask(
            exportProfile = MobileExportProfile(subtitleMode = MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE),
            artifacts = listOf(originalMediaArtifact(), transcriptArtifact()),
        )

        assertEquals(
            listOf(
                MobileTaskAction.EXPORT_TRANSLATED_SUBTITLE,
                MobileTaskAction.OPEN_RESULT,
                MobileTaskAction.SHARE_RESULT,
                MobileTaskAction.REMOVE,
            ),
            task.availableActions,
        )
    }

    @Test
    fun completedBurnedInTasksExposeRenderExportAction() {
        val task = completedTask(
            exportProfile = burnInProfile(),
            artifacts = listOf(originalMediaArtifact(), translatedSubtitleArtifact()),
        )

        assertEquals(
            listOf(
                MobileTaskAction.EXPORT_RENDERED_VIDEO,
                MobileTaskAction.OPEN_RESULT,
                MobileTaskAction.SHARE_RESULT,
                MobileTaskAction.REMOVE,
            ),
            task.availableActions,
        )
    }

    private fun completedTask(
        state: MobileTaskState = MobileTaskState.COMPLETED,
        exportProfile: MobileExportProfile = MobileExportProfile(),
        capabilities: MobileProcessingCapabilities = renderCapabilities(),
        artifacts: List<MobileTaskArtifact> = emptyList(),
    ): MobileTaskSnapshot = MobileTaskSnapshot(
        id = "task",
        platform = MobilePlatform.ANDROID,
        state = state,
        exportProfile = exportProfile,
        capabilities = capabilities,
        result = MobileTaskResult(artifacts = artifacts, primaryArtifactID = artifacts.firstOrNull()?.id),
    )

    private fun renderCapabilities(maxRenderHeight: Int = 1080): MobileProcessingCapabilities =
        MobileProcessingCapabilities(
            platform = MobilePlatform.ANDROID,
            supportedCapabilities = listOf(MobileProcessingCapability.VIDEO_RENDER),
            maxRenderHeight = maxRenderHeight,
        )

    private fun burnInProfile(): MobileExportProfile =
        MobileExportProfile(subtitleMode = MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE)

    private fun originalMediaArtifact(): MobileTaskArtifact =
        MobileTaskArtifact(
            id = "original",
            kind = MobileArtifactKind.ORIGINAL_MEDIA,
            displayName = "clip.mp4",
            storageIdentifier = "Downloads/clip.mp4",
        )

    private fun translatedSubtitleArtifact(): MobileTaskArtifact =
        MobileTaskArtifact(
            id = "subtitle",
            kind = MobileArtifactKind.TRANSLATED_SUBTITLE_FILE,
            displayName = "clip.zh.srt",
            storageIdentifier = "Subtitles/clip.zh.srt",
        )

    private fun transcriptArtifact(): MobileTaskArtifact =
        MobileTaskArtifact(
            id = "transcript",
            kind = MobileArtifactKind.TRANSCRIPT,
            displayName = "clip.en.srt",
            storageIdentifier = "Transcripts/clip.en.srt",
        )
}
