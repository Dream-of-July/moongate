import XCTest
@testable import MoongateCore

/// 产物命名去重 `UniqueFilename` 的行为测试。覆盖「同一视频多次下载 / 重复导入字幕 / 重跑云端 ASR /
/// 导入模型重名」时避免覆盖已有文件的核心逻辑——此前四处 hand-rolled 循环（QueueManager/CloudASR/
/// SettingsView/Burner）无任何测试。用注入的 `fileExists` 判存，不碰真实文件系统。
final class UniqueFilenameTests: XCTestCase {

    private let dir = URL(fileURLWithPath: "/tmp/moongate-test", isDirectory: true)

    /// 目录里没有同名文件：直接用首选名，不加序号。
    func testNoCollisionUsesPreferredName() {
        let url = UniqueFilename.url(in: dir, stem: "clip.en", ext: "srt", fileExists: { _ in false })
        XCTAssertEqual(url.lastPathComponent, "clip.en.srt")
    }

    /// 首选名被占用：跳到 -2。
    func testSingleCollisionAppendsSerialTwo() {
        let taken: Set<String> = [dir.appendingPathComponent("clip.en.srt").path]
        let url = UniqueFilename.url(in: dir, stem: "clip.en", ext: "srt", fileExists: { taken.contains($0) })
        XCTAssertEqual(url.lastPathComponent, "clip.en-2.srt")
    }

    /// 首选名与 -2 都被占用：跳到 -3（连续冲突逐个递增）。
    func testConsecutiveCollisionsIncrementSerial() {
        let taken: Set<String> = [
            dir.appendingPathComponent("clip.en.srt").path,
            dir.appendingPathComponent("clip.en-2.srt").path,
        ]
        let url = UniqueFilename.url(in: dir, stem: "clip.en", ext: "srt", fileExists: { taken.contains($0) })
        XCTAssertEqual(url.lastPathComponent, "clip.en-3.srt")
    }

    /// 序号从 2 起，且中间空位会被填（-2 空、首选被占 → 用 -2，不会跳到 -3）。
    func testFillsFirstAvailableGap() {
        let taken: Set<String> = [dir.appendingPathComponent("m.bin").path]
        let url = UniqueFilename.url(in: dir, stem: "m", ext: "bin", fileExists: { taken.contains($0) })
        XCTAssertEqual(url.lastPathComponent, "m-2.bin")
    }

    /// 空扩展名：不加点，序号直接接主名（导入无扩展名文件的场景）。
    func testEmptyExtensionOmitsDot() {
        XCTAssertEqual(
            UniqueFilename.url(in: dir, stem: "model", ext: "", fileExists: { _ in false }).lastPathComponent,
            "model"
        )
        let taken: Set<String> = [dir.appendingPathComponent("model").path]
        XCTAssertEqual(
            UniqueFilename.url(in: dir, stem: "model", ext: "", fileExists: { taken.contains($0) }).lastPathComponent,
            "model-2"
        )
    }

    /// 自定义分隔符（Burner 用空格）：保留「<原名>（字幕版） 2.mp4」的既有观感。
    func testSpaceSeparatorMatchesBurnerNaming() {
        let taken: Set<String> = [dir.appendingPathComponent("Video（字幕版）.mp4").path]
        let url = UniqueFilename.url(
            in: dir, stem: "Video（字幕版）", ext: "mp4", separator: " ", fileExists: { taken.contains($0) }
        )
        XCTAssertEqual(url.lastPathComponent, "Video（字幕版） 2.mp4")
    }

    /// 主名含点（如 "clip.cloud-asr.zh"）时，序号加在整个 stem 之后、扩展名之前，不破坏中间的点。
    func testDottedStemKeepsExtensionAtEnd() {
        let taken: Set<String> = [dir.appendingPathComponent("clip.cloud-asr.zh.srt").path]
        let url = UniqueFilename.url(in: dir, stem: "clip.cloud-asr.zh", ext: "srt", fileExists: { taken.contains($0) })
        XCTAssertEqual(url.lastPathComponent, "clip.cloud-asr.zh-2.srt")
        XCTAssertEqual(url.pathExtension, "srt")
    }

    /// 返回 URL 落在给定目录下。
    func testResultStaysInDirectory() {
        let url = UniqueFilename.url(in: dir, stem: "x", ext: "srt", fileExists: { _ in false })
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL)
    }
}
