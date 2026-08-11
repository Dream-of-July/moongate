import XCTest
@testable import MoongateCore

/// 取消/失败后临时文件清理（cleanupTemporaryFiles）的行为测试。安全属性：只删**本视频**的
/// yt-dlp 残留（.part / .ytdl / .part-Frag…），绝不碰完成的产物文件或其它视频的临时文件。
/// 此前该文件系统清理逻辑为 private 且无测试。
final class DownloadTempCleanupTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-tempcleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
    }

    private func touch(_ name: String) throws {
        try Data("x".utf8).write(to: dir.appendingPathComponent(name))
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    /// 只删本视频的 .part / .ytdl / 分片 .part-Frag，保留完成产物（.mp4/.srt）与本视频无关文件。
    func testRemovesOnlyMatchingVideoTempFiles() throws {
        try touch("Clip [abc123].mp4.part")          // 本视频未完成分片 → 删
        try touch("Clip [abc123].f137.mp4.ytdl")     // 本视频 ytdl 中间态 → 删
        try touch("Clip [abc123].mp4.part-Frag12")   // 本视频分片残留 → 删
        try touch("Clip [abc123].mp4")               // 本视频完成产物 → 保留
        try touch("Clip [abc123].en.srt")            // 本视频字幕产物 → 保留

        YtDlpEngine._testCleanupTemporaryFiles(in: dir, videoID: "abc123")

        XCTAssertFalse(exists("Clip [abc123].mp4.part"), ".part 残留应删除")
        XCTAssertFalse(exists("Clip [abc123].f137.mp4.ytdl"), ".ytdl 中间态应删除")
        XCTAssertFalse(exists("Clip [abc123].mp4.part-Frag12"), ".part-Frag 分片应删除")
        XCTAssertTrue(exists("Clip [abc123].mp4"), "完成产物必须保留")
        XCTAssertTrue(exists("Clip [abc123].en.srt"), "字幕产物必须保留")
    }

    /// 不同 videoID 的临时文件不受影响（防批量下载时误删他人残留）。
    func testDoesNotTouchOtherVideosTempFiles() throws {
        try touch("A [abc123].mp4.part")   // 目标视频 → 删
        try touch("B [xyz789].mp4.part")   // 其它视频 → 保留
        try touch("C [xyz789].mp4.ytdl")   // 其它视频 → 保留

        YtDlpEngine._testCleanupTemporaryFiles(in: dir, videoID: "abc123")

        XCTAssertFalse(exists("A [abc123].mp4.part"), "目标视频残留应删除")
        XCTAssertTrue(exists("B [xyz789].mp4.part"), "其它视频 .part 不应被误删")
        XCTAssertTrue(exists("C [xyz789].mp4.ytdl"), "其它视频 .ytdl 不应被误删")
    }

    /// 目录不存在时静默返回，不抛错、不崩溃。
    func testMissingDirectoryIsNoOp() {
        let missing = dir.appendingPathComponent("does-not-exist", isDirectory: true)
        YtDlpEngine._testCleanupTemporaryFiles(in: missing, videoID: "abc123")
        // 未崩溃即通过；原目录不受影响。
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    /// 无匹配 videoID 的临时文件时不动任何文件。
    func testNoMatchingFilesLeavesEverythingIntact() throws {
        try touch("Other [zzz000].mp4.part")
        try touch("Clip [abc123].mp4")  // 产物，非临时

        YtDlpEngine._testCleanupTemporaryFiles(in: dir, videoID: "abc123")

        XCTAssertTrue(exists("Other [zzz000].mp4.part"))
        XCTAssertTrue(exists("Clip [abc123].mp4"))
    }
}
