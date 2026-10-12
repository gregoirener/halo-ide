import Foundation

/// What both halves of Halo's MCP server share: the app, which owns the editor
/// and answers tool calls, and `Halo --mcp`, the stdio bridge Claude launches.
///
/// Claude ──stdio──▶ Halo --mcp ──unix socket──▶ Halo.app
enum MCP {
    static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let serverName = "halo"
    static let bridgeFlag = "--mcp"

    enum Keys {
        static let enabled = "mcpEnabled"
        static let allowEdits = "mcpAllowEdits"
        static let allowRun = "mcpAllowRun"
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Where the running app listens. Keyed by bundle id so a dev copy and the
    /// installed app never answer for each other.
    static var socketPath: String {
        let id = Bundle.main.bundleIdentifier ?? "dev.halo.editor"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let path = support.appendingPathComponent("Halo/\(id).mcp.sock").path
        // sockaddr_un holds 104 bytes; very long home folders fall back to the per-user temp folder.
        if path.utf8.count < 100 { return path }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("\(id).mcp.sock")
    }

    /// Read from the shared defaults domain, so the bridge sees what the app's Settings say.
    static var accessEnabled: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        return UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    static let accessOffMessage = "Claude access is turned off in Halo. The user can turn it on in Halo → Settings → Claude → “Allow Claude to connect”."

    static let instructions = """
    Halo is the code editor the user has open on this Mac. These tools work on the project folder open in Halo; \
    relative paths are relative to it. read_file returns the text in Halo's editor, unsaved changes included. \
    edit_file and write_file go through the editor, so the user sees each change and can undo it with ⌘Z; \
    files are saved afterwards. Start with get_editor_state to see what the user is looking at.
    """

    static func initializeResult(requested: String?) -> [String: Any] {
        let version = requested.flatMap { protocolVersions.contains($0) ? $0 : nil } ?? protocolVersions[0]
        return [
            "protocolVersion": version,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": serverName, "title": "Halo", "version": appVersion],
            "instructions": instructions,
        ]
    }

    /// A readable name for the app on the other end.
    static func clientName(_ info: [String: Any]?) -> String {
        let raw = (info?["title"] as? String) ?? (info?["name"] as? String) ?? ""
        switch raw.lowercased() {
        case "claude-ai", "claude", "claude desktop": return "Claude Desktop"
        case "claude-code", "claude code": return "Claude Code"
        case "": return "Claude"
        default: return raw
        }
    }

    // MARK: JSON-RPC over newline-delimited JSON

    static func encode(_ message: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(message),
              var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return nil }
        data.append(0x0A)
        return data
    }

