import SwiftUI

struct DetailRouterView: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        switch store.selectedSelection {
        case .destination(let id):
            TimeMachineDestinationView(destinationID: id)
        case .section(let section):
            switch section {
            case .exclusionRules:
                ExclusionsView()
            case .appManagedExclusions:
                AppManagedExclusionsView()
            case .commands:
                TimeMachineOverviewView()
            case .settings:
                SettingsView()
            }
        }
    }
}
