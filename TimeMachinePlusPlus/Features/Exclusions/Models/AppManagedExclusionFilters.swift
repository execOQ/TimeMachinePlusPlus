import Foundation

enum AppManagedExclusionSourceFilter: Hashable, Identifiable {
    case all
    case source(String)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .source(let source):
            return source
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All rules"
        case .source(let source):
            return source
        }
    }

    func includes(_ exclusion: AppliedExclusion) -> Bool {
        switch self {
        case .all:
            return true
        case .source(let source):
            return exclusion.sourceDescription == source
        }
    }
}

enum AppManagedExclusionSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case rule
    case path

    var id: Self { self }

    var title: String {
        switch self {
        case .newestFirst:
            return "Newest first"
        case .oldestFirst:
            return "Oldest first"
        case .rule:
            return "Rule"
        case .path:
            return "Path"
        }
    }
}

extension Array where Element == AppliedExclusion {
    func sorted(using order: AppManagedExclusionSortOrder) -> [AppliedExclusion] {
        sorted { lhs, rhs in
            switch order {
            case .newestFirst:
                if lhs.appliedAt != rhs.appliedAt {
                    return lhs.appliedAt > rhs.appliedAt
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            case .oldestFirst:
                if lhs.appliedAt != rhs.appliedAt {
                    return lhs.appliedAt < rhs.appliedAt
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            case .rule:
                let sourceComparison = lhs.sourceDescription.localizedCaseInsensitiveCompare(rhs.sourceDescription)
                if sourceComparison != .orderedSame {
                    return sourceComparison == .orderedAscending
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            case .path:
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
        }
    }
}
