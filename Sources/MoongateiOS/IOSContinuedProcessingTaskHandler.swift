import Foundation
import MoongateMobileCore

#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
#endif

public protocol IOSContinuedProcessingSystemTask: Sendable {
    var identifier: String { get }

    func updateProgress(_ progress: MobileTaskProgress) async
    func setExpirationHandler(_ handler: @escaping @Sendable () async -> Void) async
    func setTaskCompleted(success: Bool) async
}

public struct IOSContinuedProcessingTaskHandler: Sendable {
    public enum HandlerError: Error, Equatable, Sendable {
        case unrecognizedIdentifier
    }

    private let bundleIdentifier: String
    private let coordinator: IOSContinuedProcessingTaskCoordinator

    public init(
        bundleIdentifier: String,
        coordinator: IOSContinuedProcessingTaskCoordinator
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.coordinator = coordinator
    }

    public func register(_ task: any IOSContinuedProcessingSystemTask) async throws {
        let taskID = try taskID(for: task)
        await task.setExpirationHandler { [coordinator] in
            _ = try? await coordinator.markExpired(taskID: taskID)
            let success = false
            await task.setTaskCompleted(success: success)
        }
    }

    public func recordProgress(
        for task: any IOSContinuedProcessingSystemTask,
        progress: MobileTaskProgress
    ) async throws -> MobileTaskSnapshot? {
        let taskID = try taskID(for: task)
        let updated = try await coordinator.recordProgress(taskID: taskID, progress: progress)
        await task.updateProgress(progress)
        return updated
    }

    public func taskID(for task: any IOSContinuedProcessingSystemTask) throws -> String {
        try renderTaskID(from: task.identifier)
    }

    private func renderTaskID(from identifier: String) throws -> String {
        let prefix = "\(bundleIdentifier).render."
        guard identifier.hasPrefix(prefix) else {
            throw HandlerError.unrecognizedIdentifier
        }
        let encodedTaskID = String(identifier.dropFirst(prefix.count))
        guard !encodedTaskID.isEmpty else {
            throw HandlerError.unrecognizedIdentifier
        }
        if encodedTaskID.hasPrefix("encoded-hex-") {
            return try decodedTaskID(from: String(encodedTaskID.dropFirst("encoded-hex-".count)))
        }
        return encodedTaskID
    }

    private func decodedTaskID(from hex: String) throws -> String {
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else {
            throw HandlerError.unrecognizedIdentifier
        }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw HandlerError.unrecognizedIdentifier
            }
            bytes.append(byte)
            index = next
        }
        guard let taskID = String(bytes: bytes, encoding: .utf8), !taskID.isEmpty else {
            throw HandlerError.unrecognizedIdentifier
        }
        return taskID
    }
}

#if os(iOS) && canImport(BackgroundTasks)
@available(iOS 26.0, *)
public final class IOSBackgroundContinuedProcessingSystemTask: IOSContinuedProcessingSystemTask {
    private let task: BGContinuedProcessingTask

    public var identifier: String {
        task.identifier
    }

    public init(task: BGContinuedProcessingTask) {
        self.task = task
    }

    public func updateProgress(_ progress: MobileTaskProgress) async {
        guard let fractionCompleted = progress.fractionCompleted else {
            return
        }
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = Int64((fractionCompleted * 100).rounded())
    }

    public func setExpirationHandler(_ handler: @escaping @Sendable () async -> Void) async {
        task.expirationHandler = {
            Task {
                await handler()
            }
        }
    }

    public func setTaskCompleted(success: Bool) async {
        task.setTaskCompleted(success: success)
    }
}
#endif
