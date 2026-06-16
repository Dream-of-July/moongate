import Foundation
#if canImport(Photos)
import Photos
#endif

public enum IOSPhotoLibrarySaveResult: Sendable, Equatable {
    case saved
    case permissionDenied
    case failed
}

public protocol IOSPhotoLibraryExporting: Sendable {
    func saveVideo(at fileURL: URL) async -> IOSPhotoLibrarySaveResult
}

public struct IOSPhotoLibrarySaveHandler: Sendable {
    private let artifactStore: IOSArtifactStore
    private let exporter: any IOSPhotoLibraryExporting

    public init(
        artifactStore: IOSArtifactStore,
        exporter: any IOSPhotoLibraryExporting
    ) {
        self.artifactStore = artifactStore
        self.exporter = exporter
    }

    public func save(_ command: IOSLibraryActionCommand) async -> String {
        guard command.intent == .saveToPhotos,
              command.presentation == .photoLibraryExporter,
              let artifact = command.artifacts.first else {
            return command.systemMessage
        }

        let fileURL: URL
        do {
            fileURL = try artifactStore.fileURL(for: artifact).standardizedFileURL
        } catch IOSArtifactStoreError.unsafeStorageIdentifier {
            return "文件引用不安全，无法存到照片"
        } catch {
            return "无法存到照片"
        }

        switch await exporter.saveVideo(at: fileURL) {
        case .saved:
            return "已存到照片 \(artifact.displayName)"
        case .permissionDenied:
            return "没有照片写入权限，请在系统设置中允许访问照片。"
        case .failed:
            return "存到照片失败，请稍后重试。"
        }
    }
}

public struct IOSSystemPhotoLibraryExporter: IOSPhotoLibraryExporting {
    public init() {}

    public func saveVideo(at fileURL: URL) async -> IOSPhotoLibrarySaveResult {
        #if canImport(Photos)
        let status = await Self.requestAddOnlyAuthorization()
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: fileURL, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
        #else
        return .failed
        #endif
    }

    #if canImport(Photos)
    private static func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
    #endif
}
