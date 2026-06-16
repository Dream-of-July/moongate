import Foundation
import MoongateMobileCore

public actor FileTaskRepository: TaskRepository {
    public enum RepositoryError: Error, Equatable {
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

    public init(directoryURL: URL, fileName: String = "mobile-tasks.json") throws {
        guard !fileName.contains("/") else {
            throw RepositoryError.invalidDirectory
        }
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: directoryURL)
        self.init(fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false))
    }

    public func loadTasks() async throws -> [MobileTaskSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([MobileTaskSnapshot].self, from: data)
    }

    public func saveTask(_ snapshot: MobileTaskSnapshot) async throws {
        var tasks = try await loadTasks()
        tasks.removeAll { $0.id == snapshot.id }
        tasks.append(sanitizedForPersistence(snapshot))
        try write(tasks)
    }

    public func removeTask(id: String) async throws {
        var tasks = try await loadTasks()
        tasks.removeAll { $0.id == id }
        try write(tasks)
    }

    private func write(_ tasks: [MobileTaskSnapshot]) throws {
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: fileURL.deletingLastPathComponent())
        let data = try encoder.encode(tasks.sorted { $0.id < $1.id })
        try data.write(to: fileURL, options: [.atomic])
        try IOSAppStoragePolicy.applyFilePolicy(to: fileURL)
    }

    private func sanitizedForPersistence(_ snapshot: MobileTaskSnapshot) -> MobileTaskSnapshot {
        guard let result = snapshot.result else {
            return snapshot
        }

        var sanitized = snapshot
        sanitized.result = MobileTaskResult(
            artifacts: result.artifacts.map { sanitizedSourceArtifact($0, taskID: snapshot.id) },
            primaryArtifactID: result.primaryArtifactID
        )
        return sanitized
    }

    private func sanitizedSourceArtifact(_ artifact: MobileTaskArtifact, taskID: String) -> MobileTaskArtifact {
        guard artifact.storageIdentifier.hasPrefix("source:") else {
            return artifact
        }

        var copy = artifact
        copy.storageIdentifier = "mobile-source:\(taskID)"
        return copy
    }
}
