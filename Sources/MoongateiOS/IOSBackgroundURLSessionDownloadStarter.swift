import Foundation
import MoongateMobileCore

public protocol IOSBackgroundDownloadTasking: AnyObject, Sendable {
    var taskDescription: String? { get set }
    func resume()
    func cancel()
}

public protocol IOSBackgroundDownloadSessioning: Sendable {
    func makeDownloadTask(with request: URLRequest) -> any IOSBackgroundDownloadTasking
    func allDownloadTasks() async -> [any IOSBackgroundDownloadTasking]
}

extension URLSessionDownloadTask: IOSBackgroundDownloadTasking {}

public struct IOSBackgroundURLSessionDownloadSession: IOSBackgroundDownloadSessioning {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func makeDownloadTask(with request: URLRequest) -> any IOSBackgroundDownloadTasking {
        session.downloadTask(with: request)
    }

    public func allDownloadTasks() async -> [any IOSBackgroundDownloadTasking] {
        await session.allTasks.compactMap { $0 as? URLSessionDownloadTask }
    }
}

public struct IOSBackgroundURLSessionDownloadStartResult: Sendable, Equatable {
    public var transferIdentifier: String
    public var record: BackgroundTransferRecord

    public init(
        transferIdentifier: String,
        record: BackgroundTransferRecord
    ) {
        self.transferIdentifier = transferIdentifier
        self.record = record
    }
}

public protocol IOSBackgroundDownloadStarting: Sendable {
    func startBackgroundDownload(
        _ request: MobileDownloadRequest
    ) async throws -> IOSBackgroundURLSessionDownloadStartResult

    func cancelBackgroundDownload(taskID: String) async throws
}

public extension IOSBackgroundDownloadStarting {
    func cancelBackgroundDownload(taskID: String) async throws {}
}

public struct IOSBackgroundURLSessionDownloadStarter: IOSBackgroundDownloadStarting {
    public enum StartError: Error, Sendable, Equatable {
        case unsupportedURL
        case unsafeTaskID
    }

    private let transferRegistry: BackgroundTransferRegistry
    private let session: any IOSBackgroundDownloadSessioning

    public init(
        transferRegistry: BackgroundTransferRegistry,
        descriptor: IOSBackgroundURLSessionDescriptor,
        delegate: IOSBackgroundURLSessionDownloadDelegate,
        delegateQueue: OperationQueue? = nil
    ) {
        let session = URLSession(
            configuration: descriptor.makeConfiguration(),
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        self.init(
            transferRegistry: transferRegistry,
            session: IOSBackgroundURLSessionDownloadSession(session: session)
        )
    }

    public init(
        transferRegistry: BackgroundTransferRegistry,
        session: any IOSBackgroundDownloadSessioning
    ) {
        self.transferRegistry = transferRegistry
        self.session = session
    }

    public func startBackgroundDownload(
        _ request: MobileDownloadRequest
    ) async throws -> IOSBackgroundURLSessionDownloadStartResult {
        try await startBackgroundDownload(request, updatedAt: Date())
    }

    public func cancelBackgroundDownload(taskID: String) async throws {
        let safeTaskID = try safeStorageComponent(taskID)
        let transferIdentifier = "ios.download.\(safeTaskID)"
        let tasks = await session.allDownloadTasks()
        for task in tasks where task.taskDescription == transferIdentifier {
            task.cancel()
        }
    }

    public func startBackgroundDownload(
        _ request: MobileDownloadRequest,
        updatedAt: Date = Date()
    ) async throws -> IOSBackgroundURLSessionDownloadStartResult {
        guard let url = URL(string: request.sourceURL),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw StartError.unsupportedURL
        }
        let safeTaskID = try safeStorageComponent(request.id)
        let transferIdentifier = "ios.download.\(safeTaskID)"
        let storageIdentifier = "downloads/\(outputFileName(safeTaskID: safeTaskID, request: request, sourceURL: url))"
        let progress = MobileTaskProgress(phase: .downloading, completedUnitCount: 0)
        let backgroundPolicy = MobileBackgroundPolicy(
            execution: .backgroundTransfer,
            resumability: .resumable,
            limits: [.systemDeferred]
        )
        let record = BackgroundTransferRecord(
            transferIdentifier: transferIdentifier,
            taskID: request.id,
            platform: .iOS,
            backgroundPolicy: backgroundPolicy,
            artifactStorageIdentifier: storageIdentifier,
            lastProgress: progress,
            updatedAt: updatedAt
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.makeDownloadTask(with: urlRequest)
        task.taskDescription = transferIdentifier
        try await transferRegistry.record(record)
        task.resume()

        return IOSBackgroundURLSessionDownloadStartResult(
            transferIdentifier: transferIdentifier,
            record: record
        )
    }

    private func outputFileName(safeTaskID: String, request: MobileDownloadRequest, sourceURL: URL) -> String {
        "\(safeTaskID).\(fileExtension(for: request, sourceURL: sourceURL))"
    }

    private func fileExtension(for request: MobileDownloadRequest, sourceURL: URL) -> String {
        let sourceExtension = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceExtension.isEmpty {
            return sourceExtension
        }
        let formatExtension = request.formatID
            .split(separator: ".")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return request.formatID.contains(".") && !formatExtension.isEmpty ? formatExtension : "mp4"
    }

    private func safeStorageComponent(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\") else {
            throw StartError.unsafeTaskID
        }
        return trimmed
    }
}
