//
//  RuleRow.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import AppKit
import SwiftUI

private struct RulePreviewKey: Equatable {
    var kind: RuleKind
    var pattern: String
    var isEnabled: Bool
    var includeFiles: Bool

    init(rule: RegexRule) {
        kind = rule.kind
        pattern = rule.pattern
        isEnabled = rule.isEnabled
        includeFiles = rule.includeFiles
    }
}

struct RuleRow: View {
    @Binding var rule: RegexRule
    @Environment(AppStateStore.self) private var store
    var onDelete: () -> Void
    @State private var isExpanded = false
    @State private var isLoadingPreview = false
    @State private var previewResults: [RulePreviewResult] = []
    @State private var previewTask: Task<Void, Never>?
    @State private var previewKey: RulePreviewKey?
    @State private var hasRequestedPreview = false

    private var validationIssue: RuleValidationIssue? {
        RuleMatcher.validationIssue(for: rule)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
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
                        .lineLimit(1 ... 4)

                    if rule.kind == .regex {
                        RegexSuggestionBar(pattern: rule.pattern) { insertion in
                            rule.pattern += insertion
                        }
                    }
                }

                Text(rule.kind.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let validationIssue {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(validationIssue.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        if let suggestion = validationIssue.suggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }

                if rule.kind != .specific {
                    RulePreviewPanel(
                        isLoading: isLoadingPreview,
                        results: previewResults,
                        resultLimit: store.settings.previewResultLimit,
                        hasRequestedPreview: hasRequestedPreview,
                        isDisabled: !rule.isEnabled,
                        validationError: validationIssue?.message
                    ) {
                        refreshPreview(debounce: false)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()

                HStack(spacing: 4) {
                    TextField("Rule name", text: $rule.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)

                    if validationIssue != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .help("This rule has an error and will be skipped during scans.")
                    }
                }

                Picker("Mode", selection: $rule.kind) {
                    ForEach(RuleKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Toggle("Files", isOn: $rule.includeFiles)
                    .help("Allow this rule to match files as well as folders. Not applicable in 'specific' mode.")
                    .disabled(rule.kind == .specific)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete rule")
            }
            // to click on disclosure chevron without toggling on/off
            .padding(.leading, 10)
            .padding(.vertical, 4)
            .background(
                validationIssue != nil
                    ? Color.red.opacity(0.07).cornerRadius(6)
                    : nil
            )
        }
        .padding(.vertical, 8)
        .onChange(of: isExpanded) {
            if isExpanded {
                previewKey = RulePreviewKey(rule: rule)
            } else {
                previewTask?.cancel()
                isLoadingPreview = false
            }
        }
        .onChange(of: rule) {
            let nextKey = RulePreviewKey(rule: rule)
            guard nextKey != previewKey else { return }
            previewKey = nextKey
            if !isExpanded {
                isExpanded = true
            }
            refreshPreview(debounce: true)
        }
        .onChange(of: store.settings.scanRoots) {
            if isExpanded, hasRequestedPreview {
                refreshPreview(debounce: true)
            }
        }
        .onChange(of: store.settings.maxDepth) {
            if isExpanded, hasRequestedPreview {
                refreshPreview(debounce: true)
            }
        }
        .onDisappear {
            previewTask?.cancel()
        }
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

    private func refreshPreview(debounce: Bool) {
        previewTask?.cancel()
        hasRequestedPreview = true
        guard rule.isEnabled, validationIssue == nil else {
            previewResults = []
            isLoadingPreview = false
            return
        }

        let ruleSnapshot = rule
        isLoadingPreview = true
        previewTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
            }
            let results = await store.previewMatches(for: ruleSnapshot)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewResults = results
                isLoadingPreview = false
            }
        }
    }
}

private struct RegexSuggestionBar: View {
    let pattern: String
    let onInsert: (String) -> Void

    private var suggestions: [RegexSuggestionProvider.Suggestion] {
        RegexSuggestionProvider.suggestions(for: pattern)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(suggestions) { suggestion in
                    Button {
                        onInsert(suggestion.insertion)
                    } label: {
                        Text(suggestion.display)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(suggestion.description)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: suggestions.map(\.id))
    }
}

#Preview {
    RuleRow(rule: .constant(.init(name: "Damn", pattern: ""))) {}
        .previewModifiers()
}
