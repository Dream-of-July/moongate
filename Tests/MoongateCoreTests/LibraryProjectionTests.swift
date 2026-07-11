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