    static func decode(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    static func response(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func notification(_ method: String, params: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "method": method, "params": params]
    }

    static func toolResult(_ text: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    /// A stable key for a request id (number or string) to match responses.
    static func key(for id: Any) -> String {
        if let s = id as? String { return "s:" + s }
        if let n = id as? NSNumber { return "n:" + n.stringValue }
        return "?:\(id)"
    }

    // MARK: Tools

    enum Access { case read, edit, run }

    struct Tool {
        let name: String
        let title: String
        let description: String
        let access: Access
        var properties: [String: [String: Any]] = [:]
        var required: [String] = []

        var definition: [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return [
                "name": name,
                "title": title,
                "description": description,
                "inputSchema": schema,
                "annotations": [
                    "title": title,
                    "readOnlyHint": access == .read,
                    "destructiveHint": name == "write_file" || name == "run_command",
                    "idempotentHint": access == .read,
                    "openWorldHint": access == .run,
                ],
            ]
        }
    }

    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func integer(_ description: String) -> [String: Any] { ["type": "integer", "description": description] }
    private static func boolean(_ description: String) -> [String: Any] { ["type": "boolean", "description": description] }

    static let tools: [Tool] = [
        Tool(name: "get_editor_state", title: "Get editor state",
             description: "What the user is looking at in Halo: the open project folder, the open tabs (and which have unsaved changes), the active file, the caret position and the selected text.",
             access: .read),
        Tool(name: "list_files", title: "List project files",
             description: "List the files in the project (skips .git, node_modules, build output and the like). Narrow it with a folder and/or a glob such as \"*.py\" or \"src/*.ts\".",
             access: .read,
             properties: ["path": string("Folder to list, relative to the project root"),
                          "pattern": string("Glob matched against relative paths, e.g. *.swift or tests/*"),
                          "limit": integer("Most files to return (default 500)")]),
        Tool(name: "read_file", title: "Read file",
             description: "Read a file from the project with line numbers. Returns the text as Halo's editor has it, including unsaved changes. Use start_line and end_line for big files.",
             access: .read,
             properties: ["path": string("File path, relative to the project root"),
                          "start_line": integer("First line to return (1-based)"),
                          "end_line": integer("Last line to return")],
             required: ["path"]),
        Tool(name: "search", title: "Search project",
             description: "Search the project's files for text or a regular expression. Returns matches as path:line: text.",
             access: .read,
             properties: ["query": string("Text or regular expression to find"),
                          "regex": boolean("Treat query as a regular expression"),
                          "case_sensitive": boolean("Match case"),
                          "limit": integer("Most matches to return (default 100)")],
             required: ["query"]),
        Tool(name: "get_diagnostics", title: "Get problems",
             description: "The errors and warnings Halo shows (live syntax checks of open files and the last build), for one file or the whole project.",
             access: .read,
             properties: ["path": string("Only this file (relative path)")]),
        Tool(name: "git_status", title: "Git status",
             description: "The project's git branch and changed files. Set diff to include the staged and unstaged diff, optionally for one path.",
             access: .read,
             properties: ["diff": boolean("Include the diff"),
                          "path": string("Limit the diff to this path")]),
        Tool(name: "get_terminal_output", title: "Read terminal",
             description: "The last lines shown in Halo's integrated terminal, e.g. after the user ran something there.",
             access: .read,
             properties: ["lines": integer("How many lines (default 80)")]),
        Tool(name: "open_file", title: "Open file in Halo",
             description: "Show a file to the user in Halo's editor, optionally at a line or selecting a range of lines.",
             access: .read,
             properties: ["path": string("File path, relative to the project root"),
                          "line": integer("Line to show"),
                          "end_line": integer("Select from line through end_line")],
             required: ["path"]),
        Tool(name: "edit_file", title: "Edit file",
             description: "Replace exact text in a file, through Halo's editor. old_string must match exactly once (include surrounding lines to make it unique) unless replace_all is set. The user sees the change, can undo it with ⌘Z, and the file is saved.",
             access: .edit,
             properties: ["path": string("File path, relative to the project root"),
                          "old_string": string("The exact text to replace"),
                          "new_string": string("The text to put in its place"),
                          "replace_all": boolean("Replace every occurrence")],
             required: ["path", "old_string", "new_string"]),
        Tool(name: "write_file", title: "Write file",
             description: "Create a file, or replace a file's whole contents, through Halo's editor. Missing folders are created. The file opens in Halo and is saved; replacing an existing file can be undone with ⌘Z.",
             access: .edit,
             properties: ["path": string("File path, relative to the project root"),
                          "content": string("The complete new contents")],
             required: ["path", "content"]),
        Tool(name: "run_command", title: "Run command",
             description: "Run a shell command in the project folder (your login shell) and return its output and exit code. Not interactive: input is empty. For tests, builds, package managers, scripts.",
             access: .run,
             properties: ["command": string("The shell command line"),
                          "cwd": string("Folder to run in, relative to the project root"),
                          "timeout_seconds": integer("Stop it after this many seconds (default 60, at most 600)")],
             required: ["command"]),
        Tool(name: "run_file", title: "Run file",
             description: "Run a file the way Halo's Run button does (building it first for compiled languages) and return the output. Defaults to the file the user has open.",
             access: .run,
             properties: ["path": string("File to run, relative to the project root"),
                          "stdin": string("Text to send to the program's input"),
                          "timeout_seconds": integer("Stop it after this many seconds (default 60, at most 600)")]),
    ]

    static func tool(named name: String) -> Tool? { tools.first { $0.name == name } }
    static var toolDefinitions: [[String: Any]] { tools.map(\.definition) }
}
