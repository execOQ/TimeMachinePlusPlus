import Foundation

final class ProcessRegistry {
    static let shared = ProcessRegistry()
    private var processes: [ObjectIdentifier: Process] = [:]
    private let lock = NSLock()

    private init() {}

    func register(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        lock.unlock()
    }

    func deregister(_ process: Process) {
        lock.lock()
        processes.removeValue(forKey: ObjectIdentifier(process))
        lock.unlock()
    }

    func terminateAll() {
        lock.lock()
        let snapshot = Array(processes.values)
        lock.unlock()
        snapshot.forEach { $0.terminate() }
    }

    func terminateMatching(_ predicate: (Process) -> Bool) {
        lock.lock()
        let snapshot = Array(processes.values)
        lock.unlock()
        snapshot.filter(predicate).forEach { $0.terminate() }
    }
}

struct CommandResult: Equatable, Sendable {
    var exitCode: Int32
    var output: String
    var errorOutput: String

    var isSuccess: Bool { exitCode == 0 }
}

protocol TimeMachineClient {
    func addExclusion(path: String) throws -> CommandResult
    func removeExclusion(path: String) throws -> CommandResult
    func isExcluded(path: String) throws -> Bool
}

struct LiveTimeMachineClient: TimeMachineClient {
    private let commandTimeoutSeconds: TimeInterval = 30

    func addExclusion(path: String) throws -> CommandResult {
        // xattr form only: -p requires admin and prompts for a password, which is too disruptive.
        // Time Machine fully respects xattr exclusions; they just don't appear in System Settings.
        try runTmutil(arguments: ["addexclusion", path])
    }

    func removeExclusion(path: String) throws -> CommandResult {
        let xattr = try? runTmutil(arguments: ["removeexclusion", path])
        let pathBased = try? runTmutil(arguments: ["removeexclusion", "-p", path])
        // Succeed if either form was removed; both may fail if exclusion was already gone
        let didRemove = (xattr?.isSuccess ?? false) || (pathBased?.isSuccess ?? false)
        return CommandResult(exitCode: didRemove ? 0 : 1, output: "", errorOutput: "")
    }

    func isExcluded(path: String) throws -> Bool {
        let result = try runTmutil(arguments: ["isexcluded", path])
        let text = result.output + result.errorOutput
        if text.contains("[Excluded]") { return true }
        if text.contains("[Included]") { return false }
        return false
    }

    private func runTmutil(arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        ProcessRegistry.shared.register(process)
        try process.run()
        waitForProcess(process, timeout: commandTimeoutSeconds)
        ProcessRegistry.shared.deregister(process)

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output, errorOutput: errorOutput)
    }

    private func waitForProcess(_ process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
        }

        if process.isRunning {
            process.interrupt()
        }

        process.waitUntilExit()
    }
}
