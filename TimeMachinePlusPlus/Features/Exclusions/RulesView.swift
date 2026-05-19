import AppKit
import SwiftUI

struct RulesView: View {
    @ObservedObject var store: AppStateStore
    var showsHeader: Bool = true

    var body: some View {
        PageView(title: "Rules", subtitle: "Exclude by pattern or add specific files and folders") {
            List {
                ForEach($store.rules) { $rule in
                    RuleRow(rule: $rule, store: store) {
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
                    pickSpecificPaths(store: store)
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
        .onChange(of: store.rules) { store.save() }
    }

    @MainActor
    private func pickSpecificPaths(store: AppStateStore) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        store.addSpecificPaths(panel.urls)
    }
}
