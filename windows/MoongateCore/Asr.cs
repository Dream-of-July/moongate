using System.Diagnostics;
using System.Globalization;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Moongate.Core;

public static class AsrJson
{
    public static JsonSerializerOptions Options { get; } = CreateOptions();

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        return options;
    }
}

public sealed record AsrRequest
{
    public required string AudioPath { get; init; }
    public string? LanguageCode { get; init; }
    public required string ModelId { get; init; }
    public string? Prompt { get; init; }
    public bool VadEnabled { get; init; } = true;
    public bool WordTimestamps { get; init; } = true;
    public string? CacheKey { get; init; }
}

public sealed record AsrWord
{
    public required string Text { get; init; }
    public required double StartSeconds { get; init; }
    public required double EndSeconds { get; init; }
    public double? Probability { get; init; }
}

public sealed record AsrTranscript
{
    public required string Id { get; init; }
    public required string LanguageCode { get; init; }
    public double? LanguageConfidence { get; init; }
    public double? DurationSeconds { get; init; }
    public required IReadOnlyList<AsrWord> Words { get; init; }
    public required string SourceModelId { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
}

public enum AsrProgressPhase
{
    ModelDownload,
    AudioExtract,
    SpeechRecognition,
    SubtitleSegment,
}

public sealed record AsrProgress
{
    public required AsrProgressPhase Phase { get; init; }
    public double? CompletedUnits { get; init; }
    public double? TotalUnits { get; init; }
    public string? Detail { get; init; }

    public double? Fraction => CompletedUnits is { } completed
        && TotalUnits is { } total
        && total > 0
            ? Math.Clamp(completed / total, 0, 1)
            : null;
}

public enum AsrReadinessStatus
{
    Ready,
    MissingRuntime,
    MissingModel,
    BadModelHash,
    InsufficientDiskSpace,
    UnsupportedPlatform,
}

public sealed record AsrReadiness
{
    public required AsrReadinessStatus Status { get; init; }
    public string? ModelId { get; init; }
    public required string Message { get; init; }
    public bool IsReady => Status == AsrReadinessStatus.Ready;
}

public interface ISpeechRecognizer
{
    Task<AsrReadiness> ReadinessAsync(AsrRequest request, CancellationToken ct = default);
    Task<AsrTranscript> TranscribeAsync(
        AsrRequest request,
        Action<AsrProgress> progress,
        TaskControlToken? control = null,
        CancellationToken ct = default);
}

public enum FakeSpeechRecognizerError
{
    NoSpeech,
    LowLanguageConfidence,
    MissingModel,
    BadModelHash,
}

public sealed class FakeSpeechRecognizerException(FakeSpeechRecognizerError reason)
    : Exception(reason.ToString())
{
    public FakeSpeechRecognizerError Reason { get; } = reason;
}

public sealed class FakeSpeechRecognizer : ISpeechRecognizer
{
    public enum FakeMode
    {
        Success,
        Failure,
        Cancelled,
    }

    private readonly AsrReadiness _readiness;
    private readonly FakeMode _mode;
    private readonly AsrTranscript? _transcript;
    private readonly FakeSpeechRecognizerError? _failure;

    public FakeSpeechRecognizer(AsrReadiness readiness, AsrTranscript transcript)
    {
        _readiness = readiness;
        _mode = FakeMode.Success;
        _transcript = transcript;
    }

    public FakeSpeechRecognizer(AsrReadiness readiness, FakeSpeechRecognizerError failure)
    {
        _readiness = readiness;
        _mode = FakeMode.Failure;
        _failure = failure;
    }

    public static FakeSpeechRecognizer Cancelled(AsrReadiness readiness) => new(readiness, FakeMode.Cancelled);

    private FakeSpeechRecognizer(AsrReadiness readiness, FakeMode mode)
    {
        _readiness = readiness;
        _mode = mode;
    }

    public Task<AsrReadiness> ReadinessAsync(AsrRequest request, CancellationToken ct = default) =>
        Task.FromResult(_readiness);

    public Task<AsrTranscript> TranscribeAsync(
        AsrRequest request,
        Action<AsrProgress> progress,
        TaskControlToken? control = null,
        CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        return TranscribeCoreAsync(request, progress, control, ct);
    }

    private async Task<AsrTranscript> TranscribeCoreAsync(
        AsrRequest request,
        Action<AsrProgress> progress,
        TaskControlToken? control,
        CancellationToken ct)
    {
        if (control is not null) await control.GateAsync(ct).ConfigureAwait(false);
        progress(new AsrProgress
        {
            Phase = AsrProgressPhase.SpeechRecognition,
            CompletedUnits = 0,
            TotalUnits = 1,
        });

        return await (_mode switch
        {
            FakeMode.Success => CompleteSuccess(progress),
            FakeMode.Failure => Task.FromException<AsrTranscript>(
                new FakeSpeechRecognizerException(_failure ?? FakeSpeechRecognizerError.NoSpeech)),
            _ => Task.FromCanceled<AsrTranscript>(new CancellationToken(canceled: true)),
        }).ConfigureAwait(false);
    }

    private Task<AsrTranscript> CompleteSuccess(Action<AsrProgress> progress)
    {
        progress(new AsrProgress
        {
            Phase = AsrProgressPhase.SpeechRecognition,
            CompletedUnits = 1,
            TotalUnits = 1,
        });
        return Task.FromResult(_transcript!);
    }
}

public sealed record AsrModelManifest
{
    public required IReadOnlyList<AsrModelInfo> Models { get; init; }

    public static AsrModelManifest RecommendedWhisperCpp { get; } = new()
    {
        Models =
        [
            new AsrModelInfo
            {
                Id = "whisper.cpp:tiny-q5_1",
                DisplayName = "Whisper tiny q5_1",
                FileName = "ggml-tiny-q5_1.bin",
                DownloadUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin",
                SizeBytes = 32_152_673,
                Sha256 = "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7",
                MemoryRequiredMb = 256,
                License = "MIT",
                SourceDescription = "ggerganov/whisper.cpp on Hugging Face",
            },
            new AsrModelInfo
            {
                Id = "whisper.cpp:base-q5_1",
                DisplayName = "Whisper base q5_1",
                FileName = "ggml-base-q5_1.bin",
                DownloadUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin",
                SizeBytes = 59_707_625,
                Sha256 = "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898",
                MemoryRequiredMb = 512,
                License = "MIT",
                SourceDescription = "ggerganov/whisper.cpp on Hugging Face",
            },
            new AsrModelInfo
            {
                Id = "whisper.cpp:small-q5_1",
                DisplayName = "Whisper small q5_1",
                FileName = "ggml-small-q5_1.bin",
                DownloadUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin",
                SizeBytes = 190_085_487,
                Sha256 = "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
                MemoryRequiredMb = 1_024,
                License = "MIT",
                SourceDescription = "ggerganov/whisper.cpp on Hugging Face",
            },
        ],
    };
}

public sealed record AsrModelInfo
{
    public required string Id { get; init; }
    public required string DisplayName { get; init; }
    public required string FileName { get; init; }
    public required string DownloadUrl { get; init; }
    public required long SizeBytes { get; init; }
    public required string Sha256 { get; init; }
    public required int MemoryRequiredMb { get; init; }
    public required string License { get; init; }
    public required string SourceDescription { get; init; }
}

public enum AsrRuntimeBundleManifestError
{
    EmptyManifest,
    MissingRequiredField,
    InvalidExecutableRelativePath,
    InvalidSha256,
    MissingExecutable,
    Sha256Mismatch,
    DownloadUrlNotAllowed,
}

public sealed class AsrRuntimeBundleManifestException(
    AsrRuntimeBundleManifestError reason,
    string? detail = null)
    : Exception(detail is { Length: > 0 } ? $"{reason}: {detail}" : reason.ToString())
{
    public AsrRuntimeBundleManifestError Reason { get; } = reason;
    public string? Detail { get; } = detail;
}

public sealed record AsrRuntimeBundleManifest
{
    public required IReadOnlyList<AsrRuntimeBundleInfo> Runtimes { get; init; }

    public static AsrRuntimeBundleManifest FromJson(string json)
    {
        var manifest = JsonSerializer.Deserialize<AsrRuntimeBundleManifest>(json, AsrJson.Options)
            ?? throw new AsrRuntimeBundleManifestException(AsrRuntimeBundleManifestError.EmptyManifest);
        manifest.Validate();
        return manifest;
    }

