@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

final class IOSContinuedProcessingRenderTaskRunnerTests: XCTestCase {
    func testRunsContinuedProcessingRenderToCompletionAndPersistsLibraryReadyTask() async throws {
        let rendered = MobileTaskArtifact(
            id: "render-original",
            kind: .renderedVideo,
            displayName: "Render Source.rendered.mp4",
            storageIdentifier: "Renders/render-source.rendered.mp4",
            byteCount: 42
        )
        let repository = RecordingRunnerTaskRepository(tasks: [
            renderTask(id: "task-render")
        ])
        let exporter = RecordingRunnerRenderExporter(result: MobileTaskResult(
            artifacts: [rendered],
            primaryArtifactID: rendered.id
        ))
        let runner = IOSContinuedProcessingRenderTaskRunner(
            taskRepository: repository,
            renderExporter: exporter
        )

        let updated = try await runner.run(taskID: "task-render")

        XCTAssertEqual(updated?.state, .completed)
        XCTAssertEqual(updated?.result?.primaryArtifactID, rendered.id)
        XCTAssertEqual(
            updated?.result?.artifacts.map { $0.kind },
            [
                MobileArtifactKind.originalMedia,
                MobileArtifactKind.translatedSubtitleFile,
                MobileArtifactKind.renderedVideo
            ]
        )
        XCTAssertEqual(updated?.progress, MobileTaskProgress(phase: .exporting, completedUnitCount: 42, totalUnitCount: 42))
        XCTAssertNil(updated?.error)
        let requests = await exporter.requests()
        XCTAssertEqual(requests.first?.sourceMedia.id, "original")
        XCTAssertEqual(requests.first?.subtitles.map(\.id), ["subtitle"])
        let saved = await repository.savedTasks()
        XCTAssertEqual(saved.last, updated)
    }

    func testFailedContinuedProcessingRenderMarksTaskAsForegroundRequired() async throws {
        let repository = RecordingRunnerTaskRepository(tasks: [
            renderTask(id: "task-render")
        ])
        let exporter = RecordingRunnerRenderExporter(error: IOSMobileRenderExporter.RenderExportError.outputMissing)
        let runner = IOSContinuedProcessingRenderTaskRunner(
            taskRepository: repository,
            renderExporter: exporter
        )

        let updated = try await runner.run(taskID: "task-render")

        XCTAssertEqual(updated?.state, .needsForegroundToContinue)
        XCTAssertEqual(updated?.error, .exportFailed)
        XCTAssertEqual(updated?.backgroundPolicy.execution, .systemInterrupted)
        XCTAssertTrue(updated?.backgroundPolicy.limits.contains(MobileBackgroundLimit.foregroundRequired) == true)
        XCTAssertTrue(updated?.backgroundPolicy.limits.contains(MobileBackgroundLimit.notResumable) == true)
    }

    func testCompletedRenderDoesNotOverwriteExpiredPersistedTask() async throws {
        let rendered = MobileTaskArtifact(
            id: "render-after-expiration",
            kind: .renderedVideo,
            displayName: "Expired Render.rendered.mp4",
            storageIdentifier: "Renders/expired.rendered.mp4",
            byteCount: 42
        )
        let repository = RecordingRunnerTaskRepository(tasks: [
            renderTask(id: "task-expired")
        ])
        let exporter = RecordingRunnerRenderExporter(result: MobileTaskResult(
            artifacts: [rendered],
            primaryArtifactID: rendered.id
        ))
        await exporter.setBeforeReturn {
            var expired = await repository.task(id: "task-expired")!
            expired.state = .needsForegroundToContinue
            expired.error = .systemBackgroundLimit
            expired.backgroundPolicy = MobileBackgroundPolicy(
                execution: .systemInterrupted,
                resumability: .nonResumable,
                limits: [.systemInterrupted, .foregroundRequired, .notResumable]
            )
            try! await repository.saveTask(expired)
        }
        let runner = IOSContinuedProcessingRenderTaskRunner(
            taskRepository: repository,
            renderExporter: exporter
        )

        let updated = try await runner.run(taskID: "task-expired")

        XCTAssertEqual(updated?.state, .needsForegroundToContinue)
        XCTAssertEqual(updated?.error, .systemBackgroundLimit)
        XCTAssertEqual(updated?.backgroundPolicy.execution, .systemInterrupted)
        XCTAssertFalse(updated?.result?.artifacts.contains { $0.kind == .renderedVideo } == true)
        let saved = await repository.savedTasks()
        XCTAssertEqual(saved.last?.state, .needsForegroundToContinue)
        XCTAssertEqual(saved.last?.error, .systemBackgroundLimit)
    }

    private func renderTask(id: String) -> MobileTaskSnapshot {
        MobileTaskSnapshot(
            id: id,
            platform: .iOS,
            state: .exporting,
            progress: MobileTaskProgress(phase: .exporting, completedUnitCount: 0, totalUnitCount: 10),
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

private actor RecordingRunnerTaskRepository: TaskRepository {
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

    func task(id: String) -> MobileTaskSnapshot? {
        tasks.first { $0.id == id }
    }
}

private actor RecordingRunnerRenderExporter: RenderExporter {
    private let result: MobileTaskResult
    private let error: Error?
    private var recordedRequests: [MobileRenderRequest] = []
    private var beforeReturn: (@Sendable () async -> Void)?

    init(result: MobileTaskResult = MobileTaskResult(), error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func setBeforeReturn(_ hook: @escaping @Sendable () async -> Void) {
        beforeReturn = hook
    }

    func export(
        _ request: MobileRenderRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        recordedRequests.append(request)
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 21, totalUnitCount: 42))
        if let error {
            throw error
        }
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 42, totalUnitCount: 42))
        await beforeReturn?()
        return result
    }

    func requests() -> [MobileRenderRequest] {
        recordedRequests
    }
}
