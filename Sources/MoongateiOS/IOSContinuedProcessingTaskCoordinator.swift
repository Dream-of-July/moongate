import Foundation
import MoongateMobileCore

public struct IOSContinuedProcessingTaskCoordinator: Sendable {
    private let taskRepository: any TaskRepository

    public init(taskRepository: any TaskRepository) {
        self.taskRepository = taskRepository
    }

    public func recordProgress(
        taskID: String,
        progress: MobileTaskProgress
    ) async throws -> MobileTaskSnapshot? {
        guard var task = try await continuedProcessingRenderTask(taskID: taskID) else {
            return nil
        }
        task.progress = progress
        try await taskRepository.saveTask(task)
        return task
    }

    public func markExpired(taskID: String) async throws -> MobileTaskSnapshot? {
        guard var task = try await continuedProcessingRenderTask(taskID: taskID) else {
            return nil
        }
        task.state = .needsForegroundToContinue
        task.error = .systemBackgroundLimit
        task.backgroundPolicy = MobileBackgroundPolicy(
            execution: .systemInterrupted,
            resumability: .nonResumable,
            limits: [.systemInterrupted, .foregroundRequired, .notResumable]
        )
        try await taskRepository.saveTask(task)
        return task
    }

    private func continuedProcessingRenderTask(taskID: String) async throws -> MobileTaskSnapshot? {
        guard let task = try await taskRepository.loadTasks().first(where: { $0.id == taskID }) else {
            return nil
        }
        guard task.state == .exporting,
              task.progress.phase == .exporting,
              task.backgroundPolicy.execution == .continuedProcessing else {
            return nil
        }
        return task
    }
}
