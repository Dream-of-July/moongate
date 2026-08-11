@testable import MoongateCore
import XCTest

final class SubtitleTimingPlannerTests: XCTestCase {
    func testSpeechAlignedVisibleSecondsKeepsShortFeedbackBrief() {
        XCTAssertEqual(SubtitleTimingPlanner.speechAlignedVisibleSeconds("Copy.", endsSentence: true), 2.0)
        XCTAssertEqual(SubtitleTimingPlanner.speechAlignedVisibleSeconds("What heat?", endsSentence: true), 2.0)
    }

    func testSpeechAlignedVisibleSecondsExtendsShortEmphaticLines() {
        XCTAssertEqual(SubtitleTimingPlanner.speechAlignedVisibleSeconds("10,000 hours!", endsSentence: true), 2.45)
        XCTAssertEqual(SubtitleTimingPlanner.speechAlignedVisibleSeconds("No!!", endsSentence: true), 2.45)
        XCTAssertEqual(SubtitleTimingPlanner.speechAlignedVisibleSeconds("Ever again.", endsSentence: true), 2.45)
        XCTAssertEqual(SubtitleTimingPlanner.speechAlignedVisibleSeconds("like around week eight,", endsSentence: false), 1.92)
    }

    func testSpeechAlignedVisibleSecondsScalesLongSpeechWithoutDragging() {
        let duration = SubtitleTimingPlanner.speechAlignedVisibleSeconds(
            "This is a longer spoken sentence that should stay readable without lingering too long.",
            endsSentence: true
        )

        XCTAssertGreaterThan(duration, 4.0)
        XCTAssertLessThanOrEqual(duration, 9.0)
    }

