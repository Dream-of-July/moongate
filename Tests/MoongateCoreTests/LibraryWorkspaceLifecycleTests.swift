import Foundation
import XCTest
@testable import Moongate

final class LibraryWorkspaceLifecycleTests: XCTestCase {
    func testContinuousProgressDoesNotCancelAnAlreadyScheduledDurableSync() {
        let queueID = UUID()
        let downloading = [queueID: FixtureDurableSignature(state: "downloading", stage: "download")]
        var gate = QueueDurableSynchronizationGate<FixtureDurableSignature>()

        XCTAssertTrue(gate.shouldSchedule(downloading))
        for _ in 0 ..< 240 {
            XCTAssertFalse(
                gate.shouldSchedule(downloading),
                "与进度有关但结构不变的快照不能取消已排队的持久化同步"
            )
        }
        XCTAssertEqual(gate.lastScheduledQueueSignatures, downloading)
    }

    func testStageChangeSchedulesDurableSyncImmediately() {
        let queueID = UUID()
        var gate = QueueDurableSynchronizationGate<FixtureDurableSignature>()
        let downloading = [queueID: FixtureDurableSignature(state: "downloading", stage: "download")]
        let transcribing = [queueID: FixtureDurableSignature(state: "transcribing", stage: "transcribe")]

        XCTAssertTrue(gate.shouldSchedule(downloading))
        XCTAssertFalse(gate.shouldSchedule(downloading))
        XCTAssertTrue(gate.shouldSchedule(transcribing),
                      "阶段变化必须立即替换待同步结构状态，不能等待纯进度安静下来")
        XCTAssertEqual(gate.lastScheduledQueueSignatures, transcribing)
    }

    func testFailedDurableSyncCanBeScheduledAgain() {
        let queueID = UUID()
        let downloading = [queueID: FixtureDurableSignature(state: "downloading", stage: "download")]
        var gate = QueueDurableSynchronizationGate<FixtureDurableSignature>()

        XCTAssertTrue(gate.shouldSchedule(downloading))
        gate.invalidateAfterFailure()
        XCTAssertTrue(gate.shouldSchedule(downloading),
                      "写入失败后，相同的结构状态必须可由下一次队列更新重试")
    }
}

private struct FixtureDurableSignature: Equatable {
    let state: String
    let stage: String
}
