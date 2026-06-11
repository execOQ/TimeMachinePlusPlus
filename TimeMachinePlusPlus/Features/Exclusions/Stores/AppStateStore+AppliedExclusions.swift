import Foundation

extension AppStateStore {
    func removeApplied(_ exclusion: AppliedExclusion) async {
        guard canEdit else { return }
        let result = await removeExclusionFromTimeMachine(exclusion)

        switch result {
        case .success(let commandResult) where commandResult.isSuccess:
            removeAppliedExclusionFromState(exclusion)
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
            let result = await removeExclusionFromTimeMachine(exclusion)

            switch result {
            case .success(let commandResult) where commandResult.isSuccess:
                removedIDs.insert(exclusion.id)
                markMatchAsIncluded(path: exclusion.path)
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
    func removeExclusionFromTimeMachine(_ exclusion: AppliedExclusion) async -> Result<CommandResult, Error> {
        await Task.detached(priority: .userInitiated) { [timeMachine] in
            Result { try timeMachine.removeExclusion(path: exclusion.path) }
        }.value
    }

    func removeAppliedExclusionFromState(_ exclusion: AppliedExclusion) {
        appliedExclusions.removeAll { $0.id == exclusion.id }
        markMatchAsIncluded(path: exclusion.path)
    }

    func markMatchAsIncluded(path: String) {
        guard let index = matches.firstIndex(where: { $0.path == path }) else { return }
        matches[index].isExcluded = false
        matches[index].isSelected = true
    }
}
