//
//  ReleaseNotesModels.swift
//  TimeMachinePlusPlus
//
//  Created by Artem Bagin on 19.05.2026.
//

import Foundation

struct ReleaseNoteSection: Identifiable, Equatable {
    let title: String
    let markdown: String

    var id: String { "\(title)\n\(markdown)" }
    var listItems: [String] { ReleaseNoteParser.listItems(from: markdown) }
    var displayListItems: [ReleaseNoteListItem] { ReleaseNoteParser.displayListItems(from: markdown) }
}

struct ReleaseNoteListItem: Identifiable, Equatable {
    let symbol: String?
    let markdown: String
    let issueReference: String?
    let issueURL: URL?

    var id: String { "\(symbol ?? "")\n\(markdown)\n\(issueReference ?? "")\n\(issueURL?.absoluteString ?? "")" }
}

enum ReleaseNoteParser {
    static func sections(from markdown: String) -> [ReleaseNoteSection] {
        let lines = normalizedLines(from: markdown)
        var sections: [ReleaseNoteSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func finishCurrentSection() {
            guard let currentTitle else { return }
            let body = currentLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(ReleaseNoteSection(title: currentTitle, markdown: body))
        }

        for line in lines {
            if let heading = MarkdownHeading(line: line, lineNumber: 0) {
                finishCurrentSection()
                currentTitle = heading.title
                currentLines = []
            } else if currentTitle != nil {
                currentLines.append(line)
            }
        }

        finishCurrentSection()
        return sections.filter { !$0.markdown.isEmpty }
    }

    static func listItems(from markdown: String) -> [String] {
        var items: [String] = []

        for line in normalizedLines(from: markdown) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            if let item = unorderedListItem(from: trimmedLine) ?? orderedListItem(from: trimmedLine) {
                items.append(item)
            } else if !items.isEmpty {
                items[items.count - 1] += "\n" + trimmedLine
            }
        }

        return items
    }

    static func displayListItems(from markdown: String) -> [ReleaseNoteListItem] {
        listItems(from: markdown).map(displayListItem)
    }

    private static func normalizedLines(from markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func unorderedListItem(from line: String) -> String? {
        guard line.count > 2 else { return nil }
        let marker = line.prefix(2)
        guard marker == "- " || marker == "* " || marker == "+ " else { return nil }
        return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
    }

    private static func orderedListItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }

        let contentStart = line.index(after: dotIndex)
        guard contentStart < line.endIndex, line[contentStart].isWhitespace else { return nil }
        return line[contentStart...].trimmingCharacters(in: .whitespaces)
    }

    private static func displayListItem(from item: String) -> ReleaseNoteListItem {
        let issueResult = removingTrailingIssueReference(from: item)
        let symbolResult = removingLeadingSymbol(from: issueResult.markdown)

        return ReleaseNoteListItem(
            symbol: symbolResult.symbol,
            markdown: symbolResult.markdown,
            issueReference: issueResult.issueReference,
            issueURL: issueResult.issueURL
        )
    }

    private static func removingTrailingIssueReference(from item: String) -> (markdown: String, issueReference: String?, issueURL: URL?) {
        let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = removingTrailingMarkdownIssueReference(from: trimmedItem) {
            return result
        }
        if let result = removingTrailingBareIssueReference(from: trimmedItem) {
            return result
        }

        return (trimmedItem, nil, nil)
    }

    private static func removingTrailingMarkdownIssueReference(from item: String) -> (markdown: String, issueReference: String?, issueURL: URL?)? {
        guard let match = firstRegexMatch(pattern: #"\s*\[#(\d+)\]\(([^)]+)\)\s*$"#, in: item),
              let fullRange = Range(match.range, in: item),
              let issueRange = Range(match.range(at: 1), in: item),
              let urlRange = Range(match.range(at: 2), in: item)
        else { return nil }

        let markdown = String(item[..<fullRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (markdown, "#\(item[issueRange])", URL(string: String(item[urlRange])))
    }

    private static func removingTrailingBareIssueReference(from item: String) -> (markdown: String, issueReference: String?, issueURL: URL?)? {
        guard let match = firstRegexMatch(pattern: #"\s*\[?#(\d+)\]?\s*$"#, in: item),
              let fullRange = Range(match.range, in: item),
              let issueRange = Range(match.range(at: 1), in: item)
        else { return nil }

        let markdown = String(item[..<fullRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (markdown, "#\(item[issueRange])", nil)
    }

    private static func firstRegexMatch(pattern: String, in value: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range)
    }

    private static func removingLeadingSymbol(from item: String) -> (symbol: String?, markdown: String) {
        let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
        if let whitespaceIndex = trimmedItem.firstIndex(where: \.isWhitespace) {
            let prefix = String(trimmedItem[..<whitespaceIndex])
            if !prefix.containsLetterOrNumber {
                let markdown = trimmedItem[whitespaceIndex...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !markdown.isEmpty else { return (nil, trimmedItem) }
                return (prefix, markdown)
            }
        }

        guard let firstCharacter = trimmedItem.first else { return (nil, trimmedItem) }

        let prefix = String(firstCharacter)
        guard !prefix.containsLetterOrNumber else { return (nil, trimmedItem) }

        let markdown = trimmedItem.dropFirst()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else { return (nil, trimmedItem) }

        return (prefix, markdown)
    }
}

private extension String {
    var containsLetterOrNumber: Bool {
        contains { $0.isLetter || $0.isNumber }
    }
}

private struct MarkdownHeading {
    let level: Int
    let title: String
    let lineNumber: Int

    init?(line: String, lineNumber: Int) {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix("#") else { return nil }

        let level = trimmedLine.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), trimmedLine.dropFirst(level).first?.isWhitespace == true else { return nil }

        let rawTitle = trimmedLine
            .dropFirst(level)
            .trimmingCharacters(in: .whitespaces)
        let title = Self.stripClosingHashes(from: rawTitle)
        guard !title.isEmpty else { return nil }

        self.level = level
        self.title = title
        self.lineNumber = lineNumber
    }

    private static func stripClosingHashes(from title: String) -> String {
        var trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard trimmedTitle.last == "#" else { return trimmedTitle }

        while trimmedTitle.last == "#" {
            trimmedTitle.removeLast()
        }

        return trimmedTitle.trimmingCharacters(in: .whitespaces)
    }
}
