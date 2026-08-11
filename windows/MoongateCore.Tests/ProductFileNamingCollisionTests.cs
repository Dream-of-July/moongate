using Moongate.Core;

namespace MoongateCore.Tests;

/// 产物命名去重的 Windows 侧行为测试，与 macOS 的 UniqueFilenameTests 对等。
/// 覆盖「同一视频多次下载 / 重复导入字幕 / 重跑云端 ASR」时避免覆盖已有产物：
/// 首选名可用直接用，被占用则依次加 -2、-3…此前这几处 hand-rolled 循环无冲突测试。
public class ProductFileNamingCollisionTests
{
    private static string TempDir()
    {
        var dir = Path.Combine(Path.GetTempPath(), $"moongate-naming-{Guid.NewGuid():N}");
        Directory.CreateDirectory(dir);
        return dir;
    }

    // MARK: 导入字幕（QueueManager.ImportedSubtitleDestination，-<n>）

    [Fact]
    public void ImportedSubtitle_NoCollision_UsesPreferredName()
    {
        var dir = TempDir();
        try
        {
            var url = QueueManager.ImportedSubtitleDestination(dir, "en", "srt");
            Assert.Equal("imported-subtitle.en.srt", Path.GetFileName(url));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void ImportedSubtitle_Collision_AppendsSerial()
    {
        var dir = TempDir();
        try
        {
            File.WriteAllText(Path.Combine(dir, "imported-subtitle.en.srt"), "x");
            var url = QueueManager.ImportedSubtitleDestination(dir, "en", "srt");
            Assert.Equal("imported-subtitle.en-2.srt", Path.GetFileName(url));

            File.WriteAllText(Path.Combine(dir, "imported-subtitle.en-2.srt"), "x");
            var url3 = QueueManager.ImportedSubtitleDestination(dir, "en", "srt");
            Assert.Equal("imported-subtitle.en-3.srt", Path.GetFileName(url3));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void ImportedSubtitle_UnsafeLanguage_SanitizedAndEmptyBecomesAuto()
    {
        var dir = TempDir();
        try
        {
            // 非法字符（/）应被替换为 -（与 macOS safeLanguage 一致）。
            Assert.Equal("imported-subtitle.zh-Hans.srt",
                Path.GetFileName(QueueManager.ImportedSubtitleDestination(dir, "zh/Hans", "srt")));
            // 完全为空的语言码回落 auto（调用方本已归一，这里是内部防御）。
            Assert.Equal("imported-subtitle.auto.srt",
                Path.GetFileName(QueueManager.ImportedSubtitleDestination(dir, "", "srt")));
        }
        finally { Directory.Delete(dir, true); }
    }

    // MARK: 云端 ASR（OpenAI / Aligned 两套生成器的 sidecar 命名，-<n>）

    [Fact]
    public void CloudAsr_BothGenerators_ShareIdenticalCollisionNaming()
    {
        var dir = TempDir();
        try
        {
            var video = Path.Combine(dir, "clip.mp4");
            // 首选名。
            Assert.Equal("clip.cloud-asr.ja.srt",
                Path.GetFileName(OpenAICloudAsrSubtitleGenerator.UniqueOutputPath(video, "ja")));
            Assert.Equal("clip.cloud-asr.ja.srt",
                Path.GetFileName(AlignedOpenAICloudAsrSubtitleGenerator.CloudAlignedOutputPath(video, "ja")));

            // 占用首选名后，两套生成器都应跳到 -2（行为一致）。
            File.WriteAllText(Path.Combine(dir, "clip.cloud-asr.ja.srt"), "x");
            Assert.Equal("clip.cloud-asr.ja-2.srt",
                Path.GetFileName(OpenAICloudAsrSubtitleGenerator.UniqueOutputPath(video, "ja")));
            Assert.Equal("clip.cloud-asr.ja-2.srt",
                Path.GetFileName(AlignedOpenAICloudAsrSubtitleGenerator.CloudAlignedOutputPath(video, "ja")));
        }
        finally { Directory.Delete(dir, true); }
    }
}
