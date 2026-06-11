import Foundation

struct RulePreviewKey: Equatable {
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
