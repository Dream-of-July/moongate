@testable import MoongateMobileCore
@testable import MoongateiOS
import Foundation
import XCTest

final class IOSContinuedProcessingTaskHandlerTests: XCTestCase {
    func testProgressUpdatePersistsTaskAndMirrorsSystemProgress() async throws {
        let repository = RecordingHandlerTaskRepository(tasks: [
            renderTask(
                id: "task-render",
                progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 0, totalUnitCount: 10)
            )
        ])
        let handler = IOSContinuedProcessingTaskHandler(
            bundleIdentifier: "com.local.videodownloader.ios",
            coordinator: IOSContinuedProcessingTaskCoordinator(taskRepository: repository)
        )
        let systemTask = RecordingContinuedProcessingSystemTask(
            identifier: "com.local.videodownloader.ios.render.task-render"
        )

        let updated = try await handler.recordProgress(
            for: systemTask,
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 4, totalUnitCount: 10)
        )

        XCTAssertEqual(updated?.id, "task-render")
        XCTAssertEqual(updated?.progress.completedUnitCount, 4)
        let progressUpdates = await systemTask.progressUpdates()
        XCTAssertEqual(progressUpdates, [
            MobileTaskProgress(phase: .exporting, completedUnitCount: 4, totalUnitCount: 10)
        ])
        let saved = await repository.savedTasks()
        XCTAssertEqual(saved.map(\.id), ["task-render"])
    }

    func testRegisteredExpirationHandlerMarksTaskExpiredAndFailsSystemTask() async throws {
        let lastProgress = MobileTaskProgress(phase: .exporting, completedUnitCount: 6, totalUnitCount: 10)
        let repository = RecordingHandlerTaskRepository(tasks: [
            renderTask(id: "task-render", progress: lastProgress)
        ])
        let handler = IOSContinuedProcessingTaskHandler(
            bundleIdentifier: "com.local.videodownloader.ios",
            coordinator: IOSContinuedProcessingTaskCoordinator(taskRepository: repository)
        )
        let systemTask = RecordingContinuedProcessingSystemTask(
            identifier: "com.local.videodownloader.ios.render.task-render"
        )

        try await handler.register(systemTask)
        let hasExpirationHandler = await systemTask.hasExpirationHandler()
        XCTAssertTrue(hasExpirationHandler)
        await systemTask.triggerExpiration()

        let savedTasks = await repository.savedTasks()
        let expired = try XCTUnwrap(savedTasks.last)
        XCTAssertEqual(expired.state, .needsForegroundToContinue)
        XCTAssertEqual(expired.progress, lastProgress)
        XCTAssertEqual(expired.error, .systemBackgroundLimit)
        XCTAssertEqual(expired.backgroundPolicy.execution, .systemInterrupted)
        XCTAssertEqual(expired.backgroundPolicy.resumability, .nonResumable)
        let completions = await systemTask.completions()
        XCTAssertEqual(completions, [false])
    }

    func testRejectsNonRenderIdentifiersWithoutInstallingExpirationHandler() async throws {
        let repository = RecordingHandlerTaskRepository(tasks: [
            renderTask(id: "task-render")
        ])
        let handler = IOSContinuedProcessingTaskHandler(
            bundleIdentifier: "com.local.videodownloader.ios",
            coordinator: IOSContinuedProcessingTaskCoordinator(taskRepository: repository)
        )
        let systemTask = RecordingContinuedProcessingSystemTask(
            identifier: "com.local.videodownloader.ios.download.task-render"
        )

        do {
            try await handler.register(systemTask)
            XCTFail("register should reject non-render identifiers")
        } catch let error as IOSContinuedProcessingTaskHandler.HandlerError {
            XCTAssertEqual(error, .unrecognizedIdentifier)
        }

        let hasExpirationHandler = await systemTask.hasExpirationHandler()
        let savedTasks = await repository.savedTasks()
        XCTAssertFalse(hasExpirationHandler)
        XCTAssertTrue(savedTasks.isEmpty)
    }

    func testDecodesEncodedRenderTaskIdentifierBeforePersistingProgress() async throws {
        let originalTaskID = "../task with spaces"
        let repository = RecordingHandlerTaskRepository(tasks: [
            renderTask(id: originalTaskID)
        ])
        let handler = IOSContinuedProcessingTaskHandler(
            bundleIdentifier: "com.local.videodownloader.ios",
            coordinator: IOSContinuedProcessingTaskCoordinator(taskRepository: repository)
        )
        let systemTask = RecordingContinuedProcessingSystemTask(
            identifier: "com.local.videodownloader.ios.render.encoded-hex-2e2e2f7461736b207769746820737061636573"
        )

        let updated = try await handler.recordProgress(
            for: systemTask,
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 7, totalUnitCount: 10)
        )

        XCTAssertEqual(updated?.id, originalTaskID)
        let saved = await repository.savedTasks()
        XCTAssertEqual(saved.last?.id, originalTaskID)
        XCTAssertEqual(saved.last?.progress.completedUnitCount, 7)
    }

    func testRawEncodedPrefixTaskIdentifierIsNotMisdecoded() async throws {
        let rawTaskID = "encoded-6162"
        let repository = RecordingHandlerTaskRepository(tasks: [
            renderTask(id: rawTaskID)
        ])
        let handler = IOSContinuedProcessingTaskHandler(
            bundleIdentifier: "com.local.videodownloader.ios",
            coordinator: IOSContinuedProcessingTaskCoordinator(taskRepository: repository)
        )
        let systemTask = RecordingContinuedProcessingSystemTask(
            identifier: "com.local.videodownloader.ios.render.encoded-6162"
        )

        let updated = try await handler.recordProgress(
            for: systemTask,
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 2, totalUnitCount: 10)
        )

        XCTAssertEqual(updated?.id, rawTaskID)
        let saved = await repository.savedTasks()
        XCTAssertEqual(saved.last?.id, rawTaskID)
        XCTAssertEqual(saved.last?.progress.completedUnitCount, 2)
    }

    private func renderTask(
        id: String,
        progress: MobileTaskProgress = MobileTaskProgress(phase: .exporting, completedUnitCount: 0, totalUnitCount: 10)
    ) -> MobileTaskSnapshot {
        MobileTaskSnapshot(
            id: id,
            platform: .iOS,
            state: .exporting,
            progress: progress,
            exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.videoRender, .backgroundRender],
                maxRenderHeight: 1080
            ),
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .continuedProcessing,
                resumability: .nonResumable,
                limits: [.systemDeferred, .userVisibleNotificationRequired, .notResumable]
            ),
            result: MobileTaskResult(artifacts: [
                MobileTaskArtifact(
                    id: "original",
                    kind: .originalMedia,
                    displayName: "Render Source.mp4",
                    storageIdentifier: "Downloads/source.mp4"
                ),
                MobileTaskArtifact(
                    id: "subtitle",
                    kind: .translatedSubtitleFile,
                    displayName: "Render Source.zh.srt",
                    storageIdentifier: "Subtitles/source.zh.srt"
                )
            ], primaryArtifactID: "original")
        )
    }
}

