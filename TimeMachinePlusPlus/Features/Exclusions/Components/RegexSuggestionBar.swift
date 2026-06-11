import SwiftUI

struct RegexSuggestionBar: View {
    @Binding var rule: RegexRule
    let onInsert: (String) -> Void

    private var suggestions: [RegexSuggestionProvider.Suggestion] {
        RegexSuggestionProvider.suggestions(for: rule.pattern)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                primarySuggestions()
                overflowSuggestions()
            }
        }
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.15), value: suggestions.map(\.id))
    }

    // MARK: - View Components

    private func primarySuggestions() -> some View {
        ForEach(Array(suggestions.prefix(10).enumerated()), id: \.element.id) { index, suggestion in
            let keyChar: Character = index < 9 ? Character("\(index + 1)") : "0"
            Button {
                onInsert(suggestion.insertion)
            } label: {
                shortcutSuggestionLabel(suggestion: suggestion, index: index)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("⌘\(index < 9 ? "\(index + 1)" : "0")  |  \(suggestion.description)")
            .keyboardShortcut(KeyEquivalent(keyChar), modifiers: .command)
        }
    }

    private func overflowSuggestions() -> some View {
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

    private func shortcutSuggestionLabel(
        suggestion: RegexSuggestionProvider.Suggestion,
        index: Int
    ) -> some View {
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
}
