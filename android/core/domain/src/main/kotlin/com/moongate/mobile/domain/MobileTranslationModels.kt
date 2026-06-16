package com.moongate.mobile.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

@Serializable
enum class TranslationProvider {
    @SerialName("anthropic")
    ANTHROPIC,

    @SerialName("openai")
    OPENAI,
}

@Serializable
enum class TranslationEngine {
    @SerialName("anthropicCompatible")
    ANTHROPIC_COMPATIBLE,

    @SerialName("openAICompatible")
    OPENAI_COMPATIBLE,

    @SerialName("appleTranslationLowLatency")
    APPLE_TRANSLATION_LOW_LATENCY,

    @SerialName("appleTranslationHighFidelity")
    APPLE_TRANSLATION_HIGH_FIDELITY,

    @SerialName("appleFoundationOnDevice")
    APPLE_FOUNDATION_ON_DEVICE,

    @SerialName("appleFoundationPCC")
    APPLE_FOUNDATION_PCC;

    val legacyProvider: TranslationProvider?
        get() = when (this) {
            ANTHROPIC_COMPATIBLE -> TranslationProvider.ANTHROPIC
            OPENAI_COMPATIBLE -> TranslationProvider.OPENAI
            APPLE_TRANSLATION_LOW_LATENCY,
            APPLE_TRANSLATION_HIGH_FIDELITY,
            APPLE_FOUNDATION_ON_DEVICE,
            APPLE_FOUNDATION_PCC,
            -> null
        }

    val requiresCloudConfiguration: Boolean
        get() = when (this) {
            ANTHROPIC_COMPATIBLE,
            OPENAI_COMPATIBLE,
            -> true

            APPLE_TRANSLATION_LOW_LATENCY,
            APPLE_TRANSLATION_HIGH_FIDELITY,
            APPLE_FOUNDATION_ON_DEVICE,
            APPLE_FOUNDATION_PCC,
            -> false
        }
}

@Serializable
data class TranslationContext(
    val sourceLanguage: String? = null,
    val targetLanguage: String = "zh-Hans",
)

@Serializable
data class TranslationReadinessIssue(
    val kind: Kind,
    val message: String = kind.defaultMessage,
) {
    @Serializable
    enum class Kind {
        @SerialName("needsConfiguration")
        NEEDS_CONFIGURATION,

        @SerialName("needsRuntimeVerification")
        NEEDS_RUNTIME_VERIFICATION,

        @SerialName("needsLanguageDownload")
        NEEDS_LANGUAGE_DOWNLOAD,

        @SerialName("unsupportedLanguagePair")
        UNSUPPORTED_LANGUAGE_PAIR,

        @SerialName("appleIntelligenceUnavailable")
        APPLE_INTELLIGENCE_UNAVAILABLE,

        @SerialName("modelUnavailable")
        MODEL_UNAVAILABLE,

        @SerialName("pccUnavailable")
        PCC_UNAVAILABLE,
    }
}

val TranslationReadinessIssue.Kind.defaultMessage: String
    get() = when (this) {
        TranslationReadinessIssue.Kind.NEEDS_CONFIGURATION -> "需要先完成翻译设置。"
        TranslationReadinessIssue.Kind.NEEDS_RUNTIME_VERIFICATION -> "需要先检测系统翻译能力。"
        TranslationReadinessIssue.Kind.NEEDS_LANGUAGE_DOWNLOAD -> "需要先下载对应语言。"
        TranslationReadinessIssue.Kind.UNSUPPORTED_LANGUAGE_PAIR -> "当前语言组合暂不支持。"
        TranslationReadinessIssue.Kind.APPLE_INTELLIGENCE_UNAVAILABLE -> "当前设备或系统不可用 Apple Intelligence。"
        TranslationReadinessIssue.Kind.MODEL_UNAVAILABLE -> "当前模型不可用。"
        TranslationReadinessIssue.Kind.PCC_UNAVAILABLE -> "Private Cloud Compute 当前不可用。"
    }

@Serializable
data class TranslationReadiness(
    val issues: List<TranslationReadinessIssue> = emptyList(),
) {
    val isReady: Boolean
        get() = issues.isEmpty()

    companion object {
        val ready = TranslationReadiness()
    }
}

@Serializable
data class SecureCredentialReference(
    val service: String,
    val account: String,
    val displayName: String? = null,
)

@Serializable
enum class MobileTranslationCredentialRequirement {
    @SerialName("none")
    NONE,

    @SerialName("secureCredential")
    SECURE_CREDENTIAL,

    @SerialName("localModel")
    LOCAL_MODEL,

    @SerialName("runtimeEntitlement")
    RUNTIME_ENTITLEMENT,
}

