import SwiftUI

struct RulesView: View {
    @ObservedObject var store: AppStateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                title: "Smart Rules",
                subtitle: "Use friendly folder names, git-like patterns, or raw regex for precise exclusions."
            ) {
                Button {
                    store.addRule()
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .disabled(!store.canEdit)
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

                Toggle("Files", isOn: $rule.includeFiles)
                    .disabled(rule.kind == .folderName)
                    .help("Allow this rule to match files as well as folders.")

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete rule")
            }

            TextField(rule.kind.placeholder, text: $rule.pattern, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...4)

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
}
