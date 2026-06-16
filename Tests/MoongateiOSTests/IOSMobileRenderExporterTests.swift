@testable import MoongateMobileCore
@testable import MoongateiOS

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

import Foundation
import XCTest

final class IOSMobileRenderExporterTests: XCTestCase {
    func testExportsBurnedInSubtitleThroughRendererIntoAppStorage() async throws {
        let directory = temporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Downloads/source.mp4")
        let subtitleURL = directory.appendingPathComponent("Subtitles/source.zh.srt")
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source-video".utf8).write(to: mediaURL)
        try "1\n00:00:00,000 --> 00:00:01,000\n你好\n".write(to: subtitleURL, atomically: true, encoding: .utf8)
        let renderer = RecordingIOSVideoRenderer()
        let exporter = IOSMobileRenderExporter(storageDirectoryURL: directory, renderer: renderer)
        let progress = RenderProgressRecorder()

        let result = try await exporter.export(
            MobileRenderRequest(
                sourceMedia: MobileTaskArtifact(
                    id: "original-task-1",
                    kind: .originalMedia,
                    displayName: "source.mp4",
                    storageIdentifier: "Downloads/source.mp4"
                ),
                subtitles: [
                    MobileTaskArtifact(
                        id: "subtitle-task-1",
                        kind: .translatedSubtitleFile,
                        displayName: "source.zh.srt",
                        storageIdentifier: "Subtitles/source.zh.srt"
                    )
                ],
                exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle, maxRenderHeight: 720)
            ),
            progress: { progress.record($0) }
        )

