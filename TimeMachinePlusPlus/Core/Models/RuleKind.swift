import Foundation

enum RuleKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case specific
    case gitignore
    case regex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .specific: return "Specific"
        case .gitignore: return "Git-like"
        case .regex: return "Regex"
        }
    }

    var placeholder: String {
        switch self {
        case .specific: return "/Users/you/path/to/file-or-folder"
        case .gitignore: return "node_modules/"
        case .regex: return #"/node_modules($|/)"#
        }
    }

    var help: String {
        switch self {
        case .specific:
            return "Exact absolute path to a file or folder. Use the browse button or type the path directly."
        case .gitignore:
            return "Use simple gitignore-style globs like node_modules/, **/.venv/, build/, or *.xcactivitylog."
        case .regex:
            return "Match the full absolute path with a regular expression."
        }
    }
}
