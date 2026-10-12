import AppKit
import Observation

/// Adds Halo to Claude Desktop and Claude Code (and takes it out again).
@Observable @MainActor
final class ClaudeConnections {
    static let shared = ClaudeConnections()

    enum State: Equatable {
        case checking, notInstalled, notConnected, connected
        /// Set up for another copy of Halo (e.g. one that was moved).
        case otherCopy
    }

    static let desktopBundleID = "com.anthropic.claudefordesktop"

    private(set) var desktop: State = .checking
    private(set) var code: State = .checking
    private(set) var codeCLI: String?
    /// Claude Desktop was running when we changed its config: it needs a restart.
    private(set) var desktopNeedsRestart = false
    private(set) var busy = false
    var message: String?

    private init() {}

    // MARK: What Claude launches

    var command: String { Bundle.main.executableURL?.path ?? "/Applications/Halo.app/Contents/MacOS/Halo" }
    var arguments: [String] { [MCP.bridgeFlag] }

    /// Claude needs a path that stays put: not the disk image, not a translocated copy.
    var locationProblem: String? {
        if command.hasPrefix("/Volumes/") { return "Halo is running from the disk image. Drag it to Applications, open it from there, then connect." }
        if command.contains("/AppTranslocation/") { return "macOS is running Halo from a temporary location. Move Halo to Applications, open it from there, then connect." }
        return nil
    }

    var configJSON: String {
        let entry: [String: Any] = ["mcpServers": [MCP.serverName: ["command": command, "args": arguments]]]
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    var codeCommand: String {
        "claude mcp add --scope user \(MCP.serverName) -- \(Runner.q(command)) \(arguments.joined(separator: " "))"
    }

    // MARK: Status

    private var desktopConfigURL: URL {
        if let path = ProcessInfo.processInfo.environment["HALO_CLAUDE_DESKTOP_CONFIG"] { return URL(fileURLWithPath: path) }   // tests
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    private var desktopAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.desktopBundleID)
    }

    var desktopIcon: NSImage? { desktopAppURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }

    var isDesktopRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.desktopBundleID).isEmpty
    }

    func refresh() {
        desktop = desktopState()
        let home = NSHomeDirectory()
        codeCLI = Tools.find("claude") ?? ["\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        code = codeCLI == nil ? .notInstalled : codeState()
    }

    private func entryState(_ entry: [String: Any]?) -> State {
        guard let entry else { return .notConnected }
        return entry["command"] as? String == command ? .connected : .otherCopy
    }

    private func desktopState() -> State {
        let config = readJSON(desktopConfigURL)
        let entry = (config?["mcpServers"] as? [String: Any])?[MCP.serverName] as? [String: Any]
        if desktopAppURL == nil && entry == nil { return .notInstalled }
        return entryState(entry)
    }

    /// Claude Code keeps user-scoped servers in ~/.claude.json.
    private func codeState() -> State {
        let config = readJSON(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"))
        return entryState((config?["mcpServers"] as? [String: Any])?[MCP.serverName] as? [String: Any])
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Claude Desktop

    func connectDesktop() { updateDesktop(adding: true) }
    func disconnectDesktop() { updateDesktop(adding: false) }

    private func updateDesktop(adding: Bool) {
        message = nil
        let url = desktopConfigURL
        var config: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let parsed = readJSON(url) else {
                message = "Claude’s settings file isn’t valid JSON, so Halo left it alone. Use “Copy Setup” and add Halo by hand."
                return
            }
            config = parsed
            // Keep the user's original once, before Halo first touches it.
            let backup = url.appendingPathExtension("before-halo")
            if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: url, to: backup) }
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        if adding {
            servers[MCP.serverName] = ["command": command, "args": arguments]
        } else {
            servers[MCP.serverName] = nil
        }
        config["mcpServers"] = servers
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
        } catch {
            message = "Couldn’t update Claude’s settings: \(error.localizedDescription)"
            return
        }
        desktopNeedsRestart = isDesktopRunning
        if adding, !MCPServer.shared.enabled { MCPServer.shared.enabled = true }
        refresh()
    }

    /// Quits Claude Desktop and opens it again so it picks up the change.
    func restartDesktop() {
        guard let appURL = desktopAppURL else { return }
        busy = true
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.desktopBundleID)
        running.forEach { $0.terminate() }
        Task {
            for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(200))
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            busy = false
            desktopNeedsRestart = false
        }
    }

    // MARK: Claude Code

    func connectCode() {
        guard let cli = codeCLI else { return }
        let argv = [cli, "mcp", "add", "--scope", "user", MCP.serverName, "--", command] + arguments
        let replacing = code == .otherCopy
        runCLI { () -> (Int32, String) in
            if replacing { Shell.run([cli, "mcp", "remove", "--scope", "user", MCP.serverName], timeout: 30) }
            return Shell.run(argv, timeout: 30)
        } then: { ok, output in
            if ok, !MCPServer.shared.enabled { MCPServer.shared.enabled = true }
            if !ok { self.message = "Claude Code couldn’t add Halo: " + output }
        }
    }

    func disconnectCode() {
        guard let cli = codeCLI else { return }
        runCLI { Shell.run([cli, "mcp", "remove", "--scope", "user", MCP.serverName], timeout: 30) } then: { ok, output in
            if !ok { self.message = "Claude Code couldn’t remove Halo: " + output }
        }
    }

    private func runCLI(_ work: @escaping @Sendable () -> (Int32, String), then done: @escaping @MainActor (Bool, String) -> Void) {
        message = nil
        busy = true
        Task {
            let (status, output) = await Task.detached(operation: work).value
            busy = false
            done(status == 0, output.trimmingCharacters(in: .whitespacesAndNewlines))
            refresh()
        }
    }

    // MARK: Anything else

    func copyConfig() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configJSON, forType: .string)
    }

    func copyCodeCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(codeCommand, forType: .string)
    }
}
