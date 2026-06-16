package com.moongate.mobile.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MobilePlatform {
    @SerialName("ios")
    IOS,

    @SerialName("android")
    ANDROID,
}

@Serializable
enum class MobileProcessingCapability {
    @SerialName("analysis")
    ANALYSIS,

    @SerialName("download")
    DOWNLOAD,

    @SerialName("translation")
    TRANSLATION,

    @SerialName("subtitleExport")
    SUBTITLE_EXPORT,

    @SerialName("videoRender")
    VIDEO_RENDER,

    @SerialName("backgroundTransfer")
    BACKGROUND_TRANSFER,

    @SerialName("backgroundRender")
    BACKGROUND_RENDER,

    @SerialName("localTranslationModel")
    LOCAL_TRANSLATION_MODEL,

    @SerialName("cloudTranslation")
    CLOUD_TRANSLATION,

    @SerialName("appleIntelligence")
    APPLE_INTELLIGENCE,
}

@Serializable
data class MobileProcessingCapabilities(
    val platform: MobilePlatform,
    val supportedCapabilities: List<MobileProcessingCapability> = emptyList(),
    val maxRenderHeight: Int? = null,
) {
    fun supports(capability: MobileProcessingCapability): Boolean =
        supportedCapabilities.contains(capability)

    fun canSatisfy(profile: MobileExportProfile): Boolean =
        when (profile.subtitleMode) {
            MobileExportProfile.SubtitleMode.NONE -> supports(MobileProcessingCapability.DOWNLOAD)
            MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE ->
                supports(MobileProcessingCapability.TRANSLATION) &&
                    supports(MobileProcessingCapability.SUBTITLE_EXPORT)
            MobileExportProfile.SubtitleMode.SOFT_SUBTITLE ->
                supports(MobileProcessingCapability.SUBTITLE_EXPORT)
            MobileExportProfile.SubtitleMode.BURNED_IN_SUBTITLE -> {
                if (!supports(MobileProcessingCapability.VIDEO_RENDER)) {
                    false
                } else {
                    val requestedHeight = profile.maxRenderHeight
                    val maxHeight = maxRenderHeight
                    requestedHeight == null || maxHeight == null || requestedHeight <= maxHeight
                }
            }
        }
}

@Serializable
enum class MobileBackgroundExecution {
    @SerialName("foregroundRequired")
    FOREGROUND_REQUIRED,

    @SerialName("backgroundTransfer")
    BACKGROUND_TRANSFER,

    @SerialName("continuedProcessing")
    CONTINUED_PROCESSING,

    @SerialName("scheduledWork")
    SCHEDULED_WORK,

    @SerialName("systemManaged")
    SYSTEM_MANAGED,

    @SerialName("systemDeferred")
    SYSTEM_DEFERRED,

    @SerialName("systemInterrupted")
    SYSTEM_INTERRUPTED,
}

@Serializable
enum class MobileBackgroundResumability {
    @SerialName("resumable")
    RESUMABLE,

    @SerialName("nonResumable")
    NON_RESUMABLE,
}

@Serializable
enum class MobileBackgroundLimit {
    @SerialName("foregroundRequired")
    FOREGROUND_REQUIRED,

    @SerialName("systemTimeLimit")
    SYSTEM_TIME_LIMIT,

    @SerialName("systemDeferred")
    SYSTEM_DEFERRED,

    @SerialName("systemInterrupted")
    SYSTEM_INTERRUPTED,

    @SerialName("notResumable")
    NOT_RESUMABLE,

    @SerialName("requiresExternalPower")
    REQUIRES_EXTERNAL_POWER,

    @SerialName("requiresUnmeteredNetwork")
    REQUIRES_UNMETERED_NETWORK,

    @SerialName("userVisibleNotificationRequired")
    USER_VISIBLE_NOTIFICATION_REQUIRED,
}

@Serializable
data class MobileBackgroundPolicy(
    val execution: MobileBackgroundExecution = MobileBackgroundExecution.FOREGROUND_REQUIRED,
    val resumability: MobileBackgroundResumability = MobileBackgroundResumability.RESUMABLE,
    val systemTimeLimitSeconds: Int? = null,
    val limits: List<MobileBackgroundLimit> = emptyList(),
) {
    val requiresForeground: Boolean
        get() = execution == MobileBackgroundExecution.FOREGROUND_REQUIRED ||
            limits.contains(MobileBackgroundLimit.FOREGROUND_REQUIRED)

    val isSystemLimited: Boolean
        get() = when (execution) {
            MobileBackgroundExecution.FOREGROUND_REQUIRED ->
                limits.any {
                    it == MobileBackgroundLimit.SYSTEM_TIME_LIMIT ||
                        it == MobileBackgroundLimit.SYSTEM_DEFERRED ||
                        it == MobileBackgroundLimit.SYSTEM_INTERRUPTED
                }

            MobileBackgroundExecution.BACKGROUND_TRANSFER,
            MobileBackgroundExecution.CONTINUED_PROCESSING,
            MobileBackgroundExecution.SCHEDULED_WORK,
            MobileBackgroundExecution.SYSTEM_MANAGED,
            MobileBackgroundExecution.SYSTEM_DEFERRED,
            MobileBackgroundExecution.SYSTEM_INTERRUPTED,
            -> true
        }

    val canResume: Boolean
        get() = resumability == MobileBackgroundResumability.RESUMABLE &&
            !limits.contains(MobileBackgroundLimit.NOT_RESUMABLE)

    val allowsUnboundedBackgroundExecution: Boolean
        get() = false
}

@Serializable
enum class MobileDesignSystem {
    @SerialName("appleHIG")
    APPLE_HIG,

    @SerialName("material3")
    MATERIAL3,
}

@Serializable
enum class MobileSurface {
    @SerialName("add")
    ADD,

    @SerialName("queue")
    QUEUE,

    @SerialName("library")
    LIBRARY,

    @SerialName("settings")
    SETTINGS,
}

@Serializable
data class MobilePlatformProfile(
    val platform: MobilePlatform,
    val designSystem: MobileDesignSystem,
    val surfaces: List<MobileSurface>,
    val capabilities: MobileProcessingCapabilities,
    val defaultBackgroundPolicy: MobileBackgroundPolicy,
) {
    companion object {
        val iosDefault = MobilePlatformProfile(
            platform = MobilePlatform.IOS,
            designSystem = MobileDesignSystem.APPLE_HIG,
            surfaces = listOf(
                MobileSurface.ADD,
                MobileSurface.QUEUE,
                MobileSurface.LIBRARY,
                MobileSurface.SETTINGS,
            ),
            capabilities = MobileProcessingCapabilities(platform = MobilePlatform.IOS),
            defaultBackgroundPolicy = MobileBackgroundPolicy(),
        )

        val androidDefault = MobilePlatformProfile(
            platform = MobilePlatform.ANDROID,
            designSystem = MobileDesignSystem.MATERIAL3,
            surfaces = listOf(
                MobileSurface.ADD,
                MobileSurface.QUEUE,
                MobileSurface.LIBRARY,
                MobileSurface.SETTINGS,
            ),
            capabilities = MobileProcessingCapabilities(platform = MobilePlatform.ANDROID),
            defaultBackgroundPolicy = MobileBackgroundPolicy(),
        )
    }
}
