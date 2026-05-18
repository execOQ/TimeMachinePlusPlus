import Foundation

struct LaunchAgentService {
    var label = "com.timemachineplusplus.scan"

    var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func install(intervalMinutes: Int) throws {
        let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let launchAgents = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)

        let seconds = max(5, intervalMinutes) * 60
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executable)</string>
                <string>--background-scan</string>
            </array>
            <key>StartInterval</key>
            <integer>\(seconds)</integer>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """

        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        _ = try? runLaunchctl(arguments: ["unload", plistURL.path])
        _ = try runLaunchctl(arguments: ["load", plistURL.path])
    }

    func uninstall() throws {
        _ = try? runLaunchctl(arguments: ["unload", plistURL.path])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private func runLaunchctl(arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
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
}
