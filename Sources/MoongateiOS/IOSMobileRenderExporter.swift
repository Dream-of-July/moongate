import Foundation
import MoongateMobileCore

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

#if canImport(QuartzCore)
import QuartzCore
#endif

public protocol IOSVideoRendering: Sendable {
    func render(
        sourceURL: URL,
        subtitleURLs: [URL],
        outputURL: URL,
        maxRenderHeight: Int?,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws
}

enum IOSAssetExportSessionStatus: Sendable, Equatable {
    case completed
    case failed
    case cancelled
    case other
}

protocol IOSAssetExportSessioning: AnyObject, Sendable {
    var exportStatus: IOSAssetExportSessionStatus { get }
    var exportError: Error? { get }

    func exportAsynchronously(completionHandler: @escaping @Sendable () -> Void)
    func cancelExport()
}

public struct IOSVideoRenderGeometry: Sendable, Equatable {
    public var renderSize: CGSize
    public var layerTransform: CGAffineTransform

    public static func make(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        maxRenderHeight: Int?
    ) -> IOSVideoRenderGeometry {
        let transformed = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let normalizedSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        guard let maxRenderHeight,
              maxRenderHeight > 0,
              normalizedSize.height > CGFloat(maxRenderHeight) else {
            return IOSVideoRenderGeometry(
                renderSize: normalizedSize,
                layerTransform: preferredTransform
            )
        }

        let scale = CGFloat(maxRenderHeight) / normalizedSize.height
        let renderSize = CGSize(
            width: (normalizedSize.width * scale).rounded(),
            height: (normalizedSize.height * scale).rounded()
        )
        return IOSVideoRenderGeometry(
            renderSize: renderSize,
            layerTransform: preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        )
    }
}

public struct IOSMobileRenderExporter: RenderExporter {
    public enum RenderExportError: Error, Sendable, Equatable {
        case unsupportedExportProfile
        case missingSubtitle
        case unsupportedSubtitleArtifact
        case emptySubtitle
        case unsafeStorageIdentifier
        case rendererUnavailable
        case outputMissing
    }

    private let storageDirectoryURL: URL
    private let artifactStore: IOSArtifactStore
    private let renderer: any IOSVideoRendering

    public init(
        storageDirectoryURL: URL,
        renderer: any IOSVideoRendering = IOSAVFoundationVideoRenderer()
    ) {
        self.storageDirectoryURL = storageDirectoryURL
        self.artifactStore = IOSArtifactStore(storageDirectoryURL: storageDirectoryURL)
        self.renderer = renderer
    }

    public func export(
        _ request: MobileRenderRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        guard request.exportProfile.subtitleMode == .burnedInSubtitle else {
            throw RenderExportError.unsupportedExportProfile
        }
        guard !request.subtitles.isEmpty else {
            throw RenderExportError.missingSubtitle
        }
        guard request.subtitles.allSatisfy({ $0.kind == .translatedSubtitleFile }) else {
            throw RenderExportError.unsupportedSubtitleArtifact
        }

        let sourceURL = try safeURL(for: request.sourceMedia)
        let subtitleURLs = try request.subtitles.map(safeURL(for:))
        try validateSubtitles(at: subtitleURLs)
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: storageDirectoryURL)
        let outputDirectory = storageDirectoryURL.appendingPathComponent("Renders", isDirectory: true)
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: outputDirectory)
        let outputFileName = availableRenderedFileName(from: request.sourceMedia.displayName, in: outputDirectory)
        let outputURL = outputDirectory.appendingPathComponent(outputFileName, isDirectory: false)

        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 0))
        try await renderer.render(
            sourceURL: sourceURL,
            subtitleURLs: subtitleURLs,
            outputURL: outputURL,
            maxRenderHeight: request.exportProfile.maxRenderHeight,
            progress: progress
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RenderExportError.outputMissing
        }
        try IOSAppStoragePolicy.applyFilePolicy(to: outputURL)

        let finalProgress = MobileTaskProgress(phase: .exporting, completedUnitCount: 1, totalUnitCount: 1)
        progress(finalProgress)

        let artifact = MobileTaskArtifact(
            id: "render-\(request.sourceMedia.id)",
            kind: .renderedVideo,
            displayName: outputFileName,
            storageIdentifier: "Renders/\(outputFileName)",
            byteCount: storedByteCount(at: outputURL)
        )
        return MobileTaskResult(artifacts: [artifact], primaryArtifactID: artifact.id)
    }

    private func safeURL(for artifact: MobileTaskArtifact) throws -> URL {
        do {
            return try artifactStore.fileURL(for: artifact)
        } catch {
            throw RenderExportError.unsafeStorageIdentifier
        }
    }

    private func availableRenderedFileName(from displayName: String, in directory: URL) -> String {
        let root = renderedFileNameRoot(from: displayName)
        var candidate = "\(root).rendered.mp4"
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(root)-\(suffix).rendered.mp4"
            suffix += 1
        }
        return candidate
    }

    private func validateSubtitles(at urls: [URL]) throws {
        let cueCount = try urls.reduce(0) { count, url in
            let raw = try String(contentsOf: url, encoding: .utf8)
            return count + MobileSubtitleDocument.parseSRT(raw).cues.count
        }
        guard cueCount > 0 else {
            throw RenderExportError.emptySubtitle
        }
    }

    private func renderedFileNameRoot(from displayName: String) -> String {
        let base = (displayName as NSString).deletingPathExtension
        let sanitized = base
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "render" : sanitized
    }

    private func storedByteCount(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[FileAttributeKey.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }
}