    public void Validate()
    {
        if (Runtimes.Count == 0)
        {
            throw new AsrRuntimeBundleManifestException(AsrRuntimeBundleManifestError.EmptyManifest);
        }
        foreach (var runtime in Runtimes)
        {
            runtime.Validate();
        }
    }
}

public sealed record AsrRuntimeBundleInfo
{
    public required string Provider { get; init; }
    public required string Platform { get; init; }
    public required string Architecture { get; init; }
    public required string Version { get; init; }
    public required string ExecutableRelativePath { get; init; }
    public required string Sha256 { get; init; }
    public required string License { get; init; }
    public required string SourceDescription { get; init; }

    [JsonExtensionData]
    public IDictionary<string, JsonElement>? ExtraFields { get; init; }

    public string ExecutablePathUnder(string runtimeDirectory)
    {
        Validate();
        var normalizedRelative = ExecutableRelativePath.Replace('/', Path.DirectorySeparatorChar);
        return Path.GetFullPath(Path.Combine(runtimeDirectory, normalizedRelative));
    }

    public AsrRuntimeInfo VerifiedRuntimeInfoUnder(string runtimeDirectory)
    {
        var executable = ExecutablePathUnder(runtimeDirectory);
        if (!File.Exists(executable))
        {
            throw new AsrRuntimeBundleManifestException(
                AsrRuntimeBundleManifestError.MissingExecutable,
                ExecutableRelativePath);
        }
        var actualSha = AsrModelStore.Sha256Hex(executable);
        if (!string.Equals(actualSha, Sha256, StringComparison.OrdinalIgnoreCase))
        {
            throw new AsrRuntimeBundleManifestException(
                AsrRuntimeBundleManifestError.Sha256Mismatch,
                actualSha);
        }
        return new AsrRuntimeInfo { Provider = Provider, ExecutablePath = executable };
    }

    public void Validate()
    {
        if (ExtraFields?.ContainsKey("downloadUrl") == true)
        {
            throw new AsrRuntimeBundleManifestException(AsrRuntimeBundleManifestError.DownloadUrlNotAllowed);
        }
        Require(Provider, nameof(Provider));
        Require(Platform, nameof(Platform));
        Require(Architecture, nameof(Architecture));
        Require(Version, nameof(Version));
        Require(License, nameof(License));
        Require(SourceDescription, nameof(SourceDescription));
        ValidateRelativePath(ExecutableRelativePath);
        ValidateSha256(Sha256);
    }

    private static void Require(string value, string field)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new AsrRuntimeBundleManifestException(AsrRuntimeBundleManifestError.MissingRequiredField, field);
        }
    }

    private static void ValidateRelativePath(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0
            || Path.IsPathRooted(trimmed)
            || trimmed.Contains('\\', StringComparison.Ordinal)
            || trimmed.Contains(':', StringComparison.Ordinal))
        {
            throw new AsrRuntimeBundleManifestException(AsrRuntimeBundleManifestError.InvalidExecutableRelativePath, value);
        }
        var parts = trimmed.Split('/', StringSplitOptions.None);
        if (parts.Any(part => part.Length == 0 || part == "." || part == ".."))
        {
            throw new AsrRuntimeBundleManifestException(AsrRuntimeBundleManifestError.InvalidExecutableRelativePath, value);
        }
    }

    private static void ValidateSha256(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length != 64 || trimmed.Any(ch => !Uri.IsHexDigit(ch)))
        {
            throw new AsrRuntimeBundleManifestException(AsrRuntimeBundleManifestError.InvalidSha256, value);
        }
    }
}

public sealed record AsrTranscriptCacheEntry
{
    public required string CacheKey { get; init; }
    public required string AudioFingerprint { get; init; }
    public required string ModelId { get; init; }
    public string? LanguageCode { get; init; }
    public required string TranscriptPath { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
}

public static class AsrTranscriptMapper
{
    public static IReadOnlyList<SubtitleCueSourceFragment> SourceFragments(AsrTranscript transcript) =>
        transcript.Words
            .Select(word => new
            {
                Text = word.Text.Trim(),
                word.StartSeconds,
                word.EndSeconds,
            })
            .Where(word => word.Text.Length > 0
                && !double.IsNaN(word.StartSeconds)
                && !double.IsInfinity(word.StartSeconds)
                && !double.IsNaN(word.EndSeconds)
                && !double.IsInfinity(word.EndSeconds)
                && word.StartSeconds >= 0
                && word.EndSeconds >= word.StartSeconds)
            .Select(word => new SubtitleCueSourceFragment(word.StartSeconds, word.EndSeconds, word.Text))
            .ToList();

    public static IReadOnlyList<SubtitleCue> SourceCues(AsrTranscript transcript)
    {
        var fragments = SourceFragments(transcript);
        var cues = new List<SubtitleCue>();
        var current = new List<SubtitleCueSourceFragment>();

        void FlushCurrent()
        {
            if (current.Count == 0) return;
            var first = current[0];
            var last = current[^1];
            cues.Add(new SubtitleCue(
                cues.Count + 1,
                SrtTools.SecondsToSrtTime(first.StartSeconds),
                SrtTools.SecondsToSrtTime(Math.Max(last.EndSeconds, first.StartSeconds)),
                string.Join(" ", current.Select(fragment => fragment.Text)),
                current.ToList()));
            current.Clear();
        }

        foreach (var fragment in fragments)
        {
            if (current.Count > 0)
            {
                var duration = fragment.EndSeconds - current[0].StartSeconds;
                var visibleCharacters = SubtitleTimingPlanner.VisibleCharacters(
                    string.Join(" ", current.Select(item => item.Text).Append(fragment.Text)));
                if (duration > SubtitleTimingPlanner.NormalReadableCueSeconds || visibleCharacters > 42)
                {
                    FlushCurrent();
                }
            }

            current.Add(fragment);
            if (EndsSourceCueSentence(fragment.Text))
            {
                FlushCurrent();
            }
        }

        FlushCurrent();
        return cues;
    }

    public static string LocalAsrSourceSrtPath(string videoFile, string languageCode)
    {
        var directory = Path.GetDirectoryName(videoFile) ?? ".";
        var stem = Path.GetFileNameWithoutExtension(videoFile);
        var language = NormalizeLanguageCode(languageCode);
        return Path.Combine(directory, $"{stem}.local-asr.{language}.srt");
    }

    public static string WriteLocalAsrSourceSrt(AsrTranscript transcript, string videoFile)
    {
        var cues = SourceCues(transcript);
        if (cues.Count == 0)
        {
            throw new WhisperCppRecognizerException(WhisperCppRecognizerError.EmptyTranscript);
        }
        var output = LocalAsrSourceSrtPath(videoFile, transcript.LanguageCode);
        Directory.CreateDirectory(Path.GetDirectoryName(output) ?? ".");
        File.WriteAllText(output, SrtTools.SerializeSrt(cues), Encoding.UTF8);
        return output;
    }

    private static string NormalizeLanguageCode(string value)
    {
        var trimmed = value.Trim();
        return trimmed.Length == 0 ? "und" : trimmed;
    }

    private static bool EndsSourceCueSentence(string value)
    {
        var trimmed = value.Trim();
        return trimmed.Length > 0 && ".!?。！？".Contains(trimmed[^1]);
    }
}

public interface ILocalAsrSubtitleGenerator
{
    Task<string> GenerateSourceSubtitleAsync(
        string videoFile,
        string languageCode,
        TaskControlToken? control,
        Action<AsrProgress> progress,
        CancellationToken ct = default);
}

public static class AsrPromptBuilder
{
    public static string? DefaultPrompt(string videoPath, string languageCode)
    {
        var title = Path.GetFileNameWithoutExtension(videoPath).Trim();
        var language = languageCode.Trim();
        var parts = new List<string>();
        if (title.Length > 0)
        {
            parts.Add($"title={title}");
        }
        if (language.Length > 0 && !string.Equals(language, "auto", StringComparison.OrdinalIgnoreCase))
        {
            parts.Add($"language={language}");
        }
        return parts.Count == 0 ? null : string.Join("; ", parts);
    }
}

public sealed record AsrAudioExtractionPlan
{
    public required string FfmpegPath { get; init; }
    public required string InputPath { get; init; }
    public required string OutputPath { get; init; }
    public required IReadOnlyList<string> Arguments { get; init; }

