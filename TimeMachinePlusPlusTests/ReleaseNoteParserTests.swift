import XCTest
@testable import TimeMachinePlusPlus

final class ReleaseNoteParserTests: XCTestCase {
    func testReleaseNoteParserCreatesSectionsFromHeadings() {
        let markdown = """
        ## Development News
        - Support Loop by [sponsoring the project](https://example.com)
        - Join our Discord server

        ## New Features
        - Added smarter Time Machine exclusions
        """

        let sections = ReleaseNoteParser.sections(from: markdown)

        XCTAssertEqual(sections.map(\.title), ["Development News", "New Features"])
        XCTAssertTrue(sections[0].markdown.contains("sponsoring the project"))
        XCTAssertFalse(sections[0].markdown.contains("## New Features"))
        XCTAssertEqual(sections[1].markdown, "- Added smarter Time Machine exclusions")
    }

    func testReleaseNoteParserUsesRepeatedSubheadingsAfterReleaseTitle() {
        let markdown = """
        # TimeMachine++ 0.2.0

        ## Development News
        - Localizing Loop

        ## New Features
        - Adds exclusions
        """

        let sections = ReleaseNoteParser.sections(from: markdown)

        XCTAssertEqual(sections.map(\.title), ["Development News", "New Features"])
        XCTAssertEqual(sections[0].markdown, "- Localizing Loop")
        XCTAssertEqual(sections[1].listItems, ["Adds exclusions"])
    }

    func testReleaseNoteParserSplitsNestedHeadingsIntoSeparateSections() {
        let markdown = """
        # Changes

        Replace this draft text with the release notes before publishing.

        ## Assets

        Use the attached zip for automatic updates. Use the dmg for manual installation.
        """

        let sections = ReleaseNoteParser.sections(from: markdown)

        XCTAssertEqual(sections.map(\.title), ["Changes", "Assets"])
        XCTAssertEqual(sections[0].markdown, "Replace this draft text with the release notes before publishing.")
        XCTAssertEqual(sections[1].markdown, "Use the attached zip for automatic updates. Use the dmg for manual installation.")
    }

    func testReleaseNoteParserHandlesGitHubReleaseCRLFBody() {
        let markdown = "## Changes\r\n\r\n- Replace this draft text with the release notes before publishing.\r\n\r\n## Assets\r\n\r\n- Use the attached zip for automatic updates. Use the dmg for manual installation.\r\n"

        let sections = ReleaseNoteParser.sections(from: markdown)

        XCTAssertEqual(sections.map(\.title), ["Changes", "Assets"])
        XCTAssertEqual(sections[0].displayListItems, [
            ReleaseNoteListItem(
                symbol: nil,
                markdown: "Replace this draft text with the release notes before publishing.",
                issueReference: nil,
                issueURL: nil
            )
        ])
        XCTAssertEqual(sections[1].displayListItems, [
            ReleaseNoteListItem(
                symbol: nil,
                markdown: "Use the attached zip for automatic updates. Use the dmg for manual installation.",
                issueReference: nil,
                issueURL: nil
            )
        ])
    }

    func testReleaseNoteParserExtractsMarkdownListItems() {
        let markdown = """
        - Support Loop by [sponsoring the project](https://example.com)
        - Add `SkyLight` APIs
        1. Harden input monitor lifecycle
        """

        XCTAssertEqual(ReleaseNoteParser.listItems(from: markdown), [
            "Support Loop by [sponsoring the project](https://example.com)",
            "Add `SkyLight` APIs",
            "Harden input monitor lifecycle"
        ])
    }

    func testReleaseNoteParserBuildsDisplayListItems() {
        let markdown = """
        - ✨ Approachable concurrency + Lots of code refactoring [#1015](https://github.com/execOQ/TimeMachineAdvanced/pull/1015)
        - 🚨 Updated Luminare modifiers #1062
        - Support Loop by [sponsoring the project](https://example.com)
        """

        XCTAssertEqual(ReleaseNoteParser.displayListItems(from: markdown), [
            ReleaseNoteListItem(
                symbol: "✨",
                markdown: "Approachable concurrency + Lots of code refactoring",
                issueReference: "#1015",
                issueURL: URL(string: "https://github.com/execOQ/TimeMachineAdvanced/pull/1015")
            ),
            ReleaseNoteListItem(
                symbol: "🚨",
                markdown: "Updated Luminare modifiers",
                issueReference: "#1062",
                issueURL: nil
            ),
            ReleaseNoteListItem(
                symbol: nil,
                markdown: "Support Loop by [sponsoring the project](https://example.com)",
                issueReference: nil,
                issueURL: nil
            )
        ])
    }
}
