import Foundation
import MoongateMobileCore

public struct IOSBackgroundTransferEventHandler: Sendable {
    public enum EventError: Error, Sendable, Equatable {
        case missingTransferRecord
        case unsafeArtifactIdentifier
    }

    private let storageDirectoryURL: URL
    private let transferRegistry: BackgroundTransferRegistry
    private let artifactStore: IOSArtifactStore

    public init(
        storageDirectoryURL: URL,
        transferRegistry: BackgroundTransferRegistry
    ) {
        self.storageDirectoryURL = storageDirectoryURL
        self.transferRegistry = transferRegistry
        self.artifactStore = IOSArtifactStore(storageDirectoryURL: storageDirectoryURL)
    }

    public func recordCompletedDownload(
        transferIdentifier: String,
        temporaryFileURL: URL,
        updatedAt: Date = Date()
    ) async throws -> BackgroundTransferRecoveryOutcome {
        let record = try await transferRecord(for: transferIdentifier)
        let storageIdentifier = record.artifactStorageIdentifier ?? "downloads/\(record.taskID).mp4"
        let outputURL: URL
        do {
            outputURL = try artifactStore.fileURL(forStorageIdentifier: storageIdentifier)
        } catch {
            throw EventError.unsafeArtifactIdentifier
        }

        try IOSAppStoragePolicy.applyDirectoryPolicy(to: outputURL.deletingLastPathComponent())
        let replacementURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).replacement-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: temporaryFileURL, to: replacementURL)
        do {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: replacementURL)
        } catch {
            try? FileManager.default.removeItem(at: replacementURL)
            throw error
        }
        try IOSAppStoragePolicy.applyFilePolicy(to: outputURL)

        let byteCount = storedByteCount(at: outputURL)
        let progress = MobileTaskProgress(
            phase: .downloading,
            completedUnitCount: byteCount ?? record.lastProgress.completedUnitCount,
            totalUnitCount: byteCount ?? record.lastProgress.totalUnitCount
        )
        let artifact = MobileTaskArtifact(
            id: "original-\(record.taskID)",
            kind: .originalMedia,
            displayName: outputURL.lastPathComponent,
            storageIdentifier: storageIdentifier,
            byteCount: byteCount
        )
        let outcome = BackgroundTransferRecoveryOutcome(
            transferIdentifier: transferIdentifier,
            taskID: record.taskID,
            platform: record.platform,
            status: .completed,
            result: MobileTaskResult(artifacts: [artifact], primaryArtifactID: artifact.id),
            progress: progress,
            backgroundPolicy: record.backgroundPolicy,
            updatedAt: updatedAt
        )
        try await transferRegistry.recordRecoveryOutcome(outcome)
        return outcome
    }

    public func recordFailedDownload(
        transferIdentifier: String,
        error: MobileTaskError,
        updatedAt: Date = Date()
    ) async throws -> BackgroundTransferRecoveryOutcome {
        let record = try await transferRecord(for: transferIdentifier)
        return try await recordOutcome(
            for: record,
            status: .failed,
            error: error,
            progress: record.lastProgress,
            backgroundPolicy: record.backgroundPolicy,
            updatedAt: updatedAt
        )
    }

    public func recordExpiredDownload(
        transferIdentifier: String,
        updatedAt: Date = Date()
    ) async throws -> BackgroundTransferRecoveryOutcome {
        let record = try await transferRecord(for: transferIdentifier)
        var interruptedPolicy = record.backgroundPolicy
        interruptedPolicy.execution = .systemInterrupted
        if !interruptedPolicy.limits.contains(.systemInterrupted) {
            interruptedPolicy.limits.append(.systemInterrupted)
        }
        if !interruptedPolicy.limits.contains(.notResumable) {
            interruptedPolicy.limits.append(.notResumable)
        }

        return try await recordOutcome(
            for: record,
            status: .expired,
            error: .systemBackgroundLimit,
            progress: record.lastProgress,
            backgroundPolicy: interruptedPolicy,
            updatedAt: updatedAt
        )
    }

    private func transferRecord(for transferIdentifier: String) async throws -> BackgroundTransferRecord {
        let records = try await transferRegistry.loadRecords()
        guard let record = records.first(where: { $0.transferIdentifier == transferIdentifier }) else {
            throw EventError.missingTransferRecord
        }
        return record
    }

    private func recordOutcome(
        for record: BackgroundTransferRecord,
        status: BackgroundTransferRecoveryStatus,
        error: MobileTaskError?,
        progress: MobileTaskProgress,
        backgroundPolicy: MobileBackgroundPolicy,
        updatedAt: Date
    ) async throws -> BackgroundTransferRecoveryOutcome {
        let outcome = BackgroundTransferRecoveryOutcome(
            transferIdentifier: record.transferIdentifier,
            taskID: record.taskID,
            platform: record.platform,
            status: status,
            error: error,
            progress: progress,
            backgroundPolicy: backgroundPolicy,
            updatedAt: updatedAt
        )
        try await transferRegistry.recordRecoveryOutcome(outcome)
        return outcome
    }

    private func storedByteCount(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[FileAttributeKey.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }
}
