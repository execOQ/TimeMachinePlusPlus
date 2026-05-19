import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    func snapshotBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { selectedSnapshots.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectedSnapshots.insert(path)
                } else {
                    selectedSnapshots.remove(path)
                }
            }
        )
    }

    func pathEditor(_ title: String, text: Binding<String>) -> some View {
        AppPathEditor(title: title, text: text)
    }

}
