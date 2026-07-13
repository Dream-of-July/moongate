import XCTest
@testable import MoongateCore

final class LibraryProjectionTests: XCTestCase {
    func testQueuedDraftIsEditableButCancellingIsRunning() {
        XCTAssertTrue(LibraryItemState.queued.isActive)
        XCTAssertTrue(LibraryItemState.queued.isQueued)
        XCTAssertFalse(LibraryItemState.queued.isRunning)

        XCTAssertTrue(LibraryItemState.cancelling.isActive)
        XCTAssertFalse(LibraryItemState.cancelling.isQueued)
        XCTAssertTrue(LibraryItemState.cancelling.isRunning)
        XCTAssertFalse(LibraryItemState.cancelling.needsAttention)
    }

    func testSortsPinnedThenActiveThenRecentlyUpdated() {
        let pinned = makeItem(title: "Pinned", state: .completed, pinned: true, timestamp: 1)
        let active = makeItem(title: "Active", state: .downloading, timestamp: 2)
        let recent = makeItem(title: "Recent", state: .completed, timestamp: 3)
        let projection = LibraryProjection.items(in: LibraryEnvelope(items: [recent, active, pinned]))

        XCTAssertEqual(projection.map(\.item.title), ["Pinned", "Active", "Recent"])
    }

    func testFilterAndSearchUseLiveProcessingOverlayWithoutDuplicatingItems() {
        let item = makeItem(title: "Mate 80 性能分析", state: .completed, tags: ["科技"], timestamp: 1)
        let overlay = ProcessingSummary(state: .translating, stage: .translate, progress: 0.6)
        let envelope = LibraryEnvelope(items: [item])

        let active = LibraryProjection.items(
            in: envelope,
            filter: .active,
            searchQuery: "mate",
            liveProcessing: [item.id: overlay]
        )
        let tag = LibraryProjection.items(in: envelope, filter: .tag("科技"), searchQuery: "性能")

        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.processing, overlay)
        XCTAssertEqual(tag.map(\.id), [item.id])
    }

    func testLargeLibraryRemainsSearchableAndReturnsOneRecordPerLibraryItem() {
        let items = (0 ..< 1_000).map { index in
            makeItem(
                title: index == 700 ? "Needle Video" : "Video \(index)",
                state: index.isMultiple(of: 2) ? .completed : .queued,
                timestamp: TimeInterval(index)
            )
        }
        let envelope = LibraryEnvelope(items: items)

        let all = LibraryProjection.items(in: envelope)
        let search = LibraryProjection.items(in: envelope, searchQuery: "needle")

        XCTAssertEqual(all.count, 1_000)
        XCTAssertEqual(Set(all.map(\.id)).count, 1_000)
        XCTAssertEqual(search.map(\.item.title), ["Needle Video"])
    }

    func testSidebarCountsUseOneLiveProjectionPassWithoutSorting() {
        let completed = makeItem(title: "Complete", state: .completed, pinned: true, timestamp: 1)
        let recoverable = makeItem(title: "Recover", state: .failed, timestamp: 2)
        let overlay = ProcessingSummary(state: .downloading, stage: .download, progress: 0.4)
        let counts = LibraryProjection.sidebarCounts(
            in: LibraryEnvelope(items: [completed, recoverable]),
            liveProcessing: [completed.id: overlay]
        )

        XCTAssertEqual(counts[.all], 2)
        XCTAssertEqual(counts[.active], 1)
        XCTAssertEqual(counts[.needsAttention], 1)
        XCTAssertEqual(counts[.completed], 0)
        XCTAssertEqual(counts[.pinned], 1)
    }

    func testMembershipSignaturesIgnoreProgressForLargeLibraryWithFourActiveTasks() {
        let items = (0 ..< 1_000).map { index in
            makeItem(
                title: "Video \(index)",
                state: .completed,
                timestamp: TimeInterval(index)
            )
        }
        let envelope = LibraryEnvelope(items: items)
        let activeIDs = items.prefix(4).map(\.id)
        let before = Dictionary(uniqueKeysWithValues: activeIDs.enumerated().map { offset, id in
            (id, ProcessingSummary(state: .downloading, stage: .download, progress: Double(offset) / 10))
        })
        let after = Dictionary(uniqueKeysWithValues: activeIDs.enumerated().map { offset, id in
            (id, ProcessingSummary(state: .downloading, stage: .download, progress: 0.7 + Double(offset) / 100))
        })

        XCTAssertEqual(
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: before),
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: after),
            "纯进度变化不能要求重新筛选、排序整库"
        )
    }

    func testMembershipSignaturesChangeWhenAnOverlayMovesBetweenListCategories() {
        let item = makeItem(title: "Status transition", state: .completed, timestamp: 1)
        let envelope = LibraryEnvelope(items: [item])
        let completed = [item.id: ProcessingSummary(state: .completed, stage: .complete, progress: 1)]
        let downloading = [item.id: ProcessingSummary(state: .downloading, stage: .download, progress: 0.1)]
        let failed = [item.id: ProcessingSummary(state: .failed, stage: .recovery, progress: 0.1)]

        XCTAssertNotEqual(
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: completed),
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: downloading),
            "完成态进入下载态时，进行中筛选和排序位置必须更新"
        )
        XCTAssertNotEqual(
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: downloading),
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: failed),
            "下载失败进入需处理时，侧栏计数和筛选必须更新"
        )
    }

    func testMembershipSignaturesIgnoreStageOnlyChangeWithinActiveWork() {
        let item = makeItem(title: "Active stage", state: .downloading, timestamp: 1)
        let envelope = LibraryEnvelope(items: [item])
        let downloading = [item.id: ProcessingSummary(state: .downloading, stage: .download, progress: 0.4)]
        let transcribing = [item.id: ProcessingSummary(state: .transcribing, stage: .transcribe, progress: 0.4)]

        XCTAssertEqual(
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: downloading),
            LibraryProjection.membershipSignatures(in: envelope, liveProcessing: transcribing),
            "阶段文案由行内覆盖层更新；仍在进行中的任务不该为此重排整个列表"
        )
    }

    private func makeItem(
        title: String,
        state: LibraryItemState,
        pinned: Bool = false,
        tags: [String] = [],
        timestamp: TimeInterval
    ) -> MoongateCore.LibraryItem {
        let date = Date(timeIntervalSince1970: timestamp)
        let processing = ProcessingSummary(
            state: state,
            stage: state == .completed ? .complete : .download,
            progress: state == .completed ? 1 : 0.5,
            updatedAt: date
        )
        return LibraryItem(
            title: title,
            tags: tags,
            isPinned: pinned,
            versions: [LibraryVersion(number: 1, processing: processing, createdAt: date)],
            createdAt: date,
            updatedAt: date
        )
    }
}
