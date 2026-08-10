import Foundation
import MoongateMobileCore

// MARK: - 错误

public enum MoongateError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case sniffFailed(String)
    case analyzeFailed(String)
    case updateFailed(String)
    case downloadFailed(String)
    /// 站点风控/会员限制，需要用户在 App 内登录该站点后重试。关联值为站点 host（如 "youtube.com"）。
    case loginRequired(String)
    /// 站点需要用户在内置网页完成登录、验证或风控确认后，保存 Cookie 再重试。
    case siteCookieRequired(site: String, url: String, reason: String)
    case translateFailed(String)
    case burnFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name):
            return CoreL10n.t(L.Core.errorBinaryNotFound, name, name)
        case .sniffFailed(let reason):
            return CoreL10n.t(L.Core.errorSniffFailed, reason)
        case .analyzeFailed(let reason):
            return CoreL10n.t(L.Core.errorAnalyzeFailed, reason)
        case .updateFailed(let reason):
            return CoreL10n.t(L.Core.errorUpdateFailed, reason)
        case .downloadFailed(let reason):
            return CoreL10n.t(L.Core.errorDownloadFailed, reason)
        case .loginRequired(let site):
            return CoreL10n.t(L.Core.errorLoginRequired, site)
        case .siteCookieRequired(let site, _, let reason):
            return CoreL10n.text(
                en: "\(site) needs browser verification or sign-in before Moongate can access the video. Open the page here, save the site cookies, then Moongate will retry.\n\(reason)",
                zhHans: "\(site) 需要先完成网页登录或验证，月之门才能访问真实视频页面。请打开页面并保存站点验证信息，随后会自动重试。\n\(reason)",
                zhHant: "\(site) 需要先完成網頁登入或驗證，月之門才能存取真實影片頁面。請打開頁面並儲存站點驗證資訊，隨後會自動重試。\n\(reason)"
            )
        case .translateFailed(let reason):
            return CoreL10n.t(L.Core.errorTranslateFailed, reason)
        case .burnFailed(let reason):
            return CoreL10n.t(L.Core.errorBurnFailed, reason)
        case .cancelled:
            return CoreL10n.t(L.Core.errorCancelled)
        }
    }
}

// MARK: - 链接解析候选

