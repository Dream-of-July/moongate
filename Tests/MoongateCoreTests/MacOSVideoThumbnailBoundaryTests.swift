import XCTest

/// VideoThumbnail 共享缩略图组件的源码扫描 boundary 测试（App-target SwiftUI 视图不可 @testable import）。
/// 锁定 R23/R24 的关键改进：加载态(.empty) 与失败/无URL态 分开处理——防止有人把两态合回 default:
/// 导致"有缩略图的视频加载时先闪一下 film 占位"的观感回归。
final class MacOSVideoThumbnailBoundaryTests: XCTestCase {

    func testDistinguishesLoadingFromFailurePlaceholder() throws {
        let source = try videoThumbnailSource()
        // 成功显示图片、裁切填充。
        XCTAssertTrue(source.contains("case .success(let image)"))
        XCTAssertTrue(source.contains("scaledToFill()"))
        // 关键：有 URL 且加载中(.empty) → ProgressView，而非立刻 film 占位。
        XCTAssertTrue(source.contains("case .empty where url != nil"),
                      "加载态必须与失败态分开（.empty where url != nil），否则加载时会闪 film 占位")
        XCTAssertTrue(source.contains("ProgressView()"),
                      "加载态应显示 ProgressView")
        // 失败/无 URL 才落 film 占位。
        XCTAssertTrue(source.contains("Image(systemName: \"film\")"))
    }

    func testUsesHairlineStrokeFromDesignTokens() throws {
        let source = try videoThumbnailSource()
        // 统一的 0.5pt 极细描边来自 design token（三处调用点视觉一致）。
        XCTAssertTrue(source.contains("Stroke.hairline"),
                      "描边应用 Stroke.hairline 设计令牌，保持三处缩略图一致")
        XCTAssertTrue(source.contains("strokeBorder(.quaternary"))
    }

    private func videoThumbnailSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("VideoThumbnail.swift"))
    }
}
