using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Moongate.Core;

/// <summary>
/// Deterministic, no-regex script detection over titles and short text samples. Shared by the
/// language recommender; the Unicode ranges mirror LooksJapanese in Asr.cs on purpose so the
/// ready-page recommendation and the ASR profile detector agree on what "looks Japanese/Korean".
/// </summary>
public static class ScriptDetector
{
    public readonly record struct Profile(
        double KanaRatio,
        double HangulRatio,
        double CjkRatio,
        double LatinRatio,
        int VisibleCount);

    /// <summary>Counts script ratios over visible (non-whitespace) scalars in text.</summary>
    public static Profile Of(string text)
    {
        int kana = 0, hangul = 0, cjk = 0, latin = 0, visible = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (Rune.IsWhiteSpace(rune)) continue;
            visible++;
            var v = rune.Value;
            if (v is >= 0x3040 and <= 0x30FF) kana++;
            else if (v is (>= 0xAC00 and <= 0xD7A3) or (>= 0x1100 and <= 0x11FF)) hangul++;
            else if (v is >= 0x4E00 and <= 0x9FFF) cjk++;
            else if (v is (>= 0x0041 and <= 0x005A) or (>= 0x0061 and <= 0x007A)) latin++;
        }
        if (visible == 0) return new Profile(0, 0, 0, 0, 0);
        double d = visible;
        return new Profile(kana / d, hangul / d, cjk / d, latin / d, visible);
    }
}

/// <summary>
/// Language-first recommendation for the ready page. Runs BEFORE download, so it only sees the
/// video title and the available subtitle tracks (language code + manual/auto markers). It never
/// reads cue text, never goes online, never calls an LLM, and never hardcodes a language: the
/// recommendation falls out of deterministic scoring so it follows the actual video content.
/// </summary>
public static class SubtitleLanguageRecommender
{
    public sealed record Result(SubtitleLanguageChoice? Recommended, IReadOnlyList<SubtitleLanguageChoice> Others);

    public enum SourceLanguageEvidence
    {
        UserSelected,
        PlatformManualTrack,
        PlatformAutoTrack,
        TitleScript,
        TitleKeyword,
        PreviousSetting,
        AsrDetected,
        Fallback,
    }

    public enum SourceLanguageConfidence
    {
        Unknown,
        Low,
        Medium,
        High,
    }

    public sealed record SourceLanguageRecommendation(
        string Code,
        string DisplayName,
        SourceLanguageEvidence Evidence,
        SourceLanguageConfidence Confidence,
        bool IsRareLanguage,
        bool ShouldAutoSelect);

    // Scoring constants. Single source of truth lives in the cross-platform fixture
    // (languageRecommender section); the Swift and C# copies are each asserted equal to it.
    public const int ManualTrackScore = 100;
    public const int AutoTrackScore = 40;
    public const int LocalAsrOnlyScore = 10;
    public const int JapaneseScriptBonus = 80;
    public const int KoreanScriptBonus = 80;
    public const int LatinScriptBonus = 30;
    /// <summary>
    /// Weak signal: CJK ideographs (kanji) present but no kana/hangul. Romanized Japanese/Korean
    /// titles (e.g. "YOASOBI - 群青 (Gunjou)") are Latin-dominant with only a few ideographs, so a
    /// full script bonus can't fire — this lifts East-Asian-script languages over Latin ones.
    /// </summary>
    public const int CjkPresenceBonus = 20;
    /// <summary>
    /// Stronger Han-script signal when a CJK language has a platform auto track. Local-ASR choices
    /// are synthetic per-language candidates in the UI, so they are not source-language evidence.
    /// </summary>
    public const int PlatformAutoCjkPresenceBonus = 90;
    /// <summary>
    /// User/global source-language preference. This can make a local-ASR source candidate win over
    /// unrelated auto captions, while still letting manual target subtitles stay on top.
    /// </summary>
    public const int PreferredSourceLanguageScore = 180;
    public const int TitleLanguageHintBonus = 15;
    public const double TitleScriptDominanceRatio = 0.18;

