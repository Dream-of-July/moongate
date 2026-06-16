import Foundation
import MoongateMobileCore

#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
#endif

public struct IOSContinuedProcessingRequestDescriptor: Codable, Sendable, Equatable {
    public enum Strategy: String, Codable, Sendable, Equatable {
        case queue
    }

    public enum RequiredResources: String, Codable, Sendable, Equatable {
        case `default`
    }

    public var identifier: String
    public var title: String
    public var subtitle: String
    public var strategy: Strategy
    public var requiredResources: RequiredResources
    public var backgroundPolicy: MobileBackgroundPolicy

    public init(
        identifier: String,
        title: String,
        subtitle: String,
        strategy: Strategy = .queue,
        requiredResources: RequiredResources = .default,
        backgroundPolicy: MobileBackgroundPolicy
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.strategy = strategy
        self.requiredResources = requiredResources
        self.backgroundPolicy = backgroundPolicy
    }
}

public struct IOSContinuedProcessingRenderScheduler: Sendable {
    public enum ScheduleError: Error, Sendable, Equatable {
        case continuedProcessingUnavailable
        case invalidTaskID
        case systemSubmissionUnavailable
    }

    public var bundleIdentifier: String

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    public func makeRequestDescriptor(
        for plan: IOSRenderPlan,
        taskID: String
    ) throws -> IOSContinuedProcessingRequestDescriptor {
        guard plan.backgroundPolicy.execution == .continuedProcessing,
              plan.blockedReason == nil else {
            throw ScheduleError.continuedProcessingUnavailable
        }
        let safeTaskID = try safeIdentifierComponent(taskID)
        return IOSContinuedProcessingRequestDescriptor(
            identifier: "\(bundleIdentifier).render.\(safeTaskID)",
            title: "导出视频",
            subtitle: plan.request.sourceMedia.displayName,
            backgroundPolicy: plan.backgroundPolicy
        )
    }

    private func safeIdentifierComponent(_ value: String) throws -> String {
        guard !value.isEmpty else {
            throw ScheduleError.invalidTaskID
        }
        guard value.unicodeScalars.allSatisfy(Self.isSafeIdentifierScalar) else {
            return "encoded-hex-\(Self.hexEncoded(value))"
        }
        return value
    }

    private static func isSafeIdentifierScalar(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        let isDigit = value >= 48 && value <= 57
        let isUppercase = value >= 65 && value <= 90
        let isLowercase = value >= 97 && value <= 122
        return isDigit || isUppercase || isLowercase || scalar == "-"
    }

    private static func hexEncoded(_ value: String) -> String {
        value.utf8.map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}

public protocol IOSContinuedProcessingTaskSubmitting: Sendable {
    func submit(_ descriptor: IOSContinuedProcessingRequestDescriptor) async throws
}

#if os(iOS) && canImport(BackgroundTasks)
public struct IOSBackgroundTasksContinuedProcessingSubmitter: IOSContinuedProcessingTaskSubmitting {
    public init() {}

    public func submit(_ descriptor: IOSContinuedProcessingRequestDescriptor) async throws {
        guard descriptor.backgroundPolicy.execution == .continuedProcessing,
              descriptor.backgroundPolicy.limits.contains(.userVisibleNotificationRequired) else {
            throw IOSContinuedProcessingRenderScheduler.ScheduleError.continuedProcessingUnavailable
        }

        if #available(iOS 26.0, *) {
            let request = BGContinuedProcessingTaskRequest(
                identifier: descriptor.identifier,
                title: descriptor.title,
                subtitle: descriptor.subtitle
            )
            request.strategy = descriptor.strategy.backgroundTaskStrategy
            request.requiredResources = descriptor.requiredResources.backgroundTaskResources
            try BGTaskScheduler.shared.submit(request)
            return
        }
        throw IOSContinuedProcessingRenderScheduler.ScheduleError.systemSubmissionUnavailable
    }
}

@available(iOS 26.0, *)
private extension IOSContinuedProcessingRequestDescriptor.Strategy {
    var backgroundTaskStrategy: BGContinuedProcessingTaskRequest.SubmissionStrategy {
        switch self {
        case .queue:
            return .queue
        }
    }
}

@available(iOS 26.0, *)
private extension IOSContinuedProcessingRequestDescriptor.RequiredResources {
    var backgroundTaskResources: BGContinuedProcessingTaskRequest.Resources {
        switch self {
        case .default:
            return []
        }
    }
}
#endif
