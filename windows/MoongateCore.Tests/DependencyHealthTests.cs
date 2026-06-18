using Moongate.Core;

namespace MoongateCore.Tests;

/// <summary>DEP-WIN-003：结构化依赖健康检查（可执行性 + 能力），不再只看文件存在。</summary>
public class DependencyHealthTests : IDisposable
{
    private readonly string _binDir;

    public DependencyHealthTests()
    {
        _binDir = Path.Combine(Path.GetTempPath(), $"moongate-health-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_binDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_binDir, true); } catch { /* 忽略 */ }
    }

    private void Write(string name, string content = "stub") =>
        File.WriteAllText(Path.Combine(_binDir, name), content);

    // MARK: 纯解析

    [Theory]
    [InlineData("yt-dlp 2026.06.09", "2026.06.09")]
    [InlineData("ffmpeg version 7.1.1-full_build", "7.1.1")]
    [InlineData("deno 2.1.4 (release)", "2.1.4")]
    [InlineData("no version here", null)]
    [InlineData("", null)]
    public void ParseFirstVersionToken(string output, string? expected) =>
        Assert.Equal(expected, DependencyHealth.ParseFirstVersionToken(output));

    [Fact]
    public void FfmpegHasSubtitlesSupport_DetectsFilter()
    {
        Assert.True(DependencyHealth.FfmpegHasSubtitlesSupport("... subtitles  Render text subtitles ..."));
        Assert.False(DependencyHealth.FfmpegHasSubtitlesSupport("scale  crop  overlay"));
    }

    [Fact]
    public void FileLooksPresent_ZeroByteIsMissing()
    {
        var path = Path.Combine(_binDir, "empty.exe");
        File.WriteAllText(path, "");
        Assert.False(DependencyHealth.FileLooksPresent(path));
        File.WriteAllText(path, "x");
        Assert.True(DependencyHealth.FileLooksPresent(path));
        Assert.False(DependencyHealth.FileLooksPresent(Path.Combine(_binDir, "nope.exe")));
    }

    // MARK: 体检（假 runner）

    private static DependencyHealth.ProcessRunner FakeRunner(Func<string, IReadOnlyList<string>, (int, string)> fn) =>
        (exe, args, ct) => Task.FromResult(fn(exe, args));

    [Fact]
    public async Task AllHealthy_AllOk()
    {
        Write("yt-dlp.exe"); Write("ffmpeg.exe"); Write("ffprobe.exe"); Write("deno.exe");
        var runner = FakeRunner((exe, args) =>
        {
            if (args.Contains("-filters")) return (0, "subtitles Render text subtitles");
            if (exe.Contains("yt-dlp")) return (0, "2026.06.09");
            if (exe.Contains("ffmpeg")) return (0, "ffmpeg version 7.1.1");
            return (0, "deno 2.1.4");
        });
        var results = await DependencyHealth.CheckAsync(_binDir, runner);
        Assert.All(results, r => Assert.Equal(DependencyStatus.Ok, r.Status));
        Assert.Equal("2026.06.09", results.First(r => r.Component == "yt-dlp").Version);
    }

    [Fact]
    public async Task MissingFile_ReportedMissing_WithoutRunning()
    {
        Write("ffmpeg.exe"); Write("ffprobe.exe"); Write("deno.exe"); // yt-dlp 缺失
        var ran = false;
        var runner = FakeRunner((exe, args) =>
        {
            if (exe.Contains("yt-dlp")) ran = true;
            return (0, "subtitles");
        });
        var results = await DependencyHealth.CheckAsync(_binDir, runner);
        Assert.Equal(DependencyStatus.Missing, results.First(r => r.Component == "yt-dlp").Status);
        Assert.False(ran); // 缺失不应尝试执行
    }

    [Fact]
    public async Task NonZeroExit_ReportedCorrupt()
    {
        Write("yt-dlp.exe"); Write("ffmpeg.exe"); Write("ffprobe.exe"); Write("deno.exe");
        var runner = FakeRunner((exe, args) =>
        {
            if (args.Contains("-filters")) return (0, "subtitles");
            if (exe.Contains("deno")) return (-1, "bad image"); // deno 损坏/架构不符
            return (0, "version 1.0");
        });
        var results = await DependencyHealth.CheckAsync(_binDir, runner);
        Assert.Equal(DependencyStatus.Corrupt, results.First(r => r.Component == "deno").Status);
    }

    [Fact]
    public async Task FfmpegWithoutSubtitlesFilter_ReportedMissingCapability()
    {
        Write("yt-dlp.exe"); Write("ffmpeg.exe"); Write("ffprobe.exe"); Write("deno.exe");
        var runner = FakeRunner((exe, args) =>
        {
            if (args.Contains("-filters")) return (0, "scale crop overlay"); // 无 subtitles
            return (0, "version 7.1.1");
        });
        var results = await DependencyHealth.CheckAsync(_binDir, runner);
        Assert.Equal(DependencyStatus.RunnableButMissingCapability,
            results.First(r => r.Component == "ffmpeg").Status);
    }

    [Fact]
    public async Task FfprobeMissing_FfmpegReportedMissing()
    {
        Write("yt-dlp.exe"); Write("ffmpeg.exe"); Write("deno.exe"); // ffprobe 缺失
        var runner = FakeRunner((exe, args) => (0, "subtitles"));
        var results = await DependencyHealth.CheckAsync(_binDir, runner);
        Assert.Equal(DependencyStatus.Missing, results.First(r => r.Component == "ffmpeg").Status);
    }
}