    /// <summary>Aggregates flat choices into language groups (delegates to the model-layer grouping).</summary>
    public static IReadOnlyList<SubtitleLanguageChoice> Aggregate(IReadOnlyList<SubtitleChoice> choices)
        => SubtitleLanguageChoice.Aggregate(choices);

    /// <summary>Picks a recommended language from the title + available language groups.</summary>
    public static Result Recommend(
        string title,
        IReadOnlyList<SubtitleLanguageChoice> languages,
        string? targetLanguage = null,
        string? preferredSourceLanguage = null)
    {
        if (languages.Count == 0) return new Result(null, []);
        var titleProfile = ScriptDetector.Of(title);
        var lowerTitle = title.ToLowerInvariant();
        var normalizedPreferredSource = NormalizedPreferredSourceLanguage(preferredSourceLanguage);

        var ranked = languages
            .Select((language, index) => (
                language,
                score: Score(language, titleProfile, lowerTitle, normalizedPreferredSource),
                index))
            .OrderByDescending(x => x.score)
            // Tie-break: manual track first, then language code ascending.
            .ThenByDescending(x => x.language.HasManualTrack)
            .ThenBy(x => x.language.LanguageCode, StringComparer.Ordinal)
            .Select(x => x.language)
            .ToList();

        var recommended = ranked.FirstOrDefault();
        var others = ranked.Skip(1).ToList();
        return new Result(recommended, others);
    }

    public static SourceLanguageRecommendation SourceRecommendation(
        string title,
        IReadOnlyList<SubtitleLanguageChoice> languages,
        string? targetLanguage = null,
        string? preferredSourceLanguage = null)
    {
        var normalizedPreferredSource = NormalizedPreferredSourceLanguage(preferredSourceLanguage);
        var recommendation = Recommend(title, languages, targetLanguage, preferredSourceLanguage);
        if (recommendation.Recommended is null)
        {
            return new SourceLanguageRecommendation(
                "auto",
                "Auto",
                SourceLanguageEvidence.Fallback,
                SourceLanguageConfidence.Unknown,
                false,
                false);
        }

        var language = recommendation.Recommended;
        var normalizedCode = LanguageCatalog.Normalize(language.LanguageCode);
        SourceLanguageEvidence evidence;
        SourceLanguageConfidence confidence;
        if (normalizedPreferredSource == normalizedCode)
        {
            evidence = SourceLanguageEvidence.UserSelected;
            confidence = SourceLanguageConfidence.High;
        }
        else if (language.HasManualTrack)
        {
            evidence = SourceLanguageEvidence.PlatformManualTrack;
            confidence = SourceLanguageConfidence.High;
        }
        else if (language.HasAutoTrack)
        {
            evidence = SourceLanguageEvidence.PlatformAutoTrack;
            confidence = LanguageCatalog.IsRareLanguage(normalizedCode)
                ? SourceLanguageConfidence.Low
                : SourceLanguageConfidence.Medium;
        }
        else if (InferredLocalAsrLanguageCode(title) is { } inferred
                 && LanguageCatalog.Normalize(inferred) == normalizedCode)
        {
            evidence = SourceLanguageEvidence.TitleKeyword;
            confidence = LanguageCatalog.IsRareLanguage(normalizedCode)
                ? SourceLanguageConfidence.Low
                : SourceLanguageConfidence.Medium;
        }
        else
        {
            var profile = ScriptDetector.Of(title);
            evidence = ScriptEvidence(normalizedCode, profile);
            confidence = evidence == SourceLanguageEvidence.Fallback || LanguageCatalog.IsRareLanguage(normalizedCode)
                ? SourceLanguageConfidence.Low
                : SourceLanguageConfidence.Medium;
        }

        var rare = LanguageCatalog.IsRareLanguage(normalizedCode);
        var shouldAutoSelect = confidence >= SourceLanguageConfidence.Medium
            || evidence is SourceLanguageEvidence.PlatformManualTrack or SourceLanguageEvidence.UserSelected;
        return new SourceLanguageRecommendation(
            normalizedCode,
            LanguageCatalog.DisplayName(normalizedCode),
            evidence,
            confidence,
            rare,
            shouldAutoSelect);
    }