    public static AsrAudioExtractionPlan Create(string ffmpegPath, string inputPath, string outputPath) => new()
    {
        FfmpegPath = ffmpegPath,
        InputPath = inputPath,
        OutputPath = outputPath,
        Arguments =
        [
            "-y",
            "-i", inputPath,
            "-map", "0:a:0",
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            "-f", "wav",
            outputPath,
        ],
    };
}

public enum AsrAudioExtractorError
{
    ProcessFailed,
    MissingOutput,
}

public sealed class AsrAudioExtractorException(
    AsrAudioExtractorError reason,
    string? path = null,
    int? status = null,
    string? stderrTail = null)
    : Exception(reason.ToString())
{
    public AsrAudioExtractorError Reason { get; } = reason;
    public string? Path { get; } = path;
    public int? Status { get; } = status;
    public string? StderrTail { get; } = stderrTail;
}

public interface IAsrAudioExtractor
{
    Task<string> ExtractAudioAsync(
        AsrAudioExtractionPlan plan,
        TaskControlToken? control,
        Action<AsrProgress> progress,
        CancellationToken ct = default);
}

public sealed class ProcessAsrAudioExtractor : IAsrAudioExtractor
{
    public async Task<string> ExtractAudioAsync(
        AsrAudioExtractionPlan plan,
        TaskControlToken? control,
        Action<AsrProgress> progress,
        CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        if (control is not null) await control.GateAsync(ct).ConfigureAwait(false);
        Directory.CreateDirectory(Path.GetDirectoryName(plan.OutputPath) ?? ".");
        progress(new AsrProgress { Phase = AsrProgressPhase.AudioExtract, CompletedUnits = 0, TotalUnits = 1 });
        try
        {
            var result = await ProcessRunner.RunStreamingProcessAsync(
                plan.FfmpegPath,
                plan.Arguments,
                onStart: pid => control?.SetActivePid(pid),
                ct: ct).ConfigureAwait(false);
            if (result.Status != 0)
            {
                throw new AsrAudioExtractorException(
                    AsrAudioExtractorError.ProcessFailed,
                    status: result.Status,
                    stderrTail: result.StderrTail);
            }
        }
        finally
        {
            control?.SetActivePid(0);
        }
        if (!File.Exists(plan.OutputPath))
        {
            throw new AsrAudioExtractorException(AsrAudioExtractorError.MissingOutput, path: plan.OutputPath);
        }
        progress(new AsrProgress { Phase = AsrProgressPhase.AudioExtract, CompletedUnits = 1, TotalUnits = 1 });
        return plan.OutputPath;
    }
}

public sealed class WhisperCppLocalAsrSubtitleGenerator : ILocalAsrSubtitleGenerator
{
    private readonly string _ffmpegPath;
    private readonly string _workDirectoryPath;
    private readonly ISpeechRecognizer _recognizer;
    private readonly string _modelId;
    private readonly Func<string, string, string?>? _promptProvider;
    private readonly IAsrAudioExtractor _audioExtractor;

    public WhisperCppLocalAsrSubtitleGenerator(
        string ffmpegPath,
        string workDirectoryPath,
        ISpeechRecognizer recognizer,
        string modelId,
        Func<string, string, string?>? promptProvider = null,
        IAsrAudioExtractor? audioExtractor = null)
    {
        _ffmpegPath = ffmpegPath;
        _workDirectoryPath = workDirectoryPath;
        _recognizer = recognizer;
        _modelId = modelId;
        _promptProvider = promptProvider;
        _audioExtractor = audioExtractor ?? new ProcessAsrAudioExtractor();
    }

    public async Task<string> GenerateSourceSubtitleAsync(
        string videoFile,
        string languageCode,
        TaskControlToken? control,
        Action<AsrProgress> progress,
        CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        if (control is not null) await control.GateAsync(ct).ConfigureAwait(false);
        Directory.CreateDirectory(_workDirectoryPath);

        var prompt = _promptProvider?.Invoke(videoFile, languageCode);
        var audioPath = AudioPath(videoFile, languageCode);
        if (File.Exists(audioPath))
        {
            progress(new AsrProgress { Phase = AsrProgressPhase.AudioExtract, CompletedUnits = 1, TotalUnits = 1 });
        }
        else
        {
            var plan = AsrAudioExtractionPlan.Create(_ffmpegPath, videoFile, audioPath);
            await _audioExtractor.ExtractAudioAsync(plan, control, progress, ct).ConfigureAwait(false);
        }

        var request = new AsrRequest
        {
            AudioPath = audioPath,
            LanguageCode = languageCode,
            ModelId = _modelId,
            Prompt = prompt,
            VadEnabled = true,
            WordTimestamps = true,
            CacheKey = CacheKey(videoFile, languageCode, prompt),
        };
        var transcript = await _recognizer.TranscribeAsync(request, progress, control, ct).ConfigureAwait(false);
        progress(new AsrProgress { Phase = AsrProgressPhase.SubtitleSegment, CompletedUnits = 0, TotalUnits = 1 });
        var output = AsrTranscriptMapper.WriteLocalAsrSourceSrt(transcript, videoFile);
        progress(new AsrProgress { Phase = AsrProgressPhase.SubtitleSegment, CompletedUnits = 1, TotalUnits = 1 });
        return output;
    }

    private string AudioPath(string videoFile, string languageCode) =>
        Path.Combine(_workDirectoryPath, "audio", StableFileStem(AudioSeed(videoFile, languageCode)) + ".wav");

    private string CacheKey(string videoFile, string languageCode, string? prompt) =>
        "local-asr:" + StableFileStem(AudioSeed(videoFile, languageCode) + "\n" + (prompt ?? ""));

    private string AudioSeed(string videoFile, string languageCode)
    {
        var fullPath = Path.GetFullPath(videoFile);
        var info = new FileInfo(videoFile);
        var size = info.Exists ? info.Length.ToString(CultureInfo.InvariantCulture) : "unknown-size";
        var modifiedAt = info.Exists
            ? info.LastWriteTimeUtc.Ticks.ToString(CultureInfo.InvariantCulture)
            : "unknown-mtime";
        return string.Join('\n', [fullPath, languageCode, _modelId, size, modifiedAt]);
    }

    private static string StableFileStem(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
}

public static class LocalAsrGeneratorFactory
{
    public static ILocalAsrSubtitleGenerator? Create(
        AppSettings settings,
        Func<DateTimeOffset>? nowProvider = null) =>
        Create(
            settings,
            BinaryLocator.Locate("ffmpeg", "MOONGATE_FFMPEG_PATH"),
            AppSettings.SupportDirectory,
            nowProvider);

    public static ILocalAsrSubtitleGenerator? Create(
        AppSettings settings,
        string? ffmpegPath,
        string? supportDirectoryPath,
        Func<DateTimeOffset>? nowProvider = null)
    {
        if (!settings.LocalAsrEnabled) return null;
        var runtimePath = settings.LocalAsrRuntimePath.Trim();
        var modelPath = settings.LocalAsrModelPath.Trim();
        var modelId = settings.LocalAsrModelId.Trim();
        if (runtimePath.Length == 0 || modelPath.Length == 0 || modelId.Length == 0) return null;

        if (!IsExecutable(ffmpegPath) || !IsExecutable(runtimePath) || !File.Exists(modelPath))
        {
            return null;
        }
        if (!IsReadyModel(modelId, modelPath, supportDirectoryPath))
        {
            return null;
        }

        var asrDirectory = Path.Combine(supportDirectoryPath ?? AppSettings.SupportDirectory, "asr");
        var recognizer = new WhisperCppSpeechRecognizer(
            new AsrRuntimeInfo { ExecutablePath = runtimePath },
            modelPath,
            Path.Combine(asrDirectory, "transcripts-work"),
            new AsrTranscriptCacheStore(Path.Combine(asrDirectory, "cache")),
            nowProvider: nowProvider);
        return new WhisperCppLocalAsrSubtitleGenerator(
            ffmpegPath!,
            Path.Combine(asrDirectory, "work"),
            recognizer,
            modelId,
            AsrPromptBuilder.DefaultPrompt);
    }

