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

/// 根级「新建下载」sheet。它复用既有批量入队引擎，因此不会在新布局下绕开依赖检查、登录或默认设置。
struct RootNewDownloadSheet: View {
    @ObservedObject var model: ViewModel
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @FocusState private var urlFieldFocused: Bool

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

            VStack(alignment: .leading, spacing: 4) {
                Text("将使用当前默认设置")
                    .font(.caption.weight(.medium))
                Text(defaultProcessingSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            DisclosureGroup("高级设置") {
                Text("画质、字幕来源和模型可在“设置”中调整；这里不会创建无法追踪的草稿。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .font(.callout)

            HStack(spacing: Spacing.md) {
                Spacer(minLength: 0)

                Button(localizer.t(L.Common.cancel)) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(localizer.t(L.SplitLayout.addSheetConfirm)) {
                    model.addTasks(from: urlText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .onAppear { urlFieldFocused = true }
    }

    private var defaultProcessingSummary: String {
        let translationModel = model.settings.translationFollowsDefault
            ? model.settings.aiModel
            : model.settings.translationModel
        let subtitle = model.settings.lastSubtitleMode ?? ChineseSubtitleMode.off.rawValue
        let format = model.settings.lastOutputFormat?.rawValue ?? OutputFormat.original.rawValue
        let modelName = translationModel.isEmpty ? "未配置翻译模型" : translationModel
        return "格式：\(format) · 字幕：\(subtitle) · 模型：\(modelName)"
    }
}
