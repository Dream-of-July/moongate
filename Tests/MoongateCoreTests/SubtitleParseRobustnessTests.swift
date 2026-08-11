import XCTest
@testable import MoongateCore

/// `parseSRT` / `parseVTT` 是所有下游字幕分析（质量门 / 时序健康 / 置信度 / 翻译）的解析基座，
/// 其鲁棒性契约（容忍 BOM、CRLF、序号缺失按序补号、丢弃空文本条与无时间行的孤块）此前只写在
/// 源码注释里、无直接测试。这些属性易被回归且影响面大，补齐守护。
final class SubtitleParseRobustnessTests: XCTestCase {

    // MARK: - SRT

    func testParseSRTStripsLeadingBOM() {
        // BOM 直接贴在显式序号 "7" 前。若不剥离 BOM，Int("\u{FEFF}7") 解析失败 → 该条会被按序补号成 1；
        // 只有正确剥离 BOM 才会保留显式序号 7。用非-1 序号让「是否剥离 BOM」变得可观测（否则两条路径同解）。
        let srt = "\u{FEFF}7\n00:00:01,000 --> 00:00:02,000\nHello\n"
        let cues = parseSRT(srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.text, "Hello")
        XCTAssertEqual(cues.first?.index, 7,
                       "BOM 必须被剥离，否则显式序号 7 会解析失败并被误补成 1。")
    }

    func testParseSRTNormalizesCRLFAndBareCR() {
        let crlf = "1\r\n00:00:01,000 --> 00:00:02,000\r\nLine A\r\nLine B\r\n"
        let cues = parseSRT(crlf)
        XCTAssertEqual(cues.count, 1)
        // 多行文本用 \n 连接，且不留下 \r 残渣。
        XCTAssertEqual(cues.first?.text, "Line A\nLine B")
        XCTAssertFalse(cues.first?.text.contains("\r") ?? true)
    }

    func testParseSRTRenumbersWhenIndexLinesMissing() {
        // 完全没有序号行：应按出现顺序补 1、2。
        let noIndex = """
        00:00:01,000 --> 00:00:02,000
        First

        00:00:03,000 --> 00:00:04,000
        Second
        """
        let cues = parseSRT(noIndex)
        XCTAssertEqual(cues.map(\.index), [1, 2])
        XCTAssertEqual(cues.map(\.text), ["First", "Second"])
    }

    func testParseSRTHonorsExplicitIndicesEvenWhenNonSequential() {
        let srt = """
        5
        00:00:01,000 --> 00:00:02,000
        Fifth

        9
        00:00:03,000 --> 00:00:04,000
        Ninth
        """
        let cues = parseSRT(srt)
        XCTAssertEqual(cues.map(\.index), [5, 9])
    }

    func testParseSRTDropsEmptyTextCues() {
        // 中间一条只有时间行、无正文：应被丢弃，不产出空 cue。
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        Real

        2
        00:00:03,000 --> 00:00:04,000

        3
        00:00:05,000 --> 00:00:06,000
        AlsoReal
        """
        let cues = parseSRT(srt)
        XCTAssertEqual(cues.map(\.text), ["Real", "AlsoReal"])
    }

    func testParseSRTAcceptsDottedMillisecondSeparator() {
        // 点号毫秒分隔（部分工具输出 . 而非 ,）也应识别。
        let srt = "1\n00:00:01.000 --> 00:00:02.000\nDotted\n"
        XCTAssertEqual(parseSRT(srt).first?.text, "Dotted")
    }

    func testParseSRTReturnsEmptyForGarbageWithoutTimeLines() {
        XCTAssertTrue(parseSRT("not a subtitle at all\njust text").isEmpty)
        XCTAssertTrue(parseSRT("").isEmpty)
    }

    // MARK: - VTT

    func testParseVTTStripsBOMAndParsesCue() {
        let vtt = "\u{FEFF}WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello VTT\n"
        let cues = parseVTT(vtt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.text, "Hello VTT")
    }

    func testParseVTTNormalizesCRLF() {
        let vtt = "WEBVTT\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nWith CRLF\r\n"
        let cues = parseVTT(vtt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertFalse(cues.first?.text.contains("\r") ?? true)
    }
}
