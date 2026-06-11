import SwiftUI

struct RuleCollapsedLabel: View {
    @Binding var rule: RegexRule
    var validationIssue: RuleValidationIssue?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ruleStatusControl()

            TextField("Rule name", text: $rule.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)

            Picker("", selection: $rule.kind) {
                ForEach(RuleKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 100)

            Toggle("Files", isOn: $rule.includeFiles)
                .help("Allow this rule to match files as well as folders. Not applicable in Path mode.")
                .disabled(rule.kind == .path)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete rule")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(validationBackground)
    }

    // MARK: - View Components

    @ViewBuilder
    private func ruleStatusControl() -> some View {
        if validationIssue != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .help("This rule has an error and will be skipped during scans.")
        } else {
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
        }
    }

    private var validationBackground: some View {
        Group {
            if validationIssue != nil {
                Color.red.opacity(0.07)
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
    }
}
