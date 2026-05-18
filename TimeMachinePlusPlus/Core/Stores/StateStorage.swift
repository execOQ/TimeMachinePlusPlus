import Foundation

struct StateStorage {
    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeMachinePlusPlus", isDirectory: true)
        return base.appendingPathComponent("state.json")
    }

    func load() -> PersistedState {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            return .defaults
        }
    }

    func save(_ state: PersistedState) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("TimeMachine++ failed to save state: \(error.localizedDescription)")
        }
    }
}
