package com.moongate.mobile.domain

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AndroidAPICompatibleTranslationPlannerTest {
    @Test
    fun buildsOpenAIResponsesRequestWithoutPersistingSecretInConfiguration() {
        val configuration = MobileTranslationConfiguration(
            engine = TranslationEngine.OPENAI_COMPATIBLE,
            baseURL = " https://api.openai.com/ ",
            model = "gpt-5-mini",
            credential = SecureCredentialReference(
                service = "translation.openai",
                account = "default",
            ),
        )

        val request = AndroidAPICompatibleTranslationPlanner.plan(
            configuration = configuration,
            request = translationRequest(),
            secret = "TEST_SECRET_VALUE_DO_NOT_STORE",
        )
        val encodedConfiguration = Json.encodeToString(configuration)

        assertEquals("https://api.openai.com/v1/responses", request.url)
        assertEquals("POST", request.method)
        assertEquals("application/json", request.headers["content-type"])
        assertEquals("Bearer TEST_SECRET_VALUE_DO_NOT_STORE", request.headers["Authorization"])
        assertFalse(request.headers.containsKey("x-api-key"))
        assertTrue(request.body.contains("\"model\":\"gpt-5-mini\""))
        assertTrue(request.body.contains("\"store\":false"))
        assertTrue(request.body.contains("\"input\":\"1=Hello\\n2=world\""))
        assertFalse(encodedConfiguration.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
        assertFalse(encodedConfiguration.contains("Authorization"))
        assertFalse(encodedConfiguration.contains("Bearer "))
    }

    @Test
    fun buildsAnthropicGatewayRequestWithCompatibleAuthorizationHeaders() {
        val request = AndroidAPICompatibleTranslationPlanner.plan(
            configuration = MobileTranslationConfiguration(
                engine = TranslationEngine.ANTHROPIC_COMPATIBLE,
                baseURL = "https://gateway.example.com/v1",
                model = "claude-compatible",
            ),
            request = translationRequest(),
            secret = "TEST_SECRET_VALUE_DO_NOT_STORE",
        )

        assertEquals("https://gateway.example.com/v1/messages", request.url)
        assertEquals("POST", request.method)
        assertEquals("application/json", request.headers["content-type"])
        assertEquals("TEST_SECRET_VALUE_DO_NOT_STORE", request.headers["x-api-key"])
        assertEquals("Bearer TEST_SECRET_VALUE_DO_NOT_STORE", request.headers["Authorization"])
        assertEquals("2023-06-01", request.headers["anthropic-version"])
        assertTrue(request.body.contains("\"model\":\"claude-compatible\""))
        assertTrue(request.body.contains("\"max_tokens\":1024"))
        assertTrue(request.body.contains("\"messages\":[{\"role\":\"user\",\"content\":\"1=Hello\\n2=world\"}]"))
    }

    @Test
    fun officialAnthropicRequestDoesNotSendAuthorizationHeader() {
        val request = AndroidAPICompatibleTranslationPlanner.plan(
            configuration = MobileTranslationConfiguration(
                engine = TranslationEngine.ANTHROPIC_COMPATIBLE,
                baseURL = "https://api.anthropic.com",
                model = "claude-haiku-4-5",
            ),
            request = translationRequest(),
            secret = "TEST_SECRET_VALUE_DO_NOT_STORE",
        )

        assertEquals("https://api.anthropic.com/v1/messages", request.url)
        assertEquals("TEST_SECRET_VALUE_DO_NOT_STORE", request.headers["x-api-key"])
        assertFalse(request.headers.containsKey("Authorization"))
    }

    @Test
    fun rejectsInvalidConfigurationBeforeBuildingRequest() {
        val validRequest = translationRequest()

        assertFailsWith<IllegalArgumentException> {
            AndroidAPICompatibleTranslationPlanner.plan(
                configuration = MobileTranslationConfiguration(
                    engine = TranslationEngine.OPENAI_COMPATIBLE,
                    baseURL = "http://api.example.com",
                    model = "gpt-5-mini",
                ),
                request = validRequest,
                secret = "TEST_SECRET_VALUE_DO_NOT_STORE",
            )
        }
        assertFailsWith<IllegalArgumentException> {
            AndroidAPICompatibleTranslationPlanner.plan(
                configuration = MobileTranslationConfiguration(
                    engine = TranslationEngine.OPENAI_COMPATIBLE,
                    baseURL = "",
                    model = "gpt-5-mini",
                ),
                request = validRequest,
                secret = "TEST_SECRET_VALUE_DO_NOT_STORE",
            )
        }
        assertFailsWith<IllegalArgumentException> {
            AndroidAPICompatibleTranslationPlanner.plan(
                configuration = MobileTranslationConfiguration(
                    engine = TranslationEngine.OPENAI_COMPATIBLE,
                    baseURL = "https://api.openai.com",
                    model = " ",
                ),
                request = validRequest,
                secret = "TEST_SECRET_VALUE_DO_NOT_STORE",
            )
        }
        assertFailsWith<IllegalArgumentException> {
            AndroidAPICompatibleTranslationPlanner.plan(
                configuration = MobileTranslationConfiguration(
                    engine = TranslationEngine.OPENAI_COMPATIBLE,
                    baseURL = "https://api.openai.com",
                    model = "gpt-5-mini",
                ),
                request = validRequest,
                secret = " ",
            )
        }
        assertFailsWith<IllegalArgumentException> {
            AndroidAPICompatibleTranslationPlanner.plan(
                configuration = MobileTranslationConfiguration(
                    engine = TranslationEngine.APPLE_TRANSLATION_LOW_LATENCY,
                ),
                request = validRequest,
                secret = "TEST_SECRET_VALUE_DO_NOT_STORE",
            )
        }
    }

    private fun translationRequest() = MobileTranslationRequest(
        segments = listOf(
            MobileTranslationSegment(
                id = "1",
                startTime = "00:00:01,000",
                endTime = "00:00:02,000",
                text = "Hello",
            ),
            MobileTranslationSegment(
                id = "2",
                startTime = "00:00:02,000",
                endTime = "00:00:03,000",
                text = "world",
            ),
        ),
        context = TranslationContext(sourceLanguage = "en", targetLanguage = "zh-Hans"),
    )
}
