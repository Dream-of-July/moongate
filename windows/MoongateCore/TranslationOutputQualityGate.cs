using System.Globalization;
using System.Text;

namespace Moongate.Core;

public enum TranslationOutputQualityReason
{
    SourceLanguageLeakage,
}

public sealed record TranslationOutputQualityReport(
    int VisibleScalarCount,
    int SourceScriptScalarCount,
    double SourceScriptScalarRatio,
    int AffectedLineCount);

public sealed record TranslationOutputQualityVerdict(
    bool Usable,
    IReadOnlyList<TranslationOutputQualityReason> Reasons,
    TranslationOutputQualityReport Report);

public static class TranslationOutputQualityGate
{
    public static TranslationOutputQualityVerdict Assess(
        IReadOnlyList<string> lines,
        string? sourceLanguageCode,
        string targetLanguageCode)
    {
        var target = TranslationLanguage.NormalizedScript(targetLanguageCode);
        var source = TranslationLanguage.NormalizedScript(sourceLanguageCode ?? "");
        if (!target.StartsWith("zh", StringComparison.Ordinal)
            || source.Length == 0
            || source == target
            || SourceScript.FromLanguageCode(source) is not { } sourceScript)
        {
            return new TranslationOutputQualityVerdict(true, [], EmptyReport);
        }

        if (sourceScript.Kind == ScriptKind.Latin)
        {
            return AssessLatinSourceForChineseTarget(lines, sourceScript);
        }

        var visibleScalarCount = 0;
        var sourceScriptScalarCount = 0;
        var affectedLineCount = 0;

        foreach (var line in lines)
        {
            var lineVisible = 0;
            var lineSource = 0;
            foreach (var rune in line.EnumerateRunes())
            {
                if (!IsVisibleRune(rune)) continue;
                lineVisible++;
                if (sourceScript.Contains(rune)) lineSource++;
            }
            if (lineVisible == 0) continue;
            visibleScalarCount += lineVisible;
            sourceScriptScalarCount += lineSource;
            if (lineSource >= sourceScript.AffectedLineMinimum
                && (double)lineSource / lineVisible >= sourceScript.AffectedLineRatio)
            {
                affectedLineCount++;
            }
        }

        var ratio = visibleScalarCount == 0 ? 0 : (double)sourceScriptScalarCount / visibleScalarCount;
        var report = new TranslationOutputQualityReport(
            visibleScalarCount,
            sourceScriptScalarCount,
            ratio,
            affectedLineCount);
        var leaking = sourceScriptScalarCount >= sourceScript.TotalMinimum && ratio >= sourceScript.TotalRatio
            || affectedLineCount >= 2 && sourceScriptScalarCount >= sourceScript.MultiLineMinimum;
        return leaking
            ? new TranslationOutputQualityVerdict(false, [TranslationOutputQualityReason.SourceLanguageLeakage], report)
            : new TranslationOutputQualityVerdict(true, [], report);
    }

    private static TranslationOutputQualityVerdict AssessLatinSourceForChineseTarget(
        IReadOnlyList<string> lines,
        SourceScript sourceScript)
    {
        var visibleScalarCount = 0;
        var sourceScriptScalarCount = 0;
        var affectedLineCount = 0;
        var affectedLatinWordCount = 0;

        foreach (var line in lines)
        {
            var lineVisible = 0;
            var lineSource = 0;
            var lineTarget = 0;
            foreach (var rune in line.EnumerateRunes())
            {
                if (!IsVisibleRune(rune)) continue;
                lineVisible++;
                if (sourceScript.Contains(rune)) lineSource++;
                if (IsHanRune(rune)) lineTarget++;
            }
            if (lineVisible == 0) continue;
            visibleScalarCount += lineVisible;
            sourceScriptScalarCount += lineSource;

            var latinWords = LatinWordCount(line);
            var targetRatio = (double)lineTarget / lineVisible;
            var looksLikeUntranslatedEnglishLine = latinWords >= 5
                && lineSource >= 18
                && lineTarget < 2
                && targetRatio < 0.10;
            if (looksLikeUntranslatedEnglishLine)
            {
                affectedLineCount++;
                affectedLatinWordCount += latinWords;
            }
        }

        var ratio = visibleScalarCount == 0 ? 0 : (double)sourceScriptScalarCount / visibleScalarCount;
        var report = new TranslationOutputQualityReport(
            visibleScalarCount,
            sourceScriptScalarCount,
            ratio,
            affectedLineCount);
        var leaking = affectedLineCount >= 2 || affectedLatinWordCount >= 10;
        return leaking
            ? new TranslationOutputQualityVerdict(false, [TranslationOutputQualityReason.SourceLanguageLeakage], report)
            : new TranslationOutputQualityVerdict(true, [], report);
    }

