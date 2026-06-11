import SwiftUI

struct RulesToolbar: ToolbarContent {
    @Environment(AppStateStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @Binding var isTemplateSheetPresented: Bool
    @Binding var isShowingAppManagedExclusions: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            appManagedExclusionsButton()
            addMenu()
        }

        ToolbarItemGroup {
            startOrCancelButton()
        }
    }

    // MARK: - Toolbar Items

    private func appManagedExclusionsButton() -> some View {
        Button {
            isShowingAppManagedExclusions = true
        } label: {
            Label("App-Managed", systemImage: "document.badge.clock.fill")
        }
        .help("Show exclusions already applied by TimeMachine++.")
    }

    private func addMenu() -> some View {
        Menu {
            Button {
                store.addRule(undoManager: undoManager)
            } label: {
                Label("Add Rule", systemImage: "plus")
            }

            Button {
                pickPaths()
            } label: {
                Label("Add Path", systemImage: "folder.badge.plus")
            }

            Divider()

            Button {
                isTemplateSheetPresented = true
            } label: {
                Label("Add from Templates", systemImage: "square.grid.2x2")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .help("Add a new exclusion rule, or add exact paths to exclude.")
        .disabled(!store.canEdit)
    }

    @ViewBuilder
    private func startOrCancelButton() -> some View {
        if store.isWorking, store.canCancelCurrentOperation {
            Button("Cancel") {
                store.cancelOperation()
            }
            .help("Cancel the current exclusion operation.")
        } else {
            Button {
                store.startConfiguredStartAction()
            } label: {
                Label(store.startActionTitle, systemImage: "play")
            }
            .help(store.startActionHelp)
            .disabled(!store.canEdit)
        }
    }
}

private extension RulesToolbar {
    @MainActor
    func pickPaths() {
        let urls = PathPicker.pickPaths(canChooseFiles: true, canChooseDirectories: true)
        guard !urls.isEmpty else { return }
        store.addPathRules(urls, undoManager: undoManager)
    }
}
