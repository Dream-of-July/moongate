import Foundation

// MARK: - Netscape cookies.txt

/// 把 App 内 WKWebView 登录后取到的 cookies 导出成 yt-dlp 可读的 Netscape 格式文件。
/// 文件属于登录凭证，权限固定 0600，只落在本地 Application Support 目录。
public enum NetscapeCookieFile {
    public struct Record: Sendable, Equatable {
        public let domain: String
        public let path: String
        public let isSecure: Bool
        public let expiresEpochSeconds: Int?
        public let name: String
        public let value: String
    }

    /// 凭证文件创建属性：POSIX 平台 0600；Windows 无 POSIX 权限位（详见 docs/WINDOWS.md）。
    static var secureFileAttributes: [FileAttributeKey: Any]? {
        #if os(Windows)
        return nil
        #else
        return [.posixPermissions: 0o600]
        #endif
    }


    /// 写入 Netscape 格式 cookies 文件（覆盖旧内容）。
    /// - 首行固定 "# Netscape HTTP Cookie File"。
    /// - 每行 7 个制表符分隔字段：domain、includeSubdomains、path、secure、expiry、name、value；
    ///   domain 以 "." 开头时 includeSubdomains 为 TRUE。
    /// - session cookie 的 expiry 写 0。
    /// - 字段里含制表符或换行会破坏行格式，这类 cookie 直接跳过。
    /// - 自动创建父目录，文件权限设为 0600。
    public static func write(cookies: [HTTPCookie], to url: URL) throws {
        var lines = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            let textFields = [cookie.domain, cookie.path, cookie.name, cookie.value]
            if textFields.contains(where: { field in
                field.contains("\t") || field.contains("\n") || field.contains("\r")
            }) {
                continue
            }
            let includeSubdomains = cookie.domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let secure = cookie.isSecure ? "TRUE" : "FALSE"
            let expiry: Int
            if cookie.isSessionOnly {
                expiry = 0
            } else if let date = cookie.expiresDate {
                expiry = max(0, Int(date.timeIntervalSince1970))
            } else {
                expiry = 0
            }
            lines.append([
                cookie.domain, includeSubdomains, cookie.path,
                secure, String(expiry), cookie.name, cookie.value,
            ].joined(separator: "\t"))
        }

        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        // createFile 带权限一步创建（覆盖旧文件），不存在先写 0644 再收紧的窗口期。
        let created = fm.createFile(
            atPath: url.path,
            contents: data,
            attributes: Self.secureFileAttributes
        )
        guard created else {
            try? fm.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    /// 读取 Netscape 格式 cookies 文件，跳过注释、空行与字段不足的行。
    public static func read(from url: URL) throws -> [Record] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let content = try String(contentsOf: url, encoding: .utf8)
        var records: [Record] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 7 else { continue }
            let expiry = Int(fields[4]).flatMap { $0 > 0 ? $0 : nil }
            records.append(Record(
                domain: fields[0],
                path: fields[2],
                isSecure: fields[3].caseInsensitiveCompare("TRUE") == .orderedSame,
                expiresEpochSeconds: expiry,
                name: fields[5],
                value: fields[6]
            ))
        }
        return records
    }

    /// 为指定 URL 从 Netscape jar 生成 HTTP Cookie header。
    public static func cookieHeader(for url: URL, from fileURL: URL) -> String? {
        guard let host = url.host else { return nil }
        let isHTTPS = (url.scheme?.lowercased() == "https")
        let requestPath = url.path.isEmpty ? "/" : url.path
        let now = Int(Date().timeIntervalSince1970)
        let pairs = ((try? read(from: fileURL)) ?? []).filter { record in
            if record.isSecure && !isHTTPS { return false }
            if let expiry = record.expiresEpochSeconds, expiry <= now { return false }
            if !CookieSites.domainMatches(host: host, cookieDomain: record.domain) { return false }
            let cookiePath = record.path.isEmpty ? "/" : record.path
            return requestPath == cookiePath
                || requestPath.hasPrefix(cookiePath.hasSuffix("/") ? cookiePath : cookiePath + "/")
        }
        .sorted { lhs, rhs in lhs.path.count > rhs.path.count }
        .map { "\($0.name)=\($0.value)" }
        guard !pairs.isEmpty else { return nil }
        return pairs.joined(separator: "; ")
    }

    /// 删除 cookies 文件（清除登录态）；文件不存在时静默忽略。
    public static func clear(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
