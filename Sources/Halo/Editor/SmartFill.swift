import Foundation
import Observation

/// Smart Fill: Tab completions from a small open-source code model
/// (Qwen2.5-Coder, Apache-2.0) running entirely on this Mac through
/// llama.cpp. Free, offline and private — nothing leaves the machine.
/// When no model is downloaded (or it's still loading), the pattern
/// engine in `FillEngine` answers instead.
@Observable @MainActor
final class SmartFill: NSObject {
    static let shared = SmartFill()

    struct Model: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
        let file: String
        let url: URL
        let bytes: Int64
    }

    static let models: [Model] = [
        Model(id: "qwen-0.5b", name: "Fast", detail: "Qwen2.5-Coder 0.5B — recommended, first line in about 0.1 s",
              file: "qwen2.5-coder-0.5b-q8_0.gguf",
              url: URL(string: "https://huggingface.co/ggml-org/Qwen2.5-Coder-0.5B-Q8_0-GGUF/resolve/main/qwen2.5-coder-0.5b-q8_0.gguf")!,
              bytes: 531_068_128),
        Model(id: "qwen-1.5b", name: "Smart", detail: "Qwen2.5-Coder 1.5B — a bit smarter, about twice as slow",
              file: "qwen2.5-coder-1.5b-q8_0.gguf",
              url: URL(string: "https://huggingface.co/ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF/resolve/main/qwen2.5-coder-1.5b-q8_0.gguf")!,
              bytes: 1_646_573_056),
    ]

    enum State: Equatable {
        case off, notDownloaded, downloading(Double), starting, ready, failed(String)
    }

    private(set) var state: State = .off
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "smartFillEnabled"); refresh() }
    }
    var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: "smartFillModel"); restart() }
    }
    /// Milliseconds the last completion took (shown in Settings).
    private(set) var lastLatency: Int?

    @ObservationIgnored private var server: Process?
    @ObservationIgnored private var port = 0
    @ObservationIgnored private var inflight: URLSessionDataTask?
    @ObservationIgnored private var streaming: Task<String?, Never>?
    @ObservationIgnored private var download: URLSessionDownloadTask?
    @ObservationIgnored private lazy var downloadSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    @ObservationIgnored private let api: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()

    override private init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "smartFillEnabled") as? Bool ?? true
        selectedModelID = defaults.string(forKey: "smartFillModel") ?? "qwen-0.5b"   // speed first
        super.init()
    }

    var model: Model { Self.models.first { $0.id == selectedModelID } ?? Self.models[0] }
    var isReady: Bool { state == .ready }

    static var modelsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Halo/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func path(for model: Model) -> URL { Self.modelsDirectory.appendingPathComponent(model.file) }

    func isDownloaded(_ model: Model) -> Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: path(for: model).path)[.size] as? Int64 else { return false }
        return size == model.bytes
    }

    private static var helperURL: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama/llama-server")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        // `swift run` during development.
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/llama/llama-server")
        return FileManager.default.isExecutableFile(atPath: source.path) ? source : nil
    }

    // MARK: Lifecycle

    /// Starts the model server if Smart Fill is on and the model is present.
    func refresh() {
        if case .downloading = state { return }
        guard enabled else { stop(); state = .off; return }
        guard isDownloaded(model) else { stop(); state = .notDownloaded; return }
        if server?.isRunning == true { return }
        start()
    }

    private func restart() {
        stop()
        refresh()
    }

    private func start() {
        guard let helper = Self.helperURL else { state = .failed("The model runtime is missing from this build."); return }
        port = Self.freePort()
        let p = Process()
        // A tiny watchdog shell owns the server: it stops it when Halo exits for
        // any reason (even a crash), so the model never lingers in memory.
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        let watchdog = """
        "$@" &
        S=$!
        trap 'kill $S 2>/dev/null; exit 0' TERM INT HUP
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null && kill -0 $S 2>/dev/null; do sleep 1; done
        kill $S 2>/dev/null
        """
        p.arguments = ["-c", watchdog, "halo-smartfill", helper.path,
            "-m", path(for: model).path,
            "--host", "127.0.0.1", "--port", String(port),
            "-ngl", "99",              // everything on the GPU (Metal)
            "-fa", "on",               // flash attention
            "-c", "8192",              // plenty for a file's worth of context
            "-b", "1024", "-ub", "1024",
            "-np", "1",                // one editor, one slot: no wasted memory
            "--cache-reuse", "256",    // reuse the prompt cache between keystrokes
            "-cram", "512",
            "--log-disable",
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.server === proc else { return }
                self.server = nil
                if self.state == .ready || self.state == .starting { self.state = .failed("The model stopped unexpectedly.") }
            }
        }
        do {
            try p.run()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        server = p
        state = .starting
        waitUntilHealthy(attempts: 120)
    }

    func stop() {
        inflight?.cancel()
        streaming?.cancel()
        if let server, server.isRunning { server.terminate() }
        server = nil
        if state == .ready || state == .starting { state = enabled ? .notDownloaded : .off }
    }

    private func waitUntilHealthy(attempts: Int) {
        guard attempts > 0, server?.isRunning == true else {
            if state == .starting { state = .failed("The model didn’t start.") }
            return
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        request.timeoutInterval = 1
        api.dataTask(with: request) { [weak self] _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.state = .ready
                    self.warmUp()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.waitUntilHealthy(attempts: attempts - 1) }
                }
            }
        }.resume()
    }

    /// One tiny request so the first real completion doesn't pay for shader compilation.
    private func warmUp() {
        Task { _ = await complete(prefix: "def add(a, b):\n", line: "    ", suffix: "", indent: 4) }
    }

    private static func freePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(sock, $0, len) } }
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) } }
        let port = Int(UInt16(bigEndian: addr.sin_port))
        return port > 0 ? port : 18012
    }

    // MARK: Completions

    /// Fill-in-the-middle completion. `prefix` is everything before the
    /// current line, `line` the current line up to the caret, `suffix` the
    /// rest. Returns nil if the model has nothing useful (or was cancelled).
    func complete(prefix: String, line: String, suffix: String, indent: Int, extra: [(String, String)] = []) async -> String? {
        guard state == .ready else { return nil }
        inflight?.cancel()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/infill")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "input_prefix": prefix,
            "prompt": line,
            "input_suffix": suffix,
            "input_extra": extra.map { ["filename": $0.0, "text": $0.1] },
            "n_predict": 128,
            "n_indent": indent,
            "top_k": 40,
            "top_p": 0.99,
            "samplers": ["top_k", "top_p", "infill"],
            "stream": false,
            "cache_prompt": true,
            "t_max_prompt_ms": 600,
            "t_max_predict_ms": 900,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let started = Date()
        return await withCheckedContinuation { continuation in
            let task = api.dataTask(with: request) { data, _, error in
                guard error == nil, let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? String else {
                    continuation.resume(returning: nil)
                    return
                }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                DispatchQueue.main.async { SmartFill.shared.lastLatency = ms }
                continuation.resume(returning: content)
            }
            inflight = task
            task.resume()
        }
    }

    /// Streaming completion: `onLines` receives the text so far each time a
    /// line is finished, so the first line can appear while the rest is still
    /// being written. Returns the full text, or nil on error/cancellation.
    /// Starting a new stream cancels the previous one.
    @discardableResult
    func stream(prefix: String, line: String, suffix: String, indent: Int,
                onLines: @escaping @MainActor (String) -> Void) async -> String? {
        streaming?.cancel()
        inflight?.cancel()
        guard state == .ready else { return nil }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/infill")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "input_prefix": prefix,
            "prompt": line,
            "input_suffix": suffix,
            "input_extra": [[String: String]](),
            "n_predict": 192,
            "n_indent": indent,
            "top_k": 40,
            "top_p": 0.99,
            "samplers": ["top_k", "top_p", "infill"],
            "stream": true,
            "cache_prompt": true,
            "t_max_prompt_ms": 800,
            "t_max_predict_ms": 3000,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let session = api
        let started = Date()
        let task = Task<String?, Never> {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                var text = ""
                var emittedLines = 0
                var first = true
                for try await event in bytes.lines {
                    if Task.isCancelled { return nil }
                    guard event.hasPrefix("data: "),
                          let json = try? JSONSerialization.jsonObject(with: Data(event.dropFirst(6).utf8)) as? [String: Any] else { continue }
                    if let piece = json["content"] as? String { text += piece }
                    let lines = text.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
                    if lines > emittedLines {
                        emittedLines = lines
                        let complete = String(text[..<text.lastIndex(of: "\n")!])
                        if first {
                            first = false
                            let ms = Int(Date().timeIntervalSince(started) * 1000)
                            await MainActor.run { SmartFill.shared.lastLatency = ms }
                        }
                        await MainActor.run { onLines(complete) }
                    }
                    if json["stop"] as? Bool == true { break }
                }
                if first {
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    await MainActor.run { SmartFill.shared.lastLatency = ms }
                }
                return Task.isCancelled ? nil : text
            } catch {
                return nil
            }
        }
        streaming = task
        return await task.value
    }

    // MARK: Downloading

    func downloadModel() {
        guard download == nil else { return }
        let task = downloadSession.downloadTask(with: model.url)
        download = task
        state = .downloading(0)
        task.resume()
    }

    func cancelDownload() {
        download?.cancel()
        download = nil
        state = .notDownloaded
    }

    func deleteModel(_ model: Model) {
        if model.id == selectedModelID { stop() }
        try? FileManager.default.removeItem(at: path(for: model))
        refresh()
    }
}

extension SmartFill: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : model.bytes
            state = .downloading(Double(totalBytesWritten) / Double(total))
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file disappears when this returns: move it synchronously.
        let destination = MainActor.assumeIsolated { path(for: model) }
        try? FileManager.default.removeItem(at: destination)
        let moved = (try? FileManager.default.moveItem(at: location, to: destination)) != nil
        MainActor.assumeIsolated {
            download = nil
            if moved, isDownloaded(model) {
                state = .notDownloaded
                refresh()
            } else {
                state = .failed("The download didn’t complete. Try again.")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        MainActor.assumeIsolated {
            download = nil
            state = .failed(error.localizedDescription)
        }
    }
}
