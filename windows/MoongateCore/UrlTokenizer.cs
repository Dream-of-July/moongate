using System.Text.RegularExpressions;

namespace Moongate.Core;

/// <summary>
/// 从粘贴文本里提取 http(s) 链接的统一分词器（纯逻辑，便于测试）。
/// 按 http(s):// 锚点切分而非只按空白：单行输入框粘贴多行时换行可能被吞掉、
/// 多条链接首尾相接，按空白分隔会把整段当成一条，导致「只解析出一个地址」。
/// 与 macOS extractURLs 同构。
/// </summary>
public static class UrlTokenizer
{
    private static readonly char[] TrailingPunctuation =
        [',', ';', '，', '；', '、', '。', '.', ')', '）', ']', '》', '〉', '>', '」', '』', '"', '\''];

    // 每个字符既非空白、也不是下一条链接的开头（负向前瞻保证相接的链接被切开）。
    private static readonly Regex UrlExtractionRegex = new(
        @"(?i)https?://(?:(?!https?://)\S)+", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    /// <summary>提取全部合法 http(s) 链接，去尾随标点、保序去重。</summary>
    public static List<string> Extract(string input)
    {
        var seen = new HashSet<string>();
        var urls = new List<string>();
        foreach (Match match in UrlExtractionRegex.Matches(input))
        {
            var token = match.Value.Trim(TrailingPunctuation);
            if (!IsValidHttpUrl(token)) continue;
            if (!seen.Add(token)) continue;
            urls.Add(token);
        }
        return urls;
    }

    private static bool IsValidHttpUrl(string input) =>
        Uri.TryCreate(input, UriKind.Absolute, out var url)
        && (url.Scheme == "http" || url.Scheme == "https")
        && !string.IsNullOrEmpty(url.Host);
}
