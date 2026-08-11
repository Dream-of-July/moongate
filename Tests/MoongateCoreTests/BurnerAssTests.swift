@testable import MoongateCore
import XCTest

final class BurnerAssTests: XCTestCase {
    private func cue(_ text: String) -> SubtitleCue {
        SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: text)
    }

    func testLandscape169LayoutUsesReadableSubtitleWidth() {
        let layout = FFmpegBurner.ASSLayout(aspect: 16.0 / 9.0)

        XCTAssertEqual(layout.playResX, 512)
        XCTAssertEqual(layout.playResY, 288)
        XCTAssertEqual(layout.chineseSize, 13)
        // 原文字号 = round(13 × 0.8) = 10（不分语言统一）。
        XCTAssertEqual(layout.originalSize, 10)
        // 自动布局：左右只留最小边距（约画面 2.5%）。512 × 0.025 ≈ 13。
        XCTAssertEqual(layout.marginH, 13)
        XCTAssertEqual(layout.marginV, 20)
        // 容量按可用宽度推算：(512 - 26) / 13 ≈ 37，够宽就不折。
        XCTAssertEqual(layout.cjkWrapCapacity, 37)
    }

    func testLandscape169LongChineseLinePreWrappedForReadableWidth() {
        // 一行约 37 字以内不该换行（自动布局，够宽就不折）。
        let short = "今天我会介绍如何使用Xcode中的强大新工具" // 21 字
        let assShort = FFmpegBurner.makeASS(cues: [cue(short)])
        XCTAssertFalse(assShort.contains("\\N"), "未超容量不应换行：\(short)")

        // 远超容量的长行仍会按容量折行。
        let long = "今天，我会介绍如何使用Xcode中的一些强大新工具，在早期探索应用设计时快速尝试不同的界面方向。"
        let assLong = FFmpegBurner.makeASS(cues: [cue(long)])
        XCTAssertTrue(assLong.contains("\\N"), "超容量长行应换行")
    }

    func testPortrait916StillKeepsUsefulCapacity() {
        let layout = FFmpegBurner.ASSLayout(aspect: 9.0 / 16.0)

        XCTAssertEqual(layout.playResX, 162)
        XCTAssertEqual(layout.chineseSize, 8)
        // round(8 × 0.8) = 6。
        XCTAssertEqual(layout.originalSize, 6)
        XCTAssertEqual(layout.marginH, max(5, Int((162.0 * 0.025).rounded())))
        XCTAssertEqual(layout.cjkWrapCapacity, 19)
    }

    func testUltraWideCapsReadingLength() {
        let layout = FFmpegBurner.ASSLayout(aspect: 10.0)

        XCTAssertEqual(layout.playResX, 1152)
        XCTAssertEqual(layout.chineseSize, 13)
        // 自动布局：超宽屏也只留 2.5% 最小边距，不再人为收窄到「舒适阅读宽度」。
        XCTAssertEqual(layout.marginH, 29)
        XCTAssertEqual(layout.cjkWrapCapacity, 84)
    }

    // MARK: - 原文（拉丁）折行

    func testPortraitLatinCapacityComfortablyWiderThanCJK() {
        // 竖屏下英文按词折行的容量应远大于中文（拉丁字形更窄），否则英文会被切碎。
        let layout = FFmpegBurner.ASSLayout(aspect: 9.0 / 16.0)
        XCTAssertEqual(layout.latinWrapCapacity, 46)
    }

    func testLatinLineWrapMergesSourceBreaksAndRewrapsByWords() {
        // 源 SRT 把一句拆成很多碎行；折行后应合并再按词重排，且不切进单词中间。
        let wrapped = FFmpegBurner.wrapLatinLine(
            "Today\nI will\nshow you how to use some powerful new tools in Xcode to quickly explore design directions.",
            capacity: 40
        )
        XCTAssertGreaterThan(wrapped.count, 1)
        for line in wrapped {
            XCTAssertLessThanOrEqual(line.count, 40, "每行不得超过容量：\(line)")
            XCTAssertFalse(line.hasPrefix(" "))
            XCTAssertFalse(line.hasSuffix(" "))
        }
        // 不切词：重新拼接（空格连接）应还原原始单词序列。
        XCTAssertEqual(
            wrapped.joined(separator: " "),
            "Today I will show you how to use some powerful new tools in Xcode to quickly explore design directions."
        )
    }

    func testLatinShortLineStaysSingleLine() {
        let wrapped = FFmpegBurner.wrapLatinLine("A short caption.", capacity: 50)
        XCTAssertEqual(wrapped, ["A short caption."])
    }

    func testBilingualCueRewrapsEnglishUnderChinese() {
        // 双语：中文在上、英文在下；竖屏长英文行应被按词折行而非保留源碎行。
        let english = "This is a fairly long English subtitle line that would otherwise overflow or be chopped into many tiny fragments on a portrait video."
        let ass = FFmpegBurner.makeASS(
            cues: [SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500",
                               text: "这是一句中文字幕\n\(english)")],
            aspect: 9.0 / 16.0
        )
        // 英文被折成多行（出现 \N 连接），但任意单行长度不超过容量 50。
        guard let dialogue = ass.split(separator: "\n").first(where: { $0.hasPrefix("Dialogue:") }) else {
            return XCTFail("应有 Dialogue 行")
        }
        let englishPart = String(dialogue).components(separatedBy: "}").last ?? ""
        for piece in englishPart.components(separatedBy: "\\N") {
            XCTAssertLessThanOrEqual(piece.count, 50, "英文行过长：\(piece)")
        }
    }

    // MARK: - 原文分类、字号、透明度（不分语言统一 80%）

    func testOriginalSizeIsEightyPercentOfTranslation() {
        // 16:9：译文 13 → 原文 round(13×0.8)=10。
        XCTAssertEqual(FFmpegBurner.ASSLayout(aspect: 16.0/9.0).originalSize, 10)
    }

    func testBilingualAppliesSmallerSizeAndAlphaToOriginal() {
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500",
                        text: "这是中文译文\nThis is the source line")
        ])
        let dialogue = ass.split(separator: "\n").first { $0.hasPrefix("Dialogue:") }.map(String.init) ?? ""
        // 原文块带更小字号 + 80% 不透明度（alpha &H33&），且整体（含描边）变淡。
        XCTAssertTrue(dialogue.contains("{\\fs10\\alpha&H33&}"), "原文应带 10 号字 + alpha：\(dialogue)")
        // 中文在前、原文覆盖块在后。
        let zhRange = dialogue.range(of: "这是中文译文")
        let ovRange = dialogue.range(of: "{\\fs10\\alpha&H33&}")
        XCTAssertNotNil(zhRange); XCTAssertNotNil(ovRange)
        if let z = zhRange, let o = ovRange { XCTAssertLessThan(z.lowerBound, o.lowerBound) }
    }

    func testJapaneseOriginalIsTreatedAsOriginalNotTranslation() {
        // 日文原文（含假名）必须归为原文层：缩小 + 透明，而不是被当成译文用满字号。
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500",
                        text: "我会一直在你身边\nずっとそばにいるよ")
        ])
        let dialogue = ass.split(separator: "\n").first { $0.hasPrefix("Dialogue:") }.map(String.init) ?? ""
        XCTAssertTrue(dialogue.contains("\\alpha&H33&"), "日文原文应进原文层（缩小+透明）：\(dialogue)")
        // 译文（简体中文）在覆盖块之前。
        if let z = dialogue.range(of: "我会一直在你身边"),
           let o = dialogue.range(of: "\\alpha&H33&") {
            XCTAssertLessThan(z.lowerBound, o.lowerBound, "中文译文应在原文之上")
        } else {
            XCTFail("缺中文或原文：\(dialogue)")
        }
    }

    func testKoreanOriginalClassifiedAsOriginal() {
        XCTAssertFalse(FFmpegBurner.isSimplifiedChineseLine("항상 네 곁에 있을게"), "韩文不应判为简体中文译文")
        XCTAssertFalse(FFmpegBurner.isSimplifiedChineseLine("ずっとそばにいるよ"), "日文不应判为简体中文译文")
        XCTAssertTrue(FFmpegBurner.isSimplifiedChineseLine("我会一直在你身边"), "简体中文应判为译文")
        XCTAssertFalse(FFmpegBurner.isSimplifiedChineseLine("Always by your side"), "英文不是译文")
    }

    func testChineseStyleUsesNinetySixPercentOpacity() {
        // ZH 样式的译文填充用 96% 不透明度（alpha &H0A），黑色描边仍不透明保可读性。
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: "测试")
        ])
        guard let styleLine = ass.split(separator: "\n").first(where: { $0.hasPrefix("Style: ZH,") }).map(String.init) else {
            return XCTFail("应有 ZH 样式行：\(ass)")
        }
        XCTAssertTrue(styleLine.contains("&H0AFFFFFF"), "译文填充应为 96% 不透明（&H0AFFFFFF）：\(styleLine)")
        XCTAssertTrue(styleLine.contains("&H00000000"), "黑色描边应保持不透明（&H00000000）：\(styleLine)")
    }

    // MARK: - 用户可调字幕位置

    func testSubtitlePositionAssAlignmentValues() {
        XCTAssertEqual(SubtitlePosition.bottom.assAlignment, 2, "底部应映射到 ASS Alignment=2（底部居中）")
        XCTAssertEqual(SubtitlePosition.top.assAlignment, 8, "顶部应映射到 ASS Alignment=8（顶部居中）")
    }

    func testMakeASSDefaultAlignmentIsBottom() {
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: "测试")
        ])
        guard let styleLine = ass.split(separator: "\n").first(where: { $0.hasPrefix("Style: ZH,") }).map(String.init) else {
            return XCTFail("应有 ZH 样式行：\(ass)")
        }
        // Alignment 列前缀为 BorderStyle,Outline,Shadow = 1,1,0，故底部对齐应出现 ,1,0,2,
        XCTAssertTrue(styleLine.contains(",1,0,2,"), "默认应为底部对齐 Alignment=2：\(styleLine)")
    }

    func testMakeASSTopAlignmentEmitsAlignmentEight() {
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: "测试")
        ], alignment: 8)
        guard let styleLine = ass.split(separator: "\n").first(where: { $0.hasPrefix("Style: ZH,") }).map(String.init) else {
            return XCTFail("应有 ZH 样式行：\(ass)")
        }
        XCTAssertTrue(styleLine.contains(",1,0,8,"), "顶部对齐应为 Alignment=8：\(styleLine)")
        XCTAssertFalse(styleLine.contains(",1,0,2,"), "顶部对齐不应残留 Alignment=2：\(styleLine)")
    }

    // MARK: - 用户可调字号缩放

    func testSubtitleFontScaleMultipliersAreMonotonic() {
        XCTAssertLessThan(SubtitleFontScale.small.multiplier, SubtitleFontScale.standard.multiplier)
        XCTAssertEqual(SubtitleFontScale.standard.multiplier, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(SubtitleFontScale.standard.multiplier, SubtitleFontScale.large.multiplier)
        XCTAssertLessThan(SubtitleFontScale.large.multiplier, SubtitleFontScale.extraLarge.multiplier)
    }

    func testFontScaleMonotonicallyChangesLayoutSizes() {
        let aspect = 16.0 / 9.0
        let small = FFmpegBurner.ASSLayout(aspect: aspect, fontScale: SubtitleFontScale.small.multiplier)
        let standard = FFmpegBurner.ASSLayout(aspect: aspect, fontScale: SubtitleFontScale.standard.multiplier)
        let large = FFmpegBurner.ASSLayout(aspect: aspect, fontScale: SubtitleFontScale.large.multiplier)
        let extraLarge = FFmpegBurner.ASSLayout(aspect: aspect, fontScale: SubtitleFontScale.extraLarge.multiplier)

        // 译文字号随档位单调递增
        XCTAssertLessThan(small.chineseSize, standard.chineseSize)
        XCTAssertLessThan(standard.chineseSize, large.chineseSize)
        XCTAssertLessThan(large.chineseSize, extraLarge.chineseSize)

        // standard 与不传 fontScale（默认 1.0）完全等价：老用户行为不变
        XCTAssertEqual(standard.chineseSize, FFmpegBurner.ASSLayout(aspect: aspect).chineseSize)
        XCTAssertEqual(standard.originalSize, FFmpegBurner.ASSLayout(aspect: aspect).originalSize)

        // 原文字号也随档位单调递增（保持 80% 比例衍生）
        XCTAssertLessThanOrEqual(small.originalSize, standard.originalSize)
        XCTAssertLessThan(standard.originalSize, extraLarge.originalSize)
    }

    func testFontScaleLowerBoundProtection() {
        // 竖屏 + 极小倍率仍受下限保护（译文 >= 8，原文 >= 6）。
        let layout = FFmpegBurner.ASSLayout(aspect: 9.0 / 16.0, fontScale: 0.01)
        XCTAssertGreaterThanOrEqual(layout.chineseSize, 8)
        XCTAssertGreaterThanOrEqual(layout.originalSize, 6)
        // 非法倍率（0 / 非有限）回退为 1.0，与 standard 一致。
        XCTAssertEqual(
            FFmpegBurner.ASSLayout(aspect: 16.0 / 9.0, fontScale: 0).chineseSize,
            FFmpegBurner.ASSLayout(aspect: 16.0 / 9.0).chineseSize
        )
    }

    // MARK: - 用户可调字幕颜色

    func testSubtitleColorAssBGRHexValues() {
        // 白=FFFFFF；黄=RGB(255,255,0)→ASS BGR 字节序 00FFFF。
        XCTAssertEqual(SubtitleColor.white.assBGRHex, "FFFFFF", "白色 BGR 应为 FFFFFF")
        XCTAssertEqual(SubtitleColor.yellow.assBGRHex, "00FFFF", "黄色 RGB(255,255,0) → BGR 应为 00FFFF")
    }

    func testMakeASSYellowChangesPrimaryColourRGBOnly() {
        // 传入黄色 BGR：PrimaryColour 的 RGB 变黄，但译文 alpha（chineseAlphaHex）与黑色描边不受影响。
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: "测试")
        ], primaryColorBGRHex: "00FFFF")
        guard let styleLine = ass.split(separator: "\n").first(where: { $0.hasPrefix("Style: ZH,") }).map(String.init) else {
            return XCTFail("应有 ZH 样式行：\(ass)")
        }
        // PrimaryColour = &H + alpha(0A) + 黄色 BGR(00FFFF)。
        XCTAssertTrue(styleLine.contains("&H0A00FFFF"), "黄色译文填充应为 &H0A00FFFF（alpha 保留 + 黄 BGR）：\(styleLine)")
        // 未变：不应残留白色 PrimaryColour。
        XCTAssertFalse(styleLine.contains("&H0AFFFFFF"), "黄色时不应再出现白色 PrimaryColour：\(styleLine)")
        // 黑色描边仍不透明（OutlineColour &H00000000）。
        XCTAssertTrue(styleLine.contains("&H00000000"), "黑色描边应保持不透明 &H00000000：\(styleLine)")
    }

    func testMakeASSBilingualSourceLineInheritsColorViaAlphaOnly() {
        // 双语条目的原文行只用 {\fs..\alpha..} 覆盖字号/透明度，不硬编码颜色 → 颜色继承 Style 的
        // PrimaryColour。黄色时译文与原文都应是黄色（无 \c / \1c 覆盖会把原文行拉回白色）。
        // 这条防回归：若有人给原文行加了 \c 颜色覆盖，黄色字幕的原文行会静默变白。
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: "你好世界\nhello world")
        ], primaryColorBGRHex: "00FFFF")
        guard let dialogue = ass.split(separator: "\n").first(where: { $0.hasPrefix("Dialogue:") }).map(String.init) else {
            return XCTFail("应有 Dialogue 行：\(ass)")
        }
        // 原文行的行内覆盖块应只含 \fs 与 \alpha，不含颜色覆盖 \c / \1c。
        XCTAssertTrue(dialogue.contains("\\alpha&H"), "双语原文行应有 \\alpha 透明度覆盖：\(dialogue)")
        XCTAssertFalse(dialogue.contains("\\c&H"), "原文行不应硬编码颜色覆盖 \\c（否则不继承黄色）：\(dialogue)")
        XCTAssertFalse(dialogue.contains("\\1c&H"), "原文行不应硬编码颜色覆盖 \\1c：\(dialogue)")
    }

    func testMakeASSDefaultColorStaysWhiteForBackwardCompatibility() {
        // 不传颜色（默认）：Style 行仍为白色 &H0AFFFFFF，老用户零变化。
        let ass = FFmpegBurner.makeASS(cues: [
            SubtitleCue(index: 1, start: "00:00:01,000", end: "00:00:02,500", text: "测试")
        ])
        guard let styleLine = ass.split(separator: "\n").first(where: { $0.hasPrefix("Style: ZH,") }).map(String.init) else {
            return XCTFail("应有 ZH 样式行：\(ass)")
        }
        XCTAssertTrue(styleLine.contains("&H0AFFFFFF"), "默认应保持白色译文填充 &H0AFFFFFF：\(styleLine)")
    }

    // MARK: - SRT 兜底路径（parseSRT 返回空时）也应应用字幕外观设置

    func testSRTForceStyleFallbackAppliesAppearanceSettings() {
        // 大号(1.24)+顶部(8)+黄色(00FFFF)：force_style 应带上缩放字号、Alignment=8、黄色 PrimaryColour。
        let filter = FFmpegBurner.srtForceStyleFilter(
            fontScale: SubtitleFontScale.large.multiplier,
            alignment: SubtitlePosition.top.assAlignment,
            primaryColorBGRHex: SubtitleColor.yellow.assBGRHex
        )
        // 15 * 1.24 = 18.6 → 19。
        XCTAssertTrue(filter.contains("FontSize=19"), "大号应把基准 15 缩放到 19：\(filter)")
        XCTAssertTrue(filter.contains("Alignment=8"), "顶部应为 Alignment=8：\(filter)")
        XCTAssertTrue(filter.contains("PrimaryColour=&H0000FFFF"), "黄色应为 &H00 + 00FFFF：\(filter)")
    }

    func testSRTForceStyleFallbackDefaultsMatchLegacy() {
        // 默认（标准/底部/白色）：应等价于旧硬编码 FontSize=15、Alignment=2、白色。
        let filter = FFmpegBurner.srtForceStyleFilter(
            fontScale: SubtitleFontScale.standard.multiplier,
            alignment: SubtitlePosition.bottom.assAlignment,
            primaryColorBGRHex: SubtitleColor.white.assBGRHex
        )
        XCTAssertTrue(filter.contains("FontSize=15"), "标准应保持 15pt：\(filter)")
        XCTAssertTrue(filter.contains("Alignment=2"), "底部应为 Alignment=2：\(filter)")
        XCTAssertTrue(filter.contains("PrimaryColour=&H00FFFFFF"), "白色 PrimaryColour：\(filter)")
    }

    func testSRTForceStyleFallbackClampsInvalidScale() {
        // 非法倍率（0）回落 1.0，字号仍为 15，不会得到 0 或负数。
        let filter = FFmpegBurner.srtForceStyleFilter(fontScale: 0, alignment: 2, primaryColorBGRHex: "FFFFFF")
        XCTAssertTrue(filter.contains("FontSize=15"), "非法倍率应回落 1.0 → 15pt：\(filter)")
    }
}
