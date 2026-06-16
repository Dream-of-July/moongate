import Foundation
import MoongateMobileCore
#if canImport(Translation)
import Translation
#endif

public struct IOSAppleTranslationBatchRequest: Sendable, Equatable {
    public var engine: TranslationEngine
    public var context: TranslationContext
    public var segments: [MobileTranslationSegment]

    public init(
        engine: TranslationEngine,
        context: TranslationContext,
        segments: [MobileTranslationSegment]
    ) {
        self.engine = engine
        self.context = context
        self.segments = segments
    }
}

public typealias IOSAppleTranslationRequest = IOSAppleTranslationBatchRequest

public protocol IOSAppleTranslationExecuting: Sendable {
    func translate(_ request: IOSAppleTranslationBatchRequest) async throws -> [String: String]
}

public struct IOSSystemAppleTranslationExecutor: IOSAppleTranslationExecuting {
    public init() {}

    public func translate(_ request: IOSAppleTranslationBatchRequest) async throws -> [String: String] {
        let sourceIdentifier = try requiredSourceLanguage(from: request.context)
        let targetIdentifier = try requiredTargetLanguage(from: request.context)

        #if canImport(Translation)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw MobileTranslationProviderError.unsupportedEngine
        }

        let source = Locale.Language(identifier: sourceIdentifier)
        let target = Locale.Language(identifier: targetIdentifier)
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)

        guard status == .installed else {
            switch status {
            case .supported:
                throw MobileTranslationProviderError.invalidConfiguration
            case .unsupported:
                throw MobileTranslationProviderError.unsupportedEngine
            case .installed:
                break
            @unknown default:
                throw MobileTranslationProviderError.invalidConfiguration
            }
            throw MobileTranslationProviderError.invalidConfiguration
        }

        return try await executeInstalledTranslation(
            request,
            source: source,
            target: target
        )
        #else
        throw MobileTranslationProviderError.unsupportedEngine
        #endif
    }

    private func requiredSourceLanguage(from context: TranslationContext) throws -> String {
        let value = context.sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            throw MobileTranslationProviderError.invalidConfiguration
        }
        return value
    }

    private func requiredTargetLanguage(from context: TranslationContext) throws -> String {
        let value = context.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw MobileTranslationProviderError.invalidConfiguration
        }
        return value
    }
}

public struct IOSAppleTranslationMobileProvider<Executor: IOSAppleTranslationExecuting>: MobileTranslationProvider {
    public var engine: TranslationEngine
    public let executor: Executor

    public init(
        engine: TranslationEngine = .appleTranslationLowLatency,
        executor: Executor
    ) {
        self.engine = engine
        self.executor = executor
    }

    public func readiness(for context: TranslationContext) async -> TranslationReadiness {
        guard engine == .appleTranslationLowLatency || engine == .appleTranslationHighFidelity else {
            return TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsExecutionAdapter)
            ])
        }
        guard let sourceLanguage = context.sourceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceLanguage.isEmpty,
              !context.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return TranslationReadiness(issues: [
                TranslationReadinessIssue(kind: .needsRuntimeVerification)
            ])
        }
        return .ready
    }

    public func translate(_ request: MobileTranslationRequest) async throws -> MobileTranslationResult {
        let readiness = await readiness(for: request.context)
        guard readiness.isReady else {
            throw MobileTranslationProviderError.invalidConfiguration
        }

        let translations = try await executor.translate(IOSAppleTranslationBatchRequest(
            engine: engine,
            context: request.context,
            segments: request.segments
        ))

        return MobileTranslationResult(
            segments: request.segments.map { segment in
                MobileTranslationSegment(
                    id: segment.id,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    text: translations[segment.id] ?? segment.text
                )
            }
        )
    }
}

public extension IOSAppleTranslationMobileProvider where Executor == IOSSystemAppleTranslationExecutor {
    init(engine: TranslationEngine = .appleTranslationLowLatency) {
        self.init(engine: engine, executor: IOSSystemAppleTranslationExecutor())
    }
}

#if canImport(Translation)
@available(iOS 26.0, macOS 26.0, *)
private func executeInstalledTranslation(
    _ request: IOSAppleTranslationBatchRequest,
    source: Locale.Language,
    target: Locale.Language
) async throws -> [String: String] {
    let session: TranslationSession
    switch request.engine {
    case .appleTranslationHighFidelity:
        guard #available(iOS 26.4, macOS 26.4, *) else {
            throw MobileTranslationProviderError.unsupportedEngine
        }
        session = TranslationSession(
            installedSource: source,
            target: target,
            preferredStrategy: .highFidelity
        )
    case .appleTranslationLowLatency:
        if #available(iOS 26.4, macOS 26.4, *) {
            session = TranslationSession(
                installedSource: source,
                target: target,
                preferredStrategy: .lowLatency
            )
        } else {
            session = TranslationSession(installedSource: source, target: target)
        }
    case .anthropicCompatible,
         .openAICompatible,
         .appleFoundationOnDevice,
         .appleFoundationPCC,
         .appleFoundationCloudPro:
        throw MobileTranslationProviderError.unsupportedEngine
    }

    let requests = request.segments.map { segment in
        TranslationSession.Request(
            sourceText: segment.text,
            clientIdentifier: segment.id
        )
    }
    let responses = try await session.translations(from: requests)

    var translations: [String: String] = [:]
    for response in responses {
        guard let identifier = response.clientIdentifier else {
            continue
        }
        translations[identifier] = response.targetText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return translations
}
#endif
