import AppKit
import Foundation

extension AppStateStore {
    func addRule() {
        guard canEdit else { return }
        rules.append(RegexRule(name: "New rule", pattern: "cache/", kind: .gitignore, isEnabled: false))
        save()
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
