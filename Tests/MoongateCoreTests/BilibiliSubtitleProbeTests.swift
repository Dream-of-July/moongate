import XCTest
@testable import MoongateCore

/// 验证 Bilibili 字幕探针：BVID 提取、view 接口响应解析（含 ai_type 区分人工/AI 字幕）。
final class BilibiliSubtitleProbeTests: XCTestCase {

    // MARK: BVID 提取

    func testExtractsBVIDFromStandardURL() {
        XCTAssertEqual(
            BilibiliSubtitleProbe.bvid(from: "https://www.bilibili.com/video/BV1F7T46wEyT/?spm_id_from=333"),
            "BV1F7T46wEyT"
        )
        XCTAssertEqual(
            BilibiliSubtitleProbe.bvid(from: "https://bilibili.com/video/BV1F7T46wEyT"),
            "BV1F7T46wEyT"
        )
        XCTAssertEqual(
            BilibiliSubtitleProbe.bvid(from: "https://m.bilibili.com/video/BV1F7T46wEyT"),
            "BV1F7T46wEyT"
        )
    }

    func testRejectsNonBilibiliOrShortLinks() {
        XCTAssertNil(BilibiliSubtitleProbe.bvid(from: "https://www.youtube.com/watch?v=abc"))
        // b23.tv 短链需重定向，不在零成本探针范围内。
        XCTAssertNil(BilibiliSubtitleProbe.bvid(from: "https://b23.tv/abcdef"))
        XCTAssertNil(BilibiliSubtitleProbe.bvid(from: "not a url"))
    }

    // MARK: 响应解析

    private func viewJSON(subtitleList: String) -> Data {
        """
        {"code":0,"message":"OK","data":{"bvid":"BV1F7T46wEyT","subtitle":{"allow_submit":false,"list":\(subtitleList)}}}
        """.data(using: .utf8)!
    }

    func testParsesHumanChineseSubtitle() {
        // 复刻真实 view 响应：人工中文字幕（ai_type:0），subtitle_url 未登录时为空。
        let data = viewJSON(subtitleList: """
        [{"id":2054640398931922176,"lan":"zh","lan_doc":"中文","subtitle_url":"","type":0,"ai_type":0,"ai_status":0}]
        """)
        let result = BilibiliSubtitleProbe.parse(data: data)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.languageCodes, ["zh-Hans"])
        XCTAssertEqual(result?.hasHumanSubtitle, true)
    }

    func testParsesAIChineseSubtitle() {
        let data = viewJSON(subtitleList: """
        [{"lan":"ai-zh","lan_doc":"中文（自动生成）","subtitle_url":"","ai_type":1,"ai_status":2}]
        """)
        let result = BilibiliSubtitleProbe.parse(data: data)
        XCTAssertNotNil(result)
        // ai-zh 规范化到 zh-Hans，且标记为非人工字幕。
        XCTAssertEqual(result?.languageCodes, ["zh-Hans"])
        XCTAssertEqual(result?.hasHumanSubtitle, false)
    }

    func testEmptySubtitleListReturnsNil() {
        let result = BilibiliSubtitleProbe.parse(data: viewJSON(subtitleList: "[]"))
        XCTAssertNil(result)
    }

    func testNonZeroCodeReturnsNil() {
        let data = """
        {"code":-404,"message":"啥都木有","data":null}
        """.data(using: .utf8)!
        XCTAssertNil(BilibiliSubtitleProbe.parse(data: data))
    }

    func testDeduplicatesAndKeepsOrder() {
        let data = viewJSON(subtitleList: """
        [{"lan":"zh","ai_type":0},{"lan":"ai-zh","ai_type":1},{"lan":"en","ai_type":0}]
        """)
        let result = BilibiliSubtitleProbe.parse(data: data)
        // zh 与 ai-zh 都规范化为 zh-Hans，去重后保留首次出现顺序。
        XCTAssertEqual(result?.languageCodes, ["zh-Hans", "en"])
        XCTAssertEqual(result?.hasHumanSubtitle, true)
    }
}
