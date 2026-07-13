import SwiftUI
#if canImport(MoongateCore)
import MoongateCore
#endif

enum LocalRecognitionCapabilityPresentation: Equatable {
    case runtimeMissing
    case modelRequired(sizeBytes: Int64)
    case downloading(progress: Double?)
    case cancelling
    case failed
    case enabled
}

/// A task-scoped explanation of the local subtitle capability. It deliberately
/// exposes a useful outcome and recovery choices instead of internal component
/// names or installation diagnostics.
struct LocalRecognitionCapabilitySheet: View {
    let presentation: LocalRecognitionCapabilityPresentation
    let canDismiss: Bool
    let onRecheck: () -> Void
    let onInstall: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onUseAutomatic: () -> Void
    let onUseCloud: () -> Void
    let onContinueDownloadOnly: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content

            Divider()

            HStack {
                Spacer()
                Button(localizer.t(L.Common.close)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(!canDismiss)
            }
        }
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled(!canDismiss)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .runtimeMissing:
            capabilityHeader(
                title: localizer.t(L.Settings.localRecognitionRuntimeMissingTitle),
                detail: localizer.t(L.Settings.localRecognitionRuntimeMissingDetail),
                image: "captions.bubble"
            )

            Button(localizer.t(L.Settings.localRecognitionRecheck)) {
                onRecheck()
            }
            .buttonStyle(.bordered)

            fallbackActions

        case .modelRequired(let sizeBytes):
            capabilityHeader(
                title: localizer.t(L.Settings.localRecognitionModelRequiredTitle),
                detail: localizer.t(
                    L.Settings.localRecognitionModelRequiredDetail,
                    ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
                ),
                image: "arrow.down.circle"
            )

            Button(localizer.t(L.Settings.localRecognitionDownloadEnable)) {
                onInstall()
            }
            .buttonStyle(.borderedProminent)

            fallbackActions

        case .downloading(let progress):
            capabilityHeader(
                title: localizer.t(L.Settings.localRecognitionDownloadingTitle),
                detail: localizer.t(L.Settings.localRecognitionDownloadingDetail),
                image: "arrow.down.circle"
            )
            ProgressView(value: progress)
            Button(localizer.t(L.Settings.localRecognitionCancelDownload)) {
                onCancel()
            }
            .buttonStyle(.bordered)

        case .cancelling:
            capabilityHeader(
                title: localizer.t(L.Settings.localRecognitionCancellingTitle),
                detail: localizer.t(L.Settings.localRecognitionCancellingDetail),
                image: "xmark.circle"
            )
            ProgressView()

        case .failed:
            capabilityHeader(
                title: localizer.t(L.Settings.localRecognitionDownloadFailedTitle),
                detail: localizer.t(L.Settings.localRecognitionDownloadFailedDetail),
                image: "exclamationmark.triangle"
            )

            Button(localizer.t(L.Common.retry)) {
                onRetry()
            }
            .buttonStyle(.borderedProminent)

            fallbackActions

        case .enabled:
            capabilityHeader(
                title: localizer.t(L.Settings.localRecognitionEnabledTitle),
                detail: localizer.t(L.Settings.localRecognitionEnabledDetail),
                image: "checkmark.circle.fill"
            )
        }
    }

    private var fallbackActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(localizer.t(L.Settings.localRecognitionUseAutomatic)) {
                onUseAutomatic()
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(localizer.t(L.Settings.localRecognitionUseCloud)) {
                onUseCloud()
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(localizer.t(L.Settings.localRecognitionContinueVideoOnly)) {
                onContinueDownloadOnly()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }

    private func capabilityHeader(title: String, detail: String, image: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: image)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
