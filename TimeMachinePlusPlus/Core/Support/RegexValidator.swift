import Foundation

enum RegexValidator {
    static func validate(_ pattern: String) -> String? {
        validateWithSuggestion(pattern)?.message
    }

    static func validateWithSuggestion(_ pattern: String) -> RuleValidationIssue? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return RuleValidationIssue(message: "Pattern cannot be empty.", suggestion: nil)
        }

        do {
            _ = try NSRegularExpression(pattern: trimmed)
            return nil
        } catch {
            let desc = error.localizedDescription
            return RuleValidationIssue(message: desc, suggestion: suggestion(forError: desc, pattern: trimmed))
        }
    }

    private static func suggestion(forError desc: String, pattern: String) -> String? {
        let lower = desc.lowercased()

        if lower.contains("nothing to repeat") || lower.contains("quantifier") {
            if pattern.contains("*") && !pattern.contains(".*") {
                return "Use .* instead of * to match any sequence of characters in regex."
            }
            if pattern.contains("?") && !pattern.contains(".?") && !pattern.contains("[") {
                return "Use .? instead of ? in regex, or escape it as \\? to match a literal question mark."
            }
            return "Remove or escape the quantifier that has nothing to repeat (e.g., prefix * with . to get .*)."
        }

        if lower.contains("closing parenthesis") || lower.contains("unmatched") && lower.contains("(") {
            return "Every ( needs a matching ). Count your parentheses or escape literal ones as \\(."
        }

        if lower.contains("closing bracket") || lower.contains("missing") && lower.contains("bracket") {
            return "Every [ needs a matching ]. Escape a literal bracket as \\[."
        }

        if lower.contains("unmatched") && lower.contains(")") {
            return "There is a ) with no matching (. Remove the extra ) or add a ( before it."
        }

        if pattern.hasSuffix("\\") {
            return "A lone \\ at the end is not valid. Complete the escape sequence (e.g., \\.) or use \\\\ for a literal backslash."
        }

        if lower.contains("invalid escape") || lower.contains("invalid back") {
            return "Check your backslash escapes — use \\. \\/ \\( etc., or \\\\ for a literal backslash."
        }

        // Looks like a path pattern.
        if !pattern.contains("^") && !pattern.contains("$") && !pattern.contains("(") &&
            (pattern.contains("**/") || pattern.hasSuffix("/") || (!pattern.contains(".") && !pattern.contains("["))) {
            return "This looks like a path pattern. Try switching the mode to 'Pattern'."
        }

        return nil
    }
}
