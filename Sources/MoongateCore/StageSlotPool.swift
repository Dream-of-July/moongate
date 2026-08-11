import Foundation

/// 阶段槽位池：限制同一阶段（下载 / 压制 / 翻译）的并发任务数。
/// 全部在 MainActor 上运转，无锁；排队者被唤醒后重新竞争（队列规模小，开销可忽略）。
///
/// 从 App target（QueueManager.swift）下沉到 MoongateCore，使其可被 `@testable import` 做行为单测——
/// SwiftPM 无法 @testable import 可执行 target，之前该并发原语只有源码扫描测试。纯迁移，逻辑不变。
@MainActor
public final class StageSlotPool {
    private let capacity: () -> Int
    private var inUse = 0
    private var parked: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []

    public init(capacity: @escaping () -> Int) {
        self.capacity = capacity
    }

    public var hasFreeSlot: Bool { inUse < max(1, capacity()) }

    /// 等待并占用一个槽位。control 取消时抛 cancelled。
    /// respectPause=true 时，暂停中的任务不抢槽（等恢复后再竞争）；
    /// 恢复重排队的路径传 false（item 已恢复但 token 仍处暂停态，等槽到手才 SIGCONT）。
    public func acquire(id: UUID, control: TaskControlToken, respectPause: Bool = true) async throws {
        while true {
            if Task.isCancelled || control.isCancelled { throw MoongateError.cancelled }
            if respectPause, control.isPaused {
                try await control.gate()
                continue
            }
            if hasFreeSlot {
                inUse += 1
                return
            }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                parked.append((id, c))
            }
        }
    }

    /// 释放一个槽位并唤醒全部排队者重新竞争。
    public func release() {
        inUse = max(0, inUse - 1)
        wakeAll()
    }

    /// 容量调大（设置变更）后让排队者重新竞争。
    public func wakeAll() {
        let waiting = parked
        parked.removeAll()
        for waiter in waiting { waiter.continuation.resume() }
    }

    /// 取消某项时把它从排队里唤出（acquire 循环会自行检查取消并抛出）。
    public func wake(id: UUID) {
        guard let index = parked.firstIndex(where: { $0.id == id }) else { return }
        let continuation = parked[index].continuation
        parked.remove(at: index)
        continuation.resume()
    }
}
