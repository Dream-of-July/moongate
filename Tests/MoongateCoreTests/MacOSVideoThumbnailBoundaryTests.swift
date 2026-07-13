import XCTest

/// VideoThumbnail 共享缩略图组件的源码扫描 boundary 测试（App-target SwiftUI 视图不可 @testable import）。
/// 锁定加载态与失败/无 URL 态的分离，防止有缩略图的视频在请求期间先闪一下 film 占位。
final class MacOSVideoThumbnailBoundaryTests: XCTestCase {

    func testDistinguishesLoadingFromFailurePlaceholder() throws {
        let source = try videoThumbnailSource()
        // 成功显示图片、裁切填充。
        XCTAssertTrue(source.contains("if let thumbnailImage"))
        XCTAssertTrue(source.contains("scaledToFill()"))
        // 关键：有 URL 且加载中 → ProgressView，而非立刻 film 占位。
        XCTAssertTrue(source.contains("else if isLoading, url != nil"),
                      "加载态必须与失败态分开，否则加载时会闪 film 占位")
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

    func testLoadsOnlyWhileVisibleWithBoundedCacheAndBackgroundDecode() throws {
        let source = try videoThumbnailSource()

        XCTAssertTrue(source.contains(".onAppear"),
                      "缩略图只应在视图出现后才请求")
        XCTAssertTrue(source.contains(".onDisappear"),
                      "列表行离屏时必须停止未完成的缩略图请求")
        XCTAssertTrue(source.contains("loadTask?.cancel()"),
                      "离屏或 URL 变化时必须取消仍在进行的请求")
        XCTAssertTrue(source.contains("guard isVisible, let nextURL else { return }"),
                      "不可见行不应启动网络或解码任务")
        XCTAssertTrue(source.contains("ThumbnailImageCache"))
        XCTAssertTrue(source.contains("ThumbnailImageCacheLimit.entryCount"))
        XCTAssertTrue(source.contains("ThumbnailImageCacheLimit.cost"))
        XCTAssertTrue(source.contains("Task.detached(priority: .utility)"),
                      "图片解码应离开主线程")
        XCTAssertTrue(source.contains("CGImageSourceCreateThumbnailAtIndex"),
                      "应先下采样再交给 SwiftUI，避免以原图分辨率常驻内存")
        XCTAssertFalse(source.contains("AsyncImage(url: url)"),
                       "共享缩略图组件不应退回无边界缓存和取消策略的裸 AsyncImage")
    }

    private func videoThumbnailSource() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources").appendingPathComponent("Moongate")
            .appendingPathComponent("VideoThumbnail.swift"))
    }
}
