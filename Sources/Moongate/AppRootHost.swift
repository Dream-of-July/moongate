import Foundation
import SwiftUI
#if canImport(MoongateCore)
import MoongateCore
#endif

/// App 菜单与资料库工作台之间的轻量命令桥。
///
/// 命令不依赖某个具体列或视图实例；新工作台、紧凑窗口和 legacy fallback 都可以按需监听。
enum AppWorkspaceCommand {
    static let newDownloadRequested = Notification.Name("com.moongate.workspace.newDownloadRequested")
    static let startAllRequested = Notification.Name("com.moongate.workspace.startAllRequested")
    static let searchRequested = Notification.Name("com.moongate.workspace.searchRequested")
}

/// 根级「新建下载」sheet。链接在这里先变成可编辑的待开始任务；默认设置只用于预填，
/// 绝不把画质、字幕和模型选项赶回设置页。
struct RootNewDownloadSheet: View {
    @ObservedObject var model: ViewModel
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var draft: DownloadOptionsDraft
    @State private var advancedOptionsExpanded = false
    @State private var isSubmitting = false
    @State private var submissionResult: String?
    @FocusState private var urlFieldFocused: Bool

    init(model: ViewModel) {
        self.model = model
        self._draft = State(initialValue: .defaults(from: model.settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(localizer.t(L.App.newDownloadCommand))
                .font(.headline)

            TextField(
                localizer.t(L.Download.linkPlaceholder),
                text: $urlText,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...5)
            .focused($urlFieldFocused)
            .accessibilityLabel(localizer.t(L.Main.urlInputAccessibility))

            Text(localizer.t(L.Download.multipleLinksHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(localizer.t(L.Download.defaultSummary, configurationSummary))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel(localizer.t(L.Download.defaultSummary, configurationSummary))

            Picker(localizer.t(L.Download.quality), selection: $draft.quality) {
                Text(localizer.t(L.Download.qualityBestAvailable)).tag("best")
                Text(localizer.t(L.Download.quality1080p)).tag("bv*[height<=1080]+ba/b[height<=1080]")
                Text(localizer.t(L.Download.quality720p)).tag("bv*[height<=720]+ba/b[height<=720]")
            }

            Picker(localizer.t(L.Download.subtitleResult), selection: $draft.subtitleOutcome) {
                ForEach(DownloadSubtitleOutcome.allCases) { outcome in
                    Text(localizer.t(outcome.localizationKey)).tag(outcome)
                }
            }

            Picker(localizer.t(L.Download.outputFormat), selection: outputFormatBinding) {
                Text(localizer.t(L.Download.outputOriginal)).tag(OutputFormat.original.rawValue)
                Text(localizer.t(L.Download.outputMP4H264)).tag(OutputFormat.mp4H264.rawValue)
                Text(localizer.t(L.Download.outputMP4H265)).tag(OutputFormat.mp4H265.rawValue)
                Text(localizer.t(L.Download.outputMKV)).tag(OutputFormat.mkv.rawValue)
            }

            if draft.showsTranslationOptions {
                Picker(localizer.t(L.Download.targetLanguage), selection: $draft.targetLanguage) {
                    Text(localizer.t(L.Download.languageChineseSimplified)).tag("zh-Hans")
                    Text(localizer.t(L.Download.languageChineseTraditional)).tag("zh-Hant")
                    Text(localizer.t(L.Download.languageEnglish)).tag("en")
                }

                if draft.subtitleOutcome == .embeddedTranslation {
                    Picker(localizer.t(L.Download.subtitleStyle), selection: subtitleStyleBinding) {
                        Text(localizer.t(L.Download.subtitleStyleBilingual)).tag(SubtitleStyle.bilingual.rawValue)
                        Text(localizer.t(L.Download.subtitleStyleTranslationOnly)).tag(SubtitleStyle.chineseOnly.rawValue)
                    }
                }

                DisclosureGroup(localizer.t(L.Download.advancedOptions), isExpanded: $advancedOptionsExpanded) {
                    Toggle(localizer.t(L.Download.customizeRecognition), isOn: $draft.usesCustomRecognition)

                    if draft.usesCustomRecognition {
                        Picker(localizer.t(L.Download.recognitionMethod), selection: $draft.recognitionChoice) {
                            ForEach(DownloadRecognitionChoice.allCases) { choice in
                                Text(localizer.t(choice.localizationKey)).tag(choice)
                            }
                        }

                        if draft.recognitionChoice == .local {
                            TranscriptionModelPicker(selection: transcriptionModelBinding)
                        }
                    }

                    TextField(localizer.t(L.Download.translationModelAdvanced), text: optionalTextBinding(\.translationModel))
                }
                .font(.callout)
            }

            Text(localizer.t(L.Download.deferredQueueHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            if isSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.batchStatusText ?? localizer.t(L.Download.resolvingLinks))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.batchStatusText ?? localizer.t(L.Download.resolvingLinks))
            }

            if let submissionResult {
                Text(submissionResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(submissionResult)
            }

            HStack(spacing: Spacing.md) {
                Spacer(minLength: 0)

                Button(localizer.t(L.Common.cancel)) {
                    if isSubmitting { model.cancelParse() }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if submissionResult != nil {
                    Button(localizer.t(L.Common.done)) { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(localizer.t(L.Download.addToDeferredQueue)) {
                        if model.enqueueDeferredDrafts(from: urlText, configuration: draft.queuedConfiguration()) {
                            isSubmitting = true
                        } else {
                            submissionResult = model.enqueueNotice ?? localizer.t(L.Download.noUsableLinks)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSubmitting || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 500)
        .interactiveDismissDisabled(isSubmitting)
        .onAppear { urlFieldFocused = true }
        .onChange(of: model.enqueueNotice) { _, notice in
            guard isSubmitting, let notice else { return }
            isSubmitting = false
            if (model.deferredBatchAddedCount ?? 0) > 0 {
                dismiss()
            } else {
                submissionResult = notice
            }
        }
        .onDisappear {
            if isSubmitting { model.cancelParse() }
        }
    }

    private var outputFormatBinding: Binding<String> {
        Binding(
            get: { draft.outputFormat.rawValue },
            set: { draft.outputFormat = OutputFormat(rawValue: $0) ?? .original }
        )
    }

    private var subtitleStyleBinding: Binding<String> {
        Binding(
            get: { draft.subtitleStyle.rawValue },
            set: { draft.subtitleStyle = SubtitleStyle(rawValue: $0) ?? .bilingual }
        )
    }

    private var transcriptionModelBinding: Binding<String> {
        Binding(
            get: { draft.localModelID ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.localModelID = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private var configurationSummary: String {
        let quality: String
        switch draft.quality {
        case "best": quality = localizer.t(L.Download.qualityBestAvailable)
        case "bv*[height<=1080]+ba/b[height<=1080]": quality = localizer.t(L.Download.quality1080p)
        case "bv*[height<=720]+ba/b[height<=720]": quality = localizer.t(L.Download.quality720p)
        default: quality = localizer.t(L.Download.qualityCustom)
        }
        let format = switch draft.outputFormat {
        case .original: localizer.t(L.Download.outputOriginal)
        case .mp4H264: localizer.t(L.Download.outputMP4H264)
        case .mp4H265: localizer.t(L.Download.outputMP4H265)
        case .mkv: localizer.t(L.Download.outputMKV)
        }
        let subtitles = localizer.t(draft.subtitleOutcome.localizationKey)
        return [quality, format, subtitles].joined(separator: " · ")
    }

    private func optionalTextBinding(
        _ keyPath: WritableKeyPath<DownloadOptionsDraft, String?>
    ) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
            }
        )
    }
}
