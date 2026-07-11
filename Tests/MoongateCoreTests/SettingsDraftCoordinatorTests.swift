import XCTest
@testable import Moongate

@MainActor
final class SettingsDraftCoordinatorTests: XCTestCase {
    func testOrdinaryChangesDebounceToTheLatestPersistence() {
        let scheduler = ManualSettingsDraftScheduler()
        let coordinator = SettingsDraftCoordinator(scheduler: scheduler, delay: 0.4)
        var persisted: [String] = []

        coordinator.record(.ordinary) {
            persisted.append("first")
            return true
        }
        coordinator.record(.ordinary) {
            persisted.append("latest")
            return true
        }

        XCTAssertEqual(scheduler.scheduledCount, 2)
        scheduler.runAll()
        XCTAssertEqual(persisted, ["latest"])
        XCTAssertFalse(coordinator.requiresExplicitCommit)
    }

    func testSensitiveChangeCannotBePersistedByFollowingOrdinaryChange() {
        let scheduler = ManualSettingsDraftScheduler()
        let coordinator = SettingsDraftCoordinator(scheduler: scheduler, delay: 0.4)
        var persisted: [String] = []

        coordinator.record(.ordinary) {
            persisted.append("ordinary before sensitive")
            return true
        }
        coordinator.record(.sensitive) {
            persisted.append("sensitive should not autosave")
            return true
        }
        coordinator.record(.ordinary) {
            persisted.append("ordinary after sensitive")
            return true
        }

        scheduler.runAll()
        XCTAssertTrue(persisted.isEmpty)
        XCTAssertTrue(coordinator.requiresExplicitCommit)

        XCTAssertFalse(coordinator.commitImmediately {
            persisted.append("failed explicit save")
            return false
        })
        XCTAssertTrue(coordinator.requiresExplicitCommit)

        XCTAssertTrue(coordinator.commitImmediately {
            persisted.append("successful explicit save")
            return true
        })
        XCTAssertEqual(persisted, ["failed explicit save", "successful explicit save"])
        XCTAssertFalse(coordinator.requiresExplicitCommit)
    }
}

@MainActor
private final class ManualSettingsDraftScheduler: SettingsDraftScheduling {
    private final class Work: SettingsDraftScheduledWork {
        var isCancelled = false
        let operation: @MainActor () -> Void

        init(operation: @escaping @MainActor () -> Void) {
            self.operation = operation
        }

        func cancel() {
            isCancelled = true
        }
    }

    private var works: [Work] = []

    var scheduledCount: Int { works.count }

    @discardableResult
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> any SettingsDraftScheduledWork {
        let work = Work(operation: operation)
        works.append(work)
        return work
    }

    func runAll() {
        let pending = works
        works.removeAll()
        for work in pending where !work.isCancelled {
            work.operation()
        }
    }
}
