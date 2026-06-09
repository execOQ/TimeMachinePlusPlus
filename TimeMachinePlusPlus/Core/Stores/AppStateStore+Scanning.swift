import AppKit
import Foundation

extension AppStateStore {
    private static let exclusionStatusConcurrencyLimit = 6

    func scanNow() async {
        updateOperation(detail: "Scanning rules", progress: isCombinedStartOperation ? 0.12 : nil)

        let validRules = rules.filter { RuleMatcher.validationIssue(for: $0) == nil }
        let pathRules = validRules.filter { $0.kind == .path && $0.isEnabled && !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        updateOperation(detail: "Searching scan roots", progress: isCombinedStartOperation ? 0.20 : nil)
        let scanned = await Task.detached(priority: .userInitiated) { [settings, scanner] in
            scanner.scan(settings: settings, rules: validRules)
        }.value
        guard !Task.isCancelled else { return }

        updateOperation(detail: "Collecting path rules", progress: isCombinedStartOperation ? 0.34 : nil)
        // Collect path rules that exist on disk and aren't already in scanned results.
        let scannedPaths = Set(scanned.map(\.0.path))
        let pathCandidates: [(path: String, rule: RegexRule, isDirectory: Bool)] = pathRules.compactMap { rule in
            let path = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !scannedPaths.contains(path), FileManager.default.fileExists(atPath: path) else { return nil }
            let isDir = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return (path, rule, isDir)
        }
        guard !Task.isCancelled else { return }

        updateOperation(detail: "Checking Time Machine status", progress: isCombinedStartOperation ? 0.48 : nil)
        // Check exclusion status with bounded fan-out so large scans do not spawn a tmutil process storm.
        let allPaths = scanned.map(\.0.path) + pathCandidates.map(\.path)
        let exclusionStatuses = await Task.detached(priority: .userInitiated) { [timeMachine] in
            await Self.exclusionStatuses(
                for: allPaths,
                timeMachine: timeMachine,
                concurrencyLimit: Self.exclusionStatusConcurrencyLimit
            )
        }.value
        guard !Task.isCancelled else { return }

        var nextMatches: [ScanMatch] = []

        for (candidate, rule) in scanned {
            let excluded = exclusionStatuses[candidate.path] ?? false
            nextMatches.append(
                ScanMatch(
                    path: candidate.path,
                    source: .rule(rule.name),
                    isDirectory: candidate.isDirectory,
                    isExcluded: excluded,
                    sizeBytes: candidate.sizeBytes,
                    isSelected: !excluded
                )
            )
        }

        for item in pathCandidates {
            let excluded = exclusionStatuses[item.path] ?? false
            nextMatches.append(
                ScanMatch(
                    path: item.path,
                    source: .rule(item.rule.name),
                    isDirectory: item.isDirectory,
                    isExcluded: excluded,
                    sizeBytes: nil,
                    isSelected: !excluded
                )
            )
        }

        matches = nextMatches.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        lastScanDate = Date()
        statusMessage = "Found \(matches.count) candidate exclusions"
        rulesStatusMessage = statusMessage
        if isCombinedStartOperation {
            updateOperation(detail: "Found \(matches.count) candidate exclusions", progress: 0.58)
        }
    }

    @discardableResult
    func applySelectedMatches(refreshAfterApply: Bool = true) async -> Int {
        let targets = matches.filter { $0.isSelected && !$0.isExcluded }
        guard !targets.isEmpty else {
            statusMessage = "Nothing new to exclude"
            rulesStatusMessage = statusMessage
            if isCombinedStartOperation {
                updateOperation(detail: "No new exclusions to apply", progress: 0.72)
            }
            return 0
        }

        var applied = 0
        var failures: [String] = []
        let progressUpdateStride = max(1, targets.count / 20)

        for (offset, target) in targets.enumerated() {
            guard !Task.isCancelled else {
                statusMessage = "Cancelled after applying \(applied) exclusions"
                rulesStatusMessage = statusMessage
                save()
                return applied
            }

            if isCombinedStartOperation, offset == 0 || offset == targets.count - 1 || offset.isMultiple(of: progressUpdateStride) {
                let fraction = Double(offset) / Double(max(targets.count, 1))
                updateOperation(
                    detail: "Applying exclusion \(offset + 1) of \(targets.count)",
                    progress: 0.60 + min(fraction, 1) * 0.28
                )
            }

            let result = await Task.detached(priority: .userInitiated) { [timeMachine] in
                Result { try timeMachine.addExclusion(path: target.path) }
            }.value

            switch result {
            case .success(let commandResult) where commandResult.isSuccess:
                applied += 1
                appliedExclusions.removeAll { $0.path == target.path }
                appliedExclusions.append(
                    AppliedExclusion(path: target.path, sourceDescription: target.source.label)
                )
            default:
                failures.append(target.path)
            }
        }

        save()
        statusMessage = failures.isEmpty
            ? "Applied \(applied) exclusions"
            : "Applied \(applied), failed \(failures.count)."
        rulesStatusMessage = statusMessage
        if isCombinedStartOperation {
            updateOperation(detail: "Applied \(applied) exclusions", progress: 0.88)
        } else if refreshAfterApply {
            await scanNow()
        }
        return applied
    }

    func removeApplied(_ exclusion: AppliedExclusion) async {
        guard canEdit else { return }
        let result = await Task.detached(priority: .userInitiated) { [timeMachine] in
            Result { try timeMachine.removeExclusion(path: exclusion.path) }
        }.value
        switch result {
        case .success(let commandResult) where commandResult.isSuccess:
            appliedExclusions.removeAll { $0.id == exclusion.id }
            if let index = matches.firstIndex(where: { $0.path == exclusion.path }) {
                matches[index].isExcluded = false
                matches[index].isSelected = true
            }
            statusMessage = "Removed exclusion"
            rulesStatusMessage = statusMessage
            save()
        case .success:
            statusMessage = "Could not remove exclusion"
            rulesStatusMessage = statusMessage
        case .failure(let error):
            statusMessage = "Could not remove exclusion: \(error.localizedDescription)"
            rulesStatusMessage = statusMessage
        }
    }

    func removeApplied(_ exclusions: [AppliedExclusion]) async {
        guard canEdit else { return }
        let targets = exclusions.filter { target in
            appliedExclusions.contains { $0.id == target.id }
        }
        guard !targets.isEmpty else {
            statusMessage = "No exclusions selected"
            rulesStatusMessage = statusMessage
            return
        }

        var removedIDs = Set<UUID>()
        var failed = 0

        for exclusion in targets {
            let result = await Task.detached(priority: .userInitiated) { [timeMachine] in
                Result { try timeMachine.removeExclusion(path: exclusion.path) }
            }.value

            switch result {
            case .success(let commandResult) where commandResult.isSuccess:
                removedIDs.insert(exclusion.id)
                if let index = matches.firstIndex(where: { $0.path == exclusion.path }) {
                    matches[index].isExcluded = false
                    matches[index].isSelected = true
                }
            default:
                failed += 1
            }
        }

        if !removedIDs.isEmpty {
            appliedExclusions.removeAll { removedIDs.contains($0.id) }
            save()
        }

        statusMessage = failed == 0
            ? "Removed \(removedIDs.count) exclusions"
            : "Removed \(removedIDs.count), failed \(failed)"
        rulesStatusMessage = statusMessage
    }

}

private extension AppStateStore {
    static func exclusionStatuses(
        for paths: [String],
        timeMachine: TimeMachineClient,
        concurrencyLimit: Int
    ) async -> [String: Bool] {
        guard !paths.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, Bool).self) { group in
            let limit = min(max(concurrencyLimit, 1), paths.count)
            var nextIndex = 0
            var statuses: [String: Bool] = [:]

            func enqueueNext() {
                guard nextIndex < paths.count else { return }
                let path = paths[nextIndex]
                nextIndex += 1
                group.addTask {
                    let excluded = (try? timeMachine.isExcluded(path: path)) ?? false
                    return (path, excluded)
                }
            }

            for _ in 0..<limit {
                enqueueNext()
            }

            while let (path, excluded) = await group.next() {
                statuses[path] = excluded
                enqueueNext()
            }

            return statuses
        }
    }
}
