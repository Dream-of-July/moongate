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
    static let searchRequested = Notification.Name("com.moongate.workspace.searchRequested")
    static let inspectorToggleRequested = Notification.Name("com.moongate.workspace.inspectorToggleRequested")
}

/// 根级「新建下载」sheet。链接在这里先变成可编辑的待开始任务；默认设置只用于预填，
/// 绝不把画质、字幕和模型选项赶回设置页。
struct RootNewDownloadSheet: View {
    @ObservedObject var model: ViewModel
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var configuration: QueuedProcessingConfiguration
    @State private var processingOptionsExpanded = true
    @FocusState private var urlFieldFocused: Bool

    init(model: ViewModel) {
        self.model = model
        self._configuration = State(initialValue: .defaults(from: model.settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(localizer.t(L.App.newDownloadCommand))
                .font(.headline)

            TextField(
                localizer.t(L.SplitLayout.addSheetPlaceholder),
                text: $urlText,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...5)
            .focused($urlFieldFocused)
            .accessibilityLabel(localizer.t(L.Main.urlInputAccessibility))

            Text(localizer.t(L.SplitLayout.addSheetHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("处理选项", isExpanded: $processingOptionsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("画质", selection: $configuration.quality) {
                        Text("最佳可用").tag("best")
                        Text("1080p").tag("bv*[height<=1080]+ba/b[height<=1080]")
                        Text("720p").tag("bv*[height<=720]+ba/b[height<=720]")
                    }

                    Picker("输出格式", selection: outputFormatBinding) {
                        Text("保持源格式").tag(OutputFormat.original.rawValue)
                        Text("MP4 · H.264").tag(OutputFormat.mp4H264.rawValue)
                        Text("MP4 · H.265").tag(OutputFormat.mp4H265.rawValue)
                        Text("MKV").tag(OutputFormat.mkv.rawValue)
                    }

                    Picker("字幕处理", selection: subtitleModeBinding) {
                        Text("不处理字幕").tag(ChineseSubtitleMode.off.rawValue)
                        Text("生成译文 SRT").tag(ChineseSubtitleMode.srtOnly.rawValue)
                        Text("压制译文字幕").tag(ChineseSubtitleMode.burnIn.rawValue)
                        Text("压制原字幕").tag(ChineseSubtitleMode.burnOriginal.rawValue)
                    }

                    Picker("字幕来源", selection: subtitleSourcePolicyBinding) {
                        Text("自动选择最佳来源").tag(SubtitleSourcePolicy.autoBest.rawValue)
                        Text("优先平台字幕").tag(SubtitleSourcePolicy.preferPlatform.rawValue)
                        Text("仅平台字幕").tag(SubtitleSourcePolicy.forcePlatform.rawValue)
                        Text("本地识别（Whisper）").tag(SubtitleSourcePolicy.forceLocalASR.rawValue)
                        Text("云端识别").tag(SubtitleSourcePolicy.cloudASR.rawValue)
                    }

                    if configuration.subtitleMode != .off {
                        Picker("目标语言", selection: $configuration.targetLanguage) {
                            Text("简体中文").tag("zh-Hans")
                            Text("繁體中文").tag("zh-Hant")
                            Text("English").tag("en")
                        }

                        Picker("字幕样式", selection: subtitleStyleBinding) {
                            Text("双语").tag(SubtitleStyle.bilingual.rawValue)
                            Text("仅译文").tag(SubtitleStyle.chineseOnly.rawValue)
                        }

                        TextField("转录模型（可选）", text: optionalTextBinding(\.transcriptionModel))
                        TextField("翻译模型（可选）", text: optionalTextBinding(\.translationModel))
                    }
                }
                .padding(.top, 8)
            }
            .font(.callout)

            Text("确认后会加入待开始队列。你可以在资料库中逐项修改，再开始处理。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.md) {
                Spacer(minLength: 0)

                Button(localizer.t(L.Common.cancel)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("加入待开始队列") {
                    model.enqueueDeferredDrafts(from: urlText, configuration: configuration)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 500)
        .onAppear { urlFieldFocused = true }
    }

    private var outputFormatBinding: Binding<String> {
        Binding(
            get: { configuration.outputFormat.rawValue },
            set: { configuration.outputFormat = OutputFormat(rawValue: $0) ?? .original }
        )
    }

    private var subtitleModeBinding: Binding<String> {
        Binding(
            get: { configuration.subtitleMode.rawValue },
            set: { configuration.subtitleMode = ChineseSubtitleMode(rawValue: $0) ?? .off }
        )
    }

    private var subtitleSourcePolicyBinding: Binding<String> {
        Binding(
            get: { configuration.subtitleSourcePolicy.rawValue },
            set: { configuration.subtitleSourcePolicy = SubtitleSourcePolicy(rawValue: $0) ?? .autoBest }
        )
    }

    private var subtitleStyleBinding: Binding<String> {
        Binding(
            get: { configuration.subtitleStyle.rawValue },
            set: { configuration.subtitleStyle = SubtitleStyle(rawValue: $0) ?? .bilingual }
        )
    }

    private func optionalTextBinding(
        _ keyPath: WritableKeyPath<QueuedProcessingConfiguration, String?>
    ) -> Binding<String> {
        Binding(
            get: { configuration[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                configuration[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
            }
        )
    }
}