        let artifact = try XCTUnwrap(result.primaryArtifact)
        XCTAssertEqual(artifact.kind, .renderedVideo)
        XCTAssertEqual(artifact.displayName, "source.rendered.mp4")
        XCTAssertEqual(artifact.storageIdentifier, "Renders/source.rendered.mp4")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("Renders/source.rendered.mp4")), Data("rendered-video".utf8))
        XCTAssertEqual(progress.snapshots().first, MobileTaskProgress(phase: .exporting, completedUnitCount: 0, totalUnitCount: nil))
        XCTAssertEqual(progress.snapshots().last, MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 1))

        let invocations = await renderer.recordedInvocations()
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.sourceURL.standardizedFileURL, mediaURL.standardizedFileURL)
        XCTAssertEqual(invocation.subtitleURLs.map(\.standardizedFileURL), [subtitleURL.standardizedFileURL])
        XCTAssertEqual(invocation.outputURL.standardizedFileURL, directory.appendingPathComponent("Renders/source.rendered.mp4").standardizedFileURL)
        XCTAssertEqual(invocation.maxRenderHeight, 720)
    }

    func testAVFoundationRendererExportsMinimalFixtureVideo() async throws {
        #if canImport(AVFoundation) && canImport(QuartzCore) && canImport(CoreGraphics)
        let directory = temporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Downloads/fixture.mp4")
        let subtitleURL = directory.appendingPathComponent("Subtitles/fixture.zh.srt")
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeFixtureVideo(at: mediaURL)
        try "1\n00:00:00,100 --> 00:00:00,800\nHello fixture\n".write(
            to: subtitleURL,
            atomically: true,
            encoding: .utf8
        )
        let exporter = IOSMobileRenderExporter(storageDirectoryURL: directory)
        let progress = RenderProgressRecorder()

        let result = try await exporter.export(
            MobileRenderRequest(
                sourceMedia: MobileTaskArtifact(
                    id: "fixture-task",
                    kind: .originalMedia,
                    displayName: "fixture.mp4",
                    storageIdentifier: "Downloads/fixture.mp4"
                ),
                subtitles: [
                    MobileTaskArtifact(
                        id: "fixture-subtitle",
                        kind: .translatedSubtitleFile,
                        displayName: "fixture.zh.srt",
                        storageIdentifier: "Subtitles/fixture.zh.srt"
                    )
                ],
                exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle, maxRenderHeight: 64)
            ),
            progress: { progress.record($0) }
        )

        let artifact = try XCTUnwrap(result.primaryArtifact)
        XCTAssertEqual(artifact.kind, .renderedVideo)
        XCTAssertEqual(artifact.storageIdentifier, "Renders/fixture.rendered.mp4")
        let outputURL = directory.appendingPathComponent(artifact.storageIdentifier)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan(artifact.byteCount ?? 0, 0)

        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.05)
        let beforeCueLuminance = try averageFrameLuminance(in: outputURL, seconds: 0.03)
        let duringCueLuminance = try averageFrameLuminance(in: outputURL, seconds: 0.5)
        XCTAssertLessThan(duringCueLuminance, beforeCueLuminance - 10)
        XCTAssertTrue(progress.snapshots().contains(MobileTaskProgress(phase: .exporting, completedUnitCount: 0, totalUnitCount: 1)))
        #else
        throw XCTSkip("AVFoundation, QuartzCore, and CoreGraphics are required for the fixture render test.")
        #endif
    }

    func testRenderGeometryAppliesMaxRenderHeightWithoutUpscaling() {
        let downscaled = IOSVideoRenderGeometry.make(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            maxRenderHeight: 720
        )
        XCTAssertEqual(downscaled.renderSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(downscaled.layerTransform, CGAffineTransform(scaleX: 2.0 / 3.0, y: 2.0 / 3.0))

        let small = IOSVideoRenderGeometry.make(
            naturalSize: CGSize(width: 640, height: 360),
            preferredTransform: .identity,
            maxRenderHeight: 720
        )
        XCTAssertEqual(small.renderSize, CGSize(width: 640, height: 360))
        XCTAssertEqual(small.layerTransform, .identity)
    }

    func testRejectsUnsafeSourceIdentifierBeforeRendererRuns() async throws {
        let directory = temporaryDirectory()
        let renderer = RecordingIOSVideoRenderer()
        let exporter = IOSMobileRenderExporter(storageDirectoryURL: directory, renderer: renderer)

        do {
            _ = try await exporter.export(
                MobileRenderRequest(
                    sourceMedia: MobileTaskArtifact(
                        id: "original-escape",
                        kind: .originalMedia,
                        displayName: "escape.mp4",
                        storageIdentifier: "../escape.mp4"
                    ),
                    subtitles: [
                        MobileTaskArtifact(
                            id: "subtitle",
                            kind: .translatedSubtitleFile,
                            displayName: "subtitle.srt",
                            storageIdentifier: "Subtitles/subtitle.srt"
                        )
                    ],
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle)
                ),
                progress: { _ in }
            )
            XCTFail("Unsafe source media references must not be rendered.")
        } catch let error as IOSMobileRenderExporter.RenderExportError {
            XCTAssertEqual(error, .unsafeStorageIdentifier)
        }

        let invocations = await renderer.recordedInvocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testRejectsUnsupportedProfilesWithoutCreatingOutput() async throws {
        let directory = temporaryDirectory()
        let renderer = RecordingIOSVideoRenderer()
        let exporter = IOSMobileRenderExporter(storageDirectoryURL: directory, renderer: renderer)

        do {
            _ = try await exporter.export(
                MobileRenderRequest(
                    sourceMedia: MobileTaskArtifact(
                        id: "original",
                        kind: .originalMedia,
                        displayName: "source.mp4",
                        storageIdentifier: "Downloads/source.mp4"
                    ),
                    exportProfile: MobileExportProfile(subtitleMode: .translatedSubtitleFile)
                ),
                progress: { _ in }
            )
            XCTFail("The render exporter should only handle burned-in video export requests.")
        } catch let error as IOSMobileRenderExporter.RenderExportError {
            XCTAssertEqual(error, .unsupportedExportProfile)
        }

        let outputDirectory = directory.appendingPathComponent("Renders", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
        let invocations = await renderer.recordedInvocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testRejectsSoftSubtitleArtifactsBeforeRendererRuns() async throws {
        let directory = temporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Downloads/source.mp4")
        let subtitleURL = directory.appendingPathComponent("Subtitles/source.movtxt")
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source-video".utf8).write(to: mediaURL)
        try "soft subtitle payload".write(to: subtitleURL, atomically: true, encoding: .utf8)
        let renderer = RecordingIOSVideoRenderer()
        let exporter = IOSMobileRenderExporter(storageDirectoryURL: directory, renderer: renderer)

        do {
            _ = try await exporter.export(
                MobileRenderRequest(
                    sourceMedia: MobileTaskArtifact(
                        id: "original",
                        kind: .originalMedia,
                        displayName: "source.mp4",
                        storageIdentifier: "Downloads/source.mp4"
                    ),
                    subtitles: [
                        MobileTaskArtifact(
                            id: "soft",
                            kind: .softSubtitle,
                            displayName: "source.movtxt",
                            storageIdentifier: "Subtitles/source.movtxt"
                        )
                    ],
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle)
                ),
                progress: { _ in }
            )
            XCTFail("Soft subtitle artifacts are not SRT and must not be passed to the burned-in renderer.")
        } catch let error as IOSMobileRenderExporter.RenderExportError {
            XCTAssertEqual(error, .unsupportedSubtitleArtifact)
        }

        let invocations = await renderer.recordedInvocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testRejectsEmptySRTBeforeRendererRuns() async throws {
        let directory = temporaryDirectory()
        let mediaURL = directory.appendingPathComponent("Downloads/source.mp4")
        let subtitleURL = directory.appendingPathComponent("Subtitles/empty.zh.srt")
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subtitleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source-video".utf8).write(to: mediaURL)
        try "not an srt".write(to: subtitleURL, atomically: true, encoding: .utf8)
        let renderer = RecordingIOSVideoRenderer()
        let exporter = IOSMobileRenderExporter(storageDirectoryURL: directory, renderer: renderer)

        do {
            _ = try await exporter.export(
                MobileRenderRequest(
                    sourceMedia: MobileTaskArtifact(
                        id: "original",
                        kind: .originalMedia,
                        displayName: "source.mp4",
                        storageIdentifier: "Downloads/source.mp4"
                    ),
                    subtitles: [
                        MobileTaskArtifact(
                            id: "subtitle",
                            kind: .translatedSubtitleFile,
                            displayName: "empty.zh.srt",
                            storageIdentifier: "Subtitles/empty.zh.srt"
                        )
                    ],
                    exportProfile: MobileExportProfile(subtitleMode: .burnedInSubtitle)
                ),
                progress: { _ in }
            )
            XCTFail("Empty or unparsable SRT files must not produce a successful render.")
        } catch let error as IOSMobileRenderExporter.RenderExportError {
            XCTAssertEqual(error, .emptySubtitle)
        }

        let invocations = await renderer.recordedInvocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    func testAVFoundationExporterCancelsSessionWhenTaskIsCancelled() throws {
        let source = try String(contentsOf: packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MoongateiOS")
            .appendingPathComponent("IOSMobileRenderExporter.swift"))

        XCTAssertTrue(source.contains("static func awaitExportSession(_ session: any IOSAssetExportSessioning) async throws"))
        XCTAssertTrue(source.contains("withTaskCancellationHandler"))
        XCTAssertTrue(source.contains("IOSExportSessionContinuationBox"))
        XCTAssertTrue(source.contains("session.cancelExport()"))
        XCTAssertTrue(source.contains("let box = AVAssetExportSessionBox(session)"))
        XCTAssertTrue(source.contains("try await Self.awaitExportSession(box)"))
        XCTAssertTrue(source.contains("private final class AVAssetExportSessionBox"))
    }

    func testExportSessionRunnerCancelsUnderlyingSessionWhenTaskIsCancelled() async throws {
        let session = ControllableFakeExportSession()
        let task = Task {
            try await IOSAVFoundationVideoRenderer.awaitExportSession(session)
        }

        try await waitUntil("export started") {
            session.hasStarted()
        }

        task.cancel()

        try await waitUntil("session cancelled") {
            session.cancelCallCount() == 1
        }

        do {
            try await task.value
            XCTFail("Cancelling the render task should cancel and fail the export session.")
        } catch {}

        session.finish(with: .completed)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moongate-ios-render-exporter-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func waitUntil(
        _ description: String,
        predicate: @escaping () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    #if canImport(AVFoundation)
    private func makeFixtureVideo(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: 30)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            let pixelBuffer = try makePixelBuffer(frame: frame)
            let presentationTime = CMTime(value: Int64(frame), timescale: frameDuration.timescale)
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: presentationTime))
        }
        input.markAsFinished()

        let finished = expectation(description: "asset writer finished")
        writer.finishWriting {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        if writer.status != .completed {
            throw writer.error ?? IOSMobileRenderExporter.RenderExportError.outputMissing
        }
    }

    private func makePixelBuffer(frame: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw IOSMobileRenderExporter.RenderExportError.outputMissing
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw IOSMobileRenderExporter.RenderExportError.outputMissing
        }
        let buffer = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                buffer[offset] = 210
                buffer[offset + 1] = 150
                buffer[offset + 2] = 90
                buffer[offset + 3] = 255
            }
        }
        return pixelBuffer
    }

    private func averageFrameLuminance(in url: URL, seconds: Double) throws -> Double {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        let image = try generator.copyCGImage(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            actualTime: nil
        )
        return try averageLuminance(of: image)
    }

    private func averageLuminance(of image: CGImage) throws -> Double {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw IOSMobileRenderExporter.RenderExportError.outputMissing
            }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw IOSMobileRenderExporter.RenderExportError.outputMissing
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var total = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[offset])
            let green = Double(pixels[offset + 1])
            let blue = Double(pixels[offset + 2])
            total += 0.299 * red + 0.587 * green + 0.114 * blue
        }
        return total / Double(width * height)
    }
    #endif
}