    private static bool IsExecutable(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return false;
        if (OperatingSystem.IsWindows()) return true;
        try
        {
            var mode = File.GetUnixFileMode(path);
            const UnixFileMode executeBits =
                UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute;
            return (mode & executeBits) != 0;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsReadyModel(string modelId, string modelPath, string? supportDirectoryPath)
    {
        var model = AsrModelManifest.RecommendedWhisperCpp.Models
            .FirstOrDefault(candidate => string.Equals(candidate.Id, modelId, StringComparison.Ordinal));
        if (model is null) return true;

        try
        {
            var store = new AsrModelStore(Path.Combine(
                supportDirectoryPath ?? AppSettings.SupportDirectory,
                "asr",
                "models"));
            var status = store.Status(model);
            return status.IsInstalled
                && string.Equals(
                    Path.GetFullPath(modelPath),
                    Path.GetFullPath(status.InstalledPath),
                    PathComparison);
        }
        catch
        {
            return false;
        }
    }

    private static StringComparison PathComparison =>
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
}

public sealed record WhisperCppCommandPlan
{
    public required AsrRuntimeInfo Runtime { get; init; }
    public required string ModelPath { get; init; }
    public required AsrRequest Request { get; init; }
    public required string OutputBasePath { get; init; }
    public required IReadOnlyList<string> Arguments { get; init; }

    public string ExecutablePath => Runtime.ExecutablePath;

    public string OutputJsonPath => Path.ChangeExtension(OutputBasePath, ".json");

    public static WhisperCppCommandPlan Create(
        AsrRuntimeInfo runtime,
        string modelPath,
        AsrRequest request,
        string outputBasePath)
    {
        var normalizedOutputBase = WithoutExtension(outputBasePath);
        List<string> arguments =
        [
            "-m", modelPath,
            "-f", request.AudioPath,
            request.WordTimestamps ? "-ojf" : "-oj",
            "-of", normalizedOutputBase,
            "-pp",
        ];

        var languageCode = request.LanguageCode?.Trim();
        if (!string.IsNullOrEmpty(languageCode)
            && !string.Equals(languageCode, "auto", StringComparison.OrdinalIgnoreCase))
        {
            arguments.AddRange(["-l", languageCode]);
        }

        var prompt = request.Prompt?.Trim();
        if (!string.IsNullOrEmpty(prompt))
        {
            arguments.AddRange(["--prompt", prompt]);
        }

        return new WhisperCppCommandPlan
        {
            Runtime = runtime,
            ModelPath = modelPath,
            Request = request,
            OutputBasePath = normalizedOutputBase,
            Arguments = arguments,
        };
    }

    private static string WithoutExtension(string path)
    {
        var directory = Path.GetDirectoryName(path);
        var fileName = Path.GetFileNameWithoutExtension(path);
        return string.IsNullOrEmpty(directory) ? fileName : Path.Combine(directory, fileName);
    }
}

public sealed record AsrCommandResult
{
    public required int Status { get; init; }
    public required string StderrTail { get; init; }
}

public interface IAsrCommandRunner
{
    Task<AsrCommandResult> RunWhisperAsync(
        WhisperCppCommandPlan plan,
        TaskControlToken? control,
        Action<string> onLine,
        CancellationToken ct = default);
}

public sealed class ProcessAsrCommandRunner : IAsrCommandRunner
{
    public async Task<AsrCommandResult> RunWhisperAsync(
        WhisperCppCommandPlan plan,
        TaskControlToken? control,
        Action<string> onLine,
        CancellationToken ct = default)
    {
        using var process = new Process { StartInfo = MakeStartInfo(plan.ExecutablePath, plan.Arguments) };
        try
        {
            process.Start();
        }
        catch (Exception e)
        {
            throw new InvalidOperationException($"Could not start whisper.cpp runtime: {e.Message}", e);
        }
        process.StandardInput.Close();
        var pid = SafePid(process);
        if (ct.IsCancellationRequested)
        {
            ProcessTree.KillTree(pid);
        }
        else
        {
            control?.SetActivePid(pid);
        }

        var stderrTail = new StringBuilder();
        var stderrLock = new object();
        const int stderrLimit = 16 * 1024;

        var stdoutTask = Task.Run(async () =>
        {
            while (await process.StandardOutput.ReadLineAsync(CancellationToken.None).ConfigureAwait(false) is { } line)
            {
                if (line.Length > 0) onLine(line);
            }
        }, CancellationToken.None);
        var stderrTask = Task.Run(async () =>
        {
            while (await process.StandardError.ReadLineAsync(CancellationToken.None).ConfigureAwait(false) is { } line)
            {
                lock (stderrLock)
                {
                    stderrTail.AppendLine(line);
                    if (stderrTail.Length > stderrLimit)
                    {
                        stderrTail.Remove(0, stderrTail.Length - stderrLimit);
                    }
                }
                if (line.Length > 0) onLine(line);
            }
        }, CancellationToken.None);

        await using var cancelReg = ct.Register(() => ProcessTree.KillTree(pid)).ConfigureAwait(false);
        await process.WaitForExitAsync(CancellationToken.None).ConfigureAwait(false);
        control?.SetActivePid(0);
        await Task.WhenAny(
            Task.WhenAll(stdoutTask, stderrTask),
            Task.Delay(TimeSpan.FromSeconds(10), CancellationToken.None)).ConfigureAwait(false);

        ct.ThrowIfCancellationRequested();
        if (control?.IsCancelled == true) throw MoongateException.Cancelled();
        string tail;
        lock (stderrLock) tail = stderrTail.ToString();
        return new AsrCommandResult { Status = process.ExitCode, StderrTail = tail };
    }

    private static ProcessStartInfo MakeStartInfo(string executable, IReadOnlyList<string> arguments)
    {
        var psi = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var argument in arguments)
        {
            psi.ArgumentList.Add(argument);
        }
        return psi;
    }

    private static int SafePid(Process process)
    {
        try { return process.Id; } catch { return 0; }
    }
}

public enum WhisperCppRecognizerError
{
    MissingRuntime,
    MissingModel,
    ProcessFailed,
    MissingTranscriptJson,
    EmptyTranscript,
    InvalidTranscriptJson,
}

public sealed class WhisperCppRecognizerException : Exception
{
    public WhisperCppRecognizerException(
        WhisperCppRecognizerError reason,
        string? path = null,
        int? status = null,
        string? stderrTail = null,
        string? detail = null)
        : base(detail ?? reason.ToString())
    {
        Reason = reason;
        Path = path;
        Status = status;
        StderrTail = stderrTail;
    }

    public WhisperCppRecognizerError Reason { get; }
    public string? Path { get; }
    public int? Status { get; }
    public string? StderrTail { get; }
}

public static class WhisperCppProgressParser
{
    public static AsrProgress? Parse(string line)
    {
        var match = Regex.Match(line, @"([0-9]+(?:\.[0-9]+)?)\s*%");
        if (!match.Success) return null;
        if (!double.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
            || double.IsNaN(value)
            || double.IsInfinity(value))
        {
            return null;
        }
        return new AsrProgress
        {
            Phase = AsrProgressPhase.SpeechRecognition,
            CompletedUnits = Math.Clamp(value, 0, 100),
            TotalUnits = 100,
        };
    }
}

public sealed class WhisperCppJsonTranscriptParser
{
    public AsrTranscript Parse(
        byte[] data,
        AsrRequest request,
        string transcriptId,
        DateTimeOffset? createdAt = null)
    {
        using var document = ParseDocument(data);
        var root = document.RootElement;
        var languageCode = LanguageCode(root, request);
        var languageConfidence = LanguageConfidence(root);
        var words = new List<AsrWord>();
        double? maxEnd = null;

        if (TryGetArray(root, "transcription", out var segments)
            || TryGetArray(root, "segments", out segments))
        {
            foreach (var segment in segments.EnumerateArray())
            {
                if (TryInterval(segment, offsetsAreMilliseconds: true, out var segmentStart, out var segmentEnd))
                {
                    maxEnd = Math.Max(maxEnd ?? segmentEnd, segmentEnd);
                }

                var tokenWords = ParseTokenWords(segment);
                if (tokenWords.Count == 0)
                {
                    if (ParseSegmentWord(segment) is { } fallback)
                    {
                        words.Add(fallback);
                        maxEnd = Math.Max(maxEnd ?? fallback.EndSeconds, fallback.EndSeconds);
                    }
                }
                else
                {
                    words.AddRange(tokenWords);
                    foreach (var word in tokenWords)
                    {
                        maxEnd = Math.Max(maxEnd ?? word.EndSeconds, word.EndSeconds);
                    }
                }
            }
        }

        if (words.Count == 0)
        {
            throw new WhisperCppRecognizerException(WhisperCppRecognizerError.EmptyTranscript);
        }
        return new AsrTranscript
        {
            Id = transcriptId,
            LanguageCode = languageCode,
            LanguageConfidence = languageConfidence,
            DurationSeconds = maxEnd,
            Words = words,
            SourceModelId = request.ModelId,
            CreatedAt = createdAt ?? DateTimeOffset.UtcNow,
        };
    }

