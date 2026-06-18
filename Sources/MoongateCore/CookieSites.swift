import Foundation

// MARK: - 按站点隔离的 cookie

/// 一个受支持登录站点的 cookie 隔离定义：决定哪些域的 cookie 属于该站点、
/// 哪些 host 的下载该用该站点的 cookie jar、以及哪些 cookie 名代表真正已登录。
/// 与 Windows 端 CookieSite 同构。
public struct CookieSite: Sendable {
    /// 站点标识，同时是 cookie 文件名（cookies/<key>.txt）。
    public let key: String
    /// 下载 URL 的 host 命中这些域时使用本 jar（精确或子域匹配）。
    public let hosts: [String]
    /// 导出时只保留属于这些域的 cookie，避免把其它站点的会话一并导出。
    public let allowedCookieDomains: [String]
    /// 判定「真正已登录」的认证 cookie 名（出现其一即视为已登录）。
    public let authCookieNames: [String]
}

/// 受支持站点的 cookie 隔离注册表与匹配工具（纯逻辑，便于测试）。
public enum CookieSites {
    public static let youtube = CookieSite(
        key: "youtube",
        hosts: ["youtube.com", "youtu.be", "youtube-nocookie.com"],
        // YouTube 认证 cookie 实际落在 .google.com / .youtube.com；accounts.google.com 由 google.com 覆盖。
        allowedCookieDomains: ["youtube.com", "google.com"],
        authCookieNames: [
            "SID", "SSID", "HSID", "APISID", "SAPISID",
            "__Secure-1PSID", "__Secure-3PSID", "__Secure-1PAPISID", "__Secure-3PAPISID",
            "LOGIN_INFO",
        ]
    )

    public static let bilibili = CookieSite(
        key: "bilibili",
        hosts: ["bilibili.com", "b23.tv"],
        // passport.bilibili.com 等子域由 bilibili.com 覆盖。
        allowedCookieDomains: ["bilibili.com"],
        authCookieNames: ["SESSDATA", "DedeUserID", "bili_jct"]
    )

    public static let all = [youtube, bilibili]

    /// 按登录站点标识（如 "youtube.com"）找到对应隔离定义；未知站点返回 nil。
    public static func forLoginSite(_ site: String) -> CookieSite? {
        let s = site.lowercased()
        if s.contains("youtube") { return youtube }
        if s.contains("bilibili") { return bilibili }
        return nil
    }

    /// 按下载 URL 的 host 选择对应 cookie jar（无匹配返回 nil → 该下载不带 cookies）。
    public static func forHost(_ host: String) -> CookieSite? {
        let h = host.lowercased()
        for site in all where site.hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) {
            return site
        }
        return nil
    }

    /// cookie 的 domain 是否属于该站点允许导出的域（处理前导点与子域）。
    public static func domainAllowed(_ site: CookieSite, _ cookieDomain: String) -> Bool {
        let d = String(cookieDomain.lowercased().drop(while: { $0 == "." }))
        return site.allowedCookieDomains.contains(where: { d == $0 || d.hasSuffix("." + $0) })
    }

    /// 记录里是否存在该站点的认证 cookie（且域名属于该站点）——用于「是否真正登录」判定。
    public static func containsAuthCookie(_ site: CookieSite, _ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { site.authCookieNames.contains($0.name) && domainAllowed(site, $0.domain) }
    }

    /// 只保留属于该站点允许域的 cookie（导出隔离用）。
    public static func filterToSite(_ cookies: [HTTPCookie], _ site: CookieSite) -> [HTTPCookie] {
        cookies.filter { domainAllowed(site, $0.domain) }
    }
}

/// 旧版全局 cookies.txt → 按站点拆分的一次性迁移（基于 Netscape 文本行，便于测试）。
public enum CookieMigration {
    /// 把旧的全局 cookies.txt 按域拆分到各站点 jar（cookieDirectory/<key>.txt），完成后删除旧文件。
    /// 幂等：旧文件不存在则不动；目标站点文件已存在（新登录）则不覆盖。
    public static func migrateGlobalToPerSite(legacyGlobal: URL, cookieDirectory: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyGlobal.path) else { return }
        guard let content = try? String(contentsOf: legacyGlobal, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for site in CookieSites.all {
            let dataLines = lines.filter { line in
                guard !line.hasPrefix("#"), !line.isEmpty else { return false }
                let fields = line.components(separatedBy: "\t")
                guard fields.count >= 7 else { return false }
                return CookieSites.domainAllowed(site, fields[0])
            }
            guard !dataLines.isEmpty else { continue }
            let target = cookieDirectory.appendingPathComponent(site.key + ".txt")
            guard !fm.fileExists(atPath: target.path) else { continue }  // 不覆盖新登录
            try? fm.createDirectory(at: cookieDirectory, withIntermediateDirectories: true)
            let out = (["# Netscape HTTP Cookie File"] + dataLines).joined(separator: "\n") + "\n"
            _ = fm.createFile(
                atPath: target.path, contents: Data(out.utf8),
                attributes: NetscapeCookieFile.secureFileAttributes
            )
        }
        try? fm.removeItem(at: legacyGlobal)
    }
}
