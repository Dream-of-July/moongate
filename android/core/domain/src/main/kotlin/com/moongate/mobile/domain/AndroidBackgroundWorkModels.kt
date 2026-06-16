package com.moongate.mobile.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class AndroidBackgroundWorkKind {
    @SerialName("download")
    DOWNLOAD,

    @SerialName("render")
    RENDER,
}

@Serializable
enum class AndroidBackgroundRunner {
    @SerialName("userInitiatedDataTransfer")
    USER_INITIATED_DATA_TRANSFER,

    @SerialName("foregroundService")
    FOREGROUND_SERVICE,

    @SerialName("workManager")
    WORK_MANAGER,

    @SerialName("foregroundOnly")
    FOREGROUND_ONLY,
}

@Serializable
enum class AndroidBackgroundRequirement {
    @SerialName("platformAdapter")
    PLATFORM_ADAPTER,

    @SerialName("userVisibleNotification")
    USER_VISIBLE_NOTIFICATION,

    @SerialName("notificationPermission")
    NOTIFICATION_PERMISSION,

    @SerialName("workerRuntime")
    WORKER_RUNTIME,

    @SerialName("network")
    NETWORK,

    @SerialName("appOwnedStorage")
    APP_OWNED_STORAGE,

    @SerialName("checkpointing")
    CHECKPOINTING,

    @SerialName("batteryNotLow")
    BATTERY_NOT_LOW,

    @SerialName("foregroundUntilAdapterExists")
    FOREGROUND_UNTIL_ADAPTER_EXISTS,
}

@Serializable
enum class AndroidBackgroundInterruption {
    @SerialName("networkLost")
    NETWORK_LOST,

    @SerialName("appStopped")
    APP_STOPPED,

    @SerialName("systemStopped")
    SYSTEM_STOPPED,

    @SerialName("batterySaver")
    BATTERY_SAVER,

    @SerialName("storageFull")
    STORAGE_FULL,

    @SerialName("timeLimit")
    TIME_LIMIT,
}

@Serializable
enum class AndroidNotificationPermissionState {
    @SerialName("notRequired")
    NOT_REQUIRED,

    @SerialName("unknown")
    UNKNOWN,

    @SerialName("granted")
    GRANTED,

    @SerialName("denied")
    DENIED,
}

@Serializable
data class AndroidBackgroundRuntimeReadiness(
    val hasDownloaderAdapter: Boolean = false,
    val hasNotificationFlow: Boolean = false,
    val notificationPermission: AndroidNotificationPermissionState = AndroidNotificationPermissionState.UNKNOWN,
    val hasDownloadWorkerRuntime: Boolean = false,
    val hasRenderAdapter: Boolean = false,
    val supportsRenderCheckpointing: Boolean = false,
) {
    val canRunDownloadInBackground: Boolean
        get() = hasDownloaderAdapter &&
            hasNotificationFlow &&
            hasDownloadWorkerRuntime &&
            notificationPermission != AndroidNotificationPermissionState.UNKNOWN &&
            notificationPermission != AndroidNotificationPermissionState.DENIED

    val canRunRenderInBackground: Boolean
        get() = hasRenderAdapter &&
            supportsRenderCheckpointing &&
            hasNotificationFlow &&
            notificationPermission != AndroidNotificationPermissionState.UNKNOWN &&
            notificationPermission != AndroidNotificationPermissionState.DENIED
}

@Serializable
data class AndroidBackgroundWorkPlan(
    val kind: AndroidBackgroundWorkKind,
    val title: String,
    val runner: AndroidBackgroundRunner,
    val status: AndroidBackgroundTaskStatus,
    val isProductionReady: Boolean,
    val isBackgroundEligible: Boolean,
    val isResumable: Boolean,
    val requirements: List<AndroidBackgroundRequirement>,
    val interruptionHandling: List<AndroidBackgroundInterruption>,
    val userVisibleStatus: String,
    val detail: String,
) {
    val requiresForeground: Boolean
        get() = !isBackgroundEligible ||
            runner == AndroidBackgroundRunner.FOREGROUND_ONLY ||
            requirements.contains(AndroidBackgroundRequirement.FOREGROUND_UNTIL_ADAPTER_EXISTS)
}

object AndroidBackgroundWorkPlanner {
    fun downloadPlan(
        hasDownloaderAdapter: Boolean = false,
        hasNotificationFlow: Boolean = false,
        notificationPermission: AndroidNotificationPermissionState = AndroidNotificationPermissionState.UNKNOWN,
        hasDownloadWorkerRuntime: Boolean = false,
    ): AndroidBackgroundWorkPlan {
        val readiness = AndroidBackgroundRuntimeReadiness(
            hasDownloaderAdapter = hasDownloaderAdapter,
            hasNotificationFlow = hasNotificationFlow,
            notificationPermission = notificationPermission,
            hasDownloadWorkerRuntime = hasDownloadWorkerRuntime,
        )
        val ready = readiness.canRunDownloadInBackground
        return AndroidBackgroundWorkPlan(
            kind = AndroidBackgroundWorkKind.DOWNLOAD,
            title = "后台下载",
            runner = AndroidBackgroundRunner.USER_INITIATED_DATA_TRANSFER,
            status = if (ready) {
                AndroidBackgroundTaskStatus.TRANSFER_ALLOWED
            } else {
                AndroidBackgroundTaskStatus.FOREGROUND_ONLY
            },
            isProductionReady = ready,
            isBackgroundEligible = ready,
            isResumable = ready,
            requirements = listOf(
                AndroidBackgroundRequirement.PLATFORM_ADAPTER,
                AndroidBackgroundRequirement.USER_VISIBLE_NOTIFICATION,
                AndroidBackgroundRequirement.NOTIFICATION_PERMISSION,
                AndroidBackgroundRequirement.WORKER_RUNTIME,
                AndroidBackgroundRequirement.NETWORK,
                AndroidBackgroundRequirement.APP_OWNED_STORAGE,
            ) + if (ready) {
                emptyList()
            } else {
                listOf(AndroidBackgroundRequirement.FOREGROUND_UNTIL_ADAPTER_EXISTS)
            },
            interruptionHandling = listOf(
                AndroidBackgroundInterruption.NETWORK_LOST,
                AndroidBackgroundInterruption.APP_STOPPED,
                AndroidBackgroundInterruption.SYSTEM_STOPPED,
                AndroidBackgroundInterruption.STORAGE_FULL,
            ),
            userVisibleStatus = if (ready) "可后台下载" else "待接入",
            detail = if (ready) {
                "下载任务通过用户发起的数据传输路径运行，并通过系统可见通知恢复。"
            } else if (notificationPermission == AndroidNotificationPermissionState.DENIED) {
                "通知权限未授权，后台下载不会启用；当前仍以前台下载运行。"
            } else {
                "后台下载仍在验证通知权限、前台服务和任务恢复；当前请保持应用打开。"
            },
        )
    }

