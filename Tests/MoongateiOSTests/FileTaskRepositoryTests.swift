@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

final class FileTaskRepositoryTests: XCTestCase {
    func testPersistsLoadsAndReplacesTasksWithoutSecrets() async throws {
        let directory = temporaryDirectory()
        let repository = try FileTaskRepository(directoryURL: directory)
        let reference = SecureCredentialReference(service: "translation.openai", account: "default")
        let task = MobileTaskSnapshot(
            id: "task-1",
            platform: .iOS,
            state: .downloading,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 4, totalUnitCount: 10),
            exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile),
            capabilities: MobileProcessingCapabilities(platform: .iOS, supportedCapabilities: [.download, .backgroundTransfer]),
            backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable),
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "metadata",
                    kind: .metadata,
                    displayName: reference.displayName ?? "translation.openai",
                    storageIdentifier: "queue/task-1"
                )
            ])
        )

        try await repository.saveTask(task)
        var loaded = try await repository.loadTasks()

        XCTAssertEqual(loaded, [task])

        var completed = task
        completed.state = .completed
        try await repository.saveTask(completed)
        loaded = try await repository.loadTasks()

        XCTAssertEqual(loaded, [completed])
        let stored = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(stored.contains("TEST_SECRET_VALUE_DO_NOT_STORE"))
        XCTAssertFalse(stored.contains("Authorization"))
        XCTAssertFalse(stored.contains("Bearer "))
        XCTAssertFalse(stored.contains("apiKey"))
    }

    func testRemoveTaskIsStableWhenTaskIsMissing() async throws {
        let repository = try FileTaskRepository(directoryURL: temporaryDirectory())

        try await repository.saveTask(MobileTaskSnapshot(id: "task-1", platform: .iOS))
        try await repository.removeTask(id: "missing")
        var loadedTasks = try await repository.loadTasks()
        var taskIDs = loadedTasks.map(\.id)
        XCTAssertEqual(taskIDs, ["task-1"])

        try await repository.removeTask(id: "task-1")
        loadedTasks = try await repository.loadTasks()
        taskIDs = loadedTasks.map(\.id)
        XCTAssertTrue(taskIDs.isEmpty)
    }

    func testSaveTaskSanitizesLegacySourceURLArtifactsBeforeWritingJSON() async throws {
        let directory = temporaryDirectory()
        let repository = try FileTaskRepository(directoryURL: directory)
        let signedURL = "https://cdn.example.com/private/video.mp4?token=SECRET_TOKEN&X-Amz-Signature=abc123&access_token=hidden"
        let task = MobileTaskSnapshot(
            id: "signed-task",
            platform: .iOS,
            state: .waiting,
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "metadata",
                    kind: .metadata,
                    displayName: "Signed video",
                    storageIdentifier: "source:\(signedURL)"
                ),
                MobileTaskArtifact(
                    id: "original",
                    kind: .originalMedia,
                    displayName: "Signed video.mp4",
                    storageIdentifier: "source:\(signedURL)"
                )
            ], primaryArtifactID: "original")
        )

        try await repository.saveTask(task)

        let stored = try String(contentsOf: directory.appendingPathComponent("mobile-tasks.json"))
        XCTAssertFalse(stored.contains(signedURL))
        XCTAssertFalse(stored.contains("SECRET_TOKEN"))
        XCTAssertFalse(stored.contains("X-Amz-Signature"))
        XCTAssertFalse(stored.contains("access_token"))
        XCTAssertFalse(stored.contains("source:https://"))

        let loaded = try await repository.loadTasks()
        XCTAssertEqual(
            loaded.first?.result?.primaryArtifact?.storageIdentifier,
            "mobile-source:signed-task"
        )
        XCTAssertEqual(
            loaded.first?.result?.artifacts.map(\.storageIdentifier),
            ["mobile-source:signed-task", "mobile-source:signed-task"]
        )
    }

    func testSourceReferenceStorePersistsOnlySafeDirectHTTPSMediaSources() async throws {
        let directory = temporaryDirectory()
        let store = try IOSSourceReferenceStore(directoryURL: directory)
        let plainSource = "https://cdn.example.com/video.mp4"

        XCTAssertTrue(IOSSourceReferenceStore.isPersistableSourceURL(plainSource))
        XCTAssertFalse(IOSSourceReferenceStore.isPersistableSourceURL("https://cdn.example.com/video.mp4?token=SECRET"))
        XCTAssertFalse(IOSSourceReferenceStore.isPersistableSourceURL("https://cdn.example.com/video.mp4#fragment"))
        XCTAssertFalse(IOSSourceReferenceStore.isPersistableSourceURL("http://cdn.example.com/video.mp4"))
        XCTAssertFalse(IOSSourceReferenceStore.isPersistableSourceURL("https://cdn.example.com/watch"))
        XCTAssertFalse(IOSSourceReferenceStore.isPersistableSourceURL("https://cdn.example.com/token/video.mp4"))
        XCTAssertFalse(IOSSourceReferenceStore.isPersistableSourceURL("https://user:secret@cdn.example.com/video.mp4"))

        try await store.saveSource(plainSource, forTaskID: "task-1")
        let savedSources = try await store.loadSources()
        XCTAssertEqual(savedSources["task-1"], plainSource)
        let sourceFile = directory.appendingPathComponent("mobile-source-references.json")
        let stored = try String(contentsOf: sourceFile)
        XCTAssertFalse(stored.contains("SECRET"))
        XCTAssertFalse(stored.contains("access_token"))

        try await store.removeSource(forTaskID: "task-1")
        let removedSources = try await store.loadSources()
        XCTAssertTrue(removedSources.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-file-task-repository-\(UUID().uuidString)", isDirectory: true)
    }
}
