import SwiftUI
#if canImport(MoongateCore)
import MoongateCore
#endif

struct TranscriptionModelPicker: View {
    let title: String
    let selection: Binding<String>

    init(_ title: String = "转录模型", selection: Binding<String>) {
        self.title = title
        self.selection = selection
    }

    var body: some View {
        Picker(title, selection: selection) {
            Text("使用默认模型").tag("")
            ForEach(ASRModelManifest.recommendedWhisperCpp.models, id: \.id) { model in
                Text(model.displayName).tag(model.id)
            }
            if isImportedSelection {
                Divider()
                Text("当前自定义模型：\(selection.wrappedValue)")
                    .tag(selection.wrappedValue)
            }
        }
        .pickerStyle(.menu)
        .accessibilityHint("未准备的模型会让任务保持待开始，并提示你在准备中心完成安装。")
    }

    private var isImportedSelection: Bool {
        let value = selection.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return !ASRModelManifest.recommendedWhisperCpp.models.contains { $0.id == value }
    }
}
