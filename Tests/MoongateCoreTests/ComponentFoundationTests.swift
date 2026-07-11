import Foundation
import CryptoKit
import XCTest
@testable import MoongateCore

final class ComponentFoundationTests: XCTestCase {
    func testComponentPreservesSourcePolicySizeVersionAndReadiness() {
        let component = Component(
            id: "fixture.runtime",
            displayName: "Fixture runtime",
            kind: .asrRuntime,
            capabilities: [.localSpeechRecognition],
            source: .projectGitHubRelease,
            installPolicy: .onDemandUserConsent,
            isOptional: true,
            sizeBytes: 42,
            version: "fixture-v1",
            readiness: .missing(detail: "Not installed")
        )

        XCTAssertEqual(component.id, "fixture.runtime")
        XCTAssertEqual(component.kind, .asrRuntime)
        XCTAssertEqual(component.source, .projectGitHubRelease)
        XCTAssertEqual(component.installPolicy, .onDemandUserConsent)
        XCTAssertTrue(component.isOptional)
        XCTAssertEqual(component.sizeBytes, 42)
        XCTAssertEqual(component.version, "fixture-v1")
        XCTAssertEqual(component.readiness, .missing(detail: "Not installed"))
    }

    func testCatalogSeparatesToolchainRuntimeModelsVADAndAppleLanguagePackages() throws {
        let whisper = try makeModel(
            id: "whisper.cpp:fixture",
            fileName: "ggml-fixture.bin",
            bytes: 42
        )
        let vad = try makeModel(
            id: "whisper.cpp-vad:fixture",
            fileName: "ggml-vad-fixture.bin",
            bytes: 21
        )
        let catalog = ComponentCatalog.moongate(
            runtimeLocator: ASRRuntimeLocator(extraSearchURLs: [], environmentPath: ""),
            whisperModels: ASRModelManifest(models: [whisper]),
            vadModels: ASRModelManifest(models: [vad])
        )

        XCTAssertEqual(
            Set(catalog.components.map(\.kind)),
            Set([
                .downloadToolchain,
                .asrRuntime,
                .whisperModel,
                .voiceActivityDetector,
                .appleLanguagePack,
            ])
        )

        let downloadTools = try XCTUnwrap(catalog.components.first { $0.kind == .downloadToolchain })
        XCTAssertEqual(downloadTools.source, .existingDependencySetup)
        XCTAssertEqual(downloadTools.installPolicy, .existingDependencySetup)
        XCTAssertFalse(downloadTools.isOptional)

        let runtime = try XCTUnwrap(catalog.components.first { $0.kind == .asrRuntime })
        XCTAssertEqual(runtime.source, .projectGitHubRelease)
        XCTAssertEqual(runtime.installPolicy, .onDemandUserConsent)
        XCTAssertTrue(runtime.isOptional)
        XCTAssertNotEqual(runtime.source, .existingDependencySetup)

        let model = try XCTUnwrap(catalog.components.first { $0.kind == .whisperModel })
        XCTAssertEqual(model.source, .existingASRModelDownloader)
        XCTAssertEqual(model.installPolicy, .existingManagedInstaller)
        XCTAssertEqual(model.sizeBytes, whisper.sizeBytes)

        let voiceActivityDetector = try XCTUnwrap(catalog.components.first { $0.kind == .voiceActivityDetector })
        XCTAssertEqual(voiceActivityDetector.source, .existingASRModelDownloader)
        XCTAssertEqual(voiceActivityDetector.installPolicy, .existingManagedInstaller)
        XCTAssertEqual(voiceActivityDetector.sizeBytes, vad.sizeBytes)

        let languagePack = try XCTUnwrap(catalog.components.first { $0.kind == .appleLanguagePack })
        XCTAssertEqual(languagePack.source, .appleSystem)
        XCTAssertEqual(languagePack.installPolicy, .systemManaged)
        XCTAssertTrue(languagePack.isOptional)
    }

    func testCatalogReportsReadyWhenExistingVerifiedRuntimeIsDiscoverable() throws {
        let root = makeTemporaryDirectory(named: "component-runtime-ready")
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try writeVerifiedRuntime(in: root, payload: Data("existing runtime".utf8))

        let catalog = ComponentCatalog.moongate(
            runtimeLocator: ASRRuntimeLocator(extraSearchURLs: [root], environmentPath: ""),
            whisperModels: ASRModelManifest(models: []),
            vadModels: ASRModelManifest(models: [])
        )
        let runtime = try XCTUnwrap(catalog.components.first { $0.kind == .asrRuntime })

        XCTAssertEqual(runtime.readiness.status, .ready)
        XCTAssertTrue(runtime.readiness.isReady)
        XCTAssertTrue(runtime.readiness.detail?.contains(executable.path) == true)
    }

