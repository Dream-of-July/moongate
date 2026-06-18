using Moongate.Core;

namespace MoongateCore.Tests;

/// <summary>PARITY-001：统一 URL 分词器，按 http(s):// 锚点切分，覆盖换行/相邻/标点/重复等。</summary>
public class UrlTokenizerTests
{
    [Fact]
    public void SingleUrl_Extracted() =>
        Assert.Equal(["https://youtu.be/abc"], UrlTokenizer.Extract("https://youtu.be/abc"));

    [Fact]
    public void WhitespaceSeparated_MultipleUrls() =>
        Assert.Equal(
            ["https://a.com/1", "https://b.com/2"],
            UrlTokenizer.Extract("https://a.com/1  https://b.com/2"));

    [Fact]
    public void NewlineSeparated_MultipleUrls() =>
        Assert.Equal(
            ["https://a.com/1", "https://b.com/2"],
            UrlTokenizer.Extract("https://a.com/1\nhttps://b.com/2"));

    /// <summary>关键回归：换行被吞、两条链接首尾相接时，旧的按空白切分会当成一条无效 URL。</summary>
    [Fact]
    public void AdjacentUrls_NoSeparator_StillSplit() =>
        Assert.Equal(
            ["https://a.com/x", "https://b.com/y"],
            UrlTokenizer.Extract("https://a.com/xhttps://b.com/y"));

    [Fact]
    public void TrailingPunctuation_Trimmed() =>
        Assert.Equal(
            ["https://a.com/x", "https://b.com/y"],
            UrlTokenizer.Extract("https://a.com/x， https://b.com/y。"));

    [Fact]
    public void BracketWrapped_Trimmed() =>
        Assert.Equal(["https://a.com/x"], UrlTokenizer.Extract("（https://a.com/x）"));

    [Fact]
    public void DuplicateUrls_Deduped() =>
        Assert.Equal(
            ["https://a.com/x"],
            UrlTokenizer.Extract("https://a.com/x https://a.com/x"));

    [Fact]
    public void TabSeparated_MultipleUrls() =>
        Assert.Equal(
            ["https://a.com/1", "https://b.com/2"],
            UrlTokenizer.Extract("https://a.com/1\thttps://b.com/2"));

    [Fact]
    public void NonHttp_Ignored() =>
        Assert.Empty(UrlTokenizer.Extract("ftp://a.com/x mailto:foo@bar.com just text"));

    [Fact]
    public void MixedTextAndUrls_OnlyUrls() =>
        Assert.Equal(
            ["https://a.com/x"],
            UrlTokenizer.Extract("see https://a.com/x for details"));
}
