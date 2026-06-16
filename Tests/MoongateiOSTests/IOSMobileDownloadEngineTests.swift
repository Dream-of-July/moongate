@testable import MoongateMobileCore
@testable import MoongateiOS
import Foundation
import XCTest

final class IOSMobileDownloadEngineTests: XCTestCase {
    func testDownloadsHTTPSMediaIntoAppStorageAndRecordsForegroundRequiredTransfer() async throws {
        let directory = temporaryDirectory()
        let sourceFile = directory.appendingPathComponent("source-video.mp4")
        try Data("video-bytes".utf8).write(to: sourceFile)
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        let transport = RecordingMobileDownloadTransport(resultFileURL: sourceFile, byteCount: 11)
        let engine = IOSMobileDownloadEngine(
            downloadDirectoryURL: directory,
            transferRegistry: registry,
            transport: transport
        )
        let progress = ProgressRecorder()

        let result = try await engine.download(
            MobileDownloadRequest(
                id: "task-1",
                sourceURL: "https://cdn.example.com/video.mp4",
                candidateID: "candidate-1",
                videoID: "video-1",
                formatID: "1080p",
                preferredTitle: "Launch Clip"
            ),
            progress: { snapshot in progress.record(snapshot) }
        )

        let artifact = try XCTUnwrap(result.primaryArtifact)
        XCTAssertEqual(artifact.kind, .originalMedia)
        XCTAssertEqual(artifact.displayName, "Launch Clip.mp4")
        XCTAssertEqual(artifact.storageIdentifier, "downloads/task-1.mp4")
        XCTAssertEqual(artifact.byteCount, 11)
        let storedURL = directory.appendingPathComponent("task-1.mp4")
        XCTAssertEqual(try Data(contentsOf: storedURL), Data("video-bytes".utf8))

        let maybeRecordedURL = await transport.firstURL()
        let recordedURL = try XCTUnwrap(maybeRecordedURL)
        XCTAssertEqual(recordedURL.absoluteString, "https://cdn.example.com/video.mp4")
        let snapshots = progress.snapshots()
        XCTAssertEqual(snapshots.first, MobileTaskProgress(phase: .downloading, completedUnitCount: 0, totalUnitCount: nil))
        XCTAssertEqual(snapshots.last, MobileTaskProgress(phase: .downloading, completedUnitCount: 11, totalUnitCount: 11))

        let records = try await registry.loadRecords()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.transferIdentifier, "ios.download.task-1")
        XCTAssertEqual(record.taskID, "task-1")
        XCTAssertEqual(record.platform, .iOS)
        XCTAssertEqual(record.backgroundPolicy.execution, .foregroundRequired)
        XCTAssertEqual(record.backgroundPolicy.resumability, .nonResumable)
        XCTAssertTrue(record.backgroundPolicy.limits.contains(.foregroundRequired))
        XCTAssertTrue(record.backgroundPolicy.limits.contains(.notResumable))
        XCTAssertFalse(record.backgroundPolicy.canResume)
        XCTAssertFalse(record.backgroundPolicy.allowsUnboundedBackgroundExecution)
        XCTAssertEqual(record.artifactStorageIdentifier, "downloads/task-1.mp4")
        XCTAssertEqual(record.lastProgress, MobileTaskProgress(phase: .downloading, completedUnitCount: 11, totalUnitCount: 11))
    }

    func testRejectsNonHTTPSURLBeforeStartingDownload() async throws {
        let directory = temporaryDirectory()
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        let transport = RecordingMobileDownloadTransport(resultFileURL: directory.appendingPathComponent("unused.mp4"))
        let engine = IOSMobileDownloadEngine(
            downloadDirectoryURL: directory,
            transferRegistry: registry,
            transport: transport
        )

        do {
            _ = try await engine.download(
                MobileDownloadRequest(
                    id: "task-2",
                    sourceURL: "http://cdn.example.com/video.mp4",
                    candidateID: "candidate-2",
                    videoID: "video-2",
                    formatID: "720p"
                ),
                progress: { _ in }
            )
            XCTFail("Plain HTTP downloads should be rejected before any request is made.")
        } catch let error as IOSMobileDownloadEngine.DownloadError {
            XCTAssertEqual(error, .unsupportedURL)
        }

        let recordedURL = await transport.firstURL()
        XCTAssertNil(recordedURL)
        let records = try await registry.loadRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testRejectsCredentialedAndFragmentURLBeforeStartingDownload() async throws {
        for sourceURL in [
            "https://viewer@cdn.example.com/video.mp4",
            "https://cdn.example.com/video.mp4#session"
        ] {
            let directory = temporaryDirectory()
            let registry = try BackgroundTransferRegistry(directoryURL: directory)
            let transport = RecordingMobileDownloadTransport(resultFileURL: directory.appendingPathComponent("unused.mp4"))
            let engine = IOSMobileDownloadEngine(
                downloadDirectoryURL: directory,
                transferRegistry: registry,
                transport: transport
            )

            do {
                _ = try await engine.download(
                    MobileDownloadRequest(
                        id: "task-\(UUID().uuidString)",
                        sourceURL: sourceURL,
                        candidateID: "candidate",
                        videoID: "video",
                        formatID: "mp4"
                    ),
                    progress: { _ in }
                )
                XCTFail("Credentialed or fragmented downloads should be rejected before any request is made.")
            } catch let error as IOSMobileDownloadEngine.DownloadError {
                XCTAssertEqual(error, .unsupportedURL)
            }

            let recordedURL = await transport.firstURL()
            XCTAssertNil(recordedURL)
            let records = try await registry.loadRecords()
            XCTAssertTrue(records.isEmpty)
        }
    }

    func testRejectsHTTPFailureStatusBeforeStoringArtifact() async throws {
        let directory = temporaryDirectory()
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        HTTPStatusURLProtocol.responseStatusCode = 404
        HTTPStatusURLProtocol.responseBody = Data("forbidden".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPStatusURLProtocol.self]
        let transport = IOSURLSessionMobileDownloadTransport(session: URLSession(configuration: configuration))
        let engine = IOSMobileDownloadEngine(
            downloadDirectoryURL: directory,
            transferRegistry: registry,
            transport: transport
        )

        do {
            _ = try await engine.download(
                MobileDownloadRequest(
                    id: "task-404",
                    sourceURL: "https://cdn.example.com/private-video.mp4",
                    candidateID: "candidate-404",
                    videoID: "video-404",
                    formatID: "mp4"
                ),
                progress: { _ in }
            )
            XCTFail("HTTP error responses should not become completed media artifacts.")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("task-404.mp4").path))
        }

        let records = try await registry.loadRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testRejectsUnsafeTaskIDBeforeMovingFileOutsideDownloadDirectory() async throws {
        let directory = temporaryDirectory()
        let sourceFile = directory.appendingPathComponent("source-video.mp4")
        try Data("video-bytes".utf8).write(to: sourceFile)
        let escapedURL = directory.deletingLastPathComponent().appendingPathComponent("escape.mp4")
        try? FileManager.default.removeItem(at: escapedURL)
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        let transport = RecordingMobileDownloadTransport(resultFileURL: sourceFile, byteCount: 11)
        let engine = IOSMobileDownloadEngine(
            downloadDirectoryURL: directory,
            transferRegistry: registry,
            transport: transport
        )

        do {
            _ = try await engine.download(
                MobileDownloadRequest(
                    id: "../escape",
                    sourceURL: "https://cdn.example.com/video.mp4",
                    candidateID: "candidate-escape",
                    videoID: "video-escape",
                    formatID: "mp4"
                ),
                progress: { _ in }
            )
            XCTFail("Unsafe task IDs must not be accepted as storage file names.")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: escapedURL.path))
        }

        let records = try await registry.loadRecords()
        XCTAssertTrue(records.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-mobile-download-engine-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor RecordingMobileDownloadTransport: IOSMobileDownloadTransport {
    private let resultFileURL: URL
    private let byteCount: Int?
    private var urls: [URL] = []

    init(resultFileURL: URL, byteCount: Int? = nil) {
        self.resultFileURL = resultFileURL
        self.byteCount = byteCount
    }

    func download(
        from url: URL,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> IOSMobileDownloadTransportResult {
        urls.append(url)
        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: 5, totalUnitCount: byteCount))
        return IOSMobileDownloadTransportResult(temporaryFileURL: resultFileURL, byteCount: byteCount)
    }

    func firstURL() -> URL? {
        urls.first
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MobileTaskProgress] = []

    func record(_ progress: MobileTaskProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshots() -> [MobileTaskProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class HTTPStatusURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseStatusCode = 200
    static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: Self.responseStatusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(Self.responseBody.count)"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
