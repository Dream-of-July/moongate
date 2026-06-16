import Foundation
import MoongateMobileCore

public struct IOSBackgroundURLSessionDescriptor: Sendable, Equatable {
    public var bundleIdentifier: String
    public var purpose: String

    public init(bundleIdentifier: String, purpose: String = "downloads") {
        self.bundleIdentifier = IOSBackgroundURLSessionDescriptor.sanitizedIdentifierComponent(bundleIdentifier)
        self.purpose = IOSBackgroundURLSessionDescriptor.sanitizedIdentifierComponent(purpose)
    }

    public var identifier: String {
        "\(bundleIdentifier).background.\(purpose)"
    }

    public func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    private static func sanitizedIdentifierComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return sanitized.isEmpty ? "local" : sanitized
    }
}

public protocol IOSBackgroundURLSessionCompletionConsuming: AnyObject, Sendable {
    func consumeCompletionHandler(for identifier: String)
}

public final class IOSNoopBackgroundURLSessionCompletionConsumer: IOSBackgroundURLSessionCompletionConsuming, @unchecked Sendable {
    public init() {}

    public func consumeCompletionHandler(for identifier: String) {}
}

public final class IOSBackgroundURLSessionDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let eventRecorder: IOSBackgroundTransferEventHandler
    private let completionConsumer: any IOSBackgroundURLSessionCompletionConsuming
    private let pendingEvents = IOSBackgroundURLSessionPendingEventDrain()

    public init(
        eventRecorder: IOSBackgroundTransferEventHandler,
        completionConsumer: any IOSBackgroundURLSessionCompletionConsuming
    ) {
        self.eventRecorder = eventRecorder
        self.completionConsumer = completionConsumer
        super.init()
    }

    public func recordFinishedDownload(
        transferIdentifier: String,
        temporaryFileURL: URL,
        updatedAt: Date = Date()
    ) async throws -> BackgroundTransferRecoveryOutcome {
        try await eventRecorder.recordCompletedDownload(
            transferIdentifier: transferIdentifier,
            temporaryFileURL: temporaryFileURL,
            updatedAt: updatedAt
        )
    }

    public func recordTaskFailure(
        transferIdentifier: String,
        error: Error?,
        updatedAt: Date = Date()
    ) async throws -> BackgroundTransferRecoveryOutcome {
        try await eventRecorder.recordFailedDownload(
            transferIdentifier: transferIdentifier,
            error: mobileErrorBucket(for: error),
            updatedAt: updatedAt
        )
    }

    public func finishEvents(forSessionIdentifier identifier: String) {
        pendingEvents.markSessionFinished(identifier)
        drainFinishedSessionsIfReady()
    }

    public func enqueueFinishedDownload(
        transferIdentifier: String,
        temporaryFileURL: URL,
        updatedAt: Date = Date()
    ) {
        pendingEvents.begin()
        Task {
            _ = try? await recordFinishedDownload(
                transferIdentifier: transferIdentifier,
                temporaryFileURL: temporaryFileURL,
                updatedAt: updatedAt
            )
            pendingEvents.finish()
            drainFinishedSessionsIfReady()
        }
    }

    public func enqueueTaskFailure(
        transferIdentifier: String,
        error: Error?,
        updatedAt: Date = Date()
    ) {
        pendingEvents.begin()
        Task {
            _ = try? await recordTaskFailure(
                transferIdentifier: transferIdentifier,
                error: error,
                updatedAt: updatedAt
            )
            pendingEvents.finish()
            drainFinishedSessionsIfReady()
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let transferIdentifier = transferIdentifier(for: downloadTask)
        enqueueFinishedDownload(
            transferIdentifier: transferIdentifier,
            temporaryFileURL: location
        )
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        let transferIdentifier = transferIdentifier(for: task)
        enqueueTaskFailure(
            transferIdentifier: transferIdentifier,
            error: error
        )
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        finishEvents(forSessionIdentifier: identifier)
    }

    private func transferIdentifier(for task: URLSessionTask) -> String {
        let description = task.taskDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? "ios.download.\(task.taskIdentifier)" : description
    }

    private func drainFinishedSessionsIfReady() {
        for identifier in pendingEvents.drainFinishedSessionsIfReady() {
            completionConsumer.consumeCompletionHandler(for: identifier)
        }
    }

    private func mobileErrorBucket(for error: Error?) -> MobileTaskError {
        guard let error else { return .unknown }
        let urlError = error as? URLError
        switch urlError?.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .timedOut:
            return .networkUnavailable
        case .userCancelledAuthentication,
             .userAuthenticationRequired:
            return .credentialRequired
        case .cancelled:
            return .cancelled
        default:
            return .unknown
        }
    }
}

private final class IOSBackgroundURLSessionPendingEventDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingEventCount = 0
    private var finishedSessionIdentifiers: [String] = []

    func begin() {
        lock.lock()
        pendingEventCount += 1
        lock.unlock()
    }

    func finish() {
        lock.lock()
        pendingEventCount = max(0, pendingEventCount - 1)
        lock.unlock()
    }

    func markSessionFinished(_ identifier: String) {
        lock.lock()
        if !finishedSessionIdentifiers.contains(identifier) {
            finishedSessionIdentifiers.append(identifier)
        }
        lock.unlock()
    }

    func drainFinishedSessionsIfReady() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard pendingEventCount == 0 else { return [] }
        let identifiers = finishedSessionIdentifiers
        finishedSessionIdentifiers.removeAll()
        return identifiers
    }
}
