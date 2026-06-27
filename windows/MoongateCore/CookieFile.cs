namespace Moongate.Core;

/// <summary>一条待导出的 cookie（来自 GUI 层 WebView2 登录会话）。</summary>
public sealed record CookieRecord
{
    public required string Domain { get; init; }
    public required string Path { get; init; }
    public required string Name { get; init; }
    public required string Value { get; init; }
    public bool IsSecure { get; init; }
    /// <summary>过期时间（Unix 秒）；null 表示 session cookie（落盘写 0）。</summary>
    public long? ExpiresEpochSeconds { get; init; }
}

/// <summary>
/// 把 App 内 WebView 登录后取到的 cookies 导出成 yt-dlp 可读的 Netscape 格式文件。
/// 文件属于登录凭证，只落在本地应用数据目录。
/// </summary>
public static class NetscapeCookieFile
{
    /// <summary>
    /// 写入 Netscape 格式 cookies 文件（覆盖旧内容）。
    /// - 首行固定 "# Netscape HTTP Cookie File"。
    /// - 每行 7 个制表符分隔字段：domain、includeSubdomains、path、secure、expiry、name、value；
    ///   domain 以 "." 开头时 includeSubdomains 为 TRUE。
    /// - session cookie 的 expiry 写 0。
    /// - 字段里含制表符或换行会破坏行格式，这类 cookie 直接跳过。
    /// - 自动创建父目录。
    /// </summary>
    public static void Write(IEnumerable<CookieRecord> cookies, string path)
    {
        var lines = new List<string> { "# Netscape HTTP Cookie File" };
        foreach (var cookie in cookies)
        {
            var textFields = new[] { cookie.Domain, cookie.Path, cookie.Name, cookie.Value };
            if (textFields.Any(f => f.Contains('\t') || f.Contains('\n') || f.Contains('\r')))
            {
                continue;
            }
            var includeSubdomains = cookie.Domain.StartsWith('.') ? "TRUE" : "FALSE";
            var secure = cookie.IsSecure ? "TRUE" : "FALSE";
            var expiry = cookie.ExpiresEpochSeconds is { } epoch ? Math.Max(0, epoch) : 0;
            lines.Add(string.Join('\t',
                cookie.Domain, includeSubdomains, cookie.Path,
                secure, expiry.ToString(), cookie.Name, cookie.Value));
        }

        var parent = System.IO.Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
        File.WriteAllText(path, string.Join('\n', lines) + "\n");
    }

    /// <summary>删除 cookies 文件（清除登录态）；文件不存在时静默忽略。</summary>
    public static void Clear(string path)
    {
        try { File.Delete(path); } catch { /* 忽略 */ }
    }

    /// <summary>
    /// 读取 Netscape 格式 cookies 文件为记录列表（跳过注释与空行、字段不足的行）。
    /// 用于旧文件迁移与按域过滤。文件不存在返回空列表。
    /// </summary>
    public static List<CookieRecord> Read(string path)
    {
        var records = new List<CookieRecord>();
        if (!File.Exists(path)) return records;
        foreach (var raw in File.ReadAllLines(path))
        {
            var line = raw.TrimEnd('\r');
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var f = line.Split('\t');
            if (f.Length < 7) continue;
            var expiry = long.TryParse(f[4], out var e) && e > 0 ? e : (long?)null;
            records.Add(new CookieRecord
            {
                Domain = f[0],
                Path = f[2],
                IsSecure = string.Equals(f[3], "TRUE", StringComparison.OrdinalIgnoreCase),
                ExpiresEpochSeconds = expiry,
                Name = f[5],
                Value = f[6],
            });
        }
        return records;
    }

    /// <summary>只保留属于该站点允许域的 cookie（导出隔离用）。</summary>
    public static List<CookieRecord> FilterToSite(IEnumerable<CookieRecord> cookies, CookieSite site) =>
        cookies.Where(c => CookieSites.DomainAllowed(site, c.Domain)).ToList();

    /// <summary>为指定 URL 从 Netscape jar 生成 HTTP Cookie header。</summary>
    public static string? CookieHeaderFor(Uri url, string filePath)
    {
        var host = url.Host;
        if (string.IsNullOrEmpty(host)) return null;
        var isHttps = string.Equals(url.Scheme, "https", StringComparison.OrdinalIgnoreCase);
        var requestPath = string.IsNullOrEmpty(url.AbsolutePath) ? "/" : url.AbsolutePath;
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var pairs = Read(filePath)
            .Where(record =>
            {
                if (record.IsSecure && !isHttps) return false;
                if (record.ExpiresEpochSeconds is { } expiry && expiry <= now) return false;
                if (!CookieSites.DomainMatches(host, record.Domain)) return false;
                var cookiePath = string.IsNullOrEmpty(record.Path) ? "/" : record.Path;
                return requestPath == cookiePath
                    || requestPath.StartsWith(
                        cookiePath.EndsWith('/') ? cookiePath : cookiePath + "/",
                        StringComparison.Ordinal);
            })
            .OrderByDescending(record => record.Path.Length)
            .Select(record => $"{record.Name}={record.Value}")
            .ToList();
        return pairs.Count == 0 ? null : string.Join("; ", pairs);
    }
}
