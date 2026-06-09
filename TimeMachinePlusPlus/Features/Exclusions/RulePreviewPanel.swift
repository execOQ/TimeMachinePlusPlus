//
//  RulePreviewPanel.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import AppKit
import SwiftUI

struct RulePreviewPanel: View {
    var isLoading: Bool
    var results: [RulePreviewResult]
    var resultLimit: Int
    var hasRequestedPreview: Bool
    var isDisabled: Bool
    var validationError: String?
    var onRefresh: () -> Void

    private static let rowHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Quick Results", systemImage: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isDisabled || validationError != nil || isLoading)
                .help("Refresh quick results for this rule")
            }

            if isDisabled {
                Text("Enable this rule to preview matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if validationError != nil {
                Text("Fix the rule before previewing matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking this rule...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !hasRequestedPreview {
                Text("Edit this rule to preview matches, or refresh manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty {
                Text("No matches for this rule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(results) { result in
                        HStack(spacing: 8) {
                            Image(systemName: result.isDirectory ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(result.path)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .contextMenu {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.path)])
                            } label: {
                                Label("Reveal in Finder", systemImage: "finder")
                            }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result.path, forType: .string)
                            } label: {
                                Label("Copy Path", systemImage: "doc.on.doc")
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: min(CGFloat(results.count), 8) * Self.rowHeight)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.15))
                )

                if results.count >= resultLimit {
                    Text("Showing first \(resultLimit) matches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
