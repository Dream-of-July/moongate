@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

final class IOSContinuedProcessingTaskCoordinatorTests: XCTestCase {
    func testProgressUpdatePersistsContinuedProcessingRenderTask() async throws {
        let repository = RecordingContinuedProcessingTaskRepository(tasks: [
            renderTask(
                id: "task-render",
                state: .exporting,
                progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 0, totalUnitCount: 10)
            )
        ])
        let coordinator = IOSContinuedProcessingTaskCoordinator(taskRepository: repository)

        let updated = try await coordinator.recordProgress(
            taskID: "task-render",
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 4, totalUnitCount: 10)
        )

        XCTAssertEqual(updated?.state, .exporting)
        XCTAssertEqual(updated?.progress, MobileTaskProgress(phase: .exporting, completedUnitCount: 4, totalUnitCount: 10))
        let saved = await repository.savedTasks()
        XCTAssertEqual(saved.map(\.id), ["task-render"])
        XCTAssertEqual(saved.last?.progress.completedUnitCount, 4)
        XCTAssertEqual(saved.last?.backgroundPolicy.execution, .continuedProcessing)
    }

    func testExpirationMarksContinuedProcessingRenderAsForegroundRequiredWithoutDroppingProgress() async throws {
        let lastProgress = MobileTaskProgress(phase: .exporting, completedUnitCount: 6, totalUnitCount: 10)
        let repository = RecordingContinuedProcessingTaskRepository(tasks: [
            renderTask(id: "task-render", state: .exporting, progress: lastProgress)
        ])
        let coordinator = IOSContinuedProcessingTaskCoordinator(taskRepository: repository)

        let expired = try await coordinator.markExpired(taskID: "task-render")

        XCTAssertEqual(expired?.state, .needsForegroundToContinue)
        XCTAssertEqual(expired?.progress, lastProgress)
        XCTAssertEqual(expired?.error, .systemBackgroundLimit)
        XCTAssertEqual(expired?.backgroundPolicy.execution, .systemInterrupted)
        XCTAssertEqual(expired?.backgroundPolicy.resumability, .nonResumable)
        let limits = try XCTUnwrap(expired?.backgroundPolicy.limits)
        XCTAssertTrue(limits.contains(MobileBackgroundLimit.systemInterrupted))
        XCTAssertTrue(limits.contains(MobileBackgroundLimit.foregroundRequired))
        XCTAssertTrue(limits.contains(MobileBackgroundLimit.notResumable))
        XCTAssertEqual(expired?.availableActions, [MobileTaskAction.openAppToContinue, .cancel])
        let saved = await repository.savedTasks()
        XCTAssertEqual(saved.last, expired)
    }

    func testIgnoresNonContinuedProcessingTasks() async throws {
        let repository = RecordingContinuedProcessingTaskRepository(tasks: [
            renderTask(
                id: "task-foreground",
                state: .exporting,
                backgroundPolicy: MobileBackgroundPolicy(
                    execution: .foregroundRequired,
                    resumability: .nonResumable,
                    limits: [.foregroundRequired, .notResumable]
                )
            )
        ])
        let coordinator = IOSContinuedProcessingTaskCoordinator(taskRepository: repository)

        let updated = try await coordinator.recordProgress(
            taskID: "task-foreground",
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 2)
        )
        let expired = try await coordinator.markExpired(taskID: "task-foreground")

        XCTAssertNil(updated)
        XCTAssertNil(expired)
        let saved = await repository.savedTasks()
        XCTAssertTrue(saved.isEmpty)
    }

    private func renderTask(
        id: String,
        state: MobileTaskState,
        progress: MobileTaskProgress = MobileTaskProgress(phase: .exporting, completedUnitCount: 0),
        backgroundPolicy: MobileBackgroundPolicy = MobileBackgroundPolicy(
            execution: .continuedProcessing,
            resumability: .nonResumable,
            limits: [.systemDeferred, .userVisibleNotificationRequired, .notResumable]
        )
    ) -> MobileTaskSnapshot {
        MobileTaskSnapshot(
            id: id,
            platform: .iOS,
            state: state,
            progress: progress,
            exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle),
            capabilities: MobileProcessingCapabilities(
                platform: .iOS,
                supportedCapabilities: [.videoRender, .backgroundRender],
                maxRenderHeight: 1080
            ),
            backgroundPolicy: backgroundPolicy,
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

private actor RecordingContinuedProcessingTaskRepository: TaskRepository {
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
