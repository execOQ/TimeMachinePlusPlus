//
//  RuleRow.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import SwiftUI

struct RuleRow: View {
    @Binding var rule: RegexRule
    @Environment(AppStateStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    var onDelete: () -> Void
    @State private var isExpanded = false
    @State private var isAIHelperPresented = false
    @State private var aiGenerationState = AIRegexGenerationState()
    @State private var previewController = RulePreviewController()

    private var validationIssue: RuleValidationIssue? {
        RuleMatcher.validationIssue(for: rule)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            expandedContent()
        } label: {
            RuleCollapsedLabel(
                rule: $rule,
                validationIssue: validationIssue,
                onDelete: onDelete
            )
        }
        .padding(.vertical, 8)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .onChange(of: isExpanded, onExpansionChanged)
        .onChange(of: rule, onRuleChanged)
        .onChange(of: store.settings.scanRoots, onPreviewSettingsChanged)
        .onChange(of: store.settings.maxDepth, onPreviewSettingsChanged)
        .onDisappear(perform: onDisappear)
    }

    // MARK: - View Components

    private func expandedContent() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RulePatternEditor(
                rule: $rule,
                isAIHelperPresented: $isAIHelperPresented,
                aiGenerationState: aiGenerationState,
                onInsertRegexSuggestion: insertRegexSuggestion,
                onUseGeneratedPattern: applyGeneratedPattern,
                onPickPath: pickPath
            )

            Text(rule.kind.help)
                .font(.caption)
                .foregroundStyle(.secondary)

            validationIssueView()

            if rule.kind != .path {
                RulePreviewPanel(
                    isLoading: previewController.isLoading,
                    results: previewController.results,
                    resultLimit: store.settings.previewResultLimit,
                    hasRequestedPreview: previewController.hasRequestedPreview,
                    isDisabled: !rule.isEnabled,
                    validationError: validationIssue?.message
                ) {
                    refreshPreview(debounce: false)
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func validationIssueView() -> some View {
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
    }

}

private extension RuleRow {
    func onExpansionChanged() {
        if isExpanded {
            previewController.expand(with: rule)
        } else {
            previewController.collapse()
        }
    }

    func onRuleChanged() {
        guard previewController.registerRuleChange(rule) else { return }
        if !isExpanded {
            isExpanded = true
        }
        refreshPreview(debounce: true)
    }

    func onPreviewSettingsChanged() {
        if isExpanded, previewController.hasRequestedPreview {
            refreshPreview(debounce: true)
        }
    }

    func onDisappear() {
        previewController.cancel()
    }

    func insertRegexSuggestion(_ insertion: String) {
        rule.pattern += insertion
    }

    func applyGeneratedPattern(_ generated: String) {
        let previousPattern = rule.pattern
        let ruleID = rule.id
        undoManager?.registerUndo(withTarget: store) { store in
            if let idx = store.rules.firstIndex(where: { $0.id == ruleID }) {
                undoManager?.registerUndo(withTarget: store) { store in
                    if let idx = store.rules.firstIndex(where: { $0.id == ruleID }) {
                        store.rules[idx].pattern = generated
                    }
                }
                undoManager?.setActionName("Apply AI Pattern")
                store.rules[idx].pattern = previousPattern
            }
        }
        undoManager?.setActionName("Apply AI Pattern")
        rule.pattern = generated
        isAIHelperPresented = false
    }

    func pickPath() {
        guard let url = PathPicker.pickFileOrFolder(initialPath: rule.pattern) else { return }
        rule.pattern = url.path
        if rule.name == "New rule" || rule.name.isEmpty {
            rule.name = url.lastPathComponent
        }
    }

    func refreshPreview(debounce: Bool) {
        previewController.refresh(
            debounce: debounce,
            rule: rule,
            validationIssue: validationIssue,
            store: store
        )
    }
}

#Preview {
    RuleRow(rule: .constant(.init(name: "Damn", pattern: ""))) {}
        .previewModifiers()
}
