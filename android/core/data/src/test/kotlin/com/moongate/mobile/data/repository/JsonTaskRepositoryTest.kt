package com.moongate.mobile.data.repository

import com.moongate.mobile.domain.MobileBackgroundExecution
import com.moongate.mobile.domain.MobileBackgroundPolicy
import com.moongate.mobile.domain.MobileBackgroundResumability
import com.moongate.mobile.domain.MobileArtifactKind
import com.moongate.mobile.domain.MobilePlatform
import com.moongate.mobile.domain.MobileTaskArtifact
import com.moongate.mobile.domain.MobileTaskError
import com.moongate.mobile.domain.MobileTaskProgress
import com.moongate.mobile.domain.MobileTaskResult
import com.moongate.mobile.domain.MobileTaskSnapshot
import com.moongate.mobile.domain.MobileTaskState
import com.moongate.mobile.domain.AndroidImportedFile
import com.moongate.mobile.domain.AndroidOfflineFileImportPlanner
import java.nio.file.Files
import kotlin.io.path.readText
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class JsonTaskRepositoryTest {
    @Test
    fun persistsReplacesAndRemovesTasksWithoutSecrets() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-repository")
        val file = directory.resolve("tasks.json")
        val repository = JsonTaskRepository(file)

        val snapshot = MobileTaskSnapshot(
            id = "task-1",
            platform = MobilePlatform.ANDROID,
            state = MobileTaskState.DOWNLOADING,
            progress = MobileTaskProgress(completedUnitCount = 4, totalUnitCount = 10),
            backgroundPolicy = MobileBackgroundPolicy(
                execution = MobileBackgroundExecution.BACKGROUND_TRANSFER,
                resumability = MobileBackgroundResumability.RESUMABLE,
            ),
        )

        repository.saveTask(snapshot)
        repository.saveTask(snapshot.copy(state = MobileTaskState.COMPLETED))

        assertEquals(listOf(MobileTaskState.COMPLETED), repository.loadTasks().map { it.state })
        val stored = file.readText()
        assertFalse(stored.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
        assertFalse(stored.contains("Authorization"))
        assertFalse(stored.contains("Bearer "))
        assertFalse(stored.contains("apiKey"))

        repository.removeTask("task-1")
        assertEquals(emptyList(), repository.loadTasks())
    }

    @Test
    fun independentInstancesMergeWritesThroughSharedRepositoryLock() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-repository-shared-lock")
        val file = directory.resolve("tasks.json")
        val appRepository = JsonTaskRepository(file)
        val workerRepository = JsonTaskRepository(file)

        appRepository.saveTask(taskSnapshot("app-task", MobileTaskState.DOWNLOADING))
        workerRepository.saveTask(taskSnapshot("worker-task", MobileTaskState.COMPLETED))

        assertEquals(
            listOf("app-task", "worker-task"),
            appRepository.loadTasks().map { it.id }.sorted(),
        )
        assertFalse(file.readText().contains(".lock"))
    }

    @Test
    fun staleAppSnapshotCannotRevertWorkerCompletedTask() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-repository-stale-complete")
        val file = directory.resolve("tasks.json")
        val appRepository = JsonTaskRepository(file)
        val workerRepository = JsonTaskRepository(file)

        val oldAppSnapshot = taskSnapshot("task-1", MobileTaskState.DOWNLOADING)
        workerRepository.saveTask(taskSnapshot("task-1", MobileTaskState.COMPLETED))
        appRepository.saveTask(oldAppSnapshot)

        assertEquals(MobileTaskState.COMPLETED, appRepository.loadTasks().single().state)
    }

    @Test
    fun failedTaskCanStillMoveBackToDownloadingForUserRetry() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-repository-retry")
        val file = directory.resolve("tasks.json")
        val repository = JsonTaskRepository(file)

        repository.saveTask(taskSnapshot("task-1", MobileTaskState.FAILED))
        repository.saveTask(taskSnapshot("task-1", MobileTaskState.DOWNLOADING))

        assertEquals(MobileTaskState.DOWNLOADING, repository.loadTasks().single().state)
    }

    @Test
    fun oldWorkerGenerationCannotOverwriteNewerTaskGeneration() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-repository-generation")
        val file = directory.resolve("tasks.json")
        val repository = JsonTaskRepository(file)

        repository.saveTask(
            taskSnapshot(
                id = "task-1",
                state = MobileTaskState.DOWNLOADING,
                generationID = "moongate-generation-new",
            ),
        )
        repository.saveTask(
            taskSnapshot(
                id = "task-1",
                state = MobileTaskState.COMPLETED,
                generationID = "moongate-generation-old",
            ),
        )

        val task = repository.loadTasks().single()
        assertEquals(MobileTaskState.DOWNLOADING, task.state)
        assertEquals("moongate-generation-new", task.executionGenerationID)
    }

    @Test
    fun newerTaskGenerationCanStartAfterOlderTerminalGeneration() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-repository-generation-restart")
        val file = directory.resolve("tasks.json")
        val repository = JsonTaskRepository(file)

        repository.saveTask(
            taskSnapshot(
                id = "task-1",
                state = MobileTaskState.COMPLETED,
                generationID = "moongate-generation-old",
            ),
        )
        repository.saveTask(
            taskSnapshot(
                id = "task-1",
                state = MobileTaskState.DOWNLOADING,
                generationID = "moongate-generation-new",
            ),
        )

        val task = repository.loadTasks().single()
        assertEquals(MobileTaskState.DOWNLOADING, task.state)
        assertEquals("moongate-generation-new", task.executionGenerationID)
    }

    @Test
    fun recoveryMovesActiveSystemWorkToHonestForegroundState() {
        val resumable = MobileTaskSnapshot(
            id = "resumable",
            platform = MobilePlatform.ANDROID,
            state = MobileTaskState.EXPORTING,
            backgroundPolicy = MobileBackgroundPolicy(
                execution = MobileBackgroundExecution.SYSTEM_DEFERRED,
                resumability = MobileBackgroundResumability.RESUMABLE,
            ),
        )
        val nonResumable = MobileTaskSnapshot(
            id = "non-resumable",
            platform = MobilePlatform.ANDROID,
            state = MobileTaskState.EXPORTING,
            backgroundPolicy = MobileBackgroundPolicy(
                execution = MobileBackgroundExecution.SYSTEM_INTERRUPTED,
                resumability = MobileBackgroundResumability.NON_RESUMABLE,
            ),
        )

        val recovered = AndroidTaskRecoveryPolicy.recoverAll(listOf(resumable, nonResumable))

        assertEquals(MobileTaskState.NEEDS_FOREGROUND_TO_CONTINUE, recovered[0].state)
        assertEquals(MobileTaskError.SYSTEM_BACKGROUND_LIMIT, recovered[0].error)
        assertEquals(MobileTaskState.FAILED, recovered[1].state)
        assertEquals(MobileTaskError.SYSTEM_BACKGROUND_LIMIT, recovered[1].error)
    }

    @Test
    fun saveTaskSanitizesLegacySourceURLArtifactsBeforeWritingJson() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-source-sanitize")
        val file = directory.resolve("tasks.json")
        val repository = JsonTaskRepository(file)
        val signedURL = "https://cdn.example.com/private/video.mp4?token=SECRET_TOKEN&X-Amz-Signature=abc123&access_token=hidden"
        val snapshot = MobileTaskSnapshot(
            id = "signed-task",
            platform = MobilePlatform.ANDROID,
            state = MobileTaskState.COMPLETED,
            result = MobileTaskResult(
                artifacts = listOf(
                    MobileTaskArtifact(
                        id = "original",
                        kind = MobileArtifactKind.ORIGINAL_MEDIA,
                        displayName = "private.mp4",
                        storageIdentifier = "source:$signedURL",
                    ),
                    MobileTaskArtifact(
                        id = "transcript",
                        kind = MobileArtifactKind.TRANSCRIPT,
                        displayName = "private.en.srt",
                        storageIdentifier = "source:$signedURL",
                    ),
                    MobileTaskArtifact(
                        id = "metadata",
                        kind = MobileArtifactKind.METADATA,
                        displayName = "private",
                        storageIdentifier = "source:$signedURL",
                    ),
                ),
                primaryArtifactID = "original",
            ),
        )

        repository.saveTask(snapshot)

        val stored = file.readText()
        assertFalse(stored.contains(signedURL))
        assertFalse(stored.contains("SECRET_TOKEN"))
        assertFalse(stored.contains("X-Amz-Signature"))
        assertFalse(stored.contains("access_token"))
        assertFalse(stored.contains("source:https://"))
        assertEquals(
            listOf("mobile-source:signed-task", "mobile-source:signed-task", "mobile-source:signed-task"),
            repository.loadTasks().single().result?.artifacts?.map { it.storageIdentifier },
        )
    }

    @Test
    fun importedFileTaskPersistsWithoutRawContentUri() = runSuspend {
        val directory = Files.createTempDirectory("moongate-json-task-import")
        val file = directory.resolve("tasks.json")
        val repository = JsonTaskRepository(file)
        val task = AndroidOfflineFileImportPlanner.taskSnapshot(
            AndroidImportedFile(
                id = "doc-789",
                displayName = "imported.mp4",
                mimeType = "video/mp4",
                byteCount = 128L,
            ),
        )

        repository.saveTask(task)

        val stored = file.readText()
        assertFalse(stored.contains("content://"))
        assertFalse(stored.contains("file://"))
        assertFalse(stored.contains("video/mp4"))
        assertEquals("android-import:doc-789", repository.loadTasks().single().result?.primaryArtifact?.storageIdentifier)
    }

    private fun <T> runSuspend(block: suspend () -> T): T {
        var outcome: Result<T>? = null
        block.startCoroutine(
            object : Continuation<T> {
                override val context = EmptyCoroutineContext

                override fun resumeWith(result: Result<T>) {
                    outcome = result
                }
            },
        )
        return (outcome ?: error("Suspend block did not complete synchronously")).getOrThrow()
    }

    private fun taskSnapshot(
        id: String,
        state: MobileTaskState,
        generationID: String? = null,
    ): MobileTaskSnapshot =
        MobileTaskSnapshot(
            id = id,
            platform = MobilePlatform.ANDROID,
            state = state,
            executionGenerationID = generationID,
            backgroundPolicy = MobileBackgroundPolicy(
                execution = MobileBackgroundExecution.FOREGROUND_REQUIRED,
                resumability = MobileBackgroundResumability.NON_RESUMABLE,
            ),
        )
}