    func testWeakSemanticBoundaryDetectsBadEnglishSplits() {
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "the", rightToken: "ship"))
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "moon", rightToken: "and"))
        XCTAssertFalse(SubtitleTimingPlanner.isWeakBoundary(leftToken: "moon.", rightToken: "Next"))
    }

    func testWeakSemanticBoundaryDetectsRomanceLanguageSplits() {
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "tono", rightToken: "de"))
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "de", rightToken: "ponerte"))
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "des", rightToken: "chaussures"))
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "di", rightToken: "fronte"))
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "muchas", rightToken: "veces"))
        XCTAssertTrue(SubtitleTimingPlanner.isWeakBoundary(leftToken: "no", rightToken: "hacen"))
    }

    func testTokenizersHandleLatinAndCJKText() {
        XCTAssertEqual(SubtitleTimingPlanner.wordTokens("Hello, Starship!"), ["hello", "starship"])
        XCTAssertEqual(SubtitleTimingPlanner.speechTokens("Copy. 10 engines?"), ["copy", "10", "engines"])
        XCTAssertEqual(
            SubtitleTimingPlanner.speechTokens("Sì, può iniziare questa settimana?"),
            ["sì", "può", "iniziare", "questa", "settimana"]
        )
        XCTAssertEqual(SubtitleTimingPlanner.timingTokens("3 € 4,99€."), ["3", "€", "4", "99", "€"])
        XCTAssertEqual(SubtitleTimingPlanner.speechTokens("今天我们继续"), [])
        XCTAssertEqual(SubtitleTimingPlanner.speechTokens("내가 서 있는 곳"), [])
        XCTAssertEqual(SubtitleTimingPlanner.visibleCharacters("你 好 world"), 7)
    }

    // MARK: - shouldAlignToSpeechWindow 判定边界（决定是否按语音窗对齐时序）

    func testShouldAlignReturnsFalseWhenSourceAnchorsAvailable() {
        // 有源锚点时永不走语音对齐（早退守卫，最高优先级）。
        XCTAssertFalse(SubtitleTimingPlanner.shouldAlignToSpeechWindow(
            text: "hello there", originalDuration: 30,
            speechAlignTimings: true, canUseSourceAnchors: true, endsSentence: false),
            "有源锚点时应直接返回 false，不做语音对齐")
    }

    func testShouldAlignShortLatinPhraseAlignsRegardlessOfDuration() {
        // 拉丁 <= 3 词的短语：无条件对齐（即便 speechAlignTimings=false、时长短）。
        XCTAssertTrue(SubtitleTimingPlanner.shouldAlignToSpeechWindow(
            text: "copy that now", originalDuration: 1.0,
            speechAlignTimings: false, canUseSourceAnchors: false, endsSentence: false),
            "拉丁 3 词短语应对齐")
    }

    func testShouldAlignLongLatinNeedsSpeechAlignAndLongDuration() {
        // 拉丁 > 4 词、非 4 词特例：仅当 speechAlignTimings 且 时长 > normalReadableCueSeconds(9s) 才对齐。
        let text = "this is a much longer spoken sentence with many words"
        // speechAlignTimings=false → 不对齐（不满足最后一条 return 的前置）。
        XCTAssertFalse(SubtitleTimingPlanner.shouldAlignToSpeechWindow(
            text: text, originalDuration: 20,
            speechAlignTimings: false, canUseSourceAnchors: false, endsSentence: true),
            "长拉丁句在 speechAlignTimings=false 时不应对齐")
        // speechAlignTimings=true 且时长 > 9s → 对齐。
        XCTAssertTrue(SubtitleTimingPlanner.shouldAlignToSpeechWindow(
            text: text, originalDuration: 20,
            speechAlignTimings: true, canUseSourceAnchors: false, endsSentence: true),
            "长拉丁句在 speechAlignTimings 且时长>9s 时应对齐")
        // speechAlignTimings=true 但时长 <= 9s → 不对齐（时长边界）。
        XCTAssertFalse(SubtitleTimingPlanner.shouldAlignToSpeechWindow(
            text: text, originalDuration: 5,
            speechAlignTimings: true, canUseSourceAnchors: false, endsSentence: true),
            "长拉丁句时长未超 normalReadableCueSeconds(9s) 不应对齐")
    }

    func testShouldAlignCJKRequiresShortVisibleCountAndLongDuration() {
        // CJK：visibleCount <= 12 且（speechAlignTimings 或时长>9s）且时长超语音可读秒+0.5 才对齐。
        // 短 CJK（6 字）+ 长时长 + speechAlignTimings → 对齐。
        XCTAssertTrue(SubtitleTimingPlanner.shouldAlignToSpeechWindow(
            text: "今天我们继续", originalDuration: 30,
            speechAlignTimings: true, canUseSourceAnchors: false, endsSentence: false),
            "短 CJK + 长时长应对齐")
        // 长 CJK（>12 可见字符）→ 不对齐（visibleCount<=12 边界外）。
        XCTAssertFalse(SubtitleTimingPlanner.shouldAlignToSpeechWindow(
            text: "今天我们继续深入讨论这个复杂的话题内容", originalDuration: 30,
            speechAlignTimings: true, canUseSourceAnchors: false, endsSentence: false),
            "CJK 可见字符 >12 不应对齐")
    }

    // MARK: - characterSplitPartCount 边界（换行分段数的钳制）

    func testCharacterSplitPartCountClampsAndRespectsCJKMinWidth() {
        // 空文本 → 1。
        XCTAssertEqual(SubtitleTimingPlanner.characterSplitPartCount(text: "", requestedParts: 5), 1)
        // requestedParts < 1 → 至少 1。
        XCTAssertEqual(SubtitleTimingPlanner.characterSplitPartCount(text: "hello world", requestedParts: 0), 1)
        // 拉丁 minVisibleChars=1：11 可见字符（"helloworld"=10 实际）可支持较多份，requested 3 不被砍。
        XCTAssertEqual(SubtitleTimingPlanner.characterSplitPartCount(text: "hello world", requestedParts: 3), 3)
        // 拉丁超额：可见字符数即上限。"abc"(3 可见) 请求 10 → 砍到 3。
        XCTAssertEqual(SubtitleTimingPlanner.characterSplitPartCount(text: "abc", requestedParts: 10), 3)
        // CJK minVisibleChars=4：8 个 CJK 字符 → maxParts = 8/4 = 2，请求 5 → 砍到 2。
        XCTAssertEqual(SubtitleTimingPlanner.characterSplitPartCount(text: "今天我们继续讨论", requestedParts: 5), 2)
        // CJK 少于 minWidth：3 个 CJK 字符 → maxReadableParts = max(1, 3/4=0) = 1。
        XCTAssertEqual(SubtitleTimingPlanner.characterSplitPartCount(text: "我们继", requestedParts: 4), 1)
    }

    // MARK: - shouldBorrowBoundaryForHandoff 边界（冒号/分号交接借帧）

    func testShouldBorrowBoundaryForHandoff() {
        // 前句以冒号/分号结尾（半角+全角）且后句非空 → 借帧。
        XCTAssertTrue(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "他说：", nextText: "明天出发"))
        XCTAssertTrue(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "Note:", nextText: "the plan"))
        XCTAssertTrue(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "list;", nextText: "next"))
        XCTAssertTrue(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "清单；", nextText: "下一项"))
        // 冒号后跟允许的收尾符（引号）仍算冒号结尾（lastMeaningfulCharacter 跳过引号）。
        XCTAssertTrue(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "he said:\"", nextText: "go"))
        // 后句为空 / 纯空白 → 不借帧。
        XCTAssertFalse(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "Note:", nextText: ""))
        XCTAssertFalse(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "Note:", nextText: "   "))
        // 前句非冒号/分号结尾（句号/普通词）→ 不借帧。
        XCTAssertFalse(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "The end.", nextText: "next"))
        XCTAssertFalse(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "hello", nextText: "world"))
        // 前句无有意义字符（空/纯符号）→ 不借帧。
        XCTAssertFalse(SubtitleTimingPlanner.shouldBorrowBoundaryForHandoff(previousText: "  ", nextText: "next"))
    }
}
