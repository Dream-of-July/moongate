@testable import MoongateMobileCore
@testable import MoongateiOS
import Foundation
import XCTest

final class IOSBackgroundURLSessionDownloadStarterTests: XCTestCase {
    func testStartsBackgroundDownloadTaskWithTaskDescriptionAndRegistryRecord() async throws {
        let directory = temporaryDirectory()
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        let session = RecordingBackgroundDownloadSession()
        let starter = IOSBackgroundURLSessionDownloadStarter(
            transferRegistry: registry,
            session: session
        )

        let result = try await starter.startBackgroundDownload(MobileDownloadRequest(
            id: "task-1",
            sourceURL: "https://cdn.example.com/media/clip.mp4",
            candidateID: "candidate-1",
            videoID: "video-1",
            formatID: "1080p",
            preferredTitle: "Launch Clip"
        ), updatedAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(result.record.transferIdentifier, "ios.download.task-1")
        XCTAssertEqual(result.record.taskID, "task-1")
        XCTAssertEqual(result.record.platform, .iOS)
        XCTAssertEqual(result.record.backgroundPolicy.execution, .backgroundTransfer)
        XCTAssertEqual(result.record.backgroundPolicy.resumability, .resumable)
        XCTAssertTrue(result.record.backgroundPolicy.limits.contains(.systemDeferred))
        XCTAssertFalse(result.record.backgroundPolicy.allowsUnboundedBackgroundExecution)
        XCTAssertEqual(result.record.artifactStorageIdentifier, "downloads/task-1.mp4")
        XCTAssertEqual(result.record.lastProgress, MobileTaskProgress(phase: .downloading, completedUnitCount: 0))

        let requests = session.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, ["https://cdn.example.com/media/clip.mp4"])
        XCTAssertEqual(requests.first?.cachePolicy, .reloadIgnoringLocalCacheData)

        let recordedTasks = session.recordedTasks()
        let task = try XCTUnwrap(recordedTasks.first)
        XCTAssertEqual(task.taskDescription, "ios.download.task-1")
        XCTAssertTrue(task.didResume)

        let records = try await registry.loadRecords()
        XCTAssertEqual(records, [result.record])
    }

    func testRejectsPlainHTTPBeforeCreatingTaskOrRegistryRecord() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let session = RecordingBackgroundDownloadSession()
        let starter = IOSBackgroundURLSessionDownloadStarter(
            transferRegistry: registry,
            session: session
        )

        do {
            _ = try await starter.startBackgroundDownload(MobileDownloadRequest(
                id: "task-http",
                sourceURL: "http://cdn.example.com/media/clip.mp4",
                candidateID: "candidate-http",
                videoID: "video-http",
                formatID: "mp4"
            ))
            XCTFail("Plain HTTP background downloads should be rejected before any task starts.")
        } catch let error as IOSBackgroundURLSessionDownloadStarter.StartError {
            XCTAssertEqual(error, .unsupportedURL)
        }

        let records = try await registry.loadRecords()
        XCTAssertTrue(session.recordedRequests().isEmpty)
        XCTAssertTrue(records.isEmpty)
    }

    func testComputesArtifactIdentifierWithFormatExtensionFallbackThenMP4() async throws {
        let formatFallback = try await startRecord(
            id: "task-format",
            sourceURL: "https://cdn.example.com/video",
            formatID: "1080p.webm"
        )
        XCTAssertEqual(formatFallback.artifactStorageIdentifier, "downloads/task-format.webm")

        let mp4Fallback = try await startRecord(
            id: "task-mp4",
            sourceURL: "https://cdn.example.com/video",
            formatID: "1080p"
        )
        XCTAssertEqual(mp4Fallback.artifactStorageIdentifier, "downloads/task-mp4.mp4")
    }

    func testCancelsMatchingBackgroundDownloadTaskWithoutRemovingRegistryRecord() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let session = RecordingBackgroundDownloadSession()
        let starter = IOSBackgroundURLSessionDownloadStarter(
            transferRegistry: registry,
            session: session
        )
        let request = MobileDownloadRequest(
            id: "task-cancel",
            sourceURL: "https://cdn.example.com/media/clip.mp4",
            candidateID: "candidate-cancel",
            videoID: "video-cancel",
            formatID: "mp4"
        )

        _ = try await starter.startBackgroundDownload(request)
        try await starter.cancelBackgroundDownload(taskID: "task-cancel")

        let recordedTasks = session.recordedTasks()
        let task = try XCTUnwrap(recordedTasks.first)
        XCTAssertTrue(task.didCancel)
        let records = try await registry.loadRecords()
        XCTAssertEqual(records.map(\.taskID), ["task-cancel"])
    }

    private func startRecord(
        id: String,
        sourceURL: String,
        formatID: String
    ) async throws -> BackgroundTransferRecord {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let session = RecordingBackgroundDownloadSession()
        let starter = IOSBackgroundURLSessionDownloadStarter(
            transferRegistry: registry,
            session: session
        )
        return try await starter.startBackgroundDownload(MobileDownloadRequest(
            id: id,
            sourceURL: sourceURL,
            candidateID: "candidate-\(id)",
            videoID: "video-\(id)",
            formatID: formatID
        )).record
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-background-download-starter-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class RecordingBackgroundDownloadSession: IOSBackgroundDownloadSessioning, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var tasks: [RecordingBackgroundDownloadTask] = []

    func makeDownloadTask(with request: URLRequest) -> any IOSBackgroundDownloadTasking {
        let task = RecordingBackgroundDownloadTask()
        lock.lock()
        requests.append(request)
        tasks.append(task)
        lock.unlock()
        return task
    }

    func allDownloadTasks() async -> [any IOSBackgroundDownloadTasking] {
        lockedTasks()
    }

    private func lockedTasks() -> [any IOSBackgroundDownloadTasking] {
        lock.lock()
        defer { lock.unlock() }
        return tasks
    }

    func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func recordedTasks() -> [RecordingBackgroundDownloadTask] {
        lock.lock()
        defer { lock.unlock() }
        return tasks
    }
}

private final class RecordingBackgroundDownloadTask: IOSBackgroundDownloadTasking, @unchecked Sendable {
    private let lock = NSLock()
    private var storedDescription: String?
    private var resumed = false
    private var cancelled = false

    var taskDescription: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedDescription
        }
        set {
            lock.lock()
            storedDescription = newValue
            lock.unlock()
        }
    }

    var didResume: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resumed
    }

    var didCancel: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func resume() {
        lock.lock()
        resumed = true
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
