import Foundation

struct RulePreviewResult: Identifiable, Hashable {
    enum Status: Hashable {
        case excluded
        case included
        case missing
        case matched

        var label: String {
            switch self {
            case .excluded: return "Excluded"
            case .included: return "Included"
            case .missing: return "Missing"
            case .matched: return "Matched"
            }
        }
    }

    var id: String { path }
    var path: String
    var isDirectory: Bool
    var sizeBytes: Int64?
    var status: Status
}
