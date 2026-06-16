package com.moongate.mobile.worker

import com.moongate.mobile.domain.MobileDownloadRequest
import com.moongate.mobile.domain.MobileExportProfile
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI
import java.nio.channels.FileChannel
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

data class AndroidBackgroundDownloadHandoff(
    val workHandle: String,
    val generationID: String,
    val state: State,
    val request: MobileDownloadRequest,
) {
    enum class State {
        ACTIVE,
        CANCELLED,
    }

    val isActive: Boolean
        get() = state == State.ACTIVE

    fun encode(): String =
        listOf(
            "workHandle" to workHandle,
            "generationID" to generationID,
            "state" to state.name,
            "id" to request.id,
            "sourceURL" to request.sourceURL,
            "candidateID" to request.candidateID,
            "videoID" to request.videoID,
            "formatID" to request.formatID,
            "subtitleIDs" to request.subtitleIDs.joinToString(","),
            "autoSubtitleIDs" to request.autoSubtitleIDs.joinToString(","),
            "preferredTitle" to request.preferredTitle.orEmpty(),
            "subtitleMode" to request.exportProfile.subtitleMode.name,
            "maxRenderHeight" to request.exportProfile.maxRenderHeight?.toString().orEmpty(),
        ).joinToString(separator = "\n") { (key, value) ->
            "$key=${value.percentEncoded()}"
        }

    companion object {
        fun decode(raw: String): AndroidBackgroundDownloadHandoff? {
            val fields = raw
                .lineSequence()
                .mapNotNull { line ->
                    val separatorIndex = line.indexOf('=')
                    if (separatorIndex <= 0) {
                        null
                    } else {
                        line.substring(0, separatorIndex) to line.substring(separatorIndex + 1).percentDecoded()
                    }
                }
                .toMap()
            val workHandle = fields["workHandle"]?.takeIf { it.isOpaqueWorkHandle() } ?: return null
            val generationID = fields["generationID"]?.takeIf { it.isOpaqueWorkGenerationID() } ?: return null
            val state = fields["state"]
                ?.let { runCatching { State.valueOf(it) }.getOrNull() }
                ?: State.ACTIVE
            val sourceURL = fields["sourceURL"]?.takeIf { it.isSafeBackgroundSourceURL() } ?: return null
            val subtitleMode = fields["subtitleMode"]
                ?.let { runCatching { MobileExportProfile.SubtitleMode.valueOf(it) }.getOrNull() }
                ?: MobileExportProfile.SubtitleMode.TRANSLATED_SUBTITLE_FILE
            val maxRenderHeight = fields["maxRenderHeight"]?.toIntOrNull()
            val request = MobileDownloadRequest(
                id = fields["id"]?.takeIf { it.isNotBlank() } ?: return null,
                sourceURL = sourceURL,
                candidateID = fields["candidateID"]?.takeIf { it.isNotBlank() } ?: return null,
                videoID = fields["videoID"]?.takeIf { it.isNotBlank() } ?: return null,
                formatID = fields["formatID"]?.takeIf { it.isNotBlank() } ?: return null,
                subtitleIDs = fields["subtitleIDs"].orEmpty().csvList(),
                autoSubtitleIDs = fields["autoSubtitleIDs"].orEmpty().csvList(),
                exportProfile = MobileExportProfile(
                    subtitleMode = subtitleMode,
                    maxRenderHeight = maxRenderHeight,
                ),
                preferredTitle = fields["preferredTitle"]?.takeIf { it.isNotBlank() },
            ).safeForBackgroundHandoff()
            return AndroidBackgroundDownloadHandoff(
                workHandle = workHandle,
                generationID = generationID,
                state = state,
                request = request,
            )
        }
    }
}

