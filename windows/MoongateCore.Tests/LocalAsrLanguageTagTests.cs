using Moongate.Core;

namespace MoongateCore.Tests;

/// <summary>
/// 语言标签污染 bug 的回归测试：产物文件名的语言后缀必须反映转写内容的真实语言，
/// 而非可能被 yt-dlp 错报污染的输入标签。覆盖 ScriptCorrectedLanguageCode 的核心场景，
/// 与 macOS 端 LocalASRLanguageTagTests 一致镜像。
/// </summary>
public class LocalAsrLanguageTagTests
{
    // 一段足够长的纯中文（无假名/谚文），模拟 whisper 正确转写的中文内容。
    private const string ChineseText = """
        今天我们来聊一聊这个视频的主要内容
        首先要说明的是这个方法非常简单实用
        很多人都在使用它并且效果相当不错
        希望大家能够认真学习并且动手实践
        """;

    private const string EnglishText = """
        Today we are going to talk about the main content of this video.
        First of all this method is very simple and practical.
        Many people are using it and the results are quite good.
        """;

    // 日文，含明显假名混汉字。
    private const string JapaneseText = """
        今日はこの動画の内容についてお話しします
        まずこの方法はとても簡単で実用的です
        多くの人が使っていて効果もなかなか良いです
        """;

    private const string KoreanText = """
        오늘은 이 영상의 주요 내용에 대해 이야기하겠습니다
        먼저 이 방법은 매우 간단하고 실용적입니다
        많은 사람들이 사용하고 있으며 효과도 꽤 좋습니다
        """;

    /// <summary>核心诊断场景：en 标签 + 中文内容 → 校正为 zh-Hans。</summary>
    [Fact]
    public void EnglishTagWithChineseContentCorrectsToSimplifiedChinese()
    {
        Assert.Equal("zh-Hans", AsrTranscriptMapper.ScriptCorrectedLanguageCode("en", ChineseText));
    }

    /// <summary>en 标签 + 纯英文 → 保持 en，不误伤。</summary>
    [Fact]
    public void EnglishTagWithEnglishContentStaysEnglish()
    {
        Assert.Equal("en", AsrTranscriptMapper.ScriptCorrectedLanguageCode("en", EnglishText));
    }

    /// <summary>ja 标签 + 日文 → 保留 ja。</summary>
    [Fact]
    public void JapaneseTagWithJapaneseContentStaysJapanese()
    {
        Assert.Equal("ja", AsrTranscriptMapper.ScriptCorrectedLanguageCode("ja", JapaneseText));
    }

    /// <summary>en 标签 + 日文 → 校正为 ja（假名信号覆盖）。</summary>
    [Fact]
    public void EnglishTagWithJapaneseContentCorrectsToJapanese()
    {
        Assert.Equal("ja", AsrTranscriptMapper.ScriptCorrectedLanguageCode("en", JapaneseText));
    }

    /// <summary>zh-Hant 标签 + 中文 → 保留 zh-Hant，不降级成 zh-Hans。</summary>
    [Fact]
    public void TraditionalChineseTagIsNotDowngraded()
    {
        Assert.Equal("zh-Hant", AsrTranscriptMapper.ScriptCorrectedLanguageCode("zh-Hant", ChineseText));
    }

    /// <summary>yue（粤语）标签 + 中文 → 保留 yue，不降级。</summary>
    [Fact]
    public void CantoneseTagIsNotDowngraded()
    {
        Assert.Equal("yue", AsrTranscriptMapper.ScriptCorrectedLanguageCode("yue", ChineseText));
    }

    /// <summary>en 标签 + 韩文 → 校正为 ko。</summary>
    [Fact]
    public void EnglishTagWithKoreanContentCorrectsToKorean()
    {
        Assert.Equal("ko", AsrTranscriptMapper.ScriptCorrectedLanguageCode("en", KoreanText));
    }

    /// <summary>短文本（&lt; 20 可见字符）→ 保守，原样返回候选。</summary>
    [Fact]
    public void ShortTextIsLeftUnchanged()
    {
        Assert.Equal("en", AsrTranscriptMapper.ScriptCorrectedLanguageCode("en", "你好世界"));
    }

    /// <summary>auto/空标签 + 中文 → 可被内容覆盖为 zh-Hans。</summary>
    [Fact]
    public void AutoTagWithChineseContentCorrectsToSimplifiedChinese()
    {
        Assert.Equal("zh-Hans", AsrTranscriptMapper.ScriptCorrectedLanguageCode("auto", ChineseText));
    }

    /// <summary>各种 en 写法（en-US）也应被识别为同一族，中文内容仍覆盖。</summary>
    [Fact]
    public void EnUsTagWithChineseContentCorrectsToSimplifiedChinese()
    {
        Assert.Equal("zh-Hans", AsrTranscriptMapper.ScriptCorrectedLanguageCode("en-US", ChineseText));
    }
}
