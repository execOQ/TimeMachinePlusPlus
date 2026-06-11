import SwiftUI

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        @Bindable var store = store

        PageView(title: "Settings") {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsAppSection()
                    SettingsScanSection()
                    SettingsUpdatesSection()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 450, height: 500)
        .toolbar {
            Button("Close") {
                dismiss()
            }
            .help("Close Settings")
        }
        .disabled(!store.canEdit)
        .onChange(of: store.settings, onSettingsChanged)
        .onDisappear(perform: onDisappear)
        .onAppear(perform: onAppear)
    }
}

private extension SettingsView {
    func onAppear() {
        store.refreshHelperStatus()
        store.refreshLoginItemStatus()
    }

    func onDisappear() {
        autosaveTask?.cancel()
        store.save()
    }

    func onSettingsChanged() {
        if store.canEdit {
            scheduleAutosave()
        }
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            store.save()
        }
    }
}

#Preview {
    SettingsView()
        .previewModifiers(setSize: false)
}
