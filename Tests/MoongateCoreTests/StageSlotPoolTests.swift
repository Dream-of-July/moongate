import XCTest
@testable import MoongateCore

/// StageSlotPool 行为单测。此前该并发原语在 App target（不可 @testable import），只有源码扫描测试；
/// 下沉到 MoongateCore 后补上真实行为覆盖：容量占用、超额挂起→release 唤醒、取消抛出、扩容 wakeAll。
@MainActor
final class StageSlotPoolTests: XCTestCase {

    /// 容量内的 acquire 立即成功，不挂起。
    func testAcquireWithinCapacitySucceedsImmediately() async throws {
        let pool = StageSlotPool(capacity: { 2 })
        let c1 = TaskControlToken(), c2 = TaskControlToken()
        try await pool.acquire(id: UUID(), control: c1)
        try await pool.acquire(id: UUID(), control: c2)
        // 两个都拿到了槽（capacity 2），此时无空槽。
        XCTAssertFalse(pool.hasFreeSlot)
    }

    /// 超出容量的 acquire 挂起，直到 release 让出槽位才返回。
    func testAcquireBeyondCapacityBlocksUntilRelease() async throws {
        let pool = StageSlotPool(capacity: { 1 })
        let held = TaskControlToken()
        try await pool.acquire(id: UUID(), control: held)   // 占满唯一槽
        XCTAssertFalse(pool.hasFreeSlot)

        let acquired = expectation(description: "second acquire returns after release")
        let waiter = Task { @MainActor in
            try await pool.acquire(id: UUID(), control: TaskControlToken())
            acquired.fulfill()
        }
        // 给 waiter 机会跑到挂起点；此时不应已完成。
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(waiter.isCancelled, false)

        pool.release()   // 让出槽 → 唤醒 waiter
        await fulfillment(of: [acquired], timeout: 2.0)
        _ = try await waiter.value
    }

    /// 已取消的 control 让 acquire 立即抛 cancelled（即便有空槽也先查取消）。
    func testAcquireWithCancelledControlThrows() async {
        let pool = StageSlotPool(capacity: { 4 })
        let control = TaskControlToken()
        control.cancel()
        do {
            try await pool.acquire(id: UUID(), control: control)
            XCTFail("已取消的 control 应抛出")
        } catch {
            // 期望 MoongateError.cancelled。
            if case MoongateError.cancelled = error {} else {
                XCTFail("应为 MoongateError.cancelled，实际：\(error)")
            }
        }
    }

    /// 挂起中的排队者被 wake(id:) 唤出后，acquire 循环自查取消并抛出（取消某项时的路径）。
    func testWakeCancelledWaiterThrows() async throws {
        let pool = StageSlotPool(capacity: { 1 })
        try await pool.acquire(id: UUID(), control: TaskControlToken())  // 占满

        let waiterID = UUID()
        let waiterControl = TaskControlToken()
        let threw = expectation(description: "woken cancelled waiter throws")
        let waiter = Task { @MainActor in
            do {
                try await pool.acquire(id: waiterID, control: waiterControl)
                XCTFail("被取消唤出后应抛出而非拿到槽")
            } catch { threw.fulfill() }
        }
        try await Task.sleep(nanoseconds: 30_000_000)  // 等它挂起
        waiterControl.cancel()
        pool.wake(id: waiterID)   // 唤出 → acquire 循环查到取消抛出
        await fulfillment(of: [threw], timeout: 2.0)
        _ = await waiter.value
    }

    /// 扩容后 wakeAll 让挂起者重新竞争并拿到新腾出的容量。
    func testWakeAllLetsParkedWaiterAcquireAfterCapacityGrows() async throws {
        var cap = 1
        let pool = StageSlotPool(capacity: { cap })
        try await pool.acquire(id: UUID(), control: TaskControlToken())  // 占满 cap=1

        let acquired = expectation(description: "waiter acquires after capacity grows")
        let waiter = Task { @MainActor in
            try await pool.acquire(id: UUID(), control: TaskControlToken())
            acquired.fulfill()
        }
        try await Task.sleep(nanoseconds: 30_000_000)  // 等它挂起
        cap = 2            // 容量调大
        pool.wakeAll()     // 让排队者重新竞争 → 有空槽，拿到
        await fulfillment(of: [acquired], timeout: 2.0)
        _ = try await waiter.value
    }
}
