@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

final class IOSBackgroundTransferEventHandlerTests: XCTestCase {
    func testCompletedBackgroundDownloadMovesTemporaryFileIntoAppStorageAndRecordsRecoveryOutcome() async throws {
        let directory = temporaryDirectory()
        let temporaryURL = directory.appendingPathComponent("system-temp-download")
        try Data("background-video".utf8).write(to: temporaryURL)
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        try await registry.record(BackgroundTransferRecord(
            transferIdentifier: "ios.download.background-1",
            taskID: "background-1",
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            artifactStorageIdentifier: "downloads/background-1.mp4",
            lastProgress: MobileTaskProgress(phase: .downloading, completedUnitCount: 4, totalUnitCount: 20),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        let handler = IOSBackgroundTransferEventHandler(
            storageDirectoryURL: directory,
            transferRegistry: registry
        )

        let outcome = try await handler.recordCompletedDownload(
            transferIdentifier: "ios.download.background-1",
            temporaryFileURL: temporaryURL,
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(outcome.status, .completed)
        XCTAssertEqual(outcome.taskID, "background-1")
        XCTAssertEqual(outcome.backgroundPolicy.execution, .backgroundTransfer)
        XCTAssertEqual(outcome.backgroundPolicy.resumability, .resumable)
        XCTAssertEqual(outcome.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 16, totalUnitCount: 16))
        XCTAssertEqual(outcome.result?.primaryArtifact?.storageIdentifier, "downloads/background-1.mp4")
        XCTAssertEqual(outcome.result?.primaryArtifact?.displayName, "background-1.mp4")

        let storedURL = directory.appendingPathComponent("Downloads/background-1.mp4")
        XCTAssertEqual(try Data(contentsOf: storedURL), Data("background-video".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))

        let outcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(outcomes, [outcome])
        XCTAssertTrue(outcomes.allSatisfy { !$0.backgroundPolicy.allowsUnboundedBackgroundExecution })
    }

    func testCompletedBackgroundDownloadDoesNotDeleteStoredArtifactWhenReplacementIsMissing() async throws {
        let directory = temporaryDirectory()
        let storedURL = directory.appendingPathComponent("Downloads/background-1.mp4")
        try FileManager.default.createDirectory(
            at: storedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("already-stored-video".utf8).write(to: storedURL)
        let missingTemporaryURL = directory.appendingPathComponent("missing-system-temp-download")
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        try await registry.record(BackgroundTransferRecord(
            transferIdentifier: "ios.download.background-1",
            taskID: "background-1",
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            artifactStorageIdentifier: "downloads/background-1.mp4",
            lastProgress: MobileTaskProgress(phase: .downloading, completedUnitCount: 4, totalUnitCount: 20),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        let handler = IOSBackgroundTransferEventHandler(
            storageDirectoryURL: directory,
            transferRegistry: registry
        )

        do {
            _ = try await handler.recordCompletedDownload(
                transferIdentifier: "ios.download.background-1",
                temporaryFileURL: missingTemporaryURL,
                updatedAt: Date(timeIntervalSince1970: 2)
            )
            XCTFail("Expected missing replacement file to fail without deleting the stored artifact.")
        } catch {
            XCTAssertEqual(try Data(contentsOf: storedURL), Data("already-stored-video".utf8))
            let recoveryOutcomes = try await registry.loadRecoveryOutcomes()
            XCTAssertTrue(recoveryOutcomes.isEmpty)
        }
    }

    func testFailedAndExpiredBackgroundEventsRecordRecoverableOutcomesWithoutDeletingTransferEvidence() async throws {
        let directory = temporaryDirectory()
        let registry = try BackgroundTransferRegistry(directoryURL: directory)
        try await registry.record(BackgroundTransferRecord(
            transferIdentifier: "ios.download.failed",
            taskID: "failed",
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            lastProgress: MobileTaskProgress(phase: .downloading, completedUnitCount: 2, totalUnitCount: 10),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        try await registry.record(BackgroundTransferRecord(
            transferIdentifier: "ios.download.expired",
            taskID: "expired",
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            lastProgress: MobileTaskProgress(phase: .downloading, completedUnitCount: 6, totalUnitCount: 10),
            updatedAt: Date(timeIntervalSince1970: 2)
        ))
        let handler = IOSBackgroundTransferEventHandler(
            storageDirectoryURL: directory,
            transferRegistry: registry
        )

        let failed = try await handler.recordFailedDownload(
            transferIdentifier: "ios.download.failed",
            error: .networkUnavailable,
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let expired = try await handler.recordExpiredDownload(
            transferIdentifier: "ios.download.expired",
            updatedAt: Date(timeIntervalSince1970: 4)
        )

        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.error, .networkUnavailable)
        XCTAssertEqual(failed.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 2, totalUnitCount: 10))

        XCTAssertEqual(expired.status, .expired)
        XCTAssertEqual(expired.error, .systemBackgroundLimit)
        XCTAssertEqual(expired.progress, MobileTaskProgress(phase: .downloading, completedUnitCount: 6, totalUnitCount: 10))
        XCTAssertTrue(expired.backgroundPolicy.limits.contains(.systemInterrupted))

        let outcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(outcomes.map(\.taskID), ["expired", "failed"])
        let records = try await registry.loadRecords()
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.recoveryOutcome != nil })
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-background-transfer-handler-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
