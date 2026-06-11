//
//  RulePreviewPanel.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

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
            header()
            previewContent()
        }
    }

    // MARK: - View Components

    private func header() -> some View {
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
    }

    @ViewBuilder
    private func previewContent() -> some View {
        if isDisabled {
            message("Enable this rule to preview matches.")
        } else if validationError != nil {
            message("Fix the rule before previewing matches.")
        } else if isLoading {
            loadingState()
        } else if !hasRequestedPreview {
            message("Edit this rule to preview matches, or refresh manually.")
        } else if results.isEmpty {
            message("No matches for this rule.")
        } else {
            resultsList()
            resultLimitMessage()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func loadingState() -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            message("Checking this rule...")
        }
    }

    private func resultsList() -> some View {
        List {
            ForEach(results) { result in
                previewRow(for: result)
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
    }

    private func previewRow(for result: RulePreviewResult) -> some View {
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
                FinderPathActions.reveal(path: result.path)
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
            Button {
                FinderPathActions.copy(path: result.path)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
    }

    @ViewBuilder
    private func resultLimitMessage() -> some View {
        if results.count >= resultLimit {
            message("Showing first \(resultLimit) matches.")
        }
    }
}
