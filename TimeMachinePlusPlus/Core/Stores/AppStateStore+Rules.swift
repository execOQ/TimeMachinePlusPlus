import AppKit
import Foundation

struct RuleTemplate: Identifiable, Hashable {
    var id: String
    var name: String
    var category: String
    var description: String
    var pattern: String
    var kind: RuleKind = .gitignore
    var includeFiles = false

    var rule: RegexRule {
        RegexRule(name: name, pattern: pattern, kind: kind, includeFiles: includeFiles)
    }

    static let common: [RuleTemplate] = [
        RuleTemplate(
            id: "node-dependencies",
            name: "Node dependencies",
            category: "Node",
            description: "node_modules folders created by npm, pnpm, and Yarn.",
            pattern: "node_modules/"
        ),
        RuleTemplate(
            id: "node-build-artifacts",
            name: "Node build artifacts",
            category: "Node",
            description: "Common frontend build, cache, and coverage output.",
            pattern: ".next/\n.nuxt/\ndist/\nbuild/\nout/\ncoverage/"
        ),
        RuleTemplate(
            id: "python-environments",
            name: "Python virtualenvs",
            category: "Python",
            description: "Local virtual environments and package caches.",
            pattern: ".venv/\nvenv/\nenv/\n.tox/\n.nox/"
        ),
        RuleTemplate(
            id: "python-caches",
            name: "Python caches",
            category: "Python",
            description: "Interpreter, test, type-checker, and linter caches.",
            pattern: "__pycache__/\n.pytest_cache/\n.mypy_cache/\n.ruff_cache/\n.pyre/\n.ipynb_checkpoints/"
        ),
        RuleTemplate(
            id: "ruby-bundler",
            name: "Ruby vendor bundle",
            category: "Ruby",
            description: "Bundler-managed gems stored inside projects.",
            pattern: "vendor/bundle/\n.bundle/"
        ),
        RuleTemplate(
            id: "xcode-derived-data",
            name: "Xcode DerivedData",
            category: "Xcode",
            description: "DerivedData, indexes, and build intermediates.",
            pattern: "DerivedData/\nIndex.noindex/\nBuild/"
        ),
        RuleTemplate(
            id: "swift-packages",
            name: "Swift package builds",
            category: "Swift",
            description: "SwiftPM build products and resolved dependency checkouts.",
            pattern: ".build/\n.swiftpm/"
        ),
        RuleTemplate(
            id: "java-builds",
            name: "Java and Gradle builds",
            category: "Java",
            description: "Gradle, Maven, and JVM build output.",
            pattern: ".gradle/\nbuild/\ntarget/\nout/"
        ),
        RuleTemplate(
            id: "rust-builds",
            name: "Rust build artifacts",
            category: "Rust",
            description: "Cargo target directories and incremental build output.",
            pattern: "target/"
        ),
        RuleTemplate(
            id: "go-builds",
            name: "Go build caches",
            category: "Go",
            description: "Local Go build, test, and coverage output.",
            pattern: "bin/\npkg/\ncoverage/"
        ),
        RuleTemplate(
            id: "generated-build-directories",
            name: "Build directories",
            category: "General",
            description: "Common generated build and distribution folders.",
            pattern: "build/\n.build/\ndist/\nout/\n.tmp/\ntmp/"
        ),
        RuleTemplate(
            id: "ide-metadata",
            name: "Editor metadata",
            category: "General",
            description: "Project-local editor settings and caches.",
            pattern: ".idea/\n.vscode/\n*.xcworkspace/xcuserdata/",
            includeFiles: true
        )
    ]

    static let defaults = common.filter {
        [
            "node-dependencies",
            "python-environments",
            "xcode-derived-data",
            "ruby-bundler",
            "generated-build-directories"
        ].contains($0.id)
    }
}

extension AppStateStore {
    func addRule() {
        guard canEdit else { return }
        rules.append(RegexRule(name: "New rule", pattern: "cache/", kind: .gitignore, isEnabled: false))
        save()
    }

    func addRule(from template: RuleTemplate) {
        guard canEdit, !hasRule(from: template) else { return }
        rules.append(template.rule)
        save()
    }

    func addMissingRules(from templates: [RuleTemplate]) {
        guard canEdit else { return }
        let additions = templates.filter { !hasRule(from: $0) }.map(\.rule)
        guard !additions.isEmpty else { return }
        rules.append(contentsOf: additions)
        save()
    }

    func hasRule(from template: RuleTemplate) -> Bool {
        rules.contains { rule in
            rule.kind == template.kind &&
                normalizedPattern(rule.pattern) == normalizedPattern(template.pattern) &&
                rule.includeFiles == template.includeFiles
        }
    }

    func deleteRule(_ rule: RegexRule) {
        guard canEdit else { return }
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func addSpecificPaths(_ urls: [URL]) {
        guard canEdit else { return }
        let known = Set(rules.filter { $0.kind == .specific }.map(\.pattern))
        let additions = urls.map(\.path).filter { !known.contains($0) }
        let newRules = additions.map { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return RegexRule(name: name, pattern: path, kind: .specific, isEnabled: true, includeFiles: true)
        }
        rules.append(contentsOf: newRules)
        save()
    }

    func addScanRoots(_ urls: [URL]) {
        guard canEdit else { return }
        let known = Set(settings.scanRoots)
        settings.scanRoots.append(contentsOf: urls.map(\.path).filter { !known.contains($0) })
        save()
    }

    func deleteScanRoot(_ path: String) {
        guard canEdit else { return }
        settings.scanRoots.removeAll { $0 == path }
        save()
    }

    func setMatchSelected(_ match: ScanMatch, isSelected: Bool) {
        guard canEdit else { return }
        guard let index = matches.firstIndex(where: { $0.id == match.id }) else { return }
        matches[index].isSelected = isSelected
    }

    func previewMatches(for rule: RegexRule) async -> [RulePreviewResult] {
        guard rule.isEnabled, RuleMatcher.validationError(for: rule) == nil else { return [] }

        if rule.kind == .specific {
            let path = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return [] }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                return [
                    RulePreviewResult(
                        path: path,
                        isDirectory: false,
                        sizeBytes: nil,
                        status: .missing
                    )
                ]
            }

            let excluded = await Task.detached(priority: .userInitiated) { [timeMachine] in
                (try? timeMachine.isExcluded(path: path)) ?? false
            }.value

            return [
                RulePreviewResult(
                    path: path,
                    isDirectory: isDirectory.boolValue,
                    sizeBytes: nil,
                    status: excluded ? .excluded : .included
                )
            ]
        }

        let candidates = await Task.detached(priority: .userInitiated) { [settings, scanner] in
            scanner.scan(settings: settings, rule: rule, limit: settings.previewResultLimit)
        }.value
        return candidates.map { candidate in
            RulePreviewResult(
                path: candidate.path,
                isDirectory: candidate.isDirectory,
                sizeBytes: candidate.sizeBytes,
                status: .matched
            )
        }
    }
}

private func normalizedPattern(_ pattern: String) -> String {
    pattern
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}
