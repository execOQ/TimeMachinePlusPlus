import Foundation

enum AppSidebarSelection: Hashable {
    case section(SidebarSection)
    case destination(String)
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case exclusionRules = "Rules"
    case appManagedExclusions = "App-Managed"
    case commands = "Time Machine"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .exclusionRules: return "text.magnifyingglass"
        case .appManagedExclusions: return "checklist.checked"
        case .commands: return "terminal"
        case .settings: return "gearshape"
        }
    }
}