class AndroidBackgroundDownloadHandoffStore(
    private val directory: File,
) {
    fun save(descriptor: AndroidBackgroundWorkDescriptor, request: MobileDownloadRequest): AndroidBackgroundDownloadHandoff {
        val handoff = AndroidBackgroundDownloadHandoff(
            workHandle = descriptor.workHandle,
            generationID = descriptor.generationID,
            state = AndroidBackgroundDownloadHandoff.State.ACTIVE,
            request = request.safeForBackgroundHandoff(),
        )
        directory.mkdirs()
        withHandoffLock(descriptor.workHandle) {
            writeHandoffAtomically(fileFor(descriptor.workHandle), handoff.encode())
        }
        return handoff
    }

    fun load(workHandle: String): AndroidBackgroundDownloadHandoff? {
        return withHandoffLock(workHandle) {
            val file = fileFor(workHandle)
            if (!file.exists()) {
                return@withHandoffLock null
            }
            val handoff = AndroidBackgroundDownloadHandoff.decode(file.readText(StandardCharsets.UTF_8))
                ?: return@withHandoffLock null
            handoff.takeIf { it.workHandle == workHandle }
        }
    }

    fun cancelLatest(workHandle: String): AndroidBackgroundDownloadHandoff? =
        cancelIf(workHandle) { true }

    fun cancelIfGenerationMatches(
        workHandle: String,
        generationID: String,
    ): AndroidBackgroundDownloadHandoff? {
        require(generationID.isOpaqueWorkGenerationID()) { "Invalid Android background work generation." }
        return cancelIf(workHandle) { handoff -> handoff.generationID == generationID }
    }

    fun remove(workHandle: String) {
        withHandoffLock(workHandle) {
            deleteHandoffFile(fileFor(workHandle))
        }
    }

    fun removeIfGenerationMatches(
        workHandle: String,
        generationID: String,
    ): Boolean {
        require(generationID.isOpaqueWorkGenerationID()) { "Invalid Android background work generation." }
        return withHandoffLock(workHandle) {
            val file = fileFor(workHandle)
            if (!file.exists()) {
                return@withHandoffLock false
            }
            val handoff = AndroidBackgroundDownloadHandoff.decode(file.readText(StandardCharsets.UTF_8))
                ?: return@withHandoffLock false
            if (handoff.workHandle != workHandle || handoff.generationID != generationID) {
                return@withHandoffLock false
            }
            deleteHandoffFile(file)
            true
        }
    }

    fun isActiveGeneration(
        workHandle: String,
        generationID: String,
    ): Boolean {
        require(generationID.isOpaqueWorkGenerationID()) { "Invalid Android background work generation." }
        return withHandoffLock(workHandle) {
            val file = fileFor(workHandle)
            if (!file.exists()) {
                return@withHandoffLock false
            }
            val handoff = AndroidBackgroundDownloadHandoff.decode(file.readText(StandardCharsets.UTF_8))
                ?: return@withHandoffLock false
            handoff.workHandle == workHandle &&
                handoff.generationID == generationID &&
                handoff.isActive
        }
    }

    private fun cancelIf(
        workHandle: String,
        shouldCancel: (AndroidBackgroundDownloadHandoff) -> Boolean,
    ): AndroidBackgroundDownloadHandoff? {
        return withHandoffLock(workHandle) {
            val file = fileFor(workHandle)
            val existing = if (file.exists()) {
                AndroidBackgroundDownloadHandoff.decode(file.readText(StandardCharsets.UTF_8))
            } else {
                null
            }?.takeIf { handoff ->
                handoff.workHandle == workHandle && shouldCancel(handoff)
            } ?: return@withHandoffLock null
            val cancelled = existing.copy(state = AndroidBackgroundDownloadHandoff.State.CANCELLED)
            writeHandoffAtomically(file, cancelled.encode())
            cancelled
        }
    }

    private fun fileFor(workHandle: String): File {
        require(workHandle.isOpaqueWorkHandle()) { "Invalid Android background work handle." }
        return File(directory, "$workHandle.handoff")
    }

    private fun writeHandoffAtomically(
        target: File,
        encoded: String,
    ) {
        directory.mkdirs()
        val temp = File.createTempFile("${target.name}.", ".tmp", directory)
        try {
            temp.writeText(encoded, StandardCharsets.UTF_8)
            Files.move(
                temp.toPath(),
                target.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE,
            )
        } finally {
            temp.delete()
        }
    }

    private fun deleteHandoffFile(file: File) {
        if (file.exists() && !file.delete()) {
            throw IllegalStateException("Could not delete Android background handoff.")
        }
    }

    private fun <T> withHandoffLock(
        workHandle: String,
        action: () -> T,
    ): T {
        require(workHandle.isOpaqueWorkHandle()) { "Invalid Android background work handle." }
        val lockFile = lockFileFor(workHandle)
        lockFile.parentFile?.mkdirs()
        val lockKey = lockFile.toPath().toAbsolutePath().normalize()
        val processLock = processLocks.computeIfAbsent(lockKey) { Any() }
        synchronized(processLock) {
            FileChannel.open(lockFile.toPath(), StandardOpenOption.CREATE, StandardOpenOption.WRITE).use { channel ->
                channel.lock().use {
                    return action()
                }
            }
        }
    }

    private fun lockFileFor(workHandle: String): File {
        val parent = directory.parentFile ?: directory
        return File(parent, "${directory.name}-$workHandle.lock")
    }

    private companion object {
        val processLocks = ConcurrentHashMap<Path, Any>()
    }
}

