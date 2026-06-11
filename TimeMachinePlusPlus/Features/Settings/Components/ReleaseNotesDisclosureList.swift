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

            ScrollView {
                if sections.isEmpty {
                    Markdown(markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .releaseNoteGroupBackground()
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
            .frame(maxHeight: 220)
        }
        .onAppear(perform: expandFirstSectionIfNeeded)
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
        expandFirstSectionIfNeeded()
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

    func expandFirstSectionIfNeeded() {
        guard expandedSectionIDs.isEmpty, let firstSection = sections.first else { return }
        expandedSectionIDs.insert(firstSection.id)
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
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16)

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
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
                .font(item.symbol == nil ? .body : .title3)
                .foregroundStyle(item.symbol == nil ? .secondary : .primary)
                .frame(width: 28, alignment: .center)

            Markdown(item.markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let issueReference = item.issueReference {
                if let issueURL = item.issueURL {
                    Link(issueReference, destination: issueURL)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text(issueReference)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .padding(.leading, 54)
            }
        }
    }
}

private struct ReleaseNoteTitleParts {
    let symbol: String?
    let title: String

    init(_ rawTitle: String) {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let whitespaceIndex = trimmedTitle.firstIndex(where: \.isWhitespace) else {
            symbol = nil
            title = trimmedTitle
            return
        }

        let prefix = String(trimmedTitle[..<whitespaceIndex])
        guard prefix.rangeOfCharacter(from: .alphanumerics) == nil else {
            symbol = nil
            title = trimmedTitle
            return
        }

        symbol = prefix
        title = trimmedTitle[whitespaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension View {
    func releaseNoteGroupBackground() -> some View {
        background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.2), lineWidth: 1)
            }
    }
}
