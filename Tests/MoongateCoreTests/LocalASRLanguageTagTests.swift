import XCTest
@testable import MoongateCore

/// 语言标签污染 bug 的回归测试：产物文件名的语言后缀必须反映转写内容的真实语言，
/// 而非可能被 yt-dlp 错报污染的输入标签。覆盖 scriptCorrectedLanguageCode 的核心场景。
final class LocalASRLanguageTagTests: XCTestCase {
    // 一段足够长的纯中文（无假名/谚文），模拟 whisper 正确转写的中文内容。
    private let chineseText = """
    今天我们来聊一聊这个视频的主要内容
    首先要说明的是这个方法非常简单实用
    很多人都在使用它并且效果相当不错
    希望大家能够认真学习并且动手实践
    """

    private let englishText = """
    Today we are going to talk about the main content of this video.
    First of all this method is very simple and practical.
    Many people are using it and the results are quite good.
    """

    // 日文，含明显假名混汉字。
    private let japaneseText = """
    今日はこの動画の内容についてお話しします
    まずこの方法はとても簡単で実用的です
    多くの人が使っていて効果もなかなか良いです
    """

    private let koreanText = """
    오늘은 이 영상의 주요 내용에 대해 이야기하겠습니다
    먼저 이 방법은 매우 간단하고 실용적입니다
    많은 사람들이 사용하고 있으며 효과도 꽤 좋습니다
    """

    /// 核心诊断场景：en 标签 + 中文内容 → 校正为 zh-Hans。
    func testEnglishTagWithChineseContentCorrectsToSimplifiedChinese() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "en", subtitleText: chineseText)
        XCTAssertEqual(result, "zh-Hans")
    }

    /// en 标签 + 纯英文 → 保持 en，不误伤。
    func testEnglishTagWithEnglishContentStaysEnglish() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "en", subtitleText: englishText)
        XCTAssertEqual(result, "en")
    }

    /// ja 标签 + 日文 → 保留 ja。
    func testJapaneseTagWithJapaneseContentStaysJapanese() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "ja", subtitleText: japaneseText)
        XCTAssertEqual(result, "ja")
    }

    /// en 标签 + 日文 → 校正为 ja（假名信号覆盖）。
    func testEnglishTagWithJapaneseContentCorrectsToJapanese() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "en", subtitleText: japaneseText)
        XCTAssertEqual(result, "ja")
    }

    /// zh-Hant 标签 + 中文 → 保留 zh-Hant，不降级成 zh-Hans。
    func testTraditionalChineseTagIsNotDowngraded() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "zh-Hant", subtitleText: chineseText)
        XCTAssertEqual(result, "zh-Hant")
    }

    /// yue（粤语）标签 + 中文 → 保留 yue，不降级。
    func testCantoneseTagIsNotDowngraded() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "yue", subtitleText: chineseText)
        XCTAssertEqual(result, "yue")
    }

    /// en 标签 + 韩文 → 校正为 ko。
    func testEnglishTagWithKoreanContentCorrectsToKorean() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "en", subtitleText: koreanText)
        XCTAssertEqual(result, "ko")
    }

    /// 短文本（< 20 可见字符）→ 保守，原样返回候选。
    func testShortTextIsLeftUnchanged() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "en", subtitleText: "你好世界")
        XCTAssertEqual(result, "en")
    }

    /// auto/空标签 + 中文 → 可被内容覆盖为 zh-Hans。
    func testAutoTagWithChineseContentCorrectsToSimplifiedChinese() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "auto", subtitleText: chineseText)
        XCTAssertEqual(result, "zh-Hans")
    }

    /// 各种 en 写法（en-US）也应被识别为同一族，中文内容仍覆盖。
    func testEnUSTagWithChineseContentCorrectsToSimplifiedChinese() {
        let result = ASRTranscriptMapper.scriptCorrectedLanguageCode(candidate: "en-US", subtitleText: chineseText)
        XCTAssertEqual(result, "zh-Hans")
    }
}