private actor RecordingHandlerTaskRepository: TaskRepository {
    private var tasks: [MobileTaskSnapshot]
    private var saved: [MobileTaskSnapshot] = []

    init(tasks: [MobileTaskSnapshot]) {
        self.tasks = tasks
    }

    func loadTasks() async throws -> [MobileTaskSnapshot] {
        tasks
    }

    func saveTask(_ snapshot: MobileTaskSnapshot) async throws {
        tasks.removeAll { $0.id == snapshot.id }
        tasks.append(snapshot)
        saved.append(snapshot)
    }

    func removeTask(id: String) async throws {
        tasks.removeAll { $0.id == id }
    }

    func savedTasks() -> [MobileTaskSnapshot] {
        saved
    }
}

private actor RecordingContinuedProcessingSystemTask: IOSContinuedProcessingSystemTask {
    nonisolated let identifier: String
    private var progress: [MobileTaskProgress] = []
    private var expirationHandler: (@Sendable () async -> Void)?
    private var completed: [Bool] = []

    init(identifier: String) {
        self.identifier = identifier
    }

    func updateProgress(_ progress: MobileTaskProgress) async {
        self.progress.append(progress)
    }

    func setExpirationHandler(_ handler: @escaping @Sendable () async -> Void) async {
        expirationHandler = handler
    }

    func setTaskCompleted(success: Bool) async {
        completed.append(success)
    }

    func progressUpdates() -> [MobileTaskProgress] {
        progress
    }

    func hasExpirationHandler() -> Bool {
        expirationHandler != nil
    }

    func triggerExpiration() async {
        await expirationHandler?()
    }

    func completions() -> [Bool] {
        completed
    }
}
