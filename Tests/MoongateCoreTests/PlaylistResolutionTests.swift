import XCTest
@testable import MoongateCore

/// B站合集链接解析后展开显示分集：`VideoCandidate.bilibiliPlaylistCandidates` 及其纯函数契约。
final class PlaylistResolutionTests: XCTestCase {

    // MARK: - fixture

    /// 仿真实 yt-dlp 输出的 B站合集 JSON（_type=playlist，entries 各含 id/title/duration/webpage_url）。
    private func playlistJSON(entryCount: Int, includeWebpageURL: Bool = true) -> [String: Any] {
        let names = ["曙光", "晨曦", "远行", "归途", "星河", "追风", "落霞", "孤帆", "山月", "晴空", "微雨", "长街", "故人", "新芽"]
        let playlistTitle = "合集标题"
        let entries: [[String: Any]] = (0..<max(0, entryCount)).map { offset in
            let index = offset + 1
            let part = String(format: "%02d", index)
            let name = names[(index - 1) % names.count]
            var entry: [String: Any] = [
                "id": "BV1B4nSz6Evp_p\(index)",
                "title": "\(playlistTitle) p\(part) \(name)",
                "duration": Double(index * 62),
                "formats": [],
            ]
            if includeWebpageURL {
                entry["webpage_url"] = "https://www.bilibili.com/video/BV1B4nSz6Evp?p=\(index)"
            }
            return entry
        }
        return [
            "_type": "playlist",
            "id": "BV1B4nSz6Evp",
            "title": playlistTitle,
            "entries": entries,
        ]
    }

    // MARK: - playlist → 候选数组

    func testPlaylistWith14EntriesExpandsToCandidates() throws {
        let candidates = try XCTUnwrap(
            VideoCandidate.bilibiliPlaylistCandidates(from: playlistJSON(entryCount: 14))
        )

        XCTAssertEqual(candidates.count, 14)

        for (index, candidate) in candidates.enumerated() {
            let part = index + 1
            XCTAssertEqual(candidate.partIndex, part, "第 \(part) 条的 partIndex 应为 \(part)")
            XCTAssertEqual(candidate.partCount, 14)
            XCTAssertEqual(candidate.url, "https://www.bilibili.com/video/BV1B4nSz6Evp?p=\(part)")
            XCTAssertEqual(candidate.kind, .supported)
        }

        // 标题提纯：去掉 "合集标题 " 前缀与 "p01 " 序号 → "曙光"。
        XCTAssertEqual(candidates[0].title, "曙光")
        XCTAssertEqual(candidates[13].title, "新芽")
        // 时长 detail：index 1 → 62s → "1:02"；index 2 → 124s → "2:04"。
        XCTAssertEqual(candidates[0].detail, "1:02")
        XCTAssertEqual(candidates[1].detail, "2:04")
    }

