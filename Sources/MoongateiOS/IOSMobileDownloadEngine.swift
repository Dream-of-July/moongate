import Foundation
import MoongateMobileCore

public struct IOSMobileDownloadTransportResult: Sendable, Equatable {
    public var temporaryFileURL: URL
    public var byteCount: Int?

    public init(temporaryFileURL: URL, byteCount: Int? = nil) {
        self.temporaryFileURL = temporaryFileURL
        self.byteCount = byteCount
    }
}

public protocol IOSMobileDownloadTransport: Sendable {
    func download(
        from url: URL,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> IOSMobileDownloadTransportResult
}

public struct IOSURLSessionMobileDownloadTransport: IOSMobileDownloadTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        from url: URL,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> IOSMobileDownloadTransportResult {
        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: 0))
        let (temporaryURL, response) = try await session.download(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw IOSMobileDownloadEngine.DownloadError.httpStatus(httpResponse.statusCode)
        }
        let byteCount = (response as? HTTPURLResponse)?.expectedContentLength
        let normalizedByteCount = byteCount.flatMap { $0 >= 0 ? Int($0) : nil }
        if let normalizedByteCount {
            progress(MobileTaskProgress(
                phase: .downloading,
                completedUnitCount: normalizedByteCount,
                totalUnitCount: normalizedByteCount
            ))
        }
        return IOSMobileDownloadTransportResult(
            temporaryFileURL: temporaryURL,
            byteCount: normalizedByteCount
        )
    }
}

public struct IOSMobileDownloadEngine: MobileDownloadEngine {
    public enum DownloadError: Error, Sendable, Equatable {
        case unsupportedURL
        case storageUnavailable
        case unsafeTaskID
        case httpStatus(Int)
    }

    private let downloadDirectoryURL: URL
    private let transferRegistry: BackgroundTransferRegistry
    private let transport: any IOSMobileDownloadTransport

    public init(
        downloadDirectoryURL: URL,
        transferRegistry: BackgroundTransferRegistry,
        transport: any IOSMobileDownloadTransport = IOSURLSessionMobileDownloadTransport()
    ) {
        self.downloadDirectoryURL = downloadDirectoryURL
        self.transferRegistry = transferRegistry
        self.transport = transport
    }

    public func download(
        _ request: MobileDownloadRequest,
        progress: @escaping @Sendable (MobileTaskProgress) -> Void
    ) async throws -> MobileTaskResult {
        guard let url = safeDownloadURL(from: request.sourceURL) else {
            throw DownloadError.unsupportedURL
        }
        let safeTaskID = try safeStorageComponent(request.id)

        let fileManager = FileManager.default
        if downloadDirectoryURL.lastPathComponent == "Downloads" {
            try IOSAppStoragePolicy.applyDirectoryPolicy(to: downloadDirectoryURL.deletingLastPathComponent())
        }
        try IOSAppStoragePolicy.applyDirectoryPolicy(to: downloadDirectoryURL)

        progress(MobileTaskProgress(phase: .downloading, completedUnitCount: 0))
        let result = try await transport.download(from: url, progress: progress)
        let outputURL = downloadDirectoryURL.appendingPathComponent(
            outputFileName(safeTaskID: safeTaskID, request: request, sourceURL: url),
            isDirectory: false
        )
        guard outputURL.standardizedFileURL.path.hasPrefix(downloadDirectoryURL.standardizedFileURL.path + "/") else {
            throw DownloadError.unsafeTaskID
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.moveItem(at: result.temporaryFileURL, to: outputURL)
        try IOSAppStoragePolicy.applyFilePolicy(to: outputURL)

        let byteCount = result.byteCount ?? storedByteCount(at: outputURL)
        let finalProgress = MobileTaskProgress(
            phase: .downloading,
            completedUnitCount: byteCount ?? 0,
            totalUnitCount: byteCount
        )
        progress(finalProgress)

        let artifact = MobileTaskArtifact(
            id: "original-\(request.id)",
            kind: .originalMedia,
            displayName: displayName(for: request, sourceURL: url),
            storageIdentifier: "downloads/\(outputURL.lastPathComponent)",
            byteCount: byteCount
        )

        try await transferRegistry.record(BackgroundTransferRecord(
            transferIdentifier: "ios.download.\(safeTaskID)",
            taskID: request.id,
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .foregroundRequired,
                resumability: .nonResumable,
                limits: [.foregroundRequired, .notResumable]
            ),
            artifactStorageIdentifier: artifact.storageIdentifier,
            lastProgress: finalProgress
        ))

        return MobileTaskResult(
            artifacts: [artifact],
            primaryArtifactID: artifact.id
        )
    }

    private func outputFileName(safeTaskID: String, request: MobileDownloadRequest, sourceURL: URL) -> String {
        return "\(safeTaskID).\(fileExtension(for: request, sourceURL: sourceURL))"
    }

    private func displayName(for request: MobileDownloadRequest, sourceURL: URL) -> String {
        let title = sanitizedTitle(request.preferredTitle ?? request.videoID)
        return "\(title).\(fileExtension(for: request, sourceURL: sourceURL))"
    }

    private func fileExtension(for request: MobileDownloadRequest, sourceURL: URL) -> String {
        let sourceExtension = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceExtension.isEmpty {
            return sourceExtension
        }
        let formatExtension = request.formatID.split(separator: ".").last.map(String.init) ?? ""
        return formatExtension.isEmpty ? "mp4" : formatExtension
    }

    private func sanitizedTitle(_ title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = title.components(separatedBy: illegal)
        let sanitized = parts.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "download" : sanitized
    }

    private func safeStorageComponent(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\") else {
            throw DownloadError.unsafeTaskID
        }
        return trimmed
    }

    private func storedByteCount(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[FileAttributeKey.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private func safeDownloadURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.host?.isEmpty == false,
              components.fragment == nil else {
            return nil
        }
        return components.url
    }
}
