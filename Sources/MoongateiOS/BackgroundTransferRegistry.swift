import Foundation
import MoongateMobileCore

public enum BackgroundTransferRecoveryStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case completed
    case failed
    case expired
}

public struct BackgroundTransferRecoveryOutcome: Codable, Sendable, Equatable, Identifiable {
    public var id: String { transferIdentifier }
    public var transferIdentifier: String
    public var taskID: String
    public var platform: MobilePlatform
    public var status: BackgroundTransferRecoveryStatus
    public var result: MobileTaskResult?
    public var error: MobileTaskError?
    public var progress: MobileTaskProgress
    public var backgroundPolicy: MobileBackgroundPolicy
    public var updatedAt: Date

    public init(
        transferIdentifier: String,
        taskID: String,
        platform: MobilePlatform,
        status: BackgroundTransferRecoveryStatus,
        result: MobileTaskResult? = nil,
        error: MobileTaskError? = nil,
        progress: MobileTaskProgress = MobileTaskProgress(),
        backgroundPolicy: MobileBackgroundPolicy,
        updatedAt: Date = Date()
    ) {
        self.transferIdentifier = transferIdentifier
        self.taskID = taskID
        self.platform = platform
        self.status = status
        self.result = result
        self.error = error
        self.progress = progress
        self.backgroundPolicy = backgroundPolicy
        self.updatedAt = updatedAt
    }
}

public struct BackgroundTransferRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { transferIdentifier }
    public var transferIdentifier: String
    public var taskID: String
    public var platform: MobilePlatform
    public var backgroundPolicy: MobileBackgroundPolicy
    public var artifactStorageIdentifier: String?
    public var lastProgress: MobileTaskProgress
    public var updatedAt: Date
    public var recoveryOutcome: BackgroundTransferRecoveryOutcome?

    public init(
        transferIdentifier: String,
        taskID: String,
        platform: MobilePlatform,
        backgroundPolicy: MobileBackgroundPolicy,
        artifactStorageIdentifier: String? = nil,
        lastProgress: MobileTaskProgress = MobileTaskProgress(),
        updatedAt: Date = Date(),
        recoveryOutcome: BackgroundTransferRecoveryOutcome? = nil
    ) {
        self.transferIdentifier = transferIdentifier
        self.taskID = taskID
        self.platform = platform
        self.backgroundPolicy = backgroundPolicy
        self.artifactStorageIdentifier = artifactStorageIdentifier
        self.lastProgress = lastProgress
        self.updatedAt = updatedAt
        self.recoveryOutcome = recoveryOutcome
    }
}

public actor BackgroundTransferRegistry {
    public enum RegistryError: Error, Equatable {
        case invalidDirectory
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public init(directoryURL: URL, fileName: String = "background-transfers.json") throws {
        guard !fileName.contains("/") else {
            throw RegistryError.invalidDirectory
        }
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: directoryURL)
        self.init(fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false))
    }

    public func loadRecords() async throws -> [BackgroundTransferRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([BackgroundTransferRecord].self, from: data)
    }

    public func record(_ record: BackgroundTransferRecord) async throws {
        var records = try await loadRecords()
        records.removeAll { $0.transferIdentifier == record.transferIdentifier }
        records.append(record)
        try write(records)
    }

    public func recordProgress(
        transferIdentifier: String,
        progress: MobileTaskProgress,
        updatedAt: Date = Date()
    ) async throws {
        var records = try await loadRecords()
        guard let index = records.firstIndex(where: { $0.transferIdentifier == transferIdentifier }) else {
            return
        }
        records[index].lastProgress = progress
        records[index].updatedAt = updatedAt
        try write(records)
    }

    public func recordRecoveryOutcome(_ outcome: BackgroundTransferRecoveryOutcome) async throws {
        var records = try await loadRecords()
        let artifactStorageIdentifier = outcome.result?.primaryArtifact?.storageIdentifier
        if let index = records.firstIndex(where: { $0.transferIdentifier == outcome.transferIdentifier }) {
            records[index].taskID = outcome.taskID
            records[index].platform = outcome.platform
            records[index].backgroundPolicy = outcome.backgroundPolicy
            if let artifactStorageIdentifier {
                records[index].artifactStorageIdentifier = artifactStorageIdentifier
            }
            records[index].lastProgress = outcome.progress
            records[index].updatedAt = outcome.updatedAt
            records[index].recoveryOutcome = outcome
        } else {
            records.append(BackgroundTransferRecord(
                transferIdentifier: outcome.transferIdentifier,
                taskID: outcome.taskID,
                platform: outcome.platform,
                backgroundPolicy: outcome.backgroundPolicy,
                artifactStorageIdentifier: artifactStorageIdentifier,
                lastProgress: outcome.progress,
                updatedAt: outcome.updatedAt,
                recoveryOutcome: outcome
            ))
        }
        try write(records)
    }

    public func loadRecoveryOutcomes() async throws -> [BackgroundTransferRecoveryOutcome] {
        try await loadRecords()
            .compactMap(\.recoveryOutcome)
            .sorted { $0.transferIdentifier < $1.transferIdentifier }
    }

    public func removeRecoveryOutcome(transferIdentifier: String) async throws {
        var records = try await loadRecords()
        records.removeAll { $0.transferIdentifier == transferIdentifier }
        try write(records)
    }

    public func remove(transferIdentifier: String) async throws {
        var records = try await loadRecords()
        records.removeAll { $0.transferIdentifier == transferIdentifier }
        try write(records)
    }

    public func remove(taskID: String) async throws {
        var records = try await loadRecords()
        records.removeAll { $0.taskID == taskID }
        try write(records)
    }

    public func recoverableTaskIDs() async throws -> [String] {
        try await loadRecords()
            .filter { $0.backgroundPolicy.canResume }
            .map(\.taskID)
            .sorted()
    }

    private func write(_ records: [BackgroundTransferRecord]) throws {
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: fileURL.deletingLastPathComponent())
        let data = try encoder.encode(records.sorted { $0.transferIdentifier < $1.transferIdentifier })
        try data.write(to: fileURL, options: [.atomic])
        try IOSAppStoragePolicy.applyFilePolicy(to: fileURL)
    }
}