    private static TranslationOutputQualityReport EmptyReport { get; } = new(0, 0, 0, 0);

    private static bool IsVisibleRune(Rune rune)
    {
        var category = Rune.GetUnicodeCategory(rune);
        return category is not (
            UnicodeCategory.SpaceSeparator
            or UnicodeCategory.LineSeparator
            or UnicodeCategory.ParagraphSeparator
            or UnicodeCategory.Control
            or UnicodeCategory.Format
            or UnicodeCategory.DashPunctuation
            or UnicodeCategory.ConnectorPunctuation
            or UnicodeCategory.OpenPunctuation
            or UnicodeCategory.ClosePunctuation
            or UnicodeCategory.InitialQuotePunctuation
            or UnicodeCategory.FinalQuotePunctuation
            or UnicodeCategory.OtherPunctuation
            or UnicodeCategory.MathSymbol
            or UnicodeCategory.CurrencySymbol
            or UnicodeCategory.ModifierSymbol
            or UnicodeCategory.OtherSymbol);
    }

    private static bool IsHanRune(Rune rune) => rune.Value is >= 0x3400 and <= 0x4DBF
        or >= 0x4E00 and <= 0x9FFF
        or >= 0xF900 and <= 0xFAFF
        or >= 0x20000 and <= 0x2FA1F;

    private static int LatinWordCount(string line)
    {
        var count = 0;
        var inWord = false;
        foreach (var rune in line.EnumerateRunes())
        {
            var isLatin = rune.Value is >= 0x0041 and <= 0x005A
                or >= 0x0061 and <= 0x007A
                or >= 0x00C0 and <= 0x024F;
            if (isLatin)
            {
                if (!inWord)
                {
                    count++;
                    inWord = true;
                }
            }
            else
            {
                inWord = false;
            }
        }
        return count;
    }

    private enum ScriptKind
    {
        Kana,
        Hangul,
        Latin,
    }

    private sealed record SourceScript(ScriptKind Kind)
    {
        public static SourceScript? FromLanguageCode(string sourceLanguageCode) => sourceLanguageCode switch
        {
            "ja" => new SourceScript(ScriptKind.Kana),
            "ko" => new SourceScript(ScriptKind.Hangul),
            "en" or "fr" or "de" or "es" or "it" or "pt" or "vi" or "id" => new SourceScript(ScriptKind.Latin),
            _ => null,
        };

        public int TotalMinimum => Kind switch
        {
            ScriptKind.Kana or ScriptKind.Hangul => 12,
            _ => 24,
        };

        public int MultiLineMinimum => Kind switch
        {
            ScriptKind.Kana or ScriptKind.Hangul => 6,
            _ => 16,
        };

        public double TotalRatio => Kind switch
        {
            ScriptKind.Kana or ScriptKind.Hangul => 0.12,
            _ => 0.40,
        };

        public int AffectedLineMinimum => Kind switch
        {
            ScriptKind.Kana or ScriptKind.Hangul => 2,
            _ => 8,
        };

        public double AffectedLineRatio => Kind switch
        {
            ScriptKind.Kana or ScriptKind.Hangul => 0.18,
            _ => 0.40,
        };

        public bool Contains(Rune rune) => Kind switch
        {
            ScriptKind.Kana => rune.Value is >= 0x3040 and <= 0x30FF
                or >= 0x31F0 and <= 0x31FF
                or >= 0xFF66 and <= 0xFF9F,
            ScriptKind.Hangul => rune.Value is >= 0x1100 and <= 0x11FF
                or >= 0x3130 and <= 0x318F
                or >= 0xAC00 and <= 0xD7A3,
            ScriptKind.Latin => rune.Value is >= 0x0041 and <= 0x005A
                or >= 0x0061 and <= 0x007A
                or >= 0x00C0 and <= 0x024F,
            _ => false,
        };
    }
}
