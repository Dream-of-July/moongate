import MoongateMobileCore

public enum IOSRenderPlanKind: String, Codable, Sendable, Equatable, CaseIterable {
    case originalMediaOnly
    case subtitleFileOnly
    case softSubtitlePackage
    case burnedInRender
}

public enum IOSRenderPlanBlockedReason: String, Codable, Sendable, Equatable, CaseIterable {
    case capabilityUnavailable
    case rendererUnavailable
    case renderHeightUnsupported
}

public struct IOSRenderRuntimeCapabilities: Codable, Sendable, Equatable {
    public var supportsContinuedProcessing: Bool
    public var supportsCheckpointedRender: Bool
    public var continuedProcessingTimeLimitSeconds: Int?

    public init(
        supportsContinuedProcessing: Bool = false,
        supportsCheckpointedRender: Bool = false,
        continuedProcessingTimeLimitSeconds: Int? = nil
    ) {
        self.supportsContinuedProcessing = supportsContinuedProcessing
        self.supportsCheckpointedRender = supportsCheckpointedRender
        self.continuedProcessingTimeLimitSeconds = continuedProcessingTimeLimitSeconds
    }
}

public struct IOSRenderPlan: Codable, Sendable, Equatable {
    public var request: MobileRenderRequest
    public var kind: IOSRenderPlanKind
    public var outputArtifactKind: MobileArtifactKind
    public var requiresRenderExporter: Bool
    public var backgroundPolicy: MobileBackgroundPolicy
    public var blockedReason: IOSRenderPlanBlockedReason?

    public init(
        request: MobileRenderRequest,
        kind: IOSRenderPlanKind,
        outputArtifactKind: MobileArtifactKind,
        requiresRenderExporter: Bool,
        backgroundPolicy: MobileBackgroundPolicy,
        blockedReason: IOSRenderPlanBlockedReason? = nil
    ) {
        self.request = request
        self.kind = kind
        self.outputArtifactKind = outputArtifactKind
        self.requiresRenderExporter = requiresRenderExporter
        self.backgroundPolicy = backgroundPolicy
        self.blockedReason = blockedReason
    }
}

public struct IOSRenderRequestPlanner: Sendable {
    public var capabilities: MobileProcessingCapabilities
    public var runtime: IOSRenderRuntimeCapabilities

    public init(
        capabilities: MobileProcessingCapabilities = MobileProcessingCapabilities(platform: .iOS),
        runtime: IOSRenderRuntimeCapabilities = IOSRenderRuntimeCapabilities()
    ) {
        self.capabilities = capabilities
        self.runtime = runtime
    }

    public func plan(_ request: MobileRenderRequest) -> IOSRenderPlan {
        switch request.exportProfile.subtitleMode {
        case .none:
            guard capabilities.canSatisfy(request.exportProfile) else {
                return IOSRenderPlan(
                    request: request,
                    kind: .originalMediaOnly,
                    outputArtifactKind: .originalMedia,
                    requiresRenderExporter: false,
                    backgroundPolicy: foregroundPolicy(resumability: .nonResumable),
                    blockedReason: .capabilityUnavailable
                )
            }
            return IOSRenderPlan(
                request: request,
                kind: .originalMediaOnly,
                outputArtifactKind: .originalMedia,
                requiresRenderExporter: false,
                backgroundPolicy: foregroundPolicy(resumability: .resumable)
            )
        case .translatedSubtitleFile:
            guard capabilities.canSatisfy(request.exportProfile) else {
                return IOSRenderPlan(
                    request: request,
                    kind: .subtitleFileOnly,
                    outputArtifactKind: .translatedSubtitleFile,
                    requiresRenderExporter: false,
                    backgroundPolicy: foregroundPolicy(resumability: .nonResumable),
                    blockedReason: .capabilityUnavailable
                )
            }
            return IOSRenderPlan(
                request: request,
                kind: .subtitleFileOnly,
                outputArtifactKind: .translatedSubtitleFile,
                requiresRenderExporter: false,
                backgroundPolicy: foregroundPolicy(resumability: .resumable)
            )
        case .softSubtitle:
            guard capabilities.canSatisfy(request.exportProfile) else {
                return IOSRenderPlan(
                    request: request,
                    kind: .softSubtitlePackage,
                    outputArtifactKind: .softSubtitle,
                    requiresRenderExporter: false,
                    backgroundPolicy: foregroundPolicy(resumability: .nonResumable),
                    blockedReason: .capabilityUnavailable
                )
            }
            return IOSRenderPlan(
                request: request,
                kind: .softSubtitlePackage,
                outputArtifactKind: .softSubtitle,
                requiresRenderExporter: false,
                backgroundPolicy: foregroundPolicy(resumability: .resumable)
            )
        case .burnedInSubtitle:
            return burnedInPlan(for: request)
        }
    }

    private func burnedInPlan(for request: MobileRenderRequest) -> IOSRenderPlan {
        guard capabilities.supports(.videoRender) else {
            return IOSRenderPlan(
                request: request,
                kind: .burnedInRender,
                outputArtifactKind: .renderedVideo,
                requiresRenderExporter: true,
                backgroundPolicy: foregroundPolicy(resumability: .nonResumable),
                blockedReason: .rendererUnavailable
            )
        }

        guard capabilities.canSatisfy(request.exportProfile) else {
            return IOSRenderPlan(
                request: request,
                kind: .burnedInRender,
                outputArtifactKind: .renderedVideo,
                requiresRenderExporter: true,
                backgroundPolicy: foregroundPolicy(resumability: .nonResumable),
                blockedReason: .renderHeightUnsupported
            )
        }

        guard capabilities.supports(.backgroundRender),
              runtime.supportsContinuedProcessing
        else {
            return IOSRenderPlan(
                request: request,
                kind: .burnedInRender,
                outputArtifactKind: .renderedVideo,
                requiresRenderExporter: true,
                backgroundPolicy: foregroundPolicy(resumability: .nonResumable)
            )
        }

        return IOSRenderPlan(
            request: request,
            kind: .burnedInRender,
            outputArtifactKind: .renderedVideo,
            requiresRenderExporter: true,
            backgroundPolicy: MobileBackgroundPolicy(
                execution: .continuedProcessing,
                resumability: runtime.supportsCheckpointedRender ? .resumable : .nonResumable,
                systemTimeLimitSeconds: runtime.continuedProcessingTimeLimitSeconds,
                limits: continuedProcessingLimits()
            )
        )
    }

    private func foregroundPolicy(
        resumability: MobileBackgroundResumability
    ) -> MobileBackgroundPolicy {
        var limits: [MobileBackgroundLimit] = [.foregroundRequired]
        if resumability == .nonResumable {
            limits.append(.notResumable)
        }
        return MobileBackgroundPolicy(
            execution: .foregroundRequired,
            resumability: resumability,
            limits: limits
        )
    }

    private func continuedProcessingLimits() -> [MobileBackgroundLimit] {
        var limits: [MobileBackgroundLimit] = [
            .systemTimeLimit,
            .userVisibleNotificationRequired
        ]
        if !runtime.supportsCheckpointedRender {
            limits.append(.notResumable)
        }
        return limits
    }
}
