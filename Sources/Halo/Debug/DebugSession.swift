import AppKit
import Observation

/// One debugging session: builds if needed, launches the right adapter,
/// and mirrors its state (threads, frames, variables, output) for the UI.
@Observable @MainActor
final class DebugSession {
    enum State: Equatable { case building, starting, running, stopped, ended }

    struct Frame: Identifiable, Hashable {
        let id: Int
        let name: String
        let path: String?
        let line: Int
        let column: Int
    }

    struct Scope: Identifiable, Hashable {
        let name: String
        let reference: Int
        let expensive: Bool
        var id: Int { reference }
    }

    struct Variable: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let value: String
        let type: String?
        let reference: Int
    }

    struct ConsoleLine: Identifiable {
        enum Kind { case output, error, info, input, result }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    struct Location: Equatable { let path: String; let line: Int }

    private(set) var state: State = .starting
    private(set) var frames: [Frame] = []
    private(set) var selectedFrameID: Int?
    private(set) var scopes: [Scope] = []
    private(set) var variables: [Int: [Variable]] = [:]
    var expanded: Set<Int> = []
    private(set) var console: [ConsoleLine] = []
    private(set) var location: Location?
    private(set) var stopReason: String?
    let title: String
    let fileURL: URL
    let language: Language

    @ObservationIgnored private weak var workspace: Workspace?
    @ObservationIgnored private var client: DAPClient?
    @ObservationIgnored private var threadID: Int?
    @ObservationIgnored private var capabilities: DAPClient.JSON = [:]

    var isActive: Bool { state != .ended }

    init(fileURL: URL, language: Language, workspace: Workspace) {
        self.fileURL = fileURL
        self.language = language
        self.workspace = workspace
        self.title = fileURL.lastPathComponent
    }

    static func supports(_ language: Language) -> Bool {
        ["python", "c", "cpp", "swift", "rust"].contains(language.id)
    }

    // MARK: Lifecycle

    func start() {
        log(.info, "Starting \(title)…")
        if language.id == "python" { startPython() } else { buildAndStartNative() }
    }

    private func startPython() {
        guard let workspace else { return }
        let python = Tools.python(root: workspace.root)
        let (status, _) = Shell.run([python, "-c", "import debugpy"], timeout: 15)
        guard status == 0 else {
            log(.error, "The Python debugger (debugpy) isn’t installed for \(python).")
            end()
            workspace.offerDebugpyInstall(python: python)
            return
        }
        let dir = fileURL.deletingLastPathComponent()
        launch(adapter: python, arguments: ["-m", "debugpy.adapter"], adapterID: "debugpy", cwd: dir, launchArguments: [
            "name": "Halo", "type": "python", "request": "launch",
            "program": fileURL.path, "cwd": dir.path, "console": "internalConsole",
            "justMyCode": true, "stopOnEntry": false, "redirectOutput": true, "python": [python],
        ])
    }

    private func buildAndStartNative() {
        guard let workspace else { return }
        guard let adapter = Tools.xcrun("lldb-dap") else {
            log(.error, "lldb-dap wasn’t found. Install Xcode or the Command Line Tools (xcode-select --install).")
            end()
            return
        }
        switch Runner.plan(for: fileURL, language: language, root: workspace.root) {
        case .failure(let error):
            log(.error, error.localizedDescription)
            end()
        case .success(let plan):
            guard let compile = plan.compile, let program = plan.program else {
                log(.error, "Debugging \(language.name) projects isn’t supported yet — run it with ⌘R instead.")
                end()
                return
            }
            state = .building
            log(.info, "Building with \(URL(fileURLWithPath: compile[0]).lastPathComponent)…")
            Task {
                let result = await Runner.build(compile, cwd: plan.cwd)
                workspace.applyBuildDiagnostics(result.diagnostics, for: [self.fileURL.standardizedFileURL.path])
                guard result.ok else {
                    self.log(.error, "Build failed.")
                    result.output.split(separator: "\n").prefix(40).forEach { self.log(.error, String($0)) }
                    workspace.showPanel(.problems)
                    self.end()
                    return
                }
                self.launch(adapter: adapter, arguments: [], adapterID: "lldb-dap", cwd: plan.cwd, launchArguments: [
                    "name": "Halo", "type": "lldb-dap", "request": "launch",
                    "program": program, "cwd": plan.cwd.path, "args": [String](), "stopOnEntry": false,
                ])
            }
        }
    }

    private func launch(adapter: String, arguments: [String], adapterID: String, cwd: URL, launchArguments: DAPClient.JSON) {
        state = .starting
        let client = DAPClient(executable: adapter, arguments: arguments, cwd: cwd)
        self.client = client
        client.onEvent = { [weak self] event, body in self?.handle(event: event, body: body) }
        client.onExit = { [weak self] stderr in
            guard let self, self.state != .ended else { return }
            if !stderr.isEmpty { stderr.split(separator: "\n").suffix(10).forEach { self.log(.error, String($0)) } }
            self.end()
        }
        do { try client.start() } catch {
            log(.error, "Couldn’t start the debugger: \(error.localizedDescription)")
            end()
            return
        }
        client.request("initialize", [
            "clientID": "halo", "clientName": "Halo", "adapterID": adapterID, "locale": "en",
            "linesStartAt1": true, "columnsStartAt1": true, "pathFormat": "path",
            "supportsVariableType": true, "supportsVariablePaging": false, "supportsRunInTerminalRequest": false,
        ]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let failure):
                self.log(.error, failure.message)
                self.end()
            case .success(let caps):
                self.capabilities = caps
                client.request("launch", launchArguments) { [weak self] result in
                    if case .failure(let failure) = result {
                        self?.log(.error, failure.message)
                        self?.end()
                    }
                }
            }
        }
    }

    private func handle(event: String, body: DAPClient.JSON) {
        switch event {
        case "initialized":
            for (path, lines) in workspace?.breakpoints ?? [:] where !lines.isEmpty { sendBreakpoints(path: path, lines: lines) }
            if capabilities["exceptionBreakpointFilters"] != nil {
                client?.request("setExceptionBreakpoints", ["filters": [String]()])
            }
            client?.request("configurationDone")
            state = .running
        case "stopped":
            state = .stopped
            stopReason = body["reason"] as? String
            if let description = body["description"] as? String, stopReason == "exception" { log(.error, description) }
            if let text = body["text"] as? String, !text.isEmpty { log(.error, text) }
            threadID = body["threadId"] as? Int ?? threadID
            fetchStack()
            NSApp.activate()
        case "continued":
            state = .running
            location = nil
            frames = []
            scopes = []
        case "output":
            let category = body["category"] as? String ?? "console"
            guard category != "telemetry", let text = body["output"] as? String else { return }
            let kind: ConsoleLine.Kind = category == "stderr" ? .error : category == "console" || category == "important" ? .info : .output
            var body = text
            if body.hasSuffix("\n") { body.removeLast() }
            guard !body.isEmpty else { return }
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) { log(kind, String(line)) }
        case "exited":
            log(.info, "Process exited with code \(body["exitCode"] as? Int ?? 0).")
        case "terminated":
            end()
        default:
            break
        }
    }

    // MARK: Inspecting

    private func fetchStack() {
        guard let client else { return }
        let request: (Int) -> Void = { [weak self] tid in
            client.request("stackTrace", ["threadId": tid, "startFrame": 0, "levels": 50]) { [weak self] result in
                guard let self, case .success(let body) = result else { return }
                let raw = body["stackFrames"] as? [DAPClient.JSON] ?? []
                self.frames = raw.map { f in
                    Frame(id: f["id"] as? Int ?? 0, name: f["name"] as? String ?? "?",
                          path: (f["source"] as? DAPClient.JSON)?["path"] as? String,
                          line: f["line"] as? Int ?? 0, column: f["column"] as? Int ?? 0)
                }
                if let first = self.frames.first(where: { $0.path.map { FileManager.default.fileExists(atPath: $0) } ?? false }) ?? self.frames.first {
                    self.select(first)
                }
            }
        }
        if let threadID { request(threadID); return }
        client.request("threads") { [weak self] result in
            guard case .success(let body) = result, let first = (body["threads"] as? [DAPClient.JSON])?.first,
                  let tid = first["id"] as? Int else { return }
            self?.threadID = tid
            request(tid)
        }
    }

    func select(_ frame: Frame) {
        selectedFrameID = frame.id
        if let path = frame.path, frame.line > 0 {
            location = Location(path: URL(fileURLWithPath: path).standardizedFileURL.path, line: frame.line)
            if FileManager.default.fileExists(atPath: path) {
                workspace?.open(URL(fileURLWithPath: path), line: frame.line, flash: false)
            }
        }
        client?.request("scopes", ["frameId": frame.id]) { [weak self] result in
            guard let self, case .success(let body) = result else { return }
            self.scopes = (body["scopes"] as? [DAPClient.JSON] ?? []).map {
                Scope(name: $0["name"] as? String ?? "Scope", reference: $0["variablesReference"] as? Int ?? 0,
                      expensive: $0["expensive"] as? Bool ?? false)
            }
            self.variables = [:]
            for scope in self.scopes where !scope.expensive {
                self.expanded.insert(scope.reference)
                self.loadVariables(scope.reference)
            }
        }
    }

    func loadVariables(_ reference: Int) {
        guard reference > 0 else { return }
        client?.request("variables", ["variablesReference": reference]) { [weak self] result in
            guard let self, case .success(let body) = result else { return }
            self.variables[reference] = (body["variables"] as? [DAPClient.JSON] ?? []).map {
                Variable(name: $0["name"] as? String ?? "", value: $0["value"] as? String ?? "",
                         type: $0["type"] as? String, reference: $0["variablesReference"] as? Int ?? 0)
            }
        }
    }

    func toggle(_ reference: Int) {
        if expanded.contains(reference) { expanded.remove(reference) } else {
            expanded.insert(reference)
            if variables[reference] == nil { loadVariables(reference) }
        }
    }

    func evaluate(_ expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        log(.input, trimmed)
        var args: DAPClient.JSON = ["expression": trimmed, "context": "repl"]
        if let selectedFrameID { args["frameId"] = selectedFrameID }
        client?.request("evaluate", args) { [weak self] result in
            switch result {
            case .success(let body): self?.log(.result, body["result"] as? String ?? "")
            case .failure(let failure): self?.log(.error, failure.message)
            }
        }
    }

    // MARK: Controls

    private func step(_ command: String) {
        guard state == .stopped, let threadID else { return }
        state = .running
        client?.request(command, ["threadId": threadID])
    }

    func resume() { step("continue") }
    func stepOver() { step("next") }
    func stepInto() { step("stepIn") }
    func stepOut() { step("stepOut") }

    func pause() {
        guard state == .running else { return }
        if let threadID { client?.request("pause", ["threadId": threadID]); return }
        client?.request("threads") { [weak self] result in
            guard case .success(let body) = result, let tid = (body["threads"] as? [DAPClient.JSON])?.first?["id"] as? Int else { return }
            self?.threadID = tid
            self?.client?.request("pause", ["threadId": tid])
        }
    }

    func stop() {
        guard let client, state != .ended else { end(); return }
        client.request("disconnect", ["terminateDebuggee": true]) { _ in client.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { client.terminate() }
        end()
    }

    func sendBreakpoints(path: String, lines: Set<Int>) {
        guard state != .ended, state != .building else { return }
        client?.request("setBreakpoints", [
            "source": ["path": path, "name": URL(fileURLWithPath: path).lastPathComponent],
            "breakpoints": lines.sorted().map { ["line": $0] },
            "sourceModified": false,
        ])
    }

    private func end() {
        guard state != .ended else { return }
        state = .ended
        location = nil
        frames = []
        scopes = []
        variables = [:]
        log(.info, "Debugging ended.")
        let client = self.client
        self.client = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { client?.terminate() }
    }

    private func log(_ kind: ConsoleLine.Kind, _ text: String) {
        console.append(ConsoleLine(kind: kind, text: text))
        if console.count > 5000 { console.removeFirst(console.count - 5000) }
    }
}
