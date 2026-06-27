using Moongate.Core;

namespace MoongateCore.Tests;

/// <summary>SEC-COOKIE-001：按站点隔离的 cookie 路由、过滤、认证判定与旧文件迁移。</summary>
public class CookieIsolationTests : IDisposable
{
    private readonly string _dir;

    public CookieIsolationTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), $"moongate-cookie-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_dir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_dir, true); } catch { /* 忽略 */ }
    }

    private static CookieRecord Cookie(string domain, string name, string value = "v") => new()
    {
        Domain = domain,
        Path = "/",
        Name = name,
        Value = value,
        IsSecure = true,
        ExpiresEpochSeconds = 9999999999,
    };

    [Theory]
    [InlineData("www.youtube.com", "youtube")]
    [InlineData("youtu.be", "youtube")]
    [InlineData("m.youtube.com", "youtube")]
    [InlineData("www.bilibili.com", "bilibili")]
    [InlineData("b23.tv", "bilibili")]
    public void ForHost_MapsKnownHostsToSite(string host, string expectedKey)
    {
        Assert.Equal(expectedKey, CookieSites.ForHost(host)!.Key);
    }

    [Theory]
    [InlineData("example.com")]
    [InlineData("vimeo.com")]
    [InlineData("")]
    public void ForHost_UnknownHost_ReturnsNull(string host)
    {
        Assert.Null(CookieSites.ForHost(host));
    }

    [Fact]
    public void DomainAllowed_RespectsSiteBoundaries()
    {
        // YouTube jar 接受 youtube.com / google 域，但不接受 bilibili。
        Assert.True(CookieSites.DomainAllowed(CookieSites.YouTube, ".youtube.com"));
        Assert.True(CookieSites.DomainAllowed(CookieSites.YouTube, ".google.com"));
        Assert.True(CookieSites.DomainAllowed(CookieSites.YouTube, "accounts.google.com"));
        Assert.False(CookieSites.DomainAllowed(CookieSites.YouTube, ".bilibili.com"));
        // Bilibili jar 反之。
        Assert.True(CookieSites.DomainAllowed(CookieSites.Bilibili, ".bilibili.com"));
        Assert.True(CookieSites.DomainAllowed(CookieSites.Bilibili, "passport.bilibili.com"));
        Assert.False(CookieSites.DomainAllowed(CookieSites.Bilibili, ".google.com"));
    }

    [Fact]
    public void FilterToSite_DropsOtherSiteCookies()
    {
        var mixed = new[]
        {
            Cookie(".youtube.com", "LOGIN_INFO"),
            Cookie(".google.com", "SAPISID"),
            Cookie(".bilibili.com", "SESSDATA"),
        };
        var youtube = NetscapeCookieFile.FilterToSite(mixed, CookieSites.YouTube);
        Assert.Equal(2, youtube.Count);
        Assert.DoesNotContain(youtube, c => c.Domain.Contains("bilibili"));

        var bilibili = NetscapeCookieFile.FilterToSite(mixed, CookieSites.Bilibili);
        Assert.Single(bilibili);
        Assert.All(bilibili, c => Assert.Contains("bilibili", c.Domain));
    }

    [Fact]
    public void DynamicHostFiltering_UsesOnlyRelatedDomains()
    {
        var mixed = new[]
        {
            Cookie(".missav.live", "cf_clearance"),
            Cookie("cdn.missav.live", "cdn"),
            Cookie(".example.com", "other"),
        };

        var filtered = CookieSites.FilterToHost(mixed, "missav.live");
        Assert.Equal(["cdn", "cf_clearance"], filtered.Select(c => c.Name).OrderBy(name => name).ToArray());
        Assert.Equal("site-missav.live", CookieSites.DynamicKeyForHost("https://missav.live/cn/hublk-074"));
        Assert.True(CookieSites.DomainMatches("cn.missav.live", ".missav.live"));
        Assert.False(CookieSites.DomainMatches("missav.live", ".evilmissav.live"));
    }

    [Fact]
    public void EngineCookieResolution_UsesKnownThenDynamicJar()
    {
        Assert.EndsWith(
            Path.Combine("cookies", "youtube.txt"),
            YtDlpEngine.CookieFileForUrl("https://www.youtube.com/watch?v=abc"));
        Assert.EndsWith(
            Path.Combine("cookies", "site-missav.live.txt"),
            YtDlpEngine.CookieFileForUrl("https://missav.live/cn/hublk-074"));
    }

    [Fact]
    public void CookieHeaderFor_FiltersByUrlDomainPathAndScheme()
    {
        var path = Path.Combine(_dir, "site-missav.live.txt");
        File.WriteAllText(path, string.Join('\n', [
            "# Netscape HTTP Cookie File",
            ".missav.live\tTRUE\t/\tTRUE\t9999999999\tcf_clearance\tok",
            ".missav.live\tTRUE\t/cn\tFALSE\t9999999999\tlang\tzh",
            ".example.com\tTRUE\t/\tFALSE\t9999999999\tother\tbad",
        ]) + "\n");

        var header = NetscapeCookieFile.CookieHeaderFor(
            new Uri("https://missav.live/cn/hublk-074"), path);
        Assert.Equal("lang=zh; cf_clearance=ok", header);
        Assert.Null(NetscapeCookieFile.CookieHeaderFor(new Uri("http://missav.live/"), path));
    }

    [Fact]
    public void ContainsAuthCookie_RequiresKnownAuthCookieOnAllowedDomain()
    {
        // 仅有一个无关 cookie：不算已登录。
        Assert.False(CookieSites.ContainsAuthCookie(
            CookieSites.YouTube, [Cookie(".youtube.com", "VISITOR_INFO1_LIVE")]));
        // 认证 cookie 在允许域上：算已登录。
        Assert.True(CookieSites.ContainsAuthCookie(
            CookieSites.YouTube, [Cookie(".google.com", "SAPISID")]));
        // 认证 cookie 名对，但域不属于该站点：不算（防跨站误判）。
        Assert.False(CookieSites.ContainsAuthCookie(
            CookieSites.Bilibili, [Cookie(".google.com", "SESSDATA")]));
        Assert.True(CookieSites.ContainsAuthCookie(
            CookieSites.Bilibili, [Cookie(".bilibili.com", "SESSDATA")]));
    }

    [Fact]
    public void NetscapeCookieFile_WriteThenRead_RoundTrips()
    {
        var path = Path.Combine(_dir, "rt.txt");
        var records = new[]
        {
            Cookie(".youtube.com", "LOGIN_INFO", "abc"),
            Cookie("accounts.google.com", "SAPISID", "xyz"),
        };
        NetscapeCookieFile.Write(records, path);
        var read = NetscapeCookieFile.Read(path);
        Assert.Equal(2, read.Count);
        Assert.Contains(read, c => c is { Name: "LOGIN_INFO", Value: "abc", Domain: ".youtube.com" });
        Assert.Contains(read, c => c is { Name: "SAPISID", Value: "xyz" } && c.IsSecure);
    }

    [Fact]
    public void Read_MissingFile_ReturnsEmpty()
    {
        Assert.Empty(NetscapeCookieFile.Read(Path.Combine(_dir, "nope.txt")));
    }

    [Fact]
    public void Migration_SplitsGlobalCookiesPerSiteAndDeletesGlobal()
    {
        var legacy = Path.Combine(_dir, "cookies.txt");
        var cookieDir = Path.Combine(_dir, "cookies");
        NetscapeCookieFile.Write(
        [
            Cookie(".youtube.com", "LOGIN_INFO"),
            Cookie(".google.com", "SAPISID"),
            Cookie(".bilibili.com", "SESSDATA"),
            Cookie(".example.com", "irrelevant"),
        ], legacy);

        CookieMigration.MigrateGlobalToPerSite(legacy, cookieDir);

        // 旧全局文件已删除。
        Assert.False(File.Exists(legacy));
        // YouTube jar 只含 youtube/google，无 bilibili。
        var youtube = NetscapeCookieFile.Read(Path.Combine(cookieDir, "youtube.txt"));
        Assert.Equal(2, youtube.Count);
        Assert.DoesNotContain(youtube, c => c.Domain.Contains("bilibili"));
        // Bilibili jar 只含 bilibili。
        var bilibili = NetscapeCookieFile.Read(Path.Combine(cookieDir, "bilibili.txt"));
        Assert.Single(bilibili);
        Assert.Equal("SESSDATA", bilibili[0].Name);
    }

    [Fact]
    public void Migration_DoesNotOverwriteExistingPerSiteFile()
    {
        var legacy = Path.Combine(_dir, "cookies.txt");
        var cookieDir = Path.Combine(_dir, "cookies");
        Directory.CreateDirectory(cookieDir);
        // 已有新登录的 youtube jar。
        NetscapeCookieFile.Write([Cookie(".youtube.com", "LOGIN_INFO", "fresh")],
            Path.Combine(cookieDir, "youtube.txt"));
        NetscapeCookieFile.Write([Cookie(".youtube.com", "LOGIN_INFO", "stale")], legacy);

        CookieMigration.MigrateGlobalToPerSite(legacy, cookieDir);

        // 不覆盖新登录。
        var youtube = NetscapeCookieFile.Read(Path.Combine(cookieDir, "youtube.txt"));
        Assert.Equal("fresh", youtube.Single().Value);
        Assert.False(File.Exists(legacy));
    }

    [Fact]
    public void Migration_NoGlobalFile_NoOp()
    {
        var legacy = Path.Combine(_dir, "missing.txt");
        var cookieDir = Path.Combine(_dir, "cookies");
        CookieMigration.MigrateGlobalToPerSite(legacy, cookieDir);
        Assert.False(Directory.Exists(cookieDir) && Directory.GetFiles(cookieDir).Length > 0);
    }
}
