import Foundation
import MoongateMobileCore

public protocol IOSBackgroundDownloadTask: AnyObject, Sendable {
    var taskIdentifier: Int { get }
    var taskDescription: String? { get set }
    func resume()
}

public protocol IOSBackgroundDownloadSession: Sendable {
    func makeDownloadTask(with request: URLRequest) -> any IOSBackgroundDownloadTask
}

extension URLSessionDownloadTask: IOSBackgroundDownloadTask {}

public struct IOSURLSessionBackgroundDownloadSession: IOSBackgroundDownloadSession {
    private let session: URLSession

    public init(
        descriptor: IOSBackgroundURLSessionDescriptor,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) {
        self.session = URLSession(
            configuration: descriptor.makeConfiguration(),
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func makeDownloadTask(with request: URLRequest) -> any IOSBackgroundDownloadTask {
        session.downloadTask(with: request)
    }
}

public struct IOSBackgroundDownloadLaunchRequest: Sendable, Equatable {
    public var downloadRequest: MobileDownloadRequest

    public init(downloadRequest: MobileDownloadRequest) {
        self.downloadRequest = downloadRequest
    }
}

public struct IOSBackgroundDownloadLauncher: Sendable {
    public enum LaunchError: Error, Sendable, Equatable {
        case unsupportedURL
        case unsafeTaskID
    }

    private let transferRegistry: BackgroundTransferRegistry
    private let session: any IOSBackgroundDownloadSession

    public init(
        transferRegistry: BackgroundTransferRegistry,
        session: any IOSBackgroundDownloadSession
    ) {
        self.transferRegistry = transferRegistry
        self.session = session
    }

    public init(
        transferRegistry: BackgroundTransferRegistry,
        descriptor: IOSBackgroundURLSessionDescriptor,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) {
        self.init(
            transferRegistry: transferRegistry,
            session: IOSURLSessionBackgroundDownloadSession(
                descriptor: descriptor,
                delegate: delegate,
                delegateQueue: delegateQueue
            )
        )
    }

    public func start(
        _ launchRequest: IOSBackgroundDownloadLaunchRequest,
        updatedAt: Date = Date()
    ) async throws -> BackgroundTransferRecord {
        let request = launchRequest.downloadRequest
        guard let url = URL(string: request.sourceURL),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw LaunchError.unsupportedURL
        }

        let safeTaskID = try safeStorageComponent(request.id)
        let transferIdentifier = "ios.download.\(safeTaskID)"
        let artifactStorageIdentifier = "downloads/\(safeTaskID).\(fileExtension(for: request, sourceURL: url))"
        let progress = MobileTaskProgress(phase: .downloading, completedUnitCount: 0)
        let record = BackgroundTransferRecord(
            transferIdentifier: transferIdentifier,
            taskID: request.id,
            platform: .iOS,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .backgroundTransfer,
                resumability: .resumable,
                limits: [.systemDeferred]
            ),
            artifactStorageIdentifier: artifactStorageIdentifier,
            lastProgress: progress,
            updatedAt: updatedAt
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.makeDownloadTask(with: urlRequest)
        task.taskDescription = transferIdentifier
        try await transferRegistry.record(record)
        task.resume()

        return record
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
            throw LaunchError.unsafeTaskID
        }
        return trimmed
    }
}
