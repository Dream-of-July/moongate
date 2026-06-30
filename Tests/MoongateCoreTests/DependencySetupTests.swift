@testable import MoongateCore
import XCTest

final class DependencySetupTests: XCTestCase {
    func testFfmpegDependencyUsesFullBuildForSubtitleBurning() {
        let components = DependencySetup.components(
            ytDlpInstalled: true,
            subtitleRendererFfmpegInstalled: false,
            jsRuntimeInstalled: true
        )

        let ffmpeg = components.first { $0.id == "ffmpeg" }
        XCTAssertEqual(ffmpeg?.formula, "ffmpeg-full")
        XCTAssertEqual(ffmpeg?.isInstalled, false)
        XCTAssertEqual(ffmpeg?.isRequired, true)
    }

    func testNeedsSetupFollowsSharedMissingRequiredComponentList() {
        let ready = DependencySetup.components(
            ytDlpInstalled: true,
            subtitleRendererFfmpegInstalled: true,
            jsRuntimeInstalled: true
        )
        let missingDeno = DependencySetup.components(
            ytDlpInstalled: true,
            subtitleRendererFfmpegInstalled: true,
            jsRuntimeInstalled: false
        )

        XCTAssertFalse(DependencySetup.needsSetup(ready))
        XCTAssertTrue(DependencySetup.needsSetup(missingDeno))
        XCTAssertEqual(DependencySetup.missingRequired(from: missingDeno).map(\.id), ["deno"])
        XCTAssertEqual(DependencySetup.missingOptional(from: missingDeno).map(\.id), [])
    }

    func testDependencySetupOnlyContainsRequiredDownloadChainComponents() {
        let components = DependencySetup.components(
            ytDlpInstalled: true,
            subtitleRendererFfmpegInstalled: true,
            jsRuntimeInstalled: true
        )

        XCTAssertEqual(components.map(\.id), ["yt-dlp", "ffmpeg", "deno"])
        XCTAssertEqual(components.map(\.isRequired), [true, true, true])
        XCTAssertFalse(components.contains { $0.id == "whisper-cli" })
        XCTAssertFalse(DependencySetup.needsSetup(components))
        XCTAssertEqual(DependencySetup.missingOptional(from: components).map(\.id), [])
    }

    func testBurnerSkipsFfmpegWithoutSubtitleRenderer() {
        let chosen = FFmpegBurner.locateSubtitleRendererFFmpeg(
            candidates: ["/opt/homebrew/bin/ffmpeg", "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"],
            environment: [:],
            fileIsExecutable: { _ in true },
            supportsSubtitleRendering: { path in path.contains("ffmpeg-full") }
        )

        XCTAssertEqual(chosen, "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg")
    }
}