    private static JsonDocument ParseDocument(byte[] data)
    {
        try
        {
            return JsonDocument.Parse(data);
        }
        catch (JsonException e)
        {
            throw new WhisperCppRecognizerException(
                WhisperCppRecognizerError.InvalidTranscriptJson,
                detail: e.Message);
        }
    }

    private static string LanguageCode(JsonElement root, AsrRequest request)
    {
        foreach (var candidate in new[]
        {
            TryGetObject(root, "result", out var result) && TryGetString(result, "language", out var resultLanguage)
                ? resultLanguage
                : null,
            TryGetObject(root, "params", out var parameters) && TryGetString(parameters, "language", out var parameterLanguage)
                ? parameterLanguage
                : null,
            request.LanguageCode,
        })
        {
            var value = candidate?.Trim();
            if (!string.IsNullOrEmpty(value)) return value;
        }
        return "auto";
    }

    private static double? LanguageConfidence(JsonElement root)
    {
        if (!TryGetObject(root, "result", out var result)) return null;
        return Number(result, ["language_probability", "languageProbability", "language_confidence", "languageConfidence"]);
    }

    private static IReadOnlyList<AsrWord> ParseTokenWords(JsonElement segment)
    {
        if (!TryGetArray(segment, "tokens", out var tokens)
            && !TryGetArray(segment, "words", out tokens))
        {
            return [];
        }

        var words = new List<AsrWord>();
        foreach (var token in tokens.EnumerateArray())
        {
            if (!TryCleanText(token, out var text)
                || !TryInterval(token, offsetsAreMilliseconds: true, out var start, out var end))
            {
                continue;
            }
            words.Add(new AsrWord
            {
                Text = text,
                StartSeconds = start,
                EndSeconds = end,
                Probability = Number(token, ["p", "probability", "confidence"]),
            });
        }
        return words;
    }

    private static AsrWord? ParseSegmentWord(JsonElement segment)
    {
        if (!TryCleanText(segment, out var text)
            || !TryInterval(segment, offsetsAreMilliseconds: true, out var start, out var end))
        {
            return null;
        }
        return new AsrWord
        {
            Text = text,
            StartSeconds = start,
            EndSeconds = end,
            Probability = Number(segment, ["p", "probability", "confidence"]),
        };
    }

    private static bool TryInterval(
        JsonElement element,
        bool offsetsAreMilliseconds,
        out double start,
        out double end)
    {
        if (TryGetObject(element, "offsets", out var offsets)
            && TrySeconds(offsets, "from", offsetsAreMilliseconds, out start)
            && TrySeconds(offsets, "to", offsetsAreMilliseconds, out end)
            && end >= start)
        {
            return true;
        }
        if (TryGetObject(element, "timestamps", out var timestamps)
            && TrySeconds(timestamps, "from", valuesAreMilliseconds: false, out start)
            && TrySeconds(timestamps, "to", valuesAreMilliseconds: false, out end)
            && end >= start)
        {
            return true;
        }
        if ((TrySeconds(element, "start", valuesAreMilliseconds: false, out start)
                || TrySeconds(element, "startSeconds", valuesAreMilliseconds: false, out start))
            && (TrySeconds(element, "end", valuesAreMilliseconds: false, out end)
                || TrySeconds(element, "endSeconds", valuesAreMilliseconds: false, out end))
            && end >= start)
        {
            return true;
        }
        start = 0;
        end = 0;
        return false;
    }

    private static bool TrySeconds(JsonElement element, string property, bool valuesAreMilliseconds, out double seconds)
    {
        seconds = 0;
        if (!element.TryGetProperty(property, out var value)) return false;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number))
        {
            seconds = valuesAreMilliseconds ? number / 1000 : number;
            return true;
        }
        if (value.ValueKind == JsonValueKind.String && value.GetString() is { } text)
        {
            text = text.Trim();
            if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out number))
            {
                seconds = valuesAreMilliseconds ? number / 1000 : number;
                return true;
            }
            var components = text.Replace(',', '.').Split(':');
            if (components.Length == 3
                && double.TryParse(components[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var hours)
                && double.TryParse(components[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var minutes)
                && double.TryParse(components[2], NumberStyles.Float, CultureInfo.InvariantCulture, out var secs))
            {
                seconds = hours * 3600 + minutes * 60 + secs;
                return true;
            }
        }
        return false;
    }

    private static bool TryCleanText(JsonElement element, out string text)
    {
        text = "";
        if (!TryGetString(element, "text", out var value)) return false;
        text = value.Trim();
        return text.Length > 0;
    }

    private static double? Number(JsonElement element, IReadOnlyList<string> keys)
    {
        foreach (var key in keys)
        {
            if (!element.TryGetProperty(key, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number)) return number;
            if (value.ValueKind == JsonValueKind.String
                && double.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out number))
            {
                return number;
            }
        }
        return null;
    }

    private static bool TryGetArray(JsonElement element, string property, out JsonElement value) =>
        element.TryGetProperty(property, out value) && value.ValueKind == JsonValueKind.Array;

    private static bool TryGetObject(JsonElement element, string property, out JsonElement value) =>
        element.TryGetProperty(property, out value) && value.ValueKind == JsonValueKind.Object;

    private static bool TryGetString(JsonElement element, string property, out string value)
    {
        value = "";
        if (!element.TryGetProperty(property, out var child) || child.ValueKind != JsonValueKind.String) return false;
        value = child.GetString() ?? "";
        return true;
    }
}

public sealed class WhisperCppSpeechRecognizer : ISpeechRecognizer
{
    private readonly AsrRuntimeInfo _runtime;
    private readonly string _modelPath;
    private readonly string _outputDirectoryPath;
    private readonly AsrTranscriptCacheStore? _cacheStore;
    private readonly IAsrCommandRunner _commandRunner;
    private readonly Func<DateTimeOffset> _nowProvider;
    private readonly WhisperCppJsonTranscriptParser _parser;

    public WhisperCppSpeechRecognizer(
        AsrRuntimeInfo runtime,
        string modelPath,
        string outputDirectoryPath,
        AsrTranscriptCacheStore? cacheStore = null,
        IAsrCommandRunner? commandRunner = null,
        Func<DateTimeOffset>? nowProvider = null,
        WhisperCppJsonTranscriptParser? parser = null)
    {
        _runtime = runtime;
        _modelPath = modelPath;
        _outputDirectoryPath = outputDirectoryPath;
        _cacheStore = cacheStore;
        _commandRunner = commandRunner ?? new ProcessAsrCommandRunner();
        _nowProvider = nowProvider ?? (() => DateTimeOffset.UtcNow);
        _parser = parser ?? new WhisperCppJsonTranscriptParser();
    }

    public Task<AsrReadiness> ReadinessAsync(AsrRequest request, CancellationToken ct = default)
    {
        if (!IsExecutable(_runtime.ExecutablePath))
        {
            return Task.FromResult(new AsrReadiness
            {
                Status = AsrReadinessStatus.MissingRuntime,
                ModelId = request.ModelId,
                Message = "whisper.cpp runtime is missing.",
            });
        }
        if (!File.Exists(_modelPath))
        {
            return Task.FromResult(new AsrReadiness
            {
                Status = AsrReadinessStatus.MissingModel,
                ModelId = request.ModelId,
                Message = "Whisper model is not installed.",
            });
        }
        return Task.FromResult(new AsrReadiness
        {
            Status = AsrReadinessStatus.Ready,
            ModelId = request.ModelId,
            Message = "Local speech recognition is ready.",
        });
    }

