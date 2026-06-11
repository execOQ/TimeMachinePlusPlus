import SwiftUI

struct RulesView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var showsHeader: Bool = true
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isTemplateSheetPresented = false
    @State private var isShowingAppManagedExclusions = false

    var body: some View {
        @Bindable var store = store

        PageView(title: "Rules", subtitle: "Exclude by pattern or add exact paths") {
            VStack(alignment: .leading, spacing: 12) {
                rulesList(rules: $store.rules)
            }
        }
        .toolbar {
            RulesToolbar(
                isTemplateSheetPresented: $isTemplateSheetPresented,
                isShowingAppManagedExclusions: $isShowingAppManagedExclusions
            )
        }
        .sheet(isPresented: $isTemplateSheetPresented) {
            RuleTemplatesSheet()
        }
        .sheet(isPresented: $isShowingAppManagedExclusions) {
            AppManagedExclusionsView()
        }
        .onChange(of: store.rules, scheduleAutosave)
        .onDisappear(perform: onDisappear)
    }

    // MARK: - View Components

    @ContentBuilder
    private func rulesList(rules: Binding<[RegexRule]>) -> some View {
        if !rules.wrappedValue.isEmpty {
            List {
                ForEach(rules) { $rule in
                    RuleRow(rule: $rule) {
                        self.store.deleteRule(rule, undoManager: undoManager)
                    }
                }
            }
            .listStyle(.inset)
            .disabled(!store.canEdit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No rules added", systemImage: "plus", description: Text("Click plus in toolbar to create a new rule"))
        }
    }
}

private extension RulesView {
    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            store.saveInBackground()
        }
    }

    func onDisappear() {
        autosaveTask?.cancel()
        store.save()
    }
}
