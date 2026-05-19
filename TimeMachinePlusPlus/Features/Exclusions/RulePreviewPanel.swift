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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Quick Results", systemImage: "bolt")
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
                VStack(spacing: 0) {
                    ForEach(results) { result in
                        RulePreviewRow(result: result)
                        if result.id != results.last?.id {
                            Divider()
                        }
                    }
                }
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

private struct RulePreviewRow: View {
    var result: RulePreviewResult

    private var statusImage: String {
        switch result.status {
        case .excluded: return "checkmark.circle.fill"
        case .included: return "circle"
        case .missing: return "questionmark.circle"
        case .matched: return "line.3.horizontal.decrease.circle"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .excluded: return .green
        case .included: return .secondary
        case .missing: return .orange
        case .matched: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(result.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let sizeBytes = result.sizeBytes {
                Text(Formatters.fileSize(sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Label(result.status.label, systemImage: statusImage)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