    /// <summary>
    /// Best-effort language lock for local-ASR-only pages. Used only when no platform subtitles
    /// exist, so strong title hints can prevent Whisper auto-detection from mislabeling Japanese
    /// audio as English. Weak/ambiguous titles return null and keep auto-detect.
    /// </summary>
    public static string? InferredLocalAsrLanguageCode(string title)
    {
        var lowerTitle = FoldForLanguageHint(title);
        var profile = ScriptDetector.Of(title);
        if (lowerTitle.Contains("japanese")
            || lowerTitle.Contains("japaner")
            || lowerTitle.Contains("japansk")
            || lowerTitle.Contains("japonais")
            || lowerTitle.Contains("japones")
            || lowerTitle.Contains("japonesa")
            || lowerTitle.Contains("japon")
            || lowerTitle.Contains("giapponese")
            || title.Contains("日本語")
            || title.Contains("日语")
            || title.Contains("日語")
            || title.Contains("日文")
            || profile.KanaRatio >= TitleScriptDominanceRatio)
        {
            return "ja";
        }
        return null;
    }

    private static string FoldForLanguageHint(string title)
    {
        var normalized = title.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(normalized.Length);
        foreach (var ch in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            builder.Append(char.ToLowerInvariant(ch));
        }
        return builder.ToString().Normalize(NormalizationForm.FormC);
    }

    internal static int Score(
        SubtitleLanguageChoice language,
        ScriptDetector.Profile titleProfile,
        string lowerTitle,
        string? preferredSourceLanguage = null)
    {
        var total = 0;
        // 1) Track availability base score (manual preferred over auto over localASR-only).
        if (language.HasManualTrack) total += ManualTrackScore;
        else if (language.HasAutoTrack) total += AutoTrackScore;
        else total += LocalAsrOnlyScore;
        if (preferredSourceLanguage is not null
            && LanguageCatalog.Normalize(language.LanguageCode) == preferredSourceLanguage)
        {
            total += PreferredSourceLanguageScore;
        }

        // 2) Title script alignment.
        var code = language.LanguageCode;
        var titleHasKana = titleProfile.KanaRatio >= TitleScriptDominanceRatio;
        var titleHasHangul = titleProfile.HangulRatio >= TitleScriptDominanceRatio;
        var titleIsLatinDominant = titleProfile.LatinRatio >= TitleScriptDominanceRatio
            && titleProfile.KanaRatio == 0 && titleProfile.HangulRatio == 0 && titleProfile.CjkRatio == 0;
        if (IsJapaneseCode(code) && titleHasKana) total += JapaneseScriptBonus;
        if (IsKoreanCode(code) && titleHasHangul) total += KoreanScriptBonus;
        if (IsLatinScriptLanguage(code) && titleIsLatinDominant) total += LatinScriptBonus;
        // Weak East-Asian signal: any ideographs present, no kana/hangul. Helps romanized CJK titles.
        var titleHasIdeographsOnly = titleProfile.CjkRatio > 0
            && titleProfile.KanaRatio == 0 && titleProfile.HangulRatio == 0;
        if (titleHasIdeographsOnly && (IsJapaneseCode(code) || IsKoreanCode(code) || code == "zh" || code == "yue"))
        {
            total += language.HasAutoTrack
                ? PlatformAutoCjkPresenceBonus
                : CjkPresenceBonus;
        }

        // 3) Explicit title language hints (substring, no regex).
        if (IsJapaneseCode(code)
            && (lowerTitle.Contains("日本語") || lowerTitle.Contains("日语") || lowerTitle.Contains("日語")))
        {
            total += TitleLanguageHintBonus;
        }
        if (IsKoreanCode(code)
            && (lowerTitle.Contains("한국어") || lowerTitle.Contains("韓国語") || lowerTitle.Contains("韩语")))
        {
            total += TitleLanguageHintBonus;
        }
        return total;
    }

