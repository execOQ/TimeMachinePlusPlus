import Foundation

enum RuleMatcher {
    static func validationError(for rule: RegexRule) -> String? {
        switch rule.kind {
        case .specific:
            let p = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { return "Enter an absolute path." }
            if !p.hasPrefix("/") { return "Path must start with /." }
            return nil
        case .gitignore:
            return gitignorePatterns(from: rule.pattern).isEmpty ? "Enter at least one git-like pattern." : nil
        case .regex:
            return RegexValidator.validate(rule.pattern)
        }
    }

    static func matches(path: String, isDirectory: Bool, rule: RegexRule) -> Bool {
        switch rule.kind {
        case .specific:
            return path == rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)

        case .gitignore:
            return gitignorePatterns(from: rule.pattern).contains { pattern in
                gitignorePattern(pattern, matches: path, isDirectory: isDirectory)
            }

        case .regex:
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return false }
            let range = NSRange(path.startIndex..<path.endIndex, in: path)
            return regex.firstMatch(in: path, range: range) != nil
        }
    }

    private static func gitignorePatterns(from input: String) -> [String] {
        input
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("!") }
    }

    private static func gitignorePattern(_ rawPattern: String, matches path: String, isDirectory: Bool) -> Bool {
        var pattern = rawPattern
        let directoryOnly = pattern.hasSuffix("/")

        if directoryOnly && !isDirectory {
            return false
        }

        pattern = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !pattern.isEmpty else { return false }

        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidates: [String]
        if pattern.contains("/") {
            candidates = [normalizedPath]
        } else {
            candidates = normalizedPath.split(separator: "/").map(String.init)
        }

        return candidates.contains { candidate in
            wildcard(pattern: pattern, matches: candidate)
        } || wildcard(pattern: "**/\(pattern)", matches: normalizedPath)
    }

    private static func wildcard(pattern: String, matches text: String) -> Bool {
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: #"[^/]*"#)
            .replacingOccurrences(of: "\\?", with: #"[^/]"#) + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