    public async Task<AsrTranscript> TranscribeAsync(
        AsrRequest request,
        Action<AsrProgress> progress,
        TaskControlToken? control = null,
        CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        if (control is not null) await control.GateAsync(ct).ConfigureAwait(false);
        if (!IsExecutable(_runtime.ExecutablePath))
        {
            throw new WhisperCppRecognizerException(WhisperCppRecognizerError.MissingRuntime, path: _runtime.ExecutablePath);
        }
        if (!File.Exists(_modelPath))
        {
            throw new WhisperCppRecognizerException(WhisperCppRecognizerError.MissingModel, path: _modelPath);
        }

        progress(new AsrProgress { Phase = AsrProgressPhase.SpeechRecognition, CompletedUnits = 0, TotalUnits = 1 });
        var audioFingerprint = "sha256:" + AsrModelStore.Sha256Hex(request.AudioPath);
        if (request.CacheKey is { } cacheKey
            && _cacheStore?.CachedTranscript(cacheKey, audioFingerprint, request.ModelId, request.LanguageCode) is { } cached)
        {
            progress(new AsrProgress { Phase = AsrProgressPhase.SpeechRecognition, CompletedUnits = 1, TotalUnits = 1 });
            return cached;
        }

        Directory.CreateDirectory(_outputDirectoryPath);
        var transcriptId = request.CacheKey ?? Guid.NewGuid().ToString("N");
        var outputBasePath = Path.Combine(_outputDirectoryPath, StableFileStem(transcriptId));
        var plan = WhisperCppCommandPlan.Create(_runtime, _modelPath, request, outputBasePath);
        var result = await _commandRunner.RunWhisperAsync(plan, control, line =>
        {
            if (WhisperCppProgressParser.Parse(line) is { } parsed)
            {
                progress(parsed);
            }
        }, ct).ConfigureAwait(false);

        ct.ThrowIfCancellationRequested();
        if (control?.IsCancelled == true) throw MoongateException.Cancelled();
        if (result.Status != 0)
        {
            throw new WhisperCppRecognizerException(
                WhisperCppRecognizerError.ProcessFailed,
                status: result.Status,
                stderrTail: result.StderrTail);
        }
        if (!File.Exists(plan.OutputJsonPath))
        {
            throw new WhisperCppRecognizerException(
                WhisperCppRecognizerError.MissingTranscriptJson,
                path: plan.OutputJsonPath);
        }

        var transcript = _parser.Parse(File.ReadAllBytes(plan.OutputJsonPath), request, transcriptId, _nowProvider());
        if (request.CacheKey is { } writeCacheKey)
        {
            _cacheStore?.Write(transcript, writeCacheKey, audioFingerprint, request.LanguageCode);
        }
        progress(new AsrProgress { Phase = AsrProgressPhase.SpeechRecognition, CompletedUnits = 1, TotalUnits = 1 });
        return transcript;
    }

    private static bool IsExecutable(string path)
    {
        if (!File.Exists(path)) return false;
        if (OperatingSystem.IsWindows()) return true;
        try
        {
            var mode = File.GetUnixFileMode(path);
            return (mode & (UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute)) != 0;
        }
        catch
        {
            return false;
        }
    }

    private static string StableFileStem(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
}

public sealed class AsrTranscriptCacheStore
{
    public string DirectoryPath { get; }

    public AsrTranscriptCacheStore(string directoryPath)
    {
        DirectoryPath = directoryPath;
    }

    public string EntryPath(string cacheKey) =>
        Path.Combine(DirectoryPath, StableFileStem(cacheKey) + ".entry.json");

    public string TranscriptPath(string cacheKey) =>
        Path.Combine(DirectoryPath, StableFileStem(cacheKey) + ".transcript.json");

    public AsrTranscriptCacheEntry Write(
        AsrTranscript transcript,
        string cacheKey,
        string audioFingerprint,
        string? languageCode = null,
        DateTimeOffset? createdAt = null)
    {
        Directory.CreateDirectory(DirectoryPath);
        var transcriptPath = TranscriptPath(cacheKey);
        var entryPath = EntryPath(cacheKey);
        WriteAtomically(JsonSerializer.SerializeToUtf8Bytes(transcript, AsrJson.Options), transcriptPath);
        var entry = new AsrTranscriptCacheEntry
        {
            CacheKey = cacheKey,
            AudioFingerprint = audioFingerprint,
            ModelId = transcript.SourceModelId,
            LanguageCode = NormalizeCacheLanguage(languageCode) ?? NormalizeCacheLanguage(transcript.LanguageCode),
            TranscriptPath = transcriptPath,
            CreatedAt = createdAt ?? DateTimeOffset.UtcNow,
        };
        WriteAtomically(JsonSerializer.SerializeToUtf8Bytes(entry, AsrJson.Options), entryPath);
        return entry;
    }

    public AsrTranscriptCacheEntry? ReadEntry(string cacheKey)
    {
        var path = EntryPath(cacheKey);
        return File.Exists(path)
            ? JsonSerializer.Deserialize<AsrTranscriptCacheEntry>(File.ReadAllBytes(path), AsrJson.Options)
            : null;
    }

    public AsrTranscript ReadTranscript(AsrTranscriptCacheEntry entry) =>
        JsonSerializer.Deserialize<AsrTranscript>(File.ReadAllBytes(entry.TranscriptPath), AsrJson.Options)
            ?? throw new InvalidDataException("ASR transcript cache entry could not be decoded.");

    public AsrTranscript? CachedTranscript(
        string cacheKey,
        string audioFingerprint,
        string modelId,
        string? languageCode)
    {
        var entry = ReadEntry(cacheKey);
        var requestedLanguageCode = NormalizeCacheLanguage(languageCode);
        if (entry is null
            || entry.AudioFingerprint != audioFingerprint
            || entry.ModelId != modelId
            || (requestedLanguageCode is not null && NormalizeCacheLanguage(entry.LanguageCode) != requestedLanguageCode)
            || !File.Exists(entry.TranscriptPath))
        {
            return null;
        }

        return ReadTranscript(entry);
    }

    private static void WriteAtomically(byte[] data, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? ".");
        var temp = Path.Combine(
            Path.GetDirectoryName(path) ?? ".",
            "." + Path.GetFileName(path) + "." + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            File.WriteAllBytes(temp, data);
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp)) File.Delete(temp);
        }
    }

    private static string StableFileStem(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

    private static string? NormalizeCacheLanguage(string? languageCode)
    {
        var trimmed = languageCode?.Trim().ToLowerInvariant();
        return string.IsNullOrEmpty(trimmed) || trimmed == "auto" ? null : trimmed;
    }
}

public sealed record AsrRuntimeInfo
{
    public string Provider { get; init; } = "whisper.cpp";
    public required string ExecutablePath { get; init; }
}

public sealed class AsrRuntimeLocator
{
    public const string RuntimeManifestFileName = "asr-runtime-manifest.json";

    public static string CurrentPlatform
    {
        get
        {
            if (OperatingSystem.IsWindows()) return "windows";
            if (OperatingSystem.IsMacOS()) return "macos";
            if (OperatingSystem.IsLinux()) return "linux";
            return "unknown";
        }
    }

