import Foundation

struct CommandResult: Equatable {
    var exitCode: Int32
    var output: String
    var errorOutput: String

    var isSuccess: Bool { exitCode == 0 }
}

protocol TimeMachineClient {
    func addExclusion(path: String) throws -> CommandResult
    func removeExclusion(path: String) throws -> CommandResult
    func isExcluded(path: String) throws -> Bool
    func startBackup() throws -> CommandResult
    func stopBackup() throws -> CommandResult
    func run(arguments: [String], asAdministrator: Bool) throws -> CommandResult
}

struct LiveTimeMachineClient: TimeMachineClient {
    func addExclusion(path: String) throws -> CommandResult {
        try runTmutil(arguments: ["addexclusion", path])
    }

    func removeExclusion(path: String) throws -> CommandResult {
        try runTmutil(arguments: ["removeexclusion", path])
    }

    func isExcluded(path: String) throws -> Bool {
        let result = try runTmutil(arguments: ["isexcluded", path])
        let text = result.output + result.errorOutput
        if text.contains("[Excluded]") { return true }
        if text.contains("[Included]") { return false }
        return false
    }

    func startBackup() throws -> CommandResult {
        try runTmutil(arguments: ["startbackup", "--auto"])
    }

    func stopBackup() throws -> CommandResult {
        try runTmutil(arguments: ["stopbackup"])
    }

    func run(arguments: [String], asAdministrator: Bool = false) throws -> CommandResult {
        if asAdministrator {
            try runAdministratorTmutil(arguments: arguments)
        } else {
            try runTmutil(arguments: arguments)
        }
    }

    private func runTmutil(arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output, errorOutput: errorOutput)
    }

    private func runAdministratorTmutil(arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptString(shellCommand(arguments: arguments))) with administrator privileges"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output, errorOutput: errorOutput)
    }

    private func shellCommand(arguments: [String]) -> String {
        (["/usr/bin/tmutil"] + arguments).map(quoteForShell).joined(separator: " ")
    }

    private func quoteForShell(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-./:=,@%")
        if value.rangeOfCharacter(from: safeCharacters.inverted) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
