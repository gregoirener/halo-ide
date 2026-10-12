import Foundation

/// `Halo --mcp`: the command Claude launches. It speaks MCP over stdio and
/// relays tool calls to the running app over a Unix socket.
///
/// It answers the handshake and the tool list itself, so Claude starting up
/// never opens Halo; the first tool call opens Halo if it isn't running. If
/// Halo quits mid-session, the next call reconnects (and reopens it).
enum MCPBridge {
    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let bridge = Bridge(socketPath: MCP.socketPath)
        bridge.connect(launching: false)      // be listed as connected if Halo is already open
        while let line = readLine(strippingNewline: true) {
            if !line.isEmpty { bridge.handle(line) }
        }
        exit(0)
    }
}

private final class Bridge: @unchecked Sendable {
    private let socketPath: String
    private let lock = NSLock()
    private let outputLock = NSLock()
    private var fd: Int32 = -1
    private var generation = 0                     // bumps per connection, so a stale reader can't touch a new one
    private var pending: [String: Any] = [:]      // request key → id, for calls Halo hasn't answered yet
    private var clientInfo: [String: Any]?
    private var protocolVersion: String?

    init(socketPath: String) { self.socketPath = socketPath }

    // MARK: From Claude

    func handle(_ line: String) {
        guard let message = MCP.decode(Data(line.utf8)) else {
            write(MCP.error(id: NSNull(), code: -32700, message: "Parse error"))
            return
        }
        let id = message["id"]
        guard let method = message["method"] as? String else { return }   // a response; we send no requests
        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any]
            lock.withLock {
                clientInfo = params?["clientInfo"] as? [String: Any]
                protocolVersion = params?["protocolVersion"] as? String
            }
            if let id { write(MCP.response(id: id, result: MCP.initializeResult(requested: protocolVersion))) }
            sendHello()
        case "ping":
            if let id { write(MCP.response(id: id, result: [:])) }
        case "tools/list":
            if let id { write(MCP.response(id: id, result: ["tools": MCP.toolDefinitions])) }
        case "tools/call":
            guard let id else { return }
            forward(line, id: id)
        default:
            // Notifications (initialized, cancelled…) need no answer.
            if let id { write(MCP.error(id: id, code: -32601, message: "Method not found: \(method)")) }
        }
    }

    private func forward(_ line: String, id: Any) {
        guard connect(launching: true) else {
            let message = MCP.accessEnabled
                ? "Halo didn’t respond. Ask the user to open Halo, then try again."
                : MCP.accessOffMessage
            write(MCP.response(id: id, result: MCP.toolResult(message, isError: true)))
            return
        }
        let key = MCP.key(for: id)
        lock.withLock { pending[key] = id }
        var data = Data(line.utf8)
        data.append(0x0A)
        if send(data) { return }
        // Halo went away since the last call. Unless the reader already answered
        // this call as failed, reconnect once and resend.
        guard lock.withLock({ pending.removeValue(forKey: key) != nil }) else { return }
        drop(generation: lock.withLock { generation })
        lock.withLock { pending[key] = id }
        if connect(launching: true), send(data) { return }
        guard lock.withLock({ pending.removeValue(forKey: key) != nil }) else { return }
        write(MCP.response(id: id, result: MCP.toolResult("Lost the connection to Halo. Try again.", isError: true)))
    }

    // MARK: To Halo

    private func currentSocket() -> Int32 { lock.withLock { fd } }

    private func send(_ data: Data) -> Bool {
        let socket = currentSocket()
        return socket >= 0 && UnixSocket.write(socket, data)
    }

    /// Connects to the app, opening it in the background first if allowed and needed.
    @discardableResult
    func connect(launching: Bool) -> Bool {
        if currentSocket() >= 0 { return true }
        if let socket = UnixSocket.connect(socketPath) { attach(socket); return true }
        guard launching, MCP.accessEnabled else { return false }
        launchHalo()
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            usleep(200_000)
            if let socket = UnixSocket.connect(socketPath) { attach(socket); return true }
        }
        return false
    }

    private func launchHalo() {
        // This executable lives in Halo.app/Contents/MacOS: open that copy, without stealing focus.
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", bundle.path]
        try? open.run()
        open.waitUntilExit()
    }

    private func attach(_ socket: Int32) {
        let current = lock.withLock { () -> Int in
            fd = socket
            generation += 1
            return generation
        }
        sendHello()
        Thread.detachNewThread { [self] in pump(socket, generation: current) }
    }

    /// Tells the app who's connected (shown in Settings and the status bar).
    private func sendHello() {
        let (info, version) = lock.withLock { (clientInfo, protocolVersion) }
        guard info != nil || version != nil,
              let data = MCP.encode(MCP.notification("halo/hello", params: ["clientInfo": info ?? [:], "protocolVersion": version ?? ""])) else { return }
        _ = send(data)
    }

    /// Halo → Claude, until the app closes the socket. The reader owns the
    /// socket and is the only one to close it.
    private func pump(_ socket: Int32, generation current: Int) {
        var lines = LineBuffer()
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(socket, $0.baseAddress, $0.count) }
            if n <= 0 { break }
            for line in chunk.withUnsafeBytes({ lines.append(UnsafeRawBufferPointer(rebasing: $0[..<n])) }) {
                if let message = MCP.decode(line), let id = message["id"] {
                    lock.withLock { _ = pending.removeValue(forKey: MCP.key(for: id)) }
                }
                var data = line
                data.append(0x0A)
                writeRaw(data)
            }
        }
        drop(generation: current)
        Darwin.close(socket)
    }

    /// Forgets the current connection (waking its reader) and fails the calls
    /// that were waiting on it.
    private func drop(generation dropped: Int) {
        let orphans: [Any] = lock.withLock {
            guard generation == dropped, fd >= 0 else { return [] }
            shutdown(fd, SHUT_RDWR)
            fd = -1
            defer { pending = [:] }
            return Array(pending.values)
        }
        for id in orphans {
            write(MCP.response(id: id, result: MCP.toolResult("Halo closed before it finished. Try again.", isError: true)))
        }
    }

    // MARK: Output

    private func write(_ message: [String: Any]) {
        if let data = MCP.encode(message) { writeRaw(data) }
    }

    private func writeRaw(_ data: Data) {
        outputLock.lock()
        defer { outputLock.unlock() }
        do { try FileHandle.standardOutput.write(contentsOf: data) } catch { exit(0) }   // Claude went away
    }
}