    public static string CurrentArchitecture =>
        RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => "x64",
            Architecture.Arm64 => "arm64",
            Architecture.X86 => "x86",
            Architecture.Arm => "arm",
            var architecture => architecture.ToString().ToLowerInvariant(),
        };

    private readonly IReadOnlyList<string> _candidateNames;
    private readonly IReadOnlyList<string> _extraSearchPaths;
    private readonly string? _environmentPath;
    private readonly string _runtimeManifestFileName;

    public AsrRuntimeLocator(
        IReadOnlyList<string>? candidateNames = null,
        IReadOnlyList<string>? extraSearchPaths = null,
        string? environmentPath = null,
        string runtimeManifestFileName = RuntimeManifestFileName)
    {
        _candidateNames = candidateNames ?? ["whisper-cli.exe", "whisper-cli"];
        _extraSearchPaths = extraSearchPaths ?? [];
        _environmentPath = environmentPath ?? Environment.GetEnvironmentVariable("PATH");
        _runtimeManifestFileName = runtimeManifestFileName;
    }

    public AsrRuntimeInfo? Locate()
    {
        var manifestRoots = ManifestRootsWithFile().ToArray();
        foreach (var root in manifestRoots)
        {
            var runtime = RuntimeFromManifest(root);
            if (runtime is not null) return runtime;
        }
        foreach (var path in SearchCandidates())
        {
            if (IsInsideAny(path, manifestRoots)) continue;
            if (IsExecutable(path)) return new AsrRuntimeInfo { ExecutablePath = path };
        }
        return null;
    }

    private IEnumerable<string> ManifestRootsWithFile()
    {
        var seen = new HashSet<string>(PathComparer);
        foreach (var path in _extraSearchPaths)
        {
            if (!Directory.Exists(path)) continue;
            var root = NormalizeDirectoryPath(path);
            if (!File.Exists(Path.Combine(root, _runtimeManifestFileName))) continue;
            if (seen.Add(root)) yield return root;
        }
    }

    private AsrRuntimeInfo? RuntimeFromManifest(string directory)
    {
        try
        {
            var manifest = AsrRuntimeBundleManifest.FromJson(
                File.ReadAllText(Path.Combine(directory, _runtimeManifestFileName)));
            foreach (var runtime in manifest.Runtimes.Where(MatchesCurrentRuntime))
            {
                try
                {
                    return runtime.VerifiedRuntimeInfoUnder(directory);
                }
                catch (AsrRuntimeBundleManifestException)
                {
                    // Keep searching matching entries, but do not fall back to bare files from this bundle root.
                }
            }
        }
        catch (Exception error) when (
            error is IOException
                or UnauthorizedAccessException
                or JsonException
                or AsrRuntimeBundleManifestException)
        {
            return null;
        }
        return null;
    }

    private IEnumerable<string> SearchCandidates()
    {
        foreach (var path in _extraSearchPaths)
        {
            if (Directory.Exists(path))
            {
                foreach (var name in _candidateNames) yield return Path.Combine(path, name);
            }
            else
            {
                yield return path;
            }
        }

        foreach (var dir in (_environmentPath ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var name in _candidateNames) yield return Path.Combine(dir, name);
        }
    }

    private static bool IsExecutable(string path)
    {
        if (!IsWhisperCliCandidate(path)) return false;
        if (!File.Exists(path)) return false;
        if (OperatingSystem.IsWindows()) return true;
        try
        {
            var mode = File.GetUnixFileMode(path);
            return (mode & (UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute)) != 0;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsWhisperCliCandidate(string path)
    {
        var fileName = Path.GetFileName(path);
        return string.Equals(fileName, "whisper-cli", StringComparison.OrdinalIgnoreCase)
            || string.Equals(fileName, "whisper-cli.exe", StringComparison.OrdinalIgnoreCase);
    }

    private static bool MatchesCurrentRuntime(AsrRuntimeBundleInfo runtime) =>
        string.Equals(runtime.Platform, CurrentPlatform, StringComparison.OrdinalIgnoreCase)
            && string.Equals(runtime.Architecture, CurrentArchitecture, StringComparison.OrdinalIgnoreCase);

    private static bool IsInsideAny(string path, IReadOnlyList<string> roots) =>
        roots.Any(root => IsInside(path, root));

    private static bool IsInside(string path, string root)
    {
        var normalizedPath = Path.GetFullPath(path);
        var normalizedRoot = NormalizeDirectoryPath(root);
        if (string.Equals(normalizedPath, normalizedRoot, PathComparison)) return true;
        return normalizedPath.StartsWith(
            normalizedRoot + Path.DirectorySeparatorChar,
            PathComparison);
    }

    private static string NormalizeDirectoryPath(string path)
    {
        var fullPath = Path.GetFullPath(path);
        var root = Path.GetPathRoot(fullPath);
        if (string.Equals(fullPath, root, PathComparison)) return fullPath;
        return fullPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static StringComparison PathComparison =>
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    private static StringComparer PathComparer =>
        OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
}

public enum AsrModelInstallState
{
    NotInstalled,
    Installed,
    BadHash,
    InsufficientDiskSpace,
}

public enum AsrModelStoreError
{
    InvalidModelFileName,
}

public sealed class AsrModelStoreException(AsrModelStoreError reason, string modelFileName)
    : Exception(reason.ToString())
{
    public AsrModelStoreError Reason { get; } = reason;
    public string ModelFileName { get; } = modelFileName;
}

public sealed record AsrModelStatus
{
    public required string ModelId { get; init; }
    public required AsrModelInstallState State { get; init; }
    public required string InstalledPath { get; init; }
    public required string ExpectedSha256 { get; init; }
    public string? ActualSha256 { get; init; }
    public required long SizeBytes { get; init; }
    public long? AvailableBytes { get; init; }
    public bool IsInstalled => State == AsrModelInstallState.Installed;
}

public sealed class AsrModelStore
{
    private readonly Func<string, long?> _availableBytesProvider;

    public string DirectoryPath { get; }

    public AsrModelStore(string directoryPath, Func<string, long?>? availableBytesProvider = null)
    {
        DirectoryPath = directoryPath;
        _availableBytesProvider = availableBytesProvider ?? DefaultAvailableBytes;
    }

    public string InstalledPath(AsrModelInfo model) => Path.Combine(DirectoryPath, model.FileName);

    public string StagedPath(AsrModelInfo model) => Path.Combine(DirectoryPath, "." + model.FileName + ".download");

    public AsrModelStatus Status(AsrModelInfo model)
    {
        Directory.CreateDirectory(DirectoryPath);
        ValidateFileName(model.FileName);
        var path = InstalledPath(model);
        var availableBytes = _availableBytesProvider(DirectoryPath);
        if (!File.Exists(path))
        {
            var state = availableBytes is { } available && available < model.SizeBytes
                ? AsrModelInstallState.InsufficientDiskSpace
                : AsrModelInstallState.NotInstalled;
            return new AsrModelStatus
            {
                ModelId = model.Id,
                State = state,
                InstalledPath = path,
                ExpectedSha256 = model.Sha256,
                SizeBytes = model.SizeBytes,
                AvailableBytes = availableBytes,
            };
        }

        var actual = Sha256Hex(path);
        return new AsrModelStatus
        {
            ModelId = model.Id,
            State = string.Equals(actual, model.Sha256, StringComparison.OrdinalIgnoreCase)
                ? AsrModelInstallState.Installed
                : AsrModelInstallState.BadHash,
            InstalledPath = path,
            ExpectedSha256 = model.Sha256,
            ActualSha256 = actual,
            SizeBytes = model.SizeBytes,
            AvailableBytes = availableBytes,
        };
    }

    public void Delete(AsrModelInfo model)
    {
        ValidateFileName(model.FileName);
        foreach (var path in new[] { InstalledPath(model), StagedPath(model) })
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    public static string Sha256Hex(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static long? DefaultAvailableBytes(string directoryPath)
    {
        var root = Path.GetPathRoot(Path.GetFullPath(directoryPath));
        if (string.IsNullOrWhiteSpace(root)) return null;
        try
        {
            return new DriveInfo(root).AvailableFreeSpace;
        }
        catch
        {
            return null;
        }
    }

    private static void ValidateFileName(string fileName)
    {
        if (string.IsNullOrEmpty(fileName)
            || fileName is "." or ".."
            || fileName != Path.GetFileName(fileName)
            || fileName.Contains('/')
            || fileName.Contains('\\'))
        {
            throw new AsrModelStoreException(AsrModelStoreError.InvalidModelFileName, fileName);
        }
    }
}

public enum AsrModelCatalogError
{
    UnknownModelId,
}

public enum AsrModelInstallerError
{
    UnknownModelId,
    InsufficientDiskSpace,
    MissingDownloadedFile,
    HashMismatch,
}

public sealed class AsrModelCatalogException(AsrModelCatalogError reason, string modelId)
    : Exception(reason.ToString())
{
    public AsrModelCatalogError Reason { get; } = reason;
    public string ModelId { get; } = modelId;
}

public sealed class AsrModelInstallerException(
    AsrModelInstallerError reason,
    string modelId,
    string? path = null,
    string? expectedSha256 = null,
    string? actualSha256 = null,
    long? availableBytes = null,
    long? requiredBytes = null)
    : Exception(MessageFor(reason, modelId, path, expectedSha256, actualSha256, availableBytes, requiredBytes))
{
    public AsrModelInstallerError Reason { get; } = reason;
    public string ModelId { get; } = modelId;
    public string? Path { get; } = path;
    public string? ExpectedSha256 { get; } = expectedSha256;
    public string? ActualSha256 { get; } = actualSha256;
    public long? AvailableBytes { get; } = availableBytes;
    public long? RequiredBytes { get; } = requiredBytes;

    private static string MessageFor(
        AsrModelInstallerError reason,
        string modelId,
        string? path,
        string? expectedSha256,
        string? actualSha256,
        long? availableBytes,
        long? requiredBytes) =>
        reason switch
        {
            AsrModelInstallerError.UnknownModelId =>
                $"Unknown local ASR model ID: {modelId}.",
            AsrModelInstallerError.InsufficientDiskSpace =>
                $"Not enough disk space to install local ASR model {modelId}. Required: {FormatBytes(requiredBytes)}; available: {FormatBytes(availableBytes)}.",
            AsrModelInstallerError.MissingDownloadedFile =>
                $"Local ASR model download finished, but no file was found at {path ?? "(unknown path)"}.",
            AsrModelInstallerError.HashMismatch =>
                $"Local ASR model {modelId} failed SHA-256 verification. Expected {expectedSha256 ?? "(unknown)"}, got {actualSha256 ?? "(unknown)"}.",
            _ => reason.ToString(),
        };

    private static string FormatBytes(long? bytes) =>
        bytes is { } value ? $"{value:N0} bytes" : "unknown";
}

public interface IAsrModelDownloadClient
{
    Task DownloadModelAsync(
        AsrModelInfo model,
        string destinationPath,
        Action<AsrProgress> progress,
        CancellationToken ct = default);
}

public sealed class HttpAsrModelDownloadClient : IAsrModelDownloadClient, IDisposable
{
    private readonly HttpClient _client;
    private readonly bool _ownsClient;

    public HttpAsrModelDownloadClient(HttpClient? client = null)
    {
        _client = client ?? new HttpClient();
        _ownsClient = client is null;
    }

    public async Task DownloadModelAsync(
        AsrModelInfo model,
        string destinationPath,
        Action<AsrProgress> progress,
        CancellationToken ct = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath) ?? ".");
        if (File.Exists(destinationPath)) File.Delete(destinationPath);

        using var response = await _client.GetAsync(
            model.DownloadUrl,
            HttpCompletionOption.ResponseHeadersRead,
            ct).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        var totalBytes = response.Content.Headers.ContentLength ?? model.SizeBytes;
        progress(new AsrProgress
        {
            Phase = AsrProgressPhase.ModelDownload,
            CompletedUnits = 0,
            TotalUnits = totalBytes,
        });

        await using var input = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        await using var output = File.Create(destinationPath);
        var buffer = new byte[64 * 1024];
        long receivedBytes = 0;
        while (true)
        {
            var read = await input.ReadAsync(buffer.AsMemory(0, buffer.Length), ct).ConfigureAwait(false);
            if (read <= 0) break;
            await output.WriteAsync(buffer.AsMemory(0, read), ct).ConfigureAwait(false);
            receivedBytes += read;
            progress(new AsrProgress
            {
                Phase = AsrProgressPhase.ModelDownload,
                CompletedUnits = receivedBytes,
                TotalUnits = totalBytes,
            });
        }
    }

    public void Dispose()
    {
        if (_ownsClient) _client.Dispose();
    }
}

public sealed record AsrModelCatalogEntry
{
    public required AsrModelInfo Model { get; init; }
    public required AsrModelStatus Status { get; init; }

    public string Id => Model.Id;
    public string DisplayName => Model.DisplayName;
    public string FileName => Model.FileName;
    public string DownloadUrl => Model.DownloadUrl;
    public long SizeBytes => Model.SizeBytes;
    public string Sha256 => Model.Sha256;
    public int MemoryRequiredMb => Model.MemoryRequiredMb;
    public string License => Model.License;
    public string SourceDescription => Model.SourceDescription;
    public AsrModelInstallState InstallState => Status.State;
    public string InstalledPath => Status.InstalledPath;
    public bool IsInstalled => Status.IsInstalled;
    public bool NeedsUserDownloadConsent => !Status.IsInstalled;
}

public sealed class AsrModelCatalog
{
    private readonly IReadOnlyDictionary<string, AsrModelInfo> _modelsById;
    private readonly AsrModelStore _store;

    public AsrModelCatalog(AsrModelManifest manifest, AsrModelStore store)
    {
        _store = store;
        Entries = manifest.Models
            .Select(model => new AsrModelCatalogEntry
            {
                Model = model,
                Status = store.Status(model),
            })
            .ToList();
        _modelsById = manifest.Models.ToDictionary(model => model.Id, StringComparer.Ordinal);
    }

    public IReadOnlyList<AsrModelCatalogEntry> Entries { get; }

    public AsrModelCatalogEntry? Entry(string id) =>
        Entries.FirstOrDefault(entry => string.Equals(entry.Id, id, StringComparison.Ordinal));

    public AsrModelInfo DeleteModel(string id)
    {
        if (!_modelsById.TryGetValue(id, out var model))
        {
            throw new AsrModelCatalogException(AsrModelCatalogError.UnknownModelId, id);
        }
        _store.Delete(model);
        return model;
    }
}

public sealed class AsrModelInstaller
{
    private readonly IReadOnlyDictionary<string, AsrModelInfo> _modelsById;
    private readonly AsrModelStore _store;
    private readonly IAsrModelDownloadClient _downloader;

    public AsrModelInstaller(
        AsrModelManifest manifest,
        AsrModelStore store,
        IAsrModelDownloadClient? downloader = null)
    {
        _modelsById = manifest.Models.ToDictionary(model => model.Id, StringComparer.Ordinal);
        _store = store;
        _downloader = downloader ?? new HttpAsrModelDownloadClient();
    }

    public async Task<AsrModelStatus> InstallModelAsync(
        string id,
        Action<AsrProgress> progress,
        CancellationToken ct = default)
    {
        if (!_modelsById.TryGetValue(id, out var model))
        {
            throw new AsrModelInstallerException(AsrModelInstallerError.UnknownModelId, id);
        }

        var currentStatus = _store.Status(model);
        if (currentStatus.State == AsrModelInstallState.Installed)
        {
            progress(new AsrProgress
            {
                Phase = AsrProgressPhase.ModelDownload,
                CompletedUnits = model.SizeBytes,
                TotalUnits = model.SizeBytes,
            });
            return currentStatus;
        }
        if (currentStatus.State == AsrModelInstallState.InsufficientDiskSpace)
        {
            throw new AsrModelInstallerException(
                AsrModelInstallerError.InsufficientDiskSpace,
                model.Id,
                availableBytes: currentStatus.AvailableBytes,
                requiredBytes: model.SizeBytes);
        }

        var stagedPath = _store.StagedPath(model);
        var installedPath = _store.InstalledPath(model);
        if (File.Exists(stagedPath)) File.Delete(stagedPath);

        try
        {
            await _downloader.DownloadModelAsync(model, stagedPath, progress, ct).ConfigureAwait(false);
            if (!File.Exists(stagedPath))
            {
                throw new AsrModelInstallerException(
                    AsrModelInstallerError.MissingDownloadedFile,
                    model.Id,
                    path: stagedPath);
            }

            var actualSha256 = AsrModelStore.Sha256Hex(stagedPath);
            if (!string.Equals(actualSha256, model.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                if (File.Exists(stagedPath)) File.Delete(stagedPath);
                throw new AsrModelInstallerException(
                    AsrModelInstallerError.HashMismatch,
                    model.Id,
                    path: stagedPath,
                    expectedSha256: model.Sha256,
                    actualSha256: actualSha256);
            }

            if (File.Exists(installedPath)) File.Delete(installedPath);
            File.Move(stagedPath, installedPath, overwrite: true);
            progress(new AsrProgress
            {
                Phase = AsrProgressPhase.ModelDownload,
                CompletedUnits = model.SizeBytes,
                TotalUnits = model.SizeBytes,
            });
            return _store.Status(model);
        }
        catch
        {
            if (File.Exists(stagedPath)) File.Delete(stagedPath);
            throw;
        }
    }
}
