//
//  ReleaseNotesDisclosureList.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import MarkdownUI
import SwiftUI

struct ReleaseNotesDisclosureList: View {
    let markdown: String
    @State private var expandedSectionIDs: Set<String> = []

    private var sections: [ReleaseNoteSection] {
        ReleaseNoteParser.sections(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionLabel(title: "Release Notes", topPadding: 2)

            if sections.isEmpty {
                ScrollView {
                    Markdown(markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .releaseNoteGroupBackground()
                }
                .frame(maxHeight: 220)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sections) { section in
                        ReleaseNoteSectionDisclosure(
                            section: section,
                            isExpanded: isExpandedBinding(for: section)
                        ) {
                            releaseNoteContent(for: section)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: markdown, onMarkdownChanged)
    }

    // MARK: - View Components

    @ViewBuilder
    private func releaseNoteContent(for section: ReleaseNoteSection) -> some View {
        let items = section.displayListItems

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ReleaseNoteItemRow(
                        item: item,
                        showsDivider: index < items.count - 1
                    )
                }
            }
        } else if section.markdown.isEmpty {
            Text("No details provided.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        } else {
            Markdown(section.markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
    }
}

private extension ReleaseNotesDisclosureList {
    func onMarkdownChanged() {
        expandedSectionIDs.removeAll()
    }

    func isExpandedBinding(for section: ReleaseNoteSection) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(section.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(section.id)
                } else {
                    expandedSectionIDs.remove(section.id)
                }
            }
        )
    }
}

private struct ReleaseNoteSectionDisclosure<Content: View>: View {
    let section: ReleaseNoteSection
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    private var titleParts: ReleaseNoteTitleParts {
        ReleaseNoteTitleParts(section.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14)

                    Spacer(minLength: 1)

                    Text(titleParts.symbol ?? "📰")
                        .font(.title3)
                        .frame(width: 24)

                    Text(titleParts.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .padding(.all, 10)
            }
            .buttonStyle(.plain)
            .zIndex(1)

            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    Divider()
                    content()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .zIndex(0)
        }
        .releaseNoteGroupBackground()
    }
}

private struct ReleaseNoteItemRow: View {
    let item: ReleaseNoteListItem
    var showsDivider = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.symbol ?? "•")
                .font(.body)
                .foregroundStyle(item.symbol == nil ? .secondary : .primary)
                .frame(width: 20)

            Markdown(item.markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Group {
                if let issueReference = item.issueReference {
                    if let issueURL = item.issueURL {
                        Link(issueReference, destination: issueURL)
                    } else {
                        Text(issueReference)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.body.monospacedDigit().weight(.semibold))
            .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .padding(.leading, 40)
            }
        }
    }
}

private struct ReleaseNoteTitleParts {
    let symbol: String?
    let title: String

    init(_ rawTitle: String) {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // First, try the existing space-delimited approach: emoji/symbol followed by space and title
        if let whitespaceIndex = trimmedTitle.firstIndex(where: \.isWhitespace) {
            let prefix = String(trimmedTitle[..<whitespaceIndex])
            if !prefix.containsLetterOrNumber {
                symbol = prefix
                title = trimmedTitle[whitespaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }

        // Fallback: allow a leading non-alphanumeric grapheme cluster as symbol even without a space
        if let firstScalarCluster = trimmedTitle.first {
            let firstCluster = String(firstScalarCluster)
            let remainder = String(trimmedTitle.dropFirst())
            if !firstCluster.containsLetterOrNumber {
                symbol = firstCluster
                title = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }

        // Default: no symbol detected; keep the whole title
        symbol = nil
        title = trimmedTitle
    }
}

private extension String {
    var containsLetterOrNumber: Bool {
        contains { $0.isLetter || $0.isNumber }
    }
}

private extension View {
    func releaseNoteGroupBackground() -> some View {
        background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.2), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ReleaseNotesDisclosureList(markdown: """
        ## 🛠️ Fixes
        - ✨ Resolved an issue where backups could stall at 99% in rare cases. [#1234]
        - Improved reliability of network drive detection when waking from sleep. [#1250]
        - Fixed a crash when parsing very large log files. [#1278]

        ## ✨ Improvements
        - Faster incremental backup indexing for large photo libraries.
        - Reduced CPU usage during verification by up to 25%.
        - Added better progress reporting for long-running tasks.

        ## 🧪 Experimental
        - New deduplication engine (disabled by default). Enable in Settings → Advanced to try it out.

        ## 📄 Notes
        This release includes internal changes to the scheduler. If you notice unusual backup timing, please report via Feedback.

        ## 🔗 Links
        - Documentation: https://example.com/docs/release/1.2.3
        - Support: https://example.com/support

        """
    )
    .frame(maxHeight: .infinity, alignment: .top)
    .previewModifiers()
}
