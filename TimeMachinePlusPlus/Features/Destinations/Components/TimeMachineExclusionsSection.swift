import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    var exclusionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Exclusions", subtitle: "Add, remove, or check Time Machine exclusions. macOS does not expose a single complete list, so this view combines app-known paths and current scan results.")

            knownExclusionsBox

            AppSectionView(title: "Paths") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: exclusionPathsBinding)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 10) {
                        Button {
                            pickExclusionPaths()
                        } label: {
                            primaryButtonLabel("Choose Paths", systemImage: "folder")
                        }

                        Button {
                            run(arguments: ["isexcluded"] + parsedExclusionPaths, context: .exclusions, title: "Check Exclusions", status: "Checking exclusions...")
                        } label: {
                            primaryButtonLabel("Check", systemImage: "questionmark.circle")
                        }
                        .disabled(parsedExclusionPaths.isEmpty)

                        Button {
                            run(arguments: ["addexclusion"] + parsedExclusionPaths, context: .exclusions, title: "Add Exclusions", status: "Adding exclusions...")
                        } label: {
                            primaryButtonLabel("Add", systemImage: "minus.circle")
                        }
                        .disabled(parsedExclusionPaths.isEmpty)

                        Button {
                            run(arguments: ["removeexclusion"] + parsedExclusionPaths, context: .exclusions, title: "Remove Exclusions", status: "Removing exclusions...")
                        } label: {
                            primaryButtonLabel("Remove", systemImage: "plus.circle")
                        }
                        .disabled(parsedExclusionPaths.isEmpty)
                    }

                    commandFeedback(for: .exclusions)
                }
            }
        }
    }


}
