import AppKit
import Observation

/// Halo's MCP server, inside the app: listens for `Halo --mcp` bridges and
/// answers Claude's tool calls against the focused window.
@Observable @MainActor
final class MCPServer {
    static let shared = MCPServer()

    struct Client: Identifiable {
        let id: UUID
        var name: String
        let since = Date()
    }

    struct Activity: Identifiable {
        let id = UUID()
        let date = Date()
        let client: String
        let tool: String
        let summary: String
        let failed: Bool
    }

    private let defaults = UserDefaults.standard

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: MCP.Keys.enabled); enabled ? start() : stop() }
    }
    var allowEdits: Bool { didSet { defaults.set(allowEdits, forKey: MCP.Keys.allowEdits) } }
    var allowRun: Bool { didSet { defaults.set(allowRun, forKey: MCP.Keys.allowRun) } }

    private(set) var isListening = false
    private(set) var problem: String?
    private(set) var clients: [Client] = []
    private(set) var activity: [Activity] = []
    /// Tool calls in flight (the status bar shows Claude working).
    private(set) var working = 0

    @ObservationIgnored private var listener: MCPListener?
    @ObservationIgnored private var connections: [UUID: MCPConnection] = [:]

    private init() {
        enabled = defaults.bool(forKey: MCP.Keys.enabled)
        allowEdits = defaults.object(forKey: MCP.Keys.allowEdits) as? Bool ?? true
        allowRun = defaults.object(forKey: MCP.Keys.allowRun) as? Bool ?? false
    }

    var statusText: String {
        if !enabled { return "Off" }
        if let problem { return problem }
        if !isListening { return "Starting…" }
        if clients.isEmpty { return "Ready — Claude will connect when it needs Halo" }
        return "Connected to " + ListFormatter.localizedString(byJoining: Array(Set(clients.map(\.name))).sorted())
    }

    // MARK: Lifecycle

    func start() {
        guard enabled, listener == nil else { return }
        do {
            listener = try MCPListener(path: MCP.socketPath) { fd in
                DispatchQueue.main.async { MCPServer.shared.accept(fd) }
            }
            isListening = true
            problem = nil
        } catch {
            problem = error.localizedDescription
            isListening = false
        }
    }

    func stop() {
        listener?.stop()
        listener = nil
        connections.values.forEach { $0.close() }
        connections = [:]
        clients = []
        isListening = false
        problem = nil
    }

    private func accept(_ fd: Int32) {
        let id = UUID()
        let connection = MCPConnection(fd: fd,
            onLine: { line in DispatchQueue.main.async { MCPServer.shared.received(line, from: id) } },
            onClose: { DispatchQueue.main.async { MCPServer.shared.closed(id) } })
        guard isListening else { connection.close(); return }
        connections[id] = connection
        clients.append(Client(id: id, name: "Claude"))
    }

    private func closed(_ id: UUID) {
        connections[id] = nil
        clients.removeAll { $0.id == id }
    }

    // MARK: Messages

    private func send(_ message: [String: Any], to id: UUID) {
        guard let data = MCP.encode(message) else { return }
        connections[id]?.send(data)
    }

    private func received(_ line: Data, from id: UUID) {
        guard connections[id] != nil else { return }
        guard let message = MCP.decode(line) else {
            send(MCP.error(id: NSNull(), code: -32700, message: "Parse error"), to: id)
            return
        }
        let requestID = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        switch message["method"] as? String {
        case "halo/hello":
            rename(id, to: MCP.clientName(params["clientInfo"] as? [String: Any]))
        case "initialize":   // a client talking to the socket directly
            rename(id, to: MCP.clientName(params["clientInfo"] as? [String: Any]))
            if let requestID { send(MCP.response(id: requestID, result: MCP.initializeResult(requested: params["protocolVersion"] as? String)), to: id) }
        case "ping":
            if let requestID { send(MCP.response(id: requestID, result: [:]), to: id) }
        case "tools/list":
            if let requestID { send(MCP.response(id: requestID, result: ["tools": MCP.toolDefinitions]), to: id) }
        case "tools/call":
            guard let requestID else { return }
            let name = params["name"] as? String ?? ""
            guard let tool = MCP.tool(named: name) else {
                send(MCP.error(id: requestID, code: -32602, message: "Unknown tool: \(name)"), to: id)
                return
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let client = clients.first { $0.id == id }?.name ?? "Claude"
            Task { await call(tool, arguments: arguments, client: client, requestID: requestID, connection: id) }
        case let method?:
            if let requestID { send(MCP.error(id: requestID, code: -32601, message: "Method not found: \(method)"), to: id) }
        case nil:
            break
        }
    }

    private func rename(_ id: UUID, to name: String) {
        guard let i = clients.firstIndex(where: { $0.id == id }) else { return }
        clients[i].name = name
    }

    private func call(_ tool: MCP.Tool, arguments: [String: Any], client: String, requestID: Any, connection: UUID) async {
        working += 1
        let outcome: MCPTools.Outcome
        switch tool.access {
        case .edit where !allowEdits:
            outcome = .failure("Editing is turned off. The user can allow it in Halo → Settings → Claude → “Edit files”.")
        case .run where !allowRun:
            outcome = .failure("Running code is turned off. The user can allow it in Halo → Settings → Claude → “Run code and commands”.")
        default:
            outcome = await MCPTools.run(tool.name, arguments: arguments, client: client)
        }
        working -= 1
        activity.insert(Activity(client: client, tool: tool.title, summary: outcome.summary, failed: outcome.isError), at: 0)
        if activity.count > 40 { activity.removeLast(activity.count - 40) }
        send(MCP.response(id: requestID, result: MCP.toolResult(outcome.text, isError: outcome.isError)), to: connection)
    }

    func clearActivity() { activity = [] }
}
