import XCTest
@testable import MoongateCore

/// 候选按子合集分组：`CandidateGroup.groupedCandidates` 的保序分组纯函数契约。
final class CandidateGroupingTests: XCTestCase {

    // MARK: - fixture

    private func candidate(_ title: String, subcollectionTitle: String? = nil) -> VideoCandidate {
        VideoCandidate(
            url: "https://www.bilibili.com/video/\(title)",
            kind: .supported,
            title: title,
            subcollectionTitle: subcollectionTitle
        )
    }

    // MARK: - 分组契约

    func testGroupedCandidatesPreservesOrder() {
        let candidates = [
            candidate("国内a", subcollectionTitle: "国内"),
            candidate("国内b", subcollectionTitle: "国内"),
            candidate("国外c", subcollectionTitle: "国外"),
            candidate("无分组d", subcollectionTitle: nil),
        ]
        let groups = CandidateGroup.groupedCandidates(candidates)

        // 3 组：国内（2 个）、国外（1 个）、nil（1 个，最后）。
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.title), ["国内", "国外", nil])
        XCTAssertEqual(groups[0].candidates.map(\.title), ["国内a", "国内b"])
        XCTAssertEqual(groups[1].candidates.map(\.title), ["国外c"])
        XCTAssertEqual(groups[2].candidates.map(\.title), ["无分组d"])
    }

    func testGroupedCandidatesEmptyReturnsEmpty() {
        XCTAssertEqual(CandidateGroup.groupedCandidates([]), [])
    }

    func testGroupedCandidatesAllNilReturnsSingleGroup() {
        let candidates = [
            candidate("a"),
            candidate("b"),
        ]
        let groups = CandidateGroup.groupedCandidates(candidates)

        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].title)
        XCTAssertEqual(groups[0].candidates.map(\.title), ["a", "b"])
    }

    func testGroupedCandidatesSingleSubcollection() {
        let candidates = [
            candidate("a", subcollectionTitle: "国内"),
            candidate("b", subcollectionTitle: "国内"),
        ]
        let groups = CandidateGroup.groupedCandidates(candidates)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "国内")
        XCTAssertEqual(groups[0].candidates.map(\.title), ["a", "b"])
    }
}
