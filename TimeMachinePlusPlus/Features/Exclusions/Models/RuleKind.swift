import Foundation

enum RuleKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case path
    case pattern
    case regex

    var id: String { rawValue }

    static func fromPersistedRawValue(_ rawValue: String?) -> RuleKind? {
        switch rawValue {
        case "path", "specific": return .path
        case "pattern", "gitignore", "folderName": return .pattern
        case "regex": return .regex
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .path: return "Path"
        case .pattern: return "Pattern"
        case .regex: return "Regex"
        }
    }

    var placeholder: String {
        switch self {
        case .path: return "/Users/you/path/to/file-or-folder"
        case .pattern: return "node_modules/"
        case .regex: return #"/node_modules($|/)"#
        }
    }

    var help: String {
        switch self {
        case .path:
            return "Exact absolute path to a file or folder. Use the browse button or type the path directly."
        case .pattern:
            return "Use simple path patterns like node_modules/, **/.venv/, build/, or *.xcactivitylog."
        case .regex:
            return "Match the full absolute path with a regular expression."
        }
    }
}
