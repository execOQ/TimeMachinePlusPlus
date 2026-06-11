import Foundation

enum RegexSuggestionProvider {
    struct Suggestion: Identifiable {
        let id: String
        let display: String
        let insertion: String
        let description: String

        init(_ display: String, insert insertion: String? = nil, _ description: String) {
            self.display = display
            self.insertion = insertion ?? display
            self.description = description
            self.id = display + (insertion ?? display)
        }
    }

    static func suggestions(for pattern: String) -> [Suggestion] {
        if pattern.isEmpty { return opening }
        if pattern.hasSuffix("\\") { return escapeSequences }
        if isInsideCharacterClass(pattern) { return characterClass(after: pattern) }
        if pattern.hasSuffix("(") { return groupModifiers }
        if pattern.hasSuffix("{") { return bracedQuantifiers }
        if pattern.hasSuffix("|") { return opening }

        let last = pattern.unicodeScalars.last!
        if CharacterSet(charactersIn: "*+?}").contains(last) { return afterQuantifier }

        return quantifiers + closers
    }

    // MARK: - Context sets

    private static let opening: [Suggestion] = [
        Suggestion(".*", "Any characters (greedy)"),
        Suggestion("\\d+", "One or more digits"),
        Suggestion("\\w+", "One or more word characters"),
        Suggestion("[^/]+", "Any non-slash characters"),
        Suggestion("(", "Start a group"),
        Suggestion("[", "Start a character class"),
        Suggestion("^", "Anchor: start of string"),
        Suggestion("$", "Anchor: end of string"),
    ]

    // After a trailing backslash — display shows \x, insert only x
    private static let escapeSequences: [Suggestion] = [
        Suggestion("\\d", insert: "d", "Digit [0-9]"),
        Suggestion("\\w", insert: "w", "Word character [a-zA-Z0-9_]"),
        Suggestion("\\s", insert: "s", "Whitespace"),
        Suggestion("\\D", insert: "D", "Non-digit"),
        Suggestion("\\W", insert: "W", "Non-word character"),
        Suggestion("\\S", insert: "S", "Non-whitespace"),
        Suggestion("\\b", insert: "b", "Word boundary"),
        Suggestion("\\B", insert: "B", "Non-word boundary"),
        Suggestion("\\n", insert: "n", "Newline"),
        Suggestion("\\t", insert: "t", "Tab"),
        Suggestion("\\.", insert: ".", "Literal dot"),
        Suggestion("\\/", insert: "/", "Literal slash"),
        Suggestion("\\(", insert: "(", "Literal open paren"),
        Suggestion("\\)", insert: ")", "Literal close paren"),
    ]

    private static func characterClass(after pattern: String) -> [Suggestion] {
        // If [ was just opened (no content yet), offer negation first
        let afterBracket = pattern.hasSuffix("[")
        var result: [Suggestion] = []
        if afterBracket {
            result.append(Suggestion("^", "Negate — match anything NOT in this class"))
        }
        result += [
            Suggestion("a-z", "Lowercase ASCII letters"),
            Suggestion("A-Z", "Uppercase ASCII letters"),
            Suggestion("0-9", "Digits 0–9"),
            Suggestion("\\d", "Digit class"),
            Suggestion("\\w", "Word character class"),
            Suggestion("\\s", "Whitespace class"),
            Suggestion("]", "Close character class"),
        ]
        return result
    }

    private static let groupModifiers: [Suggestion] = [
        Suggestion("?:", "Non-capturing group — matches but doesn't capture"),
        Suggestion("?=", "Positive lookahead — asserts what follows"),
        Suggestion("?!", "Negative lookahead — asserts what does NOT follow"),
        Suggestion("?<=", "Positive lookbehind — asserts what precedes"),
        Suggestion("?<!", "Negative lookbehind — asserts what does NOT precede"),
    ]

    private static let bracedQuantifiers: [Suggestion] = [
        Suggestion("2}", "Exactly 2"),
        Suggestion("2,}", "2 or more"),
        Suggestion("1,}", "1 or more"),
        Suggestion("2,5}", "Between 2 and 5"),
        Suggestion("0,1}", "0 or 1 (same as ?)"),
    ]

    private static let quantifiers: [Suggestion] = [
        Suggestion("*", "Zero or more (greedy)"),
        Suggestion("+", "One or more (greedy)"),
        Suggestion("?", "Zero or one"),
        Suggestion("*?", "Zero or more (lazy)"),
        Suggestion("+?", "One or more (lazy)"),
        Suggestion("{2,}", "Two or more"),
    ]

    private static let closers: [Suggestion] = [
        Suggestion("|", "Alternation — match this OR the next"),
        Suggestion(")", "Close group"),
        Suggestion("$", "Anchor: end of string"),
        Suggestion(".*", "Any characters"),
    ]

    private static let afterQuantifier: [Suggestion] = [
        Suggestion("|", "Alternation — match this OR the next"),
        Suggestion(")", "Close group"),
        Suggestion("$", "Anchor: end of string"),
        Suggestion(".*", "Any characters"),
        Suggestion("\\d+", "One or more digits"),
        Suggestion("(", "Start a group"),
    ]

    // MARK: - Helpers

    private static func isInsideCharacterClass(_ pattern: String) -> Bool {
        var inClass = false
        var inEscape = false
        for ch in pattern {
            if inEscape { inEscape = false; continue }
            if ch == "\\" { inEscape = true; continue }
            if !inClass, ch == "[" { inClass = true }
            else if inClass, ch == "]" { inClass = false }
        }
        return inClass
    }
}
