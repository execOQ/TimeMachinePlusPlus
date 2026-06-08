import XCTest
@testable import TimeMachinePlusPlus

final class TimeMachinePlusPlusTests: XCTestCase {
    func testRegexValidatorRejectsInvalidPattern() {
        let validRule = RegexRule(name: "Regex", pattern: #"/node_modules($|/)"#, kind: .regex)
        let invalidRule = RegexRule(name: "Broken", pattern: "[", kind: .regex)

        XCTAssertNil(RuleMatcher.validationError(for: validRule))
        XCTAssertNotNil(RuleMatcher.validationError(for: invalidRule))
    }

    func testScannerMatchesGitLikeDirectoryAndSkipsDescendants() throws {
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("TimeMachinePlusPlusTests-\(UUID().uuidString)", isDirectory: true)
        let nodeModules = root.appendingPathComponent("project/node_modules", isDirectory: true)
        let nested = nodeModules.appendingPathComponent("left-pad", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = AppSettings(
            scanRoots: [root.path],
            scanIntervalMinutes: AppSettings.dailyScanIntervalMinutes,
            maxDepth: 8
        )
        let rule = RegexRule(name: "Node", pattern: "node_modules/", kind: .gitignore)

        let matches = FileSystemScanner().scan(settings: settings, rules: [rule])

        XCTAssertTrue(matches.keys.contains { $0.path == nodeModules.path })
        XCTAssertFalse(matches.keys.contains { $0.path == nested.path })
    }

    func testScannerCanPreviewOneRuleOnly() throws {
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("TimeMachinePlusPlusRulePreview-\(UUID().uuidString)", isDirectory: true)
        let nodeModules = root.appendingPathComponent("project/node_modules", isDirectory: true)
        let build = root.appendingPathComponent("project/build", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = AppSettings(
            scanRoots: [root.path],
            scanIntervalMinutes: AppSettings.dailyScanIntervalMinutes,
            maxDepth: 8
        )

        let matches = FileSystemScanner().scan(
            settings: settings,
            rule: RegexRule(name: "Build", pattern: "build/", kind: .gitignore)
        )

        XCTAssertEqual(matches.map(\.path), [build.path])
    }

    func testPersistedDefaultsIncludeUsefulTemplates() {
        let names = PersistedState.defaults.rules.map(\.name)
        XCTAssertTrue(names.contains("Node dependencies"))
        XCTAssertTrue(names.contains("Xcode DerivedData"))
    }

    func testCommonRuleTemplatesCoverDeveloperStacks() {
        let categories = Set(RuleTemplate.common.map(\.category))

        XCTAssertTrue(categories.isSuperset(of: ["Node", "Python", "Ruby", "Xcode", "Swift", "Java", "Rust", "Go", "General"]))
    }

    func testCommonRuleTemplatesAreValid() {
        for template in RuleTemplate.common {
            XCTAssertNil(RuleMatcher.validationError(for: template.rule), template.name)
        }
    }

    func testGitLikeRuleMatchesDirectoryPattern() {
        let rule = RegexRule(name: "Build", pattern: "build/", kind: .gitignore)

        XCTAssertTrue(RuleMatcher.matches(path: "/Users/me/project/build", isDirectory: true, rule: rule))
        XCTAssertFalse(RuleMatcher.matches(path: "/Users/me/project/build.log", isDirectory: false, rule: rule))
    }

    func testGitLikeRuleAcceptsMultipleDirectoryPatterns() {
        let rule = RegexRule(name: "Virtualenvs", pattern: ".venv/\nvenv/", kind: .gitignore)

        XCTAssertTrue(RuleMatcher.matches(path: "/Users/me/app/.venv", isDirectory: true, rule: rule))
        XCTAssertTrue(RuleMatcher.matches(path: "/Users/me/app/venv", isDirectory: true, rule: rule))
        XCTAssertFalse(RuleMatcher.matches(path: "/Users/me/app/venv.txt", isDirectory: false, rule: rule))
    }

    func testBackgroundHelperDefaultsToDaily() {
        XCTAssertEqual(AppSettings.defaults.scanIntervalMinutes, AppSettings.dailyScanIntervalMinutes)
    }

    func testQuickPreviewLimitDefaultsToTwentyFive() {
        XCTAssertEqual(AppSettings.defaults.previewResultLimit, 25)
    }

    func testStartButtonDefaultsToScanningOnly() {
        XCTAssertFalse(AppSettings.defaults.startButtonStartsBackup)
    }

    func testAutomaticUpdateChecksDefaultToOn() {
        XCTAssertTrue(AppSettings.defaults.automaticallyChecksForUpdates)
    }

    func testSettingsDecodeOldStateWithoutNewSettings() throws {
        let json = """
        {
          "scanRoots": ["/Users/me"],
          "backgroundScanningEnabled": true,
          "scanIntervalMinutes": 1440,
          "maxDepth": 7
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.previewResultLimit, AppSettings.defaultPreviewResultLimit)
        XCTAssertFalse(settings.startButtonStartsBackup)
        XCTAssertTrue(settings.automaticallyChecksForUpdates)
    }

    func testUpdateMenuBarIconReflectsUpdateState() {
        XCTAssertEqual(AppUpdateStatus.idle.menuBarSystemImage, "clock.arrow.circlepath")
        XCTAssertEqual(AppUpdateStatus.checking.menuBarSystemImage, "arrow.triangle.2.circlepath")
        XCTAssertEqual(AppUpdateStatus.downloading.menuBarSystemImage, "arrow.triangle.2.circlepath")
        XCTAssertEqual(AppUpdateStatus.readyToInstall.menuBarSystemImage, "arrow.down.circle.fill")
        XCTAssertEqual(AppUpdateStatus.failed.menuBarSystemImage, "clock.arrow.circlepath")
    }

    func testUpdateNotificationDedupesSameRelease() {
        XCTAssertTrue(AppUpdateNotificationPolicy.shouldNotify(version: "0.2.0", lastNotifiedVersion: nil))
        XCTAssertTrue(AppUpdateNotificationPolicy.shouldNotify(version: "0.2.1", lastNotifiedVersion: "0.2.0"))
        XCTAssertFalse(AppUpdateNotificationPolicy.shouldNotify(version: "0.2.0", lastNotifiedVersion: "0.2.0"))
    }

    func testUpdateVersionComparisonHandlesGitHubTagPrefix() {
        XCTAssertTrue(AppVersionComparator.isNewer("v0.2.0", than: "0.1.0"))
        XCTAssertTrue(AppVersionComparator.isNewer("0.2.1", than: "v0.2.0"))
        XCTAssertFalse(AppVersionComparator.isNewer("v0.1.0", than: "0.1.0"))
    }

    func testGitHubReleaseMetadataDecodesReleaseAPIShape() throws {
        let json = """
        {
          "name": "TimeMachine++ 0.2.0",
          "tag_name": "v0.2.0",
          "body": "Changes",
          "html_url": "https://github.com/execOQ/TimeMachineAdvanced/releases/tag/v0.2.0",
          "prerelease": false,
          "assets": [
            {
              "name": "TimeMachine++-0.2.0.zip",
              "content_type": "application/zip"
            }
          ]
        }
        """

        let release = try JSONDecoder().decode(GitHubReleaseMetadata.self, from: Data(json.utf8))

        XCTAssertEqual(release.displayName, "TimeMachine++ 0.2.0")
        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.assets.first?.name, "TimeMachine++-0.2.0.zip")
    }

    func testNetworkDestinationUsesMountedSparsebundleVolume() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Destinations</key>
            <array>
                <dict>
                    <key>Kind</key>
                    <string>Network</string>
                    <key>URL</key>
                    <string>smb://artem@NetStorage._smb._tcp.local./TimeMachine_Artem</string>
                    <key>Name</key>
                    <string>TimeMachine_Artem</string>
                    <key>ID</key>
                    <string>AED96266-4BB9-477A-BD2E-636BE6D03B63</string>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let diskImages = """
        image-path      : /Volumes/.timemachine/NetStorage._smb._tcp.local./2E3575C8-53AA-46D2-A807-E0E94EBF96D5/TimeMachine_Artem/MacBook Pro (Artem).sparsebundle
        /dev/disk12s1    41504653-0000-11AA-AA11-00306543ECAC    /Volumes/Backups of MacBook Pro (Artem)
        """

        let destinations = TimeMachineStateParser.destinations(
            from: CommandResult(exitCode: 0, output: plist, errorOutput: ""),
            mountOutput: "//artem@NetStorage._smb._tcp.local./TimeMachine_Artem on /Volumes/.timemachine/NetStorage._smb._tcp.local./2E3575C8-53AA-46D2-A807-E0E94EBF96D5/TimeMachine_Artem (smbfs, nobrowse)",
            diskImageOutput: diskImages
        )

        XCTAssertEqual(destinations.first?.mountPoint, "/Volumes/Backups of MacBook Pro (Artem)")
    }

    func testNetworkDestinationDoesNotUseShareMountAsSnapshotStorage() throws {
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("TimeMachinePlusPlusNetwork-\(UUID().uuidString)", isDirectory: true)
        let bundle = root.appendingPathComponent("MacBook Pro (Artem).sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let history: [String: Any] = [
            "Snapshots": [
                [
                    "com.apple.backupd.SnapshotName": "2026-05-18-183210.backup",
                    "com.apple.backupd.SnapshotCompletionDate": Date(timeIntervalSince1970: 1_779_128_730)
                ]
            ]
        ]
        let historyData = try PropertyListSerialization.data(fromPropertyList: history, format: .xml, options: 0)
        try historyData.write(to: bundle.appendingPathComponent("com.apple.TimeMachine.SnapshotHistory.plist"))

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Destinations</key>
            <array>
                <dict>
                    <key>Kind</key>
                    <string>Network</string>
                    <key>URL</key>
                    <string>smb://artem@NetStorage._smb._tcp.local./TimeMachine_Artem</string>
                    <key>Name</key>
                    <string>TimeMachine_Artem</string>
                    <key>ID</key>
                    <string>AED96266-4BB9-477A-BD2E-636BE6D03B63</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let destinations = TimeMachineStateParser.destinations(
            from: CommandResult(exitCode: 0, output: plist, errorOutput: ""),
            mountOutput: "//artem@NetStorage._smb._tcp.local/TimeMachine_Artem on \(root.path) (smbfs, nodev, nosuid, mounted by consequential)",
            diskImageOutput: ""
        )

        XCTAssertNil(destinations.first?.mountPoint)
        XCTAssertEqual(destinations.first?.shareMountPoint, root.path)
        XCTAssertEqual(
            destinations.first?.sparsebundlePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            bundle.standardizedFileURL.path
        )
        XCTAssertEqual(
            TimeMachineStateParser.sparsebundleSnapshots(sparsebundlePath: bundle.path),
            ["\(bundle.path)/2026-05-18-183210.backup"]
        )
    }

    func testBackupHistoryDetectsHostMismatch() {
        let history = TimeMachineStateParser.backupHistory(
            destinationID: "destination",
            from: CommandResult(exitCode: 2, output: "", errorOutput: "No backups found for host.")
        )

        XCTAssertTrue(history.noBackupsForCurrentHost)
        XCTAssertFalse(history.requiresFullDiskAccess)
    }

    func testLocalDestinationUsesExplicitMountPoint() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Destinations</key>
            <array>
                <dict>
                    <key>Kind</key>
                    <string>Local</string>
                    <key>ID</key>
                    <string>6B7D950C-EF65-455C-A4A0-9D6531CE320F</string>
                    <key>Name</key>
                    <string>MacBook Pro (Artem) Backups</string>
                    <key>MountPoint</key>
                    <string>/Volumes/MacBook Pro (Artem) Backups</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let destinations = TimeMachineStateParser.destinations(
            from: CommandResult(exitCode: 0, output: plist, errorOutput: ""),
            mountOutput: "com.apple.TimeMachine.2026-04-02-152252.backup@/dev/disk14s2 on /Volumes/.timemachine/29B2EE76-B698-4EA0-92DB-46CCF4327D89/2026-04-02-152252.backup (apfs)"
        )

        XCTAssertEqual(destinations.first?.mountPoint, "/Volumes/MacBook Pro (Artem) Backups")
    }

    func testMountedBackupSnapshotsMatchDestinationDevice() {
        let mountOutput = """
        /dev/disk14s2 on /Volumes/MacBook Pro (Artem) Backups (apfs, local)
        com.apple.TimeMachine.2026-04-02-152252.backup@/dev/disk14s2 on /Volumes/.timemachine/29B2EE76-B698-4EA0-92DB-46CCF4327D89/2026-04-02-152252.backup (apfs, local, read-only)
        com.apple.TimeMachine.2025-12-14-213031.backup@/dev/disk14s2 on /Volumes/.timemachine/29B2EE76-B698-4EA0-92DB-46CCF4327D89/2025-12-14-213031.backup (apfs, local, read-only)
        com.apple.TimeMachine.2026-05-18-164738.local@/dev/disk3s1 on /Volumes/com.apple.TimeMachine.localsnapshots/Backups.backupdb/MacBook Pro (Artem)/2026-05-18-164738/Macintosh HD - Data (apfs)
        """

        let snapshots = TimeMachineStateParser.mountedBackupSnapshots(
            destinationMountPoint: "/Volumes/MacBook Pro (Artem) Backups",
            mountOutput: mountOutput
        )

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots.contains("/Volumes/.timemachine/29B2EE76-B698-4EA0-92DB-46CCF4327D89/2025-12-14-213031.backup"))
        XCTAssertFalse(snapshots.contains { $0.contains("localsnapshots") })
    }

    func testMountedBackupSnapshotPathsResolveFinderVisibleNames() throws {
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("TimeMachinePlusPlusMountedBackups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("2025-12-14-213031", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("2026-04-02-152252", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = TimeMachineStateParser.mountedBackupSnapshotPaths(
            destinationMountPoint: root.path,
            backupPaths: [
                "/Volumes/.timemachine/29B2EE76-B698-4EA0-92DB-46CCF4327D89/2025-12-14-213031.backup/2025-12-14-213031.backup",
                "/Volumes/.timemachine/29B2EE76-B698-4EA0-92DB-46CCF4327D89/2026-04-02-152252.backup/2026-04-02-152252.backup"
            ]
        )

        XCTAssertEqual(
            paths,
            [
                root.appendingPathComponent("2025-12-14-213031").path,
                root.appendingPathComponent("2026-04-02-152252").path
            ]
        )
    }

    func testCommandPresentationHandlesEmptySuccessOutput() {
        let presentation = TimeMachineCommandPresentationFormatter.presentation(
            title: "Set Quota",
            arguments: ["setquota", "destination", "500"],
            result: CommandResult(exitCode: 0, output: "", errorOutput: "")
        )

        XCTAssertEqual(presentation.tone, .success)
        XCTAssertEqual(presentation.summary, "Destination quota was updated.")
        XCTAssertEqual(presentation.detail, "Exit 0. No output.")
    }

    func testCommandPresentationShowsFailureFromStandardError() {
        let presentation = TimeMachineCommandPresentationFormatter.presentation(
            title: "List Backups",
            arguments: ["listbackups"],
            result: CommandResult(exitCode: 2, output: "", errorOutput: "No backups found for host.\nTry a different destination.")
        )

        XCTAssertEqual(presentation.tone, .failure)
        XCTAssertEqual(presentation.summary, "No backups found for host.")
        XCTAssertEqual(presentation.exitCode, 2)
        XCTAssertTrue(presentation.detail.contains("Try a different destination."))
    }

    func testQuotaFailureKeepsRealTmutilError() {
        let presentation = TimeMachineCommandPresentationFormatter.presentation(
            title: "Set Quota",
            arguments: ["setquota", "destination", "500"],
            result: CommandResult(exitCode: 1, output: "", errorOutput: "Quota is not supported for this destination.")
        )

        XCTAssertEqual(presentation.tone, .failure)
        XCTAssertEqual(presentation.summary, "Quota is not supported for this destination.")
        XCTAssertFalse(presentation.summary.localizedCaseInsensitiveContains("Full Disk Access"))
    }

    func testCommandPresentationSummarizesCompareChanges() {
        let presentation = TimeMachineCommandPresentationFormatter.presentation(
            title: "Compare Selected",
            arguments: ["compare", "/Backups/One", "/Backups/Two"],
            result: CommandResult(exitCode: 0, output: "+ /Users/me/new.txt\n- /Users/me/old.txt\n! /Users/me/changed.txt", errorOutput: "")
        )

        XCTAssertEqual(presentation.tone, .success)
        XCTAssertEqual(presentation.summary, "Compared 2 paths: 1 added, 1 removed, 1 changed.")
    }

    func testCommandPresentationFallsBackToFirstDiagnosticLine() {
        let presentation = TimeMachineCommandPresentationFormatter.presentation(
            title: "tmutil Version",
            arguments: ["version"],
            result: CommandResult(exitCode: 0, output: "\n tmutil 1234\n extra details", errorOutput: "")
        )

        XCTAssertEqual(presentation.tone, .success)
        XCTAssertEqual(presentation.summary, "tmutil 1234")
        XCTAssertTrue(presentation.detail.contains("extra details"))
    }
}
