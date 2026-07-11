import XCTest
@testable import Moongate
@testable import MoongateCore

@MainActor
final class QueueManagerLifecycleTests: XCTestCase {
    func testQueuedEnqueueDoesNotStartUntilExplicitlyStarted() async throws {
        let engine = ControlledDownloadEngine(mode: .immediate(makeDownloadResult()))
        let queue = QueueManager(engine: engine)

        let id = queue.enqueue(
            info: makeVideoInfo(),
            request: makeRequest(),
            chineseMode: .off,
            settings: AppSettings(),
            startImmediately: false
        )

        await Task.yield()

        let downloadCallCount = await engine.downloadCallCount
        XCTAssertEqual(downloadCallCount, 0)
        let item = try XCTUnwrap(queue.items.first { $0.id == id })
        XCTAssertTrue(item.stage == QueueManager.ItemStage.queued)
        XCTAssertNil(item.task)
    }

    func testQueuedConfigurationUpdatesPlansAndKeepsLibraryIdentities() throws {
        let queue = QueueManager(engine: ControlledDownloadEngine(mode: .immediate(makeDownloadResult())))
        let id = queue.enqueue(
            info: makeVideoInfo(),
            request: makeRequest(),
            chineseMode: .off,
            settings: AppSettings(),
            startImmediately: false
        )
        let initial = try XCTUnwrap(queue.items.first { $0.id == id })
        let updatedRequest = makeRequest(
            url: "https://example.com/updated-source",
            formatID: "updated-format",
            outputFormat: .mp4H264
        )
        let updatedSettings = AppSettings(maxConcurrentDownloads: 1, maxConcurrentBurns: 1)

        XCTAssertTrue(queue.updateQueuedConfiguration(
            id: id,
            request: updatedRequest,
            mode: .burnIn,
            settings: updatedSettings
        ))

        let updated = try XCTUnwrap(queue.items.first { $0.id == id })
        XCTAssertEqual(updated.libraryItemID, initial.libraryItemID)
        XCTAssertEqual(updated.libraryVersionID, initial.libraryVersionID)
        XCTAssertEqual(updated.request.url, "https://example.com/updated-source")
        XCTAssertEqual(updated.request.formatID, "updated-format")
        XCTAssertEqual(updated.chineseMode, .burnIn)
        XCTAssertEqual(updated.settings, updatedSettings)
        XCTAssertEqual(updated.progressPlan.phases, [.download, .transcode, .translate, .burn])
        XCTAssertEqual(updated.workPlan.phases.map(\.phase), [.download, .transcode, .translate, .burn])
    }

    func testStartRunsUpdatedSnapshotOnlyOnceAndRejectsFurtherUpdates() async throws {
        let engine = ControlledDownloadEngine(mode: .suspended(makeDownloadResult()))
        let queue = QueueManager(engine: engine)
        let id = queue.enqueue(
            info: makeVideoInfo(), request: makeRequest(), chineseMode: .off,
            settings: AppSettings(), startImmediately: false
        )
        let snapshotRequest = makeRequest(url: "https://example.com/snapshot", formatID: "snapshot")
        let snapshotSettings = AppSettings(maxConcurrentDownloads: 1, maxConcurrentBurns: 1)
        XCTAssertTrue(queue.updateQueuedConfiguration(
            id: id, request: snapshotRequest, mode: .off, settings: snapshotSettings
        ))

        XCTAssertTrue(queue.start(id: id))
        XCTAssertFalse(queue.start(id: id))
        await engine.waitForSuspendedDownloads(1)

        let callCount = await engine.downloadCallCount
        let requests = await engine.downloadRequests
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(requests.map(\.url), ["https://example.com/snapshot"])
        XCTAssertFalse(queue.updateQueuedConfiguration(
            id: id, request: makeRequest(url: "https://example.com/ignored"),
            mode: .off, settings: AppSettings()
        ))
        let running = try XCTUnwrap(queue.items.first { $0.id == id })
        XCTAssertEqual(running.request.url, "https://example.com/snapshot")
        XCTAssertEqual(running.settings, snapshotSettings)

        await engine.completeNextDownload()
        try await waitForStage(.done, id: id, in: queue)
    }

