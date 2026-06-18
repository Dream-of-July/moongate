namespace Moongate.Core;

/// <summary>单个依赖组件的健康状态（DEP-WIN-003：不再只看文件是否存在）。</summary>
public enum DependencyStatus
{
    /// <summary>可执行且具备所需能力。</summary>
    Ok,
    /// <summary>文件缺失或为零字节/截断。</summary>
    Missing,
    /// <summary>文件在，但无法执行（架构不符/损坏，--version 失败或超时）。</summary>
    Corrupt,
    /// <summary>能运行但缺少必要能力（如 ffmpeg 不含 subtitles 滤镜，无法烧录字幕）。</summary>
    RunnableButMissingCapability,
}

/// <summary>一个组件的体检结果。</summary>
public sealed record DependencyHealthResult(string Component, DependencyStatus Status, string? Version);

/// <summary>
/// 依赖组件结构化健康检查：跑 --version / -filters 判定可执行性与能力，而不是只 File.Exists。
/// 进程执行通过可注入的 runner 完成，便于单测；纯解析（版本号、能力探测）与执行解耦。
/// </summary>
public static class DependencyHealth
{
    /// <summary>进程执行抽象：返回退出码与 stdout（合并 stderr）。超时/启动失败应返回非 0。</summary>
    public delegate Task<(int Exit, string Output)> ProcessRunner(
        string executable, IReadOnlyList<string> arguments, CancellationToken ct);

    private static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(8);

    /// <summary>默认 runner：复用 Core 的 ProcessRunner（合并 stdout+stderr，带超时）。</summary>
    internal static async Task<(int Exit, string Output)> DefaultRunner(
        string executable, IReadOnlyList<string> arguments, CancellationToken ct)
    {
        try
        {
            var output = await Moongate.Core.ProcessRunner
                .RunProcessAsync(executable, arguments, ProbeTimeout, ct).ConfigureAwait(false);
            if (output.TimedOut) return (-1, output.Stdout + output.Stderr);
            return (output.Status, output.Stdout + "\n" + output.Stderr);
        }
        catch (Exception e)
        {
            return (-1, e.Message);
        }
    }

    /// <summary>体检全部受管组件。runner 为空用默认 runner。</summary>
    public static async Task<IReadOnlyList<DependencyHealthResult>> CheckAsync(
        string binDirectory, ProcessRunner? runner = null, CancellationToken ct = default)
    {
        runner ??= DefaultRunner;
        var results = new List<DependencyHealthResult>();

        results.Add(await CheckExecutableAsync(
            "yt-dlp", Path.Combine(binDirectory, "yt-dlp.exe"), ["--version"], runner, ct).ConfigureAwait(false));

        results.Add(await CheckFfmpegAsync(binDirectory, runner, ct).ConfigureAwait(false));

        results.Add(await CheckExecutableAsync(
            "deno", Path.Combine(binDirectory, "deno.exe"), ["--version"], runner, ct).ConfigureAwait(false));

        return results;
    }

    private static async Task<DependencyHealthResult> CheckExecutableAsync(
        string component, string path, IReadOnlyList<string> versionArgs, ProcessRunner runner, CancellationToken ct)
    {
        if (!FileLooksPresent(path)) return new DependencyHealthResult(component, DependencyStatus.Missing, null);
        var (exit, output) = await runner(path, versionArgs, ct).ConfigureAwait(false);
        if (exit != 0) return new DependencyHealthResult(component, DependencyStatus.Corrupt, null);
        return new DependencyHealthResult(component, DependencyStatus.Ok, ParseFirstVersionToken(output));
    }

    /// <summary>ffmpeg + ffprobe 同包：两者都要在，ffmpeg 还要能跑且具备 subtitles 滤镜（烧录所需）。</summary>
    private static async Task<DependencyHealthResult> CheckFfmpegAsync(
        string binDirectory, ProcessRunner runner, CancellationToken ct)
    {
        var ffmpeg = Path.Combine(binDirectory, "ffmpeg.exe");
        var ffprobe = Path.Combine(binDirectory, "ffprobe.exe");
        if (!FileLooksPresent(ffmpeg) || !FileLooksPresent(ffprobe))
        {
            return new DependencyHealthResult("ffmpeg", DependencyStatus.Missing, null);
        }
        var (exit, output) = await runner(ffmpeg, ["-version"], ct).ConfigureAwait(false);
        if (exit != 0) return new DependencyHealthResult("ffmpeg", DependencyStatus.Corrupt, null);
        var version = ParseFirstVersionToken(output);

        var (filtersExit, filtersOutput) = await runner(ffmpeg, ["-hide_banner", "-filters"], ct).ConfigureAwait(false);
        if (filtersExit == 0 && !FfmpegHasSubtitlesSupport(filtersOutput))
        {
            return new DependencyHealthResult("ffmpeg", DependencyStatus.RunnableButMissingCapability, version);
        }
        return new DependencyHealthResult("ffmpeg", DependencyStatus.Ok, version);
    }

    /// <summary>文件存在且非零字节（截断/占位的 0 字节文件视为缺失）。</summary>
    internal static bool FileLooksPresent(string path)
    {
        try
        {
            var info = new FileInfo(path);
            return info.Exists && info.Length > 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>从 --version 输出里抓第一个形如 1.2 / 2026.06.09 / 7.1.1 的版本号；抓不到返回 null。</summary>
    internal static string? ParseFirstVersionToken(string output)
    {
        if (string.IsNullOrEmpty(output)) return null;
        var match = System.Text.RegularExpressions.Regex.Match(output, @"\d+(?:\.\d+){1,3}");
        return match.Success ? match.Value : null;
    }

    /// <summary>ffmpeg -filters 输出里是否含 subtitles 滤镜（烧录字幕所必需）。</summary>
    internal static bool FfmpegHasSubtitlesSupport(string filtersOutput) =>
        filtersOutput.Contains("subtitles", StringComparison.OrdinalIgnoreCase);
}
