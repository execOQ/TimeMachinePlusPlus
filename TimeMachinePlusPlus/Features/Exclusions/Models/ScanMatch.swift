import Foundation

struct ScanMatch: Identifiable, Hashable {
    enum Source: Hashable {
        case rule(String)

        var label: String {
            switch self {
            case .rule(let name):
                return name
            }
        }
    }

    var id: String { path }
    var path: String
    var source: Source
    var isDirectory: Bool
    var isExcluded: Bool
    var sizeBytes: Int64?
    var isSelected: Bool

    var plannedAction: String {
        isExcluded ? "Already excluded" : (isSelected ? "Will exclude" : "Skipped")
    }
}
