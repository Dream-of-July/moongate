package com.moongate.mobile.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AndroidBackgroundWorkPlannerTest {
    @Test
    fun downloadPlanStaysForegroundBoundUntilAdaptersAndNotificationsExist() {
        val plan = AndroidBackgroundWorkPlanner.downloadPlan()

        assertEquals(AndroidBackgroundWorkKind.DOWNLOAD, plan.kind)
        assertEquals(AndroidBackgroundRunner.USER_INITIATED_DATA_TRANSFER, plan.runner)
        assertEquals(AndroidBackgroundTaskStatus.FOREGROUND_ONLY, plan.status)
        assertFalse(plan.isProductionReady)
        assertFalse(plan.isBackgroundEligible)
        assertFalse(plan.isResumable)
        assertTrue(plan.requiresForeground)
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.PLATFORM_ADAPTER))
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.USER_VISIBLE_NOTIFICATION))
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.NOTIFICATION_PERMISSION))
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.WORKER_RUNTIME))
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.FOREGROUND_UNTIL_ADAPTER_EXISTS))
        assertTrue(plan.interruptionHandling.contains(AndroidBackgroundInterruption.NETWORK_LOST))
        assertTrue(plan.userVisibleStatus.contains("待接入"))
    }

    @Test
    fun downloadPlanCanBecomeBackgroundEligibleOnlyWithAdapterNotificationAndWorkerRuntime() {
        val plan = AndroidBackgroundWorkPlanner.downloadPlan(
            hasDownloaderAdapter = true,
            hasNotificationFlow = true,
            notificationPermission = AndroidNotificationPermissionState.GRANTED,
            hasDownloadWorkerRuntime = true,
        )

        assertEquals(AndroidBackgroundTaskStatus.TRANSFER_ALLOWED, plan.status)
        assertTrue(plan.isProductionReady)
        assertTrue(plan.isBackgroundEligible)
        assertTrue(plan.isResumable)
        assertFalse(plan.requiresForeground)
        assertFalse(plan.requirements.contains(AndroidBackgroundRequirement.FOREGROUND_UNTIL_ADAPTER_EXISTS))
    }

    @Test
    fun downloadPlanStaysForegroundBoundWhenNotificationPermissionOrWorkerRuntimeIsMissing() {
        val notificationOnly = AndroidBackgroundWorkPlanner.downloadPlan(
            hasDownloaderAdapter = true,
            hasNotificationFlow = true,
            notificationPermission = AndroidNotificationPermissionState.GRANTED,
            hasDownloadWorkerRuntime = false,
        )
        val denied = AndroidBackgroundWorkPlanner.downloadPlan(
            hasDownloaderAdapter = true,
            hasNotificationFlow = true,
            notificationPermission = AndroidNotificationPermissionState.DENIED,
            hasDownloadWorkerRuntime = true,
        )

        assertFalse(notificationOnly.isProductionReady)
        assertTrue(notificationOnly.requiresForeground)
        assertEquals(AndroidBackgroundTaskStatus.FOREGROUND_ONLY, notificationOnly.status)
        assertTrue(notificationOnly.detail.contains("后台下载仍在验证"))
        assertFalse(denied.isProductionReady)
        assertTrue(denied.detail.contains("通知权限未授权"))
    }

    @Test
    fun renderPlanStaysForegroundBoundUntilRendererAndCheckpointingExist() {
        val plan = AndroidBackgroundWorkPlanner.renderPlan()

        assertEquals(AndroidBackgroundWorkKind.RENDER, plan.kind)
        assertEquals(AndroidBackgroundRunner.FOREGROUND_SERVICE, plan.runner)
        assertEquals(AndroidBackgroundTaskStatus.RENDER_FOREGROUND_ONLY_PLACEHOLDER, plan.status)
        assertFalse(plan.isProductionReady)
        assertFalse(plan.isBackgroundEligible)
        assertFalse(plan.isResumable)
        assertTrue(plan.requiresForeground)
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.PLATFORM_ADAPTER))
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.NOTIFICATION_PERMISSION))
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.CHECKPOINTING))
        assertTrue(plan.requirements.contains(AndroidBackgroundRequirement.FOREGROUND_UNTIL_ADAPTER_EXISTS))
        assertTrue(plan.interruptionHandling.contains(AndroidBackgroundInterruption.BATTERY_SAVER))
        assertTrue(plan.interruptionHandling.contains(AndroidBackgroundInterruption.TIME_LIMIT))
    }

    @Test
    fun renderPlanUsesSystemDeferredWorkOnlyWhenCheckpointable() {
        val plan = AndroidBackgroundWorkPlanner.renderPlan(
            hasRenderAdapter = true,
            supportsCheckpointing = true,
            hasNotificationFlow = true,
            notificationPermission = AndroidNotificationPermissionState.GRANTED,
        )

        assertEquals(AndroidBackgroundRunner.WORK_MANAGER, plan.runner)
        assertEquals(AndroidBackgroundTaskStatus.SYSTEM_DEFERRED, plan.status)
        assertTrue(plan.isProductionReady)
        assertTrue(plan.isBackgroundEligible)
        assertTrue(plan.isResumable)
        assertFalse(plan.requiresForeground)
        assertTrue(plan.detail.contains("系统仍可延后或中断"))
    }

    @Test
    fun settingsDefaultCapabilitiesUseConservativeWorkPlans() {
        val state = AndroidSettingsState()

        assertEquals(
            listOf(AndroidBackgroundCapability.DOWNLOAD, AndroidBackgroundCapability.RENDER),
            state.backgroundCapabilities.map { it.capability },
        )
        assertTrue(state.backgroundCapabilities.none { it.isProductionReady })
        assertTrue(state.backgroundCapabilities.all { it.statusLabel.contains("待接入") })
        assertEquals(AndroidNotificationPermissionState.UNKNOWN, state.backgroundRuntimeReadiness.notificationPermission)
        assertEquals("允许通知", state.notificationPermissionAction.label)
        assertEquals(AndroidActionAvailability.ENABLED, state.notificationPermissionAction.availability)
    }
}
