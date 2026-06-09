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
    @Environment(\.undoManager) private var undoManager
    var onDelete: () -> Void
    @State private var isExpanded = false
    @State private var isAIHelperPresented = false
    @State private var aiGenerationState = AIRegexGenerationState()
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
                HStack(spacing: 8) {
                    TextField(rule.kind.placeholder, text: $rule.pattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    if rule.kind == .path {
                        Button {
                            pickPath(into: $rule)
                        } label: {
                            Image(systemName: "folder")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.bordered)
                        .help("Browse for a file or folder")
                    } else if rule.kind == .regex, AppleIntelligenceRegexHelper.isAvailable {
                        Button {
                            isAIHelperPresented = true
                        } label: {
                            Image(systemName: "sparkles")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.bordered)
                        .help("Generate a regex with Apple Intelligence")
                        .popover(isPresented: $isAIHelperPresented, arrowEdge: .bottom) {
                            RegexIntelligencePopover(
                                pattern: rule.pattern,
                                request: $rule.lastAIRequest,
                                generatedPattern: $rule.lastAIGeneratedPattern,
                                generatedForRequest: $rule.lastAIGeneratedForRequest,
                                generationState: aiGenerationState,
                                onUse: { generated in
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
                            )
                        }
                    }
                }

                if rule.kind == .regex {
                    RegexSuggestionBar(
                        rule: $rule,
                        onInsert: { insertion in
                            rule.pattern += insertion
                        }
                    )
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

                if rule.kind != .path {
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
                if validationIssue != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .help("This rule has an error and will be skipped during scans.")
                } else {
                    Toggle("", isOn: $rule.isEnabled)
                        .labelsHidden()
                }

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
            // to click on disclosure chevron without toggling on/off
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                validationIssue != nil
                    ? Color.red.opacity(0.07).cornerRadius(6)
                    : nil
            )
        }
        .padding(.vertical, 8)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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

    private func pickPath(into rule: Binding<RegexRule>) {
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
    @Binding var rule: RegexRule
    let onInsert: (String) -> Void

    private var suggestions: [RegexSuggestionProvider.Suggestion] {
        RegexSuggestionProvider.suggestions(for: rule.pattern)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(suggestions.prefix(10).enumerated()), id: \.element.id) { index, suggestion in
                    let keyChar: Character = index < 9 ? Character("\(index + 1)") : "0"
                    Button {
                        onInsert(suggestion.insertion)
                    } label: {
                        HStack(spacing: 6) {
                            Text(suggestion.display)
                                .font(.system(.caption, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(alignment: .trailing) {
                            Text(index < 9 ? "\(index + 1)" : "0")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .offset(x: 5)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("⌘\(index < 9 ? "\(index + 1)" : "0")  |  \(suggestion.description)")
                    .keyboardShortcut(KeyEquivalent(keyChar), modifiers: .command)
                }

                ForEach(suggestions.dropFirst(10)) { suggestion in
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
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.15), value: suggestions.map(\.id))
    }
}

@MainActor
@Observable
private final class AIRegexGenerationState {
    var isGenerating = false
    var errorMessage: String?
    private var task: Task<Void, Never>?

    func generate(
        request: String,
        currentPattern: String,
        onSuccess: @escaping (String) -> Void
    ) {
        task?.cancel()
        errorMessage = nil
        isGenerating = true

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await AppleIntelligenceRegexHelper.generateRegex(for: request, currentPattern: currentPattern)
                guard !Task.isCancelled else { return }
                onSuccess(result)
                self.isGenerating = false
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }
}

private struct RegexIntelligencePopover: View {
    let pattern: String
    @Binding var request: String
    @Binding var generatedPattern: String
    @Binding var generatedForRequest: String
    var generationState: AIRegexGenerationState
    let onUse: (String) -> Void
    @Environment(AppStateStore.self) private var store

    private var trimmedRequest: String {
        request.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isRequestLongEnough: Bool { trimmedRequest.count >= 8 }
    private var isAlreadyGenerated: Bool {
        !generationState.isGenerating &&
        !generatedPattern.isEmpty &&
        !generatedForRequest.isEmpty &&
        trimmedRequest == generatedForRequest
    }

    private func primaryAction() {
        if isAlreadyGenerated {
            onUse(generatedPattern)
        } else if isRequestLongEnough && !generationState.isGenerating {
            generatePattern()
        }
    }

    private func generatePattern() {
        let patternBinding = _generatedPattern
        let forRequestBinding = _generatedForRequest
        let requestText = trimmedRequest
        generationState.generate(request: requestText, currentPattern: pattern) { result in
            patternBinding.wrappedValue = result
            forRequestBinding.wrappedValue = requestText
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Regex Helper")
                    .font(.headline)
                Spacer()
            }

            TextField("e.g. All .log files in any folder", text: $request, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)
                .disabled(generationState.isGenerating)
                .onSubmit { primaryAction() }

            if !trimmedRequest.isEmpty && !isRequestLongEnough {
                Text("Add more detail to get a useful pattern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !generatedPattern.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Generated")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(generatedPattern)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if let errorMessage = generationState.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if generationState.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Generate") {
                    generatePattern()
                }
                .disabled(generationState.isGenerating || !isRequestLongEnough || isAlreadyGenerated)

                Button("Use") {
                    onUse(generatedPattern)
                }
                .buttonStyle(.borderedProminent)
                .disabled(generatedPattern.isEmpty || generationState.isGenerating)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onKeyPress(.return) {
            primaryAction()
            return .handled
        }
        .onDisappear {
            store.save()
        }
    }
}

#Preview {
    RuleRow(rule: .constant(.init(name: "Damn", pattern: ""))) {}
        .previewModifiers()
}