    func testRuntimeDownloadManifestRejectsUnsafeURLsPathsHashesAndIncompatibleArchitectures() throws {
        let currentPlatform = ASRRuntimeLocator.currentPlatform
        let currentArchitecture = ASRRuntimeLocator.currentArchitecture

        XCTAssertThrowsError(try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: currentArchitecture,
            downloadURL: "http://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: String(repeating: "a", count: 64)
        ))
        XCTAssertThrowsError(try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/%2e%2e/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: String(repeating: "a", count: 64)
        ))
        XCTAssertThrowsError(try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/%252e%252e/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: String(repeating: "a", count: 64)
        ))
        let encodedTraversalJSON = """
        {
          "assets": [
            {
              "provider": "whisper.cpp",
              "platform": "\(currentPlatform)",
              "architecture": "\(currentArchitecture)",
              "version": "fixture",
              "downloadUrl": "https://github.com/Dream-of-July/moongate/releases/download/%252e%252e/not-published-runtime.fixture",
              "executableRelativePath": "bin/whisper-cli",
              "sha256": "\(String(repeating: "a", count: 64))",
              "license": "MIT",
              "sourceDescription": "fixture"
            }
          ]
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(
            ASRRuntimeDownloadManifest.self,
            from: Data(encodedTraversalJSON.utf8)
        ))
        XCTAssertThrowsError(try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: currentArchitecture,
            downloadURL: "https://example.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: String(repeating: "a", count: 64)
        ))
        XCTAssertThrowsError(try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/tag/test-fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: String(repeating: "a", count: 64)
        ))
        XCTAssertThrowsError(try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "../whisper-cli",
            sha256: String(repeating: "a", count: 64)
        ))
        XCTAssertThrowsError(try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: "not-a-sha"
        ))

        let otherArchitecture = currentArchitecture == "arm64" ? "x64" : "arm64"
        let incompatible = try makeRuntimeAsset(
            platform: currentPlatform,
            architecture: otherArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: String(repeating: "a", count: 64)
        )
        let manifest = try ASRRuntimeDownloadManifest(assets: [incompatible])
        XCTAssertThrowsError(try manifest.assetForCurrentRuntime()) { error in
            XCTAssertEqual(
                error as? ASRRuntimeDownloadManifestError,
                .noCompatibleAsset(platform: currentPlatform, architecture: currentArchitecture)
            )
        }
    }

    func testOperationCoordinatorRetriesFailedInstallAndRefreshesReadiness() async throws {
        let component = Component(
            id: "fixture.runtime",
            displayName: "Fixture runtime",
            kind: .asrRuntime,
            capabilities: [.localSpeechRecognition],
            source: .projectGitHubRelease,
            installPolicy: .onDemandUserConsent,
            isOptional: true,
            sizeBytes: 1,
            version: "fixture",
            readiness: .missing(detail: "Not installed")
        )
        let client = ScriptedComponentClient(
            installOutcomes: [.failure("release unavailable"), .success],
            refreshedReadiness: .missing(detail: "Removed externally")
        )
        let coordinator = ComponentOperationCoordinator(
            catalog: ComponentCatalog(components: [component]),
            client: client
        )

        try await coordinator.install(component.id)
        await coordinator.waitForOperation(component.id)
        let failedState = await coordinator.state(for: component.id)
        XCTAssertEqual(failedState, .failed("release unavailable"))

        try await coordinator.retry(component.id)
        await coordinator.waitForOperation(component.id)
        let retriedState = await coordinator.state(for: component.id)
        let installCallCount = await client.installCallCount
        XCTAssertEqual(retriedState, .idle(.ready(detail: "Installed")))
        XCTAssertEqual(installCallCount, 2)

        try await coordinator.refresh(component.id)
        await coordinator.waitForOperation(component.id)
        let refreshedState = await coordinator.state(for: component.id)
        XCTAssertEqual(refreshedState, .idle(.missing(detail: "Removed externally")))
    }

    func testOperationCoordinatorCancelsInFlightInstallBeforeItCanReportReady() async throws {
        let component = Component(
            id: "fixture.runtime",
            displayName: "Fixture runtime",
            kind: .asrRuntime,
            capabilities: [.localSpeechRecognition],
            source: .projectGitHubRelease,
            installPolicy: .onDemandUserConsent,
            isOptional: true,
            sizeBytes: 1,
            version: "fixture",
            readiness: .missing(detail: "Not installed")
        )
        let client = ScriptedComponentClient(
            installOutcomes: [.waitForCancellation],
            refreshedReadiness: .ready(detail: "Must not be reached")
        )
        let coordinator = ComponentOperationCoordinator(
            catalog: ComponentCatalog(components: [component]),
            client: client
        )

        try await coordinator.install(component.id)
        await client.waitUntilInstallStarts()
        let installingState = await coordinator.state(for: component.id)
        guard case .installing = installingState else {
            return XCTFail("Expected an in-flight install, got \(String(describing: installingState))")
        }

        let didCancel = await coordinator.cancel(component.id)
        let cancellingState = await coordinator.state(for: component.id)
        XCTAssertTrue(didCancel)
        XCTAssertEqual(cancellingState, .cancelling)
        await coordinator.waitForOperation(component.id)
        let cancelledState = await coordinator.state(for: component.id)
        XCTAssertEqual(cancelledState, .cancelled)
    }

    func testOperationCoordinatorKeepsCommittedInstallReadyWhenCancellationRacesReturn() async throws {
        let component = Component(
            id: "fixture.runtime",
            displayName: "Fixture runtime",
            kind: .asrRuntime,
            capabilities: [.localSpeechRecognition],
            source: .projectGitHubRelease,
            installPolicy: .onDemandUserConsent,
            isOptional: true,
            sizeBytes: 1,
            version: "fixture",
            readiness: .missing(detail: "Not installed")
        )
        let client = ScriptedComponentClient(
            installOutcomes: [.waitForCancellationThenCommit],
            refreshedReadiness: .missing(detail: "Not used")
        )
        let coordinator = ComponentOperationCoordinator(
            catalog: ComponentCatalog(components: [component]),
            client: client
        )

        try await coordinator.install(component.id)
        await client.waitUntilInstallStarts()
        let didCancel = await coordinator.cancel(component.id)
        XCTAssertTrue(didCancel)
        await coordinator.waitForOperation(component.id)

        let state = await coordinator.state(for: component.id)
        XCTAssertEqual(state, .idle(.ready(detail: "Committed")))
    }

    func testRuntimeInstallerCleansStagingAfterFailureAndLeavesNoDiscoverableRuntime() async throws {
        let root = makeTemporaryDirectory(named: "component-runtime-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("runtime", isDirectory: true)
        let payload = Data("runtime that fails after download".utf8)
        let asset = try makeRuntimeAsset(
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: sha256(payload)
        )
        let client = RuntimeDownloadFixture(payload: payload, mode: .writeThenFail)
        let installer = ASRRuntimeDownloadInstaller(
            manifest: try ASRRuntimeDownloadManifest(assets: [asset]),
            destinationDirectoryURL: destination,
            downloadClient: client
        )

        await XCTAssertThrowsAsync {
            _ = try await installer.installCurrentRuntime()
        }

        assertNoRuntimeArtifacts(destination: destination, parent: root)
    }

    func testRuntimeInstallerRejectsExecutableSymlinkThatEscapesStaging() async throws {
        let fileManager = FileManager.default
        let root = makeTemporaryDirectory(named: "component-runtime-symlink")
        defer { try? fileManager.removeItem(at: root) }
        let destination = root.appendingPathComponent("runtime", isDirectory: true)
        let externalDirectory = root.appendingPathComponent("outside", isDirectory: true)
        let externalExecutable = externalDirectory.appendingPathComponent("whisper-cli", isDirectory: false)
        let payload = Data("outside executable".utf8)
        try fileManager.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try payload.write(to: externalExecutable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: externalExecutable.path)

        let asset = try makeRuntimeAsset(
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: sha256(payload)
        )
        let installer = ASRRuntimeDownloadInstaller(
            manifest: try ASRRuntimeDownloadManifest(assets: [asset]),
            destinationDirectoryURL: destination,
            downloadClient: RuntimeDownloadFixture(payload: payload, mode: .symbolicLink(to: externalExecutable))
        )

        await XCTAssertThrowsAsync {
            _ = try await installer.installCurrentRuntime()
        }
        assertNoRuntimeArtifacts(destination: destination, parent: root)
    }

    func testRuntimeInstallerRejectsStagingRootReplacedBySymbolicLink() async throws {
        let fileManager = FileManager.default
        let root = makeTemporaryDirectory(named: "component-runtime-root-symlink")
        defer { try? fileManager.removeItem(at: root) }
        let destination = root.appendingPathComponent("runtime", isDirectory: true)
        let externalDirectory = root.appendingPathComponent("outside", isDirectory: true)
        let externalExecutable = externalDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-cli", isDirectory: false)
        let payload = Data("outside runtime root".utf8)
        try fileManager.createDirectory(at: externalExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload.write(to: externalExecutable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: externalExecutable.path)

        let asset = try makeRuntimeAsset(
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: sha256(payload)
        )
        let installer = ASRRuntimeDownloadInstaller(
            manifest: try ASRRuntimeDownloadManifest(assets: [asset]),
            destinationDirectoryURL: destination,
            downloadClient: StagingRootSymlinkClient(externalDirectory: externalDirectory)
        )

        await XCTAssertThrowsAsync {
            _ = try await installer.installCurrentRuntime()
        }
        assertNoRuntimeArtifacts(destination: destination, parent: root)
    }

    func testRuntimeInstallerCleansStagingWhenCancelledAndPublishesOnlyVerifiedRuntime() async throws {
        let root = makeTemporaryDirectory(named: "component-runtime-cancel")
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("runtime", isDirectory: true)
        let payload = Data("runtime that is cancelled".utf8)
        let asset = try makeRuntimeAsset(
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: sha256(payload)
        )
        let client = RuntimeDownloadFixture(payload: payload, mode: .waitForCancellation)
        let installer = ASRRuntimeDownloadInstaller(
            manifest: try ASRRuntimeDownloadManifest(assets: [asset]),
            destinationDirectoryURL: destination,
            downloadClient: client
        )

        let task = Task {
            try await installer.installCurrentRuntime()
        }
        await client.waitUntilDownloadStarts()
        task.cancel()
        await XCTAssertThrowsAsync {
            _ = try await task.value
        }
        assertNoRuntimeArtifacts(destination: destination, parent: root)

        let successClient = RuntimeDownloadFixture(payload: payload, mode: .succeed)
        let successInstaller = ASRRuntimeDownloadInstaller(
            manifest: try ASRRuntimeDownloadManifest(assets: [asset]),
            destinationDirectoryURL: destination,
            downloadClient: successClient
        )
        let installed = try await successInstaller.installCurrentRuntime()
        let located = ASRRuntimeLocator(extraSearchURLs: [destination], environmentPath: "").locate()

        XCTAssertEqual(installed.executableURL, located?.executableURL)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(ASRRuntimeLocator.runtimeManifestFileName).path
        ))

        let replacementPayload = Data("replacement runtime".utf8)
        let replacementAsset = try makeRuntimeAsset(
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            downloadURL: "https://github.com/Dream-of-July/moongate/releases/download/test-fixture/not-published-runtime.fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: sha256(replacementPayload)
        )
        let replacementInstaller = ASRRuntimeDownloadInstaller(
            manifest: try ASRRuntimeDownloadManifest(assets: [replacementAsset]),
            destinationDirectoryURL: destination,
            downloadClient: RuntimeDownloadFixture(payload: replacementPayload, mode: .succeed)
        )
        let replacement = try await replacementInstaller.installCurrentRuntime()
        let replacementLocated = ASRRuntimeLocator(extraSearchURLs: [destination], environmentPath: "").locate()

        XCTAssertEqual(replacement.executableURL, replacementLocated?.executableURL)
        XCTAssertEqual(try Data(contentsOf: replacement.executableURL), replacementPayload)
    }

    private func makeModel(id: String, fileName: String, bytes: Int64) throws -> ASRModelInfo {
        ASRModelInfo(
            id: id,
            displayName: id,
            fileName: fileName,
            downloadURL: try XCTUnwrap(URL(string: "https://example.invalid/\(fileName)")),
            sizeBytes: bytes,
            sha256: String(repeating: "a", count: 64),
            memoryRequiredMB: 1,
            license: "MIT",
            sourceDescription: "fixture"
        )
    }

    private func makeRuntimeAsset(
        platform: String,
        architecture: String,
        downloadURL: String,
        executableRelativePath: String,
        sha256: String
    ) throws -> ASRRuntimeDownloadAsset {
        try ASRRuntimeDownloadAsset(
            provider: "whisper.cpp",
            platform: platform,
            architecture: architecture,
            version: "v0.9.1-fixture",
            downloadURL: try XCTUnwrap(URL(string: downloadURL)),
            executableRelativePath: executableRelativePath,
            sha256: sha256,
            license: "MIT",
            sourceDescription: "fixture project release"
        )
    }

    private func makeTemporaryDirectory(named name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Moongate-\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func writeVerifiedRuntime(in directory: URL, payload: Data) throws -> URL {
        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        let executable = bin.appendingPathComponent("whisper-cli", isDirectory: false)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try payload.write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runtime = try ASRRuntimeBundleInfo(
            provider: "whisper.cpp",
            platform: ASRRuntimeLocator.currentPlatform,
            architecture: ASRRuntimeLocator.currentArchitecture,
            version: "fixture",
            executableRelativePath: "bin/whisper-cli",
            sha256: sha256(payload),
            license: "MIT",
            sourceDescription: "fixture"
        )
        let manifest = try ASRRuntimeBundleManifest(runtimes: [runtime])
        try ASRJSON.makeEncoder().encode(manifest).write(
            to: directory.appendingPathComponent(ASRRuntimeLocator.runtimeManifestFileName),
            options: .atomic
        )
        return executable
    }

    private func assertNoRuntimeArtifacts(destination: URL, parent: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), file: file, line: line)
        XCTAssertNil(
            ASRRuntimeLocator(extraSearchURLs: [destination], environmentPath: "").locate(),
            file: file,
            line: line
        )
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        XCTAssertFalse(
            names.contains { $0.hasPrefix(".runtime.staging-") },
            "Cancelled and failed installs must remove their staging directory.",
            file: file,
            line: line
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum ComponentFixtureError: Error, LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

private actor ScriptedComponentClient: ComponentOperationClient {
    enum InstallOutcome: Sendable {
        case success
        case failure(String)
        case waitForCancellation
        case waitForCancellationThenCommit
    }

    private var installOutcomes: [InstallOutcome]
    private let refreshedReadiness: ComponentReadiness
    private var startedInstall = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var installCallCount = 0

    init(installOutcomes: [InstallOutcome], refreshedReadiness: ComponentReadiness) {
        self.installOutcomes = installOutcomes
        self.refreshedReadiness = refreshedReadiness
    }

    func install(
        _ component: Component,
        progress: @escaping @Sendable (ComponentOperationProgress) -> Void
    ) async throws -> ComponentReadiness {
        installCallCount += 1
        startedInstall = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        let outcome = installOutcomes.isEmpty ? .success : installOutcomes.removeFirst()
        progress(ComponentOperationProgress(completedUnitCount: 0, totalUnitCount: 1))
        switch outcome {
        case .success:
            progress(ComponentOperationProgress(completedUnitCount: 1, totalUnitCount: 1))
            return .ready(detail: "Installed")
        case .failure(let message):
            throw ComponentFixtureError.message(message)
        case .waitForCancellation:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return .ready(detail: "Unexpectedly completed")
        case .waitForCancellationThenCommit:
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return .ready(detail: "Committed")
        }
    }

    func refreshReadiness(for component: Component) async throws -> ComponentReadiness {
        refreshedReadiness
    }

    func waitUntilInstallStarts() async {
        if startedInstall { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private actor RuntimeDownloadFixture: ASRRuntimeDownloadClient {
    enum Mode: Sendable {
        case writeThenFail
        case waitForCancellation
        case succeed
        case symbolicLink(to: URL)
    }

    private let payload: Data
    private let mode: Mode
    private var startedDownload = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(payload: Data, mode: Mode) {
        self.payload = payload
        self.mode = mode
    }

    func downloadRuntime(
        _ asset: ASRRuntimeDownloadAsset,
        into stagingDirectoryURL: URL,
        progress: @escaping @Sendable (ComponentOperationProgress) -> Void
    ) async throws {
        let executable = asset.executableURL(relativeTo: stagingDirectoryURL)
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        switch mode {
        case .symbolicLink(let externalExecutable):
            try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: externalExecutable)
        case .writeThenFail, .waitForCancellation, .succeed:
            try payload.write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        progress(ComponentOperationProgress(
            completedUnitCount: Int64(payload.count),
            totalUnitCount: Int64(payload.count)
        ))
        startedDownload = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        switch mode {
        case .writeThenFail:
            throw ComponentFixtureError.message("download interrupted")
        case .waitForCancellation:
            try await Task.sleep(nanoseconds: 60_000_000_000)
        case .succeed:
            return
        case .symbolicLink:
            return
        }
    }

    func waitUntilDownloadStarts() async {
        if startedDownload { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}

private struct StagingRootSymlinkClient: ASRRuntimeDownloadClient {
    let externalDirectory: URL

    func downloadRuntime(
        _ asset: ASRRuntimeDownloadAsset,
        into stagingDirectoryURL: URL,
        progress: @escaping @Sendable (ComponentOperationProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.removeItem(at: stagingDirectoryURL)
        try fileManager.createSymbolicLink(at: stagingDirectoryURL, withDestinationURL: externalDirectory)
        progress(ComponentOperationProgress(completedUnitCount: 1, totalUnitCount: 1))
    }
}

private func XCTAssertThrowsAsync<T>(
    _ operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected async operation to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
