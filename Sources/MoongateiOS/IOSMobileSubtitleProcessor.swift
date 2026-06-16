import Foundation
import MoongateMobileCore

public struct IOSMobileSubtitleProcessor: SubtitleProcessor {
    public enum SubtitleProcessingError: Error, Sendable, Equatable {
        case unsupportedExportProfile
        case unsafeStorageIdentifier
    }

    private let storageDirectoryURL: URL

    public init(storageDirectoryURL: URL) {
        self.storageDirectoryURL = storageDirectoryURL
    }

    public func process(
        _ request: MobileSubtitleProcessingRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskArtifact {
        guard request.exportProfile.subtitleMode == .translatedSubtitleFile ||
              request.exportProfile.subtitleMode == .softSubtitle else {
            throw SubtitleProcessingError.unsupportedExportProfile
        }

        let sourceURL = try appOwnedURL(for: request.sourceSubtitle.storageIdentifier)
        let document = MobileSubtitleDocument
            .parseSRT(try String(contentsOf: sourceURL, encoding: .utf8))
            .cleanedForTranslation()
        let translated = document.applying(request.translation, style: .translatedOnly)
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: storageDirectoryURL)

        switch request.exportProfile.subtitleMode {
        case .translatedSubtitleFile:
            return try writeTranslatedSubtitleFile(
                translated,
                sourceSubtitle: request.sourceSubtitle,
                progress: progress
            )
        case .softSubtitle:
            return try writeSoftSubtitlePackage(
                translated,
                sourceSubtitle: request.sourceSubtitle,
                progress: progress
            )
        case .none, .burnedInSubtitle:
            throw SubtitleProcessingError.unsupportedExportProfile
        }
    }

    private func writeTranslatedSubtitleFile(
        _ translated: MobileSubtitleDocument,
        sourceSubtitle: MobileTaskArtifact,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) throws -> MobileTaskArtifact {
        let outputDirectory = storageDirectoryURL.appendingPathComponent("Subtitles", isDirectory: true)
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: outputDirectory)

        let fileName = availableTranslatedFileName(
            from: sourceSubtitle.displayName,
            in: outputDirectory
        )
        let outputURL = outputDirectory.appendingPathComponent(fileName, isDirectory: false)
        try translated.serializedSRT().write(to: outputURL, atomically: true, encoding: .utf8)
        try IOSAppStoragePolicy.applyFilePolicy(to: outputURL)

        progress(MobileTaskProgress(
            phase: .translating,
            completedUnitCount: translated.cues.count,
            totalUnitCount: translated.cues.count
        ))

        return MobileTaskArtifact(
            id: "subtitle-\(sourceSubtitle.id)",
            kind: .translatedSubtitleFile,
            displayName: fileName,
            storageIdentifier: "Subtitles/\(fileName)",
            byteCount: storedByteCount(at: outputURL)
        )
    }

    private func writeSoftSubtitlePackage(
        _ translated: MobileSubtitleDocument,
        sourceSubtitle: MobileTaskArtifact,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) throws -> MobileTaskArtifact {
        let outputDirectory = storageDirectoryURL.appendingPathComponent("SoftSubtitles", isDirectory: true)
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: outputDirectory)

        let packageName = availableSoftSubtitlePackageName(
            from: sourceSubtitle.displayName,
            in: outputDirectory
        )
        let packageURL = outputDirectory.appendingPathComponent(packageName, isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: packageURL)

        let subtitleFileName = "subtitles.zh-Hans.srt"
        let subtitleURL = packageURL.appendingPathComponent(subtitleFileName, isDirectory: false)
        try translated.serializedSRT().write(to: subtitleURL, atomically: true, encoding: .utf8)
        try IOSAppStoragePolicy.applyFilePolicy(to: subtitleURL)

        let manifest = """
        {"kind":"softSubtitle","subtitle":"\(subtitleFileName)"}
        """
        let manifestURL = packageURL.appendingPathComponent("manifest.json", isDirectory: false)
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        try IOSAppStoragePolicy.applyFilePolicy(to: manifestURL)

        progress(MobileTaskProgress(
            phase: .translating,
            completedUnitCount: translated.cues.count,
            totalUnitCount: translated.cues.count
        ))

        return MobileTaskArtifact(
            id: "soft-subtitle-\(sourceSubtitle.id)",
            kind: .softSubtitle,
            displayName: packageName,
            storageIdentifier: "SoftSubtitles/\(packageName)",
            byteCount: storedByteCount(at: subtitleURL)
        )
    }

    private func appOwnedURL(for storageIdentifier: String) throws -> URL {
        do {
            return try IOSArtifactStore(storageDirectoryURL: storageDirectoryURL)
                .fileURL(forStorageIdentifier: storageIdentifier)
        } catch IOSArtifactStoreError.unsafeStorageIdentifier {
            throw SubtitleProcessingError.unsafeStorageIdentifier
        } catch {
            throw SubtitleProcessingError.unsafeStorageIdentifier
        }
    }

    private func availableTranslatedFileName(from displayName: String, in directory: URL) -> String {
        let root = translatedFileNameRoot(from: displayName)
        var candidate = "\(root).zh.srt"
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(root)-\(suffix).zh.srt"
            suffix += 1
        }
        return candidate
    }

    private func availableSoftSubtitlePackageName(from displayName: String, in directory: URL) -> String {
        let root = translatedFileNameRoot(from: displayName)
        var candidate = "\(root).soft-subtitles"
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate, isDirectory: true).path) {
            candidate = "\(root)-\(suffix).soft-subtitles"
            suffix += 1
        }
        return candidate
    }

    private func translatedFileNameRoot(from displayName: String) -> String {
        let base = (displayName as NSString).deletingPathExtension
        let sanitizedBase = base
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizedBase.isEmpty ? "subtitle" : sanitizedBase
    }

    private func storedByteCount(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[FileAttributeKey.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }
}