/// 一条用户粘贴的链接背后可能藏着多个视频（例如页面主视频 + 内嵌的 YouTube 轮播）。
/// `resolveCandidates` 把它们全部找出来，交给用户选择。
public struct VideoCandidate: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case pageMain    // 页面的主视频（直链文件等）
        case directFile  // 直链视频文件（mp4 / m3u8 / webm …）
        case youtube     // 内嵌 YouTube 视频
        case vimeo       // 内嵌 Vimeo 视频
        case supported   // yt-dlp 原生支持的链接（无需嗅探）
    }

    /// 稳定标识：解析后的最终 URL 字符串
    public var id: String { url }
    /// 交给 `analyze(url:)` 的 URL
    public let url: String
    public let kind: Kind
    /// 尽力获取的标题（YouTube 走 oEmbed；直链用文件名；主视频用页面标题）
    public var title: String
    /// 补充说明，例如 "assets.nintendo.com · mp4 直链" 或 "YouTube"
    public var detail: String?
    /// B站合集分集序号（从 1 开始）；nil 表示非分集候选。
    public var partIndex: Int?
    /// B站合集总集数；nil 表示非分集候选。
    public var partCount: Int?
    /// B站合集子合集标题（如「国内」/「国外」）；nil 表示不属于子合集或未知。
    public var subcollectionTitle: String?

    public init(
        url: String,
        kind: Kind,
        title: String,
        detail: String? = nil,
        partIndex: Int? = nil,
        partCount: Int? = nil,
        subcollectionTitle: String? = nil
    ) {
        self.url = url
        self.kind = kind
        self.title = title
        self.detail = detail
        self.partIndex = partIndex
        self.partCount = partCount
        self.subcollectionTitle = subcollectionTitle
    }

    /// 从 yt-dlp 返回的 B站 playlist JSON 生成分集候选。
    /// 契约：仅当 `_type == "playlist"` 且 entries ≥ 2 时返回候选数组；
    /// 单条 entry、非 playlist、缺 entries 字段一律返回 nil，调用方走原有单候选路径。
    public static func bilibiliPlaylistCandidates(
        from json: [String: Any],
        subcollectionTitleByBV: [String: String] = [:]
    ) -> [VideoCandidate]? {
        guard json["_type"] as? String == "playlist",
              let entries = json["entries"] as? [[String: Any]],
              entries.count >= 2 else {
            return nil
        }
        let playlistID = json["id"] as? String
        let playlistTitle = json["title"] as? String
        let partCount = entries.count
        var candidates: [VideoCandidate] = []
        for (offset, entry) in entries.enumerated() {
            let partIndex = offset + 1
            guard let url = Self.partURL(from: entry, playlistID: playlistID, partIndex: partIndex) else {
                continue
            }
            let title = partTitle(from: entry["title"] as? String, playlistTitle: playlistTitle)
            let duration = (entry["duration"] as? NSNumber)?.doubleValue
            let formatted = formattedDuration(duration)
            candidates.append(VideoCandidate(
                url: url,
                kind: .supported,
                title: title,
                detail: formatted.isEmpty ? nil : formatted,
                partIndex: partIndex,
                partCount: partCount,
                subcollectionTitle: subcollectionTitleByBV[Self.bvid(from: entry) ?? ""]
            ))
        }
        return candidates.isEmpty ? nil : candidates
    }

    /// 从 yt-dlp 的 playlist 包装 dict 提取第一个 entry 的 dict（video 语义）。
    /// 契约：仅当 `_type == "playlist"` 且 entries 非空时返回 entries.first，否则 nil。
    /// 用于把 1 分P 合集等 playlist 包装在解析阶段提纯为单条 video dict，
    /// 避免 playlist 包装 dict 进入缓存导致 analyze 拿不到 formats/subtitles/正确标题。
    public static func firstEntryDict(from playlistDict: [String: Any]) -> [String: Any]? {
        guard playlistDict["_type"] as? String == "playlist",
              let entries = playlistDict["entries"] as? [[String: Any]],
              let first = entries.first else {
            return nil
        }
        return first
    }

    /// B站分集 URL 构造：优先 entry.webpage_url；缺省用顶层 playlist id + ?p=N；
    /// 再缺省用 entry id 构造；三者皆无返回 nil。
    private static func partURL(from entry: [String: Any], playlistID: String?, partIndex: Int) -> String? {
        if let webpageURL = entry["webpage_url"] as? String, !webpageURL.isEmpty {
            return webpageURL
        }
        if let playlistID, !playlistID.isEmpty {
            return "https://www.bilibili.com/video/\(playlistID)?p=\(partIndex)"
        }
        if let entryID = entry["id"] as? String, !entryID.isEmpty {
            return "https://www.bilibili.com/video/\(entryID)"
        }
        return nil
    }

    /// 从 playlist entry 提取 BVID（用于子合集归属查询）。
    /// 优先取 entry.bvid 字段，其次从 webpage_url / id 里匹配 BV 号。
    private static func bvid(from entry: [String: Any]) -> String? {
        if let bvid = entry["bvid"] as? String, !bvid.isEmpty { return bvid }
        let sources = [entry["webpage_url"] as? String, entry["id"] as? String].compactMap { $0 }
        for source in sources {
            if let range = source.range(of: #"BV[0-9A-Za-z]{10}"#, options: .regularExpression) {
                return String(source[range])
            }
        }
        return nil
    }

    /// 把 B站分集 entry 标题（如 "合集标题 p01 曙光"）提纯为纯分集名（"曙光"）。
    /// 先去掉前缀中的 playlistTitle（含紧跟的分隔符/空白），再尝试剥离 "pNN"/"P NN" 序号前缀并 trim；
    /// 任一步失败（playlistTitle 为 nil、不在前缀、无序号）或结果为空时返回原 entryTitle（非空时）。
    public static func partTitle(from entryTitle: String?, playlistTitle: String?) -> String {
        guard let entry = entryTitle,
              !entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let trimmedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = trimmedEntry
        // 第一步：去掉前缀中的 playlistTitle（含紧跟的分隔符/空白）。
        if let playlistTitle, !playlistTitle.isEmpty {
            guard let range = name.range(of: playlistTitle),
                  range.lowerBound == name.startIndex else {
                return trimmedEntry
            }
            name.removeSubrange(name.startIndex..<range.upperBound)
            let separators = CharacterSet(charactersIn: " ：:·-_|/\\（）()【】[]")
                .union(.whitespacesAndNewlines)
            while let first = name.unicodeScalars.first, separators.contains(first) {
                name = String(name.unicodeScalars.dropFirst())
            }
        } else {
            return trimmedEntry
        }
        // 第二步：剥离 "pNN"/"P NN" 之类的序号前缀并 trim 空白。
        let result = stripPartNumberPrefix(name).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? trimmedEntry : result
    }

    /// 剥离 "pNN"/"P NN" 前缀；没有该前缀时原样返回。
    private static func stripPartNumberPrefix(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "p" || first == "P" else {
            return trimmed
        }
        var rest = trimmed.dropFirst()
        while let c = rest.first, c.isWhitespace {
            rest = rest.dropFirst()
        }
        var digitCount = 0
        for c in rest {
            guard c.isNumber else { break }
            digitCount += 1
        }
        guard digitCount > 0 else { return trimmed }
        return String(rest.dropFirst(digitCount)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 时长上限：约 1000 年。真实视频时长不可能达到；用于挡掉超大有限值——
    /// 1e18 级会让 String(format:) 输出天文数字垃圾串，1e19 级会触发 Int 转换 fatal trap。
    private static let maxDurationSeconds: Double = 31_536_000_000

    /// 时长格式化为 "3:29"（分:秒），>1 小时用 "H:MM:SS"；nil/非法值返回空字符串。
    /// 取整规则：`seconds.rounded()`（如 59.6 → "1:00"）。
    public static func formattedDuration(_ seconds: Double?) -> String {
        guard let seconds,
              seconds.isFinite,
              seconds >= 0,
              seconds <= Double(Int.max),
              seconds <= Self.maxDurationSeconds else { return "" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - B站合集（ugc_season）信息

/// B站合集（大合集）信息，来自 view 接口的 `data.ugc_season`。
public struct BilibiliSeasonInfo: Sendable, Equatable {
    public let seasonID: Int
    public let seasonTitle: String
    public let sections: [BilibiliSection]

    public init(seasonID: Int, seasonTitle: String, sections: [BilibiliSection]) {
        self.seasonID = seasonID
        self.seasonTitle = seasonTitle
        self.sections = sections
    }
}

/// B站合集的一个子合集（section），如「国内」/「国外」。
public struct BilibiliSection: Sendable, Equatable {
    public let title: String
    public let episodes: [BilibiliEpisode]

    public init(title: String, episodes: [BilibiliEpisode]) {
        self.title = title
        self.episodes = episodes
    }
}

/// 子合集内的一集。
public struct BilibiliEpisode: Sendable, Equatable {
    public let bvid: String
    public let title: String
    public let duration: Double

    public init(bvid: String, title: String, duration: Double) {
        self.bvid = bvid
        self.title = title
        self.duration = duration
    }
}

public extension VideoCandidate {

    /// 从 B站 view 接口 JSON 解析 `data.ugc_season`。字段缺失/类型异常时：
    /// - 顶层 data 或 ugc_season 缺失/损坏 → nil（调用方降级到旧路径）
    /// - ugc_season 在但 sections 缺失/为空 → 返回空 sections 的 info（不返回 nil）
    static func parseBilibiliSeasonInfo(from json: [String: Any]) -> BilibiliSeasonInfo? {
        guard let data = json["data"] as? [String: Any],
              let ugc = data["ugc_season"] as? [String: Any],
              let seasonID = ugc["id"] as? Int else {
            return nil
        }
        let seasonTitle = (ugc["title"] as? String) ?? ""
        var sections: [BilibiliSection] = []
        if let rawSections = ugc["sections"] as? [[String: Any]] {
            for raw in rawSections {
                let sectionTitle = (raw["title"] as? String) ?? ""
                var episodes: [BilibiliEpisode] = []
                if let rawEpisodes = raw["episodes"] as? [[String: Any]] {
                    for rawEpisode in rawEpisodes {
                        guard let bvid = rawEpisode["bvid"] as? String, !bvid.isEmpty else { continue }
                        let episodeTitle = (rawEpisode["title"] as? String) ?? ""
                        let duration: Double
                        if let arc = rawEpisode["arc"] as? [String: Any] {
                            // 真实 B 站 API 的时长在 arc.duration。
                            duration = (arc["duration"] as? NSNumber)?.doubleValue
                                ?? (rawEpisode["duration"] as? NSNumber)?.doubleValue
                                ?? 0
                        } else {
                            duration = (rawEpisode["duration"] as? NSNumber)?.doubleValue ?? 0
                        }
                        episodes.append(BilibiliEpisode(bvid: bvid, title: episodeTitle, duration: duration))
                    }
                }
                sections.append(BilibiliSection(title: sectionTitle, episodes: episodes))
            }
        }
        return BilibiliSeasonInfo(seasonID: seasonID, seasonTitle: seasonTitle, sections: sections)
    }

    /// 查 bvid 所在的子合集标题；bvid 不在任何 section 或 info 为 nil 时返回 nil。
    static func sectionTitle(forBV bvid: String, in info: BilibiliSeasonInfo?) -> String? {
        guard let info else { return nil }
        for section in info.sections where section.episodes.contains(where: { $0.bvid == bvid }) {
            return section.title
        }
        return nil
    }

    /// 把 BilibiliSeasonInfo 的 episodes 展平成候选数组。
    /// partIndex 按合集全局顺序、partCount = 总集数、title = episode.title、detail = 时长、
    /// url = https://www.bilibili.com/video/<bvid>、subcollectionTitle = section.title。
    /// 不调用 partTitle（episode.title 已是最终标题）。
    static func bilibiliSeasonCandidates(from info: BilibiliSeasonInfo) -> [VideoCandidate] {
        let partCount = info.sections.reduce(0) { $0 + $1.episodes.count }
        var candidates: [VideoCandidate] = []
        var partIndex = 0
        for section in info.sections {
            for episode in section.episodes {
                partIndex += 1
                let formatted = formattedDuration(episode.duration)
                candidates.append(VideoCandidate(
                    url: "https://www.bilibili.com/video/\(episode.bvid)",
                    kind: .supported,
                    title: episode.title,
                    detail: formatted.isEmpty ? nil : formatted,
                    partIndex: partIndex,
                    partCount: partCount,
                    subcollectionTitle: section.title
                ))
            }
        }
        return candidates
    }
}

// MARK: - 候选按子合集分组

/// B站大合集候选按子合集分组后的结果，供 UI 做「目录式」浏览：
/// 第一层子合集列表 → 点开看组内视频。
/// title = nil 表示无分组的普通候选（subcollectionTitle 为 nil）。
public struct CandidateGroup: Sendable, Equatable {
    public let title: String?
    public let candidates: [VideoCandidate]

    public init(title: String?, candidates: [VideoCandidate]) {
        self.title = title
        self.candidates = candidates
    }

    /// 保序分组：按 subcollectionTitle 分组（保持候选原顺序），组顺序 = 首次出现顺序；
    /// 无 subcollectionTitle 的候选归为一组（title = nil），放在最后。
    /// 空 candidates 返回 []。
    public static func groupedCandidates(_ candidates: [VideoCandidate]) -> [CandidateGroup] {
        var order: [String] = []
        var grouped: [String: [VideoCandidate]] = [:]
        var ungrouped: [VideoCandidate] = []
        for candidate in candidates {
            if let title = candidate.subcollectionTitle {
                if grouped[title] == nil {
                    grouped[title] = []
                    order.append(title)
                }
                grouped[title]?.append(candidate)
            } else {
                ungrouped.append(candidate)
            }
        }
        var result = order.map { CandidateGroup(title: $0, candidates: grouped[$0] ?? []) }
        if !ungrouped.isEmpty {
            result.append(CandidateGroup(title: nil, candidates: ungrouped))
        }
        return result
    }
}

// MARK: - 解析结果

/// 视频动态范围。来自 yt-dlp 的 dynamic_range 字段。
public enum DynamicRange: String, Codable, Sendable, Equatable, CaseIterable {
    case sdr
    case hdr10
    case dolbyVision

    /// 从 yt-dlp dynamic_range 字符串解析（SDR/HDR/HDR10/HDR10+/DV/Dolby Vision 等）。
    public init(ytDlpValue raw: String?) {
        let v = (raw ?? "").uppercased()
        if v.contains("DV") || v.contains("DOLBY") {
            self = .dolbyVision
        } else if v.contains("HDR") {
            self = .hdr10
        } else {
            self = .sdr
        }
    }

    public var isHDR: Bool { self != .sdr }

    /// UI 短标签。
    public var badge: String? {
        switch self {
        case .sdr: return nil
        case .hdr10: return "HDR"
        case .dolbyVision: return CoreL10n.t(L.Core.dolbyVisionBadge)
        }
    }
}

/// 下载后输出格式（用户在选分辨率页选择）。original = 保持源，不转码。
public enum OutputFormat: String, Codable, Sendable, Equatable, CaseIterable {
    case original
    case mp4H264
    case mp4H265
    case mkv

    public var displayName: String {
        switch self {
        case .original: return CoreL10n.t(L.Core.outputOriginal)
        case .mp4H264: return CoreL10n.t(L.Core.outputH264)
        case .mp4H265: return CoreL10n.t(L.Core.outputH265)
        case .mkv: return CoreL10n.t(L.Core.outputMKV)
        }
    }
}

public struct FormatChoice: Identifiable, Hashable, Sendable {
    /// yt-dlp 的 -f 格式选择串（例如 "bv*[height<=720]+ba/b[height<=720]"），
    /// 音频选项用特殊值 "audio"（引擎据此改用 -x 提取音频）。
    public let id: String
    /// 例如 "1080p · mp4" / "原始文件 · mp4" / "仅音频 · m4a"
    public let label: String
    /// 例如 "≈ 42 MB"、编码信息；未知则为 nil
    public let detail: String?
    public let isAudioOnly: Bool
    /// 该档是否有 HDR 源可选（同分辨率下存在 HDR 流）。
    public let hdrAvailable: Bool
    /// 源视频编码简称（如 "vp9"/"av1"/"h264"），用于转码决策与标注；未知为 nil。
    public let sourceVCodec: String?
    /// 源容器扩展名（如 "webm"/"mp4"）；未知为 nil。
    public let sourceContainer: String?

    public init(
        id: String,
        label: String,
        detail: String? = nil,
        isAudioOnly: Bool = false,
        hdrAvailable: Bool = false,
        sourceVCodec: String? = nil,
        sourceContainer: String? = nil
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.isAudioOnly = isAudioOnly
        self.hdrAvailable = hdrAvailable
        self.sourceVCodec = sourceVCodec
        self.sourceContainer = sourceContainer
    }
}

public enum SubtitleSourceKind: String, Codable, Hashable, Sendable {
    case manual
    case platformAuto
    case hlsManifest
    case localASR
    case cloudASR
    case importedFile
}

public struct SubtitleTrackID: Codable, Hashable, Sendable {
    public let languageCode: String
    public let sourceKind: SubtitleSourceKind
    public let provider: String
    public let variant: String?

    public var rawValue: String {
        [
            sourceKind.rawValue,
            provider,
            languageCode,
            variant ?? ""
        ].map(Self.encodeComponent).joined(separator: "|")
    }

    public init(
        languageCode: String,
        sourceKind: SubtitleSourceKind,
        provider: String,
        variant: String? = nil
    ) {
        self.languageCode = languageCode
        self.sourceKind = sourceKind
        self.provider = provider
        self.variant = variant
    }

    /// Parses a v0.8 stable source id. Legacy language-only ids are interpreted as manual subtitles.
    public init(rawValue: String) {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 4,
           let kind = SubtitleSourceKind(rawValue: Self.decodeComponent(parts[0])) {
            self.sourceKind = kind
            self.provider = Self.decodeComponent(parts[1])
            self.languageCode = Self.decodeComponent(parts[2])
            let decodedVariant = Self.decodeComponent(parts[3])
            self.variant = decodedVariant.isEmpty ? nil : decodedVariant
        } else {
            self.sourceKind = .manual
            self.provider = "legacy"
            self.languageCode = rawValue
            self.variant = nil
        }
    }

    private static func encodeComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
    }

    private static func decodeComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%7C", with: "|")
            .replacingOccurrences(of: "%25", with: "%")
    }
}

public struct SubtitleChoice: Identifiable, Hashable, Sendable {
    /// Stable source identity. It includes language, source kind, provider, and variant.
    public let id: String
    /// Language code passed to yt-dlp or translation readiness, such as "en" or "zh-Hans".
    public let languageCode: String
    /// Display label, such as "英文 (en)".
    public let label: String
    public let sourceKind: SubtitleSourceKind
    public let provider: String
    public let variant: String?
    public let qualityHint: String?
    public let metadata: [String: String]
    /// Whether this is a platform auto-generated subtitle.
    public let isAuto: Bool

    public init(
        languageCode: String,
        label: String,
        sourceKind: SubtitleSourceKind,
        provider: String = "yt-dlp",
        variant: String? = nil,
        qualityHint: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let trackID = SubtitleTrackID(
            languageCode: languageCode,
            sourceKind: sourceKind,
            provider: provider,
            variant: variant
        )
        self.id = trackID.rawValue
        self.languageCode = languageCode
        self.label = label
        self.sourceKind = sourceKind
        self.provider = provider
        self.variant = variant
        self.qualityHint = qualityHint
        self.metadata = metadata
        self.isAuto = sourceKind == .platformAuto
    }

    /// Legacy convenience initializer. `id` used to be a language code before v0.8.
    public init(id legacyLanguageCode: String, label: String, isAuto: Bool) {
        self.init(
            languageCode: legacyLanguageCode,
            label: label,
            sourceKind: isAuto ? .platformAuto : .manual
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Upper-level language aggregation consumed by the ready page UI. A language groups all of its
/// technical tracks (manual / platform-auto / local ASR / cloud ASR) so users pick a language, not a source.
/// Pure derived view: never persisted, never sent to yt-dlp directly.
public struct SubtitleLanguageChoice: Identifiable, Hashable, Sendable {
    /// Normalized language code (lowercased, first `-` segment), e.g. "ja". Also the identity.
    public let languageCode: String
    /// Display label, taken from the best (first non-localASR) track in the group.
    public let displayLabel: String
    /// Tracks for this language, sorted manual → platformAuto → cloudASR → localASR.
    public let tracks: [SubtitleChoice]

    public var id: String { languageCode }

    public var hasManualTrack: Bool { tracks.contains { $0.sourceKind == .manual } }
    public var hasAutoTrack: Bool { tracks.contains { $0.sourceKind == .platformAuto } }
    /// Whether the group carries a local-ASR option (independent of runtime readiness).
    public var supportsLocalASR: Bool { tracks.contains { $0.sourceKind == .localASR } }
    /// Preferred technical track: manual > auto > localASR (tracks are pre-sorted).
    public var preferredTrack: SubtitleChoice? { tracks.first }

    public init(languageCode: String, displayLabel: String, tracks: [SubtitleChoice]) {
        self.languageCode = languageCode
        self.displayLabel = displayLabel
        self.tracks = tracks
    }

    /// Normalizes a subtitle language code to a stable bucket key: lowercased, first `-` segment.
    /// So "ja", "ja-JP", "ja-orig" all collapse to "ja".
    public static func normalizedLanguageCode(_ code: String) -> String {
        LanguageCatalog.normalize(code)
    }

    /// Sort rank for technical tracks within a language group.
    public static func trackRank(_ kind: SubtitleSourceKind) -> Int {
        switch kind {
        case .manual: return 0
        case .platformAuto: return 1
        case .hlsManifest: return 2
        case .cloudASR: return 3
        case .localASR: return 4
        case .importedFile: return 5
        }
    }

    /// Groups flat subtitle choices by normalized language code into ordered language choices.
    /// Group order follows first appearance of each language; tracks within a group are stably
    /// sorted by source rank. Deterministic, no regex.
    public static func aggregate(_ choices: [SubtitleChoice]) -> [SubtitleLanguageChoice] {
        var order: [String] = []
        var grouped: [String: [SubtitleChoice]] = [:]
        for choice in choices {
            let key = normalizedLanguageCode(choice.languageCode)
            guard !key.isEmpty else { continue }
            if grouped[key] == nil {
                grouped[key] = []
                order.append(key)
            }
            grouped[key]?.append(choice)
        }
        return order.map { key in
            let tracks = (grouped[key] ?? []).enumerated().sorted { lhs, rhs in
                let lr = trackRank(lhs.element.sourceKind)
                let rr = trackRank(rhs.element.sourceKind)
                if lr != rr { return lr < rr }
                return lhs.offset < rhs.offset
            }.map(\.element)
            let label = tracks.first { $0.sourceKind != .localASR && $0.sourceKind != .cloudASR }?.label
                ?? tracks.first?.label
                ?? key
            return SubtitleLanguageChoice(languageCode: key, displayLabel: label, tracks: tracks)
        }
    }
}

public struct VideoInfo: Sendable {
    public let sourceURL: String
    /// yt-dlp 信息里的视频 id（用于定位产出文件）
    public let videoID: String
    public let title: String
    /// 形如 "2:31"；未知为 nil
    public let durationText: String?
    public let thumbnailURL: URL?
    public let uploader: String?
    /// yt-dlp `language` field, normalized by `LanguageCatalog`; nil when the extractor does not know.
    public let detectedLanguageCode: String?
    /// 视频简介（yt-dlp description）；无简介为 nil。用于 AI 总结的回退数据源。
    public let description: String?
    /// 按推荐顺序排列（第一个为推荐档），保证至少一个元素
    public let formats: [FormatChoice]
    /// 真实字幕在前、自动字幕在后；可能为空
    public let subtitles: [SubtitleChoice]

    public init(
        sourceURL: String, videoID: String, title: String,
        durationText: String?, thumbnailURL: URL?, uploader: String?,
        detectedLanguageCode: String? = nil,
        description: String? = nil,
        formats: [FormatChoice], subtitles: [SubtitleChoice]
    ) {
        self.sourceURL = sourceURL
        self.videoID = videoID
        self.title = title
        self.durationText = durationText
        self.thumbnailURL = thumbnailURL
        self.uploader = uploader
        self.detectedLanguageCode = {
            let normalized = LanguageCatalog.normalize(detectedLanguageCode)
            return normalized.isEmpty ? nil : normalized
        }()
        self.description = description
        self.formats = formats
        self.subtitles = subtitles
    }
}

// MARK: - 下载

public struct DownloadRequest: Sendable {
    public let url: String
    /// 视频 id（来自 VideoInfo.videoID），用于在目标目录中识别产出文件
    public let videoID: String
    /// FormatChoice.id
    public let formatID: String
    /// 选中的真实字幕语言代码
    public let subtitleLangs: [String]
    /// 选中的自动字幕语言代码
    public let autoSubtitleLangs: [String]
    /// v0.8 stable subtitle source identity. Legacy language arrays remain for compatibility.
    public let subtitleTracks: [SubtitleChoice]
    /// The single primary subtitle source selected on the ready page. Legacy arrays remain as yt-dlp inputs.
    public let primarySubtitleTrackID: String?
    /// The language (normalized code) the user picked on the language-first ready page. The
    /// post-download source resolver uses this for language matching / quality fallback.
    /// nil falls back to `primarySubtitleTrack?.languageCode`.
    public let preferredSubtitleLanguageCode: String?
    /// Three-layer subtitle architecture: this preserves whether the user asked for automatic
    /// source-language detection or explicitly fixed a language. Legacy language fields remain as
    /// concrete yt-dlp / compatibility inputs.
    public let sourceLanguageIntent: SourceLanguageIntent
    /// Source policy selected on the Ready page. The post-download resolver uses it to honor
    /// fixed-source choices instead of silently falling back to another source.
    public let subtitleSourcePolicy: SubtitleSourcePolicy
    /// Optional user-provided subtitle file selected on the Ready page.
    public let importedSubtitleFileURL: URL?
    public let destinationDirectory: URL
    /// 期望的文件名标题。直链/页面主视频的 yt-dlp 标题往往是 CDN 文件名
    /// （如 "homepage_trailer"），此时用嗅探得到的页面标题命名更友好；nil 用 yt-dlp 默认标题。
    public let preferredTitle: String?
    /// 是否优先下载 HDR 流（仅当该档有 HDR 源时有意义）。
    public let preferHDR: Bool
    /// 下载后输出格式；.original 表示不转码（HDR 默认 mkv 封装，SDR 默认 mp4）。
    public let outputFormat: OutputFormat

    public init(
        url: String, videoID: String, formatID: String,
        subtitleLangs: [String], autoSubtitleLangs: [String],
        subtitleTracks: [SubtitleChoice] = [],
        primarySubtitleTrackID: String? = nil,
        preferredSubtitleLanguageCode: String? = nil,
        sourceLanguageIntent: SourceLanguageIntent = .automatic,
        subtitleSourcePolicy: SubtitleSourcePolicy = .autoBest,
        importedSubtitleFileURL: URL? = nil,
        destinationDirectory: URL, preferredTitle: String? = nil,
        preferHDR: Bool = false, outputFormat: OutputFormat = .original
    ) {
        self.url = url
        self.videoID = videoID
        self.formatID = formatID
        self.subtitleLangs = subtitleLangs
        self.autoSubtitleLangs = autoSubtitleLangs
        self.subtitleTracks = subtitleTracks
        self.primarySubtitleTrackID = primarySubtitleTrackID
        self.preferredSubtitleLanguageCode = preferredSubtitleLanguageCode
        self.sourceLanguageIntent = sourceLanguageIntent
        self.subtitleSourcePolicy = subtitleSourcePolicy
        self.importedSubtitleFileURL = importedSubtitleFileURL
        self.destinationDirectory = destinationDirectory
        self.preferredTitle = preferredTitle
        self.preferHDR = preferHDR
        self.outputFormat = outputFormat
    }

    public var requestedSubtitleTracks: [SubtitleChoice] {
        if !subtitleTracks.isEmpty { return subtitleTracks }
        return subtitleLangs.map {
            SubtitleChoice(languageCode: $0, label: $0, sourceKind: .manual)
        } + autoSubtitleLangs.map {
            SubtitleChoice(languageCode: $0, label: $0, sourceKind: .platformAuto)
        }
    }

    public var primarySubtitleTrack: SubtitleChoice? {
        let requested = requestedSubtitleTracks
        if let primarySubtitleTrackID,
           let exact = requested.first(where: { $0.id == primarySubtitleTrackID }) {
            return exact
        }
        return requested.first(where: { $0.sourceKind == .manual })
            ?? requested.first(where: { $0.sourceKind == .platformAuto })
            ?? requested.first
    }

    public var primarySubtitleLanguageCode: String? {
        primarySubtitleTrack?.languageCode
    }

    /// The language the post-download source resolver should match against: the user's
    /// language-first pick, falling back to the primary track's language.
    public var effectivePreferredLanguageCode: String? {
        preferredSubtitleLanguageCode ?? primarySubtitleTrack?.languageCode
    }

    public var ytDlpSubtitleLangs: [String] {
        Self.uniqueForYtDlpSubLangs(requestedSubtitleTracks.filter { $0.sourceKind == .manual }.map(\.languageCode))
    }

    public var ytDlpAutoSubtitleLangs: [String] {
        Self.uniqueForYtDlpSubLangs(requestedSubtitleTracks.filter { $0.sourceKind == .platformAuto }.map(\.languageCode))
    }

    public static func uniqueForYtDlpSubLangs(_ codes: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for code in codes {
            let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }
}

public struct DownloadProgress: Sendable {
    public enum Phase: Sendable, Equatable {
        case preparing      // 启动 yt-dlp、握手中
        case downloading    // 主体下载
        case processing     // 合并 / 转码 / 字幕转换
        case finished
    }

    public let phase: Phase
    /// 0...100；未知为 nil
    public let percent: Double?
    public let speedText: String?
    public let etaText: String?
    /// 处理阶段的具体说明（如「正在合并音视频」「正在转码」）；未知为 nil。
    public let detail: String?

    public init(phase: Phase, percent: Double? = nil, speedText: String? = nil, etaText: String? = nil, detail: String? = nil) {
        self.phase = phase
        self.percent = percent
        self.speedText = speedText
        self.etaText = etaText
        self.detail = detail
    }
}

public struct DownloadResult: Sendable {
    /// 实际写入磁盘的文件（视频 + 字幕）
    public let files: [URL]

    public init(files: [URL]) {
        self.files = files
    }
}

// MARK: - 字幕翻译与烧录

/// 烧录/输出字幕的样式
public enum SubtitleStyle: String, Codable, Sendable {
    /// 原文在上、中文在下
    case bilingual
    /// 仅中文
    case chineseOnly
}

/// 细粒度源字幕片段。YouTube VTT 自动字幕常带词级时间戳，清洗器用它来判断字幕真正应在何时出现/消失。
public struct SubtitleCueSourceFragment: Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String

    public init(startSeconds: Double, endSeconds: Double, text: String) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }
}

/// 一条 SRT 字幕
public struct SubtitleCue: Sendable {
    public let index: Int
    /// SRT 原始时间戳，如 "00:01:02,500"
    public let start: String
    public let end: String
    public var text: String
    public var sourceFragments: [SubtitleCueSourceFragment]

    public init(
        index: Int,
        start: String,
        end: String,
        text: String,
        sourceFragments: [SubtitleCueSourceFragment] = []
    ) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.sourceFragments = sourceFragments
    }
}

/// 字幕翻译器。默认实现 `ConfiguredTranslator`（Translator.swift）：
/// 按设置选择 Anthropic/DeepSeek Messages API 或 OpenAI Responses API 调用配置的模型。
/// 用 `makeTranslator(settings:)` 获取实例。
public protocol SubtitleTranslator: Sendable {
    /// 把 srt 文件翻译成中文，按 style 生成新 srt（双语：中文在上原文在下；仅中文：替换原文），
    /// 写到 srt 同目录、文件名加 ".zh" 后缀；progress 为 0...1。
    /// YouTube 自动字幕的重叠滚动碎句会先被清洗、按句合并再翻译。
    /// control 非空时支持暂停（分块间挂起）与取消；失败抛 MoongateError.translateFailed。
    func translate(
        srtFile: URL,
        style: SubtitleStyle,
        control: TaskControlToken?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

public protocol ContextualSubtitleTranslator: SubtitleTranslator {
    func translate(
        srtFile: URL,
        style: SubtitleStyle,
        context: TranslationContext,
        control: TaskControlToken?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

public extension SubtitleTranslator {
    func translate(
        srtFile: URL,
        style: SubtitleStyle,
        context: TranslationContext,
        control: TaskControlToken?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let translator = self as? any ContextualSubtitleTranslator {
            return try await translator.translate(
                srtFile: srtFile,
                style: style,
                context: context,
                control: control,
                progress: progress
            )
        }
        return try await translate(
            srtFile: srtFile,
            style: style,
            control: control,
            progress: progress
        )
    }

    func translate(
        srtFile: URL,
        style: SubtitleStyle,
        context: TranslationContext,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await translate(
            srtFile: srtFile,
            style: style,
            context: context,
            control: nil,
            progress: progress
        )
    }

    func translate(
        srtFile: URL,
        style: SubtitleStyle,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await translate(srtFile: srtFile, style: style, control: nil, progress: progress)
    }
}

public extension ContextualSubtitleTranslator {
    func translate(
        srtFile: URL,
        style: SubtitleStyle,
        control: TaskControlToken?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await translate(
            srtFile: srtFile,
            style: style,
            context: TranslationContext(),
            control: control,
            progress: progress
        )
    }
}

/// 字幕烧录器。默认实现 `FFmpegBurner`（Burner.swift）：ffmpeg subtitles 滤镜硬烧录。
/// 用 `makeBurner()` 获取实例。
public protocol SubtitleBurner: Sendable {
    /// 把 subtitle 烧录进 video，输出 "<原名>（字幕版).mp4" 风格的新文件（不覆盖原片）；
    /// outputTag 非空时自定义文件名标签，例如直压原字幕模式用 "（字幕版）"。
    /// maxHeight 非空且源更高时缩放到该高度；progress 为 0...1。
    /// backend 决定用硬件（VideoToolbox）还是软件编码器；alwaysH264=true 时无视源编码强制 H.264（兼容优先）。
    /// control 非空时支持暂停/取消（向 ffmpeg 进程树发 SIGSTOP/SIGCONT、取消时终止）。
    /// 失败抛 MoongateError.burnFailed。
    func burn(
        video: URL,
        subtitle: URL,
        maxHeight: Int?,
        backend: EncodeBackend,
        alwaysH264: Bool,
        control: TaskControlToken?,
        outputTag: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

public extension SubtitleBurner {
    func burn(
        video: URL,
        subtitle: URL,
        maxHeight: Int?,
        backend: EncodeBackend = .auto,
        alwaysH264: Bool = false,
        control: TaskControlToken?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await burn(
            video: video, subtitle: subtitle,
            maxHeight: maxHeight, backend: backend, alwaysH264: alwaysH264,
            control: control, outputTag: nil,
            progress: progress
        )
    }

    func burn(
        video: URL,
        subtitle: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await burn(
            video: video, subtitle: subtitle,
            maxHeight: nil, backend: .auto, alwaysH264: false,
            control: nil, outputTag: nil,
            progress: progress
        )
    }
}

// MARK: - 引擎协议

/// 三步流水线：resolve（一条链接里找出所有视频）→ analyze（取格式与字幕）→ download。
/// 实现位于 Engine.swift 的 `YtDlpEngine`；用 `makeDefaultEngine()` 获取默认实例。
public protocol DownloadEngine: Sendable {
    /// 第一步：解析用户粘贴的链接。
    /// - yt-dlp 原生支持的 URL：直接返回单个 `.supported` 候选（不发起网络请求也可以）。
    /// - 不支持的页面：抓取 HTML 嗅探内嵌视频（og:video、video/source 标签、
    ///   YouTube/Vimeo iframe、data-videoid、裸 mp4/m3u8 链接等），返回带标题的候选列表。
    /// - 一个都找不到时抛 `MoongateError.sniffFailed`。
    func resolveCandidates(for input: String) async throws -> [VideoCandidate]

    /// 第二步：完整解析单个候选，返回格式与字幕选项。
    /// 实现可以缓存第一步已经取得的信息避免重复请求。
    func analyze(url: String) async throws -> VideoInfo

    /// 第三步：按用户选择下载。进度经回调上报（任意线程）；
    /// control 非空时支持暂停（SIGSTOP/SIGCONT 进程树）与取消；
    /// 也可通过 Swift 任务取消中止，引擎需负责终止子进程、不留僵尸进程。
    func download(
        _ request: DownloadRequest,
        control: TaskControlToken?,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadResult

    /// 可选：只取字幕文本（不下载视频），用于 AI 内容总结。
    /// 最佳努力：没有字幕或站点不支持时返回 nil，绝不抛错阻断总结流程。
    func fetchSubtitleText(
        url: String,
        preferredLanguages: [String],
        control: TaskControlToken?
    ) async throws -> String?

    /// 可选：展开单视频的全部分 P（B 站等）。单分 P / 合集 / 失败抛错，调用方回退原 URL 走 analyze。
    func expandParts(for url: String) async throws -> [VideoCandidate]
}

public extension DownloadEngine {
    func download(
        _ request: DownloadRequest,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadResult {
        try await download(request, control: nil, progress: progress)
    }

    /// 默认不支持字幕文本抓取（mock/iOS 引擎）；返回 nil 让总结回退到简介。
    func fetchSubtitleText(
        url: String,
        preferredLanguages: [String],
        control: TaskControlToken?
    ) async throws -> String? {
        nil
    }

    /// 默认不支持展开分 P（mock/iOS 引擎）；抛错让调用方回退原 URL 走 analyze。
    func expandParts(for url: String) async throws -> [VideoCandidate] {
        throw ExpandPartsUnavailableError()
    }
}

/// 引擎不提供分 P 展开能力时抛出的默认错误。
public struct ExpandPartsUnavailableError: Error, Sendable {}
