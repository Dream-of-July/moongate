import CryptoKit
import XCTest
@testable import Moongate
@testable import MoongateCore

final class ComponentPreparationServiceTests: XCTestCase {
    func testRuntimeWithoutManifestIsUnavailableAndOnlyOffersRefresh() async throws {
        let runtimeRoot = makeTemporaryDirectory(named: "no-runtime-manifest")
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }

        let service = ComponentPreparationService(
            runtimeDirectoryURL: runtimeRoot,
            runtimeLocator: ASRRuntimeLocator(extraSearchURLs: [runtimeRoot], environmentPath: ""),
            runtimeDownloadManifest: nil,
            whisperManifest: ASRModelManifest(models: []),
            vadManifest: ASRModelManifest(models: []),
            toolchainInspector: { [] }
        )

        let snapshot = await service.refresh()
        let runtime = try XCTUnwrap(snapshot.item(id: "asr.runtime.whisper-cpp"))

        XCTAssertEqual(runtime.kind, .asrRuntime)
        XCTAssertEqual(runtime.readiness.status, .unavailable)
        XCTAssertEqual(runtime.allowedOperations, [.refresh])
        XCTAssertNil(runtime.storageURL)
        XCTAssertTrue(runtime.failureReason?.contains("project-controlled") == true)
    }

    func testExistingVerifiedRuntimeIsReadyAndNeverOffersRemovalOutsideManagedStorage() async throws {
        // The locator receives the bundle root, not its `bin` directory. Its
        // static manifest lives at the root and points to bin/whisper-cli.
        let externalRuntimeRoot = makeTemporaryDirectory(named: "external-runtime")
        defer { try? FileManager.default.removeItem(at: externalRuntimeRoot) }
        let executable = try writeVerifiedRuntimeBundle(in: externalRuntimeRoot)

        let managedRuntimeRoot = makeTemporaryDirectory(named: "managed-runtime-storage")
        defer { try? FileManager.default.removeItem(at: managedRuntimeRoot) }
        let service = ComponentPreparationService(
            runtimeDirectoryURL: managedRuntimeRoot,
            runtimeLocator: ASRRuntimeLocator(
                extraSearchURLs: [externalRuntimeRoot],
                environmentPath: ""
            ),
            runtimeDownloadManifest: nil,
            whisperManifest: ASRModelManifest(models: []),
            vadManifest: ASRModelManifest(models: []),
            toolchainInspector: { [] }
        )

        let snapshot = await service.refresh()
        let runtime = try XCTUnwrap(snapshot.item(id: "asr.runtime.whisper-cpp"))

        XCTAssertEqual(runtime.readiness.status, .ready)
        XCTAssertEqual(runtime.storageURL, executable)
        XCTAssertEqual(runtime.actualDiskUsageBytes, Int64("fixture runtime".utf8.count))
        XCTAssertEqual(runtime.allowedOperations, [.refresh])
        XCTAssertTrue(runtime.sourceDetail.contains("External"))
    }

    func testCompatibleRuntimeManifestOffersOnDemandInstallWithoutInventingAnAsset() async throws {
        let runtimeRoot = makeTemporaryDirectory(named: "compatible-runtime-manifest")
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let asset = try ASRRuntimeDownloadAsset(
            provider: "whisper.cpp",
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            version: "v0.9.1-fixture",
            downloadURL: try XCTUnwrap(URL(string: "https://github.com/Dream-of-July/moongate/releases/download/v0.9.1-fixture/moongate-asr-runtime.fixture")),
            executableRelativePath: "bin/whisper-cli",
            sha256: String(repeating: "a", count: 64),
            license: "MIT",
            sourceDescription: "fixture project release"
        )
        let service = ComponentPreparationService(
            runtimeDirectoryURL: runtimeRoot,
            runtimeLocator: ASRRuntimeLocator(extraSearchURLs: [runtimeRoot], environmentPath: ""),
            runtimeDownloadManifest: try ASRRuntimeDownloadManifest(assets: [asset]),
            whisperManifest: ASRModelManifest(models: []),
            vadManifest: ASRModelManifest(models: []),
            toolchainInspector: { [] }
        )

        let snapshot = await service.refresh()
        let runtime = try XCTUnwrap(snapshot.item(id: "asr.runtime.whisper-cpp"))

        XCTAssertEqual(runtime.readiness.status, .missing)
        XCTAssertNil(runtime.failureReason)
        XCTAssertNil(runtime.declaredSizeBytes)
        XCTAssertEqual(runtime.allowedOperations, [.refresh, .installRuntime])
        XCTAssertTrue(runtime.sourceDetail.contains(asset.downloadURL.absoluteString))
        XCTAssertEqual(runtime.storageURL, runtimeRoot)
    }

    private func makeTemporaryDirectory(named name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Moongate-Preparation-\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeVerifiedRuntimeBundle(in root: URL) throws -> URL {
        let payload = Data("fixture runtime".utf8)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let executable = bin.appendingPathComponent("whisper-cli", isDirectory: false)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try payload.write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let bundleInfo = try ASRRuntimeBundleInfo(
            provider: "whisper.cpp",
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            version: "fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
            license: "MIT",
            sourceDescription: "fixture"
        )
        let bundleManifest = try ASRRuntimeBundleManifest(runtimes: [bundleInfo])
        try ASRJSON.makeEncoder().encode(bundleManifest).write(
            to: root.appendingPathComponent(ASRRuntimeLocator.runtimeManifestFileName),
            options: .atomic
        )
        return executable
    }
}