private final class ControllableFakeExportSession: IOSAssetExportSessioning, @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable () -> Void)?
    private var started = false
    private var cancelCount = 0
    private var statusValue: IOSAssetExportSessionStatus = .other
    private var errorValue: Error?

    var exportStatus: IOSAssetExportSessionStatus {
        lock.lock()
        defer { lock.unlock() }
        return statusValue
    }

    var exportError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return errorValue
    }

    func exportAsynchronously(completionHandler: @escaping @Sendable () -> Void) {
        lock.lock()
        started = true
        completion = completionHandler
        lock.unlock()
    }

    func cancelExport() {
        lock.lock()
        cancelCount += 1
        statusValue = .cancelled
        let completion = completion
        lock.unlock()
        completion?()
    }

    func hasStarted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func cancelCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cancelCount
    }

    func finish(with status: IOSAssetExportSessionStatus, error: Error? = nil) {
        lock.lock()
        statusValue = status
        errorValue = error
        let completion = completion
        lock.unlock()
        completion?()
    }
}

private actor RecordingIOSVideoRenderer: IOSVideoRendering {
    struct Invocation: Equatable {
        var sourceURL: URL
        var subtitleURLs: [URL]
        var outputURL: URL
        var maxRenderHeight: Int?
    }

    private(set) var invocations: [Invocation] = []

    func recordedInvocations() -> [Invocation] {
        invocations
    }

    func render(
        sourceURL: URL,
        subtitleURLs: [URL],
        outputURL: URL,
        maxRenderHeight: Int?,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws {
        invocations.append(Invocation(
            sourceURL: sourceURL,
            subtitleURLs: subtitleURLs,
            outputURL: outputURL,
            maxRenderHeight: maxRenderHeight
        ))
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 2))
        try Data("rendered-video".utf8).write(to: outputURL)
    }
}

private final class RenderProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MobileTaskProgress] = []

    func record(_ progress: MobileTaskProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshots() -> [MobileTaskProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