    func testStartAllBeginsEachDeferredTaskOnlyOnce() async throws {
        let engine = ControlledDownloadEngine(mode: .suspended(makeDownloadResult()))
        let queue = QueueManager(engine: engine)
        let first = queue.enqueue(
            info: makeVideoInfo(), request: makeRequest(url: "https://example.com/first"),
            chineseMode: .off, settings: AppSettings(), startImmediately: false
        )
        let second = queue.enqueue(
            info: makeVideoInfo(), request: makeRequest(url: "https://example.com/second"),
            chineseMode: .off, settings: AppSettings(), startImmediately: false
        )

        XCTAssertEqual(queue.startAll(), 2)
        XCTAssertEqual(queue.startAll(), 0)
        await engine.waitForSuspendedDownloads(2)
        let requests = await engine.downloadRequests
        XCTAssertEqual(Set(requests.map(\.url)), Set([
            "https://example.com/first", "https://example.com/second",
        ]))

        queue.cancel(first)
        queue.cancel(second)
        await engine.completeNextDownload()
        await engine.completeNextDownload()
        try await waitForStage(.cancelled, id: first, in: queue)
        try await waitForStage(.cancelled, id: second, in: queue)
    }

    func testCancelShowsCancellingUntilPipelineConverges() async throws {
        let engine = ControlledDownloadEngine(mode: .suspended(makeDownloadResult()))
        let queue = QueueManager(engine: engine)
        let id = queue.enqueue(
            info: makeVideoInfo(), request: makeRequest(), chineseMode: .off,
            settings: AppSettings(), startImmediately: false
        )
        XCTAssertTrue(queue.start(id: id))
        await engine.waitForSuspendedDownloads(1)

        queue.cancel(id)

        let cancelling = try XCTUnwrap(queue.items.first { $0.id == id })
        XCTAssertTrue(cancelling.stage == QueueManager.ItemStage.cancelling)
        XCTAssertFalse(cancelling.statusText?.isEmpty ?? true)
        XCTAssertEqual(queue.openTaskCount, 1)
        XCTAssertFalse(queue.hasFinishedItems)
        XCTAssertFalse(queue.pause(id))
        queue.retry(id)
        XCTAssertTrue((try XCTUnwrap(queue.items.first { $0.id == id })).stage == QueueManager.ItemStage.cancelling)
        queue.clearFinished()
        XCTAssertEqual(queue.items.count, 1)

        // The fake completes successfully after cancellation; cancellation must still win.
        await engine.completeNextDownload()
        try await waitForStage(.cancelled, id: id, in: queue)
        XCTAssertEqual(queue.openTaskCount, 0)
        XCTAssertTrue(queue.hasFinishedItems)
    }

    func testCancelUnstartedDraftSettlesWithoutStartingPipeline() async throws {
        let engine = ControlledDownloadEngine(mode: .suspended(makeDownloadResult()))
        let queue = QueueManager(engine: engine)
        let id = queue.enqueue(
            info: makeVideoInfo(), request: makeRequest(), chineseMode: .off,
            settings: AppSettings(), startImmediately: false
        )

        queue.cancel(id)

        let callCount = await engine.downloadCallCount
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue((try XCTUnwrap(queue.items.first { $0.id == id })).stage == QueueManager.ItemStage.cancelled)
        XCTAssertEqual(queue.openTaskCount, 0)
    }

    func testLegacyEnqueueStillStartsImmediately() async throws {
        let engine = ControlledDownloadEngine(mode: .suspended(makeDownloadResult()))
        let queue = QueueManager(engine: engine)
        let id = queue.enqueue(
            info: makeVideoInfo(), request: makeRequest(), chineseMode: .off, settings: AppSettings()
        )

        await engine.waitForSuspendedDownloads(1)
        let callCount = await engine.downloadCallCount
        XCTAssertEqual(callCount, 1)

        queue.cancel(id)
        await engine.completeNextDownload()
        try await waitForStage(.cancelled, id: id, in: queue)
    }