    internal static string? NormalizedTargetLanguage(string? targetLanguage)
    {
        if (string.IsNullOrWhiteSpace(targetLanguage)) return null;
        return LanguageCatalog.Normalize(targetLanguage.Trim());
    }

    internal static string? NormalizedPreferredSourceLanguage(string? preferredSourceLanguage)
    {
        if (string.IsNullOrWhiteSpace(preferredSourceLanguage)) return null;
        var normalized = AppSettings.NormalizePreferredSourceLanguage(preferredSourceLanguage);
        return normalized == "auto" ? null : LanguageCatalog.Normalize(normalized);
    }

    internal static SubtitleLanguageChoice PrioritizeTargetTrack(
        SubtitleLanguageChoice language,
        string? targetLanguage)
    {
        if (!HasTargetLanguageTrack(language, targetLanguage)) return language;
        var tracks = language.Tracks
            .Select((track, index) => (track, index))
            .OrderByDescending(pair => IsTargetLanguageTrack(pair.track, targetLanguage))
            .ThenBy(pair => SubtitleLanguageChoice.TrackRank(pair.track.SourceKind))
            .ThenBy(pair => pair.index)
            .Select(pair => pair.track)
            .ToList();
        var label = tracks.FirstOrDefault(track => track.SourceKind != SubtitleSourceKind.LocalAsr)?.Label
            ?? tracks.FirstOrDefault()?.Label
            ?? language.DisplayLabel;
        return language with
        {
            DisplayLabel = label,
            Tracks = tracks,
        };
    }

    internal static bool HasTargetLanguageTrack(
        SubtitleLanguageChoice language,
        string? targetLanguage)
        => language.Tracks.Any(track => IsTargetLanguageTrack(track, targetLanguage));

    internal static bool IsTargetLanguageTrack(
        SubtitleChoice track,
        string? targetLanguage)
        => !string.IsNullOrEmpty(targetLanguage)
            && track.SourceKind != SubtitleSourceKind.LocalAsr
            && track.SourceKind != SubtitleSourceKind.PlatformAuto
            && LanguageCatalog.Normalize(track.LanguageCode) == targetLanguage;

    private static SourceLanguageEvidence ScriptEvidence(string code, ScriptDetector.Profile profile)
    {
        if (IsJapaneseCode(code) && profile.KanaRatio >= TitleScriptDominanceRatio) return SourceLanguageEvidence.TitleScript;
        if (IsKoreanCode(code) && profile.HangulRatio >= TitleScriptDominanceRatio) return SourceLanguageEvidence.TitleScript;
        if (IsLatinScriptLanguage(code)
            && profile.LatinRatio >= TitleScriptDominanceRatio
            && profile.KanaRatio == 0
            && profile.HangulRatio == 0
            && profile.CjkRatio == 0)
        {
            return SourceLanguageEvidence.TitleScript;
        }
        return SourceLanguageEvidence.Fallback;
    }

    internal static bool IsJapaneseCode(string code) => code == "ja" || code == "jpn";

    internal static bool IsKoreanCode(string code) => code == "ko" || code == "kor";

    /// <summary>Latin-script European languages we recommend on a Latin-dominant title.</summary>
    internal static bool IsLatinScriptLanguage(string code) => LatinScriptLanguageCodes.Contains(code);

    internal static readonly HashSet<string> LatinScriptLanguageCodes = new(StringComparer.Ordinal)
    {
        "en", "es", "fr", "it", "de", "pt", "nl", "sv", "no", "da", "fi", "pl", "id", "vi", "tr", "ro", "cs",
    };
}
