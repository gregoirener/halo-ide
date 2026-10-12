import Foundation

/// A Debug Adapter Protocol client — the protocol VS Code speaks to its
/// debuggers. Messages are JSON bodies framed by `Content-Length` headers
/// over the adapter's stdin/stdout. Callbacks arrive on the main queue.
final class DAPClient: @unchecked Sendable {
    typealias JSON = [String: Any]

    struct Failure: Error { let message: String }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    private var seq = 1
    private var pending: [Int: (Result<JSON, Failure>) -> Void] = [:]
    private let lock = NSLock()

    var onEvent: ((String, JSON) -> Void)?
    var onExit: ((String) -> Void)?
    private var stderrText = ""

    init(executable: String, arguments: [String], cwd: URL?, environment: [String: String] = [:]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env.merge(environment) { $1 }
        process.environment = env
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.consume(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.lock.lock(); self.stderrText += String(decoding: data, as: UTF8.self); self.lock.unlock()
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.output.fileHandleForReading.readabilityHandler = nil
            self.errors.fileHandleForReading.readabilityHandler = nil
            self.lock.lock(); let text = self.stderrText; let waiting = self.pending; self.pending = [:]; self.lock.unlock()
            DispatchQueue.main.async {
                waiting.values.forEach { $0(.failure(Failure(message: "The debugger exited."))) }
                self.onExit?(text)
            }
        }
        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    func request(_ command: String, _ arguments: JSON? = nil, completion: ((Result<JSON, Failure>) -> Void)? = nil) {
        lock.lock()
        let id = seq
        seq += 1
        if let completion { pending[id] = completion }
        lock.unlock()
        var message: JSON = ["seq": id, "type": "request", "command": command]
        if let arguments { message["arguments"] = arguments }
        send(message)
    }

    func respond(to request: JSON, success: Bool, body: JSON? = nil) {
        lock.lock(); let id = seq; seq += 1; lock.unlock()
        var message: JSON = ["seq": id, "type": "response", "request_seq": request["seq"] ?? 0,
                             "command": request["command"] ?? "", "success": success]
        if let body { message["body"] = body }
        send(message)
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func send(_ message: JSON) {
        guard process.isRunning, let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        try? input.fileHandleForWriting.write(contentsOf: frame)
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var messages: [JSON] = []
        let separator = Data("\r\n\r\n".utf8)
        while let headerEnd = buffer.range(of: separator) {
            let header = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
            guard let lengthLine = header.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
                  let length = Int(lengthLine.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) else {
                buffer.removeSubrange(buffer.startIndex..<headerEnd.upperBound)
                continue
            }
            let bodyStart = headerEnd.upperBound
            guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { break }
            let bodyEnd = buffer.index(bodyStart, offsetBy: length)
            if let json = try? JSONSerialization.jsonObject(with: buffer[bodyStart..<bodyEnd]) as? JSON { messages.append(json) }
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        }
        buffer = Data(buffer)   // re-base indices
        lock.unlock()

        for message in messages {
            DispatchQueue.main.async { self.dispatch(message) }
        }
    }

    private func dispatch(_ message: JSON) {
        switch message["type"] as? String {
        case "response":
            let id = message["request_seq"] as? Int ?? -1
            lock.lock(); let callback = pending.removeValue(forKey: id); lock.unlock()
            if message["success"] as? Bool == true {
                callback?(.success(message["body"] as? JSON ?? [:]))
            } else {
                let text = (message["body"] as? JSON)?["error"].flatMap { ($0 as? JSON)?["format"] as? String }
                    ?? message["message"] as? String ?? "Request failed"
                callback?(.failure(Failure(message: text)))
            }
        case "event":
            onEvent?(message["event"] as? String ?? "", message["body"] as? JSON ?? [:])
        case "request":
            // Reverse requests we don't support (e.g. runInTerminal) get a polite refusal.
            respond(to: message, success: false)
        default:
            break
        }
    }
}
