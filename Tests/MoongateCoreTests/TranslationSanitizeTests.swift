import XCTest
@testable import MoongateCore

/// 译文清洗：去掉模型自加的行首对话破折号、兜底折叠分隔符（修复烧录字幕出现 "– …" 和 " / " 的脏输出）。
final class TranslationSanitizeTests: XCTestCase {

    // MARK: - 句内即时重复词组折叠(whisper 口吃)

    func testCollapsesImmediatePhraseStutter() {
        // whisper 口吃:连续 3+ 次同一短语 → 折叠为 1 次,保留其后文本。
        XCTAssertEqual(
            ConfiguredTranslator.collapseImmediatePhraseRepeats("I've got to leave I've got to leave I've got to leave Sorry"),
            "I've got to leave Sorry"
        )
    }

    func testCollapseLeavesLegitimateDoubleRepeat() {
        // 仅 2 次重复(可能是强调)不折叠;且短句(<6 token)不动。
        XCTAssertEqual(
            ConfiguredTranslator.collapseImmediatePhraseRepeats("Hello hello"),
            "Hello hello"
        )
        XCTAssertEqual(
            ConfiguredTranslator.collapseImmediatePhraseRepeats("Never gonna give you up never gonna give you up"),
            "Never gonna give you up never gonna give you up"
        )
    }

    func testCollapseLeavesNonRepeatedTextUntouched() {
        let s = "I was wondering if after all these years you would like to meet"
        XCTAssertEqual(ConfiguredTranslator.collapseImmediatePhraseRepeats(s), s)
    }

    func testCollapseSingleWordStutter() {
        XCTAssertEqual(
            ConfiguredTranslator.collapseImmediatePhraseRepeats("you you you you you you I said"),
            "you I said"
        )
    }

    func testStripsLeadingDialogueDash() {
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("– 几乎从来不取决于硬件本身"), "几乎从来不取决于硬件本身")
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("- 你好"), "你好")
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("— 你好"), "你好")
    }

    func testCollapsesResidualSlashSeparator() {
        XCTAssertEqual(
            ConfiguredTranslator.sanitizeTranslation("可你要真想玩 / 《马力欧赛车 世界》"),
            "可你要真想玩，《马力欧赛车 世界》"
        )
    }

    func testHandlesDashAndSlashTogether() {
        XCTAssertEqual(
            ConfiguredTranslator.sanitizeTranslation("– 可你要真想玩 / 《马力欧赛车 世界》"),
            "可你要真想玩，《马力欧赛车 世界》"
        )
    }

    func testLeavesCleanTranslationUntouched() {
        // 句中连字符（如 well-known）不在行首，不应被动到
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("这是 well-known 的事"), "这是 well-known 的事")
    }

    func testRemovesChineseTerminalPeriodButKeepsExpressivePunctuation() {
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("这样你就能坐在沙发上，连电视玩。"), "这样你就能坐在沙发上，连电视玩")
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("真的吗？"), "真的吗？")
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("太好了！"), "太好了！")
        XCTAssertEqual(ConfiguredTranslator.sanitizeTranslation("等等……"), "等等……")
    }

    func testFlattenedNormalizesSubtitleEscapesBeforeTranslation() {
        XCTAssertEqual(
            ConfiguredTranslator.flattened("NVIDIA\\hCEO\\Nnext&nbsp;line\u{00A0}here"),
            "NVIDIA CEO next line here"
        )
    }
}
