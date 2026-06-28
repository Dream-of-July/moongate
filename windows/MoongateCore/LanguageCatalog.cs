using System.Globalization;
using System.Text;

namespace Moongate.Core;

public sealed record LanguageCatalogEntry(
    string Code,
    string EnglishName,
    string ChineseName,
    string NativeName,
    IReadOnlyList<string> Aliases,
    bool IsCommon)
{
    public string DisplayName => string.IsNullOrWhiteSpace(NativeName) ? EnglishName : NativeName;
}

public static class LanguageCatalog
{
    public static IReadOnlyList<string> CommonLanguageCodes { get; } = ["en", "ja", "zh-Hans", "ko", "yue"];

    private static readonly Dictionary<string, string> AliasNormalization = new(StringComparer.OrdinalIgnoreCase)
    {
        ["en-us"] = "en", ["en-gb"] = "en", ["eng"] = "en",
        ["ja-jp"] = "ja", ["jpn"] = "ja", ["jp"] = "ja",
        ["ko-kr"] = "ko", ["kor"] = "ko", ["kr"] = "ko",
        ["zh"] = "zh-Hans", ["zh-cn"] = "zh-Hans", ["zh-sg"] = "zh-Hans", ["zh-hans"] = "zh-Hans", ["cmn"] = "zh-Hans",
        ["zh-tw"] = "zh-Hant", ["zh-hk"] = "zh-Hant", ["zh-mo"] = "zh-Hant", ["zh-hant"] = "zh-Hant",
        ["yue-hk"] = "yue",
        ["iw"] = "he",
        ["in"] = "id",
        ["tl"] = "fil",
    };

    private static readonly IReadOnlyList<LanguageCatalogEntry> Entries =
    [
        Entry("en", "English", "英语", "English", ["english", "eng", "en-us", "en-gb"], true),
        Entry("ja", "Japanese", "日语", "日本語", ["japanese", "jpn", "jp", "日文"], true),
        Entry("zh-Hans", "Simplified Chinese", "简体中文", "中文", ["zh", "zh-cn", "cmn", "mandarin", "chinese", "中文", "汉语", "普通话"], true),
        Entry("zh-Hant", "Traditional Chinese", "繁体中文", "繁體中文", ["zh-tw", "zh-hk", "traditional chinese"], false),
        Entry("ko", "Korean", "韩语", "한국어", ["korean", "kor", "ko-kr", "韓国語"], true),
        Entry("yue", "Cantonese", "粤语", "粵語", ["cantonese", "粤语", "廣東話", "广东话"], true),
        Entry("es", "Spanish", "西班牙语", "Español", ["spanish", "es-es", "es-mx"], false),
        Entry("fr", "French", "法语", "Français", ["french", "fra", "fre", "fr-fr"], false),
        Entry("de", "German", "德语", "Deutsch", ["german", "deu", "ger", "de-de"], false),
        Entry("it", "Italian", "意大利语", "Italiano", ["italian", "ita", "it-it"], false),
        Entry("pt", "Portuguese", "葡萄牙语", "Português", ["portuguese", "por", "pt-br", "pt-pt"], false),
        Entry("vi", "Vietnamese", "越南语", "Tiếng Việt", ["vietnamese", "vie", "vi-vn"], false),
        Entry("id", "Indonesian", "印尼语", "Bahasa Indonesia", ["indonesian", "ind", "in"], false),
        Entry("fil", "Filipino", "菲律宾语", "Filipino", ["filipino", "tagalog", "tl"], false),
        Entry("he", "Hebrew", "希伯来语", "עברית", ["hebrew", "heb", "iw"], false),
        Entry("si", "Sinhala", "僧伽罗语", "සිංහල", ["sinhala", "sin", "සිංහල"], false),
    ];

    private static readonly IReadOnlyDictionary<string, LanguageCatalogEntry> EntriesByCode =
        Entries.ToDictionary(entry => entry.Code, StringComparer.Ordinal);

    public static string Normalize(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "";
        var folded = code.Trim().ToLowerInvariant();
        if (AliasNormalization.TryGetValue(folded, out var mapped)) return mapped;
        if (folded.StartsWith("zh-", StringComparison.Ordinal))
        {
            return folded.Contains("hant", StringComparison.Ordinal)
                || folded.Contains("-tw", StringComparison.Ordinal)
                || folded.Contains("-hk", StringComparison.Ordinal)
                ? "zh-Hant"
                : "zh-Hans";
        }
        var dash = folded.IndexOf('-');
        if (dash >= 0)
        {
            var baseCode = folded[..dash];
            return AliasNormalization.TryGetValue(baseCode, out var baseMapped) ? baseMapped : baseCode;
        }
        return AliasNormalization.TryGetValue(folded, out mapped) ? mapped : folded;
    }

    public static string DisplayName(string code)
    {
        var normalized = Normalize(code);
        if (EntriesByCode.TryGetValue(normalized, out var entry))
        {
            return entry.IsCommon ? entry.DisplayName : entry.EnglishName;
        }
        return TranslationLanguage.SourceDisplayName(normalized) ?? normalized;
    }

    public static bool IsCommon(string code) => CommonLanguageCodes.Contains(Normalize(code), StringComparer.Ordinal);

    public static bool IsRareLanguage(string code)
    {
        var normalized = Normalize(code);
        if (normalized.Length == 0) return false;
        return !EntriesByCode.TryGetValue(normalized, out var entry) || !entry.IsCommon;
    }

    public static IReadOnlyList<LanguageCatalogEntry> CommonEntries() =>
        CommonLanguageCodes.Select(code => EntriesByCode.GetValueOrDefault(code)).OfType<LanguageCatalogEntry>().ToList();

    public static IReadOnlyList<LanguageCatalogEntry> Search(string query)
    {
        if (string.IsNullOrWhiteSpace(query)) return CommonEntries();
        var normalizedQuery = Normalize(query);
        var folded = Fold(query.Trim());
        return Entries
            .Where(entry =>
            {
                if (entry.Code == normalizedQuery) return true;
                return new[] { entry.Code, entry.EnglishName, entry.ChineseName, entry.NativeName }
                    .Concat(entry.Aliases)
                    .Any(field => Fold(field).Contains(folded, StringComparison.Ordinal));
            })
            .OrderByDescending(entry => entry.IsCommon)
            .ThenBy(entry => entry.EnglishName, StringComparer.Ordinal)
            .ToList();
    }

    private static LanguageCatalogEntry Entry(
        string code,
        string englishName,
        string chineseName,
        string nativeName,
        IReadOnlyList<string> aliases,
        bool isCommon) => new(code, englishName, chineseName, nativeName, aliases, isCommon);

    private static string Fold(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(normalized.Length);
        foreach (var ch in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
            {
                builder.Append(char.ToLowerInvariant(ch));
            }
        }
        return builder.ToString().Normalize(NormalizationForm.FormC);
    }
}
