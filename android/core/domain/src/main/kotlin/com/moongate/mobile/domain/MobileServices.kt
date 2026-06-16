package com.moongate.mobile.domain

fun interface MobileProgressSink {
    fun onProgress(progress: MobileTaskProgress)
}

interface MobileParser {
    suspend fun resolveCandidates(input: MobileInputSource): List<MobileVideoCandidate>
    suspend fun analyze(candidate: MobileVideoCandidate): MobileVideoInfo
}

interface MobileDownloadEngine {
    suspend fun download(
        request: MobileDownloadRequest,
        progress: MobileProgressSink,
    ): MobileTaskResult
}

interface MobileTranslationProvider {
    suspend fun readiness(context: TranslationContext): TranslationReadiness
    suspend fun translate(request: MobileTranslationRequest): MobileTranslationResult
}

interface SubtitleProcessor {
    suspend fun process(
        request: MobileSubtitleProcessingRequest,
        progress: MobileProgressSink,
    ): MobileTaskArtifact
}

interface RenderExporter {
    suspend fun export(
        request: MobileRenderRequest,
        progress: MobileProgressSink,
    ): MobileTaskResult
}

interface SecureCredentialStore {
    suspend fun saveCredential(secret: String, reference: SecureCredentialReference): SecureCredentialReference
    suspend fun deleteCredential(reference: SecureCredentialReference)
    suspend fun hasCredential(reference: SecureCredentialReference): Boolean
    suspend fun credential(reference: SecureCredentialReference): String?
}

interface TaskRepository {
    suspend fun loadTasks(): List<MobileTaskSnapshot>
    suspend fun saveTask(snapshot: MobileTaskSnapshot)
    suspend fun removeTask(id: String)
}
