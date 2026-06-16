@testable import MoongateMobileCore
@testable import MoongateiOS
import Foundation
import XCTest

final class IOSBackgroundURLSessionDownloadDelegateTests: XCTestCase {
    func testBackgroundSessionDescriptorCreatesStableNoCacheConfiguration() throws {
        let descriptor = IOSBackgroundURLSessionDescriptor(
            bundleIdentifier: "com.local.videodownloader.ios",
            purpose: "downloads"
        )

        XCTAssertEqual(
            descriptor.identifier,
            "com.local.videodownloader.ios.background.downloads"
        )

        let configuration = descriptor.makeConfiguration()
        XCTAssertEqual(configuration.identifier, descriptor.identifier)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    @MainActor
    func testLiveModelUsesInjectedBundleIdentifierForBackgroundDownloadSession() async throws {
        let directory = temporaryDirectory()
        let completionConsumer = RecordingCompletionConsumer()
        let model = IOSMobileAppModel.live(
            storageDirectoryURL: directory,
            bundleIdentifier: "com.example.vdl.beta",
            backgroundCompletionConsumer: completionConsumer
        )

        let delegate = try XCTUnwrap(model.backgroundURLSessionDownloadDelegateForTesting)
        delegate.finishEvents(forSessionIdentifier: "com.example.vdl.beta.background.downloads")

        XCTAssertEqual(
            completionConsumer.consumedIdentifiers(),
            ["com.example.vdl.beta.background.downloads"]
        )
    }

    func testFinishedDownloadRecordsCompletedOutcomeAndDrainsCompletionHandlerOnce() async throws {
        let directory = temporaryDirectory()
        let temporaryURL = directory.appendingPathComponent("system-background-download")
        try Data("background-bytes".utf8).write(to: temporaryURL)
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        try await registry.record(backgroundRecord(transferIdentifier: "ios.download.task-1", taskID: "task-1"))
        let completionConsumer = RecordingCompletionConsumer()
        let delegate = IOSBackgroundURLSessionDownloadDelegate(
            eventRecorder: IOSBackgroundTransferEventHandler(
                storageDirectoryURL: directory,
                transferRegistry: registry
            ),
            completionConsumer: completionConsumer
        )

        let outcome = try await delegate.recordFinishedDownload(
            transferIdentifier: "ios.download.task-1",
            temporaryFileURL: temporaryURL,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        delegate.finishEvents(forSessionIdentifier: "com.local.videodownloader.ios.background.downloads")
        delegate.finishEvents(forSessionIdentifier: "com.local.videodownloader.ios.background.downloads")

        XCTAssertEqual(outcome.status, .completed)
        XCTAssertEqual(outcome.taskID, "task-1")
        XCTAssertEqual(outcome.result?.primaryArtifact?.storageIdentifier, "downloads/task-1.mp4")
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("Downloads/task-1.mp4")),
            Data("background-bytes".utf8)
        )
        XCTAssertEqual(
            completionConsumer.consumedIdentifiers(),
            ["com.local.videodownloader.ios.background.downloads"]
        )
    }

    func testBackgroundSessionCompletionWaitsForPendingFinishedDownloadOutcome() async throws {
        let directory = temporaryDirectory()
        let temporaryURL = directory.appendingPathComponent("system-background-download-pending")
        try Data("background-bytes".utf8).write(to: temporaryURL)
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        try await registry.record(backgroundRecord(transferIdentifier: "ios.download.task-pending", taskID: "task-pending"))
        let completionConsumer = RecordingCompletionConsumer()
        let delegate = IOSBackgroundURLSessionDownloadDelegate(
            eventRecorder: IOSBackgroundTransferEventHandler(
                storageDirectoryURL: directory,
                transferRegistry: registry
            ),
            completionConsumer: completionConsumer
        )

        delegate.enqueueFinishedDownload(
            transferIdentifier: "ios.download.task-pending",
            temporaryFileURL: temporaryURL,
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        delegate.finishEvents(forSessionIdentifier: "com.local.videodownloader.ios.background.downloads")

        XCTAssertEqual(
            completionConsumer.consumedIdentifiers(),
            [],
            "The background URLSession completion handler must not be consumed until the temporary file has moved and the recovery outcome is recorded."
        )

        try await waitUntil {
            !completionConsumer.consumedIdentifiers().isEmpty
        }

        XCTAssertEqual(
            completionConsumer.consumedIdentifiers(),
            ["com.local.videodownloader.ios.background.downloads"]
        )
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("Downloads/task-pending.mp4")),
            Data("background-bytes".utf8)
        )
        let outcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(outcomes.map(\.taskID), ["task-pending"])
    }

    func testTaskFailureRecordsFailedOutcomeWithMobileErrorBucket() async throws {
        let directory = temporaryDirectory()
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        try await registry.record(backgroundRecord(transferIdentifier: "ios.download.task-2", taskID: "task-2"))
        let delegate = IOSBackgroundURLSessionDownloadDelegate(
            eventRecorder: IOSBackgroundTransferEventHandler(
                storageDirectoryURL: directory,
                transferRegistry: registry
            ),
            completionConsumer: RecordingCompletionConsumer()
        )

        let outcome = try await delegate.recordTaskFailure(
            transferIdentifier: "ios.download.task-2",
            error: URLError(.notConnectedToInternet),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(outcome.status, .failed)
        XCTAssertEqual(outcome.taskID, "task-2")
        XCTAssertEqual(outcome.error, .networkUnavailable)
        XCTAssertEqual(outcome.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 4, totalUnitCount: 20))
    }

    @MainActor
    func testLiveModelWiresInjectedBackgroundCompletionConsumer() async throws {
        let directory = temporaryDirectory()
        let completionConsumer = RecordingCompletionConsumer()
        let model = IOSMobileAppModel.live(
            storageDirectoryURL: directory,
            backgroundCompletionConsumer: completionConsumer
        )
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        try await registry.record(backgroundRecord(transferIdentifier: "ios.download.task-3", taskID: "task-3"))
        let temporaryURL = directory.appendingPathComponent("system-background-download-3")
        try Data("background-bytes".utf8).write(to: temporaryURL)

        let delegate = try XCTUnwrap(model.backgroundURLSessionDownloadDelegateForTesting)
        _ = try await delegate.recordFinishedDownload(
            transferIdentifier: "ios.download.task-3",
            temporaryFileURL: temporaryURL,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        delegate.finishEvents(forSessionIdentifier: "com.local.videodownloader.ios.background.downloads")

        XCTAssertEqual(
            completionConsumer.consumedIdentifiers(),
            ["com.local.videodownloader.ios.background.downloads"]
        )
    }

    private func backgroundRecord(
        transferIdentifier: String,
        taskID: String
    ) -> BackgroundTransferRecord {
        BackgroundTransferRecord(
            transferIdentifier: transferIdentifier,
            taskID: taskID,
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            artifactStorageIdentifier: "downloads/\(taskID).mp4",
            lastProgress: MobileTaskProgress(phase: .downloading, completedUnitCount: 4, totalUnitCount: 20),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-background-urlsession-delegate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition.")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class RecordingCompletionConsumer: IOSBackgroundURLSessionCompletionConsuming, @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String] = []

    func consumeCompletionHandler(for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !identifiers.contains(identifier) else { return }
        identifiers.append(identifier)
    }

    func consumedIdentifiers() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return identifiers
    }
}
