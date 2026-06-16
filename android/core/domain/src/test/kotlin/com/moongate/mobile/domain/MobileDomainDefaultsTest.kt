package com.moongate.mobile.domain

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MobileDomainDefaultsTest {
    @Test
    fun exportProfileDefaultsToTranslatedSubtitleFileWithoutRender() {
        val profile = MobileExportProfile()

        assertEquals(MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE, profile.subtitleMode)
        assertEquals(1080, profile.maxRenderHeight)
        assertFalse(profile.requiresVideoRender)
    }

    @Test
    fun backgroundPolicyNeverAllowsUnboundedExecution() {
        val policy = MobileBackgroundPolicy(
            execution = MobileBackgroundExecution.SCHEDULED_WORK,
            resumability = MobileBackgroundResumability.RESUMABLE,
            systemTimeLimitSeconds = null,
        )

        assertFalse(policy.allowsUnboundedBackgroundExecution)
        assertTrue(policy.isSystemLimited)
        assertTrue(policy.canResume)
    }

    @Test
    fun secureCredentialReferenceSerializationDoesNotContainSecret() {
        val reference = SecureCredentialReference(
            service = "translation",
            account = "primary",
            displayName = "Primary key",
        )

        val encoded = Json.encodeToString(reference)

        assertTrue(encoded.contains("translation"))
        assertTrue(encoded.contains("primary"))
        assertFalse(encoded.contains("secret", ignoreCase = true))
        assertFalse(encoded.contains("token", ignoreCase = true))
        assertFalse(encoded.contains("apiKey", ignoreCase = true))
    }

    @Test
    fun androidPlatformProfileIsConservativeByDefault() {
        val profile = MobilePlatformProfile.androidDefault

        assertEquals(MobilePlatform.ANDROID, profile.platform)
        assertEquals(MobileDesignSystem.MATERIAL3, profile.designSystem)
        assertEquals(
            listOf(
                MobileSurface.ADD,
                MobileSurface.QUEUE,
                MobileSurface.LIBRARY,
                MobileSurface.SETTINGS,
            ),
            profile.surfaces,
        )
        assertEquals(MobilePlatform.ANDROID, profile.capabilities.platform)
        assertTrue(profile.capabilities.supportedCapabilities.isEmpty())
        assertNull(profile.capabilities.maxRenderHeight)
        assertFalse(profile.capabilities.supports(MobileProcessingCapability.BACKGROUND_RENDER))
        assertFalse(profile.capabilities.supports(MobileProcessingCapability.LOCAL_TRANSLATION_MODEL))
        assertFalse(profile.capabilities.supports(MobileProcessingCapability.APPLE_INTELLIGENCE))
    }
}