    func testPlaylistEntriesWithoutWebpageURLFallBackToPlaylistIDURL() throws {
        let candidates = try XCTUnwrap(
            VideoCandidate.bilibiliPlaylistCandidates(
                from: playlistJSON(entryCount: 2, includeWebpageURL: false)
            )
        )
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].url, "https://www.bilibili.com/video/BV1B4nSz6Evp?p=1")
        XCTAssertEqual(candidates[1].url, "https://www.bilibili.com/video/BV1B4nSz6Evp?p=2")
    }

    func testPlaylistEntriesFallBackToEntryIDURLWhenPlaylistIDMissing() throws {
        var json = playlistJSON(entryCount: 2, includeWebpageURL: false)
        json.removeValue(forKey: "id")
        let candidates = try XCTUnwrap(VideoCandidate.bilibiliPlaylistCandidates(from: json))
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates[0].url, "https://www.bilibili.com/video/BV1B4nSz6Evp_p1")
        XCTAssertEqual(candidates[1].url, "https://www.bilibili.com/video/BV1B4nSz6Evp_p2")
    }

    func testPlaylistEntriesWithoutAnyURLAreSkipped() {
        var json = playlistJSON(entryCount: 2, includeWebpageURL: false)
        json.removeValue(forKey: "id")
        guard let entries = json["entries"] as? [[String: Any]] else {
            return XCTFail("fixture 缺少 entries")
        }
        json["entries"] = entries.map { entry in
            var stripped = entry
            stripped.removeValue(forKey: "id")
            return stripped
        }
        XCTAssertNil(VideoCandidate.bilibiliPlaylistCandidates(from: json))
    }

    func testSingleEntryPlaylistReturnsNil() {
        XCTAssertNil(
            VideoCandidate.bilibiliPlaylistCandidates(from: playlistJSON(entryCount: 1))
        )
    }

    func testNonPlaylistDictReturnsNil() {
        let json: [String: Any] = [
            "_type": "video",
            "id": "BV1B4nSz6Evp",
            "title": "单集视频",
            "duration": 120.0,
        ]
        XCTAssertNil(VideoCandidate.bilibiliPlaylistCandidates(from: json))
    }

    func testMissingEntriesFieldReturnsNil() {
        let json: [String: Any] = [
            "_type": "playlist",
            "id": "BV1B4nSz6Evp",
            "title": "合集标题",
        ]
        XCTAssertNil(VideoCandidate.bilibiliPlaylistCandidates(from: json))
    }

    func testEntriesCountBelowTwoReturnsNil() {
        XCTAssertNil(VideoCandidate.bilibiliPlaylistCandidates(from: playlistJSON(entryCount: 0)))
    }

    // MARK: - firstEntryDict（playlist → 首个 entry 提纯）

    func testFirstEntryDictNormalPlaylistReturnsFirstEntry() {
        let first = VideoCandidate.firstEntryDict(from: playlistJSON(entryCount: 2))
        XCTAssertNotNil(first)
        // 返回的是 entry 而非 playlist 包装：标题是条目标题（含序号），不是合集标题。
        XCTAssertEqual(first?["title"] as? String, "合集标题 p01 曙光")
        XCTAssertEqual(first?["id"] as? String, "BV1B4nSz6Evp_p1")
        XCTAssertNotNil(first?["webpage_url"])
        XCTAssertNil(first?["entries"])
    }

    func testFirstEntryDictSingleEntryPlaylistReturnsThatEntry() {
        // 1 分P 合集：expandPlaylist 时 entries < 2，与 --no-playlist 一样提纯为第一个条目。
        let first = VideoCandidate.firstEntryDict(from: playlistJSON(entryCount: 1))
        XCTAssertNotNil(first)
        XCTAssertEqual(first?["title"] as? String, "合集标题 p01 曙光")
        XCTAssertEqual(first?["duration"] as? Double, 62.0)
        XCTAssertNil(first?["entries"])
    }

    func testFirstEntryDictNonPlaylistReturnsNil() {
        let json: [String: Any] = [
            "_type": "video",
            "id": "BV1B4nSz6Evp",
            "title": "单集视频",
        ]
        XCTAssertNil(VideoCandidate.firstEntryDict(from: json))
    }

    func testFirstEntryDictMissingEntriesReturnsNil() {
        let json: [String: Any] = [
            "_type": "playlist",
            "id": "BV1B4nSz6Evp",
            "title": "合集标题",
        ]
        XCTAssertNil(VideoCandidate.firstEntryDict(from: json))
    }

    func testFirstEntryDictEmptyEntriesReturnsNil() {
        let json: [String: Any] = [
            "_type": "playlist",
            "id": "BV1B4nSz6Evp",
            "title": "合集标题",
            "entries": [],
        ]
        XCTAssertNil(VideoCandidate.firstEntryDict(from: json))
    }

    // MARK: - partTitle

    func testPartTitleStripsPlaylistPrefixAndPartNumber() {
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "合集标题 p01 曙光", playlistTitle: "合集标题"),
            "曙光"
        )
    }

    func testPartTitleStripsPlaylistPrefixWithoutPartNumber() {
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "合集标题 曙光", playlistTitle: "合集标题"),
            "曙光"
        )
    }

    func testPartTitleAcceptsSingleDigitAndUppercasePartNumber() {
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "合集标题 p1 曙光", playlistTitle: "合集标题"),
            "曙光"
        )
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "合集标题 P 01 曙光", playlistTitle: "合集标题"),
            "曙光"
        )
    }

    func testPartTitleReturnsOriginalWhenPlaylistTitleIsNil() {
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "合集标题 p01 曙光", playlistTitle: nil),
            "合集标题 p01 曙光"
        )
    }

    func testPartTitleReturnsOriginalWhenPlaylistPrefixMissing() {
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "合集标题 p01 曙光", playlistTitle: "另一个标题"),
            "合集标题 p01 曙光"
        )
    }

    func testPartTitleReturnsOriginalWhenResultIsEmpty() {
        // 剥掉前缀和序号后只剩空串 → 回退完整标题。
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "合集标题 p01", playlistTitle: "合集标题"),
            "合集标题 p01"
        )
    }

    func testPartTitleEmptyEntryTitle() {
        XCTAssertEqual(VideoCandidate.partTitle(from: nil, playlistTitle: "合集标题"), "")
        XCTAssertEqual(VideoCandidate.partTitle(from: "", playlistTitle: "合集标题"), "")
        XCTAssertEqual(VideoCandidate.partTitle(from: "   ", playlistTitle: "合集标题"), "")
    }

    func testPartTitleTrimsSurroundingWhitespace() {
        XCTAssertEqual(
            VideoCandidate.partTitle(from: "  合集标题 p01 曙光  ", playlistTitle: "合集标题"),
            "曙光"
        )
    }

    // MARK: - formattedDuration

    func testFormattedDurationNilAndInvalid() {        XCTAssertEqual(VideoCandidate.formattedDuration(nil), "")
        XCTAssertEqual(VideoCandidate.formattedDuration(-5), "")
        XCTAssertEqual(VideoCandidate.formattedDuration(Double.infinity), "")
    }

    func testFormattedDurationZero() {
        XCTAssertEqual(VideoCandidate.formattedDuration(0), "0:00")
    }

    func testFormattedDurationRounds() {
        // 取整规则：rounded()。59.6 → 60 → "1:00"。
        XCTAssertEqual(VideoCandidate.formattedDuration(59.6), "1:00")
        // 121.5 → 122 → "2:02"。
        XCTAssertEqual(VideoCandidate.formattedDuration(121.5), "2:02")
        // 209.4 → 209 → "3:29"。
        XCTAssertEqual(VideoCandidate.formattedDuration(209.4), "3:29")
    }

    func testFormattedDurationHours() {
        XCTAssertEqual(VideoCandidate.formattedDuration(3600), "1:00:00")
        XCTAssertEqual(VideoCandidate.formattedDuration(3661.4), "1:01:01")
    }

    func testFormattedDurationHugeFiniteValuesReturnEmpty() {
        // 1e18：String(format:) 会输出天文数字垃圾串；1e19：Int(seconds.rounded()) 会 fatal trap。
        XCTAssertEqual(VideoCandidate.formattedDuration(1e18), "")
        XCTAssertEqual(VideoCandidate.formattedDuration(1e19), "")
        XCTAssertEqual(VideoCandidate.formattedDuration(-1e18), "")
    }

    // MARK: - fixture: ugc_season（B站 view 接口）

    /// 仿真实 B站 view 接口的 data.ugc_season JSON（两个子合集：国内/国外）。
    /// episode 保留真实结构的 arc.duration，同时提供顶层 duration（解析器读取的字段）。
    private func ugcSeasonJSON() -> [String: Any] {
        func episode(_ bvid: String, _ title: String, _ duration: Double) -> [String: Any] {
            [
                "bvid": bvid,
                "title": title,
                "arc": ["duration": duration],
            ]
        }
        return [
            "data": [
                "ugc_season": [
                    "id": 1476298,
                    "title": "国内外摇滚-HiRes无损专辑",
                    "sections": [
                        [
                            "title": "国内",
                            "episodes": [
                                episode("BV16w411x7qf", "张楚2018《一部分》", 2632),
                                episode("BV1fh4y1Z7mg", "张楚《造飞机的工厂》", 3000),
                            ],
                        ],
                        [
                            "title": "国外",
                            "episodes": [
                                episode("BV1zH4y1n7Ap", "Nirvana1989《Bleach》", 2400),
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    // MARK: - ugc_season 解析

    func testParseBilibiliSeasonInfoWithTwoSections() throws {
        let info = try XCTUnwrap(
            VideoCandidate.parseBilibiliSeasonInfo(from: ugcSeasonJSON())
        )

        XCTAssertEqual(info.seasonID, 1476298)
        XCTAssertEqual(info.seasonTitle, "国内外摇滚-HiRes无损专辑")
        XCTAssertEqual(info.sections.count, 2)
        XCTAssertEqual(info.sections[0].title, "国内")
        XCTAssertEqual(info.sections[1].title, "国外")

        XCTAssertEqual(info.sections[0].episodes.count, 2)
        XCTAssertEqual(info.sections[0].episodes[0].bvid, "BV16w411x7qf")
        XCTAssertEqual(info.sections[0].episodes[0].title, "张楚2018《一部分》")
        XCTAssertEqual(info.sections[0].episodes[0].duration, 2632)
        XCTAssertEqual(info.sections[0].episodes[1].bvid, "BV1fh4y1Z7mg")
        XCTAssertEqual(info.sections[0].episodes[1].title, "张楚《造飞机的工厂》")
        XCTAssertEqual(info.sections[0].episodes[1].duration, 3000)

        XCTAssertEqual(info.sections[1].episodes.count, 1)
        XCTAssertEqual(info.sections[1].episodes[0].bvid, "BV1zH4y1n7Ap")
        XCTAssertEqual(info.sections[1].episodes[0].title, "Nirvana1989《Bleach》")
        XCTAssertEqual(info.sections[1].episodes[0].duration, 2400)
    }

    func testParseBilibiliSeasonInfoMissingReturnsNil() {
        // 无 ugc_season → nil。
        let noUgcSeason: [String: Any] = [
            "data": ["aid": 123],
        ]
        XCTAssertNil(VideoCandidate.parseBilibiliSeasonInfo(from: noUgcSeason))

        // ugc_season 为空 dict（缺 id）→ nil。
        let emptyUgcSeason: [String: Any] = [
            "data": ["ugc_season": [String: Any]()],
        ]
        XCTAssertNil(VideoCandidate.parseBilibiliSeasonInfo(from: emptyUgcSeason))
    }

    // MARK: - ugc_season → 候选数组

    func testBilibiliSeasonCandidatesIncludeSubcollectionTitle() throws {
        let info = try XCTUnwrap(
            VideoCandidate.parseBilibiliSeasonInfo(from: ugcSeasonJSON())
        )
        let candidates = VideoCandidate.bilibiliSeasonCandidates(from: info)

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates.map(\.partIndex), [1, 2, 3])
        XCTAssertEqual(candidates.map(\.partCount), [3, 3, 3])
        XCTAssertEqual(candidates.map(\.subcollectionTitle), ["国内", "国内", "国外"])
        XCTAssertEqual(candidates.map(\.title), ["张楚2018《一部分》", "张楚《造飞机的工厂》", "Nirvana1989《Bleach》"])
        XCTAssertEqual(candidates.map(\.url), [
            "https://www.bilibili.com/video/BV16w411x7qf",
            "https://www.bilibili.com/video/BV1fh4y1Z7mg",
            "https://www.bilibili.com/video/BV1zH4y1n7Ap",
        ])
        XCTAssertEqual(candidates[0].kind, .supported)

        // 时长 detail 按现有 formattedDuration 格式：2632 → "43:52"、3000 → "50:00"、2400 → "40:00"。
        XCTAssertEqual(candidates.map(\.detail), ["43:52", "50:00", "40:00"])
    }

    // MARK: - sectionTitle 查询

    func testSectionTitleLookup() throws {
        let info = try XCTUnwrap(
            VideoCandidate.parseBilibiliSeasonInfo(from: ugcSeasonJSON())
        )

        XCTAssertEqual(VideoCandidate.sectionTitle(forBV: "BV16w411x7qf", in: info), "国内")
        XCTAssertEqual(VideoCandidate.sectionTitle(forBV: "BV1fh4y1Z7mg", in: info), "国内")
        XCTAssertEqual(VideoCandidate.sectionTitle(forBV: "BV1zH4y1n7Ap", in: info), "国外")
        // 未知 bvid → nil。
        XCTAssertNil(VideoCandidate.sectionTitle(forBV: "BV1AABBCCDD0", in: info))
        // info 为 nil → nil。
        XCTAssertNil(VideoCandidate.sectionTitle(forBV: "BV16w411x7qf", in: nil))
    }

    // MARK: - playlist + subcollectionTitleByBV 映射

    func testPlaylistCandidatesWithSubcollectionTitleByBV() throws {
        // 不传映射（默认 [:]）→ 全部 nil。
        let withoutMapping = try XCTUnwrap(
            VideoCandidate.bilibiliPlaylistCandidates(from: playlistJSON(entryCount: 2))
        )
        XCTAssertEqual(withoutMapping.count, 2)
        XCTAssertNil(withoutMapping[0].subcollectionTitle)
        XCTAssertNil(withoutMapping[1].subcollectionTitle)

        // 传映射：命中 BV1B4nSz6Evp → "国内"；未命中的 bvid → nil。
        var json = playlistJSON(entryCount: 2)
        if var entries = json["entries"] as? [[String: Any]] {
            // 把第二条 entry 改成映射外的 bvid（去掉 webpage_url，确保 bvid 从 id 提取）。
            var second = entries[1]
            second.removeValue(forKey: "webpage_url")
            second["id"] = "BV1AABBCCDD0_p2"
            entries[1] = second
            json["entries"] = entries
        }
        let withMapping = try XCTUnwrap(
            VideoCandidate.bilibiliPlaylistCandidates(
                from: json,
                subcollectionTitleByBV: ["BV1B4nSz6Evp": "国内"]
            )
        )
        XCTAssertEqual(withMapping.count, 2)
        XCTAssertEqual(withMapping[0].subcollectionTitle, "国内")
        XCTAssertNil(withMapping[1].subcollectionTitle)
    }

    /// 分 P entry 的 id 形如 "BV1B4nSz6Evp_p1"（带 _pN 后缀）。纯函数层验证：
    /// bvid 提取必须命中干净的 BV（BV1B4nSz6Evp），而不是把整条 "…_pN" 当 BV——
    /// 否则 14 个分 P 会得到 14 个不同值，被 Engine.expandParts 误判为合集。
    func testPartIDsWithSuffixExtractSameCleanBVForAllParts() throws {
        let json = playlistJSON(entryCount: 14, includeWebpageURL: false)
        let candidates = try XCTUnwrap(
            VideoCandidate.bilibiliPlaylistCandidates(
                from: json,
                subcollectionTitleByBV: ["BV1B4nSz6Evp": "国内"]
            )
        )
        XCTAssertEqual(candidates.count, 14)
        // 所有分 P 都命中同一个干净 BV 的映射 → 提取未带 _pN 后缀、未被误判为合集 BV。
        XCTAssertTrue(candidates.allSatisfy { $0.subcollectionTitle == "国内" })
    }

    // MARK: - VideoCandidate 默认值

    func testVideoCandidateSubcollectionTitleDefaultNil() {
        let candidate = VideoCandidate(
            url: "https://www.bilibili.com/video/BV1B4nSz6Evp?p=1",
            kind: .supported,
            title: "曙光",
            detail: "1:02",
            partIndex: 1,
            partCount: 2
        )
        XCTAssertNil(candidate.subcollectionTitle)
    }
}