    fun renderPlan(
        hasRenderAdapter: Boolean = false,
        supportsCheckpointing: Boolean = false,
        hasNotificationFlow: Boolean = false,
        notificationPermission: AndroidNotificationPermissionState = AndroidNotificationPermissionState.UNKNOWN,
    ): AndroidBackgroundWorkPlan {
        val readiness = AndroidBackgroundRuntimeReadiness(
            hasRenderAdapter = hasRenderAdapter,
            supportsRenderCheckpointing = supportsCheckpointing,
            hasNotificationFlow = hasNotificationFlow,
            notificationPermission = notificationPermission,
        )
        val ready = readiness.canRunRenderInBackground
        return AndroidBackgroundWorkPlan(
            kind = AndroidBackgroundWorkKind.RENDER,
            title = "后台渲染",
            runner = if (supportsCheckpointing) {
                AndroidBackgroundRunner.WORK_MANAGER
            } else {
                AndroidBackgroundRunner.FOREGROUND_SERVICE
            },
            status = if (ready) {
                AndroidBackgroundTaskStatus.SYSTEM_DEFERRED
            } else {
                AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER
            },
            isProductionReady = ready,
            isBackgroundEligible = ready,
            isResumable = ready,
            requirements = listOf(
                AndroidBackgroundRequirement.PLATFORM_ADAPTER,
                AndroidBackgroundRequirement.USER_VISIBLE_NOTIFICATION,
                AndroidBackgroundRequirement.NOTIFICATION_PERMISSION,
                AndroidBackgroundRequirement.APP_OWNED_STORAGE,
                AndroidBackgroundRequirement.CHECKPOINTING,
                AndroidBackgroundRequirement.BATTERY_NOT_LOW,
            ) + if (ready) {
                emptyList()
            } else {
                listOf(AndroidBackgroundRequirement.FOREGROUND_UNTIL_ADAPTER_EXISTS)
            },
            interruptionHandling = listOf(
                AndroidBackgroundInterruption.APP_STOPPED,
                AndroidBackgroundInterruption.SYSTEM_STOPPED,
                AndroidBackgroundInterruption.BATTERY_SAVER,
                AndroidBackgroundInterruption.STORAGE_FULL,
                AndroidBackgroundInterruption.TIME_LIMIT,
            ),
            userVisibleStatus = if (ready) "可排队后台渲染" else "待接入",
            detail = if (ready) {
                "渲染任务通过可恢复检查点和系统可见通知运行，系统仍可延后或中断。"
            } else if (notificationPermission == AndroidNotificationPermissionState.DENIED) {
                "通知权限未授权，后台渲染不会启用；当前仍需回到应用继续。"
            } else {
                "后台渲染仍在验证通知权限、检查点和渲染运行时；当前需回到应用继续。"
            },
        )
    }

    fun defaultCapabilityItems(
        runtimeReadiness: AndroidBackgroundRuntimeReadiness = AndroidBackgroundRuntimeReadiness(),
    ): List<AndroidBackgroundCapabilityItem> =
        listOf(
            downloadPlan(
                hasDownloaderAdapter = runtimeReadiness.hasDownloaderAdapter,
                hasNotificationFlow = runtimeReadiness.hasNotificationFlow,
                notificationPermission = runtimeReadiness.notificationPermission,
                hasDownloadWorkerRuntime = runtimeReadiness.hasDownloadWorkerRuntime,
            ),
            renderPlan(
                hasRenderAdapter = runtimeReadiness.hasRenderAdapter,
                supportsCheckpointing = runtimeReadiness.supportsRenderCheckpointing,
                hasNotificationFlow = runtimeReadiness.hasNotificationFlow,
                notificationPermission = runtimeReadiness.notificationPermission,
            ),
        ).map { plan ->
            AndroidBackgroundCapabilityItem(
                capability = when (plan.kind) {
                    AndroidBackgroundWorkKind.DOWNLOAD -> AndroidBackgroundCapability.DOWNLOAD
                    AndroidBackgroundWorkKind.RENDER -> AndroidBackgroundCapability.RENDER
                },
                title = plan.title,
                statusLabel = plan.userVisibleStatus,
                detail = plan.detail,
                isProductionReady = plan.isProductionReady,
            )
        }
}
