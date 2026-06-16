@testable import MoongateMobileCore
@testable import MoongateiOS
import XCTest

final class BackgroundTransferRegistryTests: XCTestCase {
    func testRecordsProgressAndRecoverableTaskIDsWithoutClaimingUnboundedBackground() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let resumable = BackgroundTransferRecord(
            transferIdentifier: "session.download.1",
            taskID: "task-resumable",
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            artifactStorageIdentifier: "downloads/task-resumable.part",
            lastProgress: MobileTaskProgress(phase: .downloading, completedUnitCount: 1, totalUnitCount: 10),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let nonResumable = BackgroundTransferRecord(
            transferIdentifier: "session.render.1",
            taskID: "task-non-resumable",
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .systemInterrupted,
                resumability: .nonResumable,
                limits: [.notResumable, .systemInterrupted]
            )
        )

        try await registry.record(resumable)
        try await registry.record(nonResumable)
        try await registry.recordProgress(
            transferIdentifier: "session.download.1",
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 7, totalUnitCount: 10),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let records = try await registry.loadRecords()
        let updated = try XCTUnwrap(records.first { $0.transferIdentifier == "session.download.1" })

        XCTAssertEqual(updated.lastProgress.completedUnitCount, 7)
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 2))
        let recoverableTaskIDs = try await registry.recoverableTaskIDs()
        XCTAssertEqual(recoverableTaskIDs, ["task-resumable"])
        XCTAssertTrue(records.allSatisfy { !$0.backgroundPolicy.allowsUnboundedBackgroundExecution })
    }

    func testRemoveTransferRecord() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())

        try await registry.record(
            BackgroundTransferRecord(
                transferIdentifier: "session.download.1",
                taskID: "task-1",
                platform: .iOS,
                backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable)
            )
        )
        try await registry.remove(transferIdentifier: "session.download.1")

        let records = try await registry.loadRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testRemoveTaskIDRemovesTransferRecordsAndRecoveryOutcomesForCancelledWork() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())

        try await registry.record(
            BackgroundTransferRecord(
                transferIdentifier: "ios.download.task-1",
                taskID: "task-1",
                platform: .iOS,
                backgroundPolicy: MobileBackgroundPolicy(
                    execution: .backgroundTransfer,
                    resumability: .resumable,
                    limits: [.systemDeferred]
                )
            )
        )
        try await registry.recordRecoveryOutcome(
            BackgroundTransferRecoveryOutcome(
                transferIdentifier: "ios.download.task-2",
                taskID: "task-2",
                platform: .iOS,
                status: .failed,
                error: .networkUnavailable,
                backgroundPolicy: MobileBackgroundPolicy(
                    execution: .backgroundTransfer,
                    resumability: .resumable,
                    limits: [.systemDeferred]
                )
            )
        )

        try await registry.remove(taskID: "task-1")

        let recoverableTaskIDs = try await registry.recoverableTaskIDs()
        let outcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(recoverableTaskIDs, ["task-2"])
        XCTAssertEqual(outcomes.map(\.taskID), ["task-2"])

        try await registry.remove(taskID: "task-2")

        let finalRecoverableTaskIDs = try await registry.recoverableTaskIDs()
        let finalOutcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(finalRecoverableTaskIDs, [])
        XCTAssertEqual(finalOutcomes, [])
    }

    func testRecordsAndConsumesRecoveryOutcomeForColdStartReconciliation() async throws {
        let registry = try BackgroundTransferRegistry(directoryURL: temporaryDirectory())
        let result = MobileTaskResult(artifacts: [
            MobileTaskArtifact(
                id: "original-task-1",
                kind: .originalMedia,
                displayName: "Recovered Clip.mp4",
                storageIdentifier: "downloads/recovered.mp4",
                byteCount: 12
            )
        ], primaryArtifactID: "original-task-1")
        let outcome = BackgroundTransferRecoveryOutcome(
            transferIdentifier: "ios.download.task-1",
            taskID: "task-1",
            platform: .iOS,
            status: .completed,
            result: result,
            progress: MobileTaskProgress(phase: .downloading, completedUnitCount: 12, totalUnitCount: 12),
            backgroundPolicy: MobileBackgroundPolicy(execution: .backgroundTransfer, resumability: .resumable),
            updatedAt: Date(timeIntervalSince1970: 3)
        )

        try await registry.recordRecoveryOutcome(outcome)

        let outcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertEqual(outcomes, [outcome])
        let records = try await registry.loadRecords()
        XCTAssertEqual(records.first?.recoveryOutcome, outcome)
        XCTAssertEqual(records.first?.artifactStorageIdentifier, "downloads/recovered.mp4")

        try await registry.removeRecoveryOutcome(transferIdentifier: "ios.download.task-1")

        let remainingOutcomes = try await registry.loadRecoveryOutcomes()
        XCTAssertTrue(remainingOutcomes.isEmpty)
    }

    func testRejectsRegistryFileNameWithPathSeparator() throws {
        XCTAssertThrowsError(
            try BackgroundTransferRegistry(directoryURL: temporaryDirectory(), fileName: "../registry.json")
        ) { error in
            XCTAssertEqual(error as? BackgroundTransferRegistry.RegistryError, .invalidDirectory)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-background-transfer-registry-\(UUID().uuidString)", isDirectory: true)
    }
}
