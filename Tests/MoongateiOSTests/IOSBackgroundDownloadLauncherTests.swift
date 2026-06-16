@testable import MoongateMobileCore
@testable import MoongateiOS
import Foundation
import XCTest

final class IOSBackgroundDownloadLauncherTests: XCTestCase {
    func testStartsBackgroundDownloadAndRecordsRecoverableTransferBeforeResume() async throws {
        let directory = temporaryDirectory()
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        let registryFileURL = directory.appendingPathComponent("background-transfers.json", isDirectory: false)
        let session = RecordingLauncherDownloadSession(registryFileURL: registryFileURL)
        let launcher = IOSBackgroundDownloadLauncher(
            transferRegistry: registry,
            session: session
        )

        let record = try await launcher.start(
            IOSBackgroundDownloadLaunchRequest(
                downloadRequest: MobileDownloadRequest(
                    id: "task-1",
                    sourceURL: "https://cdn.example.com/videos/clip.mov?token=redacted",
                    candidateID: "candidate-1",
                    videoID: "video-1",
                    formatID: "1080p.mp4"
                )
            ),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(record.transferIdentifier, "ios.download.task-1")
        XCTAssertEqual(record.taskID, "task-1")
        XCTAssertEqual(record.platform, .iOS)
        XCTAssertEqual(record.backgroundPolicy.execution, .backgroundTransfer)
        XCTAssertEqual(record.backgroundPolicy.resumability, .resumable)
        XCTAssertEqual(record.backgroundPolicy.limits, [.systemDeferred])
        XCTAssertTrue(record.backgroundPolicy.canResume)
        XCTAssertFalse(record.backgroundPolicy.allowsUnboundedBackgroundExecution)
        XCTAssertEqual(record.artifactStorageIdentifier, "downloads/task-1.mov")
        XCTAssertEqual(record.lastProgress, MobileTaskProgress(phase: .downloading, completedUnitCount: 0))

        let recordedRecords = try await registry.loadRecords()
        XCTAssertEqual(recordedRecords, [record])

        let startedRequest = try XCTUnwrap(session.startedRequest())
        XCTAssertEqual(startedRequest.url?.absoluteString, "https://cdn.example.com/videos/clip.mov?token=redacted")
        let task = session.createdTask()
        XCTAssertEqual(task.taskIdentifier, 42)
        XCTAssertEqual(task.taskDescription, "ios.download.task-1")
        XCTAssertTrue(task.didResume)
        XCTAssertEqual(task.recordCountObservedAtResume, 1)
    }

    func testRejectsUnsupportedURLsBeforeCreatingTaskOrRegistryRecord() async throws {
        for sourceURL in ["http://cdn.example.com/video.mp4", "https:///video.mp4"] {
            let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
            let session = RecordingLauncherDownloadSession()
            let launcher = IOSBackgroundDownloadLauncher(
                transferRegistry: registry,
                session: session
            )

            do {
                _ = try await launcher.start(
                    IOSBackgroundDownloadLaunchRequest(
                        downloadRequest: MobileDownloadRequest(
                            id: "task-url",
                            sourceURL: sourceURL,
                            candidateID: "candidate-url",
                            videoID: "video-url",
                            formatID: "mp4"
                        )
                    )
                )
                XCTFail("Unsupported URLs should be rejected before any task starts.")
            } catch let error as IOSBackgroundDownloadLauncher.LaunchError {
                XCTAssertEqual(error, .unsupportedURL)
            }

            XCTAssertTrue(session.startedRequests().isEmpty)
            let records = try await registry.loadRecords()
            XCTAssertTrue(records.isEmpty)
        }
    }

    func testRejectsUnsafeTaskIDsBeforeCreatingTaskOrRegistryRecord() async throws {
        for taskID in ["", " ", ".", "..", "nested/task", "nested\\task"] {
            let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
            let session = RecordingLauncherDownloadSession()
            let launcher = IOSBackgroundDownloadLauncher(
                transferRegistry: registry,
                session: session
            )

            do {
                _ = try await launcher.start(
                    IOSBackgroundDownloadLaunchRequest(
                        downloadRequest: MobileDownloadRequest(
                            id: taskID,
                            sourceURL: "https://cdn.example.com/video.mp4",
                            candidateID: "candidate-id",
                            videoID: "video-id",
                            formatID: "mp4"
                        )
                    )
                )
                XCTFail("Unsafe task IDs should be rejected before any task starts.")
            } catch let error as IOSBackgroundDownloadLauncher.LaunchError {
                XCTAssertEqual(error, .unsafeTaskID)
            }

            XCTAssertTrue(session.startedRequests().isEmpty)
            let records = try await registry.loadRecords()
            XCTAssertTrue(records.isEmpty)
        }
    }

    func testComputesArtifactIdentifierWithFormatExtensionFallbackThenMP4() async throws {
        let formatFallback = try await launchRecord(
            id: "task-format",
            sourceURL: "https://cdn.example.com/video",
            formatID: "1080p.webm"
        )
        XCTAssertEqual(formatFallback.artifactStorageIdentifier, "downloads/task-format.webm")

        let mp4Fallback = try await launchRecord(
            id: "task-mp4",
            sourceURL: "https://cdn.example.com/video",
            formatID: "1080p"
        )
        XCTAssertEqual(mp4Fallback.artifactStorageIdentifier, "downloads/task-mp4.mp4")
    }

    private func launchRecord(
        id: String,
        sourceURL: String,
        formatID: String
    ) async throws -> BackgroundTransferRecord {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let session = RecordingLauncherDownloadSession()
        let launcher = IOSBackgroundDownloadLauncher(
            transferRegistry: registry,
            session: session
        )
        return try await launcher.start(
            IOSBackgroundDownloadLaunchRequest(
                downloadRequest: MobileDownloadRequest(
                    id: id,
                    sourceURL: sourceURL,
                    candidateID: "candidate-\(id)",
                    videoID: "video-\(id)",
                    formatID: formatID
                )
            )
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-background-download-launcher-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class RecordingLauncherDownloadSession: IOSBackgroundDownloadSession, @unchecked Sendable {
    private let lock = NSLock()
    private let registryFileURL: URL?
    private var requests: [URLRequest] = []
    private var task: RecordingLauncherDownloadTask?

    init(registryFileURL: URL? = nil) {
        self.registryFileURL = registryFileURL
    }

    func makeDownloadTask(with request: URLRequest) -> any IOSBackgroundDownloadTask {
        let task = RecordingLauncherDownloadTask(registryFileURL: registryFileURL)
        lock.lock()
        requests.append(request)
        self.task = task
        lock.unlock()
        return task
    }

    func startedRequest() -> URLRequest? {
        startedRequests().first
    }

    func startedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func createdTask() -> RecordingLauncherDownloadTask {
        lock.lock()
        defer { lock.unlock() }
        return task ?? RecordingLauncherDownloadTask(registryFileURL: registryFileURL)
    }
}

private final class RecordingLauncherDownloadTask: IOSBackgroundDownloadTask, @unchecked Sendable {
    private let lock = NSLock()
    let taskIdentifier = 42
    private let registryFileURL: URL?
    private var storedDescription: String?
    private var resumed = false
    private var observedRecordCount: Int?

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

    var recordCountObservedAtResume: Int? {
        lock.lock()
        defer { lock.unlock() }
        return observedRecordCount
    }

    init(registryFileURL: URL?) {
        self.registryFileURL = registryFileURL
    }

    func resume() {
        lock.lock()
        resumed = true
        observedRecordCount = recordsOnDiskCount()
        lock.unlock()
    }

    private func recordsOnDiskCount() -> Int? {
        guard let registryFileURL,
              let data = try? Data(contentsOf: registryFileURL) else {
            return nil
        }
        return try? JSONDecoder.backgroundTransferRegistry.decode([BackgroundTransferRecord].self, from: data).count
    }
}

private extension JSONDecoder {
    static var backgroundTransferRegistry: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