@Serializable
data class MobileTranslationConfiguration(
    val engine: TranslationEngine,
    val baseURL: String? = null,
    val model: String? = null,
    val credential: SecureCredentialReference? = null,
    val readiness: TranslationReadiness = conservativeTranslationReadiness(engine),
) {
    val credentialRequirement: MobileTranslationCredentialRequirement
        get() = when (engine) {
            TranslationEngine.ANTHROPIC_COMPATIBLE,
            TranslationEngine.OPENAI_COMPATIBLE,
            -> MobileTranslationCredentialRequirement.SECURE_CREDENTIAL

            TranslationEngine.APPLE_TRANSLATION_LOW_LATENCY,
            TranslationEngine.APPLE_TRANSLATION_HIGH_FIDELITY,
            TranslationEngine.APPLE_FOUNDATION_PCC,
            -> MobileTranslationCredentialRequirement.RUNTIME_ENTITLEMENT

            TranslationEngine.APPLE_FOUNDATION_ON_DEVICE ->
                MobileTranslationCredentialRequirement.LOCAL_MODEL
        }

    val usesCloudService: Boolean
        get() = when (engine) {
            TranslationEngine.ANTHROPIC_COMPATIBLE,
            TranslationEngine.OPENAI_COMPATIBLE,
            TranslationEngine.APPLE_FOUNDATION_PCC,
            -> true

            TranslationEngine.APPLE_TRANSLATION_LOW_LATENCY,
            TranslationEngine.APPLE_TRANSLATION_HIGH_FIDELITY,
            TranslationEngine.APPLE_FOUNDATION_ON_DEVICE,
            -> false
        }

    val isRunnableWithoutUserCredential: Boolean
        get() = credentialRequirement != MobileTranslationCredentialRequirement.SECURE_CREDENTIAL

    companion object {
        fun conservativeReadiness(engine: TranslationEngine): TranslationReadiness =
            conservativeTranslationReadiness(engine)
    }
}

fun conservativeTranslationReadiness(engine: TranslationEngine): TranslationReadiness =
    when (engine) {
        TranslationEngine.ANTHROPIC_COMPATIBLE,
        TranslationEngine.OPENAI_COMPATIBLE,
        -> TranslationReadiness(
            issues = listOf(
                TranslationReadinessIssue(
                    kind = TranslationReadinessIssue.Kind.NEEDS_CONFIGURATION,
                ),
            ),
        )

        TranslationEngine.APPLE_TRANSLATION_LOW_LATENCY,
        TranslationEngine.APPLE_TRANSLATION_HIGH_FIDELITY,
        -> TranslationReadiness(
            issues = listOf(
                TranslationReadinessIssue(
                    kind = TranslationReadinessIssue.Kind.NEEDS_RUNTIME_VERIFICATION,
                ),
                TranslationReadinessIssue(
                    kind = TranslationReadinessIssue.Kind.NEEDS_LANGUAGE_DOWNLOAD,
                ),
            ),
        )

        TranslationEngine.APPLE_FOUNDATION_ON_DEVICE -> TranslationReadiness(
            issues = listOf(
                TranslationReadinessIssue(
                    kind = TranslationReadinessIssue.Kind.APPLE_INTELLIGENCE_UNAVAILABLE,
                ),
                TranslationReadinessIssue(
                    kind = TranslationReadinessIssue.Kind.MODEL_UNAVAILABLE,
                ),
            ),
        )

        TranslationEngine.APPLE_FOUNDATION_PCC -> TranslationReadiness(
            issues = listOf(
                TranslationReadinessIssue(
                    kind = TranslationReadinessIssue.Kind.PCC_UNAVAILABLE,
                ),
            ),
        )
    }

@Serializable
data class MobileTranslationSegment(
    val id: String,
    val startTime: String,
    val endTime: String,
    val text: String,
)

@Serializable
data class MobileTranslationRequest(
    val segments: List<MobileTranslationSegment>,
    val context: TranslationContext,
)

@Serializable
data class MobileTranslationResult(
    val segments: List<MobileTranslationSegment>,
)

data class AndroidTranslationTransportRequest(
    val url: String,
    val method: String = "POST",
    val headers: Map<String, String>,
    val body: String,
)

object AndroidAPICompatibleTranslationPlanner {
    private const val ANTHROPIC_VERSION = "2023-06-01"

    fun plan(
        configuration: MobileTranslationConfiguration,
        request: MobileTranslationRequest,
        secret: String,
    ): AndroidTranslationTransportRequest {
        require(configuration.engine.requiresCloudConfiguration) {
            "Only API-compatible cloud translation engines can build transport requests."
        }
        val baseURL = configuration.baseURL?.trim().orEmpty()
        require(baseURL.isNotEmpty()) { "Translation base URL is required." }
        val model = configuration.model?.trim().orEmpty()
        require(model.isNotEmpty()) { "Translation model is required." }
        val normalizedSecret = normalizedBearerSecret(secret)
        require(normalizedSecret.isNotEmpty()) { "Translation credential is required." }

        return when (configuration.engine) {
            TranslationEngine.OPENAI_COMPATIBLE -> openAIRequest(
                baseURL = baseURL,
                model = model,
                request = request,
                normalizedSecret = normalizedSecret,
            )

            TranslationEngine.ANTHROPIC_COMPATIBLE -> anthropicRequest(
                baseURL = baseURL,
                model = model,
                request = request,
                normalizedSecret = normalizedSecret,
            )

            TranslationEngine.APPLE_TRANSLATION_LOW_LATENCY,
            TranslationEngine.APPLE_TRANSLATION_HIGH_FIDELITY,
            TranslationEngine.APPLE_FOUNDATION_ON_DEVICE,
            TranslationEngine.APPLE_FOUNDATION_PCC,
            -> error("Only API-compatible cloud translation engines can build transport requests.")
        }
    }

