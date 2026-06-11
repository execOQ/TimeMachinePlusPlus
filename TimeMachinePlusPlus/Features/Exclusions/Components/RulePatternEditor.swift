import SwiftUI

struct RulePatternEditor: View {
    @Binding var rule: RegexRule
    @Binding var isAIHelperPresented: Bool
    var aiGenerationState: AIRegexGenerationState
    let onInsertRegexSuggestion: (String) -> Void
    let onUseGeneratedPattern: (String) -> Void
    let onPickPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            patternField()

            if rule.kind == .regex {
                RegexSuggestionBar(
                    rule: $rule,
                    onInsert: onInsertRegexSuggestion
                )
            }
        }
    }

    // MARK: - View Components

    private func patternField() -> some View {
        HStack(spacing: 8) {
            TextField(rule.kind.placeholder, text: $rule.pattern)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            accessoryButton()
        }
    }

    @ViewBuilder
    private func accessoryButton() -> some View {
        if rule.kind == .path {
            Button(action: onPickPath) {
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
                    request: $rule.lastAIRequest,
                    generatedPattern: $rule.lastAIGeneratedPattern,
                    generatedForRequest: $rule.lastAIGeneratedForRequest,
                    generationState: aiGenerationState,
                    onUse: onUseGeneratedPattern
                )
            }
        }
    }
}
