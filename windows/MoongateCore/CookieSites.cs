namespace Moongate.Core;

/// <summary>
/// 一个受支持登录站点的 cookie 隔离定义：决定哪些域的 cookie 属于该站点、
/// 哪些 host 的下载该用该站点的 cookie jar、以及哪些 cookie 名代表真正已登录。
/// 与 macOS CookieSites 同构。
/// </summary>
public sealed record CookieSite
{
    /// <summary>站点标识，同时是 cookie 文件名（cookies/&lt;Key&gt;.txt）。</summary>
    public required string Key { get; init; }
    /// <summary>下载 URL 的 host 命中这些域时使用本 jar（精确或子域匹配）。</summary>
    public required IReadOnlyList<string> Hosts { get; init; }
    /// <summary>导出时只保留属于这些域的 cookie，避免把其它站点的会话一并导出。</summary>
    public required IReadOnlyList<string> AllowedCookieDomains { get; init; }
    /// <summary>判定「真正已登录」的认证 cookie 名（出现其一即视为已登录）。</summary>
    public required IReadOnlyList<string> AuthCookieNames { get; init; }
}

/// <summary>受支持站点的 cookie 隔离注册表与匹配工具（纯逻辑，便于测试）。</summary>
public static class CookieSites
{
    public static readonly CookieSite YouTube = new()
    {
        Key = "youtube",
        Hosts = ["youtube.com", "youtu.be", "youtube-nocookie.com"],
        // YouTube 认证 cookie 实际落在 .google.com / .youtube.com；accounts.google.com 由 google.com 覆盖。
        AllowedCookieDomains = ["youtube.com", "google.com"],
        AuthCookieNames =
        [
            "SID", "SSID", "HSID", "APISID", "SAPISID",
            "__Secure-1PSID", "__Secure-3PSID", "__Secure-1PAPISID", "__Secure-3PAPISID",
            "LOGIN_INFO",
        ],
    };

    public static readonly CookieSite Bilibili = new()
    {
        Key = "bilibili",
        Hosts = ["bilibili.com", "b23.tv"],
        // passport.bilibili.com 等子域由 bilibili.com 覆盖。
        AllowedCookieDomains = ["bilibili.com"],
        AuthCookieNames = ["SESSDATA", "DedeUserID", "bili_jct"],
    };

    public static readonly IReadOnlyList<CookieSite> All = [YouTube, Bilibili];

    /// <summary>未注册站点的动态 cookie key。只用于文件名，不出现在设置页站点列表。</summary>
    public static string? DynamicKeyForHost(string host)
    {
        var normalized = NormalizeHost(host);
        if (normalized.Length == 0) return null;
        var chars = normalized.Select(ch =>
            char.IsLetterOrDigit(ch) || ch is '.' or '-' ? ch : '_').ToArray();
        return "site-" + new string(chars);
    }

    /// <summary>按登录站点标识（如 "youtube.com"）找到对应隔离定义；未知站点返回 null。</summary>
    public static CookieSite? ForLoginSite(string site)
    {
        var s = site.ToLowerInvariant();
        if (s.Contains("youtube")) return YouTube;
        if (s.Contains("bilibili")) return Bilibili;
        return null;
    }

    /// <summary>按下载 URL 的 host 选择对应 cookie jar（无匹配返回 null → 该下载不带 cookies）。</summary>
    public static CookieSite? ForHost(string host)
    {
        var h = host.ToLowerInvariant();
        foreach (var site in All)
        {
            if (site.Hosts.Any(name => h == name || h.EndsWith("." + name))) return site;
        }
        return null;
    }

    /// <summary>cookie 的 domain 是否属于该站点允许导出的域（处理前导点与子域）。</summary>
    public static bool DomainAllowed(CookieSite site, string cookieDomain)
    {
        var d = cookieDomain.TrimStart('.').ToLowerInvariant();
        return site.AllowedCookieDomains.Any(allowed => d == allowed || d.EndsWith("." + allowed));
    }

    /// <summary>cookie 的 domain 是否可用于当前 host。用于未注册站点的动态 jar。</summary>
    public static bool DomainMatches(string host, string cookieDomain)
    {
        var h = NormalizeHost(host);
        var d = NormalizeHost(cookieDomain);
        if (h.Length == 0 || d.Length == 0) return false;
        if (h == d || d.EndsWith("." + h)) return true;
        // 允许父域 cookie（例如 host=cn.example.com, cookieDomain=.example.com）。
        return d.Contains('.') && h.EndsWith("." + d);
    }

    /// <summary>记录里是否存在该站点的认证 cookie（且域名属于该站点）——用于「是否真正登录」判定。</summary>
    public static bool ContainsAuthCookie(CookieSite site, IEnumerable<CookieRecord> records) =>
        records.Any(r => site.AuthCookieNames.Contains(r.Name, StringComparer.Ordinal)
            && DomainAllowed(site, r.Domain));

    public static List<CookieRecord> FilterToHost(IEnumerable<CookieRecord> records, string host) =>
        records.Where(c => DomainMatches(host, c.Domain)).ToList();

    public static string NormalizeHost(string value)
    {
        var raw = (value ?? "").Trim().Trim('.').ToLowerInvariant();
        if (Uri.TryCreate(raw, UriKind.Absolute, out var uri) && !string.IsNullOrEmpty(uri.Host))
        {
            return uri.Host.Trim('.').ToLowerInvariant();
        }
        return raw;
    }
}

/// <summary>旧版全局 cookies.txt → 按站点拆分的一次性迁移（纯文件操作，便于测试）。</summary>
public static class CookieMigration
{
    /// <summary>
    /// 把旧的全局 cookies.txt 按域拆分到各站点 jar（cookieDirectory/&lt;key&gt;.txt），完成后删除旧文件。
    /// 幂等：旧文件不存在则不动；目标站点文件已存在（新登录）则不覆盖。
    /// </summary>
    public static void MigrateGlobalToPerSite(string legacyGlobalPath, string cookieDirectory)
    {
        if (!File.Exists(legacyGlobalPath)) return;
        List<CookieRecord> records;
        try { records = NetscapeCookieFile.Read(legacyGlobalPath); }
        catch { return; }
        foreach (var site in CookieSites.All)
        {
            var filtered = records.Where(r => CookieSites.DomainAllowed(site, r.Domain)).ToList();
            if (filtered.Count == 0) continue;
            var target = Path.Combine(cookieDirectory, site.Key + ".txt");
            if (File.Exists(target)) continue;  // 不覆盖已有的新登录
            NetscapeCookieFile.Write(filtered, target);
        }
        try { File.Delete(legacyGlobalPath); } catch { /* 下次启动再清 */ }
    }
}