    private fun openAIRequest(
        baseURL: String,
        model: String,
        request: MobileTranslationRequest,
        normalizedSecret: String,
    ): AndroidTranslationTransportRequest {
        val url = endpointURL(baseURL, "/v1/responses")
        val body = buildJsonObject {
            put("model", model)
            put("instructions", translationInstruction(request.context.targetLanguage))
            put("input", numberedInput(request.segments))
            put("max_output_tokens", maxOutputTokens(request.segments))
            put("store", false)
        }
        return AndroidTranslationTransportRequest(
            url = url,
            headers = mapOf(
                "content-type" to "application/json",
                "Authorization" to "Bearer $normalizedSecret",
            ),
            body = body.toCompactJson(),
        )
    }

    private fun anthropicRequest(
        baseURL: String,
        model: String,
        request: MobileTranslationRequest,
        normalizedSecret: String,
    ): AndroidTranslationTransportRequest {
        val url = endpointURL(baseURL, "/v1/messages")
        val body = buildJsonObject {
            put("model", model)
            put("max_tokens", maxOutputTokens(request.segments))
            put("system", translationInstruction(request.context.targetLanguage))
            putJsonArray("messages") {
                add(buildJsonObject {
                    put("role", "user")
                    put("content", numberedInput(request.segments))
                })
            }
        }
        val headers = mutableMapOf(
            "content-type" to "application/json",
            "anthropic-version" to ANTHROPIC_VERSION,
            "x-api-key" to normalizedSecret,
        )
        val host = hostFromHTTPSURL(url)
        if (host != "api.anthropic.com") {
            headers["Authorization"] = "Bearer $normalizedSecret"
        }
        return AndroidTranslationTransportRequest(
            url = url,
            headers = headers,
            body = body.toCompactJson(),
        )
    }

    private fun endpointURL(baseURL: String, endpointPath: String): String {
        var base = baseURL.trim()
        while (base.endsWith("/")) {
            base = base.dropLast(1)
        }
        val path = if (endpointPath.startsWith("/")) endpointPath else "/$endpointPath"
        val lowerBase = base.lowercase()
        val lowerPath = path.lowercase()
        val url = when {
            lowerBase.endsWith(lowerPath) -> base
            lowerBase.endsWith("/v1") && lowerPath.startsWith("/v1/") ->
                base + path.drop("/v1".length)
            else -> base + path
        }

        require(hostFromHTTPSURL(url).isNotEmpty()) { "Translation base URL must be HTTPS with a host." }
        return url
    }

    private fun hostFromHTTPSURL(url: String): String {
        val trimmed = url.trim()
        require(!trimmed.startsWith("http://", ignoreCase = true)) {
            "Plain HTTP translation endpoints are not allowed."
        }
        require(trimmed.startsWith("https://", ignoreCase = true)) {
            "Translation base URL must use HTTPS."
        }
        val withoutScheme = trimmed.drop("https://".length)
        val host = withoutScheme
            .substringBefore("/")
            .substringBefore("?")
            .substringBefore("#")
            .substringBefore(":")
            .lowercase()
        return host
    }

    private fun translationInstruction(targetLanguage: String): String =
        "Translate each numbered subtitle segment to $targetLanguage. Preserve numbering as '<id>=<translation>'."

    private fun numberedInput(segments: List<MobileTranslationSegment>): String =
        segments.joinToString(separator = "\n") { "${it.id}=${it.text}" }

    private fun maxOutputTokens(segments: List<MobileTranslationSegment>): Int =
        maxOf(1024, segments.size * 128)

    private fun normalizedBearerSecret(secret: String): String {
        val trimmed = secret.trim()
        return if (trimmed.startsWith("bearer ", ignoreCase = true)) {
            trimmed.drop("bearer ".length).trim()
        } else {
            trimmed
        }
    }

    private fun JsonObject.toCompactJson(): String =
        Json.encodeToString(JsonObject.serializer(), this)
}

@Serializable
data class MobileSubtitleProcessingRequest(
    val sourceSubtitle: MobileTaskArtifact,
    val translation: MobileTranslationResult,
    val exportProfile: MobileExportProfile,
)

@Serializable
data class MobileRenderRequest(
    val sourceMedia: MobileTaskArtifact,
    val subtitles: List<MobileTaskArtifact> = emptyList(),
    val exportProfile: MobileExportProfile,
)
