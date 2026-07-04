import XCTest
@testable import MoongateCore

final class SubtitleTimingHealthTests: XCTestCase {
    func testLooksUnreliableThreshold() {
        // >= 20% flash cues with enough cues -> unreliable.
        XCTAssertTrue(SubtitleTimingHealth.Assessment(cueCount: 10, flashCueCount: 3).looksUnreliable)
        // < 20% flash -> reliable.
        XCTAssertFalse(SubtitleTimingHealth.Assessment(cueCount: 10, flashCueCount: 1).looksUnreliable)
        // Too few cues to judge.
        XCTAssertFalse(SubtitleTimingHealth.Assessment(cueCount: 5, flashCueCount: 5).looksUnreliable)
    }

    func testWellTimedSubtitleLooksReliable() {
        // Normal 2s cues must never be flagged (no false positives on good subtitles).
        var srt = ""
        for i in 1...12 {
            let start = String(format: "00:00:%02d,000", i * 3)
            let end = String(format: "00:00:%02d,000", i * 3 + 2)
            srt += "\(i)\n\(start) --> \(end)\nThis is line number \(i).\n\n"
        }
        XCTAssertFalse(SubtitleTimingHealth.assess(rawSubtitle: srt, isVTT: false).looksUnreliable)
    }

    // MARK: - 阈值边界（防 >= vs > / minimumCueCount 的 off-by-one 静默回归）

    func testFlashRatioExactlyAtThresholdIsUnreliable() {
        // flashRatio == 0.20 恰在阈值：looksUnreliable 用 >=，边界必须判为不可靠。
        // 2/10 = 0.20。若有人误改成 > 0.20，此断言会失败。
        XCTAssertEqual(SubtitleTimingHealth.flashRatioThreshold, 0.20, accuracy: 1e-9)
        XCTAssertTrue(SubtitleTimingHealth.Assessment(cueCount: 10, flashCueCount: 2).looksUnreliable,
                      "恰好 20% flash（阈值 >=）应判为不可靠")
    }

    func testFlashRatioJustBelowThresholdIsReliable() {
        // 3/16 = 0.1875 < 0.20：应判为可靠（且 cueCount 16 >= min 8，排除是被 min 挡住的可能）。
        XCTAssertFalse(SubtitleTimingHealth.Assessment(cueCount: 16, flashCueCount: 3).looksUnreliable,
                      "略低于 20%（18.75%）应判为可靠")
    }

    func testMinimumCueCountBoundary() {
        // minimumCueCount=8：7 条即便 100% flash 也不足以判定（样本太小），8 条达阈值才判。
        XCTAssertEqual(SubtitleTimingHealth.minimumCueCount, 8)
        XCTAssertFalse(SubtitleTimingHealth.Assessment(cueCount: 7, flashCueCount: 7).looksUnreliable,
                      "低于 minimumCueCount（7<8）不足以判定，即便全是 flash")
        // 恰好 8 条、含 20% flash（8*0.2=1.6→需 2 条达 0.25）：2/8=0.25>=0.20 且 8>=8 → 不可靠。
        XCTAssertTrue(SubtitleTimingHealth.Assessment(cueCount: 8, flashCueCount: 2).looksUnreliable,
                      "达到 minimumCueCount 且超阈值应判为不可靠")
    }
}
