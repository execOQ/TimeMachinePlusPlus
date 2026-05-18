import AppKit
import SwiftUI

struct RulesView: View {
    @ObservedObject var store: AppStateStore
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HeaderView(
                    title: "Rules",
                    subtitle: "Exclude by pattern (git-like, regex) or add specific files and folders."
                ) {
                    Button {
                        store.addRule()
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .disabled(!store.canEdit)

                    Button {
                        pickSpecificPaths(store: store)
                    } label: {
                        Label("Add Specific", systemImage: "folder.badge.plus")
                    }
                    .disabled(!store.canEdit)
                }
            }

            List {
                ForEach($store.rules) { $rule in
                    RuleRow(rule: $rule) {
                        store.deleteRule(rule)
                    }
                }
            }
            .listStyle(.inset)
            .disabled(!store.canEdit)
            .onChange(of: store.rules) { _, _ in
                store.save()
            }
        }
    }
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
    store.startScanNow()
}

private struct RuleRow: View {
    @Binding var rule: RegexRule
    var onDelete: () -> Void

    private var validationError: String? {
        RuleMatcher.validationError(for: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()

                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)

                Picker("Mode", selection: $rule.kind) {
                    ForEach(RuleKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                if rule.kind != .specific {
                    Toggle("Files", isOn: $rule.includeFiles)
                        .help("Allow this rule to match files as well as folders.")
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete rule")
            }

            if rule.kind == .specific {
                HStack(spacing: 8) {
                    TextField(rule.kind.placeholder, text: $rule.pattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        pickSpecificPath(into: $rule)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Browse for a file or folder")
                }
            } else {
                TextField(rule.kind.placeholder, text: $rule.pattern, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
            }

            Text(rule.kind.help)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }

    private func pickSpecificPath(into rule: Binding<RegexRule>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Select"
        if !rule.wrappedValue.pattern.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: rule.wrappedValue.pattern).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rule.wrappedValue.pattern = url.path
        if rule.wrappedValue.name == "New rule" || rule.wrappedValue.name.isEmpty {
            rule.wrappedValue.name = url.lastPathComponent
        }
    }
}