private fun MobileDownloadRequest.safeForBackgroundHandoff(): MobileDownloadRequest {
    require(id.isNotBlank()) { "Background download task id is required." }
    require(sourceURL.isSafeBackgroundSourceURL()) {
        "Background download source must be a direct HTTPS media URL without credentials, query, or fragment."
    }
    return this
}

internal fun String.isSafeBackgroundSourceURL(): Boolean {
    val uri = runCatching { URI(trim()) }.getOrNull() ?: return false
    val path = uri.path.orEmpty().lowercase(Locale.US)
    val lowered = lowercase(Locale.US)
    return uri.scheme.equals("https", ignoreCase = true) &&
        !uri.host.isNullOrBlank() &&
        uri.rawUserInfo == null &&
        uri.rawQuery == null &&
        uri.rawFragment == null &&
        listOf(".mp4", ".mov", ".m4v", ".webm").any { path.endsWith(it) } &&
        !lowered.contains("token") &&
        !lowered.contains("signature") &&
        !lowered.contains("access_key")
}

internal fun String.isOpaqueWorkHandle(): Boolean =
    startsWith("moongate-work-") &&
        drop("moongate-work-".length).length == 64 &&
        drop("moongate-work-".length).all { it in '0'..'9' || it in 'a'..'f' }

internal fun String.isOpaqueWorkGenerationID(): Boolean =
    startsWith("moongate-generation-") &&
        drop("moongate-generation-".length).length == 64 &&
        drop("moongate-generation-".length).all { it in '0'..'9' || it in 'a'..'f' }

private fun String.csvList(): List<String> =
    split(",").mapNotNull { value ->
        value.trim().takeIf { it.isNotEmpty() }
    }

private fun String.percentEncoded(): String =
    buildString {
        for (byte in toByteArray(StandardCharsets.UTF_8)) {
            val value = byte.toInt().and(0xff)
            if (value in 'a'.code..'z'.code ||
                value in 'A'.code..'Z'.code ||
                value in '0'.code..'9'.code ||
                value == '-'.code ||
                value == '_'.code ||
                value == '.'.code
            ) {
                append(value.toChar())
            } else {
                append('%')
                append(value.toString(16).padStart(2, '0'))
            }
        }
    }

private fun String.percentDecoded(): String {
    val bytes = ByteArrayOutputStream()
    var index = 0
    while (index < length) {
        if (this[index] == '%' && index + 2 < length) {
            val value = substring(index + 1, index + 3).toIntOrNull(16)
            if (value != null) {
                bytes.write(value)
                index += 3
                continue
            }
        }
        bytes.write(this[index].toString().toByteArray(StandardCharsets.UTF_8))
        index += 1
    }
    return String(bytes.toByteArray(), StandardCharsets.UTF_8)
}
