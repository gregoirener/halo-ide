import Foundation
// Scripted DAP session: breakpoint in square(), inspect variables, continue to the end.
let args = CommandLine.arguments
let adapter = args[1], program = args[2], source = args[3]
let python = ProcessInfo.processInfo.environment["PY"] != nil
let line = python ? 2 : 4
let client = DAPClient(executable: adapter, arguments: python ? ["-m", "debugpy.adapter"] : [], cwd: URL(fileURLWithPath: program).deletingLastPathComponent())
var stops = 0
func finish(_ code: Int32) { client.terminate(); exit(code) }
client.onEvent = { event, body in
    switch event {
    case "initialized":
        client.request("setBreakpoints", ["source": ["path": source], "breakpoints": [["line": line]]]) { r in
            if case .success(let b) = r { print("breakpoints:", (b["breakpoints"] as? [[String: Any]] ?? []).map { "\($0["line"] ?? "?") verified=\($0["verified"] ?? "?")" }) }
        }
        client.request("configurationDone")
    case "stopped":
        stops += 1
        let tid = body["threadId"] as? Int ?? 1
        print("stopped:", body["reason"] ?? "", "thread", tid)
        client.request("stackTrace", ["threadId": tid, "levels": 5]) { r in
            guard case .success(let b) = r, let frames = b["stackFrames"] as? [[String: Any]], let top = frames.first else { return }
            print("frames:", frames.map { "\($0["name"] ?? "?"):\($0["line"] ?? "?")" })
            client.request("scopes", ["frameId": top["id"] ?? 0]) { r in
                guard case .success(let b) = r, let scope = (b["scopes"] as? [[String: Any]])?.first else { return }
                client.request("variables", ["variablesReference": scope["variablesReference"] ?? 0]) { r in
                    if case .success(let b) = r {
                        print("\(scope["name"] ?? "scope"):", (b["variables"] as? [[String: Any]] ?? []).map { "\($0["name"] ?? "")=\($0["value"] ?? "")" })
                    }
                    if stops >= 2 {
                        client.request("setBreakpoints", ["source": ["path": source], "breakpoints": [[String: Any]]()])
                    }
                    client.request("continue", ["threadId": tid])
                }
            }
        }
    case "output":
        if let text = body["output"] as? String, body["category"] as? String != "telemetry" { print("output[\(body["category"] ?? "")]:", text.trimmingCharacters(in: .newlines)) }
    case "exited": print("exited:", body["exitCode"] ?? "")
    case "terminated": print("terminated"); finish(0)
    default: break
    }
}
client.onExit = { err in print("adapter exited", err.suffix(300)); exit(1) }
try client.start()
client.request("initialize", ["clientID": "halo", "adapterID": python ? "debugpy" : "lldb-dap", "linesStartAt1": true, "columnsStartAt1": true, "pathFormat": "path"]) { r in
    if case .failure(let f) = r { print("init failed", f.message); finish(1) }
    let launch: [String: Any] = python
        ? ["name": "t", "type": "python", "request": "launch", "program": program, "console": "internalConsole", "justMyCode": true, "python": [adapter], "redirectOutput": true]
        : ["program": program, "stopOnEntry": false]
    client.request("launch", launch) { r in
        if case .failure(let f) = r { print("launch failed:", f.message); finish(1) }
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("timeout"); finish(2) }
RunLoop.main.run()
