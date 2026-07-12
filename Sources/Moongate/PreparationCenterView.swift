import SwiftUI
#if canImport(MoongateCore)
import MoongateCore
#endif

/// A shared, read-first surface for setup and Settings. It renders the real
/// preparation snapshot and delegates every mutating action to the caller's
/// existing installer, runtime-adoption, or system-settings flow.
struct PreparationCenterView: View {
    @ObservedObject var model: PreparationCenterModel

    let onOpenDependencySetup: () -> Void
    let onAdoptRuntime: () -> Void
    let onOpenSystemSettings: () -> Void
    let onManageComponent: (ComponentPreparationItem, ComponentPreparationOperation) -> Void

    init(
        model: PreparationCenterModel,
        onOpenDependencySetup: @escaping () -> Void,
        onAdoptRuntime: @escaping () -> Void,
        onOpenSystemSettings: @escaping () -> Void,
        onManageComponent: @escaping (ComponentPreparationItem, ComponentPreparationOperation) -> Void
    ) {
        self.model = model
        self.onOpenDependencySetup = onOpenDependencySetup
        self.onAdoptRuntime = onAdoptRuntime
        self.onOpenSystemSettings = onOpenSystemSettings
        self.onManageComponent = onManageComponent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let message = model.refreshState.message {
                    refreshMessage(message)
                }

                if let snapshot = model.snapshot {
                    if snapshot.items.isEmpty {
                        unavailableState
                    } else {
                        componentSections
                    }
                } else if model.isRefreshing {
                    loadingState
                } else {
                    unavailableState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .task {
            model.refreshIfNeeded()
        }
        .accessibilityIdentifier("preparation-center")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("准备中心")
                    .font(.title2.weight(.semibold))
                Text("检查下载、转录和系统翻译所需的组件。不会在此自动下载或更改你的设置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if model.isRefreshing {
                Button("取消检查") {
                    model.cancelRefresh()
                }
                .buttonStyle(.bordered)
                .disabled({
                    if case .cancelling = model.refreshState { return true }
                    return false
                }())
            } else {
                Button {
                    model.clearRefreshError()
                    model.refresh()
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.bottom, 18)
    }

    private func refreshMessage(_ message: String) -> some View {
        HStack(spacing: 8) {
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else if case .failed = model.refreshState {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取已安装组件和模型校验结果…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在读取组件状态")
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("尚未检查组件", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("检查不会安装、删除或改写任何组件。")
        } actions: {
            Button("开始检查") {
                model.clearRefreshError()
                model.refresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var componentSections: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(PreparationCenterSection.allCases) { section in
                let items = items(in: section)
                if !items.isEmpty {
                    componentSection(section, items: items)
                }
            }
        }
    }

    private func componentSection(
        _ section: PreparationCenterSection,
        items: [ComponentPreparationItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.headline)
                Text(section.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PreparationCenterComponentRow(
                    item: item,
                    onAction: { operation in
                        perform(operation, for: item)
                    }
                )
                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
    }

    private func items(in section: PreparationCenterSection) -> [ComponentPreparationItem] {
        model.items.filter { section.kinds.contains($0.kind) }
    }

    private func perform(_ operation: ComponentPreparationOperation, for item: ComponentPreparationItem) {
        switch operation {
        case .refresh:
            model.refresh()
        case .openExistingDependencySetup:
            onOpenDependencySetup()
        case .installRuntime:
            // The current app has no synthetic runtime installer. The caller
            // opens its existing adoption flow, which may find a local runtime.
            onAdoptRuntime()
        case .openSystemSettings:
            onOpenSystemSettings()
        case .installManagedModel, .removeManagedRuntime, .removeManagedModel:
            onManageComponent(item, operation)
        }
    }
}

private enum PreparationCenterSection: String, CaseIterable, Identifiable {
    case downloadTools
    case localRuntime
    case localModels
    case systemLanguage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloadTools: "下载工具"
        case .localRuntime: "本地转录运行时"
        case .localModels: "Whisper 与 VAD 模型"
        case .systemLanguage: "系统语言包"
        }
    }

    var detail: String {
        switch self {
        case .downloadTools: "视频下载与媒体处理使用的现有工具链。"
        case .localRuntime: "只显示已验证或可由现有流程接管的运行时。"
        case .localModels: "模型单独管理；不会因检查状态而自动下载。"
        case .systemLanguage: "由 macOS 管理的系统翻译资源。"
        }
    }

    var kinds: [ComponentKind] {
        switch self {
        case .downloadTools: [.downloadToolchain]
        case .localRuntime: [.asrRuntime]
        case .localModels: [.whisperModel, .voiceActivityDetector]
        case .systemLanguage: [.appleLanguagePack]
        }
    }
}

private struct PreparationCenterComponentRow: View {
    let item: ComponentPreparationItem
    let onAction: (ComponentPreparationOperation) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 26)
                .padding(.top, 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayName)
                        .font(.body.weight(.medium))
                    Text(statusTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                }

                Text("来源：\(sourceText) · \(item.sourceDetail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let version = item.version {
                    Text("版本：\(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("状态详情：\(detailText)")
                }

                let visibleOperations = item.allowedOperations.filter { $0 != .refresh }
                Text("可用操作：\(allowedActionText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !visibleOperations.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(visibleOperations, id: \.self) { operation in
                            Button(actionTitle(for: operation)) {
                                onAction(operation)
                            }
                            .buttonStyle(operation.isDestructive ? .bordered : .bordered)
                            .tint(operation.isDestructive ? .red : nil)
                            .accessibilityLabel("\(item.displayName)：\(actionTitle(for: operation))")
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 11)
    }

    private var statusSymbol: String {
        switch item.readiness.status {
        case .ready: "checkmark.circle.fill"
        case .missing: "arrow.down.circle"
        case .unavailable: "exclamationmark.triangle.fill"
        case .corrupted: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var statusTitle: String {
        switch item.readiness.status {
        case .ready: "可用"
        case .missing: "未安装"
        case .unavailable: "不可用"
        case .corrupted: "需要修复"
        case .unknown: "待检查"
        }
    }

    private var statusColor: Color {
        switch item.readiness.status {
        case .ready: .green
        case .missing: .orange
        case .unavailable: .orange
        case .corrupted: .red
        case .unknown: .secondary
        }
    }

    private var detailColor: Color {
        switch item.readiness.status {
        case .ready, .unknown: .secondary
        case .missing, .unavailable: .orange
        case .corrupted: .red
        }
    }

    private var sourceText: String {
        switch item.source {
        case .existingDependencySetup: "现有依赖配置"
        case .projectGitHubRelease: "项目受控来源"
        case .existingASRModelDownloader: "模型管理器"
        case .appleSystem: "macOS"
        }
    }

    private var sizeText: String {
        let declared = item.declaredSizeBytes.map(Self.byteCount)
        let installed = item.actualDiskUsageBytes.map(Self.byteCount)
        return switch (declared, installed) {
        case let (.some(declared), .some(installed)):
            "体积：安装包 \(declared)；本地占用 \(installed)"
        case let (.some(declared), .none):
            "体积：安装包 \(declared)"
        case let (.none, .some(installed)):
            "体积：本地占用 \(installed)"
        case (.none, .none):
            "体积：未提供"
        }
    }

    private var detailText: String? {
        item.failureReason ?? item.readiness.detail
    }

    private var allowedActionText: String {
        item.allowedOperations.map(actionTitle(for:)).joined(separator: "、")
    }

    private func actionTitle(for operation: ComponentPreparationOperation) -> String {
        switch operation {
        case .refresh: "重新检查"
        case .installRuntime: "查找本机运行时…"
        // Model install/remove remains a real, existing Settings flow until
        // the item-specific coordinator owns its cancellation and alert UI.
        // Name the transition honestly rather than promising an in-place
        // download or deletion that this view does not perform.
        case .installManagedModel, .removeManagedModel: "打开模型管理…"
        case .removeManagedRuntime: ""
        case .openExistingDependencySetup: "管理下载工具…"
        case .openSystemSettings: "打开系统设置…"
        }
    }

    private static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension ComponentPreparationOperation {
    var isDestructive: Bool {
        switch self {
        case .removeManagedRuntime, .removeManagedModel:
            true
        case .refresh, .installRuntime, .installManagedModel, .openExistingDependencySetup, .openSystemSettings:
            false
        }
    }
}
