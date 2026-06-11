import Foundation

enum ScanCandidateBuilder {
    static func pathRuleCandidates(
        from rules: [RegexRule],
        excludingScannedPaths scannedPaths: Set<String>
    ) -> [ScanPathRuleCandidate] {
        rules.compactMap { rule in
            guard rule.kind == .path, rule.isEnabled else { return nil }

            let path = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            guard !scannedPaths.contains(path) else { return nil }
            guard FileManager.default.fileExists(atPath: path) else { return nil }

            let isDirectory = (try? URL(fileURLWithPath: path)
                .resourceValues(forKeys: [.isDirectoryKey])
                .isDirectory) ?? false

            return ScanPathRuleCandidate(path: path, rule: rule, isDirectory: isDirectory)
        }
    }
}
