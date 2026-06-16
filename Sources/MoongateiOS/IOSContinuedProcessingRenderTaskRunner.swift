import Foundation
import MoongateMobileCore

public struct IOSContinuedProcessingRenderTaskRunner: Sendable {
    private let taskRepository: any TaskRepository
    private let renderExporter: any RenderExporter
    private let progressObserver: (@Sendable (MobileTaskProgress) -> Void)?

    public init(
        taskRepository: any TaskRepository,
        renderExporter: any RenderExporter,
        progressObserver: (@Sendable (MobileTaskProgress) -> Void)? = nil
    ) {
        self.taskRepository = taskRepository
        self.renderExporter = renderExporter
        self.progressObserver = progressObserver
    }

    public func run(taskID: String) async throws -> MobileTaskSnapshot? {
        guard let task = try await continuedProcessingRenderTask(taskID: taskID) else {
            return nil
        }
        guard let request = renderRequest(for: task) else {
            return try await markFailed(taskID: task.id)
        }

        do {
            let progressBox = IOSContinuedProcessingRenderProgressBox(task.progress)
            let renderedResult = try await renderExporter.export(request) { progress in
                progressBox.update(progress)
                progressObserver?(progress)
            }
            guard var currentTask = try await currentFinalizableTask(taskID: task.id) else {
                return try await persistedTask(taskID: task.id)
            }
            var artifacts = currentTask.result?.artifacts ?? []
            artifacts.removeAll { existing in
                renderedResult.artifacts.contains { $0.id == existing.id } ||
                    existing.kind == .renderedVideo
            }
            artifacts.append(contentsOf: renderedResult.artifacts)

            currentTask.state = .completed
            currentTask.error = nil
            currentTask.result = MobileTaskResult(
                artifacts: artifacts,
                primaryArtifactID: renderedResult.primaryArtifactID ?? currentTask.result?.primaryArtifactID
            )
            if let byteCount = renderedResult.primaryArtifact?.byteCount {
                currentTask.progress = MobileTaskProgress(
                    phase: .exporting,
                    completedUnitCount: byteCount,
                    totalUnitCount: byteCount
                )
            } else {
                currentTask.progress = progressBox.current()
            }
            try await taskRepository.saveTask(currentTask)
            return currentTask
        } catch {
            return try await markFailed(taskID: task.id)
        }
    }

    private func markFailed(taskID: String) async throws -> MobileTaskSnapshot? {
        guard let currentTask = try await currentFinalizableTask(taskID: taskID) else {
            return try await persistedTask(taskID: taskID)
        }
        var failed = currentTask
        failed.state = .needsForegroundToContinue
        failed.error = .exportFailed
        failed.backgroundPolicy = MobileBackgroundPolicy(
            execution: .systemInterrupted,
            resumability: .nonResumable,
            limits: [.systemInterrupted, .foregroundRequired, .notResumable]
        )
        try await taskRepository.saveTask(failed)
        return failed
    }

    private func persistedTask(taskID: String) async throws -> MobileTaskSnapshot? {
        try await taskRepository.loadTasks().first { $0.id == taskID }
    }

    private func currentFinalizableTask(taskID: String) async throws -> MobileTaskSnapshot? {
        guard let task = try await persistedTask(taskID: taskID) else {
            return nil
        }
        guard task.state == .exporting,
              task.progress.phase == .exporting,
              task.backgroundPolicy.execution == .continuedProcessing else {
            return nil
        }
        return task
    }

    private func renderRequest(for task: MobileTaskSnapshot) -> MobileRenderRequest? {
        guard task.exportProfile.subtitleMode == .burnedInSubtitle else {
            return nil
        }
        let artifacts = task.result?.artifacts ?? []
        guard let sourceMedia = artifacts.first(where: { $0.kind == .originalMedia }) else {
            return nil
        }
        let subtitles = artifacts.filter { $0.kind == .translatedSubtitleFile }
        guard !subtitles.isEmpty else {
            return nil
        }
        return MobileRenderRequest(
            sourceMedia: sourceMedia,
            subtitles: subtitles,
            exportProfile: task.exportProfile
        )
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

private final class IOSContinuedProcessingRenderProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: MobileTaskProgress

    init(_ progress: MobileTaskProgress) {
        self.progress = progress
    }

    func update(_ progress: MobileTaskProgress) {
        lock.lock()
        self.progress = progress
        lock.unlock()
    }

    func current() -> MobileTaskProgress {
        lock.lock()
        let progress = self.progress
        lock.unlock()
        return progress
    }
}
