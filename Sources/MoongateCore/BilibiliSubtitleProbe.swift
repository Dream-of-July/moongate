import Foundation

/// Bilibili 字幕探针。
///
/// 背景：Bilibili 的字幕列表（`player/v2`）在未登录时返回空，yt-dlp 因此也拿不到字幕，
/// 于是「自动」模式会静默回退到 AI 识别 —— 即使视频其实带有中文 CC。
/// 但公开的 `web-interface/view` 接口在未登录时**仍会列出字幕的存在性**（语言、是否 AI 生成），
/// 只是不给下载地址。用它做一次轻量探测，就能在 Ready 页告诉用户「该视频有字幕，登录后可直接使用」。
///
/// 该探针只读、不带 cookie、不做任何副作用；失败一律降级为「未探测到」，绝不阻塞或破坏解析。
public enum BilibiliSubtitleProbe {

    /// 探测到的字幕存在性摘要。
    public struct Result: Sendable, Equatable {
        /// 规范化后的语言码（如 "zh-Hans"），去重后按出现顺序排列。
        public let languageCodes: [String]
        /// 是否至少有一条人工字幕（非 AI 生成）。
        public let hasHumanSubtitle: Bool

        public var hasAny: Bool { !languageCodes.isEmpty }
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    /// 从 Bilibili 视频页 URL 提取 BVID。仅支持标准 `bilibili.com/video/BV...`，
    /// 不解析 b23.tv 短链（需重定向，交由 yt-dlp 处理，此处只做零成本的存在性提示）。
    public static func bvid(from urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host?.lowercased(),
              host == "bilibili.com" || host == "www.bilibili.com" || host == "m.bilibili.com" else {
            return nil
        }
        // 路径或 query 里的 BV 号：BV + 10 位 [0-9A-Za-z]。
        guard let match = urlString.range(
            of: #"BV[0-9A-Za-z]{10}"#,
            options: .regularExpression
        ) else { return nil }
        return String(urlString[match])
    }

    /// 探测该 Bilibili 视频是否带字幕。非 Bilibili URL、无法提取 BVID、网络失败、
    /// 或接口未列出字幕时返回 nil（表示「无可用提示」，调用方按无字幕处理）。
    public static func probe(urlString: String) async -> Result? {
        guard let bvid = bvid(from: urlString) else { return nil }
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return parse(data: data)
    }

    /// 解析 `web-interface/view` 响应中的 `data.subtitle.list`。测试可直接调用。
    public static func parse(data: Data) -> Result? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              (root["code"] as? Int) == 0,
              let dataDict = root["data"] as? [String: Any],
              let subtitle = dataDict["subtitle"] as? [String: Any],
              let list = subtitle["list"] as? [[String: Any]],
              !list.isEmpty else {
            return nil
        }
        var seen: Set<String> = []
        var codes: [String] = []
        var hasHuman = false
        for entry in list {
            let lan = (entry["lan"] as? String) ?? ""
            let normalized = LanguageCatalog.normalize(lan)
            guard !normalized.isEmpty else { continue }
            // ai_type / ai_status: 0 表示人工字幕（非 AI 自动生成）。
            let aiType = (entry["ai_type"] as? Int) ?? 0
            if aiType == 0 { hasHuman = true }
            if !seen.contains(normalized) {
                seen.insert(normalized)
                codes.append(normalized)
            }
        }
        guard !codes.isEmpty else { return nil }
        return Result(languageCodes: codes, hasHumanSubtitle: hasHuman)
    }
}
