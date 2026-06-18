using System.Runtime.InteropServices;

namespace Moongate.Core;

/// <summary>下载目的地与文件夹命名规则（移植自 Swift 版 ViewModel 的静态方法）。</summary>
public static class DownloadPaths
{
    /// <summary>
    /// 下载目的地：会产出多个文件（字幕/译文/烧录件）时在 Downloads 下按视频标题建文件夹，
    /// 单视频文件直接放 Downloads（避免一个视频三四个文件把下载目录搅乱）。
    /// downloadsRoot 供测试注入；null 时取系统下载目录。
    /// </summary>
    public static string DestinationDirectory(string title, bool multiFile, string? downloadsRoot = null)
    {
        var downloads = downloadsRoot ?? DownloadsDirectory();
        return multiFile ? Path.Combine(downloads, SanitizedFolderName(title)) : downloads;
    }

    /// <summary>Windows 保留设备名（大小写不敏感）：作为文件/文件夹名（含带扩展名形式如 CON.video）会创建失败。</summary>
    private static readonly HashSet<string> ReservedDeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    };

    /// <summary>
    /// 标题转安全文件夹名：去路径分隔/控制字符、截长（80 字符）、去结尾点号与空格，
    /// 并规避 Windows 保留设备名。在 Swift 版基础上额外剔除 Windows 不允许的字符 &lt;&gt;:"|?*。
    /// </summary>
    public static string SanitizedFolderName(string title)
    {
        // Swift 版分隔集：/ \ : \0 + 换行；Windows 额外加 < > " | ? *。
        // components(separatedBy:).joined(separator: " ") 等价于逐字符替换为空格。
        var separators = new HashSet<char> { '/', '\\', ':', '\0', '\n', '\r', '<', '>', '"', '|', '?', '*' };
        var chars = title.Select(c => separators.Contains(c) ? ' ' : c).ToArray();
        var name = new string(chars).Trim();
        if (name.Length > 80)
        {
            name = name[..80].Trim();
        }
        // 结尾点号与空格在 Windows 都会被静默去除/报错，统一剔除。
        name = name.TrimEnd('.', ' ');
        if (name.Length == 0) return L10n.T("视频", "影片", "Video");
        // 保留设备名（含带扩展名形式 CON.video）：取首个点号前的主名判定，命中则加下划线前缀规避。
        var firstDot = name.IndexOf('.');
        var stem = (firstDot >= 0 ? name[..firstDot] : name).Trim();
        if (ReservedDeviceNames.Contains(stem))
        {
            name = "_" + name;
        }
        return name;
    }

    /// <summary>
    /// 用户下载目录。Windows 经 SHGetKnownFolderPath 取真实 Downloads（可能被用户重定向），
    /// 失败回退 %USERPROFILE%\Downloads；非 Windows 用 ~/Downloads。
    /// </summary>
    public static string DownloadsDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!OperatingSystem.IsWindows())
        {
            return Path.Combine(home, "Downloads");
        }
        var known = TryGetKnownDownloadsFolder();
        return known ?? Path.Combine(home, "Downloads");
    }

    // MARK: Windows Known Folder

    private static readonly Guid FolderIdDownloads = new("374DE290-123F-4565-9164-39C4925E467B");

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = false)]
    private static extern string SHGetKnownFolderPath(
        [MarshalAs(UnmanagedType.LPStruct)] Guid rfid, uint flags, IntPtr token);

    private static string? TryGetKnownFolderPath(Guid folderId)
    {
        if (!OperatingSystem.IsWindows()) return null;
        try
        {
            return SHGetKnownFolderPath(folderId, 0, IntPtr.Zero);
        }
        catch
        {
            return null;
        }
    }

    private static string? TryGetKnownDownloadsFolder() => TryGetKnownFolderPath(FolderIdDownloads);
}