    func testDeferredReprocessRetainsProvidedLibraryIDsUntilExplicitStart() async throws {
        let engine = ControlledDownloadEngine(mode: .suspended(makeDownloadResult()))
        let queue = QueueManager(engine: engine)
        let libraryItemID = UUID()
        let libraryVersionID = UUID()
        let id = queue.enqueueReprocess(
            info: makeVideoInfo(), request: makeRequest(), chineseMode: .off, settings: AppSettings(),
            existingFiles: [], libraryItemID: libraryItemID, libraryVersionID: libraryVersionID,
            reuseExistingArtifacts: false, startImmediately: false
        )

        let queued = try XCTUnwrap(queue.items.first { $0.id == id })
        let callsBeforeStart = await engine.downloadCallCount
        XCTAssertEqual(queued.libraryItemID, libraryItemID)
        XCTAssertEqual(queued.libraryVersionID, libraryVersionID)
        XCTAssertNil(queued.task)
        XCTAssertEqual(callsBeforeStart, 0)

        XCTAssertTrue(queue.start(id: id))
        await engine.waitForSuspendedDownloads(1)
        queue.cancel(id)
        await engine.completeNextDownload()
        try await waitForStage(.cancelled, id: id, in: queue)
    }
}

private actor ControlledDownloadEngine: DownloadEngine {
    enum Mode: Sendable {
        case immediate(DownloadResult)
        case suspended(DownloadResult)
    }

    private let mode: Mode
    private(set) var downloadCallCount = 0
    private(set) var downloadRequests: [DownloadRequest] = []
    private var pendingDownloads: [CheckedContinuation<DownloadResult, Error>] = []
    private var suspensionWaiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(mode: Mode) { self.mode = mode }

    func resolveCandidates(for input: String) async throws -> [VideoCandidate] { [] }

    func analyze(url: String) async throws -> VideoInfo {
        throw MoongateError.analyzeFailed("not used by queue lifecycle tests")
    }

    func download(
        _ request: DownloadRequest,
        control: TaskControlToken?,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadResult {
        downloadCallCount += 1
        downloadRequests.append(request)
        switch mode {
        case .immediate(let result):
            return result
        case .suspended:
            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<DownloadResult, Error>) in
                pendingDownloads.append(continuation)
                resumeSuspensionWaiters()
            }
        }
    }

    func waitForSuspendedDownloads(_ count: Int) async {
        guard pendingDownloads.count < count else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append((minimum: count, continuation: continuation))
        }
    }

    func completeNextDownload() {
        guard !pendingDownloads.isEmpty else {
            preconditionFailure("Expected a suspended download")
        }
        guard case .suspended(let result) = mode else {
            preconditionFailure("Only suspended downloads can be completed manually")
        }
        pendingDownloads.removeFirst().resume(returning: result)
    }

    func fetchSubtitleText(
        url: String,
        preferredLanguages: [String],
        control: TaskControlToken?
    ) async throws -> String? { nil }

    nonisolated func invalidateInfoCache(for url: String) {}

    private func resumeSuspensionWaiters() {
        let ready = suspensionWaiters.filter { $0.minimum <= pendingDownloads.count }
        suspensionWaiters.removeAll { $0.minimum <= pendingDownloads.count }
        ready.forEach { $0.continuation.resume() }
    }
}

private func makeVideoInfo() -> VideoInfo {
    VideoInfo(
        sourceURL: "https://example.com/source",
        videoID: "queue-lifecycle-video",
        title: "Queue lifecycle fixture",
        durationText: nil,
        thumbnailURL: nil,
        uploader: nil,
        formats: [FormatChoice(id: "best", label: "Best")],
        subtitles: []
    )
}

private func makeRequest(
    url: String = "https://example.com/source",
    formatID: String = "best",
    outputFormat: OutputFormat = .original
) -> DownloadRequest {
    DownloadRequest(
        url: url,
        videoID: "queue-lifecycle-video",
        formatID: formatID,
        subtitleLangs: [],
        autoSubtitleLangs: [],
        destinationDirectory: FileManager.default.temporaryDirectory,
        outputFormat: outputFormat
    )
}

private func makeDownloadResult() -> DownloadResult {
    DownloadResult(files: [
        FileManager.default.temporaryDirectory.appendingPathComponent("queue-lifecycle-video.mp4")
    ])
}

@MainActor
private func waitForStage(
    _ expected: QueueManager.ItemStage,
    id: UUID,
    in queue: QueueManager
) async throws {
    for _ in 0..<100 {
        if queue.items.first(where: { $0.id == id })?.stage == expected {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for queue item to reach expected stage")
}
