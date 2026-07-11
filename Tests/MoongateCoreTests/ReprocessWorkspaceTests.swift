import XCTest
@testable import MoongateCore

final class ReprocessWorkspaceTests: XCTestCase {
    func testIsolatedArtifactsNeverOverwritePriorVersionSubtitle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoongateReprocessWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("v1", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let video = sourceDirectory.appendingPathComponent("Movie.mp4")
        let subtitle = sourceDirectory.appendingPathComponent("Movie.zh-Hans.srt")
        try Data("video-v1".utf8).write(to: video)
        try Data("subtitle-v1".utf8).write(to: subtitle)

        let versionDirectory = try ReprocessWorkspace.createVersionDirectory(
            beside: sourceDirectory,
            versionNumber: 2
        )
        let copied = try ReprocessWorkspace.copyArtifacts([video, subtitle], to: versionDirectory)
        let copiedSubtitle = try XCTUnwrap(copied.first { $0.pathExtension == "srt" })

        try Data("subtitle-v2".utf8).write(to: copiedSubtitle)

        XCTAssertNotEqual(copiedSubtitle.deletingLastPathComponent(), subtitle.deletingLastPathComponent())
        XCTAssertEqual(try String(contentsOf: subtitle), "subtitle-v1")
        XCTAssertEqual(try String(contentsOf: copiedSubtitle), "subtitle-v2")
    }
}
