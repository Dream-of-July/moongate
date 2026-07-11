import Foundation

/// Settings persistence is deliberately scheduled behind an abstraction so UI typing can be
/// tested without waiting on wall-clock time.
@MainActor
protocol SettingsDraftScheduledWork: AnyObject {
    func cancel()
}

@MainActor
protocol SettingsDraftScheduling: AnyObject {
    @discardableResult
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> any SettingsDraftScheduledWork
}

@MainActor
final class MainQueueSettingsDraftScheduler: SettingsDraftScheduling {
    private final class Work: SettingsDraftScheduledWork {
        var task: Task<Void, Never>?

        func cancel() {
            task?.cancel()
            task = nil
        }
    }

    @discardableResult
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> any SettingsDraftScheduledWork {
        let work = Work()
        let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
        work.task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            operation()
        }
        return work
    }
}

enum SettingsDraftChange {
    case ordinary
    case sensitive
}

/// Coordinates persistence for the settings editor.
///
/// Ordinary changes are coalesced behind a short debounce. Sensitive edits never flow through
/// that path: once one occurs, a caller must explicitly commit a current full draft successfully
/// before ordinary auto-persistence can resume.
@MainActor
final class SettingsDraftCoordinator {
    typealias Persistence = @MainActor () -> Bool

    private let scheduler: any SettingsDraftScheduling
    private let delay: TimeInterval
    private var scheduledWork: (any SettingsDraftScheduledWork)?
    private var generation: UInt64 = 0

    private(set) var requiresExplicitCommit = false

    init(
        scheduler: (any SettingsDraftScheduling)? = nil,
        delay: TimeInterval = 0.4
    ) {
        self.scheduler = scheduler ?? MainQueueSettingsDraftScheduler()
        self.delay = delay
    }

    func record(_ change: SettingsDraftChange, persist: @escaping Persistence) {
        switch change {
        case .ordinary:
            guard !requiresExplicitCommit else { return }
            scheduleOrdinaryPersistence(persist)
        case .sensitive:
            requiresExplicitCommit = true
            cancelPendingPersistence()
        }
    }

    @discardableResult
    func commitImmediately(_ persist: Persistence) -> Bool {
        cancelPendingPersistence()
        let didPersist = persist()
        if didPersist {
            requiresExplicitCommit = false
        }
        return didPersist
    }

    func cancelPendingPersistence() {
        generation &+= 1
        scheduledWork?.cancel()
        scheduledWork = nil
    }

    private func scheduleOrdinaryPersistence(_ persist: @escaping Persistence) {
        cancelPendingPersistence()
        let scheduledGeneration = generation
        scheduledWork = scheduler.schedule(after: delay) { [weak self] in
            guard let self,
                  self.generation == scheduledGeneration,
                  !self.requiresExplicitCommit else { return }
            self.scheduledWork = nil
            _ = persist()
        }
    }
}
