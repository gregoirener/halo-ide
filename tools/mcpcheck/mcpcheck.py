#!/usr/bin/env python3
"""Talks to Halo's MCP bridge the way Claude does (newline-delimited JSON-RPC over stdio).

    python3 tools/mcpcheck/mcpcheck.py <Halo executable> [project dir]

Without a project dir it only checks the handshake and the tool list.
"""
import json, os, queue, subprocess, sys, threading, time

class Client:
    def __init__(self, exe):
        self.proc = subprocess.Popen([exe, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, bufsize=1)
        self.lines = queue.Queue()
        self.next_id = 1
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def send(self, message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def request(self, method, params=None, timeout=60):
        rid = self.next_id
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        deadline = time.time() + timeout
        while True:
            line = self.lines.get(timeout=max(0.1, deadline - time.time()))
            if line is None:
                raise RuntimeError("bridge exited: " + self.proc.stderr.read())
            message = json.loads(line)
            if message.get("id") == rid:
                return message

    def notify(self, method, params=None):
        self.send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def call(self, name, timeout=90, **arguments):
        started = time.time()
        reply = self.request("tools/call", {"name": name, "arguments": arguments}, timeout)
        result = reply["result"]
        assert result["content"][0]["type"] == "text", result
        return result.get("isError", False), result["content"][0]["text"], time.time() - started

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=5)

failures = 0
def check(label, ok, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("  ok   " if ok else "  FAIL ") + label + (("  — " + detail) if detail and not ok else ""))

def show(label, result):
    is_error, text, seconds = result
    first = text.splitlines()[0] if text else ""
    print(f"  {'ERR' if is_error else '   '}  {label:<26} {seconds*1000:6.0f} ms  {first[:90]}")
    return result

def main():
    exe = sys.argv[1]
    project = sys.argv[2] if len(sys.argv) > 2 else None
    c = Client(exe)

    print("handshake")
    init = c.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                    "clientInfo": {"name": "claude-ai", "version": "0.1.0"}}, timeout=10)
    result = init.get("result", {})
    check("initialize answers", "result" in init, str(init))
    check("echoes protocol version", result.get("protocolVersion") == "2025-06-18", result.get("protocolVersion"))
    check("declares tools", "tools" in result.get("capabilities", {}))
    check("server info", result.get("serverInfo", {}).get("name") == "halo", str(result.get("serverInfo")))
    c.notify("notifications/initialized")
    newer = c.request("initialize", {"protocolVersion": "2099-01-01", "capabilities": {}, "clientInfo": {"name": "x"}}, timeout=10)
    check("falls back for unknown versions", newer["result"]["protocolVersion"] == "2025-11-25", newer["result"]["protocolVersion"])
    check("ping", c.request("ping", timeout=10).get("result") == {})
    tools = c.request("tools/list", timeout=10)["result"]["tools"]
    names = [t["name"] for t in tools]
    check(f"lists 12 tools", len(tools) == 12, ", ".join(names))
    check("schemas are objects", all(t["inputSchema"]["type"] == "object" for t in tools))
    unknown = c.request("resources/list", timeout=10)
    check("unknown method → -32601", unknown.get("error", {}).get("code") == -32601, str(unknown))

    if project:
        print("tools")
        r = show("get_editor_state", c.call("get_editor_state"))
        check("sees the project", project in r[1], r[1][:200])
        r = show("list_files *.py", c.call("list_files", pattern="*.py"))
        check("finds hello.py", "hello.py" in r[1], r[1][:200])
        r = show("read_file", c.call("read_file", path="hello.py"))
        check("numbered lines", "\t" in r[1] and "hello.py — lines 1" in r[1], r[1][:200])
        r = show("read_file range", c.call("read_file", path="hello.py", start_line=2, end_line=2))
        check("range", "lines 2–2" in r[1], r[1][:120])
        r = show("search", c.call("search", query="def "))
        check("search finds defs", "hello.py:" in r[1], r[1][:200])
        r = show("search bad regex", c.call("search", query="(", regex=True))
        check("bad regex is an error", r[0])
        r = show("outside project", c.call("read_file", path="/etc/hosts"))
        check("refuses paths outside", r[0] and "outside" in r[1], r[1])
        r = show("traversal", c.call("read_file", path="../../../../etc/hosts"))
        check("refuses ../ escapes", r[0], r[1])
        r = show("open_file", c.call("open_file", path="hello.py", line=2, end_line=3))
        check("opens", not r[0], r[1])

        r = show("edit_file", c.call("edit_file", path="hello.py", old_string='print("hello")', new_string='print("hello from Claude")'))
        check("edit applies", not r[0] and "Edited hello.py" in r[1], r[1])
        with open(os.path.join(project, "hello.py")) as f:
            check("edit saved to disk", 'hello from Claude' in f.read())
        r = show("edit_file not found", c.call("edit_file", path="hello.py", old_string="nope nope", new_string="x"))
        check("missing text is an error", r[0])
        r = show("edit_file ambiguous", c.call("edit_file", path="hello.py", old_string="def", new_string="def"))
        check("same strings rejected", r[0])
        r = show("write_file new", c.call("write_file", path="notes/todo.md", content="# Todo\n\n- ship MCP\n"))
        check("creates nested file", not r[0] and os.path.exists(os.path.join(project, "notes/todo.md")), r[1])
        r = show("write_file broken.py", c.call("write_file", path="broken.py", content="def broken(:\n    pass\n"))
        time.sleep(2.5)
        r = show("get_diagnostics", c.call("get_diagnostics", path="broken.py"))
        check("live lint reports the error", "broken.py:1" in r[1], r[1])
        r = show("git_status diff", c.call("git_status", diff=True))
        check("git sees the edit", "hello.py" in r[1], r[1][:300])
        r = show("get_terminal_output", c.call("get_terminal_output"))

        r = show("run_command", c.call("run_command", command="echo hi from $SHELL && pwd"))
        check("runs in project", (not r[0] and "hi from" in r[1] and os.path.realpath(project) in os.path.realpath(r[1].splitlines()[-1])) or "turned off" in r[1], r[1])
        if "turned off" not in r[1]:
            r = show("run_command timeout", c.call("run_command", command="sleep 30", timeout_seconds=2))
            check("time limit stops it", "time limit" in r[1], r[1])
            r = show("run_file stdin", c.call("run_file", path="greet.py", stdin="Ada\n"))
            check("run_file feeds stdin", "Hello, Ada" in r[1], r[1])
            r = show("run_file c", c.call("run_file", path="sum.c"))
            check("builds and runs C", "total = 55" in r[1], r[1])

    c.close()
    print("\n" + ("all checks passed" if failures == 0 else f"{failures} checks FAILED"))
    sys.exit(1 if failures else 0)

if __name__ == "__main__":
    main()
