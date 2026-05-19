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

    private var validationError: String? {
        RuleMatcher.validationError(for: rule)
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
                }

                Text(rule.kind.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                RulePreviewPanel(
                    isLoading: isLoadingPreview,
                    results: previewResults,
                    resultLimit: store.settings.previewResultLimit,
                    hasRequestedPreview: hasRequestedPreview,
                    isDisabled: !rule.isEnabled,
                    validationError: validationError
                ) {
                    refreshPreview(debounce: false)
                }
            }
            .padding(.top, 8)
        } label: {
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

//                if rule.kind != .specific {
                Toggle("Files", isOn: $rule.includeFiles)
                    .help("Allow this rule to match files as well as folders. Not applicable in 'specific' mode.")
                    .disabled(rule.kind == .specific)
//                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete rule")
            }
            .padding(.leading, 6)
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
            guard isExpanded else { return }
            let nextKey = RulePreviewKey(rule: rule)
            guard nextKey != previewKey else { return }
            previewKey = nextKey
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
        guard rule.isEnabled, validationError == nil else {
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

 
