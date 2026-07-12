import SwiftUI
#if canImport(MoongateCore)
import MoongateCore
#endif

struct TranscriptionModelPicker: View {
    let title: String
    let selection: Binding<String>
    @EnvironmentObject private var localizer: Localizer

    init(_ title: String? = nil, selection: Binding<String>) {
        self.title = title ?? L.Download.transcriptionModel
        self.selection = selection
    }

    var body: some View {
        Picker(localizer.t(title), selection: selection) {
            Text(localizer.t(L.Download.useDefaultTranscriptionModel)).tag("")
            ForEach(ASRModelManifest.recommendedWhisperCpp.models, id: \.id) { model in
                Text(model.displayName).tag(model.id)
            }
            if isImportedSelection {
                Divider()
                Text(localizer.t(L.Download.customTranscriptionModel, selection.wrappedValue))
                    .tag(selection.wrappedValue)
            }
        }
        .pickerStyle(.menu)
        .accessibilityHint(localizer.t(L.Download.transcriptionModelReadinessHint))
    }

    private var isImportedSelection: Bool {
        let value = selection.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return !ASRModelManifest.recommendedWhisperCpp.models.contains { $0.id == value }
    }
}
