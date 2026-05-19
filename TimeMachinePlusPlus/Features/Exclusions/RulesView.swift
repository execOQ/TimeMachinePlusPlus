import AppKit
import SwiftUI

struct RulesView: View {
    @Environment(AppStateStore.self) private var store
    var showsHeader: Bool = true
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        @Bindable var store = store

        PageView(title: "Rules", subtitle: "Exclude by pattern or add specific files and folders") {
            List {
                ForEach($store.rules) { $rule in
                    RuleRow(rule: $rule) {
                        store.deleteRule(rule)
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            Menu {
                Button {
                    store.addRule()
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                Button {
                    pickSpecificPaths()
                } label: {
                    Label("Add Specific", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add a new exclusion rule, or add specific files and folders to exclude.")
            .disabled(!store.canEdit)
        }
        .disabled(!store.canEdit)
        .onChange(of: store.rules) { scheduleAutosave() }
        .onDisappear {
            autosaveTask?.cancel()
            store.save()
        }
    }

    @MainActor
    private func pickSpecificPaths() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        store.addSpecificPaths(panel.urls)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            store.save()
        }
    }
}
