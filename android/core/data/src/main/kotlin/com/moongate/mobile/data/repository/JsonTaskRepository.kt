package com.moongate.mobile.data.repository

import com.moongate.mobile.domain.MobileBackgroundExecution
import com.moongate.mobile.domain.MobileBackgroundPolicy
import com.moongate.mobile.domain.MobileBackgroundResumability
import com.moongate.mobile.domain.MobileTaskError
import com.moongate.mobile.domain.MobileTaskSnapshot
import com.moongate.mobile.domain.MobileTaskState
import com.moongate.mobile.domain.TaskRepository
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.util.concurrent.ConcurrentHashMap
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.readText
import kotlin.io.path.writeText
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class JsonTaskRepository(
    private val file: Path,
    private val json: Json = Json {
        encodeDefaults = true
        prettyPrint = true
    },
) : TaskRepository {
    private val lockFile: Path = file.resolveSibling("${file.fileName}.lock")
    private val processLock: Any = processLocks.computeIfAbsent(file.toAbsolutePath().normalize()) { Any() }

    override suspend fun loadTasks(): List<MobileTaskSnapshot> =
        withRepositoryLock {
            readTasksUnlocked()
        }

    override suspend fun saveTask(snapshot: MobileTaskSnapshot) {
        withRepositoryLock {
            val existingTasks = readTasksUnlocked()
            val existing = existingTasks.firstOrNull { it.id == snapshot.id }
            val nextSnapshot = existing.mergedWith(sanitizedForPersistence(snapshot))
            val tasks = existingTasks.filterNot { it.id == snapshot.id } + nextSnapshot
            writeUnlocked(tasks.sortedBy { it.id })
        }
    }

    override suspend fun removeTask(id: String) {
        withRepositoryLock {
            writeUnlocked(readTasksUnlocked().filterNot { it.id == id })
        }
    }

    private fun readTasksUnlocked(): List<MobileTaskSnapshot> {
        if (!file.exists()) {
            return emptyList()
        }
        val text = file.readText()
        if (text.isBlank()) {
            return emptyList()
        }
        return json.decodeFromString<List<MobileTaskSnapshot>>(text)
    }

    private fun writeUnlocked(tasks: List<MobileTaskSnapshot>) {
        file.parent?.createDirectories()
        val temp = Files.createTempFile(file.parent ?: Path.of("."), file.fileName.toString(), ".tmp")
        temp.writeText(json.encodeToString(tasks))
        Files.move(
            temp,
            file,
            java.nio.file.StandardCopyOption.REPLACE_EXISTING,
            java.nio.file.StandardCopyOption.ATOMIC_MOVE,
        )
    }

    private fun <T> withRepositoryLock(action: () -> T): T {
        file.parent?.createDirectories()
        lockFile.parent?.createDirectories()
        synchronized(processLock) {
            FileChannel.open(lockFile, StandardOpenOption.CREATE, StandardOpenOption.WRITE).use { channel ->
                channel.lock().use {
                    return action()
                }
            }
        }
    }

    private fun sanitizedForPersistence(snapshot: MobileTaskSnapshot): MobileTaskSnapshot =
        snapshot.copy(
            result = snapshot.result?.copy(
                artifacts = snapshot.result.artifacts.map { artifact ->
                    if (artifact.storageIdentifier.startsWith("source:")) {
                        artifact.copy(storageIdentifier = "mobile-source:${snapshot.id}")
                    } else {
                        artifact
                    }
                },
            ),
        )

    private fun MobileTaskSnapshot?.mergedWith(incoming: MobileTaskSnapshot): MobileTaskSnapshot =
        when {
            this != null &&
                !state.isTerminal &&
                incoming.state.isTerminal &&
                executionGenerationID != null &&
                incoming.executionGenerationID != null &&
                executionGenerationID != incoming.executionGenerationID -> this

            this != null && state.isTerminal && !incoming.state.isTerminal -> this
            else -> incoming
        }

    private val MobileTaskState.isTerminal: Boolean
        get() = this == MobileTaskState.COMPLETED || this == MobileTaskState.CANCELLED

    private companion object {
        val processLocks = ConcurrentHashMap<Path, Any>()
    }
}

object AndroidTaskRecoveryPolicy {
    fun recover(snapshot: MobileTaskSnapshot): MobileTaskSnapshot =
        when (snapshot.state) {
            MobileTaskState.DOWNLOADING,
            MobileTaskState.TRANSLATING,
            MobileTaskState.EXPORTING,
            -> recoverActive(snapshot)

            else -> snapshot
        }

    fun recoverAll(tasks: List<MobileTaskSnapshot>): List<MobileTaskSnapshot> =
        tasks.map(::recover)

    private fun recoverActive(snapshot: MobileTaskSnapshot): MobileTaskSnapshot =
        if (snapshot.backgroundPolicy.canResume) {
            snapshot.copy(
                state = MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE,
                backgroundPolicy = MobileBackgroundPolicy(
                    execution = MobileBackgroundExecution.SYSTEM_INTERRUPTED,
                    resumability = MobileBackgroundResumability.RESUMABLE,
                    limits = snapshot.backgroundPolicy.limits,
                ),
                error = MobileTaskError.SYSTEM_BACKGROUND_LIMIT,
            )
        } else {
            snapshot.copy(
                state = MobileTaskState.FAILED,
                error = MobileTaskError.SYSTEM_BACKGROUND_LIMIT,
            )
        }
}
