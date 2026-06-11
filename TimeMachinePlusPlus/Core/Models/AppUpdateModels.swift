import Foundation

enum AppUpdateStatus: String, Codable, Equatable {
    case idle
    case checking
    case available
    case downloading
    case readyToInstall
    case installing
    case upToDate
    case failed

    var menuBarSystemImage: String {
        switch self {
        case .checking, .available, .downloading, .installing:
            return "arrow.triangle.2.circlepath"
        case .readyToInstall:
            return "arrow.down.circle.fill"
        case .idle, .upToDate, .failed:
            return "clock.arrow.circlepath"
        }
    }
}

enum AppBuildInfo {
    static var displayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

enum AppUpdateNotificationPolicy {
    static func shouldNotify(version: String, lastNotifiedVersion: String?) -> Bool {
        lastNotifiedVersion != version
    }
}

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
        guard let match = firstRegexMatch(pattern: #"\s*#(\d+)\s*$"#, in: item),
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
        guard let whitespaceIndex = trimmedItem.firstIndex(where: \.isWhitespace) else {
            return (nil, trimmedItem)
        }

        let prefix = String(trimmedItem[..<whitespaceIndex])
        guard prefix.rangeOfCharacter(from: .alphanumerics) == nil else {
            return (nil, trimmedItem)
        }

        let markdown = trimmedItem[whitespaceIndex...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else { return (nil, trimmedItem) }

        return (prefix, markdown)
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

struct GitHubReleaseMetadata: Decodable, Equatable {
    let name: String
    let tagName: String
    let body: String
    let htmlURL: URL
    let isPrerelease: Bool
    let assets: [Asset]

    var displayName: String {
        name.isEmpty ? tagName : name
    }

    var version: String {
        AppVersionComparator.normalizedVersion(tagName)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case isPrerelease = "prerelease"
        case assets
    }

    struct Asset: Decodable, Equatable {
        let name: String
        let contentType: String

        enum CodingKeys: String, CodingKey {
            case name
            case contentType = "content_type"
        }
    }
}

enum AppVersionComparator {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .trimmingPrefix("V")
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftComponent = index < left.count ? left[index] : 0
            let rightComponent = index < right.count ? right[index] : 0

            if leftComponent > rightComponent { return .orderedDescending }
            if leftComponent < rightComponent { return .orderedAscending }
        }

        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: "-", maxSplits: 1)
            .first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
