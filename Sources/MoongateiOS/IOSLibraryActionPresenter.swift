import Foundation
import MoongateMobileCore

public enum IOSLibraryActionPresenterError: Error, Equatable {
    case unavailable
    case noSystemPresentationRequired
    case missingArtifacts
    case unsupportedPresentation
    case unsafeArtifactReference
}

public enum IOSLibraryActionIntent: String, Sendable, Equatable {
    case open
    case share
    case exportToFiles
    case saveToPhotos
    case locateFile
}

public struct IOSLibraryActionCommand: Sendable, Equatable, Identifiable {
    public var id: String
    public var intent: IOSLibraryActionIntent
    public var presentation: MobileLibraryActionPresentation
    public var itemID: String
    public var itemTitle: String
    public var artifacts: [MobileTaskArtifact]
    public var systemMessage: String

    public init(
        id: String,
        intent: IOSLibraryActionIntent,
        presentation: MobileLibraryActionPresentation,
        itemID: String,
        itemTitle: String,
        artifacts: [MobileTaskArtifact],
        systemMessage: String
    ) {
        self.id = id
        self.intent = intent
        self.presentation = presentation
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.artifacts = artifacts
        self.systemMessage = systemMessage
    }
}

public struct IOSLibraryActionPresenter: Sendable {
    public init() {}

    public func command(for outcome: MobileLibraryActionOutcome) throws -> IOSLibraryActionCommand {
        guard outcome.status != .unavailable else {
            throw IOSLibraryActionPresenterError.unavailable
        }
        guard outcome.requiresSystemUI || outcome.status == .requiresSystemPresentation else {
            throw IOSLibraryActionPresenterError.noSystemPresentationRequired
        }

        let intent = try commandIntent(for: outcome)
        if intent != .locateFile {
            guard !outcome.artifacts.isEmpty else {
                throw IOSLibraryActionPresenterError.missingArtifacts
            }
        }
        guard outcome.artifacts.allSatisfy({ Self.isSafeArtifactReference($0.storageIdentifier) }) else {
            throw IOSLibraryActionPresenterError.unsafeArtifactReference
        }

        return IOSLibraryActionCommand(
            id: outcome.id,
            intent: intent,
            presentation: outcome.presentation,
            itemID: outcome.itemID,
            itemTitle: outcome.itemTitle,
            artifacts: outcome.artifacts,
            systemMessage: outcome.statusMessage
        )
    }

    private func commandIntent(for outcome: MobileLibraryActionOutcome) throws -> IOSLibraryActionIntent {
        switch (outcome.presentation, outcome.action) {
        case (.inAppOpen, .open):
            return .open
        case (.shareSheet, .share):
            return .share
        case (.fileExporter, .saveToFiles):
            return .exportToFiles
        case (.photoLibraryExporter, .saveToPhotos):
            return .saveToPhotos
        case (.documentPicker, .locateFile):
            return .locateFile
        case (.confirmationOnly, _), (.unavailable, _):
            throw IOSLibraryActionPresenterError.noSystemPresentationRequired
        default:
            throw IOSLibraryActionPresenterError.unsupportedPresentation
        }
    }

    private static func isSafeArtifactReference(_ storageIdentifier: String) -> Bool {
        let normalized = storageIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let lowercased = normalized.lowercased()
        if lowercased.hasPrefix("source:") ||
            lowercased.hasPrefix("http://") ||
            lowercased.hasPrefix("https://") {
            return false
        }
        let unsafeMarkers = [
            "access_token",
            "authorization",
            "bearer ",
            "cookie",
            "x-amz-signature",
            "secret_token"
        ]
        return !unsafeMarkers.contains { lowercased.contains($0) }
    }
}