public struct IOSAVFoundationVideoRenderer: IOSVideoRendering {
    public init() {}

    static func awaitExportSession(_ session: any IOSAssetExportSessioning) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let continuationBox = IOSExportSessionContinuationBox(continuation)
                session.exportAsynchronously {
                    switch session.exportStatus {
                    case .completed:
                        continuationBox.resume()
                    case .failed, .cancelled:
                        continuationBox.resume(
                            throwing: session.exportError ?? IOSMobileRenderExporter.RenderExportError.outputMissing
                        )
                    case .other:
                        continuationBox.resume(throwing: IOSMobileRenderExporter.RenderExportError.outputMissing)
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }
    }

    public func render(
        sourceURL: URL,
        subtitleURLs: [URL],
        outputURL: URL,
        maxRenderHeight: Int?,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws {
        #if canImport(AVFoundation) && canImport(QuartzCore)
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw IOSMobileRenderExporter.RenderExportError.rendererUnavailable
        }
        let duration = try await asset.load(.duration)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw IOSMobileRenderExporter.RenderExportError.rendererUnavailable
        }
        let geometry = IOSVideoRenderGeometry.make(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            maxRenderHeight: maxRenderHeight
        )
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = try videoComposition(
            videoTrack: videoTrack,
            duration: duration,
            renderSize: geometry.renderSize,
            layerTransform: geometry.layerTransform,
            subtitleURLs: subtitleURLs
        )
        progress(MobileTaskProgress(phase: .exporting, completedUnitCount: 0, totalUnitCount: 1))

        try await export(exportSession)
        #else
        _ = sourceURL
        _ = subtitleURLs
        _ = outputURL
        _ = maxRenderHeight
        _ = progress
        throw IOSMobileRenderExporter.RenderExportError.rendererUnavailable
        #endif
    }

    #if canImport(AVFoundation) && canImport(QuartzCore)
    private func videoComposition(
        videoTrack: AVAssetTrack,
        duration: CMTime,
        renderSize: CGSize,
        layerTransform: CGAffineTransform,
        subtitleURLs: [URL]
    ) throws -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(layerTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.addSublayer(videoLayer)

        let cues = try subtitleURLs.flatMap { url in
            MobileSubtitleDocument.parseSRT(try String(contentsOf: url, encoding: .utf8)).cues
        }
        for cue in cues {
            guard let start = seconds(fromSRTTime: cue.startTime),
                  let end = seconds(fromSRTTime: cue.endTime),
                  end > start else {
                continue
            }
            parentLayer.addSublayer(subtitleLayer(for: cue.text, start: start, end: end, renderSize: renderSize))
        }

        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        return composition
    }

    private func subtitleLayer(
        for text: String,
        start: Double,
        end: Double,
        renderSize: CGSize
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.alignmentMode = .center
        layer.isWrapped = true
        layer.contentsScale = 2
        layer.fontSize = max(18, min(renderSize.width, renderSize.height) * 0.045)
        layer.foregroundColor = CGColor(gray: 1, alpha: 1)
        layer.backgroundColor = CGColor(gray: 0, alpha: 0.58)
        layer.cornerRadius = 8
        layer.masksToBounds = true
        let horizontalInset = renderSize.width * 0.08
        let height = max(64, renderSize.height * 0.18)
        layer.frame = CGRect(
            x: horizontalInset,
            y: renderSize.height * 0.08,
            width: renderSize.width - horizontalInset * 2,
            height: height
        )
        layer.opacity = 0

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
        animation.duration = end - start
        animation.values = [0, 1, 1, 0]
        animation.keyTimes = [0, 0.02, 0.98, 1]
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: "subtitleOpacity")
        return layer
    }

    private func seconds(fromSRTTime value: String) -> Double? {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }
        return Double(hours) * 3_600 + Double(minutes) * 60 + seconds
    }

    private func export(_ session: AVAssetExportSession) async throws {
        let box = AVAssetExportSessionBox(session)
        try await Self.awaitExportSession(box)
    }
    #endif
}

#if canImport(AVFoundation)
private final class AVAssetExportSessionBox: IOSAssetExportSessioning, @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    var exportStatus: IOSAssetExportSessionStatus {
        switch session.status {
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        default:
            return .other
        }
    }

    var exportError: Error? {
        session.error
    }

    func exportAsynchronously(completionHandler: @escaping @Sendable () -> Void) {
        session.exportAsynchronously(completionHandler: completionHandler)
    }

    func cancelExport() {
        session.cancelExport()
    }
}
#endif

private final class IOSExportSessionContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        resume(with: .success(()))
    }

    func resume(throwing error: Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
