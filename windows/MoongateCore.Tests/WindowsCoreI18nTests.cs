using Moongate.Core;
using System.IO.Compression;
using System.Text;

namespace MoongateCore.Tests;

[Collection(L10nLanguageCollection.Name)]
public class WindowsCoreI18nTests
{
    [Fact]
    public async Task PageSnifferFallbackTitlesUseTraditionalChinese()
    {
        var previous = L10n.Language;
        L10n.Language = CoreLanguage.TraditionalChinese;
        try
        {
            const string html = """
                <iframe src="https://www.youtube.com/embed/abcdefghijk"></iframe>
                <iframe src="https://player.vimeo.com/video/12345"></iframe>
                """;
            var sniffer = new PageSniffer
            {
                FetchYouTubeTitleHook = (_, _) => Task.FromResult<string?>(null),
            };

            var candidates = await sniffer.ExtractCandidatesAsync(html, new Uri("https://example.com/"));

            Assert.Contains(candidates, c => c.Title == "YouTube 影片 abcdefghijk");
            Assert.Contains(candidates, c => c.Title == "Vimeo 影片 12345");
        }
        finally
        {
            L10n.Language = previous;
        }
    }

    [Fact]
    public void BurnerFallbackStringsUseTraditionalChinese()
    {
        var previous = L10n.Language;
        L10n.Language = CoreLanguage.TraditionalChinese;
        try
        {
            Assert.Equal("未知錯誤", FFmpegBurner.LastLine(""));
        }
        finally
        {
            L10n.Language = previous;
        }
    }

    [Fact]
    public void HardwareCompatibilityNoticeUsesSelectedLanguage()
    {
        var previous = L10n.Language;
        try
        {
            L10n.Language = CoreLanguage.TraditionalChinese;
            Assert.Equal("遇到相容性問題，實際耗時可能比預計更長。", PipelineAccelerationReport.CompatibilityModeNotice);

            L10n.Language = CoreLanguage.English;
            Assert.Equal("Compatibility handling is active, so this may take longer than expected.", PipelineAccelerationReport.CompatibilityModeNotice);
            Assert.DoesNotContain("CPU", PipelineAccelerationReport.CompatibilityModeNotice, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            L10n.Language = previous;
        }
    }

    [Fact]
    public void DynamicRangeBadgesUseSelectedLanguage()
    {
        var previous = L10n.Language;
        try
        {
            L10n.Language = CoreLanguage.TraditionalChinese;
            Assert.Equal("杜比視界", DynamicRange.DolbyVision.Badge());

            L10n.Language = CoreLanguage.English;
            Assert.Equal("Dolby Vision", DynamicRange.DolbyVision.Badge());
        }
        finally
        {
            L10n.Language = previous;
        }
    }

    [Fact]
    public async Task DependencyProgressUsesTraditionalChinese()
    {
        var previous = L10n.Language;
        L10n.Language = CoreLanguage.TraditionalChinese;
        var binDir = Path.Combine(Path.GetTempPath(), $"moongate-i18n-bin-{Guid.NewGuid():N}");
        Directory.CreateDirectory(binDir);
        try
        {
            var manager = new DependencyManager(binDir, new DependencyPayloadHandler(), ProgressTestPlans());
            var progress = new List<string>();

            await manager.EnsureAsync(new Progress<string>(progress.Add));

            // 进度文案现在带字节/速度后缀（如「正在下載 yt-dlp… 6 B / 6 B · 5.9 KB/s」），按前缀断言。
            Assert.Contains(progress, p => p.StartsWith("正在下載 yt-dlp…"));
            Assert.Contains(progress, p => p.StartsWith("正在下載 ffmpeg…"));
            Assert.Contains(progress, p => p.StartsWith("正在下載 deno…"));
            Assert.Contains("依賴元件已就緒", progress);
        }
        finally
        {
            L10n.Language = previous;
            try { Directory.Delete(binDir, recursive: true); } catch { }
        }
    }

    [Fact]
    public void EmptyDownloadFolderNameUsesTraditionalChinese()
    {
        var previous = L10n.Language;
        L10n.Language = CoreLanguage.TraditionalChinese;
        try
        {
            Assert.Equal("影片", DownloadPaths.SanitizedFolderName("///"));
        }
        finally
        {
            L10n.Language = previous;
        }
    }

    [Fact]
    public void TranslationApiErrorsUseTraditionalChinese()
    {
        var previous = L10n.Language;
        L10n.Language = CoreLanguage.TraditionalChinese;
        try
        {
            var invalidUrl = Assert.Throws<MoongateException>(() => TranslationApi.EndpointUrl("", "/v1/messages"));
            Assert.Contains("服務地址無效", invalidUrl.Message);

            var requestFailure = TranslationApi.RequestFailureMessage(400, "", new AppSettings());
            Assert.Contains("請求失敗", requestFailure);
            Assert.DoesNotContain("请求失败", requestFailure);
        }
        finally
        {
            L10n.Language = previous;
        }
    }

    private sealed class DependencyPayloadHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var url = request.RequestUri?.AbsoluteUri ?? "";
            byte[] payload;
            if (url.EndsWith("yt-dlp.exe", StringComparison.OrdinalIgnoreCase))
            {
                payload = Encoding.UTF8.GetBytes("YT_DLP");
            }
            else if (url.Contains("ffmpeg", StringComparison.OrdinalIgnoreCase))
            {
                payload = BuildZip(
                    ("ffmpeg-8.1.1-full_build/bin/ffmpeg.exe", "FFMPEG"),
                    ("ffmpeg-8.1.1-full_build/bin/ffprobe.exe", "FFPROBE"));
            }
            else if (url.Contains("denoland", StringComparison.OrdinalIgnoreCase))
            {
                payload = BuildZip(("deno.exe", "DENO"));
            }
            else
            {
                payload = [];
            }

            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(payload),
            });
        }

        private static byte[] BuildZip(params (string EntryName, string Content)[] entries)
        {
            using var stream = new MemoryStream();
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
            {
                foreach (var (entryName, content) in entries)
                {
                    var entry = archive.CreateEntry(entryName);
                    using var writer = new StreamWriter(entry.Open(), Encoding.UTF8);
                    writer.Write(content);
                }
            }
            return stream.ToArray();
        }
    }

    private static IReadOnlyList<DependencyDownload> ProgressTestPlans() =>
    [
        new DependencyDownload
        {
            Name = "yt-dlp",
            Version = "test",
            Architecture = "x64",
            Url = "https://example.test/yt-dlp.exe",
            Sha256 = "",
            Kind = DependencyDownload.DownloadKind.Executable,
            ProvidesFiles = ["yt-dlp.exe"],
        },
        new DependencyDownload
        {
            Name = "ffmpeg",
            Version = "test",
            Architecture = "x64",
            Url = "https://example.test/ffmpeg.zip",
            Sha256 = "",
            Kind = DependencyDownload.DownloadKind.Zip,
            ProvidesFiles = ["ffmpeg.exe", "ffprobe.exe"],
            ZipEntries = new Dictionary<string, string>
            {
                ["bin/ffmpeg.exe"] = "ffmpeg.exe",
                ["bin/ffprobe.exe"] = "ffprobe.exe",
            },
        },
        new DependencyDownload
        {
            Name = "deno",
            Version = "test",
            Architecture = "x64",
            Url = "https://example.test/denoland/deno.zip",
            Sha256 = "",
            Kind = DependencyDownload.DownloadKind.Zip,
            ProvidesFiles = ["deno.exe"],
            ZipEntries = new Dictionary<string, string> { ["deno.exe"] = "deno.exe" },
        },
    ];
}
