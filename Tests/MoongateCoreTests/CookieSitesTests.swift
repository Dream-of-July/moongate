import XCTest
@testable import MoongateCore

/// SEC-COOKIE-001：按站点隔离的 cookie 路由、域过滤、认证判定与旧文件迁移（与 Windows CookieIsolationTests 同构）。
final class CookieSitesTests: XCTestCase {
    private func cookie(domain: String, name: String, value: String = "v") -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])!
    }

    func testForHostMapsKnownHosts() {
        XCTAssertEqual(CookieSites.forHost("www.youtube.com")?.key, "youtube")
        XCTAssertEqual(CookieSites.forHost("youtu.be")?.key, "youtube")
        XCTAssertEqual(CookieSites.forHost("www.bilibili.com")?.key, "bilibili")
        XCTAssertEqual(CookieSites.forHost("b23.tv")?.key, "bilibili")
        XCTAssertNil(CookieSites.forHost("example.com"))
        XCTAssertNil(CookieSites.forHost(""))
    }

    func testDomainAllowedRespectsBoundaries() {
        XCTAssertTrue(CookieSites.domainAllowed(CookieSites.youtube, ".youtube.com"))
        XCTAssertTrue(CookieSites.domainAllowed(CookieSites.youtube, "accounts.google.com"))
        XCTAssertFalse(CookieSites.domainAllowed(CookieSites.youtube, ".bilibili.com"))
        XCTAssertTrue(CookieSites.domainAllowed(CookieSites.bilibili, "passport.bilibili.com"))
        XCTAssertFalse(CookieSites.domainAllowed(CookieSites.bilibili, ".google.com"))
    }

    func testFilterToSiteDropsOtherSiteCookies() {
        let mixed = [
            cookie(domain: ".youtube.com", name: "LOGIN_INFO"),
            cookie(domain: ".google.com", name: "SAPISID"),
            cookie(domain: ".bilibili.com", name: "SESSDATA"),
        ]
        let youtube = CookieSites.filterToSite(mixed, CookieSites.youtube)
        XCTAssertEqual(youtube.count, 2)
        XCTAssertFalse(youtube.contains { $0.domain.contains("bilibili") })

        let bilibili = CookieSites.filterToSite(mixed, CookieSites.bilibili)
        XCTAssertEqual(bilibili.count, 1)
        XCTAssertEqual(bilibili.first?.name, "SESSDATA")
    }

    func testDynamicHostFilteringUsesOnlyRelatedDomains() {
        let mixed = [
            cookie(domain: ".missav.live", name: "cf_clearance"),
            cookie(domain: "cdn.missav.live", name: "cdn"),
            cookie(domain: ".example.com", name: "other"),
        ]

        let filtered = CookieSites.filterToHost(mixed, host: "missav.live")
        XCTAssertEqual(Set(filtered.map(\.name)), ["cf_clearance", "cdn"])
        XCTAssertEqual(CookieSites.dynamicKey(forHost: "https://missav.live/cn/hublk-074"), "site-missav.live")
        XCTAssertTrue(CookieSites.domainMatches(host: "cn.missav.live", cookieDomain: ".missav.live"))
        XCTAssertFalse(CookieSites.domainMatches(host: "missav.live", cookieDomain: ".evilmissav.live"))
    }

    func testNetscapeCookieHeaderFiltersByUrlDomainPathAndScheme() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-cookie-header-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("site-missav.live.txt")
        try [
            "# Netscape HTTP Cookie File",
            ".missav.live\tTRUE\t/\tTRUE\t9999999999\tcf_clearance\tok",
            ".missav.live\tTRUE\t/cn\tFALSE\t9999999999\tlang\tzh",
            ".example.com\tTRUE\t/\tFALSE\t9999999999\tother\tbad",
        ].joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let header = NetscapeCookieFile.cookieHeader(
            for: URL(string: "https://missav.live/cn/hublk-074")!,
            from: file
        )
        XCTAssertEqual(header, "lang=zh; cf_clearance=ok")
        XCTAssertNil(NetscapeCookieFile.cookieHeader(
            for: URL(string: "http://missav.live/")!,
            from: file
        ))
    }

    func testContainsAuthCookieRequiresKnownAuthCookieOnAllowedDomain() {
        XCTAssertFalse(CookieSites.containsAuthCookie(
            CookieSites.youtube, [cookie(domain: ".youtube.com", name: "VISITOR_INFO1_LIVE")]))
        XCTAssertTrue(CookieSites.containsAuthCookie(
            CookieSites.youtube, [cookie(domain: ".google.com", name: "SAPISID")]))
        // 认证名对但域不属该站：不算（防跨站误判）。
        XCTAssertFalse(CookieSites.containsAuthCookie(
            CookieSites.bilibili, [cookie(domain: ".google.com", name: "SESSDATA")]))
        XCTAssertTrue(CookieSites.containsAuthCookie(
            CookieSites.bilibili, [cookie(domain: ".bilibili.com", name: "SESSDATA")]))
    }

    func testMigrationSplitsGlobalCookiesAndDeletesGlobal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-cookie-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacy = dir.appendingPathComponent("cookies.txt")
        let cookieDir = dir.appendingPathComponent("cookies", isDirectory: true)
        let lines = [
            "# Netscape HTTP Cookie File",
            ".youtube.com\tTRUE\t/\tTRUE\t9999999999\tLOGIN_INFO\tx",
            ".google.com\tTRUE\t/\tTRUE\t9999999999\tSAPISID\ty",
            ".bilibili.com\tTRUE\t/\tTRUE\t9999999999\tSESSDATA\tz",
            ".example.com\tTRUE\t/\tFALSE\t0\tirrelevant\tq",
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: legacy, atomically: true, encoding: .utf8)

        CookieMigration.migrateGlobalToPerSite(legacyGlobal: legacy, cookieDirectory: cookieDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let youtube = try String(contentsOf: cookieDir.appendingPathComponent("youtube.txt"), encoding: .utf8)
        XCTAssertTrue(youtube.contains("LOGIN_INFO"))
        XCTAssertTrue(youtube.contains("SAPISID"))
        XCTAssertFalse(youtube.contains("bilibili"))
        let bilibili = try String(contentsOf: cookieDir.appendingPathComponent("bilibili.txt"), encoding: .utf8)
        XCTAssertTrue(bilibili.contains("SESSDATA"))
        XCTAssertFalse(bilibili.contains("youtube"))
    }

    func testMigrationDoesNotOverwriteExistingPerSiteFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-cookie-\(UUID().uuidString)", isDirectory: true)
        let cookieDir = dir.appendingPathComponent("cookies", isDirectory: true)
        try FileManager.default.createDirectory(at: cookieDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fresh = cookieDir.appendingPathComponent("youtube.txt")
        try "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t9999999999\tLOGIN_INFO\tfresh\n"
            .write(to: fresh, atomically: true, encoding: .utf8)
        let legacy = dir.appendingPathComponent("cookies.txt")
        try "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t9999999999\tLOGIN_INFO\tstale\n"
            .write(to: legacy, atomically: true, encoding: .utf8)

        CookieMigration.migrateGlobalToPerSite(legacyGlobal: legacy, cookieDirectory: cookieDir)

        let youtube = try String(contentsOf: fresh, encoding: .utf8)
        XCTAssertTrue(youtube.contains("fresh"))
        XCTAssertFalse(youtube.contains("stale"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    // MARK: - 过期 / 会话 cookie（cookieHeader 的时效过滤，安全相关，此前未测）

    /// 已过期的 cookie（expiry <= now）不得进入发往服务器的 Cookie header；
    /// 未过期的正常保留。此前所有 header 测试都用 9999999999（远期），从未走过期分支。
    func testCookieHeaderDropsExpiredCookies() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-cookie-expiry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Int(Date().timeIntervalSince1970)
        let file = dir.appendingPathComponent("site-example.com.txt")
        try [
            "# Netscape HTTP Cookie File",
            ".example.com\tTRUE\t/\tTRUE\t\(now - 3600)\texpired\told",   // 1 小时前过期 → 丢弃
            ".example.com\tTRUE\t/\tTRUE\t\(now + 3600)\tfresh\tnew",     // 1 小时后过期 → 保留
        ].joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        let header = NetscapeCookieFile.cookieHeader(
            for: URL(string: "https://example.com/")!, from: file
        )
        XCTAssertEqual(header, "fresh=new", "过期 cookie 必须被排除，只发未过期的")
    }

    /// 全部 cookie 都过期时，header 应为 nil（没有可发送的凭证），而不是空串或过期值。
    func testCookieHeaderIsNilWhenAllCookiesExpired() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-cookie-allexpired-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Int(Date().timeIntervalSince1970)
        let file = dir.appendingPathComponent("site-example.com.txt")
        try [
            "# Netscape HTTP Cookie File",
            ".example.com\tTRUE\t/\tTRUE\t\(now - 10)\ta\t1",
            ".example.com\tTRUE\t/\tTRUE\t\(now - 10)\tb\t2",
        ].joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNil(NetscapeCookieFile.cookieHeader(
            for: URL(string: "https://example.com/")!, from: file
        ))
    }

    /// 会话 cookie（expiry 字段为 0）视为无过期时间（expiresEpochSeconds = nil），永不因过期被丢。
    func testSessionCookieWithZeroExpiryIsNeverDroppedAsExpired() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-cookie-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("site-example.com.txt")
        try [
            "# Netscape HTTP Cookie File",
            ".example.com\tTRUE\t/\tTRUE\t0\tsession\tkeep",  // expiry 0 = 会话 cookie
        ].joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)

        // read 应把 expiry 0 解析成 nil（无过期时间）。
        let records = try NetscapeCookieFile.read(from: file)
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records[0].expiresEpochSeconds, "expiry 0 应解析为 nil（会话 cookie，无过期时间）")

        // header 不应因“过期”丢掉会话 cookie。
        let header = NetscapeCookieFile.cookieHeader(
            for: URL(string: "https://example.com/")!, from: file
        )
        XCTAssertEqual(header, "session=keep")
    }

    /// write→read 往返：会话 cookie（isSessionOnly）写出 expiry 0，读回为 nil；
    /// 带过期日期的 cookie 写出正整数，读回原值。
    func testWriteReadRoundTripPreservesExpirySemantics() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-cookie-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let futureDate = Date(timeIntervalSince1970: 4_000_000_000)
        let persistent = HTTPCookie(properties: [
            .domain: ".example.com", .path: "/", .name: "persist", .value: "1",
            .secure: "TRUE", .expires: futureDate,
        ])!
        let session = HTTPCookie(properties: [
            .domain: ".example.com", .path: "/", .name: "sess", .value: "2",
            .secure: "TRUE",  // 无 .expires → 会话 cookie
        ])!

        let file = dir.appendingPathComponent("site-example.com.txt")
        try NetscapeCookieFile.write(cookies: [persistent, session], to: file)
        let records = try NetscapeCookieFile.read(from: file)

        let byName = Dictionary(uniqueKeysWithValues: records.map { ($0.name, $0) })
        // 持久 cookie 写出正整数 expiry、读回为正（HTTPCookie 可能对远期日期做上限钳制，
        // 故只断言“有正过期时间”而非精确值）；会话 cookie 往返后仍为 nil。
        let persistExpiry = try XCTUnwrap(byName["persist"]?.expiresEpochSeconds)
        XCTAssertGreaterThan(persistExpiry, Int(Date().timeIntervalSince1970),
                             "持久 cookie 往返后应保留一个未来的过期时间")
        XCTAssertNil(byName["sess"]?.expiresEpochSeconds, "会话 cookie 往返后仍应是 nil（无过期）")
    }
}
